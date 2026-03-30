<?php
// ===== MotoGo24 Web PHP — Potvrzení platby (po Stripe) =====

// Read query params from clean URL
$sessionId = isset($_GET['session_id']) ? $_GET['session_id'] : '';
$orderId = isset($_GET['order_id']) ? $_GET['order_id'] : '';
$bookingId = isset($_GET['booking_id']) ? $_GET['booking_id'] : '';

$isShop = !empty($orderId);
$pageTitle = $isShop ? 'Potvrzení objednávky' : 'Potvrzení rezervace';

echo renderHead(
    $pageTitle . ' | MotoGo24',
    'Ověření platby a potvrzení rezervace nebo objednávky na MotoGo24.'
);
echo renderHeader();

echo renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], $pageTitle]);

echo '<main id="content"><div class="container"><div class="ccontent">';
echo '<div id="confirm-content">';
echo '<div class="loading-overlay"><span class="spinner"></span> Ověřujeme platbu...</div>';
echo '</div>';
echo '</div></div></main>';

echo renderFooter();
echo renderPageEnd(true);
?>
<script>
var MG = window.MG || {};
window.MG = MG;

// Helper functions
MG.formatPrice = function(n){
  if(!n && n !== 0) return '';
  return Number(n).toLocaleString('cs-CZ') + ' Kč';
};
MG.formatDate = function(iso){
  if(!iso) return '';
  var d = new Date(iso);
  return d.getDate() + '.' + (d.getMonth()+1) + '.' + d.getFullYear();
};

// Read query params from URL search params (clean URL)
var _params = new URLSearchParams(window.location.search);
var _sid = _params.get('session_id') || '';
var _oid = _params.get('order_id') || '';
var _bid = _params.get('booking_id') || '';
var _isShop = !!_oid;
var _isFreeBooking = !!_bid && !_sid;

// --- Render helpers ---
MG._confirmError = function(msg){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9888;</div>' +
    '<h1>Něco se nepovedlo</h1>' +
    '<p>' + msg + '</p>' +
    '<p>Kontaktujte nás prosím na <a href="tel:+420774256271">+420 774 256 271</a></p>' +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="/rezervace">Zkusit znovu</a></p>' +
    '</div>';
};

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
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

MG._confirmPending = function(b){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9203;</div>' +
    '<h1>Platba se zpracovává</h1>' +
    '<p>Vaše platba byla odeslána a čeká na potvrzení od banky.</p>' +
    '<p>Potvrzení obdržíte e-mailem během několika minut.</p>' +
    (b ? '<p><strong>Termín:</strong> ' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + '</p>' : '') +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

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
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

MG._confirmShopPending = function(order){
  return '<div style="text-align:center;padding:2rem 0">' +
    '<div style="font-size:4rem;margin-bottom:1rem">&#9203;</div>' +
    '<h1>Platba se zpracovává</h1>' +
    '<p>Vaše platba byla odeslána a čeká na potvrzení od banky.</p>' +
    '<p>Potvrzení obdržíte e-mailem během několika minut.</p>' +
    (order ? '<p><strong>Objednávka:</strong> ' + (order.order_number || '') + '</p>' : '') +
    '<p style="margin-top:1.5rem"><a class="btn btngreen" href="/">Zpět na úvodní stránku</a></p>' +
    '</div>';
};

// --- Main polling logic (auto-init) ---
(async function(){
  var el = document.getElementById('confirm-content');
  if(!el) return;

  if(!_sid && !_oid && !_bid){
    el.innerHTML = MG._confirmError('Chybí identifikátor platby.');
    return;
  }

  // --- FREE BOOKING (100% discount, confirmed without Stripe) ---
  if(_isFreeBooking){
    var found = false;
    for(var i = 0; i < 6; i++){
      try {
        var r = await window.sb.from('bookings')
          .select('id,customer_name,customer_email,moto_id,start_date,end_date,total_price,payment_status,status')
          .eq('id', _bid)
          .maybeSingle();
        if(r.data && r.data.payment_status === 'paid'){
          el.innerHTML = MG._confirmSuccess(r.data);
          found = true; break;
        }
        if(r.data && r.data.payment_status === 'unpaid' && i < 5){
          await new Promise(function(ok){ setTimeout(ok, 1500); });
          continue;
        }
        if(r.data){
          el.innerHTML = MG._confirmPending(r.data);
          found = true; break;
        }
      } catch(e){ console.warn('[CONFIRM] free booking poll error', e); }
      await new Promise(function(ok){ setTimeout(ok, 1500); });
    }
    if(!found) el.innerHTML = MG._confirmPending(null);
    return;
  }

  // --- SHOP ORDER (voucher purchase) ---
  if(_isShop){
    var found = false;
    for(var i = 0; i < 12; i++){
      try {
        var r = await window.sb.from('shop_orders')
          .select('id,order_number,customer_name,customer_email,total,payment_status,status')
          .eq('id', _oid)
          .maybeSingle();
        if(r.data && r.data.payment_status === 'paid'){
          var vc = await window.sb.from('vouchers')
            .select('code,amount,valid_until')
            .eq('order_id', _oid);
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
        .eq('stripe_session_id', _sid)
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
})();
</script>
