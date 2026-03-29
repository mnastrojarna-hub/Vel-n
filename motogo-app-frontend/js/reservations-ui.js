/* === RESERVATIONS-UI.JS — Global vars, list rendering, FABs, filters, sorting, card rendering === */

// ===== RESERVATIONS-UI.JS – Dynamic reservation list & detail =====
// Renders reservation cards from Supabase backend data.

var _resFilter = 'all';
var _resSort = 'start_desc';
var _cachedBookings = null;

async function _getBookingById(bookingId){
  if(_isSupabaseReady()){
    try {
      var result = await supabase.from('bookings').select('*, motorcycles(*, branches(name, address, city))').eq('id',bookingId).single();
      if(result.data) return result.data;
    } catch(e){}
  }
  return null;
}

async function _getMotoById(motoId){
  if(_isSupabaseReady()){
    try {
      var result = await supabase.from('motorcycles').select('*, branches(name, address, city)').eq('id',motoId).single();
      if(result.data) return result.data;
    } catch(e){}
  }
  return null;
}

function filterRes(el, filter){
  try {
    _resFilter = filter;
    document.querySelectorAll('#s-res .chip').forEach(function(c){ c.classList.remove('active'); });
    if(el) el.classList.add('active');
    renderMyReservations();
  } catch(e){ console.error('filterRes error:', e); }
}

async function renderMyReservations(){
  try {
    var session = await _getSession();
    if(!session) return;

    var bookings = await apiFetchMyBookings();
    _cachedBookings = bookings;
    if(!bookings || bookings.length === 0){
      _setResContent('<div style="padding:40px 20px;text-align:center;color:var(--g400);font-size:13px;font-weight:600;">'+_t('res').noReservations+'</div>');
      return;
    }

    // Populate extended filter dropdowns (branches, motos)
    _resPopulateExtFilters(bookings);

    // Filter by status
    var filtered = bookings;
    if(_resFilter !== 'all'){
      filtered = bookings.filter(function(b){
        var st = _mapStatus(b.status, b.start_date, b.end_date, b);
        return st === _resFilter;
      });
    }

    // Extended filters (branch, moto)
    var branchFilter = (document.getElementById('res-filter-branch') || {}).value || '';
    var motoFilter = (document.getElementById('res-filter-moto') || {}).value || '';
    if(branchFilter){
      filtered = filtered.filter(function(b){
        var m = b.motorcycles;
        var branchName = m && m.branches ? (m.branches.name || '') : '';
        return branchName === branchFilter;
      });
    }
    if(motoFilter){
      filtered = filtered.filter(function(b){
        return b.moto_name === motoFilter;
      });
    }

    // Sort
    filtered = _resSortBookings(filtered, _resSort);

    if(filtered.length === 0){
      _setResContent('<div style="padding:40px 20px;text-align:center;color:var(--g400);font-size:13px;font-weight:600;">'+_t('res').noInCategory+'</div>');
      return;
    }

    var html = filtered.map(function(b){ return _renderResCard(b); }).join('');
    _setResContent(html);
  } catch(e){ console.error('renderMyReservations error:', e); }
}

// ===== SOS REPLACEMENT FAB (small, cart-style) =====
// Navigation helper: shows only during replacement flow (selecting / pending_payment).
// Lets user return to motorcycle selection if they accidentally leave the screen.
// After payment or free selection → replacement_status changes → FAB disappears.
// Dismiss (X) = just hides the banner, no DB changes.

function _checkAndShowSosFab(){
  if(typeof apiCheckPendingSosReplacement !== 'function') return;
  if(!_isSupabaseReady() || !window.supabase) return;
  window.supabase.auth.getUser().then(function(r){
    if(!r.data || !r.data.user) return;
    apiCheckPendingSosReplacement().then(function(pending){
      var fab = document.getElementById('sos-repl-fab');
      if(!fab) return;
      if(pending){
        // Check if dismissed for this incident
        var dismissed = {};
        try {
          dismissed = JSON.parse(localStorage.getItem('mg_sos_fab_dismissed') || '{}');
          // Prune entries older than 7 days
          var _now = Date.now(), _7d = 7*24*60*60*1000, _changed = false;
          for(var _dk in dismissed){
            if(dismissed.hasOwnProperty(_dk)){
              var _ts = dismissed[_dk];
              if(_ts === true || (typeof _ts==='number' && _now - _ts > _7d)){ delete dismissed[_dk]; _changed=true; }
            }
          }
          if(_changed) localStorage.setItem('mg_sos_fab_dismissed', JSON.stringify(dismissed));
        } catch(e){}
        if(dismissed[pending.id]){
          fab.style.display = 'none'; return;
        }
        window._pendingSosIncident = pending;
        window._sosFabIncidentId = pending.id;
        var label = document.getElementById('sos-repl-fab-text');
        if(label) label.textContent = 'SOS dokončit';
        fab.style.display = 'flex';
      } else {
        fab.style.display = 'none';
        window._pendingSosIncident = null;
        window._sosFabIncidentId = null;
      }
    }).catch(function(){ var f=document.getElementById('sos-repl-fab'); if(f) f.style.display='none'; });
  }).catch(function(){});
}

