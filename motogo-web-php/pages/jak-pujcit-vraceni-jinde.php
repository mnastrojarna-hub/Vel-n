<?php
// ===== MotoGo24 Web PHP — Vrácení motorky jinde (CMS-driven, 1:1 prepis) =====
$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/vraceni-jinde-content-1.php';
$part2 = require __DIR__ . '/../data/vraceni-jinde-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_vraceni_jinde', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.returnElsewhere')]);
$kp = 'web.jak_pujcit_vraceni_jinde';

// --- Section 1: title + intro + "Kdy se vrácení jinde hodí" ---
$whenLis = '';
foreach ((is_array($C['when']['items'] ?? null) ? $C['when']['items'] : []) as $i => $item) {
    $whenLis .= '<li data-cms-key="' . $kp . '.when.items.' . $i . '">' . $item . '</li>';
}
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">' . te('a11y.mainContent') . '</h2>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.when.title">' . ($C['when']['title'] ?? '') . '</h2>' .
    '<ul>' . $whenLis . '</ul>' .
    '</section>';

// --- Section 2: benefits "Proč využít vrácení jinde" — 5 boxes (gr5) ---
$grid = $C['why']['grid'] ?? 'gr5';
$whyHtml = '<section aria-labelledby="benefits"><h2 id="benefits" class="vh">' . te('a11y.benefits') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.why.title">' . ($C['why']['title'] ?? '') . '</h2><div class="' . htmlspecialchars($grid) . '">';
foreach ((is_array($C['why']['items'] ?? null) ? $C['why']['items'] : []) as $i => $w) {
    if (!is_array($w)) continue;
    $kBase = $kp . '.why.items.' . $i;
    $whyHtml .= renderWbox(
        $w['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($w['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($w['text'] ?? '') . '</span>'
    );
}
$whyHtml .= '</div></section>';

$main1Section = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">' . te('a11y.importantInfo') . '</h2></section>';

// --- Section 4: process ---
$pgrid = $C['process']['grid'] ?? 'gr5';
$processHtml = '<section aria-labelledby="process"><h2 id="process" class="vh">' . te('a11y.processHowItWorks') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.process.title">' . ($C['process']['title'] ?? '') . '</h2><div class="' . htmlspecialchars($pgrid) . '">';
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

// --- Section 5: 2-col (Ceník + Nesrovnalosti) ---
$priceLis = '';
foreach ((is_array($C['pricing']['items'] ?? null) ? $C['pricing']['items'] : []) as $i => $item) {
    $priceLis .= '<li data-cms-key="' . $kp . '.pricing.items.' . $i . '">' . $item . '</li>';
}
$pricingCol = '<div>' .
    '<h2 data-cms-key="' . $kp . '.pricing.title">' . ($C['pricing']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.pricing.lead">' . ($C['pricing']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $priceLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p><strong data-cms-key="' . $kp . '.pricing.example_title">' . ($C['pricing']['example_title'] ?? '') . '</strong></p>' .
    '<p data-cms-key="' . $kp . '.pricing.example_q">' . ($C['pricing']['example_q'] ?? '') . '</p>' .
    '<p data-cms-key="' . $kp . '.pricing.example_a">' . ($C['pricing']['example_a'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$issuesLis = '';
foreach ((is_array($C['issues']['items'] ?? null) ? $C['issues']['items'] : []) as $i => $item) {
    $issuesLis .= '<li data-cms-key="' . $kp . '.issues.items.' . $i . '">' . $item . '</li>';
}
$issuesCol = '<div>' .
    '<h2 data-cms-key="' . $kp . '.issues.title">' . ($C['issues']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.issues.lead">' . ($C['issues']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $issuesLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p data-cms-key="' . $kp . '.issues.closing">' . ($C['issues']['closing'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '</div>';

$twoColSection = '<section aria-labelledby="main2" class="main2"><h2 id="main2" class="vh">' . te('a11y.moreImportantInfo') . '</h2>' .
    '<div class="gr2">' . $pricingCol . $issuesCol . '</div>' .
    '</section>';

// --- Section 6: FAQ ---
$faqHtml = '<section aria-labelledby="faq"><h2 id="faq" class="vh">' . te('a11y.frequentQuestions') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.faq.title">' . ($C['faq']['title'] ?? '') . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
foreach ((is_array($C['faq']['items'] ?? null) ? $C['faq']['items'] : []) as $i => $f) {
    if (!is_array($f)) continue;
    $kBase = $kp . '.faq.items.' . $i;
    $faqHtml .= renderFaqItem(
        '<span data-cms-key="' . $kBase . '.q">' . ($f['q'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.a">' . ($f['a'] ?? '') . '</span>'
    );
}
$faqHtml .= '</div></div></div></section>';

// --- Section 7: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">' . te('a11y.contactUs') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '<p>&nbsp;</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Vrácení motorky jinde" class="sections ccontent">' .
    $titleSection .
    $whyHtml .
    $main1Section .
    $processHtml .
    $twoColSection .
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

renderPage($C['seo']['title'], $content, '/jak-pujcit/vraceni-jinde', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.returnElsewhere'), 'url' => siteCanonicalUrl('/jak-pujcit/vraceni-jinde')],
    ],
]);
