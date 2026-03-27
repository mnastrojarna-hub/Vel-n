// ===== MotoGo24 Web — Jak si půjčit motorku (podstránky) =====

var MG = window.MG || {};
window.MG = MG;

// ===== JAK SI PŮJČIT — OVERVIEW =====
MG.route('/jak-pujcit', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Jak si půjčit motorku']);
  var links = [
    {href:'/jak-pujcit/postup', label:'Postup půjčení motorky'},
    {href:'/jak-pujcit/pristaveni', label:'Přistavení motocyklu'},
    {href:'/jak-pujcit/vyzvednuti', label:'Vyzvednutí motocyklu'},
    {href:'/jak-pujcit/co-v-cene', label:'Co je v ceně'},
    {href:'/jak-pujcit/dokumenty', label:'Dokumenty a návody'},
    {href:'/jak-pujcit/faq', label:'Často kladené dotazy'}
  ];
  var linksHtml = '<div class="gr3">';
  links.forEach(function(l){
    linksHtml += '<a class="gbox" href="#' + l.href + '"><div class="gr2"><div><h3>' + l.label + '</h3></div></div></a>';
  });
  linksHtml += '</div>';

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><h1>Jak si půjčit motorku</h1>' +
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.</p>' +
    '<p>&nbsp;</p>' + linksHtml +
    '</div></div></main>';
});

// ===== POSTUP PŮJČENÍ =====
MG.route('/jak-pujcit/postup', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Jak si půjčit',href:'/jak-pujcit'},'Postup půjčení motorky']);
  var intro = '<h1>Postup půjčení motorky</h1>' +
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>. Podívej se, jak snadno to funguje.</p>' +
    '<p>&nbsp;</p><h2>Jak si půjčit motorku – půjčovna Motogo24 Vysočina</h2>' +
    '<p>V <strong>půjčovně motorek Motogo24</strong> je <strong>postup půjčení motorky</strong> jednoduchý: <strong>online rezervace</strong>, <strong>výbava v ceně</strong>, <strong>bez kauce</strong>, <strong>nonstop provoz</strong> a možnost <strong>přistavení motorky</strong>. Ať hledáš <strong>cestovní motorku</strong> na víkend, <strong>sportovní motorku</strong> pro adrenalin nebo <strong>enduro</strong> do terénu, u nás najdeš ideální řešení.</p>';

  var steps = '<section aria-labelledby="process"><h2>Jak probíhá pronájem krok za krokem</h2><div class="gr4">' +
    MG.renderWbox('gfx/ico-step1.svg','1. Vyber motorku','Prohlédni si naši nabídku <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyber si tu pravou.') +
    MG.renderWbox('gfx/ico-step2.svg','2. Počet jezdců','Zvol, jestli pojedeš sám, nebo se spolujezdcem. Nabídneme ti vhodné stroje a výbavu.') +
    MG.renderWbox('gfx/ico-step3.svg','3. Rezervace online','Jednoduše si zarezervuj motorku podle data. Platbu proveď předem <strong>online</strong>.') +
    MG.renderWbox('gfx/ico-step4.svg','4. Výbava v ceně','Automaticky, jako řidič, dostaneš helmu, bundu, kalhoty a rukavice. Velikost si vybereš při rezervaci.') +
    MG.renderWbox('gfx/ico-step5.svg','5. Potvrzení a platba','Rezervace je závazná po potvrzení. Platbu provedeš online.') +
    MG.renderWbox('gfx/ico-step6.svg','6. Převzetí motorky','Převezmeš motorku osobně v Pelhřimově nebo využiješ <strong>přistavení</strong> na domluvené místo.') +
    MG.renderWbox('gfx/ico-step7.svg','7. Užij si jízdu','Vyraz na cestu – <strong>bez kauce, bez stresu</strong>, s jasnými podmínkami a pojištěním v ceně.') +
    MG.renderWbox('gfx/ico-step8.svg','8. Vrácení motorky','Motorku vrátíš kdykoli během posledního dne výpůjčky. Nemusíš tankovat ani mýt.') +
    '</div></section>';

  var faqItems = [
    {q:'Je nutná kauce při půjčení?', a:'Ne. <strong>Půjčujeme bez kauce</strong> – férově a bez zbytečných překážek.'},
    {q:'Je v ceně půjčovného i výbava?', a:'Ano. Každý řidič dostane <strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.'},
    {q:'Kde si mohu motorku převzít?', a:'Vyzvednutí probíhá v Pelhřimově, případně nabízíme <strong>přistavení motorky</strong> na tebou zvolené místo.'},
    {q:'Do kdy musím motorku vrátit?', a:'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.'}
  ];

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' + intro + steps +
    MG.renderFaqSection('Často kladené otázky', faqItems, '/jak-pujcit/faq') +
    MG.renderCta('Připraven na jízdu?','Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong>.',[{label:'REZERVOVAT ONLINE',href:'/rezervace',cls:'btndark pulse'}]) +
    '</div></div></main>';
});

