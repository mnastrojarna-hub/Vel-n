// ===== MotoGo24 Web — Stránka „Upravit rezervaci" =====
// Klient-side flow: login (Supabase Auth) → seznam rezervací → detail s taby
// (Detail / Prodloužit / Zkrátit / Storno). RLS chrání bookings, takže každý
// přihlášený zákazník vidí jen své vlastní záznamy.
//
// Závislosti:
//   - window.sb (Supabase JS client) ze supabase-init.js
//   - MG.* helpery (formatPrice, calcPrice, formatDate) z api.js
//   - window.MG_I18N (sype PHP server-side)

var MG = window.MG || {};
window.MG = MG;

// i18n helper s {placeholder} substitucí. Pokud klíč chybí v aktuálním jazyce,
// PHP fallback chain (jazyk → cs) zajistí alespoň český text místo prázdna.
MG.t = MG.t || function(key, params){
  var dict = window.MG_I18N || {};
  var s = (typeof dict[key] === 'string') ? dict[key] : key;
  if (params && typeof s === 'string'){
    Object.keys(params).forEach(function(p){
      s = s.split('{'+p+'}').join(String(params[p]));
    });
  }
  return s;
};

// State pro celý flow upravit-rezervaci.
MG._editRez = {
  view: 'login',        // 'login' | 'forgot' | 'reset' | 'list' | 'detail'
  user: null,           // auth user
  bookings: [],         // všechny bookings zákazníka (full historie)
  shopOrders: [],       // e-shop objednávky zákazníka
  vouchers: [],         // dárkové poukazy zákazníka
  filter: 'all',        // 'all' | 'active' | 'upcoming' | 'completed' | 'cancelled'
  selectedBooking: null,
  selectedMoto: null,
  occupied: [],         // bookings z jiných rezervací stejné motorky
  tab: 'detail',        // 'detail' | 'extend' | 'shorten' | 'moto' | 'location' | 'docs' | 'cancel'
  busy: false
};

// ===== HELPERS =====

// Datum YYYY-MM-DD <-> Date
MG._editRez._toIsoDate = function(d){
  if (!d) return null;
  if (typeof d === 'string') return d.length >= 10 ? d.substring(0,10) : null;
  var y = d.getFullYear();
  var m = String(d.getMonth()+1).padStart(2,'0');
  var dd = String(d.getDate()).padStart(2,'0');
  return y+'-'+m+'-'+dd;
};

MG._editRez._daysBetween = function(start, end){
  var s = new Date(start), e = new Date(end);
  return Math.floor((e - s) / 86400000) + 1; // inclusive
};

// Hodiny do daného data (pro výpočet refund %)
MG._editRez._hoursUntil = function(targetDate){
  var t = new Date(targetDate).getTime();
  return (t - Date.now()) / 3600000;
};

// Storno % shodné s Flutter app (StornoCalc):
//   ≥ 168h → 100 %, ≥ 48h → 50 %, jinak 0 %
MG._editRez._refundPercent = function(targetDate){
  var h = MG._editRez._hoursUntil(targetDate);
  if (h >= 168) return 100;
  if (h >= 48)  return 50;
  return 0;
};

MG._editRez._statusLabel = function(status){
  return MG.t('editRez.status.' + status, {});
};

MG._editRez._showError = function(msg){
  // Lehký inline error box. Nepoužívám alert(), ať neničíme UX.
  var el = document.getElementById('edit-rez-error');
  if (!el) return;
  el.textContent = msg || MG.t('editRez.err.generic');
  el.style.display = 'block';
  setTimeout(function(){ el.style.display = 'none'; }, 6000);
};

MG._editRez._setBusy = function(b){
  MG._editRez.busy = b;
  var app = document.getElementById('edit-rez-app');
  if (!app) return;
  app.classList.toggle('busy', !!b);
};

// Render shell — header s logout + error box + content area, zachovat při view-switchu.
MG._editRez._renderShell = function(){
  var app = document.getElementById('edit-rez-app');
  if (!app) return;
  var user = MG._editRez.user;
  var logoutHtml = user
    ? '<div class="edit-rez-userbar"><span>' + (user.email || '') + '</span>'
      + '<button type="button" class="btn-link" id="edit-rez-logout">' + MG.t('editRez.logout') + '</button></div>'
    : '';
  app.innerHTML =
    '<h1>' + MG.t('editRez.h1') + '</h1>' +
    '<p class="edit-rez-intro">' + MG.t('editRez.intro') + '</p>' +
    logoutHtml +
    '<div id="edit-rez-error" class="edit-rez-error" style="display:none" role="alert" aria-live="assertive"></div>' +
    '<div id="edit-rez-content"></div>';

  if (user){
    var lo = document.getElementById('edit-rez-logout');
    if (lo) lo.addEventListener('click', MG._editRez._logout);
  }
};

// ===== ROUTER (interní view switching, žádné URL hash) =====
MG._editRez._goto = function(view){
  MG._editRez.view = view;
  if (view === 'login')   return MG._editRez._renderLogin();
  if (view === 'forgot')  return MG._editRez._renderForgot();
  if (view === 'reset')   return MG._editRez._renderReset();
  if (view === 'list')    return MG._editRez._renderList();
  if (view === 'detail')  return MG._editRez._renderDetail();
};

// ===== RESET PASSWORD (po kliku na reset link z e-mailu) =====
// Supabase přidá do URL hashe `#access_token=...&type=recovery` a knihovna
// auto-vystaví session. Detekujeme to v init() a zobrazíme set-password form.
MG._editRez._renderReset = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  c.innerHTML =
    '<section class="edit-rez-card">' +
    '<h2>' + MG.t('editRez.reset.title') + '</h2>' +
    '<p>' + MG.t('editRez.reset.help') + '</p>' +
    '<form id="edit-rez-reset-form" class="edit-rez-form" novalidate>' +
      '<label>' + MG.t('editRez.reset.password') +
        '<input type="password" name="password" required autocomplete="new-password" minlength="8">' +
      '</label>' +
      '<label>' + MG.t('editRez.reset.password2') +
        '<input type="password" name="password2" required autocomplete="new-password" minlength="8">' +
      '</label>' +
      '<button type="submit" class="btn btngreen">' + MG.t('editRez.reset.submit') + '</button>' +
    '</form>' +
    '</section>';
  document.getElementById('edit-rez-reset-form').addEventListener('submit', MG._editRez._submitReset);
};

MG._editRez._submitReset = async function(e){
  e.preventDefault();
  if (MG._editRez.busy) return;
  var f = e.currentTarget;
  var btn = f.querySelector('button[type=submit]');
  var origLabel = btn.textContent;
  var pw = f.password.value;
  var pw2 = f.password2.value;
  if (!pw || pw.length < 8){
    MG._editRez._showError(MG.t('editRez.reset.tooShort'));
    return;
  }
  if (pw !== pw2){
    MG._editRez._showError(MG.t('editRez.reset.mismatch'));
    return;
  }
  MG._editRez._setBusy(true);
  btn.disabled = true;
  btn.textContent = MG.t('editRez.reset.submitting');
  try {
    var res = await window.sb.auth.updateUser({ password: pw });
    if (res.error){
      console.error('[editRez] reset err', res.error);
      MG._editRez._showError(MG.t('editRez.reset.error'));
      return;
    }
    // Po úspěšném resetu vyčistíme hash z URL (token už nepotřebujeme)
    // a zobrazíme list rezervací — uživatel je v té chvíli již přihlášen.
    if (window.history && window.history.replaceState){
      window.history.replaceState(null, '', window.location.pathname);
    }
    var sess = await window.sb.auth.getSession();
    if (sess && sess.data && sess.data.session && sess.data.session.user){
      MG._editRez.user = sess.data.session.user;
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
    } else {
      MG._editRez._goto('login');
    }
  } catch(err){
    console.error('[editRez] reset exception', err);
    MG._editRez._showError(MG.t('editRez.reset.error'));
  } finally {
    MG._editRez._setBusy(false);
    btn.disabled = false;
    btn.textContent = origLabel;
  }
};

// ===== LOGIN =====
MG._editRez._renderLogin = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  c.innerHTML =
    '<section class="edit-rez-card">' +
    '<h2>' + MG.t('editRez.login.title') + '</h2>' +
    '<p>' + MG.t('editRez.login.help') + '</p>' +
    '<form id="edit-rez-login-form" class="edit-rez-form" novalidate autocomplete="on">' +
      '<label>' + MG.t('editRez.login.email') +
        '<input type="email" name="email" required autocomplete="email" inputmode="email">' +
      '</label>' +
      '<label>' + MG.t('editRez.login.password') +
        '<input type="password" name="password" required autocomplete="current-password" minlength="6">' +
      '</label>' +
      '<button type="submit" class="btn btngreen">' + MG.t('editRez.login.submit') + '</button>' +
    '</form>' +
    '<p class="edit-rez-tip">' + MG.t('editRez.login.tip') + '</p>' +
    '<p><a href="#" id="edit-rez-forgot-link">' + MG.t('editRez.login.forgot') + '</a></p>' +
    '</section>';

  document.getElementById('edit-rez-forgot-link').addEventListener('click', function(e){
    e.preventDefault();
    MG._editRez._goto('forgot');
  });
  document.getElementById('edit-rez-login-form').addEventListener('submit', MG._editRez._submitLogin);
};

MG._editRez._submitLogin = async function(e){
  e.preventDefault();
  if (MG._editRez.busy) return;
  var f = e.currentTarget;
  var btn = f.querySelector('button[type=submit]');
  var origLabel = btn.textContent;
  var email = f.email.value.trim().toLowerCase();
  var password = f.password.value;

  if (!email || !password){
    MG._editRez._showError(MG.t('editRez.login.error'));
    return;
  }

  MG._editRez._setBusy(true);
  btn.disabled = true;
  btn.textContent = MG.t('editRez.login.submitting');
  try {
    var res = await window.sb.auth.signInWithPassword({ email: email, password: password });
    if (res.error || !res.data || !res.data.user){
      console.error('[editRez] login err', res.error);
      // Rozlišíme typy chyb pro user-friendly zprávu.
      var msg = MG.t('editRez.login.error');
      var status = res.error && res.error.status;
      if (status === 500 || status >= 500){
        msg = MG.t('editRez.err.serverDown');
      } else if (res.error && /confirm|verified/i.test(res.error.message || '')){
        msg = MG.t('editRez.err.emailNotConfirmed');
      }
      MG._editRez._showError(msg);
      return;
    }
    MG._editRez.user = res.data.user;
    await MG._editRez._loadBookings();
    MG._editRez._goto('list');
  } catch(err){
    console.error('[editRez] login err', err);
    MG._editRez._showError(MG.t('editRez.err.serverDown'));
  } finally {
    MG._editRez._setBusy(false);
    btn.disabled = false;
    btn.textContent = origLabel;
  }
};

MG._editRez._logout = async function(){
  try { await window.sb.auth.signOut(); } catch(e){}
  MG._editRez.user = null;
  MG._editRez.bookings = [];
  MG._editRez.selectedBooking = null;
  MG._editRez._goto('login');
};

// ===== FORGOT PASSWORD =====
// Volá Supabase Auth resetPasswordForEmail. Booking ID slouží jako bonus
// kontrola na klientu (pokud je vyplněn, ověříme že email v rezervaci sedí —
// jinak prostě pošleme reset jako u standardního password reset flow).
MG._editRez._renderForgot = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  c.innerHTML =
    '<section class="edit-rez-card">' +
    '<h2>' + MG.t('editRez.forgot.title') + '</h2>' +
    '<p>' + MG.t('editRez.forgot.help') + '</p>' +
    '<form id="edit-rez-forgot-form" class="edit-rez-form" novalidate>' +
      '<label>' + MG.t('editRez.forgot.bookingId') +
        '<input type="text" name="bookingId" autocomplete="off" inputmode="text">' +
      '</label>' +
      '<label>' + MG.t('editRez.forgot.email') +
        '<input type="email" name="email" required autocomplete="email" inputmode="email">' +
      '</label>' +
      '<button type="submit" class="btn btngreen">' + MG.t('editRez.forgot.submit') + '</button>' +
    '</form>' +
    '<p><a href="#" id="edit-rez-back-login">' + MG.t('editRez.forgot.back') + '</a></p>' +
    '</section>';

  document.getElementById('edit-rez-back-login').addEventListener('click', function(e){
    e.preventDefault();
    MG._editRez._goto('login');
  });
  document.getElementById('edit-rez-forgot-form').addEventListener('submit', MG._editRez._submitForgot);
};

MG._editRez._submitForgot = async function(e){
  e.preventDefault();
  if (MG._editRez.busy) return;
  var f = e.currentTarget;
  var btn = f.querySelector('button[type=submit]');
  var origLabel = btn.textContent;
  var email = f.email.value.trim().toLowerCase();
  if (!email){ MG._editRez._showError(MG.t('editRez.forgot.error')); return; }

  MG._editRez._setBusy(true);
  btn.disabled = true;
  btn.textContent = MG.t('editRez.forgot.submitting');
  try {
    // Supabase v aktuální verzi posílá místo magic linku 8-znakový OTP kód
    // (alfanumerický, expires 1h). Stejný flow jako mobilní app.
    // resetPasswordForEmail spustí Reset Password e-mail s `{{ .Token }}` placeholderem.
    var res = await window.sb.auth.resetPasswordForEmail(email);
    if (res.error){
      console.warn('[editRez] resetPassword err', res.error);
      var st = res.error.status;
      if (st === 500 || st >= 500){
        MG._editRez._showError(MG.t('editRez.err.serverDown'));
        return;
      }
      // 4xx — generický success (anti-enumeration).
    }
    // Email byl odeslán — zobrazíme OTP formulář (zadej kód + nové heslo).
    MG._editRez._renderOtpReset(email);
  } catch(err){
    console.error('[editRez] forgot err', err);
    MG._editRez._showError(MG.t('editRez.forgot.error'));
  } finally {
    MG._editRez._setBusy(false);
    btn.disabled = false;
    btn.textContent = origLabel;
  }
};

// ===== OTP RESET (verifyOtp + updateUser) — 1:1 jako mobilní app =====
// Po `resetPasswordForEmail` zákazník dostane email s 8-znakovým OTP.
// Tady ho zadá spolu s novým heslem. verifyOtp vystaví session,
// updateUser nastaví nové heslo. Po úspěchu je rovnou přihlášen do listu.
MG._editRez._renderOtpReset = function(email){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  c.innerHTML =
    '<section class="edit-rez-card">' +
    '<h2>' + MG.t('editRez.reset.title') + '</h2>' +
    '<p>' + MG.t('editRez.reset.otpHelp', { email: email }) + '</p>' +
    '<form id="edit-rez-otp-form" class="edit-rez-form" novalidate>' +
      '<label>' + MG.t('editRez.reset.otpCode') +
        '<input type="text" name="otp" required autocomplete="one-time-code" inputmode="numeric" maxlength="10" pattern="[0-9A-Za-z]+" style="letter-spacing:.4em;font-size:1.6rem;font-weight:700;text-align:center;font-family:monospace;padding:.85rem;color:#1a2e22">' +
      '</label>' +
      '<label>' + MG.t('editRez.reset.password') +
        '<input type="password" name="password" required autocomplete="new-password" minlength="6">' +
      '</label>' +
      '<label>' + MG.t('editRez.reset.password2') +
        '<input type="password" name="password2" required autocomplete="new-password" minlength="6">' +
      '</label>' +
      '<input type="hidden" name="email" value="' + email.replace(/"/g, '&quot;') + '">' +
      '<button type="submit" class="btn btngreen">' + MG.t('editRez.reset.submit') + '</button>' +
    '</form>' +
    '<p><a href="#" id="edit-rez-otp-back">' + MG.t('editRez.forgot.back') + '</a></p>' +
    '</section>';
  document.getElementById('edit-rez-otp-back').addEventListener('click', function(ev){
    ev.preventDefault();
    MG._editRez._goto('login');
  });
  document.getElementById('edit-rez-otp-form').addEventListener('submit', MG._editRez._submitOtpReset);
};

MG._editRez._submitOtpReset = async function(e){
  e.preventDefault();
  if (MG._editRez.busy) return;
  var f = e.currentTarget;
  var btn = f.querySelector('button[type=submit]');
  var origLabel = btn.textContent;
  var email = (f.email.value || '').trim().toLowerCase();
  var otp = (f.otp.value || '').trim().toUpperCase();
  var pw = f.password.value;
  var pw2 = f.password2.value;
  if (!otp || otp.length < 6){
    MG._editRez._showError(MG.t('editRez.reset.otpInvalid'));
    return;
  }
  if (!pw || pw.length < 6){
    MG._editRez._showError(MG.t('editRez.reset.tooShort'));
    return;
  }
  if (pw !== pw2){
    MG._editRez._showError(MG.t('editRez.reset.mismatch'));
    return;
  }
  MG._editRez._setBusy(true);
  btn.disabled = true;
  btn.textContent = MG.t('editRez.reset.submitting');
  try {
    // 1) Ověř OTP kód → vystaví session
    var v = await window.sb.auth.verifyOtp({ email: email, token: otp, type: 'recovery' });
    if (v.error || !v.data || !v.data.session){
      console.error('[editRez] verifyOtp err', v.error);
      MG._editRez._showError(MG.t('editRez.reset.otpInvalid'));
      return;
    }
    // 2) Nastav nové heslo (na vystavené session)
    var u = await window.sb.auth.updateUser({ password: pw });
    if (u.error){
      console.error('[editRez] updateUser err', u.error);
      MG._editRez._showError(MG.t('editRez.reset.error'));
      return;
    }
    // 3) Hotovo — uživatel je přihlášený, načti rezervace a jdi do listu
    MG._editRez.user = (v.data && v.data.user) || (u.data && u.data.user) || null;
    await MG._editRez._loadBookings();
    MG._editRez._goto('list');
  } catch(err){
    console.error('[editRez] otp reset exception', err);
    MG._editRez._showError(MG.t('editRez.reset.error'));
  } finally {
    MG._editRez._setBusy(false);
    btn.disabled = false;
    btn.textContent = origLabel;
  }
};

// ===== LOAD BOOKINGS, SHOP ORDERS, VOUCHERS =====
// RLS ochrání: uživatel vidí jen své vlastní záznamy.
// Načítáme **kompletní historii** napříč statusy + e-shop objednávky + poukazy.
MG._editRez._loadBookings = async function(){
  if (!MG._editRez.user) return;
  var uid = MG._editRez.user.id;
  try {
    var results = await Promise.all([
      window.sb.from('bookings')
        .select('id,moto_id,start_date,end_date,pickup_time,return_time,status,payment_status,total_price,created_at,delivery_fee,extras_price,discount_amount,pickup_method,pickup_address,pickup_lat,pickup_lng,return_method,return_address,return_lat,return_lng,stripe_payment_intent_id,booking_source,modification_history,original_start_date,original_end_date,helmet_size,jacket_size,pants_size,boots_size,gloves_size,passenger_helmet_size,passenger_jacket_size,passenger_pants_size,passenger_boots_size,passenger_gloves_size,motorcycles(id,model,brand,image_url,images,license_required,price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend)')
        .eq('user_id', uid)
        .order('start_date', { ascending: false }),
      window.sb.from('shop_orders')
        .select('id,order_number,status,payment_status,total_amount,created_at,shop_order_items(product_id,size,product_name,unit_price,quantity)')
        .eq('customer_id', uid)
        .order('created_at', { ascending: false }),
      window.sb.from('vouchers')
        .select('id,code,amount,currency,status,valid_from,valid_until,created_at,description,category,redeemed_at,booking_id')
        .eq('buyer_id', uid)
        .order('created_at', { ascending: false }),
      window.sb.from('profiles')
        .select('marketing_consent,consent_gdpr,consent_vop,consent_email,consent_sms,consent_push,consent_data_processing,consent_photo,consent_whatsapp,consent_contract')
        .eq('id', uid)
        .maybeSingle()
    ]);
    MG._editRez.bookings = (results[0] && results[0].data) || [];
    MG._editRez.shopOrders = (results[1] && results[1].data) || [];
    MG._editRez.vouchers = (results[2] && results[2].data) || [];
    MG._editRez.consents = (results[3] && results[3].data) || {};
  } catch(err){
    console.error('[editRez] loadBookings exception', err);
    MG._editRez.bookings = [];
    MG._editRez.shopOrders = [];
    MG._editRez.vouchers = [];
    MG._editRez.consents = {};
  }
};

// Vypočítá display status pro filter (1:1 s Flutter app `displayStatus`).
MG._editRez._displayStatus = function(b){
  if (b.status === 'cancelled') return 'cancelled';
  if (b.status === 'completed') return 'completed';
  var today = MG._editRez._toIsoDate(new Date());
  if (b.end_date < today) return 'completed';
  if (b.start_date > today) return 'upcoming';
  return 'active';
};

// ===== LIST — 5 tabů + sekce Rezervace / E-shop / Poukazy =====
MG._editRez._renderList = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  var bs = MG._editRez.bookings || [];
  var shop = MG._editRez.shopOrders || [];
  var vouchers = MG._editRez.vouchers || [];

  MG._editRez._injectConsentsStyles();

  if (!bs.length && !shop.length && !vouchers.length){
    c.innerHTML =
      '<section class="edit-rez-card edit-rez-empty">' +
      '<h2>' + MG.t('editRez.list.title') + '</h2>' +
      '<p>' + MG.t('editRez.list.empty') + '</p>' +
      '<p><a class="btn btngreen-small" href="/rezervace">' + MG.t('editRez.list.openNew') + '</a></p>' +
      '</section>' +
      MG._editRez._renderConsentsCard();
    MG._editRez._bindConsentsCard(c);
    return;
  }

  var filter = MG._editRez.filter || 'all';
  var filtered = bs.filter(function(b){
    if (filter === 'all') return true;
    return MG._editRez._displayStatus(b) === filter;
  });

  var counts = { all: bs.length, active: 0, upcoming: 0, completed: 0, cancelled: 0 };
  bs.forEach(function(b){ var s = MG._editRez._displayStatus(b); if (counts[s] !== undefined) counts[s]++; });

  var tabKeys = ['all','active','upcoming','completed','cancelled'];
  var tabsHtml = tabKeys.map(function(k){
    var act = (filter === k) ? ' active' : '';
    return '<button type="button" class="edit-rez-filter' + act + '" data-filter="' + k + '">'
      + MG.t('editRez.filter.' + k) + ' <span class="cnt">' + counts[k] + '</span></button>';
  }).join('');

  var bookingsHtml = filtered.length
    ? filtered.map(MG._editRez._renderBookingRow).join('')
    : '<p class="edit-rez-section-empty">' + MG.t('editRez.list.empty') + '</p>';

  var shopHtml = shop.length
    ? shop.map(MG._editRez._renderShopRow).join('')
    : '';
  var vouchersHtml = vouchers.length
    ? vouchers.map(MG._editRez._renderVoucherRow).join('')
    : '';

  c.innerHTML =
    '<section class="edit-rez-card">' +
      '<h2>' + MG.t('editRez.list.title') + '</h2>' +
      '<div class="edit-rez-filters">' + tabsHtml + '</div>' +
      '<div class="edit-rez-booking-list">' + bookingsHtml + '</div>' +
    '</section>' +
    (shopHtml
      ? '<section class="edit-rez-card"><h2>' + MG.t('editRez.list.shopTitle') + '</h2>'
        + '<div class="edit-rez-booking-list">' + shopHtml + '</div></section>'
      : '') +
    (vouchersHtml
      ? '<section class="edit-rez-card"><h2>' + MG.t('editRez.list.vouchersTitle') + '</h2>'
        + '<div class="edit-rez-booking-list">' + vouchersHtml + '</div></section>'
      : '') +
    MG._editRez._renderConsentsCard();

  MG._editRez._bindConsentsCard(c);

  // Filter switchers
  c.querySelectorAll('.edit-rez-filter').forEach(function(btn){
    btn.addEventListener('click', function(){
      MG._editRez.filter = btn.getAttribute('data-filter');
      MG._editRez._renderList();
    });
  });

  // Booking row click → detail
  c.querySelectorAll('.edit-rez-booking[data-id]').forEach(function(btn){
    btn.addEventListener('click', function(){
      var id = btn.getAttribute('data-id');
      var found = (MG._editRez.bookings || []).find(function(x){ return x.id === id; });
      if (!found){ MG._editRez._showError(MG.t('editRez.err.notFound')); return; }
      MG._editRez.selectedBooking = found;
      MG._editRez.selectedMoto = found.motorcycles || null;
      MG._editRez.tab = 'detail';
      MG._editRez._goto('detail');
    });
  });

  // Pending CTA — pokračovat k platbě (resume flow na /rezervace?resume=<id>)
  c.querySelectorAll('[data-pay-id]').forEach(function(btn){
    btn.addEventListener('click', function(ev){
      ev.stopPropagation();
      MG._editRez._resumePending(btn.getAttribute('data-pay-id'));
    });
  });

  // Shop / voucher row → openuje download dokumentů (lazy load přes detail RPC)
  c.querySelectorAll('[data-shop-id]').forEach(function(btn){
    btn.addEventListener('click', function(){
      MG._editRez._showOrderDocs(btn.getAttribute('data-shop-id'), 'shop');
    });
  });
  c.querySelectorAll('[data-voucher-id]').forEach(function(btn){
    btn.addEventListener('click', function(){
      MG._editRez._showOrderDocs(btn.getAttribute('data-voucher-id'), 'voucher');
    });
  });
};

