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

// CMS-editable outro pod gridem (Velín → CMS → Texty webu → Blog)
$blogDefaults = [
    'outro' => [
        'title' => 'O našem blogu',
        'body1' => 'Na blogu MotoGo24 najdete tipy pro motorkáře, recenze našich strojů, rady jak si vybrat <strong>správnou motorku k pronájmu</strong> a inspiraci na trasy po Vysočině i celé České republice. Pravidelně přidáváme články o dárkových poukazech, údržbě motorek i o tom, jak <strong>půjčit motorku bez kauce</strong> a co všechno je v ceně nájmu zahrnuto.',
        'body2' => 'Pokud hledáte praktické informace o mototuristice, výbavě nebo o tom, jak to funguje v naší půjčovně, jste na správném místě. Máte téma, které by vás zajímalo? <a href="/kontakt">Napište nám</a> a rádi se mu věnujeme v dalším článku.',
    ],
];
$BC = $sb->siteContent('blog', $blogDefaults);
$outroT = $BC['outro']['title'] ?? $blogDefaults['outro']['title'];
$outroB1 = $BC['outro']['body1'] ?? $blogDefaults['outro']['body1'];
$outroB2 = $BC['outro']['body2'] ?? $blogDefaults['outro']['body2'];
$outroHtml = '<section class="blog-outro">'
    . '<h2 data-cms-key="web.blog.outro.title">' . sanitizeHtml($outroT) . '</h2>'
    . '<p data-cms-key="web.blog.outro.body1">' . sanitizeHtml($outroB1) . '</p>'
    . '<p data-cms-key="web.blog.outro.body2">' . sanitizeHtml($outroB2) . '</p>'
    . '</section>';

// Větší mezera mezi posledním článkem v mřížce a nadpisem "O našem blogu".
$pageStyle = '<style>.blog-outro{margin-top:3rem}</style>';

$content = '<main id="content"><div class="container">' . $bc
    . '<section class="ccontent"><h1>' . te('blog.h1') . '</h1>'
    . '<div id="blog-tags">' . $tagHtml . '</div>'
    . '<div class="tab-content"><div class="tab-pane active">'
    . '<div id="blog-grid" class="gr3">' . $gridHtml . '</div>'
    . '</div></div>'
    . $outroHtml
    . '</section></div></main>' . $pageStyle;

renderPage(t('blog.title'), $content, '/blog', [
    'description' => t('blog.description'),
    'keywords' => t('blog.keywords'),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.blog'), 'url' => siteCanonicalUrl('/blog')],
    ],
]);
