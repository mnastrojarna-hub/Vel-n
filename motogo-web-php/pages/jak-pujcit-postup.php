<?php
// ===== MotoGo24 Web PHP — Postup půjčení motorky (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/postup-content-1.php';
$part2 = require __DIR__ . '/../data/postup-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_postup', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.process')]);

// --- Section 1: title (h1 + intro p1 + h2 + intro p2) ---
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">' . te('a11y.mainContent') . '</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro_p1'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['intro_h2'] . '</h2>' .
    '<p>' . $C['intro_p2'] . '</p>' .
    '</section>';

// --- Section 2 (placeholder): main1 ---
$main1Section = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">' . te('a11y.importantInfo') . '</h2></section>';

// --- Section 3: process 12 boxes (gr4) ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">' . te('a11y.processHowItWorks') . '</h2>' .
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

$main2Section = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">' . te('a11y.moreImportantInfo') . '</h2>' .
    '<div class="gr2">' . $galleryCol . $tablesCol . '</div>' .
    '</section>';

// --- Section 5: FAQ + odkaz na další otázky ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">' . te('a11y.frequentQuestions') . '</h2>' .
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
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">' . te('a11y.contactUs') . '</h2>' .
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

// ===== FAQPage schema (otázky/odpovědi) =====
$faqSchemaItems = [];
foreach ($C['faq']['items'] as $faq) {
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';

// ===== HowTo schema — krok za krokem postup pro AI agenty =====
// Generuje se automaticky z $C['process']['steps'] (12 boxů z CMS).
// Google + AI to ukazuje jako "kroky postupu" v AI Overviews / featured snippets.
$howToSteps = [];
$stepPos = 0;
foreach ($C['process']['steps'] as $s) {
    $stepPos++;
    $stepName = trim(strip_tags($s['title'] ?? ''));
    $stepText = trim(strip_tags($s['text'] ?? ''));
    if ($stepName === '' && $stepText === '') continue;
    $howToSteps[] = '{"@type":"HowToStep","position":' . $stepPos
        . ',"name":' . json_encode($stepName !== '' ? $stepName : ('Krok ' . $stepPos), JSON_UNESCAPED_UNICODE)
        . ',"text":' . json_encode($stepText, JSON_UNESCAPED_UNICODE)
        . ',"url":"https://motogo24.cz/jak-pujcit/postup#step-' . $stepPos . '"'
        . '}';
}
$howToSchema = '';
if (!empty($howToSteps)) {
    $howToName = trim(strip_tags($C['process']['title'] ?? 'Jak si půjčit motorku'));
    $howToDesc = trim(strip_tags($C['intro_p1'] ?? 'Postup půjčení motorky v MotoGo24 — od výběru po vrácení.'));
    $howToSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"HowTo","name":' . json_encode($howToName, JSON_UNESCAPED_UNICODE)
        . ',"description":' . json_encode($howToDesc, JSON_UNESCAPED_UNICODE)
        . ',"image":"https://motogo24.cz/gfx/hero-banner.jpg"'
        . ',"totalTime":"PT15M"'
        . ',"estimatedCost":{"@type":"MonetaryAmount","currency":"CZK","value":"990"}'
        . ',"supply":[{"@type":"HowToSupply","name":"Občanský průkaz nebo cestovní pas"},{"@type":"HowToSupply","name":"Řidičský průkaz (skupina A1/A2/A nebo B pro dětské motorky)"},{"@type":"HowToSupply","name":"Platební karta nebo hotovost"}]'
        . ',"tool":[{"@type":"HowToTool","name":"Mobilní telefon nebo počítač s internetem"}]'
        . ',"step":[' . implode(',', $howToSteps) . ']'
        . '}
  </script>';
}

$combinedSchema = $faqSchema . $howToSchema;

renderPage($C['seo']['title'], $content, '/jak-pujcit/postup', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $combinedSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.process'), 'url' => siteCanonicalUrl('/jak-pujcit/postup')],
    ],
]);
