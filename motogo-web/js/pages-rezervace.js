// ===== MotoGo24 Web — Stránka Rezervace =====
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {} };

MG.route('/rezervace', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'REZERVACE']);
  var hash = window.location.hash || '';
  var mp = ''; var mm = hash.match(/[?&]moto=([^&]+)/);
  if(mm) mp = decodeURIComponent(mm[1]);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent pcontent"><h1>Rezervace motorky</h1>' +
    '<h3>Jak rezervace funguje?</h3><p>&nbsp;</p>' +
    '<p>Pokud si chcete <strong>půjčit motorku v konkrétním termínu</strong>, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.</p><p>&nbsp;</p>' +
    '<p>V případě, že si chcete <strong>vyzkoušet konkrétní motorku</strong>, vyberte ji ze seznamu.</p><p>&nbsp;</p>' +
    '<p><strong>Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.</strong></p><p>&nbsp;</p>' +
    '<div id="rez-moto-select"></div>' +
    '<div id="rez-calendar"></div>' +
    '<div id="rez-date-banner" style="display:none"></div>' +
    '<div id="rez-avail-select" style="display:none"></div>' +
    MG._rezFormHtml() +
    '</div></div></main>';

  MG._rez = { startDate: null, endDate: null, motos: [], motoId: mp, allBookings: {} };
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
});

// ===== STATIC FORM HTML =====
MG._rezFormHtml = function(){
  return '<div id="rez-form"><p>&nbsp;</p>' +
    '<input type="text" id="rez-name" placeholder="* Jméno a příjmení" required>' +
    '<div class="gr2"><input type="text" id="rez-street" placeholder="* Ulice, č.p." required>' +
    '<input type="text" id="rez-zip" placeholder="* PSČ" required></div>' +
    '<div class="gr2"><input type="text" id="rez-city" placeholder="* Město" required>' +
    '<input type="text" id="rez-country" placeholder="* Stát" value="Česká republika" required></div>' +
    '<div class="gr2"><input type="email" id="rez-email" placeholder="* E-mail" required>' +
    '<input type="tel" id="rez-phone" placeholder="* Telefon (+420XXXXXXXXX)" required pattern="^\\+\\d{12,15}$"></div>' +
    '<div class="gr2 voucher-code"><input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">' +
    '<div><span class="btn btngreen-small" onclick="MG._addVoucherField()">DALŠÍ KÓD</span></div></div>' +
    '<div id="rez-extra-vouchers"></div>' +
    '<div class="dfc pickup"><div>Čas převzetí motorky nebo přistavení</div><input type="time" id="rez-pickup-time"></div>' +
    '<div class="checkboxes">' +
    '<div><input type="checkbox" id="rez-delivery"><label for="rez-delivery">Přistavení motorky jinam, než na adresu motopůjčovny <span class="ctooltip">&#9432;<span class="ctooltiptext">Motorku vám dovezeme na domluvené místo. Nakládka 500 Kč, vykládka 500 Kč + 20 Kč/km.</span></span></label></div>' +
    '<div id="rez-delivery-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px"><input type="text" id="rez-delivery-address" placeholder="Zadejte adresu"></div>' +
    '<div><input type="radio" id="rez-return-same" name="rez-return" value="same" checked><label for="rez-return-same">Vrátit na stejném místě, kde bylo vyzvednuto</label></div>' +
    '<div><input type="radio" id="rez-return-other" name="rez-return" value="other"><label for="rez-return-other">Vrácení motorky jinde než na adrese motopůjčovny</label></div>' +
    '<div id="rez-pickup-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px"><input type="text" id="rez-pickup-address" placeholder="Zadejte adresu vrácení">' +
    '<div class="dfc" style="margin-top:.5rem"><div>Čas vrácení</div><input type="time" id="rez-return-time" style="max-width:200px"></div></div>' +
    '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Základní výbava spolujezdce - 690,- Kč</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče - 290,- Kč</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce - 290,- Kč</label></div></div>' +
    '<textarea id="rez-note" placeholder="Poznámka"></textarea>' +
    '<div class="checkboxes">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required><div>* Souhlasím s <a href="#/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr"><div>Souhlasím se <a href="#/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing"><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo"><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>' +
    '<div class="dfcs" style="flex-wrap:wrap;gap:1rem;margin-top:1rem"><div><div id="rez-price-preview"></div></div>' +
    '<div><div class="text-right"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div></div></div>' +
    '</div>';
};

