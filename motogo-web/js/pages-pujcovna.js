// ===== MotoGo24 Web — Stránka Půjčovna motorek =====

var MG = window.MG || {};
window.MG = MG;

MG.route('/pujcovna-motorek', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Půjčovna motorek']);

  var intro = '<section><h1>Půjčovna motorek Vysočina Motogo24</h1>' +
    '<p>Naše <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – ' +
    '<strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. ' +
    'Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, ' +
    'a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.</p></section>';

  var benefits = '<section><h2>Proč si půjčit motorku u nás</h2><div class="gr6">' +
    MG.renderWbox('gfx/ico-bez-kauce.svg','Bez kauce','a bez skrytých poplatků') +
    MG.renderWbox('gfx/ico-rezervace.svg','Online rezervace','na pár kliknutí') +
    MG.renderWbox('gfx/ico-vybava.svg','Výbava v ceně','pro řidiče') +
    MG.renderWbox('gfx/ico-nonstop.svg','Nonstop provoz','vyzvednutí i vrácení kdykoli') +
    MG.renderWbox('gfx/ico-spolecne.svg','Jsme v tom společně','když se něco přihodí') +
    MG.renderWbox('gfx/ico-pristaveni.svg','Možnost přistavení motorky','na domluvené místo') +
    '</div><p>&nbsp;</p>' +
    '<p>Hledáte <strong>půjčovnu motorek na Vysočině</strong>? Motogo24 nabízí férové podmínky, jasný postup a špičkově udržované stroje.</p>' +
    '<p>&nbsp;</p><p>' +
    '<a class="btn btndark" href="#/katalog">Zobrazit motorky k pronájmu</a> ' +
    '<a class="btn btngreen pulse" href="#/rezervace">REZERVOVAT</a></p></section>';

  var steps = '<section><h2>Jak probíhá půjčení motorky na Vysočině</h2><div class="gr4">' +
    MG.renderWbox('gfx/ico-step1.svg','1. Vyber motorku','Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje.') +
    MG.renderWbox('gfx/ico-step2.svg','2. Zvol jezdce','Jednoduše zaškrtni, kolik vás pojede. Zobrazí se ti jen vhodné motorky.') +
    MG.renderWbox('gfx/ico-step3.svg','3. Rezervuj online','Uskutečni rezervaci podle data nebo podle konkrétní motorky.') +
    MG.renderWbox('gfx/ico-step4.svg','4. Vyber výbavu','K zapůjčení automaticky nabízíme helmu, bundu, kalhoty a rukavice.') +
    MG.renderWbox('gfx/ico-step5.svg','5. Zaplať','Zaplať online nebo osobně na místě.') +
    MG.renderWbox('gfx/ico-step6.svg','6. Převezmi motorku','Přijď si motorku vyzvednout osobně, nebo využij bezkontaktní předání.') +
    MG.renderWbox('gfx/ico-step7.svg','7. Užij si jízdu','Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.') +
    MG.renderWbox('gfx/ico-step8.svg','8. Vrať motorku včas','Motorku jednoduše vrať ve sjednaný den, bez stresu a skrytých povinností.') +
    '</div></section>';

  var faqItems = [
    {q:'Jak si mohu rezervovat motorku?', a:'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'},
    {q:'Můžu si motorku půjčit i bez předchozí rezervace?', a:'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit.'},
    {q:'Musím složit kauci?', a:'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'},
    {q:'Můžu odcestovat s motorkou do zahraničí?', a:'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'}
  ];
  var faqHtml = MG.renderFaqSection('Často kladené otázky', faqItems, '/jak-pujcit/faq');

  var ctaHtml = MG.renderCta('Rezervuj svou motorku online',
    'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
    [{label:'REZERVOVAT MOTORKU',href:'/rezervace',cls:'btndark pulse'},{label:'Dárkový poukaz',href:'/poukazy',cls:'btndark'},{label:'Tipy na trasy',href:'/blog',cls:'btndark'}]);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' + intro + benefits + steps + faqHtml + ctaHtml + '</div></div></main>';
});
