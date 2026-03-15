// ===== TEMPLATES-RES-EDIT.JS – Edit reservation (s-edit-res) & Done detail (s-done-detail) =====
Templates['s-edit-res'] = `
  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">\u2190</div><div class="bk-l">Zp\u011bt</div></div>
    <h2 id="t-editTitle">Upravit rezervaci</h2>
    <p id="edit-subtitle">Motorka \u00b7 #ID</p>
    <div id="edit-res-dates" style="margin-top:8px;font-size:13px;color:#fff;font-weight:800;background:var(--green);display:inline-block;padding:6px 14px;border-radius:10px;"></div>
    <div id="edit-res-duration" style="margin-top:6px;font-size:12px;color:rgba(255,255,255,.7);font-weight:600;"></div>
  </div>

  <div class="bcard">
    <div style="display:flex;gap:6px;margin-bottom:14px;">
      <button id="etab-prodlouzit" style="flex:1;padding:10px 0;border-radius:50px;font-family:var(--font);font-size:11px;font-weight:700;border:none;cursor:pointer;background:var(--green);color:#fff;" onclick="switchEditTab('prodlouzit')"><span id="t-editTabExtend">Prodloužit / Změna místa</span></button>
      <button id="etab-zkratit" style="flex:1;padding:10px 0;border-radius:50px;font-family:var(--font);font-size:11px;font-weight:700;border:none;cursor:pointer;background:transparent;color:var(--gd);" onclick="switchEditTab('zkratit')"><span id="t-editTabShorten">Zkrácení / Změna místa</span></button>
    </div>
    <div id="edit-cal-card">
      <div class="bcard-h"><div class="sdot">\ud83d\udcc5</div> <span id="t-editDateSec">Term\u00edn</span></div>
      <div style="display:flex;gap:10px;margin-bottom:12px;">
        <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);">
          <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;" id="t-editPickup">Vyzvednut\u00ed</div>
          <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="edit-od-txt">\u2014</div>
        </div>
        <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);">
          <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;" id="t-editReturn">Vr\u00e1cen\u00ed</div>
          <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="edit-do-txt">\u2014</div>
        </div>
      </div>
      <div id="edit-res-info-cal" style="background:var(--gp);border:2px solid rgba(116,251,113,.3);border-radius:var(--rsm);padding:10px 12px;margin-bottom:10px;">
        <div style="font-size:11px;font-weight:800;color:var(--gd);text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px;" id="t-editYourRes">Va\u0161e st\u00e1vaj\u00edc\u00ed rezervace</div>
        <div id="edit-cal-res-dates" style="font-size:14px;font-weight:800;color:var(--black);"></div>
        <div id="edit-cal-res-moto" style="font-size:12px;color:var(--g600);font-weight:600;margin-top:2px;"></div>
      </div>
      <div id="edit-cal-instruction" style="font-size:11px;color:var(--g400);font-weight:600;margin-bottom:10px;text-align:center;"></div>
      <div id="edit-shorten-dir-wrap" style="display:none;gap:8px;margin-bottom:12px;justify-content:center;">
        <button id="edit-dir-start" onclick="setShortenDir('start')" style="flex:1;max-width:160px;padding:8px 12px;font-size:12px;font-weight:700;border-radius:var(--rsm);border:2px solid var(--g200);background:var(--g100);color:var(--g600);cursor:pointer;">⬅ Zkrátit začátek</button>
        <button id="edit-dir-end" onclick="setShortenDir('end')" style="flex:1;max-width:160px;padding:8px 12px;font-size:12px;font-weight:700;border-radius:var(--rsm);border:2px solid var(--g200);background:var(--g100);color:var(--g600);cursor:pointer;">Zkrátit konec ➡</button>
      </div>
      <div style="font-size:11px;color:var(--g400);font-weight:500;margin-bottom:6px;text-align:center;" id="t-editCalHint">Vyberte směr zkrácení a poté klikněte na datum v kalendáři</div>
      <div class="cal-mr"><button class="cal-ar" onclick="prevMonthE()">\u2039</button><div class="cal-mn" id="e-month-name">B\u0159ezen 2026</div><button class="cal-ar" onclick="nextMonthE()">\u203a</button></div>
      <div class="cal-hdr"><div class="cal-dn">Po</div><div class="cal-dn">\u00dat</div><div class="cal-dn">St</div><div class="cal-dn">\u010ct</div><div class="cal-dn">P\u00e1</div><div class="cal-dn">So</div><div class="cal-dn">Ne</div></div>
      <div class="cal-g" id="e-cal"></div>
      <div class="cal-leg">
        <div class="leg-i"><div class="leg-d" style="background:var(--green)"></div><span id="t-editLegCurrent">St\u00e1vaj\u00edc\u00ed</span></div>
        <div class="leg-i" id="edit-leg-zkraceno" style="display:none;"><div class="leg-d" style="background:var(--red)"></div><span id="t-editLegShort">Zkr\u00e1ceno</span></div>
        <div class="leg-i"><div class="leg-d" style="background:var(--dark)"></div><span id="t-editLegOcc">Obsazen\u00e9</span></div>
        <div class="leg-i"><div class="leg-d" style="background:#fff;border:1px solid #d1d5db;"></div><span id="t-editLegUnconf">Nepotvrzen\u00e9</span></div>
      </div>
      <div id="edit-shorten-note" style="display:none;background:#fff5f5;border:2px solid #fca5a5;border-radius:var(--rsm);padding:10px 12px;margin-top:10px;font-size:12px;color:#b91c1c;font-weight:600;">
        \u26a0\ufe0f Storno podm\u00ednky: 7+ dn\u00ed = 100 % vr\u00e1cen\u00ed \u00b7 2\u20137 dn\u00ed = 50 % \u00b7 m\u00e9n\u011b ne\u017e 2 dny = bez vr\u00e1cen\u00ed.
      </div>
    </div>
  </div>

  <div class="bcard" id="edit-pickup-location-card" style="display:none;">
    <div class="bcard-h"><div class="sdot">\ud83d\udccd</div> <span id="t-editPickupDel">P\u0159istaven\u00ed motorky</span></div>
    <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:10px;">
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;" id="edit-pickup-store-label">
        <input type="radio" name="edit-pickup" value="store" checked style="accent-color:var(--green);" onchange="setEditPickup('store')">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editAtBranch1">\ud83c\udfcd\ufe0f Na pobo\u010dce</div><div style="font-size:11px;color:var(--g400);">Mezn\u00e1 9, 393 01 Mezn\u00e1</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--gd);">Zdarma</div>
      </label>
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--g100);border-radius:var(--rsm);border:2px solid var(--g200);cursor:pointer;" id="edit-pickup-delivery-label">
        <input type="radio" name="edit-pickup" value="other" style="accent-color:var(--green);" onchange="setEditPickup('other')">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editToAddr1">\ud83d\udccd P\u0159istaven\u00ed na va\u0161i adresu</div><div style="font-size:11px;color:var(--g400);">1 000 K\u010d + 20 K\u010d/km</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 K\u010d</div>
      </label>
    </div>
    <div id="edit-pickup-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div class="ff" style="margin:0;position:relative;"><label id="t-editDelAddr">Ulice a \u010d.p.</label><input type="text" id="edit-pickup-address" placeholder="nap\u0159. Vodi\u010dkova 36" oninput="showAddrSuggestions(this,'edit-pickup');if(typeof _sosCalcPickupDelivery==='function')_sosCalcPickupDelivery();" autocomplete="off"><div id="edit-pickup-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:8px;">
        <div class="ff" style="margin:0;position:relative;"><label>M\u011bsto</label><input type="text" id="edit-pickup-city" placeholder="M\u011bsto" oninput="showCitySuggestionsFor(this,'edit-pickup')" autocomplete="off"><div id="edit-pickup-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div class="ff" style="margin:0;"><label>PS\u010c</label><input type="text" id="edit-pickup-zip" placeholder="PS\u010c" maxlength="6"></div>
      </div>
      <div id="edit-pickup-calc" style="display:none;margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);">
        <span id="edit-pickup-km-txt">\ud83d\udccd Zadejte adresu</span>
      </div>
    </div>
    <div style="margin-top:10px;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;margin-bottom:6px;" id="t-editDelTime">\ud83d\udd52 \u010cas p\u0159istaven\u00ed</div>
      <div id="edit-pickup-time-picker"></div>
    </div>
  </div>

  <div class="bcard" id="edit-return-location-card">
    <div class="bcard-h"><div class="sdot">\ud83d\udccd</div> <span id="t-editReturnSec">Vr\u00e1cen\u00ed motorky</span></div>
    <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:10px;">
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;" id="edit-return-store-label">
        <input type="radio" name="edit-return" value="store" checked style="accent-color:var(--green);" onchange="setEditReturn('store')">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editAtBranch2">\ud83c\udfcd\ufe0f Na pobo\u010dce</div><div style="font-size:11px;color:var(--g400);">Mezn\u00e1 9, 393 01 Mezn\u00e1</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--gd);">Zdarma</div>
      </label>
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--g100);border-radius:var(--rsm);border:2px solid var(--g200);cursor:pointer;" id="edit-return-delivery-label">
        <input type="radio" name="edit-return" value="other" style="accent-color:var(--green);" onchange="setEditReturn('other')">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editFromAddr">\ud83d\udccd Odvoz z va\u0161\u00ed adresy</div><div style="font-size:11px;color:var(--g400);">1 000 K\u010d + 20 K\u010d/km</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 K\u010d</div>
      </label>
    </div>
    <div id="edit-return-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div class="ff" style="margin:0;position:relative;"><label id="t-editReturnAddr">Ulice a \u010d.p.</label><input type="text" id="edit-return-address" placeholder="nap\u0159. Vodi\u010dkova 36" oninput="calcEditDelivery();showAddrSuggestions(this,'edit-return')" autocomplete="off"><div id="edit-return-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:8px;">
        <div class="ff" style="margin:0;position:relative;"><label>M\u011bsto</label><input type="text" id="edit-return-city" placeholder="M\u011bsto" oninput="showCitySuggestionsFor(this,'edit-return')" autocomplete="off"><div id="edit-return-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div class="ff" style="margin:0;"><label>PS\u010c</label><input type="text" id="edit-return-zip" placeholder="PS\u010c" maxlength="6"></div>
      </div>
      <div id="edit-return-calc" style="margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);display:none;">
        <span id="edit-return-km-txt">\ud83d\udccd Zadejte adresu</span>
      </div>
    </div>
    <div style="margin-top:10px;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;margin-bottom:6px;" id="t-editReturnTime">\ud83d\udd52 \u010cas vr\u00e1cen\u00ed</div>
      <div id="edit-return-time-picker"></div>
    </div>
  </div>

  <div class="bcard" id="edit-branch-card" style="display:none;">
    <div class="bcard-h"><div class="sdot">🏢</div> <span id="t-editBranch">Změna pobočky</span></div>
    <div style="display:flex;flex-direction:column;gap:8px;">
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;" id="edit-branch-mezna-label">
        <input type="radio" name="edit-branch" value="mezna" checked style="accent-color:var(--green);" onchange="setEditBranch('mezna')">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;">🏍️ Mezná</div><div style="font-size:11px;color:var(--g400);">Mezná 9, 393 01 Mezná</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--gd);" id="t-editActive">Aktivní</div>
      </label>
      <label style="display:flex;align-items:center;gap:9px;padding:11px;background:var(--g100);border-radius:var(--rsm);border:2px solid var(--g200);cursor:not-allowed;opacity:.5;">
        <input type="radio" name="edit-branch" value="praha" disabled style="accent-color:var(--green);">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;">🏙️ Praha</div><div style="font-size:11px;color:var(--g400);" id="t-editSoon">Připravujeme</div></div>
        <div style="font-size:11px;font-weight:700;color:var(--g400);" id="t-editSoonLabel">Již brzy</div>
      </label>
    </div>
  </div>

  <div class="bcard" id="edit-moto-change-card" style="display:none;">
    <div class="bcard-h"><div class="sdot">🏍️</div> <span id="t-editMotoChange">Změna motorky</span></div>
    <div id="edit-moto-current" style="background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);padding:10px 12px;margin-bottom:10px;">
      <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;" id="t-editCurrentMoto">Aktuální motorka</div>
      <div style="font-size:14px;font-weight:800;color:var(--gd);margin-top:3px;" id="edit-moto-current-name">—</div>
      <div style="font-size:12px;color:var(--g600);font-weight:600;" id="edit-moto-current-price">—</div>
    </div>
    <div style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;margin-bottom:8px;" id="t-editSelectNew">Vyberte novou motorku</div>
    <div id="edit-moto-list" style="display:flex;flex-direction:column;gap:6px;max-height:260px;overflow-y:auto;"></div>
    <div id="edit-moto-diff" style="display:none;background:#fffbeb;border:2px solid #fbbf24;border-radius:var(--rsm);padding:10px 12px;margin-top:10px;font-size:12px;font-weight:700;color:#92400e;"></div>
  </div>

  <div class="bcard" id="edit-extras-card" style="display:none;">
    <div class="bcard-h"><div class="sdot">\ud83c\udf92</div> <span id="t-editExtras">Dopl\u0148ky</span></div>
    <div style="display:flex;flex-direction:column;gap:8px;">
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="edit-extra-spolu" data-price="400">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleEditExtra(this.closest('label'),400)">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editPassGear">\ud83d\udc65 V\u00fdbava spolujezdce</div><div style="font-size:11px;color:var(--g400);">Helma, rukavice, vesta</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);">+400 K\u010d</div>
      </label>
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="edit-extra-boty" data-price="300">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleEditExtra(this.closest('label'),300)">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editRiderBoots">\ud83d\udc62 Boty \u0159idi\u010de</div><div style="font-size:11px;color:var(--g400);">Uve\u010fte velikost</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);">+300 K\u010d</div>
      </label>
      <label style="display:flex;align-items:center;gap:10px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;border:2px solid var(--g200);" id="edit-extra-boty-spolu" data-price="300">
        <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;flex-shrink:0;" onchange="toggleEditExtra(this.closest('label'),300)">
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editPassBoots">\ud83d\udc62 Boty spolujezdce</div><div style="font-size:11px;color:var(--g400);">Uve\u010fte velikost</div></div>
        <div style="font-size:13px;font-weight:800;color:var(--red);">+300 K\u010d</div>
      </label>
    </div>
  </div>

  <div class="bcard" id="edit-price-summary" style="display:none;">
    <div class="bcard-h"><div class="sdot">\ud83d\udcb0</div> <span id="t-editPriceChg">Zm\u011bna ceny</span></div>
    <div class="pr"><span id="t-editOrigPrice">P\u016fvodn\u00ed cena</span><span id="edit-orig-price">0 K\u010d</span></div>
    <div class="pr" id="edit-extend-row" style="display:none;"><span id="t-editExtension">Prodlou\u017een\u00ed</span><span id="edit-extend-price" style="color:var(--red);">+0 K\u010d</span></div>
    <div class="pr" id="edit-shorten-row" style="display:none;"><span id="t-editShortening">Zkr\u00e1cen\u00ed (vr\u00e1cen\u00ed)</span><span id="edit-refund-amt" style="color:var(--gd);">-0 K\u010d</span></div>
    <div class="pr" id="edit-return-fee-row" style="display:none;"><span id="t-editReturnFee">Odvoz na vlastn\u00ed adresu</span><span id="edit-return-fee" style="color:var(--red);">+0 K\u010d</span></div>
    <div class="pr" id="edit-return-diff-row" style="display:none;"><span id="t-editReturnDiff">Rozd\u00edl odvozu (nov\u00e9 m\u00edsto)</span><span id="edit-return-diff" style="color:var(--red);">+0 K\u010d</span></div>
    <div class="pr" id="edit-moto-diff-row" style="display:none;"><span id="t-editMotoDiff">Zm\u011bna motorky</span><span id="edit-moto-diff-price" style="color:var(--red);">+0 K\u010d</span></div>
    <div class="pr" id="edit-extras-fee-row" style="display:none;"><span id="t-editExtrasLine">Dopl\u0148ky</span><span id="edit-extras-fee" style="color:var(--red);">+0 K\u010d</span></div>
    <div class="pr total"><span id="t-editPayRefund">K doplatku / vr\u00e1cen\u00ed</span><span class="amt" id="edit-diff-total">0 K\u010d</span></div>
  </div>

  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="edit-save-btn" onclick="saveEditReservation()"><span id="t-editSaveBtn">Ulo\u017eit zm\u011bny \u2192</span></button>
  </div>
  <div style="height:80px;"></div>`;

