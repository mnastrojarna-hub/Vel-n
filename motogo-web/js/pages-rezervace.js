// ===== MotoGo24 Web — Stránka Rezervace =====
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {} };

MG.route('/rezervace', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'REZERVACE']);
  var hash = window.location.hash || '';
  var mp = ''; var mm = hash.match(/[?&]moto=([^&]+)/);
  if(mm) mp = decodeURIComponent(mm[1]);
  var preDelivery = /[?&]delivery=1/.test(hash);

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
    '<input type="text" id="rez-name" placeholder="* Jméno a příjmení" required title="Toto pole je povinné">' +
    '<div class="gr2"><input type="text" id="rez-street" placeholder="* Ulice, č.p." required title="Toto pole je povinné">' +
    '<input type="text" id="rez-zip" placeholder="* PSČ" required title="Toto pole je povinné"></div>' +
    '<div class="gr2"><input type="text" id="rez-city" placeholder="* Město" required title="Toto pole je povinné">' +
    '<input type="text" id="rez-country" placeholder="* Stát" value="Česká republika" required title="Toto pole je povinné"></div>' +
    '<div class="gr2"><input type="email" id="rez-email" placeholder="* E-mail" required title="Toto pole je povinné">' +
    '<input type="tel" id="rez-phone" placeholder="* Telefon (+420XXXXXXXXX)" required title="Toto pole je povinné" pattern="^\\+\\d{12,15}$"></div>' +
    '<div class="gr2 voucher-code"><input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">' +
    '<div><span class="btn btngreen-small" onclick="MG._addVoucherField()">DALŠÍ KÓD</span></div></div>' +
    '<div id="rez-extra-vouchers"></div>' +
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
    MG._tip('Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (20 Kč/1 km).') +
    '</label></div>' +
    '<div id="rez-delivery-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">' +
    '<input type="text" id="rez-delivery-address" placeholder="Zadejte adresu přistavení">' +
    '<div style="margin-top:.5rem"><input type="checkbox" id="rez-return-same-as-delivery" checked><label for="rez-return-same-as-delivery" style="font-size:.85rem"> Vrátit motorku na stejné adrese</label></div>' +
    '<div><input type="checkbox" id="rez-own-gear"><label for="rez-own-gear" style="font-size:.85rem"> Mám vlastní výbavu</label></div>' +
    '</div>' +
    // Vrácení motorky jinde
    '<div><input type="checkbox" id="rez-return-other"><label for="rez-return-other">Vrácení motorky na jiné adrese <span id="rez-return-price"></span>' +
    MG._tip('Motorku nemusíte vracet zpět v místě motopůjčovny, rádi si ji u vás vyzvedneme. Do ceny za vrácení motorky jinde se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (20 Kč/1 km).') +
    '</label></div>' +
    '<div id="rez-return-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">' +
    '<input type="text" id="rez-return-address" placeholder="Zadejte adresu vrácení">' +
    '<div class="dfc" style="margin-top:.5rem"><div>Čas vrácení</div><input type="time" id="rez-return-time" style="max-width:200px"></div>' +
    '</div>' +
    '</div>' +
    '<textarea id="rez-note" placeholder="Poznámka – uveďte preferovanou velikost výbavy (helma, bunda, rukavice, kalhoty)"></textarea>' +
    '<div class="checkboxes">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required><div>* Souhlasím s <a href="#/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr"><div>Souhlasím se <a href="#/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing"><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo"><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>' +
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
  // Delivery/return fees (nakládka 500 + vykládka 500 = 1000 base per direction, + km calculated later)
  var isDel = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
  if(isDel) extras += 1000;
  var retOther = document.getElementById('rez-return-other');
  var retSameAsDel = document.getElementById('rez-return-same-as-delivery');
  if(retOther && retOther.checked) extras += 1000;
  else if(retSameAsDel && retSameAsDel.checked && isDel) extras += 1000;
  var total = base + extras;
  var el = document.getElementById('rez-price-preview');
  if(el){
    if(total > 0){
      el.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:.75rem 1.5rem;border-radius:25px;font-size:1.15rem;font-weight:800;text-align:center;display:inline-block;margin:1rem 0">Celková cena: '+MG.formatPrice(total)+'</div>';
    } else {
      el.innerHTML = '';
    }
  }
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