function sosFabClick(){
  goTo('s-sos-replacement');
}

function dismissSosFab(){
  // Just hide the banner — no DB changes
  var fab = document.getElementById('sos-repl-fab');
  if(fab) fab.style.display = 'none';
  if(window._sosFabIncidentId){
    try {
      var d = JSON.parse(localStorage.getItem('mg_sos_fab_dismissed') || '{}');
      d[window._sosFabIncidentId] = Date.now();
      localStorage.setItem('mg_sos_fab_dismissed', JSON.stringify(d));
    } catch(e){}
  }
}

// ===== PENDING BOOKING FAB (unpaid reserved bookings — 10 min to pay) =====
var _pendingBookingId = null;
var _pendingBookingData = null;
var _bookingFabTimer = null;
var _BOOKING_EXPIRY_MS = 600000; // 10 minutes

function _checkAndShowBookingFab(){
  if(!window.supabase) return;
  _getSession().then(function(session){
    if(!session) return;
    var uid = session.user_id || (session.user && session.user.id);
    window.supabase.from('bookings')
      .select('id, status, payment_status, total_price, created_at')
      .eq('user_id', uid)
      .in('status', ['reserved','pending'])
      .eq('payment_status', 'unpaid')
      .order('created_at', {ascending: false})
      .limit(1)
      .then(function(r){
        if(r.error){ console.error('[FAB] booking query error:', r.error); }
        var fab = document.getElementById('booking-fab');
        if(!fab) return;
        if(r.data && r.data.length > 0){
          var bk = r.data[0];
          var created = new Date(bk.created_at).getTime();
          var remaining = _BOOKING_EXPIRY_MS - (Date.now() - created);
          if(remaining <= 0){
            fab.style.display = 'none';
            return;
          }
          _pendingBookingId = bk.id;
          _pendingBookingData = bk;
          fab.style.display = 'flex';
          _startBookingFabCountdown(created);
        } else {
          fab.style.display = 'none';
          _pendingBookingId = null;
          _pendingBookingData = null;
          if(_bookingFabTimer){ clearInterval(_bookingFabTimer); _bookingFabTimer = null; }
        }
      });
  }).catch(function(e){ console.error('[FAB] session error:', e); });
}

function _startBookingFabCountdown(createdTs){
  if(_bookingFabTimer) clearInterval(_bookingFabTimer);
  var label = document.getElementById('booking-fab-text');
  var fab = document.getElementById('booking-fab');
  function update(){
    var remaining = _BOOKING_EXPIRY_MS - (Date.now() - createdTs);
    if(remaining <= 0){
      if(_bookingFabTimer){ clearInterval(_bookingFabTimer); _bookingFabTimer = null; }
      if(fab) fab.style.display = 'none';
      _pendingBookingId = null;
      _pendingBookingData = null;
      return;
    }
    var min = Math.floor(remaining / 60000);
    var sec = Math.floor((remaining % 60000) / 1000);
    var timeStr = min + ':' + (sec < 10 ? '0' : '') + sec;
    if(label) label.textContent = 'Dokončit rezervaci · ' + timeStr;
  }
  update();
  _bookingFabTimer = setInterval(update, 1000);
}

function dismissBookingFab(){
  var fab = document.getElementById('booking-fab');
  if(fab) fab.style.display = 'none';
  if(_bookingFabTimer){ clearInterval(_bookingFabTimer); _bookingFabTimer = null; }
  // Cancel booking in DB — zákazník si to rozmyslel
  if(_pendingBookingId && window.supabase){
    window.supabase.from('bookings').update({
      status: 'cancelled',
      cancelled_by_source: 'customer',
      cancellation_reason: 'Zákazník si to rozmyslel',
      cancelled_at: new Date().toISOString()
    }).eq('id', _pendingBookingId).eq('payment_status', 'unpaid').then(function(){});
    showT('✗','Rezervace zrušena','Rezervace byla zrušena');
  }
  // Clear payment timeout if still running
  if(typeof _paymentTimeout !== 'undefined' && _paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }
  if(typeof _currentBookingId !== 'undefined') _currentBookingId = null;
  _pendingBookingId = null;
  _pendingBookingData = null;
}

