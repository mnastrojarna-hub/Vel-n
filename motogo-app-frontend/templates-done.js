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
  <div class="rd-card" id="done-google-review" style="display:none;">
    <div style="text-align:center;padding:8px 0;">
      <div style="font-size:28px;margin-bottom:6px;">⭐</div>
      <div style="font-size:14px;font-weight:800;color:var(--black);margin-bottom:4px;">Jak se v\u00e1m j\u00edzda l\u00edbila?</div>
      <div style="font-size:12px;color:var(--g400);margin-bottom:12px;">Ohodno\u0165te n\u00e1s na Google \u2013 pom\u016f\u017eete dal\u0161\u00edm jezdc\u016fm!</div>
      <button onclick="_openGoogleReview()" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:13px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:8px;">
        \u2b50 Ohodnotit na Google
      </button>
      <button onclick="document.getElementById('done-google-review').style.display='none'" style="background:none;border:none;font-family:var(--font);font-size:12px;font-weight:600;color:var(--g400);cursor:pointer;">Pozd\u011bji</button>
    </div>
  </div>
  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="t-bookAgain" onclick="openDetail('benelli');goTo('s-detail');showT('🏍️','Rezervace','Vyberte termín pro stejnou motorku')">🔁 Znovu rezervovat</button>
  </div>
  <div style="height:10px;"></div>`;

