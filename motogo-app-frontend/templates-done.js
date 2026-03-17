// ===== TEMPLATES-DONE.JS – Done detail, Contracts, Profile, Invoices =====
Templates['s-done-detail'] = `  <div class="done-hdr">
    <div class="back-row" onclick="histBack()"><div class="bk-c" >←</div><div class="bk-l" id="t-backToRes">Zpět na rezervace</div></div>
    <h2 id="t-rideDetailTitle">Detail proběhlé jízdy</h2>
    <p id="done-sub">#RES-2025-0018</p>
  </div>
  <div class="rd-card" style="margin-top:10px;">
    <img id="done-img" class="rd-moto-img" src="https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=80" alt="">
    <div class="rd-section-t">Průběh výpůjčky</div>
    <div class="rd-row"><div class="rd-label" id="t-ddMotorcycle">Motorka</div><div class="rd-value" id="done-moto">Benelli TRK 702X</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddPickup">Vyzvednutí</div><div class="rd-value">10. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddReturn">Vrácení</div><div class="rd-value">14. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddDuration">Délka výpůjčky</div><div class="rd-value">4 dny</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddPickupPlace">Místo vyzvednutí</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddReturnPlace">Místo vrácení</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-ddTotalPrice">Celková cena</div><div class="rd-value" style="color:var(--gd);font-weight:900;">10 600 Kč</div></div>
  </div>
  <div class="rd-card">
    <div class="rd-section-t" id="t-docsToDownload">📄 Doklady ke stažení</div>
    <div id="done-docs-list">
      <!-- Dynamically filled by openResDetailById -->
    </div>
  </div>
  <div class="rd-card" id="done-rating-card">
    <div class="rd-section-t" id="t-yourRating">⭐ Vaše hodnocení</div>
    <div id="done-stars-wrap" style="display:flex;justify-content:center;gap:8px;padding:10px 0;">
      <span class="star-btn" data-v="1" onclick="rateRide(1)" style="font-size:32px;cursor:pointer;transition:transform .15s;color:#f59e0b;transform:scale(1.15);">★</span>
      <span class="star-btn" data-v="2" onclick="rateRide(2)" style="font-size:32px;cursor:pointer;transition:transform .15s;color:#f59e0b;transform:scale(1.15);">★</span>
      <span class="star-btn" data-v="3" onclick="rateRide(3)" style="font-size:32px;cursor:pointer;transition:transform .15s;color:#f59e0b;transform:scale(1.15);">★</span>
      <span class="star-btn" data-v="4" onclick="rateRide(4)" style="font-size:32px;cursor:pointer;transition:transform .15s;color:#f59e0b;transform:scale(1.15);">★</span>
      <span class="star-btn" data-v="5" onclick="rateRide(5)" style="font-size:32px;cursor:pointer;transition:transform .15s;color:#f59e0b;transform:scale(1.15);">★</span>
    </div>
    <div id="done-rating-msg" style="text-align:center;font-size:12px;color:var(--g400);font-weight:600;padding-bottom:4px;">🏆 <span id="t-tapToRate">Výborná zkušenost!</span></div>
  </div>
  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="t-bookAgain" onclick="openDetail('benelli');goTo('s-detail');showT('🏍️','Rezervace','Vyberte termín pro stejnou motorku')">🔁 Znovu rezervovat</button>
  </div>
  <div style="height:10px;"></div>`;

