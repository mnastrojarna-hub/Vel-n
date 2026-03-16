// ===== ADDRESS-API.JS – Czech address autocomplete via Nominatim + OSRM =====
// Uses OpenStreetMap Nominatim (free, no key) for Czech address search
// Falls back to local ADDR_DB if offline or API fails
// Flow: 1) suggestCities → user picks city, 2) suggestStreets(city) → streets+č.p., 3) PSČ auto-fills

var AddressAPI = (function(){
  'use strict';

  // Nominatim API (free, no key, Czech addresses)
  var NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';

  // OSRM public demo server for distance calculation
  var OSRM_URL = 'https://router.project-osrm.org/route/v1/driving';

  // Branch coordinates (Mezná 9, 393 01)
  var BRANCH_LAT = 49.4147;
  var BRANCH_LNG = 15.2953;

  // Cache for recent searches
  var _cache = {};
  var _CACHE_TTL = 300000; // 5 min

  // Separate debounce timers for city vs street
  var _cityDebounce = null;
  var _streetDebounce = null;
  var _DEBOUNCE_MS = 300;

  // Geocode cache for distance calculations
  var _geoCache = {};

  /**
   * Suggest cities only (deduplicated)
   * Uses structured Nominatim query for better Czech city results
   */
  function suggestCities(query, callback){
    if(!query || query.length < 2){ callback([]); return; }

    var cacheKey = 'city_' + query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

    // Use structured query (city=X) for much better city results
    var url = NOMINATIM_URL +
      '?city=' + encodeURIComponent(query) +
      '&format=json' +
      '&addressdetails=1' +
      '&countrycodes=cz' +
      '&limit=16' +
      '&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !Array.isArray(data)){
        callback(_fallbackCities(query));
        return;
      }
      var q = query.toLowerCase();
      var seen = {};
      var cities = [];
      data.forEach(function(item){
        var addr = item.address || {};
        var city = addr.city || addr.town || addr.village || addr.municipality || '';
        if(!city || seen[city]) return;
        // Only include cities that actually start with or contain the query
        if(city.toLowerCase().indexOf(q) === -1) return;
        seen[city] = true;
        var zip = addr.postcode || '';
        var district = addr.county || '';
        cities.push({
          label: city,
          city: city,
          zip: zip,
          district: district,
          lat: parseFloat(item.lat) || null,
          lng: parseFloat(item.lon) || null
        });
      });
      // Sort: cities starting with query first, then alphabetical
      cities.sort(function(a, b){
        var aStart = a.city.toLowerCase().indexOf(q) === 0 ? 0 : 1;
        var bStart = b.city.toLowerCase().indexOf(q) === 0 ? 0 : 1;
        if(aStart !== bStart) return aStart - bStart;
        return a.city.localeCompare(b.city, 'cs');
      });
      cities = cities.slice(0, 8);
      // If structured query returned nothing, fallback to free-text
      if(cities.length === 0){
        _suggestCitiesFreetext(query, q, cacheKey, callback);
        return;
      }
      _cache[cacheKey] = { data: cities, ts: Date.now() };
      callback(cities);
    });
  }

  /**
   * Fallback free-text city search (when structured query returns nothing)
   */
  function _suggestCitiesFreetext(query, q, cacheKey, callback){
    var url = NOMINATIM_URL +
      '?q=' + encodeURIComponent(query) +
      '&format=json' +
      '&addressdetails=1' +
      '&countrycodes=cz' +
      '&limit=16' +
      '&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !Array.isArray(data)){
        callback(_fallbackCities(query));
        return;
      }
      var seen = {};
      var cities = [];
      data.forEach(function(item){
        var addr = item.address || {};
        var city = addr.city || addr.town || addr.village || addr.municipality || '';
        if(!city || seen[city]) return;
        // MUST match the query — prevents "Hum" → "Zlín"
        if(city.toLowerCase().indexOf(q) === -1) return;
        seen[city] = true;
        cities.push({
          label: city,
          city: city,
          zip: addr.postcode || '',
          district: addr.county || '',
          lat: parseFloat(item.lat) || null,
          lng: parseFloat(item.lon) || null
        });
      });
      cities = cities.slice(0, 8);
      if(cities.length === 0){ cities = _fallbackCities(query); }
      _cache[cacheKey] = { data: cities, ts: Date.now() };
      callback(cities);
    });
  }

  /**
   * Suggest cities with debounce
   */
  function suggestCitiesDebounced(query, callback){
    clearTimeout(_cityDebounce);
    _cityDebounce = setTimeout(function(){
      suggestCities(query, callback);
    }, _DEBOUNCE_MS);
  }

  /**
   * Suggest streets/addresses within a city (or general if no city)
   * Czech addresses: ulice + č.p., OR místní část + ev.č. (malé obce bez ulic)
   * Example: "Hněvkovice 9, 396 01 Humpolec" — Hněvkovice is a hamlet, not a street
   */
  function suggestStreets(query, city, callback){
    if(!query || query.length < 2){ callback([]); return; }

    var searchTerm = city ? (query + ', ' + city) : query;
    var cacheKey = 'street_' + searchTerm.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

    // Always use free-text query — structured ?street= fails for Czech hamlets/localities
    var url = NOMINATIM_URL +
      '?q=' + encodeURIComponent(searchTerm) +
      '&format=json' +
      '&addressdetails=1' +
      '&countrycodes=cz' +
      '&limit=15' +
      '&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !Array.isArray(data)){
        callback(_fallbackStreets(query, city));
        return;
      }
      var results = _parseStreetResults(data, query, city);

      // If too few results and city is set, also try query alone (might be a hamlet name)
      if(results.length < 2 && city){
        var url2 = NOMINATIM_URL +
          '?q=' + encodeURIComponent(query + ' ' + city) +
          '&format=json&addressdetails=1&countrycodes=cz&limit=10&accept-language=cs';
        _fetchJSON(url2, function(err2, data2){
          if(!err2 && data2 && Array.isArray(data2)){
            var extra = _parseStreetResults(data2, query, city);
            var seenKeys = {};
            results.forEach(function(r){ seenKeys[r.label] = true; });
            extra.forEach(function(r){
              if(!seenKeys[r.label]){ results.push(r); seenKeys[r.label] = true; }
            });
          }
          results = results.slice(0, 8);
          if(results.length === 0){ results = _fallbackStreets(query, city); }
          _cache[cacheKey] = { data: results, ts: Date.now() };
          callback(results);
        });
        return;
      }

      results = results.slice(0, 8);
      if(results.length === 0){ results = _fallbackStreets(query, city); }
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  /**
   * Parse Nominatim results into street/address suggestions
   * Handles: streets with house numbers, hamlets (místní části), ev.č. without street
   */
  function _parseStreetResults(data, query, city){
    var results = [];
    var seen = {};
    var q = query.toLowerCase();

    data.forEach(function(item){
      var addr = item.address || {};
      var itemCity = addr.city || addr.town || addr.village || addr.municipality || '';
      var street = addr.road || '';
      var houseNum = addr.house_number || '';
      var zip = addr.postcode || '';
      var hamlet = addr.hamlet || addr.suburb || addr.city_district || addr.quarter || '';
      var neighbourhood = addr.neighbourhood || '';

      // Build the best label for this result
      var label = '';
      var displayStreet = street;
      var displayDistrict = hamlet;

      if(street && houseNum){
        // Classic: "Nádražní 42"
        label = street + ' ' + houseNum;
      } else if(street){
        // Street without number: "Nádražní"
        label = street;
      } else if(hamlet && houseNum){
        // Hamlet with ev.č.: "Hněvkovice 9"
        label = hamlet + ' ' + houseNum;
        displayStreet = hamlet;
      } else if(hamlet){
        // Just hamlet name: "Hněvkovice"
        label = hamlet;
        displayStreet = hamlet;
      } else if(houseNum){
        // Just house number (ev.č.)
        label = houseNum;
      } else if(neighbourhood && houseNum){
        label = neighbourhood + ' ' + houseNum;
        displayStreet = neighbourhood;
      } else {
        // Nothing useful
        return;
      }

      // If city was specified, filter: must be same city or nearby
      if(city && itemCity){
        var cityLc = city.toLowerCase();
        var itemCityLc = itemCity.toLowerCase();
        // Accept if: exact match, one contains the other, or hamlet matches
        var cityOk = (itemCityLc === cityLc) ||
          (itemCityLc.indexOf(cityLc) !== -1) ||
          (cityLc.indexOf(itemCityLc) !== -1);
        if(!cityOk) return;
      }

      // Relevance: label or hamlet or street should relate to what user typed
      var labelLc = label.toLowerCase();
      var hamletLc = hamlet.toLowerCase();
      var streetLc = street.toLowerCase();
      var relevant = (labelLc.indexOf(q) !== -1) ||
        (hamletLc.indexOf(q) !== -1) ||
        (streetLc.indexOf(q) !== -1) ||
        (q.indexOf(labelLc.split(' ')[0]) !== -1);
      if(!relevant && city) {
        // Still accept if this is a plausible address in the right city
        relevant = true;
      }
      if(!relevant) return;

      if(seen[label]) return;
      seen[label] = true;

      results.push({
        label: label,
        street: displayStreet,
        houseNum: houseNum,
        district: displayDistrict,
        lat: parseFloat(item.lat) || null,
        lng: parseFloat(item.lon) || null,
        city: itemCity || city || '',
        zip: zip
      });
    });

    return results;
  }

  /**
   * Suggest streets with debounce
   */
  function suggestStreetsDebounced(query, city, callback){
    clearTimeout(_streetDebounce);
    _streetDebounce = setTimeout(function(){
      suggestStreets(query, city, callback);
    }, _DEBOUNCE_MS);
  }

  /**
   * Legacy suggest (kept for compatibility) — now returns 8 results
   */
  function suggest(query, callback){
    if(!query || query.length < 2){ callback([]); return; }

    var cacheKey = query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

    var url = NOMINATIM_URL +
      '?q=' + encodeURIComponent(query) +
      '&format=json' +
      '&addressdetails=1' +
      '&countrycodes=cz' +
      '&limit=12' +
      '&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !Array.isArray(data)){
        callback(_fallbackSearch(query));
        return;
      }
      var results = data.map(function(item){
        var addr = item.address || {};
        var city = addr.city || addr.town || addr.village || addr.municipality || '';
        var zip = addr.postcode || '';
        var street = addr.road || '';
        var houseNum = addr.house_number || '';
        var hamlet = addr.hamlet || addr.suburb || addr.city_district || addr.quarter || '';
        var label = '';
        var displayStreet = street;
        if(street){
          label = street + (houseNum ? ' ' + houseNum : '') + ', ' + city;
        } else if(hamlet && houseNum){
          // Hamlet address: "Hněvkovice 9, Humpolec"
          label = hamlet + ' ' + houseNum + ', ' + city;
          displayStreet = hamlet;
        } else if(hamlet){
          label = hamlet + ', ' + city;
          displayStreet = hamlet;
        } else if(city){
          label = city + (zip ? ', ' + zip : '');
        } else {
          label = item.display_name || '';
        }
        return {
          label: label,
          street: displayStreet,
          houseNum: houseNum,
          district: hamlet || '',
          lat: parseFloat(item.lat) || null,
          lng: parseFloat(item.lon) || null,
          city: city,
          zip: zip
        };
      }).filter(function(r){ return r.label; });

      results = results.slice(0, 8);
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  /**
   * Search with debounce (for oninput handlers)
   */
  function suggestDebounced(query, callback){
    clearTimeout(_streetDebounce);
    _streetDebounce = setTimeout(function(){
      suggest(query, callback);
    }, _DEBOUNCE_MS);
  }

  /**
   * Calculate driving distance from branch to address
   */
  function calcDistance(addressOrCoords, callback){
    if(!addressOrCoords){ callback(null); return; }

    if(typeof addressOrCoords === 'object' && addressOrCoords.lat){
      _routeFromCoords(addressOrCoords.lat, addressOrCoords.lng, callback);
      return;
    }

    _geocode(addressOrCoords, function(coords){
      if(!coords){
        var km = _fallbackKm(addressOrCoords);
        var fee = 1000 + km * 20;
        callback({ km: km, fee: fee, duration: null, approx: true });
        return;
      }
      _routeFromCoords(coords.lat, coords.lng, callback);
    });
  }

  /**
   * Route calculation from coordinates using OSRM
   */
  function _routeFromCoords(lat, lng, callback){
    var url = OSRM_URL + '/' +
      BRANCH_LNG + ',' + BRANCH_LAT + ';' +
      lng + ',' + lat +
      '?overview=false';

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.routes || !data.routes.length){
        var dist = _haversine(BRANCH_LAT, BRANCH_LNG, lat, lng);
        var km = Math.round(dist * 1.3);
        var fee = 1000 + km * 20;
        callback({ km: km, fee: fee, duration: null, approx: true });
        return;
      }
      var route = data.routes[0];
      var km = Math.round(route.distance / 1000);
      var fee = 1000 + km * 20;
      var mins = Math.round(route.duration / 60);
      callback({ km: km, fee: fee, duration: mins, approx: false });
    });
  }

  /**
   * Geocode address string via Nominatim
   */
  function _geocode(addr, callback){
    var cacheKey = 'geo_' + addr.toLowerCase().trim();
    if(_geoCache[cacheKey]){
      callback(_geoCache[cacheKey]);
      return;
    }

    var url = NOMINATIM_URL +
      '?q=' + encodeURIComponent(addr) +
      '&format=json&countrycodes=cz&limit=1&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.length){
        callback(null);
        return;
      }
      var coords = {
        lat: parseFloat(data[0].lat),
        lng: parseFloat(data[0].lon)
      };
      if(isNaN(coords.lat)){ callback(null); return; }
      _geoCache[cacheKey] = coords;
      callback(coords);
    });
  }

  // ===== HELPERS =====

  function _fetchJSON(url, callback){
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.timeout = 8000;
    xhr.onload = function(){
      if(xhr.status >= 200 && xhr.status < 300){
        try { callback(null, JSON.parse(xhr.responseText)); }
        catch(e){ callback(e, null); }
      } else {
        callback(new Error('HTTP ' + xhr.status), null);
      }
    };
    xhr.onerror = function(){ callback(new Error('Network error'), null); };
    xhr.ontimeout = function(){ callback(new Error('Timeout'), null); };
    xhr.send();
  }

  function _haversine(lat1, lng1, lat2, lng2){
    var R = 6371;
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLng = (lng2 - lng1) * Math.PI / 180;
    var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
      Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*
      Math.sin(dLng/2)*Math.sin(dLng/2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  }

  function _fallbackCities(query){
    if(typeof ADDR_DB === 'undefined') return [];
    var q = query.toLowerCase();
    var seen = {};
    return ADDR_DB.filter(function(a){
      if(seen[a.city]) return false;
      var match = a.city.toLowerCase().indexOf(q) !== -1;
      if(match) seen[a.city] = true;
      return match;
    }).slice(0, 8).map(function(a){
      var zipMatch = a.addr.match(/(\d{3})\s?(\d{2})/);
      return {
        label: a.city,
        city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : '',
        district: '',
        lat: null, lng: null
      };
    });
  }

  function _fallbackStreets(query, city){
    if(typeof ADDR_DB === 'undefined') return [];
    var q = query.toLowerCase();
    var results = ADDR_DB.filter(function(a){
      if(city && a.city.toLowerCase() !== city.toLowerCase()) return false;
      return a.addr.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 8).map(function(a){
      var zipMatch = a.addr.match(/(\d{3})\s?(\d{2})/);
      var streetMatch = a.addr.match(/^([^,]+?)(?:,\s*\d)/);
      var street = streetMatch ? streetMatch[1] : '';
      var numMatch = street.match(/^(.+?)\s+(\d+.*)$/);
      return {
        label: street || a.addr,
        street: numMatch ? numMatch[1] : street,
        houseNum: numMatch ? numMatch[2] : '',
        district: '',
        city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : '',
        lat: null, lng: null
      };
    });
    return results;
  }

  function _fallbackSearch(query){
    if(typeof ADDR_DB === 'undefined') return [];
    var q = query.toLowerCase();
    return ADDR_DB.filter(function(a){
      return a.addr.toLowerCase().indexOf(q) !== -1 ||
        a.city.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 8).map(function(a){
      var zipMatch = a.addr.match(/(\d{3})\s?(\d{2})/);
      var streetMatch = a.addr.match(/^([^,]+?)(?:,\s*\d)/);
      var street = streetMatch ? streetMatch[1] : '';
      var numMatch = street.match(/^(.+?)\s+(\d+.*)$/);
      return {
        label: a.addr, lat: null, lng: null,
        street: numMatch ? numMatch[1] : street,
        houseNum: numMatch ? numMatch[2] : '',
        district: '',
        city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : ''
      };
    });
  }

  function _fallbackKm(addr){
    var val = addr.toLowerCase();
    if(typeof KM_ESTIMATES !== 'undefined'){
      for(var c in KM_ESTIMATES){
        if(val.indexOf(c.toLowerCase()) !== -1) return KM_ESTIMATES[c];
      }
    }
    return Math.round(20 + addr.length * 1.5);
  }

  /**
   * Reverse geocode coordinates → address components
   */
  function reverseGeocode(lat, lng, callback){
    var url = 'https://nominatim.openstreetmap.org/reverse' +
      '?lat=' + lat + '&lon=' + lng +
      '&format=json&addressdetails=1&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.address){
        callback(null);
        return;
      }
      var addr = data.address;
      callback({
        street: addr.road || '',
        houseNum: addr.house_number || '',
        city: addr.city || addr.town || addr.village || addr.municipality || '',
        zip: addr.postcode || '',
        lat: lat,
        lng: lng
      });
    });
  }

  return {
    suggest: suggest,
    suggestDebounced: suggestDebounced,
    suggestCities: suggestCities,
    suggestCitiesDebounced: suggestCitiesDebounced,
    suggestStreets: suggestStreets,
    suggestStreetsDebounced: suggestStreetsDebounced,
    calcDistance: calcDistance,
    reverseGeocode: reverseGeocode,
    BRANCH_LAT: BRANCH_LAT,
    BRANCH_LNG: BRANCH_LNG
  };
})();
