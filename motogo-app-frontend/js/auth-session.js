// ===== AUTH-SESSION.JS – Forgot password, Logout & Render user data =====
// Split from auth-ui.js. Depends on: auth-ui.js (helpers)

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

      // Safeguard: ověř že booking reálně začal (ochrana proti špatnému statusu v DB)
      if(activeLoan && typeof _hasBookingStarted==='function' && !_hasBookingStarted(activeLoan)){
        console.warn('[HOME] apiGetActiveLoan vrátil booking co ještě nezačal:', activeLoan.id, 'start_date:', activeLoan.start_date);
        activeLoan._isUpcoming = true;
      }

      if(activeLoan && !activeLoan._isUpcoming){
        var motoName = activeLoan.moto ? activeLoan.moto.model : 'Motorka';
        var isPast = activeLoan._pastEndTime;
        var icon = isPast ? '\u23f0' : '\ud83c\udfcd\ufe0f';
        var label = isPast ? 'K vr\u00e1cen\u00ed' : _t('auth').active;
        var tagStyle = isPast ? 'background:rgba(239,68,68,.15);color:#b91c1c;' : '';
        homeActiveRes.innerHTML = '<div class="ares" onclick="openResDetailById(\''+activeLoan.id+'\')">' +
          '<div style="font-size:24px;">'+icon+'</div>' +
          '<div><div class="ares-n">'+motoName+'</div><div class="ares-s">#'+activeLoan.id.substr(-8).toUpperCase()+' \u00b7 '+label+'</div></div>' +
          '<div class="ares-tag" style="'+tagStyle+'">'+label+'</div></div>';
      } else {
        // Pokud apiGetActiveLoan vrátil upcoming booking, použij ho; jinak fetch pending
        var upcomingPromise = (activeLoan && activeLoan._isUpcoming)
          ? Promise.resolve([activeLoan])
          : Promise.resolve(apiFetchMyBookings('pending'));
        return upcomingPromise.then(function(upcoming){
          if(upcoming && upcoming.length > 0){
            var nextBooking = (upcoming.length === 1 && upcoming[0]._isUpcoming) ? upcoming[0] : upcoming[upcoming.length-1];
            var nextName = nextBooking.moto_name || (nextBooking.moto ? nextBooking.moto.model : 'Motorka');
            homeActiveRes.innerHTML = '<div class="ares" onclick="openResDetailById(\''+nextBooking.id+'\')">' +
              '<div style="font-size:24px;">\ud83d\udcc5</div>' +
              '<div><div class="ares-n">'+nextName+'</div><div class="ares-s">#'+nextBooking.id.substr(-8).toUpperCase()+' \u00b7 '+_t('auth').upcoming+'</div></div>' +
              '<div class="ares-tag" style="background:rgba(59,130,246,.15);color:#1d4ed8;">'+_t('auth').ready+'</div></div>';
          } else {
            homeActiveRes.innerHTML = '<div class="ares" onclick="goTo(\'s-search\')" style="cursor:pointer;">' +
              '<div style="font-size:24px;">\ud83c\udfcd\ufe0f</div>' +
              '<div><div class="ares-n">'+_t('auth').noRes+'</div><div class="ares-s">'+_t('auth').newRes+'</div></div>' +
              '<div style="font-size:18px;color:var(--g400);">\u203a</div></div>';
          }
        });
      }
    });
  });
}