Templates['s-contracts'] = `  <div class="topbar"><div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div><h2 id="t-docsTitle">📄 Dokumenty a smlouvy</h2><p id="t-docsSubtitle">Archiv smluvní dokumentace</p></div>
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
    <div class="back-row" onclick="histBack()" style="position:relative;z-index:2;"><div class="bk-c">\u2190</div><div class="bk-l">Zp\u011bt</div></div>
    <div style="display:flex;align-items:center;justify-content:center;gap:10px;">
      <img src="${IMG_BASE64_0}" style="width:56px;height:56px;border-radius:14px;object-fit:cover;background:var(--green);" alt="MotoGo24">
      <div><div style="font-size:24px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div><div style="font-size:9px;font-weight:700;color:rgba(255,255,255,.4);letter-spacing:2.5px;text-transform:uppercase;margin-top:3px;">Půjčovna motorek</div></div>
    </div>
    <div class="prof-pilot-lbl" id="t-loggedPilot">Přihlášený pilot</div>
    <div class="prof-pilot-name" id="profile-header-name"></div>
    <div class="prof-email" id="profile-header-email"></div>
  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-account">Můj účet</div>
    <div class="mi" onclick="toggleExpand('exp-udaje','arr-udaje')"><div class="mii">👤</div><div class="mit" id="prof-lbl-personal">Osobní údaje</div><div class="mia" id="arr-udaje">›</div></div>
    <div class="mi-expand" id="exp-udaje">
      <div class="edit-field"><label>Jméno a příjmení</label><input id="profile-name" type="text" value=""></div>
      <div class="edit-field"><label id="t-pEmail">E-mail</label><input id="profile-email" type="email" value="" disabled></div>
      <div class="edit-field"><label id="t-pPhone">Telefon</label><input id="profile-phone" type="tel" value=""></div>
      <div class="edit-field"><label id="t-pCity">Město</label><input id="profile-city" type="text" value=""></div>
      <div class="edit-field"><label id="t-pZip">PSČ</label><input id="profile-zip" type="text" value=""></div>
      <div class="edit-field"><label id="t-pStreet">Ulice</label><input id="profile-street" type="text" value=""></div>
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
    <div class="mi" onclick="toggleExpand('exp-platba','arr-platba')"><div class="mii">💳</div><div class="mit" id="prof-lbl-pay">Platební metody</div><div class="mia" id="arr-platba">›</div></div>
    <div class="mi-expand" id="exp-platba">
      <div style="display:flex;align-items:center;gap:10px;padding:10px;background:#fff;border-radius:var(--rsm);margin-bottom:8px;">
        <div style="font-size:20px;">💳</div>
        <div><div style="font-size:13px;font-weight:700;color:var(--black);">•••• •••• •••• 4242</div><div style="font-size:11px;color:var(--g400);font-weight:500;">Platí do 12/27</div></div>
        <div style="margin-left:auto;font-size:11px;font-weight:700;color:var(--red);cursor:pointer;" onclick="showT('🗑️','Karta odebrána','')">Odebrat</div>
      </div>
      <div class="edit-field"><label id="t-addNewCard">Přidat novou kartu</label><input type="text" placeholder="Číslo karty"></div>
      <button class="save-btn" id="t-addCard" onclick="showT('✓','Karta přidána','Uloženo')">Přidat kartu</button>
    </div>
  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-settings">Nastavení</div>
    <div class="mi" onclick="toggleExpand('exp-notif','arr-notif')"><div class="mii">🔔</div><div class="mit" id="prof-lbl-notif">Notifikace</div><div class="mia" id="arr-notif">›</div></div>
    <div class="mi-expand" id="exp-notif">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="t-pushNotif">Push notifikace</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="t-emailNews">E-mailové novinky</span> <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="t-smsReminders">SMS připomínky</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="t-specialOffers">Speciální nabídky</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" id="t-settingsSaved" onclick="showT('✓','Nastavení uloženo','')">Uložit</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-bio-set','arr-bio-set')"><div class="mii">🔐</div><div class="mit" id="prof-lbl-bio">Biometrické přihlášení</div><div class="mia" id="arr-bio-set">›</div></div>
    <div class="mi-expand" id="exp-bio-set">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="t-pFingerprint">Otisk prstu</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" id="t-bioSet" onclick="showT('✓','Biometrika nastavena','')">Uložit</button>
    </div>
    <div class="mi" onclick="toggleExpand('exp-priv','arr-priv')"><div class="mii">🔒</div><div class="mit" id="prof-lbl-priv">Soukromí & Oprávnění</div><div class="mia" id="arr-priv">›</div></div>
    <div class="mi-expand" id="exp-priv">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="prof-priv-loc">Sdílení polohy</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="prof-priv-cam">Fotoaparát</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="prof-priv-mic">Mikrofon</span> <input type="checkbox" checked style="accent-color:var(--green);width:16px;height:16px;"></label>
        <label style="display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:600;color:var(--black);"><span id="prof-priv-anal">Anonymní analytika</span> <input type="checkbox" style="accent-color:var(--green);width:16px;height:16px;"></label>
      </div>
      <button class="save-btn" id="t-permSaved" onclick="showT('✓','Oprávnění uložena','')">Uložit</button>
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

  </div>

  <div class="msec">
    <div class="msec-t" id="prof-sec-help">Pomoc & Podpora</div>
    <div class="mi" onclick="showT('❓','Nápověda','Otevírám FAQ...')"><div class="mii">❓</div><div class="mit" id="t-helpFAQ">Nápověda & FAQ</div><div class="mia">›</div></div>
    <div class="mi" onclick="openExternalLink('https://motogo24.vseproweb.com')"><div class="mii">🌐</div><div class="mit">motogo24.vseproweb.com</div><div class="mia">›</div></div>
    <div class="mi" onclick="openExternalLink('https://motogo24.vseproweb.com/blog')"><div class="mii">📝</div><div class="mit">Blog MotoGo24</div><div class="mia">›</div></div>
  </div>
  <div class="msec">
    <div class="msec-t" id="prof-sec-other">Ostatní</div>
    <div class="mi" onclick="doLogout()"><div class="mii" style="background:#fef2f2;">🚪</div><div class="mit" style="color:var(--red);" id="prof-lbl-logout">Odhlásit se</div></div>
  </div>
    <div style="text-align:center;padding:16px 14px 4px;">
      <span onclick="doDeleteAccount()" style="font-size:11px;color:var(--g400);cursor:pointer;text-decoration:underline;" id="prof-lbl-delete">Smazat účet a všechna data</span>
    </div>
  <div style="height:14px;"></div>`;

Templates['s-messages'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">\u2190</div><div class="bk-l">Zp\u011bt na profil</div></div>
    <h2>Zpr\u00e1vy</h2>
    <p>Komunikace s MotoGo24</p>
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
    <div class="back-row" onclick="histBack();msgSwitchTab('chat')"><div class="bk-c">\u2190</div><div class="bk-l">Zp\u011bt</div></div>
    <h2 id="thread-title">Konverzace</h2>
    <p id="thread-status" style="font-size:11px;"></p>
  </div>
  <div id="thread-messages" style="margin:0 20px;padding-bottom:80px;"></div>`;

Templates['s-invoices'] = `  <div class="topbar">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l" id="t-backToProfile">Zpět na profil</div></div>
    <h2 id="t-invoicesTitle">Faktury a vyúčtování</h2>
    <p id="t-autoGenerated">Automaticky generované dokumenty</p>
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
