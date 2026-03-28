// ===== MotoGo24 Web — Stránka Rezervace: route + form + events =====
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {}, appliedCodes: [], discountAmt: 0 };

MG.route('/rezervace', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'REZERVACE']);
  var hash = window.location.hash || '';
  var mp = ''; var mm = hash.match(/[?&]moto=([^&]+)/);
  if(mm) mp = decodeURIComponent(mm[1]);
  var preDelivery = /[?&]delivery=1/.test(hash);
  var preStart = ''; var ms = hash.match(/[?&]start=([^&]+)/);
  if(ms) preStart = decodeURIComponent(ms[1]);
  var preEnd = ''; var me = hash.match(/[?&]end=([^&]+)/);
  if(me) preEnd = decodeURIComponent(me[1]);

  // ===== RESUME FLOW: ?resume=BOOKING_ID (from QR code or abandoned email) =====
  var resumeId = ''; var mResume = hash.match(/[?&]resume=([^&]+)/);
  if(mResume) resumeId = decodeURIComponent(mResume[1]);

  if(resumeId){
    app.innerHTML = '<main id="content"><div class="container">' + bc +
      '<div class="ccontent pcontent"><h1>Dokončení rezervace</h1>' +
      '<div id="rez-form"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervaci...</div></div>' +
      '</div></div></main>';

    try {
      var resumeRes = await window.sb.rpc('get_web_booking_resume', { p_booking_id: resumeId });
      if(resumeRes.error || (resumeRes.data && resumeRes.data.error)){
        document.getElementById('rez-form').innerHTML =
          '<div style="text-align:center;padding:2rem 0">' +
          '<div style="font-size:3rem;margin-bottom:1rem">&#9888;</div>' +
          '<h2>Rezervace nenalezena</h2>' +
          '<p>' + (resumeRes.data && resumeRes.data.error ? resumeRes.data.error : 'Rezervace již byla dokončena nebo zrušena.') + '</p>' +
          '<p style="margin-top:1rem"><a class="btn btngreen" href="#/rezervace">Vytvořit novou rezervaci</a></p></div>';
        return;
      }

      var bd = resumeRes.data;
      MG._rez = {
        startDate: bd.start_date ? bd.start_date.split('T')[0] : null,
        endDate: bd.end_date ? bd.end_date.split('T')[0] : null,
        motos: [{ id: bd.moto_id, model: bd.moto_model }],
        motoId: bd.moto_id,
        allBookings: {},
        appliedCodes: [],
        discountAmt: 0,
        bookingId: bd.booking_id,
        userId: bd.user_id,
        bookingAmount: bd.total_price,
        _isResume: true,
        _docsValidated: bd.has_id_number && bd.has_license_number,
        _docNumber: bd.has_id_number ? '(vyplněno)' : '',
        _licenseNumber: bd.has_license_number ? '(vyplněno)' : '',
        formData: {
          motoId: bd.moto_id, name: bd.customer_name || '', email: bd.customer_email || '',
          phone: bd.customer_phone || '', street: '', city: '', zip: '', country: 'Česká republika',
          extras: [], appliedCodes: [], discountAmt: 0, deliveryAddr: null, returnAddr: null
        }
      };

      // Mobile + docs already provided → go straight to Mindee step
      if(MG._isMobile() && MG._rez._docsValidated){
        MG._rezShowMindeeStep();
      } else {
        // Desktop or docs missing → show step 2 (docs + QR + invoice)
        MG._rezShowStep2();
      }
    } catch(e){
      console.error('[REZ] resume error', e);
      document.getElementById('rez-form').innerHTML =
        '<div style="text-align:center;padding:2rem 0">' +
        '<h2>Chyba při načítání rezervace</h2>' +
        '<p>Zkuste to prosím znovu nebo nás kontaktujte.</p>' +
        '<p style="margin-top:1rem"><a class="btn btngreen" href="#/rezervace">Vytvořit novou rezervaci</a></p></div>';
    }
    return;
  }

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent pcontent"><div id="rez-intro"><h1>Rezervace motorky</h1>' +
    '<h3>Jak rezervace funguje?</h3><p>&nbsp;</p>' +
    '<p>Pokud si chcete <strong>půjčit motorku v konkrétním termínu</strong>, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.</p><p>&nbsp;</p>' +
    '<p>V případě, že si chcete <strong>vyzkoušet konkrétní motorku</strong>, vyberte ji ze seznamu.</p><p>&nbsp;</p>' +
    '<p><strong>Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.</strong></p><p>&nbsp;</p></div>' +
    '<div id="rez-moto-select"></div>' +
    '<div id="rez-calendar"></div>' +
    '<div id="rez-date-banner" style="display:none"></div>' +
    '<div id="rez-avail-select" style="display:none"></div>' +
    MG._rezFormHtml() +
    '</div></div></main>';

  MG._rez = { startDate: preStart || null, endDate: preEnd || null, motos: [], motoId: mp, allBookings: {}, appliedCodes: [], discountAmt: 0 };
  var motos = await MG._getMotos();
  MG._rez.motos = motos;

  var sel = document.getElementById('rez-moto-select');
  if(sel){
    var h = '<form class="form-product-select gr2"><div>Vyber motorku:</div><select id="rez-moto-dropdown">' +
      '<option value="">libovolná dostupná motorka v mém termínu</option>';
    motos.forEach(function(m){ h += '<option value="'+m.id+'"'+(m.id===mp?' selected':'')+'>'+m.model+'</option>'; });
    h += '</select></form>';
    sel.innerHTML = h;
    document.getElementById('rez-moto-dropdown').addEventListener('change', function(){
      MG._rez.motoId = this.value;
      MG._rezResetDates();
      MG._rezLoadCalendar();
    });
  }
  MG._rezInitFormEvents();
  await MG._rezLoadCalendar();

  // If dates were pre-filled from URL, show banner and update price
  if(preStart && preEnd){
    MG._rezUpdateBanner();
    MG._rezUpdatePrice();
  }

  // Pre-fill delivery if ?delivery=1
  if(preDelivery){
    var dc = document.getElementById('rez-delivery');
    if(dc){ dc.checked = true; dc.dispatchEvent(new Event('change')); }
  }
});

