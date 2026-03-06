// ===== ADDRESS-API.JS – Czech address autocomplete via Mapy.cz + OSRM distance =====
// Replaces hardcoded ADDR_DB with live Mapy.cz Suggest API
// Falls back to local ADDR_DB if offline or API fails

var AddressAPI = (function(){
  'use strict';

  // Mapy.cz Suggest API (free, no key required, Czech addresses)
  var SUGGEST_URL = 'https://api.mapy.cz/v1/suggest';
  var MAPY_API_KEY = ''; // empty = free tier (limited but sufficient)

  // OSRM public demo server for distance calculation
  var OSRM_URL = 'https://router.project-osrm.org/route/v1/driving';

  // Branch coordinates (Mezná 9, 393 01)
  var BRANCH_LAT = 49.4147;
  var BRANCH_LNG = 15.2953;

  // Cache for recent searches
  var _cache = {};
  var _CACHE_TTL = 300000; // 5 min

  // Debounce timer
  var _debounceTimer = null;
  var _DEBOUNCE_MS = 300;

  // Geocode cache for distance calculations
  var _geoCache = {};

  /**
   * Search Czech addresses via Mapy.cz Suggest API
   * Returns array of {label, lat, lng, city, zip}
   */
  function suggest(query, callback){
    if(!query || query.length < 2){ callback([]); return; }

    var cacheKey = query.toLowerCase().trim();
    if(_cache[cacheKey] && (Date.now() - _cache[cacheKey].ts < _CACHE_TTL)){
      callback(_cache[cacheKey].data);
      return;
    }

    var url = SUGGEST_URL +
      '?query=' + encodeURIComponent(query) +
      '&lang=cs' +
      '&limit=6' +
      '&type=regional.address' +
      '&country=cz';
    if(MAPY_API_KEY) url += '&apikey=' + MAPY_API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items){
        // Fallback to local DB
        callback(_fallbackSearch(query));
        return;
      }
      var results = data.items.map(function(item){
        var pos = item.position || {};
        return {
          label: item.name || '',
          lat: pos.lat || null,
          lng: pos.lon || null,
          city: _extractCity(item),
          zip: _extractZip(item)
        };
      }).filter(function(r){ return r.label; });

      _cache[cacheKey] = { data: results, ts: Date.now() };
      callback(results);
    });
  }

  /**
   * Search with debounce (for oninput handlers)
   */
  function suggestDebounced(query, callback){
    clearTimeout(_debounceTimer);
    _debounceTimer = setTimeout(function(){
      suggest(query, callback);
    }, _DEBOUNCE_MS);
  }

  /**
   * Calculate driving distance from branch to address
   * Returns {km, fee, duration} via callback
   */
  function calcDistance(addressOrCoords, callback){
    if(!addressOrCoords){ callback(null); return; }

    if(typeof addressOrCoords === 'object' && addressOrCoords.lat){
      _routeFromCoords(addressOrCoords.lat, addressOrCoords.lng, callback);
      return;
    }

    // Need to geocode first
    _geocode(addressOrCoords, function(coords){
      if(!coords){
        // Fallback to KM_ESTIMATES
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
        // Fallback: Haversine estimate
        var dist = _haversine(BRANCH_LAT, BRANCH_LNG, lat, lng);
        var km = Math.round(dist * 1.3); // road factor
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
   * Geocode address string to coordinates via Mapy.cz
   */
  function _geocode(addr, callback){
    var cacheKey = 'geo_' + addr.toLowerCase().trim();
    if(_geoCache[cacheKey]){
      callback(_geoCache[cacheKey]);
      return;
    }

    var url = 'https://api.mapy.cz/v1/geocode' +
      '?query=' + encodeURIComponent(addr) +
      '&lang=cs&limit=1&country=cz';
    if(MAPY_API_KEY) url += '&apikey=' + MAPY_API_KEY;

    _fetchJSON(url, function(err, data){
      if(err || !data || !data.items || !data.items.length){
        callback(null);
        return;
      }
      var pos = data.items[0].position;
      if(!pos){ callback(null); return; }
      var coords = { lat: pos.lat, lng: pos.lon };
      _geoCache[cacheKey] = coords;
      callback(coords);
    });
  }

  // ===== HELPERS =====

  function _fetchJSON(url, callback){
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.timeout = 5000;
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

  function _extractCity(item){
    if(item.regionalStructure){
      for(var i = 0; i < item.regionalStructure.length; i++){
        var r = item.regionalStructure[i];
        if(r.type === 'regional.municipality') return r.name || '';
      }
    }
    if(item.location) return item.location;
    return '';
  }

  function _extractZip(item){
    if(item.zip) return item.zip;
    var match = (item.name || '').match(/(\d{3})\s?(\d{2})/);
    return match ? match[1] + ' ' + match[2] : '';
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

  /**
   * Fallback: search local ADDR_DB when API is unavailable
   */
  function _fallbackSearch(query){
    if(typeof ADDR_DB === 'undefined') return [];
    var q = query.toLowerCase();
    return ADDR_DB.filter(function(a){
      return a.addr.toLowerCase().indexOf(q) !== -1 ||
        a.city.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 6).map(function(a){
      var zipMatch = a.addr.match(/(\d{3})\s?(\d{2})/);
      return {
        label: a.addr,
        lat: null,
        lng: null,
        city: a.city,
        zip: zipMatch ? zipMatch[1] + ' ' + zipMatch[2] : ''
      };
    });
  }

  /**
   * Fallback: estimate km from KM_ESTIMATES when API is unavailable
   */
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
    calcDistance: calcDistance,
    BRANCH_LAT: BRANCH_LAT,
    BRANCH_LNG: BRANCH_LNG
  };
})();
