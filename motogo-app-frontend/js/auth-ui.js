// ===== AUTH-UI.JS – Login, Register, Logout & user data rendering =====
// Produkční verze – pouze Supabase backend, bez mock fallbacků.

// ===== HELPERS =====
function _isSupabaseReady(){
  return typeof window.supabase !== 'undefined' && window.supabase !== null && typeof authSignUp === 'function';
}

function _syncLocalSession(userId, email){
  try {
    var now = new Date();
    var exp = new Date(now.getTime() + 7*24*60*60*1000);
    localStorage.setItem('mg_current_session', JSON.stringify({
      access_token:'sb_'+userId, user_id:userId, email:email,
      created_at:now.toISOString(), expires_at:exp.toISOString()
    }));
  } catch(e){}
}

// Store biometric user data + refresh token – call after every successful auth
function _storeBioUser(userId, email, refreshToken){
  try {
    var data = {user_id: userId, email: email};
    if(refreshToken) data.refresh_token = refreshToken;
    localStorage.setItem('mg_bio_user', JSON.stringify(data));
  } catch(e){}
}

// ===== SHARED SESSION HELPER =====
async function _getSession(){
  if(_isSupabaseReady()){
    try {
      var result = await authGetSession();
      if(result && result.session) return {
        user_id: result.session.user.id,
        email: result.session.user.email,
        access_token: result.session.access_token
      };
      // JWT expired – zkus refresh
      try {
        var refreshResult = await window.supabase.auth.refreshSession();
        if(refreshResult.data && refreshResult.data.session){
          var s = refreshResult.data.session;
          _syncLocalSession(s.user.id, s.user.email);
          return {
            user_id: s.user.id,
            email: s.user.email,
            access_token: s.access_token
          };
        }
      } catch(re){ console.warn('[AUTH] refreshSession failed:', re); }
    } catch(e){ console.warn('[AUTH] getSession error:', e); }
    // Supabase is ready but session is invalid — do NOT fall back to stale localStorage
    try { localStorage.removeItem('mg_current_session'); } catch(e){}
    return null;
  }
  // Fallback: lokální session ONLY when Supabase SDK is not loaded at all
  try {
    var raw = localStorage.getItem('mg_current_session');
    if(raw){
      var local = JSON.parse(raw);
      if(local && local.user_id && local.expires_at){
        if(new Date(local.expires_at) > new Date()){
          return {
            user_id: local.user_id,
            email: local.email || '',
            access_token: local.access_token || ''
          };
        }
      }
    }
  } catch(e){}
  return null;
}

// ===== LOGIN =====
function doLogin(){
  var email = document.getElementById('login-email').value.trim();
  var pass = document.getElementById('login-pass').value;

  if(!email || !pass){
    showT('✗',_t('auth').error,_t('auth').fillEmail);
    return;
  }

  function _loginSuccess(userId, email, session){
    _syncLocalSession(userId, email);
    var refreshToken = (session && session.refresh_token) || null;
    _storeBioUser(userId, email, refreshToken);
    showT('✓',_t('auth').loginTitle,_t('auth').welcome);
    renderUserData();
    setTimeout(function(){ goTo('s-home'); }, 700);
  }

  // Supabase je jediný backend
  if(_isSupabaseReady()){
    authSignIn(email, pass).then(function(result){
      if(result.error){
        showT('✗',_t('auth').loginErr,result.error);
        return;
      }
      if(result.user) _loginSuccess(result.user.id, email, result.session);
    }).catch(function(e){
      console.error('doLogin supabase error:', e);
      showT('✗',_t('auth').error,_t('auth').loginFail);
    });
    return;
  }

  // Supabase není dostupný — zobraz offline hlášku
  OfflineGuard.check();
}

