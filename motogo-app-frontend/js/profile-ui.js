// ===== PROFILE-UI.JS – Profile screen rendering and editing =====

async function renderProfile(){
  try {
    var profile = await apiFetchProfile();
    if(!profile) return;

    // Format ISO date to Czech format
    function fmtIso(v){if(!v)return '';if(/\d{4}-\d{2}-\d{2}/.test(v)){var p=v.split('-');return parseInt(p[2])+'. '+parseInt(p[1])+'. '+p[0];}return v;}
    // Fill profile fields
    var fields = {
      'profile-name': profile.full_name,
      'profile-email': profile.email,
      'profile-phone': profile.phone,
      'profile-dob': fmtIso(profile.date_of_birth),
      'profile-street': profile.street,
      'profile-city': profile.city,
      'profile-zip': profile.zip,
      'profile-license-num': profile.license_number,
      'profile-license-expiry': fmtIso(profile.license_expiry),
      'profile-license-group': Array.isArray(profile.license_group) ? profile.license_group.join(', ') : (profile.license_group || '')
    };

    for(var id in fields){
      var el = document.getElementById(id);
      if(el){
        if(el.tagName === 'INPUT' || el.tagName === 'SELECT') el.value = fields[id] || '';
        else el.textContent = fields[id] || '';
      }
    }

    // Profile header
    var headerName = document.getElementById('profile-header-name');
    if(headerName) headerName.textContent = profile.full_name || '';
    var headerEmail = document.getElementById('profile-header-email');
    if(headerEmail) headerEmail.textContent = profile.email || '';
    var headerInitials = document.getElementById('profile-header-initials');
    if(headerInitials){
      headerInitials.textContent = (profile.full_name || 'NN').split(' ').map(function(n){ return n.charAt(0).toUpperCase(); }).join('');
    }

    // Verification badge
    var vBadge = document.getElementById('profile-docs-badge');
    if(vBadge){
      if(profile.docs_verified_at){
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#dcfce7;color:#166534;border:1px solid #86efac;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#9989; Doklady ověřeny</span>';
      } else if(profile.docs_verification_status === 'mismatch'){
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#fef3c7;color:#92400e;border:1px solid #f59e0b;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#9888;&#65039; Rozpory v dokladech</span>';
      } else {
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#f3f4f6;color:#6b7280;border:1px solid #d1d5db;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#128196; Doklady neověřeny</span>';
      }
    }

    // Documents section
    renderDocuments();
  } catch(e){ console.error('renderProfile error:', e); }
}

// ===== POBOČKY =====
var _branchesLoaded = false;
async function loadBranches(){
  if(_branchesLoaded) return;
  _branchesLoaded = true;
  renderBranches();
}

async function renderBranches(){
  var wrap = document.getElementById('branches-list');
  if(!wrap) return;
  if(!window.supabase){
    wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--g400);">Pobočky nejsou dostupné offline</div>';
    return;
  }
  try {
    var r = await window.supabase.from('branches').select('id, name, address, city, gps_lat, gps_lng, is_open, type').order('name');
    if(!r.data || r.data.length === 0){
      wrap.innerHTML = '<div style="padding:12px;text-align:center;font-size:12px;color:var(--g400);">Žádné pobočky</div>';
      return;
    }
    var html = '';
    r.data.forEach(function(b){
      var statusColor = b.is_open ? '#16a34a' : '#b91c1c';
      var statusText = b.is_open ? 'Nonstop' : 'Zavřeno';
      var typeLabel = b.type ? ' · ' + b.type : '';
      var hasGps = b.gps_lat && b.gps_lng;
      var gpsText = hasGps ? '<div style="font-size:10px;color:var(--g400);margin-top:2px;">GPS: '+Number(b.gps_lat).toFixed(5)+', '+Number(b.gps_lng).toFixed(5)+'</div>' : '';
      var navBtn = hasGps ? '<button onclick="event.stopPropagation();navigateToBranch('+b.gps_lat+','+b.gps_lng+',\''+_escHtml(b.name)+'\')" style="background:var(--green);color:#fff;border:none;border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:5px;margin-top:8px;width:100%;">📍 Navigovat</button>' : '';
      var addrBtn = '<button onclick="event.stopPropagation();navigateToAddress(\''+_escHtml((b.address||'')+', '+(b.city||''))+'\')" style="background:var(--gp);color:var(--gd);border:1px solid var(--green);border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:5px;margin-top:6px;width:100%;">🗺️ Otevřít v mapách</button>';
      html += '<div style="background:#fff;border-radius:var(--rsm);padding:12px;margin-bottom:8px;border:1px solid var(--g200);">' +
        '<div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;">' +
        '<div style="font-size:24px;">🏪</div>' +
        '<div style="flex:1;"><div style="font-size:14px;font-weight:800;color:var(--black);">'+b.name+'</div>' +
        '<div style="font-size:11px;color:var(--g400);font-weight:500;">'+((b.address||'')+(b.city?', '+b.city:''))+typeLabel+'</div>' +
        gpsText + '</div>' +
        '<span style="font-size:10px;font-weight:800;color:'+statusColor+';background:'+(b.is_open?'#dcfce7':'#fee2e2')+';padding:3px 8px;border-radius:10px;">'+statusText+'</span></div>' +
        (hasGps ? navBtn : addrBtn) +
        '</div>';
    });
    wrap.innerHTML = html;
  } catch(e){ wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--red);">Chyba při načítání poboček</div>'; }
}

