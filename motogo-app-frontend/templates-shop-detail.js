// ===== TEMPLATES-SHOP-DETAIL.JS – Cart, Checkout, Merch Detail, Voucher =====

Templates['s-cart'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div>
    <h2 id="t-sdCartTitle">🛒 Košík</h2>
    <p id="t-sdCartSub">Souhrn objednávky</p>
  </div>
  <div id="cart-items-list" style="padding:12px 20px 0;"></div>
  <div style="padding:16px 20px;">
    <div style="background:var(--g100);border-radius:var(--r);padding:14px;margin-bottom:14px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span id="t-sdTotalDue" style="font-size:14px;font-weight:700;color:var(--dark);">Celkem k úhradě</span>
        <span style="font-size:20px;font-weight:900;color:var(--green);" id="cart-total-final">0 Kč</span>
      </div>
      <div id="t-sdPriceNote" style="font-size:11px;color:var(--g400);margin-top:4px;">Ceny jsou konečné – nejsme plátci DPH · Doručení poštou / osobní odběr na provozovně</div>
    </div>
    <button id="t-sdProceed" class="btn-g" onclick="checkoutMerch()">Pokračovat →</button>
  </div>`;

Templates['s-checkout'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l" id="t-sdBackCart">Zpět do košíku</div></div>
    <h2 id="t-sdPayTitle">💳 Platba</h2>
    <p id="t-sdLastStep">Posledni krok před odesláním</p>
  </div>
  <div style="padding:14px 20px 0;">
    <div class="bcard" style="margin:0 0 12px;padding:14px;">
      <div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">📦 Doručení</div>
      <div style="display:flex;gap:8px;margin-bottom:12px;">
        <div id="ship-post" onclick="selectShipping('post')" style="flex:1;border:2px solid var(--green);background:var(--gp);border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
          <div style="font-size:20px;">📮</div>
          <div style="font-size:12px;font-weight:700;margin-top:4px;">Doručení poštou</div>
          <div style="font-size:11px;color:var(--g400);">99 Kč · 2–4 dny</div>
        </div>
        <div id="ship-pickup" onclick="selectShipping('pickup')" style="flex:1;border:2px solid var(--g200);background:#fff;border-radius:var(--rsm);padding:10px;cursor:pointer;text-align:center;">
          <div style="font-size:20px;">🏪</div>
          <div style="font-size:12px;font-weight:700;margin-top:4px;">Osobní odběr</div>
          <div style="font-size:11px;color:var(--g400);">Zdarma · Mezná 9</div>
        </div>
      </div>
      <div id="ship-section-wrap" style="">
        <div onclick="toggleShipDetails()" style="display:flex;align-items:center;justify-content:space-between;cursor:pointer;padding:8px 0;border-top:1px solid var(--g100);margin-top:8px;">
          <div style="font-size:12px;font-weight:700;">\ud83d\udccb Doru\u010dovac\u00ed \u00fadaje <span id="ship-details-name" style="color:var(--g400);font-weight:500;"></span></div>
          <span id="ship-details-arrow" style="transition:transform .2s;">\u203a</span>
        </div>
        <div id="ship-address" style="display:none;">
          <div class="ff" style="margin-bottom:8px;"><label>Jm\u00e9no a p\u0159\u00edjmen\u00ed</label><input type="text" id="ship-name" placeholder="Jan Nov\u00e1k"></div>
          <div class="ff" style="margin-bottom:8px;position:relative;"><label>Ulice a \u010d\u00edslo popisn\u00e9</label><input type="text" id="ship-street" placeholder="P\u0159\u00edkladov\u00e1 123" oninput="showAddrSuggestions(this,'ship')" autocomplete="off"><div id="ship-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
          <div style="display:grid;grid-template-columns:1fr 2fr;gap:8px;">
            <div class="ff"><label>PS\u010c</label><input type="text" id="ship-zip" placeholder="393 01" maxlength="6" list="cz-zip-list"></div>
            <div class="ff" style="position:relative;"><label>M\u011bsto</label><input type="text" id="ship-city" placeholder="Pelh\u0159imov" oninput="showCitySuggestionsFor(this,'ship')" autocomplete="off"><div id="ship-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
          </div>
        </div>
      </div>
    </div>
    <div class="bcard" style="margin:0 0 12px;padding:14px;">
      <div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">💳 Způsob platby</div>
      <div id="pm-card-ch" onclick="selCheckoutP('card')" class="pm sel" style="margin-bottom:8px;">
        <div class="pmi" style="background:var(--green);">💳</div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;">Platební karta</div><div style="font-size:11px;color:var(--g400);">Visa · Mastercard</div></div>
        <div class="pmr on" id="pmr-card-ch"></div>
      </div>
      <div id="pm-apple-ch" onclick="selCheckoutP('apple')" class="pm" style="margin-bottom:0;">
        <div class="pmi">🍎</div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;">Apple Pay / Google Pay</div><div style="font-size:11px;color:var(--g400);">Rychlá platba</div></div>
        <div class="pmr" id="pmr-apple-ch"></div>
      </div>
    </div>
    <div class="bcard" style="margin:0 0 12px;padding:14px;">
      <div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">🏷️ Slevový kód / Dárkový poukaz</div>
      <div style="display:flex;gap:8px;align-items:center;">
        <input type="text" id="shop-discount-input" placeholder="Zadejte kód" style="flex:1;padding:10px 14px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;font-weight:600;text-transform:uppercase;" autocomplete="off">
        <button onclick="applyShopDiscount()" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:10px 16px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;white-space:nowrap;">Uplatnit</button>
      </div>
      <div id="shop-discount-msg" style="font-size:11px;margin-top:6px;min-height:16px;"></div>
      <div id="shop-discount-row" style="display:none;margin-top:8px;padding:8px 12px;background:var(--gp);border-radius:var(--rsm);">
        <div style="display:flex;justify-content:space-between;align-items:center;">
          <span style="font-size:12px;font-weight:600;color:var(--gd);" id="shop-discount-label"></span>
          <span style="font-size:13px;font-weight:800;color:var(--gd);" id="shop-discount-amt"></span>
        </div>
      </div>
    </div>
    <div style="background:var(--g100);border-radius:var(--r);padding:14px;margin-bottom:14px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span style="font-size:13px;font-weight:700;">Celkem</span>
        <span style="font-size:20px;font-weight:900;color:var(--green);" id="checkout-total">—</span>
      </div>
    </div>
    <button id="t-sdConfirmPay" class="btn-g" onclick="finalizeCheckout()">✅ Potvrdit a zaplatit →</button>
    <div style="height:30px;"></div>
  </div>`;

Templates['s-merch-detail'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět do shopu</div></div>
    <h2 id="md-title">Detail produktu</h2>
    <p>MotoGo24 Shop</p>
  </div>
  <div style="padding:14px 20px 100px;">
    <div id="md-images" style="display:flex;gap:10px;margin-bottom:14px;overflow-x:auto;scrollbar-width:none;">
    </div>
    <div style="font-size:18px;font-weight:900;color:var(--dark);margin-bottom:4px;" id="md-name"></div>
    <div style="font-size:22px;font-weight:900;color:var(--green);margin-bottom:10px;" id="md-price"></div>
    <div style="font-size:13px;color:var(--g600);line-height:1.7;margin-bottom:14px;" id="md-desc"></div>
    <div style="display:flex;gap:10px;margin-bottom:14px;">
      <div style="flex:1;background:var(--g100);border-radius:var(--rsm);padding:10px 12px;">
        <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;">Barva</div>
        <div style="font-size:13px;font-weight:700;color:var(--black);margin-top:3px;" id="md-color"></div>
      </div>
      <div style="flex:1;background:var(--g100);border-radius:var(--rsm);padding:10px 12px;">
        <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;">Materiál</div>
        <div style="font-size:13px;font-weight:700;color:var(--black);margin-top:3px;" id="md-material"></div>
      </div>
    </div>
    <div id="md-size-wrap" style="display:none;margin-bottom:14px;">
      <div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:8px;">Velikost</div>
      <div style="display:flex;gap:8px;" id="md-sizes">
        <button onclick="selectMerchSize('XS')" class="md-size-btn" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">XS</button>
        <button onclick="selectMerchSize('S')" class="md-size-btn" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">S</button>
        <button onclick="selectMerchSize('M')" class="md-size-btn" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">M</button>
        <button onclick="selectMerchSize('L')" class="md-size-btn" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">L</button>
        <button onclick="selectMerchSize('XL')" class="md-size-btn" style="flex:1;border:2px solid var(--g200);background:#fff;color:var(--black);border-radius:var(--rsm);padding:10px 4px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">XL</button>
      </div>
      <div id="md-size-msg" style="font-size:11px;color:var(--red);font-weight:600;margin-top:6px;display:none;"></div>
    </div>
    <button class="btn-g" id="md-add-btn" onclick="addMerchFromDetail()" style="position:sticky;bottom:14px;">🛒 Přidat do košíku</button>
  </div>`;
