// ===== BOOKING-UTILS.JS – AppTime engine & rental utility functions =====

// ===== AppTime – Global time-aware engine =====
var AppTime = {
  now: function(){ return new Date(); },
  today: function(){
    var d = new Date(); d.setHours(0,0,0,0); return d;
  },
  todayISO: function(){ return AppTime.today().toISOString(); },
  isWeekend: function(date){
    var day = (date || new Date()).getDay();
    return day === 0 || day === 5 || day === 6; // Pa-Ne
  },
  isWorkday: function(date){ return !AppTime.isWeekend(date); },
  isPast: function(date){
    return new Date(date).setHours(0,0,0,0) < AppTime.today().getTime();
  },
  isFuture: function(date){
    return new Date(date).setHours(0,0,0,0) > AppTime.today().getTime();
  },
  isToday: function(date){
    return new Date(date).setHours(0,0,0,0) === AppTime.today().getTime();
  }
};

// ===== Rental duration (exact days) =====
function calcRentalDays(startDate, endDate){
  var s = new Date(startDate); s.setHours(0,0,0,0);
  var e = new Date(endDate);   e.setHours(0,0,0,0);
  return Math.max(1, Math.round((e - s) / 86400000) + 1);
}

// ===== Rental hours (for sub-day precision) =====
function calcRentalHours(startISO, endISO){
  return Math.max(1, Math.round((new Date(endISO) - new Date(startISO)) / 3600000));
}

// ===== Day-of-week price for a single date =====
function dayPrice(moto, date){
  var p = moto.pricing;
  if(!p) return 2600;
  var dow = new Date(date).getDay();
  // 0=Ne,1=Po,2=Ut,3=St,4=Ct,5=Pa,6=So
  var map = [p.ne, p.po, p.ut, p.st, p.ct, p.pa, p.so];
  return map[dow] || p.po || 2600;
}

// ===== Total price across date range (day-of-week aware) =====
function calcTotalPrice(moto, startDate, endDate){
  var s = new Date(startDate); s.setHours(0,0,0,0);
  var e = new Date(endDate);   e.setHours(0,0,0,0);
  var total = 0;
  var d = new Date(s);
  while(d <= e){
    total += dayPrice(moto, d);
    d.setDate(d.getDate() + 1);
  }
  return total || dayPrice(moto, s);
}

// ===== Reservation status from dates =====
function getResStatus(startDate, endDate){
  var now = AppTime.today().getTime();
  var s = new Date(startDate); s.setHours(0,0,0,0);
  var e = new Date(endDate);   e.setHours(0,0,0,0);
  if(now > e.getTime()) return 'dokoncena';
  if(now >= s.getTime() && now <= e.getTime()) return 'aktivni';
  return 'nadchazejici';
}

// ===== Can a reservation be modified? =====
function canModifyRes(startDate, endDate){
  var status = getResStatus(startDate, endDate);
  if(status === 'dokoncena') return { extend: false, shorten: false, cancel: false };
  if(status === 'aktivni')   return { extend: true, shorten: true, cancel: false };
  // nadchazejici
  return { extend: true, shorten: true, cancel: true };
}

// ===== ISO helpers for localStorage =====
function dateToISO(d, m, y){
  return new Date(y, m, d).toISOString();
}

function isoToDateObj(iso){
  var dt = new Date(iso);
  return { d: dt.getDate(), m: dt.getMonth(), y: dt.getFullYear() };
}

// ===== Save / load reservations in localStorage (ISO format) =====
function saveReservation(resId, data){
  try {
    var all = JSON.parse(localStorage.getItem('mg_reservations') || '{}');
    data.updatedAt = AppTime.now().toISOString();
    if(data.startDate && !(typeof data.startDate === 'string'))
      data.startDate = data.startDate.toISOString();
    if(data.endDate && !(typeof data.endDate === 'string'))
      data.endDate = data.endDate.toISOString();
    all[resId] = data;
    localStorage.setItem('mg_reservations', JSON.stringify(all));
  } catch(e){}
}

function loadReservation(resId){
  try {
    var all = JSON.parse(localStorage.getItem('mg_reservations') || '{}');
    return all[resId] || null;
  } catch(e){ return null; }
}

