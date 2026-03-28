/* === RESERVATIONS-DETAIL-2.JS — Cancellation dialog & execution === */
/* Split from reservations-detail.js. All functions remain global. */

async function doCancelBooking(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('\u2717',_t('common').error,_t('res').resNotFound); return; }

    var now = new Date();
    var startDate = new Date(booking.start_date);
    var hoursUntilStart = (startDate - now) / (1000 * 60 * 60);
    var daysUntilStart = Math.ceil(hoursUntilStart / 24);
    var refundMsg = '';
    var refundPolicy = '<div style="font-size:11px;color:var(--g400);line-height:1.7;margin-top:8px;text-align:left;border-top:1px solid var(--g100);padding-top:8px;">' +
      '<div' + (hoursUntilStart > 7*24 ? ' style="color:var(--gd);font-weight:700;"' : '') + '>'+_t('res').policy7days+'</div>' +
      '<div' + (hoursUntilStart > 48 && hoursUntilStart <= 7*24 ? ' style="color:#d97706;font-weight:700;"' : '') + '>'+_t('res').policy2to7days+'</div>' +
      '<div' + (hoursUntilStart <= 48 ? ' style="color:var(--red);font-weight:700;"' : '') + '>'+_t('res').policyUnder2days+'</div></div>';

    if(hoursUntilStart > 7 * 24) refundMsg = _t('res').refund100+' (' + (booking.total_price||0).toLocaleString('cs-CZ') + ' K\u010d).<br><span style="font-size:11px;color:var(--g400);">'+_t('res').daysRemaining+' ' + daysUntilStart + ' '+_t('res').daysToStart+'</span>';
    else if(hoursUntilStart > 48) refundMsg = _t('res').refund50+' (' + Math.round((booking.total_price||0)*0.5).toLocaleString('cs-CZ') + ' K\u010d).<br><span style="font-size:11px;color:var(--g400);">'+_t('res').daysRemaining+' ' + daysUntilStart + ' '+_t('res').daysToStart+'</span>';
    else refundMsg = _t('res').refundNone+'<br><span style="font-size:11px;color:var(--g400);">'+_t('res').lessThan2days+'</span>';

    _showCancelDialog(bookingId, refundMsg + refundPolicy);
  } catch(e){ console.error('doCancelBooking error:', e); showT('\u2717',_t('common').error,_t('res').cancelFailed); }
}

function _showCancelDialog(bookingId, refundMsg){
  var existing = document.getElementById('cancel-confirm-overlay');
  if(existing) existing.remove();

  var overlay = document.createElement('div');
  overlay.id = 'cancel-confirm-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:20px;';
  overlay.innerHTML = '<div style="background:#fff;border-radius:16px;padding:24px;max-width:320px;width:100%;text-align:center;">' +
    '<div style="font-size:32px;margin-bottom:10px;">\ud83d\uddd1\ufe0f</div>' +
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
  if(result.error){ showT('\u2717',_t('common').error, result.error); return; }

  // Generate cancellation receipt (storno doklad) with storno conditions
  if(typeof apiGenerateCancellationReceipt === 'function'){
    apiGenerateCancellationReceipt(bookingId, result.refund_percent || 0, result.refund_amount || 0).catch(function(e){});
  }

  var refundText = result.refund_percent > 0
    ? _t('res').refundOf+' ' + (result.refund_amount||0).toLocaleString('cs-CZ') + ' K\u010d (' + result.refund_percent + ' %)'
    : _t('res').noRefundText;
  showT('\u2713',_t('res').resCancelled, refundText);
  renderMyReservations();
  if(typeof cur !== 'undefined' && cur === 's-res-detail') histBack();
}
