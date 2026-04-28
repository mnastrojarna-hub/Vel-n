// ===== MotoGo24 Web — E-shop pokladna =====
// Renderuje souhrn košíku, validuje formulář, volá RPC create_web_shop_order
// (anon-friendly, validuje ceny v DB), pak proces-payment edge fn → Stripe
// Checkout. Vyžaduje window.MGCart (cart.js) a window.sb (supabase-init.js).
(function(){
  'use strict';

  var SHIP_PRICES = { pickup: 0, post: 99, zasilkovna: 79 };

  function fmtPrice(amount){
    var v = Math.round(Number(amount) || 0);
    return v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' Kč';
  }
  function escapeHtml(s){
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  function init(){
    var loading = document.querySelector('[data-checkout-loading]');
    var empty   = document.querySelector('[data-checkout-empty]');
    var content = document.querySelector('[data-checkout-content]');
    var form    = document.querySelector('[data-checkout-form]');
    if (!form) return;

    var i18n = window.MG_I18N || {};
    var items = (window.MGCart ? window.MGCart.load() : []);
    if (loading) loading.setAttribute('hidden','');

    if (!items.length) {
      if (empty)   empty.removeAttribute('hidden');
      if (content) content.setAttribute('hidden','');
      return;
    }
    if (empty)   empty.setAttribute('hidden','');
    if (content) content.removeAttribute('hidden');

    // Render summary list
    var listEl = form.querySelector('[data-checkout-items]');
    if (listEl) {
      listEl.innerHTML = items.map(function(it){
        var sizeBadge = it.size ? '<span class="checkout-line-size">' + escapeHtml(it.size) + '</span>' : '';
        var line = (Number(it.price) || 0) * (Number(it.qty) || 0);
        return '<div class="checkout-line">'
          + '<div class="checkout-line-info"><strong>' + escapeHtml(it.name) + '</strong> ' + sizeBadge
          +   '<small>' + (it.qty|0) + ' × ' + fmtPrice(it.price) + '</small></div>'
          + '<div class="checkout-line-amount">' + fmtPrice(line) + '</div>'
          + '</div>';
      }).join('');
    }

    var subEl  = form.querySelector('[data-checkout-subtotal]');
    var shipEl = form.querySelector('[data-checkout-shipping]');
    var totEl  = form.querySelector('[data-checkout-total]');
    var payEl  = form.querySelector('[data-checkout-pay]');
    var addrBox = form.querySelector('[data-checkout-address]');

    function selectedShip(){
      var input = form.querySelector('[data-ship-method]:checked');
      return input ? input.value : 'pickup';
    }
    function recompute(){
      var ship = selectedShip();
      var subtotal = items.reduce(function(a, it){
        return a + (Number(it.price) || 0) * (Number(it.qty) || 0);
      }, 0);
      var shipCost = SHIP_PRICES[ship] || 0;
      var total = subtotal + shipCost;
      if (subEl)  subEl.textContent  = fmtPrice(subtotal);
      if (shipEl) shipEl.textContent = shipCost > 0 ? fmtPrice(shipCost) : (i18n.shipping_free || 'zdarma');
      if (totEl)  totEl.textContent  = fmtPrice(total);
      if (payEl)  payEl.textContent  = fmtPrice(total);
      if (addrBox) {
        if (ship === 'pickup') addrBox.setAttribute('hidden','');
        else                   addrBox.removeAttribute('hidden');
      }
    }
    form.querySelectorAll('[data-ship-method]').forEach(function(r){
      r.addEventListener('change', recompute);
    });
    recompute();

    // Submit
    var submitBtn = form.querySelector('[data-checkout-submit]');
    var errEl     = form.querySelector('[data-checkout-error]');
    function showError(msg){
      if (!errEl) { alert(msg); return; }
      errEl.textContent = msg;
      errEl.removeAttribute('hidden');
      errEl.scrollIntoView({behavior:'smooth', block:'center'});
    }
    function clearError(){
      if (errEl) { errEl.setAttribute('hidden',''); errEl.textContent = ''; }
    }

    submitBtn.addEventListener('click', async function(){
      clearError();
      var name  = (form.querySelector('#co-name').value  || '').trim();
      var email = (form.querySelector('#co-email').value || '').trim();
      var phone = (form.querySelector('#co-phone').value || '').trim();
      var notes = (form.querySelector('#co-notes').value || '').trim();
      var ship  = selectedShip();

      if (!name)  return showError(i18n.err_name  || 'Vyplňte prosím jméno.');
      if (!email || email.indexOf('@') < 0)
                  return showError(i18n.err_email || 'Vyplňte platný e-mail.');
      if (!phone) return showError(i18n.err_phone || 'Vyplňte telefon.');

      var shipAddr = null;
      if (ship !== 'pickup') {
        var street  = (form.querySelector('#co-street').value  || '').trim();
        var zip     = (form.querySelector('#co-zip').value     || '').trim();
        var city    = (form.querySelector('#co-city').value    || '').trim();
        var country = (form.querySelector('#co-country').value || 'CZ').trim();
        if (!street || !zip || !city) {
          return showError(i18n.err_address || 'Vyplňte prosím doručovací adresu.');
        }
        shipAddr = {street: street, zip: zip, city: city, country: country};
      }

      var rpcItems = items.map(function(it){
        return {product_id: it.product_id, size: it.size || null, qty: it.qty | 0};
      });

      if (!window.sb) {
        return showError(i18n.err_init || 'Aplikace se nepodařila inicializovat. Obnovte prosím stránku.');
      }

      submitBtn.disabled = true;
      var origLabel = submitBtn.textContent;
      submitBtn.textContent = i18n.processing || 'Vytvářím objednávku…';

      try {
        var rpc = await window.sb.rpc('create_web_shop_order', {
          p_items:           rpcItems,
          p_customer_name:   name,
          p_customer_email:  email,
          p_customer_phone:  phone,
          p_shipping_method: ship,
          p_shipping_address: shipAddr,
          p_payment_method:  'card',
          p_promo_code:      null,
          p_notes:           notes || null
        });
        if (rpc.error) throw new Error(rpc.error.message || 'RPC error');
        var data = rpc.data;
        if (!data || data.error) {
          var err = data && data.error;
          var errMsg = (i18n['err_' + err]) || (err ? ('Chyba: ' + err) : 'Objednávku se nepodařilo vytvořit.');
          throw new Error(errMsg);
        }
        var orderId = data.order_id;
        if (!orderId) throw new Error('Chybí order_id');

        // Po úspěšném vytvoření objednávky → Stripe Checkout
        // (process-payment edge fn ve Fázi 5 rozšíříme; dnes při neúspěchu
        // přesměrujeme rovnou na potvrzovací stránku)
        var redirectUrl = (window.MG_I18N && window.MG_I18N.cart_url ? window.MG_I18N.cart_url.replace('/kosik','') : '') + '/objednavka/dokoncit?order_id=' + encodeURIComponent(orderId);
        try {
          var subtotalNow = items.reduce(function(a, it){ return a + (Number(it.price)||0)*(Number(it.qty)||0); }, 0);
          var totalNow = subtotalNow + (SHIP_PRICES[ship] || 0);
          var resp = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey':        window.MOTOGO_CONFIG.SUPABASE_ANON_KEY,
              'Authorization': 'Bearer ' + window.MOTOGO_CONFIG.SUPABASE_ANON_KEY
            },
            body: JSON.stringify({
              type:    'shop',
              kind:    'products',
              source:  'web',
              order_id: orderId,
              amount:   totalNow,
              currency: 'czk',
              customer_email: email,
              customer_name:  name,
              customer_phone: phone,
              shipping_method: ship,
              shipping_address: shipAddr
            })
          });
          var json = await resp.json().catch(function(){ return null; });
          var checkoutUrl = json && (json.url || json.checkout_url);
          if (resp.ok && checkoutUrl) {
            // Vyčistit košík až těsně před navigací (kdyby Stripe selhal,
            // uživatel stále vidí svůj košík při návratu).
            window.MGCart.clear();
            window.location.href = checkoutUrl;
            return;
          }
          // Fallback — pokud edge fn ještě nepodporuje web_shop produkty,
          // přejdi rovnou na potvrzení; objednávka v DB existuje, admin se
          // s tím dohodne, košík vyčistíme.
          window.MGCart.clear();
          window.location.href = redirectUrl;
        } catch(e){
          window.MGCart.clear();
          window.location.href = redirectUrl;
        }
      } catch (e) {
        submitBtn.disabled = false;
        submitBtn.textContent = origLabel;
        showError(e.message || (i18n.err_generic || 'Něco se pokazilo, zkuste to prosím znovu.'));
      }
    });
  }

  // Počkat, až bude MGCart připravený. cart.js běží také přes `defer`, ale
  // protože je v layoutu pod obsahem (pozdější DOM order), spouští se až po
  // checkout.js. Bez tohohle waitu by MGCart.load() vrátil [] a stránka by
  // hlásila prázdný košík i když je naplněný.
  function waitForMGCart(cb, attemptsLeft){
    if (window.MGCart) return cb();
    if (attemptsLeft <= 0) return cb(); // bezpečný fallback (zobrazí empty)
    setTimeout(function(){ waitForMGCart(cb, attemptsLeft - 1); }, 50);
  }

  function bootstrap(){ waitForMGCart(init, 40); /* až 2 s */ }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootstrap);
  } else {
    bootstrap();
  }
})();
