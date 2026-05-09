// ===== MotoGo24 Web — Rezervace: vraceji se zakaznici (login panel v kroku 3) =====
// Nezavisly modul. Pripojuje se do `MG._rezAuth.*`.
//
// Flow:
//   1) V kroku 3 (kontaktni udaje) je nahore checkbox "Uz jsem si u vas pujcoval".
//      Po zaskrtnuti se schova klasicky form a ukaze se mini-login (email+heslo+forgot).
//   2) Po uspesnem signInWithPassword nacte profil ze `profiles` + ureni doklady.
//      Predvyplni vsechny fieldy v kroku 3 (jmeno, adresa, telefon, email) a sbali
//      sekci do "Prihlasen jako: ..., Upravit udaje" baneru. Stejne pro souhlasy
//      (krok 6) a velikosti (krok 5) — sbali, predvyplni.
//   3) Pokud profile.id_number+license_number+platne validity → docs OK.
//      Nastavi MG._rez._docsValidated/_passwordSet/_licenseConfirmed/_docNumber/
//      _licenseNumber → krok 2 (Step 2 / Mindee step) preskoci sekce 1+2+3
//      (doc fields, Mindee scan, password) a ukaze jen QR + doprodej + sumarizaci.
//   4) Realtime check: pri blur na rez-email zavola check_web_booking_email RPC,
//      pokud existuje → inline hint "tento mail uz znames, prihlaste se" s tlacitkem.
//   5) create_web_booking vrati 'email_exists' pro anon+znamy mail. Submit handler
//      to zachyti a aktivuje login panel s predvyplnenym mailem.

var MG = window.MG || {};
window.MG = MG;
MG._rezAuth = MG._rezAuth || {
  user: null,
  profile: null,
  docsOk: false,
  busy: false
};

// ===== HELPER: Tx = strucna i18n s fallbackem =====
MG._rezAuth._t = function(key, fallback, vars){
  var s = (MG.t && typeof MG.t === 'function') ? MG.t(key, vars) : null;
  if(!s || s === key) s = fallback;
  if(vars && s){
    Object.keys(vars).forEach(function(k){ s = s.replace('{'+k+'}', vars[k]); });
  }
  return s;
};

