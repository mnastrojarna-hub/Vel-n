<?php
// ===== MotoGo24 Web PHP — E-shop (výpis produktů) =====
// Texty produktů se automaticky překládají z Velínu přes edge funkci
// `translate-content` (Anthropic) do JSONB sloupce `products.translations`.
// PHP čte přes helper `localized()` s CZ fallbackem.

$sb = new SupabaseClient();
$products = $sb->fetchProducts();

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.shop')]);

$gridHtml = '';
if (empty($products)) {
    $gridHtml = '<p>' . te('shop.empty') . '</p>';
} else {
    foreach ($products as $p) { $gridHtml .= renderProductCard($p); }
}

$content = '<main id="content"><div class="container">' . $bc
    . '<section class="ccontent"><h1>' . te('shop.h1') . '</h1>'
    . '<p>' . te('shop.intro') . '</p>'
    . '<div id="shop-grid" class="gr3">' . $gridHtml . '</div>'
    . '</section></div></main>';

// ItemList JSON-LD pro AI agenty / Google rich results
$listItems = [];
$pos = 0;
foreach ((is_array($products) ? $products : []) as $p) {
    if (empty($p['id'])) continue;
    $pos++;
    $pname = (string)localized($p, 'name');
    if ($pname === '') $pname = (string)($p['name'] ?? '');
    $listItems[] = '{"@type":"ListItem","position":' . $pos
        . ',"url":"https://motogo24.cz/eshop/' . htmlspecialchars($p['id']) . '"'
        . ',"name":' . json_encode($pname, JSON_UNESCAPED_UNICODE)
        . '}';
    if ($pos >= 50) break;
}
$itemListSchema = '';
if (!empty($listItems)) {
    $itemListSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"ItemList","name":"E-shop motorkářské výbavy MotoGo24","numberOfItems":' . count($products) . ',"itemListElement":[' . implode(',', $listItems) . ']}
  </script>';
}

renderPage(t('shop.title'), $content, '/eshop', [
    'description' => t('shop.description'),
    'keywords' => t('shop.keywords'),
    'schema' => $itemListSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.shop'), 'url' => 'https://motogo24.cz/eshop'],
    ],
]);