// ===== PŘISTAVENÍ MOTOCYKLU =====
MG.route('/jak-pujcit/pristaveni', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Jak si půjčit',href:'/jak-pujcit'},'Přistavení motocyklu']);

  var pricingTable = MG.renderTable(
    ['Vzdálenost od Pelhřimova','Cena za 1 směr','Příklady lokalit'],
    [
      ['Do 10 km','290 Kč','Centrum Pelhřimov, blízké obce'],
      ['Do 30 km','590 Kč','Humpolec, Kamenice nad Lipou, Pacov'],
      ['Do 60 km','990 Kč','Jihlava, Třebíč, Tábor'],
      ['Do 100 km','1 490 Kč','České Budějovice, Kolín, Havlíčkův Brod'],
      ['100+ km','Individuálně','Praha, Brno, další místa po dohodě']
    ]
  );

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' +
    '<h1>Přistavení motocyklu – doručení až k tobě</h1>' +
    '<p>Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky</strong> na <strong>domluvené místo</strong>.</p>' +
    '<p>&nbsp;</p><p><a class="btn btngreen" href="#/rezervace?delivery=1">REZERVOVAT S PŘISTAVENÍM</a></p>' +

    '<section><h2>Proč využít přistavení motorky</h2><div class="gr5">' +
    MG.renderWbox('gfx/ico-pohodli.svg','Pohodlí a čas','motorku přivezeme, kam potřebuješ') +
    MG.renderWbox('gfx/ico-flexibilita.svg','Flexibilita','vyzvednutí i vrácení lze řešit mimo provozovnu.') +
    MG.renderWbox('gfx/ico-nonstop.svg','Nonstop provoz','přistavení/vrácení v den výpůjčky i večer') +
    MG.renderWbox('gfx/ico-bez-kauce.svg','Bez kauce','férové a jasné podmínky půjčovny Motogo24') +
    MG.renderWbox('gfx/ico-vybava.svg','Výbava v ceně','pro řidiče') +
    '</div></section>' +

    '<section><h2>Ceník přistavení a svozu</h2>' +
    '<p>Výchozí bod: <strong>Pelhřimov (Vysočina)</strong>. Obousměrnou dopravu účtujeme jako dvojnásobek.</p><p>&nbsp;</p>' +
    pricingTable + '</section>' +

    '<section aria-labelledby="process"><h2>Jak přistavení probíhá</h2><div class="gr4">' +
    MG.renderWbox('gfx/ico-step1.svg','Vyber motorku a termín','v online rezervaci') +
    MG.renderWbox('gfx/ico-step3.svg','Zadej adresu','přistavení/vrácení (hotel, nádraží, adresa)') +
    MG.renderWbox('gfx/ico-step5.svg','Potvrď cenu','za dopravu dle vzdálenosti') +
    MG.renderWbox('gfx/ico-step6.svg','Převzetí na místě','předáme klíče, výbavu a dokumenty') +
    '</div></section>' +

    MG.renderCta('Přistavení motorky – půjčovna motorek Vysočina',
      'Motogo24 nabízí <strong>přistavení motocyklu</strong> po regionu i mimo něj. <strong>Nonstop provoz, bez kauce, výbava v ceně</strong>.',
      [{label:'REZERVOVAT S PŘISTAVENÍM',href:'/rezervace?delivery=1',cls:'btndark pulse'}]) +
    '</div></div></main>';
});
