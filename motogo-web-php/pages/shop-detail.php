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
    renderPage(t('shop.detail.notFoundTitle'), $content, '/eshop/' . htmlspecialchars($id));
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
$mainImg = !empty($images[0]) ? $images[0] : '';
if ($mainImg && strpos($mainImg, 'http') !== 0 && strpos($mainImg, 'data:') !== 0 && strpos($mainImg, '/') !== 0) {
    $mainImg = imgUrl($mainImg);
}

$galleryHtml = '';
if (!empty($images)) {
    $galleryHtml = '<div class="shop-gallery" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:14px;">';
    foreach ($images as $img) {
        $u = (strpos($img, 'http') === 0 || strpos($img, '/') === 0) ? $img : imgUrl($img);
        $galleryHtml .= '<a href="' . htmlspecialchars($u) . '" target="_blank" rel="noopener"><img src="' . htmlspecialchars($u) . '" alt="' . htmlspecialchars(t('shop.productAlt', ['name' => $nameRaw])) . '" loading="lazy" style="width:100%;height:auto;border-radius:12px;border:1px solid #d4e8e0;"></a>';
    }
    $galleryHtml .= '</div>';
}

// Cena, sklad, velikosti
$price = isset($product['price']) ? (float)$product['price'] : 0;
$priceText = $price > 0 ? formatPrice($price) : '';
$stock = (int)($product['stock_quantity'] ?? 0);
$sku = trim((string)($product['sku'] ?? ''));
$sizes = is_array($product['sizes'] ?? null) ? array_filter($product['sizes']) : [];

$specsRows = [];
if ($colorRaw !== '') $specsRows[] = [t('shop.specColor'), $colorRaw];
if ($matRaw !== '')   $specsRows[] = [t('shop.specMaterial'), $matRaw];
if (!empty($sizes))   $specsRows[] = [t('shop.specSizes'), implode(', ', $sizes)];
if ($sku !== '')      $specsRows[] = [t('shop.specSku'), $sku];
$specsRows[] = [t('shop.specStock'), $stock > 0 ? t('shop.inStock', ['n' => $stock]) : t('shop.outOfStock')];

$specsHtml = '';
if (!empty($specsRows)) {
    $specsHtml = '<table class="moto-specs" style="margin-top:14px;width:100%;border-collapse:collapse;">';
    foreach ($specsRows as [$lbl, $val]) {
        $specsHtml .= '<tr><th style="text-align:left;padding:8px 12px;border-bottom:1px solid #d4e8e0;font-weight:700;color:#1a2e22;">' . htmlspecialchars($lbl) . '</th><td style="padding:8px 12px;border-bottom:1px solid #d4e8e0;color:#0f1a14;">' . htmlspecialchars($val) . '</td></tr>';
    }
    $specsHtml .= '</table>';
}

// CTA — kontakt (rozsáhlejší shop checkout je samostatný task)
$mailtoSubject = rawurlencode(t('shop.detail.inquirySubject', ['name' => $nameRaw]));
$mailtoBody = rawurlencode(t('shop.detail.inquiryBody', ['name' => $nameRaw, 'price' => $priceText ?: '—', 'sku' => $sku ?: '—']));
$ctaButtons = $stock > 0
    ? '<a class="btn btngreen" href="mailto:info@motogo24.cz?subject=' . $mailtoSubject . '&body=' . $mailtoBody . '">' . te('shop.detail.buy') . '</a>'
    : '<a class="btn btndark" href="' . BASE_URL . '/kontakt">' . te('shop.detail.notifyAvailable') . '</a>';

$descHtml = '';
if ($descRaw !== '') {
    $descHtml = '<div class="ccontent" style="margin-top:18px;"><h2>' . te('shop.detail.descTitle') . '</h2><p>' . nl2br(htmlspecialchars($descRaw)) . '</p></div>';
}

$leftCol = '<div>'
    . ($mainImg ? '<img src="' . htmlspecialchars($mainImg) . '" alt="' . htmlspecialchars(t('shop.productAlt', ['name' => $nameRaw])) . '" style="width:100%;height:auto;border-radius:12px;border:1px solid #d4e8e0;" loading="lazy">' : '')
    . $galleryHtml
    . '</div>';

$rightCol = '<div>'
    . '<h1>' . $name . '</h1>'
    . ($priceText ? '<p style="font-size:24px;font-weight:800;color:#1a2e22;">' . htmlspecialchars($priceText) . '</p>' : '')
    . $specsHtml
    . '<p style="margin-top:18px;">' . $ctaButtons . '</p>'
    . '</div>';

$content = '<main id="content"><div class="container">' . $bc
    . '<article class="moto-detail">'
    . '<section class="gr2" style="display:grid;grid-template-columns:1fr 1fr;gap:24px;align-items:start;">'
    . $leftCol . $rightCol
    . '</section>'
    . $descHtml
    . '</article></div></main>';

// Schema.org Product — kompletní data pro AI: brand, materiál, barva, velikosti,
// stav skladu, cena, currency. Aggregate rating se přidá globálně z reviews tabulky
// pokud existuje min. 3 recenze.
$productUrl = 'https://motogo24.cz/eshop/' . htmlspecialchars($id);
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
    ',"seller":{"@type":"Organization","name":"MotoGo24","url":"https://motogo24.cz"}' .
    ',"url":' . json_encode($productUrl) . '}' : '') .
  $reviewAgg .
  '}
  </script>';

renderPage($nameRaw . ' | ' . t('shop.title'), $content, '/eshop/' . htmlspecialchars($id), [
    'description' => mb_substr(strip_tags($descRaw !== '' ? $descRaw : $nameRaw), 0, 160),
    'og_type' => 'product',
    'og_image' => $mainImg ?: null,
    'schema' => $productSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.shop'), 'url' => 'https://motogo24.cz/eshop'],
        ['name' => $nameRaw, 'url' => 'https://motogo24.cz/eshop/' . $id],
    ],
]);