function goToBookingFab(){
  if(!_pendingBookingId || !_pendingBookingData) return;
  var bk = _pendingBookingData;
  // Set up payment context and go to payment screen
  if(typeof _currentBookingId !== 'undefined') _currentBookingId = bk.id;
  if(typeof _currentPaymentAmount !== 'undefined') _currentPaymentAmount = bk.total_price || 0;
  if(typeof _currentPaymentMethod !== 'undefined') _currentPaymentMethod = 'card';
  if(typeof _paymentAttempts !== 'undefined') _paymentAttempts = 0;
  // Update payment button
  var payBtn = document.getElementById('pay-btn');
  if(payBtn){
    payBtn.textContent = 'Zaplatit ' + (bk.total_price || 0).toLocaleString('cs-CZ') + ' Kč →';
    payBtn.onclick = function(){ doPayment(); };
  }
  var applePayBtn = document.getElementById('apple-pay-btn');
  if(applePayBtn) applePayBtn.textContent = '🍎 Pay ' + (bk.total_price || 0).toLocaleString('cs-CZ') + ' Kč';
  goTo('s-payment');
}

function _updateBookingFabVisibility(){
  var fab = document.getElementById('booking-fab');
  if(!fab) return;
  // Hide on payment flow screens (user is already paying) and auth
  var hideOn = ['s-login','s-register','s-doc-scan','s-payment','s-success'];
  if(hideOn.indexOf(cur) !== -1){ fab.style.display = 'none'; return; }
  // Re-check on ANY screen outside hideOn — FAB must be visible everywhere
  _checkAndShowBookingFab();
}

function _updateSosFabVisibility(){
  var fab = document.getElementById('sos-repl-fab');
  if(!fab) return;
  // Hide on certain screens (SOS flow screens, auth)
  var hideOn = ['s-login','s-register','s-docs','s-sos','s-sos-nehoda','s-sos-nepojizda','s-sos-porucha','s-sos-nepojizda-porucha','s-sos-servis','s-sos-kradez','s-sos-replacement','s-sos-payment','s-sos-done'];
  if(hideOn.indexOf(cur) !== -1){ fab.style.display = 'none'; return; }
  // Re-check on navigation to main screens (FAB might need refresh after SOS resolved)
  var recheckOn = ['s-home','s-res','s-search','s-profile'];
  if(recheckOn.indexOf(cur) !== -1 && typeof _checkAndShowSosFab === 'function'){
    _checkAndShowSosFab();
  }
}

function _setResContent(html){
  // Render into #res-list container inside s-res
  var resList = document.getElementById('res-list');
  if(resList){ resList.innerHTML = html; return; }
  // Fallback: append to screen
  var resScreen = document.getElementById('s-res');
  if(!resScreen) return;
  var existing = resScreen.querySelector('.res-cards-dynamic');
  if(existing) existing.remove();
  var container = document.createElement('div');
  container.className = 'res-cards-dynamic';
  container.innerHTML = html;
  resScreen.appendChild(container);
}

// ===== SORTING =====
function resApplySort(val){
  _resSort = val;
  renderMyReservations();
}

function _resSortBookings(arr, sortKey){
  var copy = arr.slice();
  copy.sort(function(a, b){
    switch(sortKey){
      case 'start_asc': return new Date(a.start_date) - new Date(b.start_date);
      case 'start_desc': return new Date(b.start_date) - new Date(a.start_date);
      case 'created_asc': return new Date(a.created_at) - new Date(b.created_at);
      case 'created_desc': return new Date(b.created_at) - new Date(a.created_at);
      case 'price_asc': return (a.total_price||0) - (b.total_price||0);
      case 'price_desc': return (b.total_price||0) - (a.total_price||0);
      case 'rating_desc': return (b.rating||0) - (a.rating||0);
      default: return new Date(b.start_date) - new Date(a.start_date);
    }
  });
  return copy;
}

