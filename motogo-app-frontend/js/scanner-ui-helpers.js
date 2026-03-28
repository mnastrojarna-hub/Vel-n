// ===== SCANNER-UI-HELPERS.JS – Extracted from scanner-ui.js IIFE =====
// Global helper functions used by ScannerUI (loaded before scanner-ui.js)

function _scannerEsc(s){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

// Show verification overlay (success or mismatches)
function _showScannerVerificationResult(ok, mismatches, warnings){
  // Remove any existing overlay
  var old = document.getElementById('doc-verify-overlay');
  if(old) old.remove();

  var ov = document.createElement('div');
  ov.id = 'doc-verify-overlay';
  ov.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;' +
    'background:rgba(0,0,0,.85);display:flex;align-items:center;justify-content:center;padding:20px;';

  if(ok && (!warnings || warnings.length === 0)){
    // All good — verified
    ov.innerHTML = '<div style="background:#fff;border-radius:20px;padding:32px 24px;' +
      'max-width:340px;width:100%;text-align:center;">' +
      '<div style="font-size:56px;margin-bottom:12px;">&#9989;</div>' +
      '<div style="font-size:18px;font-weight:800;color:#166534;margin-bottom:8px;">' +
      'Doklady ověřeny</div>' +
      '<div style="font-size:13px;color:#4a6357;margin-bottom:20px;line-height:1.5;">' +
      'Občanský průkaz a řidičský průkaz souhlasí s profilem. ' +
      'Přístupové kódy budou odeslány do zpráv.</div>' +
      '<button onclick="closeVerifyOverlay()" style="width:100%;background:var(--green,#22c55e);' +
      'color:#fff;border:none;border-radius:12px;padding:14px;font-size:15px;font-weight:700;' +
      'font-family:var(--font);cursor:pointer;">Rozumím</button></div>';
  } else {
    // Mismatches or warnings
    var html = '<div style="background:#fff;border-radius:20px;padding:28px 20px;' +
      'max-width:360px;width:100%;max-height:80vh;overflow-y:auto;">' +
      '<div style="text-align:center;margin-bottom:16px;">' +
      '<div style="font-size:48px;margin-bottom:8px;">&#9888;&#65039;</div>' +
      '<div style="font-size:17px;font-weight:800;color:#b45309;">Nalezeny rozpory</div>' +
      '<div style="font-size:12px;color:#92400e;margin-top:4px;">Zkontrolujte a opravte údaje v profilu</div></div>';

    if(mismatches && mismatches.length > 0){
      html += '<div style="margin-bottom:16px;">';
      for(var i=0;i<mismatches.length;i++){
        var mm = mismatches[i];
        html += '<div style="background:#fef3c7;border:1px solid #f59e0b;border-radius:10px;' +
          'padding:12px;margin-bottom:8px;">' +
          '<div style="font-size:11px;font-weight:700;color:#92400e;text-transform:uppercase;' +
          'letter-spacing:.5px;margin-bottom:6px;">'+_scannerEsc(mm.label||mm.field)+'</div>' +
          '<div style="display:flex;gap:8px;font-size:12px;">' +
          '<div style="flex:1;background:#fff;border-radius:6px;padding:6px 8px;">' +
          '<div style="font-size:9px;color:#6b7280;margin-bottom:2px;">Z dokladu</div>' +
          '<div style="font-weight:700;color:#b45309;">'+_scannerEsc(mm.ocr||'–')+'</div></div>' +
          '<div style="flex:1;background:#fff;border-radius:6px;padding:6px 8px;">' +
          '<div style="font-size:9px;color:#6b7280;margin-bottom:2px;">V profilu</div>' +
          '<div style="font-weight:700;color:#1f2937;">'+_scannerEsc(mm.profile||'–')+'</div></div>' +
          '</div></div>';
      }
      html += '</div>';
    }

    if(warnings && warnings.length > 0){
      for(var j=0;j<warnings.length;j++){
        var w = warnings[j];
        html += '<div style="background:#fee2e2;border:1px solid #ef4444;border-radius:10px;' +
          'padding:12px;margin-bottom:8px;font-size:13px;font-weight:600;color:#991b1b;">' +
          _scannerEsc(w.label||w.type)+'</div>';
      }
    }

    html += '<div style="font-size:11px;color:#6b7280;margin-bottom:16px;line-height:1.4;">' +
      'Přístupové kódy nebudou odeslány, dokud nebudou doklady v pořádku. ' +
      'Opravte údaje v profilu a naskenujte doklady znovu.</div>' +
      '<button onclick="closeVerifyOverlay();goTo(\'s-profile\')" style="width:100%;' +
      'background:#f59e0b;color:#fff;border:none;border-radius:12px;padding:14px;' +
      'font-size:14px;font-weight:700;font-family:var(--font);cursor:pointer;margin-bottom:8px;">' +
      'Opravit profil</button>' +
      '<button onclick="closeVerifyOverlay()" style="width:100%;background:transparent;' +
      'color:#6b7280;border:1px solid #d1d5db;border-radius:12px;padding:12px;' +
      'font-size:13px;font-weight:600;font-family:var(--font);cursor:pointer;">Zavřít</button></div>';

    ov.innerHTML = html;
  }

  document.body.appendChild(ov);

  // Refresh profile to show verification badge
  if(ok && typeof renderProfile==='function'){
    setTimeout(function(){ renderProfile(); }, 500);
  }
}
