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

  // Check if a JWT is expired (with 30s margin)
  function _isExpired(token){
    try {
      var parts = token.split('.');
      if(parts.length !== 3) return true;
      var payload = JSON.parse(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')));
      if(!payload.exp) return false;
      return (payload.exp * 1000) < (Date.now() - 30000);
    } catch(e){ return true; }
  }

  // Get real JWT from Supabase SDK (not fake localStorage token)
  // Always refresh session first to avoid expired token → 401
  function _getRealToken(anonKey){
    try {
      if(window.supabase && window.supabase.auth){
        return window.supabase.auth.refreshSession().then(function(ref){
          if(ref.data && ref.data.session && ref.data.session.access_token){
            var t = ref.data.session.access_token;
            if(!_isExpired(t)) return { token: t, userId: ref.data.session.user.id };
          }
          // Refresh failed or returned expired token — try getSession
          return window.supabase.auth.getSession().then(function(r){
            if(r.data && r.data.session && r.data.session.access_token){
              var t2 = r.data.session.access_token;
              if(!_isExpired(t2)) return { token: t2, userId: r.data.session.user.id };
            }
            // All tokens expired — use anon key (always valid)
            return { token: anonKey, userId: null };
          });
        }).catch(function(){
          return window.supabase.auth.getSession().then(function(r){
            if(r.data && r.data.session && r.data.session.access_token){
              var t3 = r.data.session.access_token;
              if(!_isExpired(t3)) return { token: t3, userId: r.data.session.user.id };
            }
            return { token: anonKey, userId: null };
          }).catch(function(){ return { token: anonKey, userId: null }; });
        });
      }
    } catch(e){}
    return Promise.resolve({ token: anonKey, userId: null });
  }

  // Send image to Mindee via Edge Function (with retry)
  function runOCR(canvas, cb){
    var cfg = window.MOTOGO_CONFIG || {};
    var baseUrl = cfg.SUPABASE_URL;
    var anonKey = cfg.SUPABASE_ANON_KEY;
    if(!baseUrl || !anonKey){
      cb(new Error('Missing Supabase config'), '');
      return;
    }

    var docType = _getApiDocType(DocScanner.getDocType());

    // Odeslat BAREVNÝ JPEG – Mindee potřebuje barvy
    // Strip data URI prefix – posíláme čistý base64
    var dataUri = canvas.toDataURL('image/jpeg', 0.92);
    var imageBase64 = dataUri.indexOf(',') !== -1 ? dataUri.split(',')[1] : dataUri;

    // Get real JWT from Supabase SDK (mg_current_session has fake token)
    _getRealToken(anonKey).then(function(auth){
      console.log('[DocScanner] Token type: '+(auth.userId ? 'user JWT' : 'anon key')+
        ', token prefix: '+auth.token.substring(0,20)+'...');
      _sendWithRetry(baseUrl, anonKey, auth.token, imageBase64, docType, auth.userId, 0, cb);
    });
  }

  function _sendWithRetry(baseUrl, anonKey, token, imageBase64, docType, userId, attempt, cb){
    console.log('[DocScanner] OCR attempt '+(attempt+1)+'/'+
      (MAX_RETRIES+1)+' type='+docType+' base64len='+imageBase64.length);

    fetch(baseUrl + '/functions/v1/scan-document', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token,
        'apikey': anonKey
      },
      body: JSON.stringify({
        image_base64: imageBase64,
        document_type: docType,
        user_id: userId
      })
    })
    .then(function(resp){
      // On 401, force anon key on next retry (user JWT is clearly invalid)
      if(resp.status === 401 && attempt < MAX_RETRIES){
        console.warn('[DocScanner] 401 JWT rejected, retrying with anon key...');
        setTimeout(function(){
          _sendWithRetry(baseUrl, anonKey, anonKey, imageBase64, docType, null, attempt+1, cb);
        }, 500);
        return null;
      }
      if(!resp.ok && attempt < MAX_RETRIES){
        console.warn('[DocScanner] OCR HTTP '+resp.status+', retrying...');
        setTimeout(function(){
          _sendWithRetry(baseUrl, anonKey, token, imageBase64, docType, userId, attempt+1, cb);
        }, 1000 * (attempt+1));
        return null;
      }
      if(!resp.ok){
        return resp.text().then(function(txt){
          throw new Error('HTTP '+resp.status+': '+txt.substring(0,200));
        });
      }
      return resp.json();
    })
    .then(function(result){
      if(!result) return; // retry in progress
      if(result.success && result.data){
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
          _sendWithRetry(baseUrl, anonKey, token, imageBase64, docType, userId, attempt+1, cb);
        }, 1000 * (attempt+1));
      } else {
        console.error('[DocScanner] Mindee failed after all retries:', result.error);
        cb(new Error(result.error || 'OCR failed'), '');
      }
    })
    .catch(function(err){
      if(attempt < MAX_RETRIES){
        console.warn('[DocScanner] OCR error, retrying:', err.message);
        setTimeout(function(){
          _sendWithRetry(baseUrl, anonKey, token, imageBase64, docType, userId, attempt+1, cb);
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
