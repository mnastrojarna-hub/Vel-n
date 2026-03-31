// ===== MotoGo24 Web PHP — Stránka Rezervace: init + form + events =====
// Adaptace pro PHP: žádný MG.route(), params z window.REZERVACE_PARAMS, čisté URL
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {}, appliedCodes: [], discountAmt: 0 };

// ===== TOOLTIP HELPER =====
MG._tip = function(text){ return ' <span class="ctooltip">&#9432;<span class="ctooltiptext">'+text+'</span></span>'; };
MG._reqTip = function(){ return ' <span class="ctooltip" style="color:#c00;font-size:.75rem">*<span class="ctooltiptext">Toto pole je povinné</span></span>'; };

// ===== STATIC FORM HTML =====
MG._rezFormHtml = function(){
  return '<div id="rez-form"><p>&nbsp;</p>' +
    '<input type="text" id="rez-name" name="name" placeholder="* Jméno a příjmení" required title="Toto pole je povinné" autocomplete="name">' +
    '<div class="gr2"><input type="text" id="rez-street" name="street-address" placeholder="* Ulice, č.p." required autocomplete="street-address">' +
    '<input type="text" id="rez-zip" name="postal-code" placeholder="* PSČ" required autocomplete="postal-code"></div>' +
    '<div class="gr2"><input type="text" id="rez-city" name="address-level2" placeholder="* Město" required autocomplete="address-level2">' +
    '<input type="text" id="rez-country" name="country-name" placeholder="* Stát" value="Česká republika" required autocomplete="country-name"></div>' +
    '<div class="gr2"><input type="email" id="rez-email" name="email" placeholder="* E-mail" required autocomplete="email">' +
    '<input type="tel" id="rez-phone" name="tel" placeholder="* Telefon (+420XXXXXXXXX)" required autocomplete="tel" pattern="^\\+\\d{12,15}$"></div>' +
    '<div class="gr2 voucher-code"><input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">' +
    '<div><span class="btn btngreen-small" onclick="MG._applyVoucher()">UPLATNIT</span></div></div>' +
    '<div id="rez-applied-codes"></div>' +
    '<div id="rez-voucher-msg" style="font-size:.85rem;margin:-.5rem 0 .75rem"></div>' +
    '<div class="dfc pickup"><div>* Čas převzetí nebo přistavení motorky'+MG._reqTip()+'</div><input type="time" id="rez-pickup-time" required title="Toto pole je povinné"></div>' +
    '<div class="checkboxes">' +
    '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Výbava pro spolujezdce <strong>+ 690 Kč</strong>' +
    MG._tip('Výbavu pro spolujezdce zaškrtněte jen v případě, že pojedete ve dvou a spolujezdec si výbavu potřebuje zapůjčit. Velikost si vyzkouší na místě. Základní výbava pro spolujezdce zahrnuje helmu, bundu, rukavice a kuklu.') +
    '</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče <strong>+ 290 Kč</strong>' +
    MG._tip('Motocyklové boty nejsou součástí základní výbavy. V případě zájmu vám rádi zapůjčíme boty ve vaší velikosti.') +
    '</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce <strong>+ 290 Kč</strong></label></div>' +
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
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required checked><div>* Souhlasím s <a href="/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr" checked><div>Souhlasím se <a href="/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing" checked><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo" checked><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>' +
    '<div id="rez-price-preview"></div>' +
    '<div class="text-center" style="margin-top:1rem"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div>' +
    '</div>';
};

