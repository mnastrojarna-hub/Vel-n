// ===== TEMPLATES-RES-SOS3.JS – Handover protocol (s-protocol) =====
Templates['s-protocol'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div>
    <h2 id="t-protoTitle">📋 Předávací protokol</h2>
    <p id="t-protoSub">Přečtěte a potvrďte digitálním podpisem</p>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">1</div> <span id="t-protoIdent">Identifikace</span></div>
    <div class="rd-row"><div class="rd-label" id="t-protoLessor">Pronajímatel</div><div class="rd-value">MotoGo24, Bc. Petra Semorádová</div></div>
    <div class="rd-row"><div class="rd-label" id="t-protoLessee">Nájemce</div><div class="rd-value" id="proto-najemce"></div></div>
    <div class="rd-row"><div class="rd-label" id="t-protoContract">Číslo smlouvy</div><div class="rd-value" id="proto-smlouva">#RES-2026-0043</div></div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">2</div> <span id="t-protoMoto">Motocykl</span></div>
    <div class="rd-row"><div class="rd-label" id="t-protoBrand">Značka / Model</div><div class="rd-value" id="proto-moto">BMW R 1200 GS Adventure</div></div>
    <div class="rd-row"><div class="rd-label">VIN</div><div class="rd-value" id="proto-vin">WB1063504LZA21485</div></div>
    <div class="rd-row"><div class="rd-label" id="t-protoOdo">Tachometr při předání</div><div class="rd-value"><input type="text" id="proto-tacho" placeholder="km" style="border:1.5px solid var(--g200);border-radius:8px;padding:6px 10px;font-size:13px;font-family:var(--font);width:100px;"></div></div>
    <div class="rd-row"><div class="rd-label" id="t-protoFuel">Stav paliva</div><div class="rd-value">
      <select id="proto-palivo" style="border:1.5px solid var(--g200);border-radius:8px;padding:6px 10px;font-size:13px;font-family:var(--font);">
        <option id="t-fuelFull">Plná nádrž</option><option>3/4</option><option>1/2</option><option>1/4</option>
      </select>
    </div></div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">3</div> <span id="t-protoEquip">Výbava a příslušenství</span></div>
    <div id="t-protoCheckAll" style="font-size:11px;color:var(--g400);font-weight:600;margin-bottom:10px;">Zaškrtněte vše co bylo předáno:</div>
    <div style="display:flex;flex-direction:column;gap:7px;">
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Klíče (od motorky + od kufru)</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Zelená karta (mezinárodní pojištění)</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Malý technický průkaz</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> 2× reflexní vesta</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Motolékárnička</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Záznam o dopravní nehodě s propiskou</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Kukla (nová – zůstává nájemci)</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Helma řidiče</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Rukavice</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Bunda</label>
      <label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer;"><input type="checkbox" class="proto-item" style="accent-color:var(--green);width:15px;height:15px;"> Kalhoty</label>
      <div class="ff" style="margin-top:6px;"><label>Ostatní příslušenství (poznámka)</label><input type="text" id="proto-other" placeholder="kufry, GPS, boty..."></div>
    </div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">4</div> <span id="t-protoCondition">Potvrzení stavu</span></div>
    <div class="ff"><label id="t-protoDamageLabel">Existující poškození při předání (pokud žádné, nechte prázdné)</label><textarea id="proto-damage" rows="3" placeholder="Popis stávajících škrábanců, poškození..." style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:13px;font-family:var(--font);outline:none;resize:none;"></textarea></div>
    <div style="background:var(--g100);border-radius:var(--rsm);padding:12px;margin-top:10px;font-size:12px;color:var(--g600);font-weight:500;line-height:1.6;">
      <span id="t-protoCondText">Nájemce potvrzuje, že se s Předávacím protokolem seznámil, souhlasí s jeho obsahem a přebírá motocykl ve výše uvedeném stavu. Fotodokumentace pořízená při předání je rozhodující pro posouzení stavu motorky.</span>
    </div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">5</div> <span id="t-protoSign">Digitální podpis</span></div>
    <p id="t-protoSignInstr" style="font-size:12px;color:var(--g400);margin-bottom:12px;">Potvrďte svou totožnost pro digitální podpis protokolu:</p>
    <div style="display:flex;gap:8px;margin-bottom:10px;">
      <button onclick="signProtocol('biometric')" style="flex:1;background:var(--dark);color:#fff;border:none;border-radius:var(--r);padding:14px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;">
        🔐 Face / Touch ID
      </button>
      <button onclick="signProtocol('pin')" style="flex:1;background:var(--green);color:#fff;border:none;border-radius:var(--r);padding:14px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;">
        🔢 PIN kód
      </button>
    </div>
    <div id="pin-input-wrap" style="display:none;margin-top:8px;">
      <div class="ff"><label>Zadejte váš PIN (heslo z profilu)</label>
        <input type="password" id="proto-pin" placeholder="••••" maxlength="6" style="letter-spacing:4px;font-size:18px;">
      </div>
      <button id="t-protoConfirmSign" onclick="confirmPin()" style="width:100%;margin-top:8px;background:var(--green);color:#fff;border:none;border-radius:50px;padding:13px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">Potvrdit podpis</button>
    </div>
    <div id="proto-signed" style="display:none;background:#dcfce7;border-radius:var(--rsm);padding:14px;text-align:center;">
      <div style="font-size:24px;">✅</div>
      <div id="t-protoSigned" style="font-size:14px;font-weight:800;color:#15803d;margin-top:4px;">Protokol podepsán</div>
      <div style="font-size:11px;color:#166534;margin-top:3px;" id="proto-signed-time"></div>
    </div>
  </div>
  <div style="padding:0 20px 28px;">
    <button id="t-protoSubmit" class="btn-g" onclick="submitProtocol()">📤 Odeslat protokol MotoGo24</button>
  </div>`;

