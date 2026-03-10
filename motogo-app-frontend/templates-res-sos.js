// ===== TEMPLATES-RES-SOS.JS – SOS core screens (s-sos, s-sos-nehoda, s-sos-nepojizda) =====
// s-contracts template moved to templates-done.js (dynamic renderContractsPage)

Templates['s-sos'] = `  <div class="sos-hdr">
    <div class="back-row" onclick="histBack()" style="margin-bottom:10px;"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div>
    <h2 id="t-sosTitle">🆘 Pomoc na cestě</h2><p id="t-sosSub">Co se stalo? Vybereme nejlepší pomoc.</p>
  </div>
  <div style="padding:14px 20px 0;">
    <div class="sos-option" onclick="goTo('s-sos-nehoda')" style="border-color:#fca5a5;">
      <div class="sos-option-icon" style="background:#fee2e2;">💥</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-sosTheft">Krádež, nehoda</div>
        <div class="sos-option-sub" id="t-sosTheftDesc">Havárie, kolize, odcizení – potřebuji pomoc</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="goTo('s-sos-porucha')" style="border-color:#fde68a;">
      <div class="sos-option-icon" style="background:#fef3c7;">🔧</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-sosBreakdown">Porucha motorky</div>
        <div class="sos-option-sub" id="t-sosBreakdownDesc">Technická závada – AI asistent & asistence</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="sosShareLocation()" style="border-color:var(--g200);">
      <div class="sos-option-icon" style="background:var(--gp);">📍</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-sosShareLoc">Sdílet polohu</div>
        <div class="sos-option-sub" id="t-sosShareLocDesc">Odeslat GPS souřadnice MotoGo24</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div style="margin-top:16px;background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);">
      <div id="t-sosDirectContact" style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px;">Přímý kontakt</div>
      <a href="tel:+420774256271" style="display:flex;align-items:center;gap:12px;text-decoration:none;">
        <div style="width:44px;height:44px;background:var(--green);border-radius:14px;display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0;">📞</div>
        <div><div style="font-size:15px;font-weight:800;color:var(--black);">+420 774 256 271</div><div id="t-sosSupportLine" style="font-size:12px;color:var(--g400);margin-top:2px;">MotoGo24 asistenční linka 24/7</div></div>
      </a>
    </div>
  </div>`;

Templates['s-sos-nehoda'] = `  <div class="sos-sub-hdr">
    <div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">←</div><div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zpět</div></div>
    <div style="font-size:28px;margin-bottom:8px;">💥</div>
    <h2 id="t-accTitle" style="color:#fff;font-size:22px;font-weight:900;">Nehoda</h2>
    <p id="t-accSub" style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Nahlaste situaci MotoGo24</p>
  </div>
  <div style="padding:14px 20px 0;">
    <div class="sos-option" onclick="sosReportAccident('lehka')" style="border-color:#fde68a;">
      <div class="sos-option-icon" style="background:#fef3c7;">⚠️</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-accMinor">Lehká nehoda – jen škrábanec</div>
        <div class="sos-option-sub" id="t-accMinorDesc">Jedu dál, jen informuji MotoGo24 o incidentu</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="sosReportTheft();goTo('s-sos-kradez')" style="border-color:#dc2626;">
      <div class="sos-option-icon" style="background:#fee2e2;">🔓</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-accTheft" style="color:#b91c1c;">Krádež motorky</div>
        <div class="sos-option-sub" id="t-accTheftDesc">Motorka byla odcizena – neprodleně volejte policii</div>
      </div>
      <div class="sos-option-arrow" style="color:#b91c1c;">›</div>
    </div>
    <div class="sos-option" onclick="_sosActiveIncidentId=null;_sosFault=null;goTo('s-sos-nepojizda')" style="border-color:#fca5a5;">
      <div class="sos-option-icon" style="background:#fee2e2;">🚨</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-accImmob">Motorka je nepojízdná</div>
        <div class="sos-option-sub" id="t-accImmobDesc">Potřebuji pomoc – náhradní moto nebo odtah</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div style="margin-top:14px;background:rgba(239,68,68,.06);border-radius:var(--rsm);padding:12px 14px;border:1px solid rgba(239,68,68,.15);">
      <div id="t-accLegalInfo" style="font-size:12px;color:#b91c1c;font-weight:600;line-height:1.8;">
        🚑 Záchrannou (112/155) volejte dle potřeby sami.<br>
        🚔 <strong>Policii ČR jste povinni volat</strong> při: zranění · škodě nad 100 000 Kč · škodě na majetku třetích osob · nesouhlasu účastníků · krádeži.<br>
        📱 <strong>Veškeré hlášení výhradně přes aplikaci.</strong> Policejní protokoly zasílejte e-mailem na <a href="mailto:info@motogo.cz" style="color:#b91c1c;font-weight:700;">info@motogo.cz</a>.<br>
        💚 Při nezaviněné nehodě – náhradní motorka a odtah jsou zdarma.<br>
        ⚠️ Při porušení podmínek (alkohol, rychlost...) hradíte škodu v plné výši.
      </div>
    </div>
  </div>`;