// ===== HTML: Toggle panel pro krok 3 =====
// Vrati string, ktery se vlozi nahoru do <section> kroku 3 (kontaktni udaje).
MG._rezAuth.togglePanelHtml = function(){
  var T = MG._rezAuth._t;
  return ''+
  '<div id="rez-auth-toggle" class="rez-auth-toggle">'+
    '<label class="rez-auth-toggle-row">'+
      '<input type="checkbox" id="rez-auth-returning">'+
      '<div class="rez-auth-toggle-body">'+
        '<div class="rez-auth-toggle-title">'+T('rez.auth.returning.title','Už jsem si u vás půjčoval motorku')+'</div>'+
        '<div class="rez-auth-toggle-sub">'+T('rez.auth.returning.sub','Přihlas se a my všechno (kontaktní údaje, doklady, souhlasy) předvyplníme. Nemusíš nic vyplňovat znovu.')+'</div>'+
      '</div>'+
    '</label>'+
  '</div>'+
  '<div id="rez-auth-panel" class="rez-auth-panel" style="display:none">'+
    '<div id="rez-auth-login" class="rez-auth-card">'+
      '<h3 class="rez-auth-h">'+T('rez.auth.login.title','Přihlášení k vašemu účtu')+'</h3>'+
      '<p class="rez-auth-help">'+T('rez.auth.login.help','Použijte e-mail a heslo, které jste si nastavili při minulé rezervaci.')+'</p>'+
      '<form id="rez-auth-login-form" class="rez-auth-form" novalidate autocomplete="on" onsubmit="return false">'+
        '<input type="email" id="rez-auth-email" placeholder="'+T('rez.auth.email','E-mail')+'" required autocomplete="email" inputmode="email">'+
        '<input type="password" id="rez-auth-password" placeholder="'+T('rez.auth.password','Heslo')+'" required autocomplete="current-password" minlength="6">'+
        '<button type="submit" class="btn btngreen" id="rez-auth-login-btn">'+T('rez.auth.login.submit','Přihlásit se')+'</button>'+
      '</form>'+
      '<div id="rez-auth-msg" class="rez-auth-msg" style="display:none"></div>'+
      '<p class="rez-auth-forgot"><a href="#" id="rez-auth-forgot-link">'+T('rez.auth.login.forgot','Zapomenuté heslo?')+'</a></p>'+
    '</div>'+
    '<div id="rez-auth-forgot" class="rez-auth-card" style="display:none">'+
      '<h3 class="rez-auth-h">'+T('rez.auth.forgot.title','Obnovit heslo')+'</h3>'+
      '<p class="rez-auth-help">'+T('rez.auth.forgot.help','Pošleme vám e-mail s odkazem pro nastavení nového hesla. Po obnově se sem vraťte a přihlaste.')+'</p>'+
      '<form id="rez-auth-forgot-form" class="rez-auth-form" novalidate onsubmit="return false">'+
        '<input type="email" id="rez-auth-forgot-email" placeholder="'+T('rez.auth.email','E-mail')+'" required autocomplete="email" inputmode="email">'+
        '<button type="submit" class="btn btngreen" id="rez-auth-forgot-btn">'+T('rez.auth.forgot.submit','Odeslat odkaz')+'</button>'+
      '</form>'+
      '<div id="rez-auth-forgot-msg" class="rez-auth-msg" style="display:none"></div>'+
      '<p class="rez-auth-forgot"><a href="#" id="rez-auth-forgot-back">'+T('rez.auth.forgot.back','Zpět na přihlášení')+'</a></p>'+
    '</div>'+
  '</div>'+
  '<div id="rez-auth-loggedin" class="rez-auth-loggedin" style="display:none">'+
    '<div class="rez-auth-loggedin-icon">&#10004;</div>'+
    '<div class="rez-auth-loggedin-body">'+
      '<div class="rez-auth-loggedin-title"></div>'+
      '<div class="rez-auth-loggedin-sub"></div>'+
    '</div>'+
    '<button type="button" class="btn btngreen-small" id="rez-auth-edit-btn">'+T('rez.auth.edit','Upravit údaje')+'</button>'+
    '<button type="button" class="rez-auth-logout" id="rez-auth-logout-btn" title="'+T('rez.auth.logout','Odhlásit')+'">&times;</button>'+
  '</div>';
};

// ===== INIT po vlozeni formu do DOM =====
MG._rezAuth.init = function(){
  var toggle = document.getElementById('rez-auth-returning');
  if(!toggle) return; // panel neexistuje (jiny krok)

  toggle.addEventListener('change', function(){
    var p = document.getElementById('rez-auth-panel');
    if(p) p.style.display = this.checked ? 'block' : 'none';
    if(this.checked){
      var em = document.getElementById('rez-auth-email');
      if(em){
        var pre = (document.getElementById('rez-email')||{}).value;
        if(pre && !em.value) em.value = pre;
        try { em.focus(); } catch(e){}
      }
    }
  });

  var loginForm = document.getElementById('rez-auth-login-form');
  if(loginForm) loginForm.addEventListener('submit', MG._rezAuth._submitLogin);

  var forgotLink = document.getElementById('rez-auth-forgot-link');
  if(forgotLink) forgotLink.addEventListener('click', function(e){
    e.preventDefault();
    document.getElementById('rez-auth-login').style.display = 'none';
    document.getElementById('rez-auth-forgot').style.display = 'block';
    var em = document.getElementById('rez-auth-forgot-email');
    var src = document.getElementById('rez-auth-email');
    if(em && src && src.value) em.value = src.value;
  });

  var forgotBack = document.getElementById('rez-auth-forgot-back');
  if(forgotBack) forgotBack.addEventListener('click', function(e){
    e.preventDefault();
    document.getElementById('rez-auth-forgot').style.display = 'none';
    document.getElementById('rez-auth-login').style.display = 'block';
  });

  var forgotForm = document.getElementById('rez-auth-forgot-form');
  if(forgotForm) forgotForm.addEventListener('submit', MG._rezAuth._submitForgot);

  var editBtn = document.getElementById('rez-auth-edit-btn');
  if(editBtn) editBtn.addEventListener('click', MG._rezAuth._expandFields);

  var logoutBtn = document.getElementById('rez-auth-logout-btn');
  if(logoutBtn) logoutBtn.addEventListener('click', MG._rezAuth._logout);

  // Real-time email check (blur)
  var emailInput = document.getElementById('rez-email');
  if(emailInput){
    emailInput.addEventListener('blur', MG._rezAuth._checkEmailExists);
  }

  // Auto-detekce existujici session — kdyz prijde uzivatel uz prihlaseny
  // (napr. po reset hesla nebo prepnuti z editaci rezervace).
  MG._rezAuth._restoreSession();
};

