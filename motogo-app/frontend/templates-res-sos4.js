// ===== TEMPLATES-RES-SOS4.JS – Replacement motorcycle selection (s-sos-replacement) =====
// Zákazník, který zavinil nehodu a chce náhradní moto, musí vybrat motorku, adresu přistavení a zaplatit.

Templates['s-sos-replacement'] = `  <div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1a2e22,#2d5a3f);">
    <div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">←</div><div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zpět</div></div>
    <div style="font-size:28px;margin-bottom:8px;">🏍️</div>
    <h2 style="color:#fff;font-size:22px;font-weight:900;">Náhradní motorka</h2>
    <p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Vyberte motorku a adresu přistavení</p>
  </div>

  <div style="padding:14px 20px 0;">
    <!-- Info box: zaviněná nehoda = poplatek -->
    <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--r);padding:12px 14px;margin-bottom:14px;">
      <div style="font-size:12px;font-weight:700;color:#b91c1c;line-height:1.7;">
        ⚠️ Nehoda byla vaší chybou – náhradní motorka a přistavení jsou <strong>za poplatek</strong>.<br>
        Cena pronájmu dle ceníku motorky + přistavení 1 000 Kč + 20 Kč/km.
      </div>
    </div>

    <!-- Step 1: Výběr motorky -->
    <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">1. Vyberte motorku</div>
    <div id="sos-moto-list" style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px;">
      <div style="text-align:center;padding:20px;color:var(--g400);font-size:13px;">Načítám dostupné motorky...</div>
    </div>

    <!-- Step 2: Adresa přistavení -->
    <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">2. Adresa přistavení</div>
    <div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:16px;">
      <div class="ff" style="margin-bottom:8px;">
        <label style="font-size:12px;font-weight:700;">Ulice a číslo popisné</label>
        <input type="text" id="sos-repl-street" placeholder="např. Vodičkova 30" style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:13px;font-family:var(--font);outline:none;">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
        <div class="ff">
          <label style="font-size:12px;font-weight:700;">Město</label>
          <input type="text" id="sos-repl-city" placeholder="Praha" style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:13px;font-family:var(--font);outline:none;">
        </div>
        <div class="ff">
          <label style="font-size:12px;font-weight:700;">PSČ</label>
          <input type="text" id="sos-repl-zip" placeholder="110 00" style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:13px;font-family:var(--font);outline:none;">
        </div>
      </div>
      <div class="ff" style="margin-top:8px;">
        <label style="font-size:12px;font-weight:700;">Poznámka k přistavení (volitelné)</label>
        <input type="text" id="sos-repl-note" placeholder="např. Parkoviště za budovou, zvonek 3B" style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:10px 12px;font-size:13px;font-family:var(--font);outline:none;">
      </div>
      <button onclick="sosReplUseGPS()" style="margin-top:10px;background:var(--g100);border:2px solid var(--g200);border-radius:50px;padding:10px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;display:flex;align-items:center;gap:6px;color:var(--g600);">
        📍 Použít aktuální GPS polohu
      </button>
    </div>

    <!-- Step 3: Souhrn a platba -->
    <div id="sos-repl-summary" style="display:none;background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin-bottom:16px;">
      <div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">3. Souhrn objednávky</div>
      <div id="sos-repl-summary-content" style="font-size:13px;font-weight:600;line-height:1.8;color:var(--black);"></div>
      <div style="border-top:1px solid var(--g200);margin-top:10px;padding-top:10px;">
        <div style="display:flex;justify-content:space-between;font-size:15px;font-weight:900;">
          <span>Celkem k úhradě:</span>
          <span id="sos-repl-total" style="color:var(--green);">—</span>
        </div>
        <div style="font-size:11px;color:var(--g400);margin-top:2px;">Platba kartou při potvrzení objednávky</div>
      </div>
    </div>

    <!-- CTA -->
    <button id="sos-repl-confirm-btn" onclick="sosReplConfirmOrder()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font);font-size:15px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(116,251,113,.4);margin-bottom:14px;opacity:.5;pointer-events:none;">
      💳 Potvrdit a zaplatit
    </button>
    <div style="font-size:11px;color:var(--g400);text-align:center;line-height:1.5;margin-bottom:20px;">
      Po potvrzení objednávky bude motorka přistavena co nejdříve.<br>
      MotoGo24 asistent vás bude kontaktovat s upřesněním doby přistavení.
    </div>
  </div>`;
