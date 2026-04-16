// ===== TEMPLATES-SHOP.JS – Merch, Cart, Checkout, Voucher =====

// Dynamic product data loaded from Supabase (replaces old hardcoded MERCH_ITEMS)
var MERCH_ITEMS = {};
var _shopProductsLoaded = false;
var selectedMerchSize = null;
var currentMerchId = null;

// Load products from Supabase products table
function renderShopProducts() {
  var grid = document.getElementById('merch-products-grid');
  if (!grid) return;
  if (_shopProductsLoaded && Object.keys(MERCH_ITEMS).length > 0) {
    _renderProductGrid(grid); return;
  }
  grid.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;">Načítám produkty…</div>';
  if (typeof window.supabase === 'undefined' || !window.supabase) {
    grid.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;">Shop není dostupný offline</div>';
    return;
  }
  window.supabase.from('products').select('*').eq('is_active', true).order('sort_order', { ascending: true })
    .then(function(res) {
      MERCH_ITEMS = {};
      if (res.data && res.data.length > 0) {
        res.data.forEach(function(p) {
          var pid = p.sku ? p.sku.toLowerCase().replace(/[^a-z0-9]/g, '-') : p.id.substring(0, 8);
          MERCH_ITEMS[pid] = {
            id: pid, dbId: p.id, name: p.name, price: Number(p.price),
            desc: p.description || '', color: p.color || '',
            material: p.material || '',
            img: (p.images && p.images[0]) || '',
            img2: (p.images && p.images[1]) || (p.images && p.images[0]) || '',
            images: p.images || [],
            needsSize: p.sizes && p.sizes.length > 0,
            sizes: p.sizes || [],
            stock: p.stock_quantity || 0
          };
        });
      }
      _shopProductsLoaded = true;
      _renderProductGrid(grid);
    }).catch(function(e) {
      console.error('[renderShopProducts]', e);
      grid.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;">Chyba načítání produktů</div>';
    });
}

