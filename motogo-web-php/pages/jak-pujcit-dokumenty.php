<?php
// ===== MotoGo24 Web PHP — Dokumenty a návody (CMS-driven, 1:1 prepis) =====
$sb = new SupabaseClient();

$part1 = require __DIR__ . '/../data/dokumenty-content-1.php';
$part2 = require __DIR__ . '/../data/dokumenty-content-2.php';
$defaults = array_merge($part1, $part2);

$C = $sb->siteContent('jak_pujcit_dokumenty', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.documents')]);
$kp = 'web.jak_pujcit_dokumenty';

// --- Section 1: title + intro + top CTA ---
$tcta = is_array($C['top_cta'] ?? null) ? $C['top_cta'] : [];
$titleSection = '<section aria-labelledby="title"><h2 id="title" class="vh">' . te('a11y.mainContent') . '</h2>' .
    '<h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<p data-cms-key="' . $kp . '.intro">' . ($C['intro'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($tcta['aria'] ?? '') . '" class="btn btngreen" href="' . BASE_URL . ($tcta['href'] ?? '#') . '" data-cms-key="' . $kp . '.top_cta.button.label">' . ($tcta['label'] ?? '') . '</a></p>' .
    '</section>';

// --- Section 2: summary 6 boxů ---
$summaryHtml = '<section aria-labelledby="benefits"><h2 id="benefits" class="vh">' . te('a11y.benefits') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.summary.title">' . ($C['summary']['title'] ?? '') . '</h2><div class="gr6">';
foreach ((is_array($C['summary']['items'] ?? null) ? $C['summary']['items'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $kBase = $kp . '.summary.items.' . $i;
    $summaryHtml .= renderWbox(
        $s['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($s['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($s['text'] ?? '') . '</span>'
    );
}
$summaryHtml .= '</div></section>';

// --- Section 3: requirements + payments table + 2-col (usage/handover) + privacy + documents ---
$reqLis = '';
foreach ((is_array($C['required_docs']['items'] ?? null) ? $C['required_docs']['items'] : []) as $i => $item) {
    $reqLis .= '<li data-cms-key="' . $kp . '.required_docs.items.' . $i . '">' . $item . '</li>';
}

$paymentsTable = '<div class="table-responsive"><table aria-label="' . htmlspecialchars($C['payments']['aria'] ?? '') . '" class="table table-striped table-hover"><thead><tr>';
foreach ((is_array($C['payments']['headers'] ?? null) ? $C['payments']['headers'] : []) as $h) { $paymentsTable .= '<th>' . $h . '</th>'; }
$paymentsTable .= '</tr></thead><tbody>';
foreach ((is_array($C['payments']['rows'] ?? null) ? $C['payments']['rows'] : []) as $rIdx => $row) {
    if (!is_array($row)) continue;
    $paymentsTable .= '<tr>';
    foreach ($row as $cIdx => $cell) {
        $paymentsTable .= '<td data-cms-key="' . $kp . '.payments.rows.' . $rIdx . '.' . $cIdx . '">' . $cell . '</td>';
    }
    $paymentsTable .= '</tr>';
}
$paymentsTable .= '</tbody></table></div>';

$mid = is_array($C['payments']['mid_cta'] ?? null) ? $C['payments']['mid_cta'] : [];
$paymentsBlock = '<h2 data-cms-key="' . $kp . '.payments.title">' . ($C['payments']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.payments.lead">' . ($C['payments']['lead'] ?? '') . '</p>' .
    '<p>&nbsp;</p>' . $paymentsTable . '<p>&nbsp;</p>' .
    '<p><a aria-label="' . htmlspecialchars($mid['aria'] ?? '') . '" class="btn btngreen" href="' . BASE_URL . ($mid['href'] ?? '#') . '" data-cms-key="' . $kp . '.payments.mid_cta.label">' . ($mid['label'] ?? '') . '</a></p>' .
    '<p>&nbsp;</p>';

// 2-col usage / handover
$linkFix = function ($html) {
    return preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $html);
};
$useLis = '';
foreach ((is_array($C['usage']['items'] ?? null) ? $C['usage']['items'] : []) as $i => $item) {
    $useLis .= '<li data-cms-key="' . $kp . '.usage.items.' . $i . '">' . $linkFix($item) . '</li>';
}
$handLis = '';
foreach ((is_array($C['handover']['items'] ?? null) ? $C['handover']['items'] : []) as $i => $item) {
    $handLis .= '<li data-cms-key="' . $kp . '.handover.items.' . $i . '">' . $linkFix($item) . '</li>';
}
$twoColHtml = '<div class="gr2">' .
    '<div><h2 data-cms-key="' . $kp . '.usage.title">' . ($C['usage']['title'] ?? '') . '</h2><ul>' . $useLis . '</ul></div>' .
    '<div><h2 data-cms-key="' . $kp . '.handover.title">' . ($C['handover']['title'] ?? '') . '</h2><ul>' . $handLis . '</ul></div>' .
    '</div>';

$privacyHtml = '<p>&nbsp;</p><h2 data-cms-key="' . $kp . '.privacy.title">' . ($C['privacy']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.privacy.text">' . $linkFix($C['privacy']['text'] ?? '') . '</p><p>&nbsp;</p>';

// Dokumenty PDF — boxwhitey karty
$docsCardsHtml = '<h2 data-cms-key="' . $kp . '.documents.title">' . ($C['documents']['title'] ?? '') . '</h2><div class="attachments attachments-columns gr2">';
foreach ((is_array($C['documents']['items'] ?? null) ? $C['documents']['items'] : []) as $i => $d) {
    if (!is_array($d)) continue;
    $href = BASE_URL . ($d['href'] ?? '#');
    $name = htmlspecialchars($d['name'] ?? '');
    $size = htmlspecialchars($d['size'] ?? '');
    $kBase = $kp . '.documents.items.' . $i;
    $docsCardsHtml .= '<a class="boxwhitey dfac" href="' . $href . '" title="' . $name . '"><div class="gr3">' .
        '<img src="' . BASE_URL . '/gfx/ico-pdf.svg" class="icon-big" alt="' . $name . '" title="' . $name . '" loading="lazy">' .
        '<div><h3 data-cms-key="' . $kBase . '.name">' . ($d['name'] ?? '') . '</h3><br>(<span data-cms-key="' . $kBase . '.size">' . ($d['size'] ?? '') . '</span>)</div>' .
        '<div><span class="btn btngreen-small"><img src="' . BASE_URL . '/gfx/ico-stahnout.svg" alt="' . te('common.download') . '" loading="lazy"><br>' . te('common.downloadCaps') . '</span></div>' .
        '</div></a>';
}
$docsCardsHtml .= '</div>';

$mainSection = '<section aria-labelledby="main1" class="main1"><h2 id="main1" class="vh">' . te('a11y.importantInfo') . '</h2>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.required_docs.title">' . ($C['required_docs']['title'] ?? '') . '</h2><ul>' . $reqLis . '</ul>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    $paymentsBlock .
    $twoColHtml .
    $privacyHtml .
    $docsCardsHtml .
    '</section>';

// --- Section 4: mid CTA "Souhlasíte s podmínkami?" ---
$midCtaSection = '<section aria-labelledby="main3" class="main3"><h2 id="main3" class="vh">' . te('a11y.moreInfo') . '</h2>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<h2 data-cms-key="' . $kp . '.midcta.title">' . ($C['midcta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.midcta.text">' . ($C['midcta']['text'] ?? '') . '</p>' .
    '</section>';

// --- Section 5: final CTA ---
$ctaButtons = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons .= '<a aria-label="' . htmlspecialchars($btn['aria'] ?? ($btn['label'] ?? '')) . '" class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '" data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</a>&nbsp;';
}
$finalCtaSection = '<section aria-labelledby="cta"><h2 id="cta" class="vh">' . te('a11y.contactUs') . '</h2>' .
    '<h2 data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</h2>' .
    '<p data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</p>' .
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
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.documents'), 'url' => siteCanonicalUrl('/jak-pujcit/dokumenty')],
    ],
]);