// ===== EXTENDED FILTERS =====
function resToggleExtFilter(){
  var el = document.getElementById('res-ext-filter');
  var btn = document.getElementById('res-filter-toggle');
  if(!el) return;
  var visible = el.style.display !== 'none';
  el.style.display = visible ? 'none' : 'block';
  if(btn) btn.style.background = visible ? '#fff' : 'var(--gp)';
  if(btn) btn.style.borderColor = visible ? 'var(--g200)' : 'var(--green)';
}

function resClearExtFilter(){
  var branchSel = document.getElementById('res-filter-branch');
  var motoSel = document.getElementById('res-filter-moto');
  if(branchSel) branchSel.value = '';
  if(motoSel) motoSel.value = '';
  renderMyReservations();
}

function _resPopulateExtFilters(bookings){
  var branchSel = document.getElementById('res-filter-branch');
  var motoSel = document.getElementById('res-filter-moto');
  if(!branchSel && !motoSel) return;
  var branches = {}, motos = {};
  for(var i = 0; i < bookings.length; i++){
    var b = bookings[i];
    var m = b.motorcycles || null;
    if(m && m.branches && m.branches.name) branches[m.branches.name] = 1;
    if(b.moto_name) motos[b.moto_name] = 1;
  }
  var branchVal = branchSel ? branchSel.value : '';
  var motoVal = motoSel ? motoSel.value : '';
  if(branchSel){
    var bhtml = '<option value="">Všechny</option>';
    Object.keys(branches).sort().forEach(function(name){ bhtml += '<option value="'+name+'"'+(name===branchVal?' selected':'')+'>'+name+'</option>'; });
    branchSel.innerHTML = bhtml;
  }
  if(motoSel){
    var mhtml = '<option value="">Všechny</option>';
    Object.keys(motos).sort().forEach(function(name){ mhtml += '<option value="'+name+'"'+(name===motoVal?' selected':'')+'>'+name+'</option>'; });
    motoSel.innerHTML = mhtml;
  }
}

function _mapStatus(status, startDate, endDate, booking){
  if(status === 'cancelled') return 'cancelled';
  if(status === 'completed') return 'dokoncene';
  // ended_by_sos = always completed regardless of dates
  if(booking && booking.ended_by_sos) return 'dokoncene';
  var nowFull = new Date();
  var now = new Date(nowFull); now.setHours(0,0,0,0);
  var s = _parseDateSafe(startDate); s.setHours(0,0,0,0);
  var eFull = _parseDateSafe(endDate);
  var e = new Date(eFull); e.setHours(0,0,0,0);
  if(now > e) return 'dokoncene';
  // Delivery/svoz return: přesný čas end_date — když uplynul, je dokončené
  if(booking && booking.return_method === 'delivery' && now.getTime() === e.getTime()){
    if(nowFull >= eFull) return 'dokoncene';
  }
  if(now >= s && now <= e) return 'aktivni';
  return 'nadchazejici';
}

function _statusLabel(st){
  var map = {aktivni:_t('res').active, nadchazejici:_t('res').upcoming, dokoncene:_t('res').completed, cancelled:_t('res').cancelled};
  return map[st] || st;
}

function _statusClass(st){
  var map = {aktivni:'s-act', nadchazejici:'s-up', dokoncene:'s-done', cancelled:'s-done'};
  return map[st] || '';
}

function _parseDateSafe(str){
  if(!str) return null;
  if(typeof str==='string' && str.length===10) str += 'T12:00:00';
  return new Date(str);
}

function _fmtDate(iso){
  try {
    var d = _parseDateSafe(iso);
    if(!d || isNaN(d.getTime())) return '—';
    return d.getDate() + '. ' + (d.getMonth()+1) + '. ' + d.getFullYear();
  } catch(e){ return '—'; }
}

function _fmtDateRange(isoStart, isoEnd){
  try {
    var s = _parseDateSafe(isoStart);
    var e = _parseDateSafe(isoEnd);
    s.setHours(0,0,0,0); e.setHours(0,0,0,0);
    if(s.getTime() === e.getTime()) return _fmtDate(isoStart);
    var sd = s.getDate(), sm = s.getMonth()+1, sy = s.getFullYear();
    var ed = e.getDate(), em = e.getMonth()+1, ey = e.getFullYear();
    if(sy === ey && sm === em) return sd+'. – '+ed+'. '+em+'. '+ey;
    if(sy === ey) return sd+'. '+sm+'. – '+ed+'. '+em+'. '+ey;
    return sd+'. '+sm+'. '+sy+' – '+ed+'. '+em+'. '+ey;
  } catch(ex){ return '—'; }
}

