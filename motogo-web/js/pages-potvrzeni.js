// ===== MotoGo24 Web — Potvrzení rezervace (po Stripe platbě) =====
var MG = window.MG || {};
window.MG = MG;

MG.route('/potvrzeni', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Potvrzení rezervace']);
  var hash = window.location.hash || '';
  var sid = ''; var sm = hash.match(/[?&]session_id=([^&]+)/);
  if(sm) sid = decodeURIComponent(sm[1]);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><div id="confirm-content">' +
    '<div class="loading-overlay"><span class="spinner"></span> Ověřujeme platbu...</div>' +
    '</div></div></div></main>';

  var el = document.getElementById('confirm-content');
  if(!el) return;

  if(!sid){
    el.innerHTML = MG._confirmError('Chybí identifikátor platby.');
    return;
  }

  // Poll booking status (webhook may take a few seconds)
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

MG._confirmSuccess = function(b){
  var motoName = b.moto_id ? b.moto_id.slice(0,8) : '';
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
