// ===== TEMPLATES-BOOKING-FORM.JS – Booking form (s-booking) steps 1-4 =====
// Steps 5-7, price summary, consents → templates-booking-form2.js

Templates['s-booking'] = `  <div class="topbar"><div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">Zpět</div></div><h2 id="t-bkTitle">Rezervace motorky</h2><p id="t-bkSub">Vyplňte formulář pro rezervaci</p></div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">1</div> <span id="t-bkStep1">Motorka</span></div>
    <div class="sel-m"><div class="sel-img"><img id="b-img" src=""></div><div style="flex:1;min-width:0;"><div style="font-size:13px;font-weight:800;color:var(--black);" id="b-name"></div><div style="font-size:11px;color:var(--g400);font-weight:600;margin-top:2px;">od 2 600 Kč/den · záloha neúčtována</div><div style="font-size:11px;color:var(--gd);font-weight:600;margin-top:3px;" id="b-branch-info"></div></div><div class="chng" id="t-bkChange" onclick="goTo('s-search')">Změnit</div></div>
  </div>
  <div class="bcard" id="b-date-section">
    <div class="bcard-h"><div class="sdot">2</div> <span id="t-bkStep2">Datum</span></div>
    <!-- Date summary (shown when coming from detail with dates) -->
    <div id="b-date-summary" style="display:none;">
      <div style="display:flex;gap:10px;margin-bottom:8px;">
        <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);cursor:pointer;">
          <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;" id="t-bkPickup">Vyzvednutí</div>
          <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="b-od-txt" onclick="event.stopPropagation();showBookingCal()">—</div>
        </div>
        <div style="flex:1;background:var(--gp);border-radius:var(--rsm);padding:11px 14px;border:2px solid var(--green);cursor:pointer;">
          <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;" id="t-bkReturn">Vrácení</div>
          <div style="font-size:15px;font-weight:800;color:var(--gd);margin-top:3px;" id="b-do-txt" onclick="event.stopPropagation();showBookingCal()">—</div>
        </div>
      </div>
      <div style="text-align:center;font-size:11px;color:var(--g400);font-weight:500;" id="t-bkCalHint1">Klikněte na datum pro výběr v kalendáři</div>
      <div style="text-align:center;"><button id="t-bkOpenCal" onclick="showBookingCal()" style="background:none;border:none;color:var(--green);font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;padding:4px 0;">📅 Otevřít kalendář</button></div>
    </div>
    <!-- Calendar (shown when going directly to booking or on "Změnit termín") -->
    <div id="b-cal-wrap" style="display:none;">
      <div style="font-size:11px;color:var(--g400);font-weight:500;margin-bottom:6px;text-align:center;" id="t-bkCalHint2">Pro výběr jednoho dne klikněte na stejný den dvakrát</div>
      <div class="cal-mr"><button class="cal-ar" onclick="prevMonthB()">‹</button><div class="cal-mn" id="b-month-name">Únor 2026</div><button class="cal-ar" onclick="nextMonthB()">›</button></div>
      <div class="cal-hdr"><div class="cal-dn">Po</div><div class="cal-dn">Út</div><div class="cal-dn">St</div><div class="cal-dn">Čt</div><div class="cal-dn">Pá</div><div class="cal-dn">So</div><div class="cal-dn">Ne</div></div>
      <div class="cal-g" id="b-cal"></div>
      <div class="cal-leg"><div class="leg-i"><div class="leg-d" style="background:var(--green)"></div><span id="t-bkLegFree">Volné</span></div><div class="leg-i"><div class="leg-d" style="background:var(--dark)"></div><span id="t-bkLegOcc">Obsazené</span></div><div class="leg-i"><div class="leg-d" style="background:#fff;border:1px solid #d1d5db;"></div><span id="t-bkLegUnconf">Nepotvrzené</span></div></div>
      <div id="b-cal-price" style="display:none;margin-top:12px;background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);padding:12px 14px;text-align:center;">
        <div style="font-size:10px;font-weight:700;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;" id="t-bkTotalLabel">Celková cena</div>
        <div style="font-size:22px;font-weight:900;color:var(--gd);margin-top:4px;" id="b-cal-price-val">0 Kč</div>
        <div style="font-size:10px;color:var(--g400);margin-top:2px;" id="t-bkNoVAT">Cena bez DPH, nejsme plátci</div>
      </div>
    </div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">3</div> <span id="t-bkStep3">Čas vyzvednutí</span></div>
    <div style="font-size:11px;color:var(--g400);font-weight:600;margin-bottom:8px;" id="t-bkTimeDesc">Vyberte čas, kdy si motorku vyzvednete / chcete přistavit.</div>
    <div id="booking-time-grid"></div>
  </div>
  <div class="bcard">
    <div class="bcard-h"><div class="sdot">4</div> <span id="t-bkStep4">Kontaktní údaje</span></div>
    <div id="contact-collapsed" onclick="toggleContactDetails()" style="display:flex;align-items:center;justify-content:space-between;padding:11px;background:var(--gp);border-radius:var(--rsm);border:2px solid var(--green);cursor:pointer;">
      <div style="display:flex;align-items:center;gap:10px;">
        <div id="contact-initials-box" style="width:36px;height:36px;background:var(--green);border-radius:10px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:14px;font-weight:900;">–</div>
        <div><div id="contact-name-preview" style="font-size:14px;font-weight:800;color:var(--black);">Načítání...</div><div style="font-size:11px;color:var(--g400);margin-top:1px;" id="t-bkProfileNote">Údaje z profilu · klikněte pro úpravu</div></div>
      </div>
      <div id="contact-arrow" style="font-size:18px;color:var(--gd);transition:transform .25s;">›</div>
    </div>
    <div id="b-license-info" style="margin-top:8px;padding:8px 11px;background:var(--gp);border-radius:var(--rsm);display:none;"></div>
    <div id="contact-expanded" style="display:none;margin-top:10px;">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:9px;">
        <div class="ff" style="margin:0;"><label id="t-bkName">Jméno a příjmení</label><input type="text" id="b-contact-name" value=""></div>
        <div class="ff" style="margin:0;position:relative;"><label id="t-bkCity">Obec / město</label><input type="text" id="b-contact-city" list="cz-city-list" value="" oninput="showCitySuggestionsFor(this,'b-contact')" autocomplete="off"><div id="b-contact-city-suggestions" class="addr-suggestions" style="display:none;"></div></div>
      </div>
      <div style="display:grid;grid-template-columns:2fr 1fr;gap:9px;margin-top:9px;">
        <div class="ff" style="margin:0;position:relative;"><label id="t-bkStreet">Ulice a č.p. / č.o.</label><input type="text" id="b-contact-street" value="" oninput="showAddrSuggestions(this,'b-contact')" autocomplete="off"><div id="b-contact-addr-suggestions" class="addr-suggestions" style="display:none;"></div></div>
        <div class="ff" style="margin:0;"><label id="t-bkZip">PSČ</label><input type="text" id="b-contact-zip" list="cz-zip-list" value=""></div>
      </div>
      <div class="ff" style="margin-top:9px;"><label id="t-bkCountry">Stát</label><select id="b-contact-country" style="width:100%;border:2px solid var(--g200);border-radius:var(--rsm);padding:12px 14px;font-size:14px;font-family:var(--font);outline:none;background:var(--g100);color:var(--black);font-weight:500;"><option id="t-bkCZ" selected>Česká republika</option><option id="t-bkSK">Slovensko</option><option id="t-bkDE">Německo</option><option id="t-bkAT">Rakousko</option><option id="t-bkPL">Polsko</option><option id="t-bkOther">Jiné</option></select></div>
      <div class="ff" style="margin-top:9px;"><label id="t-bkEmail">E-mail</label><input type="email" id="b-contact-email" value=""></div>
      <div class="ff"><label id="t-bkPhone">Telefon</label><input type="tel" id="b-contact-phone" value=""></div>
    </div>
  </div>` +
// Continue in templates-booking-form2.js
(typeof _BOOKING_FORM_PART2 !== 'undefined' ? _BOOKING_FORM_PART2 : '');
