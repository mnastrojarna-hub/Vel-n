// ===== MotoGo24 Web — Stránka Rezervace =====
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {} };

MG.route('/rezervace', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'REZERVACE']);
  var hash = window.location.hash || '';
  var mp = ''; var mm = hash.match(/[?&]moto=([^&]+)/);
  if(mm) mp = decodeURIComponent(mm[1]);

  app.innerHTML = '<main id="content"><section class="container">' + bc +
    '<div class="pcontent"><h1>Rezervace motorky</h1>' +
    '<h3>Jak rezervace funguje?</h3><p>&nbsp;</p>' +
    '<p>Pokud si chcete <strong>půjčit motorku v konkrétním termínu</strong>, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.</p><p>&nbsp;</p>' +
    '<p>V případě, že si chcete <strong>vyzkoušet konkrétní motorku</strong>, vyberte ji ze seznamu a v kalendáři se vám zobrazí dostupné termíny.</p><p>&nbsp;</p>' +
    '<p><strong>Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.</strong></p><p>&nbsp;</p>' +
    '<div id="rez-moto-select"></div>' +
    '<div id="rez-calendar"></div>' +
    '<div id="rez-date-banner" style="display:none"></div>' +
    '<div id="rez-avail-select" style="display:none"></div>' +
    '<div id="rez-form" style="display:none"></div>' +
    '</div></section></main>';

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
  MG._rezLoadCalendar();
});

