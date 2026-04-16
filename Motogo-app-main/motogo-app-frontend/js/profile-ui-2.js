// ===== PROFILE-UI-2.JS – Account deletion, invoices, payment methods, consents =====
// Split from profile-ui.js. All functions remain global.

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
    showT('\u2713',_t('common').accountDeleted,_t('common').dataRemoved);
    setTimeout(function(){ goTo('s-login'); }, 1000);
  } catch(e){ console.error('doDeleteAccount error:', e); showT('\u2717',_t('common').error,_t('common').deleteFailed); }
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
      wrap.innerHTML = '<div style="text-align:center;padding:30px;color:var(--g400);">'+(_t('common').noDocuments||'Zat\u00edm \u017e\u00e1dn\u00e9 faktury')+'</div>';
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
        var icon = isReceipt ? '\u2705' : (d.type === 'invoice_advance' ? '\ud83e\uddfe' : '\ud83d\udcb0');
        var label = isReceipt ? (_t('doc').paymentReceipt||'Doklad k platb\u011b') : (d.type === 'invoice_advance' ? (_t('doc').invoiceAdvance||'Z\u00e1lohov\u00e1 faktura') : (_t('doc').invoiceFinal||'Faktura'));
        var amt = d.amount ? d.amount.toLocaleString('cs-CZ') + ' K\u010d' : '';
        var invType = isReceipt ? 'payment_receipt' : (d.type === 'invoice_advance' ? 'advance' : 'final');
        html += '<div class="inv-item" onclick="showInvoice(\''+d.booking_id+'\',\''+invType+'\')">' +
          '<div class="inv-icon">'+icon+'</div>' +
          '<div class="inv-info"><div class="inv-name">'+(d.moto_name||'')+' \u00b7 '+label+'</div>' +
          '<div class="inv-sub">'+(d.res_num||'')+' \u00b7 '+dateFmt+'</div></div>' +
          '<div>'+(amt?'<div class="inv-amt">'+amt+'</div>':'')+
          '<div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF \u2b07\ufe0f \u00b7 \ud83d\udce7</div></div></div>';
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
    wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--g400);">'+_t('hc').noCardsOffline+'</div>';
    return;
  }
  try {
    wrap.innerHTML = '<div style="text-align:center;padding:12px;color:var(--g400);font-size:12px;">'+_t('hc').loadingCards+'</div>';
    var r = await apiFetchPaymentMethods();
    if(!r.success || !r.methods || r.methods.length === 0){
      wrap.innerHTML = '<div style="padding:12px;text-align:center;font-size:12px;color:var(--g400);">'+_t('hc').noCards+'</div>';
      return;
    }
    var brandIcons = {visa:'VISA',mastercard:'MC',amex:'AMEX',discover:'DISC'};
    var html = '';
    r.methods.forEach(function(m){
      var brandLabel = brandIcons[m.brand] || m.brand.toUpperCase();
      var expStr = (m.exp_month < 10 ? '0' : '') + m.exp_month + '/' + String(m.exp_year).slice(-2);
      var nameStr = m.holder_name ? '<div style="font-size:10px;color:var(--g400);margin-top:1px;">'+m.holder_name+'</div>' : '';
      var defBadge = m.is_default ? '<span style="background:var(--green);color:#fff;font-size:9px;font-weight:800;padding:2px 6px;border-radius:10px;margin-left:6px;">'+_t('hc').priority+'</span>' : '';
      var defBtn = m.is_default ? '' : '<div onclick="event.stopPropagation();setDefaultCard(\''+m.id+'\')" style="font-size:10px;font-weight:700;color:var(--gd);cursor:pointer;margin-bottom:2px;">'+_t('hc').setPriority+'</div>';
      html += '<div style="display:flex;align-items:center;gap:10px;padding:10px;background:#fff;border-radius:var(--rsm);margin-bottom:6px;border:1px solid '+(m.is_default?'var(--green)':'var(--g200)')+';">' +
        '<div style="font-size:20px;">\ud83d\udcb3</div>' +
        '<div style="flex:1;"><div style="font-size:13px;font-weight:700;color:var(--black);">\u2022\u2022\u2022\u2022 '+m.last4+' <span style="font-size:10px;font-weight:800;color:var(--g400);">'+brandLabel+'</span>'+defBadge+'</div>' +
        '<div style="font-size:11px;color:var(--g400);font-weight:500;">'+_t('hc').validUntil+' '+expStr+'</div>'+nameStr+'</div>' +
        '<div style="text-align:right;">'+defBtn+
        '<div onclick="event.stopPropagation();deleteCard(\''+m.id+'\')" style="font-size:10px;font-weight:700;color:var(--red);cursor:pointer;">'+_t('hc').removeBtn+'</div></div></div>';
    });
    wrap.innerHTML = html;
  } catch(e){ wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--red);">'+_t('hc').loadCardsError+'</div>'; }
}

