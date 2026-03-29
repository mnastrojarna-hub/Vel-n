// ===== MotoGo24 Web — Rezervace: calendar + date picking + banner + avail motos =====
var MG = window.MG || {};
window.MG = MG;

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

// ===== DATE PICK LOGIC (2-step: 1. start, 2. end — same as app) =====
MG._rezPickDate = function(ds){
  var r = MG._rez;
  if(!r.startDate || (r.startDate && r.endDate)){
    // Krok 1: vybrat začátek (nebo reset pokud už je vybrán rozsah)
    r.startDate = ds; r.endDate = null;
  } else {
    // Krok 2: vybrat konec
    if(ds < r.startDate){
      // Klikl před začátek → nový začátek
      r.startDate = ds; r.endDate = null;
    } else {
      // Klikl na začátek nebo po něm → konec (jednodenní i vícedenní)
      // Ověřit, že celý rozsah je volný
      var allFree = true;
      var check = new Date(r.startDate);
      var end = new Date(ds);
      while(check <= end){
        var cs = check.toISOString().split('T')[0];
        if(cs !== r.startDate && cs !== ds && !MG._rezDateAvail(cs)){ allFree = false; break; }
        check.setDate(check.getDate() + 1);
      }
      if(!allFree){
        alert('V tomto rozsahu jsou obsazené dny. Vyberte jiný termín.');
        return;
      }
      r.endDate = ds;
    }
  }
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