// ===== INIT FORM EVENTS (called once) =====
MG._rezInitFormEvents = function(){
  var dc = document.getElementById('rez-delivery');
  if(dc) dc.addEventListener('change',function(){
    var p=document.getElementById('rez-delivery-panel');
    if(p) p.style.display=this.checked?'block':'none';
    if(!this.checked){ var rs=document.getElementById('rez-return-same-as-delivery'); if(rs) rs.checked=true; }
    MG._rezUpdatePrice();
  });
  var retO = document.getElementById('rez-return-other');
  if(retO) retO.addEventListener('change',function(){
    var p=document.getElementById('rez-return-panel');
    if(p) p.style.display=this.checked?'block':'none';
    var rs=document.getElementById('rez-return-same-as-delivery');
    if(rs && this.checked) rs.checked=false;
    MG._rezUpdatePrice();
  });
  var rSame = document.getElementById('rez-return-same-as-delivery');
  if(rSame) rSame.addEventListener('change',function(){
    if(this.checked){
      var ro=document.getElementById('rez-return-other');
      if(ro){ ro.checked=false; var p=document.getElementById('rez-return-panel'); if(p) p.style.display='none'; }
    }
    MG._rezUpdatePrice();
  });
  var og = document.getElementById('rez-own-gear');
  if(og) og.addEventListener('change',function(){
    var n=document.getElementById('rez-note');
    if(n) n.placeholder = this.checked ? 'Poznámka' : 'Poznámka – uveďte preferovanou velikost výbavy (helma, bunda, rukavice, kalhoty)';
  });
  ['rez-eq-passenger','rez-eq-boots-rider','rez-eq-boots-passenger'].forEach(function(id){
    var cb = document.getElementById(id);
    if(cb) cb.addEventListener('change', function(){ MG._rezUpdatePrice(); });
  });
};