// ===== RESET DATE SELECTION =====
MG._rezResetDates = function(){
  MG._rez.startDate = null; MG._rez.endDate = null;
  var b = document.getElementById('rez-date-banner'); if(b) b.style.display = 'none';
  var a = document.getElementById('rez-avail-select'); if(a){ a.style.display = 'none'; a.innerHTML = ''; }
  var f = document.getElementById('rez-form'); if(f){ f.style.display = 'none'; f.innerHTML = ''; }
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

// ===== BUILD BOOKED-DAYS MAP =====
MG._rezBookedMap = function(bookings){
  var map = {};
  bookings.forEach(function(b){
    var s = new Date(b.start_date), e = new Date(b.end_date), d = new Date(s);
    while(d <= e){ map[d.toISOString().split('T')[0]] = true; d.setDate(d.getDate()+1); }
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
  // "any moto" mode: available if at least one moto is free
  var motos = MG._rez.motos;
  for(var i = 0; i < motos.length; i++){
    var m = MG._rez.allBookings[motos[i].id] || {};
    if(!m[dateStr]) return true;
  }
  return false;
};

// ===== RENDER CALENDAR =====
MG._rezRenderCal = function(){
  var cal = document.getElementById('rez-calendar'); if(!cal) return;
  var y = MG._rez.calYear, m = MG._rez.calMonth;
  var months = ['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'];
  var dayN = ['Po','Út','St','Čt','Pá','So','Ne'];
  var first = new Date(y,m,1), last = new Date(y,m+1,0);
  var dow = (first.getDay()+6)%7;
  var todayStr = new Date().toISOString().split('T')[0];

  var h = '<div class="cal-nav"><button onclick="MG._rezCalPrev()">&larr;</button><span>'+months[m]+' '+y+'</span><button onclick="MG._rezCalNext()">&rarr;</button></div>';
  h += '<div class="cal-grid">';
  dayN.forEach(function(d){ h += '<div class="cal-header">'+d+'</div>'; });
  for(var i=0;i<dow;i++) h += '<div class="cal-day empty"></div>';

  var sd = MG._rez.startDate, ed = MG._rez.endDate;
  for(var d=1;d<=last.getDate();d++){
    var ds = y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0');
    var isPast = ds < todayStr;
    var avail = !isPast && MG._rezDateAvail(ds);
    var isToday = ds === todayStr;
    var inRange = sd && ed && ds >= sd && ds <= ed;
    var isStart = sd && ds === sd;
    var isEnd = ed && ds === ed;

    var bg, color, cursor = 'default', border = 'none';
    if(isPast || !avail){ bg = '#444'; color = '#fff'; cursor = 'not-allowed'; }
    else if(isStart || isEnd){ bg = '#1a8c1a'; color = '#fff'; cursor = 'pointer'; border = '2px solid #fff'; }
    else if(inRange){ bg = '#1a8c1a'; color = '#fff'; cursor = 'pointer'; }
    else if(isToday){ bg = '#74FB71'; color = '#0b0b0b'; cursor = 'pointer'; }
    else { bg = '#74FB71'; color = '#0b0b0b'; cursor = 'pointer'; }

    var style = 'background:'+bg+';color:'+color+';cursor:'+cursor+';border:'+border+';border-radius:20px;';
    var click = (isPast || !avail) ? '' : ' onclick="MG._rezPickDate(\''+ds+'\')"';
    h += '<div class="cal-day" style="'+style+'"'+click+'>'+d+'</div>';
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
};

// ===== DATE BANNER =====
MG._rezUpdateBanner = function(){
  var r = MG._rez;
  var ban = document.getElementById('rez-date-banner');
  var avail = document.getElementById('rez-avail-select');
  var form = document.getElementById('rez-form');
  if(!ban) return;

  if(!r.startDate){ ban.style.display='none'; if(avail){avail.style.display='none';avail.innerHTML='';} if(form){form.style.display='none';form.innerHTML='';} return; }
  if(!r.endDate){
    ban.style.display='block';
    ban.innerHTML = '<div style="background:#1a8c1a;color:#fff;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
      '<span>Vybrán začátek: <strong>'+MG.formatDate(r.startDate)+'</strong> — klikněte na koncové datum</span>' +
      '<span class="btn btngreen-small" style="background:#74FB71;color:#0b0b0b;cursor:pointer" onclick="MG._rezResetDates();MG._rezRenderCal()">&#x2715; ZRUŠIT VÝBĚR</span></div>';
    if(avail){avail.style.display='none';avail.innerHTML='';} if(form){form.style.display='none';form.innerHTML='';}
    return;
  }

  ban.style.display='block';
  ban.innerHTML = '<div style="background:#1a8c1a;color:#fff;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
    '<span>MÁTE VYBRANÝ TERMÍN: <strong>'+MG.formatDate(r.startDate)+' - '+MG.formatDate(r.endDate)+'</strong></span>' +
    '<span class="btn btngreen-small" style="background:#74FB71;color:#0b0b0b;cursor:pointer" onclick="MG._rezResetDates();MG._rezRenderCal()">&#x2715; ZRUŠIT VÝBĚR</span></div>';

  if(!r.motoId) MG._rezShowAvailMotos(); else MG._rezShowForm();
};

// ===== AVAILABLE MOTOS DROPDOWN (libovolná mode) =====
MG._rezShowAvailMotos = function(){
  var r = MG._rez, el = document.getElementById('rez-avail-select'); if(!el) return;
  var free = r.motos.filter(function(m){
    var map = r.allBookings[m.id] || {};
    var d = new Date(r.startDate);
    var end = new Date(r.endDate);
    while(d <= end){ if(map[d.toISOString().split('T')[0]]) return false; d.setDate(d.getDate()+1); }
    return true;
  });
  if(!free.length){
    el.style.display='block';
    el.innerHTML='<p style="color:#f66;margin:12px 0">V tomto termínu bohužel není dostupná žádná motorka.</p>';
    var f=document.getElementById('rez-form'); if(f){f.style.display='none';f.innerHTML='';}
    return;
  }
  var h = '<form class="form-product-select gr2" style="margin:12px 0"><div>Dostupné motorky:</div><select id="rez-avail-dropdown">' +
    '<option value="">— vyberte motorku —</option>';
  free.forEach(function(m){ h += '<option value="'+m.id+'">'+m.model+'</option>'; });
  h += '</select></form>';
  el.style.display='block'; el.innerHTML = h;
  document.getElementById('rez-avail-dropdown').addEventListener('change', function(){
    MG._rez.selectedMotoId = this.value;
    if(this.value) MG._rezShowForm(); else { var f=document.getElementById('rez-form'); if(f){f.style.display='none';f.innerHTML='';} }
  });
};

// ===== SHOW BOOKING FORM =====
MG._rezShowForm = function(){
  var r = MG._rez, f = document.getElementById('rez-form'); if(!f) return;
  var mId = r.motoId || r.selectedMotoId;
  var moto = r.motos.find(function(m){ return m.id === mId; });
  var prodLabel = moto ? moto.model : 'Libovolná motorka';
  var price = moto ? MG.calcPrice(moto, r.startDate, r.endDate) : 0;

  f.style.display = 'block';
  f.innerHTML = '<p>&nbsp;</p>' +
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
    '<div><input type="checkbox" id="rez-delivery"><label for="rez-delivery">Přistavení motorky jinam, než na adresu motopůjčovny <span class="ctooltip">&#9432;<span class="ctooltiptext">Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (20 Kč/1 km).</span></span></label></div>' +
    '<div id="rez-delivery-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px"><input type="text" id="rez-delivery-address" placeholder="Zadejte adresu"></div>' +
    '<div><input type="radio" id="rez-return-same" name="rez-return" value="same" checked><label for="rez-return-same">Vrátit na stejném místě, kde bylo vyzvednuto</label></div>' +
    '<div><input type="radio" id="rez-return-other" name="rez-return" value="other"><label for="rez-return-other">Vrácení motorky jinde než na adrese motopůjčovny</label></div>' +
    '<div id="rez-pickup-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px"><input type="text" id="rez-pickup-address" placeholder="Zadejte adresu vrácení">' +
    '<div class="dfc" style="margin-top:.5rem"><div>Čas vrácení</div><input type="time" id="rez-return-time" style="max-width:200px"></div></div>' +
    '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Základní výbava spolujezdce - 690,- Kč <span class="ctooltip">&#9432;<span class="ctooltiptext">Příslušné velikosti, prosím, uveďte do pole POZNÁMKA. Pokud si nejste jisti velikostí, výbavu je možné vyzkoušet na místě.</span></span></label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče - 290,- Kč <span class="ctooltip">&#9432;<span class="ctooltiptext">Půjčujeme ve velikostech 39-46 a u dětí v rozmezí 29-35. Příslušnou velikost, prosím, zapište do pole POZNÁMKA.</span></span></label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce - 290,- Kč <span class="ctooltip">&#9432;<span class="ctooltiptext">Půjčujeme ve velikostech 39-46. Příslušnou velikost, prosím, zapište do pole POZNÁMKA.</span></span></label></div></div>' +
    '<textarea id="rez-note" placeholder="Poznámka"></textarea>' +
    '<div class="checkboxes">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required><div>* Souhlasím s <a href="#/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr"><div>Souhlasím se <a href="#/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing"><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo"><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>' +
    '<div class="dfcs" style="flex-wrap:wrap;gap:1rem;margin-top:1rem"><div><div id="rez-price-preview">'+(price ? 'Celková cena: <strong>'+MG.formatPrice(price)+'</strong>' : '')+'</div></div>' +
    '<div><div class="text-right"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div></div></div>';

  // Delivery toggle
  var dc = document.getElementById('rez-delivery');
  if(dc) dc.addEventListener('change',function(){ var p=document.getElementById('rez-delivery-panel'); if(p) p.style.display=this.checked?'block':'none'; });

  // Return location toggle
  var retOther = document.getElementById('rez-return-other');
  var retSame = document.getElementById('rez-return-same');
  if(retOther) retOther.addEventListener('change',function(){ var p=document.getElementById('rez-pickup-panel'); if(p) p.style.display=this.checked?'block':'none'; });
  if(retSame) retSame.addEventListener('change',function(){ var p=document.getElementById('rez-pickup-panel'); if(p) p.style.display='none'; });

  // Live price recalc on extras
  ['rez-eq-passenger','rez-eq-boots-rider','rez-eq-boots-passenger'].forEach(function(id){
    var cb = document.getElementById(id);
    if(cb) cb.addEventListener('change', function(){ MG._rezUpdatePrice(); });
  });
};

// ===== PRICE UPDATE =====
MG._rezUpdatePrice = function(){
  var r = MG._rez, mId = r.motoId || r.selectedMotoId;
  var moto = r.motos.find(function(m){ return m.id === mId; });
  var base = moto ? MG.calcPrice(moto, r.startDate, r.endDate) : 0;
  var extras = 0;
  if(document.getElementById('rez-eq-passenger') && document.getElementById('rez-eq-passenger').checked) extras += 690;
  if(document.getElementById('rez-eq-boots-rider') && document.getElementById('rez-eq-boots-rider').checked) extras += 290;
  if(document.getElementById('rez-eq-boots-passenger') && document.getElementById('rez-eq-boots-passenger').checked) extras += 290;
  var el = document.getElementById('rez-price-preview');
  if(el) el.innerHTML = 'Celková cena: <strong>'+MG.formatPrice(base + extras)+'</strong>';
};

// ===== VOUCHER FIELD =====
MG._addVoucherField = function(){
  var c = document.getElementById('rez-extra-vouchers'); if(!c) return;
  var d = document.createElement('div'); d.className = 'gr2 voucher-code';
  d.innerHTML = '<input type="text" placeholder="Slevový kód" maxlength="255">';
  c.appendChild(d);
};

// ===== SUBMIT =====
MG._submitReservation = function(){
  var name = document.getElementById('rez-name');
  var email = document.getElementById('rez-email');
  var phone = document.getElementById('rez-phone');
  var agree = document.getElementById('rez-agree-vop');
  if(!name || !name.value || !email || !email.value || !phone || !phone.value){
    alert('Vyplňte prosím všechna povinná pole.'); return;
  }
  if(!agree || !agree.checked){
    alert('Pro pokračování musíte souhlasit s obchodními podmínkami.'); return;
  }
  var r = MG._rez;
  if(!r.startDate || !r.endDate){ alert('Vyberte prosím termín v kalendáři.'); return; }
  var mId = r.motoId || r.selectedMotoId;
  if(!mId){ alert('Vyberte prosím motorku.'); return; }

  alert('Děkujeme za rezervaci! Tato funkce bude brzy plně propojená s rezervačním systémem.\n\nPro rezervaci nás prosím kontaktujte na '+MG.PHONE+' nebo '+MG.EMAIL_USER+'@'+MG.EMAIL_DOMAIN);
};
