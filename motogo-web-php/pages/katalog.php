<?php
// ===== MotoGo24 Web PHP — Katalog motorek s rozšířenými filtry =====
// Filtry přes GET: ?kategorie, ?ridicak, ?kw_min, ?kw_max, ?cena_max, ?abs, ?jezdci, ?q, ?sort

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$category = null;
$title = 'Katalog motorek';

if ($path === '/katalog/cestovni') {
    $category = 'cestovni';
    $title = 'Cestovní motorky';
} elseif ($path === '/katalog/naked') {
    $category = 'naked';
    $title = 'Naked motorky';
} elseif ($path === '/katalog/supermoto') {
    $category = 'supermoto';
    $title = 'Supermoto motorky';
} elseif ($path === '/katalog/detske') {
    $category = 'detske';
    $title = 'Dětské motorky';
}

// Dynamické hranice slideru výkonu z dat
$kwValues = [];
foreach ($motos as $m) {
    $v = (float)($m['power_kw'] ?? 0);
    if ($v > 0) $kwValues[] = $v;
}
if (!empty($kwValues)) {
    $kwBoundMin = (int)floor(min($kwValues));
    $kwBoundMax = (int)ceil(max($kwValues));
} else {
    $kwBoundMin = 0;
    $kwBoundMax = 150;
}
if ($kwBoundMin === $kwBoundMax) $kwBoundMax = $kwBoundMin + 1;

// Všechny GET filtry
$getCat     = trim($_GET['kategorie'] ?? '');
$getLic     = trim($_GET['ridicak'] ?? '');
$getKwMin   = isset($_GET['kw_min']) && $_GET['kw_min'] !== '' ? (int)$_GET['kw_min'] : $kwBoundMin;
$getKwMax   = isset($_GET['kw_max']) && $_GET['kw_max'] !== '' ? (int)$_GET['kw_max'] : $kwBoundMax;
$getKwMin   = max($kwBoundMin, min($getKwMin, $kwBoundMax));
$getKwMax   = max($kwBoundMin, min($getKwMax, $kwBoundMax));
if ($getKwMin > $getKwMax) { $tmp = $getKwMin; $getKwMin = $getKwMax; $getKwMax = $tmp; }
$getPriceMax= (float)($_GET['cena_max'] ?? 0);
$getAbs     = isset($_GET['abs']) && $_GET['abs'] === '1';
$getRiders  = (int)($_GET['jezdci'] ?? 0); // 1=sólo, 2=se spolujezdcem
$getQuery   = trim($_GET['q'] ?? '');
$getSort    = $_GET['razeni'] ?? 'default';

if ($getCat) $category = $getCat;