// ===== INIT PAGE (called from PHP inline script) =====
MG._rezInit = async function(){
  var P = window.REZERVACE_PARAMS || {};
  var mp = P.moto || '';
  var preStart = P.start || '';
  var preEnd = P.end || '';
  var preDelivery = P.delivery === '1';
  var resumeId = P.resume || '';

  // ===== RESUME FLOW =====
  if(resumeId){
    var rezApp = document.getElementById('rezervace-app');
    if(rezApp) rezApp.innerHTML = '<div id="rez-form"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervaci...</div></div>';
    try {
      var resumeRes = await window.sb.rpc('get_web_booking_resume', { p_booking_id: resumeId });
      if(resumeRes.error || (resumeRes.data && resumeRes.data.error)){
        document.getElementById('rez-form').innerHTML =
          '<div style="text-align:center;padding:2rem 0"><div style="font-size:3rem;margin-bottom:1rem">&#9888;</div>' +
          '<h2>Rezervace nenalezena</h2><p>' + (resumeRes.data && resumeRes.data.error ? resumeRes.data.error : 'Rezervace již byla dokončena nebo zrušena.') + '</p>' +
          '<p style="margin-top:1rem"><a class="btn btngreen" href="/rezervace">Vytvořit novou rezervaci</a></p></div>';
        return;
      }
      var bd = resumeRes.data;
      MG._rez = {
        startDate: bd.start_date ? bd.start_date.split('T')[0] : null,
        endDate: bd.end_date ? bd.end_date.split('T')[0] : null,
        motos: [{ id: bd.moto_id, model: bd.moto_model }],
        motoId: bd.moto_id, allBookings: {}, appliedCodes: [], discountAmt: 0,
        bookingId: bd.booking_id, userId: bd.user_id, bookingAmount: bd.total_price,
        _isResume: true, _passwordSet: true,
        _docsValidated: bd.has_id_number && bd.has_license_number,
        _docNumber: bd.has_id_number ? '(vyplněno)' : '',
        _licenseNumber: bd.has_license_number ? '(vyplněno)' : '',
        formData: {
          motoId: bd.moto_id, name: bd.customer_name || '', email: bd.customer_email || '',
          phone: bd.customer_phone || '', street: '', city: '', zip: '', country: 'Česká republika',
          extras: [], appliedCodes: [], discountAmt: 0, deliveryAddr: null, returnAddr: null
        }
      };
      if(MG._isMobile() && MG._rez._docsValidated) MG._rezShowMindeeStep();
      else MG._rezShowStep2();
    } catch(e){
      console.error('[REZ] resume error', e);
      document.getElementById('rez-form').innerHTML =
        '<div style="text-align:center;padding:2rem 0"><h2>Chyba při načítání rezervace</h2>' +
        '<p>Zkuste to prosím znovu nebo nás kontaktujte.</p>' +
        '<p style="margin-top:1rem"><a class="btn btngreen" href="/rezervace">Vytvořit novou rezervaci</a></p></div>';
    }
    return;
  }

  // ===== NORMAL FLOW =====
  var rezApp = document.getElementById('rezervace-app');
  if(rezApp){
    rezApp.innerHTML = '<div id="rez-intro"><h1>Rezervace motorky</h1>' +
      '<p>Vyberte motorku nebo zvolte „libovolná dostupná" a v kalendáři označte termín. <strong>Půjčujeme bez kauce, výbava pro řidiče je v ceně.</strong></p></div>' +
      '<div id="rez-moto-select"></div>' +
      '<div id="rez-calendar"></div>' +
      '<div id="rez-date-banner" style="display:none"></div>' +
      '<div id="rez-avail-select" style="display:none"></div>' +
      MG._rezFormHtml();
  }

  MG._rez = { startDate: preStart || null, endDate: preEnd || null, motos: [], motoId: mp, allBookings: {}, appliedCodes: [], discountAmt: 0 };

  // Restore from sessionStorage
  try {
    var saved = sessionStorage.getItem('mg_rez_form');
    if(saved){
      var sd = JSON.parse(saved);
      if(sd.formData) MG._rez.formData = sd.formData;
      if(sd.bookingId) MG._rez.bookingId = sd.bookingId;
      if(sd.userId) MG._rez.userId = sd.userId;
      if(sd.bookingAmount) MG._rez.bookingAmount = sd.bookingAmount;
      if(sd._docNumber) MG._rez._docNumber = sd._docNumber;
      if(sd._licenseNumber) MG._rez._licenseNumber = sd._licenseNumber;
      if(sd._docsValidated) MG._rez._docsValidated = sd._docsValidated;
      if(sd._passwordSet) MG._rez._passwordSet = sd._passwordSet;
      if(!preStart && sd.startDate) MG._rez.startDate = sd.startDate;
      if(!preEnd && sd.endDate) MG._rez.endDate = sd.endDate;
      if(!mp && sd.motoId) MG._rez.motoId = sd.motoId;
      if(sd.appliedCodes) MG._rez.appliedCodes = sd.appliedCodes;
      if(sd.discountAmt) MG._rez.discountAmt = sd.discountAmt;
    }
  } catch(e){}

  var motos = await MG.fetchMotos();
  MG._rez.motos = motos;
  MG._motosCache = motos;

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

  if(MG._rez.motoId && !mp){
    var dd = document.getElementById('rez-moto-dropdown');
    if(dd) dd.value = MG._rez.motoId;
  }

  await MG._rezLoadCalendar();

  if(MG._rez.startDate && MG._rez.endDate){
    MG._rezUpdateBanner();
    MG._rezUpdatePrice();
  }

  // Pre-fill form from session
  if(MG._rez.formData){
    var _f = function(id, v){ var e = document.getElementById(id); if(e && v) e.value = v; };
    var d = MG._rez.formData;
    _f('rez-name', d.name); _f('rez-email', d.email); _f('rez-phone', d.phone);
    _f('rez-street', d.street); _f('rez-city', d.city); _f('rez-zip', d.zip);
    _f('rez-country', d.country); _f('rez-note', d.note); _f('rez-pickup-time', d.pickupTime);
  }

  if(preDelivery){
    var dc = document.getElementById('rez-delivery');
    if(dc){ dc.checked = true; dc.dispatchEvent(new Event('change')); }
  }
};
