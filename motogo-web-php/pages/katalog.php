<?php
// ===== MotoGo24 Web PHP — Katalog motorek s rozšířenými filtry =====
// Filtry přes GET: ?kategorie, ?ridicak, ?kw_min, ?cena_max, ?abs, ?jezdci, ?q, ?sort

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$category = null;
$title = t('menu.catalog');

if ($path === '/katalog/cestovni') {
    $category = 'cestovni';
    $title = t('menu.catalog.touring');
} elseif ($path === '/katalog/naked') {
    $category = 'naked';
    $title = t('menu.catalog.naked');
} elseif ($path === '/katalog/supermoto') {
    $category = 'supermoto';
    $title = t('menu.catalog.supermoto');
} elseif ($path === '/katalog/detske') {
    $category = 'detske';
    $title = t('menu.catalog.kids');
}

// Všechny GET filtry
$getCat     = trim($_GET['kategorie'] ?? '');
$getLic     = trim($_GET['ridicak'] ?? '');
$getKwMin   = (float)($_GET['kw_min'] ?? 0);
$getPriceMax= (float)($_GET['cena_max'] ?? 0);
$getAbs     = isset($_GET['abs']) && $_GET['abs'] === '1';
$getRiders  = (int)($_GET['jezdci'] ?? 0); // 1=sólo, 2=se spolujezdcem
$getQuery   = trim($_GET['q'] ?? '');
$getSort    = $_GET['razeni'] ?? 'default';

if ($getCat) $category = $getCat;

$bc = [['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.catalog'), 'href' => '/katalog']];
if ($category) { $bc[] = $title; } else { $bc[1] = $title; }

// ---- Filtrování ----
$filtered = $motos;

if ($category) {
    $filtered = array_filter($filtered, function ($m) use ($category) {
        $cat = strtolower($m['category'] ?? '');
        $fc = strtolower($category);
        if ($fc === 'cestovni') {
            return strpos($cat, 'cestov') !== false || strpos($cat, 'adventure') !== false || strpos($cat, 'touring') !== false;
        } elseif ($fc === 'naked') {
            return strpos($cat, 'naked') !== false || strpos($cat, 'street') !== false || strpos($cat, 'roadster') !== false;
        } elseif ($fc === 'supermoto') {
            return strpos($cat, 'supermoto') !== false || strpos($cat, 'super moto') !== false || strpos($cat, 'sm') === 0;
        } elseif ($fc === 'detske') {
            return strpos($cat, 'dets') !== false || strpos($cat, 'dět') !== false || (isset($m['license_required']) && strtoupper($m['license_required']) === 'N');
        }
        return $cat === $fc;
    });
}
if ($getLic) {
    $filtered = array_filter($filtered, function ($m) use ($getLic) {
        return ($m['license_required'] ?? '') === $getLic;
    });
}
if ($getKwMin > 0) {
    $filtered = array_filter($filtered, function ($m) use ($getKwMin) {
        return (float)($m['power_kw'] ?? 0) >= $getKwMin;
    });
}
if ($getPriceMax > 0) {
    $filtered = array_filter($filtered, function ($m) use ($getPriceMax) {
        $min = getMinPrice($m);
        return $min > 0 && $min <= $getPriceMax;
    });
}
if ($getAbs) {
    $filtered = array_filter($filtered, function ($m) {
        return !empty($m['has_abs']);
    });
}
if ($getRiders === 2) {
    $filtered = array_filter($filtered, function ($m) {
        // Dětské motorky mají jen 1 místo
        $cat = strtolower($m['category'] ?? '');
        return strpos($cat, 'dets') === false && strpos($cat, 'dět') === false;
    });
}
if ($getQuery !== '') {
    $q = mb_strtolower($getQuery, 'UTF-8');
    $filtered = array_filter($filtered, function ($m) use ($q) {
        $hay = mb_strtolower(
            ($m['model'] ?? '') . ' ' . ($m['category'] ?? '') . ' ' . ($m['description'] ?? '') . ' ' . ($m['ideal_usage'] ?? '') . ' ' . ($m['features'] ?? ''),
            'UTF-8'
        );
        return strpos($hay, $q) !== false;
    });
}

// ---- Řazení ----
$filtered = array_values($filtered);
switch ($getSort) {
    case 'cena_asc':
        usort($filtered, function ($a, $b) { return getMinPrice($a) <=> getMinPrice($b); });
        break;
    case 'cena_desc':
        usort($filtered, function ($a, $b) { return getMinPrice($b) <=> getMinPrice($a); });
        break;
    case 'vykon_desc':
        usort($filtered, function ($a, $b) { return (float)($b['power_kw'] ?? 0) <=> (float)($a['power_kw'] ?? 0); });
        break;
    case 'vykon_asc':
        usort($filtered, function ($a, $b) { return (float)($a['power_kw'] ?? 0) <=> (float)($b['power_kw'] ?? 0); });
        break;
    // default = zachovat původní řazení z DB (model.asc)
}

// ---- Grid ----
$gridHtml = '';
if (empty($filtered)) {
    $gridHtml = '<div class="katalog-empty"><p>' . te('filters.empty') . '</p>'
        . '<p><a class="btn btngreen" href="' . BASE_URL . '/katalog">' . te('filters.clearFilters') . '</a></p></div>';
} else {
    foreach ($filtered as $m) {
        $gridHtml .= '<section aria-label="' . te('filters.aria.catalog') . '">' . renderMotoCard($m) . '</section>';
    }
}

