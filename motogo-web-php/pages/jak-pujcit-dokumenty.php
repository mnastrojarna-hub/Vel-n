<?php
// ===== MotoGo24 Web PHP — Dokumenty a návody (CMS-driven, 1:1 prepis) =====
// Zdroj: https://www.motogo24.cz/cz/jak-si-pujcit-motorku/dokumenty-a-navody
// Obsah rozdelen do 2 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/dokumenty-content-1.php';
$part2 = require __DIR__ . '/../data/dokumenty-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_dokumenty', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.documents')]);

// --- Section 1: title + intro + top CTA ---
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">' . te('a11y.mainContent') . '</h2>' .
    '<h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($C['top_cta']['aria']) . '" class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p>' .
    '</section>';

// --- Section 2: summary 6 boxů ---
$summaryHtml = '<section aria-labelledby="benefits"><h2 id="benefits" class="vh">' . te('a11y.benefits') . '</h2>' .
    '<h2>' . $C['summary']['title'] . '</h2><div class="gr6">';
foreach ($C['summary']['items'] as $s) {
    $summaryHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$summaryHtml .= '</div></section>';

// --- Section 3: requirements + payments table + 2-col (usage/handover) + privacy + documents ---
$reqLis = '';
foreach ($C['required_docs']['items'] as $i) { $reqLis .= '<li>' . $i . '</li>'; }

$paymentsTable = '<div class="table-responsive"><table aria-label="' . htmlspecialchars($C['payments']['aria']) . '" class="table table-striped table-hover"><thead><tr>';
foreach ($C['payments']['headers'] as $h) { $paymentsTable .= '<th>' . $h . '</th>'; }
$paymentsTable .= '</tr></thead><tbody>';
foreach ($C['payments']['rows'] as $row) {
    $paymentsTable .= '<tr>';
    foreach ($row as $cell) { $paymentsTable .= '<td>' . $cell . '</td>'; }
    $paymentsTable .= '</tr>';
}
$paymentsTable .= '</tbody></table></div>';

$mid = $C['payments']['mid_cta'];
$paymentsBlock = '<h2>' . $C['payments']['title'] . '</h2>' .
    '<p>' . $C['payments']['lead'] . '</p>' .
    '<p>&nbsp;</p>' . $paymentsTable . '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($mid['aria']) . '" class="btn btngreen" href="' . BASE_URL . $mid['href'] . '">' . $mid['label'] . '</a></p>' .
    '<p>&nbsp;</p>';

// 2-col usage / handover, oba s relativnimi linky → BASE_URL
$linkFix = function ($html) {
    return preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $html);
};
$useLis = '';
foreach ($C['usage']['items'] as $i) { $useLis .= '<li>' . $linkFix($i) . '</li>'; }
$handLis = '';
foreach ($C['handover']['items'] as $i) { $handLis .= '<li>' . $linkFix($i) . '</li>'; }
$twoColHtml = '<div class="gr2">' .
    '<div><h2>' . $C['usage']['title'] . '</h2><ul>' . $useLis . '</ul></div>' .
    '<div><h2>' . $C['handover']['title'] . '</h2><ul>' . $handLis . '</ul></div>' .
    '</div>';

$privacyHtml = '<p>&nbsp;</p><h2>' . $C['privacy']['title'] . '</h2>' .
    '<p>' . $linkFix($C['privacy']['text']) . '</p><p>&nbsp;</p>';

// Dokumenty PDF — boxwhitey karty
$docsCardsHtml = '<h2>' . $C['documents']['title'] . '</h2><div class="attachments attachments-columns gr2">';
foreach ($C['documents']['items'] as $d) {
    $href = BASE_URL . $d['href'];
    $name = htmlspecialchars($d['name']);
    $size = htmlspecialchars($d['size']);
    $docsCardsHtml .= '<a class="boxwhitey dfac" href="' . $href . '" title="' . $name . '"><div class="gr3">' .
        '<img src="' . BASE_URL . '/gfx/ico-pdf.svg" class="icon-big" alt="' . $name . '" title="' . $name . '" loading="lazy">' .
        '<div><h3>' . $name . '</h3><br>(' . $size . ')</div>' .
        '<div><span class="btn btngreen-small"><img src="' . BASE_URL . '/gfx/ico-stahnout.svg" alt="' . te('common.download') . '" loading="lazy"><br>' . te('common.downloadCaps') . '</span></div>' .
        '</div></a>';
}
$docsCardsHtml .= '</div>';

$mainSection = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">' . te('a11y.importantInfo') . '</h2>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['required_docs']['title'] . '</h2><ul>' . $reqLis . '</ul>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    $paymentsBlock .
    $twoColHtml .
    $privacyHtml .
    $docsCardsHtml .
    '</section>';

// --- Section 4: mid CTA "Souhlasíte s podmínkami?" ---
$midCtaSection = '<section aria-labelledby="main3" class="main3"><h2 id="main3" class="vh">' . te('a11y.moreInfo') . '</h2>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2>' . $C['midcta']['title'] . '</h2>' .
    '<p>' . $C['midcta']['text'] . '</p>' .
    '</section>';

// --- Section 5: final CTA ---
$ctaButtons = '';
foreach ($C['cta']['buttons'] as $btn) {
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? $btn['label']) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">' . te('a11y.contactUs') . '</h2>' .
    '<h2>' . $C['cta']['title'] . '</h2>' .
    '<p>' . $C['cta']['text'] . '</p>' .
    '<p>&nbsp;</p>' .
    '<p>' . $ctaButtons . '</p>' .
    '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div data-tag="Dokumenty a návody" class="sections ccontent">' .
    $titleSection .
    $summaryHtml .
    $mainSection .
    $midCtaSection .
    $finalCtaSection .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/dokumenty', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.howto'), 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => t('menu.howto.documents'), 'url' => 'https://motogo24.cz/jak-pujcit/dokumenty'],
    ],
]);
