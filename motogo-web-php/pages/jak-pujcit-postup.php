<?php
// ===== MotoGo24 Web PHP — Postup půjčení motorky (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/postup-content-1.php';
$part2 = require __DIR__ . '/../data/postup-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_postup', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Postup půjčení motorky']);

// --- Section 1: title (h1 + intro p1 + h2 + intro p2) ---
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">Hlavní obsah stránky</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro_p1'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['intro_h2'] . '</h2>' .
    '<p>' . $C['intro_p2'] . '</p>' .
    '</section>';

// --- Section 2 (placeholder): main1 ---
$main1Section = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">Důležité informace</h2></section>';

// --- Section 3: process 12 boxes (gr4) ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">Jak to u nás funguje</h2>' .
    '<h2>' . $C['process']['title'] . '</h2>' .
    '<div class="' . htmlspecialchars($grid) . '">';
foreach ($C['process']['steps'] as $s) {
    $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$processHtml .= '</div></section>';

// --- Section 4 (main2): 2-col image gallery (left) + 2 tables (right) ---
$g = $C['gallery'];
$imgFull = (strpos($g['image'], 'http') === 0) ? $g['image'] : (BASE_URL . $g['image']);
$galleryCol = '<div><div class="gr1">' .
    '<div><a data-fancybox-group="' . htmlspecialchars($g['group']) . '" title="' . $g['alt'] . '" href="' . htmlspecialchars($imgFull) . '">' .
    '<div class="gallery-img"><img src="' . htmlspecialchars($imgFull) . '" alt="' . $g['alt'] . '" loading="lazy" class="imgres"></div>' .
    '</a></div>' .
    '</div></div>';

// Adult sizes table
$adult = $C['sizes']['adult'];
$adultTable = '<div class="table-responsive"><table class="table table-hover table-striped"><thead><tr>';
foreach ($adult['headers'] as $h) { $adultTable .= '<th>' . $h . '</th>'; }
$adultTable .= '</tr></thead><tbody>';
foreach ($adult['rows'] as $row) {
    $adultTable .= '<tr><td>' . $row[0] . '</td><td>' . $row[1] . '</td></tr>';
}
$adultTable .= '</tbody></table></div>';

// Kid sizes table
$kid = $C['sizes']['kid'];
$kidTable = '<div class="table-responsive"><table class="table table-hover table-striped"><thead><tr>';
foreach ($kid['headers'] as $h) { $kidTable .= '<th>' . $h . '</th>'; }
$kidTable .= '</tr></thead><tbody>';
foreach ($kid['rows'] as $row) {
    $kidTable .= '<tr><td>' . $row[0] . '</td><td>' . $row[1] . '</td></tr>';
}
$kidTable .= '</tbody></table></div>';

$tablesCol = '<div>' .
    '<h3>' . $adult['title'] . '</h3>' .
    '<p>&nbsp;</p>' . $adultTable . '<p>&nbsp;</p>' .
    '<h3>' . $kid['title'] . '</h3>' .
    '<p>&nbsp;</p>' . $kidTable . '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$main2Section = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">Další důležité informace</h2>' .
    '<div class="gr2">' . $galleryCol . $tablesCol . '</div>' .
    '</section>';

// --- Section 5: FAQ + odkaz na další otázky ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">Na co se nás často ptáte</h2>' .
    '<h2>' . $C['faq']['title'] . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ($C['faq']['items'] as $f) {
    $faqHtml .= renderFaqItem($f['q'], $f['a']);
}
$faqHtml .= '</div></div></div>';
if (!empty($C['faq']['more_link'])) {
    $ml = $C['faq']['more_link'];
    $faqHtml .= '<p>&nbsp;</p>' .
        '<p><a aria-label="' . htmlspecialchars($ml['aria']) . '" class="btn btngreen" href="' . BASE_URL . $ml['href'] . '">' . $ml['label'] . '</a></p>';
}
$faqHtml .= '</section>';

// --- Section 6: final CTA "Sedni na motorku!" ---
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
    '<div data-tag="Postup půjčení motorky" class="sections ccontent">' .
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

renderPage($C['seo']['title'], $content, '/jak-pujcit/postup', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Postup půjčení', 'url' => 'https://motogo24.cz/jak-pujcit/postup'],
    ],
]);
