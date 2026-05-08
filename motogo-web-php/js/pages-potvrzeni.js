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

  // CMS admin režim — index.php po ověření `?cms_admin=<token>` nastaví cookie
  // `mg_cms_admin=1` a token z URL stripne (redirect). Preview tedy nesmíme
  // detekovat podle URL parametru, ale podle cookie — jinak po redirectu
  // pages-potvrzeni.js spadne do error stavu „Chybí identifikátor platby".
  function isCmsAdmin(){
    try { return /(?:^|;\s*)mg_cms_admin=1(?:;|$)/.test(document.cookie); }
    catch(e){ return false; }
  }

  // CMS-aware překlad pro body kontext: pro adminy obalí výsledek do
  // `<span data-cms-key="web.layout.<klíč>">…</span>`, aby cms-admin.js
  // (pravý-klik = inline editor) mohl saved value uložit do cms_variables.
  // Reálná stránka i mock preview čtou stejný cms_variables klíč, takže
  // úprava ve Velíně i na webu se projeví okamžitě v obou kontextech.
  // Pro atributy (title, aria-label, href) a placeholder-bearing texty
  // (např. `thanks` s `{name}`) používej dál `esc(I18N.X)`.
  function tc(jsKey){
    var raw = I18N[jsKey];
    if (raw == null) raw = '';
    var safe = esc(raw);
    if (!isCmsAdmin()) return safe;
    var map = window.MOTOGO_CONFIRM_CMS_KEYS || {};
    var cmsKey = map[jsKey];
    if (!cmsKey) return safe;
    return '<span class="mg-cms-text" data-cms-key="web.layout.' + cmsKey + '">' + safe + '</span>';
  }

  // Google Ads conversion via GTM dataLayer. Vystřelí jen jednou per
  // transaction_id (sessionStorage guard) — refresh /potvrzeni nebo opětovné
  // dotažení dat nezpůsobí dvojí započtení konverze v Google Ads.
  // V GTM se nastaví trigger Custom Event = "purchase" → Google Ads Conversion
  // Tag (conversion ID + label si dodá inzerent v GTM, ne v kódu).
  function pushPurchaseConversion(kind, txId, value, currency, extras){
    if(!txId) return;
    try {
      var key = 'mg_conv_' + kind + '_' + txId;
      if(window.sessionStorage && sessionStorage.getItem(key)) return;
      window.dataLayer = window.dataLayer || [];
      window.dataLayer.push({ ecommerce: null });
      var payload = {
        event: 'purchase',
        conversion_type: kind,
        ecommerce: {
          transaction_id: String(txId),
          value: Number(value || 0),
          currency: currency || 'CZK'
        }
      };
      if(extras && typeof extras === 'object'){
        Object.keys(extras).forEach(function(k){
          if(extras[k] != null) payload[k] = extras[k];
        });
      }
      window.dataLayer.push(payload);
      if(window.sessionStorage) sessionStorage.setItem(key, '1');
    } catch(e){ /* analytics nesmí shodit stránku */ }
  }

  // CMS preview režim — když je v URL `cms_admin` token, neptej se Supabase
  // a rovnou rendruj mock data podle `?preview=booking|order|voucher|pending|error`.
  // Defaultně booking; konverze do GTM se v preview NESPOUŠTÍ.
  function renderPreview(){
    var el = document.getElementById('confirm-content');
    if(!el) return;
    var preview = (getParam('preview') || 'booking').toLowerCase();
    var mockBooking = {
      id: 'PREVIEWBOOKING12345678',
      customer_name: 'Petra Nováková',
      customer_email: 'petra.novakova@example.cz',
      moto_id: 'preview-moto',
      start_date: '2026-05-10',
      end_date: '2026-05-14',
      total_price: 4900,
      payment_status: 'paid',
      status: 'confirmed'
    };
    var mockOrder = {
      id: 'PREVIEWORDER',
      order_number: 'MG-2026-0042',
      customer_name: 'Petra Nováková',
      customer_email: 'petra.novakova@example.cz',
      total: 1290,
      payment_status: 'paid',
      status: 'paid'
    };
    var mockVouchers = [
      { code: 'MG-PREVIEW-2000', amount: 2000, valid_until: '2027-05-10' }
    ];
    if(preview === 'order'){
      el.innerHTML = renderShopSuccess(mockOrder);
    } else if(preview === 'voucher'){
      el.innerHTML = renderVoucherSuccess(mockOrder, mockVouchers);
    } else if(preview === 'pending' || preview === 'pending_booking'){
      var pendingMock = Object.assign({}, mockBooking, { payment_status: 'unpaid' });
      el.innerHTML = renderPending(pendingMock, 'booking');
    } else if(preview === 'pending_order'){
      var pendingOrder = Object.assign({}, mockOrder, { payment_status: 'unpaid' });
      el.innerHTML = renderPending(pendingOrder, 'order');
    } else if(preview === 'pending_voucher'){
      var pendingVoucher = Object.assign({}, mockOrder, { payment_status: 'unpaid', order_number: 'MG-VCH-2026-0042' });
      el.innerHTML = renderPending(pendingVoucher, 'order');
    } else if(preview === 'error'){
      el.innerHTML = renderError(I18N.errorMissingId || 'Missing payment identifier.');
    } else {
      el.innerHTML = renderBookingSuccess(mockBooking);
    }
  }

  async function init(){
    if(isCmsAdmin() || getParam('cms_admin')){
      renderPreview();
      return;
    }

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
    // Web booking je anonymní (žádná auth session) → přímý select na bookings
    // narazí na RLS (`user_id = auth.uid()`). Použijeme SECURITY DEFINER RPC
    // `get_web_booking_confirmation`, která vrací jen veřejně bezpečná pole
    // (status + jméno/email z profilu pro greeting), granted to anon.
    if(isFreeBooking){
      var found = false;
      for(var i = 0; i < 6; i++){
        try {
          var r = await window.sb.rpc('get_web_booking_confirmation', { p_booking_id: bid });
          var rec = r && r.data && !r.data.error ? r.data : null;
          if(rec && rec.payment_status === 'paid'){
            el.innerHTML = renderBookingSuccess(rec);
            pushPurchaseConversion('booking', rec.id, rec.total_price, 'CZK', { is_free: true });
            found = true; break;
          }
          if(rec && rec.payment_status === 'unpaid' && i < 5){ await sleep(1500); continue; }
          if(rec){ el.innerHTML = renderPending(rec, 'booking'); found = true; break; }
        } catch(e){ console.warn('[CONFIRM] free booking poll error', e); }
        await sleep(1500);
      }
      if(!found) el.innerHTML = renderPending(null, 'booking');
      return;
    }

    // --- SHOP / VOUCHER ORDER ---
    // Anon JWT neprojde RLS na shop_orders (customer_id IS NULL pro web objednávky),
    // takže polling přes přímý select vrací prázdno a stránka navždy ukazuje "Pending".
    // SECURITY DEFINER RPC `get_web_shop_order_confirmation` to obchází a vrací i vouchery.
    if(isShop){
      var found = false;
      for(var i = 0; i < 12; i++){
        try {
          var r = await window.sb.rpc('get_web_shop_order_confirmation', { p_order_id: oid });
          var rec = r && r.data && !r.data.error ? r.data : null;
          if(rec && rec.payment_status === 'paid'){
            var vouchersArr = Array.isArray(rec.vouchers) ? rec.vouchers : [];
            var hasVouchers = vouchersArr.length > 0;
            el.innerHTML = hasVouchers
              ? renderVoucherSuccess(rec, vouchersArr)
              : renderShopSuccess(rec);
            pushPurchaseConversion(hasVouchers ? 'voucher' : 'shop_order', rec.order_number || rec.id, rec.total, 'CZK');
            found = true; break;
          }
          if(rec && rec.payment_status !== 'paid' && i < 11){ await sleep(2000); continue; }
          if(rec){ el.innerHTML = renderPending(rec, 'order'); found = true; break; }
        } catch(e){ console.warn('[CONFIRM] shop poll error', e); }
        await sleep(2000);
      }
      if(!found) el.innerHTML = renderPending(null, 'order');
      return;
    }

    // --- BOOKING via Stripe session ---
    // Stejně jako u free booking: anon JWT neprojde RLS, voláme SECURITY DEFINER RPC.
    var found = false;
    for(var i = 0; i < 10; i++){
      try {
        var r = await window.sb.rpc('get_web_booking_confirmation', { p_session_id: sid });
        var rec = r && r.data && !r.data.error ? r.data : null;
        if(rec && rec.payment_status === 'paid'){
          el.innerHTML = renderBookingSuccess(rec);
          pushPurchaseConversion('booking', rec.id, rec.total_price, 'CZK', { stripe_session_id: sid });
          found = true; break;
        }
        if(rec && rec.payment_status === 'unpaid' && i < 9){ await sleep(2000); continue; }
        if(rec){ el.innerHTML = renderPending(rec, 'booking'); found = true; break; }
      } catch(e){ console.warn('[CONFIRM] poll error', e); }
      await sleep(2000);
    }
    if(!found) el.innerHTML = renderPending(null, 'booking');
  }

  function sleep(ms){ return new Promise(function(ok){ setTimeout(ok, ms); }); }

  // Položky `items` přicházejí jako pole [jsKey, ...], aby každá <li> mohla mít
  // vlastní data-cms-key (jinak by inline edit nahradil všechny kroky najednou).
  function nextStepsList(items){
    if(!items || !items.length) return '';
    var lis = items.map(function(jsKey){
      var v = I18N[jsKey];
      if (!v) return '';
      return '<li>' + tc(jsKey) + '</li>';
    }).filter(Boolean).join('');
    if (!lis) return '';
    return '<div class="confirm-next">' +
      '<h3>' + tc('nextTitle') + '</h3>' +
      '<ol>' + lis + '</ol>' +
      '</div>';
  }

  function backHomeBtn(){
    return '<p style="margin-top:1.5rem">' +
      '<a class="btn btngreen" href="' + esc(HOME) + '">' + tc('backHome') + '</a></p>';
  }

  // summaryRow s podporou inline editace popisku (label) — value je dynamická
  // hodnota z DB (jméno, datum), nikdy se needituje.
  function summaryRowTc(jsKey, value){
    return '<p><strong>' + tc(jsKey) + ':</strong> ' + value + '</p>';
  }

  function renderBookingSuccess(b){
    var name = (b && b.customer_name) || '';
    // `thanks` má placeholder `{name}` → wrapping span by uložil rendered text
    // s konkrétním jménem zákazníka. Necháme bez data-cms-key; admin edituje
    // šablonu ve Velíně.
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon ? tc('thanksAnon') : '');
    var shortId = b && b.id ? String(b.id).slice(-8).toUpperCase() : '';
    // docs_status: NULL = doklady OK; jinak český důvod (zobrazit ho).
    // Backend RPC `get_web_booking_confirmation` reflektuje stejnou logiku jako
    // trigger `auto_generate_door_codes` → co je v door_codes mailu, sedí i tady.
    var docsStatus = b && Object.prototype.hasOwnProperty.call(b, 'docs_status') ? b.docs_status : undefined;
    var docsOk = docsStatus === null;
    var docsMissing = typeof docsStatus === 'string' && docsStatus.length > 0;

    var summary = '<div class="confirm-summary">' +
      '<h3>' + tc('summaryTitle') + '</h3>' +
      (shortId ? summaryRowTc('bookingNumber', '<strong>#' + esc(shortId) + '</strong>') : '') +
      (b && b.start_date ? summaryRowTc('period', esc(fmtDate(b.start_date)) + ' – ' + esc(fmtDate(b.end_date))) : '') +
      (b && b.total_price != null ? summaryRowTc('total', esc(fmtPrice(b.total_price))) : '') +
      summaryRowTc('paid', '✓') +
      (docsOk ? '<p><strong>' + esc(I18N.docsLabel || 'Doklady') + ':</strong> <span style="color:#1a8c1a">✓ ' + esc(I18N.docsVerified || 'Ověřeny') + '</span></p>' : '') +
      (b && b.customer_email ? summaryRowTc('email', esc(b.customer_email)) : '') +
      '</div>';

    // Docs step: pokud OK → zelený potvrzovací řádek; pokud chybí → varování + CTA;
    // pokud docs_status undefined (starší RPC bez fieldu) → fallback na původní text.
    var docsStep;
    if(docsOk){
      docsStep = '<span style="color:#1a8c1a">✓ ' + esc(I18N.nextBookingDocsDone || 'Doklady jsme ověřili — žádná akce není potřeba.') + '</span>';
    } else if(docsMissing){
      docsStep = '<strong style="color:#b35900">⚠ ' + esc(docsStatus) + '</strong>';
    } else {
      docsStep = tc('nextBookingDocs');
    }

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + tc('successBookingTitle') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      summary +
      '<p class="confirm-emailed">' + tc('emailSentBooking') + '</p>' +
      nextStepsListHtml([
        docsStep,
        (docsOk
          ? (I18N.nextBookingCodesDone ? tc('nextBookingCodesDone') : '')
          : (I18N.nextBookingCodes ? tc('nextBookingCodes') : '')),
        I18N.nextBookingPickup ? tc('nextBookingPickup') : '',
        I18N.nextContact ? tc('nextContact') : ''
      ].filter(Boolean)) +
      (I18N.seeYouSoon ? '<p class="confirm-see-you" style="margin-top:1rem;font-weight:600">' + tc('seeYouSoon') + '</p>' : '') +
      backHomeBtn() +
      '</div>';
  }

  // Varianta nextStepsList která NEEsc položky (umožňuje vlastní HTML, např. ✓ barevné).
  // Bezpečnost: volající musí escapovat user-controlled obsah sám (renderBookingSuccess
  // escapuje `docsStatus` když ho vkládá).
  function nextStepsListHtml(items){
    if(!items || !items.length) return '';
    var lis = items.map(function(t){ return '<li>' + (t || '') + '</li>'; }).join('');
    return '<div class="confirm-next">' +
      '<h3>' + tc('nextTitle') + '</h3>' +
      '<ol>' + lis + '</ol>' +
      '</div>';
  }

  function renderShopSuccess(order){
    var name = (order && order.customer_name) || '';
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon ? tc('thanksAnon') : '');

    var summary = '<div class="confirm-summary">' +
      '<h3>' + tc('summaryTitle') + '</h3>' +
      (order && order.order_number ? summaryRowTc('orderNumber', '<strong>' + esc(order.order_number) + '</strong>') : '') +
      (order && order.total != null ? summaryRowTc('total', esc(fmtPrice(order.total))) : '') +
      summaryRowTc('paid', '✓') +
      (order && order.customer_email ? summaryRowTc('email', esc(order.customer_email)) : '') +
      '</div>';

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + tc('successOrderTitle') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      summary +
      '<p class="confirm-emailed">' + tc('emailSentOrder') + '</p>' +
      nextStepsList(['nextOrderShip', 'nextContact']) +
      '<p style="margin-top:1.5rem">' +
        '<a class="btn btngreen" href="' + esc(SHOP) + '">' + tc('continueShopping') + '</a>' +
        '&nbsp;<a class="btn btndark" href="' + esc(HOME) + '">' + tc('backHome') + '</a>' +
      '</p>' +
      '</div>';
  }

  function renderVoucherSuccess(order, vouchers){
    var name = (order && order.customer_name) || '';
    var greet = name ? fmt(I18N.thanks || '', {name: esc(name)}) : (I18N.thanksAnon ? tc('thanksAnon') : '');

    var voucherHtml = '';
    if(vouchers && vouchers.length){
      voucherHtml = '<div class="confirm-vouchers">';
      vouchers.forEach(function(v){
        var validUntil = v.valid_until ? fmtDate(v.valid_until) : '—';
        // `validUntil` má placeholder `{date}` → necháme bez data-cms-key.
        voucherHtml += '<div class="confirm-voucher-card">' +
          '<div class="confirm-voucher-label">' + tc('voucherCode') + '</div>' +
          '<div class="confirm-voucher-code">' + esc(v.code || '') + '</div>' +
          '<div class="confirm-voucher-amount">' + esc(fmtPrice(v.amount)) + '</div>' +
          '<div class="confirm-voucher-validity">' + esc(fmt(I18N.validUntil || 'Valid until {date}', {date: validUntil})) + '</div>' +
          '</div>';
      });
      voucherHtml += '</div>';
    }

    var summary = '<div class="confirm-summary">' +
      '<h3>' + tc('summaryTitle') + '</h3>' +
      (order && order.order_number ? summaryRowTc('orderNumber', '<strong>' + esc(order.order_number) + '</strong>') : '') +
      (order && order.total != null ? summaryRowTc('total', esc(fmtPrice(order.total))) : '') +
      summaryRowTc('paid', '✓') +
      (order && order.customer_email ? summaryRowTc('email', esc(order.customer_email)) : '') +
      '</div>';

    return '<div class="confirm-page confirm-success">' +
      '<div class="confirm-icon" aria-hidden="true">✔</div>' +
      '<h1>' + tc('successVoucherTitle') + '</h1>' +
      '<p class="confirm-lead">' + greet + '</p>' +
      voucherHtml +
      summary +
      '<p class="confirm-emailed">' + tc('emailSentVoucher') + '</p>' +
      nextStepsList(['nextVoucherEmail', 'nextVoucherPrint', 'nextContact']) +
      backHomeBtn() +
      '</div>';
  }

  function renderPending(rec, kind){
    var rowsHtml = '';
    var bid = (rec && rec.id) || getParam('booking_id') || '';
    if(rec){
      rowsHtml += '<div class="confirm-summary">';
      if(kind === 'booking'){
        if(rec.start_date) rowsHtml += summaryRowTc('period', esc(fmtDate(rec.start_date)) + ' – ' + esc(fmtDate(rec.end_date)));
      } else {
        if(rec.order_number) rowsHtml += summaryRowTc('orderNumber', '<strong>' + esc(rec.order_number) + '</strong>');
      }
      rowsHtml += '</div>';
    }
    var stepKeys = ['pendingNextStep1', 'pendingNextStep2', 'pendingNextStep3'].filter(function(k){ return I18N[k]; });
    var stepsHtml = stepKeys.length ? '<div class="confirm-next">' +
      '<h3>' + (I18N.pendingNextTitle ? tc('pendingNextTitle') : tc('nextTitle')) + '</h3>' +
      '<ol>' + stepKeys.map(function(k){ return '<li>' + tc(k) + '</li>'; }).join('') + '</ol>' +
      '</div>' : '';
    var reasonKeys = ['pendingReason1','pendingReason2','pendingReason3','pendingReason4','pendingReason5','pendingReason6']
      .filter(function(k){ return I18N[k]; });
    var reasonsHtml = reasonKeys.length ? '<details class="confirm-reasons" style="margin-top:1.25rem">' +
      '<summary style="cursor:pointer;font-weight:600">' + tc('pendingFailIntro') + '</summary>' +
      '<ul style="margin-top:.5rem">' + reasonKeys.map(function(k){ return '<li>' + tc(k) + '</li>'; }).join('') + '</ul>' +
      '</details>' : '';

    var retryUrl = '';
    if(kind === 'booking' && bid){
      retryUrl = REZ + (REZ.indexOf('?') >= 0 ? '&' : '?') + 'resume=' + encodeURIComponent(bid);
    } else if(kind === 'order'){
      retryUrl = (I18N.cartUrl || SHOP);
    }
    var retryLabel = I18N.retryPayment ? tc('retryPayment') : (I18N.errorTryAgain ? tc('errorTryAgain') : esc('Try again'));
    var retryBtn = retryUrl ? '<a class="btn btngreen" href="' + esc(retryUrl) + '">' + retryLabel + '</a>&nbsp;' : '';
    var phone = I18N.errorContactPhone || '+420 774 256 271';
    var contactHtml = '<p style="margin-top:.75rem">' + tc('errorContactPrefix') + ' <a href="tel:' + esc(phone.replace(/\s+/g, '')) + '">' + tc('errorContactPhone') + '</a></p>';

    return '<div class="confirm-page confirm-pending">' +
      '<div class="confirm-icon" aria-hidden="true">⏳</div>' +
      '<h1>' + tc('pendingTitle') + '</h1>' +
      '<p>' + tc('pendingText1') + '</p>' +
      '<p>' + tc('pendingText2') + '</p>' +
      rowsHtml +
      stepsHtml +
      reasonsHtml +
      contactHtml +
      '<p style="margin-top:1.25rem">' + retryBtn +
        '<a class="btn btndark" href="' + esc(HOME) + '">' + tc('backHome') + '</a>' +
      '</p>' +
      '</div>';
  }

  function renderError(msg){
    var phone = I18N.errorContactPhone || '+420 774 256 271';
    var phoneHref = phone.replace(/\s+/g, '');
    // `msg` je defaultně I18N.errorMissingId (jediný error msg, který se sem
    // posílá) — wrapni ho přes tc, ať admin může editovat. Pokud volající
    // pošle jiný msg, fallback na esc.
    var msgHtml = (msg === I18N.errorMissingId) ? tc('errorMissingId') : esc(msg);
    return '<div class="confirm-page confirm-error">' +
      '<div class="confirm-icon" aria-hidden="true">⚠</div>' +
      '<h1>' + tc('errorTitle') + '</h1>' +
      '<p>' + msgHtml + '</p>' +
      '<p>' + tc('errorContactPrefix') + ' <a href="tel:' + esc(phoneHref) + '">' + tc('errorContactPhone') + '</a></p>' +
      '<p style="margin-top:1.5rem">' +
        '<a class="btn btngreen" href="' + esc(REZ) + '">' + tc('errorTryAgain') + '</a>' +
        '&nbsp;<a class="btn btndark" href="' + esc(HOME) + '">' + tc('backHome') + '</a>' +
      '</p>' +
      '</div>';
  }

  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', function(){ setTimeout(init, 200); });
  } else { setTimeout(init, 200); }
})();
