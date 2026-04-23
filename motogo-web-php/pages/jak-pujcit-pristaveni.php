<?php
// ===== MotoGo24 Web PHP — Přistavení motocyklu (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Přistavení motorky | MotoGo24',
        'description' => 'Přistavení motorky až k vám. Dovezeme motorku na hotel, nádraží nebo jinou adresu. Ceník přistavení od 290 Kč. Nonstop provoz.',
        'keywords' => 'přistavení motorky, dovoz motorky, doručení motorky, půjčovna motorek Vysočina',
    ],
    'h1' => 'Přistavení motocyklu – doručení až k tobě',
    'intro' => 'Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky</strong> na <strong>domluvené místo</strong>.',
    'top_cta' => ['label' => 'REZERVOVAT S PŘISTAVENÍM', 'href' => '/rezervace?delivery=1'],
    'why' => [
        'title' => 'Proč využít přistavení motorky',
        'items' => [
            ['icon' => 'gfx/ico-pohodli.svg', 'title' => 'Pohodlí a čas', 'text' => 'motorku přivezeme, kam potřebuješ'],
            ['icon' => 'gfx/ico-flexibilita.svg', 'title' => 'Flexibilita', 'text' => 'vyzvednutí i vrácení lze řešit mimo provozovnu.'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'přistavení/vrácení v den výpůjčky i večer'],
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'férové a jasné podmínky půjčovny Motogo24'],
            ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Výbava v ceně', 'text' => 'pro řidiče'],
        ],
    ],
    'pricing' => [
        'title' => 'Ceník přistavení a svozu',
        'note' => 'Výchozí bod: <strong>Pelhřimov (Vysočina)</strong>. Obousměrnou dopravu účtujeme jako dvojnásobek.',
        'headers' => ['Vzdálenost od Pelhřimova', 'Cena za 1 směr', 'Příklady lokalit'],
        'rows' => [
            ['Do 10 km', '290 Kč', 'Centrum Pelhřimov, blízké obce'],
            ['Do 30 km', '590 Kč', 'Humpolec, Kamenice nad Lipou, Pacov'],
            ['Do 60 km', '990 Kč', 'Jihlava, Třebíč, Tábor'],
            ['Do 100 km', '1 490 Kč', 'České Budějovice, Kolín, Havlíčkův Brod'],
            ['100+ km', 'Individuálně', 'Praha, Brno, další místa po dohodě'],
        ],
    ],
    'process' => [
        'title' => 'Jak přistavení probíhá',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Vyber motorku a termín', 'text' => 'v online rezervaci'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Zadej adresu', 'text' => 'přistavení/vrácení (hotel, nádraží, adresa)'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => 'Potvrď cenu', 'text' => 'za dopravu dle vzdálenosti'],
            ['icon' => 'gfx/ico-step6.svg', 'title' => 'Převzetí na místě', 'text' => 'předáme klíče, výbavu a dokumenty'],
        ],
    ],
    'cta' => [
        'title' => 'Přistavení motorky – půjčovna motorek Vysočina',
        'text' => 'Motogo24 nabízí <strong>přistavení motocyklu</strong> po regionu i mimo něj. <strong>Nonstop provoz, bez kauce, výbava v ceně</strong>.',
        'buttons' => [['label' => 'REZERVOVAT S PŘISTAVENÍM', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_pristaveni', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Přistavení motocyklu']);

$whyHtml = '<section><h2>' . $C['why']['title'] . '</h2><div class="gr5">';
foreach ($C['why']['items'] as $w) { $whyHtml .= renderWbox($w['icon'], $w['title'], $w['text']); }
$whyHtml .= '</div></section>';

$pricingTable = renderTable($C['pricing']['headers'], $C['pricing']['rows']);
$pricingHtml = '<section><h2>' . $C['pricing']['title'] . '</h2><p>' . $C['pricing']['note'] . '</p><p>&nbsp;</p>' . $pricingTable . '</section>';

$processHtml = '<section aria-labelledby="process"><h2>' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $s) { $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']); }
$processHtml .= '</div></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . $C['h1'] . '</h1><p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p>' .
    $whyHtml . $pricingHtml . $processHtml .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/pristaveni', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Přistavení', 'url' => 'https://motogo24.cz/jak-pujcit/pristaveni'],
    ],
]);