function loadAllReservations(){
  try {
    return JSON.parse(localStorage.getItem('mg_reservations') || '{}');
  } catch(e){ return {}; }
}

// ===== PER-MOTORCYCLE AVAILABILITY =====
var MOTO_OCC = {};
var MOTO_UNCONF = {};

function _normName(s){ return (s||'').replace(/\s+/g,'').toLowerCase(); }

function initMotoAvailability(){
  if(typeof _isSupabaseReady === 'function' && _isSupabaseReady()){
    _initMotoAvailabilityAsync();
  }
}

async function _initMotoAvailabilityAsync(){
  try {
    var bookings = await apiFetchMyBookings('all');
    if(typeof MOTOS === 'undefined') return;
    MOTOS.forEach(function(m){
      var occ = {};
      var unc = {};
      // Použij _db.id z enrichMOTOS (UUID), fallback na lokální ID
      var dbId = (m._db && m._db.id) ? m._db.id : m.id;
      var motoBookings = bookings.filter(function(b){
        return b.moto_id && (b.moto_id === m.id || b.moto_id === dbId);
      });
      _fillOccFromBookings(motoBookings, occ, unc);
      MOTO_OCC[m.id] = occ;
      MOTO_UNCONF[m.id] = unc;
    });
    if(typeof syncGlobalOcc === 'function') syncGlobalOcc();
  } catch(e){
    console.error('_initMotoAvailabilityAsync error:', e);
  }
}

function _fillOccFromBookings(motoBookings, occ, unc){
  motoBookings.forEach(function(b){
    if(b.status === 'cancelled') return;
    var sd = new Date(b.start_date); sd.setHours(0,0,0,0);
    var ed = new Date(b.end_date); ed.setHours(0,0,0,0);
    var d = new Date(sd);
    while(d <= ed){
      var month = d.getMonth();
      var day = d.getDate();
      if(b.payment_status === 'paid' || b.status === 'confirmed'){
        if(!occ[month]) occ[month] = [];
        if(occ[month].indexOf(day) === -1) occ[month].push(day);
      } else {
        if(!unc[month]) unc[month] = [];
        if(unc[month].indexOf(day) === -1) unc[month].push(day);
      }
      d.setDate(d.getDate() + 1);
    }
  });
}

// Rebuild global OCC/UNCONF from per-moto data.
// A date is globally occupied only if ALL motos are occupied that day.
function syncGlobalOcc(){
  // Clear old static data
  for(var k in OCC) delete OCC[k];
  for(var k2 in UNCONF) delete UNCONF[k2];
  if(!MOTOS || MOTOS.length === 0) return;
  // Collect all months that have any data
  var allMonths = {};
  MOTOS.forEach(function(m){
    var occ = MOTO_OCC[m.id] || {};
    var unc = MOTO_UNCONF[m.id] || {};
    for(var mo in occ)(allMonths[mo] = allMonths[mo] || new Set(), occ[mo].forEach(function(d){ allMonths[mo].add(d); }));
    for(var mo2 in unc)(allMonths[mo2] = allMonths[mo2] || new Set(), unc[mo2].forEach(function(d){ allMonths[mo2].add(d); }));
  });
  // A date is globally occupied only if EVERY moto is occupied or unconfirmed
  var totalMotos = MOTOS.length;
  for(var month in allMonths){
    var mi = parseInt(month);
    allMonths[month].forEach(function(day){
      var occCount = 0; var uncCount = 0;
      MOTOS.forEach(function(m){
        var mocc = MOTO_OCC[m.id] ? (MOTO_OCC[m.id][mi] || []) : [];
        var munc = MOTO_UNCONF[m.id] ? (MOTO_UNCONF[m.id][mi] || []) : [];
        if(mocc.indexOf(day) !== -1) occCount++;
        else if(munc.indexOf(day) !== -1) uncCount++;
      });
      if(occCount >= totalMotos){
        if(!OCC[mi]) OCC[mi] = [];
        if(OCC[mi].indexOf(day) === -1) OCC[mi].push(day);
      } else if(occCount + uncCount >= totalMotos){
        if(!UNCONF[mi]) UNCONF[mi] = [];
        if(UNCONF[mi].indexOf(day) === -1) UNCONF[mi].push(day);
      }
    });
  }
}

