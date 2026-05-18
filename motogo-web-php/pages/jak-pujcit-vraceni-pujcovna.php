<?php
// ===== MotoGo24 Web PHP — Vrácení motocyklu v půjčovně (CMS-driven, 1:1 prepis) =====
$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/vraceni-pujcovna-content-1.php';
$part2 = require __DIR__ . '/../data/vraceni-pujcovna-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_vraceni_pujcovna', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.returnHome')]);
$kp = 'web.jak_pujcit_vraceni_pujcovna';

// --- Section 1: title + intro ---
$titleSection = '<section>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '</section>';

// --- Section 3: process boxes ---
$grid = $C['process']['grid'] ?? 'gr4';
$processHtml = '<section>' .
    '<div class="' . htmlspecialchars($grid) . '">';
foreach ((is_array($C['process']['steps'] ?? null) ? $C['process']['steps'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $iconSrc = !empty($s['icon']) ? BASE_URL . '/' . ltrim($s['icon'], '/') : '';
    $titleText = trim(strip_tags((string)($s['title'] ?? '')));
    $kBase = $kp . '.process.steps.' . $i;
    $processHtml .= '<div class="wbox">' .
        (!empty($s['icon']) ? '<div class="wbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . htmlspecialchars($titleText) . '" loading="lazy"></div>' : '') .
        '<h3 data-cms-key="' . $kBase . '.title">' . ($s['title'] ?? '') . '</h3>' .
        (!empty($s['text']) ? '<p data-cms-key="' . $kBase . '.text">' . $s['text'] . '</p>' : '') .
        '</div>';
}
$processHtml .= '</div></section>';

// --- Section 4 (main2): Cas vraceni + Nesrovnalosti ---
$issuesLis = '';
foreach ((is_array($C['issues']['items'] ?? null) ? $C['issues']['items'] : []) as $i => $item) {
    $issuesLis .= '<li data-cms-key="' . $kp . '.issues.items.' . $i . '">' . $item . '</li>';
}
$main2Section = '<section class="main2">' .
    '<h2 data-cms-key="' . $kp . '.time.title">' . ($C['time']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.time.text">' . ($C['time']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.issues.title">' . ($C['issues']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.issues.lead">' . ($C['issues']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<ul>' . $issuesLis . '</ul>' .
    '<p>&nbsp;</p>' .
    '<p data-cms-key="' . $kp . '.issues.closing">' . ($C['issues']['closing'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<div class="gr2"><div></div><div></div></div>' .
    '</section>';

// --- Section 5: FAQ ---
$faqHtml = '<section>' .
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

// --- Section 6: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section>' .
    '<h2 data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '<p>&nbsp;</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Vrácení motocyklu v půjčovně" class="sections ccontent">' .
    $titleSection .
    $processHtml .
    $main2Section .
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

renderPage($C['seo']['title'], $content, '/jak-pujcit/vraceni-pujcovna', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.returnHome'), 'url' => siteCanonicalUrl('/jak-pujcit/vraceni-pujcovna')],
    ],
]);