function _renderProductGrid(grid) {
  var keys = Object.keys(MERCH_ITEMS);
  if (keys.length === 0) {
    grid.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;">Žádné produkty</div>';
    return;
  }
  grid.innerHTML = keys.map(function(k) {
    var p = MERCH_ITEMS[k];
    var imgSrc = p.img || '';
    var stockLabel = p.stock <= 0 ? '<div style="font-size:10px;color:#dc2626;font-weight:700;margin-top:2px;">Vyprodáno</div>' : '';
    return '<div style="background:#fff;border-radius:var(--r);overflow:hidden;box-shadow:var(--shadow);cursor:pointer;'+(p.stock<=0?'opacity:.5;':'') +'" onclick="openMerchItem(\''+k+'\')">' +
      '<div style="height:120px;background:linear-gradient(135deg,var(--dark) 0%,#1f2937 100%);overflow:hidden;">' +
        (imgSrc ? '<img src="'+imgSrc+'?w=400&q=80&auto=format&fit=crop" style="width:100%;height:100%;object-fit:cover;opacity:.85;">' : '') +
      '</div>' +
      '<div style="padding:10px 12px 12px;">' +
        '<div style="font-size:13px;font-weight:800;color:var(--dark);">'+p.name+'</div>' +
        '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(p.color||'')+(p.material?' · '+p.material:'')+'</div>' +
        '<div style="font-size:15px;font-weight:900;color:var(--green);margin-top:6px;">'+p.price.toLocaleString('cs-CZ')+' Kč</div>' +
        stockLabel +
        '<button onclick="event.stopPropagation();openMerchItem(\''+k+'\')" class="t-productDetail" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">Detail produktu</button>' +
      '</div></div>';
  }).join('');
}
Templates['s-merch'] = `  <div style="background:var(--dark);padding:10px 20px 12px;border-radius:0 0 28px 28px;position:relative;overflow:hidden;">
    <div style="display:flex;align-items:center;gap:10px">
      <div class="bk-c" onclick="histBack()" style="flex-shrink:0">←</div>
      <div style="flex:1;"><h2 id="t-shopTitle" style="color:#fff;font-size:16px;font-weight:900;margin:0;">🛍️ MotoGo Shop</h2><p id="t-merchTitle" style="color:rgba(255,255,255,.5);font-size:12px;font-weight:600;margin:2px 0 0;">Oblečení, doplňky & vybavení</p></div>
      <div class="h-av" onclick="goTo('s-profile')" title="Profil" style="width:34px;height:34px;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
    </div>
  </div>

  <!-- DÁRKOVÝ POUKAZ – featured -->
  <div style="margin:16px 20px 0;">
    <div style="background:var(--dark);border-radius:var(--r);overflow:hidden;box-shadow:0 8px 32px rgba(0,0,0,.3);">
      <img src="${IMG_BASE64_1}" style="width:100%;display:block;" alt="Dárkový poukaz MotoGo24">
      <div style="padding:14px 16px 16px;">
        <div id="t-voucherTitle" style="font-size:22px;font-weight:900;color:#fff;margin-bottom:2px;letter-spacing:-.5px;">🎁 Dárkový poukaz</div>
        <div style="font-size:10px;font-weight:800;color:var(--green);letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">MOTO GO 24 · Dárková karta</div>
        <div id="t-voucherDesc" style="font-size:12px;color:rgba(255,255,255,.6);margin-bottom:10px;line-height:1.5;">Otevřená hodnota · Platnost 3 roky od zakoupení · Uplatnění online i na provozovně</div>
        <div style="display:flex;gap:8px;margin-bottom:10px;">
          <button onclick="selectVoucherAmt(500)" class="vamt-btn" id="vamt-500" style="flex:1;border:2px solid rgba(255,255,255,.2);background:transparent;color:#fff;border-radius:var(--rsm);padding:9px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">500 Kč</button>
          <button onclick="selectVoucherAmt(1000)" class="vamt-btn" id="vamt-1000" style="flex:1;border:2px solid rgba(255,255,255,.2);background:transparent;color:#fff;border-radius:var(--rsm);padding:9px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">1 000 Kč</button>
          <button onclick="selectVoucherAmt(2000)" class="vamt-btn" id="vamt-2000" style="flex:1;border:2px solid rgba(255,255,255,.2);background:transparent;color:#fff;border-radius:var(--rsm);padding:9px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">2 000 Kč</button>
          <button onclick="selectVoucherAmt(0)" class="vamt-btn" id="vamt-0" style="flex:1;border:2px solid var(--green);background:var(--green);color:#fff;border-radius:var(--rsm);padding:9px 4px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;"><span id="t-customBtn">Vlastní ✏️</span></button>
        </div>
        <div id="vamt-custom-wrap" style="display:block;margin-bottom:10px;">
          <input type="number" id="vamt-custom" placeholder="Zadejte částku v Kč..." style="width:100%;border:2px solid rgba(255,255,255,.2);border-radius:var(--rsm);padding:10px 12px;font-size:14px;font-family:var(--font);background:rgba(255,255,255,.08);color:#fff;outline:none;box-sizing:border-box;" oninput="customVoucherAmt(this.value)">
        </div>
        <div style="margin-bottom:12px;">
          <div id="t-voucherForm" style="font-size:11px;font-weight:700;color:rgba(255,255,255,.5);text-transform:uppercase;letter-spacing:.5px;margin-bottom:6px;">Forma poukazu</div>
          <div style="display:flex;gap:8px;">
            <div id="voucher-digital" onclick="selectVoucherType('digital')" style="flex:1;border:2px solid var(--green);background:rgba(116,251,113,.15);border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
              <div style="font-size:18px;">📧</div>
              <div id="t-digitalCode" style="font-size:12px;font-weight:700;color:#fff;margin-top:4px;">Digitální kód</div>
              <div id="t-freeEmail" style="font-size:10px;color:rgba(255,255,255,.5);">Zdarma · e-mailem</div>
            </div>
            <div id="voucher-printed" onclick="selectVoucherType('printed')" style="flex:1;border:2px solid rgba(255,255,255,.2);background:transparent;border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
              <div style="font-size:18px;">🎁</div>
              <div id="t-printedVoucher" style="font-size:12px;font-weight:700;color:#fff;margin-top:4px;">Tištěný poukaz</div>
              <div id="t-shippingFee" style="font-size:10px;color:rgba(255,255,255,.5);">+180 Kč doprava a balné</div>
            </div>
          </div>
        </div>
        <button onclick="buyVoucher()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(116,251,113,.4);"><span id="t-buyVoucherBtn">🎁 Koupit poukaz –</span> <span id="voucher-price-btn">Zadejte částku</span></button>
      </div>
    </div>
  </div>

  <!-- MERCH – dynamic from Supabase -->
  <div id="t-clothingTitle" style="margin:20px 20px 8px;font-size:13px;font-weight:800;color:var(--dark);text-transform:uppercase;letter-spacing:.5px;">👕 Oblečení a doplňky</div>
  <div id="merch-products-grid" style="padding:0 20px;display:grid;grid-template-columns:1fr 1fr;gap:12px;padding-bottom:100px;">
    <div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;grid-column:span 2;">Načítám produkty…</div>
  </div>
`;

