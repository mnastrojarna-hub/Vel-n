
// Uložená data pro platbu
var _sosReplacementPaymentData = null;

// Called from router when navigating to s-sos-payment
function _sosInitPaymentFromRouter(){
  if(_sosReplacementPaymentData && _sosReplacementPaymentData.total){
    _sosInitPaymentGateway(_sosReplacementPaymentData.total);
  }
}

// Stripe platební brána (pro zaviněné nehody)
function _sosInitPaymentGateway(amount){
    var amountEl = document.getElementById('sos-pay-amount');
    var errorEl = document.getElementById('sos-pay-error');

    if(amountEl){
      amountEl.textContent = amount.toLocaleString('cs-CZ') + ' Kč';
      // Show breakdown under amount
      var parent = amountEl.parentElement;
      if(parent){
        var breakdown = parent.querySelector('.pay-breakdown');
        if(!breakdown){ breakdown = document.createElement('div'); breakdown.className = 'pay-breakdown'; parent.appendChild(breakdown); }
        var pd = _sosReplacementPaymentData;
        if(pd && pd.replacementData){
          var rd = pd.replacementData;
          breakdown.style.cssText = 'font-size:11px;color:var(--g400,#6b7280);margin-top:8px;text-align:left;line-height:1.8;';
          breakdown.innerHTML = '🏍️ Motorka: ' + (rd.moto_total || 0).toLocaleString('cs-CZ') + ' Kč<br>' +
            '🚛 Přistavení: ' + (rd.delivery_fee || 0).toLocaleString('cs-CZ') + ' Kč<br>' +
            '🛡️ <strong>Záloha na poškození: ' + (rd.damage_deposit || 30000).toLocaleString('cs-CZ') + ' Kč</strong>';
        }
      }
    }
    if(errorEl) errorEl.style.display = 'none';
    // Update button text with amount
    var btn = document.getElementById('sos-pay-btn');
    if(btn) btn.textContent = '💳 Zaplatit ' + amount.toLocaleString('cs-CZ') + ' Kč';
}

async function sosPaymentSubmit(){
    var errorEl = document.getElementById('sos-pay-error');
    var btn = document.getElementById('sos-pay-btn');

    if(errorEl) errorEl.style.display = 'none';
    sosLoading();
    if(btn){ btn.textContent = '⏳ Zpracovávám platbu...'; btn.disabled = true; btn.style.opacity = '0.6'; }

    try {
      var pd = _sosReplacementPaymentData;
      if(!pd){
        showT('❌','Chyba','Chybí data objednávky');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; }
        return;
      }

      // Ensure customer_fault is preserved from snapshot
      if(pd.replacementData.customer_fault !== true && _sosFaultSnapshot === true){
        pd.replacementData.customer_fault = true;
      }

      var sosAmount = pd.replacementData.payment_amount || pd.total || 0;

      // First do the swap so we get a replacement booking ID
      await _sosSwapBookingsAndConfirm(pd.incId, pd.replacementData, true, pd.address, pd.city);

      // Find replacement booking ID
      var replBookingId = pd.replacementData.replacement_booking_id;
      if(!replBookingId && pd.incId){
        var incCheck = await window.supabase.from('sos_incidents').select('replacement_booking_id').eq('id', pd.incId).single();
        if(incCheck.data && incCheck.data.replacement_booking_id) replBookingId = incCheck.data.replacement_booking_id;
      }
      if(!replBookingId){
        try {
          var uid = null;
          try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
          if(uid){
            var recentBk = await window.supabase.from('bookings').select('id')
              .eq('user_id', uid).eq('sos_replacement', true)
              .order('created_at', {ascending: false}).limit(1);
            if(recentBk.data && recentBk.data.length > 0) replBookingId = recentBk.data[0].id;
          }
        } catch(e2){ console.warn('[SOS] Retry find replacement booking:', e2); }
      }

      if(!replBookingId){
        console.error('[SOS] No replacement booking ID found after swap. incId=' + pd.incId);
        showT('❌','Chyba','Nepodařilo se vytvořit náhradní rezervaci');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
        return;
      }

      // Process payment via Stripe (inline Payment Element)
      var payResult = await apiProcessPayment(replBookingId, sosAmount, 'card', {type: 'sos', incident_id: pd.incId});

      if(payResult.success && payResult.client_secret){
        // Inline Payment Element — platba v appce
        sosLoadingHide();
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit ' + sosAmount.toLocaleString('cs-CZ') + ' Kč'; }
        showStripeInlinePayment(payResult.client_secret, sosAmount, {
          bookingId: replBookingId,
          onSuccess: function(){
            pd.replacementData.payment_status = 'paid';
            pd.replacementData.paid_at = new Date().toISOString();
            showT('✅','Platba přijata!', sosAmount.toLocaleString('cs-CZ') + ' Kč');
            try {
              if(typeof apiGenerateAdvanceInvoice === 'function') apiGenerateAdvanceInvoice(replBookingId, sosAmount, 'sos').catch(function(){});
              if(typeof apiGeneratePaymentReceipt === 'function') apiGeneratePaymentReceipt(replBookingId, sosAmount, 'sos').catch(function(){});
            } catch(e){}
            goTo('s-reservations');
            if(typeof loadMyReservations === 'function') loadMyReservations();
          },
          onCancel: function(){
            showT('ℹ️','Platba přerušena','Můžete zaplatit později');
            if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
          }
        });
        return;
      }

      if(payResult.success && payResult.checkout_url){
        // Fallback: Checkout redirect
        _stripeCheckoutBookingId = replBookingId;
        if(typeof _lockPaymentScreen==='function') _lockPaymentScreen('↗ Platební brána otevřena...');
        if(btn){ btn.textContent = '↗ Přesměrování na platbu...'; btn.disabled = true; btn.style.opacity = '0.6'; }
        if(typeof _openExternalUrl==='function') _openExternalUrl(payResult.checkout_url);
        else window.location.href = payResult.checkout_url;
        return;
      }

      if(!payResult.success){
        sosLoadingHide();
        showT('❌','Platba selhala', payResult.error || 'Zkuste to znovu');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
      }
    } catch(e){
      console.error('[SOS] Payment processing error:', e);
      sosLoadingHide();
      showT('❌','Chyba při zpracování','Zkuste to znovu');
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
    }
}