MG._editRez._isPendingUnpaid = function(b){
  return b && b.status === 'pending' && b.payment_status !== 'paid';
};

// Pokračování k platbě = zákazník se vrátí přesně tam, kde skončil v rezervačním
// flow (resume RPC v `pages-rezervace.js` načte všechny step-1 hodnoty, motorky,
// extras, slevu a předskočí na step 2 — doklady + heslo + Stripe).
MG._editRez._resumePending = function(bookingId){
  if (!bookingId) return;
  window.location.href = '/rezervace?resume=' + encodeURIComponent(bookingId);
};

// Storno pending+unpaid — žádný refund (nebylo zaplaceno), použijeme stejný RPC
// jako u zaplacených rezervací; cancel_booking_tracked si ošetří refund kalkulaci
// (0 % protože payment_status != 'paid').
MG._editRez._cancelPending = async function(bookingId){
  if (!bookingId || MG._editRez.busy) return;
  MG._editRez._setBusy(true);
  try {
    var r = await window.sb.rpc('cancel_booking_tracked', {
      p_booking_id: bookingId,
      p_reason: 'Zrušeno zákazníkem před zaplacením'
    });
    if (r.error){
      console.error('[editRez] cancelPending err', r.error);
      MG._editRez._showError(MG.t('editRez.err.generic'));
      return;
    }
    // Po stornu zpět na list (s refreshem)
    MG._editRez.selectedBooking = null;
    await MG._editRez._loadBookings();
    MG._editRez._goto('list');
  } catch(err){
    console.error('[editRez] cancelPending exception', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
  }
};

MG._editRez._renderBookingRow = function(b){
  var m = b.motorcycles || {};
  var motoLabel = (m.brand ? m.brand + ' ' : '') + (m.model || '');
  // Preferuj images[0] (gallery), fallback image_url, fallback emoji placeholder.
  // onerror skryje img a zobrazí placeholder pokud cesta vrátí 404.
  var heroSrc = (m.images && m.images.length ? m.images[0] : m.image_url) || '';
  var heroUrl = heroSrc && typeof MG.imgUrl === 'function' ? MG.imgUrl(heroSrc) : heroSrc;
  var img = heroUrl
    ? '<img src="' + heroUrl + '" alt="" loading="lazy" onerror="this.style.display=\'none\';this.nextElementSibling.style.display=\'flex\'">' +
      '<div class="erez-row-img-ph" style="display:none">🏍️</div>'
    : '<div class="erez-row-img-ph">🏍️</div>';
  var dates = MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date);
  var days = MG._editRez._daysBetween(b.start_date, b.end_date);
  var daysLbl = days + (days === 1 ? ' den' : days < 5 ? ' dny' : ' dní');
  var ds = MG._editRez._displayStatus(b);
  var pending = MG._editRez._isPendingUnpaid(b);
  var statusLbl = pending ? 'Nezaplaceno' : MG.t('editRez.status.' + ds);
  var statusCls = pending ? 'pending-unpaid' : ds;
  var price = MG.formatPrice(Number(b.total_price || 0));
  var bookingNum = (b.id || '').substring(0,8).toUpperCase();
  var payCta = pending
    ? '<button type="button" class="edit-rez-row-pay" data-pay-id="' + b.id + '" aria-label="Pokračovat k platbě">💳 Pokračovat k platbě</button>'
    : '';
  return '<div class="edit-rez-booking-wrap">' +
    '<button type="button" class="edit-rez-booking erez-row' + (pending ? ' pending' : '') + '" data-id="' + b.id + '">' +
      '<div class="erez-row-img">' + img + '</div>' +
      '<div class="erez-row-body">' +
        '<div class="erez-row-num">#' + bookingNum + '</div>' +
        '<div class="erez-row-title">' + motoLabel + '</div>' +
        '<div class="erez-row-meta">📅 ' + dates + ' <span class="muted">· ' + daysLbl + '</span></div>' +
        '<div class="edit-rez-booking-status status-' + statusCls + '">' + statusLbl + '</div>' +
      '</div>' +
      '<div class="erez-row-price">' + price + '</div>' +
    '</button>' + payCta + '</div>';
};

MG._editRez._renderShopRow = function(o){
  var num = o.order_number ? '#' + o.order_number : (o.id || '').substring(0,8).toUpperCase();
  var when = MG.formatDate(o.created_at);
  var price = MG.formatPrice(Number(o.total_amount || 0));
  var statusKey = 'editRez.shopStatus.' + (o.status || 'unknown');
  var lbl = MG.t(statusKey, {});
  if (lbl === statusKey) lbl = o.status || '';
  return '<button type="button" class="edit-rez-booking erez-row" data-shop-id="' + o.id + '">' +
    '<div class="erez-row-img"><div class="erez-row-img-ph">🛒</div></div>' +
    '<div class="erez-row-body">' +
      '<div class="erez-row-num">' + num + '</div>' +
      '<div class="erez-row-title">E-shop objednávka</div>' +
      '<div class="erez-row-meta">📅 ' + when + '</div>' +
      '<div class="edit-rez-booking-status status-' + (o.payment_status === 'paid' ? 'completed' : 'pending') + '">' + lbl + '</div>' +
    '</div>' +
    '<div class="erez-row-price">' + price + '</div>' +
  '</button>';
};

MG._editRez._renderVoucherRow = function(v){
  var code = v.code || '';
  var when = MG.formatDate(v.created_at);
  var price = MG.formatPrice(Number(v.amount || 0));
  var lbl = MG.t('editRez.voucherStatus.' + (v.status || 'active'), {});
  return '<button type="button" class="edit-rez-booking erez-row" data-voucher-id="' + v.id + '">' +
    '<div class="erez-row-img"><div class="erez-row-img-ph">🎁</div></div>' +
    '<div class="erez-row-body">' +
      '<div class="erez-row-num">' + code + '</div>' +
      '<div class="erez-row-title">Dárkový poukaz</div>' +
      '<div class="erez-row-meta">📅 ' + when + '</div>' +
      '<div class="edit-rez-booking-status status-' + (v.status === 'active' ? 'upcoming' : v.status === 'redeemed' ? 'completed' : 'cancelled') + '">' + lbl + '</div>' +
    '</div>' +
    '<div class="erez-row-price">' + price + '</div>' +
  '</button>';
};

// ===== SOUHLASY =====
// Sloupce v profiles odpovídají Velínu 1:1. Některé jsou zákonem povinné pro
// rezervaci (GDPR, VOP, Smlouva, Zpracování dat) — pokud je zákazník odvolá,
// v Supabase je uložíme jako false, ale ve Velíně se mu to obarví červeně a
// nová rezervace už od něj nepůjde, dokud neodsouhlasí znovu (řeší create_web_booking).
MG._editRez._CONSENT_FIELDS = [
  { key: 'consent_gdpr',          label: 'GDPR',                  desc: 'Souhlas se zpracováním osobních údajů.', icon: '🛡️', required: true },
  { key: 'consent_vop',           label: 'VOP',                   desc: 'Všeobecné obchodní podmínky.',           icon: '📜', required: true },
  { key: 'consent_contract',      label: 'Nájemní smlouva',       desc: 'Souhlas s návrhem nájemní smlouvy MotoGo24.', icon: '✍️', required: true },
  { key: 'consent_data_processing', label: 'Zpracování dat',      desc: 'Souhlas se zpracováním dat pro plnění smlouvy.', icon: '🗄️', required: true },
  { key: 'marketing_consent',     label: 'Marketing',             desc: 'Newslettery, slevové akce a novinky.',   icon: '📣' },
  { key: 'consent_email',         label: 'Email',                 desc: 'Komunikace e-mailem (potvrzení, faktury, smlouvy).', icon: '📧' },
  { key: 'consent_sms',           label: 'SMS',                   desc: 'Komunikace přes SMS (přístupové kódy, urgentní upozornění).', icon: '💬' },
  { key: 'consent_whatsapp',      label: 'WhatsApp',              desc: 'Komunikace přes WhatsApp.',              icon: '🟢' },
  { key: 'consent_push',          label: 'Push',                  desc: 'Push notifikace v aplikaci MotoGo24.',   icon: '🔔' },
  { key: 'consent_photo',         label: 'Foto dokladů',          desc: 'Fotografování dokladů přes Mindee OCR pro autonomní pobočku.', icon: '📷' }
];

MG._editRez._renderConsentsCard = function(){
  var cs = MG._editRez.consents || {};
  // Default-on: pokud sloupec v DB je NULL (nikdy explicitně neuložen),
  // bereme to jako udělený souhlas. Pouze explicitní `false` se zobrazí
  // jako vypnutý.
  var isOn = function(key){ return cs[key] !== false; };
  var renderRow = function(f){
    var val = isOn(f.key);
    var badge = f.required
      ? '<span class="edit-rez-consent-badge required">Povinné</span>'
      : '<span class="edit-rez-consent-badge optional">Volitelné</span>';
    return '<div class="edit-rez-consent-row' + (f.required ? ' is-required' : '') + (val ? ' is-on' : '') + '" data-key="' + f.key + '">' +
      '<div class="edit-rez-consent-icon" aria-hidden="true">' + (f.icon || '✅') + '</div>' +
      '<div class="edit-rez-consent-body">' +
        '<div class="edit-rez-consent-head"><span class="edit-rez-consent-label">' + f.label + '</span>' + badge + '</div>' +
        '<div class="edit-rez-consent-desc">' + f.desc + '</div>' +
      '</div>' +
      '<label class="edit-rez-toggle" aria-label="' + f.label + '">' +
        '<input type="checkbox" data-consent="' + f.key + '"' + (val ? ' checked' : '') + '>' +
        '<span class="edit-rez-toggle-slider"></span>' +
        '<span class="edit-rez-toggle-state">' + (val ? 'Ano' : 'Ne') + '</span>' +
      '</label>' +
    '</div>';
  };
  var required = MG._editRez._CONSENT_FIELDS.filter(function(f){ return f.required; });
  var optional = MG._editRez._CONSENT_FIELDS.filter(function(f){ return !f.required; });
  var rows =
    '<div class="edit-rez-consents-section">' +
      '<div class="edit-rez-consents-section-h"><span class="ico">⚖️</span> Povinné pro rezervaci</div>' +
      required.map(renderRow).join('') +
    '</div>' +
    '<div class="edit-rez-consents-section">' +
      '<div class="edit-rez-consents-section-h"><span class="ico">⚙️</span> Volitelné — komunikace a marketing</div>' +
      optional.map(renderRow).join('') +
    '</div>';

  return '<section class="edit-rez-card edit-rez-consents-card">' +
    '<div class="edit-rez-consents-head">' +
      '<div class="edit-rez-consents-title">' +
        '<span class="edit-rez-consents-title-ico">🔒</span>' +
        '<div><h2>Souhlasy a komunikace</h2>' +
        '<p class="edit-rez-consents-help">Změny se ukládají automaticky. Odvolání povinných souhlasů zablokuje další nové rezervace.</p></div>' +
      '</div>' +
      '<div class="edit-rez-consents-actions">' +
        '<button type="button" class="btn-pill primary" id="edit-rez-consents-grant-all">✓ Přijmout vše</button>' +
        '<button type="button" class="btn-pill ghost" id="edit-rez-consents-revoke-all">Odvolat vše</button>' +
      '</div>' +
    '</div>' +
    '<div class="edit-rez-consents-list">' + rows + '</div>' +
    '<div id="edit-rez-consents-status" class="edit-rez-consents-status" aria-live="polite"></div>' +
  '</section>';
};