// Cart, Checkout, Merch Detail → templates-shop-detail.js

Templates['s-voucher'] = `  <div class="topbar">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-voucherTitle2">🎁 Dárkový poukaz</h2></div></div>
  </div>
  <div style="padding:16px 20px;">
    <img src="${IMG_BASE64_1}" style="width:100%;border-radius:var(--r);box-shadow:var(--shadow);display:block;margin-bottom:16px;" alt="Dárkový poukaz">
    <div class="bcard" style="margin:0 0 12px;padding:14px;">
      <div id="t-voucherValue" style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">Hodnota poukazu</div>
      <div style="display:flex;gap:8px;margin-bottom:10px;">
        <button onclick="selectVoucherAmtV(500)" class="vamt-btn-v" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">500 Kč</button>
        <button onclick="selectVoucherAmtV(1000)" class="vamt-btn-v" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">1 000 Kč</button>
        <button onclick="selectVoucherAmtV(2000)" class="vamt-btn-v" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">2 000 Kč</button>
      </div>
      <input type="number" id="vamt-custom-v" placeholder="Nebo vlastní částka v Kč..." style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:14px;font-family:var(--font);background:var(--g100);color:var(--black);outline:none;box-sizing:border-box;margin-bottom:10px;" oninput="customVoucherAmtV(this.value)">
      <div id="t-voucherForm2" style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:6px;">Forma poukazu</div>
      <div style="display:flex;gap:8px;margin-bottom:10px;">
        <div id="vtype-digital-v" onclick="selectVoucherTypeV('digital')" style="flex:1;border:2px solid var(--green);background:var(--gp);border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
          <div style="font-size:18px;">📧</div>
          <div id="t-digitalCode2" style="font-size:12px;font-weight:700;margin-top:4px;">Digitální kód</div>
          <div id="t-freeEmail2" style="font-size:10px;color:var(--g400);">Zdarma · e-mailem</div>
        </div>
        <div id="vtype-printed-v" onclick="selectVoucherTypeV('printed')" style="flex:1;border:2px solid var(--g200);background:#fff;border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
          <div style="font-size:18px;">🎁</div>
          <div id="t-printedVoucher2" style="font-size:12px;font-weight:700;margin-top:4px;">Tištěný poukaz</div>
          <div id="t-shippingOnly" style="font-size:10px;color:var(--g400);">+180 Kč doprava</div>
        </div>
      </div>
    </div>
    <button class="btn-g" onclick="buyVoucher()">🎁 Koupit poukaz – <span id="voucher-price-btn-v">Zadejte částku</span></button>
    <div style="height:6px;"></div>
    <div class="bcard" style="margin:0;">
      <div class="bcard-h"><div class="sdot">ℹ</div> <span id="t-howVoucher">Jak funguje poukaz</span></div>
      <div style="font-size:13px;color:var(--g600);line-height:1.7;">
        <span id="t-howLine1">✅ Otevřená hodnota – Vy zvolíte částku</span><br>
        <span id="t-howLine2">🗓️ Platnost 3 roky od zakoupení</span><br>
        <span id="t-howLine3">📧 Poukaz dorazí e-mailem s unikátním kódem</span><br>
        <span id="t-howLine4">🏍️ Uplatnění při online rezervaci nebo na provozovně</span><br>
        <span id="t-howLine5">💚 Ideální jako narozeninový či vánoční dárek</span>
      </div>
    </div>
  </div>`;