function _renderResCard(b){
  var st = _mapStatus(b.status, b.start_date, b.end_date, b);
  var stLabel = _statusLabel(st);
  var stClass = _statusClass(st);
  var s = new Date(b.start_date); s.setHours(0,0,0,0);
  var e = new Date(b.end_date); e.setHours(0,0,0,0);
  var days = Math.max(1, Math.round((e-s)/86400000)+1);
  var img = b.moto_image || '';
  var name = b.moto_name || 'Motorka';
  var grayscale = (st === 'dokoncene' || st === 'cancelled') ? 'filter:grayscale(.5);' : '';

  // SOS replacement badges
  var sosBadge = '';
  if(b.sos_replacement){
    sosBadge = '<div style="background:#dcfce7;color:#1a8a18;border-radius:50px;padding:3px 10px;font-size:10px;font-weight:800;display:inline-block;margin-top:4px;">🏍️ Náhradní motorka (SOS)</div>';
  } else if(b.ended_by_sos){
    sosBadge = '<div style="background:#fee2e2;color:#b91c1c;border-radius:50px;padding:3px 10px;font-size:10px;font-weight:800;display:inline-block;margin-top:4px;">🆘 Ukončeno — SOS incident</div>';
  }

  var btns = '';
  if(st === 'aktivni'){
    btns = '<div class="rbtn g" onclick="event.stopPropagation();openResDetailById(\''+b.id+'\')">📋 '+_t('res').detail+'</div>' +
           '<div class="rbtn" style="background:var(--green);color:#fff;border-color:var(--green);" onclick="event.stopPropagation();openEditResByBookingId(\''+b.id+'\')">⏱ '+_t('res').extendRental+'</div>' +
           '<div class="rbtn" style="background:#fee2e2;color:#b91c1c;border-color:#fca5a5;" onclick="event.stopPropagation();goTo(\'s-sos\')">🆘 '+_t('res').fault+'</div>';
  } else if(st === 'nadchazejici'){
    btns = '<div class="rbtn g" onclick="event.stopPropagation();openResDetailById(\''+b.id+'\')">📋 '+_t('res').detail+'</div>' +
           '<div class="rbtn" style="background:var(--green);color:#fff;border-color:var(--green);" onclick="event.stopPropagation();openEditResByBookingId(\''+b.id+'\')">✏️ '+_t('res').editReservation+'</div>';
  } else if(st === 'dokoncene'){
    btns = '<div class="rbtn g" onclick="event.stopPropagation();openResDetailById(\''+b.id+'\')">📋 '+_t('res').rideDetail+'</div>' +
           '<div class="rbtn" onclick="event.stopPropagation();openResDetailById(\''+b.id+'\')">⭐ '+_t('res').rate+'</div>';
  } else if(st === 'cancelled'){
    btns = '<div class="rbtn g" onclick="event.stopPropagation();openResDetailById(\''+b.id+'\')">📋 '+_t('res').detail+'</div>' +
           '<div class="rbtn" style="background:var(--green);color:#fff;border-color:var(--green);" onclick="event.stopPropagation();restoreBooking(\''+b.id+'\')">🔄 '+_t('res').restoreRes+'</div>';
  }

  return '<div class="rcard" onclick="openResDetailById(\''+b.id+'\')">' +
    '<div class="rci" style="'+grayscale+'"><img src="'+img+'" onerror="this.style.display=\'none\'" loading="lazy"><div class="rcio"><div><div class="rcn">'+name+'</div><div class="rcid">#'+b.id.substr(-8).toUpperCase()+'</div>'+sosBadge+'</div></div><div class="rst '+stClass+'">'+stLabel+'</div></div>' +
    '<div class="rcb"><div class="rcinfo"><div class="rccol"><div class="rccol-l">'+_t('res').date+'</div><div class="rccol-v">'+_fmtDateRange(b.start_date, b.end_date)+'</div></div><div class="rccol"><div class="rccol-l">'+_t('res').duration+'</div><div class="rccol-v">'+days+' '+(days===1?_t('res').day1:_t('res').days5)+'</div></div><div class="rccol"><div class="rccol-l">'+_t('res').total+'</div><div class="rccol-v">'+(b.total_price||0).toLocaleString('cs-CZ')+' Kč</div></div></div>' +
    '<div class="ract">'+btns+'</div></div></div>';
}
