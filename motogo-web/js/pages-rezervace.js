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
  var preStart = ''; var ms = hash.match(/[?&]start=([^&]+)/);
  if(ms) preStart = decodeURIComponent(ms[1]);
  var preEnd = ''; var me = hash.match(/[?&]end=([^&]+)/);
  if(me) preEnd = decodeURIComponent(me[1]);

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

  MG._rez = { startDate: preStart || null, endDate: preEnd || null, motos: [], motoId: mp, allBookings: {} };
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
    '<input type="text" id="rez-name" placeholder="* Jméno a příjmení" required title="Toto pole je povinné">' +
    '<div class="gr2"><input type="text" id="rez-street" placeholder="* Ulice, č.p." required title="Toto pole je povinné">' +
    '<input type="text" id="rez-zip" placeholder="* PSČ" required title="Toto pole je povinné"></div>' +
    '<div class="gr2"><input type="text" id="rez-city" placeholder="* Město" required title="Toto pole je povinné">' +
    '<input type="text" id="rez-country" placeholder="* Stát" value="Česká republika" required title="Toto pole je povinné"></div>' +
    '<div class="gr2"><input type="email" id="rez-email" placeholder="* E-mail" required title="Toto pole je povinné">' +
    '<input type="tel" id="rez-phone" placeholder="* Telefon (+420XXXXXXXXX)" required title="Toto pole je povinné" pattern="^\\+\\d{12,15}$"></div>' +
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
  // If start date is pre-filled, show that month; otherwise show current month
  var calDate = MG._rez.startDate ? new Date(MG._rez.startDate) : new Date();
  MG._rez.calYear = calDate.getFullYear(); MG._rez.calMonth = calDate.getMonth();
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
  MG._rez.discountAmt = MG._rez.appliedCodes ? MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0) : 0;
  var total = Math.max(0, base + extras - MG._rez.discountAmt);
  var el = document.getElementById('rez-price-preview');
  if(el){
    if(total > 0 || MG._rez.discountAmt > 0){
      var discTxt = MG._rez.discountAmt > 0 ? '<div style="font-size:.85rem;color:#1a8c1a;margin-top:.3rem">Sleva: −'+MG.formatPrice(MG._rez.discountAmt)+'</div>' : '';
      el.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:.75rem 1.5rem;border-radius:25px;font-size:1.15rem;font-weight:800;text-align:center;display:inline-block;margin:1rem 0">Celková cena: '+MG.formatPrice(total)+discTxt+'</div>';
    } else { el.innerHTML = ''; }
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

// ===== VOUCHER / PROMO CODE VALIDATION =====
MG._rez.appliedCodes = []; // [{code, type:'promo'|'voucher', id, discountAmt, discountType, discountValue}]
MG._rez.discountAmt = 0;

MG._applyVoucher = async function(){
  var inp = document.getElementById('rez-voucher');
  var msg = document.getElementById('rez-voucher-msg');
  if(!inp || !inp.value.trim()){ if(msg) msg.innerHTML='<span style="color:#c00">Zadejte kód</span>'; return; }
  var code = inp.value.trim().toUpperCase();
  // Check duplicate
  for(var i=0;i<MG._rez.appliedCodes.length;i++){
    if(MG._rez.appliedCodes[i].code===code){ if(msg) msg.innerHTML='<span style="color:#c00">Kód již uplatněn</span>'; return; }
  }
  if(msg) msg.innerHTML='<span style="color:#999">Ověřuji...</span>';
  // Calculate base for discount
  var r=MG._rez, mId=r.motoId||r.selectedMotoId;
  var moto=r.motos.find(function(m){return m.id===mId;});
  var base=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;

  // Try promo code first
  var pr = await window.sb.rpc('validate_promo_code',{p_code:code});
  if(pr.data && pr.data.valid){
    var pd=pr.data;
    if(pd.type==='percent' && MG._rez.appliedCodes.some(function(c){return c.discountType==='percent';})){
      if(msg) msg.innerHTML='<span style="color:#c00">Nelze kombinovat dva procentuální kódy</span>'; return;
    }
    var disc=pd.type==='percent'?Math.round(base*pd.value/100):pd.value;
    var curDisc=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    disc=Math.min(disc,Math.max(0,base-curDisc));
    MG._rez.appliedCodes.push({code:code,type:'promo',id:pd.id,discountAmt:disc,discountType:pd.type,discountValue:pd.value});
    var lbl=pd.type==='percent'?pd.value+'%':pd.value+' Kč';
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">✓ Sleva '+lbl+' uplatněna (−'+MG.formatPrice(disc)+')</span>';
    inp.value=''; MG._renderAppliedCodes(); MG._rezUpdatePrice(); return;
  }
  // Try voucher
  var vr = await window.sb.rpc('validate_voucher_code',{p_code:code});
  if(vr.data && vr.data.valid){
    var vd=vr.data;
    var curDiscV=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    var vDisc=Math.min(vd.value,Math.max(0,base-curDiscV));
    MG._rez.appliedCodes.push({code:code,type:'voucher',id:vd.id,discountAmt:vDisc,discountType:'fixed',discountValue:vd.value});
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">✓ Poukaz '+MG.formatPrice(vd.value)+' uplatněn</span>';
    inp.value=''; MG._renderAppliedCodes(); MG._rezUpdatePrice(); return;
  }
  if(msg) msg.innerHTML='<span style="color:#c00">✗ Neplatný kód</span>';
};

MG._renderAppliedCodes = function(){
  var el=document.getElementById('rez-applied-codes'); if(!el) return;
  if(!MG._rez.appliedCodes.length){ el.innerHTML=''; return; }
  var h='';
  MG._rez.appliedCodes.forEach(function(c,i){
    h+='<div style="display:inline-flex;align-items:center;gap:.4rem;background:#dcfce7;padding:.3rem .7rem;border-radius:20px;margin:0 .5rem .5rem 0;font-size:.85rem">' +
      '<strong>'+c.code+'</strong> −'+MG.formatPrice(c.discountAmt) +
      ' <span style="cursor:pointer;color:#c00" onclick="MG._removeCode('+i+')">✕</span></div>';
  });
  el.innerHTML=h;
};

MG._removeCode = function(idx){
  MG._rez.appliedCodes.splice(idx,1);
  MG._rez.discountAmt=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
  MG._renderAppliedCodes(); MG._rezUpdatePrice();
};
// Steps 1-3 + Stripe → pages-rezervace-steps.js