// Inject one-shot styles pro souhlasy (toggle switches + layout).
MG._editRez._injectConsentsStyles = function(){
  if (document.getElementById('edit-rez-consents-styles')) return;
  var st = document.createElement('style');
  st.id = 'edit-rez-consents-styles';
  st.textContent =
    '.edit-rez-consents-card{background:linear-gradient(180deg,#fafffb 0%,#ffffff 70%);border:1px solid #d4e8e0;border-left:4px solid #74FB71}'+
    '.edit-rez-consents-card h2{font-size:1.25rem;color:#0f1f17;margin:0;display:flex;align-items:center;gap:.5rem}'+
    '.edit-rez-consents-head{display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:1rem;margin-bottom:1rem;padding-bottom:.9rem;border-bottom:1px dashed #d4e8e0}'+
    '.edit-rez-consents-title{display:flex;align-items:flex-start;gap:.8rem;flex:1;min-width:240px}'+
    '.edit-rez-consents-title-ico{font-size:2rem;line-height:1;flex:0 0 auto;background:#e8f5ee;border:1.5px solid #b9e3c8;border-radius:14px;width:48px;height:48px;display:flex;align-items:center;justify-content:center}'+
    '.edit-rez-consents-help{font-size:.82rem;color:#5a6a60;margin:.2rem 0 0;line-height:1.45}'+
    '.edit-rez-consents-actions{display:flex;gap:.5rem;flex-wrap:wrap;align-self:center}'+
    '.edit-rez-consents-actions .btn-pill{padding:.55rem 1.1rem;border-radius:999px;font-weight:800;font-size:.85rem;cursor:pointer;font-family:inherit;letter-spacing:.01em;transition:all .15s;border:1.5px solid transparent;white-space:nowrap}'+
    '.edit-rez-consents-actions .btn-pill.primary{background:#74FB71;color:#0f1f17;border-color:#5edc5a;box-shadow:0 3px 10px rgba(116,251,113,.35)}'+
    '.edit-rez-consents-actions .btn-pill.primary:hover{background:#5edc5a;transform:translateY(-1px);box-shadow:0 5px 14px rgba(116,251,113,.45)}'+
    '.edit-rez-consents-actions .btn-pill.ghost{background:#fff;border-color:#d4e8e0;color:#5a6a60}'+
    '.edit-rez-consents-actions .btn-pill.ghost:hover{border-color:#c0392b;color:#c0392b;background:#fff5f3}'+
    /* Sekce */
    '.edit-rez-consents-section{margin-bottom:1.1rem}'+
    '.edit-rez-consents-section:last-child{margin-bottom:0}'+
    '.edit-rez-consents-section-h{font-size:.78rem;color:#147214;font-weight:800;text-transform:uppercase;letter-spacing:.08em;margin:0 0 .5rem;padding:.35rem .6rem;background:#e8f5ee;border-radius:999px;display:inline-flex;align-items:center;gap:.4rem}'+
    '.edit-rez-consents-section-h .ico{font-size:.95rem}'+
    '.edit-rez-consents-list{display:flex;flex-direction:column;gap:0}'+
    /* Řádek */
    '.edit-rez-consent-row{display:grid;grid-template-columns:42px 1fr auto;gap:.8rem;align-items:center;padding:.85rem 1rem;background:#fff;border:1.5px solid #e5efe9;border-radius:14px;margin-bottom:.45rem;transition:all .15s}'+
    '.edit-rez-consent-row:hover{border-color:#74FB71;box-shadow:0 4px 12px rgba(20,80,40,.08)}'+
    '.edit-rez-consent-row.is-on{border-color:#74FB71;background:linear-gradient(90deg,#f4fff4 0%,#ffffff 60%)}'+
    '.edit-rez-consent-row.is-required{background:#fcfff8}'+
    '.edit-rez-consent-row.is-required.is-on{background:linear-gradient(90deg,#e8f9ec 0%,#ffffff 60%);border-color:#5edc5a}'+
    '.edit-rez-consent-row.busy{opacity:.55;pointer-events:none}'+
    '.edit-rez-consent-icon{font-size:1.5rem;line-height:1;text-align:center;background:#f0f5f2;width:42px;height:42px;border-radius:12px;display:flex;align-items:center;justify-content:center;flex:0 0 auto}'+
    '.edit-rez-consent-row.is-on .edit-rez-consent-icon{background:#e8f5ee}'+
    '.edit-rez-consent-body{min-width:0}'+
    '.edit-rez-consent-head{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap;margin-bottom:.15rem}'+
    '.edit-rez-consent-label{font-weight:800;color:#0f1f17;font-size:.98rem}'+
    '.edit-rez-consent-badge{font-size:.65rem;font-weight:800;padding:.15rem .55rem;border-radius:999px;text-transform:uppercase;letter-spacing:.06em}'+
    '.edit-rez-consent-badge.required{background:#fff4d6;color:#7a5400;border:1px solid #e6a019}'+
    '.edit-rez-consent-badge.optional{background:#eef4f0;color:#5a6a60;border:1px solid #d4e8e0}'+
    '.edit-rez-consent-desc{font-size:.8rem;color:#5a6a60;line-height:1.4}'+
    /* Toggle */
    '.edit-rez-toggle{display:inline-flex;align-items:center;gap:.55rem;cursor:pointer;user-select:none;flex:0 0 auto}'+
    '.edit-rez-toggle input{position:absolute;opacity:0;pointer-events:none}'+
    '.edit-rez-toggle-slider{width:50px;height:28px;background:#cdd7d2;border-radius:999px;position:relative;transition:background .18s,box-shadow .18s;border:1px solid #b8c7be}'+
    '.edit-rez-toggle-slider::after{content:"";position:absolute;top:2px;left:2px;width:22px;height:22px;background:#fff;border-radius:50%;box-shadow:0 2px 4px rgba(0,0,0,.25);transition:left .18s,background .18s}'+
    '.edit-rez-toggle input:checked + .edit-rez-toggle-slider{background:#74FB71;border-color:#5edc5a;box-shadow:0 0 0 3px rgba(116,251,113,.18)}'+
    '.edit-rez-toggle input:checked + .edit-rez-toggle-slider::after{left:25px;background:#fff}'+
    '.edit-rez-toggle input:focus-visible + .edit-rez-toggle-slider{box-shadow:0 0 0 3px rgba(116,251,113,.45)}'+
    '.edit-rez-toggle-state{font-weight:800;font-size:.78rem;color:#5a6a60;min-width:24px;letter-spacing:.04em;text-transform:uppercase}'+
    '.edit-rez-toggle input:checked ~ .edit-rez-toggle-state{color:#147214}'+
    /* Status */
    '.edit-rez-consents-status{font-size:.85rem;margin-top:.9rem;min-height:1.2em;color:#147214;font-weight:700;display:flex;align-items:center;gap:.4rem}'+
    '.edit-rez-consents-status:not(:empty)::before{content:"✓";display:inline-block;font-weight:800}'+
    '.edit-rez-consents-status.error{color:#c0392b}'+
    '.edit-rez-consents-status.error:not(:empty)::before{content:"✕"}'+
    '@media(max-width:680px){.edit-rez-consent-row{grid-template-columns:36px 1fr;gap:.6rem}'+
      '.edit-rez-consent-row .edit-rez-toggle{grid-column:1/3;justify-content:flex-end;margin-top:.2rem}'+
      '.edit-rez-consents-head{flex-direction:column}.edit-rez-consents-actions{align-self:stretch}'+
      '.edit-rez-consents-actions .btn-pill{flex:1;text-align:center}}'+
    /* ===== PENDING ROW + BANNER ===== */
    '.edit-rez-booking-wrap{display:flex;flex-direction:column;gap:0;margin-bottom:.6rem}'+
    '.edit-rez-booking-wrap .edit-rez-booking{margin-bottom:0;border-bottom-left-radius:0;border-bottom-right-radius:0}'+
    '.edit-rez-booking-wrap .edit-rez-row-pay{background:linear-gradient(90deg,#1a8c1a,#0f5e0f);color:#fff;border:none;font-weight:800;padding:.7rem 1rem;cursor:pointer;font-size:.92rem;border-bottom-left-radius:14px;border-bottom-right-radius:14px;display:flex;align-items:center;justify-content:center;gap:.5rem;letter-spacing:.02em;transition:filter .15s}'+
    '.edit-rez-booking-wrap .edit-rez-row-pay:hover{filter:brightness(1.08)}'+
    '.edit-rez-booking.pending{border-left:4px solid #e6a019}'+
    '.edit-rez-booking-status.status-pending-unpaid{background:#fff4d6;color:#7a5400;border:1px solid #e6a019}'+
    '.edit-rez-pending-banner{background:linear-gradient(135deg,#fff4d6 0%,#ffe9b3 100%);border:1.5px solid #e6a019;display:grid;grid-template-columns:60px 1fr auto;gap:1rem;align-items:center;padding:1rem 1.2rem}'+
    '@media(max-width:680px){.edit-rez-pending-banner{grid-template-columns:1fr;text-align:center}}'+
    '.edit-rez-pending-icon{font-size:2.2rem;line-height:1;text-align:center}'+
    '.edit-rez-pending-body h3{margin:0 0 .25rem;color:#7a5400;font-size:1.05rem}'+
    '.edit-rez-pending-body p{margin:0;color:#5a4000;font-size:.85rem;line-height:1.4}'+
    '.edit-rez-pending-actions{display:flex;flex-direction:column;gap:.45rem;min-width:200px}'+
    '@media(max-width:680px){.edit-rez-pending-actions{min-width:0;flex-direction:row;flex-wrap:wrap;justify-content:center}}'+
    '.edit-rez-pending-actions .btn{padding:.55rem 1rem;border-radius:999px;font-weight:700;cursor:pointer;border:none;font-size:.88rem;white-space:nowrap}'+
    '.edit-rez-pending-actions .btngreen{background:#1a8c1a;color:#fff}'+
    '.edit-rez-pending-actions .btngreen:hover{background:#147214}'+
    '.edit-rez-pending-actions .btn-secondary{background:#fff;border:1.5px solid #e6a019;color:#7a5400}'+
    '.edit-rez-pending-actions .btn-secondary:hover{background:#fff4d6}'+
    /* ===== DETAIL TAB ===== */
    '.edit-rez-detail-grid{display:grid;grid-template-columns:minmax(0,1.55fr) minmax(0,1fr);gap:1.4rem;align-items:start;margin-bottom:1.2rem}'+
    '@media(max-width:880px){.edit-rez-detail-grid{grid-template-columns:1fr}}'+
    '.edit-rez-detail-gallery .rez-moto-hero{border-radius:18px;overflow:hidden;box-shadow:0 6px 20px rgba(20,80,40,.12);min-height:280px;max-height:440px}'+
    '@media(max-width:880px){.edit-rez-detail-gallery .rez-moto-hero{aspect-ratio:4/3;min-height:240px;max-height:380px}}'+
    '.edit-rez-detail-headline{margin-top:1rem}'+
    '.edit-rez-detail-headline h3{margin:0 0 .35rem;font-size:1.55rem;color:#1a2e22;line-height:1.15}'+
    '.edit-rez-chip{display:inline-block;background:#e8f5ee;color:#147214;padding:.3rem .7rem;border-radius:999px;font-size:.78rem;font-weight:700;margin-right:.4rem}'+
    '.edit-rez-detail-id{font-size:.78rem;color:#6a7a70;margin-top:.6rem}'+
    '.edit-rez-detail-id code{background:#f0f5f2;padding:.15rem .5rem;border-radius:6px;font-family:Menlo,monospace;font-size:.85rem;letter-spacing:.05em}'+
    '.edit-rez-detail-side{display:flex;flex-direction:column;gap:.6rem}'+
    '.edit-rez-detail-extras{margin-top:.4rem}'+
    /* Legacy support — pokud někde info-grid zůstane, zachová 2 sloupce */
    '.edit-rez-info-grid{display:grid;grid-template-columns:1fr 1fr;gap:.7rem;margin:1.1rem 0}'+
    '@media(max-width:680px){.edit-rez-info-grid{grid-template-columns:1fr}}'+
    '.edit-rez-info-item{display:flex;gap:.7rem;padding:.7rem .85rem;background:#fafdfb;border:1px solid #e5efe9;border-radius:14px}'+
    '.edit-rez-info-item .ico{font-size:1.4rem;line-height:1}'+
    '.edit-rez-info-item .lbl{font-size:.72rem;color:#6a7a70;text-transform:uppercase;letter-spacing:.05em;font-weight:700}'+
    '.edit-rez-info-item .val{font-size:.92rem;color:#1a2e22;margin-top:.15rem;line-height:1.35}'+
    '.edit-rez-info-item .val .muted{color:#6a7a70;font-weight:400}'+
    '.edit-rez-section-h{font-size:1rem;color:#1a2e22;margin:1.4rem 0 .5rem;border-bottom:1px solid #e5efe9;padding-bottom:.4rem;font-weight:800}'+
    /* Cena */
    '.edit-rez-price-card{background:#fafdfb;border:1px solid #e5efe9;border-radius:14px;padding:.4rem .9rem}'+
    '.edit-rez-price-row{display:flex;justify-content:space-between;padding:.55rem 0;border-bottom:1px dashed #e5efe9;font-size:.92rem;color:#1a2e22}'+
    '.edit-rez-price-row:last-child{border-bottom:none}'+
    '.edit-rez-price-row.total{border-top:2px solid #1a8c1a;border-bottom:none;font-size:1.05rem;font-weight:800;color:#0f5e0f;padding-top:.7rem}'+
    /* Výbava */
    '.edit-rez-gear-grid{display:grid;grid-template-columns:1fr 1fr;gap:.7rem}'+
    '@media(max-width:680px){.edit-rez-gear-grid{grid-template-columns:1fr}}'+
    '.edit-rez-gear-block{background:#fafdfb;border:1px solid #e5efe9;border-radius:14px;padding:.7rem .9rem}'+
    '.edit-rez-gear-block h5{margin:0 0 .4rem;font-size:.85rem;color:#1a2e22;font-weight:800;text-transform:uppercase;letter-spacing:.04em}'+
    '.edit-rez-gear-list{list-style:none;margin:0;padding:0}'+
    '.edit-rez-gear-list li{display:flex;justify-content:space-between;padding:.3rem 0;font-size:.88rem;color:#1a2e22;border-bottom:1px dashed #e5efe9}'+
    '.edit-rez-gear-list li:last-child{border-bottom:none}'+
    '.edit-rez-gear-list .gear-val{font-weight:800;color:#147214}'+
    /* Historie */
    '.edit-rez-history-empty{color:#6a7a70;font-style:italic;font-size:.9rem;padding:.5rem 0}'+
    '.edit-rez-history-list{list-style:none;margin:0;padding:.4rem 0 .2rem .9rem;border-left:2px solid #e5efe9}'+
    '.edit-rez-history-item{position:relative;padding:.4rem 0 1rem 1rem}'+
    '.edit-rez-history-dot{position:absolute;left:-1.36rem;top:.55rem;width:14px;height:14px;border-radius:50%;background:#1a8c1a;border:3px solid #fff;box-shadow:0 0 0 2px #d4e8e0}'+
    '.edit-rez-history-when{font-size:.75rem;color:#6a7a70;font-weight:600;text-transform:uppercase;letter-spacing:.04em}'+
    '.edit-rez-history-when .muted{color:#9aa8a0;font-weight:500}'+
    '.edit-rez-history-changes{margin-top:.2rem;font-size:.92rem;color:#1a2e22;line-height:1.45}'+
    '.edit-rez-history-changes s{color:#9aa8a0}'+
    /* ===== MOTO PICKER (katalog-style) ===== */
    '.edit-rez-loading{display:flex;align-items:center;gap:.6rem;color:#6a7a70;padding:1rem 0}'+
    '.edit-rez-moto-head{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:.6rem;margin-bottom:.4rem}'+
    '.edit-rez-moto-head .btn-secondary{background:#fff;border:1.5px solid #d4e8e0;color:#1a2e22;padding:.45rem .9rem;border-radius:999px;font-weight:700;cursor:pointer;font-size:.85rem}'+
    '.edit-rez-moto-head .btn-secondary:hover{border-color:#1a8c1a;background:#f0faf5}'+
    '.erez-moto-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:1rem;margin-top:.8rem}'+
    '@media(max-width:520px){.erez-moto-grid{grid-template-columns:1fr}}'+
    '.erez-moto-card{background:#fff;border:1px solid #d4e8e0;border-radius:18px;overflow:hidden;display:flex;flex-direction:column;transition:transform .15s, box-shadow .15s, border-color .15s;box-shadow:0 4px 12px rgba(20,80,40,.05)}'+
    '.erez-moto-card:hover:not(.is-disabled){transform:translateY(-3px);box-shadow:0 12px 28px rgba(20,80,40,.14);border-color:#1a8c1a}'+
    '.erez-moto-card.is-disabled{opacity:.55;filter:grayscale(.4)}'+
    '.erez-moto-hero{position:relative;aspect-ratio:4/3;background:linear-gradient(135deg,#f0faf5 0%,#e0f0e6 100%);display:flex;align-items:center;justify-content:center;overflow:hidden}'+
    '.erez-moto-hero-img{width:100%;height:100%;object-fit:cover;display:block}'+
    '.erez-moto-hero-placeholder{font-size:3.5rem;opacity:.4}'+
    '.erez-moto-pill{position:absolute;top:.6rem;left:.6rem;background:#1a8c1a;color:#fff;padding:.25rem .65rem;border-radius:999px;font-size:.72rem;font-weight:800;letter-spacing:.04em}'+
    '.erez-moto-pill.alt{background:#fff;color:#1a8c1a;border:1.5px solid #1a8c1a}'+
    '.erez-moto-meta{padding:1rem 1.1rem 1.1rem;display:flex;flex-direction:column;gap:.45rem;flex:1}'+
    '.erez-moto-meta h4{margin:0;color:#1a2e22;font-size:1.12rem;line-height:1.2}'+
    '.erez-moto-specs{font-size:.78rem;color:#7d978a;font-weight:600;letter-spacing:.04em;text-transform:uppercase}'+
    '.erez-moto-price{font-size:.92rem;color:#1a2e22;font-weight:700;margin-top:.2rem}'+
    '.erez-moto-price .muted{color:#9aa8a0;font-weight:500;text-decoration:line-through}'+
    '.erez-moto-diff{display:inline-block;padding:.3rem .7rem;border-radius:999px;font-size:.82rem;font-weight:700;align-self:flex-start}'+
    '.erez-moto-diff.up{background:#fff4d6;color:#7a5400;border:1px solid #e6a019}'+
    '.erez-moto-diff.down{background:#e8f5ee;color:#147214;border:1px solid #1a8c1a}'+
    '.erez-moto-diff.zero{background:#f0f5f2;color:#3a4a40;border:1px solid #d4e8e0}'+
    '.erez-moto-reasons{font-size:.8rem;color:#c0392b;font-weight:600;background:#ffebe7;padding:.4rem .65rem;border-radius:8px}'+
    '.erez-moto-cta{margin-top:auto;background:#1a8c1a;color:#fff;border:none;padding:.7rem 1rem;border-radius:12px;font-weight:800;cursor:pointer;font-size:.92rem;letter-spacing:.02em;transition:filter .15s, transform .12s}'+
    '.erez-moto-cta:hover:not(.disabled){filter:brightness(1.08);transform:translateY(-1px)}'+
    '.erez-moto-cta.disabled{background:#d4e8e0;color:#7d978a;cursor:not-allowed}'+
    /* ===== LOCATION CARDS ===== */
    '.erez-loc-grid{display:grid;grid-template-columns:1fr 1fr;gap:.7rem;margin-bottom:.8rem}'+
    '@media(max-width:680px){.erez-loc-grid{grid-template-columns:1fr}}'+
    '.erez-loc-card{display:grid;grid-template-columns:48px 1fr 28px;gap:.7rem;align-items:center;padding:1rem 1.1rem;background:#fff;border:1.5px solid #d4e8e0;border-radius:14px;cursor:pointer;transition:all .15s;position:relative}'+
    '.erez-loc-card:hover{border-color:#1a8c1a;background:#f7fcf9}'+
    '.erez-loc-card.active{border-color:#1a8c1a;background:#e8f5ee;box-shadow:0 0 0 3px rgba(26,140,26,.15)}'+
    '.erez-loc-card input[type=radio]{position:absolute;opacity:0;pointer-events:none}'+
    '.erez-loc-ico{font-size:2rem;line-height:1;text-align:center}'+
    '.erez-loc-body{display:flex;flex-direction:column;gap:.2rem}'+
    '.erez-loc-title{font-size:1rem;color:#1a2e22}'+
    '.erez-loc-sub{font-size:.78rem;color:#5a6a60;line-height:1.35}'+
    '.erez-loc-check{display:none;background:#1a8c1a;color:#fff;width:24px;height:24px;border-radius:50%;text-align:center;line-height:24px;font-size:.85rem;font-weight:800}'+
    '.erez-loc-card.active .erez-loc-check{display:block}'+
    '.erez-loc-addr-panel{padding:.85rem 1rem;background:#fafdfb;border:1px dashed #d4e8e0;border-radius:14px;margin-bottom:1rem}'+
    '.erez-loc-addr-row{display:flex;gap:.5rem;align-items:stretch;flex-wrap:wrap}'+
    '.erez-loc-input{flex:1;min-width:200px;padding:.65rem .85rem;border:1.5px solid #d4e8e0;border-radius:10px;font-family:Montserrat,sans-serif;font-size:.92rem;color:#1a2e22;background:#fff}'+
    '.erez-loc-input:focus{outline:none;border-color:#1a8c1a;box-shadow:0 0 0 3px rgba(26,140,26,.12)}'+
    '.erez-loc-mapbtn{background:#1a8c1a;color:#fff;border:none;padding:.65rem 1rem;border-radius:10px;font-weight:700;cursor:pointer;font-size:.85rem;white-space:nowrap;transition:filter .15s}'+
    '.erez-loc-mapbtn:hover{filter:brightness(1.08)}'+
    '.erez-loc-route{margin-top:.6rem;font-size:.85rem;color:#1a2e22}'+
    /* transparentní rozpis ceny: orig vs. nové fee + diff */
    '.erez-loc-calc{background:#fafdfb;border:1px solid #d4e8e0;border-radius:14px;padding:.6rem .9rem;margin:.4rem 0}'+
    '.erez-loc-calc-row{display:flex;justify-content:space-between;align-items:center;padding:.3rem 0;font-size:.88rem;color:#3a4a40;border-bottom:1px dashed #e3ecde}'+
    '.erez-loc-calc-row:last-child{border-bottom:none}'+
    '.erez-loc-calc-row strong{color:#1a2e22;font-weight:700;text-align:right}'+
    '.erez-loc-calc-total{border-top:2px solid #1a8c1a;margin-top:.3rem;padding-top:.55rem;font-size:1rem}'+
    '.erez-loc-calc-total span{font-weight:700;color:#1a2e22}'+
    '.erez-loc-calc-total.erez-loc-diff-pay strong{color:#c0392b;font-size:1.05rem}'+
    '.erez-loc-calc-total.erez-loc-diff-refund strong{color:#1a8c1a;font-size:1.05rem}'+
    '.edit-rez-loc-submit{margin-top:.5rem;padding:.85rem 1.4rem;border-radius:14px;font-size:1rem}'+
    /* ===== ROZSIRENA KARTA REZERVACE V LISTU ===== */
    '.edit-rez-booking.erez-row{display:grid;grid-template-columns:120px 1fr auto;gap:1rem;padding:1rem 1.1rem;background:#fff;border:1px solid #d4e8e0;border-radius:16px;align-items:center;text-align:left;cursor:pointer;width:100%;transition:transform .15s, box-shadow .15s, border-color .15s;font:inherit;color:inherit}'+
    '.edit-rez-booking.erez-row:hover{transform:translateY(-2px);box-shadow:0 10px 24px rgba(20,80,40,.12);border-color:#1a8c1a}'+
    '@media(max-width:520px){.edit-rez-booking.erez-row{grid-template-columns:90px 1fr;grid-template-areas:"img body" "img price";align-items:start}}'+
    '@media(max-width:520px){.edit-rez-booking.erez-row .erez-row-img{grid-area:img}}'+
    '@media(max-width:520px){.edit-rez-booking.erez-row .erez-row-body{grid-area:body}}'+
    '@media(max-width:520px){.edit-rez-booking.erez-row .erez-row-price{grid-area:price;justify-self:end;margin-top:.4rem}}'+
    '.erez-row-img{aspect-ratio:4/3;background:linear-gradient(135deg,#f0faf5 0%,#e0f0e6 100%);border-radius:12px;overflow:hidden;display:flex;align-items:center;justify-content:center}'+
    '.erez-row-img img{width:100%;height:100%;object-fit:cover}'+
    '.erez-row-img-ph{font-size:2.2rem;opacity:.5}'+
    '.erez-row-num{font-size:.7rem;color:#7d978a;font-weight:700;letter-spacing:.06em;font-family:Menlo,monospace}'+
    '.erez-row-title{font-size:1.05rem;color:#1a2e22;font-weight:800;margin:.2rem 0 .35rem}'+
    '.erez-row-meta{font-size:.85rem;color:#3a4a40;margin-bottom:.5rem}'+
    '.erez-row-meta .muted{color:#9aa8a0}'+
    '.erez-row-price{font-weight:800;color:#1a2e22;font-size:1.1rem;white-space:nowrap}';
  document.head.appendChild(st);
};

// Po render listu připojí listenery na toggle switche + tlačítka.
MG._editRez._bindConsentsCard = function(scope){
  var card = scope.querySelector('.edit-rez-consents-card');
  if (!card) return;
  card.querySelectorAll('input[data-consent]').forEach(function(inp){
    inp.addEventListener('change', function(){
      MG._editRez._saveConsent(inp.getAttribute('data-consent'), inp.checked, inp);
    });
  });
  var grantAll = card.querySelector('#edit-rez-consents-grant-all');
  if (grantAll) grantAll.addEventListener('click', function(){
    MG._editRez._saveAllConsents(true);
  });
  var revokeAll = card.querySelector('#edit-rez-consents-revoke-all');
  if (revokeAll) revokeAll.addEventListener('click', function(){
    MG._editRez._confirmDialog('Opravdu chcete odvolat všechny souhlasy?', function(){
      MG._editRez._saveAllConsents(false);
    }, { yesLabel: 'Odvolat vše', noLabel: 'Zachovat', danger: true });
  });
};

MG._editRez._setConsentsStatus = function(msg, isError){
  var el = document.getElementById('edit-rez-consents-status');
  if (!el) return;
  el.textContent = msg || '';
  el.classList.toggle('error', !!isError);
  if (msg && !isError){
    setTimeout(function(){
      if (el.textContent === msg) el.textContent = '';
    }, 3000);
  }
};

// Save jednoho souhlasu — direct profiles.update (RLS: user UPDATE id=uid OK).
MG._editRez._saveConsent = async function(key, value, inp){
  if (!MG._editRez.user) return;
  var row = inp && inp.closest('.edit-rez-consent-row');
  if (row){ row.classList.add('busy'); row.classList.toggle('is-on', !!value); }
  inp.disabled = true;
  var stateEl = row && row.querySelector('.edit-rez-toggle-state');
  if (stateEl) stateEl.textContent = value ? 'Ano' : 'Ne';
  try {
    var payload = {}; payload[key] = !!value;
    var r = await window.sb.from('profiles').update(payload).eq('id', MG._editRez.user.id);
    if (r.error){
      console.error('[editRez] consent save err', key, r.error);
      // Rollback UI
      inp.checked = !value;
      if (row) row.classList.toggle('is-on', !value);
      if (stateEl) stateEl.textContent = !value ? 'Ano' : 'Ne';
      MG._editRez._setConsentsStatus('Nepodařilo se uložit souhlas.', true);
    } else {
      (MG._editRez.consents = MG._editRez.consents || {})[key] = !!value;
      MG._editRez._setConsentsStatus(value ? 'Souhlas udělen.' : 'Souhlas odvolán.', false);
    }
  } catch(e){
    console.error('[editRez] consent save exception', e);
    inp.checked = !value;
    if (row) row.classList.toggle('is-on', !value);
    if (stateEl) stateEl.textContent = !value ? 'Ano' : 'Ne';
    MG._editRez._setConsentsStatus('Nepodařilo se uložit souhlas.', true);
  } finally {
    inp.disabled = false;
    if (row) row.classList.remove('busy');
  }
};

// Hromadné nastavení všech souhlasů (Přijmout vše / Odvolat vše)
MG._editRez._saveAllConsents = async function(value){
  if (!MG._editRez.user) return;
  var card = document.querySelector('.edit-rez-consents-card');
  if (!card) return;
  card.classList.add('busy');
  var inputs = card.querySelectorAll('input[data-consent]');
  inputs.forEach(function(inp){ inp.disabled = true; });
  try {
    var payload = {};
    MG._editRez._CONSENT_FIELDS.forEach(function(f){ payload[f.key] = !!value; });
    var r = await window.sb.from('profiles').update(payload).eq('id', MG._editRez.user.id);
    if (r.error){
      console.error('[editRez] saveAll consents err', r.error);
      MG._editRez._setConsentsStatus('Nepodařilo se uložit souhlasy.', true);
      return;
    }
    MG._editRez.consents = MG._editRez.consents || {};
    inputs.forEach(function(inp){
      var key = inp.getAttribute('data-consent');
      inp.checked = !!value;
      MG._editRez.consents[key] = !!value;
      var stateEl = inp.parentElement.querySelector('.edit-rez-toggle-state');
      if (stateEl) stateEl.textContent = value ? 'Ano' : 'Ne';
      var row = inp.closest('.edit-rez-consent-row');
      if (row) row.classList.toggle('is-on', !!value);
    });
    MG._editRez._setConsentsStatus(value ? 'Všechny souhlasy uděleny.' : 'Všechny souhlasy odvolány.', false);
  } catch(e){
    console.error('[editRez] saveAll exception', e);
    MG._editRez._setConsentsStatus('Nepodařilo se uložit souhlasy.', true);
  } finally {
    inputs.forEach(function(inp){ inp.disabled = false; });
    card.classList.remove('busy');
  }
};

