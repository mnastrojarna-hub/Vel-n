<?php
// ===== MotoGo24 Web PHP — Převzetí v půjčovně (CMS-driven, 1:1 prepis) =====
$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/prevzeti-content-1.php';
$part2 = require __DIR__ . '/../data/prevzeti-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_vyzvednuti', $defaults);

$pagePath = parse_url($_SERVER['REQUEST_URI'] ?? '/jak-pujcit/prevzeti', PHP_URL_PATH);
if ($pagePath !== '/jak-pujcit/vyzvednuti') $pagePath = '/jak-pujcit/prevzeti';

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.pickup')]);
$kp = 'web.jak_pujcit_vyzvednuti';

// --- Section 1: title + intro + top CTA ---
$tcta = is_array($C['top_cta'] ?? null) ? $C['top_cta'] : ($defaults['top_cta'] ?? []);
$titleSection = '<section>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($tcta['aria'] ?? '') . '" class="btn btngreen" href="' . BASE_URL . ($tcta['href'] ?? '#') . '" data-cms-key="' . $kp . '.top_cta.button.label">' . ($tcta['label'] ?? '') . '</a></p>' .
    '<p>&nbsp;</p>' .
    '</section>';

// --- Section 2 (main1): 2-col adresa + Google Maps embed ---
$pl = is_array($C['place'] ?? null) ? $C['place'] : ($defaults['place'] ?? []);
$mapIframe = '<iframe class="map" loading="lazy" src="' . htmlspecialchars($pl['map_src'] ?? '') . '" title="' . htmlspecialchars($pl['map_title'] ?? '') . '"></iframe>';
$placeSection = '<section class="main1">' .
    '<div class="gr2"><div>' .
    '<h2 data-cms-key="' . $kp . '.place.title">' . ($pl['title'] ?? '') . '</h2>' .
    '<p><strong>' . ($pl['address_label'] ?? '') . '&nbsp;</strong><span data-cms-key="' . $kp . '.place.address">' . ($pl['address'] ?? '') . '</span></p>' .
    '<p><strong data-cms-key="' . $kp . '.place.hours_label">' . ($pl['hours_label'] ?? '') . '</strong> <span data-cms-key="' . $kp . '.place.hours">' . ($pl['hours'] ?? '') . '</span></p>' .
    '<p>&nbsp;</p>' .
    '</div><div>' .
    '<p>' . $mapIframe . '</p>' .
    '</div></div>' .
    '</section>';

// --- Section 3: process 8 boxes (gr4) ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section>' .
    '<h2 data-cms-key="' . $kp . '.process.title">' . ($C['process']['title'] ?? '') . '</h2>' .
    '<div class="' . htmlspecialchars($grid) . '">';
foreach ((is_array($C['process']['steps'] ?? null) ? $C['process']['steps'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $kBase = $kp . '.process.steps.' . $i;
    $processHtml .= renderWbox(
        $s['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($s['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($s['text'] ?? '') . '</span>'
    );
}
$processHtml .= '</div></section>';

// --- Section 4 (main2): 2-col Co najdes (s tlacitkem) + Co s sebou ---
$amenitiesLis = '';
foreach ((is_array($C['amenities']['items'] ?? null) ? $C['amenities']['items'] : []) as $i => $item) {
    $amenitiesLis .= '<li data-cms-key="' . $kp . '.amenities.items.' . $i . '">' . $item . '</li>';
}
$amCta = is_array($C['amenities']['cta'] ?? null) ? $C['amenities']['cta'] : [];
$amenityCol = '<div>' .
    '<h2 data-cms-key="' . $kp . '.amenities.title">' . ($C['amenities']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.amenities.lead">' . ($C['amenities']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $amenitiesLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($amCta['aria'] ?? '') . '" class="btn btngreen" href="' . BASE_URL . ($amCta['href'] ?? '#') . '" data-cms-key="' . $kp . '.amenities.cta.label">' . ($amCta['label'] ?? '') . '</a></p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$bringLis = '';
foreach ((is_array($C['bring']['items'] ?? null) ? $C['bring']['items'] : []) as $i => $item) {
    $bringLis .= '<li data-cms-key="' . $kp . '.bring.items.' . $i . '">' . $item . '</li>';
}
$bringCol = '<div>' .
    '<h2 data-cms-key="' . $kp . '.bring.title">' . ($C['bring']['title'] ?? '') . '</h2>' .
    '<ul>' . $bringLis . '</ul>' .
    '<p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$main2Section = '<section class="main2">' .
    '<div class="gr2">' . $amenityCol . $bringCol . '</div>' .
    '</section>';

// FAQ sekce odstraněna (2026-05-17) — centrální FAQ je pouze na /jak-pujcit/faq.
// Klíče `web.jak_pujcit_vyzvednuti.faq.*` v cms_variables zůstávají, ale nikde se nečtou.
$faqHtml = '';

// --- Section 6 (main3): mid CTA ---
$mid = is_array($C['mid_cta'] ?? null) ? $C['mid_cta'] : [];
$mid3Section = '<section class="main3">' .
    '<p><a aria-label="' . htmlspecialchars($mid['aria'] ?? '') . '" class="btn btngreen" href="' . BASE_URL . ($mid['href'] ?? '#') . '" data-cms-key="' . $kp . '.mid_cta.label">' . ($mid['label'] ?? '') . '</a></p>' .
    '</section>';

// --- Section 7: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section>' .
    '<h2 data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<p data-cms-key="' . $kp . '.cta.text2">' . ($C['cta']['text2'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Převzetí v půjčovně" class="sections ccontent">' .
    $titleSection .
    $placeSection .
    $processHtml .
    $main2Section .
    $faqHtml .
    $mid3Section .
    $finalCtaSection .
    '</div></div></main>';

// FAQPage schema odstraněno (2026-05-17) — viditelná FAQ sekce zmizela.
$faqSchema = '';

renderPage($C['seo']['title'], $content, $pagePath, [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'canonical' => 'https://www.motogo24.cz/jak-pujcit/prevzeti',
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.pickup'), 'url' => siteCanonicalUrl('/jak-pujcit/prevzeti')],
    ],
]);