// ===== INIT FORM EVENTS (called once) =====
MG._rezInitFormEvents = function(){
  var dc = document.getElementById('rez-delivery');
  if(dc) dc.addEventListener('change',function(){ var p=document.getElementById('rez-delivery-panel'); if(p) p.style.display=this.checked?'block':'none'; });
  var retO = document.getElementById('rez-return-other');
  var retS = document.getElementById('rez-return-same');
  if(retO) retO.addEventListener('change',function(){ var p=document.getElementById('rez-pickup-panel'); if(p) p.style.display=this.checked?'block':'none'; });
  if(retS) retS.addEventListener('change',function(){ var p=document.getElementById('rez-pickup-panel'); if(p) p.style.display='none'; });
  ['rez-eq-passenger','rez-eq-boots-rider','rez-eq-boots-passenger'].forEach(function(id){
    var cb = document.getElementById(id);
    if(cb) cb.addEventListener('change', function(){ MG._rezUpdatePrice(); });
  });
};

// ===== RESET DATE SELECTION =====
MG._rezResetDates = function(){
  MG._rez.startDate = null; MG._rez.endDate = null;
  var b = document.getElementById('rez-date-banner'); if(b) b.style.display = 'none';
  var a = document.getElementById('rez-avail-select'); if(a){ a.style.display='none'; a.innerHTML=''; }
  MG._rezUpdatePrice();
};

// ===== LOAD CALENDAR =====
MG._rezLoadCalendar = async function(){
  var cal = document.getElementById('rez-calendar'); if(!cal) return;
  var motoId = MG._rez.motoId;
  MG._rez.allBookings = {};
  if(motoId){
    var bookings = await MG.fetchMotoBookings(motoId);
    MG._rez.allBookings[motoId] = MG._rezBookedMap(bookings);
  } else {
    var motos = MG._rez.motos;
    for(var i = 0; i < motos.length; i++){
      var bk = await MG.fetchMotoBookings(motos[i].id);
      MG._rez.allBookings[motos[i].id] = MG._rezBookedMap(bk);
    }
  }
  var now = new Date();
  MG._rez.calYear = now.getFullYear(); MG._rez.calMonth = now.getMonth();
  MG._rezRenderCal();
};

// ===== BUILD BOOKED-DAYS MAP (with pending status for <4h) =====
MG._rezBookedMap = function(bookings){
  var map = {};
  var now = new Date();
  bookings.forEach(function(b){
    var s = new Date(b.start_date), e = new Date(b.end_date), d = new Date(s);
    var isPending = b.status === 'pending';
    var createdAt = b.created_at ? new Date(b.created_at) : null;
    var isRecent = createdAt && (now - createdAt) < 4 * 60 * 60 * 1000;
    var status = (isPending && isRecent) ? 'unconfirmed' : 'occupied';
    while(d <= e){ map[d.toISOString().split('T')[0]] = status; d.setDate(d.getDate()+1); }
  });
  return map;
};

// ===== CHECK IF DATE IS AVAILABLE =====
MG._rezDateAvail = function(dateStr){
  var motoId = MG._rez.motoId;
  if(motoId){
    var map = MG._rez.allBookings[motoId] || {};
    return !map[dateStr];
  }
  var motos = MG._rez.motos;
  for(var i = 0; i < motos.length; i++){
    var m = MG._rez.allBookings[motos[i].id] || {};
    if(!m[dateStr]) return true;
  }
  return false;
};

// ===== GET DATE STATUS (for calendar coloring) =====
MG._rezDateStatus = function(dateStr){
  var motoId = MG._rez.motoId;
  if(motoId){
    return (MG._rez.allBookings[motoId] || {})[dateStr] || 'free';
  }
  var motos = MG._rez.motos, hasFree = false, hasUnconf = false;
  for(var i = 0; i < motos.length; i++){
    var s = (MG._rez.allBookings[motos[i].id] || {})[dateStr];
    if(!s) hasFree = true;
    else if(s === 'unconfirmed') hasUnconf = true;
  }
  if(hasFree) return 'free';
  if(hasUnconf) return 'unconfirmed';
  return 'occupied';
};

