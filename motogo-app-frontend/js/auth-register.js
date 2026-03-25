// ===== AUTH-REGISTER.JS – Registration flow =====
// Split from auth-ui.js. Depends on: auth-ui.js (helpers), auth-session.js (renderUserData)

// ===== REGISTER =====
var regStep = 1;

function regBack(){
  if(regStep>1){
    document.getElementById('reg-step-'+regStep).classList.remove('active');
    var p=document.getElementById('rp'+regStep);if(p)p.classList.remove('cur');
    regStep--;
    document.getElementById('reg-step-'+regStep).classList.add('active');
    var p2=document.getElementById('rp'+regStep);if(p2)p2.classList.add('cur');
    document.getElementById('reg-next-btn').textContent=_t('auth').next;
    var lbl=document.getElementById('reg-back-label');
    if(lbl)lbl.textContent=regStep===1?_t('auth').backLogin:_t('auth').back;
  } else {
    histBack();
  }
}

function regNext(){
  try {
    // Validate current step before proceeding
    if(regStep === 1){
      var fname = document.getElementById('reg-fname');
      var lname = document.getElementById('reg-lname');
      var email = document.getElementById('reg-email');
      var phone = document.getElementById('reg-phone');
      var pass = document.getElementById('reg-pass');

      if(!fname || !fname.value.trim()){ showT('⚠️',_t('auth').fillName,''); return; }
      if(!lname || !lname.value.trim()){ showT('⚠️',_t('auth').fillSurname,''); return; }
      if(!email || !email.value.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value.trim())){
        showT('⚠️',_t('auth').badEmail,_t('auth').validEmail); return;
      }
      if(!pass || pass.value.length < 8){
        showT('⚠️',_t('auth').shortPass,_t('auth').minPass); return;
      }
    }

    if(regStep < 4){
      document.getElementById('reg-step-'+regStep).classList.remove('active');
      document.getElementById('rp'+regStep).classList.remove('cur');
      document.getElementById('rp'+regStep).classList.add('done');
      regStep++;
      document.getElementById('reg-step-'+regStep).classList.add('active');
      document.getElementById('rp'+regStep).classList.add('cur');
      if(regStep === 4) document.getElementById('reg-next-btn').textContent=_t('auth').finish;
    } else {
      // Final step – validate consents and register
      doRegister();
    }
  } catch(e){ console.error('regNext error:', e); }
}

function _regResetForm(){
  regStep = 1;
  for(var i=1; i<=4; i++){
    var step = document.getElementById('reg-step-'+i);
    if(step) step.classList.toggle('active', i===1);
    var p = document.getElementById('rp'+i);
    if(p){ p.classList.remove('done','cur'); if(i===1) p.classList.add('cur'); }
  }
  document.getElementById('reg-next-btn').textContent=_t('auth').next;
}

function _collectRegFields(){
  return {
    email: (document.getElementById('reg-email').value || '').trim(),
    pass: document.getElementById('reg-pass').value || '',
    fname: (document.getElementById('reg-fname').value || '').trim(),
    lname: (document.getElementById('reg-lname').value || '').trim(),
    phone: (document.getElementById('reg-phone').value || '').trim(),
    dob: (document.getElementById('reg-dob').value || '').trim(),
    street: (document.getElementById('reg-street').value || '').trim(),
    zip: (document.getElementById('reg-zip').value || '').trim(),
    city: (document.getElementById('reg-city').value || '').trim(),
    country: document.getElementById('reg-country') ? document.getElementById('reg-country').value : 'Česká republika',
    licenseNum: (document.getElementById('reg-license-num').value || '').trim(),
    licenseExpiry: (document.getElementById('reg-license-to').value || '').trim(),
    licenseGroup: document.getElementById('reg-license-group') ? document.getElementById('reg-license-group').value : 'A2'
  };
}

// Registration success handler
function _regSuccess(userId, email, session, password){
  _syncLocalSession(userId, email);
  var refreshToken = (session && session.refresh_token) || null;
  _storeBioUser(userId, email, refreshToken, password);
  // Auto-enable biometric
  localStorage.setItem('mg_bio_enabled','1');
  showT('✓',_t('auth').regDone,_t('auth').regWelcome);
  _regResetForm();
  renderUserData();
  setTimeout(function(){ showBiometricPrompt(); }, 800);
}

function doRegister(){
  // Validate required consents
  var terms = document.getElementById('reg-terms');
  var gdpr = document.getElementById('reg-gdpr');
  if(!terms || !terms.checked || !gdpr || !gdpr.checked){
    showT('⚠️',_t('auth').consents,_t('auth').checkConsent);
    return;
  }

  var f = _collectRegFields();
  var metadata = {
    full_name: f.fname + ' ' + f.lname,
    phone: f.phone,
    date_of_birth: f.dob,
    street: f.street,
    city: f.city,
    zip: f.zip,
    country: f.country,
    license_number: f.licenseNum,
    license_expiry: f.licenseExpiry,
    license_group: f.licenseGroup
  };

  // Collect all consent values
  var consents = {
    marketing_consent: _regCheckbox('reg-marketing'),
    consent_gdpr: _regCheckbox('reg-gdpr'),
    consent_vop: _regCheckbox('reg-terms'),
    consent_data_processing: _regCheckbox('reg-data-processing'),
    consent_email: _regCheckbox('reg-email-comm'),
    consent_sms: _regCheckbox('reg-sms-comm'),
    consent_push: _regCheckbox('reg-push-comm'),
    consent_whatsapp: _regCheckbox('reg-wa-comm'),
    consent_photo: _regCheckbox('reg-photos'),
    consent_contract: _regCheckbox('reg-contract')
  };

  // Supabase je jediný backend
  if(_isSupabaseReady()){
    authSignUp(f.email, f.pass, metadata).then(function(result){
      if(result.error){
        console.error('doRegister supabase error:', result.error);
        showT('✗',_t('auth').regErr,result.error);
        return;
      }
      var userId = (result.user && result.user.id) ? result.user.id : null;
      if(userId){
        // Save consents to profiles table
        window.supabase.from('profiles').update(consents).eq('id', userId).then(function(){});
        _regSuccess(userId, f.email, result.session, f.pass);
      } else {
        showT('✗',_t('auth').regErr,'Registrace se nezdařila. Zkuste to znovu.');
      }
    }).catch(function(e){
      console.error('doRegister supabase error:', e);
      showT('✗',_t('auth').error,'Registrace selhala. Zkontrolujte připojení.');
    });
    return;
  }

  // Supabase není dostupný — zobraz offline hlášku
  OfflineGuard.check();
}

function _regCheckbox(id){
  var el = document.getElementById(id);
  return el ? !!el.checked : false;
}
