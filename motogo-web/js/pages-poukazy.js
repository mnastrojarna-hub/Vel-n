// ===== MotoGo24 Web — Stránka Poukazy =====

var MG = window.MG || {};
window.MG = MG;

MG.route('/poukazy', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Poukazy']);

  var intro = '<section><h1>Kup dárkový poukaz – daruj zážitek na dvou kolech!</h1>' +
    '<div class="gr2"><div>' +
    '<p>Hledáš originální dárek pro partnera, kamaráda nebo tátu?</p><p>&nbsp;</p>' +
    '<p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovna motorek Vysočina</strong> – potěší začátečníky i zkušené jezdce.</p><p>&nbsp;</p>' +
    '<p>Vyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.</p><p>&nbsp;</p>' +
    '<p><a class="btn btngreen" href="#poukaz-order">OBJEDNAT DÁRKOVÝ POUKAZ</a></p>' +
    '</div><div>' +
    '<img alt="Dárkový poukaz" style="width:100%;max-width:500px;border-radius:10px" loading="lazy" src="gfx/darkovy-poukaz.jpg">' +
    '</div></div></section>';

  var steps = '<section><div class="gr3">' +
    MG.renderWbox('gfx/ico-step1.svg','1. Vyber','Vybereš si hodnotu poukazu nebo konkrétní motorku.') +
    MG.renderWbox('gfx/ico-step2.svg','2. Zaplať','Zaplatíš online.') +
    MG.renderWbox('gfx/ico-step3.svg','3. Vyzvedni','Poukaz po zaplacení přistane do tvé e-mailové schránky.') +
    '</div>' +
    '<p>&nbsp;</p><p>Všechny vouchery mají <strong>platnost 3 roky</strong> od data vystavení. <strong>Obdarovaný si sám zvolí termín výpůjčky</strong>.</p>' +
    '<p>&nbsp;</p>' +
    '<div class="gr2"><div>' +
    '<h2>Proč zakoupit poukaz</h2><ul>' +
    '<li><strong>Flexibilní volba</strong> – hodnota poukazu nebo konkrétní motorka.</li>' +
    '<li><strong>Platnost 3 roky</strong> – obdarovaný si sám vybere termín.</li>' +
    '<li><strong>Bez kauce</strong> – férové podmínky.</li>' +
    '<li><strong>Výbava v ceně</strong> – helma, bunda, kalhoty a rukavice zdarma.</li>' +
    '<li><strong>Nonstop provoz</strong> – vyzvednutí i vrácení kdykoli.</li>' +
    '<li><strong>Online objednávka</strong> – poukaz ti po zaplacení přijde e-mailem.</li></ul>' +
    '</div><div>' +
    '<h2>Jak poukaz využít</h2><ul>' +
    '<li><strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině i celé ČR.</li>' +
    '<li><strong>Sportovní motorky</strong> – adrenalinová jízda v zatáčkách.</li>' +
    '<li><strong>Enduro</strong> – lehký terén a dobrodružství mimo hlavní cesty.</li>' +
    '<li><strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem.</li></ul>' +
    '</div></div>' +
    '<p>&nbsp;</p><p><a class="btn btngreen" href="#/katalog">ZOBRAZIT KATALOG MOTOREK</a></p>' +
    '</section>';

  var faqItems = [
    {q:'Jaká je platnost dárkového poukazu?', a:'Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.'},
    {q:'Jak poukaz doručíte?', a:'<strong>Okamžitě e-mailem</strong> po úhradě. Na požádání umíme připravit i dárkový tisk.'},
    {q:'Musí obdarovaný skládat kauci?', a:'Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové.'},
    {q:'Lze změnit termín uplatnění?', a:'Ano, <strong>termín lze po domluvě změnit</strong> dle dostupnosti konkrétní motorky.'},
    {q:'Na jaké motorky lze voucher uplatnit?', a:'Na <strong>cestovní, sportovní, enduro i dětské motorky</strong> v nabídce Motogo24.'}
  ];

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' + intro + steps +
    '<h2>Často kladené dotazy k dárkovým poukazům</h2>' +
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';

  var faqHtml = '';
  faqItems.forEach(function(faq){ faqHtml += MG.renderFaqItem(faq.q, faq.a); });

  var orderForm = '<section id="poukaz-order"><h2>Objednat dárkový poukaz</h2>' +
    '<div style="max-width:600px">' +
    '<label style="font-weight:600;color:#111;display:block;margin-bottom:.4rem">Hodnota poukazu (Kč)</label>' +
    '<input type="number" id="poukaz-amount" placeholder="Zadejte libovolnou částku v Kč" min="500" step="100" style="margin-bottom:1rem">' +
    '<div class="checkboxes" style="margin:.75rem 0">' +
    '<div><input type="radio" id="poukaz-digital" name="poukaz-type" value="digital" checked><label for="poukaz-digital">Elektronický poukaz (okamžité doručení e-mailem)</label></div>' +
    '<div><input type="radio" id="poukaz-print" name="poukaz-type" value="print"><label for="poukaz-print">Tištěný poukaz (doručení poštou)</label></div>' +
    '</div>' +
    '<div id="poukaz-print-addr" style="display:none;margin-bottom:1rem">' +
    '<input type="text" id="poukaz-addr-name" placeholder="* Jméno a příjmení příjemce">' +
    '<input type="text" id="poukaz-addr-street" placeholder="* Ulice a č.p.">' +
    '<div class="gr2"><input type="text" id="poukaz-addr-zip" placeholder="* PSČ">' +
    '<input type="text" id="poukaz-addr-city" placeholder="* Město"></div>' +
    '</div>' +
    '<input type="text" id="poukaz-buyer-name" placeholder="* Vaše jméno a příjmení" style="margin-bottom:.5rem">' +
    '<input type="email" id="poukaz-buyer-email" placeholder="* Váš e-mail" style="margin-bottom:.5rem">' +
    '<input type="tel" id="poukaz-buyer-phone" placeholder="* Váš telefon (+420...)" style="margin-bottom:1rem">' +
    '<div class="text-center"><button class="btn btngreen" onclick="MG._submitVoucherOrder()">Pokračovat k platbě</button></div>' +
    '</div></section>';

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' + intro + steps + orderForm +
    '<section><h2>Často kladené dotazy k dárkovým poukazům</h2>' +
    '<div class="tab-content"><div class="tab-pane active"><div class="gr2">' +
    faqHtml + '</div></div></div></section>' +
    MG.renderCta('Dárkový poukaz na pronájem motorky – Vysočina',
      'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>.',
      [{label:'OBJEDNAT POUKAZ',href:'#poukaz-order',cls:'btndark pulse'}]) +
    '</div></div></main>';

  // Toggle print address
  var pr = document.getElementById('poukaz-print');
  var di = document.getElementById('poukaz-digital');
  if(pr) pr.addEventListener('change', function(){ var p=document.getElementById('poukaz-print-addr'); if(p) p.style.display='block'; });
  if(di) di.addEventListener('change', function(){ var p=document.getElementById('poukaz-print-addr'); if(p) p.style.display='none'; });
});

