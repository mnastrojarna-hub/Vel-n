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
  await MG._rezFetchBookings();
  // If start date is pre-filled, show that month; otherwise show current month
  var calDate = MG._rez.startDate ? new Date(MG._rez.startDate) : new Date();
  MG._rez.calYear = calDate.getFullYear(); MG._rez.calMonth = calDate.getMonth();
  MG._rezRenderCal();
  MG._rezStartLiveRefresh();
};

// ===== FETCH BOOKINGS (sdílená logika pro init i live refresh) =====
MG._rezFetchBookings = async function(){
  var motoId = MG._rez.motoId;
  var fresh = {};
  if(motoId){
    var bookings = await MG.fetchMotoBookings(motoId);
    fresh[motoId] = MG._rezBookedMap(bookings);
  } else {
    var motos = MG._rez.motos || [];
    for(var i = 0; i < motos.length; i++){
      var bk = await MG.fetchMotoBookings(motos[i].id);
      fresh[motos[i].id] = MG._rezBookedMap(bk);
    }
  }
  MG._rez.allBookings = fresh;
};

// ===== LIVE REFRESH (real-time polling pro anon usery — RLS blokuje subscribe) =====
MG._rezStartLiveRefresh = function(){
  if(MG._rezLiveTimer) return; // už běží
  MG._rezLiveTimer = setInterval(async function(){
    var cal = document.getElementById('rez-calendar');
    if(!cal){ MG._rezStopLiveRefresh(); return; }
    var prev = JSON.stringify(MG._rez.allBookings || {});
    await MG._rezFetchBookings();
    var next = JSON.stringify(MG._rez.allBookings || {});
    if(prev !== next) MG._rezRenderCal();
  }, 30000); // 30 s — drží krok s 4h pending oknem i 2min cron auto-cancel
};

