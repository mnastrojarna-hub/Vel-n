<?php
// ===== MotoGo24 Web PHP — SEO stránka pobočky (/motopujcovna-brno, /motopujcovna-vysocina) =====
// $_GET['seo'] = id z seoPobockyPages() (data/seo-pobocky.php) nastaví index.php.
// Obsah je klasická info stránka (H1 + úvod, karty, města, tipy, postup, FAQ, CTA, SEO text),
// kterou ve v2 přestaví landing-info.php (lpInfoPage) — hero, karty, časová osa, akordeon FAQ,
// pruh motorek pobočky a sbalený závěrečný text. Jen česky: v cizím jazyce 301 na detail pobočky.
// Schema: FAQPage + LocalBusiness pobočky s areaServed (města z textu).

require_once __DIR__ . '/../data/seo-pobocky.php';
require_once __DIR__ . '/../data/pobocky.php';

$seoId = (string)($_GET['seo'] ?? '');
$P = seoPobockyPages()[$seoId] ?? null;
if (!$P) { http_response_code(404); require __DIR__ . '/404.php'; return; }

$pbDef = pobockyDefaults();
$br = $pbDef['branches'][$P['branch']];
$branchId = (string)$br['branch_id'];

if (i18nDetectLanguage() !== 'cs') {
    header('Location: ' . BASE_URL . i18nLocalizePath('/pobocky/' . $br['slug']), true, 301);
    exit;
}

$sb = new SupabaseClient();
$key = $P['key'];
$C = $sb->siteContent($key, require __DIR__ . '/../data/' . $P['file']);
$k = 'web.' . $key . '.';
$rezHref = '/rezervace?pobocka=' . $branchId;
$katHref = '/katalog?pobocka=' . $branchId;
$href = function ($h) use ($rezHref, $katHref) { return strtr((string)$h, ['{rezervace}' => $rezHref, '{katalog}' => $katHref]); };
$list = function ($v) { return is_array($v) ? $v : []; };
$h1Plain = strip_tags((string)$C['h1']);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('menu.branches'), 'href' => '/pobocky'], htmlspecialchars($h1Plain)]);

// Úvod: H1, úvodní text, tlačítko rezervace s předvybranou pobočkou (ve v2 hlavní CTA hero)
$html = '<section><h1 data-cms-key="' . $k . 'h1">' . sanitizeHtml((string)$C['h1']) . '</h1>'
    . '<p data-cms-key="' . $k . 'intro">' . sanitizeHtml((string)$C['intro']) . '</p>'
    . '<p><a class="btn btngreen" href="' . he($rezHref) . '" data-cms-key="' . $k . 'cta_top">' . sanitizeHtml((string)$C['cta_top']) . '</a></p></section>';

// Karty (výhody, tipy na výlety) a postup (klíče *.process.steps.* = časová osa ve v2)
$boxes = function ($sec, $field, $grid) use ($C, $k, $list) {
    $out = '<section><h2 data-cms-key="' . $k . $sec . '.title">' . sanitizeHtml((string)($C[$sec]['title'] ?? '')) . '</h2><div class="' . $grid . '">';
    foreach ($list($C[$sec][$field] ?? null) as $i => $b) {
        if (!is_array($b)) continue;
        $kb = $k . $sec . '.' . $field . '.' . $i;
        $out .= renderWbox($b['icon'] ?? '', '<span data-cms-key="' . $kb . '.title">' . ($b['title'] ?? '') . '</span>', '<span data-cms-key="' . $kb . '.text">' . ($b['text'] ?? '') . '</span>');
    }
    return $out . '</div></section>';
};
$html .= $boxes('why', 'items', 'gr3');

// Odkud k nám: města z okolí pobočky
$A = $C['areas'] ?? [];
$lis = '';
foreach ($list($A['items'] ?? null) as $i => $it) $lis .= '<li data-cms-key="' . $k . 'areas.items.' . $i . '">' . sanitizeHtml((string)$it) . '</li>';
$html .= '<section><h2 data-cms-key="' . $k . 'areas.title">' . sanitizeHtml((string)($A['title'] ?? '')) . '</h2>'
    . '<p data-cms-key="' . $k . 'areas.text">' . sanitizeHtml((string)($A['text'] ?? '')) . '</p>'
    . ($lis !== '' ? '<ul>' . $lis . '</ul>' : '')
    . '<p data-cms-key="' . $k . 'areas.note">' . sanitizeHtml((string)($A['note'] ?? '')) . '</p></section>';

$html .= $boxes('tips', 'items', 'gr3');
$html .= $boxes('process', 'steps', 'gr4');

// FAQ (+ FAQPage schema)
$faq = '';
$faqLd = [];
foreach ($list($C['faq']['items'] ?? null) as $i => $f) {
    if (!is_array($f) || empty($f['q']) || empty($f['a'])) continue;
    $kb = $k . 'faq.items.' . $i;
    $faq .= renderFaqItem('<span data-cms-key="' . $kb . '.q">' . $f['q'] . '</span>', '<span data-cms-key="' . $kb . '.a">' . $f['a'] . '</span>');
    $faqLd[] = ['@type' => 'Question', 'name' => strip_tags((string)$f['q']), 'acceptedAnswer' => ['@type' => 'Answer', 'text' => strip_tags((string)$f['a'])]];
}
if ($faq !== '') {
    $html .= '<section><h2 data-cms-key="' . $k . 'faq.title">' . sanitizeHtml((string)($C['faq']['title'] ?? '')) . '</h2>'
        . '<div class="tab-content"><div class="tab-pane active"><div class="gr2">' . $faq . '</div></div></div></section>';
}

