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
   */
  function suggestCities(query, callback){
    if(!query || query.length < 2){ callback([]); return; }

    var cacheKey = 'city_' + query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

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
      // If not enough unique cities, also try matching display_name
      if(cities.length < 3){
        data.forEach(function(item){
          var name = item.display_name || '';
          var parts = name.split(',');
          var first = (parts[0] || '').trim();
          if(first && !seen[first] && first.toLowerCase().indexOf(query.toLowerCase()) !== -1){
            seen[first] = true;
            var addr = item.address || {};
            cities.push({
              label: first,
              city: first,
              zip: addr.postcode || '',
              district: addr.county || '',
              lat: parseFloat(item.lat) || null,
              lng: parseFloat(item.lon) || null
            });
          }
        });
      }
      cities = cities.slice(0, 8);
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
   * Suggest streets within a city (or general address if no city)
   */
  function suggestStreets(query, city, callback){
    if(!query || query.length < 2){ callback([]); return; }

    // Build search: "street, city" for better Nominatim results
    var searchTerm = city ? (query + ', ' + city) : query;

    var cacheKey = 'street_' + searchTerm.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

    var url = NOMINATIM_URL +
      '?q=' + encodeURIComponent(searchTerm) +
      '&format=json' +
      '&addressdetails=1' +
      '&countrycodes=cz' +
      '&limit=12' +
      '&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !Array.isArray(data)){
        callback(_fallbackStreets(query, city));
        return;
      }
      var results = [];
      var seen = {};
      data.forEach(function(item){
        var addr = item.address || {};
        var itemCity = addr.city || addr.town || addr.village || addr.municipality || '';
        var street = addr.road || '';
        var houseNum = addr.house_number || '';
        var zip = addr.postcode || '';
        var district = addr.suburb || addr.city_district || addr.quarter || '';

        if(!street) return;
        // If city was specified, prefer results from that city
        if(city && itemCity && itemCity.toLowerCase() !== city.toLowerCase()) return;

        var key = street + '_' + houseNum;
        if(seen[key]) return;
        seen[key] = true;

        var label = street + (houseNum ? ' ' + houseNum : '');
        results.push({
          label: label,
          street: street,
          houseNum: houseNum,
          district: district,
          lat: parseFloat(item.lat) || null,
          lng: parseFloat(item.lon) || null,
          city: itemCity || city || '',
          zip: zip
        });
      });

      // If strict city filter returned too few, retry without filter
      if(results.length < 3 && city){
        data.forEach(function(item){
          var addr = item.address || {};
          var itemCity = addr.city || addr.town || addr.village || addr.municipality || '';
          var street = addr.road || '';
          var houseNum = addr.house_number || '';
          var zip = addr.postcode || '';
          var district = addr.suburb || addr.city_district || addr.quarter || '';
          if(!street) return;
          var key = street + '_' + houseNum;
          if(seen[key]) return;
          seen[key] = true;
          results.push({
            label: street + (houseNum ? ' ' + houseNum : ''),
            street: street,
            houseNum: houseNum,
            district: district,
            lat: parseFloat(item.lat) || null,
            lng: parseFloat(item.lon) || null,
            city: itemCity || city || '',
            zip: zip
          });
        });
      }

      results = results.slice(0, 8);
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
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
        var district = addr.suburb || addr.city_district || addr.quarter || '';
        var label = '';
        if(street){
          label = street + (houseNum ? ' ' + houseNum : '') + ', ' + city;
        } else if(city){
          label = city + (zip ? ', ' + zip : '');
        } else {
          label = item.display_name || '';
        }
        return {
          label: label,
          street: street,
          houseNum: houseNum,
          district: district,
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

  return {
    suggest: suggest,
    suggestDebounced: suggestDebounced,
    suggestCities: suggestCities,
    suggestCitiesDebounced: suggestCitiesDebounced,
    suggestStreets: suggestStreets,
    suggestStreetsDebounced: suggestStreetsDebounced,
    calcDistance: calcDistance,
    BRANCH_LAT: BRANCH_LAT,
    BRANCH_LNG: BRANCH_LNG
  };
})();
