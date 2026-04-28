// ===== MotoGo24 Web — E-shop cart (localStorage) =====
// Vanilla JS, žádné závislosti. Spravuje košík v localStorage pod klíčem
// "motogo_cart". Detail produktu, košík a checkout používají tyto helpery.
(function(){
  'use strict';
  var KEY = 'motogo_cart';
  var EVT = 'motogo:cart:changed';

  var Cart = {
    load: function(){
      try {
        var raw = localStorage.getItem(KEY);
        if (!raw) return [];
        var arr = JSON.parse(raw);
        if (!Array.isArray(arr)) return [];
        return arr.filter(function(it){
          return it && it.product_id && typeof it.qty === 'number' && it.qty > 0;
        });
      } catch (e) { return []; }
    },
    save: function(items){
      try { localStorage.setItem(KEY, JSON.stringify(items || [])); } catch(e){}
      try {
        document.dispatchEvent(new CustomEvent(EVT, {detail: {items: items || []}}));
      } catch(e){}
    },
    add: function(item){
      // item: {product_id, name, price, image, size, qty, stock}
      if (!item || !item.product_id) return;
      var qty = Math.max(1, parseInt(item.qty, 10) || 1);
      var size = item.size || null;
      var items = Cart.load();
      // Sloučit existující řádek (stejný product_id + size)
      var found = false;
      for (var i = 0; i < items.length; i++) {
        if (items[i].product_id === item.product_id && (items[i].size || null) === size) {
          var max = item.stock ? Math.min(item.stock, 99) : 99;
          items[i].qty = Math.min(items[i].qty + qty, max);
          found = true;
          break;
        }
      }
      if (!found) {
        items.push({
          product_id: item.product_id,
          name: item.name || '',
          price: Number(item.price) || 0,
          image: item.image || '',
          size: size,
          qty: qty,
          stock: item.stock || null,
          added_at: Date.now()
        });
      }
      Cart.save(items);
    },
    update: function(idx, qty){
      var items = Cart.load();
      if (!items[idx]) return;
      qty = Math.max(0, parseInt(qty, 10) || 0);
      if (qty === 0) {
        items.splice(idx, 1);
      } else {
        var max = items[idx].stock ? Math.min(items[idx].stock, 99) : 99;
        items[idx].qty = Math.min(qty, max);
      }
      Cart.save(items);
    },
    remove: function(idx){
      var items = Cart.load();
      items.splice(idx, 1);
      Cart.save(items);
    },
    clear: function(){ Cart.save([]); },
    count: function(){
      return Cart.load().reduce(function(a, it){ return a + (it.qty || 0); }, 0);
    },
    subtotal: function(){
      return Cart.load().reduce(function(a, it){
        return a + (Number(it.price) || 0) * (Number(it.qty) || 0);
      }, 0);
    },
    onChange: function(handler){
      document.addEventListener(EVT, handler);
      return function(){ document.removeEventListener(EVT, handler); };
    }
  };

  window.MGCart = Cart;

  // ----- Detail produktu: bind size/qty/add-to-cart -----
  function bindProductDetail(){
    var form = document.querySelector('[data-shop-form]');
    if (!form) return;

    var addBtn = form.querySelector('[data-shop-add]');
    if (!addBtn) return;

    // Size chips
    var sizeWrap = form.querySelector('[data-shop-sizes]');
    var sizeError = form.querySelector('[data-shop-size-error]');
    var selectedSize = null;
    if (sizeWrap) {
      sizeWrap.addEventListener('click', function(e){
        var chip = e.target.closest && e.target.closest('.shop-size-chip');
        if (!chip) return;
        sizeWrap.querySelectorAll('.shop-size-chip').forEach(function(c){
          c.classList.remove('active');
          c.setAttribute('aria-checked','false');
        });
        chip.classList.add('active');
        chip.setAttribute('aria-checked','true');
        selectedSize = chip.getAttribute('data-size');
        if (sizeError) sizeError.setAttribute('hidden','');
      });
    }

    // Qty stepper
    var qtyInput = form.querySelector('[data-shop-qty]');
    form.querySelectorAll('[data-qty-step]').forEach(function(btn){
      btn.addEventListener('click', function(){
        if (!qtyInput) return;
        var step = parseInt(btn.getAttribute('data-qty-step'), 10) || 0;
        var min = parseInt(qtyInput.min, 10) || 1;
        var max = parseInt(qtyInput.max, 10) || 99;
        var v = parseInt(qtyInput.value, 10) || 1;
        v = Math.max(min, Math.min(max, v + step));
        qtyInput.value = v;
      });
    });
    if (qtyInput) {
      qtyInput.addEventListener('change', function(){
        var min = parseInt(qtyInput.min, 10) || 1;
        var max = parseInt(qtyInput.max, 10) || 99;
        var v = parseInt(qtyInput.value, 10);
        if (!v || v < min) v = min;
        if (v > max) v = max;
        qtyInput.value = v;
      });
    }

    // Add to cart
    addBtn.addEventListener('click', function(){
      var hasSizes = addBtn.getAttribute('data-product-has-sizes') === '1';
      if (hasSizes && !selectedSize) {
        if (sizeError) sizeError.removeAttribute('hidden');
        if (sizeWrap) sizeWrap.scrollIntoView({behavior:'smooth', block:'center'});
        return;
      }
      var stock = parseInt(addBtn.getAttribute('data-product-stock'), 10) || null;
      var qty = qtyInput ? (parseInt(qtyInput.value, 10) || 1) : 1;
      Cart.add({
        product_id: addBtn.getAttribute('data-product-id'),
        name:       addBtn.getAttribute('data-product-name'),
        price:      Number(addBtn.getAttribute('data-product-price')) || 0,
        image:      addBtn.getAttribute('data-product-image'),
        size:       selectedSize,
        qty:        qty,
        stock:      stock
      });
      var fb = form.querySelector('[data-shop-feedback]');
      if (fb) {
        fb.textContent = (window.MG_I18N && window.MG_I18N.cart_added) || 'Přidáno do košíku';
        fb.removeAttribute('hidden');
        fb.classList.add('shop-cart-feedback-ok');
      }
      // Po krátké pauze přesměrovat na košík (klasický e-shop pattern)
      setTimeout(function(){
        var url = (window.MG_I18N && window.MG_I18N.cart_url) || '/kosik';
        window.location.href = url;
      }, 900);
    });
  }

  // ----- Cart page (/kosik) renderer -----
  function fmtPrice(amount){
    var v = Math.round(Number(amount) || 0);
    // 1 234 Kč — non-breaking space jako oddělovač tisíců
    var s = v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return s + ' Kč';
  }
  function escapeHtml(s){
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  function renderCartPage(){
    var loading = document.querySelector('[data-cart-loading]');
    var empty   = document.querySelector('[data-cart-empty]');
    var loaded  = document.querySelector('[data-cart-loaded]');
    var list    = document.querySelector('[data-cart-items]');
    if (!list && !empty) return; // ne košíková stránka
    if (loading) loading.setAttribute('hidden','');

    var items = Cart.load();
    if (items.length === 0) {
      if (empty)  empty.removeAttribute('hidden');
      if (loaded) loaded.setAttribute('hidden','');
      return;
    }
    if (empty)  empty.setAttribute('hidden','');
    if (loaded) loaded.removeAttribute('hidden');

    var i18n = window.MG_I18N || {};
    var rows = items.map(function(it, idx){
      var max = it.stock ? Math.min(it.stock, 99) : 99;
      var sizeLine = it.size ? '<p class="cart-item-size">' + escapeHtml(i18n.cart_size || 'Velikost') + ': <strong>' + escapeHtml(it.size) + '</strong></p>' : '';
      var img = it.image ? '<img src="' + escapeHtml(it.image) + '" alt="' + escapeHtml(it.name) + '" class="cart-item-img" loading="lazy">' : '<div class="cart-item-img cart-item-img-placeholder" aria-hidden="true"></div>';
      var line = (Number(it.price) || 0) * (Number(it.qty) || 0);
      return '<div class="cart-item" data-cart-row="' + idx + '">'
        + img
        + '<div class="cart-item-info">'
        +   '<h3 class="cart-item-name">' + escapeHtml(it.name) + '</h3>'
        +   sizeLine
        +   '<p class="cart-item-unit">' + fmtPrice(it.price) + ' / ' + escapeHtml(i18n.cart_pcs || 'ks') + '</p>'
        + '</div>'
        + '<div class="cart-item-qty">'
        +   '<label class="visually-hidden" for="cart-qty-' + idx + '">' + escapeHtml(i18n.cart_qty || 'Množství') + '</label>'
        +   '<div class="shop-qty-stepper">'
        +     '<button type="button" class="shop-qty-btn" data-cart-qty-step="-1" data-row="' + idx + '" aria-label="−">−</button>'
        +     '<input type="number" id="cart-qty-' + idx + '" class="shop-qty-input" data-cart-qty-input data-row="' + idx + '" value="' + (it.qty|0) + '" min="1" max="' + max + '" inputmode="numeric">'
        +     '<button type="button" class="shop-qty-btn" data-cart-qty-step="1" data-row="' + idx + '" aria-label="+">+</button>'
        +   '</div>'
        +   '<button type="button" class="cart-item-remove" data-cart-remove data-row="' + idx + '" aria-label="' + escapeHtml(i18n.cart_remove || 'Odebrat') + '" title="' + escapeHtml(i18n.cart_remove || 'Odebrat') + '">✕</button>'
        + '</div>'
        + '<div class="cart-item-line"><strong>' + fmtPrice(line) + '</strong></div>'
        + '</div>';
    }).join('');
    list.innerHTML = rows;

    var subtotal = Cart.subtotal();
    var sub = document.querySelector('[data-cart-subtotal]');
    var tot = document.querySelector('[data-cart-total]');
    if (sub) sub.textContent = fmtPrice(subtotal);
    if (tot) tot.textContent = fmtPrice(subtotal); // dopravu řeší checkout
  }

  function bindCartPage(){
    var list = document.querySelector('[data-cart-items]');
    if (!list && !document.querySelector('[data-cart-empty]')) return;

    document.addEventListener('click', function(e){
      var stepBtn = e.target.closest && e.target.closest('[data-cart-qty-step]');
      if (stepBtn) {
        var row = parseInt(stepBtn.getAttribute('data-row'), 10);
        var step = parseInt(stepBtn.getAttribute('data-qty-step') || stepBtn.getAttribute('data-cart-qty-step'), 10) || 0;
        var items = Cart.load();
        if (!items[row]) return;
        Cart.update(row, (items[row].qty || 0) + step);
        return;
      }
      var rmBtn = e.target.closest && e.target.closest('[data-cart-remove]');
      if (rmBtn) {
        var rrow = parseInt(rmBtn.getAttribute('data-row'), 10);
        Cart.remove(rrow);
        return;
      }
    });
    document.addEventListener('change', function(e){
      var input = e.target.closest && e.target.closest('[data-cart-qty-input]');
      if (!input) return;
      var rrow = parseInt(input.getAttribute('data-row'), 10);
      var v = parseInt(input.value, 10);
      if (!v || v < 1) v = 1;
      Cart.update(rrow, v);
    });

    Cart.onChange(renderCartPage);
    renderCartPage();
  }

  // ----- Topbar cart icon -----
  function bindCartBadge(){
    var badge = document.querySelector('[data-cart-badge]');
    if (!badge) return;
    function refresh(){
      var n = Cart.count();
      if (n > 0) {
        badge.textContent = n > 99 ? '99+' : String(n);
        badge.removeAttribute('hidden');
      } else {
        badge.setAttribute('hidden','');
        badge.textContent = '';
      }
    }
    refresh();
    Cart.onChange(refresh);
    // I cross-tab synchronization (storage event z jiného tabu)
    window.addEventListener('storage', function(e){
      if (e.key === KEY) refresh();
    });
  }

  function init(){
    bindProductDetail();
    bindCartBadge();
    bindCartPage();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
