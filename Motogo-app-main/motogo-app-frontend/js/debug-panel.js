// ===== DEBUG-PANEL.JS – Global diagnostics overlay for every screen =====
// Shows relevant data for the current screen. Toggle with 3-finger tap or _toggleDebug().

var _debugEnabled = false; // PRODUCTION: debug panel disabled

function _debugPanel(screenId){
  if(!_debugEnabled) return;
  // Remove previous debug panel
  var old = document.getElementById('_dbg-panel');
  if(old) old.remove();

  var lines = [];
  var title = 'DEBUG: ' + screenId;

  // Common info
  var session = null;
  try { var raw = localStorage.getItem('mg_current_session'); if(raw) session = JSON.parse(raw); } catch(e){}
  lines.push('Session: ' + (session ? session.user?.email || session.user?.id?.substr(-8) || 'yes' : 'none'));
  lines.push('Supabase: ' + (_isSupabaseReady ? (_isSupabaseReady() ? 'OK' : 'NO') : '?'));
  lines.push('Screen: ' + screenId + ' | Stack: [' + (typeof navStack !== 'undefined' ? navStack.join(' > ') : '?') + ']');
  lines.push('Time: ' + new Date().toLocaleTimeString('cs-CZ'));
  lines.push('---');

  // Screen-specific data
  switch(screenId){
    case 's-home':
      lines.push('MOTOS: ' + (typeof MOTOS !== 'undefined' ? MOTOS.length + ' motorek' : 'N/A'));
      if(typeof MOTOS !== 'undefined'){
        var avail = MOTOS.filter(function(m){ return m.avail; }).length;
        var cats = {};
        MOTOS.forEach(function(m){ cats[m.cat] = (cats[m.cat]||0)+1; });
        lines.push('Dostupné: ' + avail + '/' + MOTOS.length);
        lines.push('Kategorie: ' + Object.keys(cats).map(function(k){ return k+'='+cats[k]; }).join(', '));
        var withDb = MOTOS.filter(function(m){ return m._db; }).length;
        lines.push('Enriched (_db): ' + withDb + '/' + MOTOS.length);
      }
      if(typeof _motoOccupancy !== 'undefined') lines.push('Occupancy cache: ' + Object.keys(_motoOccupancy).length + ' motorek');
      break;

    case 's-search':
      lines.push('sOd: ' + (typeof sOd !== 'undefined' && sOd ? sOd.d+'.'+(sOd.m+1)+'.'+sOd.y : 'null'));
      lines.push('sDo: ' + (typeof sDo !== 'undefined' && sDo ? sDo.d+'.'+(sDo.m+1)+'.'+sDo.y : 'null'));
      lines.push('sStep: ' + (typeof sStep !== 'undefined' ? sStep : '?'));
      lines.push('MOTOS: ' + (typeof MOTOS !== 'undefined' ? MOTOS.length : 'N/A'));
      var filterEls = document.querySelectorAll('#s-search .fchip.on');
      lines.push('Active filters: ' + filterEls.length);
      break;

    case 's-detail':
      var detMoto = (typeof dList !== 'undefined' && typeof dIdx !== 'undefined') ? dList[dIdx] : null;
      lines.push('detailMoto: ' + (detMoto ? detMoto.name + ' (id:' + (detMoto.id||'?').toString().substr(-8) + ')' : 'null'));
      lines.push('dOd: ' + (typeof dOd !== 'undefined' && dOd ? dOd.d+'.'+(dOd.m+1)+'.'+dOd.y : 'null'));
      lines.push('dDo: ' + (typeof dDo !== 'undefined' && dDo ? dDo.d+'.'+(dDo.m+1)+'.'+dDo.y : 'null'));
      lines.push('dStep: ' + (typeof dStep !== 'undefined' ? dStep : '?'));
      lines.push('dIdx: ' + (typeof dIdx !== 'undefined' ? dIdx : '?') + '/' + (typeof dList !== 'undefined' ? dList.length : '?'));
      if(detMoto){
        lines.push('cat: ' + (detMoto.cat||'?') + ' | rp: ' + (detMoto.rp||'?'));
        lines.push('pricing: ' + (detMoto.pricing ? JSON.stringify(detMoto.pricing) : 'N/A'));
        if(detMoto._db) lines.push('DB id: ' + detMoto._db.id.substr(-8));
      }
      lines.push('bookingMoto: ' + (typeof bookingMoto !== 'undefined' && bookingMoto ? bookingMoto.name : 'null'));
      break;

    case 's-booking':
      lines.push('bookingMoto: ' + (typeof bookingMoto !== 'undefined' && bookingMoto ? bookingMoto.name : 'null'));
      lines.push('bOd: ' + (typeof bOd !== 'undefined' && bOd ? bOd.d+'.'+(bOd.m+1)+'.'+bOd.y : 'null'));
      lines.push('bDo: ' + (typeof bDo !== 'undefined' && bDo ? bDo.d+'.'+(bDo.m+1)+'.'+bDo.y : 'null'));
      lines.push('bookingDays: ' + (typeof bookingDays !== 'undefined' ? bookingDays : '?'));
      lines.push('extraTotal: ' + (typeof extraTotal !== 'undefined' ? extraTotal : 0) + ' Kč');
      lines.push('deliveryFee: ' + (typeof deliveryFee !== 'undefined' ? deliveryFee : 0) + ' Kč');
      lines.push('discountAmt: ' + (typeof discountAmt !== 'undefined' ? discountAmt : 0) + ' Kč');
      lines.push('bookingFromDetail: ' + (typeof bookingFromDetail !== 'undefined' ? bookingFromDetail : '?'));
      break;

    case 's-payment':
      lines.push('_currentBookingId: ' + (typeof _currentBookingId !== 'undefined' ? (_currentBookingId ? _currentBookingId.substr(-8) : 'null') : '?'));
      lines.push('_currentPaymentAmount: ' + (typeof _currentPaymentAmount !== 'undefined' ? _currentPaymentAmount + ' Kč' : '?'));
      lines.push('_currentPaymentMethod: ' + (typeof _currentPaymentMethod !== 'undefined' ? _currentPaymentMethod : '?'));
      lines.push('_paymentAttempts: ' + (typeof _paymentAttempts !== 'undefined' ? _paymentAttempts : '?'));
      lines.push('_isEditPayment: ' + (typeof _isEditPayment !== 'undefined' ? _isEditPayment : 'false'));
      lines.push('_isRestorePayment: ' + (typeof _isRestorePayment !== 'undefined' ? _isRestorePayment : 'false'));
      break;

    case 's-res':
      lines.push('_resFilter: ' + (typeof _resFilter !== 'undefined' ? _resFilter : '?'));
      lines.push('_cachedBookings: ' + (typeof _cachedBookings !== 'undefined' && _cachedBookings ? _cachedBookings.length + ' items' : 'null'));
      break;

    case 's-res-detail':
      lines.push('Current detail booking: scanning DOM...');
      var rdSum = document.getElementById('rd-detail-summary');
      if(rdSum){
        var lis = rdSum.querySelectorAll('li');
        lis.forEach(function(li){ lines.push('  ' + li.textContent.substr(0,80)); });
      }
      break;

    case 's-edit-res':
      lines.push('editIsActive: ' + (typeof editIsActive !== 'undefined' ? editIsActive : '?'));
      lines.push('editMode: ' + (typeof editMode !== 'undefined' ? editMode : '?'));
      lines.push('origResStart: ' + (typeof origResStart !== 'undefined' ? origResStart.d+'.'+(origResStart.m+1)+'.'+origResStart.y : 'null'));
      lines.push('origResEnd: ' + (typeof origResEnd !== 'undefined' ? origResEnd.d+'.'+(origResEnd.m+1)+'.'+origResEnd.y : 'null'));
      lines.push('eOd: ' + (typeof eOd !== 'undefined' && eOd ? eOd.d+'.'+(eOd.m+1)+'.'+eOd.y : 'null'));
      lines.push('eDo: ' + (typeof eDo !== 'undefined' && eDo ? eDo.d+'.'+(eDo.m+1)+'.'+eDo.y : 'null'));
      lines.push('_editBookingId: ' + (typeof window._editBookingId !== 'undefined' ? (window._editBookingId||'').substr(-8) : '?'));
      lines.push('editExtrasTotal: ' + (typeof editExtrasTotal !== 'undefined' ? editExtrasTotal : 0));
      lines.push('editReturnFee: ' + (typeof editReturnFee !== 'undefined' ? editReturnFee : 0));
      lines.push('editMotoDiffPrice: ' + (typeof editMotoDiffPrice !== 'undefined' ? editMotoDiffPrice : 0));
      lines.push('editNewMotoId: ' + (typeof editNewMotoId !== 'undefined' ? editNewMotoId : 'null'));
      break;

    case 's-profile':
      _debugProfileAsync(lines);
      return; // async – renders itself

    case 's-invoices':
      lines.push('(see inline diagnostics above invoice list)');
      break;

    case 's-contracts':
      lines.push('Checking contracts DOM...');
      var contractsList = document.getElementById('contracts-list');
      if(contractsList) lines.push('Items in DOM: ' + contractsList.children.length);
      break;

    case 's-merch':
      lines.push('MOTOS merch: ' + (typeof SHOP_ITEMS !== 'undefined' ? SHOP_ITEMS.length + ' items' : 'N/A'));
      lines.push('cart: ' + (typeof cart !== 'undefined' ? cart.length + ' items, ' + cart.reduce(function(s,c){return s+c.price*c.qty;},0) + ' Kč' : 'empty'));
      break;

    case 's-cart':
      lines.push('cart items: ' + (typeof cart !== 'undefined' ? cart.length : 0));
      if(typeof cart !== 'undefined') cart.forEach(function(c){
        lines.push('  ' + c.name + ' x' + c.qty + ' = ' + (c.price*c.qty) + ' Kč');
      });
      lines.push('shipMode: ' + (typeof shipMode !== 'undefined' ? shipMode : '?'));
      break;

    case 's-checkout':
      lines.push('cart: ' + (typeof cart !== 'undefined' ? cart.length + ' items' : '0'));
      lines.push('shipMode: ' + (typeof shipMode !== 'undefined' ? shipMode : '?'));
      lines.push('shopDiscountAmt: ' + (typeof shopDiscountAmt !== 'undefined' ? shopDiscountAmt : 0));
      break;

    case 's-messages':
      lines.push('Checking messages DOM...');
      var msgList = document.getElementById('admin-msgs-list');
      if(msgList) lines.push('Admin msgs in DOM: ' + msgList.children.length);
      var threadList = document.getElementById('threads-list');
      if(threadList) lines.push('Threads in DOM: ' + threadList.children.length);
      break;

    case 's-voucher':
      lines.push('Voucher screen');
      break;

    case 's-sos':
    case 's-sos-nehoda':
    case 's-sos-nepojizda':
    case 's-sos-porucha':
    case 's-sos-nepojizda-porucha':
    case 's-sos-servis':
    case 's-sos-kradez':
      lines.push('SOS screen: ' + screenId);
      lines.push('_sosCurrentBookingId: ' + (typeof _sosCurrentBookingId !== 'undefined' && _sosCurrentBookingId ? _sosCurrentBookingId.substr(-8) : 'none'));
      lines.push('_sosCurrentMotoId: ' + (typeof _sosCurrentMotoId !== 'undefined' && _sosCurrentMotoId ? _sosCurrentMotoId.substr(-8) : 'none'));
      lines.push('_sosActiveIncidentId: ' + (typeof _sosActiveIncidentId !== 'undefined' && _sosActiveIncidentId ? _sosActiveIncidentId.substr(-8) : 'none'));
      lines.push('_sosReplacementMode: ' + (typeof _sosReplacementMode !== 'undefined' ? _sosReplacementMode : '?'));
      lines.push('_sosFault: ' + (typeof _sosFault !== 'undefined' ? _sosFault : '?'));
      break;

    case 's-sos-replacement':
      lines.push('_sosPendingIncidentId: ' + (typeof _sosPendingIncidentId !== 'undefined' ? (_sosPendingIncidentId||'').substr(-8) : '?'));
      lines.push('_sosReplacementMode: ' + (typeof _sosReplacementMode !== 'undefined' ? _sosReplacementMode : '?'));
      break;

    case 's-success':
      lines.push('Booking success screen');
      lines.push('_currentBookingId: ' + (typeof _currentBookingId !== 'undefined' ? (_currentBookingId||'').substr(-8) : '?'));
      break;

    default:
      lines.push('No specific debug data for this screen');
  }

  _renderDebugDiv(screenId, title, lines);
}

