Templates['s-contracts'] = `  <div class="topbar"><div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-docsTitle">📄 Dokumenty a smlouvy</h2><p id="t-docsSubtitle">Archiv smluvní dokumentace</p></div></div></div>
  <div style="display:flex;gap:6px;margin:10px 20px 0;">
    <select id="con-sort" onchange="renderContractsPage()" class="filter-sel">
      <option value="date_desc">Datum: nejnovější</option>
      <option value="date_asc">Datum: nejstarší</option>
    </select>
    <select id="con-type-filter" onchange="renderContractsPage()" class="filter-sel">
      <option value="">Všechny typy</option>
      <option value="contract">Smlouva</option>
      <option value="protocol">Předávací protokol</option>
      <option value="vop">VOP</option>
    </select>
  </div>
  <div id="contracts-content" style="margin:0;"></div>
  <div style="text-align:center;padding:40px 20px;color:var(--g400);font-size:12px;" id="contracts-loading">⏳ Načítám dokumenty...</div>`;

Templates['s-profile'] = `  <div class="prof-hdr">
    <div style="display:flex;align-items:center;justify-content:space-between;">
      <div style="display:flex;align-items:center;gap:10px;">
        <div class="bk-c" onclick="histBack()" style="flex-shrink:0;width:30px;height:30px;background:var(--green);border-radius:8px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:14px;font-weight:900;cursor:pointer;">\u2190</div>
        <img src="${IMG_BASE64_0}" style="width:36px;height:36px;border-radius:10px;object-fit:cover;background:var(--green);" alt="MotoGo24">
        <div>
          <div style="font-size:16px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div>
          <div style="font-size:9px;font-weight:700;color:rgba(255,255,255,.4);letter-spacing:2.5px;text-transform:uppercase;margin-top:2px;">P\u016fj\u010dovna motorek</div>
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:8px;">
        <div style="width:8px;height:8px;border-radius:50%;background:var(--green);"></div>
        <div class="h-av" onclick="goTo('s-profile')" title="Profil" style="width:34px;height:34px;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
      </div>
    </div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-top:8px;">
      <div style="flex-shrink:0;display:flex;align-items:center;gap:5px;background:rgba(116,251,113,.12);border-radius:8px;padding:7px 10px"><div style="font-size:9px;font-weight:700;color:rgba(255,255,255,.45);text-transform:uppercase;letter-spacing:.3px">Pilot:</div><div style="font-size:13px;font-weight:800;color:#fff" id="profile-header-name"></div></div>
      <div style="font-size:12px;color:rgba(255,255,255,.4);text-align:right;" id="profile-header-email"></div>
    </div>
  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-account">Můj účet</div>
    <div class="mi" onclick="toggleExpand('exp-udaje','arr-udaje')"><div class="mii">👤</div><div class="mit" id="prof-lbl-personal">Osobní údaje</div><div class="mia" id="arr-udaje">›</div></div>
    <div class="mi-expand" id="exp-udaje">
      <div class="edit-field"><label>Jméno a příjmení</label><input id="profile-name" type="text" value=""></div>
      <div class="edit-field"><label id="t-pEmail">E-mail</label><input id="profile-email" type="email" value="" disabled></div>
      <div class="edit-field"><label id="t-pPhone">Telefon</label><input id="profile-phone" type="tel" value=""></div>
      <div class="edit-field"><label id="t-pCity">Obec / město</label><input id="profile-city" type="text" value=""></div>
      <div class="edit-field"><label id="t-pZip">PSČ</label><input id="profile-zip" type="text" value=""></div>
      <div class="edit-field"><label id="t-pStreet">Ulice a č.p. / č.o.</label><input id="profile-street" type="text" value=""></div>
      <div class="edit-field"><label id="t-pDob">Datum narození</label><input id="profile-dob" type="text" readonly value="" placeholder="Vyberte datum" onclick="openDatePicker(this)" style="cursor:pointer;"></div>
      <div class="edit-field"><label id="t-pLicNum">Č. řidičského průkazu</label><input id="profile-license-num" type="text" value=""></div>
      <div class="edit-field"><label id="t-pLicExp">Platnost ŘP do</label><input id="profile-license-expiry" type="text" readonly value="" placeholder="Vyberte datum" onclick="openDatePicker(this)" style="cursor:pointer;"></div>
      <div class="edit-field"><label id="t-pLicCat">Kategorie ŘP</label><input id="profile-license-group" type="text" value=""></div>
      <button class="save-btn" id="t-saveChanges" onclick="doSaveProfile()">Uložit změny</button>
    </div>
    <div class="mi" onclick="goTo('s-messages')" style="position:relative;"><div class="mii" style="background:#e8ffe8;">📩</div><div class="mit" id="prof-lbl-messages">Zprávy z Moto Go</div><div id="msg-badge" class="msg-badge" style="display:none;">0</div><div class="mia">›</div></div>
    <div class="mi" onclick="goTo('s-docs')"><div class="mii">📋</div><div class="mit" id="prof-lbl-docs">Moje doklady</div><div class="mia">›</div></div>
    <div class="mi" onclick="goTo('s-invoices')"><div class="mii">🧾</div><div class="mit" id="prof-lbl-invoices">Faktury a vyúčtování</div><div class="mia">›</div></div>
    <div class="mi" onclick="goTo('s-contracts')"><div class="mii">📄</div><div class="mit" id="prof-lbl-contracts">Dokumenty a smlouvy</div><div class="mia">›</div></div>
    <div id="profile-documents" style="display:none;"></div>
    <div class="mi" onclick="toggleExpand('exp-platba','arr-platba');loadPaymentMethods()"><div class="mii">💳</div><div class="mit" id="prof-lbl-pay">Platební metody</div><div class="mia" id="arr-platba">›</div></div>
    <div class="mi-expand" id="exp-platba">
      <div id="pm-cards-list" style="margin-bottom:8px;">
        <div style="text-align:center;padding:12px;color:var(--g400);font-size:12px;">Načítám uložené karty...</div>
      </div>
      <div id="pm-add-card-form" style="display:none;background:#fff;border-radius:var(--rsm);padding:14px;margin-bottom:8px;border:2px solid var(--green);">
        <div style="font-size:13px;font-weight:700;color:var(--black);margin-bottom:10px;">Nová platební karta</div>
        <div style="margin-bottom:10px;">
          <label style="font-size:11px;font-weight:600;color:var(--g400);display:block;margin-bottom:4px;">Jméno držitele</label>
          <input id="card-holder-name" type="text" placeholder="Jan Novák" autocomplete="cc-name" style="width:100%;padding:10px 12px;border:1px solid var(--g200);border-radius:8px;font-family:var(--font);font-size:14px;font-weight:500;color:var(--black);background:#fafafa;box-sizing:border-box;">
        </div>
        <div style="margin-bottom:10px;">
          <label style="font-size:11px;font-weight:600;color:var(--g400);display:block;margin-bottom:4px;">Údaje karty</label>
          <div id="stripe-card-element" style="padding:10px 12px;border:1px solid var(--g200);border-radius:8px;background:#fafafa;min-height:20px;"></div>
        </div>
        <div id="card-form-error" style="font-size:11px;color:var(--red);margin-bottom:8px;min-height:14px;"></div>
        <button id="save-card-btn" onclick="submitNewCard()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:var(--rsm);padding:12px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;">Uložit kartu</button>
        <div style="font-size:10px;color:var(--g400);text-align:center;margin-top:6px;line-height:1.4;">Údaje karty jsou zabezpečeny přes Stripe. MotoGo24 nikdy neukládá číslo karty.</div>
      </div>
      <button id="add-card-btn" onclick="addNewCard()" style="width:100%;background:var(--gp);color:var(--gd);border:2px solid var(--green);border-radius:var(--rsm);padding:12px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;margin-bottom:8px;">+ Přidat novou kartu</button>
    </div>
  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-settings">Nastavení</div>
    <div class="mi" onclick="toggleExpand('exp-notif','arr-notif');loadProfileConsents('notif')"><div class="mii">🔔</div><div class="mit" id="prof-lbl-notif">Notifikace</div><div class="mia" id="arr-notif">›</div></div>
    <div class="mi-expand" id="exp-notif">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Push notifikace</span> <input type="checkbox" id="pref-push" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Email komunikace</span> <input type="checkbox" id="pref-email" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>SMS komunikace</span> <input type="checkbox" id="pref-sms" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>WhatsApp komunikace</span> <input type="checkbox" id="pref-wa" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Marketingový souhlas</span> <input type="checkbox" id="pref-marketing" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" onclick="saveProfileConsents('notif')">Uložit</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-bio-set','arr-bio-set')"><div class="mii">🔐</div><div class="mit" id="prof-lbl-bio">Biometrické přihlášení</div><div class="mia" id="arr-bio-set">›</div></div>
    <div class="mi-expand" id="exp-bio-set">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Otisk prstu / Face ID</span> <input type="checkbox" id="pref-bio-toggle" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" onclick="toggleBiometricSetting()">Uložit</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-priv','arr-priv');loadProfileConsents('priv')"><div class="mii">🔒</div><div class="mit" id="prof-lbl-priv">Soukromí a souhlasy</div><div class="mia" id="arr-priv">›</div></div>
    <div class="mi-expand" id="exp-priv">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>VOP — všeobecné obchodní podmínky</span> <input type="checkbox" id="pref-vop" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>GDPR — zpracování osobních údajů</span> <input type="checkbox" id="pref-gdpr" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Zpracování dat pro provoz služby</span> <input type="checkbox" id="pref-data" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Četl/a jsem návrh smlouvy na motogo24.cz a souhlasím</span> <input type="checkbox" id="pref-contract" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span>Fotografování dokladů a motorky</span> <input type="checkbox" id="pref-photo" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" onclick="saveProfileConsents('priv')">Uložit</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-heslo','arr-heslo')"><div class="mii">🔑</div><div class="mit">Změna hesla</div><div class="mia" id="arr-heslo">›</div></div>
    <div class="mi-expand" id="exp-heslo">
      <div class="edit-field"><label>Současné heslo</label><input id="chp-old" type="password" placeholder="••••••••"></div>
      <div class="edit-field"><label>Nové heslo (min. 8 znaků)</label><input id="chp-new1" type="password" placeholder="••••••••"></div>
      <div class="edit-field"><label>Nové heslo znovu</label><input id="chp-new2" type="password" placeholder="••••••••"></div>
      <button class="save-btn" onclick="doChangePassword()">Změnit heslo</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-jazyk','arr-jazyk')"><div class="mii">🌐</div><div class="mit" id="prof-lbl-lang">Jazyk aplikace</div><div class="mia" id="arr-jazyk">›</div></div>
    <div class="mi-expand" id="exp-jazyk">
      <div class="edit-field">
        <select id="lang-select" class="lang-sel" onchange="setLanguage(this.value)">
          <option value="cs" selected>🇨🇿 Čeština</option>
          <option value="en">🇬🇧 English</option>
          <option value="de">🇩🇪 Deutsch</option>
          <option value="es">🇪🇸 Español</option>
          <option value="fr">🇫🇷 Français</option>
          <option value="nl">🇳🇱 Nederlands</option>
          <option value="pl">🇵🇱 Polski</option>
        </select>
      </div>
    </div>
    <div class="mi" onclick="showStorageDiag()"><div class="mii">💾</div><div class="mit">Úložiště a cache</div><div class="mia">›</div></div>

  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-help">Pomoc & Podpora</div>
    <div class="mi" onclick="goTo('s-sos')"><div class="mii" style="background:#fee2e2;">🆘</div><div class="mit">SOS – Pomoc na cestě</div><div class="mia">›</div></div>
    <div class="mi" onclick="showT('❓','Nápověda','Otevírám FAQ...')"><div class="mii">❓</div><div class="mit" id="t-helpFAQ">Nápověda & FAQ</div><div class="mia">›</div></div>
    <div class="mi" onclick="openExternalLink('https://www.motogo24.cz')"><div class="mii">🌐</div><div class="mit">www.motogo24.cz</div><div class="mia">›</div></div>
    <div class="mi" onclick="openExternalLink('https://www.motogo24.cz/blog')"><div class="mii">📝</div><div class="mit">Blog MotoGo24</div><div class="mia">›</div></div>
    <div class="mi" onclick="toggleExpand('exp-pobocky','arr-pobocky');loadBranches()"><div class="mii" style="background:#e8f5e9;">📍</div><div class="mit" id="prof-lbl-branches">Pobočky</div><div class="mia" id="arr-pobocky">›</div></div>
    <div class="mi-expand" id="exp-pobocky">
      <div id="branches-list" style="margin-bottom:4px;">
        <div style="text-align:center;padding:12px;color:var(--g400);font-size:12px;">Načítám pobočky...</div>
      </div>
    </div>
  </div>
  <div class="msec">
    <div class="msec-t" id="prof-sec-other">Ostatní</div>
    <div class="mi" onclick="doLogout()"><div class="mii" style="background:#fef2f2;">🚪</div><div class="mit" style="color:var(--red);" id="prof-lbl-logout">Odhlásit se</div></div>
  </div>
    <div style="text-align:center;padding:16px 14px 4px;">
      <span onclick="doDeleteAccount()" style="font-size:11px;color:var(--g400);cursor:pointer;text-decoration:underline;" id="prof-lbl-delete">Smazat účet a všechna data</span>
    </div>
  <div style="text-align:center;padding:6px 14px 14px;font-size:10px;color:var(--g400);font-weight:600;letter-spacing:.5px;">MotoGo24 v5.5.4</div>`;

