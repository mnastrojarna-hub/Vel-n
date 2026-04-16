Templates['s-edit-res'] = `
  <div class="topbar">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">\u2190</div><div><h2 id="t-editTitle">Upravit rezervaci</h2><p id="edit-subtitle">Motorka \u00b7 #ID</p></div></div>
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
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="t-editToAddr1">\ud83d\udccd P\u0159istaven\u00ed na va\u0161i adresu</div><div style="font-size:11px;color:var(--g400);">1 000 K\u010d + 40 K\u010d/km</div></div>
        <div style="font-size:12px;font-weight:700;color:var(--red);">od 1 000 K\u010d</div>
      </label>
    </div>
    <div id="edit-pickup-detail" style="display:none;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;">
        <div class="ff" style="margin:0;position:relative;"><label>Obec / m\u011bsto</label><input type="text" id="edit-pickup-city" placeholder="nap\u0159. Humpolec, Hojanivice" oninput="showCitySuggestionsFor(this,'edit-pickup')" autocomplete="off"><div id="edit-pickup-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div class="ff" style="margin:0;"><label>PS\u010c</label><input type="text" id="edit-pickup-zip" placeholder="PS\u010c" maxlength="6"></div>
      </div>
      <div class="ff" style="margin:0;margin-top:8px;position:relative;"><label id="t-editDelAddr">Ulice a \u010d.p. / \u010d.o.</label><input type="text" id="edit-pickup-address" placeholder="nap\u0159. Vodi\u010dkova 36, Mezn\u00e1 9" oninput="showAddrSuggestions(this,'edit-pickup');if(typeof _sosCalcPickupDelivery==='function')_sosCalcPickupDelivery();" autocomplete="off"><div id="edit-pickup-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <div style="display:flex;gap:6px;margin-top:8px;">
        <button type="button" onclick="useMyLocation('edit-pickup')" style="flex:1;display:flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;background:var(--g100);border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:700;color:var(--gd);cursor:pointer;">\ud83d\udccd Poloha</button>
        <button type="button" onclick="openMapPicker('edit-pickup')" style="display:flex;align-items:center;justify-content:center;gap:4px;padding:10px 12px;background:var(--g100);border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:700;color:var(--gd);cursor:pointer;">\ud83d\uddfa\ufe0f Mapa</button>
      </div>
      <div id="edit-pickup-calc" style="display:none;margin-top:8px;background:var(--gp);border-radius:var(--rsm);padding:10px 12px;font-size:12px;color:var(--gd);">
        <span id="edit-pickup-km-txt">\ud83d\udccd Zadejte adresu</span>
      </div>
      <label id="edit-pickup-confirm-label" style="display:none;margin-top:8px;align-items:center;gap:8px;padding:9px 12px;background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);cursor:pointer;font-size:12px;font-weight:700;color:var(--gd);">
        <input type="checkbox" id="edit-pickup-addr-confirmed" style="accent-color:var(--green);width:16px;height:16px;" onchange="onAddrConfirmed('edit-pickup',this.checked)"> \u2705 Potvrdit adresu p\u0159istaven\u00ed
      </label>
    </div>
    <div style="margin-top:10px;border-top:1px solid var(--g200);padding-top:10px;">
      <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;margin-bottom:6px;" id="t-editDelTime">\ud83d\udd52 \u010cas p\u0159istaven\u00ed</div>
      <div id="edit-pickup-time-picker"></div>
    </div>
  </div>
`;
