<?php
// ===== MotoGo24 Web PHP — CMS stránky (VOP, GDPR, Smlouva) =====
// Odpovídá pages-cms.js

$sb = new SupabaseClient();
$slug = $_GET['cms_slug'] ?? '';
$title = $_GET['cms_title'] ?? 'Stránka';

$bcLabel = $title;
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], $bcLabel]);

$page = $sb->fetchCmsPage($slug);
$pageContent = '';
if ($page && !empty($page['content'])) {
    $pageContent = $page['content'];
} else {
    $pageContent = '<p>Obsah se připravuje. Kontaktujte nás pro více informací.</p>' .
        '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/kontakt">KONTAKTOVAT NÁS</a></p>';
}

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . htmlspecialchars($title) . '</h1>' . $pageContent . '</div></div></main>';

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
renderPage($title . ' | MotoGo24', $content, $path, [
    'description' => $page['excerpt'] ?? ($title . ' – půjčovna motorek Motogo24'),
]);
