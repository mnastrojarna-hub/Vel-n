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
$titleSection = '<section>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.when.title">' . ($C['when']['title'] ?? '') . '</h2>' .
    '<ul>' . $whenLis . '</ul>' .
    '</section>';

// --- Section 2: benefits "Proč využít vrácení jinde" — 5 boxes (gr5) ---
$grid = $C['why']['grid'] ?? 'gr5';
$whyHtml = '<section>' .
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

// --- Section 4: process ---
$pgrid = $C['process']['grid'] ?? 'gr5';
$processHtml = '<section>' .
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

$twoColSection = '<section class="main2">' .
    '<div class="gr2">' . $pricingCol . $issuesCol . '</div>' .
    '</section>';

// FAQ sekce odstraněna (2026-05-17) — centrální FAQ je pouze na /jak-pujcit/faq.
// Klíče `web.jak_pujcit_vraceni_jinde.faq.*` v cms_variables zůstávají, ale nikde se nečtou.
$faqHtml = '';

// --- Section 7: final CTA ---
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
    '<div data-tag="Vrácení motorky jinde" class="sections ccontent">' .
    $titleSection .
    $whyHtml .
    $processHtml .
    $twoColSection .
    $faqHtml .
    $finalCtaSection .
    '</div></div></main>';

// FAQPage schema odstraněno (2026-05-17) — viditelná FAQ sekce zmizela.
$faqSchema = '';

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
