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

// ===== LOAD BOOKINGS, SHOP ORDERS, VOUCHERS =====
// RLS ochrání: uživatel vidí jen své vlastní záznamy.
// Načítáme **kompletní historii** napříč statusy + e-shop objednávky + poukazy.
MG._editRez._loadBookings = async function(){
  if (!MG._editRez.user) return;
  var uid = MG._editRez.user.id;
  try {
    var results = await Promise.all([
      window.sb.from('bookings')
        .select('id,moto_id,start_date,end_date,pickup_time,return_time,status,payment_status,total_price,created_at,delivery_fee,extras_price,discount_amount,pickup_method,pickup_address,pickup_lat,pickup_lng,return_method,return_address,return_lat,return_lng,stripe_payment_intent_id,booking_source,motorcycles(id,model,brand,image_url,license_required,price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend)')
        .eq('user_id', uid)
        .order('start_date', { ascending: false }),
      window.sb.from('shop_orders')
        .select('id,order_number,status,payment_status,total_amount,created_at,confirmed_at,stripe_payment_intent_id,shop_order_items(product_id,size,name,price,quantity)')
        .eq('customer_id', uid)
        .order('created_at', { ascending: false }),
      window.sb.from('vouchers')
        .select('id,code,amount,currency,status,valid_from,valid_until,created_at,description,category,redeemed_at,booking_id')
        .eq('buyer_id', uid)
        .order('created_at', { ascending: false })
    ]);
    MG._editRez.bookings = (results[0] && results[0].data) || [];
    MG._editRez.shopOrders = (results[1] && results[1].data) || [];
    MG._editRez.vouchers = (results[2] && results[2].data) || [];
  } catch(err){
    console.error('[editRez] loadBookings exception', err);
    MG._editRez.bookings = [];
    MG._editRez.shopOrders = [];
    MG._editRez.vouchers = [];
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

  if (!bs.length && !shop.length && !vouchers.length){
    c.innerHTML =
      '<section class="edit-rez-card edit-rez-empty">' +
      '<h2>' + MG.t('editRez.list.title') + '</h2>' +
      '<p>' + MG.t('editRez.list.empty') + '</p>' +
      '<p><a class="btn btngreen-small" href="/rezervace">' + MG.t('editRez.list.openNew') + '</a></p>' +
      '</section>';
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
      : '');

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

MG._editRez._renderBookingRow = function(b){
  var m = b.motorcycles || {};
  var motoLabel = (m.brand ? m.brand + ' ' : '') + (m.model || '');
  var img = m.image_url ? '<img src="'+m.image_url+'" alt="" loading="lazy">' : '';
  var dates = MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date);
  var ds = MG._editRez._displayStatus(b);
  var statusLbl = MG.t('editRez.status.' + ds);
  var price = MG.formatPrice(Number(b.total_price || 0));
  return '<button type="button" class="edit-rez-booking" data-id="' + b.id + '">' +
    '<div class="edit-rez-booking-img">' + img + '</div>' +
    '<div class="edit-rez-booking-body">' +
      '<div class="edit-rez-booking-title">' + motoLabel + '</div>' +
      '<div class="edit-rez-booking-meta">' + dates + '</div>' +
      '<div class="edit-rez-booking-status status-' + ds + '">' + statusLbl + '</div>' +
    '</div>' +
    '<div class="edit-rez-booking-price">' + price + '</div>' +
  '</button>';
};

MG._editRez._renderShopRow = function(o){
  var num = o.order_number ? '#' + o.order_number : (o.id || '').substring(0,8).toUpperCase();
  var when = MG.formatDate(o.created_at);
  var price = MG.formatPrice(Number(o.total_amount || 0));
  var statusKey = 'editRez.shopStatus.' + (o.status || 'unknown');
  var lbl = MG.t(statusKey, {});
  if (lbl === statusKey) lbl = o.status || '';
  return '<button type="button" class="edit-rez-booking" data-shop-id="' + o.id + '">' +
    '<div class="edit-rez-booking-img">🛒</div>' +
    '<div class="edit-rez-booking-body">' +
      '<div class="edit-rez-booking-title">' + num + '</div>' +
      '<div class="edit-rez-booking-meta">' + when + '</div>' +
      '<div class="edit-rez-booking-status status-' + (o.payment_status === 'paid' ? 'completed' : 'pending') + '">' + lbl + '</div>' +
    '</div>' +
    '<div class="edit-rez-booking-price">' + price + '</div>' +
  '</button>';
};

MG._editRez._renderVoucherRow = function(v){
  var code = v.code || '';
  var when = MG.formatDate(v.created_at);
  var price = MG.formatPrice(Number(v.amount || 0));
  var lbl = MG.t('editRez.voucherStatus.' + (v.status || 'active'), {});
  return '<button type="button" class="edit-rez-booking" data-voucher-id="' + v.id + '">' +
    '<div class="edit-rez-booking-img">🎁</div>' +
    '<div class="edit-rez-booking-body">' +
      '<div class="edit-rez-booking-title">' + code + '</div>' +
      '<div class="edit-rez-booking-meta">' + when + '</div>' +
      '<div class="edit-rez-booking-status status-' + (v.status === 'active' ? 'upcoming' : v.status === 'redeemed' ? 'completed' : 'cancelled') + '">' + lbl + '</div>' +
    '</div>' +
    '<div class="edit-rez-booking-price">' + price + '</div>' +
  '</button>';
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

// Otevře PDF z Supabase Storage. invoices.pdf_path může být plný path (s bucketem)
// nebo jen relativní; default bucket = 'invoices'.
MG._editRez._openDocPdf = async function(path){
  if (!path){ MG._editRez._showError(MG.t('editRez.doc.notAvailable')); return; }
  try {
    var bucket = 'invoices';
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

  c.innerHTML =
    '<section class="edit-rez-card edit-rez-detail-head">' +
      '<button type="button" class="btn-link" id="edit-rez-back">← ' + MG.t('editRez.list.title') + '</button>' +
      '<h2>' + motoLabel + '</h2>' +
      '<div class="edit-rez-detail-meta">' + dates + ' · ' + status + '</div>' +
    '</section>' +
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
        .select('id,type,name,file_url,storage_path,created_at')
        .eq('booking_id', b.id)
        .order('created_at', { ascending: true })
    ]);
    var invoices = (results[0] && results[0].data) || [];
    var docs     = (results[1] && results[1].data) || [];

    var rows = [];
    invoices.forEach(function(d){
      var label = MG.t('editRez.doc.type.' + (d.type || 'unknown'), {});
      var num = d.number || (d.id || '').substring(0,8);
      var amt = d.total ? MG.formatPrice(Number(d.total)) : '';
      var when = d.issue_date ? MG.formatDate(d.issue_date) : (d.created_at ? MG.formatDate(d.created_at) : '');
      rows.push({ kind:'invoice', label: label, num: num, amt: amt, when: when, path: d.pdf_path });
    });
    docs.forEach(function(d){
      var label = MG.t('editRez.doc.type.' + (d.type || 'unknown'), {});
      var when = d.created_at ? MG.formatDate(d.created_at) : '';
      var path = d.storage_path || d.file_url;
      rows.push({ kind:'document', label: label, num: d.name || '', amt: '', when: when, path: path });
    });

    var listHtml = rows.length
      ? '<ul class="edit-rez-doclist">' + rows.map(function(r){
          var meta = [r.num, r.when, r.amt].filter(function(x){ return x; }).join(' · ');
          var btn = r.path
            ? '<button type="button" class="btn-link" data-pdf="' + r.path + '">' + MG.t('editRez.doc.download') + '</button>'
            : '<span class="muted">' + MG.t('editRez.doc.notAvailable') + '</span>';
          return '<li><div><strong>' + r.label + '</strong>' + (meta ? '<br><span class="muted">' + meta + '</span>' : '') + '</div><div>' + btn + '</div></li>';
        }).join('') + '</ul>'
      : '<p>' + MG.t('editRez.doc.empty') + '</p>';

    t.innerHTML = '<h3>' + MG.t('editRez.doc.title') + '</h3>'
      + '<p class="edit-rez-tip">' + MG.t('editRez.doc.help') + '</p>'
      + listHtml;

    t.querySelectorAll('[data-pdf]').forEach(function(btn){
      btn.addEventListener('click', function(){
        MG._editRez._openDocPdf(btn.getAttribute('data-pdf'));
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
    + '<p>' + MG.t('editRez.moto.help') + '</p>'
    + '<p class="edit-rez-tip">' + MG.t('editRez.loading') + '</p>';

  // Načti všechny aktivní motorky + profil zákazníka pro license
  try {
    var [motosR, profileR] = await Promise.all([
      window.sb.from('motorcycles').select('id,model,brand,image_url,license_required,price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend').eq('status','active').order('model'),
      window.sb.from('profiles').select('license_group').eq('id', MG._editRez.user.id).single()
    ]);
    var motos = (motosR && motosR.data) || [];
    var profileGroups = (profileR && profileR.data && profileR.data.license_group) || [];
    // Vyloučit aktuální motorku
    motos = motos.filter(function(m){ return m.id !== b.moto_id; });

    if (!motos.length){
      t.innerHTML = '<h3>' + MG.t('editRez.moto.title') + '</h3>'
        + '<p>' + MG.t('editRez.moto.help') + '</p>'
        + '<p class="muted">' + MG.t('editRez.moto.noOptions') + '</p>';
      return;
    }

    // Pro každou motorku: dostupnost v termínu + cenový rozdíl
    var rangePromises = motos.map(function(m){
      return window.sb.rpc('get_moto_booked_dates', { p_moto_id: m.id })
        .then(function(r){ return { moto: m, occupied: (r && r.data) || [] }; });
    });
    var withAvail = await Promise.all(rangePromises);

    var oldPrice = MG._editRez._priceForRange(MG._editRez.selectedMoto, b.start_date, b.end_date);
    var rows = withAvail.map(function(x){
      var m = x.moto;
      var licOk = MG._editRez._licenseAllows(profileGroups, m.license_required);
      var available = !MG._editRez._rangeOverlapsOccupied(b.start_date, b.end_date, x.occupied);
      var newPrice = MG._editRez._priceForRange(m, b.start_date, b.end_date);
      var diff = Math.round(newPrice - oldPrice);
      var disabled = !licOk || !available;
      var reasons = [];
      if (!licOk) reasons.push(MG.t('editRez.moto.licenseInsufficient'));
      if (!available) reasons.push(MG.t('editRez.moto.notAvailable'));
      var diffLabel = diff === 0 ? '' : (diff > 0
        ? '<span class="diff-pos">+' + MG.formatPrice(diff) + '</span>'
        : '<span class="diff-neg">' + MG.formatPrice(diff) + '</span>');
      var img = m.image_url ? '<img src="'+m.image_url+'" alt="" loading="lazy">' : '';
      var label = (m.brand ? m.brand + ' ' : '') + m.model;
      return '<button type="button" class="edit-rez-moto-card' + (disabled ? ' disabled' : '') + '" data-id="' + m.id + '"' + (disabled ? ' disabled' : '') + '>'
        + '<div class="edit-rez-booking-img">' + img + '</div>'
        + '<div class="edit-rez-booking-body">'
          + '<div class="edit-rez-booking-title">' + label + '</div>'
          + '<div class="edit-rez-booking-meta">' + MG.t('editRez.moto.licReq', { lic: m.license_required || '—' }) + '</div>'
          + (reasons.length ? '<div class="edit-rez-moto-reasons">' + reasons.join(' · ') + '</div>' : '')
        + '</div>'
        + '<div class="edit-rez-booking-price">' + diffLabel + '</div>'
      + '</button>';
    }).join('');

    t.innerHTML = '<h3>' + MG.t('editRez.moto.title') + '</h3>'
      + '<p>' + MG.t('editRez.moto.help') + '</p>'
      + '<div class="edit-rez-booking-list">' + rows + '</div>';

    t.querySelectorAll('.edit-rez-moto-card:not(.disabled)').forEach(function(btn){
      btn.addEventListener('click', function(){
        var newId = btn.getAttribute('data-id');
        MG._editRez._confirmDialog(MG.t('editRez.moto.confirm'), function(){
          MG._editRez._submitChange({ p_new_moto_id: newId });
        });
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
      // Otevři Stripe Checkout přes process-payment Edge.
      // Pošleme dokument změny, který se aplikuje až po platbě (server-side).
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
          // Edge funkce process-payment uloží pendingChanges do session metadata
          // a webhook po platbě zavolá apply_booking_changes znovu (idempotentně)
          // s identickými parametry — atomický apply.
          pending_changes: payload,
          success_url: window.location.origin + '/potvrzeni?booking_id=' + b.id,
          cancel_url:  window.location.origin + '/upravit-rezervaci'
        })
      });
      var data = await resp.json().catch(function(){ return null; });
      if (!resp.ok || !data || !data.url){
        console.error('[editRez] payment err', resp.status, data);
        MG._editRez._showError((data && data.error) ? data.error : MG.t('editRez.err.generic'));
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

  t.innerHTML =
    '<h3>' + MG.t('editRez.loc.title') + '</h3>' +
    '<p>' + MG.t('editRez.loc.help') + '</p>' +
    '<form id="edit-rez-loc-form" class="edit-rez-form" novalidate>' +
      // PICKUP
      '<fieldset class="edit-rez-loc-fieldset">' +
        '<legend>' + MG.t('editRez.loc.pickup') + '</legend>' +
        '<label class="edit-rez-loc-radio"><input type="radio" name="pickup" value="pickup"' + (!isDelP ? ' checked' : '') + '>' +
          ' <span><strong>' + MG.t('editRez.loc.atRental') + '</strong> · ' + MG.formatPrice(0) + '</span></label>' +
        '<label class="edit-rez-loc-radio"><input type="radio" name="pickup" value="delivery"' + (isDelP ? ' checked' : '') + '>' +
          ' <span><strong>' + MG.t('editRez.loc.delivery') + '</strong> · 1 000 Kč + 40 Kč/km</span></label>' +
        '<div class="edit-rez-loc-addr" data-side="pickup" style="display:' + (isDelP ? 'block' : 'none') + '">' +
          '<input type="text" name="pickupAddr" placeholder="' + MG.t('editRez.loc.addrPlaceholder') + '" value="' + (b.pickup_address || '').replace(/"/g,'&quot;') + '" autocomplete="street-address">' +
          '<button type="button" class="btn-link edit-rez-map-btn" data-map="pickup">📍 ' + MG.t('editRez.loc.mapBtn') + '</button>' +
          '<div class="edit-rez-loc-route" id="edit-rez-loc-route-pickup"></div>' +
          '<input type="hidden" name="pickupLat" value="' + (b.pickup_lat || '') + '">' +
          '<input type="hidden" name="pickupLng" value="' + (b.pickup_lng || '') + '">' +
          '<input type="hidden" name="pickupFee" value="0">' +
        '</div>' +
      '</fieldset>' +
      // RETURN
      '<fieldset class="edit-rez-loc-fieldset">' +
        '<legend>' + MG.t('editRez.loc.return') + '</legend>' +
        '<label class="edit-rez-loc-radio"><input type="radio" name="returnM" value="pickup"' + (!isDelR ? ' checked' : '') + '>' +
          ' <span><strong>' + MG.t('editRez.loc.atRental') + '</strong> · ' + MG.formatPrice(0) + '</span></label>' +
        '<label class="edit-rez-loc-radio"><input type="radio" name="returnM" value="delivery"' + (isDelR ? ' checked' : '') + '>' +
          ' <span><strong>' + MG.t('editRez.loc.deliveryReturn') + '</strong> · 1 000 Kč + 40 Kč/km</span></label>' +
        '<div class="edit-rez-loc-addr" data-side="return" style="display:' + (isDelR ? 'block' : 'none') + '">' +
          '<input type="text" name="returnAddr" placeholder="' + MG.t('editRez.loc.addrPlaceholder') + '" value="' + (b.return_address || '').replace(/"/g,'&quot;') + '" autocomplete="street-address">' +
          '<button type="button" class="btn-link edit-rez-map-btn" data-map="return">📍 ' + MG.t('editRez.loc.mapBtn') + '</button>' +
          '<div class="edit-rez-loc-route" id="edit-rez-loc-route-return"></div>' +
          '<input type="hidden" name="returnLat" value="' + (b.return_lat || '') + '">' +
          '<input type="hidden" name="returnLng" value="' + (b.return_lng || '') + '">' +
          '<input type="hidden" name="returnFee" value="0">' +
        '</div>' +
      '</fieldset>' +
      '<div id="edit-rez-loc-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen" id="edit-rez-loc-cta" disabled>' + MG.t('editRez.loc.cta') + '</button>' +
    '</form>';

  var f = document.getElementById('edit-rez-loc-form');

  // Toggle adresa boxů podle radia
  function syncAddrVisibility(){
    var pkV = f.pickup.value;
    var rtV = f.returnM.value;
    document.querySelector('[data-side="pickup"]').style.display = (pkV === 'delivery') ? 'block' : 'none';
    document.querySelector('[data-side="return"]').style.display = (rtV === 'delivery') ? 'block' : 'none';
    if (pkV !== 'delivery'){ f.pickupFee.value = '0'; }
    if (rtV !== 'delivery'){ f.returnFee.value = '0'; }
    livePreview();
  }
  Array.from(f.pickup).forEach(function(r){ r.addEventListener('change', syncAddrVisibility); });
  Array.from(f.returnM).forEach(function(r){ r.addEventListener('change', syncAddrVisibility); });

  // Mapa picker (reuse existující MG._openWebMapPicker — ale ten zapisuje
  // do rezervačních inputů. Sklouzneme se do vlastního mini-pickeru, který
  // přepoužije Leaflet+Mapy.cz tile layer.)
  f.querySelectorAll('.edit-rez-map-btn').forEach(function(btn){
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
      var fee = MG._calcDeliveryFee ? MG._calcDeliveryFee(km) : (1000 + Math.ceil(km) * 40);
      feeInp.value = String(fee);
      routeEl.innerHTML = '<strong>' + km.toFixed(1).replace('.', ',') + ' km</strong> · '
        + MG.formatPrice(fee) + '</strong>';
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

  // Live preview ceny přes apply_booking_changes(p_dry_run:=true)
  function livePreview(){
    var summary = document.getElementById('edit-rez-loc-summary');
    var cta = document.getElementById('edit-rez-loc-cta');
    var pkM = f.pickup.value;
    var rtM = f.returnM.value;
    var pkFee = (pkM === 'delivery') ? Number(f.pickupFee.value || 0) : 0;
    var rtFee = (rtM === 'delivery') ? Number(f.returnFee.value || 0) : 0;
    if (pkM === b.pickup_method && rtM === b.return_method
        && pkFee === Number(b.delivery_fee || 0) - 0 /* approximation */){
      // Beze změny — nedělej nic.
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
    window.sb.rpc('apply_booking_changes', args).then(function(r){
      if (r.error || !r.data || r.data.success === false){
        var code = r.data && r.data.error;
        if (code === 'no_change'){
          summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
        } else {
          summary.innerHTML = '<span class="error">' + MG.t('editRez.err.generic') + '</span>';
        }
        cta.disabled = true;
        return;
      }
      var d = r.data;
      var diff = d.net_diff || 0;
      var refund = d.refund_amount || 0;
      if (diff > 0){
        summary.innerHTML = '<div class="line">' + MG.t('editRez.extend.priceDiff') + ': <strong>'
          + MG.formatPrice(diff) + '</strong></div>';
      } else if (diff < 0 || refund > 0){
        summary.innerHTML = '<div class="line refund-full">' + MG.t('editRez.cancel.refundLabel') + ': <strong>'
          + MG.formatPrice(refund || -diff) + '</strong></div>';
      } else {
        summary.innerHTML = '<span class="muted">' + MG.t('editRez.loc.noPriceChange') + '</span>';
      }
      cta.disabled = false;
    });
  }

  syncAddrVisibility();
  if (isDelP) recalcRoute('pickup');
  if (isDelR) recalcRoute('return');

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
MG._editRez._renderTabDetail = function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var days = MG._editRez._daysBetween(b.start_date, b.end_date);
  var rows = [
    [MG.t('editRez.detail.bookingId'), '<code>' + b.id.substring(0,8).toUpperCase() + '</code>'],
    [MG.t('editRez.detail.moto'), (m.brand ? m.brand + ' ' : '') + (m.model || '')],
    [MG.t('editRez.detail.dates'), MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + ' (' + MG.t('editRez.detail.daysCount', { n: days }) + ')'],
    [MG.t('editRez.detail.pickup'), (b.pickup_time || '—') + (b.pickup_address ? ' · ' + b.pickup_address : '')],
    [MG.t('editRez.detail.return'), (b.return_time || '—') + (b.return_address ? ' · ' + b.return_address : '')],
    [MG.t('editRez.detail.totalPaid'), '<strong>' + MG.formatPrice(Number(b.total_price || 0)) + '</strong>']
  ];
  var rowsHtml = rows.map(function(r){
    return '<dt>' + r[0] + '</dt><dd>' + r[1] + '</dd>';
  }).join('');
  t.innerHTML =
    '<h3>' + MG.t('editRez.detail.title') + '</h3>' +
    '<dl class="edit-rez-dl">' + rowsHtml + '</dl>' +
    MG._editRez._stornoBoxHtml();
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
    });
  });
};

// ===== Inline confirm dialog =====
MG._editRez._confirmDialog = function(title, onYes){
  var existing = document.getElementById('edit-rez-confirm-overlay');
  if (existing) existing.remove();
  var ov = document.createElement('div');
  ov.id = 'edit-rez-confirm-overlay';
  ov.className = 'edit-rez-confirm-overlay';
  ov.innerHTML =
    '<div class="edit-rez-confirm-dialog" role="dialog" aria-modal="true">' +
      '<h4>' + title + '</h4>' +
      '<div class="edit-rez-confirm-actions">' +
        '<button type="button" class="btn btn-secondary" data-no>' + MG.t('editRez.cancel.confirmNo') + '</button>' +
        '<button type="button" class="btn btnred" data-yes>' + MG.t('editRez.cancel.confirmYes') + '</button>' +
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
// Pro extend kontrolujeme překryv s ostatními rezervacemi stejné motorky.
// Používáme veřejnou RPC get_moto_booked_dates a vyřazujeme aktuální booking.
MG._editRez._loadOccupied = async function(){
  var b = MG._editRez.selectedBooking;
  if (!b || !b.moto_id) return [];
  try {
    var r = await window.sb.rpc('get_moto_booked_dates', { p_moto_id: b.moto_id });
    if (r.error){ console.warn('[editRez] occupied err', r.error); return []; }
    var data = r.data || [];
    return data.filter(function(x){
      // RPC vrací dates+status; vyhazujeme svůj vlastní booking dle datumů.
      // (RPC neuvádí booking_id; porovnáme tedy dle start+end+status, což je
      // dostatečné — pravděpodobnost, že má někdo identický rozsah, je nulová,
      // a v case match nám to jen umožní více volnosti — bezpečné fail-open.)
      return !(x.start_date === b.start_date && x.end_date === b.end_date);
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

// ===== TAB: PROLONGATION =====
// Aktivní rezervace: měnit lze JEN end_date (start je zamčený).
// Reserved: měnit lze obojí (dříve začít / později skončit).
MG._editRez._renderTabExtend = async function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var isActive = (b.status === 'active');
  var helpKey = isActive ? 'editRez.extend.helpActive' : 'editRez.extend.helpUpcoming';
  var todayIso = MG._editRez._toIsoDate(new Date());

  t.innerHTML =
    '<h3>' + MG.t('editRez.extend.title') + '</h3>' +
    '<p>' + MG.t(helpKey) + '</p>' +
    '<form id="edit-rez-extend-form" class="edit-rez-form edit-rez-date-grid" novalidate>' +
      '<label>' + MG.t('editRez.extend.newStart') +
        '<input type="date" name="newStart" value="' + b.start_date + '" min="' + (isActive ? b.start_date : todayIso) + '" max="' + b.start_date + '"' + (isActive ? ' readonly' : '') + '>' +
      '</label>' +
      '<label>' + MG.t('editRez.extend.newEnd') +
        '<input type="date" name="newEnd" value="' + b.end_date + '" min="' + b.end_date + '">' +
      '</label>' +
      '<div id="edit-rez-extend-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen" id="edit-rez-extend-cta" disabled>' + MG.t('editRez.extend.cta') + '</button>' +
    '</form>';

  // Načteme occupied jen jednou, pak cachujeme pro live recalcs.
  var occupied = await MG._editRez._loadOccupied();
  var f = document.getElementById('edit-rez-extend-form');

  function recalc(){
    var ns = f.newStart.value, ne = f.newEnd.value;
    var summary = document.getElementById('edit-rez-extend-summary');
    var cta = document.getElementById('edit-rez-extend-cta');
    if (!ns || !ne || ns > ne){
      summary.textContent = '';
      cta.disabled = true;
      return;
    }
    var noChange = (ns === b.start_date && ne === b.end_date);
    if (noChange){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true;
      return;
    }
    // Pro extend: alespoň jedno z nových dat musí být MIMO původní rozsah a
    // celý nový rozsah musí původní obsahovat (start dříve nebo stejně, end
    // později nebo stejně).
    if (ns > b.start_date || ne < b.end_date){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.err.notExtending') + '</span>';
      cta.disabled = true;
      return;
    }
    if (MG._editRez._rangeOverlapsOccupied(ns, ne, occupied)){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.extend.unavailable') + '</span>';
      cta.disabled = true;
      return;
    }
    var origPrice = MG._editRez._priceForRange(m, b.start_date, b.end_date);
    var newPrice  = MG._editRez._priceForRange(m, ns, ne);
    var diff = Math.max(0, Math.round(newPrice - origPrice));
    summary.innerHTML = '<div class="line"><span class="lbl">' + MG.t('editRez.extend.priceDiff') + ':</span> ' +
      '<strong>' + MG.formatPrice(diff) + '</strong></div>';
    cta.disabled = (diff <= 0);
  }
  f.newStart.addEventListener('change', recalc);
  f.newEnd.addEventListener('change', recalc);
  recalc();

  f.addEventListener('submit', function(e){
    e.preventDefault();
    if (MG._editRez.busy) return;
    MG._editRez._submitExtend(f.newStart.value, f.newEnd.value);
  });
};

// Pošle požadavek na Stripe Checkout přes Edge funkci `process-payment`
// (typ='extension'). Edge vrátí { url } a my zákazníka přesměrujeme.
// Webhook po úspěšné platbě atomicky aplikuje datumy + cenu (existující logika).
MG._editRez._submitExtend = async function(newStart, newEnd){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var origPrice = MG._editRez._priceForRange(m, b.start_date, b.end_date);
  var newPrice  = MG._editRez._priceForRange(m, newStart, newEnd);
  var diff = Math.round(newPrice - origPrice);
  if (diff <= 0){ MG._editRez._showError(MG.t('editRez.err.invalidRange')); return; }

  var cta = document.getElementById('edit-rez-extend-cta');
  var origLabel = cta ? cta.textContent : '';
  if (cta){ cta.disabled = true; cta.textContent = MG.t('editRez.extend.creating'); }
  MG._editRez._setBusy(true);
  try {
    // Auth token pro Edge volání.
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
        new_start_date: newStart,
        new_end_date: newEnd,
        amount: diff,
        success_url: window.location.origin + '/potvrzeni?booking_id=' + b.id,
        cancel_url:  window.location.origin + '/upravit-rezervaci'
      })
    });
    var data = await resp.json().catch(function(){ return null; });
    if (!resp.ok || !data || !data.url){
      console.error('[editRez] extend payment err', resp.status, data);
      MG._editRez._showError((data && data.error) ? data.error : MG.t('editRez.err.generic'));
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
// Reserved: měnit lze obojí (později začít / dříve skončit).
MG._editRez._renderTabShorten = function(){
  var b = MG._editRez.selectedBooking;
  var m = MG._editRez.selectedMoto || {};
  var t = document.getElementById('edit-rez-tab-content');
  var isActive = (b.status === 'active');
  var helpKey = isActive ? 'editRez.shorten.helpActive' : 'editRez.shorten.helpUpcoming';

  t.innerHTML =
    '<h3>' + MG.t('editRez.shorten.title') + '</h3>' +
    '<p>' + MG.t(helpKey) + '</p>' +
    '<form id="edit-rez-shorten-form" class="edit-rez-form edit-rez-date-grid" novalidate>' +
      '<label>' + MG.t('editRez.extend.newStart') +
        '<input type="date" name="newStart" value="' + b.start_date + '" min="' + b.start_date + '" max="' + b.end_date + '"' + (isActive ? ' readonly' : '') + '>' +
      '</label>' +
      '<label>' + MG.t('editRez.extend.newEnd') +
        '<input type="date" name="newEnd" value="' + b.end_date + '" min="' + b.start_date + '" max="' + b.end_date + '">' +
      '</label>' +
      '<label>' + MG.t('editRez.shorten.reasonLabel') +
        '<textarea name="reason" rows="2" maxlength="500"></textarea>' +
      '</label>' +
      '<div id="edit-rez-shorten-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="submit" class="btn btngreen" id="edit-rez-shorten-cta" disabled>' + MG.t('editRez.shorten.cta') + '</button>' +
    '</form>' +
    MG._editRez._stornoBoxHtml();

  var f = document.getElementById('edit-rez-shorten-form');
  function recalc(){
    var ns = f.newStart.value, ne = f.newEnd.value;
    var summary = document.getElementById('edit-rez-shorten-summary');
    var cta = document.getElementById('edit-rez-shorten-cta');
    if (!ns || !ne || ns > ne){
      summary.textContent = ''; cta.disabled = true; return;
    }
    var noChange = (ns === b.start_date && ne === b.end_date);
    if (noChange){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true; return;
    }
    // Pro shorten: nové datumy musí být UVNITŘ původních.
    if (ns < b.start_date || ne > b.end_date){
      summary.innerHTML = '<span class="error">' + MG.t('editRez.err.notShortening') + '</span>';
      cta.disabled = true; return;
    }
    var origPrice = MG._editRez._priceForRange(m, b.start_date, b.end_date);
    var newPrice  = MG._editRez._priceForRange(m, ns, ne);
    var diff = Math.max(0, Math.round(origPrice - newPrice));
    if (diff <= 0){
      summary.innerHTML = '<span class="muted">' + MG.t('editRez.extend.noChange') + '</span>';
      cta.disabled = true; return;
    }
    // Refund % podle nového konce / začátku (shoda s SQL backend logikou).
    var target = (ne < b.end_date) ? ne : ns;
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
  f.newStart.addEventListener('change', recalc);
  f.newEnd.addEventListener('change', recalc);
  recalc();

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
      await MG._editRez._loadBookings();
      MG._editRez._goto('list');
      return;
    }
  } catch(e){ /* fallthrough do login */ }
  MG._editRez._goto('login');
};
