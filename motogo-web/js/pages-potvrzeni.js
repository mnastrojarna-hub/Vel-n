// ===== MotoGo24 Web — Potvrzení platby (po Stripe) =====
// Podporuje: booking (session_id) i shop objednávky (order_id)
var MG = window.MG || {};
window.MG = MG;

MG.route('/potvrzeni', async function(app){
  var hash = window.location.hash || '';
  var sid = ''; var sm = hash.match(/[?&]session_id=([^&]+)/);
  if(sm) sid = decodeURIComponent(sm[1]);
  var oid = ''; var om = hash.match(/[?&]order_id=([^&]+)/);
  if(om) oid = decodeURIComponent(om[1]);

  var isShop = !!oid;
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'}, isShop ? 'Potvrzení objednávky' : 'Potvrzení rezervace']);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><div id="confirm-content">' +
    '<div class="loading-overlay"><span class="spinner"></span> Ověřujeme platbu...</div>' +
    '</div></div></div></main>';

  var el = document.getElementById('confirm-content');
  if(!el) return;

  if(!sid && !oid){
    el.innerHTML = MG._confirmError('Chybí identifikátor platby.');
    return;
  }

  // --- SHOP ORDER (voucher purchase) ---
  if(isShop){
    var found = false;
    for(var i = 0; i < 12; i++){
      try {
        var r = await window.sb.from('shop_orders')
          .select('id,order_number,customer_name,customer_email,total,payment_status,status')
          .eq('id', oid)
          .maybeSingle();
        if(r.data && r.data.payment_status === 'paid'){
          // Fetch voucher codes
          var vc = await window.sb.from('vouchers')
            .select('code,amount,valid_until')
            .eq('order_id', oid);
          el.innerHTML = MG._confirmShopSuccess(r.data, vc.data || []);
          found = true; break;
        }
        if(r.data && r.data.payment_status !== 'paid' && i < 11){
          await new Promise(function(ok){ setTimeout(ok, 2000); });
          continue;
        }
        if(r.data){
          el.innerHTML = MG._confirmShopPending(r.data);
          found = true; break;
        }
      } catch(e){ console.warn('[CONFIRM] shop poll error', e); }
      await new Promise(function(ok){ setTimeout(ok, 2000); });
    }
    if(!found) el.innerHTML = MG._confirmShopPending(null);
    return;
  }

  // --- BOOKING ---
  var found = false;
  for(var i = 0; i < 10; i++){
    try {
      var r = await window.sb.from('bookings')
        .select('id,customer_name,customer_email,moto_id,start_date,end_date,total_price,payment_status,status')
        .eq('stripe_session_id', sid)
        .maybeSingle();
      if(r.data && r.data.payment_status === 'paid'){
        el.innerHTML = MG._confirmSuccess(r.data);
        found = true; break;
      }
      if(r.data && r.data.payment_status === 'unpaid' && i < 9){
        await new Promise(function(ok){ setTimeout(ok, 2000); });
        continue;
      }
      if(r.data){
        el.innerHTML = MG._confirmPending(r.data);
        found = true; break;
      }
    } catch(e){ console.warn('[CONFIRM] poll error', e); }
    await new Promise(function(ok){ setTimeout(ok, 2000); });
  }

  if(!found){
    el.innerHTML = MG._confirmPending(null);
  }
});

