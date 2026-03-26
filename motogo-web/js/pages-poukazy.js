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
    '<p><a class="btn btngreen" href="#/kontakt">OBJEDNAT DÁRKOVÝ POUKAZ</a></p>' +
    '</div><div>' +
    '<img alt="Dárkový poukaz" class="imgres" loading="lazy" src="gfx/darkovy-poukaz.jpg">' +
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

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' + intro + steps +
    '<section><h2>Často kladené dotazy k dárkovým poukazům</h2>' +
    '<div class="tab-content"><div class="tab-pane active"><div class="gr2">' +
    faqHtml + '</div></div></div></section>' +
    MG.renderCta('Dárkový poukaz na pronájem motorky – Vysočina',
      'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>.',
      [{label:'OBJEDNAT VOUCHER',href:'/kontakt',cls:'btndark pulse'}]) +
    '</div></div></main>';
});
