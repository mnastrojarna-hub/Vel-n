<?php
// ===== MotoGo24 Web PHP — Blog listing =====
// Podpora GET parametru ?tag=X pro filtrování dle štítku.
// Pokud DB cms_pages nemá záznamy, použijí se fallback články z blog_fallback.php.

$sb = new SupabaseClient();
$activeTag = $_GET['tag'] ?? '';

$posts = $activeTag ? $sb->fetchCmsPages($activeTag) : $sb->fetchCmsPages();
$allPosts = $sb->fetchCmsPages();
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Blog']);

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
    $tagHtml = '<ul class="nav nav-pills df"><li>Štítky</li>'
        . '<li' . $isAllActive . '><a href="' . BASE_URL . '/blog">Všechny (' . count($allPosts) . ')</a></li>';
    foreach ($tagCounts as $tag => $count) {
        $isActive = ($activeTag === $tag) ? ' class="active"' : '';
        $tagHtml .= '<li' . $isActive . '><a href="' . BASE_URL . '/blog?tag=' . urlencode($tag) . '">' . htmlspecialchars($tag) . ' (' . $count . ')</a></li>';
    }
    $tagHtml .= '</ul>';
}

$gridHtml = '';
if (empty($posts)) {
    $gridHtml = '<p>Žádné články v této kategorii.</p>';
} else {
    foreach ($posts as $p) { $gridHtml .= renderBlogCard($p); }
}

$intro = '<p>Tipy na <strong>motorkářské trasy</strong>, rady pro bezpečnou jízdu, novinky z naší <strong>půjčovny motorek na Vysočině</strong> i praktické postupy pro začátečníky i zkušené jezdce.</p>';

$content = '<main id="content"><div class="container">' . $bc
    . '<section class="ccontent"><h1>Blog a tipy pro motorkáře</h1>' . $intro
    . '<div id="blog-tags">' . $tagHtml . '</div>'
    . '<div class="tab-content"><div class="tab-pane active">'
    . '<div id="blog-grid" class="gr3">' . $gridHtml . '</div>'
    . '</div></div></section></div></main>';

renderPage('Blog a tipy pro motorkáře | MotoGo24', $content, '/blog', [
    'description' => 'Blog Motogo24 – tipy na motorkářské trasy na Vysočině i v ČR, novinky z půjčovny, rady pro bezpečnou jízdu a praktické postupy.',
    'keywords' => 'motorkářský blog, trasy na motorku, tipy pro motorkáře, novinky půjčovna motorek, Vysočina, Český ráj',
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Blog', 'url' => 'https://motogo24.cz/blog'],
    ],
]);