// ===== STEP 1: SUBMIT FORM → show identity verification =====
MG._submitReservation = function(){
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
  var ptEl = document.getElementById('rez-pickup-time');
  if(!ptEl || !ptEl.value){ alert('Vyplňte prosím čas převzetí nebo přistavení motorky.'); return; }
  if(!MG._rezValidatePickupTime()){
    var isDel = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
    alert(isDel ? 'Při přistavení je nejdříve možný čas aktuální čas + 6 hodin.' : 'Nejdříve možný čas převzetí je aktuální čas + 1 hodina.');
    return;
  }

  // Save form data to state
  var extras = [];
  if(document.getElementById('rez-eq-passenger') && document.getElementById('rez-eq-passenger').checked)
    extras.push({name:'Výbava spolujezdce', price:690});
  if(document.getElementById('rez-eq-boots-rider') && document.getElementById('rez-eq-boots-rider').checked)
    extras.push({name:'Boty řidič', price:290});
  if(document.getElementById('rez-eq-boots-passenger') && document.getElementById('rez-eq-boots-passenger').checked)
    extras.push({name:'Boty spolujezdce', price:290});

  var deliveryAddr = null, returnAddr = null;
  if(document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked)
    deliveryAddr = (document.getElementById('rez-delivery-address') || {}).value || null;
  var retOther = document.getElementById('rez-return-other');
  var retSameAsDel = document.getElementById('rez-return-same-as-delivery');
  if(retOther && retOther.checked)
    returnAddr = (document.getElementById('rez-return-address') || {}).value || null;
  else if(retSameAsDel && retSameAsDel.checked && deliveryAddr)
    returnAddr = deliveryAddr;

  // Add delivery/return fees as extras (nakládka 500 + vykládka 500 = 1000 base per direction)
  if(deliveryAddr) extras.push({name:'Přistavení motorky (nakládka + vykládka + doprava)', price:1000});
  if(returnAddr) extras.push({name:'Vrácení motorky (nakládka + vykládka + doprava)', price:1000});

  MG._rez.formData = {
    motoId: mId,
    name: name.value, email: email.value, phone: phone.value,
    street: street.value, city: city.value, zip: zip.value,
    country: (country && country.value) || 'Česká republika',
    note: (document.getElementById('rez-note') || {}).value || '',
    pickupTime: ptEl.value,
    deliveryAddr: deliveryAddr, returnAddr: returnAddr,
    extras: extras
  };

  // Show Step 2: Identity verification
  MG._rezShowStep2();
};

// ===== STEP 2 HTML: Ověření totožnosti a ŘP =====
MG._rezShowStep2 = function(){
  var form = document.getElementById('rez-form');
  if(!form) return;
  form.innerHTML =
    '<h2 style="margin-top:1rem">Ověření totožnosti a řidičského oprávnění</h2>' +
    '<p style="color:#555;line-height:1.6;margin-bottom:1.5rem">Pro přípravu nájemní smlouvy a urychlení předání motocyklu prosíme o vyplnění údajů z dokladu totožnosti a řidičského průkazu. Originály dokladů budou zkontrolovány při osobním převzetí motocyklu.</p>' +
    '<h3>Doklad totožnosti</h3>' +
    '<div class="checkboxes" style="margin:.75rem 0">' +
    '<div><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked><label for="rez-doc-op">Občanský průkaz</label></div>' +
    '<div><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas"><label for="rez-doc-pas">Cestovní pas</label></div>' +
    '</div>' +
    '<input type="text" id="rez-doc-number" placeholder="* Číslo dokladu" required title="Toto pole je povinné">' +
    '<h3 style="margin-top:1.5rem">Řidičský průkaz</h3>' +
    '<input type="text" id="rez-license-number" placeholder="* Číslo řidičského průkazu" required title="Toto pole je povinné">' +
    '<div class="checkboxes" style="margin:1.5rem 0">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-license-confirm" required>' +
    '<div>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</div></div>' +
    '</div>' +
    '<div class="dfcs" style="flex-wrap:wrap;gap:1rem;margin-top:1rem">' +
    '<button class="btn btndark" onclick="MG._rezBackToStep1()">← Zpět</button>' +
    '<button class="btn btngreen" onclick="MG._rezSubmitStep2()">Pokračovat v rezervaci</button>' +
    '</div>';
  window.scrollTo({top: form.offsetTop - 80, behavior:'smooth'});
};

