// ===== TEMPLATES-SCREENS.JS – Home (s-home) & Search (s-search) =====
// Split from original templates-screens.js
// Booking flow templates (s-detail, s-booking, s-payment, s-success) → templates-screens-booking.js

Templates['s-home'] = `  <div class="hdr">
    <div style="display:flex;align-items:center;justify-content:space-between;">
      <div style="display:flex;align-items:center;gap:10px;">
        <img src="${IMG_BASE64_0}" style="width:36px;height:36px;border-radius:10px;object-fit:cover;background:var(--green);" alt="MotoGo24">
        <div>
          <div style="font-size:16px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div>
          <div id="t-rentalTagline" style="font-size:9px;font-weight:700;color:rgba(255,255,255,.45);letter-spacing:3px;text-transform:uppercase;margin-top:2px;">Půjčovna motorek</div>
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:8px;">
        <div id="online-dot" style="width:8px;height:8px;border-radius:50%;background:var(--green);" title="Online – synchronizováno"></div>
        <div class="h-av" onclick="goTo('s-profile')" title="Menu / Profil" style="width:40px;height:40px;border-radius:12px;background:rgba(116,251,113,.2);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;position:relative;z-index:60;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
      </div>
    </div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-top:8px;gap:10px;">
      <div style="flex-shrink:0;display:flex;align-items:center;gap:5px;background:rgba(116,251,113,.12);border-radius:8px;padding:7px 10px"><div style="font-size:9px;font-weight:700;color:rgba(255,255,255,.45);text-transform:uppercase;letter-spacing:.3px" id="t-pilot">Pilot:</div><div style="font-size:13px;font-weight:800;color:#fff" id="home-user-name"></div></div>
      <div class="h-search" onclick="goTo('s-search')" style="flex:1;padding:7px 10px;margin-top:0;">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
        <span id="t-whenRide">Kdy jedete?...</span>
      </div>
    </div>
  </div>
  <div class="sec-hdr" style="padding-top:14px;"><div class="sec-t" id="t-activeRes">Aktivní rezervace</div><div class="sec-l" id="t-viewAll" onclick="goTo('s-res')">Vše</div></div>
  <div id="home-active-res">
    <div class="ares" onclick="goTo('s-res')">
      <div style="font-size:24px;">🏍️</div>
      <div><div class="ares-n" id="home-ares-name">Načítání...</div><div class="ares-s" id="home-ares-sub">Ověřuji rezervace</div></div>
      <div class="ares-tag" id="home-ares-tag">–</div>
    </div>
  </div>
  <button class="sos-btn sos-btn-sm" onclick="goTo('s-sos')">
    <div class="sos-icon" style="width:28px;height:28px;border-radius:8px;font-size:14px;">🆘</div>
    <div style="text-align:left;"><div id="t-sosEmergency" style="font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.5px;">Nehoda, krádež, porucha</div><div id="t-sosHelp24" style="font-size:10px;opacity:.8;margin-top:1px;font-weight:500;">Okamžitá pomoc 24/7</div></div>
    <div style="margin-left:auto;font-size:16px;opacity:.7;">›</div>
  </button>
  <!-- ROZŠÍŘENÝ FILTR -->
  <div style="margin:14px 20px 0;background:#fff;border-radius:var(--r);box-shadow:var(--shadow);overflow:hidden;">
    <div style="padding:14px 16px;border-bottom:1px solid var(--g100);display:flex;align-items:center;justify-content:space-between;">
      <div id="t-filterTitle" style="font-size:14px;font-weight:800;color:var(--black);">🎛️ Filtr motorek</div>
      <button id="t-resetBtn" onclick="resetHomeFilters()" style="font-size:11px;font-weight:700;color:var(--g400);background:none;border:none;cursor:pointer;font-family:var(--font);">Resetovat</button>
    </div>
    <div style="padding:12px 16px 4px;">
      <!-- Kategorie -->
      <div id="t-catLabel" style="font-size:10px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.6px;margin-bottom:7px;">Kategorie</div>
      <div style="display:flex;gap:6px;flex-wrap:nowrap;margin-bottom:6px;">
        <div class="hf-chip on" id="hfc-all" onclick="setHF('cat','all',this)"><span id="t-hfAll">Vše</span></div>
        <div class="hf-chip" id="hfc-cestovni" onclick="setHF('cat','cestovni',this)"><span id="t-hfTouring">🧭 Cestovní/Enduro</span></div>
        <div class="hf-chip" id="hfc-detske" onclick="setHF('cat','detske',this)"><span id="t-hfKids">👶 Dětské</span></div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:nowrap;margin-bottom:14px;">
        <div class="hf-chip" id="hfc-sportovni" onclick="setHF('cat','sportovni',this)"><span id="t-hfSport">⚡ Sportovní</span></div>
        <div class="hf-chip" id="hfc-naked" onclick="setHF('cat','naked',this)"><span id="t-hfNaked">🔥 Naked</span></div>
        <div class="hf-chip" id="hfc-chopper" onclick="setHF('cat','chopper',this)"><span id="t-hfChopper">Chopper</span></div>
      </div>
      <!-- ŘP -->
      <div id="t-licGroup" style="font-size:10px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.6px;margin-bottom:7px;">Skupina ŘP</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:14px;">
        <div class="hf-chip on" id="hfr-all" onclick="setHF('rp','all',this)"><span id="t-hfAllGroups">Vše</span></div>
        <div class="hf-chip" id="hfr-A2" onclick="setHF('rp','A2',this)"><span id="t-hfA2">A2 (do 35 kW)</span></div>
        <div class="hf-chip" id="hfr-A" onclick="setHF('rp','A',this)"><span id="t-hfA">A (plný)</span></div>
        <div class="hf-chip" id="hfr-N" onclick="setHF('rp','N',this)"><span id="t-hfN">N (bez ŘP)</span></div>
      </div>
      <!-- Pobočka -->
      <div id="t-branchLabel" style="font-size:10px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.6px;margin-bottom:7px;">Pobočka</div>
      <select id="f-branch-home" onchange="applyHomeFilters()" style="width:100%;border:1.5px solid var(--g200);border-radius:var(--rsm);padding:9px 10px;font-size:12px;font-family:var(--font);background:var(--g100);outline:none;margin-bottom:14px;color:var(--black);font-weight:600;">
        <option value="">🏪 Všechny pobočky</option>
      </select>
      <!-- Výkon slider -->
      <div style="font-size:10px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.6px;margin-bottom:7px;"><span id="t-maxPower">Max. výkon</span>: <span id="hf-vykon-lbl" style="color:var(--gd);">vše</span></div>
      <input type="range" id="hf-vykon" min="5" max="120" value="120" step="5"
        style="width:100%;accent-color:var(--green);margin:0 0 12px;"
        oninput="setHFVykon(this.value)">
      <!-- Dostupnost + řazení -->
      <div style="display:flex;gap:8px;margin-bottom:12px;">
        <label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;color:var(--black);cursor:pointer;flex:1;">
          <input type="checkbox" id="hf-avail" style="accent-color:var(--green);" onchange="applyHomeFilters()">
          <span id="t-showAvail">Zobrazit dnes volné</span>
        </label>
        <select id="hf-sort" onchange="applyHomeFilters()" style="flex:1;border:1.5px solid var(--g200);border-radius:var(--rsm);padding:7px 8px;font-size:11px;font-family:var(--font);background:var(--g100);outline:none;">
          <option id="t-sortDefault" value="default">Řazení: výchozí</option>
          <option id="t-sortPriceUp" value="price-asc">Cena ↑</option>
          <option id="t-sortPriceDown" value="price-desc">Cena ↓</option>
          <option id="t-sortPowerDown" value="vykon-desc">Výkon ↓</option>
          <option id="t-sortAZ" value="name-asc">A–Z</option>
        </select>
      </div>
    </div>
    <div style="padding:0 16px 14px;">
      <div style="font-size:11px;color:var(--g400);font-weight:600;" id="hf-count-txt">Zobrazeno: 14 motorek</div>
    </div>
  </div>
  <div style="height:12px;"></div>
  <div class="mg-grid" id="home-motos"></div>
  <div style="height:10px;"></div>`;