// ===== TOOLTIP HELPER =====
MG._tip = function(text){ return ' <span class="ctooltip">&#9432;<span class="ctooltiptext">'+text+'</span></span>'; };
MG._reqTip = function(){ return ' <span class="ctooltip" style="color:#c00;font-size:.75rem">*<span class="ctooltiptext">Toto pole je povinné</span></span>'; };

// ===== STATIC FORM HTML =====
MG._rezFormHtml = function(){
  return '<div id="rez-form"><p>&nbsp;</p>' +
    '<input type="text" id="rez-name" placeholder="* Jméno a příjmení" required title="Toto pole je povinné" autocomplete="name">' +
    '<div class="gr2"><input type="text" id="rez-street" placeholder="* Ulice, č.p." required autocomplete="street-address">' +
    '<input type="text" id="rez-zip" placeholder="* PSČ" required autocomplete="postal-code"></div>' +
    '<div class="gr2"><input type="text" id="rez-city" placeholder="* Město" required autocomplete="address-level2">' +
    '<input type="text" id="rez-country" placeholder="* Stát" value="Česká republika" required autocomplete="country-name"></div>' +
    '<div class="gr2"><input type="email" id="rez-email" placeholder="* E-mail" required autocomplete="email">' +
    '<input type="tel" id="rez-phone" placeholder="* Telefon (+420XXXXXXXXX)" required autocomplete="tel" pattern="^\\+\\d{12,15}$"></div>' +
    '<div class="gr2 voucher-code"><input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">' +
    '<div><span class="btn btngreen-small" onclick="MG._applyVoucher()">UPLATNIT</span></div></div>' +
    '<div id="rez-applied-codes"></div>' +
    '<div id="rez-voucher-msg" style="font-size:.85rem;margin:-.5rem 0 .75rem"></div>' +
    '<div class="dfc pickup"><div>* Čas převzetí nebo přistavení motorky'+MG._reqTip()+'</div><input type="time" id="rez-pickup-time" required title="Toto pole je povinné"></div>' +
    '<div class="checkboxes">' +
    // Výbava spolujezdce
    '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Výbava pro spolujezdce <strong>+ 690 Kč</strong>' +
    MG._tip('Výbavu pro spolujezdce zaškrtněte jen v případě, že pojedete ve dvou a spolujezdec si výbavu potřebuje zapůjčit. Velikost si vyzkouší na místě. Základní výbava pro spolujezdce zahrnuje helmu, bundu, rukavice a kuklu.') +
    '</label></div>' +
    // Boty řidič
    '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče <strong>+ 290 Kč</strong>' +
    MG._tip('Motocyklové boty nejsou součástí základní výbavy. V případě zájmu vám rádi zapůjčíme boty ve vaší velikosti.') +
    '</label></div>' +
    // Boty spolujezdec
    '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce <strong>+ 290 Kč</strong></label></div>' +
    // Přistavení motorky
    '<div><input type="checkbox" id="rez-delivery"><label for="rez-delivery">Přistavení motorky jinam <span id="rez-delivery-price"></span>' +
    MG._tip('Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (40 Kč/km, tam i zpět).') +
    '</label></div>' +
    '<div id="rez-delivery-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">' +
    '<input type="text" id="rez-delivery-address" placeholder="Zadejte adresu přistavení">' +
    '<div style="display:flex;gap:6px;margin-top:.5rem"><button type="button" onclick="MG._openWebMapPicker(\'delivery\')" style="padding:6px 12px;background:#fff;border:1px solid #ccc;border-radius:6px;font-size:.85rem;cursor:pointer">🗺️ Vybrat na mapě</button></div>' +
    '<div id="rez-delivery-confirm" style="display:none;margin-top:.5rem"><input type="checkbox" id="rez-delivery-confirmed"><label for="rez-delivery-confirmed" style="font-size:.85rem;font-weight:600;color:#1a8c1a"> ✅ Potvrdit adresu přistavení</label></div>' +
    '<div style="margin-top:.5rem"><input type="checkbox" id="rez-return-same-as-delivery" checked><label for="rez-return-same-as-delivery" style="font-size:.85rem"> Vrátit motorku na stejné adrese</label></div>' +
    '<div><input type="checkbox" id="rez-own-gear"><label for="rez-own-gear" style="font-size:.85rem"> Mám vlastní výbavu</label></div>' +
    '</div>' +
    // Vrácení motorky jinde
    '<div><input type="checkbox" id="rez-return-other"><label for="rez-return-other">Vrácení motorky na jiné adrese <span id="rez-return-price"></span>' +
    MG._tip('Motorku nemusíte vracet zpět v místě motopůjčovny, rádi si ji u vás vyzvedneme. Do ceny za vrácení motorky jinde se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (40 Kč/km, tam i zpět).') +
    '</label></div>' +
    '<div id="rez-return-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">' +
    '<input type="text" id="rez-return-address" placeholder="Zadejte adresu vrácení">' +
    '<div style="display:flex;gap:6px;margin-top:.5rem"><button type="button" onclick="MG._openWebMapPicker(\'return\')" style="padding:6px 12px;background:#fff;border:1px solid #ccc;border-radius:6px;font-size:.85rem;cursor:pointer">🗺️ Vybrat na mapě</button></div>' +
    '<div id="rez-return-confirm" style="display:none;margin-top:.5rem"><input type="checkbox" id="rez-return-confirmed"><label for="rez-return-confirmed" style="font-size:.85rem;font-weight:600;color:#1a8c1a"> ✅ Potvrdit adresu vrácení</label></div>' +
    '<div class="dfc" style="margin-top:.5rem"><div>Čas vrácení</div><input type="time" id="rez-return-time" style="max-width:200px"></div>' +
    '</div>' +
    '</div>' +
    '<textarea id="rez-note" placeholder="Poznámka – uveďte preferovanou velikost výbavy (helma, bunda, rukavice, kalhoty)"></textarea>' +
    '<div class="checkboxes">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required checked><div>* Souhlasím s <a href="#/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr" checked><div>Souhlasím se <a href="#/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing" checked><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo" checked><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>' +
    '<div id="rez-price-preview"></div>' +
    '<div class="text-center" style="margin-top:1rem"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div>' +
    '</div>';
};

