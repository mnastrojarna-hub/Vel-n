// ===== TEMPLATES-RES-SOS2.JS – SOS screens part 2 (s-sos-porucha, s-sos-nepojizda-porucha, s-sos-servis, s-sos-kradez) =====
Templates['s-sos-porucha'] = `  <div class="sos-sub-hdr warn">
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 style="color:#fff;font-size:16px;font-weight:900;margin:0;" id="t-breakdownTitle">⚠️ Porucha za jízdy</h2><p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;" id="t-breakdownSub">Motorka jede, ale má problém</p></div></div>
  </div>

  <div style="padding:14px 20px 0;">
    <div id="sos-photo-step-porucha"></div>
    <div style="font-size:11px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px;" id="t-orSelect">Vyberte situaci:</div>
    <div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;margin-bottom:10px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;" id="t-freeRepairNote">
      💚 Při vážné poruše (nezaviněné) je náhradní motorka i přistavení <strong>zdarma</strong>. Vše hlaste přes appku.
    </div>
    <div class="sos-option" onclick="sosDrobnaZavada()" style="border-color:#fde68a;">
      <div class="sos-option-icon" style="background:#fef3c7;">🔩</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-minorFault">Drobná závada – jedu dál</div>
        <div class="sos-option-sub" id="t-cosmeticDmg">Kosmetická závada (kufr, kryt...) – informuji MotoGo24, pokračuji</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="goTo('s-sos-nepojizda-porucha')" style="border-color:#fca5a5;">
      <div class="sos-option-icon" style="background:#fee2e2;">🚫</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-cantRide">Motorka je nepojízdná</div>
        <div class="sos-option-sub" id="t-seriousFault">Vážná závada – náhradní motorka nebo odtah zdarma (nezaviněné)</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="goTo('s-sos-servis')" style="border-color:#bfdbfe;">
      <div class="sos-option-icon" style="background:#eff6ff;">🔧</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-nearService">Nejbližší servis – faktura</div>
        <div class="sos-option-sub" id="t-serviceProcess">Vyhledat nejbližší servis · vezměte fakturu · MotoGo24 zpětně proplatí</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
  </div>`;

Templates['s-sos-nepojizda-porucha'] = `  <div class="sos-sub-hdr warn">
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 style="color:#fff;font-size:16px;font-weight:900;margin:0;" id="t-wontStartTitle">🔧 Nepojízdná – porucha</h2><p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;" id="t-wontStartSub">Technická závada</p></div></div>
  </div>
  <div style="padding:14px 20px 0;">
    <div class="sos-option" onclick="_sosActiveIncidentId=null;sosRequestReplacement()" style="border-color:#86efac;">
      <div class="sos-option-icon" style="background:var(--gp);">🏍️</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-replaceTitle">Náhradní motorka co nejdříve</div>
        <div class="sos-option-sub" id="t-replaceFree">Vyberte motorku, zadejte adresu – <strong>zdarma</strong></div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div class="sos-option" onclick="sosEndRideFree()" style="border-color:#86efac;">
      <div class="sos-option-icon" style="background:var(--gp);">✅</div>
      <div style="flex:1;">
        <div class="sos-option-title" id="t-endRideTitle">Ukončit jízdu – zařídím se sám</div>
        <div class="sos-option-sub" id="t-rentalFree">Pronájem bude <strong>zdarma</strong> – peníze vrátíme. MotoGo24 odbaví odtah.</div>
      </div>
      <div class="sos-option-arrow">›</div>
    </div>
    <div style="margin-top:14px;background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);">
      <button onclick="sosShareLocation()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:13px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;">
        <span id="t-shareGPSBtn2">📍 Sdílet GPS polohu asistentům</span>
      </button>
    </div>
  </div>`;