Templates['s-search'] = `  <div class="search-hdr">
    <div style="display:flex;align-items:center;justify-content:space-between;">
      <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">\u2190</div><h2 id="t-searchTitle" style="font-size:16px;font-weight:900;color:#fff;margin:0;">Vyhled\u00e1v\u00e1n\u00ed</h2></div>
      <div class="h-av" onclick="goTo('s-profile')" title="Profil" style="width:34px;height:34px;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
    </div>
    <div class="date-row" style="margin-top:8px;">
      <div class="dbox focus" id="db-od">
        <div class="dbox-l" id="t-srchPickup">Vyzvednutí</div>
        <div class="dbox-v ph" id="dbv-od" onclick="openSearchDP('od')">Vyberte datum</div>
      </div>
      <div class="dbox" id="db-do">
        <div class="dbox-l" id="t-srchReturn">Vrácení</div>
        <div class="dbox-v ph" id="dbv-do" onclick="openSearchDP('do')">Vyberte datum</div>
      </div>
    </div>
  </div>
  <div class="cal-wrap">
    <div class="cal-head"><div class="sdot" id="cal-step-el">1</div><span id="cal-label-el">Vyberte datum vyzvednutí</span></div>
    <div id="t-calHint" style="font-size:11px;color:var(--g400);font-weight:500;margin-bottom:6px;text-align:center;">Pro výběr jednoho dne klikněte na stejný den dvakrát</div>
    <div class="cal-mr"><button class="cal-ar" onclick="prevMonth()">‹</button><div class="cal-mn" id="cal-month-name">Únor 2026</div><button class="cal-ar" onclick="nextMonth()">›</button></div>
    <div class="cal-hdr"><div class="cal-dn">Po</div><div class="cal-dn">Út</div><div class="cal-dn">St</div><div class="cal-dn">Čt</div><div class="cal-dn">Pá</div><div class="cal-dn">So</div><div class="cal-dn">Ne</div></div>
    <div class="cal-g" id="s-cal"></div>
    <div class="cal-leg">
      <div class="leg-i"><div class="leg-d" style="background:var(--green)"></div><span id="t-legFree">Volné</span></div>
      <div class="leg-i"><div class="leg-d" style="background:var(--dark)"></div><span id="t-legOcc">Obsazené</span></div>
      <div class="leg-i"><div class="leg-d" style="background:#fff;border:1px solid #d1d5db;"></div><span id="t-legUnconf">Nepotvrzené</span></div>
    </div>
  </div>
  <div class="fcard">
    <h3 id="t-filtersH">🎛️ Filtry</h3>
    <div class="frow" style="grid-template-columns:1fr;">
      <select class="fsel" id="f-branch" onchange="applyFilters()">
        <option id="t-allBranches" value="">🏪 Všechny pobočky</option>
        <option value="mezna">Mezná 9, 393 01 Mezná (aktuální)</option>
        <option value="brno" disabled>Brno – připravujeme</option>
        <option value="prague" disabled>Praha – připravujeme</option>
      </select>
    </div>
    <div class="frow" style="display:flex;gap:8px;">
      <select class="fsel" id="f-cat" style="flex:1;" onchange="applyFilters()"><option id="t-fCat" value="">Kategorie</option><option id="t-fKids" value="detske">Dětské</option><option id="t-fTouring" value="cestovni">Cestovní</option><option id="t-fSport" value="sportovni">Sportovní</option><option id="t-fNaked" value="naked">Naked</option><option id="t-fChopper" value="chopper">Chopper</option></select>
      <select class="fsel" id="f-vykon" style="flex:1;" onchange="applyFilters()"><option id="t-fPower" value="">Výkon</option><option id="t-fPow35" value="35">do 35 kW</option><option id="t-fPow60" value="60">do 60 kW</option><option id="t-fPow61" value="61">60+ kW</option></select>
    </div>
    <div class="frow" style="display:flex;gap:8px;align-items:center;">
      <select class="fsel" id="f-rp" style="flex:1;" onchange="applyFilters()"><option id="t-fRP" value="">ŘP skupina</option><option id="t-fRPA2" value="A2">A2 (do 35 kW)</option><option id="t-fRPA" value="A">A (plný)</option><option id="t-fRPN" value="N">N (bez ŘP)</option></select>
      <label class="fsel" style="flex:1;display:flex;align-items:center;gap:6px;cursor:pointer;"><input type="checkbox" id="f-avail-chk" style="accent-color:var(--green);" onchange="applyFilters()"> <span id="t-todayFree">Dnes volné</span></label>
    </div>
    <div id="t-usageLabel" style="font-size:11px;font-weight:700;color:var(--g600);margin-bottom:7px;text-transform:uppercase;letter-spacing:.5px;">Využití</div>
    <div class="fchips" id="fchips-wrap">
      <div class="fchip" data-vyuziti="silnice" onclick="toggleFchip(this)"><span id="t-uRoad">🛣️ Silnice</span></div>
      <div class="fchip" data-vyuziti="teren" onclick="toggleFchip(this)"><span id="t-uTerrain">🏔️ Lehký terén</span></div>
      <div class="fchip" data-vyuziti="dvou" onclick="toggleFchip(this)"><span id="t-uTwoUp">👫 Ve dvou</span></div>
      <div class="fchip" data-vyuziti="zacatecnici" onclick="toggleFchip(this)"><span id="t-uBeginners">🟢 Začátečníci</span></div>
      <div class="fchip" data-vyuziti="dlouhe-cesty" onclick="toggleFchip(this)"><span id="t-uLongTrips">🗺️ Dlouhé cesty</span></div>
    </div>
  </div>
  <div class="avail-drop" id="avail-drop" style="display:none;">
    <div class="avail-drop-hdr" onclick="toggleDrop()">
      <div class="avail-drop-title">🏍️ <span id="avail-count-txt">3 volné motorky</span></div>
      <span class="drop-arr" id="drop-arr">›</span>
    </div>
    <div class="avail-drop-body" id="drop-body"></div>
  </div>
  <div style="height:12px;"></div>`;
