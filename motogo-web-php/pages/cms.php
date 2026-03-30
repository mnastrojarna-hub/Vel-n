<?php
// ===== MotoGo24 Web PHP — CMS stránky (OP, GDPR, Smlouva) =====

$slugMap = [
    '/obchodni-podminky' => 'obchodni-podminky',
    '/gdpr' => 'gdpr',
    '/smlouva' => 'smlouva-o-pronajmu',
];

$slug = $slugMap[$requestUri] ?? '';

if (!$slug) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$page = $sb->fetchCmsPage($slug);

if (!$page) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$title = e($page['title'] ?? 'Stránka');
$content = $page['content'] ?? '';
$description = e($page['excerpt'] ?? $page['description'] ?? '');

echo renderHead($title . ' – Motogo24', $description);
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], $title]);

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<h1>' . $title . '</h1>' .
    '<div class="cms-content">' . $content . '</div>' .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