// Modal s odkazy na faktury / dokumenty pro shop_order nebo voucher.
// (Pro bookings je ekvivalent v Detail tabu „Doklady" — v dalším commitu.)
MG._editRez._showOrderDocs = async function(orderId, kind){
  if (!orderId) return;
  MG._editRez._setBusy(true);
  try {
    var col = (kind === 'voucher') ? 'order_id' : 'order_id';
    var r = await window.sb
      .from('invoices')
      .select('id,number,type,status,total,pdf_path,issue_date')
      .eq(col, orderId)
      .order('issue_date', { ascending: true });
    var docs = (r && r.data) || [];
    var listHtml = docs.length
      ? '<ul class="edit-rez-doclist">' + docs.map(function(d){
          var label = MG.t('editRez.doc.type.' + (d.type || 'unknown'), {}) || (d.type || '');
          var num = d.number || (d.id || '').substring(0,8);
          var amt = MG.formatPrice(Number(d.total || 0));
          var actions = '<button type="button" class="btn-link" data-pdf="' + (d.pdf_path || '') + '">' + MG.t('editRez.doc.download') + '</button>';
          return '<li><div><strong>' + label + '</strong> ' + num + ' · ' + amt + '</div><div>' + actions + '</div></li>';
        }).join('') + '</ul>'
      : '<p>' + MG.t('editRez.doc.empty') + '</p>';

    var ov = document.createElement('div');
    ov.className = 'edit-rez-confirm-overlay';
    ov.innerHTML = '<div class="edit-rez-confirm-dialog edit-rez-doc-dialog" role="dialog">'
      + '<h4>' + MG.t('editRez.doc.title') + '</h4>'
      + listHtml
      + '<div class="edit-rez-confirm-actions"><button type="button" class="btn btn-secondary" data-close>' + MG.t('editRez.doc.close') + '</button></div>'
      + '</div>';
    document.body.appendChild(ov);
    ov.querySelector('[data-close]').addEventListener('click', function(){ ov.remove(); });
    ov.addEventListener('click', function(e){ if (e.target === ov) ov.remove(); });
    // PDF download — vystaví signed URL pro storage path
    ov.querySelectorAll('[data-pdf]').forEach(function(btn){
      btn.addEventListener('click', async function(){
        var p = btn.getAttribute('data-pdf');
        await MG._editRez._openDocPdf(p);
      });
    });
  } catch(err){
    console.error('[editRez] showOrderDocs err', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
  }
};

// Sestaví placeholder mapu pro klient-side render šablony VOP / smlouva, když
// generated_documents záznam ještě není (typicky upcoming rezervace před aktivací).
// Klíče se snaží zhruba krýt s `fillTemplate` použitím ve Velíně + Edge funkci
// generate-document. Co tam není, se v šabloně zobrazí jako prázdný řetězec —
// {{key}} regex v _fillTemplate vrací '' pro chybějící hodnoty.
MG._editRez._buildDocFallbackData = async function(b){
  if (!b) return {};
  var moto = MG._editRez.selectedMoto || {};
  var profile = null;
  try {
    var pr = await window.sb.from('profiles')
      .select('full_name,first_name,last_name,phone,email,address,city,postal_code,country,birth_date,id_number,license_number,license_group')
      .eq('id', MG._editRez.user.id)
      .maybeSingle();
    profile = pr && pr.data;
  } catch(e){ /* nemůžeme — zákazník stejně může smlouvu prohlédnout, prázdná pole nahradí podpisem */ }
  profile = profile || {};
  var origStart = MG._editRez._normIso(b.start_date);
  var origEnd = MG._editRez._normIso(b.end_date);
  var fmt = function(iso){ return iso ? MG.formatDate(iso) : ''; };
  var customer_name = profile.full_name
    || ((profile.first_name || '') + ' ' + (profile.last_name || '')).trim()
    || (MG._editRez.user && MG._editRez.user.email) || '';

  return {
    // Booking
    booking_id: b.id || '',
    booking_number: (b.id || '').slice(0, 8).toUpperCase(),
    start_date: fmt(origStart),
    end_date: fmt(origEnd),
    pickup_date: fmt(origStart),
    return_date: fmt(origEnd),
    pickup_time: b.pickup_time || '',
    return_time: b.return_time || '',
    total_price: b.total_price ? MG.formatPrice(Number(b.total_price)) : '',
    delivery_fee: b.delivery_fee ? MG.formatPrice(Number(b.delivery_fee)) : '0 Kč',
    pickup_method: b.pickup_method === 'delivery' ? 'Přistavení' : 'V půjčovně Mezná',
    return_method: b.return_method === 'delivery' ? 'Vyzvednutí' : 'V půjčovně Mezná',
    pickup_address: b.pickup_address || 'Mezná 9, 257 87',
    return_address: b.return_address || 'Mezná 9, 257 87',
    // Customer (vyplněno z profilu, prázdné pokud chybí)
    customer_name: customer_name,
    customer_first_name: profile.first_name || '',
    customer_last_name: profile.last_name || '',
    customer_email: profile.email || (MG._editRez.user && MG._editRez.user.email) || '',
    customer_phone: profile.phone || '',
    customer_address: profile.address || '',
    customer_city: profile.city || '',
    customer_postal_code: profile.postal_code || '',
    customer_country: profile.country || 'Česko',
    customer_birth_date: profile.birth_date ? MG.formatDate(profile.birth_date) : '',
    customer_id_number: profile.id_number || '',
    customer_license_number: profile.license_number || '',
    customer_license_group: profile.license_group || '',
    // Moto
    moto_brand: moto.brand || '',
    moto_model: moto.model || '',
    moto_name: ((moto.brand || '') + ' ' + (moto.model || '')).trim(),
    moto_year: moto.year || '',
    moto_engine_size: moto.engine_size || '',
    moto_license_required: moto.license_required || '',
    // Společnost
    company_name: 'Bc. Petra Semorádová',
    company_ico: '21874263',
    company_address: 'Mezná 9, 257 87',
    company_phone: '+420 774 256 271',
    company_email: 'info@motogo24.cz',
    // Aktuální datum (pro datum vystavení smlouvy)
    today: MG.formatDate(new Date().toISOString().slice(0,10))
  };
};

// Stáhne / otevře dokument podle „kind" a dostupných polí. Tři režimy:
//   1) `path` v storage → signed URL (nebo public fallback)
//   2) generated_documents bez path → render template HTML + dosaď filled_data,
//      uložíme jako Blob a otevřeme/uložíme — to je důvod, proč šlo VOP/Smlouva
//      ve Velíně stáhnout a na webu ne (web předtím spoléhal jen na storage path).
//   3) jinak — chybová hláška.
MG._editRez._downloadDocRow = async function(row){
  if (!row){ MG._editRez._showError(MG.t('editRez.doc.notAvailable')); return; }
  // 1) preferuj storage
  if (row.path){
    return MG._editRez._openDocPdf(row.path, row.bucket || 'invoices');
  }
  // 2) klient render z template
  if (row.kind === 'generated' && row.templateHtml && row.filledData){
    try {
      var html = MG._editRez._fillTemplate(row.templateHtml, row.filledData);
      var blob = new Blob([html], { type: 'text/html;charset=utf-8' });
      var url = URL.createObjectURL(blob);
      // Otevřeme v novém tabu — zákazník si dokument prohlédne / vytiskne / uloží
      var w = window.open(url, '_blank');
      if (!w){
        // Fallback: vynucené stažení (popup blocker)
        var a = document.createElement('a');
        a.href = url; a.download = (row.label || 'dokument') + '.html';
        document.body.appendChild(a); a.click(); a.remove();
      }
      setTimeout(function(){ URL.revokeObjectURL(url); }, 30000);
      return;
    } catch(e){
      console.error('[editRez] template render err', e);
    }
  }
  MG._editRez._showError(MG.t('editRez.doc.notAvailable'));
};

// Jednoduchá template substituce {{key}} a {{nested.key}} — kompatibilní s
// Velínovým `fillTemplate` ze `clientTemplates.js` (web nemá Mustache lib,
// takže to děláme manuálně přes regex).
MG._editRez._fillTemplate = function(html, vars){
  if (!html || !vars) return html || '';
  return String(html).replace(/\{\{\s*([\w.]+)\s*\}\}/g, function(_, key){
    var parts = key.split('.'), v = vars;
    for (var i = 0; i < parts.length; i++){
      if (v == null) return '';
      v = v[parts[i]];
    }
    return v == null ? '' : String(v);
  });
};

// Otevře PDF z Supabase Storage. invoices.pdf_path může být plný path (s bucketem)
// nebo jen relativní; default bucket = 'invoices'.
MG._editRez._openDocPdf = async function(path, defaultBucket){
  if (!path){ MG._editRez._showError(MG.t('editRez.doc.notAvailable')); return; }
  try {
    var bucket = defaultBucket || 'invoices';
    var key = path;
    // Pokud path obsahuje slash a první segment je bucket name, rozdělíme
    if (path.indexOf('/') > -1){
      var first = path.split('/')[0];
      if (['invoices','documents','generated_documents'].indexOf(first) > -1){
        bucket = first;
        key = path.substring(first.length + 1);
      }
    }
    var r = await window.sb.storage.from(bucket).createSignedUrl(key, 600);
    if (r.error || !r.data || !r.data.signedUrl){
      // fallback na public URL
      var p = window.sb.storage.from(bucket).getPublicUrl(key);
      if (p && p.data && p.data.publicUrl){ window.open(p.data.publicUrl, '_blank'); return; }
      MG._editRez._showError(MG.t('editRez.doc.notAvailable'));
      return;
    }
    window.open(r.data.signedUrl, '_blank');
  } catch(err){
    console.error('[editRez] openDocPdf err', err);
    MG._editRez._showError(MG.t('editRez.doc.notAvailable'));
  }
};

// ===== DETAIL — tab shell + per-tab render =====
MG._editRez._renderDetail = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  var b = MG._editRez.selectedBooking;
  if (!b){ MG._editRez._goto('list'); return; }
  var m = MG._editRez.selectedMoto || {};

  // Hlavička s motorkou + datumem + back na list.
  var motoLabel = (m.brand ? m.brand + ' ' : '') + (m.model || '');
  var dates = MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date);
  var status = '<span class="edit-rez-booking-status status-' + b.status + '">'
    + MG._editRez._statusLabel(b.status) + '</span>';

  // Tab buttons. Edit-akce jen pro paid+(reserved|active). Doklady vždy.
  var canEdit = (b.status === 'reserved' || b.status === 'active') && b.payment_status === 'paid';
  var tabs = [
    { key:'detail',   label: MG.t('editRez.tab.detail'),   show: true },
    { key:'extend',   label: MG.t('editRez.tab.extend'),   show: canEdit },
    { key:'shorten',  label: MG.t('editRez.tab.shorten'),  show: canEdit },
    { key:'moto',     label: MG.t('editRez.tab.moto'),     show: canEdit && b.status === 'reserved' },
    { key:'location', label: MG.t('editRez.tab.location'), show: canEdit && b.status === 'reserved' },
    { key:'docs',     label: MG.t('editRez.tab.docs'),     show: true },
    { key:'cancel',   label: MG.t('editRez.tab.cancel'),   show: canEdit }
  ].filter(function(t){ return t.show; });

  var tabHtml = tabs.map(function(t){
    var act = (MG._editRez.tab === t.key) ? ' active' : '';
    return '<button type="button" class="edit-rez-tab' + act + '" data-tab="' + t.key + '">' + t.label + '</button>';
  }).join('');

  // Pending banner — vyzve k dokončení platby (nebo storno bez vrácení)
  var pending = MG._editRez._isPendingUnpaid(b);
  var pendingBanner = pending
    ? '<section class="edit-rez-card edit-rez-pending-banner">' +
        '<div class="edit-rez-pending-icon">⏳</div>' +
        '<div class="edit-rez-pending-body">' +
          '<h3>Rezervace čeká na zaplacení</h3>' +
          '<p>Tato rezervace ještě nebyla potvrzena platbou. Dokud nezaplatíte, motorka pro vás není rezervována. Úpravy (datum, motorka, místo) půjdou až po dokončení platby.</p>' +
        '</div>' +
        '<div class="edit-rez-pending-actions">' +
          '<button type="button" class="btn btngreen" id="edit-rez-resume-pay">💳 Pokračovat k platbě</button>' +
          '<button type="button" class="btn btn-secondary" id="edit-rez-cancel-pending">Zrušit rezervaci</button>' +
        '</div>' +
      '</section>'
    : '';

  c.innerHTML =
    '<section class="edit-rez-card edit-rez-detail-head">' +
      '<button type="button" class="btn-link" id="edit-rez-back">← ' + MG.t('editRez.list.title') + '</button>' +
      '<h2>' + motoLabel + '</h2>' +
      '<div class="edit-rez-detail-meta">' + dates + ' · ' + status + '</div>' +
    '</section>' +
    pendingBanner +
    '<nav class="edit-rez-tabs" role="tablist">' + tabHtml + '</nav>' +
    '<section class="edit-rez-card" id="edit-rez-tab-content"></section>';

  document.getElementById('edit-rez-back').addEventListener('click', function(){
    MG._editRez.selectedBooking = null;
    MG._editRez._goto('list');
  });
  c.querySelectorAll('.edit-rez-tab').forEach(function(btn){
    btn.addEventListener('click', function(){
      MG._editRez.tab = btn.getAttribute('data-tab');
      MG._editRez._renderDetail();
    });
  });

  // Pending banner CTA
  if (pending){
    var resumeBtn = document.getElementById('edit-rez-resume-pay');
    if (resumeBtn) resumeBtn.addEventListener('click', function(){
      MG._editRez._resumePending(b.id);
    });
    var cancelBtn = document.getElementById('edit-rez-cancel-pending');
    if (cancelBtn) cancelBtn.addEventListener('click', function(){
      MG._editRez._confirmDialog('Opravdu chcete zrušit nezaplacenou rezervaci?', function(){
        MG._editRez._cancelPending(b.id);
      }, { yesLabel: 'Ano, zrušit', noLabel: 'Ne, ponechat', danger: true });
    });
  }

  // Per-tab obsah.
  if (MG._editRez.tab === 'detail')   return MG._editRez._renderTabDetail();
  if (MG._editRez.tab === 'cancel')   return MG._editRez._renderTabCancel();
  if (MG._editRez.tab === 'extend')   return MG._editRez._renderTabExtend();
  if (MG._editRez.tab === 'shorten')  return MG._editRez._renderTabShorten();
  if (MG._editRez.tab === 'moto')     return MG._editRez._renderTabMoto();
  if (MG._editRez.tab === 'location') return MG._editRez._renderTabLocation();
  if (MG._editRez.tab === 'docs')     return MG._editRez._renderTabDocs();
  return MG._editRez._renderTabDetail();
};

// ===== TAB: DOKLADY =====
// Načte všechny doklady spojené s booking_id z `invoices` (ZF/FV/dobropis/
// platební doklad/shop_*) a `documents` (smlouva/VOP/protokol). Každý
// stažitelný PDF přes Supabase Storage signed URL.
MG._editRez._renderTabDocs = async function(){
  var b = MG._editRez.selectedBooking;
  var t = document.getElementById('edit-rez-tab-content');
  t.innerHTML = '<h3>' + MG.t('editRez.doc.title') + '</h3>'
    + '<p>' + MG.t('editRez.loading') + '</p>';

  try {
    var results = await Promise.all([
      window.sb.from('invoices')
        .select('id,number,type,status,total,pdf_path,issue_date,created_at')
        .eq('booking_id', b.id)
        .order('issue_date', { ascending: true }),
      window.sb.from('documents')
        .select('id,type,file_path,file_name,file_url,created_at')
        .eq('booking_id', b.id)
        .order('created_at', { ascending: true }),
      window.sb.from('generated_documents')
        .select('id,template_id,booking_id,pdf_path,filled_data,created_at,document_templates(name,type,content_html)')
        .eq('booking_id', b.id)
        .order('created_at', { ascending: true }),
      // Fallback šablony pro VOP a smlouvu — pro upcoming rezervaci ještě nemusí
      // existovat vygenerovaný generated_documents záznam, ale zákazník má právo
      // si VOP a smlouvu kdykoliv stáhnout (jako v Flutter app).
      window.sb.from('document_templates')
        .select('id,type,name,content_html,version')
        .in('type', ['contract','vop'])
        .eq('active', true)
        .order('version', { ascending: false })
    ]);
    var invoices = (results[0] && results[0].data) || [];
    var docs     = (results[1] && results[1].data) || [];
    var gen      = (results[2] && results[2].data) || [];
    var tpls     = (results[3] && results[3].data) || [];

    // Trigger sync_invoice_to_documents() / sync_generated_doc_to_documents()
    // duplikuje záznamy do `documents`. Aby se v UI nezobrazovaly 2x, vyfiltrujeme
    // typy které spravují faktury a generated_documents.
    var SYNCED_TYPES = ['invoice_advance','payment_receipt','invoice_final','invoice_shop',
                        'rental_contract','contract','vop','handover_protocol','protocol'];
    docs = docs.filter(function(d){ return SYNCED_TYPES.indexOf(d.type) === -1; });

    var rows = [];
    invoices.forEach(function(d){
      var label = MG.t('editRez.doc.type.' + (d.type || 'unknown'), {});
      var num = d.number || (d.id || '').substring(0,8);
      var amt = d.total ? MG.formatPrice(Number(d.total)) : '';
      var when = d.issue_date ? MG.formatDate(d.issue_date) : (d.created_at ? MG.formatDate(d.created_at) : '');
      rows.push({ kind:'invoice', label: label, num: num, amt: amt, when: when, path: d.pdf_path, bucket: 'invoices' });
    });
    var hasContract = false, hasVop = false;
    gen.forEach(function(d){
      var tplType = (d.document_templates && d.document_templates.type) || '';
      var name = (d.document_templates && d.document_templates.name) || '';
      var lblKey = 'editRez.doc.type.' + tplType;
      var label = MG.t(lblKey, {});
      if (label === lblKey || !label) label = name || tplType || 'Dokument';
      var when = d.created_at ? MG.formatDate(d.created_at) : '';
      // Klient-side fallback render — vždy generujeme HTML z template + filled_data,
      // takže VOP/Smlouva půjde stáhnout i bez existujícího pdf_path v storage.
      rows.push({
        kind: 'generated', label: label, num: name, amt: '', when: when,
        path: d.pdf_path, bucket: 'generated_documents',
        templateHtml: (d.document_templates && d.document_templates.content_html) || '',
        filledData: d.filled_data || null,
        templateType: tplType
      });
      if (tplType === 'contract' || tplType === 'rental_contract') hasContract = true;
      if (tplType === 'vop') hasVop = true;
    });
    docs.forEach(function(d){
      var label = MG.t('editRez.doc.type.' + (d.type || 'unknown'), {});
      var when = d.created_at ? MG.formatDate(d.created_at) : '';
      var path = d.file_path || d.file_url;
      rows.push({ kind:'document', label: label, num: d.file_name || '', amt: '', when: when, path: path, bucket: 'documents' });
    });

    // Fallback: pokud chybí smlouva nebo VOP v generated_documents, doplníme je
    // ze šablony — vyplníme dostupnými údaji z bookingu/profilu/motorky a render
    // proběhne klient-side jako u ostatních generated dokumentů.
    var fallbackData = await MG._editRez._buildDocFallbackData(b);
    tpls.forEach(function(tpl){
      var isContract = tpl.type === 'contract' || tpl.type === 'rental_contract';
      var isVop = tpl.type === 'vop';
      if (isContract && hasContract) return;
      if (isVop && hasVop) return;
      if (!isContract && !isVop) return;
      var lblKey = 'editRez.doc.type.' + tpl.type;
      var label = MG.t(lblKey, {});
      if (label === lblKey || !label) label = tpl.name || tpl.type;
      rows.push({
        kind: 'generated',
        label: label,
        num: tpl.name || '',
        amt: '',
        when: '',
        path: null,
        bucket: 'generated_documents',
        templateHtml: tpl.content_html || '',
        filledData: fallbackData,
        templateType: tpl.type
      });
      if (isContract) hasContract = true;
      if (isVop) hasVop = true;
    });

    // Ulož řádky pro lazy-handlery (klient render html z template + filled_data)
    MG._editRez._docRows = rows;

    var listHtml = rows.length
      ? '<ul class="edit-rez-doclist">' + rows.map(function(r, i){
          var meta = [r.num, r.when, r.amt].filter(function(x){ return x; }).join(' · ');
          var canDownload = r.path || (r.kind === 'generated' && r.templateHtml && r.filledData);
          var btn = canDownload
            ? '<button type="button" class="btn-link" data-row="' + i + '">' + MG.t('editRez.doc.download') + '</button>'
            : '<span class="muted">' + MG.t('editRez.doc.notAvailable') + '</span>';
          return '<li><div><strong>' + r.label + '</strong>' + (meta ? '<br><span class="muted">' + meta + '</span>' : '') + '</div><div>' + btn + '</div></li>';
        }).join('') + '</ul>'
      : '<p>' + MG.t('editRez.doc.empty') + '</p>';

    t.innerHTML = '<h3>' + MG.t('editRez.doc.title') + '</h3>'
      + '<p class="edit-rez-tip">' + MG.t('editRez.doc.help') + '</p>'
      + listHtml;

    t.querySelectorAll('[data-row]').forEach(function(btn){
      btn.addEventListener('click', function(){
        var row = MG._editRez._docRows[parseInt(btn.getAttribute('data-row'), 10)];
        MG._editRez._downloadDocRow(row);
      });
    });
  } catch(err){
    console.error('[editRez] renderTabDocs err', err);
    t.innerHTML = '<h3>' + MG.t('editRez.doc.title') + '</h3>'
      + '<div class="edit-rez-error">' + MG.t('editRez.err.generic') + '</div>';
  }
};

// ===== TAB: ZMĚNA MOTORKY =====
// License hierarchie 1:1 jako v Flutter app + apply_booking_changes RPC
// (server validuje znovu — bezpečné).
MG._editRez._licenseAllows = function(profileGroups, motoRequired){
  if (!motoRequired || motoRequired === 'N') return true;
  if (!profileGroups || !profileGroups.length) return false;
  var allowed = {
    AM: ['AM','A1','A2','A','B'],
    A1: ['A1','A2','A'],
    A2: ['A2','A'],
    A:  ['A'],
    B:  ['B']
  }[motoRequired] || [motoRequired];
  return profileGroups.some(function(g){ return allowed.indexOf(g) > -1; });
};

MG._editRez._renderTabMoto = async function(){
  var b = MG._editRez.selectedBooking;
  var t = document.getElementById('edit-rez-tab-content');
  t.innerHTML = '<h3>' + MG.t('editRez.moto.title') + '</h3>'
    + '<p class="muted">Vyberte si jinou motorku z naší flotily — zobrazujeme všechny dostupné v daném termínu, kompatibilní s vaším řidičským oprávněním.</p>'
    + '<div class="edit-rez-loading"><span class="spinner"></span> Načítám flotilu…</div>';

  try {
    var [motosR, profileR] = await Promise.all([
      window.sb.from('motorcycles')
        .select('id,model,brand,image_url,images,description,license_required,engine_cc,power_kw,year,price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend')
        .eq('status','active').order('model'),
      window.sb.from('profiles').select('license_group').eq('id', MG._editRez.user.id).maybeSingle()
    ]);
    var motos = (motosR && motosR.data) || [];
    var profileGroups = (profileR && profileR.data && profileR.data.license_group) || [];
    motos = motos.filter(function(m){ return m.id !== b.moto_id; });

    if (!motos.length){
      t.innerHTML = '<h3>' + MG.t('editRez.moto.title') + '</h3>'
        + '<p class="muted">' + MG.t('editRez.moto.noOptions') + '</p>';
      return;
    }

    var rangePromises = motos.map(function(m){
      return window.sb.rpc('get_moto_booked_dates', { p_moto_id: m.id })
        .then(function(r){ return { moto: m, occupied: (r && r.data) || [] }; });
    });
    var withAvail = await Promise.all(rangePromises);

    var oldPrice = MG._editRez._priceForRange(MG._editRez.selectedMoto, b.start_date, b.end_date);
    var cards = withAvail.map(function(x){
      var m = x.moto;
      var licOk = MG._editRez._licenseAllows(profileGroups, m.license_required);
      var available = !MG._editRez._rangeOverlapsOccupied(b.start_date, b.end_date, x.occupied);
      var newPrice = MG._editRez._priceForRange(m, b.start_date, b.end_date);
      var diff = Math.round(newPrice - oldPrice);
      var disabled = !licOk || !available;

      // Galerie — preferujeme images[0] jako hero, fallback na image_url
      var heroSrc = (m.images && m.images.length ? m.images[0] : m.image_url) || '';
      var heroUrl = (typeof MG.imgUrl === 'function') ? MG.imgUrl(heroSrc) : heroSrc;
      var heroHtml = heroUrl
        ? '<img class="erez-moto-hero-img" src="' + heroUrl + '" alt="" loading="lazy">'
        : '<div class="erez-moto-hero-placeholder">🏍️</div>';

      var bStr = (m.brand || '').trim();
      var mStr = (m.model || '').trim();
      var label = (bStr && mStr.toLowerCase().indexOf(bStr.toLowerCase()) !== 0)
        ? (bStr + ' ' + mStr) : (mStr || bStr);
      var lic = m.license_required && m.license_required !== 'N'
        ? '<span class="erez-moto-pill">ŘP ' + m.license_required + '</span>'
        : '<span class="erez-moto-pill alt">Bez ŘP</span>';

      var specs = [];
      if (m.engine_cc) specs.push(m.engine_cc + ' cm³');
      if (m.power_kw)    specs.push(m.power_kw + ' kW');
      if (m.year)        specs.push(m.year);
      var specsHtml = specs.length ? '<div class="erez-moto-specs">' + specs.join(' · ') + '</div>' : '';

      var diffHtml = diff === 0
        ? '<span class="erez-moto-diff zero">Stejná cena</span>'
        : (diff > 0
          ? '<span class="erez-moto-diff up">+' + MG.formatPrice(diff) + ' za celou rezervaci</span>'
          : '<span class="erez-moto-diff down">' + MG.formatPrice(diff) + ' (vrátíme)</span>');

      var reasons = [];
      if (!licOk) reasons.push('🚫 Nedostatečné ŘP');
      if (!available) reasons.push('📅 V termínu obsazené');
      var reasonsHtml = reasons.length
        ? '<div class="erez-moto-reasons">' + reasons.join(' · ') + '</div>'
        : '';

      var cta = disabled
        ? '<button type="button" class="erez-moto-cta disabled" disabled>Nedostupné</button>'
        : '<button type="button" class="erez-moto-cta" data-id="' + m.id + '" data-name="' + label.replace(/"/g,'&quot;') + '">Vybrat tuto motorku →</button>';

      return '<article class="erez-moto-card' + (disabled ? ' is-disabled' : '') + '">' +
        '<div class="erez-moto-hero">' + heroHtml + lic + '</div>' +
        '<div class="erez-moto-meta">' +
          '<h4>' + label + '</h4>' +
          specsHtml +
          '<div class="erez-moto-price">' + MG.formatPrice(newPrice) + ' celkem' +
            ' <span class="muted">vs. </span>' + MG.formatPrice(oldPrice) + '</div>' +
          diffHtml +
          reasonsHtml +
          cta +
        '</div>' +
      '</article>';
    }).join('');

    t.innerHTML = '<div class="edit-rez-moto-head">' +
        '<h3>' + MG.t('editRez.moto.title') + '</h3>' +
        '<button type="button" class="btn btn-secondary" id="edit-rez-moto-back">← Zpět na detail</button>' +
      '</div>' +
      '<p class="muted">Vyberte si jinou motorku z naší flotily — zobrazujeme všechny dostupné v daném termínu, kompatibilní s vaším řidičským oprávněním.</p>' +
      '<div class="erez-moto-grid">' + cards + '</div>';

    var back = document.getElementById('edit-rez-moto-back');
    if (back) back.addEventListener('click', function(){
      MG._editRez.tab = 'detail';
      MG._editRez._renderDetail();
    });

    t.querySelectorAll('.erez-moto-cta:not(.disabled)').forEach(function(btn){
      btn.addEventListener('click', function(){
        var newId = btn.getAttribute('data-id');
        var name = btn.getAttribute('data-name');
        MG._editRez._confirmDialog(
          'Změnit motorku na ' + name + '?',
          function(){ MG._editRez._submitChange({ p_new_moto_id: newId }); },
          { yesLabel: 'Ano, změnit motorku', noLabel: 'Ne, ponechat' }
        );
      });
    });
  } catch(err){
    console.error('[editRez] renderTabMoto err', err);
    t.innerHTML = '<h3>' + MG.t('editRez.moto.title') + '</h3>'
      + '<div class="edit-rez-error">' + MG.t('editRez.err.generic') + '</div>';
  }
};

// ===== UNIFIED CHANGE SUBMIT =====
// Volá apply_booking_changes RPC (existující). Server vrátí buď
// payment_required=true (otevřeme Stripe Checkout přes process-payment Edge),
// nebo aplikuje rovnou + případný refund.
MG._editRez._submitChange = async function(payload){
  if (MG._editRez.busy) return;
  var b = MG._editRez.selectedBooking;
  MG._editRez._setBusy(true);
  try {
    var args = Object.assign({ p_booking_id: b.id }, payload || {});
    var r = await window.sb.rpc('apply_booking_changes', args);
    if (r.error || !r.data || r.data.success === false){
      var code = r.data && r.data.error;
      var msgKey = {
        'wrong_status': 'editRez.err.wrongStatus',
        'not_paid': 'editRez.err.notPaid',
        'active_start_locked': 'editRez.err.activeStartLocked',
        'active_moto_locked': 'editRez.err.activeMotoLocked',
        'invalid_range': 'editRez.err.invalidRange',
        'no_change': 'editRez.err.invalidRange',
        'not_found': 'editRez.err.notFound',
        'overlap': 'editRez.extend.unavailable',
        'license_insufficient': 'editRez.moto.licenseInsufficient',
        'moto_not_found': 'editRez.err.notFound',
        'unauthenticated': 'editRez.login.error'
      }[code] || 'editRez.err.generic';
      MG._editRez._showError(MG.t(msgKey));
      return;
    }
    if (r.data.payment_required){
      // Webhook (process-payment Edge) dnes pro type='extension' jen potvrdí
      // platbu, ale neaplikuje pending změny (na rozdíl od Flutter app, která
      // je drží v RAM a aplikuje po success). Uložíme tedy pending_changes
      // do localStorage a po návratu z Stripe je aplikuje klient-side
      // (viz _applyPendingAfterPayment v init flow).
      try {
        localStorage.setItem('editRez_pending_' + b.id, JSON.stringify({
          payload: payload,
          ts: Date.now()
        }));
      } catch(e){ /* localStorage disabled — fallback ztratí změny */ }

      var sess = await window.sb.auth.getSession();
      var token = sess && sess.data && sess.data.session && sess.data.session.access_token;
      if (!token) throw new Error('no-auth');
      var url = window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment';
      var resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + token,
          'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY
        },
        body: JSON.stringify({
          type: 'extension',
          booking_id: b.id,
          amount: r.data.net_diff,
          success_url: window.location.origin + '/upravit-rezervaci?paid_booking=' + b.id,
          cancel_url:  window.location.origin + '/upravit-rezervaci'
        })
      });
      var data = await resp.json().catch(function(){ return null; });
      if (!resp.ok || !data || !data.url){
        console.error('[editRez] payment err', resp.status, data);
        MG._editRez._showError((data && data.error) ? data.error : MG.t('editRez.err.generic'));
        try { localStorage.removeItem('editRez_pending_' + b.id); } catch(e){}
        return;
      }
      window.location.href = data.url;
      return;
    }
    // Aplikováno bez doplatku — možná s refundem.
    var refund = r.data.refund_amount || 0;
    var msg = refund > 0
      ? MG.t('editRez.change.successWithRefund', { amount: MG.formatPrice(refund) })
      : MG.t('editRez.change.success');
    var c = document.getElementById('edit-rez-tab-content');
    if (c) c.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + msg + '</p>'
      + '<button type="button" class="btn btngreen-small" id="edit-rez-back-list">'
      + MG.t('editRez.list.title') + '</button></div>';
    var back = document.getElementById('edit-rez-back-list');
    if (back) back.addEventListener('click', async function(){
      MG._editRez.selectedBooking = null;
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
    });
  } catch(err){
    console.error('[editRez] submitChange err', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
  }
};

