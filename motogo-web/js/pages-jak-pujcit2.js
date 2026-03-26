// ===== MotoGo24 Web — Jak si půjčit (vyzvednutí, co v ceně, dokumenty) =====

var MG = window.MG || {};
window.MG = MG;

// ===== VYZVEDNUTÍ MOTOCYKLU =====
MG.route('/jak-pujcit/vyzvednuti', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Jak si půjčit',href:'/jak-pujcit'},'Vyzvednutí motocyklu']);

  var mapIframe = '<iframe class="map" loading="lazy" src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d53928.274636159236!2d15.154130970132716!3d49.35168867371007!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x470ce75bf69a97b3%3A0xe75f9d3fadf02b5b!2zTWV6bsOhIDksIDM5MyAwMSBNZXpuw6E!5e0!3m2!1scs!2scz!4v1759860051295!5m2!1scs!2scz" title="Jak se k nám dostanete"></iframe>';

  var faqItems = [
    {q:'Musím platit kauci při vyzvednutí?', a:'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.'},
    {q:'Je možný kontakt bez osobního setkání?', a:'Ano, nabízíme <strong>bezkontaktní předání</strong> po domluvě.'},
    {q:'Co když nestíhám domluvený čas?', a:'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong>.'},
    {q:'Je v ceně i výbava pro spolujezdce?', a:'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.'}
  ];

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' +
    '<section><h1>Vyzvednutí motocyklu – rychle, jednoduše a nonstop</h1>' +
    '<p>V <strong>Motogo24 – půjčovna motorek Vysočina</strong> je <strong>vyzvednutí motorky</strong> otázkou pár minut. Půjčujeme <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.</p>' +
    '<p>&nbsp;</p><p><a class="btn btngreen" href="#/rezervace">REZERVOVAT ONLINE</a></p></section>' +

    '<section><div class="gr2"><div>' +
    '<h2>Kde probíhá vyzvednutí</h2>' +
    '<p><strong>Provozovna:</strong> Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)</p>' +
    '<p><strong>Provozní doba:</strong> <em>nonstop</em></p>' +
    '<p><strong>Telefon:</strong> <a href="tel:+420774256271">+420 774 256 271</a></p>' +
    '<p>&nbsp;</p><h2>Vrácení motorky – bez stresu</h2>' +
    '<p>Motorku můžeš vrátit <strong>kdykoli během posledního dne výpůjčky</strong>. Nevyžadujeme vrácení s plnou nádrží ani mytí.</p>' +
    '</div><div><p>' + mapIframe + '</p></div></div></section>' +

    '<section><h2>Jak probíhá vyzvednutí krok za krokem</h2><div class="gr5">' +
    MG.renderWbox('gfx/ico-step1.svg','Přijď v domluvený čas','na naši adresu nebo vyčkej na přistavení') +
    MG.renderWbox('gfx/ico-step2.svg','Ověříme doklady','OP/pas + řidičský průkaz odpovídající skupiny') +
    MG.renderWbox('gfx/ico-step3.svg','Předáme motorku a výbavu','helma, bunda, kalhoty, rukavice') +
    MG.renderWbox('gfx/ico-step4.svg','Krátké seznámení se strojem','ovládání, tipy, doporučení k trase') +
    MG.renderWbox('gfx/ico-step5.svg','Podepíšeme předávací protokol','a můžeš vyrazit') +
    '</div></section>' +

    '<section><h2>Co si vzít s sebou</h2><ul>' +
    '<li><strong>Občanský průkaz / pas</strong></li>' +
    '<li><strong>Řidičský průkaz</strong> odpovídající skupiny (A/A2 podle motorky)</li>' +
    '<li><strong>Vhodnou obuv</strong> (moto boty lze půjčit jako nadstandard)</li>' +
    '</ul><p>&nbsp;</p><p><a class="btn btngreen" href="#/rezervace">ZAREZERVOVAT TERMÍN</a></p></section>' +

    MG.renderFaqSection('Časté dotazy k vyzvednutí', faqItems) +
    MG.renderCta('Vyzvednutí motorky – půjčovna motorek Vysočina',
      'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop vyzvednutím i vrácením</strong>, <strong>bez kauce</strong> a s <strong>výbavou v ceně</strong>.',
      [{label:'REZERVOVAT ONLINE',href:'/rezervace',cls:'btndark pulse'}]) +
    '</div></div></main>';
});

