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
    http_response_code(404);
    $content = '<main id="content"><div class="container">' .
        renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.blog'), 'href' => '/blog'], t('blog.detail.notFoundHeading')]) .
        '<div class="ccontent"><h1>' . te('blog.detail.notFoundHeading') . '</h1><p><a class="btn btngreen" href="' . BASE_URL . '/blog">' . te('blog.detail.backToBlog') . '</a></p></div></div></main>';
    renderPage(t('blog.detail.notFoundTitle'), $content, '/blog/' . htmlspecialchars($slug), [
        'robots' => 'noindex,follow',
    ]);
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
$openLabel = htmlspecialchars(t('gallery.openImage'), ENT_QUOTES, 'UTF-8');
// SEO: per-image alt z `image_alts[i]` (paralelní pole, plní admin ve Velíně
// BlogWizard). Pokud prázdný → fallback na titulek článku (původní chování).
$postImageAlts = is_array($post['image_alts'] ?? null) ? $post['image_alts'] : [];
$composeBlogAlt = function (string $desc) use ($titleRaw) {
    $desc = trim($desc);
    if ($desc === '') return htmlspecialchars($titleRaw, ENT_QUOTES, 'UTF-8');
    return htmlspecialchars(trim($titleRaw) . ' – ' . $desc, ENT_QUOTES, 'UTF-8');
};
if (!empty($post['images']) && count($post['images']) > 0) {
    $galleryHtml = '<section><div class="gallery-blog">';
    $idx = 0;
    foreach ($post['images'] as $img) {
        $imgAlt = $composeBlogAlt((string)($postImageAlts[$idx] ?? ''));
        $galleryHtml .= '<div class="col-lg-3 col-md-4 col-sm-6">' .
            '<a href="' . htmlspecialchars($img) . '" data-gallery="blog" data-index="' . $idx . '" aria-label="' . $openLabel . '"><div class="gallery-background"><div class="gallery-box">' .
            '<img src="' . htmlspecialchars($img) . '" alt="' . $imgAlt . '" loading="lazy"></div></div></a></div>';
        $idx++;
    }
    $galleryHtml .= '</div></section>';
} elseif (!empty($post['image_url'])) {
    $imgAlt = $composeBlogAlt((string)($postImageAlts[0] ?? ''));
    $galleryHtml = '<section><div class="gallery-blog">' .
        '<div class="col-lg-3 col-md-4 col-sm-6"><a href="' . htmlspecialchars($post['image_url']) . '" data-gallery="blog" data-index="0" aria-label="' . $openLabel . '"><div class="gallery-background"><div class="gallery-box">' .
        '<img src="' . htmlspecialchars($post['image_url']) . '" alt="' . $imgAlt . '" loading="lazy"></div></div></a></div></div></section>';
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

// ===== Article schema — kompletní pro AI Overviews / Discover / Perplexity / Seznam Zprávy =====
// @type zahrnuje "NewsArticle" — Seznam Zprávy a Google News News tab články
// chytí podle tohoto typu. Multi-type podle schema.org spec.
$articleUrl = siteCanonicalUrl('/blog/' . $slug);
// Origin pro logo — preferujeme český origin (NAP konzistence pro Seznam)
$brandOrigin = i18nOriginForLang('cs');
$schemaImages = [];
if (!empty($post['images']) && is_array($post['images'])) {
    foreach ($post['images'] as $img) {
        if (!empty($img)) $schemaImages[] = $img;
    }
}
if (empty($schemaImages) && !empty($post['image_url'])) $schemaImages[] = $post['image_url'];
if (empty($schemaImages)) $schemaImages[] = $brandOrigin . '/gfx/hero-banner.jpg';

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
  {"@context":"https://schema.org","@type":["Article","BlogPosting","NewsArticle"]'
    . ',"headline":' . json_encode($titleRaw, JSON_UNESCAPED_UNICODE)
    . ',"description":' . json_encode($excerpt !== '' ? $excerpt : $titleRaw, JSON_UNESCAPED_UNICODE)
    . ',"image":' . json_encode($schemaImages)
    . ',"url":' . json_encode($articleUrl)
    . ',"mainEntityOfPage":{"@type":"WebPage","@id":' . json_encode($articleUrl) . '}'
    . ',"author":{"@type":"Organization","name":"MotoGo24","url":' . json_encode($brandOrigin) . '}'
    . ',"publisher":{"@type":"Organization","name":"MotoGo24","logo":{"@type":"ImageObject","url":' . json_encode($brandOrigin . '/gfx/logo.svg') . ',"width":512,"height":512}}'
    . ($datePublished ? ',"datePublished":' . json_encode($datePublished) : '')
    . ($dateModified  ? ',"dateModified":'  . json_encode($dateModified)  : '')
    . ($wordCount > 0 ? ',"wordCount":' . $wordCount : '')
    . ($articleBodyText !== '' ? ',"articleBody":' . json_encode($articleBodyText, JSON_UNESCAPED_UNICODE) : '')
    . ',"inLanguage":' . json_encode(i18nHtmlLang())
    . ',"isAccessibleForFree":true'
    . '}
  </script>';

// Suffix u dlouhych titulku zkracujeme z " | Blog MotoGo24" (15 znaku) na
// " | MotoGo24" (11 znaku) — usetri ~30 px a vejde se pod 580 px limit.
$titleSuffix = mb_strlen($titleRaw) > 45 ? ' | MotoGo24' : ' | Blog MotoGo24';
renderPage($titleRaw . $titleSuffix, $content, '/blog/' . $slug, [
    'description' => $excerpt ?: t('blog.detail.descFallback', ['title' => $titleRaw]),
    'og_type' => 'article',
    // SEO: og:image MAX 1200px / quality 85 — predejde 'Large file size' issue.
    'og_image' => (function () use ($post) {
        $raw = !empty($post['images'][0]) ? $post['images'][0] : (!empty($post['image_url']) ? $post['image_url'] : null);
        return $raw ? imgUrlSized($raw, 1200, 85) : null;
    })(),
    'schema' => $articleSchema,
    'breadcrumbs' => [['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')], ['name' => t('breadcrumb.blog'), 'url' => siteCanonicalUrl('/blog')], ['name' => $titleRaw, 'url' => siteCanonicalUrl('/blog/') . $slug]],
]);