// Core: swap bookings via RPC + update incident
async function _sosSwapBookingsAndConfirm(incId, replacementData, isPaid, address, city){
    var isFault = replacementData.customer_fault;
    var total = replacementData.payment_amount || 0;
    var swapOk = false;

    try {
      // 1. Swap bookings via RPC (atomická operace v DB)
      var swapResult = await window.supabase.rpc('sos_swap_bookings', {
        p_incident_id: incId,
        p_replacement_moto_id: replacementData.replacement_moto_id,
        p_replacement_model: replacementData.replacement_model || null,
        p_delivery_fee: replacementData.delivery_fee || 0,
        p_daily_price: replacementData.daily_price || 0,
        p_is_free: !isFault
      });

      if(swapResult.error){
        console.error('[SOS] sos_swap_bookings RPC error:', swapResult.error.message);
      } else if(swapResult.data){
        var sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data;
        if(sr.error){
          console.warn('[SOS] swap returned error:', sr.error);
        } else if(sr.success){
          swapOk = true;
          replacementData.original_booking_id = sr.original_booking_id;
          replacementData.replacement_booking_id = sr.replacement_booking_id;
          replacementData.original_end_date = sr.original_end_date;
        }
      }
    } catch(e){
      console.error('[SOS] swap exception:', e);
    }

    // Pokud RPC swap selhal, zkus manuální fallback (přímé DB operace)
    if(!swapOk){
      console.warn('[SOS] RPC swap failed — trying manual fallback');
      try {
        var uid = await _getUserId();
        if(uid){
          var todayISO = new Date().toISOString().slice(0,10);
          // Najdi aktivní booking (nebo ended_by_sos)
          var bkR = await window.supabase.from('bookings')
            .select('id, moto_id, end_date, original_end_date, status, ended_by_sos')
            .eq('user_id', uid)
            .in('status', ['active','reserved'])
            .eq('payment_status', 'paid')
            .lte('start_date', todayISO)
            .gte('end_date', todayISO)
            .limit(1);
          var origBooking = bkR.data && bkR.data[0];
          // Fallback: hledej ended_by_sos booking
          if(!origBooking){
            var bkR2 = await window.supabase.from('bookings')
              .select('id, moto_id, end_date, original_end_date, status, ended_by_sos')
              .eq('user_id', uid).eq('ended_by_sos', true).eq('status', 'completed')
              .order('created_at', {ascending: false}).limit(1);
            if(bkR2.data && bkR2.data.length > 0) origBooking = bkR2.data[0];
          }
          if(origBooking){
            var alreadyEnded = origBooking.status === 'completed' && origBooking.ended_by_sos;
            var origEndDate = origBooking.original_end_date || origBooking.end_date;
            if(!alreadyEnded){
              // Ukonči původní booking
              await window.supabase.from('bookings').update({
                original_end_date: origBooking.end_date,
                end_date: todayISO,
                status: 'completed',
                ended_by_sos: true,
                sos_incident_id: incId
              }).eq('id', origBooking.id);
            }
            // Vytvoř náhradní booking
            var newBk = await window.supabase.from('bookings').insert({
              user_id: uid,
              moto_id: replacementData.replacement_moto_id,
              start_date: todayISO,
              end_date: origEndDate,
              pickup_time: '09:00',
              status: 'active',
              payment_status: isFault ? 'unpaid' : 'paid',
              total_price: total,
              delivery_fee: isFault ? (replacementData.delivery_fee || 0) : 0,
              sos_replacement: true,
              replacement_for_booking_id: origBooking.id,
              sos_incident_id: incId,
              notes: '[SOS] Náhradní motorka (fallback). Incident: ' + incId,
              picked_up_at: new Date().toISOString()
            }).select('id').single();
            if(newBk.data){
              swapOk = true;
              replacementData.original_booking_id = origBooking.id;
              replacementData.replacement_booking_id = newBk.data.id;
              replacementData.original_end_date = origBooking.end_date;
              // Update incident
              await window.supabase.from('sos_incidents').update({
                original_booking_id: origBooking.id,
                replacement_booking_id: newBk.data.id,
                original_moto_id: origBooking.moto_id
              }).eq('id', incId);
              // Motorka do servisu
              if(origBooking.moto_id){
                await window.supabase.from('motorcycles').update({status:'maintenance'}).eq('id', origBooking.moto_id);
              }
            }
          }
        }
      } catch(e2){ console.error('[SOS] manual fallback failed:', e2); }
    }

    // 2. Update incident
    var newStatus = isFault ? (isPaid ? 'admin_review' : 'pending_payment') : 'admin_review';
    await window.supabase.from('sos_incidents').update({
      replacement_status: newStatus,
      replacement_data: replacementData
    }).eq('id', incId);

    // 3. Timeline
    var actionText = isFault
      ? 'Zákazník zaplatil ' + total + ' Kč a objednal náhradní motorku: ' + (replacementData.replacement_model || '?')
      : 'Zákazník objednal náhradní motorku: ' + (replacementData.replacement_model || '?') + ' (zdarma)';
    if(!swapOk) actionText += ' [SWAP SELHAL — čeká na ruční zpracování adminem]';
    await window.supabase.from('sos_timeline').insert({
      incident_id: incId,
      action: actionText,
      description: 'Adresa: ' + (address||'') + ', ' + (city||'') + '.' + (swapOk ? ' Rezervace automaticky přepnuta.' : ' SWAP SELHAL — admin musí zpracovat ručně.') + ' Čeká na schválení adminem.'
    });

    if(!isFault) apiSosRequestReplacement(incId);

    // 4. Refresh reservations cache
    _cachedBookings = null;

    // 5. Success feedback
    _sosPendingIncidentId = null;
    _sosReplacementPaymentData = null;
    // Refresh reservations cache
    if(typeof renderMyReservations === 'function') renderMyReservations();

    var resBtn = '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>';
    if(!swapOk){
      // Swap selhal — informuj uživatele že admin to vyřeší
      _sosShowDone(isFault ? 'Zaplaceno — ' + total.toLocaleString('cs-CZ') + ' Kč' : 'Požadavek odeslán',
        'Objednávka náhradní motorky (' + (replacementData.replacement_model || '?') + ') byla zaznamenána.<br>' +
        'MotoGo24 zpracuje váš požadavek co nejdříve.<br>' +
        (isFault ? 'Platba přijata, admin potvrdí přepnutí rezervace.' : ''),
        resBtn);
    } else if(isFault){
      _sosShowDone('Zaplaceno — ' + total.toLocaleString('cs-CZ') + ' Kč',
        'Rezervace přepnuta na ' + (replacementData.replacement_model || 'náhradní motorku') + '.<br>' +
        'Objednávka čeká na schválení MotoGo24.<br>' +
        'Zálohová faktura byla vygenerována do sekce Faktury.',
        resBtn);
    } else {
      _sosShowDone('Náhradní motorka objednána',
        'Rezervace přepnuta na ' + (replacementData.replacement_model || 'náhradní motorku') + ' (zdarma).<br>' +
        'Objednávka čeká na schválení MotoGo24.',
        resBtn);
    }
}