MG._rezStopLiveRefresh = function(){
  if(MG._rezLiveTimer){ clearInterval(MG._rezLiveTimer); MG._rezLiveTimer = null; }
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

// ===== INJECT MODERN STYLES (jednorázově) =====
MG._rezInjectCalStyles = function(){
  if(document.getElementById('mg-rezcal-styles')) return;
  var st = document.createElement('style'); st.id='mg-rezcal-styles';
  st.textContent =
    '#rez-calendar{background:#fff;border:1px solid #d4e8e0;border-radius:18px;padding:1rem;box-shadow:0 4px 14px rgba(20,80,40,.06);font-family:Montserrat,sans-serif;margin:.4rem 0}'+
    '#rez-calendar .rezcal-nav{display:flex;align-items:center;justify-content:space-between;margin-bottom:.7rem;gap:.6rem}'+
    '#rez-calendar .rezcal-nav button{background:#1a8c1a;color:#fff;border:none;width:38px;height:38px;border-radius:999px;cursor:pointer;font-size:1.4rem;line-height:1;font-weight:700;transition:transform .12s}'+
    '#rez-calendar .rezcal-nav button:hover{transform:scale(1.06);background:#147214}'+
    '#rez-calendar .rezcal-title{font-weight:800;font-size:1.05rem;color:#1a2e22;text-align:center;flex:1}'+
    '#rez-calendar .rezcal-single{max-width:520px;margin:0 auto}'+
    '#rez-calendar .rezcal-month{}'+
    '#rez-calendar .rezcal-mhead{text-align:center;font-weight:700;color:#1a2e22;margin:.2rem 0 .55rem;font-size:.95rem;letter-spacing:.02em}'+
    '#rez-calendar .cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}'+
    '#rez-calendar .cal-header{font-size:.7rem;color:#7d978a;text-align:center;font-weight:700;padding:.2rem 0;letter-spacing:.04em;text-transform:uppercase}'+
    '#rez-calendar .cal-day{aspect-ratio:1/1;display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:10px;font-weight:700;font-size:.92rem;transition:transform .1s, box-shadow .1s, background .1s;user-select:none}'+
    '#rez-calendar .cal-day.empty{background:transparent}'+
    '#rez-calendar .cal-day.free{background:#74FB71;color:#0b0b0b;cursor:pointer}'+
    '#rez-calendar .cal-day.free:hover{transform:scale(1.07);box-shadow:0 3px 8px rgba(26,140,26,.25)}'+
    '#rez-calendar .cal-day.in-range{background:#1a8c1a;color:#fff;cursor:pointer}'+
    '#rez-calendar .cal-day.sel-start, #rez-calendar .cal-day.sel-end{background:#0f5e0f;color:#fff;box-shadow:0 0 0 2px #74FB71;cursor:pointer}'+
    '#rez-calendar .cal-day.occupied{background:#444;color:#fff;cursor:not-allowed}'+
    '#rez-calendar .cal-day.unconfirmed{background:#fff;color:#333;cursor:not-allowed;border:2px solid #ccc}'+
    '#rez-calendar .cal-day.past{background:#3a3a3a;color:#fff;cursor:not-allowed;opacity:.85}'+
    '#rez-calendar .cal-day.today{outline:2px solid #1a8c1a;outline-offset:-2px}'+
    '#rez-calendar .cal-day .dn{font-size:.6rem;opacity:.7;line-height:1}'+
    '#rez-calendar .calendar-icons{display:flex;flex-wrap:wrap;gap:.6rem 1.1rem;margin-top:.85rem;font-size:.78rem;color:#3a4a40}'+
    '#rez-calendar .calendar-icons div{display:inline-flex;align-items:center;gap:.35rem}'+
    '#rez-calendar .cicon{display:inline-block;width:11px;height:11px;border-radius:3px}'+
    '#rez-calendar .cicon.loosely{background:#74FB71}'+
    '#rez-calendar .cicon.occupied{background:#444}'+
    '#rez-calendar .cicon.unconfirmed{background:#fff;border:1.5px solid #ccc}'+
    '#rez-calendar .cicon.selrange{background:#1a8c1a}';
  document.head.appendChild(st);
};

// i18n helpers — názvy měsíců a dní z window.MG_I18N (sype lang/*.php přes
// pages/rezervace.php). Bez fallback hardcoded textů — pokud klíč chybí,
// MG.t vrátí samotný klíč a admin / dev to v konzoli ihned vidí.
MG._rezMonthNames = function(){
  var arr = []; for (var i = 0; i < 12; i++) arr.push(MG.t('rez.cal.month.' + i)); return arr;
};
MG._rezDayShortMon = function(){
  // Pondělí jako první den týdne (CZ konvence). dayShort.0=Po, .6=Ne
  var arr = []; for (var i = 0; i < 7; i++) arr.push(MG.t('rez.cal.dayShort.' + i)); return arr;
};
MG._rezDayShortSun = function(){
  // JS Date.getDay() vrací 0=Ne, 1=Po, ... — namapuj přes Mon-first pole
  // Ne=6, Po=0, Út=1, St=2, Čt=3, Pá=4, So=5 → výsledné pole indexované Date.getDay()
  var mon = MG._rezDayShortMon();
  return [mon[6], mon[0], mon[1], mon[2], mon[3], mon[4], mon[5]];
};

// ===== RENDER MĚSÍCE — pomocná =====
MG._rezRenderMonthHtml = function(y, m){
  var months = MG._rezMonthNames();
  var dayN = MG._rezDayShortMon();
  var dayFull = MG._rezDayShortSun();
  var first = new Date(y,m,1), last = new Date(y,m+1,0);
  var dow = (first.getDay()+6)%7;
  var todayStr = new Date().toISOString().split('T')[0];
  var sd = MG._rez.startDate, ed = MG._rez.endDate;

  var h = '<div class="rezcal-month"><div class="rezcal-mhead">'+months[m]+' '+y+'</div>';
  h += '<div class="cal-grid">';
  dayN.forEach(function(d){ h += '<div class="cal-header">'+d+'</div>'; });
  for(var i=0;i<dow;i++) h += '<div class="cal-day empty"></div>';

  for(var d=1;d<=last.getDate();d++){
    var ds = y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0');
    var isPast = ds < todayStr;
    var status = isPast ? 'past' : MG._rezDateStatus(ds);
    var inRange = sd && ed && ds >= sd && ds <= ed;
    var isStart = sd && ds === sd;
    var isEnd = ed && ds === ed;
    var dayOfWeek = dayFull[new Date(y,m,d).getDay()];

    var cls = ['cal-day'];
    var canClick = false;
    if(isPast){ cls.push('past'); }
    else if(status === 'occupied'){ cls.push('occupied'); }
    else if(status === 'unconfirmed'){ cls.push('unconfirmed'); }
    else { cls.push('free'); canClick = true; }
    if(isStart) cls.push('sel-start');
    else if(isEnd) cls.push('sel-end');
    else if(inRange) cls.push('in-range');
    if(ds === todayStr) cls.push('today');

    var click = canClick ? ' onclick="MG._rezPickDate(\''+ds+'\')"' : '';
    h += '<div class="'+cls.join(' ')+'"'+click+'>' +
      '<span class="dn">'+dayOfWeek+'</span>' +
      '<span>'+d+'</span></div>';
  }
  h += '</div></div>';
  return h;
};

// ===== RENDER CALENDAR (single month) =====
MG._rezRenderCal = function(){
  var cal = document.getElementById('rez-calendar'); if(!cal) return;
  MG._rezInjectCalStyles();
  var y = MG._rez.calYear, m = MG._rez.calMonth;
  var months = MG._rezMonthNames();

  var h = '<div class="rezcal-nav">'+
    '<button type="button" onclick="MG._rezCalPrev()" aria-label="'+MG.t('rez.cal.prev')+'">‹</button>'+
    '<span class="rezcal-title">'+months[m]+' '+y+'</span>'+
    '<button type="button" onclick="MG._rezCalNext()" aria-label="'+MG.t('rez.cal.next')+'">›</button>'+
    '</div>'+
    '<div class="rezcal-single">'+ MG._rezRenderMonthHtml(y, m) +'</div>'+
    '<div class="calendar-icons">' +
      '<div><span class="cicon loosely"></span> '+MG.t('rez.cal.legend.free')+'</div>' +
      '<div><span class="cicon selrange"></span> '+MG.t('rez.cal.legend.selected')+'</div>' +
      '<div><span class="cicon occupied"></span> '+MG.t('rez.cal.legend.occupied')+'</div>' +
      '<div><span class="cicon unconfirmed"></span> '+MG.t('rez.cal.legend.unconfirmed')+'</div>' +
    '</div>';
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
    el.innerHTML='<p style="color:#f66;margin:12px 0">'+MG.t('rez.cal.noMotoInRange')+'</p>';
    return;
  }
  var h = '<form class="rez-moto-pick rez-moto-pick-avail"><label for="rez-avail-dropdown">'+
    '<span class="rez-pick-badge">'+MG.t('rez.cal.freeInRange')+': '+free.length+'</span> '+MG.t('rez.cal.pickFromList')+'</label>' +
    '<div class="rez-moto-pick-wrap"><select id="rez-avail-dropdown">' +
    '<option value="">— '+MG.t('rez.cal.selectMoto')+' —</option>';
  free.forEach(function(m){ h += '<option value="'+m.id+'">'+m.model+'</option>'; });
  h += '</select></div></form>';
  el.style.display='block'; el.innerHTML = h;
  document.getElementById('rez-avail-dropdown').addEventListener('change', function(){
    MG._rez.selectedMotoId = this.value;
    MG._rezUpdatePrice();
  });
};