// ===== RENDER CALENDAR =====
MG._rezRenderCal = function(){
  var cal = document.getElementById('rez-calendar'); if(!cal) return;
  var y = MG._rez.calYear, m = MG._rez.calMonth;
  var months = ['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'];
  var dayN = ['Po','Út','St','Čt','Pá','So','Ne'];
  var dayFull = ['Ne','Po','Út','St','Čt','Pá','So'];
  var first = new Date(y,m,1), last = new Date(y,m+1,0);
  var dow = (first.getDay()+6)%7;
  var todayStr = new Date().toISOString().split('T')[0];

  var h = '<div class="cal-nav"><button onclick="MG._rezCalPrev()">&larr;</button><span style="font-weight:800;font-size:1.2rem">'+months[m]+' '+y+'</span><button onclick="MG._rezCalNext()">&rarr;</button></div>';
  h += '<div class="cal-grid">';
  dayN.forEach(function(d){ h += '<div class="cal-header">'+d+'</div>'; });
  for(var i=0;i<dow;i++) h += '<div class="cal-day empty"></div>';

  var sd = MG._rez.startDate, ed = MG._rez.endDate;
  for(var d=1;d<=last.getDate();d++){
    var ds = y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0');
    var isPast = ds < todayStr;
    var status = isPast ? 'past' : MG._rezDateStatus(ds);
    var inRange = sd && ed && ds >= sd && ds <= ed;
    var isStart = sd && ds === sd;
    var isEnd = ed && ds === ed;
    var dayOfWeek = dayFull[new Date(y,m,d).getDay()];

    var bg, color, cursor = 'default', border = 'none';
    if(isPast || status === 'occupied'){ bg = '#444'; color = '#fff'; cursor = 'not-allowed'; }
    else if(status === 'unconfirmed'){ bg = '#fff'; color = '#333'; cursor = 'not-allowed'; border = '2px solid #ccc'; }
    else if(isStart || isEnd){ bg = '#1a8c1a'; color = '#fff'; cursor = 'pointer'; border = '2px solid #fff'; }
    else if(inRange){ bg = '#1a8c1a'; color = '#fff'; cursor = 'pointer'; }
    else { bg = '#74FB71'; color = '#0b0b0b'; cursor = 'pointer'; }

    var canClick = !isPast && status === 'free';
    var style = 'background:'+bg+';color:'+color+';cursor:'+cursor+';border:'+border+';border-radius:12px;';
    var click = canClick ? ' onclick="MG._rezPickDate(\''+ds+'\')"' : '';
    h += '<div class="cal-day" style="'+style+'"'+click+'>' +
      '<span style="font-size:.65rem;opacity:.7;display:block;line-height:1">'+dayOfWeek+'</span>' +
      '<span style="font-weight:700">'+d+'</span></div>';
  }
  h += '</div>';
  h += '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div>' +
    '<div><span class="cicon occupied">&nbsp;</span> Obsazené</div>' +
    '<div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>';
  cal.innerHTML = h;
};

MG._rezCalPrev = function(){ MG._rez.calMonth--; if(MG._rez.calMonth<0){MG._rez.calMonth=11;MG._rez.calYear--;} MG._rezRenderCal(); };
MG._rezCalNext = function(){ MG._rez.calMonth++; if(MG._rez.calMonth>11){MG._rez.calMonth=0;MG._rez.calYear++;} MG._rezRenderCal(); };

// ===== DATE PICK LOGIC =====
MG._rezPickDate = function(ds){
  var r = MG._rez;
  if(!r.startDate || r.endDate){ r.startDate = ds; r.endDate = null; }
  else if(ds < r.startDate){ r.startDate = ds; r.endDate = null; }
  else if(ds === r.startDate){ r.startDate = null; r.endDate = null; }
  else { r.endDate = ds; }
  MG._rezRenderCal();
  MG._rezUpdateBanner();
  MG._rezUpdatePrice();
};

// ===== DATE BANNER =====
MG._rezUpdateBanner = function(){
  var r = MG._rez;
  var ban = document.getElementById('rez-date-banner');
  var avail = document.getElementById('rez-avail-select');
  if(!ban) return;

  if(!r.startDate){ ban.style.display='none'; if(avail){avail.style.display='none';avail.innerHTML='';} return; }
  if(!r.endDate){
    ban.style.display='block';
    ban.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
      '<span>Vybrán začátek: <strong>'+MG.formatDate(r.startDate)+'</strong> — klikněte na koncové datum</span>' +
      '<span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="MG._rezResetDates();MG._rezRenderCal()">&#x2715; ZRUŠIT VÝBĚR</span></div>';
    if(avail){avail.style.display='none';avail.innerHTML='';}
    return;
  }

  ban.style.display='block';
  ban.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:14px 18px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
    '<span style="font-size:1.05rem"><strong>MÁTE VYBRANÝ TERMÍN: '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+'</strong></span>' +
    '<span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="MG._rezResetDates();MG._rezRenderCal()">&#x2715; ZRUŠIT VÝBĚR</span></div>';

  if(!r.motoId) MG._rezShowAvailMotos();
};