// ===== LOGIN submit =====
MG._rezAuth._submitLogin = async function(e){
  if(e && e.preventDefault) e.preventDefault();
  if(MG._rezAuth.busy) return;
  var T = MG._rezAuth._t;
  var email = (document.getElementById('rez-auth-email')||{}).value;
  var pwd = (document.getElementById('rez-auth-password')||{}).value;
  if(!email || !pwd){
    MG._rezAuth._showMsg(T('rez.auth.err.empty','Vyplňte e-mail i heslo.'), 'err'); return;
  }
  var btn = document.getElementById('rez-auth-login-btn');
  var orig = btn ? btn.textContent : '';
  if(btn){ btn.disabled = true; btn.textContent = T('rez.auth.login.submitting','Přihlašuji…'); }
  MG._rezAuth.busy = true;
  try {
    var res = await window.sb.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password: pwd
    });
    if(res.error || !res.data || !res.data.user){
      var msg = T('rez.auth.err.login','Přihlášení selhalo. Zkontrolujte e-mail a heslo.');
      MG._rezAuth._showMsg(msg, 'err');
      return;
    }
    MG._rezAuth.user = res.data.user;
    await MG._rezAuth._afterLogin();
  } catch(err){
    console.error('[rezAuth] login err', err);
    MG._rezAuth._showMsg(T('rez.auth.err.server','Server je nedostupný, zkuste to prosím za chvíli.'), 'err');
  } finally {
    MG._rezAuth.busy = false;
    if(btn){ btn.disabled = false; btn.textContent = orig; }
  }
};

// ===== FORGOT submit =====
MG._rezAuth._submitForgot = async function(e){
  if(e && e.preventDefault) e.preventDefault();
  if(MG._rezAuth.busy) return;
  var T = MG._rezAuth._t;
  var email = (document.getElementById('rez-auth-forgot-email')||{}).value;
  if(!email){
    MG._rezAuth._showMsg(T('rez.auth.err.empty','Vyplňte e-mail.'), 'err', 'rez-auth-forgot-msg'); return;
  }
  var btn = document.getElementById('rez-auth-forgot-btn');
  var orig = btn ? btn.textContent : '';
  if(btn){ btn.disabled = true; btn.textContent = T('rez.auth.forgot.submitting','Odesílám…'); }
  MG._rezAuth.busy = true;
  try {
    // Odkaz vede na stranku /upravit-rezervaci — tam uz je hotovy reset flow
    var redirectTo = window.location.origin + '/upravit-rezervaci';
    var res = await window.sb.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
      redirectTo: redirectTo
    });
    if(res.error){
      console.error('[rezAuth] forgot err', res.error);
      MG._rezAuth._showMsg(T('rez.auth.err.forgot','Odeslání selhalo. Zkuste to prosím znovu.'), 'err', 'rez-auth-forgot-msg');
      return;
    }
    MG._rezAuth._showMsg(T('rez.auth.forgot.sent','E-mail s odkazem byl odeslán. Zkontrolujte schránku (i spam) a po obnově se vraťte sem.'), 'ok', 'rez-auth-forgot-msg');
  } catch(err){
    console.error('[rezAuth] forgot exception', err);
    MG._rezAuth._showMsg(T('rez.auth.err.server','Server je nedostupný.'), 'err', 'rez-auth-forgot-msg');
  } finally {
    MG._rezAuth.busy = false;
    if(btn){ btn.disabled = false; btn.textContent = orig; }
  }
};