// ===== STEP 2 SUBMIT → show invoice preview =====
MG._rezSubmitStep2 = function(){
  var docNum = document.getElementById('rez-doc-number');
  var licNum = document.getElementById('rez-license-number');
  var licConf = document.getElementById('rez-license-confirm');
  if(!docNum || !docNum.value){ alert('Vyplňte číslo dokladu totožnosti.'); return; }
  if(!licNum || !licNum.value){ alert('Vyplňte číslo řidičského průkazu.'); return; }
  if(!licConf || !licConf.checked){ alert('Potvrďte prosím držení platného řidičského oprávnění.'); return; }

  var docType = document.querySelector('input[name="rez-doc-type"]:checked');
  MG._rez.identity = {
    docType: docType ? docType.value : 'op',
    docNumber: docNum.value,
    licenseNumber: licNum.value
  };

  // Show Step 3: Invoice preview
  MG._rezShowStep3();
};

// ===== BACK TO STEP 1 =====
MG._rezBackToStep1 = function(){
  var form = document.getElementById('rez-form');
  if(!form) return;
  // Re-render the form HTML and re-init events
  form.outerHTML = MG._rezFormHtml();
  MG._rezInitFormEvents();
  // Restore saved data
  var d = MG._rez.formData;
  if(d){
    var f = function(id,v){ var e=document.getElementById(id); if(e&&v) e.value=v; };
    f('rez-name',d.name); f('rez-email',d.email); f('rez-phone',d.phone);
    f('rez-street',d.street); f('rez-city',d.city); f('rez-zip',d.zip);
    f('rez-country',d.country); f('rez-note',d.note); f('rez-pickup-time',d.pickupTime);
  }
  MG._rezUpdatePrice();
};