// ===== BIOMETRIC PROMPT AFTER REGISTRATION =====
function showBiometricPrompt(){
  var old=document.getElementById('bio-prompt-overlay');if(old)old.remove();
  var ov=document.createElement('div');ov.id='bio-prompt-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:20px;';document.querySelector('.phone').appendChild(ov);
  ov.innerHTML='<div style="background:#fff;border-radius:18px;padding:24px;max-width:320px;width:100%;text-align:center;">'+
    '<div style="font-size:48px;margin-bottom:12px;">🔐</div>'+
    '<div style="font-size:18px;font-weight:900;color:var(--black);margin-bottom:6px;">'+_t('auth').bioPromptTitle+'</div>'+
    '<div style="font-size:13px;color:var(--g400);margin-bottom:20px;line-height:1.5;">'+_t('auth').bioPrompt+'</div>'+
    '<button onclick="enableBiometric(true)" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;margin-bottom:8px;">'+_t('auth').bioYes+'</button>'+
    '<button onclick="enableBiometric(false)" style="width:100%;background:var(--g100);color:var(--black);border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;">'+_t('auth').bioNo+'</button>'+
    '</div>';
  ov.style.display='flex';
}
function enableBiometric(yes){
  if(yes){
    localStorage.setItem('mg_bio_enabled','1');
    // mg_bio_user is already stored from doRegister/_regSuccess
    showT('✓',_t('auth').bioOn,_t('auth').bioNext);
  }
  var ov=document.getElementById('bio-prompt-overlay');if(ov)ov.style.display='none';
  // If pending booking from scan flow, continue to booking
  if(typeof _pendingBookingAction!=='undefined' && _pendingBookingAction){
    continuePendingBooking();
  } else {
    // Show gentle doc upload hint, then go home
    setTimeout(function(){ _showDocsHint(); }, 400);
  }
}

// Gentle, informative hint to upload documents after registration
function _showDocsHint(){
  var old=document.getElementById('docs-hint-overlay');if(old)old.remove();
  var ov=document.createElement('div');ov.id='docs-hint-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;padding:20px;';document.querySelector('.phone').appendChild(ov);
  ov.innerHTML='<div style="background:#fff;border-radius:18px;padding:24px;max-width:320px;width:100%;text-align:center;">'+
    '<div style="font-size:42px;margin-bottom:10px;">🎉</div>'+
    '<div style="font-size:18px;font-weight:900;color:var(--black);margin-bottom:6px;">Registrace dokončena!</div>'+
    '<div style="font-size:13px;color:var(--g400);margin-bottom:16px;line-height:1.5;">Pro rychlejší vyřízení rezervace můžete nahrát doklady (OP a řidičák) v sekci <strong>Profil → Moje doklady</strong>.</div>'+
    '<div style="font-size:11px;color:var(--g300);margin-bottom:18px;line-height:1.4;">Není to povinné hned — doklady lze nahrát kdykoliv před první jízdou.</div>'+
    '<button onclick="_closeDocsHint()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;">Rozumím, pokračovat</button>'+
    '</div>';
  ov.style.display='flex';
}
function _closeDocsHint(){
  var ov=document.getElementById('docs-hint-overlay');if(ov)ov.style.display='none';
  goTo('s-home');
}

// ===== BIO LOGIN =====
function bioLogin(){
  try {
    var bioEnabled=localStorage.getItem('mg_bio_enabled');
    if(!bioEnabled){showT('ℹ️',_t('auth').bio,_t('auth').bioOff);return;}
    var bioUser = null;
    try { var raw = localStorage.getItem('mg_bio_user'); if(raw) bioUser = JSON.parse(raw); } catch(e){}
    if(!bioUser || !bioUser.user_id || !bioUser.email){
      showT('ℹ️',_t('auth').bio,_t('auth').bioFirst);
      return;
    }
    // Must restore a REAL Supabase session, not just a local fake token
    _bioRestoreSession(bioUser).then(function(ok){
      if(ok){
        _syncLocalSession(bioUser.user_id, bioUser.email);
        showT('🔐',_t('auth').bio,_t('auth').bioOk);
        renderUserData();
        setTimeout(function(){ goTo('s-home'); }, 1200);
      } else {
        _clearBioData();
        showT('ℹ️',_t('auth').bio,_t('auth').bioFirst);
      }
    });
  } catch(e){ console.error('bioLogin error:', e); showT('✗',_t('auth').error,_t('auth').bioFail); }
}

