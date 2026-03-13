// ===== TEMPLATES-BOOKING-FORM2.JS – Booking form steps 5-7, price, consents =====
// Continuation of templates-booking-form.js

var _BOOKING_FORM_PART2 = `
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">5</div> <span id="t-bkStep5">Vyzvednutí motorky</span></div>
    <div id="t-bkBranch" style="background:var(--g100);border-radius:var(--rsm);padding:10px 12px;margin-bottom:10px;font-size:12px;color:var(--g600);line-height:1.6;">
      🏪 Pobočka: <strong>Mezná 9, 393 01 Mezná</strong>
    </div>
    <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:10px;">
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;" id="pickup-store-label">
        <input type="radio" name="pickup" value="store" checked style="accent-color:var(--green);" onchange="setPickup('store')">
        <div style="flex:1;"><div id="t-bkPickupStore" style="font-size:13px;font-weight:700;">🏍️ Osobní vyzvednutí na pobočce</div><div id="t-bkPickupStoreNote" style="font-size:11px;color:var(--g400);">Mezná 9, 393 01 Mezná – ve vámi zvolenou dobu</div></div>
        <div id="t-bkFree1" style="font-size:12px;font-weight:700;color:var(--gd);">Zdarma</div>
      </label>
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--g100);border-radius:var(--rsm);border:2px solid var(--g200);cursor:pointer;" id="pickup-delivery-label">
        <input type="radio" name="pickup" value="delivery" style="accent-color:var(--green);" onchange="setPickup('delivery')">
        <div style="flex:1;"><div id="t-bkDelivery" style="font-size:13px;font-weight:700;">🚚 Přistavení na vaši adresu</div><div id="t-bkDeliveryNote" style="font-size:11px;color:var(--g400);">1 000 Kč + 20 Kč/km od provozovny (Mezná 9, 393 01 Mezná)</div></div>
        <div id="t-bkFromPrice1" style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 Kč</div>
      </label>
    </div>
    <div id="pickup-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="display:grid;grid-template-columns:1fr;gap:8px;">
        <div class="ff" style="margin:0;position:relative;"><label id="t-bkDelivAddr">Ulice a č.p.</label><input type="text" id="pickup-addr-input" placeholder="např. Vodičkova 36" oninput="calcDelivery('pickup');showAddrSuggestions(this,'pickup')" autocomplete="off"><div id="pickup-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      </div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:8px;">
        <div class="ff" style="margin:0;"><label>Město</label><input type="text" id="pickup-city" placeholder="Město"></div>
        <div class="ff" style="margin:0;"><label>PSČ</label><input type="text" id="pickup-zip" placeholder="PSČ" maxlength="6"></div>
      </div>
      <div id="pickup-price-calc" style="margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);display:none;">
        <span id="pickup-km-txt">📍 Zadejte adresu pro výpočet</span>
      </div>
    </div>
  </div>

  <div class="bcard">
    <div class="bcard-h"><div class="sdot">6</div> <span id="t-bkStep6">Vrácení motorky</span></div>
    <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:10px;">
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;" id="return-store-label">
        <input type="radio" name="return" value="store" checked style="accent-color:var(--green);" onchange="setReturn('store')">
        <div style="flex:1;"><div id="t-bkReturnStore" style="font-size:13px;font-weight:700;">🏍️ Vrácení na pobočce</div><div id="t-bkReturnStoreNote" style="font-size:11px;color:var(--g400);">Mezná 9, 393 01 Mezná – nejpozději do 24:00 posledního dne</div></div>
        <div id="t-bkFree2" style="font-size:12px;font-weight:700;color:var(--gd);">Zdarma</div>
      </label>
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--g100);border-radius:var(--rsm);border:2px solid var(--g200);cursor:pointer;" id="return-delivery-label">
        <input type="radio" name="return" value="other" style="accent-color:var(--green);" onchange="setReturn('other')">
        <div style="flex:1;"><div id="t-bkPickupFromHome" style="font-size:13px;font-weight:700;">📍 Odvoz z vaší adresy</div><div id="t-bkPickupNote" style="font-size:11px;color:var(--g400);">Uveďte čas vyzvednutí · 1 000 Kč + 20 Kč/km od provozovny</div></div>
        <div id="t-bkFromPrice2" style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 Kč</div>
      </label>
    </div>
    <div id="return-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="display:grid;grid-template-columns:1fr;gap:8px;">
        <div class="ff" style="margin:0;position:relative;"><label id="t-bkReturnAddr">Ulice a č.p.</label><input type="text" id="return-addr-input" placeholder="např. Vodičkova 36" oninput="calcDelivery('return');showAddrSuggestions(this,'return')" autocomplete="off"><div id="return-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      </div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:8px;">
        <div class="ff" style="margin:0;"><label>Město</label><input type="text" id="return-city" placeholder="Město"></div>
        <div class="ff" style="margin:0;"><label>PSČ</label><input type="text" id="return-zip" placeholder="PSČ" maxlength="6"></div>
      </div>
      <div class="ff" style="margin:0;margin-top:8px;"><label id="t-bkReturnTime">Čas vrácení</label>
        <div id="return-time-picker"></div>
      </div>
      <div id="return-price-calc" style="margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);display:none;">
        <span id="return-km-txt">📍 Zadejte adresu pro výpočet</span>
      </div>
    </div>
  </div>

  <div class="bcard">
    <div class="bcard-h"><div class="sdot">7</div> <span id="t-bkStep7">Výbava a doplňky</span></div>
    <div style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);margin-bottom:10px;">
      <div style="font-size:22px;flex-shrink:0;">🛡️</div>
      <div style="flex:1;"><div id="t-bkFreeBase" style="font-size:13px;font-weight:700;color:var(--gd);">Základní výbava zdarma</div><div id="t-bkFreeList" style="font-size:11px;color:var(--g400);margin-top:2px;">Helma, rukavice, bunda, kalhoty</div></div>
      <div id="t-bkFree3" style="font-size:13px;font-weight:800;color:var(--gd);white-space:nowrap;">Zdarma</div>
    </div>
    <div style="display:flex;flex-direction:column;gap:8px;">
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="extra-spolujezdec" data-price="400">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleExtra(this.closest('label'),400)">
        <div style="flex:1;"><div id="t-bkPassGear" style="font-size:13px;font-weight:700;">👥 Výbava spolujezdce</div><div id="t-bkPassGearDesc" style="font-size:11px;color:var(--g400);">Helma, rukavice, vesta</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);white-space:nowrap;">+400 Kč</div>
      </label>
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="extra-boty-ridic" data-price="300">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleExtra(this.closest('label'),300)">
        <div style="flex:1;"><div id="t-bkRiderBoots" style="font-size:13px;font-weight:700;">👢 Boty řidiče</div><div id="t-bkBootNote1" style="font-size:11px;color:var(--g400);">Moto boty – uveďte velikost v poznámce</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);white-space:nowrap;">+300 Kč</div>
      </label>
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="extra-boty-spolu" data-price="300">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleExtra(this.closest('label'),300)">
        <div style="flex:1;"><div id="t-bkPassBoots" style="font-size:13px;font-weight:700;">👟 Boty spolujezdce</div><div id="t-bkBootNote2" style="font-size:11px;color:var(--g400);">Moto boty – uveďte velikost v poznámce</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);white-space:nowrap;">+300 Kč</div>
      </label>
    </div>
  </div>

  <div class="bcard">
    <div class="bcard-h"><div class="sdot">💰</div> <span id="t-bkPriceSum">Shrnutí ceny</span></div>
    <div class="pr"><span id="pr-base-label">Motorka × 2 dny</span><span id="pr-base">5 200 Kč</span></div>
    <div class="pr" id="pr-delivery-row" style="display:none;"><span id="t-bkAltDelivery">Přistavení / vrácení jinde</span><span id="pr-delivery-amt">0 Kč</span></div>
    <div class="pr" id="pr-extras-row" style="display:none;"><span id="t-bkExtrasLine">Doplňky a výbava</span><span id="pr-extras-amt">0 Kč</span></div>
    <div class="pr" id="pr-discount-row" style="display:none;color:var(--gd);font-weight:700;"><span id="t-bkDiscountLine">🏷️ Slevový kód</span><span id="pr-discount-amt">-0 Kč</span></div>
    <div class="pr" style="color:var(--gd);font-weight:700;"><span id="t-bkNoDeposit">✓ Záloha se neúčtuje</span><span>0 Kč</span></div>
    <div class="pr total"><span id="t-bkTotalFinal">Celkem (cena konečná)</span><span class="amt" id="pr-total">5 400 Kč</span></div>
    <div style="margin-top:12px;border-top:1px solid var(--g100);padding-top:12px;">
      <div id="t-bkDiscountTitle" style="font-size:11px;font-weight:700;color:var(--g600);text-transform:uppercase;letter-spacing:.5px;margin-bottom:7px;">🏷️ Slevový kód</div>
      <div style="display:flex;gap:8px;">
        <input type="text" id="discount-input" placeholder="Zadejte kód (MOTO10, MOTO20...)" style="flex:1;border:2px solid var(--g200);border-radius:var(--rsm);padding:11px 12px;font-size:13px;font-family:var(--font);outline:none;background:var(--g100);-webkit-appearance:none;" oninput="this.style.borderColor='var(--g200)'">
        <button id="t-bkApplyBtn" onclick="applyDiscount()" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:11px 16px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;white-space:nowrap;flex-shrink:0;">Použít</button>
      </div>
      <div id="discount-msg" style="font-size:11px;margin-top:6px;font-weight:600;min-height:16px;"></div>
    </div>
  </div>
  <div class="bcard">
    <div style="display:flex;flex-direction:column;gap:8px;font-size:12px;color:var(--g600);font-weight:500;">
      <label id="t-bkAgreeVOP" style="display:flex;align-items:flex-start;gap:7px;cursor:pointer;"><input type="checkbox" id="consent-vop" style="accent-color:var(--green);width:14px;height:14px;flex-shrink:0;margin-top:1px;"> Souhlasím s <span onclick="event.stopPropagation();showContractPreview()" style="color:var(--gd);text-decoration:underline;cursor:pointer;">návrhem smlouvy</span> a <span onclick="event.stopPropagation();showVOP()" style="color:var(--gd);text-decoration:underline;cursor:pointer;">VOP</span> (vč. podmínek odpovědnosti za škodu)</label>
      <label id="t-bkAgreeGDPR" style="display:flex;align-items:flex-start;gap:7px;cursor:pointer;"><input type="checkbox" id="consent-gdpr" style="accent-color:var(--green);width:14px;height:14px;flex-shrink:0;margin-top:1px;"> Souhlasím se <span onclick="event.stopPropagation();showGDPR()" style="color:var(--gd);text-decoration:underline;cursor:pointer;">zpracováním osobních údajů</span></label>
      <div id="kids-consent-wrap" style="display:none;"><label id="t-bkAgreeKids" style="display:flex;align-items:flex-start;gap:7px;cursor:pointer;"><input type="checkbox" id="consent-kids" style="accent-color:var(--green);width:14px;height:14px;flex-shrink:0;margin-top:1px;"> Potvrzuji, že jsem zákonný zástupce a dětský motocykl bude provozován pouze v uzavřeném prostoru pod mým dohledem.</label></div>
    </div>
  </div>
  <div style="padding:12px 20px 100px;"><button id="t-bkProceed" class="btn-g" onclick="proceedToPayment()">Pokračovat k platbě →</button></div>`;
