// ===== MotoGo24 Web — Rezervace: Mindee OCR scan + Stripe payment =====
var MG = window.MG || {};
window.MG = MG;

// ===== PC ↔ MOBIL REALTIME MIRROR =====
// PC v kroku 2 (s QR) poslouchá realtime UPDATEy svého pending booking.
// Až mobilní zařízení dokončí platbu (Stripe → atomic confirm_payment →
// UPDATE bookings.payment_status='paid'), PC se okamžitě přesměruje na
// děkovací stránku — zrcadlí výsledek mobilu.
// Vyžaduje RLS politiku `bookings_anon_pending_realtime` (anon SELECT pro
// web pending+unpaid řádky max 4h staré).
MG._rezSubscribeMobileMirror = function(){
  if(!window.sb || !MG._rez || !MG._rez.bookingId) return;
  if(MG._isMobile && MG._isMobile()) return; // jen desktop
  // Cleanup předchozí kanál (re-render step 2)
  if(MG._rezMirrorChannel){
    try { window.sb.removeChannel(MG._rezMirrorChannel); } catch(e){}
    MG._rezMirrorChannel = null;
  }
  var bookingId = MG._rez.bookingId;
  MG._rezMirrorChannel = window.sb
    .channel('rez-mirror-'+bookingId)
    .on('postgres_changes', {
      event: 'UPDATE', schema: 'public', table: 'bookings',
      filter: 'id=eq.'+bookingId
    }, function(payload){
      var nu = payload && payload.new;
      if(!nu) return;
      // 1) Mobil zaplatil → redirect na děkovací stránku
      if(nu.payment_status === 'paid'){
        try { window.sb.removeChannel(MG._rezMirrorChannel); } catch(e){}
        MG._rezMirrorChannel = null;
        window.location.href = '/potvrzeni?booking_id='+bookingId;
        return;
      }
      // 2) Live indikátor — mobil aktivně mění data rezervace
      MG._rezShowMobileMirrorBanner('Mobilní zařízení dokončuje rezervaci…');
    })
    .subscribe();
};

MG._rezShowMobileMirrorBanner = function(text){
  var el = document.getElementById('rez-mobile-mirror-banner');
  if(!el){
    el = document.createElement('div');
    el.id = 'rez-mobile-mirror-banner';
    el.style.cssText = 'position:fixed;bottom:1.25rem;left:50%;transform:translateX(-50%);background:#1a8c1a;color:#fff;padding:.85rem 1.4rem;border-radius:10px;font-weight:600;box-shadow:0 6px 22px rgba(0,0,0,.3);z-index:9999;font-family:Montserrat,sans-serif;font-size:.95rem;display:flex;align-items:center;gap:.6rem';
    el.innerHTML = '<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#74FB71;animation:mg-pulse 1.4s infinite ease-in-out"></span><span class="mg-mirror-text"></span>';
    var st = document.createElement('style');
    st.textContent = '@keyframes mg-pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(.7)}}';
    document.head.appendChild(st);
    document.body.appendChild(el);
  }
  var t = el.querySelector('.mg-mirror-text');
  if(t) t.textContent = text;
  el.style.display = 'flex';
};

// ===== OCR s 2× retry + vždy uložit foto na Supabase =====
// Mindee občas vrátí prázdný výsledek (rozmazaná fotka, špatné světlo, atd.).
// Retry totéž burst znovu (2× celkem). Když ani druhý pokus neuspěje, fotka
// se stejně nahraje do storage jako manuální — admin ji ve Velínu zkontroluje ručně.
MG._rezOcrBurstRetry = async function(frames, docType, userId, attempts){
  attempts = attempts || 2;
  var last = { ok:false, response:null, frame: (frames&&frames[0])||null };
  for(var a=0; a<attempts; a++){
    try { last = await MG._rezOcrBurst(frames, docType, userId); }
    catch(e){ last = { ok:false, response:{error:String(e)}, frame:(frames&&frames[0])||null }; }
    if(last && last.ok) return last;
    // krátký delay před druhým pokusem (síťová chyba / Mindee hiccup)
    if(a < attempts-1) await new Promise(function(r){ setTimeout(r, 600); });
  }
  return last;
};

