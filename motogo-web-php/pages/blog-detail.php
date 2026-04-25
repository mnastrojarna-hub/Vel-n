<?php
// ===== MotoGo24 Web PHP — Blog detail =====
// Odpovídá pages-blog.js (detail route)

$sb = new SupabaseClient();
$slug = $_GET['slug'] ?? '';
$post = $sb->fetchCmsPage($slug);

// Fallback: pokud DB nemá článek, zkus fallback set
if (!$post) {
    require_once __DIR__ . '/blog_fallback.php';
    foreach (getBlogFallbackPosts() as $p) {
        if (($p['slug'] ?? '') === $slug) { $post = $p; break; }
    }
}

if (!$post) {
    $content = '<main id="content"><div class="container">' .
        renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.blog'), 'href' => '/blog'], t('blog.detail.notFoundHeading')]) .
        '<div class="ccontent"><h1>' . te('blog.detail.notFoundHeading') . '</h1><p><a class="btn btngreen" href="' . BASE_URL . '/blog">' . te('blog.detail.backToBlog') . '</a></p></div></div></main>';
    renderPage(t('blog.detail.notFoundTitle'), $content, '/blog/' . htmlspecialchars($slug));
    return;
}

// Lokalizované varianty (auto-překlady z Velínu, fallback CZ)
$titleRaw = localized($post, 'title');
$excerptRaw = localized($post, 'excerpt');
if ($excerptRaw === '') $excerptRaw = $post['description'] ?? '';
$contentRaw = localized($post, 'content');
if ($contentRaw === '') $contentRaw = $post['description'] ?? '';

$title = htmlspecialchars($titleRaw);
$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.blog'), 'href' => '/blog'], $title]);

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

$postContent = sanitizeHtml($contentRaw);
$excerpt = $excerptRaw;

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
  {"@context":"https://schema.org","@type":"Article","headline":' . json_encode($titleRaw, JSON_UNESCAPED_UNICODE) . ',"author":{"@type":"Organization","name":"MotoGo24"},"publisher":{"@type":"Organization","name":"MotoGo24","logo":{"@type":"ImageObject","url":"https://motogo24.cz/gfx/logo.svg"}}' . (!empty($post['created_at']) ? ',"datePublished":' . json_encode($post['created_at']) : '') . '}
  </script>';

renderPage($titleRaw . ' | Blog MotoGo24', $content, '/blog/' . $slug, [
    'description' => $excerpt ?: t('blog.detail.descFallback', ['title' => $titleRaw]),
    'og_type' => 'article',
    'og_image' => !empty($post['images'][0]) ? $post['images'][0] : (!empty($post['image_url']) ? $post['image_url'] : null),
    'schema' => $articleSchema,
    'breadcrumbs' => [['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'], ['name' => t('breadcrumb.blog'), 'url' => 'https://motogo24.cz/blog'], ['name' => $titleRaw, 'url' => 'https://motogo24.cz/blog/' . $slug]],
]);
