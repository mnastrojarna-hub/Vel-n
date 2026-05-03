<?php
// ===== MotoGo24 Web PHP — Převzetí v půjčovně (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/prevzeti-v-pujcovne
// Pozn.: URL /jak-pujcit/vyzvednuti i /jak-pujcit/prevzeti vede sem (SEO).
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/prevzeti-content-1.php';
$part2 = require __DIR__ . '/../data/prevzeti-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_vyzvednuti', $defaults);

// /jak-pujcit/prevzeti je primární URL, /jak-pujcit/vyzvednuti zachováno kvůli SEO
$pagePath = parse_url($_SERVER['REQUEST_URI'] ?? '/jak-pujcit/prevzeti', PHP_URL_PATH);
if ($pagePath !== '/jak-pujcit/vyzvednuti') $pagePath = '/jak-pujcit/prevzeti';

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.pickup')]);

// --- Section 1: title + intro + top CTA ---
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">' . te('a11y.mainContent') . '</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($C['top_cta']['aria']) . '" class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</section>';

// --- Section 2 (main1): 2-col adresa + Google Maps embed ---
$mapIframe = '<iframe class="map" loading="lazy" src="' . htmlspecialchars($C['place']['map_src']) . '" title="' . htmlspecialchars($C['place']['map_title']) . '"></iframe>';
$placeSection = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">' . te('a11y.importantInfo') . '</h2>' .
    '<div class="gr2"><div>' .
    '<h2>' . $C['place']['title'] . '</h2>' .
    '<p><strong>' . $C['place']['address_label'] . '&nbsp;</strong>' . $C['place']['address'] . '</p>' .
    '<p><strong>' . $C['place']['hours_label'] . '</strong> ' . $C['place']['hours'] . '</p>' .
    '<p>&nbsp;</p>' .
    '</div><div>' .
    '<p>' . $mapIframe . '</p>' .
    '</div></div>' .
    '</section>';

// --- Section 3: process 8 boxes (gr4) ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">' . te('a11y.processHowItWorks') . '</h2>' .
    '<h2>' . $C['process']['title'] . '</h2>' .
    '<div class="' . htmlspecialchars($grid) . '">';
foreach ($C['process']['steps'] as $s) {
    $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$processHtml .= '</div></section>';

// --- Section 4 (main2): 2-col Co najdes (s tlacitkem) + Co s sebou ---
$amenitiesLis = '';
foreach ($C['amenities']['items'] as $i) { $amenitiesLis .= '<li>' . $i . '</li>'; }
$amenityCol = '<div>' .
    '<h2>' . $C['amenities']['title'] . '</h2>' .
    '<p>' . $C['amenities']['lead'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $amenitiesLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($C['amenities']['cta']['aria']) . '" class="btn btngreen" href="' . BASE_URL . $C['amenities']['cta']['href'] . '">' . $C['amenities']['cta']['label'] . '</a></p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$bringLis = '';
foreach ($C['bring']['items'] as $i) { $bringLis .= '<li>' . $i . '</li>'; }
$bringCol = '<div>' .
    '<h2>' . $C['bring']['title'] . '</h2>' .
    '<ul>' . $bringLis . '</ul>' .
    '<p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$main2Section = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">' . te('a11y.moreImportantInfo') . '</h2>' .
    '<div class="gr2">' . $amenityCol . $bringCol . '</div>' .
    '</section>';

// --- Section 5: FAQ ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">' . te('a11y.frequentQuestions') . '</h2>' .
    '<h2>' . $C['faq']['title'] . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ($C['faq']['items'] as $f) {
    $faqHtml .= renderFaqItem($f['q'], $f['a']);
}
$faqHtml .= '</div></div></div></section>';

// --- Section 6 (main3): mid CTA "REZERVOVAT VYZVEDNUTÍ" ---
$mid = $C['mid_cta'];
$mid3Section = '<section aria-labelledby="main3" class="main3"><h2 id="main3" class="vh">' . te('a11y.moreInfo') . '</h2>' .
    '<p><a aria-label="' . htmlspecialchars($mid['aria']) . '" class="btn btngreen" href="' . BASE_URL . $mid['href'] . '">' . $mid['label'] . '</a></p>' .
    '</section>';

// --- Section 7: final CTA ---
$ctaButtons = '';
foreach ($C['cta']['buttons'] as $btn) {
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? $btn['label']) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">' . te('a11y.contactUs') . '</h2>' .
    '<h2>' . $C['cta']['title'] . '</h2>' .
    '<p>' . $C['cta']['text'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<p>' . $C['cta']['text2'] . '</p>' .
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

// FAQPage schema
$faqSchemaItems = [];
foreach ($C['faq']['items'] as $faq) {
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';

renderPage($C['seo']['title'], $content, $pagePath, [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'canonical' => 'https://motogo24.cz/jak-pujcit/prevzeti',
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.pickup'), 'url' => siteCanonicalUrl('/jak-pujcit/prevzeti')],
    ],
]);
