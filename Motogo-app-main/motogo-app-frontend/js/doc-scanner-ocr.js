// ===== DOC-SCANNER-OCR.JS – Mindee API OCR (v5.0.0) =====
// Sends captured image to Supabase Edge Function → Mindee API
// Returns structured data (no local parsing needed)

(function(){
  'use strict';

  var MAX_RETRIES = 2; // celkem 3 pokusy (1 + 2 retry)

  // Determine document type for API
  function _getApiDocType(scanType){
    if(scanType==='dl_front'||scanType==='dl_back') return 'dl';
    if(scanType==='passport_front') return 'passport';
    return 'id';
  }

  // Get user ID from current session (best-effort, non-blocking)
  function _getUserId(){
    try {
      if(window.supabase && window.supabase.auth){
        return window.supabase.auth.getSession().then(function(r){
          return (r.data && r.data.session && r.data.session.user) ? r.data.session.user.id : null;
        }).catch(function(){ return null; });
      }
    } catch(e){}
    return Promise.resolve(null);
  }

  // Resize image to max dimension for OCR (saves bandwidth, avoids body size limits)
  var MAX_OCR_DIM = 1600; // px — sufficient for Mindee OCR
  var OCR_JPEG_QUALITY = 0.80;

  function _resizeForOCR(canvas){
    var w = canvas.width, h = canvas.height;
    if(w <= MAX_OCR_DIM && h <= MAX_OCR_DIM) return canvas;
    var scale = Math.min(MAX_OCR_DIM / w, MAX_OCR_DIM / h);
    var nw = Math.round(w * scale), nh = Math.round(h * scale);
    var c2 = document.createElement('canvas');
    c2.width = nw; c2.height = nh;
    c2.getContext('2d').drawImage(canvas, 0, 0, nw, nh);
    return c2;
  }

  // Send image to Mindee via Edge Function using supabase.functions.invoke()
  // This handles JWT auth automatically via the Supabase client
  function runOCR(canvas, cb){
    if(!window.supabase || !window.supabase.functions){
      console.error('[DocScanner] supabase client or functions not available!',
        'supabase:', !!window.supabase,
        'functions:', !!(window.supabase && window.supabase.functions));
      cb(new Error('Supabase client not available'), '');
      return;
    }

    var docType = _getApiDocType(DocScanner.getDocType());

    // Resize to max 1600px and use lower quality — OCR doesn't need 4K
    var resized = _resizeForOCR(canvas);
    var dataUri = resized.toDataURL('image/jpeg', OCR_JPEG_QUALITY);
    var imageBase64 = dataUri.indexOf(',') !== -1 ? dataUri.split(',')[1] : dataUri;

    console.log('[DocScanner] Image for OCR: '+resized.width+'x'+resized.height+' base64len='+imageBase64.length+' (~'+Math.round(imageBase64.length/1024)+'KB)');

    _getUserId().then(function(userId){
      console.log('[DocScanner] Calling scan-document via supabase.functions.invoke, user='+(userId||'anon'));
      _invokeWithRetry(imageBase64, docType, userId, 0, cb);
    });
  }

  function _invokeWithRetry(imageBase64, docType, userId, attempt, cb){
    console.log('[DocScanner] OCR attempt '+(attempt+1)+'/'+(MAX_RETRIES+1)+' type='+docType+' base64len='+imageBase64.length);

    window.supabase.functions.invoke('scan-document', {
      body: {
        image_base64: imageBase64,
        document_type: docType,
        user_id: userId
      }
    })
    .then(function(res){
      var error = res.error;
      var data = res.data;

      console.log('[DocScanner] invoke response: error=', error, 'data type=', typeof data, 'data=', data ? (typeof data === 'string' ? data.substring(0,200) : JSON.stringify(data).substring(0,200)) : null);

      // functions.invoke returns {data, error}
      if(error){
        var errMsg = (error.message || error.msg || String(error));
        var errContext = error.context || '';
        console.error('[DocScanner] invoke error (attempt '+(attempt+1)+'):', errMsg, 'context:', errContext, 'full:', error);
        if(attempt < MAX_RETRIES){
          setTimeout(function(){
            _invokeWithRetry(imageBase64, docType, userId, attempt+1, cb);
          }, 1000 * (attempt+1));
          return;
        }
        cb(new Error(errMsg), '');
        return;
      }

      // Parse result — data may be string or object
      var result = data;
      if(typeof data === 'string'){
        try { result = JSON.parse(data); } catch(e){ result = {}; }
      }

      if(result && result.success && result.data){
        var textParts = [];
        var d = result.data;
        if(d.lastName) textParts.push(d.lastName);
        if(d.firstName) textParts.push(d.firstName);
        if(d.dob) textParts.push(d.dob);
        if(d.idNumber) textParts.push(d.idNumber);
        if(d.licenseNumber) textParts.push(d.licenseNumber);
        if(d.address) textParts.push(d.address);
        if(d.licenseCategory) textParts.push('Sk. '+d.licenseCategory);
        var text = textParts.join('\n');

        console.log('[DocScanner] Mindee OK: '+Object.keys(d).filter(function(k){return !!d[k];}).length+' fields');
        DocScanner._lastMindeeData = result.data;
        cb(null, text);
      } else if(attempt < MAX_RETRIES){
        console.warn('[DocScanner] Mindee no data (attempt '+(attempt+1)+'), retrying...');
        setTimeout(function(){
          _invokeWithRetry(imageBase64, docType, userId, attempt+1, cb);
        }, 1000 * (attempt+1));
      } else {
        var errDetail = (result && result.error) || 'OCR failed — no data';
        console.error('[DocScanner] Mindee failed after all retries:', errDetail);
        cb(new Error(errDetail), '');
      }
    })
    .catch(function(err){
      if(attempt < MAX_RETRIES){
        console.warn('[DocScanner] OCR error, retrying:', err.message);
        setTimeout(function(){
          _invokeWithRetry(imageBase64, docType, userId, attempt+1, cb);
        }, 1000 * (attempt+1));
      } else {
        console.error('[DocScanner] OCR failed after all retries:', err);
        cb(err, '');
      }
    });
  }

  // Merge results from all scanned document sides
  function mergeResults(){
    var merged = {};
    var allData = DocScanner._allMindeeData || {};

    var fields = ['firstName','lastName','dob','idNumber','address',
      'issuedDate','expiryDate','nationality','sex',
      'licenseCategory','licenseNumber'];

    DocScanner.getSequence().forEach(function(key){
      var d = allData[key];
      if(!d) return;
      fields.forEach(function(f){
        if(d[f] && !merged[f]) merged[f] = d[f];
      });
    });

    var result = {};
    if(merged.firstName) result.firstName = merged.firstName;
    if(merged.lastName) result.lastName = merged.lastName;
    if(merged.dob) result.dob = _formatDate(merged.dob);
    if(merged.idNumber) result.idNumber = merged.idNumber;
    if(merged.address){
      var addr = _parseAddress(merged.address);
      if(addr.street) result.street = addr.street;
      if(addr.city) result.city = addr.city;
      if(addr.zip) result.zip = addr.zip;
    }
    if(merged.licenseCategory) result.licenseCategory = merged.licenseCategory;
    // License number: prefer explicit licenseNumber, fallback to idNumber from DL
    if(merged.licenseNumber){
      result.licenseNumber = merged.licenseNumber;
    } else if(merged.idNumber && /^[A-Z]{1,2}\s*\d+/.test(merged.idNumber)){
      result.licenseNumber = merged.idNumber;
    }
    if(merged.issuedDate) result.licenseIssued = _formatDate(merged.issuedDate);
    if(merged.expiryDate) result.licenseExpiry = _formatDate(merged.expiryDate);

    if(!result.zip && (result.city || result.street)){
      result._zipPromise = _lookupZip(result.city, result.street);
    }

    return result;
  }

  function _formatDate(isoDate){
    if(!isoDate) return '';
    var m = isoDate.match(/(\d{4})-(\d{2})-(\d{2})/);
    if(m) return parseInt(m[3])+'. '+parseInt(m[2])+'. '+m[1];
    return isoDate;
  }

  function _parseAddress(addr){
    var result = {};
    if(!addr) return result;
    var zipMatch = addr.match(/(\d{3})\s*(\d{2})/);
    if(zipMatch) result.zip = zipMatch[1]+' '+zipMatch[2];
    var parts = addr.split(/,/).map(function(p){return p.trim();});
    if(parts.length >= 1) result.street = parts[0];
    if(parts.length >= 2) result.city = parts[parts.length-1].replace(/\d{3}\s*\d{2}/,'').trim();
    return result;
  }

  function _lookupZip(city, street){
    if(!city) return Promise.resolve('');
    var query = (street ? street + ', ' : '') + city + ', Česko';
    var url = 'https://nominatim.openstreetmap.org/search?format=json&limit=1' +
      '&countrycodes=cz&q=' + encodeURIComponent(query);
    return fetch(url, {headers:{'Accept-Language':'cs'}})
      .then(function(r){ return r.json(); })
      .then(function(arr){
        if(!arr || !arr.length) return '';
        var display = arr[0].display_name || '';
        var zm = display.match(/(\d{3})\s*(\d{2})/);
        return zm ? zm[1]+' '+zm[2] : '';
      })
      .catch(function(){ return ''; });
  }

  // Override: store Mindee data per document type
  var _origSetResult = DocScanner.setResult;
  DocScanner.setResult = function(key, text){
    _origSetResult(key, text);
    if(DocScanner._lastMindeeData){
      if(!DocScanner._allMindeeData) DocScanner._allMindeeData = {};
      DocScanner._allMindeeData[key] = DocScanner._lastMindeeData;
      DocScanner._lastMindeeData = null;
    }
  };

  var _origReset = DocScanner.reset;
  DocScanner.reset = function(){
    _origReset();
    DocScanner._allMindeeData = {};
    DocScanner._lastMindeeData = null;
  };

  function fillRegistration(data){
    var map = {
      'reg-fname': data.firstName||'',
      'reg-lname': data.lastName||'',
      'reg-dob': data.dob||'',
      'reg-street': data.street||'',
      'reg-zip': data.zip||'',
      'reg-city': data.city||'',
      'reg-license-num': data.licenseNumber||'',
      'reg-license-from': data.licenseIssued||'',
      'reg-license-to': data.licenseExpiry||''
    };
    Object.keys(map).forEach(function(id){
      var el=document.getElementById(id);
      if(el && map[id]) el.value = map[id];
    });
    if(data._zipPromise){
      data._zipPromise.then(function(zip){
        if(zip){
          var zipEl=document.getElementById('reg-zip');
          if(zipEl && !zipEl.value) zipEl.value = zip;
        }
      });
    }
    if(data.licenseCategory){
      var sel=document.getElementById('reg-license-group');
      if(sel) for(var i=0;i<sel.options.length;i++){
        if(sel.options[i].value===data.licenseCategory){sel.selectedIndex=i;break;}
      }
    }
    try{
      localStorage.setItem('mg_scan_token',JSON.stringify({
        scanned:new Date().toISOString(),
        types:Object.keys(DocScanner._allMindeeData||{}),
        device:'mindee-cloud',dataStored:'local-only',gdpr:'EU-compliant'
      }));
      localStorage.setItem('mg_docs_verified','1');
    }catch(e){}
  }

  function fillProfile(data){
    var map={
      'profile-name':((data.firstName||'')+' '+(data.lastName||'')).trim(),
      'profile-street':data.street||'','profile-zip':data.zip||'',
      'profile-city':data.city||'','profile-dob':data.dob||'',
      'profile-license-num':data.licenseNumber||'',
      'profile-license-expiry':data.licenseExpiry||'',
      'profile-license-group':data.licenseCategory||''
    };
    Object.keys(map).forEach(function(id){
      var el=document.getElementById(id);
      if(el && map[id]) el.value = map[id];
    });
    if(data._zipPromise){
      data._zipPromise.then(function(zip){
        if(zip){
          var zipEl=document.getElementById('profile-zip');
          if(zipEl && !zipEl.value) zipEl.value = zip;
        }
      });
    }
  }

  // Attach to DocScanner
  DocScanner.runOCR = runOCR;
  DocScanner.mergeResults = mergeResults;
  DocScanner.fillRegistration = fillRegistration;
  DocScanner.fillProfile = fillProfile;
})();
