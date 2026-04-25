<?php
// ===== MotoGo24 Web PHP — Stránka Půjčovna motorek (CMS-driven) =====
// Obsah lze editovat v app_settings klíč 'site.pujcovna'

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'O půjčovně motorek | MotoGo24',
        'description' => 'Půjčovna motorek Motogo24 na Vysočině. Bez kauce, s online rezervací a výbavou v ceně. Cestovní, sportovní, enduro i dětské motorky. Nonstop provoz.',
        'keywords' => 'půjčovna motorek, pronájem motorek Vysočina, motorky bez kauce, nonstop půjčovna, výbava v ceně',
    ],
    'breadcrumb' => [
        ['label' => 'Domů', 'href' => '/'],
        'Půjčovna motorek',
    ],
    'intro' => [
        'h1' => 'Půjčovna motorek Vysočina Motogo24',
        'body' => 'Naše <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.',
    ],
    'benefits' => [
        'title' => 'Proč si půjčit motorku u nás',
        'closing' => 'Hledáte <strong>půjčovnu motorek na Vysočině</strong>? Motogo24 – <strong>půjčovna motorek na Vysočině</strong> – nabízí férové podmínky, jasný postup a špičkově udržované stroje pro výlety po ČR i do zahraničí.',
        'buttons' => [
            ['label' => 'Zobrazit motorky k pronájmu', 'href' => '/katalog', 'cls' => 'btngreen'],
            ['label' => 'REZERVOVAT', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
        ],
        'items' => [
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'a bez skrytých poplatků'],
            ['icon' => 'gfx/ico-online-rez.svg', 'title' => 'Online rezervace', 'text' => 'na pár kliknutí'],
            ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Výbava pro řidiče v ceně', 'text' => 'helma, bunda, kalhoty a rukavice'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'pro vyzvednutí i vrácení dle rezervace'],
            ['icon' => 'gfx/ico-spolecne.svg', 'title' => 'Jsme v tom společně', 'text' => 'když se něco přihodí'],
            ['icon' => 'gfx/ico-pristaveni.svg', 'title' => 'Přistavení i vrácení motorky', 'text' => 'na domluvené místo'],
        ],
    ],
    'process' => [
        'title' => 'Jak probíhá půjčení motorky na Vysočině',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Vyber motorku', 'text' => 'Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje, odpovídá tvým zkušenostem a řidičskému oprávnění.'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => '2. Rezervuj online', 'text' => 'Uskutečni rezervaci podle data nebo podle konkrétní motorky, kterou si chceš půjčit.'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => '3. Vyber výbavu', 'text' => 'Výbava pro řidiče je v ceně, pro spolujezdce za příplatek. Velikost si můžeš zvolit až na místě.'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => '4. Zaplať', 'text' => 'Zaplať jednoduše online prostřednictvím platební brány.'],
            ['icon' => 'gfx/ico-step6.svg', 'title' => '5. Převezmi motorku', 'text' => 'Motorku si vyzvedni přímo v půjčovně, nebo na místě, které jsi zvolil při rezervaci.'],
            ['icon' => 'gfx/ico-step7.svg', 'title' => '6. Užij si jízdu', 'text' => 'Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.'],
            ['icon' => 'gfx/ico-step8.svg', 'title' => '7. Vrať motorku', 'text' => 'Motorku jednoduše vrať ve sjednaný den – přímo v půjčovně, nebo na předem domluveném místě.'],
            ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Sleva na příští jízdu', 'text' => 'Po vrácení motorky ti automaticky zašleme slevový kód 200 Kč na další rezervaci.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        'items' => [
            ['q' => 'Jak si mohu rezervovat motorku?', 'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'],
            ['q' => 'Můžu si motorku půjčit i bez předchozí rezervace?', 'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit.'],
            ['q' => 'Musím složit kauci?', 'a' => 'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'],
            ['q' => 'Můžu odcestovat s motorkou do zahraničí?', 'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj svou motorku online',
        'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
        'buttons' => [
            ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
            ['label' => 'Dárkový poukaz', 'href' => '/poukazy', 'cls' => 'btndark'],
            ['label' => 'Tipy na trasy', 'href' => '/blog', 'cls' => 'btndark'],
        ],
    ],
];

$C = $sb->siteContent('pujcovna', $defaults);

$bc = renderBreadcrumb($C['breadcrumb']);

$intro = '<section><h1>' . $C['intro']['h1'] . '</h1><p>' . $C['intro']['body'] . '</p></section>';

$benefitsHtml = '<section><h2>' . $C['benefits']['title'] . '</h2><div class="gr6">';
foreach ($C['benefits']['items'] as $b) {
    $benefitsHtml .= renderWbox($b['icon'], $b['title'], $b['text']);
}
$benefitsHtml .= '</div><p>&nbsp;</p><p>' . $C['benefits']['closing'] . '</p><p>&nbsp;</p><p>';
foreach ($C['benefits']['buttons'] as $btn) {
    $benefitsHtml .= '<a class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a> ';
}
$benefitsHtml .= '</p></section>';

$stepsHtml = '<section aria-labelledby="process"><h2>' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $s) {
    $stepsHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$stepsHtml .= '</div></section>';

$faqHtml = renderFaqSection($C['faq']['title'], $C['faq']['items'], $C['faq']['more_link'] ?? null);
$ctaHtml = renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $benefitsHtml . $stepsHtml . $faqHtml . $ctaHtml . '</div></div></main>';

renderPage($C['seo']['title'], $content, '/pujcovna-motorek', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('menu.rental'), 'url' => 'https://motogo24.cz/pujcovna-motorek'],
    ],
]);
