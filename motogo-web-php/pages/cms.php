<?php
// ===== MotoGo24 Web PHP — CMS stránky (VOP, GDPR, Smlouva) =====
// Odpovídá pages-cms.js

$sb = new SupabaseClient();
$slug = $_GET['cms_slug'] ?? '';
// Default title je předaný z routeru jako CS string; přepneme na lokalizovaný dle slugu.
$titleMap = [
    'obchodni-podminky' => t('cms.terms'),
    'gdpr' => t('cms.gdpr'),
    'smlouva-o-pronajmu' => t('cms.contract'),
];
$title = $titleMap[$slug] ?? ($_GET['cms_title'] ?? 'Stránka');

$bcLabel = $title;
$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], $bcLabel]);

$page = $sb->fetchCmsPage($slug);
$pageContent = '';
if ($page && !empty($page['content'])) {
    $pageContent = sanitizeHtml($page['content']);
} else {
    $pageContent = '<p>' . te('common.preparingContent') . '</p>' .
        '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/kontakt">' . te('common.contactUs') . '</a></p>';
}

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . htmlspecialchars($title) . '</h1>' . $pageContent . '</div></div></main>';

// Unikátní meta description per slug — Google penalizuje stejné description
// na vícero stránkách. Per-jazyk přes překladové klíče (cs/en/de/fr/es/nl/pl).
$descKeyMap = [
    'obchodni-podminky'  => 'cms.terms.description',
    'gdpr'               => 'cms.gdpr.description',
    'smlouva-o-pronajmu' => 'cms.contract.description',
];
$fallbackDesc = isset($descKeyMap[$slug]) ? t($descKeyMap[$slug]) : ($title . ' — MotoGo24');

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
renderPage($title . ' | MotoGo24', $content, $path, [
    'description' => $page['excerpt'] ?? $fallbackDesc,
]);