// ===== AVAILABLE MOTOS DROPDOWN =====
MG._rezShowAvailMotos = function(){
  var r = MG._rez, el = document.getElementById('rez-avail-select'); if(!el) return;
  var free = r.motos.filter(function(m){
    var map = r.allBookings[m.id] || {};
    var d = new Date(r.startDate), end = new Date(r.endDate);
    while(d <= end){ if(map[d.toISOString().split('T')[0]]) return false; d.setDate(d.getDate()+1); }
    return true;
  });
  if(!free.length){
    el.style.display='block';
    el.innerHTML='<p style="color:#f66;margin:12px 0">V tomto termínu bohužel není dostupná žádná motorka.</p>';
    return;
  }
  var h = '<form class="form-product-select gr2" style="margin:12px 0"><div>Dostupné motorky:</div><select id="rez-avail-dropdown">' +
    '<option value="">— vyberte motorku —</option>';
  free.forEach(function(m){ h += '<option value="'+m.id+'">'+m.model+'</option>'; });
  h += '</select></form>';
  el.style.display='block'; el.innerHTML = h;
  document.getElementById('rez-avail-dropdown').addEventListener('change', function(){
    MG._rez.selectedMotoId = this.value;
    MG._rezUpdatePrice();
  });
};

// ===== PRICE UPDATE (in-place, no form rebuild) =====
MG._rezUpdatePrice = function(){
  var r = MG._rez, mId = r.motoId || r.selectedMotoId;
  var moto = r.motos.find(function(m){ return m.id === mId; });
  var base = (moto && r.startDate && r.endDate) ? MG.calcPrice(moto, r.startDate, r.endDate) : 0;
  var extras = 0;
  if(document.getElementById('rez-eq-passenger') && document.getElementById('rez-eq-passenger').checked) extras += 690;
  if(document.getElementById('rez-eq-boots-rider') && document.getElementById('rez-eq-boots-rider').checked) extras += 290;
  if(document.getElementById('rez-eq-boots-passenger') && document.getElementById('rez-eq-boots-passenger').checked) extras += 290;
  var total = base + extras;
  var el = document.getElementById('rez-price-preview');
  if(el) el.innerHTML = total > 0 ? 'Celková cena: <strong>'+MG.formatPrice(total)+'</strong>' : '';
};

// ===== PICKUP TIME VALIDATION =====
// Returns min allowed time as HH:MM string; null if any time is ok (future date)
MG._rezMinPickupTime = function(){
  var r = MG._rez;
  if(!r.startDate) return null;
  var today = new Date().toISOString().split('T')[0];
  if(r.startDate > today) return null; // future date, any time
  var isDelivery = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
  var now = new Date();
  var offsetH = isDelivery ? 6 : 1;
  now.setHours(now.getHours() + offsetH);
  var hh = String(now.getHours()).padStart(2,'0');
  var mm = String(now.getMinutes()).padStart(2,'0');
  return hh + ':' + mm;
};

MG._rezValidatePickupTime = function(){
  var pt = document.getElementById('rez-pickup-time');
  if(!pt || !pt.value) return false;
  var min = MG._rezMinPickupTime();
  if(!min) return true;
  return pt.value >= min;
};

// ===== VOUCHER FIELD =====
MG._addVoucherField = function(){
  var c = document.getElementById('rez-extra-vouchers'); if(!c) return;
  var d = document.createElement('div'); d.className = 'gr2 voucher-code';
  d.innerHTML = '<input type="text" placeholder="Slevový kód" maxlength="255">';
  c.appendChild(d);
};

