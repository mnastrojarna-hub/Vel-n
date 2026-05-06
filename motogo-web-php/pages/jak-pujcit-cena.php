<?php
// ===== MotoGo24 Web PHP — Co je v ceně nájmu (CMS-driven, 1:1 prepis) =====
$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/cena-content-1.php';
$part2 = require __DIR__ . '/../data/cena-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_cena', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.price')]);
$kp = 'web.jak_pujcit_cena';

// --- Section 1: title + intro + 2-col (basic / extra + services) ---
$basicLis = '';
foreach ((is_array($C['gear']['basic']['items'] ?? null) ? $C['gear']['basic']['items'] : []) as $i => $item) {
    $basicLis .= '<li data-cms-key="' . $kp . '.gear.basic.items.' . $i . '">' . $item . '</li>';
}
$extraLis = '';
foreach ((is_array($C['gear']['extra']['items'] ?? null) ? $C['gear']['extra']['items'] : []) as $i => $item) {
    $extraLis .= '<li data-cms-key="' . $kp . '.gear.extra.items.' . $i . '">' . $item . '</li>';
}
$servicesLis = '';
foreach ((is_array($C['gear']['services']['items'] ?? null) ? $C['gear']['services']['items'] : []) as $i => $item) {
    $servicesLis .= '<li data-cms-key="' . $kp . '.gear.services.items.' . $i . '">' . $item . '</li>';
}

$leftCol = '<div>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.gear.basic.title">' . ($C['gear']['basic']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.gear.basic.lead">' . ($C['gear']['basic']['lead'] ?? '') . '<br>&nbsp;</p>' .
    '<ul>' . $basicLis . '</ul>' .
    '<p data-cms-key="' . $kp . '.gear.basic.note1">' . ($C['gear']['basic']['note1'] ?? '') . '</p>' .
    '<p data-cms-key="' . $kp . '.gear.basic.note2">' . ($C['gear']['basic']['note2'] ?? '') . '</p>' .
    '</div>';

$rightCol = '<div>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.gear.extra.title">' . ($C['gear']['extra']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.gear.extra.lead">' . ($C['gear']['extra']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $extraLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.gear.services.title">' . ($C['gear']['services']['title'] ?? '') . '</h2>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $servicesLis . '</ul>' .
    '</div>';

$titleSection = '<section>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<div class="gr2">' . $leftCol . $rightCol . '</div>' .
    '</section>';

// --- Section 2: benefits "Další výhody v ceně" — 5 boxes (gr5) ---
$grid = $C['benefits']['grid'] ?? 'gr5';
$benefitsHtml = '<section>' .
    '<h2 data-cms-key="' . $kp . '.benefits.title">' . ($C['benefits']['title'] ?? '') . '</h2><div class="' . htmlspecialchars($grid) . '">';
foreach ((is_array($C['benefits']['items'] ?? null) ? $C['benefits']['items'] : []) as $i => $b) {
    if (!is_array($b)) continue;
    $kBase = $kp . '.benefits.items.' . $i;
    $benefitsHtml .= renderWbox(
        $b['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($b['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($b['text'] ?? '') . '</span>'
    );
}
$benefitsHtml .= '</div></section>';

// --- Section 4: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section>' .
    '<h2 data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Co je v ceně nájmu" class="sections ccontent">' .
    $titleSection .
    $benefitsHtml .
    $finalCtaSection .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/co-v-cene', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.price'), 'url' => siteCanonicalUrl('/jak-pujcit/co-v-cene')],
    ],
]);