async function deleteCard(pmId){
  if(!confirm(_t('hc').removeCard)) return;
  var r = await apiDeletePaymentMethod(pmId);
  if(r.success){ showT('\u2713',_t('hc').cardRemoved,''); _pmLoaded = false; renderPaymentMethods(); }
  else { showT('\u2717',_t('common').error,r.error || _t('hc').cardRemoveFailed); }
}

async function setDefaultCard(pmId){
  var r = await apiSetDefaultPaymentMethod(pmId);
  if(r.success){ showT('\u2713',_t('hc').priorityCardSet,''); _pmLoaded = false; renderPaymentMethods(); }
  else { showT('\u2717',_t('common').error,r.error || _t('hc').priorityCardFailed); }
}

// -- In-app card form (Stripe Elements) --
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
  if(btn) btn.textContent='\u2715 '+_t('hc').cancelBtn;
}

function hideAddCardForm(){
  _addCardFormVisible = false;
  var formWrap = document.getElementById('pm-add-card-form');
  if(formWrap) formWrap.style.display = 'none';
  if(typeof _destroyCardElement === 'function') _destroyCardElement();
  var btn = document.getElementById('add-card-btn');
  if(btn) btn.textContent='+ '+_t('hc').addNewCard;
}

async function submitNewCard(){
  var errEl = document.getElementById('card-form-error');
  var saveBtn = document.getElementById('save-card-btn');
  if(errEl) errEl.textContent = '';
  if(saveBtn){ saveBtn.disabled = true; saveBtn.textContent=_t('hc').saving; }
  try {
    var holderName = (document.getElementById('card-holder-name') || {}).value || '';
    if(typeof apiCreatePaymentMethod !== 'function'){
      if(errEl) errEl.textContent = _t('hc').funcNotAvailable||'Function not available';
      return;
    }
    var r = await apiCreatePaymentMethod(holderName);
    if(r.success){
      showT('\u2713',_t('hc').cardSaved,_t('hc').cardSavedMsg);
      hideAddCardForm();
      _pmLoaded = false;
      renderPaymentMethods();
    } else {
      if(errEl) errEl.textContent = r.error || _t('hc').cardSaveFailed;
    }
  } catch(e){
    if(errEl) errEl.textContent = (_t('common').error||'Error') + ': ' + e.message;
  }
  if(saveBtn){ saveBtn.disabled = false; saveBtn.textContent=_t('hc').saveCard; }
}

function addNewCard(){
  showAddCardForm();
}

async function downloadDoc(docId){
  showT('\u2b07\ufe0f',_t('common').downloadDoc,_t('common').openPDF);
  var result = await apiSendDocumentEmail(docId);
  if(result.success){
    setTimeout(function(){
      showT('\ud83d\udce7',_t('common').sentToEmail,result.email);
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
      showT('\u2717',_t('common').error,result.error);
      return;
    }
    // Update local cache
    for(var k in data) _consentData[k] = data[k];
    showT('\u2713',_t('hc').saved,_t('hc').settingsSaved);
  } catch(e){ showT('\u2717',_t('common').error,_t('hc').saveFailed||'Save failed'); }
}

function toggleBiometricSetting(){
  var el = document.getElementById('pref-bio-toggle');
  if(!el) return;
  if(el.checked){
    localStorage.setItem('mg_bio_enabled','1');
    showT('\u2713',_t('hc').bioOn,_t('hc').bioOnMsg);
  } else {
    localStorage.removeItem('mg_bio_enabled');
    showT('\u2713',_t('hc').bioOff,'');
  }
}
