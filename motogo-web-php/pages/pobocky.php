<?php
// ===== MotoGo24 Web PHP — Pobočky: přehled (CMS-driven) =====
// Karty Mezná (obslužná) + Velké Němčice (samoobslužná), každá vede na vlastní
// stránku /pobocky/<slug> (pages/pobocka-detail.php). Defaulty + helpery:
// data/pobocky.php. Texty: Velín → Texty webu → Pobočky (`web.pobocky.*`).

require_once __DIR__ . '/../data/pobocky.php';
$sb = new SupabaseClient();
$defaults = pobockyDefaults();
$C = $sb->siteContent('pobocky', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('menu.branches')]);

$cards = '';
foreach (array_keys($defaults['branches']) as $i) {
    $b = pobockyBranch($C, $defaults, $i);
    $k = 'web.pobocky.branches.' . $i;
    $href = BASE_URL . '/pobocky/' . $b['slug'];
    $photo = trim((string)$b['photo']);
    $cards .= '<section class="branch-card">'
        . ($photo !== '' ? '<a href="' . $href . '"><img class="branch-photo" src="' . htmlspecialchars(BASE_URL . '/' . ltrim($photo, '/')) . '" alt="' . htmlspecialchars(strip_tags((string)$b['title'])) . '" loading="lazy"></a>' : '')
        . '<span class="branch-badge" data-cms-key="' . $k . '.badge">' . sanitizeHtml((string)$b['badge']) . '</span>'
        . '<h2><a href="' . $href . '" data-cms-key="' . $k . '.title">' . sanitizeHtml((string)$b['title']) . '</a></h2>'
        . '<p>📍 <span data-cms-key="' . $k . '.address">' . sanitizeHtml((string)$b['address']) . '</span></p>'
        . '<p>🕑 <span data-cms-key="' . $k . '.hours">' . sanitizeHtml((string)$b['hours']) . '</span></p><p>&nbsp;</p>'
        . '<p><a class="btn btngreen-small" href="' . $href . '" data-cms-key="web.pobocky.detail_button">' . sanitizeHtml((string)($C['detail_button'] ?? $defaults['detail_button'])) . '</a></p>'
        . '</section>';
}

$cta = is_array($C['cta'] ?? null) ? array_merge($defaults['cta'], $C['cta']) : $defaults['cta'];
$ctaHtml = '<section class="cta-green-box"><h2 data-cms-key="web.pobocky.cta.title">' . sanitizeHtml((string)$cta['title']) . '</h2>'
    . '<p data-cms-key="web.pobocky.cta.text">' . sanitizeHtml((string)$cta['text']) . '</p><p>&nbsp;</p>'
    . '<p><a class="btn btndark" href="' . BASE_URL . '/rezervace" data-cms-key="web.pobocky.cta.button">' . sanitizeHtml((string)$cta['button']) . '</a></p></section>';

$content = pobockyCss() . '<main id="content"><div class="container">' . $bc
    . '<div class="ccontent">'
    . '<h1 data-cms-key="web.pobocky.h1">' . sanitizeHtml((string)$C['h1']) . '</h1>'
    . '<p data-cms-key="web.pobocky.intro">' . sanitizeHtml((string)$C['intro']) . '</p>'
    . '<div class="branches-list">' . $cards . '</div>'
    . $ctaHtml
    . '</div></div></main>';

renderPage(strip_tags((string)$C['seo']['title']), $content, '/pobocky', [
    'description' => strip_tags((string)$C['seo']['description']),
    'keywords' => strip_tags((string)$C['seo']['keywords']),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('menu.branches'), 'url' => siteCanonicalUrl('/pobocky')],
    ],
]);