// ===== TAB: ZMĚNA MÍSTA =====
// Pro pickup i return: radio "v půjčovně (Mezná) / přistavení na adresu".
// Pokud "přistavení", zobrazí se input s autocomplete + tlačítko "Mapa".
// Cena se přepočítává live přes Mapy.cz routing API (1000 + km*40).
// Submit → apply_booking_changes RPC.
MG._editRez._renderTabLocation = function(){
  var b = MG._editRez.selectedBooking;
  var t = document.getElementById('edit-rez-tab-content');
  var isDelP = b.pickup_method === 'delivery';
  var isDelR = b.return_method === 'delivery';

  // ===== ORIG fees per side =====
  // V DB je jen `delivery_fee` jako součet — nemáme uložené zvlášť pickup/return
  // ani km. Spočítáme zpětně z koordinátů (pokud delivery), abychom dokázali
  // ukázat transparentně rozdíl: orig_km × 40 + 1 000 Kč → orig_fee.
  var origPickupFee = 0, origReturnFee = 0;
  var origPickupKm = null, origReturnKm = null;

  // 4 karty (2x pickup + 2x return) — vizuálně shodné s rezervačním formulářem.
  // Každá karta má ikonu, titulek, popis a cenu; aktivní = zelená border + check.
  function locCard(name, val, ico, title, sub, checked){
    return '<label class="erez-loc-card' + (checked ? ' active' : '') + '" data-loc-name="' + name + '" data-loc-val="' + val + '">' +
      '<input type="radio" name="' + name + '" value="' + val + '"' + (checked ? ' checked' : '') + '>' +
      '<span class="erez-loc-ico" aria-hidden="true">' + ico + '</span>' +
      '<span class="erez-loc-body">' +
        '<span class="erez-loc-title">' + title + '</span>' +
        '<span class="erez-loc-sub">' + sub + '</span>' +
      '</span>' +
      '<span class="erez-loc-check">✓</span>' +
    '</label>';
  }

  t.innerHTML =
    '<h3>' + MG.t('editRez.loc.title') + '</h3>' +
    '<p class="muted">' + MG.t('editRez.loc.help') + '</p>' +
    '<form id="edit-rez-loc-form" class="edit-rez-form" novalidate>' +
      // PICKUP
      '<h4 class="edit-rez-section-h">📥 Vyzvednutí motorky</h4>' +
      '<div class="erez-loc-grid">' +
        locCard('pickup', 'pickup', '🏠',
          '<strong>V půjčovně Mezná</strong>',
          'Mezná 9, 257 87 — autonomní pobočka, otevřeno nonstop. <strong>0 Kč.</strong>',
          !isDelP) +
        locCard('pickup', 'delivery', '🚚',
          '<strong>Přistavení na adresu</strong>',
          '<strong>1 000 Kč + 40 Kč/km</strong> z Mezné. Cena se vypočte automaticky z trasy.',
          isDelP) +
      '</div>' +
      '<div class="erez-loc-addr-panel" data-side="pickup" style="display:' + (isDelP ? 'block' : 'none') + '">' +
        '<div class="erez-loc-addr-row">' +
          '<input type="text" name="pickupAddr" class="erez-loc-input" placeholder="' + MG.t('editRez.loc.addrPlaceholder') + '" value="' + (b.pickup_address || '').replace(/"/g,'&quot;') + '" autocomplete="street-address">' +
          '<button type="button" class="erez-loc-mapbtn" data-map="pickup">📍 Vybrat na mapě</button>' +
        '</div>' +
        '<div class="erez-loc-route" id="edit-rez-loc-route-pickup"></div>' +
        '<input type="hidden" name="pickupLat" value="' + (b.pickup_lat || '') + '">' +
        '<input type="hidden" name="pickupLng" value="' + (b.pickup_lng || '') + '">' +
        '<input type="hidden" name="pickupFee" value="0">' +
      '</div>' +

      // RETURN
      '<h4 class="edit-rez-section-h">📤 Vrácení motorky</h4>' +
      '<div class="erez-loc-grid">' +
        locCard('returnM', 'pickup', '🏠',
          '<strong>V půjčovně Mezná</strong>',
          'Vrátíte v autonomní pobočce. <strong>0 Kč.</strong>',
          !isDelR) +
        locCard('returnM', 'delivery', '🛵',
          '<strong>Vyzvedneme od vás</strong>',
          '<strong>1 000 Kč + 40 Kč/km</strong> z Mezné. Cena se vypočte automaticky.',
          isDelR) +
      '</div>' +
      '<div class="erez-loc-addr-panel" data-side="return" style="display:' + (isDelR ? 'block' : 'none') + '">' +
        '<div class="erez-loc-addr-row">' +
          '<input type="text" name="returnAddr" class="erez-loc-input" placeholder="' + MG.t('editRez.loc.addrPlaceholder') + '" value="' + (b.return_address || '').replace(/"/g,'&quot;') + '" autocomplete="street-address">' +
          '<button type="button" class="erez-loc-mapbtn" data-map="return">📍 Vybrat na mapě</button>' +
        '</div>' +
        '<div class="erez-loc-route" id="edit-rez-loc-route-return"></div>' +
        '<input type="hidden" name="returnLat" value="' + (b.return_lat || '') + '">' +
        '<input type="hidden" name="returnLng" value="' + (b.return_lng || '') + '">' +
        '<input type="hidden" name="returnFee" value="0">' +
      '</div>' +

      '<div id="edit-rez-loc-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen edit-rez-loc-submit" id="edit-rez-loc-cta" disabled>' + MG.t('editRez.loc.cta') + '</button>' +
    '</form>';

  var f = document.getElementById('edit-rez-loc-form');

  // Toggle adresa boxů + active class na kartách
  function syncAddrVisibility(){
    var pkV = f.pickup.value;
    var rtV = f.returnM.value;
    f.querySelector('.erez-loc-addr-panel[data-side="pickup"]').style.display = (pkV === 'delivery') ? 'block' : 'none';
    f.querySelector('.erez-loc-addr-panel[data-side="return"]').style.display = (rtV === 'delivery') ? 'block' : 'none';
    if (pkV !== 'delivery'){ f.pickupFee.value = '0'; }
    if (rtV !== 'delivery'){ f.returnFee.value = '0'; }
    // Active class na kartách
    f.querySelectorAll('.erez-loc-card').forEach(function(c){
      var name = c.getAttribute('data-loc-name');
      var val = c.getAttribute('data-loc-val');
      var current = (name === 'pickup') ? pkV : rtV;
      c.classList.toggle('active', current === val);
    });
    livePreview();
  }
  Array.from(f.pickup).forEach(function(r){ r.addEventListener('change', syncAddrVisibility); });
  Array.from(f.returnM).forEach(function(r){ r.addEventListener('change', syncAddrVisibility); });

  // Mapa picker (reuse existující MG._openWebMapPicker — ale ten zapisuje
  // do rezervačních inputů. Sklouzneme se do vlastního mini-pickeru, který
  // přepoužije Leaflet+Mapy.cz tile layer.)
  f.querySelectorAll('.erez-loc-mapbtn').forEach(function(btn){
    btn.addEventListener('click', function(){
      var side = btn.getAttribute('data-map');
      MG._editRez._openLocPicker(side, function(result){
        if (!result) return;
        var addrInp = side === 'pickup' ? f.pickupAddr : f.returnAddr;
        var latInp = side === 'pickup' ? f.pickupLat : f.returnLat;
        var lngInp = side === 'pickup' ? f.pickupLng : f.returnLng;
        addrInp.value = result.address || '';
        latInp.value = result.lat;
        lngInp.value = result.lng;
        recalcRoute(side);
      });
    });
  });

  // Při změně adresy textem zkusíme suggest → routing
  function debounce(fn, ms){
    var to;
    return function(){ var args = arguments, ctx = this;
      clearTimeout(to);
      to = setTimeout(function(){ fn.apply(ctx, args); }, ms);
    };
  }
  function calcFee(km){
    return MG._calcDeliveryFee ? MG._calcDeliveryFee(km) : (1000 + Math.ceil(km || 0) * 40);
  }
  function recalcRoute(side){
    var addrInp = side === 'pickup' ? f.pickupAddr : f.returnAddr;
    var latInp = side === 'pickup' ? f.pickupLat : f.returnLat;
    var lngInp = side === 'pickup' ? f.pickupLng : f.returnLng;
    var feeInp = side === 'pickup' ? f.pickupFee : f.returnFee;
    var routeEl = document.getElementById('edit-rez-loc-route-' + side);
    var addr = (addrInp.value || '').trim();
    if (!addr){ routeEl.textContent = ''; feeInp.value = '0'; livePreview(); return; }
    routeEl.innerHTML = '<span class="muted">' + MG.t('editRez.loc.routing') + '</span>';

    function applyFee(km){
      var fee = calcFee(km);
      feeInp.value = String(fee);
      routeEl.innerHTML = '<div><strong>' + km.toFixed(1).replace('.', ',') + ' km</strong> z Mezné · '
        + Math.round(km) + ' × 40 Kč + 1 000 Kč = <strong>' + MG.formatPrice(fee) + '</strong></div>';
      livePreview();
    }

    var p = (latInp.value && lngInp.value)
      ? Promise.resolve({ lat: Number(latInp.value), lng: Number(lngInp.value) })
      : (MG._mapySuggest ? MG._mapySuggest(addr, 1).then(function(a){ return (a && a[0]) || null; }) : Promise.resolve(null));

    p.then(function(coords){
      if (!coords){ routeEl.innerHTML = '<span class="muted">' + MG.t('editRez.loc.geocodeFail') + '</span>'; return; }
      latInp.value = coords.lat; lngInp.value = coords.lng;
      if (!MG._ensureBranchCoords || !MG._mapyRouting){ applyFee(50); return; }  // fallback estimate
      MG._ensureBranchCoords().then(function(branch){
        if (!branch) return applyFee(50);
        return MG._mapyRouting(branch.lat, branch.lng, coords.lat, coords.lng).then(function(rt){
          applyFee(rt && rt.distanceKm ? rt.distanceKm : 50);
        });
      });
    });
  }
  f.pickupAddr.addEventListener('input', debounce(function(){ recalcRoute('pickup'); }, 600));
  f.returnAddr.addEventListener('input', debounce(function(){ recalcRoute('return'); }, 600));

  // ===== Spočti orig fees zpětně z uložených koordinátů =====
  // Booking neukládá zvlášť pickup/return fee, jen sum delivery_fee. Pro
  // transparentní zobrazení rozdílu si km dopočítáme z lat/lng (pokud delivery).
  function computeOrigFees(){
    var promises = [];
    if (isDelP && b.pickup_lat && b.pickup_lng && MG._ensureBranchCoords && MG._mapyRouting){
      promises.push(MG._ensureBranchCoords().then(function(br){
        if (!br) return null;
        return MG._mapyRouting(br.lat, br.lng, Number(b.pickup_lat), Number(b.pickup_lng))
          .then(function(rt){
            if (rt && rt.distanceKm){
              origPickupKm = rt.distanceKm;
              origPickupFee = calcFee(origPickupKm);
            }
          });
      }));
    } else if (isDelP){
      // Žádné koordináty — fallback: pokud byl jen jeden delivery side, použij
      // celé delivery_fee; jinak rozděl půl-půl.
      origPickupFee = isDelR ? Math.round(Number(b.delivery_fee || 0) / 2) : Number(b.delivery_fee || 0);
    }
    if (isDelR && b.return_lat && b.return_lng && MG._ensureBranchCoords && MG._mapyRouting){
      promises.push(MG._ensureBranchCoords().then(function(br){
        if (!br) return null;
        return MG._mapyRouting(br.lat, br.lng, Number(b.return_lat), Number(b.return_lng))
          .then(function(rt){
            if (rt && rt.distanceKm){
              origReturnKm = rt.distanceKm;
              origReturnFee = calcFee(origReturnKm);
            }
          });
      }));
    } else if (isDelR){
      origReturnFee = isDelP ? Math.round(Number(b.delivery_fee || 0) / 2) : Number(b.delivery_fee || 0);
    }
    return Promise.all(promises);
  }

  // ===== Live preview ceny (klient-side breakdown + serverside dry-run) =====
  // Klient transparentně ukáže "starý poplatek za vyzvednutí + vrácení vs. nový"
  // — uživatel vidí, jak se diff počítá. Backend (apply_booking_changes dry-run)
  // vrátí autoritativní net_diff; pokud se liší od klientského, dáme přednost
  // serveru a ukážeme oba pro transparentnost.
  function livePreview(){
    var summary = document.getElementById('edit-rez-loc-summary');
    var cta = document.getElementById('edit-rez-loc-cta');
    var pkM = f.pickup.value;
    var rtM = f.returnM.value;
    var pkFee = (pkM === 'delivery') ? Number(f.pickupFee.value || 0) : 0;
    var rtFee = (rtM === 'delivery') ? Number(f.returnFee.value || 0) : 0;
    var newTotal = pkFee + rtFee;
    var origTotal = origPickupFee + origReturnFee;
    var diffLocal = newTotal - origTotal;
    var noChange = (pkM === b.pickup_method && rtM === b.return_method && diffLocal === 0);

    // Klient breakdown — vždy zobrazený
    var lines = [];
    lines.push('<div class="erez-loc-calc-row"><span>Vyzvednutí — původní</span><strong>'
      + (isDelP ? (origPickupKm ? Math.round(origPickupKm) + ' km × 40 Kč + 1 000 Kč = ' : '')
                  + MG.formatPrice(origPickupFee) : 'V půjčovně (0 Kč)') + '</strong></div>');
    lines.push('<div class="erez-loc-calc-row"><span>Vyzvednutí — nové</span><strong>'
      + (pkM === 'delivery' ? MG.formatPrice(pkFee) : 'V půjčovně (0 Kč)') + '</strong></div>');
    lines.push('<div class="erez-loc-calc-row"><span>Vrácení — původní</span><strong>'
      + (isDelR ? (origReturnKm ? Math.round(origReturnKm) + ' km × 40 Kč + 1 000 Kč = ' : '')
                  + MG.formatPrice(origReturnFee) : 'V půjčovně (0 Kč)') + '</strong></div>');
    lines.push('<div class="erez-loc-calc-row"><span>Vrácení — nové</span><strong>'
      + (rtM === 'delivery' ? MG.formatPrice(rtFee) : 'V půjčovně (0 Kč)') + '</strong></div>');
    var diffCls = diffLocal > 0 ? 'erez-loc-diff-pay' : diffLocal < 0 ? 'erez-loc-diff-refund' : '';
    var diffLabel = diffLocal > 0 ? 'Doplatek' : diffLocal < 0 ? 'Vrátíme' : 'Bez změny ceny';
    lines.push('<div class="erez-loc-calc-row erez-loc-calc-total ' + diffCls + '"><span>'
      + diffLabel + '</span><strong>' + (diffLocal !== 0 ? MG.formatPrice(Math.abs(diffLocal)) : '0 Kč') + '</strong></div>');

    if (noChange){
      summary.innerHTML = '<div class="erez-loc-calc">' + lines.join('') + '</div>'
        + '<div class="muted" style="margin-top:.4rem">' + MG.t('editRez.loc.noPriceChange') + '</div>';
      cta.disabled = true;
      return;
    }

    var args = {
      p_booking_id: b.id,
      p_new_pickup_method: pkM,
      p_new_pickup_address: pkM === 'delivery' ? f.pickupAddr.value : null,
      p_new_pickup_lat: pkM === 'delivery' && f.pickupLat.value ? Number(f.pickupLat.value) : null,
      p_new_pickup_lng: pkM === 'delivery' && f.pickupLng.value ? Number(f.pickupLng.value) : null,
      p_new_pickup_fee: pkM === 'delivery' ? pkFee : 0,
      p_new_return_method: rtM,
      p_new_return_address: rtM === 'delivery' ? f.returnAddr.value : null,
      p_new_return_lat: rtM === 'delivery' && f.returnLat.value ? Number(f.returnLat.value) : null,
      p_new_return_lng: rtM === 'delivery' && f.returnLng.value ? Number(f.returnLng.value) : null,
      p_new_return_fee: rtM === 'delivery' ? rtFee : 0,
      p_dry_run: true
    };
    summary.innerHTML = '<div class="erez-loc-calc">' + lines.join('') + '</div>'
      + '<div class="muted" style="margin-top:.4rem">Ověřuji u serveru…</div>';
    window.sb.rpc('apply_booking_changes', args).then(function(r){
      if (r.error || !r.data || r.data.success === false){
        var code = r.data && r.data.error;
        if (code === 'no_change'){
          summary.innerHTML = '<div class="erez-loc-calc">' + lines.join('') + '</div>'
            + '<div class="muted" style="margin-top:.4rem">' + MG.t('editRez.extend.noChange') + '</div>';
        } else {
          summary.innerHTML = '<div class="erez-loc-calc">' + lines.join('') + '</div>'
            + '<div class="error" style="margin-top:.4rem">' + MG.t('editRez.err.generic') + '</div>';
        }
        cta.disabled = true;
        return;
      }
      var d = r.data;
      var serverDiff = d.net_diff || 0;
      var refund = d.refund_amount || 0;
      // Pokud se serverside diff výrazně liší (>10 Kč) od klientského, přepíšeme
      // poslední řádek serverovou hodnotou — ale ukážeme původní cenu pro transparenci.
      var displayDiff = serverDiff;
      var displayLines = lines.slice(0, lines.length - 1);
      var actLabel = displayDiff > 0 ? 'Doplatek (Stripe)'
                  : displayDiff < 0 || refund > 0 ? 'Vrátíme'
                  : 'Bez změny ceny';
      var actCls = displayDiff > 0 ? 'erez-loc-diff-pay'
                : (displayDiff < 0 || refund > 0) ? 'erez-loc-diff-refund' : '';
      var actAmount = displayDiff > 0 ? displayDiff
                    : (refund || Math.abs(displayDiff));
      displayLines.push('<div class="erez-loc-calc-row erez-loc-calc-total ' + actCls + '"><span>'
        + actLabel + '</span><strong>' + (actAmount ? MG.formatPrice(actAmount) : '0 Kč') + '</strong></div>');
      summary.innerHTML = '<div class="erez-loc-calc">' + displayLines.join('') + '</div>';
      cta.disabled = (displayDiff === 0 && refund === 0 && pkM === b.pickup_method && rtM === b.return_method);
    });
  }

  // Načti orig fees z lat/lng (async) → pak refresh routes + preview
  computeOrigFees().then(function(){
    syncAddrVisibility();
    if (isDelP) recalcRoute('pickup');
    if (isDelR) recalcRoute('return');
    livePreview();
  });

  f.addEventListener('submit', function(e){
    e.preventDefault();
    if (MG._editRez.busy) return;
    var pkM = f.pickup.value, rtM = f.returnM.value;
    var payload = {
      p_new_pickup_method: pkM,
      p_new_pickup_address: pkM === 'delivery' ? f.pickupAddr.value : null,
      p_new_pickup_lat: pkM === 'delivery' && f.pickupLat.value ? Number(f.pickupLat.value) : null,
      p_new_pickup_lng: pkM === 'delivery' && f.pickupLng.value ? Number(f.pickupLng.value) : null,
      p_new_pickup_fee: pkM === 'delivery' ? Number(f.pickupFee.value || 0) : 0,
      p_new_return_method: rtM,
      p_new_return_address: rtM === 'delivery' ? f.returnAddr.value : null,
      p_new_return_lat: rtM === 'delivery' && f.returnLat.value ? Number(f.returnLat.value) : null,
      p_new_return_lng: rtM === 'delivery' && f.returnLng.value ? Number(f.returnLng.value) : null,
      p_new_return_fee: rtM === 'delivery' ? Number(f.returnFee.value || 0) : 0
    };
    MG._editRez._confirmDialog(MG.t('editRez.loc.confirm'), function(){
      MG._editRez._submitChange(payload);
    });
  });
};

// Mini map picker pro location tab — full-screen Leaflet + Mapy.cz tiles,
// reuse libraries z rezervace flow (Leaflet už načtený když se otevřela
// rezervace dříve; jinak loadnut on-demand).
MG._editRez._openLocPicker = function(side, onConfirm){
  var prev = document.getElementById('edit-rez-map-overlay');
  if (prev) prev.remove();
  var ov = document.createElement('div');
  ov.id = 'edit-rez-map-overlay';
  ov.className = 'edit-rez-map-overlay';
  ov.innerHTML =
    '<div class="edit-rez-map-bar">' +
      '<button type="button" class="btn-link" data-close>✕</button>' +
      '<strong>' + MG.t('editRez.loc.pickOnMap') + '</strong>' +
      '<button type="button" class="btn btngreen-small" data-confirm>' + MG.t('editRez.loc.pickConfirm') + '</button>' +
    '</div>' +
    '<div class="edit-rez-map-pin">📍</div>' +
    '<div id="edit-rez-map-container"></div>' +
    '<div class="edit-rez-map-addr" id="edit-rez-map-addr"></div>';
  document.body.appendChild(ov);
  document.body.style.overflow = 'hidden';

  var center = { lat: 49.8175, lng: 15.473 };
  function init(){
    if (!window.L) return;
    var map = L.map('edit-rez-map-container', { zoomControl: true }).setView([center.lat, center.lng], 7);
    var tileUrl = (MG.MAPY_CZ_BASE || 'https://api.mapy.cz/v1') + '/maptiles/basic/256/{z}/{x}/{y}?apikey=' + MG.MAPY_CZ_KEY;
    L.tileLayer(tileUrl, { minZoom: 0, maxZoom: 19, attribution: '<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz</a>' }).addTo(map);
    var c = map.getCenter();
    var addrEl = document.getElementById('edit-rez-map-addr');
    function rev(lat, lng){
      if (!MG._mapyRgeocode) return;
      MG._mapyRgeocode(lat, lng).then(function(r){
        if (r && r.full && addrEl){ addrEl.textContent = r.full; }
      });
    }
    rev(c.lat, c.lng);
    map.on('moveend', function(){
      var c2 = map.getCenter();
      center = { lat: c2.lat, lng: c2.lng };
      rev(c2.lat, c2.lng);
    });
    ov._mgmap = map;
    ov._addrEl = addrEl;
  }
  if (!window.L){
    var css = document.createElement('link'); css.rel = 'stylesheet'; css.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(css);
    var scr = document.createElement('script'); scr.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    scr.onload = init;
    document.head.appendChild(scr);
  } else { setTimeout(init, 30); }

  function close(){ if (ov._mgmap) ov._mgmap.remove(); ov.remove(); document.body.style.overflow = ''; }
  ov.querySelector('[data-close]').addEventListener('click', close);
  ov.querySelector('[data-confirm]').addEventListener('click', function(){
    var addr = (ov._addrEl && ov._addrEl.textContent) || '';
    close();
    onConfirm({ lat: center.lat, lng: center.lng, address: addr });
  });
};

// ===== TAB: DETAIL =====
// Mapování klíčů velikostí výbavy na lidský label.
MG._editRez._GEAR_LABELS = {
  helmet: '🪖 Helma', jacket: '🧥 Bunda', pants: '👖 Kalhoty',
  boots: '🥾 Boty', gloves: '🧤 Rukavice'
};

// Z bookingu sestavíme strukturu velikostí pro řidiče i spolujezdce.
MG._editRez._collectSizes = function(b){
  var rider = {}, passenger = {};
  ['helmet','jacket','pants','boots','gloves'].forEach(function(k){
    if (b[k + '_size']) rider[k] = b[k + '_size'];
    if (b['passenger_' + k + '_size']) passenger[k] = b['passenger_' + k + '_size'];
  });
  return { rider: rider, passenger: passenger };
};

MG._editRez._gearListHtml = function(group, label){
  var keys = Object.keys(group || {});
  if (!keys.length) return '';
  var items = keys.map(function(k){
    var lbl = MG._editRez._GEAR_LABELS[k] || k;
    return '<li><span class="gear-key">' + lbl + '</span><span class="gear-val">' + group[k] + '</span></li>';
  }).join('');
  return '<div class="edit-rez-gear-block"><h5>' + label + '</h5><ul class="edit-rez-gear-list">' + items + '</ul></div>';
};

// Historie úprav z modification_history (jsonb array). Každý záznam:
//   { at, from_start, from_end, to_start, to_end, source, ... }
// Render: časová osa s ikonami (calendar / motorbike / location).
MG._editRez._historyHtml = function(b){
  var hist = Array.isArray(b.modification_history) ? b.modification_history : [];
  if (!hist.length){
    if (b.original_start_date || b.original_end_date){
      hist = [{
        at: b.created_at,
        from_start: b.original_start_date || b.start_date,
        from_end: b.original_end_date || b.end_date,
        to_start: b.start_date,
        to_end: b.end_date,
        source: 'system'
      }];
    } else {
      return '<p class="edit-rez-history-empty">Rezervace ještě nebyla upravována.</p>';
    }
  }
  // Seřadíme od nejnovější
  var sorted = hist.slice().sort(function(a, c){
    return (c.at || '').localeCompare(a.at || '');
  });
  var items = sorted.map(function(h){
    var when = h.at ? new Date(h.at).toLocaleString('cs-CZ', {
      day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'
    }) : '';
    var changes = [];
    if (h.from_start && h.to_start && h.from_start !== h.to_start){
      changes.push('📅 Začátek: <s>' + MG.formatDate(h.from_start) + '</s> → <strong>' + MG.formatDate(h.to_start) + '</strong>');
    }
    if (h.from_end && h.to_end && h.from_end !== h.to_end){
      changes.push('🏁 Konec: <s>' + MG.formatDate(h.from_end) + '</s> → <strong>' + MG.formatDate(h.to_end) + '</strong>');
    }
    if (h.from_moto_id && h.to_moto_id && h.from_moto_id !== h.to_moto_id){
      changes.push('🏍️ Motorka byla změněna');
    }
    if (h.pickup_change || h.return_change){
      changes.push('📍 Změna místa vyzvednutí / vrácení');
    }
    if (!changes.length) changes.push('Úprava rezervace');
    var src = (h.source === 'web_customer' ? 'Z webu' :
               h.source === 'app_customer' ? 'Z aplikace' :
               h.source === 'admin'        ? 'Admin' :
               h.source === 'system'       ? 'Vytvoření' : (h.source || ''));
    return '<li class="edit-rez-history-item">' +
      '<div class="edit-rez-history-dot"></div>' +
      '<div class="edit-rez-history-body">' +
        '<div class="edit-rez-history-when">' + when + (src ? ' · <span class="muted">' + src + '</span>' : '') + '</div>' +
        '<div class="edit-rez-history-changes">' + changes.join('<br>') + '</div>' +
      '</div>' +
    '</li>';
  }).join('');
  return '<ol class="edit-rez-history-list">' + items + '</ol>';
};

// Cenový rozpis — pronájem + extras + sleva + delivery + total.
MG._editRez._priceBreakdownHtml = function(b, m){
  var total = Number(b.total_price || 0);
  var extras = Number(b.extras_price || 0);
  var delivery = Number(b.delivery_fee || 0);
  var discount = Number(b.discount_amount || 0);
  // base = total + discount - extras - delivery (zpětně z toho, co máme)
  var base = total + discount - extras - delivery;
  if (base < 0) base = 0;
  var rows = [];
  rows.push(['🏍️ Pronájem motorky', MG.formatPrice(base)]);
  if (extras > 0)   rows.push(['➕ Příslušenství', MG.formatPrice(extras)]);
  if (delivery > 0) rows.push(['🚚 Přistavení / vrácení', MG.formatPrice(delivery)]);
  if (discount > 0) rows.push(['🎁 Sleva', '−' + MG.formatPrice(discount)]);
  var rowsHtml = rows.map(function(r){
    return '<div class="edit-rez-price-row"><span>' + r[0] + '</span><span>' + r[1] + '</span></div>';
  }).join('');
  return '<div class="edit-rez-price-card">' +
    rowsHtml +
    '<div class="edit-rez-price-row total"><span>Celkem zaplaceno</span><span>' + MG.formatPrice(total) + '</span></div>' +
  '</div>';
};

MG._editRez._renderTabDetail = function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var days = MG._editRez._daysBetween(b.start_date, b.end_date);
  var sizes = MG._editRez._collectSizes(b);
  var hasSizes = Object.keys(sizes.rider).length || Object.keys(sizes.passenger).length;

  // Galerie — reuse z rezervačního flow (loaduje se z pages-rezervace-steps.js)
  var galleryHtml = (typeof MG._rezGalleryHtml === 'function')
    ? MG._rezGalleryHtml(m)
    : '<div class="edit-rez-detail-img">' + (m.image_url ? '<img src="' + m.image_url + '" alt="">' : '') + '</div>';

  // Pickup / return labely
  var pickupLbl = (b.pickup_method === 'delivery')
    ? '<strong>Přistavení na adresu:</strong> ' + (b.pickup_address || '—')
    : '<strong>Vyzvednutí v půjčovně:</strong> Mezná 9, Mezná';
  var returnLbl = (b.return_method === 'delivery')
    ? '<strong>Vrácení na adrese:</strong> ' + (b.return_address || '—')
    : '<strong>Vrácení v půjčovně:</strong> Mezná 9, Mezná';

  var brandStr = (m.brand || '').trim();
  var modelStr = (m.model || '').trim();
  var motoLbl = (brandStr && modelStr.toLowerCase().indexOf(brandStr.toLowerCase()) !== 0)
    ? (brandStr + ' ' + modelStr)
    : (modelStr || brandStr || '—');
  var licReq = m.license_required && m.license_required !== 'N'
    ? '<span class="edit-rez-chip">Vyžaduje ŘP: ' + m.license_required + '</span>'
    : '<span class="edit-rez-chip">Bez ŘP</span>';

  t.innerHTML =
    '<div class="edit-rez-detail-grid">' +
      '<div class="edit-rez-detail-gallery" id="edit-rez-detail-gallery">' +
        galleryHtml +
        '<div class="edit-rez-detail-headline">' +
          '<h3>' + motoLbl + '</h3>' +
          licReq +
          '<div class="edit-rez-detail-id">Číslo rezervace <code>' + b.id.substring(0,8).toUpperCase() + '</code></div>' +
        '</div>' +
      '</div>' +
      '<aside class="edit-rez-detail-side">' +
        '<div class="edit-rez-info-item"><div class="ico">📅</div><div><div class="lbl">Termín</div>' +
          '<div class="val">' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) +
          ' <span class="muted">(' + days + (days === 1 ? ' den' : days < 5 ? ' dny' : ' dní') + ')</span></div></div></div>' +
        '<div class="edit-rez-info-item"><div class="ico">🕐</div><div><div class="lbl">Čas vyzvednutí / vrácení</div>' +
          '<div class="val">' + (b.pickup_time || '—') + ' / ' + (b.return_time || 'při vrácení v půjčovně') + '</div></div></div>' +
        '<div class="edit-rez-info-item"><div class="ico">📍</div><div><div class="lbl">Místo vyzvednutí</div>' +
          '<div class="val">' + pickupLbl + '</div></div></div>' +
        '<div class="edit-rez-info-item"><div class="ico">🏁</div><div><div class="lbl">Místo vrácení</div>' +
          '<div class="val">' + returnLbl + '</div></div></div>' +
      '</aside>' +
    '</div>' +

    '<div class="edit-rez-detail-extras">' +
      // Cenový rozpis
      '<h4 class="edit-rez-section-h">💰 Cenový rozpis</h4>' +
      MG._editRez._priceBreakdownHtml(b, m) +

      // Výbava
      (hasSizes
        ? '<h4 class="edit-rez-section-h">🎽 Výbava</h4>' +
          '<div class="edit-rez-gear-grid">' +
            MG._editRez._gearListHtml(sizes.rider, 'Řidič') +
            MG._editRez._gearListHtml(sizes.passenger, 'Spolujezdec') +
          '</div>'
        : '') +

      // Historie úprav
      '<h4 class="edit-rez-section-h">🕘 Historie úprav</h4>' +
      MG._editRez._historyHtml(b) +
    '</div>';

  // Aktivuj prev/next/dots galerie (event listenery z pages-rezervace-steps.js)
  if (typeof MG._rezInitGallery === 'function') MG._rezInitGallery();
};

