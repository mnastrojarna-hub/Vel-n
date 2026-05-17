<?php
// ===== MotoGo24 Web PHP — E-shop detail produktu =====

$sb = new SupabaseClient();
$id = $_GET['id'] ?? '';
$product = $sb->fetchProduct($id);

if (!$product || empty($product['is_active'])) {
    http_response_code(404);
    $content = '<main id="content"><div class="container">' .
        renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.shop'), 'href' => '/eshop'], t('shop.detail.notFoundHeading')]) .
        '<div class="ccontent"><h1>' . te('shop.detail.notFoundHeading') . '</h1>' .
        '<p><a class="btn btngreen" href="' . BASE_URL . '/eshop">' . te('shop.detail.backToShop') . '</a></p></div></div></main>';
    renderPage(t('shop.detail.notFoundTitle'), $content, '/eshop/' . htmlspecialchars($id), [
        'robots' => 'noindex,follow',
    ]);
    return;
}

// Lokalizované texty (auto-překlady z Velínu, fallback CZ)
$nameRaw  = trim((string)localized($product, 'name'));
if ($nameRaw === '') $nameRaw = t('shop.unnamedProduct');
$descRaw  = (string)localized($product, 'description');
$colorRaw = (string)localized($product, 'color');
$matRaw   = (string)localized($product, 'material');

$name = htmlspecialchars($nameRaw);
$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.shop'), 'href' => '/eshop'],
    $name,
]);

// Obrázky
$images = is_array($product['images'] ?? null) ? array_filter($product['images']) : [];
if (empty($images) && !empty($product['image_url'])) $images = [$product['image_url']];
$mainImgRaw = !empty($images[0]) ? $images[0] : '';
$mainImg = $mainImgRaw;
if ($mainImg && strpos($mainImg, 'http') !== 0 && strpos($mainImg, 'data:') !== 0 && strpos($mainImg, '/') !== 0) {
    $mainImg = imgUrl($mainImg);
}
// Pro zobrazení použijeme transformovanou verzi (~1000 px); pro Schema.org / OG
// zůstává $mainImg (plná object/public URL) — sociální boty si vezmou vlastní velikost.
$isShopMainLocal = $mainImgRaw && ((strpos($mainImgRaw, '/') === 0) || (strpos($mainImgRaw, 'http') === 0 && strpos($mainImgRaw, '/storage/v1/') === false));
$mainImgDisplay = ($mainImgRaw && !$isShopMainLocal) ? imgUrlSized($mainImgRaw, 1000) : $mainImg;
$mainImgSrcset = ($mainImgRaw && !$isShopMainLocal) ? imgSrcset($mainImgRaw, [600, 1000, 1400]) : '';

$galleryHtml = '';
if (!empty($images)) {
    $galleryHtml = '<div class="shop-gallery">';
    $openLabel = htmlspecialchars(t('gallery.openImage'), ENT_QUOTES, 'UTF-8');
    $idx = 0;
    foreach ($images as $img) {
        // Lokální /gfx/... a externí URL (mimo Supabase storage) nepřepisujeme.
        $isLocal = (strpos($img, '/') === 0) || (strpos($img, 'http') === 0 && strpos($img, '/storage/v1/') === false);
        if ($isLocal) {
            $thumb = $img; $full = $img; $thumbSrcset = '';
        } else {
            $thumb = imgUrlSized($img, 300);
            $thumbSrcset = imgSrcset($img, [200, 400, 600]);
            $full = imgUrlSized($img, 1400, 75);
        }
        $galleryHtml .= '<a href="' . htmlspecialchars($full) . '" data-gallery="shop" data-index="' . $idx . '" aria-label="' . $openLabel . '"><img src="' . htmlspecialchars($thumb) . '"'
            . ($thumbSrcset ? ' srcset="' . htmlspecialchars($thumbSrcset) . '" sizes="120px"' : '')
            . ' alt="' . htmlspecialchars(t('shop.productAlt', ['name' => $nameRaw])) . '" loading="lazy" decoding="async"></a>';
        $idx++;
    }
    $galleryHtml .= '</div>';
}

// Cena, sklad, velikosti
$price = isset($product['price']) ? (float)$product['price'] : 0;
$priceText = $price > 0 ? formatPrice($price) : '';
$stock = (int)($product['stock_quantity'] ?? 0);
$sku = trim((string)($product['sku'] ?? ''));
$sizes = is_array($product['sizes'] ?? null) ? array_filter($product['sizes']) : [];

