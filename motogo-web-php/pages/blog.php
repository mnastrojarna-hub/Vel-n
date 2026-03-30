<?php
// ===== MotoGo24 Web PHP — Blog (listing) =====

echo renderHead('Blog – tipy na motocyklové trasy a výlety | Motogo24', 'Blog o motocyklových trasách, výletech a tipech pro motorkáře. Objevte nejlepší trasy v Česku a na Vysočině.');
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], 'Blog']);

$posts = $sb->fetchCmsPages();

// Collect unique tags
$allTags = [];
foreach ($posts as $p) {
    if (!empty($p['tags']) && is_array($p['tags'])) {
        foreach ($p['tags'] as $tag) {
            if ($tag && !in_array($tag, $allTags)) {
                $allTags[] = $tag;
            }
        }
    }
}
sort($allTags);

// Tag filter buttons
$tagsHtml = '<div class="tags-filter">';
$tagsHtml .= '<button class="tag-btn active" data-tag="all">Vše</button>';
foreach ($allTags as $tag) {
    $tagsHtml .= '<button class="tag-btn" data-tag="' . e($tag) . '">' . e($tag) . '</button>';
}
$tagsHtml .= '</div>';

// Blog cards
$cardsHtml = '<div class="gr3 blog-grid">';
if (!empty($posts)) {
    foreach ($posts as $p) {
        $dataTags = '';
        if (!empty($p['tags']) && is_array($p['tags'])) {
            $dataTags = e(implode(',', $p['tags']));
        }
        $cardsHtml .= '<div class="blog-card-wrap" data-tags="' . $dataTags . '">' . renderBlogCard($p) . '</div>';
    }
} else {
    $cardsHtml .= '<p>Zatím nemáme žádné články.</p>';
}
$cardsHtml .= '</div>';

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Blog – tipy na motocyklové trasy a výlety</h1>' .
    '<p>Objevte nejlepší <strong>motocyklové trasy</strong>, tipy na <strong>výlety na motorce</strong> a novinky z naší <strong>půjčovny motorek na Vysočině</strong>.</p>' .
    '<p>&nbsp;</p>' .
    $tagsHtml .
    '<p>&nbsp;</p>' .
    $cardsHtml .
    '</div></div></main>';

echo renderFooter();
?>
<script>
document.querySelectorAll('.tag-btn[data-tag]').forEach(function(btn){
  btn.addEventListener('click', function(){
    var tag = btn.getAttribute('data-tag');
    document.querySelectorAll('.tag-btn').forEach(function(b){ b.classList.remove('active'); });
    btn.classList.add('active');
    document.querySelectorAll('.blog-card-wrap').forEach(function(card){
      if(tag === 'all'){
        card.style.display = '';
      } else {
        var tags = (card.getAttribute('data-tags') || '').split(',');
        card.style.display = tags.indexOf(tag) >= 0 ? '' : 'none';
      }
    });
  });
});
</script>
<?php
echo renderPageEnd();