// Storno podmínky box — sdílený mezi tab Storno, Zkrátit a Detail.
MG._editRez._stornoBoxHtml = function(){
  return '<aside class="edit-rez-storno-box">' +
    '<h4>' + MG.t('editRez.storno.title') + '</h4>' +
    '<ul>' +
      '<li>' + MG.t('editRez.storno.tier1') + '</li>' +
      '<li>' + MG.t('editRez.storno.tier2') + '</li>' +
      '<li>' + MG.t('editRez.storno.tier3') + '</li>' +
    '</ul>' +
    '<p class="edit-rez-storno-note">' + MG.t('editRez.storno.note') + '</p>' +
    '</aside>';
};

// ===== TAB: STORNO =====
MG._editRez._renderTabCancel = function(){
  var b = MG._editRez.selectedBooking;
  var t = document.getElementById('edit-rez-tab-content');
  // Refund se počítá podle hours-until-start (shoda s Flutter app StornoCalc).
  var percent = MG._editRez._refundPercent(b.start_date);
  var refund = Math.round(Number(b.total_price || 0) * percent / 100);

  t.innerHTML =
    '<h3>' + MG.t('editRez.cancel.title') + '</h3>' +
    '<div class="edit-rez-warn">' + MG.t('editRez.cancel.warn') + '</div>' +
    '<div class="edit-rez-refund-line refund-' + (percent === 100 ? 'full' : percent === 50 ? 'half' : 'none') + '">' +
      '<span class="lbl">' + MG.t('editRez.cancel.refundLabel') + ':</span> ' +
      '<strong>' + MG.formatPrice(refund) + '</strong> ' +
      '<span class="pct">(' + percent + '%)</span>' +
    '</div>' +
    '<form id="edit-rez-cancel-form" class="edit-rez-form" novalidate>' +
      '<label>' + MG.t('editRez.cancel.reasonLabel') +
        '<textarea name="reason" rows="3" placeholder="' + MG.t('editRez.cancel.reasonPlaceholder') + '" maxlength="500"></textarea>' +
      '</label>' +
      '<button type="submit" class="btn btnred">' + MG.t('editRez.cancel.cta') + '</button>' +
    '</form>' +
    MG._editRez._stornoBoxHtml();

  document.getElementById('edit-rez-cancel-form').addEventListener('submit', function(e){
    e.preventDefault();
    var reason = (e.currentTarget.reason.value || '').trim();
    // Inline confirm (žádný native confirm, lepší UX).
    MG._editRez._confirmDialog(MG.t('editRez.cancel.confirmTitle'), function(){
      MG._editRez._submitCancel(reason, percent, refund);
    }, { yesLabel: MG.t('editRez.cancel.confirmYes'), noLabel: MG.t('editRez.cancel.confirmNo'), danger: true });
  });
};

// ===== Inline confirm dialog =====
// opts (volitelné): { yesLabel, noLabel, danger }
//   - default labels = neutrální Ano/Ne (ne storno-ANO/storno-NE)
//   - `danger:true` udělá hlavní tlačítko červené (storno tok)
MG._editRez._confirmDialog = function(title, onYes, opts){
  opts = opts || {};
  var yesLabel = opts.yesLabel || 'Ano';
  var noLabel  = opts.noLabel  || 'Ne';
  var btnCls = opts.danger ? 'btnred' : 'btngreen';
  var existing = document.getElementById('edit-rez-confirm-overlay');
  if (existing) existing.remove();
  var ov = document.createElement('div');
  ov.id = 'edit-rez-confirm-overlay';
  ov.className = 'edit-rez-confirm-overlay';
  ov.innerHTML =
    '<div class="edit-rez-confirm-dialog" role="dialog" aria-modal="true">' +
      '<h4>' + title + '</h4>' +
      '<div class="edit-rez-confirm-actions">' +
        '<button type="button" class="btn btn-secondary" data-no>' + noLabel + '</button>' +
        '<button type="button" class="btn ' + btnCls + '" data-yes>' + yesLabel + '</button>' +
      '</div>' +
    '</div>';
  document.body.appendChild(ov);
  ov.querySelector('[data-no]').addEventListener('click', function(){ ov.remove(); });
  ov.querySelector('[data-yes]').addEventListener('click', function(){ ov.remove(); onYes(); });
  ov.addEventListener('click', function(e){ if (e.target === ov) ov.remove(); });
};

