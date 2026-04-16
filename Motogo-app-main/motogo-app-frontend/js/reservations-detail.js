/* === RESERVATIONS-DETAIL.JS — Reservation detail view === */

// ===== RESERVATION DETAIL =====
var _currentResId = null;

async function openResDetailById(bookingId){
  try {
    _currentResId = bookingId;
    // Always fetch fresh data from Supabase for detail view
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('\u2717',_t('common').error,_t('res').resNotFound); return; }

    var moto = booking.motorcycles || (booking.moto_id ? await _getMotoById(booking.moto_id) : null);
    // Fetch promo code type info for display
    if(booking.discount_code && booking.discount_amount > 0 && window.supabase){
      try {
        var _pu = await window.supabase.from('promo_code_usage').select('discount_applied, promo_codes(type, value)')
          .eq('booking_id', bookingId).limit(1);
        if(_pu.data && _pu.data.length > 0 && _pu.data[0].promo_codes){
          booking._promoType = _pu.data[0].promo_codes.type;
          booking._promoValue = _pu.data[0].promo_codes.value;
        }
      } catch(e2){}
    }
    var st = _mapStatus(booking.status, booking.start_date, booking.end_date, booking);
    var s = _parseDateSafe(booking.start_date); s.setHours(0,0,0,0);
    var e = _parseDateSafe(booking.end_date); e.setHours(0,0,0,0);
    var days = Math.max(1, Math.round((e-s)/86400000)+1);
    var motoName = (moto && moto.model) ? moto.model : (booking.moto_name || 'Motorka nedostupn\u00e1');
    var motoSpz = (moto && moto.spz) ? moto.spz : '\u2014';

    var titleEl = document.getElementById('rd-title');
    if(titleEl) titleEl.textContent = _t('res').resDetail + ' \u2013 ' + _statusLabel(st);
    var subEl = document.getElementById('rd-subtitle');
    if(subEl) subEl.textContent = '#' + bookingId.substr(-8).toUpperCase();

    var imgEl = document.getElementById('rd-moto-img');
    if(imgEl) imgEl.src = (moto && moto.image_url) ? moto.image_url : '';

    var nameEl = document.getElementById('rd-moto-name');
    if(nameEl) nameEl.textContent = motoName;

    var pickupEl = document.getElementById('rd-pickup');
    if(pickupEl) pickupEl.textContent = _fmtDate(booking.start_date) + ' ' + _t('res').at + ' ' + (booking.pickup_time || '9:00');
    var returnEl = document.getElementById('rd-return');
    if(returnEl) returnEl.textContent = _fmtDate(booking.end_date) + ' ' + _t('res').at + ' ' + (booking.pickup_time || '9:00');
    var durEl = document.getElementById('rd-duration');
    if(durEl) durEl.textContent = days + ' ' + (days===1?_t('res').day1:_t('res').days5);

    var totalEl = document.getElementById('rd-total');
    if(totalEl) totalEl.textContent = (booking.total_price||0).toLocaleString('cs-CZ') + ' K\u010d';

    // Payment method — show real card info if available
    var pmEl = document.getElementById('rd-pay-method');
    if(pmEl){
      pmEl.textContent = booking.payment_method === 'card' ? 'Platebn\u00ed karta' : (booking.payment_method || 'Platebn\u00ed karta');
      if(typeof apiFetchPaymentMethods === 'function'){
        apiFetchPaymentMethods().then(function(r){
          if(r.success && r.methods && r.methods.length > 0){
            var def = r.methods.find(function(m){ return m.is_default; }) || r.methods[0];
            var brandIcons = {visa:'VISA',mastercard:'MC',amex:'AMEX'};
            var brand = brandIcons[def.brand] || def.brand.toUpperCase();
            pmEl.textContent = brand + ' \u2022\u2022\u2022\u2022' + def.last4;
          }
        }).catch(function(){});
      }
    }

    // Pickup/return locations
    var branchName = (moto && moto.branches) ? (moto.branches.address || moto.branches.name) + ', ' + (moto.branches.city || '') : '\u2014';
    var pickupLocEl = document.getElementById('rd-pickup-loc');
    if(pickupLocEl){
      if(booking.pickup_method === 'delivery' && booking.pickup_address){
        pickupLocEl.textContent = '\ud83d\ude9a P\u0159istaven\u00ed: ' + booking.pickup_address;
      } else {
        pickupLocEl.textContent = '\ud83c\udfea ' + branchName;
      }
    }
    var returnLocEl = document.getElementById('rd-return-loc');
    if(returnLocEl){
      if(booking.return_method === 'delivery' && booking.return_address){
        returnLocEl.textContent = '\ud83d\ude9a Svoz: ' + booking.return_address;
      } else {
        returnLocEl.textContent = '\ud83c\udfea ' + branchName;
      }
    }

    // Extras detail section
    var extrasEl = document.getElementById('rd-extras');
    if(extrasEl){
      var extrasHtml = '';
      if(booking.extras_price > 0){
        extrasHtml += '<div class="rd-row"><div class="rd-label">P\u0159\u00edslu\u0161enstv\u00ed</div><div class="rd-value">' + (booking.extras_price||0).toLocaleString('cs-CZ') + ' K\u010d</div></div>';
      }
      if(booking.boots_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Boty</div><div class="rd-value">vel. ' + booking.boots_size + '</div></div>';
      if(booking.helmet_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Helma</div><div class="rd-value">vel. ' + booking.helmet_size + '</div></div>';
      if(booking.jacket_size) extrasHtml += '<div class="rd-row"><div class="rd-label">Bunda</div><div class="rd-value">vel. ' + booking.jacket_size + '</div></div>';
      if(booking.delivery_fee > 0) extrasHtml += '<div class="rd-row"><div class="rd-label">Doru\u010den\u00ed</div><div class="rd-value">' + booking.delivery_fee.toLocaleString('cs-CZ') + ' K\u010d</div></div>';
      if(booking.discount_amount > 0){
        var _discLabel = '-' + booking.discount_amount.toLocaleString('cs-CZ') + ' K\u010d';
        if(booking._promoType === 'percent' && booking._promoValue){
          _discLabel = 'sleva ' + booking._promoValue + '%';
        }
        extrasHtml += '<div class="rd-row"><div class="rd-label">Sleva / poukaz</div><div class="rd-value" style="color:var(--green);">' + _discLabel + '</div></div>';
      }
      if(booking.discount_code) extrasHtml += '<div class="rd-row"><div class="rd-label">Slevov\u00fd k\u00f3d</div><div class="rd-value">' + booking.discount_code + '</div></div>';
      extrasEl.innerHTML = extrasHtml;
      extrasEl.style.display = extrasHtml ? 'block' : 'none';
      if(window.supabase && booking.id){
        window.supabase.from('booking_extras').select('*, extras_catalog(name, price)').eq('booking_id', booking.id)
          .then(function(r){
            if(r.data && r.data.length > 0){
              var h = '';
              r.data.forEach(function(ex){ h += '<div class="rd-row"><div class="rd-label">'+(ex.extras_catalog?ex.extras_catalog.name:'Extra')+'</div><div class="rd-value">'+(ex.extras_catalog?ex.extras_catalog.price:0).toLocaleString('cs-CZ')+' K\u010d</div></div>'; });
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
        banner.innerHTML = '\ud83c\udfcd\ufe0f '+_t('res').ridingNow+' ' + daysLeft + ' ' + (daysLeft===1?_t('res').day1:daysLeft<5?_t('res').days2:_t('res').days5) + '.' + refInfo;
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
        banner.innerHTML = '\ud83d\udcc5 '+_t('res').pickupOn+' ' + _fmtDate(booking.start_date) + ' ('+_t('res').inDays+' ' + daysTo + ' ' + (daysTo===1?_t('res').day1:daysTo<5?_t('res').days2:_t('res').days5) + ')' + refInfo2;
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
          mh += '<div style="font-size:12px;color:#4a6357;margin-top:4px;">'+_fmtDate(booking.original_start_date)+' \u2013 '+_fmtDate(booking.original_end_date)+' \u2192 '+_fmtDate(booking.start_date)+' \u2013 '+_fmtDate(booking.end_date)+'</div>';
          mh += '</div>';
          mh += '<div class="rd-row"><div class="rd-label">P\u016fvodn\u00ed term\u00edn</div><div class="rd-value" style="color:#b45309;">'+_fmtDate(booking.original_start_date)+' \u2013 '+_fmtDate(booking.original_end_date)+' ('+_m.origDays+' dn\u00ed)</div></div>';
          mh += '<div class="rd-row"><div class="rd-label">Nov\u00fd term\u00edn</div><div class="rd-value" style="color:'+_m.color+';">'+_fmtDate(booking.start_date)+' \u2013 '+_fmtDate(booking.end_date)+' ('+_m.newDays+' dn\u00ed)</div></div>';
          var _hist2 = Array.isArray(booking.modification_history) ? booking.modification_history : [];
          if(_hist2.length > 0){
            mh += '<div style="margin-top:8px;border-top:1px solid var(--g100);padding-top:8px;">';
            mh += '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:4px;">Historie \u00faprav ('+_hist2.length+'\u00d7)</div>';
            for(var hi2=0; hi2<_hist2.length; hi2++){
              var _hm2 = _descMod(_hist2[hi2].from_start, _hist2[hi2].from_end, _hist2[hi2].to_start, _hist2[hi2].to_end);
              var _hmE2 = '';
              if(_hist2[hi2].from_moto && _hist2[hi2].to_moto) _hmE2 = ' \u00b7 motorka: '+_hist2[hi2].from_moto+' \u2192 '+_hist2[hi2].to_moto;
              mh += '<div style="font-size:11px;color:'+_hm2.color+';margin-bottom:2px;">'+(hi2+1)+'. '+_fmtDT(_hist2[hi2].at)+' \u2014 '+_hm2.type+' ('+_hm2.detail+')'+_hmE2+' \u00b7 '+(_hist2[hi2].source==='admin'?'admin':'z\u00e1kazn\u00edk')+'</div>';
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
          '<button class="btn-out" onclick="showRentalContract(\''+bookingId+'\')">📄 '+(_t('res').contract||'Smlouva o pron\u00e1jmu')+'</button>' +
          '</div>';
      }
      if(st === 'aktivni'){
        btns = '<button class="btn-g" onclick="openEditResByBookingId(\''+bookingId+'\')">✏️ '+_t('res').editExtend+'</button>' +
               '<button class="btn-g" style="background:#fee2e2;color:#b91c1c;border:none;margin-top:8px;" onclick="goTo(\'s-sos\')">🆘 '+_t('res').reportFault+'</button>' +
               '<button class="btn-out" style="margin-top:8px;" onclick="showDigitalProtocol(\''+bookingId+'\')">📝 '+(_t('res').handoverProtocol||'P\u0159ed\u00e1vac\u00ed protokol')+'</button>' +
               docBtns;
      } else if(st === 'nadchazejici'){
        btns = '<button class="btn-g" onclick="openEditResByBookingId(\''+bookingId+'\')">✏️ '+_t('res').editReservation+'</button>' +
               '<button class="btn-g" style="background:var(--red);color:#fff;border:none;margin-top:8px;" onclick="doCancelBooking(\''+bookingId+'\')">🗑️ '+_t('res').cancelRes+'</button>' +
               docBtns;
      } else if(st === 'dokoncene'){
        var motoId = booking.moto_id || (moto ? moto.id : '');
        btns = '<div style="border-top:1px solid var(--g100);padding-top:10px;">' +
               '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:6px;">'+(_t('res').documents||'Dokumenty')+'</div>' +
               '<button class="btn-out" onclick="showInvoice(\''+bookingId+'\',\'final\')">💰 '+(_t('res').finalInvoice||'Kone\u010dn\u00e1 faktura')+'</button>' +
               '<button class="btn-out" style="margin-top:6px;" onclick="showRentalContract(\''+bookingId+'\')">📄 '+(_t('res').contract||'Smlouva o pron\u00e1jmu')+'</button>' +
               '</div>' +
               '<div style="border-top:1px solid var(--g100);margin-top:12px;padding-top:12px;">' +
               '<div style="font-size:10px;font-weight:800;text-transform:uppercase;color:var(--g400);margin-bottom:8px;">⭐ '+(_t('res').yourRating||'Va\u0161e hodnocen\u00ed')+'</div>' +
               '<button class="btn-g" style="margin-top:4px;" onclick="_openGoogleReview()">⭐ '+(_t('res').rateOnGoogle||'Ohodnotit na Google')+'</button>' +
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
        var msgs = ['','\ud83d\ude1e','\ud83d\ude10','\ud83d\ude42','\ud83d\ude0a','\ud83c\udfc6'];
        var msgEl = actionsEl.querySelector('#done-rating-msg');
        if(msgEl) msgEl.textContent = msgs[r] + ' ' + (_t('res').thankStars||'D\u011bkujeme').replace('{n}',r);
      }
    }

    goTo('s-res-detail');
  } catch(e){ console.error('openResDetailById error:', e); }
}