// Nahraje fotku dokladu do storage + vytvoří záznam v documents přes edge fn
// `save-verification-document` (běží pod service_role → obejde RLS, nezávisí na
// auth session zákazníka). metadata.mindee_status = 'ok' | 'failed' (vidí ve
// Velínu, jestli stačí kontrola extrahovaných polí, nebo musí prohlédnout fotku
// ručně). Když edge fn z jakéhokoli důvodu selže, fallback na přímý SDK upload.
MG._rezSaveDocPhoto = async function(base64, docType, mindeeStatus, ocrFields, side){
  if(!MG._rez || !MG._rez.userId || !base64) return false;
  // side: 'front' | 'back' | null (pas)
  var docSide = (side === 'front' || side === 'back') ? side : null;
  var sideLabel = docSide === 'front' ? ' — líc' : (docSide === 'back' ? ' — rub' : '');
  // Edge fn pod service_role — robustní proti chybějící customer session i RLS
  try {
    var res = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/save-verification-document', {
      method: 'POST',
      headers: { 'Content-Type':'application/json', 'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY },
      body: JSON.stringify({
        user_id: MG._rez.userId,
        booking_id: MG._rez.bookingId || null,
        doc_type: docType,                    // 'id' | 'dl' | 'passport'
        image_base64: base64,
        mindee_status: mindeeStatus,          // 'ok' | 'failed'
        ocr_fields: ocrFields || null,
        mime: 'image/jpeg',
        doc_side: docSide                     // 2026-05-08: 'front' | 'back' | null (pas)
      })
    });
    var data = await res.json().catch(function(){ return null; });
    if(res.ok && data && data.success) return true;
    console.warn('[REZ] save-verification-document non-ok response, fallback to direct upload', data);
  } catch(e){
    console.warn('[REZ] save-verification-document fetch failed, fallback to direct upload', e);
  }
  // Fallback — přímý SDK upload (vyžaduje customer session + storage RLS)
  var docTypeStr = docType==='id' ? 'id_card' : (docType==='passport' ? 'passport' : 'drivers_license');
  var labelOk = docType==='id' ? 'Doklad totožnosti'+sideLabel+' (web sken)' : (docType==='passport' ? 'Cestovní pas (web sken)' : 'Řidičský průkaz'+sideLabel+' (web sken)');
  var labelManual = docType==='id' ? 'Doklad totožnosti'+sideLabel+' (web — manuální)' : (docType==='passport' ? 'Cestovní pas (web — manuální)' : 'Řidičský průkaz'+sideLabel+' (web — manuální)');
  var sideSuffix = docSide ? '_'+docSide : '';
  var fileName = MG._rez.userId+'/'+docTypeStr+sideSuffix+'_'+Date.now()+'.jpg';
  try {
    var blob = MG._rezB64toBlob(base64,'image/jpeg');
    await window.sb.storage.from('documents').upload(fileName, blob).catch(function(e){ console.warn('[REZ] storage upload error', e); });
  } catch(e){ console.warn('[REZ] blob/upload exception', e); }
  try {
    var row = {
      user_id: MG._rez.userId,
      booking_id: MG._rez.bookingId || null,
      type: docTypeStr,
      file_path: fileName,
      file_name: fileName.split('/').pop(),
      name: mindeeStatus==='ok' ? labelOk : labelManual,
      metadata: {
        source: 'web',
        mindee_status: mindeeStatus,
        ocr_fields: ocrFields || null,
        captured_at: new Date().toISOString(),
        side: docSide
      }
    };
    var ins = await window.sb.from('documents').insert(row);
    if(ins && ins.error && /metadata/i.test(ins.error.message||'')){
      delete row.metadata;
      await window.sb.from('documents').insert(row).catch(function(){});
    }
  } catch(e){ console.warn('[REZ] documents insert exception', e); }
  return true;
};

// ===== PERSIST DOC FIELDS DO PROFILU =====
// Brand-new web zákazník není po create_web_booking RPC přihlášen client-side,
// proto profile.update() padá na RLS (povolen jen own row, id=auth.uid()).
// Tato funkce zaručí, že údaje skutečně dorazí do Supabase:
//  1) nastaví heslo přes set_web_booking_password (SECURITY DEFINER)
//  2) signInWithPassword() — vytvoří klientskou session
//  3) update profiles (id_number / license_number / license_group / license_expiry)
//  4) verify read-back — když selže, logujeme do konzole.
MG._rezPersistDocs = async function(idNumber, licenseNumber, licenseGroup, licenseExpiry){
  if(!MG._rez.userId){ console.warn('[REZ] persistDocs: no userId'); return false; }

  // 1) Heslo — jen jednou
  if(MG._rez._password && MG._rez.bookingId && !MG._rez._passwordSet){
    try {
      var pwRes = await window.sb.rpc('set_web_booking_password', {
        p_booking_id: MG._rez.bookingId, p_password: MG._rez._password
      });
      if(pwRes && pwRes.error){ console.error('[REZ] set_web_booking_password error:', pwRes.error); }
      MG._rez._passwordSet = true;
    } catch(e){ console.error('[REZ] set_web_booking_password exception:', e); }
  }

  // 2) Sign-in (idempotentní)
  var signedIn = false;
  try {
    var sess = await window.sb.auth.getSession();
    signedIn = !!(sess && sess.data && sess.data.session && sess.data.session.user);
  } catch(e){}
  if(!signedIn && MG._rez._password && MG._rez.formData && MG._rez.formData.email){
    try {
      var siRes = await window.sb.auth.signInWithPassword({
        email: MG._rez.formData.email.trim().toLowerCase(),
        password: MG._rez._password
      });
      if(siRes && siRes.error){ console.warn('[REZ] auto sign-in error:', siRes.error.message); }
      else { signedIn = true; }
    } catch(e){ console.warn('[REZ] auto sign-in exception:', e); }
  }
  delete MG._rez._password;

  // 3) Update profilu
  var payload = {
    id_number: idNumber || null,
    license_number: licenseNumber || null,
    license_group: licenseGroup ? [licenseGroup] : null,
    license_expiry: licenseExpiry || null
  };
  try {
    var ur = await window.sb.from('profiles').update(payload).eq('id', MG._rez.userId);
    if(ur && ur.error){ console.error('[REZ] profile update error:', ur.error); }
  } catch(e){ console.error('[REZ] profile update exception:', e); }

  // 4) Verify
  try {
    var rd = await window.sb.from('profiles')
      .select('license_group,license_expiry,id_number,license_number')
      .eq('id', MG._rez.userId).maybeSingle();
    if(rd && rd.data){
      var ok = (rd.data.license_group && rd.data.license_group.length) ||
        rd.data.id_number || rd.data.license_number || rd.data.license_expiry;
      if(!ok){ console.warn('[REZ] profile verify: empty after update — pravděpodobně RLS (sign-in selhal)'); }
    } else if(rd && rd.error){
      console.warn('[REZ] profile verify error:', rd.error);
    }
  } catch(e){}
  return true;
};