// ===== INIT FORM EVENTS (called once) =====
MG._rezInitFormEvents = function(){
  // Delivery panel toggle
  var dc = document.getElementById('rez-delivery');
  if(dc) dc.addEventListener('change',function(){
    var p=document.getElementById('rez-delivery-panel');
    if(p) p.style.display=this.checked?'block':'none';
    // When delivery unchecked, also uncheck return-same-as-delivery
    if(!this.checked){
      var rs=document.getElementById('rez-return-same-as-delivery');
      if(rs) rs.checked=true;
    }
    MG._rezUpdatePrice();
  });
  // Return other panel toggle
  var retO = document.getElementById('rez-return-other');
  if(retO) retO.addEventListener('change',function(){
    var p=document.getElementById('rez-return-panel');
    if(p) p.style.display=this.checked?'block':'none';
    // Uncheck return-same-as-delivery when separate return address
    var rs=document.getElementById('rez-return-same-as-delivery');
    if(rs && this.checked) rs.checked=false;
    MG._rezUpdatePrice();
  });
  // Return same as delivery toggle
  var rSame = document.getElementById('rez-return-same-as-delivery');
  if(rSame) rSame.addEventListener('change',function(){
    if(this.checked){
      var ro=document.getElementById('rez-return-other');
      if(ro){ ro.checked=false; var p=document.getElementById('rez-return-panel'); if(p) p.style.display='none'; }
    }
    MG._rezUpdatePrice();
  });
  // Own gear: clear note placeholder
  var og = document.getElementById('rez-own-gear');
  if(og) og.addEventListener('change',function(){
    var n=document.getElementById('rez-note');
    if(n) n.placeholder = this.checked ? 'Poznámka' : 'Poznámka – uveďte preferovanou velikost výbavy (helma, bunda, rukavice, kalhoty)';
  });
  // Extras price recalc
  ['rez-eq-passenger','rez-eq-boots-rider','rez-eq-boots-passenger'].forEach(function(id){
    var cb = document.getElementById(id);
    if(cb) cb.addEventListener('change', function(){ MG._rezUpdatePrice(); });
  });
};

// Calendar, pricing, vouchers, map → pages-rezervace-calendar.js, pages-rezervace-pricing.js