// ---- Filtry UI: pevné hlavní kategorie + dynamicky dopln z dat ----
$fixedCats = [
    'cestovni'  => t('menu.catalog.touring'),
    'naked'     => t('menu.catalog.naked'),
    'supermoto' => t('menu.catalog.supermoto'),
    'detske'    => t('menu.catalog.kids'),
];
$lics = [];
foreach ($motos as $m) {
    if (!empty($m['license_required'])) $lics[$m['license_required']] = true;
}
ksort($lics);

$activeCat = $category ?: '';
$activeLic = $getLic ?: '';

// Helper pro option
$opt = function ($val, $label, $active) {
    $sel = ((string)$val === (string)$active) ? ' selected' : '';
    return '<option value="' . htmlspecialchars((string)$val) . '"' . $sel . '>' . htmlspecialchars($label) . '</option>';
};

$filterHtml = '<form id="katalog-filters" class="katalog-filters" method="get" action="' . BASE_URL . '/katalog">'
    . '<div class="filter-row">'
    . '<div class="filter-field filter-field-search"><label class="sr-only" for="flt-q">' . te('filters.search') . '</label>'
        . '<span class="filter-icon" aria-hidden="true">🔍</span>'
        . '<input type="search" id="flt-q" name="q" placeholder="' . te('filters.searchPlaceholder') . '" value="' . htmlspecialchars($getQuery) . '"></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-cat">' . te('filters.category') . '</label>'
        . '<select id="flt-cat" name="kategorie"><option value="">' . te('filters.categoryAll') . '</option>';
foreach ($fixedCats as $cVal => $cLabel) {
    $filterHtml .= $opt($cVal, $cLabel, strtolower($activeCat));
}
$filterHtml .= '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-lic">' . te('filters.license') . '</label>'
        . '<select id="flt-lic" name="ridicak"><option value="">' . te('filters.licenseAny') . '</option>';
foreach (array_keys($lics) as $l) {
    $filterHtml .= $opt($l, ($l === 'N') ? t('filters.licenseNone') : t('filters.licenseGroup', ['group' => $l]), $activeLic);
}
$filterHtml .= '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-kw">' . te('filters.power') . '</label>'
        . '<select id="flt-kw" name="kw_min">'
        . $opt(0, t('filters.powerAny'), $getKwMin)
        . $opt(11, t('filters.powerFromA1'), $getKwMin)
        . $opt(35, t('filters.powerFromA2'), $getKwMin)
        . $opt(70, t('filters.powerFrom', ['kw' => 70]), $getKwMin)
        . $opt(100, t('filters.powerFrom', ['kw' => 100]), $getKwMin)
        . '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-price">' . te('filters.priceMax') . '</label>'
        . '<select id="flt-price" name="cena_max">'
        . $opt(0, t('filters.priceAny'), $getPriceMax)
        . $opt(1000, t('filters.priceTo', ['price' => '1 000']), $getPriceMax)
        . $opt(1500, t('filters.priceTo', ['price' => '1 500']), $getPriceMax)
        . $opt(2000, t('filters.priceTo', ['price' => '2 000']), $getPriceMax)
        . $opt(3000, t('filters.priceTo', ['price' => '3 000']), $getPriceMax)
        . '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-sort">' . te('filters.sort') . '</label>'
        . '<select id="flt-sort" name="razeni">'
        . $opt('default', t('filters.sortDefault'), $getSort)
        . $opt('cena_asc', t('filters.sortPriceAsc'), $getSort)
        . $opt('cena_desc', t('filters.sortPriceDesc'), $getSort)
        . $opt('vykon_desc', t('filters.sortPowerDesc'), $getSort)
        . $opt('vykon_asc', t('filters.sortPowerAsc'), $getSort)
        . '</select></div>'
    . '</div>'
    . '<div class="filter-row filter-row-checks">'
    . '<label class="filter-check"><input type="checkbox" name="abs" value="1"' . ($getAbs ? ' checked' : '') . '><span>' . te('filters.absOnly') . '</span></label>'
    . '<label class="filter-check"><input type="radio" name="jezdci" value="0"' . ($getRiders !== 2 ? ' checked' : '') . '><span>' . te('filters.ridersAny') . '</span></label>'
    . '<label class="filter-check"><input type="radio" name="jezdci" value="2"' . ($getRiders === 2 ? ' checked' : '') . '><span>' . te('filters.ridersTwo') . '</span></label>'
    . '<div class="filter-actions">'
    . '<a class="btn btndark" href="' . BASE_URL . '/katalog">' . te('filters.reset') . '</a>'
    . '<button type="submit" class="btn btngreen filter-submit"><span>' . te('filters.submit') . '</span></button>'
    . '</div>'
    . '</div></form>';

// Počet výsledků
$countHtml = '<p class="katalog-count">' . t('filters.countLine', ['count' => count($filtered), 'total' => count($motos)]) . '</p>';

$content = '<main id="content"><div class="container">'
    . renderBreadcrumb($bc)
    . '<div class="ccontent"><h1>' . htmlspecialchars($title) . '</h1>'
    . '<p>' . t('filters.catalogLead') . '</p>'
    . $filterHtml
    . $countHtml
    . '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>'
    . '</div></div></main>';

renderPage($title . ' | MotoGo24', $content, $path, [
    'description' => t('katalog.seo.description'),
    'keywords' => t('katalog.seo.keywords'),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.catalog'), 'url' => 'https://motogo24.cz/katalog'],
    ],
]);
