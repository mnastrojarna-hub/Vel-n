<?php
// ===== MotoGo24 Web PHP — Blog listing =====
// Podpora GET parametru ?tag=X pro filtrování dle štítku.
// Pokud DB cms_pages nemá záznamy, použijí se fallback články z blog_fallback.php.

$sb = new SupabaseClient();
$activeTag = $_GET['tag'] ?? '';

$posts = $activeTag ? $sb->fetchCmsPages($activeTag) : $sb->fetchCmsPages();
$allPosts = $sb->fetchCmsPages();
$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.blog')]);

// Fallback články (pokud cms_pages v DB prázdná). Plné články jsou v
// blog_fallback.php, kde si je načte i blog-detail.php pro single view.
if (!$allPosts || empty($allPosts)) {
    require_once __DIR__ . '/blog_fallback.php';
    $allPosts = getBlogFallbackPosts();
    if ($activeTag) {
        $posts = array_values(array_filter($allPosts, function ($p) use ($activeTag) {
            return !empty($p['tags']) && in_array($activeTag, $p['tags'], true);
        }));
    } else {
        $posts = $allPosts;
    }
}

$tagCounts = [];
foreach ($allPosts as $p) {
    if (!empty($p['tags'])) {
        foreach ($p['tags'] as $t) {
            $tagCounts[$t] = ($tagCounts[$t] ?? 0) + 1;
        }
    }
}

$tagHtml = '';
if (!empty($tagCounts)) {
    $isAllActive = !$activeTag ? ' class="active"' : '';
    $tagHtml = '<ul class="nav blog-tabs df">'
        . '<li' . $isAllActive . '><a href="' . BASE_URL . '/blog">' . htmlspecialchars(t('blog.tagAll', ['count' => count($allPosts)])) . '</a></li>';
    foreach ($tagCounts as $tag => $count) {
        $isActive = ($activeTag === $tag) ? ' class="active"' : '';
        $tagHtml .= '<li' . $isActive . '><a href="' . BASE_URL . '/blog?tag=' . urlencode($tag) . '">' . htmlspecialchars($tag) . ' (' . $count . ')</a></li>';
    }
    $tagHtml .= '</ul>';
}

$gridHtml = '';
if (empty($posts)) {
    $gridHtml = '<p>' . te('blog.empty') . '</p>';
} else {
    foreach ($posts as $p) { $gridHtml .= renderBlogCard($p); }
}

$content = '<main id="content"><div class="container">' . $bc
    . '<section class="ccontent"><h1>' . te('blog.h1') . '</h1>'
    . '<div id="blog-tags">' . $tagHtml . '</div>'
    . '<div class="tab-content"><div class="tab-pane active">'
    . '<div id="blog-grid" class="gr3">' . $gridHtml . '</div>'
    . '</div></div></section></div></main>';

renderPage(t('blog.title'), $content, '/blog', [
    'description' => t('blog.description'),
    'keywords' => t('blog.keywords'),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.blog'), 'url' => 'https://motogo24.cz/blog'],
    ],
]);
