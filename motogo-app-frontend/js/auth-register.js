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

// --- Registration validation helpers ---
function _regIsNameValid(v){
  if(!v||v.length<2)return false;
  // Only unicode letters, spaces, hyphens, apostrophes
  if(!/^[\p{Letter}\s'\-]+$/u.test(v))return false;
  // Block gibberish: 3+ identical chars in a row (aaa, xxx)
  if(/(.)\1{2,}/i.test(v))return false;
  return true;
}
function _regIsPhoneValid(v){
  if(!v)return false;
  var digits=v.replace(/[\s\-()]/g,'');
  // Must start with +, 9-15 digits total
  if(!/^\+\d{8,14}$/.test(digits))return false;
  return true;
}
function _regParseCzDate(v){
  if(!v)return null;
  var m=v.trim().match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
  if(m)return new Date(parseInt(m[3]),parseInt(m[2])-1,parseInt(m[1]));
  return null;
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
      var dob = document.getElementById('reg-dob');

      if(!_regIsNameValid((fname||{}).value)){
        showT('⚠️','Jméno','Zadejte platné jméno (min. 2 písmena, bez číslic)'); return;
      }
      if(!_regIsNameValid((lname||{}).value)){
        showT('⚠️','Příjmení','Zadejte platné příjmení (min. 2 písmena, bez číslic)'); return;
      }
      if(!email || !email.value.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value.trim())){
        showT('⚠️',_t('auth').badEmail,_t('auth').validEmail); return;
      }
      if(!_regIsPhoneValid((phone||{}).value)){
        showT('⚠️','Telefon','Zadejte telefon v mezinárodním formátu (např. +420 777 000 000)'); return;
      }
      // DOB: required, 18-99 years
      var dobDate=_regParseCzDate((dob||{}).value);
      if(!dobDate){
        showT('⚠️','Datum narození','Vyberte datum narození'); return;
      }
      var today=new Date();today.setHours(0,0,0,0);
      var age=today.getFullYear()-dobDate.getFullYear();
      var mDiff=today.getMonth()-dobDate.getMonth();
      if(mDiff<0||(mDiff===0&&today.getDate()<dobDate.getDate()))age--;
      if(age<18){
        showT('⚠️','Věk','Pro registraci musíte být starší 18 let'); return;
      }
      if(age>99||dobDate>today){
        showT('⚠️','Datum narození','Zadejte platné datum narození'); return;
      }
      if(!pass || pass.value.length < 8){
        showT('⚠️',_t('auth').shortPass,_t('auth').minPass); return;
      }
    }

    if(regStep === 2){
      var city = document.getElementById('reg-city');
      var street = document.getElementById('reg-street');
      if(!city||!city.value.trim()||city.value.trim().length<2){
        showT('⚠️','Město','Zadejte město (min. 2 znaky)'); return;
      }
      if(!street||!street.value.trim()||street.value.trim().length<3){
        showT('⚠️','Ulice','Zadejte ulici a číslo popisné (min. 3 znaky)'); return;
      }
    }

    if(regStep < 3){
      document.getElementById('reg-step-'+regStep).classList.remove('active');
      document.getElementById('rp'+regStep).classList.remove('cur');
      document.getElementById('rp'+regStep).classList.add('done');
      regStep++;
      document.getElementById('reg-step-'+regStep).classList.add('active');
      document.getElementById('rp'+regStep).classList.add('cur');
      if(regStep === 3) document.getElementById('reg-next-btn').textContent=_t('auth').finish;
    } else {
      // Final step – validate consents and register
      doRegister();
    }
  } catch(e){ console.error('regNext error:', e); }
}

function _regResetForm(){
  regStep = 1;
  for(var i=1; i<=3; i++){
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
  var f = _collectRegFields();

  // Step 3 validation — ŘP
  if(!f.licenseNum||f.licenseNum.length<4){
    showT('⚠️','Řidičský průkaz','Číslo ŘP musí mít alespoň 4 znaky'); return;
  }
  var licExpDate=_regParseCzDate(f.licenseExpiry);
  if(!licExpDate){
    showT('⚠️','Platnost ŘP','Vyberte datum platnosti řidičského průkazu'); return;
  }
  var minExpiry=new Date();minExpiry.setHours(0,0,0,0);minExpiry.setDate(minExpiry.getDate()+14);
  if(licExpDate<minExpiry){
    showT('⚠️','Platnost ŘP','Řidičský průkaz musí být platný min. 14 dní od dnes'); return;
  }
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

  // All consents default to true (managed in profile)
  var consents = {
    marketing_consent: true,
    consent_gdpr: true,
    consent_vop: true,
    consent_data_processing: true,
    consent_email: true,
    consent_sms: true,
    consent_push: true,
    consent_whatsapp: true,
    consent_photo: true,
    consent_contract: true
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
        // Save consents + registration source to profiles table
        consents.registration_source = 'app';
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