function _escHtml(s){ return (s||'').replace(/'/g,"\\'").replace(/"/g,'&quot;'); }

function navigateToBranch(lat, lng, name){
  var url = 'https://www.google.com/maps/dir/?api=1&destination='+lat+','+lng;
  if(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser){
    window.Capacitor.Plugins.Browser.open({ url: url });
  } else {
    window.open(url, '_blank');
  }
}

function navigateToAddress(address){
  var url = 'https://www.google.com/maps/dir/?api=1&destination='+encodeURIComponent(address);
  if(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser){
    window.Capacitor.Plugins.Browser.open({ url: url });
  } else {
    window.open(url, '_blank');
  }
}

async function doSaveProfile(){
  try {
    // Parse Czech date "D. M. YYYY" back to ISO "YYYY-MM-DD"
    function parseCzDate(v){
      if(!v) return null;
      v = v.trim();
      if(/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      var m = v.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
      if(m) return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);
      return null;
    }
    var data = {
      full_name: (document.getElementById('profile-name') || {}).value || '',
      phone: (document.getElementById('profile-phone') || {}).value || '',
      street: (document.getElementById('profile-street') || {}).value || '',
      city: (document.getElementById('profile-city') || {}).value || '',
      zip: (document.getElementById('profile-zip') || {}).value || '',
      license_number: (document.getElementById('profile-license-num') || {}).value || '',
      license_group: (function(){ var v = (document.getElementById('profile-license-group') || {}).value || ''; return v ? v.split(/[,\s]+/).filter(Boolean) : []; })()
    };
    var dob = parseCzDate((document.getElementById('profile-dob') || {}).value);
    if(dob) data.date_of_birth = dob;
    var licExp = parseCzDate((document.getElementById('profile-license-expiry') || {}).value);
    if(licExp) data.license_expiry = licExp;

    var result = await apiUpdateProfile(data);
    if(result.error){
      showT('✗',_t('common').error,result.error);
      return;
    }
    showT('✓',_t('common').profileSaved,_t('common').changesSaved);
    renderUserData();
  } catch(e){ console.error('doSaveProfile error:', e); showT('✗',_t('common').error,_t('common').saveFailed); }
}