// ===== Po prihlaseni — nacti profil + prefill =====
MG._rezAuth._afterLogin = async function(){
  if(!MG._rezAuth.user) return;
  var T = MG._rezAuth._t;
  // Nacti profil
  try {
    var res = await window.sb
      .from('profiles')
      .select('id, full_name, email, phone, street, city, zip, country, license_group, license_number, license_expiry, id_number, id_verified_until, license_verified_until, gear_sizes, consent_gdpr, consent_vop, consent_marketing, consent_email, consent_photo')
      .eq('id', MG._rezAuth.user.id)
      .maybeSingle();
    if(res.error){
      console.warn('[rezAuth] profile fetch err', res.error);
    }
    MG._rezAuth.profile = (res && res.data) || null;
  } catch(e){ console.warn('[rezAuth] profile fetch exception', e); }

  // Nastavi flagy + naplni form
  MG._rezAuth._applyToForm();
  // Skryj toggle/login form, zobraz "Prihlasen jako" baner
  var p = document.getElementById('rez-auth-panel');
  if(p) p.style.display = 'none';
  var t = document.getElementById('rez-auth-toggle');
  if(t) t.style.display = 'none';
  var li = document.getElementById('rez-auth-loggedin');
  if(li){
    li.style.display = 'flex';
    var prof = MG._rezAuth.profile || {};
    var nm = prof.full_name || (MG._rezAuth.user.email);
    var titEl = li.querySelector('.rez-auth-loggedin-title');
    var subEl = li.querySelector('.rez-auth-loggedin-sub');
    if(titEl) titEl.textContent = T('rez.auth.loggedin.title','Přihlášen jako {name}', {name: nm});
    if(subEl){
      var docsTxt = MG._rezAuth.docsOk
        ? T('rez.auth.loggedin.docsOk','Doklady jsou ověřené, formulář předvyplněný.')
        : T('rez.auth.loggedin.docsMissing','Po pokračování ještě jednou ověříme doklady.');
      subEl.textContent = docsTxt;
    }
  }
  // Sbal sekce 5 (vybava) + 6 (souhlasy) — automaticky predvyplneno
  MG._rezAuth._collapseSection('rez-step-num-5');
  MG._rezAuth._collapseSection('rez-step-num-6');
};