// Specs (bez velikostí — ty jsou nyní interaktivní selector v CTA bloku)
$specsRows = [];
if ($colorRaw !== '') $specsRows[] = [t('shop.specColor'), $colorRaw];
if ($matRaw !== '')   $specsRows[] = [t('shop.specMaterial'), $matRaw];
if ($sku !== '')      $specsRows[] = [t('shop.specSku'), $sku];
$specsRows[] = [t('shop.specStock'), $stock > 0 ? t('shop.inStock', ['n' => $stock]) : t('shop.outOfStock')];

$specsHtml = '';
if (!empty($specsRows)) {
    $specsHtml = '<table class="shop-specs">';
    foreach ($specsRows as [$lbl, $val]) {
        $specsHtml .= '<tr><th>' . htmlspecialchars($lbl) . '</th><td>' . htmlspecialchars($val) . '</td></tr>';
    }
    $specsHtml .= '</table>';
}

// CTA blok — velikost (pokud produkt má sizes[]), množství, "Přidat do košíku".
// Výběr velikosti je povinný, když má produkt sizes[]; jinak je hidden.
$cartFormHtml = '';
if ($stock > 0) {
    $sizesPickerHtml = '';
    if (!empty($sizes)) {
        $sizesPickerHtml .= '<div class="shop-size-picker" data-shop-sizes>';
        $sizesPickerHtml .= '<label class="shop-size-label">' . te('shop.detail.chooseSize') . '</label>';
        $sizesPickerHtml .= '<div class="shop-size-chips" role="radiogroup" aria-label="' . te('shop.detail.chooseSize') . '">';
        foreach ($sizes as $sz) {
            $sizeEsc = htmlspecialchars((string)$sz, ENT_QUOTES, 'UTF-8');
            $sizesPickerHtml .= '<button type="button" class="shop-size-chip" data-size="' . $sizeEsc . '" role="radio" aria-checked="false">' . $sizeEsc . '</button>';
        }
        $sizesPickerHtml .= '</div>';
        $sizesPickerHtml .= '<p class="shop-size-error" data-shop-size-error hidden>' . te('shop.detail.sizeRequired') . '</p>';
        $sizesPickerHtml .= '</div>';
    }

    $maxQty = $stock > 0 ? min($stock, 99) : 1;
    $qtyHtml = '<div class="shop-qty-picker">'
        . '<label class="shop-qty-label" for="shop-qty-' . htmlspecialchars($id) . '">' . te('shop.detail.quantity') . '</label>'
        . '<div class="shop-qty-stepper">'
        . '<button type="button" class="shop-qty-btn" data-qty-step="-1" aria-label="' . te('shop.detail.qtyDecrease') . '">−</button>'
        . '<input type="number" id="shop-qty-' . htmlspecialchars($id) . '" class="shop-qty-input" data-shop-qty value="1" min="1" max="' . $maxQty . '" inputmode="numeric">'
        . '<button type="button" class="shop-qty-btn" data-qty-step="1" aria-label="' . te('shop.detail.qtyIncrease') . '">+</button>'
        . '</div>'
        . '</div>';

    $addBtnHtml = '<button type="button" class="btn btngreen shop-add-to-cart"'
        . ' data-shop-add'
        . ' data-product-id="' . htmlspecialchars($id) . '"'
        . ' data-product-name="' . htmlspecialchars($nameRaw, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-product-price="' . htmlspecialchars((string)$price, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-product-image="' . htmlspecialchars($mainImg ?: '', ENT_QUOTES, 'UTF-8') . '"'
        . ' data-product-stock="' . $stock . '"'
        . ' data-product-has-sizes="' . (!empty($sizes) ? '1' : '0') . '"'
        . '>' . te('shop.detail.addToCart') . '</button>';

    $cartFormHtml = '<form class="shop-cart-form" data-shop-form onsubmit="return false;">'
        . $sizesPickerHtml . $qtyHtml
        . '<p class="shop-cta">' . $addBtnHtml . '</p>'
        . '<p class="shop-cart-feedback" data-shop-feedback hidden></p>'
        . '</form>';
} else {
    $cartFormHtml = '<p class="shop-cta"><a class="btn btndark" href="' . BASE_URL . '/kontakt">' . te('shop.detail.notifyAvailable') . '</a></p>';
}

$descHtml = '';
if ($descRaw !== '') {
    $descHtml = '<div class="ccontent" style="margin-top:18px;"><h2>' . te('shop.detail.descTitle') . '</h2><p>' . nl2br(htmlspecialchars($descRaw)) . '</p></div>';
}

$leftCol = '<div class="shop-detail-media">'
    . ($mainImgDisplay ? '<img src="' . htmlspecialchars($mainImgDisplay) . '"'
        . ($mainImgSrcset ? ' srcset="' . htmlspecialchars($mainImgSrcset) . '" sizes="(max-width: 768px) 100vw, 50vw"' : '')
        . ' alt="' . htmlspecialchars(t('shop.productAlt', ['name' => $nameRaw])) . '" class="shop-main-img" fetchpriority="high" decoding="async">' : '')
    . $galleryHtml
    . '</div>';

$rightCol = '<div class="shop-detail-info">'
    . '<h1>' . $name . '</h1>'
    . ($priceText ? '<p class="shop-price">' . htmlspecialchars($priceText) . '</p>' : '')
    . $specsHtml
    . $cartFormHtml
    . '</div>';

// Sdílená SEO outro sekce (zobrazí se pod každým produktovým detailem) — Velín → Texty webu → E-shop detail
$shopDetailDefaults = [
    'outro' => [
        'title' => 'Nákup motorkářských doplňků u MotoGo24',
        'body1' => 'V e-shopu MotoGo24 najdete pečlivě vybrané <strong>motorkářské oblečení a doplňky</strong> v běžných i atypických velikostech. Sortiment doplňujeme podle potřeb našich zákazníků z půjčovny i pravidelných jezdců, kteří chtějí drobnosti od trika přes čepici až po reflexní kuklu pod helmu. Vše máme fyzicky skladem v půjčovně v Pelhřimově — můžete přijít, vyzkoušet velikost a odvézt si zboží na místě.',
        'body2' => 'Doručujeme po celé České republice — můžete si vybrat <strong>osobní vyzvednutí v půjčovně zdarma</strong>, doručení Zásilkovnou nebo Českou poštou. Po objednání obdržíte automatický potvrzovací e-mail a my zboží odešleme do druhého pracovního dne. Pokud něco potřebujete poradit (velikost, materiál, kombinace s motorkářskou výbavou), ozvěte se nám — odpovíme zpravidla do hodiny.',
    ],
];
$SDC = $sb->siteContent('eshop_detail', $shopDetailDefaults);
$shopDetailOutroT = $SDC['outro']['title'] ?? $shopDetailDefaults['outro']['title'];
$shopDetailOutroB1 = $SDC['outro']['body1'] ?? $shopDetailDefaults['outro']['body1'];
$shopDetailOutroB2 = $SDC['outro']['body2'] ?? $shopDetailDefaults['outro']['body2'];
$shopDetailOutroHtml = '<section class="shop-detail-outro">'
    . '<h2 data-cms-key="web.eshop_detail.outro.title">' . htmlspecialchars($shopDetailOutroT) . '</h2>'
    . '<p data-cms-key="web.eshop_detail.outro.body1">' . $shopDetailOutroB1 . '</p>'
    . '<p data-cms-key="web.eshop_detail.outro.body2">' . $shopDetailOutroB2 . '</p>'
    . '</section>';

$content = '<main id="content"><div class="container">' . $bc
    . '<article class="moto-detail shop-detail">'
    . '<section class="shop-detail-grid">'
    . $leftCol . $rightCol
    . '</section>'
    . $descHtml
    . $shopDetailOutroHtml
    . '</article></div></main>';

// Schema.org Product — kompletní data pro AI: brand, materiál, barva, velikosti,
// stav skladu, cena, currency. Aggregate rating se přidá globálně z reviews tabulky
// pokud existuje min. 3 recenze.
$productUrl = siteCanonicalUrl('/eshop/' . htmlspecialchars($id));
$schemaImages = [];
foreach ($images as $img) {
    $u = (strpos($img, 'http') === 0 || strpos($img, '/') === 0) ? $img : imgUrl($img);
    if ($u && !in_array($u, $schemaImages, true)) $schemaImages[] = $u;
}

$globalReviews = $sb->fetchPublicReviews(50);
$reviewAgg = '';
if (is_array($globalReviews) && count($globalReviews) >= 3) {
    $sum = 0; $n = 0;
    foreach ($globalReviews as $r) {
        $rt = (int)($r['rating'] ?? 0);
        if ($rt >= 1 && $rt <= 5) { $sum += $rt; $n++; }
    }
    if ($n >= 3) {
        $avg = round($sum / $n, 2);
        $reviewAgg = ',"aggregateRating":{"@type":"AggregateRating","ratingValue":' . $avg . ',"bestRating":5,"worstRating":1,"ratingCount":' . $n . ',"reviewCount":' . $n . '}';
    }
}

$additionalProps = [];
if ($colorRaw !== '')  $additionalProps[] = '{"@type":"PropertyValue","name":"Barva","value":' . json_encode($colorRaw, JSON_UNESCAPED_UNICODE) . '}';
if ($matRaw !== '')    $additionalProps[] = '{"@type":"PropertyValue","name":"Materiál","value":' . json_encode($matRaw, JSON_UNESCAPED_UNICODE) . '}';
if (!empty($sizes))    $additionalProps[] = '{"@type":"PropertyValue","name":"Dostupné velikosti","value":' . json_encode(implode(', ', $sizes), JSON_UNESCAPED_UNICODE) . '}';

$category = trim((string)($product['category'] ?? ''));

$productSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Product","name":' . json_encode($nameRaw, JSON_UNESCAPED_UNICODE) .
  ',"description":' . json_encode($descRaw !== '' ? $descRaw : $nameRaw, JSON_UNESCAPED_UNICODE) .
  ',"url":' . json_encode($productUrl) .
  (!empty($schemaImages) ? ',"image":' . json_encode($schemaImages) : '') .
  ($sku !== '' ? ',"sku":' . json_encode($sku) . ',"mpn":' . json_encode($sku) : '') .
  ($category !== '' ? ',"category":' . json_encode($category, JSON_UNESCAPED_UNICODE) : '') .
  ($colorRaw !== '' ? ',"color":' . json_encode($colorRaw, JSON_UNESCAPED_UNICODE) : '') .
  ($matRaw !== '' ? ',"material":' . json_encode($matRaw, JSON_UNESCAPED_UNICODE) : '') .
  (!empty($additionalProps) ? ',"additionalProperty":[' . implode(',', $additionalProps) . ']' : '') .
  ',"brand":{"@type":"Brand","name":"MotoGo24"}' .
  ($price > 0 ? ',"offers":{"@type":"Offer","priceCurrency":"CZK","price":' . json_encode($price) .
    ',"availability":' . json_encode($stock > 0 ? 'https://schema.org/InStock' : 'https://schema.org/OutOfStock') .
    ',"itemCondition":"https://schema.org/NewCondition"' .
    ',"priceValidUntil":' . json_encode(date('Y-m-d', strtotime('+1 year'))) .
    ',"seller":{"@type":"Organization","name":"MotoGo24","url":"https://www.motogo24.cz"}' .
    ',"url":' . json_encode($productUrl) . '}' : '') .
  $reviewAgg .
  '}
  </script>';

// SEO: Title kratsi suffix '| MotoGo24' misto plne 'E-shop MotoGo24 —
// motorkarske doplnky a merch'. Externi SEO hlasil 'Title too long' +
// 'Word repetition' kdyz produktovy nazev obsahuje 'MotoGo24' a suffix taky
// (Truckerka MotoGo24 | E-shop MotoGo24 -> dvojite MotoGo24). Krátký
// 'MotoGo24' suffix se vejde do 65 chars limit a brand neopakuje.
$suffix = (stripos($nameRaw, 'motogo') !== false) ? '| E-shop' : '| MotoGo24';
renderPage($nameRaw . ' ' . $suffix, $content, '/eshop/' . htmlspecialchars($id), [
    'description' => preg_replace('/\s+\S*$/u', '', mb_substr(preg_replace('/\s+/', ' ', strip_tags($descRaw !== '' ? $descRaw : $nameRaw)), 0, 155)),
    'og_type' => 'product',
    // SEO: og:image MAX 1200px / quality 85 (Facebook/Twitter optimal). Predtim
    // raw URL z Supabase = 3-5 MB jpg (Seobility 'Large file size' issue).
    'og_image' => $mainImgRaw ? imgUrlSized($mainImgRaw, 1200, 85) : null,
    'schema' => $productSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.shop'), 'url' => siteCanonicalUrl('/eshop')],
        ['name' => $nameRaw, 'url' => siteCanonicalUrl('/eshop/' . $id)],
    ],
]);
