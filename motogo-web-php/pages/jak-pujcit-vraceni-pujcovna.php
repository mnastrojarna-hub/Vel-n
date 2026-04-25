<?php
// ===== MotoGo24 Web PHP — Vrácení motocyklu v půjčovně (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/vraceni-motocyklu-v-pujcovne
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/vraceni-pujcovna-content-1.php';
$part2 = require __DIR__ . '/../data/vraceni-pujcovna-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_vraceni_pujcovna', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.returnHome')]);

// --- Section 1: title + intro ---
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">Hlavní obsah stránky</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '</section>';

// --- Section 2 (placeholder): main1 ---
$main1Section = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">Důležité informace</h2></section>';

// --- Section 3: process 4 boxes (gr4) — pouze titulky bez popisu (jako v originale) ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">Jak to u nás funguje</h2>' .
    '<div class="' . htmlspecialchars($grid) . '">';
foreach ($C['process']['steps'] as $s) {
    // Pokud step nema text, vykreslime jen wbox-img + h3 (bez <p>)
    $iconSrc = $s['icon'] ? BASE_URL . '/' . ltrim($s['icon'], '/') : '';
    $titleText = trim(strip_tags($s['title']));
    $processHtml .= '<div class="wbox">' .
        ($s['icon'] ? '<div class="wbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . htmlspecialchars($titleText) . '" loading="lazy"></div>' : '') .
        '<h3>' . $s['title'] . '</h3>' .
        ($s['text'] !== '' ? '<p>' . $s['text'] . '</p>' : '') .
        '</div>';
}
$processHtml .= '</div></section>';

// --- Section 4 (main2): Cas vraceni + Nesrovnalosti ---
$issuesLis = '';
foreach ($C['issues']['items'] as $i) { $issuesLis .= '<li>' . $i . '</li>'; }
$main2Section = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">Další důležité informace</h2>' .
    '<h2>' . $C['time']['title'] . '</h2>' .
    '<p>' . $C['time']['text'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<h2>' . $C['issues']['title'] . '</h2>' .
    '<p>' . $C['issues']['lead'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $issuesLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p>' . $C['issues']['closing'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<div class="gr2"><div></div><div></div></div>' .
    '</section>';

// --- Section 5: FAQ ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">Na co se nás často ptáte</h2>' .
    '<h2>' . $C['faq']['title'] . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ($C['faq']['items'] as $f) {
    $faqHtml .= renderFaqItem($f['q'], $f['a']);
}
$faqHtml .= '</div></div></div></section>';

// --- Section 6: final CTA → KONTAKT ---
$ctaButtons = '';
foreach ($C['cta']['buttons'] as $btn) {
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? $btn['label']) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">Kontaktujte nás</h2>' .
    '<h2>' . $C['cta']['title'] . '</h2>' .
    '<p>' . $C['cta']['text'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '<p>&nbsp;</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Vrácení motocyklu v půjčovně" class="sections ccontent">' .
    $titleSection .
    $main1Section .
    $processHtml .
    $main2Section .
    $faqHtml .
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

renderPage($C['seo']['title'], $content, '/jak-pujcit/vraceni-pujcovna', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.howto'), 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => t('menu.howto.returnHome'), 'url' => 'https://motogo24.cz/jak-pujcit/vraceni-pujcovna'],
    ],
]);
