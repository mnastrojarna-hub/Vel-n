// ===== TEMPLATES-RES.JS – Reservation list (s-res) & Reservation detail (s-res-detail) =====
Templates['s-res'] = `  <div class="res-hdr" style="position:relative;"><div class="h-av" onclick="goTo('s-profile')" title="Profil" style="position:absolute;right:20px;top:54px;width:36px;height:36px;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:7px;cursor:pointer;z-index:20;"><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:12px;height:2px;background:#fff;border-radius:2px;"></div><div style="width:16px;height:2px;background:#fff;border-radius:2px;"></div></div>
    <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px;">
      <img src="${IMG_BASE64_0}" style="width:96px;height:96px;border-radius:22px;object-fit:cover;background:var(--green);" alt="MotoGo24">
      <div>
        <div style="font-size:24px;font-weight:900;color:#fff;letter-spacing:-.5px;line-height:1;">MOTO GO 24</div>
        <div id="t-resRentalTag" style="font-size:10px;font-weight:700;color:rgba(255,255,255,.45);letter-spacing:3px;text-transform:uppercase;margin-top:4px;">P\u016fj\u010dovna motorek</div>
      </div>
    </div>
    <h2 id="t-myRes">Moje rezervace</h2><p id="t-resMgmt">Spr\u00e1va v\u0161ech rezervac\u00ed</p></div>
  <div style="padding:9px 20px 4px;display:flex;gap:7px;overflow-x:auto;scrollbar-width:none;">
    <div class="chip active" id="t-resAll" onclick="filterRes(this,'all')">Vše</div>
    <div class="chip" id="t-resActive" onclick="filterRes(this,'aktivni')">Aktivní</div>
    <div class="chip" id="t-resUpcoming" onclick="filterRes(this,'nadchazejici')">Nadcházející</div>
    <div class="chip" id="t-resDone" onclick="filterRes(this,'dokoncene')">Dokončené</div>
  </div>
  <div style="padding:4px 20px 0;display:flex;gap:8px;align-items:center;">
    <div style="flex:1;position:relative;">
      <select id="res-sort" onchange="resApplySort(this.value)" style="width:100%;padding:7px 28px 7px 10px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:11px;font-weight:700;color:var(--black);background:#fff;appearance:none;-webkit-appearance:none;cursor:pointer;">
        <option value="start_desc">Začátek: nejnovější</option>
        <option value="start_asc">Začátek: nejstarší</option>
        <option value="created_desc">Vytvořeno: nejnovější</option>
        <option value="created_asc">Vytvořeno: nejstarší</option>
        <option value="price_desc">Cena: nejvyšší</option>
        <option value="price_asc">Cena: nejnižší</option>
        <option value="rating_desc">Hodnocení: nejlepší</option>
      </select>
      <div style="position:absolute;right:8px;top:50%;transform:translateY(-50%);pointer-events:none;font-size:10px;color:var(--g400);">▼</div>
    </div>
    <button id="res-filter-toggle" onclick="resToggleExtFilter()" style="padding:7px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:11px;font-weight:700;color:var(--black);background:#fff;cursor:pointer;white-space:nowrap;">⚙ Filtr</button>
  </div>
  <div id="res-ext-filter" style="display:none;padding:6px 20px 0;">
    <div style="background:#fff;border-radius:var(--rsm);padding:10px 12px;border:2px solid var(--g200);">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
        <div>
          <label style="font-size:10px;font-weight:700;color:var(--g400);display:block;margin-bottom:3px;">Pobočka</label>
          <select id="res-filter-branch" onchange="renderMyReservations()" style="width:100%;padding:6px 8px;border:1px solid var(--g200);border-radius:6px;font-family:var(--font);font-size:11px;">
            <option value="">Všechny</option>
          </select>
        </div>
        <div>
          <label style="font-size:10px;font-weight:700;color:var(--g400);display:block;margin-bottom:3px;">Motorka</label>
          <select id="res-filter-moto" onchange="renderMyReservations()" style="width:100%;padding:6px 8px;border:1px solid var(--g200);border-radius:6px;font-family:var(--font);font-size:11px;">
            <option value="">Všechny</option>
          </select>
        </div>
      </div>
      <button onclick="resClearExtFilter()" style="margin-top:6px;padding:5px 12px;border:none;background:var(--g100);border-radius:6px;font-family:var(--font);font-size:10px;font-weight:700;color:var(--g400);cursor:pointer;">Smazat filtry</button>
    </div>
  </div>
  <div style="height:9px;"></div>
  <div id="res-list" style="padding:0 20px;"></div>
  <!-- Dynamic reservation cards rendered by reservations-ui.js -->`;

Templates['s-res-detail'] = `  <div class="rd-hdr">
    <div class="back-row" onclick="histBack()"><div class="bk-c" >←</div><div class="bk-l" id="t-rdBack">Zpět na rezervace</div></div>
    <h2 id="rd-title">Detail rezervace</h2>
    <p id="rd-subtitle">#RES-2026-0043</p>
  </div>
  <div id="rd-banner" class="rd-info-banner rd-banner-info" style="display:none;"></div>
  <div class="rd-card" style="margin-top:10px;">
    <img id="rd-moto-img" class="rd-moto-img" src="https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=80" alt="">
    <div class="rd-section-t" id="t-rdMotoSec">Motorka</div>
    <div class="rd-row"><div class="rd-label" id="t-rdModel">Model</div><div class="rd-value" id="rd-moto-name">BMW R 1200 GS Adventure</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdCat">Kategorie</div><div class="rd-value">Cestovní enduro · A</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdPickup">Vyzvednutí</div><div class="rd-value" id="rd-pickup">22. 2. 2026 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdReturn">Vrácení</div><div class="rd-value" id="rd-return">24. 2. 2026 v 9:00</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdDuration">Délka výpůjčky</div><div class="rd-value" id="rd-duration">2 dny</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdPickupPlace">Místo vyzvednutí</div><div class="rd-value" id="rd-pickup-loc">Mezná 9, 393 01 Mezná</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdReturnPlace">Místo vrácení</div><div class="rd-value" id="rd-return-loc">Mezná 9, 393 01 Mezná</div></div>
  </div>
  <div id="rd-modification" class="rd-card" style="display:none;">
    <div class="rd-section-t">Úprava termínu</div>
    <div id="rd-mod-content"></div>
  </div>
  <div id="rd-extras" class="rd-card" style="display:none;">
    <div class="rd-section-t">Doplňky a slevy</div>
  </div>
  <div class="rd-card">
    <div class="rd-section-t" id="t-rdPaySec">Platba</div>
    <div class="rd-row"><div class="rd-label" id="t-rdDeposit">Záloha</div><div class="rd-value" id="t-rdNoDeposit" style="color:var(--gd)">Neúčtujeme ✓</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdTotal">Celkem</div><div class="rd-value" id="rd-total" style="color:var(--gd);font-size:16px;">5 400 Kč</div></div>
    <div class="rd-row"><div class="rd-label" id="t-rdPayMethod">Způsob platby</div><div class="rd-value" id="rd-pay-method">Platební karta</div></div>
  </div>
  <div id="rd-detail-summary" class="rd-card" style="display:none;">
    <div class="rd-section-t">Kompletní přehled rezervace</div>
  </div>
  <div class="rd-actions" id="rd-actions"></div>
  <div style="height:10px;"></div>`;
