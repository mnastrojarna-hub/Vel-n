<?php
// ===== MotoGo24 Web PHP — Blog listing =====
// Odpovídá pages-blog.js

$sb = new SupabaseClient();
$posts = $sb->fetchCmsPages();
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Blog']);

// Fallback sample articles if CMS is empty
if (!$posts || empty($posts)) {
    $posts = [
        ['slug' => 'nove-motorky-v-nabidce', 'title' => 'Nové motorky v nabídce', 'excerpt' => 'Představujeme nové motorky na pronájem na Vysočině v naší půjčovně Motogo24. Objevte sportovní a cestovní modely pro vaše dobrodružství.', 'tags' => ['Novinky půjčovny'], 'image_url' => '', 'images' => []],
        ['slug' => 'top-motorkarske-trasy', 'title' => 'Top motorkářské trasy', 'excerpt' => 'Projeďte motorkářské trasy v ČR, jako je Český ráj nebo Krušné hory, s našimi motorkami k zapůjčení.', 'tags' => ['Motorkářské trasy'], 'image_url' => '', 'images' => []],
        ['slug' => 'tipy-pro-bezpecnou-jizdu', 'title' => 'Tipy pro bezpečnou jízdu', 'excerpt' => 'Zjistěte, jak si půjčit motorku na Vysočině a užít bezpečnou jízdu. Praktické rady pro začátečníky i zkušené jezdce.', 'tags' => ['Rady a tipy'], 'image_url' => '', 'images' => []],
    ];
}

// Extract tags
$tagCounts = [];
foreach ($posts as $p) {
    if (!empty($p['tags'])) {
        foreach ($p['tags'] as $t) {
            $tagCounts[$t] = ($tagCounts[$t] ?? 0) + 1;
        }
    }
}

$tagHtml = '';
if (!empty($tagCounts)) {
    $tagHtml = '<ul class="nav nav-pills df"><li>Štítky</li>' .
        '<li class="active"><a href="#" data-blog-tag="">Všechny (' . count($posts) . ')</a></li>';
    foreach ($tagCounts as $tag => $count) {
        $tagHtml .= '<li><a href="#" data-blog-tag="' . htmlspecialchars($tag) . '">' . htmlspecialchars($tag) . ' (' . $count . ')</a></li>';
    }
    $tagHtml .= '</ul>';
}

// Render all posts
$gridHtml = '';
if (empty($posts)) {
    $gridHtml = '<p>Žádné články v této kategorii.</p>';
} else {
    foreach ($posts as $p) { $gridHtml .= renderBlogCard($p); }
}

// Tag filtering JS
$tagJs = '<script>
document.querySelectorAll("[data-blog-tag]").forEach(function(a){
  a.addEventListener("click", function(e){
    e.preventDefault();
    var tag = a.getAttribute("data-blog-tag");
    document.querySelectorAll("[data-blog-tag]").forEach(function(el){ el.parentElement.classList.remove("active"); });
    a.parentElement.classList.add("active");
    document.querySelectorAll("#blog-grid > div").forEach(function(card){
      if(!tag){ card.style.display=""; return; }
      var tagEl = card.querySelector(".tag-label");
      var cardTag = tagEl ? tagEl.textContent : "";
      card.style.display = (cardTag === tag) ? "" : "none";
    });
  });
});
</script>';

$content = '<main id="content"><div class="container">' . $bc .
    '<section class="ccontent"><h1>Blog a tipy</h1>' .
    '<div id="blog-tags">' . $tagHtml . '</div>' .
    '<div class="tab-content"><div class="tab-pane active">' .
    '<div id="blog-grid" class="gr3">' . $gridHtml . '</div>' .
    '</div></div></section></div></main>' . $tagJs;

renderPage('Blog – Motogo24', $content, '/blog');
