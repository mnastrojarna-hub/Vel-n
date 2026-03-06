// ===== TEMPLATES-SCREENS-BOOKING.JS – Detail (s-detail), Payment (s-payment), Success (s-success) =====
// Split from original templates-screens.js
// Home & Search templates (s-home, s-search) → templates-screens.js
// Booking form (s-booking) → templates-booking-form.js

Templates['s-detail'] = `  <div class="det-back" onclick="histBack()">←</div>
  <div class="det-img" id="d-img-wrap">
    <div class="det-grad"><div class="det-h2" id="d-name"></div><div class="det-sub" id="d-loc"></div></div>
    <div class="det-nav-btns">
      <button class="det-nav-btn" onclick="detSlide(-1)">‹</button>
      <button class="det-nav-btn" onclick="detSlide(1)">›</button>
    </div>
  </div>
  <div class="det-dots" id="d-dots"></div>
  <div class="det-body">
    <div class="avl-badge" id="d-avl"></div>
    <div style="font-size:12px;color:var(--g400);margin-bottom:8px;font-weight:600;" id="d-branch"></div>
    <p id="d-desc" style="font-size:13px;color:var(--g600);line-height:1.7;margin-bottom:14px;"></p>
    <div id="t-techSpec" style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:8px;">🔧 Technická specifikace</div>
    <div class="spec-grid" id="d-specs" style="margin-bottom:14px;"></div>
    <div id="t-idealUse" style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:8px;">✅ Ideální použití</div>
    <ul class="fl" id="d-feats" style="margin-bottom:14px;"></ul>
    <div id="d-pricing" class="bcard" style="margin:0 0 14px;padding:14px;"></div>
    <div class="bcard" style="margin:0 0 14px;padding:14px;" id="d-cal-card">
      <div id="t-availability" style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">📅 Dostupnost – vyberte termín</div>
      <!-- Date summary (shown when coming from search with dates already selected) -->
      <div id="d-date-summary" style="display:none;">
        <div style="display:flex;gap:10px;margin-bottom:8px;">
          <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);">
            <div id="t-dPickup" style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;">Vyzvednutí</div>
            <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="d-od-txt">—</div>
          </div>
          <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);">
            <div id="t-dReturn" style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;">Vrácení</div>
            <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="d-do-txt">—</div>
          </div>
        </div>
        <div style="text-align:center;"><button id="t-changeDate" onclick="showDetailCal()" style="background:none;border:none;color:var(--green);font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;padding:4px 0;">✏️ Změnit termín</button></div>
      </div>
      <!-- Calendar (shown when browsing detail directly without pre-selected dates) -->
      <div id="d-cal-wrap">
        <div id="t-dCalHint" style="font-size:11px;color:var(--g400);font-weight:500;margin-bottom:6px;text-align:center;">Pro výběr jednoho dne klikněte na stejný den dvakrát</div>
      <div class="cal-mr"><button class="cal-ar" onclick="prevMonthD()">‹</button><div class="cal-mn" id="d-cal-month">Únor 2026</div><button class="cal-ar" onclick="nextMonthD()">›</button></div>
        <div class="cal-hdr"><div class="cal-dn">Po</div><div class="cal-dn">Út</div><div class="cal-dn">St</div><div class="cal-dn">Čt</div><div class="cal-dn">Pá</div><div class="cal-dn">So</div><div class="cal-dn">Ne</div></div>
        <div class="cal-g" id="d-cal"></div>
        <div class="cal-leg"><div class="leg-i"><div class="leg-d" style="background:var(--green)"></div><span id="t-dLegFree">Volné</span></div><div class="leg-i"><div class="leg-d" style="background:var(--dark)"></div><span id="t-dLegOcc">Obsazené</span></div><div class="leg-i"><div class="leg-d" style="background:#fff;border:1px solid #d1d5db;"></div><span id="t-dLegUnconf">Nepotvrzené</span></div></div>
      </div>
      <div id="d-cal-price" style="display:none;margin-top:12px;background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);padding:12px 14px;text-align:center;">
        <div id="t-dTotalLabel" style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;">Celková cena za pronájem</div>
        <div style="font-size:22px;font-weight:900;color:var(--gd);margin-top:4px;" id="d-cal-price-val">0 Kč</div>
        <div id="t-dNoVAT" style="font-size:10px;color:var(--g400);margin-top:2px;">Cena bez DPH, nejsme plátci</div>
      </div>
    </div>
    <div class="bcard" style="margin:0 0 100px;padding:14px;">
      <div id="t-manualTitle" style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">📖 Návod k obsluze</div>
      <div style="display:flex;align-items:center;gap:12px;padding:11px;background:var(--g100);border-radius:var(--rsm);cursor:pointer;" id="d-manual-btn">
        <div style="font-size:28px;">📄</div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:700;" id="d-manual-name">Návod k obsluze</div><div id="t-pdfGuide" style="font-size:11px;color:var(--g400);margin-top:2px;">PDF · Kompletní příručka</div></div>
        <div style="font-size:18px;color:var(--g400);">⬇️</div>
      </div>
    </div>
    <div class="pbar" id="d-pbar"></div>
  </div>
  <div class="sticky-btn"><button class="btn-g" id="d-cta"></button></div>`;

