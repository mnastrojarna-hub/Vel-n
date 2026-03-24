// ===== ADDRESS-API.JS – Czech address autocomplete via Mapy.cz REST API v1 =====
// Uses Mapy.cz Suggest (excellent Czech address search, Revolut-level quality)
// + Mapy.cz Routing for real road distance
// Falls back to local ADDR_DB if offline or API fails
// API key: free tier at developer.mapy.cz

var AddressAPI = (function(){
  'use strict';

  // Mapy.cz REST API v1 (free tier: 10 000 req/day)
  var API_BASE = 'https://api.mapy.cz/v1';
  var API_KEY = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';

  // Branch coordinates (Mezná 9, 393 01)
  var BRANCH_LAT = 49.4147;
  var BRANCH_LNG = 15.2953;

  // Cache for recent searches
  var _cache = {};
  var _CACHE_TTL = 300000; // 5 min

  // Separate debounce timers for city vs street
  var _cityDebounce = null;
  var _streetDebounce = null;
  var _DEBOUNCE_MS = 200; // faster than Nominatim, Mapy.cz handles it

  // Geocode cache for distance calculations
  var _geoCache = {};

  // ===== SUGGEST CITIES =====

  function suggestCities(query, callback){
    if(!query || query.length < 2){ callback([]); return; }
    var cacheKey = 'city_' + query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data); return;
    }
    var url = API_BASE + '/suggest' +
      '?query=' + encodeURIComponent(query) +
      '&lang=cs&limit=8&type=regional.municipality&locality=cz' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items){
        callback(_fallbackCities(query)); return;
      }
      var cities = data.items.map(function(item){
        var city = item.name || '';
        var zip = item.zip || '';
        var district = _getRegion(item, 'regional.district') || _getRegion(item, 'regional.region') || '';
        return {
          label: city,
          city: city,
          zip: zip,
          district: district,
          lat: item.position ? item.position.lat : null,
          lng: item.position ? item.position.lon : null
        };
      });
      _cache[cacheKey] = { data: cities, ts: Date.now() };
      callback(cities);
    });
  }

  function suggestCitiesDebounced(query, callback){
    clearTimeout(_cityDebounce);
    _cityDebounce = setTimeout(function(){
      suggestCities(query, callback);
    }, _DEBOUNCE_MS);
  }

  // ===== SUGGEST STREETS / ADDRESSES =====

  function suggestStreets(query, city, callback){
    if(!query || query.length < 2){ callback([]); return; }
    var searchTerm = city ? (query + ', ' + city) : query;
    var cacheKey = 'street_' + searchTerm.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data); return;
    }
    var url = API_BASE + '/suggest' +
      '?query=' + encodeURIComponent(searchTerm) +
      '&lang=cs&limit=8&type=regional.address&locality=cz' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items || data.items.length === 0){
        // Fallback: try without type filter (catches hamlets, POIs)
        _suggestStreetsFallback(searchTerm, cacheKey, query, city, callback);
        return;
      }
      var results = _parseMapyczResults(data.items, city);
      if(results.length === 0){
        _suggestStreetsFallback(searchTerm, cacheKey, query, city, callback);
        return;
      }
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  function _suggestStreetsFallback(searchTerm, cacheKey, query, city, callback){
    // Try broader search without type restriction
    var url = API_BASE + '/suggest' +
      '?query=' + encodeURIComponent(searchTerm) +
      '&lang=cs&limit=8&locality=cz' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items){
        callback(_fallbackStreets(query, city)); return;
      }
      var results = _parseMapyczResults(data.items, city);
      if(results.length === 0){ results = _fallbackStreets(query, city); }
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  function suggestStreetsDebounced(query, city, callback){
    clearTimeout(_streetDebounce);
    _streetDebounce = setTimeout(function(){
      suggestStreets(query, city, callback);
    }, _DEBOUNCE_MS);
  }

  // ===== LEGACY SUGGEST (combined) =====

  function suggest(query, callback){
    if(!query || query.length < 2){ callback([]); return; }
    var cacheKey = 'q_' + query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data); return;
    }
    var url = API_BASE + '/suggest' +
      '?query=' + encodeURIComponent(query) +
      '&lang=cs&limit=8&locality=cz' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items){
        callback(_fallbackSearch(query)); return;
      }
      var results = _parseMapyczResults(data.items, null);
      if(results.length === 0){ results = _fallbackSearch(query); }
      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  function suggestDebounced(query, callback){
    clearTimeout(_streetDebounce);
    _streetDebounce = setTimeout(function(){
      suggest(query, callback);
    }, _DEBOUNCE_MS);
  }

  // ===== PARSE MAPY.CZ RESULTS =====

  function _parseMapyczResults(items, filterCity){
    var results = [];
    var seen = {};

    items.forEach(function(item){
      var name = item.name || '';
      var label = item.label || name;
      var zip = item.zip || '';
      var cat = item.category || '';
      var pos = item.position || {};
      var lat = pos.lat || null;
      var lon = pos.lon || null;

      // Extract city and district from regionalStructure
      var municipality = _getRegion(item, 'regional.municipality') || '';
      var district = _getRegion(item, 'regional.municipality_part') ||
                     _getRegion(item, 'regional.district') || '';

      // Parse street and house number from name
      var street = '', houseNum = '';
      if(cat === 'regional.address'){
        // Mapy.cz address format: "Ulice čp/čo" or "Obec čp"
        var numMatch = name.match(/^(.+?)\s+(\d+\/?[\da-zA-Z]*)$/);
        if(numMatch){
          street = numMatch[1];
          houseNum = numMatch[2];
        } else {
          street = name;
        }
      } else if(cat === 'regional.street'){
        street = name;
      } else if(cat === 'regional.municipality' || cat === 'regional.municipality_part'){
        street = name;
        municipality = municipality || name;
      } else {
        // POI or other — use name as-is
        street = name;
      }

      // City: from municipality, or from label parsing
      var city = municipality;
      if(!city && label){
        var labelParts = label.split(',');
        if(labelParts.length > 1) city = labelParts[labelParts.length - 1].trim();
      }

      // Filter by city if needed
      if(filterCity && city){
        var fc = filterCity.toLowerCase();
        var cc = city.toLowerCase();
        var cityOk = (cc === fc) || cc.indexOf(fc) !== -1 || fc.indexOf(cc) !== -1;
        if(!cityOk) return;
      }

      var key = (street + ' ' + houseNum + ' ' + city).trim();
      if(seen[key]) return;
      seen[key] = true;

      results.push({
        label: street + (houseNum ? ' ' + houseNum : ''),
        street: street,
        houseNum: houseNum,
        district: district,
        city: city,
        zip: zip,
        lat: lat,
        lng: lon
      });
    });

    return results.slice(0, 8);
  }

  function _getRegion(item, type){
    if(!item.regionalStructure) return '';
    for(var i = 0; i < item.regionalStructure.length; i++){
      if(item.regionalStructure[i].type === type) return item.regionalStructure[i].name;
    }
    return '';
  }

  // ===== DISTANCE CALCULATION (Mapy.cz Routing) =====

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
   * Road routing via Mapy.cz Routing API
   */
  function _routeFromCoords(lat, lng, callback){
    var url = API_BASE + '/routing/route' +
      '?start=' + BRANCH_LNG + ',' + BRANCH_LAT +
      '&end=' + lng + ',' + lat +
      '&routeType=car_fast&lang=cs' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data){
        // Fallback to OSRM
        _routeOSRM(lat, lng, callback);
        return;
      }
      // Mapy.cz returns { length: meters, duration: seconds, geometry: ... }
      var routeLen = data.length || (data.route && data.route.length) || 0;
      var routeDur = data.duration || (data.route && data.route.duration) || 0;
      // Also handle array response: [{ length, duration }]
      if(Array.isArray(data) && data[0]){
        routeLen = data[0].length || 0;
        routeDur = data[0].duration || 0;
      }
      if(!routeLen){
        _routeOSRM(lat, lng, callback); return;
      }
      var km = Math.round(routeLen / 1000);
      var fee = 1000 + km * 20;
      var mins = Math.round(routeDur / 60);
      callback({ km: km, fee: fee, duration: mins, approx: false });
    });
  }

  /**
   * Fallback routing via OSRM (if Mapy.cz routing fails)
   */
  function _routeOSRM(lat, lng, callback){
    var url = 'https://router.project-osrm.org/route/v1/driving/' +
      BRANCH_LNG + ',' + BRANCH_LAT + ';' +
      lng + ',' + lat + '?overview=false';

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
   * Geocode via Mapy.cz Geocode API
   */
  function _geocode(addr, callback){
    var cacheKey = 'geo_' + addr.toLowerCase().trim();
    if(_geoCache[cacheKey]){
      callback(_geoCache[cacheKey]); return;
    }
    var url = API_BASE + '/geocode' +
      '?query=' + encodeURIComponent(addr) +
      '&lang=cs&limit=1&locality=cz' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items || !data.items.length){
        // Fallback to Nominatim
        _geocodeNominatim(addr, callback);
        return;
      }
      var pos = data.items[0].position;
      if(!pos || !pos.lat){ callback(null); return; }
      var coords = { lat: pos.lat, lng: pos.lon };
      _geoCache[cacheKey] = coords;
      callback(coords);
    });
  }

  function _geocodeNominatim(addr, callback){
    var url = 'https://nominatim.openstreetmap.org/search' +
      '?q=' + encodeURIComponent(addr) +
      '&format=json&countrycodes=cz&limit=1&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.length){ callback(null); return; }
      var coords = { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) };
      if(isNaN(coords.lat)){ callback(null); return; }
      _geoCache['geo_' + addr.toLowerCase().trim()] = coords;
      callback(coords);
    });
  }

  /**
   * Reverse geocode via Mapy.cz
   */
  function reverseGeocode(lat, lng, callback){
    var url = API_BASE + '/rgeocode' +
      '?lat=' + lat + '&lon=' + lng +
      '&lang=cs' +
      '&apikey=' + API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items || !data.items.length){
        // Fallback to Nominatim reverse
        _reverseNominatim(lat, lng, callback);
        return;
      }
      var item = data.items[0];
      var name = item.name || '';
      var numMatch = name.match(/^(.+?)\s+(\d+\/?[\da-zA-Z]*)$/);
      var street = numMatch ? numMatch[1] : name;
      var houseNum = numMatch ? numMatch[2] : '';
      var city = _getRegion(item, 'regional.municipality') || '';
      var zip = item.zip || '';
      callback({
        street: street,
        houseNum: houseNum,
        city: city,
        zip: zip,
        lat: lat,
        lng: lng
      });
    });
  }

  function _reverseNominatim(lat, lng, callback){
    var url = 'https://nominatim.openstreetmap.org/reverse' +
      '?lat=' + lat + '&lon=' + lng +
      '&format=json&addressdetails=1&accept-language=cs';

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.address){ callback(null); return; }
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

  // ===== HELPERS =====

  function _fetchJSON(url, callback){
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.timeout = 6000;
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
        label: a.city, city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : '',
        district: '', lat: null, lng: null
      };
    });
  }

  function _fallbackStreets(query, city){
    if(typeof ADDR_DB === 'undefined') return [];
    var q = query.toLowerCase();
    return ADDR_DB.filter(function(a){
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
        district: '', city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : '',
        lat: null, lng: null
      };
    });
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
        district: '', city: a.city,
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
    reverseGeocode: reverseGeocode,
    BRANCH_LAT: BRANCH_LAT,
    BRANCH_LNG: BRANCH_LNG
  };
})();