// Restore real Supabase session for biometric login
function _bioRestoreSession(bioUser){
  if(!_isSupabaseReady()) return Promise.resolve(false);
  // 1. Check if Supabase already has a valid session
  return window.supabase.auth.getSession().then(function(r){
    if(r.data && r.data.session && r.data.session.user){
      // Update stored refresh token
      _storeBioUser(r.data.session.user.id, r.data.session.user.email, r.data.session.refresh_token);
      return true;
    }
    // 2. Try to restore session using stored refresh token
    if(bioUser.refresh_token){
      return window.supabase.auth.refreshSession({refresh_token: bioUser.refresh_token}).then(function(ref){
        if(ref.data && ref.data.session){
          _storeBioUser(ref.data.session.user.id, ref.data.session.user.email, ref.data.session.refresh_token);
          return true;
        }
        return false;
      }).catch(function(){ return false; });
    }
    return false;
  }).catch(function(){ return false; });
}

// Clear biometric data when session can't be restored
function _clearBioData(){
  try { localStorage.removeItem('mg_bio_user'); } catch(e){}
  try { localStorage.removeItem('mg_bio_enabled'); } catch(e){}
}

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
function _regSuccess(userId, email, session){
  _syncLocalSession(userId, email);
  var refreshToken = (session && session.refresh_token) || null;
  _storeBioUser(userId, email, refreshToken);
  showT('✓',_t('auth').regDone,_t('auth').regWelcome);
  _regResetForm();
  renderUserData();
  setTimeout(function(){ showBiometricPrompt(); }, 800);
}

