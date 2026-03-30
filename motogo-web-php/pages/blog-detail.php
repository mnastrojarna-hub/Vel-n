<?php
// ===== MotoGo24 Web PHP — Blog detail =====
// Odpovídá pages-blog.js (detail route)

$sb = new SupabaseClient();
$slug = $_GET['slug'] ?? '';
$post = $sb->fetchCmsPage($slug);

if (!$post) {
    $content = '<main id="content"><div class="container">' .
        renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Blog', 'href' => '/blog'], 'Článek nenalezen']) .
        '<div class="ccontent"><h1>Článek nenalezen</h1><p><a class="btn btngreen" href="' . BASE_URL . '/blog">Zpět na blog</a></p></div></div></main>';
    renderPage('Článek nenalezen – Motogo24', $content, '/blog/' . htmlspecialchars($slug));
    return;
}

$title = htmlspecialchars($post['title'] ?? '');
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Blog', 'href' => '/blog'], $title]);

// Gallery
$galleryHtml = '';
if (!empty($post['images']) && count($post['images']) > 0) {
    $galleryHtml = '<section><div class="gallery-blog">';
    foreach ($post['images'] as $img) {
        $galleryHtml .= '<div class="col-lg-3 col-md-4 col-sm-6">' .
            '<a href="' . htmlspecialchars($img) . '" target="_blank"><div class="gallery-background"><div class="gallery-box">' .
            '<img src="' . htmlspecialchars($img) . '" alt="' . $title . '" loading="lazy"></div></div></a></div>';
    }
    $galleryHtml .= '</div></section>';
} elseif (!empty($post['image_url'])) {
    $galleryHtml = '<section><div class="gallery-blog">' .
        '<div class="col-lg-3 col-md-4 col-sm-6"><a href="' . htmlspecialchars($post['image_url']) . '" target="_blank"><div class="gallery-background"><div class="gallery-box">' .
        '<img src="' . htmlspecialchars($post['image_url']) . '" alt="' . $title . '" loading="lazy"></div></div></a></div></div></section>';
}

$postContent = $post['content'] ?? ($post['description'] ?? '');
$excerpt = $post['excerpt'] ?? ($post['description'] ?? '');

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent blog-detail">' .
    '<section><h1>' . $title . '</h1>' .
    '<p>' . htmlspecialchars($excerpt) . '</p></section>' .
    ($postContent ? '<section><div class="blog-content">' . $postContent . '</div></section>' : '') .
    $galleryHtml .
    '</div></div></main>';

// Article schema
$articleSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Article","headline":' . json_encode($post['title'] ?? '', JSON_UNESCAPED_UNICODE) . ',"author":{"@type":"Organization","name":"MotoGo24"},"publisher":{"@type":"Organization","name":"MotoGo24","logo":{"@type":"ImageObject","url":"https://motogo24.cz/gfx/logo.svg"}}' . (!empty($post['created_at']) ? ',"datePublished":' . json_encode($post['created_at']) : '') . '}
  </script>';

renderPage($title . ' | Blog MotoGo24', $content, '/blog/' . $slug, [
    'description' => $excerpt ?: ('Článek na blogu Motogo24 – ' . ($post['title'] ?? '')),
    'og_type' => 'article',
    'og_image' => !empty($post['images'][0]) ? $post['images'][0] : (!empty($post['image_url']) ? $post['image_url'] : 'https://motogo24.cz/gfx/hero-banner.png'),
    'schema' => $articleSchema,
    'breadcrumbs' => [['name' => 'Domů', 'url' => 'https://motogo24.cz/'], ['name' => 'Blog', 'url' => 'https://motogo24.cz/blog'], ['name' => $post['title'] ?? '', 'url' => 'https://motogo24.cz/blog/' . $slug]],
]);