// ===== DOCS SCREEN — show verification status from DB =====
async function renderDocsScreenStatus(){
  var banner=document.getElementById('docs-verified-banner');
  var unverified=document.getElementById('docs-unverified-section');
  if(!banner||!unverified) return;
  if(!_isSupabaseReady()){banner.style.display='none';unverified.style.display='';return;}
  try {
    var uid=await _getUserId();if(!uid)return;
    var r=await window.supabase.from('profiles')
      .select('id_verified_at,id_verified_until,license_verified_at,license_verified_until,passport_verified_at,passport_verified_until,license_expiry,license_number')
      .eq('id',uid).maybeSingle();
    if(!r||!r.data){banner.style.display='none';unverified.style.display='';return;}
    var p=r.data,today=new Date().toISOString().slice(0,10);
    var hasId=p.id_verified_at&&(!p.id_verified_until||p.id_verified_until>=today);
    var hasPas=p.passport_verified_at&&(!p.passport_verified_until||p.passport_verified_until>=today);
    var hasLic=p.license_verified_at&&(!p.license_verified_until||p.license_verified_until>=today);
    var idOk=hasId||hasPas;
    var allOk=idOk&&hasLic;
    if(allOk){
      // Format dates
      function fmtD(d){if(!d)return'—';var p=d.split('-');return parseInt(p[2])+'.'+parseInt(p[1])+'.'+p[0];}
      var licUntil=p.license_verified_until||p.license_expiry||'—';
      var idUntil=hasId?p.id_verified_until:p.passport_verified_until;
      banner.style.display='block';
      banner.innerHTML='<div style="margin:12px 20px 0;background:#ecfdf5;border:2px solid #6ee7b7;border-radius:var(--r);padding:16px;text-align:center;">'+
        '<div style="font-size:36px;margin-bottom:6px;">✅</div>'+
        '<div style="font-size:16px;font-weight:900;color:#065f46;margin-bottom:4px;">Doklady ověřeny</div>'+
        '<div style="font-size:12px;color:#047857;line-height:1.7;">'+
        (hasId?'🪪 OP ověřen':'📕 Pas ověřen')+(idUntil?' — platnost do <strong>'+fmtD(idUntil)+'</strong>':'')+'<br>'+
        '🏍️ ŘP ověřen — platnost do <strong>'+fmtD(licUntil)+'</strong></div>'+
        '<div style="font-size:11px;color:#059669;margin-top:8px;line-height:1.5;">Vaše doklady jsou evidovány v systému.<br>Po reinstalaci ani aktualizaci aplikace je nemusíte znovu nahrávat.</div>'+
        '</div>';
      unverified.style.display='none';
      localStorage.setItem('mg_docs_verified','1');
    } else {
      banner.style.display='none';
      unverified.style.display='';
      // Show partial status if some docs are verified
      if(idOk||hasLic){
        var partial='<div style="margin:12px 20px 0;background:#fefce8;border:1px solid #fde047;border-radius:var(--rsm);padding:11px 13px;">'+
          '<div style="font-size:13px;font-weight:700;color:#854d0e;margin-bottom:3px;">📋 Částečně ověřeno</div>'+
          '<div style="font-size:12px;color:#a16207;line-height:1.6;">'+(idOk?'✅ Doklad totožnosti OK':'❌ Chybí doklad totožnosti')+' · '+(hasLic?'✅ ŘP OK':'❌ Chybí řidičský průkaz')+'</div></div>';
        banner.style.display='block';banner.innerHTML=partial;
      }
    }
  }catch(e){console.warn('[DOCS] renderDocsScreenStatus:',e);}
}

async function renderDocuments(){
  try {
    var docsWrap = document.getElementById('profile-documents');
    if(!docsWrap) return;

    var docs = await apiFetchDocuments();
    if(!docs || docs.length === 0){
      docsWrap.innerHTML = '<div style="font-size:12px;color:var(--g400);padding:8px 0;">'+_t('common').noDocs+'</div>';
      return;
    }

    docsWrap.innerHTML = docs.map(function(d){
      var typeLabels = {contract:'📄 '+_t('doc').contractLabel, protocol:'📋 '+_t('doc').protocolLabel, invoice:'🧾 '+_t('doc').invoiceFinal.split(' ')[0],
        vop:'📜 VOP', license_photo:'🏍️', id_photo:'🪪', document:'📎'};
      return '<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--g100);">' +
        '<div style="font-size:20px;">' + (typeLabels[d.type] ? typeLabels[d.type].split(' ')[0] : '📎') + '</div>' +
        '<div style="flex:1;"><div style="font-size:12px;font-weight:700;">' + (d.file_name || d.type) + '</div>' +
        '<div style="font-size:10px;color:var(--g400);">' + (d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '') + '</div></div></div>';
    }).join('');
  } catch(e){ console.error('renderDocuments error:', e); }
}