// ===== STEP 3 HTML: Náhled zálohové faktury =====
MG._rezShowStep3 = function(){
  var form = document.getElementById('rez-form');
  if(!form) return;
  var d = MG._rez.formData, r = MG._rez;
  var moto = r.motos.find(function(m){ return m.id === d.motoId; });
  var motoName = moto ? moto.model : '—';
  var base = (moto && r.startDate && r.endDate) ? MG.calcPrice(moto, r.startDate, r.endDate) : 0;
  var extrasTotal = 0;
  d.extras.forEach(function(e){ extrasTotal += e.price; });
  var total = base + extrasTotal;

  var rows = '<tr><td style="padding:6px 0;border-bottom:1px solid #eee">Pronájem motocyklu '+motoName+'</td>' +
    '<td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;white-space:nowrap">'+MG.formatPrice(base)+'</td></tr>';
  d.extras.forEach(function(e){
    rows += '<tr><td style="padding:6px 0;border-bottom:1px solid #eee">'+e.name+'</td>' +
      '<td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;white-space:nowrap">'+MG.formatPrice(e.price)+'</td></tr>';
  });

  form.innerHTML =
    '<h2 style="margin-top:1rem">Náhled zálohové faktury</h2>' +
    '<p style="color:#555;margin-bottom:1rem">Zkontrolujte prosím údaje před pokračováním k platbě.</p>' +
    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1.25rem;margin-bottom:1.5rem">' +
    '<table style="width:100%;border-collapse:collapse;font-size:.9rem;color:#333">' +
    '<tr><td style="padding:6px 0;font-weight:700;border-bottom:1px solid #ccc">Položka</td>' +
    '<td style="padding:6px 0;font-weight:700;border-bottom:1px solid #ccc;text-align:right">Cena</td></tr>' +
    rows +
    '</table>' +
    '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;padding-top:12px;border-top:2px solid #1a8c1a">' +
    '<strong style="font-size:1.1rem">Celkem k úhradě</strong>' +
    '<strong style="font-size:1.1rem;color:#1a8c1a">'+MG.formatPrice(total)+'</strong></div>' +
    '</div>' +
    '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:10px;padding:1rem;margin-bottom:1.5rem;font-size:.88rem;color:#374151">' +
    '<strong>Odběratel:</strong> '+d.name+'<br>' +
    d.street+', '+d.zip+' '+d.city+'<br>' +
    d.email+' | '+d.phone+'<br>' +
    '<strong>Motorka:</strong> '+motoName+'<br>' +
    '<strong>Termín:</strong> '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+'<br>' +
    '<strong>Čas převzetí:</strong> '+d.pickupTime +
    (d.deliveryAddr ? '<br><strong>Přistavení na:</strong> '+d.deliveryAddr : '') +
    (d.returnAddr ? '<br><strong>Vrácení na:</strong> '+d.returnAddr : '') +
    '</div>' +
    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1rem">' +
    '<button class="btn btndark" onclick="MG._rezShowStep2()">← Zpět</button>' +
    '<div style="display:flex;align-items:center;gap:1rem"><div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>' +
    '<button class="btn btngreen" onclick="MG._rezSubmitPayment()">Pokračovat k platbě</button></div>' +
    '</div>';
  window.scrollTo({top: form.offsetTop - 80, behavior:'smooth'});
};

// ===== STEP 3 SUBMIT → create booking + Stripe Checkout =====
MG._rezSubmitPayment = async function(){
  var d = MG._rez.formData, r = MG._rez, id = MG._rez.identity;
  var btn = document.querySelector('#rez-form .btn.btngreen');
  if(btn){ btn.disabled = true; btn.textContent = 'Zpracovávám...'; }

  try {
    var res = await window.sb.rpc('create_web_booking', {
      p_moto_id: d.motoId,
      p_start_date: r.startDate, p_end_date: r.endDate,
      p_name: d.name, p_email: d.email, p_phone: d.phone,
      p_street: d.street, p_city: d.city, p_zip: d.zip,
      p_country: d.country, p_note: d.note,
      p_pickup_time: d.pickupTime,
      p_delivery_address: d.deliveryAddr,
      p_return_address: d.returnAddr,
      p_extras: d.extras
    });

    if(res.error){ alert('Chyba: '+res.error.message); if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';} return; }
    var data = res.data;
    if(data.error){ alert(data.error); if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';} return; }

    var bookingId = data.booking_id;

    // Save identity docs to profile (best effort)
    if(data.user_id && id){
      window.sb.from('profiles').update({
        id_number: id.docNumber,
        license_number: id.licenseNumber
      }).eq('id', data.user_id).then(function(){});
    }

    // Call Stripe Checkout
    var payRes = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY },
      body: JSON.stringify({
        booking_id: bookingId, amount: data.amount,
        type: 'booking', source: 'web', mode: 'checkout'
      })
    });

    var payData = await payRes.json();
    if(payData.error){ alert('Chyba platby: '+payData.error); if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';} return; }

    if(payData.checkout_url){
      window.location.href = payData.checkout_url;
    } else {
      alert('Nepodařilo se vytvořit platební relaci.');
      if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
    }
  } catch(e){
    console.error('[REZ] Payment error:', e);
    alert('Došlo k chybě. Zkuste to prosím znovu.');
    if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
  }
};