async function _debugProfileAsync(){
  var lines = [];
  lines.push('Loading profile data...');
  try {
    var p = await apiFetchProfile();
    if(p){
      lines.push('full_name: ' + (p.full_name||'—'));
      lines.push('email: ' + (p.email||'—'));
      lines.push('phone: ' + (p.phone||'—'));
      lines.push('id: ' + (p.id ? p.id.substr(-8) : '?'));
      lines.push('license: ' + (p.license_number||'—') + ' exp: ' + (p.license_expiry||'—'));
      lines.push('license_group: ' + (Array.isArray(p.license_group) ? p.license_group.join(',') : (p.license_group||'—')));
      lines.push('address: ' + [p.street, p.city, p.zip].filter(Boolean).join(', '));
      lines.push('lang: ' + (p.language||'—') + ' | branch: ' + (p.preferred_branch||'—'));
      lines.push('marketing: ' + (p.marketing_consent ? 'yes' : 'no'));
      lines.push('dob: ' + (p.date_of_birth||'—'));
    } else {
      lines.push('Profile: null / not loaded');
    }
  } catch(e){ lines.push('Error: ' + e.message); }
  _renderDebugDiv('s-profile', 'DEBUG: s-profile', lines);
}

function _renderDebugDiv(screenId, title, lines){
  var el = document.getElementById(screenId);
  if(!el) return;
  var panel = document.createElement('div');
  panel.id = '_dbg-panel';
  panel.style.cssText = 'background:#fffbeb;border:1px solid #fbbf24;border-radius:8px;padding:10px;margin:8px 12px;font-size:10px;font-family:monospace;color:#78350f;line-height:1.5;max-height:300px;overflow-y:auto;position:relative;z-index:50;';
  panel.innerHTML = '<strong>' + title + '</strong> <span onclick="_toggleDebug()" style="cursor:pointer;float:right;font-size:12px;">✕</span><br>' +
    lines.map(function(l){
      if(l === '---') return '<hr style="border:none;border-top:1px dashed #fbbf24;margin:3px 0;">';
      return l;
    }).join('<br>');
  // Insert at top of screen
  var first = el.firstChild;
  if(first) el.insertBefore(panel, first);
  else el.appendChild(panel);
}

function _toggleDebug(){
  _debugEnabled = !_debugEnabled;
  var old = document.getElementById('_dbg-panel');
  if(old) old.remove();
  if(_debugEnabled && typeof cur !== 'undefined') _debugPanel(cur);
}

// Auto-refresh debug panel for async screens
function _refreshDebug(){
  if(!_debugEnabled) return;
  if(typeof cur !== 'undefined') _debugPanel(cur);
}