Templates['s-sos-nepojizda'] = `  <div class="sos-sub-hdr">
    <div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">←</div><div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zpět</div></div>
    <div style="font-size:28px;margin-bottom:8px;">🚨</div>
    <h2 id="t-immobTitle" style="color:#fff;font-size:22px;font-weight:900;">Motorka je nepojízdná</h2>
    <p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Nejdříve upřesněte situaci</p>
  </div>
  <div style="padding:10px 20px 0;display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:6px;">
    <button onclick="setNepojizda(false)" id="btn-nepoj-nevinik" style="background:var(--green);color:#fff;border:none;border-radius:var(--r);padding:14px 8px;font-family:var(--font);font-size:13px;font-weight:800;cursor:pointer;line-height:1.4;">
      ✅ Nehoda nebyla<br>moje chyba
    </button>
    <button onclick="setNepojizda(true)" id="btn-nepoj-vinik" style="background:var(--g100);color:var(--black);border:2px solid var(--g200);border-radius:var(--r);padding:14px 8px;font-family:var(--font);font-size:13px;font-weight:800;cursor:pointer;line-height:1.4;">
      ⚠️ Nehoda byla<br>moje chyba
    </button>
  </div>
  <div id="nepojizda-info" style="padding:0 20px;margin-bottom:8px;"><div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;">💚 Při poruše (bez vaší viny) je náhradní motorka i přistavení <strong>zdarma</strong>.</div></div>
  <div style="padding:0 20px 0;">
    <div class="sos-option" onclick="sosRequestReplacement()" style="border-color:#86efac;">
      <div class="sos-option-icon" style="background:var(--gp);">🏍️</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="nahr-title">Náhradní motorka – <span id="nahr-zdarma">zdarma</span></div>
        <div class="sos-option-sub" id="nahr-sub">Přivezeme náhradní moto · bez vaší viny = zdarma</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="sosEndRide()" style="border-color:#fca5a5;">
      <div class="sos-option-icon" style="background:#fee2e2;">🚛</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-immobEnd">Ukončit jízdu – zavolat odtah</div>
        <div class="sos-option-sub" id="t-immobEndDesc">MotoGo24 zařídí odtah motorky, pronájem ukončíme</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div style="margin-top:14px;background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);">
      <div id="t-immobShareLabel" style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">Sdílet polohu asistentům</div>
      <button id="t-immobShareBtn" onclick="sosShareLocation()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:13px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;">
        📍 Sdílet GPS polohu
      </button>
    </div>
  </div>`;