// CTA (ve v2 tmavá karta, rezervace jako první tlačítko)
$btns = '';
foreach ($list($C['cta']['buttons'] ?? null) as $i => $b) {
    if (!is_array($b) || trim((string)($b['label'] ?? '')) === '') continue;
    $btns .= '<a class="btn ' . ($i === 0 ? 'btngreen' : 'btndark') . '" href="' . he($href($b['href'] ?? '/rezervace')) . '" data-cms-key="' . $k . 'cta.buttons.' . $i . '.label">' . sanitizeHtml((string)$b['label']) . '</a>&nbsp;';
}
$html .= '<section><h2 data-cms-key="' . $k . 'cta.title">' . sanitizeHtml((string)($C['cta']['title'] ?? '')) . '</h2>'
    . '<p data-cms-key="' . $k . 'cta.text">' . sanitizeHtml((string)($C['cta']['text'] ?? '')) . '</p><p>' . $btns . '</p></section>';

// Závěrečný SEO text (ve v2 sbalitelná karta na konci stránky)
$out = '';
foreach ($list($C['outro']['paragraphs'] ?? null) as $i => $p) $out .= '<p data-cms-key="' . $k . 'outro.paragraphs.' . $i . '">' . sanitizeHtml((string)$p) . '</p>';
if ($out !== '') $html .= '<section><h2 data-cms-key="' . $k . 'outro.title">' . sanitizeHtml((string)($C['outro']['title'] ?? '')) . '</h2>' . $out . '</section>';

$content = '<main id="content"><div class="container">' . $bc
    . '<div data-tag="' . he($h1Plain) . '" class="sections ccontent">' . $html . '</div></div></main>';

// Schema: pobočka jako LocalBusiness s obsluhovanými městy (areaServed = tučná města ze seznamu)
$cities = [];
foreach ($list($A['items'] ?? null) as $it) {
    if (!preg_match('#<strong>(.*?)</strong>#u', (string)$it, $m)) continue;
    foreach (preg_split('/,\s*|\s+a\s+/u', strip_tags($m[1])) as $c) if (trim($c) !== '') $cities[] = ['@type' => 'City', 'name' => trim($c)];
}
$geo = null;
foreach ((array)$sb->fetchBranches() as $row) {
    if (is_array($row) && (string)($row['id'] ?? '') === $branchId && isset($row['gps_lat'], $row['gps_lng'])) {
        $geo = ['@type' => 'GeoCoordinates', 'latitude' => (float)$row['gps_lat'], 'longitude' => (float)$row['gps_lng']];
    }
}
$addr = strip_tags((string)$br['address']);
$zipCity = preg_match('/(\d{3}\s?\d{2})\s+(.+)$/u', $addr, $am) ? [$am[1], $am[2]] : ['', ''];
$biz = array_filter([
    '@type' => ['LocalBusiness', 'AutomotiveBusiness'],
    '@id' => siteCanonicalUrl($P['path']) . '#branch',
    'name' => 'MotoGo24 — ' . $h1Plain,
    'url' => siteCanonicalUrl($P['path']),
    'telephone' => PHONE,
    'parentOrganization' => ['@id' => siteOrigin() . '/#organization'],
    'address' => ['@type' => 'PostalAddress', 'streetAddress' => trim(explode(',', $addr)[0]), 'postalCode' => $zipCity[0], 'addressLocality' => $zipCity[1], 'addressCountry' => 'CZ'],
    'geo' => $geo,
    'areaServed' => $cities ?: null,
    'openingHoursSpecification' => ['@type' => 'OpeningHoursSpecification', 'dayOfWeek' => ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'], 'opens' => '00:00', 'closes' => '23:59'],
]);
$graph = [$biz];
if ($faqLd) $graph[] = ['@type' => 'FAQPage', 'mainEntity' => $faqLd];
$schema = "\n  <script type=\"application/ld+json\">\n  " . json_encode(['@context' => 'https://schema.org', '@graph' => $graph], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n  </script>";

require_once __DIR__ . '/../landing-info.php';
[$content, $lpiMeta] = lpInfoPage($content, $key, $sb);

renderPage(strip_tags((string)$C['seo']['title']), $content, $P['path'], $lpiMeta + [
    'description' => strip_tags((string)$C['seo']['description']),
    'keywords' => strip_tags((string)$C['seo']['keywords']),
    'schema' => $schema,
    // Stránka existuje jen česky → hreflang jen cs (cizí jazyky by vedly na 301)
    'hreflang' => ['cs'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('menu.branches'), 'url' => siteCanonicalUrl('/pobocky')],
        ['name' => $h1Plain, 'url' => siteCanonicalUrl($P['path'])],
    ],
]);