// ===== Aplikuj profil do form fields + nastavi MG._rez flagy =====
MG._rezAuth._applyToForm = function(){
  var prof = MG._rezAuth.profile;
  if(!prof) return;
  var setVal = function(id, v){
    var el = document.getElementById(id);
    if(el && v != null && v !== '') el.value = v;
  };
  setVal('rez-name', prof.full_name);
  setVal('rez-email', prof.email);
  setVal('rez-phone', prof.phone);
  setVal('rez-street', prof.street);
  setVal('rez-city', prof.city);
  setVal('rez-zip', prof.zip);
  setVal('rez-country', prof.country);

  // Velikosti vybavy → MG._rez.sizes (pokud profile.gear_sizes jsou ulozene)
  if(prof.gear_sizes && typeof prof.gear_sizes === 'object'){
    MG._rez = MG._rez || {};
    MG._rez.sizes = MG._rez.sizes || { rider:{}, passenger:{} };
    var gs = prof.gear_sizes;
    if(gs.rider){ Object.assign(MG._rez.sizes.rider, gs.rider); }
    if(gs.passenger){ Object.assign(MG._rez.sizes.passenger, gs.passenger); }
    // Pokud renderer velikosti existuje — refresh chip stavy
    if(typeof MG._rezRefreshGearSizeChips === 'function'){
      try { MG._rezRefreshGearSizeChips(); } catch(e){}
    }
  }

  // Doklady — over platnost vuci aktualnimu end_date rezervace
  var endDate = MG._rez && MG._rez.endDate ? new Date(MG._rez.endDate) : null;
  var hasIdDoc = !!prof.id_number;
  var hasLic = !!prof.license_number;
  var licValid = !prof.license_expiry || (endDate && new Date(prof.license_expiry) >= endDate) || !endDate;
  var licVerifiedValid = prof.license_verified_until
    ? (endDate ? new Date(prof.license_verified_until) >= endDate : true)
    : true;
  var idVerifiedValid = prof.id_verified_until
    ? (endDate ? new Date(prof.id_verified_until) >= endDate : true)
    : true;
  MG._rezAuth.docsOk = hasIdDoc && hasLic && licValid && licVerifiedValid && idVerifiedValid;

  if(MG._rezAuth.docsOk){
    // Predvyplni vsechny flagy v MG._rez, ktere step 2 (Mindee) pouziva pro skip
    MG._rez = MG._rez || {};
    MG._rez._docsValidated = true;
    MG._rez._passwordSet = true;
    MG._rez._licenseConfirmed = true;
    MG._rez._docNumber = prof.id_number || '';
    MG._rez._licenseNumber = prof.license_number || '';
    if(MG._rez.formData){
      MG._rez.formData._licGroup = (prof.license_group && prof.license_group[0]) || null;
      MG._rez.formData._licExpiry = prof.license_expiry || null;
    } else {
      // formData se vytvari pri submit; ulozime si do _prefill
      MG._rez._prefillLicGroup = (prof.license_group && prof.license_group[0]) || null;
      MG._rez._prefillLicExpiry = prof.license_expiry || null;
    }
  }

  // Soucasna sezona/auth: pokud uziatel jiz pristupil pres "Pokracovat" a backend
  // hodil email_exists, pak se po loginu hned posle volani znova — handler v
  // _submitReservation to zachyti.
};

// ===== Skryt sekci formulare a ukazat "predvyplneno, upravit" tip =====
MG._rezAuth._collapseSection = function(/*placeholder pro budoucnost*/){
  // V tuto chvili necechame DOM pozmenit — fields zustanou viditelne, ale
  // predvyplnene. Zakaznik je vidi a muze je upravit. (V dalsi iteraci muzeme
  // pridat collapse animaci.)
};

// ===== Edit fields tlacitko =====
MG._rezAuth._expandFields = function(){
  // Sbal-li jsme nejake sekce, znovu ukaz. (Aktualne nesbalujeme, takze no-op.)
  // Hlavni efekt: focus na prvni input.
  var nm = document.getElementById('rez-name');
  if(nm){ try { nm.focus(); nm.scrollIntoView({behavior:'smooth', block:'center'}); } catch(e){} }
};

// ===== Logout — vraci form do puvodniho stavu =====
MG._rezAuth._logout = async function(){
  try { await window.sb.auth.signOut(); } catch(e){}
  MG._rezAuth.user = null;
  MG._rezAuth.profile = null;
  MG._rezAuth.docsOk = false;
  // Reset MG._rez flagy
  if(MG._rez){
    MG._rez._docsValidated = false;
    MG._rez._passwordSet = false;
    MG._rez._licenseConfirmed = false;
    MG._rez._docNumber = null;
    MG._rez._licenseNumber = null;
  }
  // UI reset
  var li = document.getElementById('rez-auth-loggedin');
  if(li) li.style.display = 'none';
  var t = document.getElementById('rez-auth-toggle');
  if(t) t.style.display = 'block';
  var toggle = document.getElementById('rez-auth-returning');
  if(toggle) toggle.checked = false;
  var p = document.getElementById('rez-auth-panel');
  if(p) p.style.display = 'none';
};

