// ===== TEMPLATES.JS – Screen HTML templates for MotoGo24 =====
// Dependencies: images.js (for IMG_BASE64_* constants)

const Templates = {};

Templates['s-login'] = `  <div class="lt">
    <div style="position:relative;z-index:2;text-align:center;">
      <div style="display:flex;align-items:center;justify-content:center;gap:10px;margin-bottom:6px;">
        <img src="${IMG_BASE64_0}" style="width:88px;height:88px;border-radius:22px;object-fit:contain;background:#000;" alt="MotoGo24">
        <div><div style="font-size:32px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div><div id="t-rental" style="font-size:10px;font-weight:700;color:rgba(255,255,255,.45);letter-spacing:3px;text-transform:uppercase;margin-top:4px;">Půjčovna motorek</div></div>
      </div>
    </div>
    <div class="lt-tagline"><span id="t-tagline">Zažijte svobodu.</span></div>
  </div>
  <div class="ls">
    <div class="ls-head" id="t-loginHead">Přihlaste se pro snadnou jízdu 🏍️</div>
    <div class="ls-sub" id="t-loginSub">Váš profil a rezervace vždy po ruce</div>
    <div class="ff"><label id="t-loginEmail">E-mail</label><input id="login-email" type="email" placeholder="jan.novak@email.cz"></div>
    <div class="ff"><label id="t-loginPass">Heslo</label><input id="login-pass" type="password" placeholder="••••••••"></div>
    <button class="btn-g" id="t-loginBtn" onclick="doLogin()">Přihlásit se</button>
    <div style="text-align:center;margin-top:8px;"><a href="#" id="t-forgot" onclick="event.preventDefault();showForgotPassword()" style="font-size:12px;color:var(--green);font-weight:600;text-decoration:none;">Zapomněli jste heslo?</a></div>
    <!-- Biometric: shown dynamically based on device - shows only one button -->
    <div id="bio-section" style="display:none">
      <div class="divr" id="t-orBio">nebo rychle biometrikou</div>
      <div class="bio-single" id="bio-btn" onclick="bioLogin()">
        <div class="bio-icon" id="bio-icon">🔐</div>
        <div class="bio-label" id="bio-label">Biometrické přihlášení</div>
        <div class="bio-sub" id="bio-sub">Otisk prstu</div>
      </div>
    </div>
    <div class="divr"><span id="t-or">nebo</span></div>
    <button class="btn-out" id="t-registerBtn" onclick="startRegistrationWithScan()">Registrovat se</button>
    <div style="margin-top:12px;text-align:center;font-size:11px;color:var(--g400);font-weight:600;">📞 <a href="tel:+420774256271" style="color:var(--g400);text-decoration:none;">+420 774 256 271</a> · <a href="#" onclick="event.preventDefault();openExternalLink('https://motogo24.vseproweb.com')" style="color:var(--green);text-decoration:underline;">motogo24.vseproweb.com</a> · v5.5.4</div>
  </div>`;