// ===== CO JE V CENĚ =====
MG.route('/jak-pujcit/co-v-cene', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Jak si půjčit',href:'/jak-pujcit'},'Co je v ceně']);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' +
    '<section><h1>Co je v ceně pronájmu motorky</h1>' +
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> dostaneš férové podmínky. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>.</p>' +
    '<div class="gr2"><div>' +
    '<h2>Základní výbava zdarma</h2>' +
    '<p>Každý řidič má k dispozici kompletní <strong>motorkářskou výbavu</strong>:</p>' +
    '<ul><li><strong>Helma</strong> – vždy čistá a bezpečná</li><li><strong>Motorkářská bunda</strong> s chrániči</li><li><strong>Moto kalhoty</strong> pro maximální komfort</li><li><strong>Rukavice</strong> ve správné velikosti</li></ul>' +
    '</div><div>' +
    '<h2>Nadstandardní výbava</h2>' +
    '<ul><li><strong>Výbava pro spolujezdce</strong></li><li><strong>Páteřák</strong> pro maximální ochranu</li><li><strong>Chrániče hrudi</strong> (pro enduro/cross)</li><li><strong>Motorkářské boty</strong></li><li><strong>Bluetooth komunikátor</strong></li><li><strong>Kufry</strong> a zavazadlový systém</li></ul>' +
    '</div></div></section>' +

    '<section aria-labelledby="benefits"><h2>Další výhody v ceně</h2><div class="gr6">' +
    MG.renderWbox('gfx/ico-nonstop.svg','Nonstop provoz','vyzvednutí i vrácení kdykoli') +
    MG.renderWbox('gfx/ico-bez-kauce.svg','Bez kauce','žádná záloha při půjčení') +
    MG.renderWbox('gfx/ico-pojisteni.svg','Pojištění','součástí pronájmu') +
    MG.renderWbox('gfx/ico-bezkontaktni.svg','Bezkontaktní předání','na vyžádání') +
    MG.renderWbox('gfx/ico-jasna-pravidla.svg','Jasné podmínky','bez skrytých poplatků') +
    '</div></section>' +

    '<section><h2>Rezervuj si motorku s výbavou v ceně</h2>' +
    '<p>Vyber si z nabídky <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyraž na cestu bez starostí. Vše potřebné máš zahrnuto v půjčovném.</p></section>' +

    MG.renderCta('Výbava v ceně – půjčovna motorek Vysočina',
      'Motogo24 je moderní <strong>půjčovna motorek na Vysočině</strong>. U nás dostaneš <strong>výbavu v ceně</strong>, půjčení <strong>bez kauce</strong>, <strong>online rezervaci</strong> a <strong>nonstop provoz</strong>.',
      [{label:'REZERVOVAT ONLINE',href:'/rezervace',cls:'btndark pulse'}]) +
    '</div></div></main>';
});

// ===== DOKUMENTY A NÁVODY =====
MG.route('/jak-pujcit/dokumenty', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Jak si půjčit',href:'/jak-pujcit'},'Dokumenty a návody']);

  var paymentTable = MG.renderTable(
    ['Položka','Podmínky'],
    [
      ['<strong>Platba nájemného</strong>','Online předem.'],
      ['<strong>Storno rezervace</strong>','Lze bezplatně do předem domluveného času.'],
      ['<strong>Palivo & čištění</strong>','Vrácení bez povinnosti dotankovat a mýt.'],
      ['<strong>Přistavení / svoz</strong>','Dle ceníku přistavení.'],
      ['<strong>Pozdní vrácení</strong>','Při zpoždění účtujeme dle domluvy.']
    ]
  );

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent">' +
    '<section><h1>Nájemní smlouva a kauce – férové podmínky bez zálohy</h1>' +
    '<p>V <strong>Motogo24</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>, <strong>pojištěním v ceně</strong> a <strong>výbavou pro řidiče</strong>.</p>' +
    '<p>&nbsp;</p><p><a class="btn btngreen" href="#/rezervace">REZERVOVAT ONLINE</a></p></section>' +

    '<section><h2>Shrnutí hlavních bodů</h2><div class="gr6">' +
    MG.renderWbox('gfx/ico-bez-kauce.svg','Bez kauce / zálohy','motorku půjčujeme bez blokace peněz') +
    MG.renderWbox('gfx/ico-pojisteni.svg','Pojištění','v ceně (povinné ručení; havarijní dle konkrétního modelu a podmínek)') +
    MG.renderWbox('gfx/ico-vybava.svg','Výbava pro řidiče','v ceně (helma, bunda, kalhoty, rukavice)') +
    MG.renderWbox('gfx/ico-nonstop.svg','Nonstop provoz','převzetí a vrácení kdykoli v den výpůjčky') +
    MG.renderWbox('gfx/ico-jasna-pravidla.svg','Jasná pravidla užívání','doma i v zahraničí (podle zelené karty)') +
    MG.renderWbox('gfx/ico-bezskryte.svg','Žádné skryté poplatky','vše je uvedeno níže a ve smlouvě') +
    '</div></section>' +

    '<section><h2>Co potřebujete k uzavření smlouvy</h2><ul>' +
    '<li><strong>Občanský průkaz / pas</strong></li><li><strong>Řidičský průkaz</strong> odpovídající skupiny</li>' +
    '<li><strong>Věk</strong> min. 18 let</li><li><strong>Kontakty</strong> (telefon, e-mail)</li></ul>' +
    '<p>&nbsp;</p><h2>Platby, storno a poplatky</h2>' + paymentTable + '</section>' +

    '<section><div class="gr2"><div><h2>Užívání motorky a odpovědnost</h2><ul>' +
    '<li>Jezděte v <strong>souladu s předpisy</strong></li>' +
    '<li>Za <strong>pokuty a přestupky</strong> odpovídá nájemce</li>' +
    '<li><strong>Zahraničí</strong>: možné; řiďte se územní platností pojištění</li>' +
    '<li>V případě <strong>nehody nebo poruchy</strong> postupujte dle pokynů</li>' +
    '<li><strong>Úpravy motorky</strong> bez souhlasu nejsou dovoleny</li></ul></div>' +
    '<div><h2>Předání a vrácení</h2><ul>' +
    '<li><strong>Převzetí</strong> v Pelhřimově nebo <a href="#/jak-pujcit/pristaveni">přistavení</a></li>' +
    '<li>Při předání obdržíte <strong>klíče, výbavu a dokumenty</strong></li>' +
    '<li><strong>Vrácení</strong> kdykoli během posledního dne výpůjčky</li></ul></div></div></section>' +

    MG.renderCta('Nájemní smlouva bez kauce – půjčovna motorek Vysočina',
      'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s férovými podmínkami.',
      [{label:'REZERVOVAT ONLINE',href:'/rezervace',cls:'btndark pulse'}]) +
    '</div></div></main>';
});
