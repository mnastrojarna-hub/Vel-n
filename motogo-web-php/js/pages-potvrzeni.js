// ===== MotoGo24 Web PHP — Potvrzení platby (po Stripe) =====
// Lokalizované děkovací stránky pro 3 toky: rezervace, e-shop poukaz, free booking.
// Texty bere z window.MOTOGO_CONFIRM_I18N (předává PHP), redirect tlačítka cílí
// vždy na kanonickou doménu pro daný jazyk (cs → motogo24.cz, ostatní → motogo24.com).

(function(){
  var MG = window.MG || {};
  window.MG = MG;
  var I18N = window.MOTOGO_CONFIRM_I18N || {};
  var HOME = I18N.homeUrl || '/';
  var SHOP = I18N.shopUrl || '/eshop';
  var REZ  = I18N.rezUrl  || '/rezervace';
  var JS_LOCALE = I18N.jsLocale || 'cs-CZ';

  function fmt(tpl, vars){
    if(!tpl) return '';
    if(!vars) return tpl;
    return Object.keys(vars).reduce(function(acc, k){
      return acc.replace(new RegExp('\\{'+k+'\\}','g'), vars[k] == null ? '' : vars[k]);
    }, tpl);
  }
  function esc(s){
    if(s == null) return '';
    return String(s).replace(/[&<>"']/g, function(c){
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
    });
  }
  function fmtDate(s){
    if(!s) return '';
    try { return new Date(s).toLocaleDateString(JS_LOCALE); }
    catch(e){ return s; }
  }
  function fmtPrice(v){
    if(MG.formatPrice) return MG.formatPrice(v);
    return Number(v||0).toLocaleString(JS_LOCALE) + ' Kč';
  }

  function getParam(key){
    var params = new URLSearchParams(window.location.search);
    return params.get(key) || '';
  }

  async function init(){
    var sid = getParam('session_id');
    var oid = getParam('order_id');
    var bid = getParam('booking_id');

    var isShop = !!oid;
    var isFreeBooking = !!bid && !sid;

    var el = document.getElementById('confirm-content');
    if(!el) return;

    if(!sid && !oid && !bid){
      el.innerHTML = renderError(I18N.errorMissingId || 'Missing payment identifier.');
      return;
    }

    // --- FREE BOOKING (100% sleva) ---
    if(isFreeBooking){
      var found = false;
      for(var i = 0; i < 6; i++){
        try {
          var r = await window.sb.from('bookings')
            .select('id,customer_name,customer_email,moto_id,start_date,end_date,total_price,payment_status,status')
            .eq('id', bid).maybeSingle();
          if(r.data && r.data.payment_status === 'paid'){ el.innerHTML = renderBookingSuccess(r.data); found = true; break; }
          if(r.data && r.data.payment_status === 'unpaid' && i < 5){ await sleep(1500); continue; }
          if(r.data){ el.innerHTML = renderPending(r.data, 'booking'); found = true; break; }
        } catch(e){ console.warn('[CONFIRM] free booking poll error', e); }
        await sleep(1500);
      }
      if(!found) el.innerHTML = renderPending(null, 'booking');
      return;
    }

    // --- SHOP / VOUCHER ORDER ---
    if(isShop){
      var found = false;
      for(var i = 0; i < 12; i++){
        try {
          var r = await window.sb.from('shop_orders')
            .select('id,order_number,customer_name,customer_email,total,payment_status,status')
            .eq('id', oid).maybeSingle();
          if(r.data && r.data.payment_status === 'paid'){
            var vc = await window.sb.from('vouchers').select('code,amount,valid_until').eq('order_id', oid);
            var hasVouchers = vc.data && vc.data.length > 0;
            el.innerHTML = hasVouchers
              ? renderVoucherSuccess(r.data, vc.data)
              : renderShopSuccess(r.data);
            found = true; break;
          }
          if(r.data && r.data.payment_status !== 'paid' && i < 11){ await sleep(2000); continue; }
          if(r.data){ el.innerHTML = renderPending(r.data, 'order'); found = true; break; }
        } catch(e){ console.warn('[CONFIRM] shop poll error', e); }
        await sleep(2000);
      }
      if(!found) el.innerHTML = renderPending(null, 'order');
      return;
    }

    // --- BOOKING via Stripe session ---
    var found = false;
    for(var i = 0; i < 10; i++){
      try {
        var r = await window.sb.from('bookings')
          .select('id,customer_name,customer_email,moto_id,start_date,end_date,total_price,payment_status,status')
          .eq('stripe_session_id', sid).maybeSingle();
        if(r.data && r.data.payment_status === 'paid'){ el.innerHTML = renderBookingSuccess(r.data); found = true; break; }
        if(r.data && r.data.payment_status === 'unpaid' && i < 9){ await sleep(2000); continue; }
        if(r.data){ el.innerHTML = renderPending(r.data, 'booking'); found = true; break; }
      } catch(e){ console.warn('[CONFIRM] poll error', e); }
      await sleep(2000);
    }
    if(!found) el.innerHTML = renderPending(null, 'booking');
  }

  function sleep(ms){ return new Promise(function(ok){ setTimeout(ok, ms); }); }

  function summaryRow(label, value){
    return '<p><strong>' + esc(label) + ':</strong> ' + value + '</p>';
  }

  function nextStepsList(items){
    if(!items || !items.length) return '';
    var lis = items.map(function(t){ return '<li>' + esc(t) + '</li>'; }).join('');
    return '<div class="confirm-next">' +
      '<h3>' + esc(I18N.nextTitle || '') + '</h3>' +
      '<ol>' + lis + '</ol>' +
      '</div>';
  }

  function backHomeBtn(){
    return '<p style="margin-top:1.5rem">' +
      '<a class="btn btngreen" href="' + esc(HOME) + '">' + esc(I18N.backHome || 'Home') + '</a></p>';
  }

  function renderBookingSuccess(b){
    var name = (b && b.customer_name) || '';
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon || '');
    var shortId = b && b.id ? String(b.id).slice(-8).toUpperCase() : '';

    var summary = '<div class="confirm-summary">' +
      '<h3>' + esc(I18N.summaryTitle || 'Summary') + '</h3>' +
      (shortId ? summaryRow(I18N.bookingNumber, '<strong>#' + esc(shortId) + '</strong>') : '') +
      (b && b.start_date ? summaryRow(I18N.period, esc(fmtDate(b.start_date)) + ' – ' + esc(fmtDate(b.end_date))) : '') +
      (b && b.total_price != null ? summaryRow(I18N.total, esc(fmtPrice(b.total_price))) : '') +
      summaryRow(I18N.paid, '✓') +
      (b && b.customer_email ? summaryRow(I18N.email, esc(b.customer_email)) : '') +
      '</div>';

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + esc(I18N.successBookingTitle || 'Booking confirmed!') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      summary +
      '<p class="confirm-emailed">' + esc(I18N.emailSentBooking || '') + '</p>' +
      nextStepsList([
        I18N.nextBookingDocs,
        I18N.nextBookingCodes,
        I18N.nextBookingPickup,
        I18N.nextContact
      ].filter(Boolean)) +
      backHomeBtn() +
      '</div>';
  }

  function renderShopSuccess(order){
    var name = (order && order.customer_name) || '';
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon || '');

    var summary = '<div class="confirm-summary">' +
      '<h3>' + esc(I18N.summaryTitle || 'Summary') + '</h3>' +
      (order && order.order_number ? summaryRow(I18N.orderNumber, '<strong>' + esc(order.order_number) + '</strong>') : '') +
      (order && order.total != null ? summaryRow(I18N.total, esc(fmtPrice(order.total))) : '') +
      summaryRow(I18N.paid, '✓') +
      (order && order.customer_email ? summaryRow(I18N.email, esc(order.customer_email)) : '') +
      '</div>';

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + esc(I18N.successOrderTitle || 'Order paid!') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      summary +
      '<p class="confirm-emailed">' + esc(I18N.emailSentOrder || '') + '</p>' +
      nextStepsList([
        I18N.nextOrderShip,
        I18N.nextContact
      ].filter(Boolean)) +
      '<p style="margin-top:1.5rem">' +
        '<a class="btn btngreen" href="' + esc(SHOP) + '">' + esc(I18N.continueShopping || 'Shop') + '</a>' +
        '&nbsp;<a class="btn btndark" href="' + esc(HOME) + '">' + esc(I18N.backHome || 'Home') + '</a>' +
      '</p>' +
      '</div>';
  }

  function renderVoucherSuccess(order, vouchers){
    var name = (order && order.customer_name) || '';
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon || '');

    var voucherHtml = '';
    if(vouchers && vouchers.length){
      voucherHtml = '<div class="confirm-vouchers">';
      vouchers.forEach(function(v){
        var validUntil = v.valid_until ? fmtDate(v.valid_until) : '—';
        voucherHtml += '<div class="confirm-voucher-card">' +
          '<div class="confirm-voucher-label">' + esc(I18N.voucherCode || 'Voucher code') + '</div>' +
          '<div class="confirm-voucher-code">' + esc(v.code || '') + '</div>' +
          '<div class="confirm-voucher-amount">' + esc(fmtPrice(v.amount)) + '</div>' +
          '<div class="confirm-voucher-validity">' + esc(fmt(I18N.validUntil || 'Valid until {date}', {date: validUntil})) + '</div>' +
          '</div>';
      });
      voucherHtml += '</div>';
    }

    var summary = '<div class="confirm-summary">' +
      '<h3>' + esc(I18N.summaryTitle || 'Summary') + '</h3>' +
      (order && order.order_number ? summaryRow(I18N.orderNumber, '<strong>' + esc(order.order_number) + '</strong>') : '') +
      (order && order.total != null ? summaryRow(I18N.total, esc(fmtPrice(order.total))) : '') +
      summaryRow(I18N.paid, '✓') +
      (order && order.customer_email ? summaryRow(I18N.email, esc(order.customer_email)) : '') +
      '</div>';

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + esc(I18N.successVoucherTitle || 'Voucher paid!') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      voucherHtml +
      summary +
      '<p class="confirm-emailed">' + esc(I18N.emailSentVoucher || '') + '</p>' +
      nextStepsList([
        I18N.nextVoucherEmail,
        I18N.nextVoucherPrint,
        I18N.nextContact
      ].filter(Boolean)) +
      backHomeBtn() +
      '</div>';
  }

  function renderPending(rec, kind){
    var rowsHtml = '';
    if(rec){
      rowsHtml += '<div class="confirm-summary">';
      if(kind === 'booking'){
        if(rec.start_date) rowsHtml += summaryRow(I18N.period, esc(fmtDate(rec.start_date)) + ' – ' + esc(fmtDate(rec.end_date)));
      } else {
        if(rec.order_number) rowsHtml += summaryRow(I18N.orderNumber, '<strong>' + esc(rec.order_number) + '</strong>');
      }
      rowsHtml += '</div>';
    }
    return '<div class="confirm-page confirm-pending">' +
      '<div class="confirm-icon" aria-hidden="true">⏳</div>' +
      '<h1>' + esc(I18N.pendingTitle || 'Payment pending') + '</h1>' +
      '<p>' + esc(I18N.pendingText1 || '') + '</p>' +
      '<p>' + esc(I18N.pendingText2 || '') + '</p>' +
      rowsHtml +
      backHomeBtn() +
      '</div>';
  }

  function renderError(msg){
    var phone = I18N.errorContactPhone || '+420 774 256 271';
    var phoneHref = phone.replace(/\s+/g, '');
    return '<div class="confirm-page confirm-error">' +
      '<div class="confirm-icon" aria-hidden="true">⚠</div>' +
      '<h1>' + esc(I18N.errorTitle || 'Error') + '</h1>' +
      '<p>' + esc(msg) + '</p>' +
      '<p>' + esc(I18N.errorContactPrefix || 'Contact us at') + ' <a href="tel:' + esc(phoneHref) + '">' + esc(phone) + '</a></p>' +
      '<p style="margin-top:1.5rem">' +
        '<a class="btn btngreen" href="' + esc(REZ) + '">' + esc(I18N.errorTryAgain || 'Try again') + '</a>' +
        '&nbsp;<a class="btn btndark" href="' + esc(HOME) + '">' + esc(I18N.backHome || 'Home') + '</a>' +
      '</p>' +
      '</div>';
  }

  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', function(){ setTimeout(init, 200); });
  } else { setTimeout(init, 200); }
})();