Templates['s-register'] = `  <div class="reg-hdr">
    <div class="back-row" onclick="regBack()"><div class="bk-c">←</div><div class="bk-l" id="reg-back-label">Zpět na přihlášení</div></div>
    <h2 id="t-regTitle">Registrace pilota 🏍️</h2>
    <div class="reg-progress">
      <div class="reg-prog-step cur" id="rp1"></div>
      <div class="reg-prog-step" id="rp2"></div>
      <div class="reg-prog-step" id="rp3"></div>
      <div class="reg-prog-step" id="rp4"></div>
    </div>
  </div>
  <div class="bcard" style="margin-top:14px;">
    <div class="reg-step active" id="reg-step-1">
      <div class="reg-step-title" id="t-s1t">👤 Krok 1 / 4 – Základní údaje</div>
      <div class="reg-step-sub" id="t-s1s">Vyplňte své osobní informace</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:9px;">
        <div class="ff" style="margin:0;"><label id="t-firstName">Jméno</label><input id="reg-fname" type="text" placeholder="Jan"></div>
        <div class="ff" style="margin:0;"><label id="t-lastName">Příjmení</label><input id="reg-lname" type="text" placeholder="Novák"></div>
      </div>
      <div class="ff" style="margin-top:9px;"><label id="t-regEmail">E-mail</label><input id="reg-email" type="email" placeholder="jan@email.cz"></div>
      <div class="ff"><label id="t-phone">Telefon</label><input id="reg-phone" type="tel" placeholder="+420 777 000 000"></div>
      <div class="ff"><label id="t-dob">Datum narození</label><input id="reg-dob" type="text" readonly placeholder="Vyberte datum" onclick="openDatePicker(this)" style="cursor:pointer;"></div>
      <div class="ff" style="margin-bottom:0;"><label id="t-passLabel">Heslo (min. 8 znaků)</label><input id="reg-pass" type="password" placeholder="••••••••"></div>
      <div style="text-align:right;margin-top:6px;"><a href="#" id="t-regForgot" onclick="event.preventDefault();showForgotPassword()" style="font-size:12px;color:var(--green);font-weight:600;text-decoration:none;">Zapomněli jste heslo?</a></div>
    </div>
    <div class="reg-step" id="reg-step-2">
      <div class="reg-step-title" id="t-s2t">🏠 Krok 2 / 4 – Adresa bydliště</div>
      <div class="reg-step-sub" id="t-s2s">Potřebujeme vaši kontaktní adresu</div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:9px;">
        <div class="ff" style="margin:0;"><label id="t-city">Město</label><input id="reg-city" type="text" placeholder="Praha"></div>
        <div class="ff" style="margin:0;"><label id="t-zip">PSČ</label><input id="reg-zip" type="text" placeholder="110 00"></div>
      </div>
      <div class="ff" style="margin-top:9px;"><label id="t-street">Ulice a č.p.</label><input id="reg-street" type="text" placeholder="Náměstí 1"></div>
      <div class="ff" style="margin-top:9px;margin-bottom:0;"><label id="t-country">Stát</label>
        <select id="reg-country"><option id="t-cCZ">Česká republika</option><option id="t-cSK">Slovenská republika</option><option id="t-cDE">Německo</option><option id="t-cAT">Rakousko</option><option id="t-cPL">Polsko</option></select>
      </div>
    </div>
    <div class="reg-step" id="reg-step-3">
      <div class="reg-step-title" id="t-s3t">🏍️ Krok 3 / 4 – Řidičský průkaz</div>
      <div class="reg-step-sub" id="t-s3s">Informace o vašem řidičském oprávnění</div>
      <div class="ff"><label id="t-licNum">Číslo řidičského průkazu</label><input id="reg-license-num" type="text" placeholder="AB 123456"></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:9px;">
        <div class="ff" style="margin:0;"><label id="t-licFrom">Vydán dne</label><input id="reg-license-from" type="text" readonly placeholder="Vyberte datum" onclick="openDatePicker(this)" style="cursor:pointer;"></div>
        <div class="ff" style="margin:0;"><label id="t-licTo">Platí do</label><input id="reg-license-to" type="text" readonly placeholder="Vyberte datum" onclick="openDatePicker(this)" style="cursor:pointer;"></div>
      </div>
      <div class="ff" style="margin-top:9px;margin-bottom:0;"><label id="t-licCat">Kategorie ŘP</label>
        <select id="reg-license-group"><option value="A2" id="t-catA2">A2 – do 35 kW</option><option value="A" id="t-catA">A – bez omezení výkonu</option></select>
      </div>
    </div>
    <div class="reg-step" id="reg-step-4">
      <div class="reg-step-title" id="t-s4t">✅ Krok 4 / 4 – Souhlasy</div>
      <div class="reg-step-sub" id="t-s4s">Přečtěte si a odsouhlaste podmínky</div>
      <div style="display:flex;flex-direction:column;gap:12px;margin-bottom:4px;">
        <label style="display:flex;align-items:flex-start;gap:9px;font-size:13px;font-weight:500;cursor:pointer;color:var(--g600);">
          <input id="reg-terms" type="checkbox" style="width:18px;height:18px;accent-color:var(--green);flex-shrink:0;margin-top:2px;"> <span id="t-agreeTerms">Souhlasím s\u00a0<span style="color:var(--gd);text-decoration:underline;">obchodními podmínkami</span></span>
        </label>
        <label style="display:flex;align-items:flex-start;gap:9px;font-size:13px;font-weight:500;cursor:pointer;color:var(--g600);">
          <input id="reg-gdpr" type="checkbox" style="width:18px;height:18px;accent-color:var(--green);flex-shrink:0;margin-top:2px;"> <span id="t-agreeGDPR">Souhlasím se zpracováním osobních údajů (GDPR)</span>
        </label>
        <label style="display:flex;align-items:flex-start;gap:9px;font-size:13px;font-weight:500;cursor:pointer;color:var(--g600);">
          <input id="reg-newsletter" type="checkbox" style="width:18px;height:18px;accent-color:var(--green);flex-shrink:0;margin-top:2px;"> <span id="t-agreeNews">Chci dostávat nabídky a novinky e-mailem</span>
        </label>
        <label style="display:flex;align-items:flex-start;gap:9px;font-size:13px;font-weight:500;cursor:pointer;color:var(--g600);">
          <input id="reg-photos" type="checkbox" style="width:18px;height:18px;accent-color:var(--green);flex-shrink:0;margin-top:2px;"> <span id="t-agreePhoto">Souhlasím s pořizováním fotografií pro marketing</span>
        </label>
      </div>
    </div>
  </div>
  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="reg-next-btn" onclick="regNext()">Pokračovat →</button>
  </div>`;

