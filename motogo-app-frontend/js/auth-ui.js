// ===== AUTH-UI.JS – Helpers, Login & Biometric =====
// Produkční verze – pouze Supabase backend, bez mock fallbacků.
// Split: auth-register.js (registrace), auth-session.js (forgot password, logout, render)

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