// ===== MINDEE STEP (mobile: mandatory, desktop: optional) =====
MG._rezShowMindeeStep = async function(){
  // If docs not yet validated (coming from step 2 form), validate first
  if(!MG._rez._docsValidated){
    var docNum=document.getElementById('rez-doc-number');
    var licNum=document.getElementById('rez-license-number');
    var licGroup=document.getElementById('rez-license-group');
    var licExpiry=document.getElementById('rez-license-expiry');
    var licConf=document.getElementById('rez-license-confirm');
    if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
    if(!licGroup||!licGroup.value){alert('Vyberte skupinu řidičského oprávnění (A2, A nebo Bez ŘP).');return;}
    var _isNoLic = (licGroup.value === 'N');
    if(!_isNoLic){
      if(!licNum||!licNum.value||licNum.value.trim().length<4){alert('Číslo řidičského průkazu musí mít alespoň 4 znaky.');return;}
      if(!licExpiry||!licExpiry.value){alert('Vyplňte platnost řidičského průkazu.');return;}
      if(!MG._isLicenseExpiryValid(licExpiry.value)){alert('Řidičský průkaz musí být platný min. 14 dní od dnes.');return;}
      if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}
    }

    // Validace hesla (pokud nebylo nastaveno dříve)
    if(!MG._rez._passwordSet){
      var pwd=document.getElementById('rez-password');
      var pwdC=document.getElementById('rez-password-confirm');
      if(!pwd||!pwd.value||pwd.value.length<8){alert('Heslo musí mít alespoň 8 znaků.');return;}
      if(!pwdC||pwd.value!==pwdC.value){alert('Hesla se neshodují.');return;}
      MG._rez._password=pwd.value;
    }

    MG._rez._docNumber=docNum.value;
    MG._rez._licenseNumber=_isNoLic?null:licNum.value;
    // Zapamatuj výběr OP / pas — určuje, kolik stran musí zákazník naskenovat
    var docTypeRadio = document.querySelector('input[name="rez-doc-type"]:checked');
    MG._rez._idDocType = (docTypeRadio && docTypeRadio.value === 'pas') ? 'pas' : 'op';
    if(MG._rez.formData){
      MG._rez.formData._licGroup=licGroup.value;
      MG._rez.formData._licExpiry=_isNoLic?null:(licExpiry?licExpiry.value:null);
    }
    MG._rez._docsValidated=true;

    // Save license/doklad to profile — pořadí důležité:
    // 1) Nastav heslo (RPC SECURITY DEFINER)
    // 2) Sign-in zákazníka (jinak RLS blokuje update profilu)
    // 3) Update profilu — license_group/expiry/id_number/license_number
    await MG._rezPersistDocs(docNum.value, _isNoLic?null:licNum.value,
      licGroup.value, _isNoLic?null:(licExpiry?licExpiry.value:null));
  }

  // Reset scan flags (per-strana)
  MG._rez._idFrontScanned=false;
  MG._rez._idBackScanned=false;
  MG._rez._passportScanned=false;
  MG._rez._dlFrontScanned=false;
  MG._rez._dlBackScanned=false;
  // Backwards-compat — některé starší cesty stále kontrolují souhrnný flag
  MG._rez._idScanned=false;
  MG._rez._dlScanned=false;

  var isMob=MG._isMobile();
  var idDocType = MG._rez._idDocType || 'op'; // 'op' (líc+rub) nebo 'pas' (1×)
  var isPassport = idDocType === 'pas';

  // Show Mindee scanning UI
  var form=document.getElementById('rez-form');if(!form)return;
  var total=MG._rez.bookingAmount||0;

  // Doporučené, ale lze přeskočit (na desktopu i mobilu)
  var subtitle=isMob
    ?'Doporučujeme vyfotit oba doklady — odbavení je rychlejší a získáte přístup k autonomní pobočce. Tento krok lze přeskočit.'
    :'Vyfotografujte doklady pro rychlejší odbavení a možnost využít autonomní pobočku. Tento krok můžete přeskočit.';

  form.innerHTML=
    '<section class="rez-section">'+
      '<div class="rez-section-head"><span class="rez-step-num">&#128247;</span><h2>Ověření dokladů fotoaparátem</h2></div>'+
      '<p class="rez-section-sub">'+subtitle+'</p>'+

      // ── Doklad totožnosti — OP (líc + rub) nebo pas (1×) ──
      '<div class="rez-scan-card">'+
        '<div class="rez-scan-card-head">'+
          '<span class="rez-scan-ico">&#128196;</span>'+
          '<div><div class="rez-scan-title">'+(isPassport?'Cestovní pas':'Občanský průkaz')+' <span class="rez-scan-tag">doporučeno</span></div>'+
          '<div class="rez-scan-sub">'+(isPassport?'Strana s fotografií':'Vyfoťte líc i rub průkazu')+'</div></div>'+
        '</div>'+
        (isPassport
          ? // Pas — jedna fotka
            '<div id="mindee-id-front-status"></div>'+
            '<div class="rez-doc-upload-actions" style="margin-top:.5rem">'+
              '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'id\',null)">&#128247; Vyfotit</button>'+
              '<button class="btn btngreen-small" onclick="MG._rezGalleryDoc(\'id\',\'mindee\',null)">&#128194; Nahrát ze zařízení</button>'+
            '</div>'
          : // OP — líc + rub
            '<div class="rez-doc-side-row" style="margin-top:.5rem"><strong>1. Líc</strong>'+
              '<div id="mindee-id-front-status"></div>'+
              '<div class="rez-doc-upload-actions">'+
                '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'id\',\'front\')">&#128247; Vyfotit líc</button>'+
                '<button class="btn btngreen-small" onclick="MG._rezGalleryDoc(\'id\',\'mindee\',\'front\')">&#128194; Nahrát líc</button>'+
              '</div>'+
            '</div>'+
            '<div class="rez-doc-side-row" style="margin-top:.85rem"><strong>2. Rub</strong>'+
              '<div id="mindee-id-back-status"></div>'+
              '<div class="rez-doc-upload-actions">'+
                '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'id\',\'back\')">&#128247; Vyfotit rub</button>'+
                '<button class="btn btngreen-small" onclick="MG._rezGalleryDoc(\'id\',\'mindee\',\'back\')">&#128194; Nahrát rub</button>'+
              '</div>'+
            '</div>'
        )+
      '</div>'+

      // ── Řidičský průkaz — vždy líc + rub ──
      '<div class="rez-scan-card">'+
        '<div class="rez-scan-card-head">'+
          '<span class="rez-scan-ico">&#128663;</span>'+
          '<div><div class="rez-scan-title">Řidičský průkaz <span class="rez-scan-tag">doporučeno</span></div>'+
          '<div class="rez-scan-sub">Vyfoťte líc i rub průkazu</div></div>'+
        '</div>'+
        '<div class="rez-doc-side-row" style="margin-top:.5rem"><strong>1. Líc</strong>'+
          '<div id="mindee-dl-front-status"></div>'+
          '<div class="rez-doc-upload-actions">'+
            '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'dl\',\'front\')">&#128247; Vyfotit líc</button>'+
            '<button class="btn btngreen-small" onclick="MG._rezGalleryDoc(\'dl\',\'mindee\',\'front\')">&#128194; Nahrát líc</button>'+
          '</div>'+
        '</div>'+
        '<div class="rez-doc-side-row" style="margin-top:.85rem"><strong>2. Rub</strong>'+
          '<div id="mindee-dl-back-status"></div>'+
          '<div class="rez-doc-upload-actions">'+
            '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'dl\',\'back\')">&#128247; Vyfotit rub</button>'+
            '<button class="btn btngreen-small" onclick="MG._rezGalleryDoc(\'dl\',\'mindee\',\'back\')">&#128194; Nahrát rub</button>'+
          '</div>'+
        '</div>'+
      '</div>'+

      '<p id="mindee-mandatory-msg" class="rez-scan-hint">Doklady jsou volitelné — pokud nechcete fotit, klikněte níže na <strong>Přeskočit a zaplatit</strong>.</p>'+
    '</section>'+

    '<div class="rez-step2-actions">'+
      '<button class="btn btndark" onclick="MG._rezShowStep2()">&#8592; Zpět</button>'+
      '<div class="rez-step2-pay">'+
        '<div class="rez-step2-amount">'+MG.formatPrice(total)+'</div>'+
        '<button id="mindee-pay-btn" class="btn btngreen" onclick="MG._rezSubmitPayment()">Přeskočit a zaplatit</button>'+
      '</div>'+
    '</div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== Helpers — IDs status elementů a flagů per (docType, side) =====
