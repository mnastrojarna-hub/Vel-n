Templates['s-done-detail'] = `  <div class="done-hdr">
    <div class="back-row" onclick="histBack()"><div class="bk-c" >←</div><div class="bk-l" id="t-doneBack">Zpět na rezervace</div></div>
    <h2 id="t-doneTitle">Detail proběhlé jízdy</h2>
    <p id="done-sub">#RES-2025-0018</p>
  </div>
  <div class="rd-card" style="margin-top:10px;">
    <img id="done-img" class="rd-moto-img" src="https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=80" alt="">
    <div class="rd-section-t" id="t-doneHistory">Průběh výpůjčky</div>
    <div class="rd-row"><div class="rd-label" id="t-doneMoto">Motorka</div><div class="rd-value" id="done-moto">Benelli TRK 702X</div></div>
    <div class="rd-row"><div class="rd-label" id="t-donePickup">Vyzvednutí</div><div class="rd-value">10. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneReturn">Vrácení</div><div class="rd-value">14. 1. 2025 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneDuration">Délka výpůjčky</div><div class="rd-value">4 dny</div></div>
    <div class="rd-row"><div class="rd-label" id="t-donePickupPlace">Místo vyzvednutí</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneReturnPlace">Místo vrácení</div><div class="rd-value">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-doneTotalPrice">Celková cena</div><div class="rd-value" style="color:var(--gd);font-weight:900;">10 600 Kč</div></div>
  </div>
  <div class="rd-card">
    <div class="rd-section-t" id="t-doneDocs">📄 Doklady ke stažení</div>
    <div class="doc-dl-row" onclick="showT('⬇️','Stahování...','Zálohová faktura.pdf')">
      <div class="doc-dl-icon">🧾</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneAdvInv">Zálohová faktura</div><div class="doc-dl-sub">PDF · 45 kB</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
    <div class="doc-dl-row" onclick="showDigitalProtocol()">
      <div class="doc-dl-icon">📋</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneProtocol">Předávací protokol</div><div class="doc-dl-sub" id="t-doneDigital">Digitální · zobrazit a podepsat</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
    <div class="doc-dl-row" onclick="showT('⬇️','Stahování...','Konečná faktura.pdf')">
      <div class="doc-dl-icon">💰</div>
      <div class="doc-dl-info"><div class="doc-dl-name" id="t-doneFinalInv">Konečná faktura</div><div class="doc-dl-sub">PDF · 52 kB</div></div>
      <div class="doc-dl-actions">
        <button class="doc-dl-btn dl" onclick="event.stopPropagation();showT('⬇️','Stahování...','Uloženo')">⬇️</button>
        <button class="doc-dl-btn sh" onclick="event.stopPropagation();showT('↗️','Sdílení...','Otevírám...')">↗️</button>
      </div>
    </div>
  </div>
  <div class="rd-card" id="done-rating-card">
    <div class="rd-section-t" id="t-doneRating">⭐ Vaše hodnocení</div>
    <div id="done-stars-wrap" style="display:flex;justify-content:center;gap:8px;padding:10px 0;">
      <span class="star-btn" data-v="1" onclick="rateRide(1)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="2" onclick="rateRide(2)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="3" onclick="rateRide(3)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="4" onclick="rateRide(4)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
      <span class="star-btn" data-v="5" onclick="rateRide(5)" style="font-size:32px;cursor:pointer;transition:transform .15s;">★</span>
    </div>
    <div id="done-rating-msg" style="text-align:center;font-size:12px;color:var(--g400);font-weight:600;padding-bottom:4px;"><span id="t-doneTapRate">Klepněte na hvězdičku pro hodnocení</span></div>
  </div>
  <div style="padding:12px 20px 22px;">
    <button class="btn-g" id="t-doneBookAgain" onclick="openDetail('benelli');goTo('s-detail');showT('🏍️','Rezervace','Vyberte termín pro stejnou motorku')">🔁 Znovu rezervovat</button>
  </div>
  <div style="height:10px;"></div>`;