// ===== VOUCHER ORDER SUBMIT =====
MG._submitVoucherOrder = async function(){
  var amount = document.getElementById('poukaz-amount');
  var bName = document.getElementById('poukaz-buyer-name');
  var bEmail = document.getElementById('poukaz-buyer-email');
  var bPhone = document.getElementById('poukaz-buyer-phone');
  if(!amount || !amount.value || Number(amount.value) < 500){
    alert('Zadejte prosím částku poukazu (min. 500 Kč).'); return;
  }
  if(!bName || !bName.value || !bEmail || !bEmail.value || !bPhone || !bPhone.value){
    alert('Vyplňte prosím všechna povinná pole.'); return;
  }
  var isPrint = document.getElementById('poukaz-print') && document.getElementById('poukaz-print').checked;
  if(isPrint){
    var aName = document.getElementById('poukaz-addr-name');
    var aSt = document.getElementById('poukaz-addr-street');
    var aZip = document.getElementById('poukaz-addr-zip');
    var aCity = document.getElementById('poukaz-addr-city');
    if(!aName || !aName.value || !aSt || !aSt.value || !aZip || !aZip.value || !aCity || !aCity.value){
      alert('Vyplňte prosím doručovací adresu pro tištěný poukaz.'); return;
    }
  }

  var btn = document.querySelector('#poukaz-order .btn.btngreen');
  if(btn){ btn.disabled = true; btn.textContent = 'Zpracovávám...'; }

  try {
    // Create shop order for voucher
    var orderRes = await window.sb.rpc('create_shop_order', {
      p_items: JSON.stringify([{product_id:null, name:'Dárkový poukaz', quantity:1, price:Number(amount.value)}]),
      p_shipping_method: isPrint ? 'post' : 'email',
      p_shipping_address: isPrint ? JSON.stringify({
        name: document.getElementById('poukaz-addr-name').value,
        street: document.getElementById('poukaz-addr-street').value,
        zip: document.getElementById('poukaz-addr-zip').value,
        city: document.getElementById('poukaz-addr-city').value
      }) : null,
      p_payment_method: 'stripe',
      p_promo_code: null
    });

    if(orderRes.error){
      alert('Chyba: '+orderRes.error.message);
      if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';} return;
    }

    var orderId = orderRes.data?.order_id || orderRes.data?.id;
    var totalAmount = Number(amount.value);

    // Redirect to Stripe
    var payRes = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': window.MOTOGO_CONFIG.SUPABASE_ANON_KEY },
      body: JSON.stringify({
        order_id: orderId, amount: totalAmount,
        type: 'shop', source: 'web', mode: 'checkout',
        customer_email: bEmail.value, customer_name: bName.value
      })
    });
    var payData = await payRes.json();
    if(payData.checkout_url){
      window.location.href = payData.checkout_url;
    } else {
      alert(payData.error || 'Nepodařilo se vytvořit platbu.');
      if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
    }
  } catch(e){
    console.error('[POUKAZ] Error:', e);
    alert('Došlo k chybě. Zkuste to prosím znovu.');
    if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}
  }
};