Templates['s-messages'] = `  <div class="topbar">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">\u2190</div><div><h2>📩 Zpr\u00e1vy</h2><p>Komunikace s MotoGo24</p></div></div>
  </div>
  <div style="margin:0 20px;">
    <div id="msg-tabs" style="display:flex;gap:4px;margin-bottom:12px;">
      <button onclick="msgSwitchTab('notif')" id="msg-tab-notif" class="msg-tab msg-tab-active" style="flex:1;padding:10px;border:2px solid var(--green);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:800;cursor:pointer;background:var(--green);color:#fff;">Ozn\u00e1men\u00ed</button>
      <button onclick="msgSwitchTab('chat')" id="msg-tab-chat" class="msg-tab" style="flex:1;padding:10px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:12px;font-weight:800;cursor:pointer;background:#fff;color:var(--black);">Konverzace</button>
    </div>
    <div style="display:flex;gap:6px;">
    <select id="msg-sort" onchange="msgApplyFilter()" class="filter-sel">
      <option value="date_desc">Datum: nejnov\u011bj\u0161\u00ed</option>
      <option value="date_asc">Datum: nejstar\u0161\u00ed</option>
    </select>
    <select id="msg-type-filter" onchange="msgApplyFilter()" class="filter-sel">
      <option value="">V\u0161echny typy</option>
      <option value="info">Informace</option>
      <option value="sos_response">SOS</option>
      <option value="thanks">Pod\u011bkov\u00e1n\u00ed</option>
      <option value="voucher">Voucher</option>
      <option value="replacement">N\u00e1hrada</option>
      <option value="tow">Odtah</option>
    </select>
    </div>
  </div>
  <div id="messages-list" style="margin:0 20px;">
    <div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1n\u00ed...</div>
  </div>
  <div id="threads-list" style="margin:0 20px;display:none;">
    <div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1n\u00ed...</div>
  </div>
  <div style="height:20px;"></div>`;