async function doDeleteAccount(){
  try {
    if(!confirm(_t('common').deleteAccount)) return;
    if(!confirm(_t('common').deleteConfirm)) return;

    if(_isSupabaseReady()){
      try {
        var session = await _getSession();
        if(session && session.user_id){
          await supabase.from('profiles').delete().eq('id', session.user_id);
        }
        await supabase.auth.signOut();
      } catch(e){ console.error('doDeleteAccount supabase error:', e); }
    }

    try { localStorage.removeItem('mg_current_session'); } catch(e){}
    showT('✓',_t('common').accountDeleted,_t('common').dataRemoved);
    setTimeout(function(){ goTo('s-login'); }, 1000);
  } catch(e){ console.error('doDeleteAccount error:', e); showT('✗',_t('common').error,_t('common').deleteFailed); }
}

async function renderInvoices(){
  try {
    var wrap = document.getElementById('invoices-list');
    if(!wrap) return;
    var docs = await apiFetchDocuments();
    // Filter only invoice types
    var invoices = (docs || []).filter(function(d){
      return d.type === 'invoice_advance' || d.type === 'invoice_final' || d.type === 'payment_receipt';
    });
    if(invoices.length === 0){
      wrap.innerHTML = '<div style="text-align:center;padding:30px;color:var(--g400);">'+(_t('common').noDocuments||'Zatím žádné faktury')+'</div>';
      return;
    }
    var years = {};
    invoices.forEach(function(d){
      var y = new Date(d.created_at || d.date).getFullYear();
      if(!years[y]) years[y] = [];
      years[y].push(d);
    });
    var html = '';
    Object.keys(years).sort(function(a,b){return b-a;}).forEach(function(yr){
      html += '<div class="msec-t" style="padding:'+(html?'12':'0')+'px 0 8px;">'+yr+'</div>';
      years[yr].forEach(function(d){
        var dateFmt = new Date(d.date || d.created_at).toLocaleDateString('cs-CZ');
        var isReceipt = d.type === 'payment_receipt';
        var icon = isReceipt ? '✅' : (d.type === 'invoice_advance' ? '🧾' : '💰');
        var label = isReceipt ? (_t('doc').paymentReceipt||'Doklad k platbě') : (d.type === 'invoice_advance' ? (_t('doc').invoiceAdvance||'Zálohová faktura') : (_t('doc').invoiceFinal||'Faktura'));
        var amt = d.amount ? d.amount.toLocaleString('cs-CZ') + ' Kč' : '';
        var invType = isReceipt ? 'payment_receipt' : (d.type === 'invoice_advance' ? 'advance' : 'final');
        html += '<div class="inv-item" onclick="showInvoice(\''+d.booking_id+'\',\''+invType+'\')">' +
          '<div class="inv-icon">'+icon+'</div>' +
          '<div class="inv-info"><div class="inv-name">'+(d.moto_name||'')+' · '+label+'</div>' +
          '<div class="inv-sub">'+(d.res_num||'')+' · '+dateFmt+'</div></div>' +
          '<div>'+(amt?'<div class="inv-amt">'+amt+'</div>':'')+
          '<div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️ · 📧</div></div></div>';
      });
    });
    wrap.innerHTML = html;
  } catch(e){ console.error('renderInvoices error:', e); }
}

var _pmLoaded = false;
async function loadPaymentMethods(){
  if(_pmLoaded) return;
  _pmLoaded = true;
  renderPaymentMethods();
}

