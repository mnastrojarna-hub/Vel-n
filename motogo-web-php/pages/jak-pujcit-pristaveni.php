<?php
// ===== MotoGo24 Web PHP — Přistavení motocyklu =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Přistavení motocyklu']);

$pricingTable = renderTable(
    ['Vzdálenost od Pelhřimova', 'Cena za 1 směr', 'Příklady lokalit'],
    [
        ['Do 10 km', '290 Kč', 'Centrum Pelhřimov, blízké obce'],
        ['Do 30 km', '590 Kč', 'Humpolec, Kamenice nad Lipou, Pacov'],
        ['Do 60 km', '990 Kč', 'Jihlava, Třebíč, Tábor'],
        ['Do 100 km', '1 490 Kč', 'České Budějovice, Kolín, Havlíčkův Brod'],
        ['100+ km', 'Individuálně', 'Praha, Brno, další místa po dohodě'],
    ]
);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<h1>Přistavení motocyklu – doručení až k tobě</h1>' .
    '<p>Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky</strong> na <strong>domluvené místo</strong>.</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/rezervace?delivery=1">REZERVOVAT S PŘISTAVENÍM</a></p>' .

    '<section><h2>Proč využít přistavení motorky</h2><div class="gr5">' .
    renderWbox('gfx/ico-pohodli.svg', 'Pohodlí a čas', 'motorku přivezeme, kam potřebuješ') .
    renderWbox('gfx/ico-flexibilita.svg', 'Flexibilita', 'vyzvednutí i vrácení lze řešit mimo provozovnu.') .
    renderWbox('gfx/ico-nonstop.svg', 'Nonstop provoz', 'přistavení/vrácení v den výpůjčky i večer') .
    renderWbox('gfx/ico-bez-kauce.svg', 'Bez kauce', 'férové a jasné podmínky půjčovny Motogo24') .
    renderWbox('gfx/ico-vybava.svg', 'Výbava v ceně', 'pro řidiče') .
    '</div></section>' .

    '<section><h2>Ceník přistavení a svozu</h2>' .
    '<p>Výchozí bod: <strong>Pelhřimov (Vysočina)</strong>. Obousměrnou dopravu účtujeme jako dvojnásobek.</p><p>&nbsp;</p>' .
    $pricingTable . '</section>' .

    '<section aria-labelledby="process"><h2>Jak přistavení probíhá</h2><div class="gr4">' .
    renderWbox('gfx/ico-step1.svg', 'Vyber motorku a termín', 'v online rezervaci') .
    renderWbox('gfx/ico-step3.svg', 'Zadej adresu', 'přistavení/vrácení (hotel, nádraží, adresa)') .
    renderWbox('gfx/ico-step5.svg', 'Potvrď cenu', 'za dopravu dle vzdálenosti') .
    renderWbox('gfx/ico-step6.svg', 'Převzetí na místě', 'předáme klíče, výbavu a dokumenty') .
    '</div></section>' .

    renderCta('Přistavení motorky – půjčovna motorek Vysočina',
        'Motogo24 nabízí <strong>přistavení motocyklu</strong> po regionu i mimo něj. <strong>Nonstop provoz, bez kauce, výbava v ceně</strong>.',
        [['label' => 'REZERVOVAT S PŘISTAVENÍM', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

renderPage('Přistavení motocyklu – Motogo24', $content, '/jak-pujcit/pristaveni');
