<?php
// ===== MotoGo24 Web PHP — Převzetí v půjčovně (CMS-driven) =====
// Pozn.: URL /jak-pujcit/vyzvednuti i /jak-pujcit/prevzeti vede sem (SEO).

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Převzetí motocyklu v půjčovně | MotoGo24',
        'description' => 'Převzetí motorky v půjčovně Pelhřimov. Nonstop provoz, bez kauce, výbava v ceně. Co si vzít s sebou a jak probíhá předání.',
        'keywords' => 'převzetí motorky v půjčovně, vyzvednutí motocyklu, půjčovna Pelhřimov, nonstop převzetí',
    ],
    'h1' => 'Převzetí motocyklu v půjčovně – rychle, jednoduše a nonstop',
    'intro' => 'V <strong>Motogo24 – půjčovna motorek Vysočina</strong> je <strong>převzetí motorky</strong> otázkou pár minut. Půjčujeme <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.',
    'top_cta' => ['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace'],
    'place' => [
        'title' => 'Kde probíhá převzetí',
        'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
        'hours' => '<em>nonstop</em>',
        'phone' => '+420 774 256 271',
        'return_title' => 'Vrácení motorky – bez stresu',
        'return_text' => 'Motorku můžeš vrátit <strong>kdykoli během posledního dne výpůjčky</strong>. Více informací viz <a href="/jak-pujcit/vraceni-pujcovna">vrácení v půjčovně</a> nebo <a href="/jak-pujcit/vraceni-jinde">vrácení jinde</a>.',
        'map_src' => 'https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169',
    ],
    'steps' => [
        'title' => 'Jak probíhá převzetí krok za krokem',
        'items' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Přijď v domluvený čas', 'text' => 'na naši adresu nebo vyčkej na přistavení'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => 'Ověříme doklady', 'text' => 'OP/pas + řidičský průkaz odpovídající skupiny'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Předáme motorku a výbavu', 'text' => 'helma, bunda, kalhoty, rukavice'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => 'Krátké seznámení se strojem', 'text' => 'ovládání, tipy, doporučení k trase'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => 'Podepíšeme předávací protokol', 'text' => 'a můžeš vyrazit'],
        ],
    ],
    'bring' => [
        'title' => 'Co si vzít s sebou',
        'items' => [
            '<strong>Občanský průkaz / pas</strong>',
            '<strong>Řidičský průkaz</strong> odpovídající skupiny (A/A2 podle motorky)',
            '<strong>Vhodnou obuv</strong> (moto boty lze půjčit jako nadstandard)',
        ],
        'cta' => ['label' => 'ZAREZERVOVAT TERMÍN', 'href' => '/rezervace'],
    ],
    'faq' => [
        'title' => 'Časté dotazy k převzetí',
        'items' => [
            ['q' => 'Musím platit kauci při převzetí?', 'a' => 'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.'],
            ['q' => 'Je možný kontakt bez osobního setkání?', 'a' => 'Ano, nabízíme <strong>bezkontaktní předání</strong> po domluvě.'],
            ['q' => 'Co když nestíhám domluvený čas?', 'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong>.'],
            ['q' => 'Je v ceně i výbava pro spolujezdce?', 'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.'],
        ],
    ],
    'cta' => [
        'title' => 'Převzetí motorky v půjčovně – Motogo24 Vysočina',
        'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop převzetím i vrácením</strong>, <strong>bez kauce</strong> a s <strong>výbavou v ceně</strong>.',
        'buttons' => [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_vyzvednuti', $defaults);

// /jak-pujcit/prevzeti je primární URL, /jak-pujcit/vyzvednuti zachováno kvůli SEO
$pagePath = parse_url($_SERVER['REQUEST_URI'] ?? '/jak-pujcit/prevzeti', PHP_URL_PATH);
if ($pagePath !== '/jak-pujcit/vyzvednuti') $pagePath = '/jak-pujcit/prevzeti';

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.pickup')]);

$mapIframe = '<iframe class="map" loading="lazy" src="' . htmlspecialchars($C['place']['map_src']) . '" title="Jak se k nám dostanete"></iframe>';

$placeHtml = '<section><div class="gr2"><div>' .
    '<h2>' . $C['place']['title'] . '</h2>' .
    '<p><strong>Provozovna:</strong> ' . $C['place']['address'] . '</p>' .
    '<p><strong>Provozní doba:</strong> ' . $C['place']['hours'] . '</p>' .
    '<p><strong>Telefon:</strong> <a href="tel:' . preg_replace('/\s+/', '', $C['place']['phone']) . '">' . htmlspecialchars($C['place']['phone']) . '</a></p>' .
    '<p>&nbsp;</p><h2>' . $C['place']['return_title'] . '</h2>' .
    '<p>' . $C['place']['return_text'] . '</p>' .
    '</div><div><p>' . $mapIframe . '</p></div></div></section>';

$stepsHtml = '<section><h2>' . $C['steps']['title'] . '</h2><div class="gr5">';
foreach ($C['steps']['items'] as $s) { $stepsHtml .= renderWbox($s['icon'], $s['title'], $s['text']); }
$stepsHtml .= '</div></section>';

$bringLis = '';
foreach ($C['bring']['items'] as $b) { $bringLis .= '<li>' . $b . '</li>'; }
$bringHtml = '<section><h2>' . $C['bring']['title'] . '</h2><ul>' . $bringLis . '</ul>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['bring']['cta']['href'] . '">' . $C['bring']['cta']['label'] . '</a></p></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>' . $C['h1'] . '</h1><p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p></section>' .
    $placeHtml . $stepsHtml . $bringHtml .
    renderFaqSection($C['faq']['title'], $C['faq']['items']) .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, $pagePath, [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'canonical' => 'https://motogo24.cz/jak-pujcit/prevzeti',
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.howto'), 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => t('menu.howto.pickup'), 'url' => 'https://motogo24.cz/jak-pujcit/prevzeti'],
    ],
]);