Templates['s-docs'] = `  <div class="docs-hdr">
    <div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div>
    <h2>Moje doklady 📋</h2><p>Před první rezervací – stačí jednou</p>
  </div>
  <div style="margin:12px 20px 0;background:rgba(249,115,22,.1);border:2px solid rgba(249,115,22,.3);border-radius:var(--r);padding:13px;display:flex;gap:11px;">
    <div style="font-size:21px;flex-shrink:0;">⚠️</div>
    <div style="font-size:13px;color:#9a3412;font-weight:600;line-height:1.5;">Pro rezervaci motorky jsou nutné oba doklady. Data z dokladů se automaticky uloží do vašeho profilu.</div>
  </div>
  <div style="margin:10px 20px 0;background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.2);border-radius:var(--rsm);padding:11px 13px;">
    <div style="font-size:13px;font-weight:700;color:#b91c1c;margin-bottom:3px;">⚠️ Bez nahraných dokladů</div>
    <div style="font-size:12px;color:#dc2626;line-height:1.6;">Motorku lze rezervovat, ale <strong>kód k otevření boxu</strong> s klíčem obdržíte až po ověření dokladů. Doporučujeme nahrát předem.</div>
  </div>
  <div style="padding:14px 20px 0;">
    <button class="btn-g" onclick="openDocsProfileScan()">📷 Naskenovat doklady kamerou</button>
    <div style="margin-top:10px;"><button class="btn-out" onclick="handleDocUp()">📁 Nahrát z galerie</button></div>
  </div>
  <div class="doc-area" id="doc-area-wrap" style="display:none;">
    <div class="doc-prev" id="doc-prev"></div>
  </div>`;

Templates['s-doc-scan'] = `  <div class="scan-screen">
    <div class="scan-hdr">
      <div class="back-row" onclick="scanClose()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div>
      <h2><span id="scan-doc-icon">🪪</span> Skenování dokladů</h2>
      <p id="scan-doc-label">Občanský průkaz – přední strana</p>
      <div class="scan-progress-bar">
        <div class="scan-prog-dot cur" id="scan-dot-0"></div>
        <div class="scan-prog-dot" id="scan-dot-1"></div>
        <div class="scan-prog-dot" id="scan-dot-2"></div>
        <div class="scan-prog-dot" id="scan-dot-3"></div>
        <span id="scan-progress" style="font-size:11px;color:rgba(255,255,255,.5);margin-left:8px;">1 / 4</span>
      </div>
    </div>
    <div class="scan-camera-wrap">
      <video id="scan-video" autoplay playsinline muted></video>
      <div class="scan-overlay" id="scan-overlay">
        <div class="scan-frame">
          <div class="scan-corner tl"></div>
          <div class="scan-corner tr"></div>
          <div class="scan-corner bl"></div>
          <div class="scan-corner br"></div>
        </div>
      </div>
      <div id="scan-preview" class="scan-preview" style="display:none;"></div>
      <div id="scan-hint" class="scan-hint">Umístěte přední stranu OP do rámečku</div>
      <div class="scan-rotate-hint" style="position:absolute;bottom:8px;left:50%;transform:translateX(-50%);color:rgba(255,255,255,.5);font-size:11px;font-weight:600;z-index:5;">📱 Držte telefon na výšku, doklad na šířku</div>
      <div id="scan-status" class="scan-status scan-status-ready">Zaměřte doklad do rámečku</div>
    </div>
    <div class="scan-actions">
      <button class="scan-btn-capture" onclick="scanCapture()">
        <div class="scan-btn-ring"></div>
      </button>
      <button class="scan-btn-skip" onclick="scanSkip()">Přeskočit →</button>
    </div>
    <div class="scan-info">
      <div class="scan-info-item">🔒 Zabezpečené rozpoznávání</div>
      <div class="scan-info-item">📱 Data uložena v telefonu</div>
      <div class="scan-info-item">🇪🇺 EU GDPR compliant</div>
    </div>
  </div>`;