// ===== SOS PLATEBNÍ BRÁNA (simulace) — zaviněná nehoda =====
Templates['s-sos-payment'] = `  <div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1e293b,#334155);">
    <div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">←</div><div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zpět</div></div>
    <div style="font-size:28px;margin-bottom:8px;">💳</div>
    <h2 style="color:#fff;font-size:20px;font-weight:900;">Platba za náhradní motorku</h2>
    <p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Zaviněná nehoda — přistavení za poplatek</p>
  </div>
  <div style="padding:14px 20px 0;">
    <!-- Částka -->
    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;text-align:center;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:6px;">K úhradě</div>
      <div id="sos-pay-amount" style="font-size:28px;font-weight:900;color:#b91c1c;">0 Kč</div>
      <div style="font-size:11px;color:var(--g400);margin-top:4px;">Náhradní motorka + přistavení</div>
    </div>

    <!-- Platební formulář -->
    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:14px;">
        <div style="font-size:20px;">🔒</div>
        <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;">Zabezpečená platba</div>
        <div style="margin-left:auto;display:flex;gap:4px;">
          <span style="background:#1a1f36;color:#fff;border-radius:4px;padding:2px 6px;font-size:9px;font-weight:800;">VISA</span>
          <span style="background:#eb001b;color:#fff;border-radius:4px;padding:2px 6px;font-size:9px;font-weight:800;">MC</span>
        </div>
      </div>

      <div style="margin-bottom:10px;">
        <label style="font-size:11px;font-weight:700;color:var(--g400);display:block;margin-bottom:4px;">Číslo karty</label>
        <input type="text" id="sos-pay-card" placeholder="1234 5678 9012 3456" maxlength="19"
          oninput="this.value=this.value.replace(/[^0-9 ]/g,'').replace(/(.{4})/g,'$1 ').trim()"
          style="width:100%;box-sizing:border-box;padding:12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:15px;letter-spacing:2px;">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
        <div>
          <label style="font-size:11px;font-weight:700;color:var(--g400);display:block;margin-bottom:4px;">Expirace</label>
          <input type="text" id="sos-pay-expiry" placeholder="MM/RR" maxlength="5"
            oninput="var v=this.value.replace(/[^0-9]/g,'');if(v.length>2)v=v.slice(0,2)+'/'+v.slice(2);this.value=v;"
            style="width:100%;box-sizing:border-box;padding:12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:15px;text-align:center;">
        </div>
        <div>
          <label style="font-size:11px;font-weight:700;color:var(--g400);display:block;margin-bottom:4px;">CVC</label>
          <input type="text" id="sos-pay-cvc" placeholder="123" maxlength="4"
            oninput="this.value=this.value.replace(/[^0-9]/g,'')"
            style="width:100%;box-sizing:border-box;padding:12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:15px;text-align:center;">
        </div>
      </div>

      <div id="sos-pay-error" style="display:none;margin-top:10px;padding:8px 12px;background:#fee2e2;border-radius:var(--rsm);font-size:12px;font-weight:600;color:#b91c1c;"></div>
    </div>

    <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:var(--rsm);padding:10px 14px;font-size:11px;font-weight:600;color:#92400e;line-height:1.6;margin-bottom:12px;">
      ⚠️ <strong>Testovací prostředí</strong> — platba bude simulována. Zadejte libovolné údaje karty.
    </div>

    <button id="sos-pay-btn" onclick="sosPaymentSubmit()"
      style="width:100%;background:#b91c1c;color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(185,28,28,.3);">
      💳 Zaplatit
    </button>
    <div style="text-align:center;margin-top:10px;margin-bottom:20px;">
      <button onclick="histBack()" style="background:none;border:none;font-family:var(--font);font-size:12px;font-weight:600;color:var(--g400);cursor:pointer;text-decoration:underline;">Zrušit</button>
    </div>
  </div>`;