async function renderPaymentMethods(){
  var wrap = document.getElementById('pm-cards-list');
  if(!wrap) return;
  if(typeof apiFetchPaymentMethods !== 'function'){
    wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--g400);">Platební metody nejsou dostupné offline</div>';
    return;
  }
  try {
    wrap.innerHTML = '<div style="text-align:center;padding:12px;color:var(--g400);font-size:12px;">Načítám uložené karty...</div>';
    var r = await apiFetchPaymentMethods();
    if(!r.success || !r.methods || r.methods.length === 0){
      wrap.innerHTML = '<div style="padding:12px;text-align:center;font-size:12px;color:var(--g400);">Žádné uložené karty</div>';
      return;
    }
    var brandIcons = {visa:'VISA',mastercard:'MC',amex:'AMEX',discover:'DISC'};
    var html = '';
    r.methods.forEach(function(m){
      var brandLabel = brandIcons[m.brand] || m.brand.toUpperCase();
      var expStr = (m.exp_month < 10 ? '0' : '') + m.exp_month + '/' + String(m.exp_year).slice(-2);
      var nameStr = m.holder_name ? '<div style="font-size:10px;color:var(--g400);margin-top:1px;">'+m.holder_name+'</div>' : '';
      var defBadge = m.is_default ? '<span style="background:var(--green);color:#fff;font-size:9px;font-weight:800;padding:2px 6px;border-radius:10px;margin-left:6px;">PRIORITNÍ</span>' : '';
      var defBtn = m.is_default ? '' : '<div onclick="event.stopPropagation();setDefaultCard(\''+m.id+'\')" style="font-size:10px;font-weight:700;color:var(--gd);cursor:pointer;margin-bottom:2px;">Nastavit prioritní</div>';
      html += '<div style="display:flex;align-items:center;gap:10px;padding:10px;background:#fff;border-radius:var(--rsm);margin-bottom:6px;border:1px solid '+(m.is_default?'var(--green)':'var(--g200)')+';">' +
        '<div style="font-size:20px;">💳</div>' +
        '<div style="flex:1;"><div style="font-size:13px;font-weight:700;color:var(--black);">•••• '+m.last4+' <span style="font-size:10px;font-weight:800;color:var(--g400);">'+brandLabel+'</span>'+defBadge+'</div>' +
        '<div style="font-size:11px;color:var(--g400);font-weight:500;">Platí do '+expStr+'</div>'+nameStr+'</div>' +
        '<div style="text-align:right;">'+defBtn+
        '<div onclick="event.stopPropagation();deleteCard(\''+m.id+'\')" style="font-size:10px;font-weight:700;color:var(--red);cursor:pointer;">Odebrat</div></div></div>';
    });
    wrap.innerHTML = html;
  } catch(e){ wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--red);">Chyba při načítání karet</div>'; }
}

async function deleteCard(pmId){
  if(!confirm('Opravdu odebrat tuto kartu?')) return;
  var r = await apiDeletePaymentMethod(pmId);
  if(r.success){ showT('✓','Karta odebrána',''); _pmLoaded = false; renderPaymentMethods(); }
  else { showT('✗','Chyba',r.error || 'Nepodařilo se odebrat kartu'); }
}

async function setDefaultCard(pmId){
  var r = await apiSetDefaultPaymentMethod(pmId);
  if(r.success){ showT('✓','Prioritní karta nastavena',''); _pmLoaded = false; renderPaymentMethods(); }
  else { showT('✗','Chyba',r.error || 'Nepodařilo se nastavit prioritní kartu'); }
}

// ── In-app card form (Stripe Elements) ──
var _addCardFormVisible = false;

function showAddCardForm(){
  var formWrap = document.getElementById('pm-add-card-form');
  if(!formWrap) return;
  if(_addCardFormVisible){
    hideAddCardForm();
    return;
  }
  _addCardFormVisible = true;
  formWrap.style.display = 'block';
  // Init Stripe Elements card field
  if(typeof _initCardElement === 'function') _initCardElement('stripe-card-element');
  var nameInput = document.getElementById('card-holder-name');
  if(nameInput) nameInput.value = '';
  var errEl = document.getElementById('card-form-error');
  if(errEl) errEl.textContent = '';
  var btn = document.getElementById('add-card-btn');
  if(btn) btn.textContent = '✕ Zrušit';
}

function hideAddCardForm(){
  _addCardFormVisible = false;
  var formWrap = document.getElementById('pm-add-card-form');
  if(formWrap) formWrap.style.display = 'none';
  if(typeof _destroyCardElement === 'function') _destroyCardElement();
  var btn = document.getElementById('add-card-btn');
  if(btn) btn.textContent = '+ Přidat novou kartu';
}

async function submitNewCard(){
  var errEl = document.getElementById('card-form-error');
  var saveBtn = document.getElementById('save-card-btn');
  if(errEl) errEl.textContent = '';
  if(saveBtn){ saveBtn.disabled = true; saveBtn.textContent = 'Ukládám...'; }
  try {
    var holderName = (document.getElementById('card-holder-name') || {}).value || '';
    if(typeof apiCreatePaymentMethod !== 'function'){
      if(errEl) errEl.textContent = 'Funkce není dostupná';
      return;
    }
    var r = await apiCreatePaymentMethod(holderName);
    if(r.success){
      showT('✓','Karta uložena','Karta byla úspěšně přidána');
      hideAddCardForm();
      _pmLoaded = false;
      renderPaymentMethods();
    } else {
      if(errEl) errEl.textContent = r.error || 'Nepodařilo se uložit kartu';
    }
  } catch(e){
    if(errEl) errEl.textContent = 'Chyba: ' + e.message;
  }
  if(saveBtn){ saveBtn.disabled = false; saveBtn.textContent = 'Uložit kartu'; }
}