MG._rezSideStatusId = function(prefix, docType, side){
  // 'mindee-id-front-status' | 'mindee-dl-back-status' | (pas) 'mindee-id-front-status'
  var key = (docType==='id'?'id':'dl') + '-' + (side==='back'?'back':'front');
  return prefix + key + '-status';
};
MG._rezMarkSideScanned = function(docType, side){
  if(docType==='id'){
    if(side==='back') MG._rez._idBackScanned = true;
    else if(side==='front') MG._rez._idFrontScanned = true;
    else MG._rez._passportScanned = true; // pas — bez strany
    MG._rez._idScanned = !!(MG._rez._passportScanned || (MG._rez._idFrontScanned && MG._rez._idBackScanned));
  } else if(docType==='dl'){
    if(side==='back') MG._rez._dlBackScanned = true;
    else MG._rez._dlFrontScanned = true;
    MG._rez._dlScanned = !!(MG._rez._dlFrontScanned && MG._rez._dlBackScanned);
  }
};

// ===== SCAN DOCUMENT — open in-page camera (frame + auto burst), then OCR best frames =====
MG._rezScanDoc = function(docType, side){
  side = (side==='front'||side==='back') ? side : null;
  var statusId = MG._rezSideStatusId('mindee-', docType, side);
  var statusEl=document.getElementById(statusId);
  MG._rezOpenCamera(docType, function(frames){
    if(!frames||!frames.length){ return; }
    if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Rozpoznávám doklad ze '+frames.length+' snímků...</div>';
    MG._rezOcrBurstRetry(frames, docType, MG._rez.userId||null, 2).then(async function(result){
      if(result.ok){
        await MG._rezApplyOcrResult(result.fields, docType, result.frame, 'mindee', side);
      } else {
        // Mindee selhal i po 2 pokusech → uložit foto jako manuální (admin zkontroluje ve Velínu)
        await MG._rezSaveDocPhoto(result.frame || frames[0], docType, 'failed', null, side);
        MG._rezMarkSideScanned(docType, side);
        if(typeof MG._rezCheckMandatoryDocs==='function') MG._rezCheckMandatoryDocs();
        if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad nahrán — ověření proběhne na pobočce</div>';
      }
    });
  });
};