Templates['s-sos-servis'] = `  <div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1e3a5f,#2563eb);">
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 style="color:#fff;font-size:16px;font-weight:900;margin:0;" id="t-selfServiceTitle">🔧 Servisní požadavek</h2><p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;" id="t-selfServiceSub">Plánovaná údržba</p></div></div>
  </div>
  <div style="padding:14px 20px 0;">
    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:13px;font-weight:800;color:#1d4ed8;margin-bottom:12px;" id="t-stepsTitle">📋 Postup:</div>
      <div style="display:flex;flex-direction:column;gap:10px;">
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">1</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Vyhledejte nejbližší autorizovaný nebo značkový servis<br><button onclick="sosNearbyServis()" style="margin-top:6px;background:#2563eb;color:#fff;border:none;border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">📍 Vyhledat servis v okolí</button></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">2</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Informujte MotoGo24 před opravou<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Telefonicky nebo přes appku – schválíme rozsah opravy.</span></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">3</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Vezměte fakturu na jméno MotoGo24<br><span style="font-size:11px;color:#6b7280;font-weight:500;">IČ: 123 456 78 · DIČ: CZ12345678 · Mezná 9, 393 01</span></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">4</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Nahrajte fakturu přes aplikaci nebo e-mailem<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Proplatíme do 7 dní od doručení.</span></div></div>
      </div>
    </div>
    <div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:var(--r);padding:12px;margin-bottom:12px;font-size:12px;font-weight:600;color:#1d4ed8;line-height:1.7;">
      ✅ Proplácíme: opravy přímých závad motorcyklu vzniklých bez zavinění nájemce.<br>
      ❌ Neproplácíme: opravy po nehodě nebo poškozením z vaší strany.
    </div>
    <button onclick="showT('📞','Volám MotoGo24','Schválení opravy nutné před realizací')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(116,251,113,.4);">
      <span id="t-notifyFirst">📞 Nejdříve informovat MotoGo24</span>
    </button>
  </div>`;

Templates['s-sos-kradez'] = `  <div class="sos-sub-hdr" style="background:linear-gradient(135deg,#991b1b,#b91c1c);">
    <div style="display:flex;align-items:center;gap:10px"><div class="sos-sub-back-btn" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 style="color:#fff;font-size:16px;font-weight:900;margin:0;" id="t-stolenTitle">🚨 Krádež motorky</h2><p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:2px;" id="t-stolenSub">Okamžitě nahlaste</p></div></div>
  </div>
  <div style="padding:14px 20px 0;">
    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="font-size:13px;font-weight:800;color:#b91c1c;margin-bottom:12px;display:flex;align-items:center;gap:6px;" id="t-immediateSteps">🚨 Okamžité kroky:</div>
      <div style="display:flex;flex-direction:column;gap:10px;">
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#b91c1c;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">1</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Zavolejte <strong>Policii ČR: 158</strong><br><span style="font-size:11px;color:#6b7280;font-weight:500;">Krádež vozidla musíte nahlásit policii – bez policejního protokolu nemůžete být zproštěni odpovědnosti.</span></div></div>
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#b91c1c;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">2</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Kontaktujte MotoGo24 okamžitě<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Telefonicky a e-mailem. GPS poloha motorky bude ověřena.</span></div></div>
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#92400e;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">3</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Zajistěte číslo jednací od policie<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Bude potřeba pro vypořádání škody.</span></div></div>
      </div>
    </div>
    <div style="background:#fff3cd;border:1px solid #fde68a;border-radius:var(--r);padding:14px;margin-bottom:12px;">
      <div style="font-size:12px;font-weight:700;color:#92400e;line-height:1.7;">
        ⚠️ <strong>Vaše odpovědnost:</strong><br>
        Pokud bylo vozidlo řádně zabezpečeno (zamčená řídítka, klíče mimo zapalování) → max. 30 000 Kč.<br>
        Pokud nebylo zabezpečeno → <strong>plná tržní hodnota motorky</strong>.
      </div>
    </div>
    <a href="tel:158" style="display:flex;align-items:center;justify-content:center;gap:10px;background:#b91c1c;color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;text-decoration:none;margin-bottom:10px;box-shadow:0 4px 18px rgba(185,28,28,.4);">
      <span id="t-callPoliceBtn">📞 Volat Policii ČR – 158</span>
    </a>
    <a href="tel:+420774256271" style="display:flex;align-items:center;justify-content:center;gap:10px;background:var(--green);color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;text-decoration:none;box-shadow:0 4px 18px rgba(116,251,113,.4);">
      <span id="t-callMotoGoBtn">📞 Volat MotoGo24</span>
    </a>
    <div id="sos-photo-step-kradez"></div>
    <button id="sos-kradez-report-btn" onclick="sosReportTheft()" style="width:100%;margin-top:12px;background:#7f1d1d;color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(127,29,29,.4);">
      🚨 Nahlásit krádež MotoGo24
    </button>
    <div style="background:#fff3cd;border:1px solid #fde68a;border-radius:var(--r);padding:14px;margin-top:12px;text-align:center;">
      <div style="font-size:13px;font-weight:800;color:#92400e;line-height:1.7;">
        POKUD CHCETE NOVOU MOTORKU UDĚLEJTE NOVOU REZERVACI
      </div>
    </div>
  </div>`;
