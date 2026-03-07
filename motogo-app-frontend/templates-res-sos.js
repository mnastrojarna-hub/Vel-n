// ===== TEMPLATES-RES-SOS.JS – Contracts & SOS core screens (s-contracts, s-sos, s-sos-nehoda, s-sos-nepojizda) =====
Templates['s-contracts'] = `  <div class="topbar"><div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l" id="t-contrBack">Zpět</div></div><h2 id="t-contrTitle">📄 Dokumenty a smlouvy</h2><p id="t-contrSub">Archiv smluvní dokumentace</p></div>
  <div style="padding:10px 20px 0;"><div id="t-contrGDPR" style="background:var(--gp);border-radius:var(--r);padding:13px;margin-bottom:10px;font-size:12px;color:var(--gd);line-height:1.6;">🔒 Přístupné pouze vám. Zpracování dle GDPR.</div></div>
  <div style="padding:0 20px;">
    <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;padding:8px 0;">2026</div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">📋</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Smlouva – BMW R 1200 GS</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#RES-2026-0043 · 22. 2. 2026</div></div><button onclick="showT('⬇️','Stahování...','Smlouva_2026-0043.pdf')" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">🧾</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Faktura – BMW R 1200 GS</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#FAK-2026-0043 · 5 400 Kč cena bez DPH není plátcem</div></div><button onclick="showT('⬇️','Stahování...','Faktura_2026-0043.pdf')" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>
    <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;padding:8px 0;">2025</div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--g100);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">📋</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Smlouva – Benelli TRK 702X</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#RES-2025-0018 · 10. 1. 2025</div></div><button onclick="showT('⬇️','Stahování...','Smlouva_2025-0018.pdf')" style="background:var(--dark);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>
  </div>`;

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
      <input type="text" id="sos-repl-address" placeholder="Ulice a číslo popisné" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;margin-bottom:8px;">
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
