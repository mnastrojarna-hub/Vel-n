// ===== TEXTS.JS – Long text blocks loaded on demand via innerHTML =====

const TEXTS = {

  // ── Contract / Document archive (s-contracts) ─────────────────────────

  contracts2026: `<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;padding:8px 0;">2026</div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">📋</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Smlouva – BMW R 1200 GS</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#RES-2026-0043 · 22. 2. 2026</div></div><button onclick="showT('⬇️','Stahování...','Smlouva_2026-0043.pdf')" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">🧾</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Faktura – BMW R 1200 GS</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#FAK-2026-0043 · 5 400 Kč cena bez DPH není plátcem</div></div><button onclick="showT('⬇️','Stahování...','Faktura_2026-0043.pdf')" style="background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>`,

  contracts2025: `<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;padding:8px 0;">2025</div>
    <div class="bcard" style="margin:0 0 10px;">
      <div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--g100);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">📋</div><div style="flex:1;"><div style="font-size:13px;font-weight:800;">Smlouva – Benelli TRK 702X</div><div style="font-size:11px;color:var(--g400);margin-top:2px;">#RES-2025-0018 · 10. 1. 2025</div></div><button onclick="showT('⬇️','Stahování...','Smlouva_2025-0018.pdf')" style="background:var(--dark);color:#fff;border:none;border-radius:var(--rsm);padding:8px 14px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">⬇️ PDF</button></div>
    </div>`,

  // ── SOS Nehoda – info banner (s-sos-nehoda) ───────────────────────────

  sosNehodaInfo: `<div style="font-size:12px;color:#b91c1c;font-weight:600;line-height:1.8;">
        🚑 Záchrannou (112/155) volejte dle potřeby sami.<br>
        🚔 <strong>Policii ČR jste povinni volat</strong> při: zranění · škodě nad 100 000 Kč · škodě na majetku třetích osob · nesouhlasu účastníků · krádeži.<br>
        📱 <strong>Veškeré hlášení výhradně přes aplikaci.</strong> Policejní protokoly zasílejte e-mailem na info@motogo24.cz.<br>
        💚 Při nezaviněné nehodě – náhradní motorka a odtah jsou zdarma.<br>
        ⚠️ Při porušení podmínek (alkohol, rychlost...) hradíte škodu v plné výši.
      </div>`,

  // ── SOS Krádež – step-by-step (s-sos-kradez) ─────────────────────────

  sosKradezSteps: `<div style="font-size:13px;font-weight:800;color:#b91c1c;margin-bottom:12px;display:flex;align-items:center;gap:6px;">🚨 Okamžité kroky:</div>
      <div style="display:flex;flex-direction:column;gap:10px;">
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#b91c1c;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">1</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Zavolejte <strong>Policii ČR: 158</strong><br><span style="font-size:11px;color:#6b7280;font-weight:500;">Krádež vozidla musíte nahlásit policii – bez policejního protokolu nemůžete být zproštěni odpovědnosti.</span></div></div>
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#b91c1c;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">2</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Kontaktujte MotoGo24 okamžitě<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Telefonicky a e-mailem. GPS poloha motorky bude ověřena.</span></div></div>
        <div style="display:flex;align-items:flex-start;gap:10px;"><div style="width:24px;height:24px;background:#92400e;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">3</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Zajistěte číslo jednací od policie<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Bude potřeba pro vypořádání škody.</span></div></div>
      </div>`,

  sosKradezOdpovednost: `<div style="font-size:12px;font-weight:700;color:#92400e;line-height:1.7;">
        ⚠️ <strong>Vaše odpovědnost:</strong><br>
        Pokud bylo vozidlo řádně zabezpečeno (zamčená řídítka, klíče mimo zapalování) → max. 30 000 Kč.<br>
        Pokud nebylo zabezpečeno → <strong>plná tržní hodnota motorky</strong>.
      </div>`,

  sosKradezNahradni: `<div style="font-size:12px;font-weight:700;color:var(--gd);line-height:1.7;">
        🏍️ <strong>Po vyřešení s policií:</strong><br>
        MotoGo24 vám zajistí náhradní motorku. Přistavení se v tomto případě účtuje dle km (1 000 Kč + 20 Kč/km) – krádež není provozní závada.
      </div>`,

  // ── SOS Servis – postup (s-sos-servis) ────────────────────────────────

  sosServisSteps: `<div style="font-size:13px;font-weight:800;color:#1d4ed8;margin-bottom:12px;">📋 Postup:</div>
      <div style="display:flex;flex-direction:column;gap:10px;">
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">1</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Vyhledejte nejbližší autorizovaný nebo značkový servis<br><button onclick="sosNearbyServis()" style="margin-top:6px;background:#2563eb;color:#fff;border:none;border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">📍 Vyhledat servis v okolí</button></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">2</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Informujte MotoGo24 před opravou<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Telefonicky nebo přes appku – schválíme rozsah opravy.</span></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">3</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Vezměte fakturu na jméno MotoGo24<br><span style="font-size:11px;color:#6b7280;font-weight:500;">IČ: 123 456 78 · DIČ: CZ12345678 · Mezná 9, 393 01</span></div></div>
        <div style="display:flex;gap:10px;"><div style="width:24px;height:24px;background:#2563eb;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;flex-shrink:0;">4</div><div style="font-size:13px;font-weight:600;line-height:1.5;">Nahrajte fakturu přes aplikaci nebo e-mailem<br><span style="font-size:11px;color:#6b7280;font-weight:500;">Proplatíme do 7 dní od doručení.</span></div></div>
      </div>`,

  sosServisInfo: `<div style="font-size:12px;font-weight:600;color:#1d4ed8;line-height:1.7;">
      ✅ Proplácíme: opravy přímých závad motorcyklu vzniklých bez zavinění nájemce.<br>
      ❌ Neproplácíme: opravy po nehodě nebo poškozením z vaší strany.
    </div>`,

  // ── Protocol checklist items (s-protocol section 3) ───────────────────

  protocolItems: `<div style="font-size:11px;color:var(--g400);font-weight:600;margin-bottom:10px;">Zaškrtněte vše co bylo předáno:</div>
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
    </div>`,

  protocolConfirmation: `Nájemce potvrzuje, že se s Předávacím protokolem seznámil, souhlasí s jeho obsahem a přebírá motocykl ve výše uvedeném stavu. Fotodokumentace pořízená při předání je rozhodující pro posouzení stavu motorky.`,

  // ── Invoices list (s-invoices) ────────────────────────────────────────

  invoices2026: `<div class="msec-t" style="padding:0 0 8px;">2026</div>
    <div class="inv-item" onclick="showT('⬇️','Stahování...','BMW GS – zálohová faktura.pdf')">
      <div class="inv-icon">🧾</div>
      <div class="inv-info"><div class="inv-name">BMW R 1200 GS · Záloha</div><div class="inv-sub">#RES-2026-0043 · 20. 2. 2026</div></div>
      <div><div class="inv-amt">5 400 Kč</div><div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️</div></div>
    </div>
    <div class="inv-item" onclick="showT('⬇️','Stahování...','Jawa RVM – konečná faktura.pdf')">
      <div class="inv-icon">💰</div>
      <div class="inv-info"><div class="inv-name">Jawa RVM 500 · Konečná</div><div class="inv-sub">#RES-2026-0031 · Probíhající</div></div>
      <div><div class="inv-amt">8 000 Kč</div><div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️</div></div>
    </div>`,

  invoices2025: `<div class="msec-t" style="padding:12px 0 8px;">2025</div>
    <div class="inv-item" onclick="showT('⬇️','Stahování...','Benelli – konečná faktura.pdf')">
      <div class="inv-icon">💰</div>
      <div class="inv-info"><div class="inv-name">Benelli TRK 702X · Konečná</div><div class="inv-sub">#RES-2025-0018 · 15. 1. 2025</div></div>
      <div><div class="inv-amt">10 600 Kč</div><div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️</div></div>
    </div>
    <div class="inv-item" onclick="showT('⬇️','Stahování...','CF MOTO – konečná faktura.pdf')">
      <div class="inv-icon">💰</div>
      <div class="inv-info"><div class="inv-name">CF MOTO 800 MT · Konečná</div><div class="inv-sub">#RES-2025-0009 · 10. 8. 2025</div></div>
      <div><div class="inv-amt">10 600 Kč</div><div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️</div></div>
    </div>`,

  // ── Docs upload warnings (s-docs) ─────────────────────────────────────

  docsWarning: `<div style="font-size:13px;color:#9a3412;font-weight:600;line-height:1.5;">Pro rezervaci motorky jsou nutné oba doklady. Uloženy bezpečně ve vašem zařízení.</div>`,

  docsNoUpload: `<div style="font-size:13px;font-weight:700;color:#b91c1c;margin-bottom:3px;">⚠️ Bez nahraných dokladů</div>
    <div style="font-size:12px;color:#dc2626;line-height:1.6;">Motorku lze rezervovat, ale <strong>kód k otevření boxu</strong> s klíčem obdržíte až po ověření dokladů. Doporučujeme nahrát předem.</div>`
};
