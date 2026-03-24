// ===== TEMPLATES-SOS-PAYMENT.JS – SOS payment, replacement & done templates =====
// Split from templates-res-sos.js (lines 146-296)

// ===== SOS PLATEBNÍ BRÁNA (Stripe LIVE) — zaviněná nehoda =====
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

    <!-- Stripe info -->
    <div style="background:#fff;border-radius:var(--r);padding:16px;box-shadow:var(--shadow);margin-bottom:12px;">
      <div style="display:flex;align-items:center;justify-content:center;gap:10px;margin-bottom:14px;">
        <svg width="60" height="25" viewBox="0 0 60 25" fill="none"><rect width="60" height="25" rx="4" fill="#635BFF"/><text x="30" y="17" text-anchor="middle" fill="#fff" font-family="sans-serif" font-size="11" font-weight="700">stripe</text></svg>
        <span style="background:#1a1f36;color:#fff;border-radius:4px;padding:3px 8px;font-size:10px;font-weight:800;">VISA</span>
        <span style="background:#eb001b;color:#fff;border-radius:4px;padding:3px 8px;font-size:10px;font-weight:800;">MC</span>
      </div>
      <div style="font-size:12px;color:var(--g400);text-align:center;line-height:1.7;">
        Po kliknutí na <strong>Zaplatit</strong> budete přesměrováni na zabezpečenou platební stránku Stripe.
      </div>
      <div id="sos-pay-error" style="display:none;margin-top:10px;padding:8px 12px;background:#fee2e2;border-radius:var(--rsm);font-size:12px;font-weight:600;color:#b91c1c;"></div>
    </div>

    <button id="sos-pay-btn" onclick="sosPaymentSubmit()"
      style="width:100%;background:#b91c1c;color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(185,28,28,.3);">
      💳 Zaplatit přes Stripe
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
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-bottom:8px;">
        <div style="position:relative;"><label style="font-size:11px;font-weight:600;color:var(--g400);margin-bottom:2px;display:block;">Obec / město</label><input type="text" id="sos-repl-city" placeholder="např. Humpolec, Hojanivice" oninput="showCitySuggestionsFor(this,'sos-repl');sosReplCalcDelivery()" onchange="sosReplCalcDelivery()" autocomplete="off" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;"><div id="sos-repl-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div><label style="font-size:11px;font-weight:600;color:var(--g400);margin-bottom:2px;display:block;">PSČ</label><input type="text" id="sos-repl-zip" placeholder="PSČ" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;"></div>
      </div>
      <div style="position:relative;"><label style="font-size:11px;font-weight:600;color:var(--g400);margin-bottom:2px;display:block;">Ulice a č.p. / č.o.</label><input type="text" id="sos-repl-address" placeholder="např. Vodičkova 36, Mezná 9" oninput="showAddrSuggestions(this,'sos-repl')" autocomplete="off" style="width:100%;box-sizing:border-box;padding:10px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;"><div id="sos-repl-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      <button onclick="sosReplFillGPS()" style="margin-top:8px;background:var(--gp);color:var(--gd);border:1px solid var(--green);border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:11px;font-weight:700;cursor:pointer;">📍 Použít mou aktuální polohu</button>
      <div id="sos-repl-delivery-calc" style="display:none;font-size:11px;color:var(--g400);margin-top:6px;font-weight:600;"></div>
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
