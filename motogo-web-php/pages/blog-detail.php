<?php
// ===== MotoGo24 Web PHP — Blog detail =====

$post = $sb->fetchCmsPage($blogSlug);

if (!$post) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$title = e($post['title'] ?? '');
$excerpt = e($post['excerpt'] ?? $post['description'] ?? '');
$content = $post['content'] ?? '';
$images = $post['images'] ?? [];
$ogImg = !empty($images) ? $images[0] : '';

echo renderHead($title . ' – Blog Motogo24', $excerpt, '', $ogImg);
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], ['href'=>'/blog', 'label'=>'Blog'], $title]);

// Gallery
$galleryHtml = '';
if (!empty($images)) {
    $galleryHtml .= '<div class="gallery gr3">';
    foreach ($images as $img) {
        $src = imgUrl($img);
        $galleryHtml .= '<div class="gallery-item"><img src="' . e($src) . '" alt="' . $title . '" class="imgres" loading="lazy"></div>';
    }
    $galleryHtml .= '</div><p>&nbsp;</p>';
}

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<h1>' . $title . '</h1>' .
    ($excerpt ? '<p class="excerpt"><strong>' . $excerpt . '</strong></p><p>&nbsp;</p>' : '') .
    $galleryHtml .
    '<div class="cms-content">' . $content . '</div>' .
    '<p>&nbsp;</p>' .
    '<p><a class="btn btndark" href="/blog">&larr; Zpět na blog</a></p>' .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
