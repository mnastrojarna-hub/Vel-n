// ===== TEMPLATES-SHOP.JS – Merch, Cart, Checkout, Voucher =====

// Merch items data for detail screen
var MERCH_ITEMS = {
  cap: {
    id: 'cap', name: 'Snapback čepice', price: 490,
    desc: 'Stylová snapback čepice s vyšitým logem MotoGo24. Nastavitelný pásek vzadu pro dokonalé padnutí. Kvalitní bavlněný materiál.',
    img: 'https://images.unsplash.com/photo-1588850561407-ed78c334e67a?w=800&q=80&auto=format&fit=crop',
    img2: 'https://images.unsplash.com/photo-1575428652377-a2d80e2277fc?w=800&q=80&auto=format&fit=crop',
    color: 'Černá', material: '100% bavlna', needsSize: false
  },
  tshirt: {
    id: 'tshirt', name: 'Tričko Classic', price: 590,
    desc: 'Klasické tričko s logem MotoGo24 na hrudi. Pohodlný střih, kvalitní 100% bavlna. Ideální na motorku i do města.',
    img: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=800&q=80&auto=format&fit=crop',
    img2: 'https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?w=800&q=80&auto=format&fit=crop',
    color: 'Černé', material: '100% bavlna · 180g/m²', needsSize: true
  },
  hoodie: {
    id: 'hoodie', name: 'Hoodie Premium', price: 990,
    desc: 'Prémiová mikina s kapucí a zipem. Fleece podšívka pro maximální pohodlí. Vyšité logo MotoGo24 na hrudi.',
    img: 'https://images.unsplash.com/photo-1556821840-3a63f95609a7?w=800&q=80&auto=format&fit=crop',
    img2: 'https://images.unsplash.com/photo-1578768079470-0a4536cc4e96?w=800&q=80&auto=format&fit=crop',
    color: 'Černá', material: '80% bavlna · 20% polyester · Fleece', needsSize: true
  },
  tshirt2: {
    id: 'tshirt2', name: 'Tričko Ride Hard', price: 690,
    desc: 'Prémiové tričko z limitované edice Ride Hard. Měkký materiál, moderní střih. Velký potisk MotoGo24 Ride Hard na zádech.',
    img: 'https://images.unsplash.com/photo-1503341504253-dff4f94032fc?w=800&q=80&auto=format&fit=crop',
    img2: 'https://images.unsplash.com/photo-1576566588028-4147f3842f27?w=800&q=80&auto=format&fit=crop',
    color: 'Zelené', material: '100% bavlna · Premium 200g/m²', needsSize: true
  }
};
var selectedMerchSize = null;
var currentMerchId = null;
Templates['s-merch'] = `  <div style="background:var(--dark);padding:50px 20px 20px;border-radius:0 0 28px 28px;position:relative;overflow:hidden;">
    <div class="h-av" onclick="goTo('s-profile')" title="Profil" style="position:absolute;right:20px;top:54px;width:36px;height:36px;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;z-index:20;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
    <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px;">
      <img src="${IMG_BASE64_0}" style="width:96px;height:96px;border-radius:22px;object-fit:cover;background:#000;" alt="MotoGo24">
      <div>
        <div style="font-size:24px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div>
        <div id="t-rental2" style="font-size:10px;font-weight:700;color:rgba(255,255,255,.45);letter-spacing:3px;text-transform:uppercase;margin-top:4px;">Půjčovna motorek</div>
      </div>
    </div>
    <h2 id="t-shopTitle" style="color:#fff;font-size:22px;font-weight:900;margin-bottom:4px;">MotoGo24 Shop</h2>
    <p id="t-merchTitle" style="color:rgba(255,255,255,.5);font-size:12px;font-weight:600;margin-bottom:16px;">Merch & dárkové poukazy</p>
  </div>

  <!-- DÁRKOVÝ POUKAZ – featured -->
  <div style="margin:16px 20px 0;">
    <div style="background:var(--dark);border-radius:var(--r);overflow:hidden;box-shadow:0 8px 32px rgba(0,0,0,.3);">
      <img src="${IMG_BASE64_1}" style="width:100%;display:block;" alt="Dárkový poukaz MotoGo24">
      <div style="padding:14px 16px 16px;">
        <div id="t-voucherTitle" style="font-size:16px;font-weight:900;color:#fff;margin-bottom:4px;">🎁 Dárkový poukaz</div>
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

  <!-- MERCH -->
  <div id="t-clothingTitle" style="margin:20px 20px 8px;font-size:13px;font-weight:800;color:var(--dark);text-transform:uppercase;letter-spacing:.5px;">👕 Oblečení a doplňky</div>
  <div style="padding:0 20px;display:grid;grid-template-columns:1fr 1fr;gap:12px;padding-bottom:100px;">

    <!-- Čepice -->
    <div style="background:#fff;border-radius:var(--r);overflow:hidden;box-shadow:var(--shadow);cursor:pointer;" onclick="openMerchItem('cap')">
      <div style="height:120px;background:linear-gradient(135deg,var(--dark) 0%,#1f2937 100%);overflow:hidden;"><img src="https://images.unsplash.com/photo-1588850561407-ed78c334e67a?w=400&q=80&auto=format&fit=crop" style="width:100%;height:100%;object-fit:cover;opacity:.85;"></div>
      <div style="padding:10px 12px 12px;">
        <div id="t-capName" style="font-size:13px;font-weight:800;color:var(--dark);">Snapback čepice</div>
        <div id="t-capSub" style="font-size:11px;color:var(--g400);margin-top:2px;">Černá · Logo MotoGo24</div>
        <div style="font-size:15px;font-weight:900;color:var(--green);margin-top:6px;">490 Kč</div>
        <button onclick="event.stopPropagation();openMerchItem('cap')" class="t-productDetail" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">Detail produktu</button>
      </div>
    </div>

    <!-- Tričko -->
    <div style="background:#fff;border-radius:var(--r);overflow:hidden;box-shadow:var(--shadow);cursor:pointer;" onclick="openMerchItem('tshirt')">
      <div style="height:120px;background:linear-gradient(135deg,var(--dark) 0%,#1f2937 100%);overflow:hidden;"><img src="https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400&q=80&auto=format&fit=crop" style="width:100%;height:100%;object-fit:cover;opacity:.85;"></div>
      <div style="padding:10px 12px 12px;">
        <div id="t-tshirtName" style="font-size:13px;font-weight:800;color:var(--dark);">Tričko Classic</div>
        <div style="font-size:11px;color:var(--g400);margin-top:2px;">Černé · 100% bavlna</div>
        <div style="font-size:15px;font-weight:900;color:var(--green);margin-top:6px;">590 Kč</div>
        <button onclick="event.stopPropagation();openMerchItem('tshirt')" class="t-productDetail" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">Detail produktu</button>
      </div>
    </div>

    <!-- Mikina -->
    <div style="background:#fff;border-radius:var(--r);overflow:hidden;box-shadow:var(--shadow);cursor:pointer;" onclick="openMerchItem('hoodie')">
      <div style="height:120px;background:linear-gradient(135deg,var(--dark) 0%,#1f2937 100%);overflow:hidden;"><img src="https://images.unsplash.com/photo-1556821840-3a63f95609a7?w=400&q=80&auto=format&fit=crop" style="width:100%;height:100%;object-fit:cover;opacity:.85;"></div>
      <div style="padding:10px 12px 12px;">
        <div id="t-hoodieName" style="font-size:13px;font-weight:800;color:var(--dark);">Hoodie Premium</div>
        <div style="font-size:11px;color:var(--g400);margin-top:2px;">Černá · Zip · Fleece</div>
        <div style="font-size:15px;font-weight:900;color:var(--green);margin-top:6px;">990 Kč</div>
        <button onclick="event.stopPropagation();openMerchItem('hoodie')" class="t-productDetail" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">Detail produktu</button>
      </div>
    </div>

    <!-- Tričko Ride -->
    <div style="background:#fff;border-radius:var(--r);overflow:hidden;box-shadow:var(--shadow);cursor:pointer;" onclick="openMerchItem('tshirt2')">
      <div style="height:120px;background:linear-gradient(135deg,#3dba3a 0%,#74FB71 100%);overflow:hidden;"><img src="https://images.unsplash.com/photo-1503341504253-dff4f94032fc?w=400&q=80&auto=format&fit=crop" style="width:100%;height:100%;object-fit:cover;opacity:.85;"></div>
      <div style="padding:10px 12px 12px;">
        <div id="t-tshirt2Name" style="font-size:13px;font-weight:800;color:var(--dark);">Tričko Ride Hard</div>
        <div style="font-size:11px;color:var(--g400);margin-top:2px;">Zelené · Premium</div>
        <div style="font-size:15px;font-weight:900;color:var(--green);margin-top:6px;">690 Kč</div>
        <button onclick="event.stopPropagation();openMerchItem('tshirt2')" class="t-productDetail" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">Detail produktu</button>
      </div>
    </div>

  </div>
`;

// Cart, Checkout, Merch Detail → templates-shop-detail.js

Templates['s-voucher'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div id="t-voucherBack" class="bk-l">Zpět</div></div>
    <h2 id="t-voucherTitle2">🎁 Dárkový poukaz</h2>
    <p id="t-perfectGift">Perfektní dárek pro každého motorkáře</p>
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
