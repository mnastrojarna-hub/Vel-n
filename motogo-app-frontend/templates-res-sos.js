// ===== TEMPLATES-RES-SOS.JS – SOS core screens (s-sos, s-sos-nehoda, s-sos-nepojizda) =====
// SOS payment + replacement + done templates moved to templates-sos-payment.js
// s-contracts template moved to templates-done.js (dynamic renderContractsPage)

Templates['s-sos'] = `  <div class="sos-hdr">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-sosTitle" style="font-size:16px;font-weight:900;color:#fff;margin:0;">🆘 Pomoc na cestě</h2><p id="t-sosSub" style="font-size:12px;color:rgba(255,255,255,.7);font-weight:500;margin-top:2px;">Co se stalo? Vybereme nejlepší pomoc.</p></div></div>
  </div>
  <div style="padding:14px 20px 0;">
    <!-- AI Diagnostika — featured card -->
    <div onclick="aiAgentOpen()" style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);border-radius:var(--r);padding:16px;margin-bottom:14px;cursor:pointer;box-shadow:0 4px 20px rgba(26,46,34,.35);position:relative;overflow:hidden;">
      <div style="position:absolute;top:-20px;right:-20px;width:100px;height:100px;background:rgba(116,251,113,.08);border-radius:50%;"></div>
      <div style="position:absolute;bottom:-30px;right:30px;width:70px;height:70px;background:rgba(116,251,113,.05);border-radius:50%;"></div>
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:10px;">
        <div style="width:44px;height:44px;background:var(--green);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0;box-shadow:0 2px 12px rgba(116,251,113,.4);">🤖</div>
        <div style="flex:1;">
          <div style="font-size:15px;font-weight:900;color:#fff;">MotoGo AI Asistent</div>
          <div style="font-size:11px;color:rgba(255,255,255,.6);margin-top:2px;">AI diagnostika & technická podpora 24/7</div>
        </div>
        <div style="display:flex;align-items:center;gap:4px;"><div style="width:7px;height:7px;background:#4ade80;border-radius:50%;"></div><span style="font-size:10px;color:#4ade80;font-weight:700;">Online</span></div>
      </div>
      <div style="font-size:12px;color:rgba(255,255,255,.75);line-height:1.6;margin-bottom:10px;">Svítí kontrolka? Motorka dělá divný zvuk? Popište problém a AI technik vám poradí:</div>
      <div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px;">
        <span style="background:rgba(116,251,113,.15);color:#4ade80;font-size:10px;font-weight:700;padding:4px 10px;border-radius:50px;">🔍 Diagnostika závady</span>
        <span style="background:rgba(116,251,113,.15);color:#4ade80;font-size:10px;font-weight:700;padding:4px 10px;border-radius:50px;">📖 Návody & obsluha</span>
        <span style="background:rgba(116,251,113,.15);color:#4ade80;font-size:10px;font-weight:700;padding:4px 10px;border-radius:50px;">🛠️ Řešení na místě</span>
      </div>
      <div style="display:flex;align-items:center;justify-content:center;gap:8px;background:var(--green);border-radius:50px;padding:11px 16px;font-size:13px;font-weight:800;color:#fff;">🤖 Spustit AI diagnostiku<span style="font-size:16px;">›</span></div>
    </div>

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
        <div class="sos-option-sub" id="t-sosBreakdownDesc">Technická závada – náhradní moto & asistence</div>
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
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-accTitle" style="color:#fff;font-size:16px;font-weight:900;margin:0;">💥 Hlášení nehody</h2><p id="t-accSub" style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;">Zdokumentujte nehodu</p></div></div>
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
    <div class="sos-option" onclick="goTo('s-sos-kradez')" style="border-color:#dc2626;">
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
    <div id="sos-photo-step-nehoda"></div>
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
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-immobTitle" style="color:#fff;font-size:16px;font-weight:900;margin:0;">🚫 Motorka nepojízdná</h2><p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;">Nelze pokračovat v jízdě</p></div></div>
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