MG._editRez._submitCancel = async function(reason, percent, refund){
  if (MG._editRez.busy) return;
  var b = MG._editRez.selectedBooking;
  MG._editRez._setBusy(true);
  try {
    var r = await window.sb.rpc('cancel_booking_tracked', {
      p_booking_id: b.id,
      p_reason: reason || null
    });
    if (r.error){
      console.error('[editRez] cancel err', r.error);
      MG._editRez._showError(MG.t('editRez.err.generic'));
      return;
    }
    // Success — ukázat zprávu a vrátit na seznam.
    var msg = MG.t('editRez.cancel.success', { amount: MG.formatPrice(refund), percent: percent });
    var c = document.getElementById('edit-rez-tab-content');
    if (c) c.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + msg + '</p>'
      + '<button type="button" class="btn btngreen-small" id="edit-rez-back-list">'
      + MG.t('editRez.list.title') + '</button></div>';
    var back = document.getElementById('edit-rez-back-list');
    if (back) back.addEventListener('click', async function(){
      MG._editRez.selectedBooking = null;
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
    });
  } catch(err){
    console.error('[editRez] cancel exception', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
  }
};

// ===== AVAILABILITY (occupied dates other than this booking) =====
// Pro extend/shorten/moto-swap kontrolujeme překryv s ostatními rezervacemi
// stejné motorky a vyřazujeme tu vlastní (jinak by si zákazník nemohl posunout
// vlastní termín). RPC get_moto_booked_dates vrací jen start_date/end_date/status,
// proto identifikujeme vlastní booking přes přesný match dat NEBO přes plné
// obsažení v aktuálním rozsahu (pro případ že už byl jednou upraven a created_at
// kolize není spolehlivá). Toto je fail-open — pokud by se omylem vyhodil cizí
// booking, server-side overlap check v RPC apply_booking_changes ho zachytí.
MG._editRez._loadOccupied = async function(p_moto_id){
  var b = MG._editRez.selectedBooking;
  var motoId = p_moto_id || (b && b.moto_id);
  if (!motoId) return [];
  try {
    var r = await window.sb.rpc('get_moto_booked_dates', { p_moto_id: motoId });
    if (r.error){ console.warn('[editRez] occupied err', r.error); return []; }
    // Normalizujeme všechny date stringy z RPC na čistý YYYY-MM-DD,
    // aby string-compare s b.start_date nešel mimo (timestamptz vs date).
    var nz = MG._editRez._normIso;
    var data = (r.data || []).map(function(x){
      return { start_date: nz(x.start_date), end_date: nz(x.end_date), status: x.status };
    });
    if (!b || p_moto_id && p_moto_id !== b.moto_id) return data;
    var bs = nz(b.start_date), be = nz(b.end_date);
    return data.filter(function(x){
      // 1) Přesný match původního rozsahu = vlastní booking
      if (x.start_date === bs && x.end_date === be) return false;
      // 2) Záznam plně uvnitř původního rozsahu = vlastní booking po dřívější úpravě
      if (x.start_date >= bs && x.end_date <= be) return false;
      return true;
    });
  } catch(e){ return []; }
};

// Cena za rozsah — duplikát logiky z api.js MG.calcPrice, ale pracujeme s motorkou
// předanou (může chybět v cache). Inclusive start+end.
MG._editRez._priceForRange = function(moto, startIso, endIso){
  if (!moto || !startIso || !endIso) return 0;
  var s = new Date(startIso), e = new Date(endIso);
  if (s > e) return 0;
  var days = ['sun','mon','tue','wed','thu','fri','sat'];
  var d = new Date(s); var total = 0;
  while (d <= e){
    var k = 'price_' + days[d.getDay()];
    var p = Number(moto[k] || moto.price_weekday || 0);
    total += p;
    d.setDate(d.getDate() + 1);
  }
  return total;
};

// Detekce překryvu rozsahu se seznamem occupied (každý je {start_date,end_date}).
MG._editRez._rangeOverlapsOccupied = function(startIso, endIso, occupied){
  return (occupied || []).some(function(o){
    return !(endIso < o.start_date || startIso > o.end_date);
  });
};

// ===== UNIFIED CALENDAR PICKER (extend / shorten) =====
// 1:1 chování jako Flutter EditReservationCalendar:
//   • EXTEND: kliknutí PŘED origStart posune začátek dříve (zachová konec);
//             kliknutí ZA origEnd posune konec později (zachová začátek);
//             kliknutí UVNITŘ původního rozsahu = chyba (toto je rezervace);
//             re-klik na již prodloužený okraj → reset na původní termín;
//             u active rezervace lze posouvat jen konec (start zamčený).
//   • SHORTEN: kliknutí UVNITŘ rezervace zkrátí podle vybraného směru;
//             u upcoming je třeba nejdřív zvolit Začátek nebo Konec;
//             u active se zkracuje pouze konec (vrácení dříve).
//
// opts = {
//   container,                          // HTMLElement
//   mode: 'extend' | 'shorten',
//   isActive: bool,                     // probíhající rezervace (jiná pravidla)
//   origStart, origEnd: 'YYYY-MM-DD',   // původní rezervace
//   newStart, newEnd: 'YYYY-MM-DD',     // aktuální výběr (na startu = orig)
//   occupied: [{start_date,end_date}],  // cizí rezervace, bez vlastní
//   shortenDir: 'start'|'end'|null,     // jen pro shorten upcoming
//   onChange(s, e),                     // emit nového výběru
//   onError(message)                    // toast zpráva (zobrazí se nahoře v banneru)
// }
MG._editRez._renderRangeCalendar = function(opts){
  var state = { pivotYear: 0, pivotMonth: 0 };
  var anchor = opts.newStart || opts.origStart;
  var ad = anchor ? new Date(anchor) : new Date();
  state.pivotYear = ad.getFullYear();
  state.pivotMonth = ad.getMonth();

  var monthsCs = ['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'];
  var dayN = ['Po','Út','St','Čt','Pá','So','Ne'];

  function iso(y,m,d){ return y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0'); }
  function todayIso(){ var t=new Date(); return iso(t.getFullYear(),t.getMonth(),t.getDate()); }
  function inOrig(ds){ return opts.origStart && opts.origEnd && ds >= opts.origStart && ds <= opts.origEnd; }
  function inNew(ds){
    if (!opts.newStart || !opts.newEnd) return false;
    return ds >= opts.newStart && ds <= opts.newEnd;
  }
  function isOccupied(ds){
    return (opts.occupied||[]).some(function(o){ return ds >= o.start_date && ds <= o.end_date; });
  }
  function isPast(ds){ return ds < todayIso(); }
  function rangeFreeForExtension(fromIso, toIso){
    // Vrací false pokud nějaký den v rozsahu je obsazený cizí rezervací
    // (vlastní origRange ignorujeme).
    var d = new Date(fromIso), end = new Date(toIso);
    while (d <= end){
      var ds = iso(d.getFullYear(), d.getMonth(), d.getDate());
      if (isOccupied(ds) && !inOrig(ds)) return false;
      d.setDate(d.getDate()+1);
    }
    return true;
  }
  function fmtCs(isoStr){
    if (!isoStr) return '';
    var p = isoStr.split('-');
    return parseInt(p[2],10) + '.' + parseInt(p[1],10) + '.' + p[0];
  }
  function err(msg){ if (typeof opts.onError === 'function') opts.onError(msg); }
  function emit(s, e){
    opts.newStart = s || null; opts.newEnd = e || null;
    if (typeof opts.onChange === 'function') opts.onChange(s, e);
    render();
  }

  function pick(ds){
    if (isPast(ds)){ err('Nelze vybrat datum v minulosti.'); return; }
    if (isOccupied(ds) && !inOrig(ds)){ err('Tento den je obsazený jinou rezervací.'); return; }
    if (opts.mode === 'shorten') return handleShorten(ds);
    return handleExtend(ds);
  }

  function handleExtend(ds){
    var origS = opts.origStart, origE = opts.origEnd;
    var curS = opts.newStart || origS;
    var curE = opts.newEnd || origE;

    // Re-klik na již prodloužený okraj → reset na původní termín
    var hasExt = curS !== origS || curE !== origE;
    if (hasExt){
      var isExtStart = ds === curS && curS < origS;
      var isExtEnd = ds === curE && curE > origE;
      if (isExtStart || isExtEnd){ emit(origS, origE); return; }
    }

    // Klik PŘED origStart
    if (ds < origS){
      if (opts.isActive){
        err('U probíhající rezervace nelze měnit datum vyzvednutí. Klikněte na den po ' + fmtCs(origE) + '.');
        return;
      }
      // Upcoming: posun začátku dříve. Ověř volnost úseku <ds, origS-1>.
      var prevDay = new Date(origS); prevDay.setDate(prevDay.getDate()-1);
      var prevIso = iso(prevDay.getFullYear(), prevDay.getMonth(), prevDay.getDate());
      if (ds <= prevIso && !rangeFreeForExtension(ds, prevIso)){
        err('Mezi vybraným datem a začátkem rezervace jsou obsazené dny.'); return;
      }
      emit(ds, curE); return;
    }

    // Klik UVNITŘ původního rozsahu → toto je vaše rezervace, neklikatelné
    if (ds >= origS && ds <= origE){
      if (opts.isActive){
        err('Pro prodloužení klikněte na den po ' + fmtCs(origE) + '.');
      } else {
        err('Toto je vaše rezervace. Pro prodloužení klikněte na den před ' + fmtCs(origS) + ' nebo po ' + fmtCs(origE) + '.');
      }
      return;
    }

    // Klik ZA origEnd → posun konce později
    if (ds > origE){
      var nextDay = new Date(origE); nextDay.setDate(nextDay.getDate()+1);
      var nextIso = iso(nextDay.getFullYear(), nextDay.getMonth(), nextDay.getDate());
      if (nextIso <= ds && !rangeFreeForExtension(nextIso, ds)){
        err('Mezi koncem rezervace a vybraným datem jsou obsazené dny.'); return;
      }
      emit(curS, ds);
    }
  }

  function handleShorten(ds){
    var origS = opts.origStart, origE = opts.origEnd;
    var inRes = ds >= origS && ds <= origE;
    if (!inRes){ err('Pro zkrácení klikněte uvnitř vaší rezervace.'); return; }
    var curS = opts.newStart || origS;
    var curE = opts.newEnd || origE;
    var hasSh = curS !== origS || curE !== origE;

    // Re-klik na zkrácený okraj → reset
    if (hasSh){
      if (opts.isActive && ds === curE){ emit(origS, origE); return; }
      if (!opts.isActive){
        var dir = opts.shortenDir;
        if (dir === 'start' && ds === curS && curS > origS){ emit(origS, origE); return; }
        if (dir === 'end' && ds === curE && curE < origE){ emit(origS, origE); return; }
      }
    }

    if (opts.isActive){
      // Pouze konec lze zkrátit; nový konec nesmí být >= origE a >= dnešek
      if (ds >= origE){ err('Pro zkrácení klikněte na den před ' + fmtCs(origE) + '.'); return; }
      if (ds < todayIso()){ err('Nelze zkrátit do minulosti.'); return; }
      emit(origS, ds); return;
    }

    // Upcoming → potřebujeme vybraný směr
    var dirU = opts.shortenDir;
    if (!dirU){ err('Nejdříve vyberte, jestli chcete zkrátit Začátek, nebo Konec.'); return; }
    if (dirU === 'start'){
      var newS = ds > origS ? ds : origS;
      if (newS > origE){ err('Začátek nesmí být po konci.'); return; }
      emit(newS, origE);
    } else {
      var newE = ds < origE ? ds : origE;
      if (newE < origS){ err('Konec nesmí být před začátkem.'); return; }
      emit(origS, newE);
    }
  }

  function getCellInfo(ds){
    var cls = ['erez-cal-day'];
    if (isPast(ds)){ cls.push('past'); return cls; }
    if (isOccupied(ds) && !inOrig(ds)){ cls.push('occ'); return cls; }
    if (opts.mode === 'extend'){
      if (inOrig(ds)){ cls.push('orig'); return cls; }
      if (inNew(ds) && !inOrig(ds)){
        cls.push('extension');
        if (ds === opts.newStart) cls.push('extension-start');
        if (ds === opts.newEnd) cls.push('extension-end');
        return cls;
      }
      cls.push('free'); return cls;
    }
    // SHORTEN
    if (inOrig(ds) && inNew(ds)){
      cls.push('keep');
      if (ds === opts.newStart) cls.push('keep-start');
      if (ds === opts.newEnd) cls.push('keep-end');
      return cls;
    }
    if (inOrig(ds) && !inNew(ds)){
      cls.push('removed');
      if (ds === opts.origStart) cls.push('keep-start');
      if (ds === opts.origEnd) cls.push('keep-end');
      return cls;
    }
    if (inOrig(ds) && !opts.newStart){ cls.push('keep'); return cls; }
    cls.push('free-out'); return cls; // mimo rezervaci u shorten — neklikatelné
  }

  function renderMonth(y, m){
    var first = new Date(y,m,1), last = new Date(y,m+1,0);
    var dow = (first.getDay()+6)%7; // Po=0
    var h = '<div class="erez-cal-month"><div class="erez-cal-mhead">'+monthsCs[m]+' '+y+'</div>';
    h += '<div class="erez-cal-grid">';
    dayN.forEach(function(d){ h += '<div class="erez-cal-dn">'+d+'</div>'; });
    for(var i=0;i<dow;i++) h += '<div class="erez-cal-empty"></div>';
    var ti = todayIso();
    for(var d=1; d<=last.getDate(); d++){
      var ds = iso(y,m,d);
      var cls = getCellInfo(ds);
      if (ds === ti) cls.push('today');
      h += '<div class="'+cls.join(' ')+'" data-ds="'+ds+'"><span>'+d+'</span></div>';
    }
    h += '</div></div>';
    return h;
  }

  function shiftMonth(delta){
    state.pivotMonth += delta;
    while(state.pivotMonth < 0){ state.pivotMonth += 12; state.pivotYear--; }
    while(state.pivotMonth > 11){ state.pivotMonth -= 12; state.pivotYear++; }
    render();
  }

  function legendHtml(){
    if (opts.mode === 'shorten'){
      return '<div class="erez-cal-legend">' +
        '<span><i class="dot dot-keep"></i> Zachováno</span>' +
        '<span><i class="dot dot-removed"></i> Zkráceno</span>' +
        '<span><i class="dot dot-occ"></i> Mimo rezervaci</span>' +
        '</div>';
    }
    return '<div class="erez-cal-legend">' +
      '<span><i class="dot dot-free"></i> Volné</span>' +
      '<span><i class="dot dot-orig"></i> Tato rezervace</span>' +
      '<span><i class="dot dot-extension"></i> Prodloužení</span>' +
      '<span><i class="dot dot-occ"></i> Obsazené</span>' +
      '</div>';
  }

  function render(){
    var y = state.pivotYear, m = state.pivotMonth;
    opts.container.innerHTML =
      '<div class="erez-cal-wrap">' +
        '<div class="erez-cal-nav">' +
          '<button type="button" class="erez-cal-navbtn" data-prev aria-label="Předchozí měsíc">‹</button>' +
          '<span class="erez-cal-navtitle">' + monthsCs[m] + ' ' + y + '</span>' +
          '<button type="button" class="erez-cal-navbtn" data-next aria-label="Další měsíc">›</button>' +
        '</div>' +
        '<div class="erez-cal-single">' + renderMonth(y, m) + '</div>' +
        legendHtml() +
      '</div>';
    var prev = opts.container.querySelector('[data-prev]');
    var next = opts.container.querySelector('[data-next]');
    if (prev) prev.addEventListener('click', function(){ shiftMonth(-1); });
    if (next) next.addEventListener('click', function(){ shiftMonth(1); });
    opts.container.querySelectorAll('.erez-cal-day').forEach(function(el){
      el.addEventListener('click', function(){ pick(el.getAttribute('data-ds')); });
    });
  }

  // Inject styles once
  if (!document.getElementById('erez-cal-styles')){
    var st = document.createElement('style');
    st.id = 'erez-cal-styles';
    st.textContent =
      '.erez-cal-wrap{background:#fff;border:1px solid #d4e8e0;border-radius:18px;padding:1rem;margin:.6rem 0 1rem;box-shadow:0 4px 14px rgba(20,80,40,.06);font-family:Montserrat,sans-serif}'+
      '.erez-cal-nav{display:flex;align-items:center;justify-content:space-between;margin-bottom:.7rem}'+
      '.erez-cal-navbtn{background:#1a8c1a;color:#fff;border:none;width:38px;height:38px;border-radius:999px;cursor:pointer;font-size:1.4rem;line-height:1;font-weight:700;display:inline-flex;align-items:center;justify-content:center;transition:transform .12s}'+
      '.erez-cal-navbtn:hover{transform:scale(1.06);background:#147214}'+
      '.erez-cal-navtitle{font-weight:800;font-size:1.05rem;color:#1a2e22;text-align:center;flex:1}'+
      '.erez-cal-single{max-width:520px;margin:0 auto}'+
      '.erez-cal-mhead{text-align:center;font-weight:700;color:#1a2e22;margin:.2rem 0 .55rem;font-size:.95rem;letter-spacing:.02em}'+
      '.erez-cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}'+
      '.erez-cal-dn{font-size:.7rem;color:#7d978a;text-align:center;font-weight:700;padding:.2rem 0;letter-spacing:.04em;text-transform:uppercase}'+
      '.erez-cal-empty{}'+
      '.erez-cal-day{aspect-ratio:1/1;display:flex;align-items:center;justify-content:center;border-radius:10px;font-weight:700;font-size:.92rem;transition:transform .1s, box-shadow .1s, background .1s;user-select:none}'+
      /* extend mode */
      '.erez-cal-day.free{background:#74FB71;color:#0b0b0b;cursor:pointer}'+
      '.erez-cal-day.free:hover{transform:scale(1.07);box-shadow:0 3px 8px rgba(26,140,26,.25)}'+
      '.erez-cal-day.orig{background:#bce6c9;color:#0b3a18;border:1.5px dashed #1a8c1a;cursor:not-allowed}'+
      '.erez-cal-day.extension{background:#0f5e0f;color:#fff;cursor:pointer}'+
      '.erez-cal-day.extension:hover{box-shadow:0 0 0 2px #74FB71}'+
      '.erez-cal-day.extension-start, .erez-cal-day.extension-end{box-shadow:0 0 0 2px #74FB71}'+
      /* shorten mode */
      '.erez-cal-day.keep{background:#1a8c1a;color:#fff;cursor:pointer;font-weight:800}'+
      '.erez-cal-day.keep:hover{transform:scale(1.07);box-shadow:0 3px 8px rgba(26,140,26,.35)}'+
      '.erez-cal-day.keep-start{border-top-left-radius:50% 100%;border-bottom-left-radius:50% 100%}'+
      '.erez-cal-day.keep-end{border-top-right-radius:50% 100%;border-bottom-right-radius:50% 100%}'+
      '.erez-cal-day.removed{background:#e74c3c;color:#fff;cursor:pointer;text-decoration:line-through;font-weight:800}'+
      '.erez-cal-day.removed:hover{transform:scale(1.07)}'+
      '.erez-cal-day.free-out{background:#2e2e2e;color:#9aa8a0;cursor:not-allowed;opacity:.85}'+
      /* shared */
      '.erez-cal-day.occ{background:#444;color:#fff;cursor:not-allowed}'+
      '.erez-cal-day.past{background:#3a3a3a;color:#fff;cursor:not-allowed;opacity:.6}'+
      '.erez-cal-day.today{outline:2px solid #1a8c1a;outline-offset:-2px}'+
      '.erez-cal-legend{display:flex;flex-wrap:wrap;gap:.6rem 1.1rem;margin-top:.85rem;font-size:.78rem;color:#3a4a40}'+
      '.erez-cal-legend .dot{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:.3rem;vertical-align:middle}'+
      '.erez-cal-legend .dot-free{background:#74FB71}'+
      '.erez-cal-legend .dot-orig{background:#bce6c9;border:1.5px dashed #1a8c1a}'+
      '.erez-cal-legend .dot-extension{background:#0f5e0f}'+
      '.erez-cal-legend .dot-keep{background:#1a8c1a}'+
      '.erez-cal-legend .dot-removed{background:#e74c3c}'+
      '.erez-cal-legend .dot-occ{background:#2e2e2e}'+
      '.erez-range-banner{background:#74FB71;color:#0b0b0b;padding:.7rem 1rem;border-radius:18px;margin:.4rem 0 .8rem;font-weight:700;display:flex;justify-content:space-between;flex-wrap:wrap;gap:.4rem;align-items:center}'+
      '.erez-range-banner.warn{background:#fff3cd;color:#7a5a00}'+
      '.erez-range-banner.error{background:#ffe0e0;color:#7a1a1a}'+
      '.erez-range-banner .erez-clear{background:#0b0b0b;color:#74FB71;padding:.35rem .8rem;border-radius:14px;cursor:pointer;font-size:.78rem;border:none;font-weight:700}'+
      '.erez-shorten-dirs{display:grid;grid-template-columns:1fr 1fr;gap:.5rem;margin:.4rem 0 .8rem}'+
      '.erez-shorten-dirs button{background:#eef3f0;color:#3a4a40;border:1.5px solid #d4e8e0;border-radius:14px;padding:.7rem .6rem;cursor:pointer;font-weight:700;font-size:.92rem;font-family:Montserrat,sans-serif;transition:all .15s}'+
      '.erez-shorten-dirs button:hover{background:#dcefe2;border-color:#1a8c1a}'+
      '.erez-shorten-dirs button.active{background:#1a8c1a;color:#fff;border-color:#1a8c1a}'+
      /* manuální zadání datumů */
      '.erez-dates-manual{display:grid;grid-template-columns:1fr 1fr;gap:.7rem;margin-bottom:.5rem}'+
      '@media(max-width:520px){.erez-dates-manual{grid-template-columns:1fr}}'+
      '.erez-date-field{display:flex;flex-direction:column;gap:.25rem}'+
      '.erez-date-field>span{font-size:.78rem;font-weight:700;color:#1a2e22;letter-spacing:.03em;text-transform:uppercase}'+
      '.erez-date-field.locked>span::after{content:" (zamčeno)";color:#9aa8a0;font-weight:500;text-transform:none}'+
      '.erez-date-input{padding:.7rem .9rem;border:1.5px solid #d4e8e0;border-radius:12px;font-family:Montserrat,sans-serif;font-size:1rem;font-weight:700;color:#1a2e22;background:#fafdfb;letter-spacing:.05em;transition:all .15s;text-align:center}'+
      '.erez-date-input:focus{outline:none;border-color:#1a8c1a;background:#fff;box-shadow:0 0 0 3px rgba(26,140,26,.12)}'+
      '.erez-date-input.invalid{border-color:#c0392b;background:#ffebe7}'+
      '.erez-date-input[readonly]{background:#eef3f0;color:#9aa8a0;cursor:not-allowed}'+
      '.erez-dates-help{font-size:.75rem;color:#6a7a70;margin:-.2rem 0 .6rem;text-align:center}';
    document.head.appendChild(st);
  }

  render();
  return {
    setSelection: function(s, e){ opts.newStart = s||null; opts.newEnd = e||null; render(); },
    getSelection: function(){ return { start: opts.newStart, end: opts.newEnd }; },
    showMonth: function(year, month){ state.pivotYear = year; state.pivotMonth = month; render(); },
    setShortenDir: function(dir){ opts.shortenDir = dir || null; render(); }
  };
};

// ===== MANUAL DATE INPUT (DD.MM.RRRR) =====
// Pomocná funkce pro hezká pole "Nový začátek / Nový konec" — synchronizovaná
// s kalendářem. Auto-format na blur (DD.MM.YYYY → ISO YYYY-MM-DD).
//
// Backend někdy posílá `start_date` / `end_date` jako date (YYYY-MM-DD), jindy
// jako timestamptz (YYYY-MM-DDTHH:MM:SS+00:00). Všechny date-helpery i kalendář
// porovnávají datumy jako stringy → stačí, když se jeden ze stringů má příponu
// času, a porovnání leetne ven (`'2026-05-01' < '2026-05-01T00:00:00+00:00'`).
// Proto všechno přicházející datum nejdřív protáhneme tímhle normalizátorem.
MG._editRez._normIso = function(d){
  if (!d) return '';
  var s = String(d);
  // ISO timestamp / timestamptz → utneme na 'YYYY-MM-DD'
  if (s.length >= 10 && /^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  // Date object
  if (d instanceof Date && !isNaN(d.getTime())){
    return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
  }
  // Fallback: zkusíme přes Date constructor
  var dt = new Date(s);
  if (!isNaN(dt.getTime())){
    return dt.getFullYear() + '-' + String(dt.getMonth()+1).padStart(2,'0') + '-' + String(dt.getDate()).padStart(2,'0');
  }
  return '';
};
MG._editRez._isoToCs = function(iso){
  var norm = MG._editRez._normIso(iso);
  if (!norm) return '';
  var p = norm.split('-');
  if (p.length !== 3) return '';
  return p[2] + '.' + p[1] + '.' + p[0];
};
MG._editRez._csToIso = function(cs){
  if (!cs) return '';
  var s = cs.replace(/\s+/g,'').replace(/-/g,'.').replace(/\//g,'.');
  var p = s.split('.');
  if (p.length !== 3) return '';
  var d = p[0].padStart(2,'0'), m = p[1].padStart(2,'0'), y = p[2];
  if (y.length === 2) y = '20' + y;
  if (!/^\d{4}$/.test(y) || !/^\d{2}$/.test(m) || !/^\d{2}$/.test(d)) return '';
  // sanity
  var dt = new Date(y+'-'+m+'-'+d);
  if (isNaN(dt.getTime())) return '';
  if (dt.getFullYear() != y || (dt.getMonth()+1) != parseInt(m,10) || dt.getDate() != parseInt(d,10)) return '';
  return y+'-'+m+'-'+d;
};

// Vykreslí dvojici inputů "Nový začátek" + "Nový konec" do containeru.
// opts: { container, startIso, endIso, minIso, maxIso, minEndIso, maxEndIso,
//         lockStart, onChange(start,end) }
// minIso/maxIso platí pro START; minEndIso/maxEndIso pro END (fallback minIso/maxIso).
MG._editRez._renderManualDates = function(opts){
  var minStartIso = opts.minIso || '';
  var maxStartIso = opts.maxIso || '';
  var minEndIso = opts.minEndIso || opts.minIso || '';
  var maxEndIso = opts.maxEndIso || opts.maxIso || '';
  var startHelp = (minStartIso || maxStartIso)
    ? 'Začátek: ' + (minStartIso ? MG._editRez._isoToCs(minStartIso) : '–') + ' – ' + (maxStartIso ? MG._editRez._isoToCs(maxStartIso) : '–')
    : '';
  var endHelp = (minEndIso || maxEndIso)
    ? 'Konec: ' + (minEndIso ? MG._editRez._isoToCs(minEndIso) : '–') + ' – ' + (maxEndIso ? MG._editRez._isoToCs(maxEndIso) : '–')
    : '';
  var rangeHelp = (startHelp || endHelp)
    ? '<small class="muted">' + [startHelp, endHelp].filter(Boolean).join(' · ') + '</small>'
    : '';
  opts.container.innerHTML =
    '<div class="erez-dates-manual">' +
      '<label class="erez-date-field' + (opts.lockStart ? ' locked' : '') + '">' +
        '<span>Nový začátek</span>' +
        '<input type="text" class="erez-date-input" data-which="start" placeholder="DD.MM.RRRR" inputmode="numeric" value="' +
          MG._editRez._isoToCs(opts.startIso || '') + '"' + (opts.lockStart ? ' readonly' : '') + '>' +
      '</label>' +
      '<label class="erez-date-field">' +
        '<span>Nový konec</span>' +
        '<input type="text" class="erez-date-input" data-which="end" placeholder="DD.MM.RRRR" inputmode="numeric" value="' +
          MG._editRez._isoToCs(opts.endIso || '') + '">' +
      '</label>' +
    '</div>' +
    (rangeHelp ? '<div class="erez-dates-help">' + rangeHelp + '</div>' : '');

  function applyValue(input){
    var which = input.getAttribute('data-which');
    var iso = MG._editRez._csToIso(input.value);
    if (!iso){ input.classList.add('invalid'); return; }
    var lo = which === 'start' ? minStartIso : minEndIso;
    var hi = which === 'start' ? maxStartIso : maxEndIso;
    if (lo && iso < lo){ input.classList.add('invalid'); return; }
    if (hi && iso > hi){ input.classList.add('invalid'); return; }
    input.classList.remove('invalid');
    input.value = MG._editRez._isoToCs(iso);  // normalizovaný formát
    if (typeof opts.onChange === 'function') opts.onChange(which, iso);
  }
  opts.container.querySelectorAll('.erez-date-input').forEach(function(inp){
    if (inp.readOnly) return;
    // Auto-format jen číslic při psaní
    inp.addEventListener('input', function(){
      var v = inp.value.replace(/[^\d]/g,'').slice(0,8);
      if (v.length >= 5) v = v.slice(0,2) + '.' + v.slice(2,4) + '.' + v.slice(4);
      else if (v.length >= 3) v = v.slice(0,2) + '.' + v.slice(2);
      inp.value = v;
    });
    inp.addEventListener('blur', function(){ applyValue(inp); });
    inp.addEventListener('keydown', function(e){ if (e.key === 'Enter'){ e.preventDefault(); applyValue(inp); } });
  });
  return {
    setStart: function(iso){
      var i = opts.container.querySelector('[data-which=start]');
      if (i) i.value = MG._editRez._isoToCs(iso || '');
    },
    setEnd: function(iso){
      var i = opts.container.querySelector('[data-which=end]');
      if (i) i.value = MG._editRez._isoToCs(iso || '');
    }
  };
};

// ===== TAB: PROLONGATION =====
// Aktivní rezervace: měnit lze JEN end_date (start je zamčený).
// Reserved: měnit lze obojí (dříve začít / později skončit).
// UI: kalendář s dnem před začátkem / po konci pro prodloužení (1:1 jako
// Flutter EditReservationCalendar) + alternativní manuální zadání data.
MG._editRez._renderTabExtend = async function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var isActive = (b.status === 'active');
  var todayIso = MG._editRez._toIsoDate(new Date());
  // Backend može vrátit start_date/end_date jako timestamptz; všude porovnáváme
  // jako stringy, takže normalizujeme na čistý YYYY-MM-DD jednou na startu.
  var origStart = MG._editRez._normIso(b.start_date);
  var origEnd = MG._editRez._normIso(b.end_date);

  // Strop pro extend: rok dopředu (víc nedává smysl + brzdí render).
  var maxIsoDate = (function(){
    var d = new Date(); d.setFullYear(d.getFullYear()+1);
    return MG._editRez._toIsoDate(d);
  })();

  // Kontextová nápověda — jasně co se kliká
  var helpHtml = isActive
    ? 'V kalendáři klikněte na <strong>den po ' + MG.formatDate(origEnd)
        + '</strong> — prodlouží se vrácení o tento počet dní. Začátek (' + MG.formatDate(origStart)
        + ') už nelze měnit, protože rezervace už běží.'
    : 'V kalendáři klikněte na <strong>den před ' + MG.formatDate(origStart)
        + '</strong> (vyzvednutí dříve) <em>nebo</em> na <strong>den po ' + MG.formatDate(origEnd)
        + '</strong> (vrácení později). Můžete prodloužit obě strany.';

  t.innerHTML =
    '<h3>' + MG.t('editRez.extend.title') + '</h3>' +
    '<p>' + helpHtml + '</p>' +
    '<div id="edit-rez-extend-banner" class="erez-range-banner" style="display:none"></div>' +
    '<div id="edit-rez-extend-manual"></div>' +
    '<div id="edit-rez-extend-cal"></div>' +
    '<form id="edit-rez-extend-form" class="edit-rez-form" novalidate>' +
      '<input type="hidden" name="newStart" value="' + origStart + '">' +
      '<input type="hidden" name="newEnd"   value="' + origEnd   + '">' +
      '<div id="edit-rez-extend-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen" id="edit-rez-extend-cta" disabled>' + MG.t('editRez.extend.cta') + '</button>' +
    '</form>';

  var occupied = (await MG._editRez._loadOccupied()).map(function(o){
    return { start_date: MG._editRez._normIso(o.start_date), end_date: MG._editRez._normIso(o.end_date), status: o.status };
  });
  var f = document.getElementById('edit-rez-extend-form');
  var banner = document.getElementById('edit-rez-extend-banner');

  function showError(msg){
    banner.className = 'erez-range-banner error';
    banner.style.display='flex';
    banner.innerHTML = '<span>⚠️ ' + msg + '</span>' +
      '<button type="button" class="erez-clear">✕</button>';
    var btn = banner.querySelector('.erez-clear');
    if (btn) btn.addEventListener('click', function(){ updateBanner(f.newStart.value, f.newEnd.value); });
  }

  function updateBanner(ns, ne){
    banner.className = 'erez-range-banner';
    if (!ns || !ne || (ns === origStart && ne === origEnd)){
      banner.style.display='none'; banner.innerHTML='';
      return;
    }
    banner.style.display='flex';
    banner.innerHTML = '<span>Nový termín: <strong>'+MG.formatDate(ns)+' – '+MG.formatDate(ne)+'</strong></span>' +
      '<button type="button" class="erez-clear">✕ Zrušit</button>';
    var btn = banner.querySelector('.erez-clear');
    if (btn) btn.addEventListener('click', function(){
      cal.setSelection(origStart, origEnd);
      onChange(origStart, origEnd);
    });
  }

  function recalc(ns, ne){
    var summary = document.getElementById('edit-rez-extend-summary');
    var cta = document.getElementById('edit-rez-extend-cta');
    if (!ns || !ne || ns > ne){
      summary.textContent = ''; cta.disabled = true; return;
    }
    var noChange = (ns === origStart && ne === origEnd);
    if (noChange){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true; return;
    }
    // Pojistka — kalendář a manuál by toto neměly nikdy dovolit, ale držíme
    // serverside pravidlo: extend = nový rozsah obsahuje původní.
    if (ns > origStart || ne < origEnd){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.err.notExtending') + '</span>';
      cta.disabled = true; return;
    }
    if (MG._editRez._rangeOverlapsOccupied(ns, ne, occupied)){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.extend.unavailable') + '</span>';
      cta.disabled = true; return;
    }
    var origPrice = MG._editRez._priceForRange(m, origStart, origEnd);
    var newPrice  = MG._editRez._priceForRange(m, ns, ne);
    var diff = Math.max(0, Math.round(newPrice - origPrice));
    summary.innerHTML = '<div class="line"><span class="lbl">' + MG.t('editRez.extend.priceDiff') + ':</span> ' +
      '<strong>' + MG.formatPrice(diff) + '</strong></div>';
    cta.disabled = (diff <= 0);
  }

  // Pravidla extend (1:1 jako Flutter app):
  //  - upcoming (reserved): start lze posunout DŘÍVE (max do dneška), end POZDĚJI
  //  - active: start zamčený = origStart, end posunout POZDĚJI
  var manual = MG._editRez._renderManualDates({
    container: document.getElementById('edit-rez-extend-manual'),
    startIso: origStart, endIso: origEnd,
    // Manuální start: od dneška do origStart (nelze posunout pozdějc — to by zkracovalo)
    minIso: isActive ? origStart : todayIso,
    maxIso: origStart,
    // Manuální end: od origEnd do +1 rok (nelze posunout dřív)
    minEndIso: origEnd,
    maxEndIso: maxIsoDate,
    lockStart: isActive,
    onChange: function(which, iso){
      var ns = (which === 'start') ? iso : f.newStart.value;
      var ne = (which === 'end')   ? iso : f.newEnd.value;
      cal.setSelection(ns, ne);
      var d = new Date(iso);
      cal.showMonth(d.getFullYear(), d.getMonth());
      onChange(ns, ne);
    }
  });

  function onChange(s, e){
    f.newStart.value = s || '';
    f.newEnd.value = e || '';
    if (manual){ manual.setStart(s); manual.setEnd(e); }
    updateBanner(s, e);
    recalc(s, e);
  }

  var cal = MG._editRez._renderRangeCalendar({
    container: document.getElementById('edit-rez-extend-cal'),
    mode: 'extend',
    isActive: isActive,
    origStart: origStart,
    origEnd: origEnd,
    newStart: origStart,
    newEnd: origEnd,
    occupied: occupied,
    onChange: onChange,
    onError: showError
  });
  onChange(origStart, origEnd);

  f.addEventListener('submit', function(e){
    e.preventDefault();
    if (MG._editRez.busy) return;
    MG._editRez._submitExtend(f.newStart.value, f.newEnd.value);
  });
};

// Pošle požadavek na Stripe Checkout přes Edge funkci `process-payment`.
// Pending změny (nové datumy) ukládáme do localStorage; po návratu na
// success_url je _applyPendingAfterPayment() aplikuje na booking přes RLS.
MG._editRez._submitExtend = async function(newStart, newEnd){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var origPrice = MG._editRez._priceForRange(m, MG._editRez._normIso(b.start_date), MG._editRez._normIso(b.end_date));
  var newPrice  = MG._editRez._priceForRange(m, newStart, newEnd);
  var diff = Math.round(newPrice - origPrice);
  if (diff <= 0){ MG._editRez._showError(MG.t('editRez.err.invalidRange')); return; }

  var cta = document.getElementById('edit-rez-extend-cta');
  var origLabel = cta ? cta.textContent : '';
  if (cta){ cta.disabled = true; cta.textContent = MG.t('editRez.extend.creating'); }
  MG._editRez._setBusy(true);
  try {
    // Uložíme pending pro post-Stripe handler.
    try {
      localStorage.setItem('editRez_pending_' + b.id, JSON.stringify({
        payload: { p_new_start: newStart, p_new_end: newEnd },
        ts: Date.now()
      }));
    } catch(e){}
    var sess = await window.sb.auth.getSession();
    var token = sess && sess.data && sess.data.session && sess.data.session.access_token;
    if (!token) throw new Error('no-auth');
    var url = window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment';
    var resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token,
        'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({
        type: 'extension',
        booking_id: b.id,
        amount: diff,
        success_url: window.location.origin + '/upravit-rezervaci?paid_booking=' + b.id,
        cancel_url:  window.location.origin + '/upravit-rezervaci'
      })
    });
    var data = await resp.json().catch(function(){ return null; });
    if (!resp.ok || !data || !data.url){
      console.error('[editRez] extend payment err', resp.status, data);
      MG._editRez._showError((data && data.error) ? data.error : MG.t('editRez.err.generic'));
      try { localStorage.removeItem('editRez_pending_' + b.id); } catch(e){}
      return;
    }
    window.location.href = data.url;
  } catch(err){
    console.error('[editRez] extend exception', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
    if (cta){ cta.disabled = false; cta.textContent = origLabel; }
  }
};

