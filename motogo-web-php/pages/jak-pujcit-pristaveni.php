<?php
// ===== MotoGo24 Web PHP — Přistavení motocyklu (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/pristaveni-motocyklu
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/pristaveni-content-1.php';
$part2 = require __DIR__ . '/../data/pristaveni-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_pristaveni', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Přistavení motocyklu']);

// --- Section 1: title + intro + "Kdy se přistavení hodí" ---
$whenLis = '';
foreach ($C['when']['items'] as $i) { $whenLis .= '<li>' . $i . '</li>'; }
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">Hlavní obsah stránky</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['when']['title'] . '</h2>' .
    '<ul>' . $whenLis . '</ul>' .
    '</section>';

// --- Section 2: benefits "Proč využít přistavení motorky" — 5 boxes (gr5) ---
$grid = $C['why']['grid'] ?? 'gr5';
$whyHtml = '<section aria-labelledby="benefits"><h2 id="benefits" class="vh">Hlavní výhody a přínosy</h2>' .
    '<h2>' . $C['why']['title'] . '</h2><div class="' . htmlspecialchars($grid) . '">';
foreach ($C['why']['items'] as $w) {
    $whyHtml .= renderWbox($w['icon'], $w['title'], $w['text']);
}
$whyHtml .= '</div></section>';

// --- Section 3: process "Jak přistavení probíhá" — 10 boxes (gr5) ---
$pgrid = $C['process']['grid'] ?? 'gr5';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">Jak to u nás funguje</h2>' .
    '<h2>' . $C['process']['title'] . '</h2><div class="' . htmlspecialchars($pgrid) . '">';
foreach ($C['process']['steps'] as $s) {
    $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$processHtml .= '</div></section>';

// --- Section 4: pricing "Ceník přistavení" + příklad ---
$priceLis = '';
foreach ($C['pricing']['items'] as $i) { $priceLis .= '<li>' . $i . '</li>'; }
$pricingHtml = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">Další důležité informace</h2>' .
    '<h2>' . $C['pricing']['title'] . '</h2>' .
    '<p>' . $C['pricing']['lead'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $priceLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p>' . $C['pricing']['example'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</section>';

// --- Section 5: FAQ ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">Na co se nás často ptáte</h2>' .
    '<h2>' . $C['faq']['title'] . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ($C['faq']['items'] as $f) {
    $faqHtml .= renderFaqItem($f['q'], $f['a']);
}
$faqHtml .= '</div></div></div></section>';

// --- Section 6: final CTA ---
$ctaButtons = '';
foreach ($C['cta']['buttons'] as $btn) {
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? $btn['label']) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">Kontaktujte nás</h2>' .
    '<h2>' . $C['cta']['title'] . '</h2>' .
    '<p>' . $C['cta']['text'] . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Přistavení motocyklu" class="sections ccontent">' .
    $titleSection .
    $whyHtml .
    '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">Důležité informace</h2></section>' .
    $processHtml .
    $pricingHtml .
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

renderPage($C['seo']['title'], $content, '/jak-pujcit/pristaveni', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Přistavení', 'url' => 'https://motogo24.cz/jak-pujcit/pristaveni'],
    ],
]);