// ===== GALLERY upload (mobile + desktop) — image (OCR) or PDF (raw upload) =====
MG._rezGalleryDoc = function(docType, mode, side){
  side = (side==='front'||side==='back') ? side : null;
  var prefix = (mode==='mindee') ? 'mindee-' : 'webdoc-';
  var statusId = MG._rezSideStatusId(prefix, docType, side);
  var statusEl=document.getElementById(statusId);
  MG._rezPickFromGallery(function(b64,file){
    if(!b64 && !file){ return; }
    if(b64){
      if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Rozpoznávám doklad...</div>';
      MG._rezOcrBurstRetry([b64], docType, MG._rez.userId||null, 2).then(async function(result){
        if(result.ok){
          await MG._rezApplyOcrResult(result.fields, docType, result.frame, mode, side);
        } else {
          // Mindee selhal i po 2 pokusech → fotka se stejně uloží, admin ověří ručně
          await MG._rezSaveDocPhoto(b64, docType, 'failed', null, side);
          if(mode==='mindee'){
            MG._rezMarkSideScanned(docType, side);
            if(typeof MG._rezCheckMandatoryDocs==='function') MG._rezCheckMandatoryDocs();
          }
          if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad nahrán — ověření proběhne na pobočce</div>';
        }
      });
    } else if(file){
      // PDF — raw upload, no OCR
      MG._rezUploadDocFile(file, docType);
    }
  });
};