Templates['s-messages-thread'] = `  <div class="topbar">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack();msgSwitchTab('chat')" style="flex-shrink:0">\u2190</div><div><h2 id="thread-title">Vl\u00e1kno zpr\u00e1v</h2><p id="thread-status" style="font-size:11px;"></p></div></div>
  </div>
  <div id="thread-messages" style="margin:0 20px;padding-bottom:80px;"></div>`;

Templates['s-invoices'] = `  <div class="topbar">
    <div style="display:flex;align-items:center;gap:10px"><div class="bk-c" onclick="histBack()" style="flex-shrink:0">←</div><div><h2 id="t-invoicesTitle">🧾 Faktury a vyúčtování</h2><p id="t-autoGenerated">Automaticky generované dokumenty</p></div></div>
  </div>
  <div style="display:flex;gap:6px;margin:10px 20px 0;">
    <select id="inv-sort" onchange="renderInvoicesPage()" class="filter-sel">
      <option value="date_desc">Datum: nejnovější</option>
      <option value="date_asc">Datum: nejstarší</option>
    </select>
    <select id="inv-type-filter" onchange="renderInvoicesPage()" class="filter-sel">
      <option value="">Všechny typy</option>
      <option value="invoice_advance">Zálohová faktura</option>
      <option value="payment_receipt">Doklad k platbě</option>
      <option value="invoice_final">Faktura</option>
      <option value="invoice_shop">Shop faktura</option>
    </select>
  </div>
  <div id="invoices-list" style="margin:10px 20px 0;">
    <div style="text-align:center;padding:20px;color:var(--g400);"><span id="t-loading">⏳ Načítání...</span></div>
  </div>
  <div style="height:20px;"></div>`;

function loadTemplates() {
  for (const [id, html] of Object.entries(Templates)) {
    const el = document.getElementById(id);
    if (el) el.innerHTML = html;
  }
}