// --- SHOP SUCCESS ---
MG._confirmShopSuccess = function(order, vouchers){
  var voucherHtml = '';
  if(vouchers && vouchers.length > 0){
    voucherHtml = '<div style="margin:1.5rem 0">';
    vouchers.forEach(function(v){
      var validUntil = v.valid_until ? new Date(v.valid_until).toLocaleDateString('cs-CZ') : '—';
      voucherHtml += '<div style="background:#fff;border:2px solid #1a8c1a;border-radius:12px;padding:1rem;margin-bottom:.75rem;text-align:center">' +
        '<div style="font-size:.8rem;color:#6b7280;text-transform:uppercase;letter-spacing:2px;margin-bottom:4px">Kód poukazu</div>' +
        '<div style="font-size:1.5rem;font-weight:900;color:#1a8c1a;letter-spacing:3px;font-family:monospace">' + v.code + '</div>' +
        '<div style="font-size:1rem;font-weight:700;margin-top:6px">' + MG.formatPrice(v.amount) + '</div>' +
        '<div style="font-size:.8rem;color:#6b7280;margin-top:4px">Platný do ' + validUntil + '</div>' +
        '</div>';
    });
    voucherHtml += '</div>';
  }

  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#10004;</div>' +
    '<h1 style="color:#1a8c1a">Objednávka zaplacena!</h1>' +
    '<p style="font-size:1.1rem">Děkujeme, <strong>' + (order.customer_name||'') + '</strong>. Vaše platba byla úspěšně přijata.</p>' +
    voucherHtml +
    '<div style="background:#e8fce8;border-radius:12px;padding:1.5rem;margin:1.5rem auto;max-width:500px;text-align:left">' +
    '<p><strong>Objednávka:</strong> ' + (order.order_number || '') + '</p>' +
    '<p><strong>Celková cena:</strong> ' + MG.formatPrice(order.total) + '</p>' +
    '<p><strong>Stav:</strong> Zaplaceno &#10004;</p>' +
    '<p><strong>E-mail:</strong> ' + (order.customer_email||'') + '</p>' +
    '</div>' +
    '<p>Na váš e-mail jsme odeslali potvrzení s detaily objednávky' + (vouchers && vouchers.length > 0 ? ' a kódem poukazu' : '') + '.</p>' +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="#/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

// --- SHOP PENDING ---
MG._confirmShopPending = function(order){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9203;</div>' +
    '<h1>Platba se zpracovává</h1>' +
    '<p>Vaše platba byla odeslána a čeká na potvrzení od banky.</p>' +
    '<p>Potvrzení obdržíte e-mailem během několika minut.</p>' +
    (order ? '<p><strong>Objednávka:</strong> ' + (order.order_number || '') + '</p>' : '') +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="#/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

// --- BOOKING SUCCESS ---
MG._confirmSuccess = function(b){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#10004;</div>' +
    '<h1 style="color:#1a8c1a">Rezervace potvrzena!</h1>' +
    '<p style="font-size:1.1rem">Děkujeme, <strong>' + (b.customer_name||'') + '</strong>. Vaše platba byla úspěšně přijata.</p>' +
    '<div style="background:#e8fce8;border-radius:12px;padding:1.5rem;margin:1.5rem auto;max-width:500px;text-align:left">' +
    '<p><strong>Termín:</strong> ' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + '</p>' +
    '<p><strong>Celková cena:</strong> ' + MG.formatPrice(b.total_price) + '</p>' +
    '<p><strong>Stav:</strong> Zaplaceno &#10004;</p>' +
    '<p><strong>E-mail:</strong> ' + (b.customer_email||'') + '</p>' +
    '</div>' +
    '<p>Na váš e-mail jsme odeslali potvrzení s detaily rezervace.</p>' +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="#/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

MG._confirmPending = function(b){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9203;</div>' +
    '<h1>Platba se zpracovává</h1>' +
    '<p>Vaše platba byla odeslána a čeká na potvrzení od banky.</p>' +
    '<p>Potvrzení obdržíte e-mailem během několika minut.</p>' +
    (b ? '<p><strong>Termín:</strong> ' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + '</p>' : '') +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="#/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

MG._confirmError = function(msg){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9888;</div>' +
    '<h1>Něco se nepovedlo</h1>' +
    '<p>' + msg + '</p>' +
    '<p>Kontaktujte nás prosím na <a href="tel:+420774256271">+420 774 256 271</a></p>' +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="#/rezervace">Zkusit znovu</a></p>' +
    '</div>';
};
