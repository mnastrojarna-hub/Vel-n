<?php
// ===== MotoGo24 Web PHP — FAQ stránka s taby (CMS-driven) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/casto-kladene-dotazy
// Obsah rozdelen do 3 souboru v /data/ kvuli pravidlu max 5000 tokenu na soubor.

$sb = new SupabaseClient();

// Slozeni defaults z 3 datasetu
$part1 = require __DIR__ . '/../data/faq-content-1.php';
$part2 = require __DIR__ . '/../data/faq-content-2.php';
$part3 = require __DIR__ . '/../data/faq-content-3.php';

$meta = $part3['__meta'];
unset($part3['__meta']);

$categories = [];
foreach ([$part1, $part2, $part3] as $part) {
    foreach ($part as $catKey => $catData) {
        if (!isset($categories[$catKey])) {
            $categories[$catKey] = ['label' => $catData['label'], 'items' => []];
        }
        $categories[$catKey]['items'] = array_merge($categories[$catKey]['items'], $catData['items']);
    }
}

$defaults = [
    'seo' => $meta['seo'],
    'h1' => $meta['h1'],
    'closing' => $meta['closing'],
    'cta' => $meta['cta'],
    'categories' => $categories,
];

$C = $sb->siteContent('faq', $defaults);

// Postprocess: link expand + aggregate
$allItems = [];
$cats = $C['categories'];
foreach ($cats as $k => &$cat) {
    foreach ($cat['items'] as &$it) {
        // relative href → BASE_URL prefix
        $it['a'] = preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $it['a']);
    }
    unset($it);
    $allItems = array_merge($allItems, $cat['items']);
}
unset($cat);

$tabs = [['id' => 'all', 'label' => t('faq.tabAll', ['count' => count($allItems)]), 'items' => $allItems]];
foreach ($cats as $id => $cat) {
    $tabs[] = ['id' => $id, 'label' => $cat['label'] . ' (' . count($cat['items']) . ')', 'items' => $cat['items']];
}

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'], t('menu.howto.faq')]);

$tabsHtml = '<ul class="tabs">';
foreach ($tabs as $t) {
    $tabsHtml .= '<li><a class="tab' . ($t['id'] === 'all' ? ' active' : '') . '" href="#' . htmlspecialchars($t['id']) . '" data-tab="' . htmlspecialchars($t['id']) . '">' . htmlspecialchars($t['label']) . '</a></li>';
}
$tabsHtml .= '</ul>';

$panesHtml = '<div class="tab-content">';
foreach ($tabs as $t) {
    $panesHtml .= '<div class="tab-pane' . ($t['id'] === 'all' ? ' active' : '') . '" id="' . htmlspecialchars($t['id']) . '"><div class="gr2">';
    foreach ($t['items'] as $faq) {
        $panesHtml .= renderFaqItem($faq['q'], $faq['a']);
    }
    $panesHtml .= '</div></div>';
}
$panesHtml .= '</div>';

$tabJs = '<script>
document.querySelectorAll(".tab[data-tab]").forEach(function(t){
  t.addEventListener("click", function(e){
    e.preventDefault();
    var tabId = t.getAttribute("data-tab");
    document.querySelectorAll(".tab").forEach(function(el){ el.classList.remove("active"); });
    document.querySelectorAll(".tab-pane").forEach(function(el){ el.classList.remove("active"); });
    t.classList.add("active");
    var pane = document.getElementById(tabId);
    if(pane) pane.classList.add("active");
  });
});
</script>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . htmlspecialchars($C['h1']) . '</h1>' .
    $tabsHtml . $panesHtml .
    '<p>&nbsp;</p><p>' . $C['closing'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['cta']['href'] . '">' . htmlspecialchars($C['cta']['label']) . '</a></p>' .
    '</div></div></main>' . $tabJs;

// FAQPage schema
$faqSchemaItems = [];
foreach ($allItems as $faq) {
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/faq', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.howto'), 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => t('menu.howto.faq'), 'url' => 'https://motogo24.cz/jak-pujcit/faq'],
    ],
]);