Templates['s-payment'] = `  <div class="topbar"><div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l" id="t-payBack">Zpět</div></div><h2 id="t-payTitle">Platba</h2><p id="t-paySSL">Bezpečná platba – SSL šifrováno</p></div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">💳</div> <span id="t-payMethod">Způsob platby</span></div>
    <div class="pm sel" id="pm-card" onclick="selP('card')"><div class="pmi">💳</div><div style="flex:1;"><div class="pmn" id="t-creditCard">Platební karta</div><div class="pms">Visa, Mastercard</div></div><div class="pmr on" id="pmr-card"></div></div>
    <div class="pm-detail open" id="pmd-card">
      <div class="vc"><div class="vcl">💳</div><div class="vcn">4242 4242 4242 4242</div><div class="vcm"><div><div class="vcml" id="t-cardHolder">Držitel</div><div class="vcmv">JAN NOVÁK</div></div><div><div class="vcml" id="t-cardExpiry">Platnost</div><div class="vcmv">12/27</div></div><div><div class="vcml">CVV</div><div class="vcmv">•••</div></div></div></div>
      <div class="ff"><label id="t-cardNumber">Číslo karty</label><input type="text" value="4242 4242 4242 4242" style="font-family:monospace;letter-spacing:1px;"></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:9px;"><div class="ff"><label id="t-cardExp2">Platnost</label><input type="text" value="12/27"></div><div class="ff"><label>CVV</label><input type="text" value="•••"></div></div>
    </div>
    <div class="pm" id="pm-apple" onclick="selP('apple')"><div class="pmi">📱</div><div style="flex:1;"><div class="pmn">Google Pay</div><div class="pms" id="t-biometric">Biometrické ověření · Android</div></div><div class="pmr" id="pmr-apple"></div></div>
    <div class="pm-detail" id="pmd-apple"><div style="text-align:center;padding:14px 0 6px;"><div style="font-size:38px;margin-bottom:7px;">📱</div><div style="font-size:14px;font-weight:700;color:var(--black);">Google Pay</div><button style="margin-top:12px;background:#000;color:#fff;border:none;border-radius:50px;padding:12px 28px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;" id="apple-pay-btn">📱 Google Pay 0 Kč</button></div></div>

  </div>
  <div style="padding:10px 20px 100px;">
    <div id="t-encryptedPay" style="text-align:center;font-size:11px;color:var(--g400);font-weight:600;margin-bottom:12px;display:flex;align-items:center;justify-content:center;gap:5px;">🔒 Šifrovaná platba · motogo24.vseproweb.com</div>
    <button class="btn-g" id="pay-btn" onclick="doPayment()">Zaplatit 0 Kč →</button>
  </div>`;

Templates['s-success'] = `  <div class="suc-inner">
    <div class="suc-ring">✓</div>
    <div class="suc-h"><span id="t-sucRes">Rezervace</span><br><span id="t-sucConf">Potvrzena!</span></div>
    <div class="suc-p" id="t-sucMsg">Motorka na vás čeká. Potvrzení bylo odesláno e-mailem.</div>
    <div style="background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.4);border-radius:var(--rsm);padding:12px 14px;margin:10px 20px 0;text-align:left;">
      <div style="font-size:12px;font-weight:700;color:#92400e;line-height:1.7;">
        🔐 <strong id="t-secTitle">Zabezpečení motorky:</strong><br>
        <span id="t-secTip1">· Nikdy nenechávejte klíče v zapalování</span><br>
        <span id="t-secTip2">· Vždy zajistěte řídítka zámkem</span><br>
        <span id="t-secTip3">· Za krádež při porušení podmínek zodpovídáte v plné výši</span>
      </div>
    </div>
    <div class="suc-box"><div class="sb-l" id="t-resNum">Číslo rezervace</div><div class="sb-n" id="suc-res-id">#RES-2026-0043</div><div class="sb-row"><div><div class="sbi-l" id="t-sucMoto">Motorka</div><div class="sbi-v">BMW R 1200 GS</div></div><div><div class="sbi-l" id="t-sucFrom">Od</div><div class="sbi-v" id="suc-od">—</div></div><div><div class="sbi-l" id="t-sucTo">Do</div><div class="sbi-v" id="suc-do">—</div></div></div></div>
    <div class="sync-badge"><div class="pulse"></div> <span id="t-syncBadge">Synchronizováno s webem MotoGo24</span></div>
    <button class="btn-g" onclick="goTo('s-res')" id="t-myResBtn" style="width:100%">Moje rezervace →</button>
  </div>`;