// ===== Restore session =====
MG._rezAuth._restoreSession = async function(){
  try {
    var res = await window.sb.auth.getUser();
    if(res && res.data && res.data.user){
      MG._rezAuth.user = res.data.user;
      // Pokud jiz prihlasen, ukaz banner + prefill
      await MG._rezAuth._afterLogin();
    }
  } catch(e){}
};

// ===== Real-time email check (blur na rez-email) =====
MG._rezAuth._checkEmailExists = async function(e){
  var email = e && e.target ? e.target.value : '';
  if(!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())){
    MG._rezAuth._hideEmailHint();
    return;
  }
  // Pokud uzivatel prave prihlasen, neukazuj hint pro vlastni mail
  if(MG._rezAuth.user && MG._rezAuth.user.email
     && MG._rezAuth.user.email.toLowerCase() === email.trim().toLowerCase()){
    MG._rezAuth._hideEmailHint(); return;
  }
  try {
    var res = await window.sb.rpc('check_web_booking_email', { p_email: email.trim() });
    if(res && res.data && res.data.exists){
      MG._rezAuth._showEmailHint(email.trim());
    } else {
      MG._rezAuth._hideEmailHint();
    }
  } catch(err){
    console.warn('[rezAuth] check email err', err);
  }
};

MG._rezAuth._showEmailHint = function(email){
  var T = MG._rezAuth._t;
  var hint = document.getElementById('rez-auth-email-hint');
  if(!hint){
    hint = document.createElement('div');
    hint.id = 'rez-auth-email-hint';
    hint.className = 'rez-auth-email-hint';
    var emInput = document.getElementById('rez-email');
    if(emInput && emInput.parentNode){
      emInput.parentNode.insertBefore(hint, emInput.nextSibling);
    }
  }
  hint.innerHTML =
    '<strong>'+T('rez.auth.exists.title','Tento e-mail u nás už máme.')+'</strong> '+
    T('rez.auth.exists.body','Pokračujte přihlášením, ať vám předvyplníme údaje a nemusíte vyplňovat doklady znovu.')+
    ' <button type="button" class="btn btngreen-small" id="rez-auth-exists-btn">'+T('rez.auth.exists.btn','Přihlásit se')+'</button>';
  hint.style.display = 'block';
  var btn = document.getElementById('rez-auth-exists-btn');
  if(btn) btn.addEventListener('click', function(){
    MG._rezAuth._activateLoginPanel(email);
  });
};

MG._rezAuth._hideEmailHint = function(){
  var hint = document.getElementById('rez-auth-email-hint');
  if(hint) hint.style.display = 'none';
};

// ===== Aktivace login panelu zvenku (po hint kliku NEBO email_exists chybe) =====
MG._rezAuth._activateLoginPanel = function(prefillEmail){
  var toggle = document.getElementById('rez-auth-returning');
  if(toggle){
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change'));
  }
  var em = document.getElementById('rez-auth-email');
  if(em && prefillEmail) em.value = prefillEmail;
  // Scroll k panelu
  var p = document.getElementById('rez-auth-panel');
  if(p){ try { p.scrollIntoView({behavior:'smooth', block:'center'}); } catch(e){} }
  // Focus na heslo (mail uz mame)
  setTimeout(function(){
    var pwd = document.getElementById('rez-auth-password');
    if(pwd) try { pwd.focus(); } catch(e){}
  }, 250);
};

// ===== Show msg in panel =====
MG._rezAuth._showMsg = function(text, type, targetId){
  var el = document.getElementById(targetId || 'rez-auth-msg');
  if(!el) return;
  el.textContent = text;
  el.className = 'rez-auth-msg rez-auth-msg-'+(type==='ok'?'ok':'err');
  el.style.display = 'block';
};