$bc = [['label' => 'Domů', 'href' => '/'], ['label' => 'Katalog motorek', 'href' => '/katalog']];
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
if ($getKwMin > $kwBoundMin || $getKwMax < $kwBoundMax) {
    $filtered = array_filter($filtered, function ($m) use ($getKwMin, $getKwMax) {
        $kw = (float)($m['power_kw'] ?? 0);
        return $kw >= $getKwMin && $kw <= $getKwMax;
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
    $gridHtml = '<div class="katalog-empty"><p>Podle zvolených filtrů momentálně nemáme žádné motorky.</p>'
        . '<p><a class="btn btngreen" href="' . BASE_URL . '/katalog">Zrušit filtry</a></p></div>';
} else {
    foreach ($filtered as $m) {
        $gridHtml .= '<section aria-label="katalog motorek">' . renderMotoCard($m) . '</section>';
    }
}

// ---- Filtry UI: pevné hlavní kategorie + dynamicky dopln z dat ----
$fixedCats = [
    'cestovni'  => 'Cestovní motorky',
    'naked'     => 'Naked motorky',
    'supermoto' => 'Supermoto motorky',
    'detske'    => 'Dětské motorky',
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
    . '<div class="filter-field filter-field-search"><label class="sr-only" for="flt-q">Hledat</label>'
        . '<span class="filter-icon" aria-hidden="true">🔍</span>'
        . '<input type="search" id="flt-q" name="q" placeholder="Hledat model, značku…" value="' . htmlspecialchars($getQuery) . '"></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-cat">Kategorie</label>'
        . '<select id="flt-cat" name="kategorie"><option value="">Kategorie — všechny</option>';
foreach ($fixedCats as $cVal => $cLabel) {
    $filterHtml .= $opt($cVal, $cLabel, strtolower($activeCat));
}
$filterHtml .= '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-lic">Řidičský průkaz</label>'
        . '<select id="flt-lic" name="ridicak"><option value="">Řidičský průkaz</option>';
foreach (array_keys($lics) as $l) {
    $filterHtml .= $opt($l, ($l === 'N') ? 'Bez ŘP (dětské)' : 'Skupina ' . $l, $activeLic);
}
$filterHtml .= '</select></div>'
    . '<div class="filter-field filter-field-range">'
        . '<div class="range-header">'
            . '<span class="range-title">Výkon</span>'
            . '<span class="range-value" id="flt-kw-display">'
                . htmlspecialchars((string)$getKwMin) . ' – '
                . ($getKwMax >= $kwBoundMax ? 'max' : htmlspecialchars((string)$getKwMax))
                . ' kW</span>'
        . '</div>'
        . '<div class="range-slider" data-bound-min="' . $kwBoundMin . '" data-bound-max="' . $kwBoundMax . '">'
            . '<div class="range-track"></div>'
            . '<div class="range-fill" id="flt-kw-fill"></div>'
            . '<input type="range" id="flt-kw-min" name="kw_min" class="range-input range-input-min"'
                . ' min="' . $kwBoundMin . '" max="' . $kwBoundMax . '" step="1"'
                . ' value="' . $getKwMin . '" aria-label="Minimální výkon v kW">'
            . '<input type="range" id="flt-kw-max" name="kw_max" class="range-input range-input-max"'
                . ' min="' . $kwBoundMin . '" max="' . $kwBoundMax . '" step="1"'
                . ' value="' . $getKwMax . '" aria-label="Maximální výkon v kW">'
        . '</div>'
        . '<div class="range-bounds">'
            . '<span>' . $kwBoundMin . ' kW</span>'
            . '<span>' . $kwBoundMax . ' kW</span>'
        . '</div>'
    . '</div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-price">Cena max.</label>'
        . '<select id="flt-price" name="cena_max">'
        . $opt(0, 'Cena — libovolná', $getPriceMax)
        . $opt(1000, 'do 1 000 Kč/den', $getPriceMax)
        . $opt(1500, 'do 1 500 Kč/den', $getPriceMax)
        . $opt(2000, 'do 2 000 Kč/den', $getPriceMax)
        . $opt(3000, 'do 3 000 Kč/den', $getPriceMax)
        . '</select></div>'
    . '<div class="filter-field"><label class="sr-only" for="flt-sort">Řazení</label>'
        . '<select id="flt-sort" name="razeni">'
        . $opt('default', 'Řazení — výchozí', $getSort)
        . $opt('cena_asc', 'Cena: od nejnižší', $getSort)
        . $opt('cena_desc', 'Cena: od nejvyšší', $getSort)
        . $opt('vykon_desc', 'Výkon: od nejvyššího', $getSort)
        . $opt('vykon_asc', 'Výkon: od nejnižšího', $getSort)
        . '</select></div>'
    . '</div>'
    . '<div class="filter-row filter-row-checks">'
    . '<label class="filter-check"><input type="checkbox" name="abs" value="1"' . ($getAbs ? ' checked' : '') . '><span>Pouze s ABS</span></label>'
    . '<label class="filter-check"><input type="radio" name="jezdci" value="0"' . ($getRiders !== 2 ? ' checked' : '') . '><span>Libovolný počet jezdců</span></label>'
    . '<label class="filter-check"><input type="radio" name="jezdci" value="2"' . ($getRiders === 2 ? ' checked' : '') . '><span>Pro 2 osoby</span></label>'
    . '<div class="filter-actions">'
    . '<a class="btn btndark" href="' . BASE_URL . '/katalog">Resetovat</a>'
    . '<button type="submit" class="btn btngreen filter-submit"><span>HLEDAT</span></button>'
    . '</div>'
    . '</div></form>'
    . '<script>(function(){'
    . 'var minIn=document.getElementById("flt-kw-min");'
    . 'var maxIn=document.getElementById("flt-kw-max");'
    . 'var disp=document.getElementById("flt-kw-display");'
    . 'var fill=document.getElementById("flt-kw-fill");'
    . 'var form=document.getElementById("katalog-filters");'
    . 'if(!minIn||!maxIn)return;'
    . 'var bMin=+minIn.min,bMax=+minIn.max;'
    . 'function update(src){'
    . 'var a=+minIn.value,b=+maxIn.value;'
    . 'if(a>b){if(src==="min"){maxIn.value=a;b=a;}else{minIn.value=b;a=b;}}'
    . 'if(disp)disp.textContent=a+" – "+(b>=bMax?"max":b)+" kW";'
    . 'if(fill&&bMax>bMin){var l=((a-bMin)/(bMax-bMin))*100;var r=100-((b-bMin)/(bMax-bMin))*100;fill.style.left=l+"%";fill.style.right=r+"%";}'
    . '}'
    . 'minIn.addEventListener("input",function(){update("min");});'
    . 'maxIn.addEventListener("input",function(){update("max");});'
    . 'if(form){form.addEventListener("submit",function(){'
    . 'if(+minIn.value<=bMin)minIn.disabled=true;'
    . 'if(+maxIn.value>=bMax)maxIn.disabled=true;'
    . '});}'
    . 'update();'
    . '})();</script>';

// Počet výsledků
$countHtml = '<p class="katalog-count">Nalezeno <strong>' . count($filtered) . '</strong> z ' . count($motos) . ' motorek</p>';

$content = '<main id="content"><div class="container">'
    . renderBreadcrumb($bc)
    . '<div class="ccontent"><h1>' . htmlspecialchars($title) . '</h1>'
    . '<p>Vyberte si z naší nabídky <strong>cestovních, sportovních, enduro i dětských motorek</strong>. Můžete filtrovat podle kategorie, řidičského průkazu, výkonu, ceny a dalších parametrů.</p>'
    . $filterHtml
    . $countHtml
    . '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>'
    . '</div></div></main>';

renderPage($title . ' | MotoGo24', $content, $path, [
    'description' => 'Katalog motorek k pronájmu na Vysočině. Filtr dle kategorie, ŘP, výkonu a ceny. Cestovní, sportovní, enduro a dětské motorky. Online rezervace.',
    'keywords' => 'katalog motorek, motorky k pronájmu, cestovní motorky, sportovní motorky, enduro, dětské motorky, filtr motorek',
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Katalog motorek', 'url' => 'https://motogo24.cz/katalog'],
    ],
]);
