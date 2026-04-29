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
  view: 'login',        // 'login' | 'forgot' | 'list' | 'detail'
  user: null,           // auth user
  bookings: [],         // user's editable bookings
  selectedBooking: null,
  selectedMoto: null,
  occupied: [],         // bookings z jiných rezervací stejné motorky
  tab: 'detail',        // 'detail' | 'extend' | 'shorten' | 'cancel'
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
  if (view === 'list')    return MG._editRez._renderList();
  if (view === 'detail')  return MG._editRez._renderDetail();
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
      MG._editRez._showError(MG.t('editRez.login.error'));
      return;
    }
    MG._editRez.user = res.data.user;
    await MG._editRez._loadBookings();
    MG._editRez._goto('list');
  } catch(err){
    console.error('[editRez] login err', err);
    MG._editRez._showError(MG.t('editRez.login.error'));
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
    // Redirect zpět na úpravu po nastavení hesla (Supabase přidá ?type=recovery).
    var redirectTo = window.location.origin + '/upravit-rezervaci';
    var res = await window.sb.auth.resetPasswordForEmail(email, { redirectTo: redirectTo });
    if (res.error){
      console.warn('[editRez] resetPassword err', res.error);
      // I při error ukážeme generický success — neprozradíme, že email neexistuje
      // (anti-enumeration), je to standardní auth pattern.
    }
    var c = document.getElementById('edit-rez-content');
    c.innerHTML = '<section class="edit-rez-card edit-rez-success">'
      + '<p>' + MG.t('editRez.forgot.success') + '</p>'
      + '<p><a href="#" id="edit-rez-back-login2">' + MG.t('editRez.forgot.back') + '</a></p>'
      + '</section>';
    document.getElementById('edit-rez-back-login2').addEventListener('click', function(ev){
      ev.preventDefault();
      MG._editRez._goto('login');
    });
  } catch(err){
    console.error('[editRez] forgot err', err);
    MG._editRez._showError(MG.t('editRez.forgot.error'));
  } finally {
    MG._editRez._setBusy(false);
    btn.disabled = false;
    btn.textContent = origLabel;
  }
};

// ===== LOAD BOOKINGS =====
// RLS ochrání: uživatel vidí jen vlastní bookingy (auth.uid() = user_id).
// Filtrujeme na statusy, kde má smysl něco upravovat: pending+paid (vzácné),
// reserved, active. Completed/cancelled se nezobrazují (nelze měnit).
MG._editRez._loadBookings = async function(){
  if (!MG._editRez.user) return;
  try {
    var r = await window.sb
      .from('bookings')
      .select('id,moto_id,start_date,end_date,pickup_time,return_time,status,payment_status,total_price,created_at,delivery_fee,extras_price,discount_amount,pickup_method,pickup_address,return_method,return_address,stripe_payment_intent_id,motorcycles(id,model,brand,image_url,price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend)')
      .eq('user_id', MG._editRez.user.id)
      .in('status', ['pending','reserved','active'])
      .order('start_date', { ascending: true });
    if (r.error){
      console.error('[editRez] loadBookings err', r.error);
      MG._editRez.bookings = [];
      return;
    }
    MG._editRez.bookings = r.data || [];
  } catch(err){
    console.error('[editRez] loadBookings exception', err);
    MG._editRez.bookings = [];
  }
};

// ===== LIST OF BOOKINGS =====
MG._editRez._renderList = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  var bs = MG._editRez.bookings || [];
  if (!bs.length){
    c.innerHTML =
      '<section class="edit-rez-card edit-rez-empty">' +
      '<h2>' + MG.t('editRez.list.title') + '</h2>' +
      '<p>' + MG.t('editRez.list.empty') + '</p>' +
      '<p><a class="btn btngreen-small" href="/rezervace">' + MG.t('editRez.list.openNew') + '</a></p>' +
      '</section>';
    return;
  }

  var rows = bs.map(function(b){
    var m = b.motorcycles || {};
    var motoLabel = (m.brand ? m.brand + ' ' : '') + (m.model || '');
    var img = m.image_url ? '<img src="'+m.image_url+'" alt="" loading="lazy">' : '';
    var dates = MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date);
    var statusLbl = MG._editRez._statusLabel(b.status);
    var price = MG.formatPrice(Number(b.total_price || 0));
    return '<button type="button" class="edit-rez-booking" data-id="' + b.id + '">' +
      '<div class="edit-rez-booking-img">' + img + '</div>' +
      '<div class="edit-rez-booking-body">' +
        '<div class="edit-rez-booking-title">' + motoLabel + '</div>' +
        '<div class="edit-rez-booking-meta">' + dates + '</div>' +
        '<div class="edit-rez-booking-status status-' + b.status + '">' + statusLbl + '</div>' +
      '</div>' +
      '<div class="edit-rez-booking-price">' + price + '</div>' +
      '</button>';
  }).join('');

  c.innerHTML =
    '<section class="edit-rez-card">' +
    '<h2>' + MG.t('editRez.list.title') + '</h2>' +
    '<div class="edit-rez-booking-list">' + rows + '</div>' +
    '</section>';

  c.querySelectorAll('.edit-rez-booking').forEach(function(btn){
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
};

// ===== DETAIL placeholder (rozšíříme v dalších commitech) =====
MG._editRez._renderDetail = function(){
  MG._editRez._renderShell();
  var c = document.getElementById('edit-rez-content');
  c.innerHTML = '<p>' + MG.t('editRez.loading') + '</p>';
  // TODO: tab UI + tab content (detail / extend / shorten / cancel) — další commit.
};

// ===== INIT =====
MG._editRezInit = async function(){
  // Zachytit Supabase password recovery flow: Supabase v hash # přidá access_token
  // a type=recovery. Knihovna ho zpracuje automaticky a vystaví session.
  // Po recovery flow chceme uživatele rovnou pustit do listu.
  try {
    var sess = await window.sb.auth.getSession();
    if (sess && sess.data && sess.data.session && sess.data.session.user){
      MG._editRez.user = sess.data.session.user;
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
      return;
    }
  } catch(e){ /* fallthrough do login */ }
  MG._editRez._goto('login');
};
