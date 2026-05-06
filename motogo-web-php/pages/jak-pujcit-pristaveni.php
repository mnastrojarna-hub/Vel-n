<?php
// ===== MotoGo24 Web PHP — Přistavení motocyklu (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/pristaveni-motocyklu
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/pristaveni-content-1.php';
$part2 = require __DIR__ . '/../data/pristaveni-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_pristaveni', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.delivery')]);

// --- Section 1: title + intro + "Kdy se přistavení hodí" ---
$whenLis = '';
foreach ((is_array($C['when']['items'] ?? null) ? $C['when']['items'] : []) as $i => $item) {
    $whenLis .= '<li data-cms-key="web.jak_pujcit_pristaveni.when.items.' . $i . '">' . $item . '</li>';
}
$titleSection = '<section>' .
    '<h1 data-cms-key="web.jak_pujcit_pristaveni.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="web.jak_pujcit_pristaveni.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.when.title">' . ($C['when']['title'] ?? '') . '</h2>' .
    '<ul>' . $whenLis . '</ul>' .
    '</section>';

// --- Section 2: benefits "Proč využít přistavení motorky" — 5 boxes (gr5) ---
$grid = $C['why']['grid'] ?? 'gr5';
$whyHtml = '<section>' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.why.title">' . ($C['why']['title'] ?? '') . '</h2><div class="' . htmlspecialchars($grid) . '">';
foreach ((is_array($C['why']['items'] ?? null) ? $C['why']['items'] : []) as $i => $w) {
    if (!is_array($w)) continue;
    $kBase = 'web.jak_pujcit_pristaveni.why.items.' . $i;
    $whyHtml .= renderWbox(
        $w['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($w['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($w['text'] ?? '') . '</span>'
    );
}
$whyHtml .= '</div></section>';

// --- Section 3: process "Jak přistavení probíhá" — 10 boxes (gr5) ---
$pgrid = $C['process']['grid'] ?? 'gr5';
$processHtml = '<section>' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.process.title">' . ($C['process']['title'] ?? '') . '</h2><div class="' . htmlspecialchars($pgrid) . '">';
foreach ((is_array($C['process']['steps'] ?? null) ? $C['process']['steps'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $kBase = 'web.jak_pujcit_pristaveni.process.steps.' . $i;
    $processHtml .= renderWbox(
        $s['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($s['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($s['text'] ?? '') . '</span>'
    );
}
$processHtml .= '</div></section>';

// --- Section 4: pricing "Ceník přistavení" + příklad ---
$priceLis = '';
foreach ((is_array($C['pricing']['items'] ?? null) ? $C['pricing']['items'] : []) as $i => $item) {
    $priceLis .= '<li data-cms-key="web.jak_pujcit_pristaveni.pricing.items.' . $i . '">' . $item . '</li>';
}
$pricingHtml = '<section class="main2">' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.pricing.title">' . ($C['pricing']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="web.jak_pujcit_pristaveni.pricing.lead">' . ($C['pricing']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $priceLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p data-cms-key="web.jak_pujcit_pristaveni.pricing.example">' . ($C['pricing']['example'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</section>';

// --- Section 5: FAQ ---
$faqHtml = '<section>' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.faq.title">' . ($C['faq']['title'] ?? '') . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ((is_array($C['faq']['items'] ?? null) ? $C['faq']['items'] : []) as $i => $f) {
    if (!is_array($f)) continue;
    $kBase = 'web.jak_pujcit_pristaveni.faq.items.' . $i;
    $faqHtml .= renderFaqItem(
        '<span data-cms-key="' . $kBase . '.q">' . ($f['q'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.a">' . ($f['a'] ?? '') . '</span>'
    );
}
$faqHtml .= '</div></div></div></section>';

// --- Section 6: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="web.jak_pujcit_pristaveni.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section>' .
    '<h2 data-cms-key="web.jak_pujcit_pristaveni.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="web.jak_pujcit_pristaveni.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Přistavení motocyklu" class="sections ccontent">' .
    $titleSection .
    $whyHtml .
    $processHtml .
    $pricingHtml .
    $faqHtml .
    $finalCtaSection .
    '</div></div></main>';

// FAQPage schema
$faqSchemaItems = [];
foreach ((is_array($C['faq']['items'] ?? null) ? $C['faq']['items'] : []) as $faq) {
    if (!is_array($faq) || empty($faq['q']) || empty($faq['a'])) continue;
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags((string)$faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags((string)$faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '';
if (!empty($faqSchemaItems)) {
    $faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';
}

renderPage($C['seo']['title'], $content, '/jak-pujcit/pristaveni', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.delivery'), 'url' => siteCanonicalUrl('/jak-pujcit/pristaveni')],
    ],
]);
