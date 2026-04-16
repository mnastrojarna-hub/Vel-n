Templates['s-edit-res'] += `
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
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editFromAddr">\ud83d\udccd Odvoz z va\u0161\u00ed adresy</div><div style="font-size:11px;color:var(--g400);">1 000 K\u010d + 40 K\u010d/km</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 K\u010d</div>
      </label>
    </div>
    <div id="edit-return-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;">
        <div class="ff" style="margin:0;position:relative;"><label>Obec / m\u011bsto</label><input type="text" id="edit-return-city" placeholder="nap\u0159. Humpolec, Hojanivice" oninput="showCitySuggestionsFor(this,'edit-return')" autocomplete="off"><div id="edit-return-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div class="ff" style="margin:0;"><label>PS\u010c</label><input type="text" id="edit-return-zip" placeholder="PS\u010c" maxlength="6"></div>
      </div>
      <div class="ff" style="margin:0;margin-top:8px;position:relative;"><label id="t-editReturnAddr">Ulice a \u010d.p. / \u010d.o.</label><input type="text" id="edit-return-address" placeholder="nap\u0159. Vodi\u010dkova 36, Mezn\u00e1 9" oninput="calcEditDelivery();showAddrSuggestions(this,'edit-return')" autocomplete="off"><div id="edit-return-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <div style="display:flex;gap:6px;margin-top:8px;">
        <button type="button" onclick="useMyLocation('edit-return')" style="flex:1;display:flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;background:var(--g100);border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:700;color:var(--gd);cursor:pointer;">\ud83d\udccd Poloha</button>
        <button type="button" onclick="openMapPicker('edit-return')" style="display:flex;align-items:center;justify-content:center;gap:4px;padding:10px 12px;background:var(--g100);border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:700;color:var(--gd);cursor:pointer;">\ud83d\uddfa\ufe0f Mapa</button>
      </div>
      <div id="edit-return-calc" style="margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);display:none;">
        <span id="edit-return-km-txt">\ud83d\udccd Zadejte adresu</span>
      </div>
      <label id="edit-return-confirm-label" style="display:none;margin-top:8px;align-items:center;gap:8px;padding:9px 12px;background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);cursor:pointer;font-size:12px;font-weight:700;color:var(--gd);">
        <input type="checkbox" id="edit-return-addr-confirmed" style="accent-color:var(--green);width:16px;height:16px;" onchange="onAddrConfirmed('edit-return',this.checked)"> \u2705 Potvrdit adresu vr\u00e1cen\u00ed
      </label>
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

