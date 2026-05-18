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

// CMS-editable outro pod gridem (Velín → CMS → Texty webu → E-shop)
$shopDefaults = [
    'outro' => [
        'title' => 'Motorkářské doplňky pro každého jezdce',
        'body1' => 'V e-shopu MotoGo24 najdete <strong>motorkářské doplňky</strong>, oblečení a merchandise, který se hodí na cesty i do města. Sortiment průběžně doplňujeme — od trik, čepic a kuklí přes reflexní prvky až po praktické drobnosti, které využijete při každé jízdě. Většinu zboží máme skladem v půjčovně v Pelhřimově a expedujeme do druhého pracovního dne.',
        'body2' => 'Doručujeme po celé České republice — můžete si vybrat <strong>osobní vyzvednutí v půjčovně</strong>, doručení Zásilkovnou nebo Českou poštou. Platba probíhá online přes platební bránu. Pokud něco hledáte a v nabídce to nevidíte, ozvěte se nám telefonicky nebo e-mailem — rádi poradíme s výběrem nebo doporučíme alternativu.',
    ],
];
$SC = $sb->siteContent('eshop', $shopDefaults);
$shopOutroT = $SC['outro']['title'] ?? $shopDefaults['outro']['title'];
$shopOutroB1 = $SC['outro']['body1'] ?? $shopDefaults['outro']['body1'];
$shopOutroB2 = $SC['outro']['body2'] ?? $shopDefaults['outro']['body2'];
$shopOutroHtml = '<section class="shop-outro">'
    . '<h2 data-cms-key="web.eshop.outro.title">' . sanitizeHtml($shopOutroT) . '</h2>'
    . '<p data-cms-key="web.eshop.outro.body1">' . sanitizeHtml($shopOutroB1) . '</p>'
    . '<p data-cms-key="web.eshop.outro.body2">' . sanitizeHtml($shopOutroB2) . '</p>'
    . '</section>';

$content = '<main id="content"><div class="container">' . $bc
    . '<section class="ccontent"><h1>' . te('shop.h1') . '</h1>'
    . '<p>' . te('shop.intro') . '</p>'
    . '<div id="shop-grid" class="gr3">' . $gridHtml . '</div>'
    . $shopOutroHtml
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
        . ',"url":' . json_encode(siteCanonicalUrl('/eshop/' . $p['id']), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)
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
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.shop'), 'url' => siteCanonicalUrl('/eshop')],
    ],
]);