// ===== APPLY OCR RESULT — save to profile, upload to storage, update UI =====
// mode: 'mindee' (Mindee step on mobile) or 'webdoc' (desktop optional upload — auto-fills form)
// side: 'front' | 'back' | null (pas)
MG._rezApplyOcrResult = async function(f, docType, base64, mode, side){
  side = (side==='front'||side==='back') ? side : null;
  var prefix = (mode==='mindee') ? 'mindee-' : 'webdoc-';
  var statusEl=document.getElementById(MG._rezSideStatusId(prefix, docType, side));
  var info=docType==='id'?(f.idNumber?'č. '+f.idNumber:''):(f.licenseNumber?'č. '+f.licenseNumber:'');
  if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad rozpoznán'+(info?' — '+info:'')+'</div>';

  // Auto-fill form fields (desktop step 2 only) — jen z líce, kde jsou klíčové údaje
  if(mode==='webdoc' && side !== 'back'){
    if(docType==='id'&&f.idNumber){ var dn=document.getElementById('rez-doc-number'); if(dn) dn.value=f.idNumber; }
    if(docType==='dl'){
      if(f.licenseNumber){ var ln=document.getElementById('rez-license-number'); if(ln) ln.value=f.licenseNumber; }
      if(f.licenseCategory){ var lg=document.getElementById('rez-license-group'); if(lg) lg.value=String(f.licenseCategory).toUpperCase(); }
      if(f.licenseExpiry){ var le=document.getElementById('rez-license-expiry'); if(le) le.value=f.licenseExpiry; }
    }
  }

  // Mark side scanned + flip souhrnný flag
  MG._rezMarkSideScanned(docType, side);
  if(typeof MG._rezCheckMandatoryDocs==='function') MG._rezCheckMandatoryDocs();

  // Save OCR to profile + upload foto + insert documents (s metadata.mindee_status='ok')
  if(MG._rez.userId){
    try{
      var upd={};
      if(docType==='id'&&f.idNumber){upd.id_number=f.idNumber;upd.id_verified_at=new Date().toISOString();}
      if(docType==='dl'&&f.licenseNumber){upd.license_number=f.licenseNumber;upd.license_verified_at=new Date().toISOString();}
      if(Object.keys(upd).length) await window.sb.from('profiles').update(upd).eq('id',MG._rez.userId);
    }catch(e){}
    if(base64){ await MG._rezSaveDocPhoto(base64, docType, 'ok', f, side); }
  }
};

// Legacy single-frame OCR (kept for backward compat — routes through burst path of length 1).
// side: 'front' | 'back' | null (pas)
MG._rezProcessOcr = async function(base64, docType, side){
  side = (side==='front'||side==='back') ? side : null;
  var statusEl=document.getElementById(MG._rezSideStatusId('mindee-', docType, side));
  var result=await MG._rezOcrBurstRetry([base64], docType, MG._rez.userId||null, 2);
  if(result.ok){
    await MG._rezApplyOcrResult(result.fields, docType, result.frame, 'mindee', side);
  } else {
    await MG._rezSaveDocPhoto(base64, docType, 'failed', null, side);
    MG._rezMarkSideScanned(docType, side);
    if(typeof MG._rezCheckMandatoryDocs==='function') MG._rezCheckMandatoryDocs();
    if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad nahrán — ověření proběhne na pobočce</div>';
  }
};

// ===== CHECK SCAN STATUS — flip button label when all required scans done =====
// OP vyžaduje líc + rub, pas jen 1×, ŘP vždy líc + rub.
MG._rezCheckMandatoryDocs = function(){
  var btn=document.getElementById('mindee-pay-btn');
  var msg=document.getElementById('mindee-mandatory-msg');
  var idDocType = MG._rez._idDocType || 'op';
  var idDone = idDocType === 'pas'
    ? !!MG._rez._passportScanned
    : !!(MG._rez._idFrontScanned && MG._rez._idBackScanned);
  var dlDone = !!(MG._rez._dlFrontScanned && MG._rez._dlBackScanned);
  if(idDone && dlDone){
    if(btn){ btn.textContent='Pokračovat k platbě'; }
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">&#10004; Všechny doklady nahrány — můžete pokračovat k platbě.</span>';
  } else if(idDone || dlDone){
    if(btn){ btn.textContent='Přeskočit zbytek a zaplatit'; }
  }
};

// ===== UPLOAD DOCUMENT FROM FILE (web step 2 — gallery / PDF) =====
MG._rezUploadDoc = function(docType, side){
  MG._rezGalleryDoc(docType, 'webdoc', side);
};

// ===== CAPTURE DOCUMENT WITH IN-PAGE CAMERA (web step 2 — burst + frame) =====
MG._rezCaptureDoc = function(docType, side){
  side = (side==='front'||side==='back') ? side : null;
  var statusEl=document.getElementById(MG._rezSideStatusId('webdoc-', docType, side));
  MG._rezOpenCamera(docType, function(frames){
    if(!frames||!frames.length){ return; }
    if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Rozpoznávám doklad ze '+frames.length+' snímků...</div>';
    MG._rezOcrBurstRetry(frames, docType, MG._rez.userId||null, 2).then(async function(result){
      if(result.ok){
        await MG._rezApplyOcrResult(result.fields, docType, result.frame, 'webdoc', side);
      } else {
        await MG._rezSaveDocPhoto(result.frame || frames[0], docType, 'failed', null, side);
        if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad nahrán — ověření proběhne na pobočce</div>';
      }
    });
  });
};

