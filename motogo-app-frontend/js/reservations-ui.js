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
        try { dismissed = JSON.parse(localStorage.getItem('mg_sos_fab_dismissed') || '{}'); } catch(e){}
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
      d[window._sosFabIncidentId] = true;
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
    var uid = session.user.id;
    window.supabase.from('bookings')
      .select('id, status, payment_status, total_price, created_at, motorcycles(name, model)')
      .eq('user_id', uid)
      .in('status', ['reserved','pending'])
      .eq('payment_status', 'unpaid')
      .order('created_at', {ascending: false})
      .limit(1)
      .then(function(r){
        var fab = document.getElementById('booking-fab');
        if(!fab) return;
        if(r.data && r.data.length > 0){
          var bk = r.data[0];
          var created = new Date(bk.created_at).getTime();
          var remaining = _BOOKING_EXPIRY_MS - (Date.now() - created);
          if(remaining <= 0){
            // Already expired — backend will cancel, hide FAB
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
  }).catch(function(){});
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
  var hideOn = ['s-login','s-register','s-docs','s-booking','s-payment','s-success'];
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
    var m = b.motorcycles;
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
  var now = new Date(); now.setHours(0,0,0,0);
  var s = new Date(startDate); s.setHours(0,0,0,0);
  var e = new Date(endDate); e.setHours(0,0,0,0);
  if(now > e) return 'dokoncene';
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

function _fmtDate(iso){
  try {
    var d = new Date(iso);
    return d.getDate() + '. ' + (d.getMonth()+1) + '. ' + d.getFullYear();
  } catch(e){ return '—'; }
}

function _fmtDateRange(isoStart, isoEnd){
  try {
    var s = new Date(isoStart);
    var e = new Date(isoEnd);
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

// ===== RESERVATION DETAIL =====
var _currentResId = null;

async function openResDetailById(bookingId){
  try {
    _currentResId = bookingId;
    // Always fetch fresh data from Supabase for detail view
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }

    var moto = booking.motorcycles || (booking.moto_id ? await _getMotoById(booking.moto_id) : null);
    var st = _mapStatus(booking.status, booking.start_date, booking.end_date, booking);
    var s = new Date(booking.start_date); s.setHours(0,0,0,0);
    var e = new Date(booking.end_date); e.setHours(0,0,0,0);
    var days = Math.max(1, Math.round((e-s)/86400000)+1);
    var motoName = moto ? (moto.model || moto.name) : (booking.moto_name || 'Motorka');

    var titleEl = document.getElementById('rd-title');
    if(titleEl) titleEl.textContent = _t('res').resDetail + ' – ' + _statusLabel(st);
    var subEl = document.getElementById('rd-subtitle');
    if(subEl) subEl.textContent = '#' + bookingId.substr(-8).toUpperCase();

    var imgEl = document.getElementById('rd-moto-img');
    if(imgEl && moto) imgEl.src = moto.image_url || '';

    var nameEl = document.getElementById('rd-moto-name');
    if(nameEl) nameEl.textContent = motoName;

    var pickupEl = document.getElementById('rd-pickup');
    if(pickupEl) pickupEl.textContent = _fmtDate(booking.start_date) + ' ' + _t('res').at + ' ' + (booking.pickup_time || '9:00');
    var returnEl = document.getElementById('rd-return');
    if(returnEl) returnEl.textContent = _fmtDate(booking.end_date) + ' ' + _t('res').at + ' ' + (booking.pickup_time || '9:00');
    var durEl = document.getElementById('rd-duration');
    if(durEl) durEl.textContent = days + ' ' + (days===1?_t('res').day1:_t('res').days5);

    var totalEl = document.getElementById('rd-total');
    if(totalEl) totalEl.textContent = (booking.total_price||0).toLocaleString('cs-CZ') + ' Kč';

    // Pickup/return locations
    var branchName = moto && moto.branches ? (moto.branches.address || moto.branches.name) + ', ' + moto.branches.city : '—';
    var pickupLocEl = document.getElementById('rd-pickup-loc');
    if(pickupLocEl){
      if(booking.pickup_method === 'delivery' && booking.pickup_address){
        pickupLocEl.textContent = '🚚 Přistavení: ' + booking.pickup_address;
      } else {
        pickupLocEl.textContent = '🏪 ' + branchName;
      }
    }
    var returnLocEl = document.getElementById('rd-return-loc');
    if(returnLocEl){
      if(booking.return_method === 'delivery' && booking.return_address){
        returnLocEl.textContent = '🚚 Svoz: ' + booking.return_address;
      } else {
        returnLocEl.textContent = '🏪 ' + branchName;
      }
    }

    // Extras detail section
    var extrasEl = document.getElementById('rd-extras');
    if(extrasEl){
      var extrasHtml = '';
      if(booking.extras_price > 0){
        extrasHtml += '<div class="rd-row"><div class="rd-label">Příslušenství</div><div class="rd-value">' + (booking.extras_price||0).toLocaleString('cs-CZ') + ' Kč</div></div>';
      }
      if(booking.boots_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Boty</div><div class="rd-value">vel. ' + booking.boots_size + '</div></div>';
      if(booking.helmet_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Helma</div><div class="rd-value">vel. ' + booking.helmet_size + '</div></div>';
      if(booking.jacket_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Bunda</div><div class="rd-value">vel. ' + booking.jacket_size + '</div></div>';
      if(booking.delivery_fee > 0) extrasHtml += '<div class="rd-row"><div class="rd-label">Doručení</div><div class="rd-value">' + booking.delivery_fee.toLocaleString('cs-CZ') + ' Kč</div></div>';
      if(booking.discount_amount > 0) extrasHtml += '<div class="rd-row"><div class="rd-label">Sleva / poukaz</div><div class="rd-value" style="color:var(--green);">-' + booking.discount_amount.toLocaleString('cs-CZ') + ' Kč</div></div>';
      if(booking.discount_code) extrasHtml += '<div class="rd-row"><div class="rd-label">Kód poukazu</div><div class="rd-value">' + booking.discount_code + '</div></div>';
      extrasEl.innerHTML = extrasHtml;
      extrasEl.style.display = extrasHtml ? 'block' : 'none';
      // Load individual extras from booking_extras (async)
      if(window.supabase && booking.id){
        window.supabase.from('booking_extras').select('*, extras_catalog(name, price)').eq('booking_id', booking.id)
          .then(function(r){
            if(r.data && r.data.length > 0){
              var h = '';
              r.data.forEach(function(ex){ h += '<div class="rd-row"><div class="rd-label">'+(ex.extras_catalog?ex.extras_catalog.name:'Extra')+'</div><div class="rd-value">'+(ex.extras_catalog?ex.extras_catalog.price:0).toLocaleString('cs-CZ')+' Kč</div></div>'; });
              var container = document.getElementById('rd-extras-detail');
              if(!container){
                container = document.createElement('div'); container.id='rd-extras-detail'; container.style.cssText='margin-top:4px;padding:6px 10px;background:var(--gp);border-radius:var(--rsm);';
                extrasEl.appendChild(container);
              }
              container.innerHTML = h;
            }
          }).catch(function(){});
      }
    }


    // Banner
    var banner = document.getElementById('rd-banner');
    if(banner){
      if(st === 'aktivni'){
        var now2 = new Date(); now2.setHours(0,0,0,0);
        var endD = new Date(booking.end_date); endD.setHours(0,0,0,0);
        var daysLeft = Math.max(0, Math.round((endD - now2) / 86400000)) + 1;
        var hoursLeft = (new Date(booking.end_date) - new Date()) / (1000*60*60);
        var refInfo = '';
        if(hoursLeft > 7*24) refInfo = '<div style="font-size:11px;margin-top:6px;color:var(--gd);">'+_t('res').cancelFull+'</div>';
        else if(hoursLeft > 48) refInfo = '<div style="font-size:11px;margin-top:6px;color:#d97706;">'+_t('res').cancelHalf+'</div>';
        else refInfo = '<div style="font-size:11px;margin-top:6px;color:var(--red);">'+_t('res').cancelNone+'</div>';
        banner.style.display = 'block';
        banner.className = 'rd-info-banner rd-banner-info';
        banner.innerHTML = '🏍️ '+_t('res').ridingNow+' ' + daysLeft + ' ' + (daysLeft===1?_t('res').day1:daysLeft<5?_t('res').days2:_t('res').days5) + '.' + refInfo;
      } else if(st === 'nadchazejici'){
        var now3 = new Date();
        var startD2 = new Date(booking.start_date);
        var hoursTo = (startD2 - now3) / (1000*60*60);
        var daysTo = Math.ceil(hoursTo / 24);
        var refInfo2 = '';
        if(hoursTo > 7*24) refInfo2 = '<div style="font-size:11px;margin-top:6px;color:var(--gd);">'+_t('res').cancelNowFull+'</div>';
        else if(hoursTo > 48) refInfo2 = '<div style="font-size:11px;margin-top:6px;color:#d97706;">'+_t('res').cancelNowHalf+'</div>';
        else refInfo2 = '<div style="font-size:11px;margin-top:6px;color:var(--red);">'+_t('res').cancelNowNone+'</div>';
        banner.style.display = 'block';
        banner.className = 'rd-info-banner rd-banner-info';
        banner.innerHTML = '📅 '+_t('res').pickupOn+' ' + _fmtDate(booking.start_date) + ' ('+_t('res').inDays+' ' + daysTo + ' ' + (daysTo===1?_t('res').day1:daysTo<5?_t('res').days2:_t('res').days5) + ')' + refInfo2;
      } else {
        banner.style.display = 'none';
      }
    }

    // ===== MODIFICATION INFO (prominent card) =====
    var modEl = document.getElementById('rd-modification');
    var modContent = document.getElementById('rd-mod-content');
    if(modEl && modContent){
      if(booking.original_start_date && booking.original_end_date){
        var _ldCmp = function(a,b){ try{return new Date(a).toLocaleDateString('sv-SE')!==new Date(b).toLocaleDateString('sv-SE');}catch(e){return a!==b;} };
        var datesDiffer = _ldCmp(booking.original_start_date, booking.start_date) || _ldCmp(booking.original_end_date, booking.end_date);
        if(datesDiffer){
          var _m = _descMod(booking.original_start_date, booking.original_end_date, booking.start_date, booking.end_date);
          var mh = '<div style="background:'+(_m.color==='#2563eb'?'#dbeafe':_m.color==='#dc2626'?'#fee2e2':'#fef3c7')+';border:2px solid '+_m.color+';border-radius:12px;padding:12px 14px;margin-bottom:8px;">';
          mh += '<div style="font-size:14px;font-weight:900;color:'+_m.color+';">'+_m.type.charAt(0).toUpperCase()+_m.type.slice(1)+'</div>';
          mh += '<div style="font-size:12px;color:#4a6357;margin-top:4px;">'+_fmtDate(booking.original_start_date)+' – '+_fmtDate(booking.original_end_date)+' → '+_fmtDate(booking.start_date)+' – '+_fmtDate(booking.end_date)+'</div>';
          mh += '</div>';
          mh += '<div class="rd-row"><div class="rd-label">Původní termín</div><div class="rd-value" style="color:#b45309;">'+_fmtDate(booking.original_start_date)+' – '+_fmtDate(booking.original_end_date)+' ('+_m.origDays+' dní)</div></div>';
          mh += '<div class="rd-row"><div class="rd-label">Nový termín</div><div class="rd-value" style="color:'+_m.color+';">'+_fmtDate(booking.start_date)+' – '+_fmtDate(booking.end_date)+' ('+_m.newDays+' dní)</div></div>';
          // Show full history
          var _hist2 = Array.isArray(booking.modification_history) ? booking.modification_history : [];
          if(_hist2.length > 0){
            mh += '<div style="margin-top:8px;border-top:1px solid var(--g100);padding-top:8px;">';
            mh += '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:4px;">Historie úprav ('+_hist2.length+'×)</div>';
            for(var hi2=0; hi2<_hist2.length; hi2++){
              var _hm2 = _descMod(_hist2[hi2].from_start, _hist2[hi2].from_end, _hist2[hi2].to_start, _hist2[hi2].to_end);
              var _hmE2 = '';
              if(_hist2[hi2].from_moto && _hist2[hi2].to_moto) _hmE2 = ' · motorka: '+_hist2[hi2].from_moto+' → '+_hist2[hi2].to_moto;
              mh += '<div style="font-size:11px;color:'+_hm2.color+';margin-bottom:2px;">'+(hi2+1)+'. '+_fmtDT(_hist2[hi2].at)+' — '+_hm2.type+' ('+_hm2.detail+')'+_hmE2+' · '+(_hist2[hi2].source==='admin'?'admin':'zákazník')+'</div>';
            }
            mh += '</div>';
          }
          modContent.innerHTML = mh;
          modEl.style.display = 'block';
        } else {
          modEl.style.display = 'none';
        }
      } else {
        modEl.style.display = 'none';
      }
    }

    // ===== COMPREHENSIVE DETAIL SUMMARY =====
    _renderDetailSummary(booking, moto, st, days, branchName, bookingId);

    // Action buttons
    var actionsEl = document.getElementById('rd-actions');
    if(actionsEl){
      var btns = '';
      var docBtns = '';
      if(booking.payment_status === 'paid' && st !== 'cancelled'){
        docBtns = '<div style="border-top:1px solid var(--g100);margin-top:10px;padding-top:10px;">' +
          '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:6px;">'+(_t('res').documents||'Dokumenty')+'</div>' +
          '<button class="btn-out" onclick="showRentalContract(\''+bookingId+'\')">📄 '+(_t('res').contract||'Smlouva o pronájmu')+'</button>' +
          '</div>';
      }
      if(st === 'aktivni'){
        btns = '<button class="btn-g" onclick="openEditResByBookingId(\''+bookingId+'\')">✏️ '+_t('res').editExtend+'</button>' +
               '<button class="btn-g" style="background:#fee2e2;color:#b91c1c;border:none;margin-top:8px;" onclick="goTo(\'s-sos\')">🆘 '+_t('res').reportFault+'</button>' +
               '<button class="btn-out" style="margin-top:8px;" onclick="showDigitalProtocol(\''+bookingId+'\')">📝 '+(_t('res').handoverProtocol||'Předávací protokol')+'</button>' +
               docBtns;
      } else if(st === 'nadchazejici'){
        btns = '<button class="btn-g" onclick="openEditResByBookingId(\''+bookingId+'\')">✏️ '+_t('res').editReservation+'</button>' +
               '<button class="btn-g" style="background:var(--red);color:#fff;border:none;margin-top:8px;" onclick="doCancelBooking(\''+bookingId+'\')">🗑️ '+_t('res').cancelRes+'</button>' +
               docBtns;
      } else if(st === 'dokoncene'){
        var motoId = booking.moto_id || (moto ? moto.id : '');
        btns = '<div style="border-top:1px solid var(--g100);padding-top:10px;">' +
               '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:6px;">'+(_t('res').documents||'Dokumenty')+'</div>' +
               '<button class="btn-out" onclick="showInvoice(\''+bookingId+'\',\'final\')">💰 '+(_t('res').finalInvoice||'Konečná faktura')+'</button>' +
               '<button class="btn-out" style="margin-top:6px;" onclick="showRentalContract(\''+bookingId+'\')">📄 '+(_t('res').contract||'Smlouva o pronájmu')+'</button>' +
               '</div>' +
               '<div style="border-top:1px solid var(--g100);margin-top:12px;padding-top:12px;">' +
               '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:8px;">⭐ '+(_t('res').yourRating||'Vaše hodnocení')+'</div>' +
               '<button class="btn-g" style="margin-top:4px;" onclick="window.open(\'https://www.google.com/maps/search/MotoGo24+p%C5%AFj%C4%8Dovna+motorek\',\'_blank\')">⭐ '+(_t('res').rateOnGoogle||'Ohodnotit na Google')+'</button>' +
               '</div>' +
               '<button class="btn-g" style="margin-top:12px;" onclick="_rebookMoto(\''+motoId+'\')">🔁 '+(_t('res').bookAgain||'Znovu rezervovat')+'</button>';
      } else if(st === 'cancelled'){
        btns = '<button class="btn-g" onclick="restoreBooking(\''+bookingId+'\')">🔄 '+_t('res').restoreBtn+'</button>';
      }
      actionsEl.innerHTML = btns;
      if(st === 'dokoncene' && booking.rating){
        var r = booking.rating;
        _currentRating = r;
        actionsEl.querySelectorAll('.star-btn').forEach(function(s,i){
          s.style.color = i < r ? '#f59e0b' : '#d1d5db';
          s.style.transform = i < r ? 'scale(1.15)' : 'scale(1)';
        });
        var msgs = ['','😞','😐','🙂','😊','🏆'];
        var msgEl = actionsEl.querySelector('#done-rating-msg');
        if(msgEl) msgEl.textContent = msgs[r] + ' ' + (_t('res').thankStars||'Děkujeme').replace('{n}',r);
      }
    }

    goTo('s-res-detail');
  } catch(e){ console.error('openResDetailById error:', e); }
}

async function doCancelBooking(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }

    var now = new Date();
    var startDate = new Date(booking.start_date);
    var hoursUntilStart = (startDate - now) / (1000 * 60 * 60);
    var daysUntilStart = Math.ceil(hoursUntilStart / 24);
    var refundMsg = '';
    var refundPolicy = '<div style="font-size:11px;color:var(--g400);line-height:1.7;margin-top:8px;text-align:left;border-top:1px solid var(--g100);padding-top:8px;">' +
      '<div' + (hoursUntilStart > 7*24 ? ' style="color:var(--gd);font-weight:700;"' : '') + '>'+_t('res').policy7days+'</div>' +
      '<div' + (hoursUntilStart > 48 && hoursUntilStart <= 7*24 ? ' style="color:#d97706;font-weight:700;"' : '') + '>'+_t('res').policy2to7days+'</div>' +
      '<div' + (hoursUntilStart <= 48 ? ' style="color:var(--red);font-weight:700;"' : '') + '>'+_t('res').policyUnder2days+'</div></div>';

    if(hoursUntilStart > 7 * 24) refundMsg = _t('res').refund100+' (' + (booking.total_price||0).toLocaleString('cs-CZ') + ' Kč).<br><span style="font-size:11px;color:var(--g400);">'+_t('res').daysRemaining+' ' + daysUntilStart + ' '+_t('res').daysToStart+'</span>';
    else if(hoursUntilStart > 48) refundMsg = _t('res').refund50+' (' + Math.round((booking.total_price||0)*0.5).toLocaleString('cs-CZ') + ' Kč).<br><span style="font-size:11px;color:var(--g400);">'+_t('res').daysRemaining+' ' + daysUntilStart + ' '+_t('res').daysToStart+'</span>';
    else refundMsg = _t('res').refundNone+'<br><span style="font-size:11px;color:var(--g400);">'+_t('res').lessThan2days+'</span>';

    _showCancelDialog(bookingId, refundMsg + refundPolicy);
  } catch(e){ console.error('doCancelBooking error:', e); showT('✗',_t('common').error,_t('res').cancelFailed); }
}

function _showCancelDialog(bookingId, refundMsg){
  var existing = document.getElementById('cancel-confirm-overlay');
  if(existing) existing.remove();

  var overlay = document.createElement('div');
  overlay.id = 'cancel-confirm-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:20px;';
  overlay.innerHTML = '<div style="background:#fff;border-radius:16px;padding:24px;max-width:320px;width:100%;text-align:center;">' +
    '<div style="font-size:32px;margin-bottom:10px;">🗑️</div>' +
    '<div style="font-size:16px;font-weight:800;color:var(--black);margin-bottom:8px;">'+_t('res').cancelConfirmTitle+'</div>' +
    '<div style="font-size:13px;color:var(--g600);line-height:1.5;margin-bottom:18px;">' + refundMsg + '</div>' +
    '<div style="display:flex;gap:10px;">' +
      '<button onclick="document.getElementById(\'cancel-confirm-overlay\').remove()" style="flex:1;padding:12px;border-radius:10px;border:2px solid var(--g200);background:#fff;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;color:var(--black);">'+_t('res').keepBtn+'</button>' +
      '<button onclick="_execCancelBooking(\'' + bookingId + '\')" style="flex:1;padding:12px;border-radius:10px;border:none;background:var(--red);color:#fff;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">'+_t('res').cancelBtn+'</button>' +
    '</div></div>';
  document.body.appendChild(overlay);
  overlay.addEventListener('click', function(e){ if(e.target === overlay) overlay.remove(); });
}

async function _execCancelBooking(bookingId){
  var overlay = document.getElementById('cancel-confirm-overlay');
  if(overlay) overlay.remove();

  var result = await apiCancelBooking(bookingId);
  if(result.error){ showT('✗',_t('common').error, result.error); return; }

  // Generate cancellation receipt (storno doklad) with storno conditions
  if(typeof apiGenerateCancellationReceipt === 'function'){
    apiGenerateCancellationReceipt(bookingId, result.refund_percent || 0, result.refund_amount || 0).catch(function(e){});
  }

  var refundText = result.refund_percent > 0
    ? _t('res').refundOf+' ' + (result.refund_amount||0).toLocaleString('cs-CZ') + ' Kč (' + result.refund_percent + ' %)'
    : _t('res').noRefundText;
  showT('✓',_t('res').resCancelled, refundText);
  renderMyReservations();
  if(typeof cur !== 'undefined' && cur === 's-res-detail') histBack();
}

async function openEditResByBookingId(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }
    var moto = booking.motorcycles || (booking.moto_id ? await _getMotoById(booking.moto_id) : null);
    var st = _mapStatus(booking.status, booking.start_date, booking.end_date, booking);
    var isActive = (st === 'aktivni');

    // Set V9 global variables for edit screen
    editIsActive = isActive;

    var s = new Date(booking.start_date); s.setHours(0,0,0,0);
    var e = new Date(booking.end_date); e.setHours(0,0,0,0);
    var motoName = moto ? (moto.model || moto.name) : (booking.moto_name || 'Motorka');
    var days = Math.max(1, Math.round((e-s)/86400000)+1);

    // origResStart and origResEnd for edit calendar
    origResStart = {d:s.getDate(), m:s.getMonth(), y:s.getFullYear()};
    origResEnd = {d:e.getDate(), m:e.getMonth(), y:e.getFullYear()};

    // Fill UI
    var subEl = document.getElementById('edit-subtitle');
    if(subEl) subEl.textContent = motoName + ' · #' + bookingId.substr(-8).toUpperCase();

    var durEl = document.getElementById('edit-res-duration');
    var dateRangeEl = document.getElementById('edit-res-dates');
    var now = new Date(); now.setHours(0,0,0,0);

    if(isActive){
      var remaining = Math.max(0, Math.round((e-now)/86400000))+1;
      if(durEl) durEl.textContent = _t('res').activeRemaining+' ' + remaining + (remaining===1?' '+_t('res').day1:remaining<5?' '+_t('res').days2:' '+_t('res').days5);
    } else {
      var daysTo = Math.max(0, Math.round((s-now)/86400000));
      if(durEl) durEl.textContent = _t('res').upcomingIn+' ' + daysTo + (daysTo===1?' '+_t('res').day1:daysTo<5?' '+_t('res').days2:' '+_t('res').days5) + ' · ' + days + (days===1?' '+_t('res').day1:days<5?' '+_t('res').days2:' '+_t('res').days5);
    }
    if(dateRangeEl) dateRangeEl.textContent = s.getDate()+'.'+(s.getMonth()+1)+'. – '+e.getDate()+'.'+(e.getMonth()+1)+'.'+e.getFullYear();

    // Calendar info
    var calResDates = document.getElementById('edit-cal-res-dates');
    var calResMoto = document.getElementById('edit-cal-res-moto');
    var calResInfo = document.getElementById('edit-res-info-cal');
    if(calResDates) calResDates.textContent = dateRangeEl ? dateRangeEl.textContent : '';
    if(calResMoto) calResMoto.textContent = motoName + ' · #' + bookingId.substr(-8).toUpperCase();
    if(calResInfo){
      var infoDiv = calResInfo.querySelector('div');
      if(infoDiv) infoDiv.textContent = isActive ? _t('res').yourActiveRes : _t('res').yourUpcomingRes;
    }

    // Reset edit UI
    var shortenNote = document.getElementById('edit-shorten-note');
    if(shortenNote) shortenNote.style.display = 'none';
    var priceSum = document.getElementById('edit-price-summary');
    if(priceSum) priceSum.style.display = 'none';
    var saveBtn = document.getElementById('edit-save-btn');
    if(saveBtn) saveBtn.textContent = _t('res').saveChanges;

    // Store booking ID for saveEditReservation
    window._editBookingId = bookingId;
    window._editBookingMoto = moto;

    // Update branch address in pickup/return/branch sections dynamically
    var _brAddr = moto && moto.branches && moto.branches.address ? moto.branches.address : 'Mezná 9';
    var _brCity = moto && moto.branches && moto.branches.city ? moto.branches.city : '393 01 Mezná';
    var _brName = moto && moto.branches && moto.branches.name ? moto.branches.name : 'Mezná';
    var _brFull = _brAddr + ', ' + _brCity;
    // Pickup section
    var psl = document.getElementById('edit-pickup-store-label');
    if(psl){ var psn = psl.querySelector('div > div:last-child'); if(psn) psn.textContent = _brFull; }
    // Return section
    var rsl = document.getElementById('edit-return-store-label');
    if(rsl){ var rsn = rsl.querySelector('div > div:last-child'); if(rsn) rsn.textContent = _brFull; }
    // Branch change section
    var bml = document.getElementById('edit-branch-mezna-label');
    if(bml){ var bn = bml.querySelector('div > div:first-child'); if(bn) bn.innerHTML = '🏍️ ' + _brName; var ba = bml.querySelector('div > div:last-child'); if(ba) ba.textContent = _brFull; }

    // Zobrazit doplňky jen pro nadcházející
    var extrasCard = document.getElementById('edit-extras-card');
    if(extrasCard) extrasCard.style.display = isActive ? 'none' : 'block';

    // Naplnit text data
    var odTxt = document.getElementById('edit-od-txt');
    var doTxt = document.getElementById('edit-do-txt');
    if(odTxt) odTxt.textContent = s.getDate()+'.'+(s.getMonth()+1)+'.'+s.getFullYear();
    if(doTxt) doTxt.textContent = e.getDate()+'.'+(e.getMonth()+1)+'.'+e.getFullYear();

    // Nastavit eOd, eDo
    eOd = {d:s.getDate(), m:s.getMonth(), y:s.getFullYear()};
    eDo = {d:e.getDate(), m:e.getMonth(), y:e.getFullYear()};

    // Reset extras and moto change
    if(typeof editExtrasTotal !== 'undefined') editExtrasTotal = 0;
    if(typeof editReturnFee !== 'undefined') editReturnFee = 0;
    if(typeof editMotoDiffPrice !== 'undefined') editMotoDiffPrice = 0;
    if(typeof editNewMotoId !== 'undefined') editNewMotoId = null;

    if(typeof switchEditTab === 'function') switchEditTab('prodlouzit');
    goTo('s-edit-res');
  } catch(e){
    console.error('openEditResByBookingId error:', e);
    showT('✗',_t('common').error,_t('res').openEditFailed);
  }
}

async function restoreBooking(bookingId){
  try {
    if(!confirm(_t('res').restoreConfirm)) return;
    var result = await apiRestoreBooking(bookingId);
    if(result.error){ showT('✗',_t('common').error,result.error); return; }
    var booking = result.booking;
    // Check for overlapping reservations before restoring
    if(typeof apiCheckBookingOverlap === 'function' && booking){
      var oc = await apiCheckBookingOverlap(booking.start_date, booking.end_date, bookingId);
      if(oc.overlap){
        var cf = oc.conflicting;
        showT('⚠️',_t('pay').overlapTitle||'Termín obsazen',
          (_t('pay').overlapMsg||'Již máte rezervaci v tomto termínu')+': '+(cf.moto_name||'motorka')+' ('+_fmtDate(cf.start_date)+' – '+_fmtDate(cf.end_date)+'). '+(_t('pay').overlapHint||'Zvolte jiný termín nebo upravte stávající rezervaci.'));
        return;
      }
    }
    if(!booking){ showT('✗',_t('common').error,'Rezervace nenalezena'); return; }

    // Reservation stays cancelled until payment succeeds
    // Set up payment flow for the restore
    _currentBookingId = bookingId;
    _currentPaymentAmount = booking.total_price || 0;
    _currentPaymentMethod = 'card';
    _paymentAttempts = 0;
    _isRestorePayment = true;

    // Navigate to payment screen
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
      payBtn.onclick = function(){ doRestorePayment(bookingId); };
    }
    var applePayBtn = document.getElementById('apple-pay-btn');
    if(applePayBtn) applePayBtn.textContent = '🍎 Pay ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč';

    goTo('s-payment');
  } catch(e){ console.error('restoreBooking error:', e); showT('✗',_t('common').error,_t('res').restoreFailed); }
}

function _rebookMoto(motoId){
  if(motoId && typeof openDetail === 'function'){
    openDetail(motoId);
    goTo('s-detail');
    showT('🏍️',_t('res').bookAgain||'Rezervace',_t('res').selectDateSameMoto||'Vyberte termín pro stejnou motorku');
  } else {
    goTo('s-home');
    showT('🏍️',_t('res').bookAgain||'Rezervace',_t('res').selectMoto||'Vyberte motorku');
  }
}

function _fmtDT(iso){
  try { var d=new Date(iso); return d.getDate()+'.'+(d.getMonth()+1)+'.'+d.getFullYear()+' '+d.getHours()+':'+('0'+d.getMinutes()).slice(-2); } catch(e){ return '—'; }
}

function _descMod(fromStart, fromEnd, toStart, toEnd){
  // Normalize to local midnight to avoid timezone drift
  var _nd=function(d){var dt=new Date(d);return new Date(dt.getFullYear(),dt.getMonth(),dt.getDate());};
  var fs=_nd(fromStart),fe=_nd(fromEnd),ts=_nd(toStart),te=_nd(toEnd);
  var sd=Math.round((ts-fs)/86400000), ed=Math.round((te-fe)/86400000);
  var origD=Math.max(1,Math.round((fe-fs)/86400000)+1), newD=Math.max(1,Math.round((te-ts)/86400000)+1);
  var dd=newD-origD;
  var parts=[];
  if(sd<0) parts.push('začátek dříve o '+Math.abs(sd)+' d');
  else if(sd>0) parts.push('začátek později o '+sd+' d');
  if(ed>0) parts.push('konec později o '+ed+' d');
  else if(ed<0) parts.push('konec dříve o '+Math.abs(ed)+' d');
  var type,color;
  if(dd>0){type='prodlouženo o '+dd+' d';color='#2563eb';}
  else if(dd<0){type='zkráceno o '+Math.abs(dd)+' d';color='#dc2626';}
  else if(sd!==0||ed!==0){type='posunuto';color='#92400e';}
  else{type='beze změny';color='#4a6357';}
  var detail=parts.length>0?parts.join(', '):type;
  return {type:type,detail:detail,origDays:origD,newDays:newD,color:color};
}

function _renderDetailSummary(b, moto, st, days, branchName, bookingId){
  var el = document.getElementById('rd-detail-summary');
  if(!el) return;
  var li = function(label, val){ return val ? '<li><strong>'+label+':</strong> '+val+'</li>' : ''; };
  var h = '<ul class="rd-sum">';

  // Status & ID
  h += li('Stav', _statusLabel(st));
  h += li('ID rezervace', '#'+bookingId.substr(-8).toUpperCase());
  h += li('Motorka', moto ? (moto.model||'—') + (moto.spz ? ' ('+moto.spz+')' : '') : '—');
  if(moto && moto.category){
    var catMap = {cestovni:'Cestovní enduro',naked:'Naked',supermoto:'Supermoto',detske:'Dětské',sportovni:'Sportovní'};
    var catLabel = catMap[(moto.category||'').toLowerCase()] || moto.category;
    var licReq = moto.license_required ? ' · ' + moto.license_required : '';
    h += li('Kategorie', catLabel + licReq);
  }
  h += li('Pobočka', branchName);

  // Dates — current
  h += li('Začátek', _fmtDate(b.start_date) + ' v ' + (b.pickup_time||'9:00'));
  h += li('Konec', _fmtDate(b.end_date) + ' v ' + (b.pickup_time || '9:00'));
  h += li('Délka', days + ' ' + (days===1?'den':days<5?'dny':'dní'));

  // Original dates (if modified)
  if(b.original_start_date && b.original_end_date && (b.original_start_date !== b.start_date || b.original_end_date !== b.end_date)){
    var _mod = _descMod(b.original_start_date, b.original_end_date, b.start_date, b.end_date);
    h += '<li style="color:#b45309;"><strong>Původní termín:</strong> '+_fmtDate(b.original_start_date)+' – '+_fmtDate(b.original_end_date)+' ('+_mod.origDays+' dní)</li>';
    h += '<li style="color:'+_mod.color+';"><strong>Celkem:</strong> '+_mod.type+' → '+_fmtDate(b.start_date)+' – '+_fmtDate(b.end_date)+' ('+days+' dní)</li>';
    // Show full modification history
    var _hist = Array.isArray(b.modification_history) ? b.modification_history : [];
    for(var hi=0; hi<_hist.length; hi++){
      var _hm = _descMod(_hist[hi].from_start, _hist[hi].from_end, _hist[hi].to_start, _hist[hi].to_end);
      var _hmExtra = '';
      if(_hist[hi].from_moto && _hist[hi].to_moto) _hmExtra = ' · motorka: '+_hist[hi].from_moto+' → '+_hist[hi].to_moto;
      h += '<li style="color:'+_hm.color+';font-size:11px;"><strong>Úprava #'+(hi+1)+':</strong> '+_fmtDT(_hist[hi].at)+' — '+_hm.type+' ('+_hm.detail+')'+_hmExtra+' · '+(_hist[hi].source==='admin'?'admin':'zákazník')+'</li>';
    }
  }

  // Pickup/return method & address
  h += li(b.pickup_method==='delivery'?'Přistavení':'Vyzvednutí', (b.pickup_method==='delivery'?'Přistavení na adresu':'Na pobočce') + ' — ' + (b.pickup_address||branchName));
  h += li(b.return_method==='delivery'?'Svoz':'Vrácení', (b.return_method==='delivery'?'Svoz z adresy':'Na pobočce') + ' — ' + (b.return_address||branchName));
  if(b.delivery_fee > 0){
    var pFee = typeof pickupDelivFee !== 'undefined' ? pickupDelivFee : 0;
    var rFee = typeof returnDelivFee !== 'undefined' ? returnDelivFee : 0;
    if(pFee > 0) h += li('Přistavení cena', pFee.toLocaleString('cs-CZ')+' Kč');
    if(rFee > 0) h += li('Svoz cena', rFee.toLocaleString('cs-CZ')+' Kč');
  }

  // Gear
  if(b.boots_size) h += li('Boty', 'vel. '+b.boots_size);
  if(b.helmet_size) h += li('Helma', 'vel. '+b.helmet_size);
  if(b.jacket_size) h += li('Bunda', 'vel. '+b.jacket_size);

  // Insurance
  if(b.insurance_type) h += li('Pojištění', b.insurance_type);

  // Pricing
  h += li('Cena výpůjčky', (b.total_price||0).toLocaleString('cs-CZ')+' Kč');
  if(b.extras_price > 0) h += li('Příslušenství', b.extras_price.toLocaleString('cs-CZ')+' Kč');
  if(b.delivery_fee > 0) h += li('Doručení', b.delivery_fee.toLocaleString('cs-CZ')+' Kč');
  if(b.discount_amount > 0) h += li('Sleva', '-'+b.discount_amount.toLocaleString('cs-CZ')+' Kč'+(b.discount_code?' (kód: '+b.discount_code+')':''));
  h += li('Platba', b.payment_status==='paid'?'Zaplaceno':'Nezaplaceno');
  if(b.payment_method) h += li('Způsob platby', b.payment_method);

  // Mileage
  if(b.mileage_start) h += li('Nájezd při převzetí', b.mileage_start+' km');
  if(b.mileage_end) h += li('Nájezd při vrácení', b.mileage_end+' km');
  if(b.mileage_start && b.mileage_end) h += li('Najeto', (b.mileage_end-b.mileage_start)+' km');

  // Damage
  if(b.damage_report) h += '<li style="color:#b91c1c;"><strong>Poškození:</strong> '+b.damage_report+'</li>';

  // SOS
  if(b.sos_replacement) h += '<li style="color:#1a8a18;"><strong>SOS náhrada:</strong> Ano'+(b.replacement_for_booking_id?' (za #'+b.replacement_for_booking_id.substr(-8)+')':'')+'</li>';
  if(b.ended_by_sos) h += '<li style="color:#b91c1c;"><strong>Ukončeno SOS:</strong> Ano'+(b.sos_incident_id?' (incident #'+b.sos_incident_id.substr(-8)+')':'')+'</li>';

  // Cancellation
  if(b.status==='cancelled'){
    h += '<li style="color:#b91c1c;"><strong>Zrušeno:</strong> '+_fmtDT(b.cancelled_at)+'</li>';
    if(b.cancellation_reason) h += '<li style="color:#b91c1c;"><strong>Důvod:</strong> '+b.cancellation_reason+'</li>';
  }

  // Timeline
  h += '</ul><div class="rd-sum-t" style="margin-top:8px;"><strong>Průběh:</strong></div><ul class="rd-sum">';
  if(b.created_at) h += '<li>Vytvořeno: '+_fmtDT(b.created_at)+'</li>';
  if(b.confirmed_at) h += '<li>Potvrzeno: '+_fmtDT(b.confirmed_at)+'</li>';
  if(b.picked_up_at) h += '<li>Vydáno: '+_fmtDT(b.picked_up_at)+'</li>';
  if(b.returned_at) h += '<li>Vráceno: '+_fmtDT(b.returned_at)+'</li>';
  if(b.actual_return_date) h += '<li>Skutečné vrácení: '+_fmtDT(b.actual_return_date)+'</li>';
  if(b.cancelled_at) h += '<li style="color:#b91c1c;">Zrušeno: '+_fmtDT(b.cancelled_at)+'</li>';
  if(b.rated_at) h += '<li>Hodnoceno: '+_fmtDT(b.rated_at)+' ('+b.rating+'/5)</li>';
  h += '</ul>';

  // Fetch SOS incidents async
  el.innerHTML = h;
  el.style.display = 'block';
  _loadSosForDetail(b.id, el);
}

async function _loadSosForDetail(bookingId, el){
  if(!_isSupabaseReady()) return;
  try {
    var r = await supabase.from('sos_incidents').select('id,type,title,status,severity,created_at,resolved_at,description').eq('booking_id',bookingId).order('created_at',{ascending:false});
    if(!r.data || r.data.length===0) return;
    var h = '<div class="rd-sum-t" style="margin-top:8px;"><strong>SOS incidenty:</strong></div><ul class="rd-sum">';
    for(var i=0;i<r.data.length;i++){
      var inc = r.data[i];
      h += '<li style="color:#b91c1c;">#'+inc.id.substr(-6)+' — '+inc.type+' ('+inc.severity+') — '+inc.status;
      if(inc.title) h += ' — '+inc.title;
      h += ' — '+_fmtDT(inc.created_at);
      if(inc.resolved_at) h += ' → vyřešeno '+_fmtDT(inc.resolved_at);
      h += '</li>';
    }
    h += '</ul>';
    el.innerHTML += h;
  } catch(e){}
}

async function openExtendBooking(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }

    var currentEnd = new Date(booking.end_date);
    var newEnd = new Date(currentEnd);
    newEnd.setDate(newEnd.getDate() + 1);

    var msg = _t('res').extendConfirm + ' ' + newEnd.getDate() + '. ' + (newEnd.getMonth()+1) + '. ' + newEnd.getFullYear() + '?';
    if(!confirm(msg)) return;

    var result = await apiExtendBooking(bookingId, newEnd.getFullYear()+'-'+String(newEnd.getMonth()+1).padStart(2,'0')+'-'+String(newEnd.getDate()).padStart(2,'0'));
    if(result.error){
      showT('✗',_t('common').error, result.error);
      return;
    }

    showT('✓',_t('res').extended,_t('res').extendedMsg);
    renderMyReservations();
    if(_currentResId === bookingId) openResDetailById(bookingId);
  } catch(e){ console.error('openExtendBooking error:', e); showT('✗',_t('common').error,_t('res').extendFailed); }
}
