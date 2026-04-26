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

// ===== Article schema — kompletní pro AI Overviews / Discover / Perplexity =====
$articleUrl = 'https://motogo24.cz/blog/' . htmlspecialchars($slug);
$schemaImages = [];
if (!empty($post['images']) && is_array($post['images'])) {
    foreach ($post['images'] as $img) {
        if (!empty($img)) $schemaImages[] = $img;
    }
}
if (empty($schemaImages) && !empty($post['image_url'])) $schemaImages[] = $post['image_url'];
if (empty($schemaImages)) $schemaImages[] = 'https://motogo24.cz/gfx/hero-banner.jpg';

// articleBody — striputj HTML a vezmi prvních ~5000 znaků (rich snippet limit)
$articleBodyText = trim(strip_tags($contentRaw));
if (mb_strlen($articleBodyText) > 5000) {
    $articleBodyText = mb_substr($articleBodyText, 0, 4997) . '...';
}

$wordCount = $articleBodyText !== '' ? str_word_count($articleBodyText) : 0;

$datePublished = $post['created_at'] ?? null;
$dateModified  = $post['updated_at'] ?? $datePublished;

$articleSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":["Article","BlogPosting"]'
    . ',"headline":' . json_encode($titleRaw, JSON_UNESCAPED_UNICODE)
    . ',"description":' . json_encode($excerpt !== '' ? $excerpt : $titleRaw, JSON_UNESCAPED_UNICODE)
    . ',"image":' . json_encode($schemaImages)
    . ',"url":' . json_encode($articleUrl)
    . ',"mainEntityOfPage":{"@type":"WebPage","@id":' . json_encode($articleUrl) . '}'
    . ',"author":{"@type":"Organization","name":"MotoGo24","url":"https://motogo24.cz"}'
    . ',"publisher":{"@type":"Organization","name":"MotoGo24","logo":{"@type":"ImageObject","url":"https://motogo24.cz/gfx/logo.svg","width":512,"height":512}}'
    . ($datePublished ? ',"datePublished":' . json_encode($datePublished) : '')
    . ($dateModified  ? ',"dateModified":'  . json_encode($dateModified)  : '')
    . ($wordCount > 0 ? ',"wordCount":' . $wordCount : '')
    . ($articleBodyText !== '' ? ',"articleBody":' . json_encode($articleBodyText, JSON_UNESCAPED_UNICODE) : '')
    . ',"inLanguage":' . json_encode(i18nHtmlLang())
    . ',"isAccessibleForFree":true'
    . '}
  </script>';

renderPage($titleRaw . ' | Blog MotoGo24', $content, '/blog/' . $slug, [
    'description' => $excerpt ?: t('blog.detail.descFallback', ['title' => $titleRaw]),
    'og_type' => 'article',
    'og_image' => !empty($post['images'][0]) ? $post['images'][0] : (!empty($post['image_url']) ? $post['image_url'] : null),
    'schema' => $articleSchema,
    'breadcrumbs' => [['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'], ['name' => t('breadcrumb.blog'), 'url' => 'https://motogo24.cz/blog'], ['name' => $titleRaw, 'url' => 'https://motogo24.cz/blog/' . $slug]],
]);