Templates['s-done-detail'] = `  <div class="done-hdr">
    <div class="back-row" onclick="histBack()"><div class="bk-c" >←</div><div class="bk-l" id="t-doneBack">Zpět na rezervace</div></div>
    <h2 id="t-doneTitle">Detail proběhlé jízdy</h2>
    <p id="done-sub">#RES-2025-0018</p>
  </div>
  <div class="rd-card" style="margin-top:10px;">
    <img id="done-img" class="rd-moto-img" src="https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=80" alt="">
    <div class="rd-section-t" id="t-doneHistory">Průběh výpůjčky</div>
    <div class="rd-row"><div class="rd-label" id="t-doneMoto">Motorka</div><div class="rd-value" id="done-moto">Benelli TRK 702X</div></div>
    <div class="rd-row"><div class="rd-label" id="t-donePickup">Vyzvednutí</div><div class="rd-value">10. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneReturn">Vrácení</div><div class="rd-value">14. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneDuration">Délka výpůjčky</div><div class="rd-value">4 dny</div></div>
    <div class="rd-row"><div class="rd-label" id="t-donePickupPlace">Místo vyzvednutí</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneReturnPlace">Místo vrácení</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneTotalPrice">Celková cena</div><div class="rd-value" style="color:var(--gd);font-weight:900;">10 600 Kč</div></div>
  </div>
  <div class="rd-card">
    <div class="rd-section-t" id="t-doneDocs">📄 Doklady ke stažení</div>
    <div class="doc-dl-row" onclick="showT('⬇️','Stahování...','Zálohová faktura.pdf')">
      <div class="doc-dl-icon">🧾</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneAdvInv">Zálohová faktura</div><div class="doc-dl-sub">PDF · 45 kB</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
    <div class="doc-dl-row" onclick="showDigitalProtocol()">
      <div class="doc-dl-icon">📋</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneProtocol">Předávací protokol</div><div class="doc-dl-sub" id="t-doneDigital">Digitální · zobrazit a podepsat</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
    <div class="doc-dl-row" onclick="showT('⬇️','Stahování...','Konečná faktura.pdf')">
      <div class="doc-dl-icon">💰</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneFinalInv">Konečná faktura</div><div class="doc-dl-sub">PDF · 52 kB</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
  </div>
  <div class="rd-card" id="done-rating-card">
    <div class="rd-section-t" id="t-doneRating">⭐ Vaše hodnocení</div>
    <div id="done-stars-wrap" style="display:flex;justify-content:center;gap:8px;padding:10px 0;">
      <span class="star-btn" data-v="1" onclick="rateRide(1)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="2" onclick="rateRide(2)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="3" onclick="rateRide(3)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="4" onclick="rateRide(4)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="5" onclick="rateRide(5)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
    </div>
    <div id="done-rating-msg" style="text-align:center;font-size:12px;color:var(--g400);font-weight:600;padding-bottom:4px;"><span id="t-doneTapRate">Klepněte na hvězdičku pro hodnocení</span></div>
  </div>
  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="t-doneBookAgain" onclick="openDetail('benelli');goTo('s-detail');showT('🏍️','Rezervace','Vyberte termín pro stejnou motorku')">🔁 Znovu rezervovat</button>
  </div>
  <div style="height:10px;"></div>`;