// ===== SUBMIT — create booking + redirect to Stripe =====
MG._submitReservation = async function(){
  var name = document.getElementById('rez-name');
  var email = document.getElementById('rez-email');
  var phone = document.getElementById('rez-phone');
  var street = document.getElementById('rez-street');
  var city = document.getElementById('rez-city');
  var zip = document.getElementById('rez-zip');
  var country = document.getElementById('rez-country');
  var agree = document.getElementById('rez-agree-vop');

  if(!name || !name.value || !email || !email.value || !phone || !phone.value ||
     !(street && street.value) || !(city && city.value) || !(zip && zip.value)){
    alert('Vyplňte prosím všechna povinná pole.'); return;
  }
  if(!agree || !agree.checked){
    alert('Pro pokračování musíte souhlasit s obchodními podmínkami.'); return;
  }
  var r = MG._rez;
  if(!r.startDate || !r.endDate){ alert('Vyberte prosím termín v kalendáři.'); return; }
  var mId = r.motoId || r.selectedMotoId;
  if(!mId){ alert('Vyberte prosím motorku.'); return; }
  // Pickup time required
  var ptEl = document.getElementById('rez-pickup-time');
  if(!ptEl || !ptEl.value){
    alert('Vyplňte prosím čas převzetí nebo přistavení motorky.'); return;
  }
  if(!MG._rezValidatePickupTime()){
    var isDel = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
    alert(isDel ? 'Při přistavení motorky je nejdříve možný čas aktuální čas + 6 hodin.' : 'Nejdříve možný čas převzetí je aktuální čas + 1 hodina.');
    return;
  }

  // Build extras array
  var extras = [];
  if(document.getElementById('rez-eq-passenger') && document.getElementById('rez-eq-passenger').checked)
    extras.push({name:'Výbava spolujezdce', price:690});
  if(document.getElementById('rez-eq-boots-rider') && document.getElementById('rez-eq-boots-rider').checked)
    extras.push({name:'Boty řidič', price:290});
  if(document.getElementById('rez-eq-boots-passenger') && document.getElementById('rez-eq-boots-passenger').checked)
    extras.push({name:'Boty spolujezdce', price:290});

  var note = (document.getElementById('rez-note') || {}).value || '';
  var pickupTime = (document.getElementById('rez-pickup-time') || {}).value || null;
  var deliveryAddr = null, returnAddr = null;
  if(document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked)
    deliveryAddr = (document.getElementById('rez-delivery-address') || {}).value || null;
  var retOther = document.getElementById('rez-return-other');
  if(retOther && retOther.checked)
    returnAddr = (document.getElementById('rez-pickup-address') || {}).value || null;

  // Disable button
  var btn = document.querySelector('#rez-form .btn.btngreen');
  if(btn){ btn.disabled = true; btn.textContent = 'Zpracovávám...'; }

  try {
    // 1. Create booking via RPC
    var res = await window.sb.rpc('create_web_booking', {
      p_moto_id: mId,
      p_start_date: r.startDate,
      p_end_date: r.endDate,
      p_name: name.value,
      p_email: email.value,
      p_phone: phone.value,
      p_street: (street && street.value) || '',
      p_city: (city && city.value) || '',
      p_zip: (zip && zip.value) || '',
      p_country: (country && country.value) || 'CZ',
      p_note: note,
      p_pickup_time: pickupTime,
      p_delivery_address: deliveryAddr,
      p_return_address: returnAddr,
      p_extras: extras
    });

    if(res.error){ alert('Chyba: ' + res.error.message); if(btn){btn.disabled=false;btn.textContent='Pokračovat v rezervaci';} return; }
    var data = res.data;
    if(data.error){ alert(data.error); if(btn){btn.disabled=false;btn.textContent='Pokračovat v rezervaci';} return; }

    var bookingId = data.booking_id;
    var amount = data.amount;

    // 2. Call process-payment edge function for Stripe Checkout
    var payRes = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({
        booking_id: bookingId,
        amount: amount,
        type: 'booking',
        source: 'web',
        mode: 'checkout'
      })
    });

    var payData = await payRes.json();
    if(payData.error){ alert('Chyba platby: ' + payData.error); if(btn){btn.disabled=false;btn.textContent='Pokračovat v rezervaci';} return; }

    // 3. Redirect to Stripe Checkout
    if(payData.checkout_url){
      window.location.href = payData.checkout_url;
    } else {
      alert('Nepodařilo se vytvořit platební relaci.'); if(btn){btn.disabled=false;btn.textContent='Pokračovat v rezervaci';}
    }
  } catch(e){
    console.error('[REZ] Submit error:', e);
    alert('Došlo k chybě. Zkuste to prosím znovu.');
    if(btn){btn.disabled=false;btn.textContent='Pokračovat v rezervaci';}
  }
};