function addNewCard(){
  showAddCardForm();
}

async function downloadDoc(docId){
  showT('⬇️',_t('common').downloadDoc,_t('common').openPDF);
  var result = await apiSendDocumentEmail(docId);
  if(result.success){
    setTimeout(function(){
      showT('📧',_t('common').sentToEmail,result.email);
    }, 1500);
  }
}

// ===== CONSENT / NOTIFICATION MANAGEMENT (DB-backed) =====
var _consentsLoaded = false;
var _consentData = {};

async function loadProfileConsents(section){
  if(_consentsLoaded){
    _fillConsentCheckboxes();
    return;
  }
  try {
    var profile = await apiFetchProfile();
    if(!profile) return;
    _consentData = {
      consent_push: !!profile.consent_push,
      consent_email: !!profile.consent_email,
      consent_sms: !!profile.consent_sms,
      consent_whatsapp: !!profile.consent_whatsapp,
      marketing_consent: !!profile.marketing_consent,
      consent_vop: !!profile.consent_vop,
      consent_gdpr: !!profile.consent_gdpr,
      consent_data_processing: !!profile.consent_data_processing,
      consent_contract: !!profile.consent_contract,
      consent_photo: !!profile.consent_photo
    };
    _consentsLoaded = true;
    _fillConsentCheckboxes();
  } catch(e){ console.error('loadProfileConsents:', e); }
}

function _fillConsentCheckboxes(){
  var map = {
    'pref-push': 'consent_push',
    'pref-email': 'consent_email',
    'pref-sms': 'consent_sms',
    'pref-wa': 'consent_whatsapp',
    'pref-marketing': 'marketing_consent',
    'pref-vop': 'consent_vop',
    'pref-gdpr': 'consent_gdpr',
    'pref-data': 'consent_data_processing',
    'pref-contract': 'consent_contract',
    'pref-photo': 'consent_photo'
  };
  for(var id in map){
    var el = document.getElementById(id);
    if(el) el.checked = !!_consentData[map[id]];
  }
  // Bio toggle
  var bioEl = document.getElementById('pref-bio-toggle');
  if(bioEl) bioEl.checked = !!localStorage.getItem('mg_bio_enabled');
}

async function saveProfileConsents(section){
  try {
    var data = {};
    if(section === 'notif'){
      data.consent_push = !!document.getElementById('pref-push').checked;
      data.consent_email = !!document.getElementById('pref-email').checked;
      data.consent_sms = !!document.getElementById('pref-sms').checked;
      data.consent_whatsapp = !!document.getElementById('pref-wa').checked;
      data.marketing_consent = !!document.getElementById('pref-marketing').checked;
    } else {
      data.consent_vop = !!document.getElementById('pref-vop').checked;
      data.consent_gdpr = !!document.getElementById('pref-gdpr').checked;
      data.consent_data_processing = !!document.getElementById('pref-data').checked;
      data.consent_contract = !!document.getElementById('pref-contract').checked;
      data.consent_photo = !!document.getElementById('pref-photo').checked;
    }
    var result = await apiUpdateProfile(data);
    if(result.error){
      showT('✗','Chyba',result.error);
      return;
    }
    // Update local cache
    for(var k in data) _consentData[k] = data[k];
    showT('✓','Uloženo','Nastavení bylo uloženo');
  } catch(e){ showT('✗','Chyba','Nepodařilo se uložit'); }
}

function toggleBiometricSetting(){
  var el = document.getElementById('pref-bio-toggle');
  if(!el) return;
  if(el.checked){
    localStorage.setItem('mg_bio_enabled','1');
    showT('✓','Biometrika zapnuta','Příští přihlášení bude biometrické');
  } else {
    localStorage.removeItem('mg_bio_enabled');
    showT('✓','Biometrika vypnuta','');
  }
}