function isMotoFreeOnDate(motoId, d, m){
  if(!MOTO_OCC[motoId]) return true;
  var occ = MOTO_OCC[motoId][m] || [];
  var unc = MOTO_UNCONF[motoId] ? (MOTO_UNCONF[motoId][m] || []) : [];
  return occ.indexOf(d) === -1 && unc.indexOf(d) === -1;
}

function isMotoFreeToday(motoId){
  return isMotoFreeOnDate(motoId, TODAY_D, TODAY_M);
}

function isMotoFreeForRange(motoId, startDate, endDate){
  var d = new Date(startDate); d.setHours(0,0,0,0);
  var e = new Date(endDate); e.setHours(0,0,0,0);
  while(d <= e){
    if(!isMotoFreeOnDate(motoId, d.getDate(), d.getMonth())) return false;
    d.setDate(d.getDate() + 1);
  }
  return true;
}

function getMotoOcc(motoId, m){
  if(!MOTO_OCC[motoId]) return OCC[m] || [];
  return MOTO_OCC[motoId][m] || [];
}
function getMotoUnconf(motoId, m){
  if(!MOTO_UNCONF[motoId]) return UNCONF[m] || [];
  return MOTO_UNCONF[motoId][m] || [];
}

// ===== Check if a motorcycle is free today (backward compat) =====
function isTodayFree(motoId){
  if(motoId) return isMotoFreeToday(motoId);
  var occ=OCC[TODAY_M]||[];
  var unc=UNCONF[TODAY_M]||[];
  return !occ.includes(TODAY_D)&&!unc.includes(TODAY_D);
}

// ===== Check if a date is free in calendar =====
function isDateFree(d,m,motoId){
  if(motoId) return isMotoFreeOnDate(motoId, d, m);
  var occ=OCC[m]||[];
  var unc=UNCONF[m]||[];
  return !occ.includes(d)&&!unc.includes(d);
}

// ===== Update reservation buttons based on time =====
function updateResButtons(){
  var actStatus = getResStatus(
    new Date(ACT_START.y, ACT_START.m, ACT_START.d),
    new Date(ACT_END.y, ACT_END.m, ACT_END.d)
  );
  var actBtns = document.getElementById('rc-act-btns');
  if(actBtns){
    if(actStatus === 'aktivni'){
      actBtns.innerHTML =
        '<div class="rbtn g" onclick="event.stopPropagation();openResDetail(\'aktivni\')">📋 Detail</div>'+
        '<div class="rbtn" style="background:var(--green);color:#fff;border-color:var(--green);" onclick="event.stopPropagation();openResDetail(\'aktivni-upravit\')">⏱ Prodloužit výpůjčku</div>'+
        '<div class="rbtn" style="background:#fee2e2;color:#b91c1c;border-color:#fca5a5;" onclick="event.stopPropagation();goTo(\'s-sos\')">🆘 Porucha</div>';
    } else if(actStatus === 'dokoncena'){
      actBtns.innerHTML =
        '<div class="rbtn g" onclick="event.stopPropagation();openDoneDetail(\'jawa\')">📋 Detail jízdy</div>'+
        '<div class="rbtn" style="background:var(--dark);color:#fff;border-color:var(--dark);" onclick="event.stopPropagation();goTo(\'s-protocol\')">📝 Vrátit / Protokol</div>';
    }
  }

  // Save demo reservations to localStorage in ISO
  saveReservation('RES-'+ACT_START.y+'-0031', {
    moto: 'Jawa RVM 500 Adventure',
    startDate: dateToISO(ACT_START.d, ACT_START.m, ACT_START.y),
    endDate: dateToISO(ACT_END.d, ACT_END.m, ACT_END.y),
    status: actStatus
  });
  saveReservation('RES-'+UPC_START.y+'-0043', {
    moto: 'BMW R 1200 GS Adventure',
    startDate: dateToISO(UPC_START.d, UPC_START.m, UPC_START.y),
    endDate: dateToISO(UPC_END.d, UPC_END.m, UPC_END.y),
    status: getResStatus(
      new Date(UPC_START.y, UPC_START.m, UPC_START.d),
      new Date(UPC_END.y, UPC_END.m, UPC_END.d)
    )
  });
}