function doRegister(){
  // Validate consents
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
        _regSuccess(userId, f.email, result.session);
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

// ===== FORGOT PASSWORD FLOW =====
var _fpStep=1;
function showForgotPassword(){
  _fpStep=1;
  var html='<div class="reg-hdr"><div class="back-row" onclick="closeForgotPassword()"><div class="bk-c">←</div><div class="bk-l">'+_t('auth').backLogin+'</div></div>'+
    '<h2>'+_t('auth').passRecovery+'</h2></div>'+
    '<div class="bcard" style="margin:14px 20px;">'+
    '<div id="fp-step-1" class="reg-step active"><div class="reg-step-title">'+_t('auth').fpStep1Title+'</div>'+
    '<div class="reg-step-sub">'+_t('auth').fpStep1Sub+'</div>'+
    '<div class="ff"><label>'+_t('auth').email+'</label><input id="fp-email" type="email" placeholder="jan@email.cz"></div>'+
    '<button class="btn-g" onclick="fpNext()">'+_t('auth').fpSendCode+'</button></div>'+
    '<div id="fp-step-2" class="reg-step"><div class="reg-step-title">'+_t('auth').fpStep2Title+'</div>'+
    '<div class="reg-step-sub">'+_t('auth').fpStep2Sub+'</div>'+
    '<div class="ff"><label>'+_t('auth').fpCodeLabel+'</label><input id="fp-code" type="text" placeholder="123456" maxlength="6" style="letter-spacing:4px;text-align:center;font-size:20px;"></div>'+
    '<button class="btn-g" onclick="fpNext()">'+_t('auth').fpVerifyCode+'</button></div>'+
    '<div id="fp-step-3" class="reg-step"><div class="reg-step-title">'+_t('auth').fpStep3Title+'</div>'+
    '<div class="reg-step-sub">'+_t('auth').fpStep3Sub+'</div>'+
    '<div class="ff"><label>'+_t('auth').fpNewPass+'</label><input id="fp-pass1" type="password" placeholder="••••••••"></div>'+
    '<div class="ff"><label>'+_t('auth').fpRepeatPass+'</label><input id="fp-pass2" type="password" placeholder="••••••••"></div>'+
    '<button class="btn-g" onclick="fpNext()">'+_t('auth').fpSetPass+'</button></div>'+
    '</div>';
  var ov=document.getElementById('fp-overlay');
  if(!ov){ov=document.createElement('div');ov.id='fp-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:#f8f8f8;overflow-y:auto;';document.querySelector('.phone').appendChild(ov);}
  ov.innerHTML=html;ov.style.display='block';
}
function closeForgotPassword(){
  if(_fpStep>1){_fpStep--;
    document.getElementById('fp-step-'+(_fpStep+1)).classList.remove('active');
    document.getElementById('fp-step-'+_fpStep).classList.add('active');
    return;
  }
  var ov=document.getElementById('fp-overlay');if(ov)ov.style.display='none';
}
function fpNext(){
  if(_fpStep===1){
    var em=document.getElementById('fp-email');
    if(!em||!em.value.trim()||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(em.value.trim())){showT('⚠️',_t('auth').email,_t('auth').validEmail);return;}
    if(_isSupabaseReady()){
      authResetPassword(em.value.trim()).then(function(r){
        if(r.error){showT('✗',_t('auth').error,r.error);return;}
        showT('📧',_t('auth').codeSent,_t('auth').checkMail);
        document.getElementById('fp-step-'+_fpStep).classList.remove('active');
        _fpStep++;
        document.getElementById('fp-step-'+_fpStep).classList.add('active');
      });
      return;
    }
    showT('📧',_t('auth').codeSent,_t('auth').checkMail);
  } else if(_fpStep===2){
    var code=document.getElementById('fp-code');
    if(!code||code.value.trim().length<4){showT('⚠️',_t('auth').code,_t('auth').enterCode);return;}
    showT('✓',_t('auth').codeOk,_t('auth').enterNew);
  } else if(_fpStep===3){
    var p1=document.getElementById('fp-pass1'),p2=document.getElementById('fp-pass2');
    if(!p1||p1.value.length<8){showT('⚠️',_t('auth').passTitle,_t('auth').minPass);return;}
    if(p1.value!==p2.value){showT('⚠️',_t('auth').passTitle,_t('auth').passMismatch);return;}
    if(_isSupabaseReady()){
      // Supabase handles password reset via email link (step 1 already sent it)
      // The new password is set via the reset link, not here
    }
    showT('✓',_t('auth').passChanged,_t('auth').loginNow);
    var ov=document.getElementById('fp-overlay');if(ov)ov.style.display='none';
    _fpStep=1;return;
  }
  document.getElementById('fp-step-'+_fpStep).classList.remove('active');
  _fpStep++;
  document.getElementById('fp-step-'+_fpStep).classList.add('active');
}

// ===== LOGOUT =====
function doLogout(){
  try {
    if(_isSupabaseReady()){
      authSignOut().catch(function(e){ console.error('doLogout supabase:', e); });
    }
    try { localStorage.removeItem('mg_current_session'); } catch(e){}
    // Clear cart & shop state
    if(typeof clearCart==='function') clearCart(true);
    // Cleanup realtime subscriptions
    if(typeof cleanupRealtimeChannels==='function') cleanupRealtimeChannels();
    // Clear stale DOM data to prevent ghost profile after bio login
    var homeNameEl = document.getElementById('home-user-name');
    if(homeNameEl) homeNameEl.textContent = '';
    var har = document.getElementById('home-active-res');
    if(har) har.innerHTML = '';
    showT('✓',_t('auth').logoutTitle,_t('auth').logoutMsg);
    setTimeout(function(){
      goTo('s-login');
      if(typeof setupBioButton==='function') setupBioButton();
    }, 700);
  } catch(e){ console.error('doLogout error:', e); }
}

// ===== RENDER USER DATA =====
function renderUserData(){
  _renderUserDataAsync().catch(function(e){ console.error('renderUserData error:', e); });
}

function _renderUserDataAsync(){
  return Promise.resolve(apiFetchProfile()).then(function(profile){
    if(!profile){
      // Profile fetch failed — session is invalid, force redirect to login
      console.warn('[AUTH] Profile fetch failed — redirecting to login');
      try { localStorage.removeItem('mg_current_session'); } catch(e){}
      try { if(window.supabase) window.supabase.auth.signOut().catch(function(){}); } catch(e){}
      // Clear stale name from DOM
      var homeNameEl = document.getElementById('home-user-name');
      if(homeNameEl) homeNameEl.textContent = '';
      // Hide bottom nav and go to login
      var bnav = document.getElementById('bnav');
      if(bnav) bnav.style.display = 'none';
      if(typeof goTo === 'function') goTo('s-login');
      return;
    }

    // Home screen greeting
    var homeNameEl = document.getElementById('home-user-name');
    if(homeNameEl) homeNameEl.textContent = profile.full_name || 'Pilot';

    // Booking form contact details
    var bName = document.getElementById('b-contact-name');
    if(bName) bName.value = profile.full_name || '';
    var bStreet = document.getElementById('b-contact-street');
    if(bStreet) bStreet.value = profile.street || '';
    var bZip = document.getElementById('b-contact-zip');
    if(bZip) bZip.value = profile.zip || '';
    var bCity = document.getElementById('b-contact-city');
    if(bCity) bCity.value = profile.city || '';
    var bEmail = document.getElementById('b-contact-email');
    if(bEmail) bEmail.value = profile.email || '';
    var bPhone = document.getElementById('b-contact-phone');
    if(bPhone) bPhone.value = profile.phone || '';

    // Update contact collapsed preview
    var contactInitials = document.getElementById('contact-initials-box');
    var contactNamePrev = document.getElementById('contact-name-preview');
    if(contactInitials && profile.full_name){
      var parts = profile.full_name.split(' ');
      contactInitials.textContent = parts.map(function(n){return n.charAt(0).toUpperCase();}).join('');
    }
    if(contactNamePrev && profile.full_name){
      contactNamePrev.textContent = profile.full_name;
    }

    // Active loan banner on home
    return Promise.resolve(apiGetActiveLoan()).then(function(activeLoan){
      var homeActiveRes = document.getElementById('home-active-res');
      if(!homeActiveRes) return;

      if(activeLoan){
        var motoName = activeLoan.moto ? activeLoan.moto.model : 'Motorka';
        homeActiveRes.innerHTML = '<div class="ares" onclick="openResDetailById(\''+activeLoan.id+'\')">' +
          '<div style="font-size:24px;">🏍️</div>' +
          '<div><div class="ares-n">'+motoName+'</div><div class="ares-s">#'+activeLoan.id.substr(-8).toUpperCase()+' · '+_t('auth').active+'</div></div>' +
          '<div class="ares-tag">'+_t('auth').active+'</div></div>';
      } else {
        return Promise.resolve(apiFetchMyBookings('pending')).then(function(upcoming){
          if(upcoming && upcoming.length > 0){
            var nextBooking = upcoming[upcoming.length-1];
            var nextName = nextBooking.moto_name || 'Motorka';
            homeActiveRes.innerHTML = '<div class="ares" onclick="openResDetailById(\''+nextBooking.id+'\')">' +
              '<div style="font-size:24px;">📅</div>' +
              '<div><div class="ares-n">'+nextName+'</div><div class="ares-s">#'+nextBooking.id.substr(-8).toUpperCase()+' · '+_t('auth').upcoming+'</div></div>' +
              '<div class="ares-tag" style="background:rgba(59,130,246,.15);color:#1d4ed8;">'+_t('auth').ready+'</div></div>';
          } else {
            homeActiveRes.innerHTML = '<div class="ares" onclick="goTo(\'s-search\')" style="cursor:pointer;">' +
              '<div style="font-size:24px;">🏍️</div>' +
              '<div><div class="ares-n">'+_t('auth').noRes+'</div><div class="ares-s">'+_t('auth').newRes+'</div></div>' +
              '<div style="font-size:18px;color:var(--g400);">›</div></div>';
          }
        });
      }
    });
  });
}