// ===== OBJEDNÁVKA NÁHRADNÍ MOTORKY — výběr moto, adresa, platba =====
Templates['s-sos-replacement'] = `  <div class="sos-sub-hdr" id="sos-repl-hdr" style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);">
    <div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">←</div><div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zpět</div></div>
    <div style="font-size:28px;margin-bottom:8px;">🏍️</div>
    <h2 style="color:#fff;font-size:20px;font-weight:900;">Náhradní motorka</h2>
    <p style="color:rgba(255,255,255,.8);font-size:12px;margin-top:4px;" id="sos-repl-subtitle">Vyberte motorku a zadejte adresu přistavení</p>
  </div>
  <div style="padding:14px 20px 0;">
    <!-- Info banner -->
    <div id="sos-repl-banner" style="border-radius:var(--rsm);padding:10px 14px;font-size:12px;font-weight:600;line-height:1.6;margin-bottom:12px;"></div>

    <!-- 1. Výběr motorky -->
    <div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">1. Vyberte náhradní motorku</div>
      <div id="sos-repl-motos" style="display:flex;flex-direction:column;gap:8px;">
        <div style="text-align:center;padding:20px;color:var(--g400);font-size:12px;">Načítám dostupné motorky...</div>
      </div>
    </div>

    <!-- 2. Adresa přistavení -->
    <div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">2. Adresa přistavení</div>
      <div style="position:relative;"><input type="text" id="sos-repl-address" placeholder="Ulice a číslo popisné" oninput="showAddrSuggestions(this,'sos-repl')" autocomplete="off" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;margin-bottom:8px;"><div id="sos-repl-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;">
        <input type="text" id="sos-repl-city" placeholder="Město" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;">
        <input type="text" id="sos-repl-zip" placeholder="PSČ" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;">
      </div>
      <button onclick="sosReplFillGPS()" style="margin-top:8px;background:var(--gp);color:var(--gd);border:1px solid var(--green);border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">📍 Použít mou aktuální polohu</button>
      <textarea id="sos-repl-note" placeholder="Poznámka pro řidiče (volitelné)" rows="2" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;margin-top:8px;resize:vertical;"></textarea>
    </div>

    <!-- 3. Shrnutí a platba -->
    <div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">3. Shrnutí objednávky</div>
      <div id="sos-repl-summary" style="font-size:13px;line-height:1.8;color:var(--black);"></div>
      <div style="border-top:2px solid var(--g100);margin-top:10px;padding-top:10px;display:flex;justify-content:space-between;align-items:center;">
        <span style="font-size:15px;font-weight:900;" id="sos-repl-total-label">Celkem</span>
        <span style="font-size:20px;font-weight:900;" id="sos-repl-total">0 Kč</span>
      </div>
    </div>

    <!-- Tlačítko -->
    <button id="sos-repl-btn" onclick="sosConfirmReplacement()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(116,251,113,.4);">
      Potvrdit objednávku
    </button>
    <div style="text-align:center;margin-top:10px;margin-bottom:20px;">
      <button onclick="histBack()" style="background:none;border:none;font-family:var(--font);font-size:12px;font-weight:600;color:var(--g400);cursor:pointer;text-decoration:underline;">Zrušit</button>
    </div>
  </div>`;

// ===== SOS DONE — potvrzení po nahlášení =====
Templates['s-sos-done'] = `  <div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1a8a18,#22c55e);">
    <div style="font-size:48px;margin-bottom:8px;margin-top:20px;">✅</div>
    <h2 style="color:#fff;font-size:22px;font-weight:900;">Incident nahlášen</h2>
    <p style="color:rgba(255,255,255,.8);font-size:13px;margin-top:6px;" id="sos-done-subtitle">MotoGo24 přijala vaše hlášení</p>
  </div>
  <div style="padding:14px 20px 0;">
    <div id="sos-done-detail" style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;"></div>

    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">Co bude dál?</div>
      <div id="sos-done-next" style="font-size:13px;line-height:1.8;color:var(--black);"></div>
    </div>

    <div id="sos-done-actions" style="margin-bottom:12px;"></div>

    <div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:8px;">Přímý kontakt</div>
      <a href="tel:+420774256271" style="display:flex;align-items:center;gap:12px;text-decoration:none;">
        <div style="width:40px;height:40px;background:var(--green);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">📞</div>
        <div><div style="font-size:14px;font-weight:800;color:var(--black);">+420 774 256 271</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">MotoGo24 asistenční linka 24/7</div></div>
      </a>
    </div>

    <button onclick="goTo('s-messages')" style="width:100%;background:var(--gp);color:var(--gd);border:2px solid var(--green);border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:8px;">
      📨 Zprávy z MotoGo24
    </button>

    <button onclick="goTo('s-res')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:8px;">
      📋 Moje rezervace
    </button>

    <button onclick="goTo('s-home')" style="width:100%;background:var(--g100);color:var(--black);border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:20px;">
      Zpět na hlavní obrazovku
    </button>
  </div>`;