// ===== TAB: SHORTEN =====
// Aktivní rezervace: měnit lze JEN end_date (vrátit dříve).
// Reserved: měnit lze obojí (později začít / dříve skončit), ale uživatel
// musí nejdřív zvolit, kterou stranu chce zkrátit (1:1 jako Flutter app).
MG._editRez._renderTabShorten = function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var isActive = (b.status === 'active');
  // Backend posílá start_date/end_date někdy jako date, někdy jako timestamptz —
  // všechno protáhneme normalizátorem na YYYY-MM-DD, jinak string-compare leetne.
  var origStart = MG._editRez._normIso(b.start_date);
  var origEnd = MG._editRez._normIso(b.end_date);
  var todayIso = MG._editRez._toIsoDate(new Date());

  // Kontextová nápověda — jasně co se kliká
  var helpHtml = isActive
    ? 'V kalendáři klikněte na <strong>den před ' + MG.formatDate(origEnd)
        + '</strong> — vrátíte motorku dříve. Začátek (' + MG.formatDate(origStart)
        + ') už nelze měnit, protože rezervace běží. Refund podle storno podmínek.'
    : 'Vyberte stranu, kterou chcete zkrátit (Začátek = pozdější vyzvednutí, Konec = dřívější vrácení), pak klikněte v kalendáři uvnitř rezervace na nový den. Refund podle storno podmínek.';

  // Šipky pro výběr směru (jen upcoming)
  var dirsHtml = '';
  if (!isActive){
    dirsHtml =
      '<div class="erez-shorten-dirs">' +
        '<button type="button" data-dir="start">← Zkrátit začátek</button>' +
        '<button type="button" data-dir="end">Zkrátit konec →</button>' +
      '</div>';
  }

  t.innerHTML =
    '<h3>' + MG.t('editRez.shorten.title') + '</h3>' +
    '<p>' + helpHtml + '</p>' +
    dirsHtml +
    '<div id="edit-rez-shorten-banner" class="erez-range-banner" style="display:none"></div>' +
    '<div id="edit-rez-shorten-manual"></div>' +
    '<div id="edit-rez-shorten-cal"></div>' +
    '<form id="edit-rez-shorten-form" class="edit-rez-form" novalidate>' +
      '<input type="hidden" name="newStart" value="' + origStart + '">' +
      '<input type="hidden" name="newEnd"   value="' + origEnd   + '">' +
      '<label>' + MG.t('editRez.shorten.reasonLabel') +
        '<textarea name="reason" rows="2" maxlength="500"></textarea>' +
      '</label>' +
      '<div id="edit-rez-shorten-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen" id="edit-rez-shorten-cta" disabled>' + MG.t('editRez.shorten.cta') + '</button>' +
    '</form>' +
    MG._editRez._stornoBoxHtml();

  var f = document.getElementById('edit-rez-shorten-form');
  var banner = document.getElementById('edit-rez-shorten-banner');
  // Upcoming → start, active → konec rovnou
  var shortenDir = isActive ? 'end' : null;

  function showError(msg){
    banner.className = 'erez-range-banner error';
    banner.style.display='flex';
    banner.innerHTML = '<span>⚠️ ' + msg + '</span>' +
      '<button type="button" class="erez-clear">✕</button>';
    var btn = banner.querySelector('.erez-clear');
    if (btn) btn.addEventListener('click', function(){ updateBanner(f.newStart.value, f.newEnd.value); });
  }

  function updateBanner(ns, ne){
    banner.className = 'erez-range-banner';
    if (!ns || !ne || (ns === origStart && ne === origEnd)){
      banner.style.display='none'; banner.innerHTML='';
      return;
    }
    banner.style.display='flex';
    banner.innerHTML = '<span>Nový termín: <strong>'+MG.formatDate(ns)+' – '+MG.formatDate(ne)+'</strong></span>' +
      '<button type="button" class="erez-clear">✕ Zrušit</button>';
    var btn = banner.querySelector('.erez-clear');
    if (btn) btn.addEventListener('click', function(){
      cal.setSelection(origStart, origEnd);
      onChange(origStart, origEnd);
    });
  }

  function recalc(ns, ne){
    var summary = document.getElementById('edit-rez-shorten-summary');
    var cta = document.getElementById('edit-rez-shorten-cta');
    if (!ns || !ne || ns > ne){
      summary.textContent = ''; cta.disabled = true; return;
    }
    var noChange = (ns === origStart && ne === origEnd);
    if (noChange){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true; return;
    }
    // Pro shorten: nové datumy musí být UVNITŘ původních.
    if (ns < origStart || ne > origEnd){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.err.notShortening') + '</span>';
      cta.disabled = true; return;
    }
    var origPrice = MG._editRez._priceForRange(m, origStart, origEnd);
    var newPrice  = MG._editRez._priceForRange(m, ns, ne);
    var diff = Math.max(0, Math.round(origPrice - newPrice));
    if (diff <= 0){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true; return;
    }
    // Refund % podle nového konce / začátku (shoda s SQL backend logikou).
    var target = (ne < origEnd) ? ne : ns;
    var pct = MG._editRez._refundPercent(target);
    var refund = Math.round(diff * pct / 100);
    var cls = pct === 100 ? 'refund-full' : pct === 50 ? 'refund-half' : 'refund-none';
    if (pct === 0){
      summary.innerHTML = '<div class="line ' + cls + '">' + MG.t('editRez.shorten.refundZero') + '</div>';
      cta.disabled = true;
    } else {
      summary.innerHTML = '<div class="line ' + cls + '">'
        + MG.t('editRez.shorten.refund', { amount: MG.formatPrice(refund), percent: pct })
        + '</div>';
      cta.disabled = false;
    }
    f.dataset.refund = String(refund);
    f.dataset.pct = String(pct);
  }

  // Pravidla shorten:
  //  - upcoming (reserved): start lze posunout POZDĚJI (uvnitř původního rozsahu)
  //    NEBO end DŘÍVE — uživatel volí směr přes tlačítka výše
  //  - active: start zamčený = origStart, end pouze DŘÍVE (mezi dneškem a origEnd-1)
  var manual = MG._editRez._renderManualDates({
    container: document.getElementById('edit-rez-shorten-manual'),
    startIso: origStart, endIso: origEnd,
    minIso: origStart,
    maxIso: origEnd,
    minEndIso: isActive ? todayIso : origStart,
    maxEndIso: origEnd,
    lockStart: isActive,
    onChange: function(which, iso){
      var ns = (which === 'start') ? iso : f.newStart.value;
      var ne = (which === 'end')   ? iso : f.newEnd.value;
      cal.setSelection(ns, ne);
      var d = new Date(iso);
      cal.showMonth(d.getFullYear(), d.getMonth());
      onChange(ns, ne);
    }
  });

  function onChange(s, e){
    f.newStart.value = s || '';
    f.newEnd.value = e || '';
    if (manual){ manual.setStart(s); manual.setEnd(e); }
    updateBanner(s, e);
    recalc(s, e);
  }

  var cal = MG._editRez._renderRangeCalendar({
    container: document.getElementById('edit-rez-shorten-cal'),
    mode: 'shorten',
    isActive: isActive,
    origStart: origStart,
    origEnd: origEnd,
    newStart: origStart,
    newEnd: origEnd,
    occupied: [],            // při zkrácení se zužujeme uvnitř vlastního rozsahu — žádný cizí overlap
    shortenDir: shortenDir,
    onChange: onChange,
    onError: showError
  });
  onChange(origStart, origEnd);

  // Přepínač směru zkrácení (jen upcoming)
  if (!isActive){
    var dirBtns = t.querySelectorAll('.erez-shorten-dirs button');
    dirBtns.forEach(function(btn){
      btn.addEventListener('click', function(){
        shortenDir = btn.getAttribute('data-dir');
        dirBtns.forEach(function(x){ x.classList.toggle('active', x === btn); });
        cal.setShortenDir(shortenDir);
        // Při změně směru reset výběru na orig — ať si uživatel vybírá od začátku
        cal.setSelection(origStart, origEnd);
        onChange(origStart, origEnd);
      });
    });
  }

  f.addEventListener('submit', function(e){
    e.preventDefault();
    if (MG._editRez.busy) return;
    var ns = f.newStart.value, ne = f.newEnd.value;
    var reason = (f.reason.value || '').trim();
    var refund = Number(f.dataset.refund || 0);
    var pct = Number(f.dataset.pct || 0);
    MG._editRez._confirmDialog(MG.t('editRez.shorten.cta') + '?', function(){
      MG._editRez._submitShorten(ns, ne, reason, refund, pct);
    });
  });
};

MG._editRez._submitShorten = async function(newStart, newEnd, reason, refund, pct){
  var b = MG._editRez.selectedBooking;
  MG._editRez._setBusy(true);
  try {
    var r = await window.sb.rpc('shorten_booking_with_refund', {
      p_booking_id: b.id,
      p_new_start: newStart,
      p_new_end: newEnd,
      p_reason: reason || null
    });
    if (r.error || !r.data || r.data.success === false){
      console.error('[editRez] shorten err', r.error, r.data);
      var errCode = r.data && r.data.error;
      var msgKey = {
        'wrong_status': 'editRez.err.wrongStatus',
        'not_paid': 'editRez.err.notPaid',
        'active_start_locked': 'editRez.err.activeStartLocked',
        'not_a_shortening': 'editRez.err.notShortening',
        'invalid_range': 'editRez.err.invalidRange',
        'no_change': 'editRez.err.invalidRange',
        'no_diff': 'editRez.err.invalidRange',
        'not_found': 'editRez.err.notFound',
        'unauthenticated': 'editRez.login.error'
      }[errCode] || 'editRez.err.generic';
      MG._editRez._showError(MG.t(msgKey));
      return;
    }
    var actualRefund = r.data.refund_amount || refund;
    var actualPct = r.data.refund_percent || pct;
    var msg = MG.t('editRez.shorten.success', { amount: MG.formatPrice(actualRefund), percent: actualPct });
    var c = document.getElementById('edit-rez-tab-content');
    if (c) c.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + msg + '</p>'
      + '<button type="button" class="btn btngreen-small" id="edit-rez-back-list">'
      + MG.t('editRez.list.title') + '</button></div>';
    var back = document.getElementById('edit-rez-back-list');
    if (back) back.addEventListener('click', async function(){
      MG._editRez.selectedBooking = null;
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
    });
  } catch(err){
    console.error('[editRez] shorten exception', err);
    MG._editRez._showError(MG.t('editRez.err.generic'));
  } finally {
    MG._editRez._setBusy(false);
  }
};

// ===== POST-STRIPE HANDLER =====
// Po návratu ze Stripe success URL (?paid_booking=<id>) aplikujeme
// pending_changes uložené v localStorage před redirectem. Webhook už
// zaktualizoval payment_status, ale datumy/motorka/lokace se aplikují
// až klient-side (1:1 jako Flutter app pendingEditChanges flow).
MG._editRez._applyPendingAfterPayment = async function(bookingId){
  if (!bookingId) return false;
  var raw = null;
  try { raw = localStorage.getItem('editRez_pending_' + bookingId); } catch(e){}
  if (!raw) return false;
  var entry; try { entry = JSON.parse(raw); } catch(e){ return false; }
  if (!entry || !entry.payload) return false;

  // Polling: počkáme až payment_status='paid' (webhook potvrzuje async).
  // Max 30s, krok 2s.
  var paid = false;
  for (var i = 0; i < 15; i++){
    var r = await window.sb.from('bookings').select('payment_status,total_price').eq('id', bookingId).single();
    if (r.data && r.data.payment_status === 'paid'){ paid = true; break; }
    await new Promise(function(res){ setTimeout(res, 2000); });
  }
  if (!paid){ console.warn('[editRez] post-stripe: payment not confirmed in time'); return false; }

  // Aplikujeme změny — RLS umožní vlastní booking update.
  // Skládáme update payload z pending payloadu (mapování p_new_* → bookings sloupce).
  var p = entry.payload || {};
  var update = {};
  if (p.p_new_start)         update.start_date = p.p_new_start;
  if (p.p_new_end)           update.end_date = p.p_new_end;
  if (p.p_new_moto_id)       update.moto_id = p.p_new_moto_id;
  if (p.p_new_pickup_method) update.pickup_method = p.p_new_pickup_method;
  if (p.p_new_pickup_address !== undefined) update.pickup_address = p.p_new_pickup_address;
  if (p.p_new_pickup_lat !== undefined && p.p_new_pickup_lat !== null) update.pickup_lat = p.p_new_pickup_lat;
  if (p.p_new_pickup_lng !== undefined && p.p_new_pickup_lng !== null) update.pickup_lng = p.p_new_pickup_lng;
  if (p.p_new_return_method) update.return_method = p.p_new_return_method;
  if (p.p_new_return_address !== undefined) update.return_address = p.p_new_return_address;
  if (p.p_new_return_lat !== undefined && p.p_new_return_lat !== null) update.return_lat = p.p_new_return_lat;
  if (p.p_new_return_lng !== undefined && p.p_new_return_lng !== null) update.return_lng = p.p_new_return_lng;
  if (p.p_new_pickup_fee !== undefined || p.p_new_return_fee !== undefined){
    update.delivery_fee = Number(p.p_new_pickup_fee || 0) + Number(p.p_new_return_fee || 0);
  }

  if (Object.keys(update).length){
    var ur = await window.sb.from('bookings').update(update).eq('id', bookingId);
    if (ur.error){
      console.error('[editRez] post-stripe update err', ur.error);
      return false;
    }
  }
  try { localStorage.removeItem('editRez_pending_' + bookingId); } catch(e){}
  return true;
};

// ===== INIT =====
MG._editRezInit = async function(){
  // Detekce password recovery flow: Supabase přidá do URL hashe `#type=recovery`
  // a access_token; knihovna automaticky vytvoří session a emituje
  // PASSWORD_RECOVERY event. Pak musíme zákazníka donutit nastavit nové heslo,
  // ne ho rovnou pustit do listu se starým session tokenem.
  var isRecovery = false;
  try {
    var hash = String(window.location.hash || '');
    isRecovery = hash.indexOf('type=recovery') !== -1;
    // Bezpečnostní pojistka: i kdyby Supabase event nestihl, listener níže
    // recovery flag přepne také.
    if (window.sb && window.sb.auth && window.sb.auth.onAuthStateChange){
      window.sb.auth.onAuthStateChange(function(event){
        if (event === 'PASSWORD_RECOVERY'){
          MG._editRez._goto('reset');
        }
      });
    }
  } catch(e){}

  if (isRecovery){
    // Necháme Supabase chvíli na zpracování hashe (vystavení session).
    setTimeout(function(){ MG._editRez._goto('reset'); }, 50);
    return;
  }

  try {
    var sess = await window.sb.auth.getSession();
    if (sess && sess.data && sess.data.session && sess.data.session.user){
      MG._editRez.user = sess.data.session.user;

      // Detekce post-Stripe návratu: ?paid_booking=<id>
      var paidId = null;
      try {
        var u = new URL(window.location.href);
        paidId = u.searchParams.get('paid_booking');
      } catch(e){}
      if (paidId){
        // Vykreslíme rychlou loading obrazovku, pak aplikujeme pending změny.
        MG._editRez._renderShell();
        var c = document.getElementById('edit-rez-content');
        if (c) c.innerHTML = '<section class="edit-rez-card"><p>'
          + MG.t('editRez.postStripe.applying') + '</p></section>';
        var ok = await MG._editRez._applyPendingAfterPayment(paidId);
        // Vyčistíme query string aby se to při reload neopakovalo
        if (window.history && window.history.replaceState){
          window.history.replaceState(null, '', window.location.pathname);
        }
        await MG._editRez._loadBookings();
        // Zobrazíme úspěch v listu, jinak rovnou list
        MG._editRez._goto('list');
        if (!ok){
          MG._editRez._showError(MG.t('editRez.postStripe.error'));
        }
        return;
      }

      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
      return;
    }
  } catch(e){ /* fallthrough do login */ }
  MG._editRez._goto('login');
};