// Legacy alias — kept so any external callers keep working.
MG._rezProcessWebDocOcr = function(base64, docType, side){
  side = (side==='front'||side==='back') ? side : null;
  return MG._rezOcrBurstRetry([base64], docType, MG._rez.userId||null, 2).then(async function(result){
    if(result.ok) return MG._rezApplyOcrResult(result.fields, docType, result.frame, 'webdoc', side);
    await MG._rezSaveDocPhoto(base64, docType, 'failed', null, side);
    var statusEl=document.getElementById(MG._rezSideStatusId('webdoc-', docType, side));
    if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad nahrán — ověření proběhne na pobočce</div>';
  });
};

// ===== UPLOAD DOC FILE (PDF, non-image) =====
MG._rezUploadDocFile = async function(file,docType){
  var statusEl=document.getElementById('webdoc-'+(docType==='id'?'id':'dl')+'-status');
  try{
    if(MG._rez.userId){
      var docTypeStr=docType==='id'?'id_card':'drivers_license';
      var ext=file.name.split('.').pop()||'pdf';
      var path = MG._rez.userId+'/'+docTypeStr+'_'+Date.now()+'.'+ext;
      await window.sb.storage.from('documents').upload(path, file).catch(function(){});
      // PDF se neposílá do Mindee — vždy mindee_status='failed' (admin ověří ručně)
      var row = {
        user_id: MG._rez.userId,
        booking_id: MG._rez.bookingId || null,
        type: docTypeStr,
        file_path: path,
        file_name: path.split('/').pop(),
        name: docType==='id' ? 'Doklad totožnosti (web — manuální PDF)' : 'Řidičský průkaz (web — manuální PDF)',
        metadata: { source: 'web', mindee_status: 'failed', captured_at: new Date().toISOString() }
      };
      var ins = await window.sb.from('documents').insert(row);
      if(ins && ins.error && /metadata/i.test(ins.error.message||'')){
        delete row.metadata;
        await window.sb.from('documents').insert(row).catch(function(){});
      }
      if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Soubor nahrán — ověření proběhne na pobočce</div>';
    } else {
      if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Nelze nahrát — vyplňte údaje ručně</div>';
    }
  }catch(e){
    if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Chyba nahrávání</div>';
  }
};

// ===== BASE64 TO BLOB =====
MG._rezB64toBlob = function(b64,mime){
  var bytes=atob(b64),arr=[];
  for(var i=0;i<bytes.length;i+=512){
    var slice=bytes.slice(i,i+512),nums=new Array(slice.length);
    for(var j=0;j<slice.length;j++) nums[j]=slice.charCodeAt(j);
    arr.push(new Uint8Array(nums));
  }
  return new Blob(arr,{type:mime});
};

