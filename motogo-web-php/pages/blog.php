<?php
// ===== MotoGo24 Web PHP — Blog listing =====
// Odpovídá pages-blog.js
// Podpora GET parametru ?tag=X pro filtrování dle štítku

$sb = new SupabaseClient();
$activeTag = $_GET['tag'] ?? '';

// Načtení postů — pokud tag, filtrujeme na serveru
$posts = $activeTag ? $sb->fetchCmsPages($activeTag) : $sb->fetchCmsPages();
$allPosts = $sb->fetchCmsPages(); // pro počty v tag filtru
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Blog']);

// Fallback sample articles if CMS is empty
if (!$allPosts || empty($allPosts)) {
    $allPosts = [
        ['slug' => 'nove-motorky-v-nabidce', 'title' => 'Nové motorky v nabídce', 'excerpt' => 'Představujeme nové motorky na pronájem na Vysočině v naší půjčovně Motogo24. Objevte sportovní a cestovní modely pro vaše dobrodružství.', 'tags' => ['Novinky půjčovny'], 'image_url' => '', 'images' => []],
        ['slug' => 'top-motorkarske-trasy', 'title' => 'Top motorkářské trasy', 'excerpt' => 'Projeďte motorkářské trasy v ČR, jako je Český ráj nebo Krušné hory, s našimi motorkami k zapůjčení.', 'tags' => ['Motorkářské trasy'], 'image_url' => '', 'images' => []],
        ['slug' => 'tipy-pro-bezpecnou-jizdu', 'title' => 'Tipy pro bezpečnou jízdu', 'excerpt' => 'Zjistěte, jak si půjčit motorku na Vysočině a užít bezpečnou jízdu. Praktické rady pro začátečníky i zkušené jezdce.', 'tags' => ['Rady a tipy'], 'image_url' => '', 'images' => []],
    ];
    if (empty($posts)) $posts = $allPosts;
}

// Extract tags (z všech postů pro kompletní počty)
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
    $tagHtml = '<ul class="nav nav-pills df"><li>Štítky</li>' .
        '<li' . $isAllActive . '><a href="' . BASE_URL . '/blog">Všechny (' . count($allPosts) . ')</a></li>';
    foreach ($tagCounts as $tag => $count) {
        $isActive = ($activeTag === $tag) ? ' class="active"' : '';
        $tagHtml .= '<li' . $isActive . '><a href="' . BASE_URL . '/blog?tag=' . urlencode($tag) . '">' . htmlspecialchars($tag) . ' (' . $count . ')</a></li>';
    }
    $tagHtml .= '</ul>';
}

// Render posts
$gridHtml = '';
if (empty($posts)) {
    $gridHtml = '<p>Žádné články v této kategorii.</p>';
} else {
    foreach ($posts as $p) { $gridHtml .= renderBlogCard($p); }
}

$content = '<main id="content"><div class="container">' . $bc .
    '<section class="ccontent"><h1>Blog a tipy</h1>' .
    '<div id="blog-tags">' . $tagHtml . '</div>' .
    '<div class="tab-content"><div class="tab-pane active">' .
    '<div id="blog-grid" class="gr3">' . $gridHtml . '</div>' .
    '</div></div></section></div></main>';

renderPage('Blog – Motogo24', $content, '/blog');
