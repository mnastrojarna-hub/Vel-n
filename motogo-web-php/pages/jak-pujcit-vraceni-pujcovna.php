<?php
// ===== MotoGo24 Web PHP — Vrácení motocyklu v půjčovně (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Vrácení motocyklu v půjčovně | MotoGo24',
        'description' => 'Vrácení motorky přímo v půjčovně Pelhřimov. Nonstop, bez kauce, bez zbytečné administrativy. Jak probíhá vrácení motorky krok za krokem.',
        'keywords' => 'vrácení motorky, vrácení motocyklu v půjčovně, půjčovna Pelhřimov, nonstop vrácení motorky',
    ],
    'h1' => 'Vrácení motocyklu v půjčovně',
    'intro' => 'Motorku vracíš pohodlně přímo v <strong>Motogo24 – půjčovně motorek na Vysočině</strong>. <strong>Nonstop provoz</strong>, žádný stres a férové podmínky.',
    'top_cta' => ['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace'],
    'place' => [
        'title' => 'Kde a kdy motorku vrátit',
        'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
        'hours' => '<em>nonstop</em> – kdykoli během posledního dne výpůjčky',
        'phone' => '+420 774 256 271',
        'note_title' => 'Co je potřeba splnit',
        'note_text' => 'Motorku vracej <strong>v dohodnutém čase</strong> a v podobném technickém stavu, v jakém jsi ji převzal/a. <strong>Plnou nádrž ani mytí nevyžadujeme.</strong>',
        'map_src' => 'https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169',
    ],
    'steps' => [
        'title' => 'Jak vrácení v půjčovně probíhá',
        'items' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Přijeď v dohodnutém čase', 'text' => 'na adresu půjčovny v Pelhřimově'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => 'Společně projdeme stav motorky', 'text' => 'kontrola karoserie, nádrže a výbavy'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Vrátíš výbavu', 'text' => 'helma, bunda, kalhoty, rukavice'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => 'Podepíšeme protokol o vrácení', 'text' => 'jasný a férový záznam'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => 'Hotovo', 'text' => 'pošleme ti potvrzení e-mailem'],
        ],
    ],
    'tips' => [
        'title' => 'Praktické tipy k vrácení',
        'items' => [
            '<strong>Plnou nádrž nevyžadujeme</strong> – pohonné hmoty se účtují jen v případě potřeby.',
            '<strong>Mytí motorky není nutné</strong> – běžné znečištění z jízdy je v pořádku.',
            '<strong>Pozdní vrácení</strong> hlas předem telefonicky, abychom domluvili řešení.',
            '<strong>Bezkontaktní vrácení</strong> je možné po předchozí domluvě.',
        ],
        'cta' => ['label' => 'ZAREZERVOVAT TERMÍN', 'href' => '/rezervace'],
    ],
    'faq' => [
        'title' => 'Časté dotazy k vrácení v půjčovně',
        'items' => [
            ['q' => 'Co když nestihnu domluvený čas vrácení?', 'a' => 'Dej nám prosím vědět telefonicky. Většinou se domluvíme na <strong>posunutí o pár hodin</strong>; delší prodlení může být zpoplatněno dle ceníku.'],
            ['q' => 'Musím motorku umýt?', 'a' => 'Ne. Běžné znečištění je v pořádku, mytí <strong>nevyžadujeme</strong>.'],
            ['q' => 'Musím motorku vrátit s plnou nádrží?', 'a' => 'Není to povinné. Pokud nádrž není plná, doplníme palivo a <strong>doúčtujeme jen reálnou cenu</strong> bez přirážek.'],
            ['q' => 'Co když je půjčovna zavřená?', 'a' => 'Provoz je <strong>nonstop</strong>. V noci stačí zavolat na +420 774 256 271 a domluvíme předání.'],
            ['q' => 'Můžu vrátit motorku na jiném místě?', 'a' => 'Ano, využij <a href="/jak-pujcit/vraceni-jinde"><strong>vrácení motorky jinde</strong></a> (přistavení/svoz dle ceníku).'],
        ],
    ],
    'cta' => [
        'title' => 'Vrácení motorky v půjčovně – Motogo24 Pelhřimov',
        'text' => 'Vrať motorku přímo u nás v Pelhřimově – <strong>nonstop, bez kauce, bez stresu</strong>.',
        'buttons' => [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_vraceni_pujcovna', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Vrácení motocyklu v půjčovně']);

$mapIframe = '<iframe class="map" loading="lazy" src="' . htmlspecialchars($C['place']['map_src']) . '" title="Adresa půjčovny"></iframe>';

$placeHtml = '<section><div class="gr2"><div>' .
    '<h2>' . $C['place']['title'] . '</h2>' .
    '<p><strong>Adresa:</strong> ' . $C['place']['address'] . '</p>' .
    '<p><strong>Kdy vracíme:</strong> ' . $C['place']['hours'] . '</p>' .
    '<p><strong>Telefon:</strong> <a href="tel:' . preg_replace('/\s+/', '', $C['place']['phone']) . '">' . htmlspecialchars($C['place']['phone']) . '</a></p>' .
    '<p>&nbsp;</p><h2>' . $C['place']['note_title'] . '</h2>' .
    '<p>' . $C['place']['note_text'] . '</p>' .
    '</div><div><p>' . $mapIframe . '</p></div></div></section>';

$stepsHtml = '<section><h2>' . $C['steps']['title'] . '</h2><div class="gr5">';
foreach ($C['steps']['items'] as $s) { $stepsHtml .= renderWbox($s['icon'], $s['title'], $s['text']); }
$stepsHtml .= '</div></section>';

$tipsLis = '';
foreach ($C['tips']['items'] as $t) { $tipsLis .= '<li>' . $t . '</li>'; }
$tipsHtml = '<section><h2>' . $C['tips']['title'] . '</h2><ul>' . $tipsLis . '</ul>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['tips']['cta']['href'] . '">' . $C['tips']['cta']['label'] . '</a></p></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>' . $C['h1'] . '</h1><p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p></section>' .
    $placeHtml . $stepsHtml . $tipsHtml .
    renderFaqSection($C['faq']['title'], $C['faq']['items']) .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/vraceni-pujcovna', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Vrácení v půjčovně', 'url' => 'https://motogo24.cz/jak-pujcit/vraceni-pujcovna'],
    ],
]);