// ===== STRIPE CHECKOUT (skip doc validation if done in Mindee step) =====
MG._rezSubmitPayment = async function(){
  if(!MG._rez._docsValidated){
    var docNum=document.getElementById('rez-doc-number');
    var licNum=document.getElementById('rez-license-number');
    var licGroup=document.getElementById('rez-license-group');
    var licExpiry=document.getElementById('rez-license-expiry');
    var licConf=document.getElementById('rez-license-confirm');
    if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
    if(!licGroup||!licGroup.value){alert('Vyberte skupinu řidičského oprávnění (A2, A nebo Bez ŘP).');return;}
    var _isNoLic = (licGroup.value === 'N');
    if(!_isNoLic){
      if(!licNum||!licNum.value||licNum.value.trim().length<4){alert('Číslo řidičského průkazu musí mít alespoň 4 znaky.');return;}
      if(!licExpiry||!licExpiry.value){alert('Vyplňte platnost řidičského průkazu.');return;}
      if(!MG._isLicenseExpiryValid(licExpiry.value)){alert('Řidičský průkaz musí být platný min. 14 dní od dnes.');return;}
      if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}
    }

    // Validace hesla (pokud nebylo nastaveno dříve)
    if(!MG._rez._passwordSet){
      var pwd=document.getElementById('rez-password');
      var pwdC=document.getElementById('rez-password-confirm');
      if(!pwd||!pwd.value||pwd.value.length<8){alert('Heslo musí mít alespoň 8 znaků.');return;}
      if(!pwdC||pwd.value!==pwdC.value){alert('Hesla se neshodují.');return;}
      MG._rez._password=pwd.value;
    }

    // Kontrola ŘP skupiny vs. motorka (jen pokud motorka vyžaduje ŘP)
    var _moto = MG._rez.motos ? MG._rez.motos.find(function(m){return m.id===(MG._rez.formData||{}).motoId;}) : null;
    if(_moto && _moto.license_required && _moto.license_required !== 'N'){
      var _lg = licGroup.value.toUpperCase();
      var _allowed = {A:['A','A2','A1','AM'],A2:['A2','A1','AM']};
      var _ok = _allowed[_lg] || [];
      if(_ok.indexOf(_moto.license_required) === -1){
        alert('Pro tuto motorku potřebujete ŘP skupiny ' + _moto.license_required + '. Vaše skupina: ' + (_lg==='N'?'Bez ŘP':_lg));
        return;
      }
    }

    if(MG._rez.formData){
      MG._rez.formData._licGroup=licGroup.value;
      MG._rez.formData._licExpiry=_isNoLic?null:(licExpiry?licExpiry.value:null);
    }

    await MG._rezPersistDocs(docNum.value, _isNoLic?null:licNum.value,
      licGroup.value, _isNoLic?null:(licExpiry?licExpiry.value:null));
  }

  var btn=document.querySelector('#rez-form .btn.btngreen');
  if(btn){btn.disabled=true;btn.textContent='Zpracovávám...';}

  var bookingId=MG._rez.bookingId;
  var amount=MG._rez.bookingAmount;
  if(!bookingId){alert('Chyba: rezervace nebyla vytvořena. Zkuste znovu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}

  // Pokud zákazník přidal doplňky z e-shopu — vytvoř shop_order (pickup, doprava 0)
  // a pošli ID do process-payment, ať se přibalí do stejné Stripe session.
  var shopOrderId = MG._rez._shopOrderId || null;
  var shopItems = MG._rezShopItems || [];
  if(shopItems.length && !shopOrderId){
    try {
      var d = MG._rez.formData || {};
      var addr = (d.street||'') + (d.zip?(', '+d.zip):'') + (d.city?(' '+d.city):'');
      var soRes = await window.sb.rpc('create_web_shop_order', {
        items: shopItems.map(function(it){ return { product_id: it.product_id, size: it.size||null, qty: it.qty||1 }; }),
        customer_name: d.name||'',
        customer_email: d.email||'',
        customer_phone: d.phone||'',
        shipping_method: 'pickup',
        shipping_address: addr.trim()||null,
        payment_method: 'stripe',
        promo_code: null,
        notes: 'Doprodej k rezervaci '+bookingId
      });
      if(soRes.error || (soRes.data && soRes.data.error)){
        console.warn('[REZ] create_web_shop_order failed:', soRes.error || soRes.data);
        alert('Nepodařilo se vytvořit objednávku doplňků: '+((soRes.data&&soRes.data.error)||(soRes.error&&soRes.error.message)||'neznámá chyba'));
        if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
        return;
      }
      shopOrderId = (soRes.data && soRes.data.order_id) || null;
      MG._rez._shopOrderId = shopOrderId;
    } catch(e){
      console.error('[REZ] shop order exception', e);
      alert('Chyba při vytváření objednávky doplňků.');
      if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
      return;
    }
  }

  try{
    var payBody={booking_id:bookingId,amount:amount,type:'booking',source:'web',mode:'checkout',
      origin: window.location.origin,
      locale: (document.documentElement.lang||'cs').slice(0,2)};
    if(shopOrderId) payBody.shop_order_id = shopOrderId;
    var payRes=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/process-payment',{method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify(payBody)});
    var payData=await payRes.json();
    if(payData.error){
      var emsg = payData.error || '';
      if(emsg.indexOf('Booking overlap') !== -1) alert('Tuto motorku pr\u00e1v\u011b rezervoval jin\u00fd z\u00e1kazn\u00edk ve stejn\u00e9m term\u00ednu. Zvolte pros\u00edm jin\u00fd term\u00edn nebo jinou motorku.');
      else if(emsg.indexOf('overlapping booking') !== -1) alert('V tomto term\u00ednu ji\u017e m\u00e1te jinou aktivn\u00ed rezervaci.');
      else alert('Chyba platby: '+emsg);
      if(btn){btn.disabled=false;btn.textContent='Pokra\u010dovat k platb\u011b';}return;
    }
    // 100% sleva — potvrzeno bez Stripe
    if(payData.success && payData.free){
      MG._rez._paymentDone=true;
      try{sessionStorage.removeItem('mg_rez_form');}catch(e){}
      alert('Rezervace potvrzena! 100% sleva \u2014 platba nen\u00ed pot\u0159eba.');
      window.location.href='/potvrzeni?booking_id='+bookingId;
      return;
    }
    if(payData.checkout_url){
      MG._rez._paymentDone=true;
      try{sessionStorage.removeItem('mg_rez_form');}catch(e){}
      window.location.href=payData.checkout_url;
    }
    else{alert('Nepodařilo se vytvořit platbu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
  }catch(e){console.error('[REZ]',e);alert('Došlo k chybě.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
};
