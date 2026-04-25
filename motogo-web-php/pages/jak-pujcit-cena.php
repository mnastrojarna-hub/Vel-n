<?php
// ===== MotoGo24 Web PHP — Co je v ceně nájmu (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/co-je-v-cene-najmu
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/cena-content-1.php';
$part2 = require __DIR__ . '/../data/cena-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_cena', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Co je v ceně nájmu']);

// --- Section 1: title + intro + 2-col (basic / extra + services) ---
$basicLis = '';
foreach ($C['gear']['basic']['items'] as $i) { $basicLis .= '<li>' . $i . '</li>'; }
$extraLis = '';
foreach ($C['gear']['extra']['items'] as $i) { $extraLis .= '<li>' . $i . '</li>'; }
$servicesLis = '';
foreach ($C['gear']['services']['items'] as $i) { $servicesLis .= '<li>' . $i . '</li>'; }

$leftCol = '<div>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['gear']['basic']['title'] . '</h2>' .
    '<p>' . $C['gear']['basic']['lead'] . '<br>&nbsp;</p>' .
    '<ul>' . $basicLis . '</ul>' .
    '<p>' . $C['gear']['basic']['note1'] . '</p>' .
    '<p>' . $C['gear']['basic']['note2'] . '</p>' .
    '</div>';

$rightCol = '<div>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['gear']['extra']['title'] . '</h2>' .
    '<p>' . $C['gear']['extra']['lead'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $extraLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<h2>' . $C['gear']['services']['title'] . '</h2>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $servicesLis . '</ul>' .
    '</div>';

$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">Hlavní obsah stránky</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<div class="gr2">' . $leftCol . $rightCol . '</div>' .
    '</section>';

// --- Section 2: benefits "Další výhody v ceně" — 5 boxes (gr5) ---
$grid = $C['benefits']['grid'] ?? 'gr5';
$benefitsHtml = '<section aria-labelledby="benefits"><h2 id="benefits" class="vh">Hlavní výhody a přínosy</h2>' .
    '<h2>' . $C['benefits']['title'] . '</h2><div class="' . htmlspecialchars($grid) . '">';
foreach ($C['benefits']['items'] as $b) {
    $benefitsHtml .= renderWbox($b['icon'], $b['title'], $b['text']);
}
$benefitsHtml .= '</div></section>';

// --- Section 3: prazdny placeholder main1 (jako v originale) ---
$main1Section = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">Důležité informace</h2></section>';

// --- Section 4: final CTA ---
$ctaButtons = '';
foreach ($C['cta']['buttons'] as $btn) {
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? $btn['label']) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">Kontaktujte nás</h2>' .
    '<h2>' . $C['cta']['title'] . '</h2>' .
    '<p>' . $C['cta']['text'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Co je v ceně nájmu" class="sections ccontent">' .
    $titleSection .
    $benefitsHtml .
    $main1Section .
    $finalCtaSection .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/co-v-cene', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Co je v ceně nájmu', 'url' => 'https://motogo24.cz/jak-pujcit/co-v-cene'],
    ],
]);
