// ===== SCANNER-UI.JS – Scanner screen UI controller (v5.0.0) =====
// Handles scan flow: id_front → id_back → dl_front → dl_back → verify → register

var ScannerUI = (function(){
  'use strict';
  var _stepIdx = 0;
  var _processing = false;
  var _autoCapturing = false;
  var _afterScanTarget = 's-register';
  var _d = (typeof CamDebug!=='undefined') ? CamDebug.log.bind(CamDebug) : function(){};

  function _hideBanner(){
    var b = document.getElementById('header-banner');
    if(b) b.style.display = 'none';
    document.documentElement.classList.remove('has-banner');
  }
  function _restoreBanner(){
    // Re-fetch banner config — if banner is enabled it will re-appear
    if(typeof apiFetchHeaderBanner === 'function') apiFetchHeaderBanner();
  }

  function open(target, idType){
    _stepIdx = 0;
    _processing = false;
    _afterScanTarget = target || 's-register';
    _hideBanner();
    DocScanner.reset();
    goTo('s-doc-scan');
    if(idType){
      DocScanner.setIdType(idType);
      setTimeout(function(){ _renderStep(); },100);
    } else {
      setTimeout(function(){ _showIdChoice(); },100);
    }
  }

  function _showIdChoice(){
    var wrap = document.querySelector('#s-doc-scan .scan-camera-wrap');
    if(!wrap){ _renderStep(); return; }
    var ov = document.createElement('div');
    ov.id = 'scan-id-choice';
    ov.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;z-index:10;background:var(--dark);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:24px;';
    ov.innerHTML = '<div style="font-size:16px;font-weight:800;color:#fff;margin-bottom:8px;">Vyberte doklad totožnosti</div>' +
      '<button onclick="scanChooseId(\'op\')" style="width:100%;max-width:260px;background:#fff;border:none;border-radius:14px;padding:18px;font-family:var(--font);font-size:15px;font-weight:700;cursor:pointer;display:flex;align-items:center;gap:12px;"><span style="font-size:28px;">🪪</span> Občanský průkaz</button>' +
      '<button onclick="scanChooseId(\'passport\')" style="width:100%;max-width:260px;background:#fff;border:none;border-radius:14px;padding:18px;font-family:var(--font);font-size:15px;font-weight:700;cursor:pointer;display:flex;align-items:center;gap:12px;"><span style="font-size:28px;">📕</span> Cestovní pas</button>';
    wrap.appendChild(ov);
  }

  function chooseId(type){
    DocScanner.setIdType(type);
    var ov = document.getElementById('scan-id-choice');
    if(ov) ov.remove();
    _renderStep();
  }

  function _renderStep(){
    var seq = DocScanner.getSequence();
    var type = seq[_stepIdx];
    DocScanner.setDocType(type);
    var lbl = document.getElementById('scan-doc-label');
    if(lbl) lbl.textContent = DocScanner.DOC_LABELS[type];
    var icon = document.getElementById('scan-doc-icon');
    if(icon) icon.textContent = DocScanner.DOC_ICONS[type];
    var prog = document.getElementById('scan-progress');
    if(prog) prog.textContent = (_stepIdx+1)+' / '+seq.length;
    for(var i=0;i<4;i++){
      var dot = document.getElementById('scan-dot-'+i);
      if(dot){
        dot.style.display = i<seq.length ? '' : 'none';
        dot.className = 'scan-prog-dot' +
          (i<_stepIdx?' done':'') +
          (i===_stepIdx?' cur':'');
      }
    }
    var hint = document.getElementById('scan-hint');
    if(hint){
      var sc=_t('scan');
      var hints = {
        id_front:sc.placeInFrame||'Umístěte přední stranu OP do rámečku',
        id_back:sc.placeInFrame||'Otočte OP a zachyťte zadní stranu',
        passport_front:sc.placeInFrame||'Umístěte datovou stranu pasu do rámečku',
        dl_front:sc.placeInFrame||'Umístěte přední stranu ŘP do rámečku',
        dl_back:sc.placeInFrame||'Otočte ŘP a zachyťte zadní stranu'
      };
      hint.textContent = hints[type]||'';
    }
    _setStatus('ready',_t('scan').aimDocument||'Zaměřte doklad do rámečku');
    var video = document.getElementById('scan-video');
    var overlay = document.getElementById('scan-overlay');
    if(video){
      try {
        var camPromise = DocScanner.startCamera(video, overlay);
        if(camPromise && typeof camPromise.then === 'function'){
          camPromise.then(function(){
            _setStatus('ready','Zaměřte doklad do rámečku a stiskněte tlačítko');
          }).catch(function(e){ _handleCameraError(e); });
        }
      } catch(e){ _handleCameraError(e); }
    } else {
      _setStatus('error', _t('common').error||'Nepodařilo se spustit kameru');
    }
    DocScanner.initWorker();
  }

  function _handleCameraError(e){
    var name = (e && e.name) || '';
    var msg = (e && e.message) || String(e);
    var code = name + ': ' + msg;
    _d('UI','_handleCameraError: ' + code);
    var hint = 'Nepodařilo se spustit kameru';

    if(name==='NotFoundError' || msg.indexOf('NotFound')!==-1 || msg.indexOf('not found')!==-1){
      hint = 'Fotoaparát nenalezen na tomto zařízení';
    } else if(name==='NotAllowedError' || msg.indexOf('NotAllowed')!==-1 || msg.indexOf('denied')!==-1 || msg.indexOf('Permission')!==-1){
      hint = 'Přístup k fotoaparátu zamítnut – povolte v nastavení';
    } else if(name==='NotReadableError' || msg.indexOf('NotReadable')!==-1 || msg.indexOf('Could not start')!==-1){
      hint = 'Kamera je používaná jinou aplikací nebo není čitelná';
    } else if(name==='OverconstrainedError' || msg.indexOf('Overconstrained')!==-1){
      hint = 'Kamera nepodporuje požadované rozlišení';
    } else if(name==='AbortError' || msg.indexOf('Abort')!==-1){
      hint = 'Spuštění kamery bylo přerušeno';
    } else if(name==='TypeError' || msg.indexOf('TypeError')!==-1){
      hint = 'Neplatné nastavení kamery (TypeError)';
    } else if(name==='NotSupportedError' || msg.indexOf('NotSupported')!==-1){
      hint = 'Kamera není podporována v tomto prostředí';
    } else if(msg.indexOf('secure')!==-1 || msg.indexOf('https')!==-1 || msg.indexOf('HTTPS')!==-1){
      hint = 'Kamera vyžaduje zabezpečené připojení (HTTPS)';
    } else if(msg.indexOf('all 3 attempts')!==-1 || msg.indexOf('Timeout')!==-1 || msg.indexOf('timeout')!==-1){
      hint = 'Kamera není dostupná. Zkontrolujte oprávnění v Nastavení → Aplikace → MotoGo24 → Oprávnění → Fotoaparát';
    }
    _setStatus('error', hint);
    _showCameraFallback(hint);
  }

  function _showCameraFallback(hint){
    var wrap = document.querySelector('#s-doc-scan .scan-camera-wrap');
    if(!wrap) return;
    var existing = document.getElementById('scan-cam-fallback');
    if(existing) existing.remove();
    var fb = document.createElement('div');
    fb.id = 'scan-cam-fallback';
    fb.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;z-index:20;' +
      'background:var(--dark);display:flex;flex-direction:column;align-items:center;' +
      'justify-content:center;gap:16px;padding:24px;text-align:center;';
    fb.innerHTML = '<div style="font-size:48px;">📷</div>' +
      '<div style="font-size:15px;font-weight:700;color:#fff;">'+hint+'</div>' +
      '<div style="font-size:13px;color:var(--g400);line-height:1.5;">' +
        'Doklady můžete naskenovat později v profilu.</div>' +
      '<button onclick="scanFallbackContinue()" style="width:100%;max-width:260px;' +
        'background:var(--green);color:#fff;border:none;border-radius:14px;padding:16px;' +
        'font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;">' +
        'Pokračovat bez skenování</button>' +
      '<button onclick="scanFallbackRetry()" style="width:100%;max-width:260px;' +
        'background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.2);' +
        'border-radius:14px;padding:14px;font-family:var(--font);font-size:13px;' +
        'font-weight:600;cursor:pointer;">Zkusit znovu</button>';
    wrap.appendChild(fb);
  }

  function _setStatus(type, text){
    var el = document.getElementById('scan-status');
    if(!el) return;
    el.textContent = text;
    el.className = 'scan-status scan-status-'+type;
  }

  function _frameOk(on){
    var f = document.querySelector('.scan-frame');
    if(f){ if(on) f.classList.add('scan-frame-ok'); else f.classList.remove('scan-frame-ok'); }
  }

  // Uloží fotku lokálně + nahraje do Supabase storage
  function _savePhotoLocally(canvas){
    try {
      var docType = DocScanner.getDocType();
      var dataUri = canvas.toDataURL('image/jpeg',0.85);

      // Upload do Supabase storage (async, non-blocking)
      // Base64 se NEUKLÁDÁ do localStorage — šetříme místo na zařízení
      if(typeof apiUploadDocPhoto === 'function'){
        apiUploadDocPhoto(dataUri, docType).then(function(res){
          if(res.error) console.warn('[DocScanner] Cloud upload failed:', res.error);
          else console.log('[DocScanner] Photo uploaded to cloud:', res.filePath);
        }).catch(function(e){ console.warn('[DocScanner] Cloud upload error:', e); });
      }

      // 3) Uložit do galerie přes Cordova file API
      if(window.cordova && window.resolveLocalFileSystemURL){
        var picDir = cordova.file.externalRootDirectory;
        if(!picDir) picDir = cordova.file.externalDataDirectory;
        if(!picDir) return;
        window.resolveLocalFileSystemURL(picDir, function(root){
          root.getDirectory('Pictures', {create:true}, function(picsDir){
            picsDir.getDirectory('MotoGo24', {create:true}, function(mgDir){
              var b64 = dataUri.split(',')[1];
              var byteChars = atob(b64);
              var byteArr = new Uint8Array(byteChars.length);
              for(var j=0;j<byteChars.length;j++) byteArr[j]=byteChars.charCodeAt(j);
              var blob = new Blob([byteArr],{type:'image/jpeg'});
              var fname = 'scan_'+docType+'_'+Date.now()+'.jpg';
              mgDir.getFile(fname,{create:true},function(fileEntry){
                fileEntry.createWriter(function(writer){
                  writer.write(blob);
                  if(window.plugins && window.plugins.mediascanner){
                    window.plugins.mediascanner.scan(fileEntry.nativeURL);
                  }
                });
              });
            });
          });
        });
      }
    } catch(e){ console.warn('[DocScanner] Photo save failed:', e); }
  }

  // Capture: vyfotí → uloží lokálně → pošle na Mindee → pokračuje
  function capture(){
    if(_processing) return;
    _processing = true;
    _setStatus('processing','Fotografuji...');

    var frame = DocScanner.captureFrame();
    if(!frame){
      _processing = false;
      _setStatus('error','Nepodařilo se zachytit snímek');
      return;
    }

    // Zelený rámeček = fotka pořízena
    _frameOk(true);
    showT('📸','Fotka pořízena','Odesílám na rozpoznání textu...');
    _setStatus('processing','Připojuji k Mindee OCR...');

    // Uložit fotku lokálně VŽDY (nezávisle na Mindee výsledku)
    _savePhotoLocally(frame);

    // Odeslat na Mindee – žádná lokální quality gate, API rozhodne
    DocScanner.runOCR(frame, function(err, text){
      _processing = false;

      // Zkontroluj strukturovaná data z Mindee
      var hasStructured = DocScanner._lastMindeeData &&
        Object.keys(DocScanner._lastMindeeData).some(function(k){
          return !!DocScanner._lastMindeeData[k];
        });

      var type = DocScanner.getDocType();

      if(err && !hasStructured){
        // Mindee selhalo – fotka je uložena, pokračuj dál
        console.warn('[DocScanner] Mindee chyba: '+err.message+' (fotka uložena do cloudu i lokálně)');
        _frameOk(false);
        _setStatus('warn','Rozpoznání selhalo – fotka uložena');
        showT('⚠️','Rozpoznání textu selhalo',
          'Fotka uložena do cloudu. Zkuste to znovu nebo vyplňte ručně.\n\n['+err.message+']');

        DocScanner.setResult(type, 'photo-only');
        _advanceStep(1500);
        return;
      }

      // Mindee vrátil data – zobraz co rozpoznal
      if(!text && hasStructured) text = 'mindee-structured-data';
      DocScanner.setResult(type, text);

      // Spočítej kolik polí Mindee vrátil
      var fieldCount = 0;
      var fieldNames = [];
      if(DocScanner._allMindeeData && DocScanner._allMindeeData[type]){
        var md = DocScanner._allMindeeData[type];
        ['firstName','lastName','dob','idNumber','address',
         'licenseCategory','licenseNumber','issuedDate','expiryDate'].forEach(function(f){
          if(md[f]){fieldCount++;fieldNames.push(f);}
        });
      }

      _setStatus('success','Rozpoznáno '+fieldCount+' údajů ✓');
      showT('✓','Mindee rozpoznal '+fieldCount+' údajů',
        DocScanner.DOC_LABELS[type]);

      _advanceStep(1000);
    });
  }

  function _advanceStep(delay){
    setTimeout(function(){
      _frameOk(false);
      var prev = document.getElementById('scan-preview');
      if(prev) prev.style.display = 'none';
      _stepIdx++;
      if(_stepIdx < DocScanner.getSequence().length) _renderStep();
      else _finishScan();
    }, delay);
  }

  function skip(){
    _stepIdx++;
    if(_stepIdx < DocScanner.getSequence().length){
      _renderStep();
    } else {
      _finishScan();
    }
  }

  function _finishScan(){
    DocScanner.stopCamera();
    _restoreBanner();
    var merged = DocScanner.mergeResults();
    var hasData = Object.keys(merged).length > 0;
    var fieldList = Object.keys(merged).filter(function(k){return k.charAt(0)!=='_';});

    if(hasData){
      // Save OCR data to profile, then run verification
      var saveData = Object.assign({}, merged);
      var zipProm = merged._zipPromise || Promise.resolve('');
      zipProm.then(function(zip){
        if(zip && !saveData.zip) saveData.zip = zip;
        if(typeof apiSaveOcrToProfile === 'function') return apiSaveOcrToProfile(saveData);
        return {error:null, updated:0};
      }).then(function(res){
        if(res && res.updated) console.log('[DocScanner] Auto-saved '+res.updated+' fields');
        // Run verification against profile
        if(typeof apiVerifyDocs === 'function') return apiVerifyDocs(saveData);
        return null;
      }).then(function(vResult){
        if(!vResult || !vResult.success) {
          console.warn('[DocScanner] Verification failed:', vResult);
          return;
        }
        if(vResult.status === 'verified'){
          localStorage.setItem('mg_docs_verified','1');
          // Persist verification to DB (survives logout)
          if(typeof apiSaveDocVerification === 'function'){
            var scannedTypes = Object.keys(DocScanner._allMindeeData || {});
            apiSaveDocVerification(saveData, scannedTypes).catch(function(){});
          }
          _showScannerVerificationResult(true, [], vResult.warnings || []);
        } else {
          localStorage.removeItem('mg_docs_verified');
          _showScannerVerificationResult(false, vResult.mismatches || [], vResult.warnings || []);
        }
      }).catch(function(e){ console.warn('[DocScanner] Verify error:', e); });

      showT('✓',_t('scan').docsUploaded||'Doklady naskenované',
        'Rozpoznáno '+fieldList.length+' údajů – ověřuji...');
    } else {
      showT('📸','Fotky uloženy','Mindee nerozpoznal data – vyplňte ručně');
    }

    goTo(_afterScanTarget);
    setTimeout(function(){
      if(_afterScanTarget==='s-register'){
        DocScanner.fillRegistration(merged);
      } else if(_afterScanTarget==='s-profile' || _afterScanTarget==='s-docs'){
        if(typeof DocScanner.fillProfile==='function') DocScanner.fillProfile(merged);
        DocScanner.fillRegistration(merged);
      }
      if(_afterScanTarget==='s-docs' && typeof renderDocs==='function') renderDocs();
      if((_afterScanTarget==='s-profile' || _afterScanTarget==='s-docs') && typeof renderProfile==='function'){
        setTimeout(function(){ renderProfile(); }, 1500);
      }
    }, 200);

    try {
      localStorage.setItem('mg_scan_token',JSON.stringify({
        scanned:new Date().toISOString(),
        types:Object.keys(DocScanner._allMindeeData||{}),
        device:'mindee-cloud',dataStored:'supabase+local',gdpr:'EU-compliant'
      }));
    } catch(e){}
  }

  // _showVerificationResult and _esc extracted to scanner-ui-helpers.js (global scope)

  function close(){
    DocScanner.stopCamera();
    _restoreBanner();
    histBack();
  }

  function getTarget(){ return _afterScanTarget; }

  return {
    open: open,
    capture: capture,
    skip: skip,
    close: close,
    chooseId: chooseId,
    getTarget: getTarget
  };
})();

// Global shortcut for onclick handlers
function openDocScanner(target){ ScannerUI.open(target); }
function scanChooseId(type){ ScannerUI.chooseId(type); }
function scanCapture(){ ScannerUI.capture(); }
function scanSkip(){ ScannerUI.skip(); }
function scanClose(){ ScannerUI.close(); }
function scanFallbackContinue(){ ScannerUI.close(); }
function scanFallbackRetry(){
  var fb = document.getElementById('scan-cam-fallback');
  if(fb) fb.remove();
  ScannerUI.open(ScannerUI.getTarget()||'s-register');
}
function closeVerifyOverlay(){
  var ov = document.getElementById('doc-verify-overlay');
  if(ov) ov.remove();
}
