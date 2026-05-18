<?php
// ===== MotoGo24 Web PHP — Katalog motorek s rozšířenými filtry =====
// Filtry přes GET: ?kategorie, ?ridicak, ?kw_min, ?kw_max, ?cena_max, ?abs, ?jezdci, ?q, ?sort

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

// REQUEST_URI obsahuje query string i případný trailing slash — normalizujeme,
// jinak by /katalog/supermoto/ neprošlo přes níže uvedené porovnání cest a
// kategorie by se nepoužila (katalog by ukázal všechny motorky).
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
if (is_string($path) && $path !== '/' && substr($path, -1) === '/') {
    $path = rtrim($path, '/');
}
if ($path === '' || $path === false) $path = '/katalog';
$category = null;
$title = t('menu.catalog');

if ($path === '/katalog/cestovni') {
    $category = 'cestovni';
    $title = t('menu.catalog.touring');
} elseif ($path === '/katalog/sportovni') {
    $category = 'sportovni';
    $title = t('menu.catalog.sport');
} elseif ($path === '/katalog/naked') {
    $category = 'naked';
    $title = t('menu.catalog.naked');
} elseif ($path === '/katalog/supermoto') {
    $category = 'supermoto';
    $title = t('menu.catalog.supermoto');
} elseif ($path === '/katalog/chopper') {
    $category = 'chopper';
    $title = t('menu.catalog.chopper');
} elseif ($path === '/katalog/detske') {
    $category = 'detske';
    $title = t('menu.catalog.kids');
}

// CMS overlay (Velín) — editovatelné texty hlavičky katalogu
$katalogDefaults = [
    'h1'    => $title,
    'intro' => t('filters.catalogLead'),
    'outro' => [
        'title' => 'Jak si vybrat motorku v našem katalogu',
        'body1' => 'V katalogu motorek MotoGo24 najdete pečlivě udržované stroje pro každý typ jízdy — od pohodlných <strong>cestovních motorek</strong> na dlouhé túry přes hbité <strong>naked stroje</strong> do města, ostré <strong>supermoto</strong> pro zábavu na zatáčkách až po bezpečné <strong>dětské elektromotorky</strong>. Filtrovat můžete podle kategorie, řidičského oprávnění, výkonu v kW, maximální ceny za den i podle toho, jestli má motorka <strong>ABS</strong> nebo místo pro spolujezdce.',
        'body2' => 'Každá motorka v naší flotile má v detailu uvedené kompletní technické parametry, fotky i ceník po dnech. Půjčení probíhá <strong>bez kauce</strong>, výbava pro řidiče (helma, bunda, kalhoty, rukavice) je <strong>v ceně nájmu</strong> a vyzvednutí si můžete domluvit i mimo otevírací dobu díky <strong>nonstop provozu</strong>. Pokud si nejste jistí výběrem, ozvěte se nám telefonicky nebo e-mailem — rádi vám poradíme, která motorka je pro vás ta pravá.',
    ],
];

// Per-kategorie outro — Seobility hlásil 'Duplicate content' na /katalog/{cestovni,
// naked,detske} + /katalog protože všechny sdílely stejný outro text. Každá kategorie
// dostává vlastní unikátní outro (řeší duplicate i SEO klíčovku per cíl).
$categoryOutros = [
    'cestovni' => [
        'title' => 'Cestovní motorky k pronájmu — pro dlouhé túry a dovolené',
        'body1' => 'Cestovní (touring) a adventure motorky v naší flotile jsou stavěné na dlouhé vzdálenosti — vyšší posed, pohodlné sedadlo pro řidiče i spolujezdce, velká nádrž s dojezdem 300–400 km a kufry pro zavazadla. Najdete tu klasické cestovní stroje jako <strong>Honda Africa Twin</strong>, <strong>BMW R 1200 GS Adventure</strong> nebo <strong>Benelli TRK</strong> — všechny pravidelně servisované a připravené na trasu po ČR i do zahraničí.',
        'body2' => 'Půjčujeme bez kauce, zelenou kartu i mezinárodní doklady dáváme automaticky a v ceně máte kompletní výbavu pro řidiče. Pokud plánujete delší cestu (5+ dní), nabízíme automatickou slevu — promítne se přímo do online rezervace. Pro spolujezdce si můžete doobjednat výbavu (helma, bunda, kukla) za příplatek.',
    ],
    'naked' => [
        'title' => 'Naked motorky — sportovně laděné stroje pro každodenní jízdu',
        'body1' => 'Naked motorky bez kapotáže nabízejí <strong>nezaměnitelný pocit svobody</strong> a přímé spojení s motorem. Hodí se na rychlou jízdu městem, víkendové výlety i na zábavu v zatáčkách. V naší flotile najdete například <strong>Kawasaki Z 900</strong> nebo <strong>Yamaha MT-09 Street Rally</strong> — všechny ve výborném technickém stavu, s nízkým nájezdem a pravidelným servisem.',
        'body2' => 'Půjčujeme bez kauce a výbava pro řidiče (helma, bunda, kalhoty, rukavice) je vždy v ceně. Před vyzvednutím motorku společně prohlédneme a vysvětlíme vám její specifika. Pokud nemáte zkušenost s konkrétní třídou výkonu, rádi poradíme s výběrem.',
    ],
    'supermoto' => [
        'title' => 'Supermoto motorky — lehké a hbité stroje pro městský zlob',
        'body1' => 'Supermoto kombinuje výhody enduro motorky (lehkost, dlouhé pružení, vysoký posed) se silničními pneumatikami a kotoučovými brzdami. Výsledek je <strong>velmi hbitý stroj</strong>, který si rozumí s městským provozem, polními cestami i krátkými túrami po Vysočině. V katalogu najdete například <strong>Yamaha XT660 X</strong> — klasické supermoto s velkým jednoválcovým srdcem.',
        'body2' => 'Tyto motorky vyžadují řidičské oprávnění A nebo A2 a hodí se spíš zkušenějším jezdcům, kteří si chtějí užít hravost a lehkost stroje. Půjčujeme bez kauce, výbavu řidiče máte v ceně. Při vyzvednutí vám vysvětlíme specifika jízdy s vyšším posedem a důraz na vyvážení.',
    ],
    'naked_chopper' => [
        'title' => 'Chopper a cruiser motorky pro pohodovou jízdu',
        'body1' => 'Chopper a cruiser motorky jsou stavěné pro <strong>pohodlnou jízdu na dlouhé vzdálenosti</strong> — nízký posed, tažné držení těla, charakteristický zvuk dvouválcového motoru a estetika klasiky. Hodí se na nedělní výlet i na delší cestu po ČR.',
        'body2' => 'V naší flotile rozšiřujeme nabídku průběžně — pokud máte konkrétní model na mysli, ozvěte se nám. Půjčujeme bez kauce a výbavu řidiče máte v ceně. Při vyzvednutí vám předáme klíče, dokumenty a kompletní výbavu.',
    ],
    'detske' => [
        'title' => 'Dětské motorky — bezpečná zábava pro malé jezdce',
        'body1' => 'Dětské elektromotorky a malé motorky s nízkým výkonem (do 4,1 kW) si můžete půjčit <strong>bez řidičského oprávnění</strong> a využít je na zahradě, tábořišti nebo v rámci jezdeckého kurzu pro děti. V katalogu najdete například <strong>Yamaha PW 50</strong> — legendu mezi dětskými stroji, která se vyrábí prakticky beze změny už desítky let.',
        'body2' => 'Před každou jízdou doporučujeme dítěti přečíst základní bezpečnostní pravidla a vždy ho vybavit helmou a chrániči (k zapůjčení v ceně). Doručujeme motorku po celé ČR — domluvíme se na čase i adrese přistavení přímo při rezervaci.',
    ],
    'sportovni' => [
        'title' => 'Sportovní motorky — adrenalin a výkon pro zkušené jezdce',
        'body1' => 'Sportovní (supersport) motorky jsou určené pro <strong>zkušené jezdce</strong>, kteří hledají vysoký výkon, ostrou geometrii a sportovní posed. Hodí se na okruh, klikaté silnice a víkendové výlety po hezkých moravských a vysočinských trasách.',
        'body2' => 'Vyžadujeme řidičské oprávnění A a minimálně 2 roky praxe na motorce nad 35 kW. Půjčujeme bez kauce, kompletní výbavu řidiče máte v ceně. Před vyzvednutím vám vysvětlíme specifika jízdy se sportovní motorkou a doporučíme bezpečnostní postupy.',
    ],
];
// Aplikuj per-kategorie outro pokud existuje, jinak default
if ($category && isset($categoryOutros[$category])) {
    $katalogDefaults['outro'] = $categoryOutros[$category];
}

$C = $sb->siteContent('katalog' . ($category ? '_' . $category : ''), $katalogDefaults);
// Pro kategorie subpages necháme dynamický nadpis z překladů, jen sdílený intro lze přepsat
// H1 extension: kategorie ("Cestovní motorky" má jen ~16 px) doplníme o "k pronájmu na Vysočině"
// aby přesáhly Seobility 120 px limit (řeší 'H1 too short' na všech /katalog/{kat}).
$h1Suffix = ' k pronájmu na Vysočině';
$displayH1 = $category ? ($title . $h1Suffix) : ($C['h1'] ?? $title);
$displayIntro = $C['intro'] ?? t('filters.catalogLead');
$outroTitle = $C['outro']['title'] ?? $katalogDefaults['outro']['title'];
$outroBody1 = $C['outro']['body1'] ?? $katalogDefaults['outro']['body1'];
$outroBody2 = $C['outro']['body2'] ?? $katalogDefaults['outro']['body2'];

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

// Dynamické hranice slideru ceny z dat (min/max getMinPrice napříč motorkami).
// Krok slideru je 100 Kč, hranice se zaokrouhlují dolů/nahoru na 100 Kč pro
// hezčí čísla. Po přidání nové motorky se hranice automaticky přepočítají
// (nikde se neukládají — pokaždé čteme z motos).
$priceValues = [];
foreach ($motos as $m) {
    $p = getMinPrice($m);
    if ($p > 0) $priceValues[] = $p;
}
if (!empty($priceValues)) {
    $priceBoundMin = (int)(floor(min($priceValues) / 100) * 100);
    $priceBoundMax = (int)(ceil(max($priceValues) / 100) * 100);
} else {
    $priceBoundMin = 0;
    $priceBoundMax = 10000;
}
if ($priceBoundMin === $priceBoundMax) $priceBoundMax = $priceBoundMin + 100;

// Všechny GET filtry
$getCat     = trim($_GET['kategorie'] ?? '');
$getLic     = trim($_GET['ridicak'] ?? '');
$getKwMin   = isset($_GET['kw_min']) && $_GET['kw_min'] !== '' ? (int)$_GET['kw_min'] : $kwBoundMin;
$getKwMax   = isset($_GET['kw_max']) && $_GET['kw_max'] !== '' ? (int)$_GET['kw_max'] : $kwBoundMax;
$getKwMin   = max($kwBoundMin, min($getKwMin, $kwBoundMax));
$getKwMax   = max($kwBoundMin, min($getKwMax, $kwBoundMax));
if ($getKwMin > $getKwMax) { $tmp = $getKwMin; $getKwMin = $getKwMax; $getKwMax = $tmp; }
// Cena: range slider [cena_min..cena_max]. Pokud GET nenastaven, použij hranice z dat.
$getPriceMin = isset($_GET['cena_min']) && $_GET['cena_min'] !== '' ? (int)$_GET['cena_min'] : $priceBoundMin;
$getPriceMax = isset($_GET['cena_max']) && $_GET['cena_max'] !== '' ? (int)$_GET['cena_max'] : $priceBoundMax;
$getPriceMin = max($priceBoundMin, min($getPriceMin, $priceBoundMax));
$getPriceMax = max($priceBoundMin, min($getPriceMax, $priceBoundMax));
if ($getPriceMin > $getPriceMax) { $tmp = $getPriceMin; $getPriceMin = $getPriceMax; $getPriceMax = $tmp; }
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
            return strpos($cat, 'cestov') !== false || strpos($cat, 'adventure') !== false || strpos($cat, 'touring') !== false || strpos($cat, 'enduro') !== false;
        } elseif ($fc === 'sportovni') {
            return strpos($cat, 'sport') !== false || strpos($cat, 'supersport') !== false || strpos($cat, 'super sport') !== false;
        } elseif ($fc === 'naked') {
            return strpos($cat, 'naked') !== false || strpos($cat, 'street') !== false || strpos($cat, 'roadster') !== false;
        } elseif ($fc === 'supermoto') {
            return strpos($cat, 'supermoto') !== false || strpos($cat, 'super moto') !== false || strpos($cat, 'super-moto') !== false || strpos($cat, 'motard') !== false || $cat === 'sm';
        } elseif ($fc === 'chopper') {
            return strpos($cat, 'chopper') !== false || strpos($cat, 'cruiser') !== false || strpos($cat, 'bobber') !== false;
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
// Filtr ceny — aplikuje se jen pokud uživatel posunul slider z výchozích hodnot.
// Hodnota 0 (`getMinPrice` vrací 0) projde vždy (motorka bez ceny by jinak při
// posunu slideru zmizela, což není žádoucí — nechceme skrýt motorky kvůli chybějícímu
// ceníku).
if ($getPriceMin > $priceBoundMin || $getPriceMax < $priceBoundMax) {
    $filtered = array_filter($filtered, function ($m) use ($getPriceMin, $getPriceMax) {
        $min = getMinPrice($m);
        if ($min <= 0) return true; // motorky bez ceníku necháme projít
        return $min >= $getPriceMin && $min <= $getPriceMax;
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
            ($m['model'] ?? '') . ' ' . ($m['category'] ?? '') . ' ' . ($m['description'] ?? '') . ' ' . ($m['features'] ?? ''),
            'UTF-8'
        );
        return strpos($hay, $q) !== false;
    });
}

// ---- Řazení ----
$filtered = array_values($filtered);
// Helper pro řazení podle ceny: motorky bez ceny (`price=0`) musejí jít na KONEC
// nezávisle na směru řazení (asc/desc) — jinak by `cena_asc` ukázal nejdřív všechny
// motorky bez ceníku, což vypadá jako že řazení nefunguje. Vrací PHP_INT_MAX pro
// cena_asc a 0 pro cena_desc (zachová chování "0 vždy nakonec").
$pricedKey = function ($m, $direction) {
    $p = getMinPrice($m);
    if ($p <= 0) return $direction === 'asc' ? PHP_INT_MAX : -1;
    return $p;
};
switch ($getSort) {
    case 'cena_asc':
        usort($filtered, function ($a, $b) use ($pricedKey) {
            return $pricedKey($a, 'asc') <=> $pricedKey($b, 'asc');
        });
        break;
    case 'cena_desc':
        usort($filtered, function ($a, $b) use ($pricedKey) {
            return $pricedKey($b, 'desc') <=> $pricedKey($a, 'desc');
        });
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
    'sportovni' => t('menu.catalog.sport'),
    'naked'     => t('menu.catalog.naked'),
    'supermoto' => t('menu.catalog.supermoto'),
    'chopper'   => t('menu.catalog.chopper'),
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

// Helper pro formátování ceny (např. 1500 → "1 500 Kč/den")
$priceFmt = function ($p) {
    return number_format((int)$p, 0, ',', ' ') . ' Kč';
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
    . '<div class="filter-field filter-field-range">'
        . '<div class="range-header">'
            . '<span class="range-title">' . te('filters.power') . '</span>'
            . '<span class="range-value" id="flt-kw-display">'
                . htmlspecialchars((string)$getKwMin) . ' – '
                . ($getKwMax >= $kwBoundMax ? te('filters.rangeMax') : htmlspecialchars((string)$getKwMax))
                . ' kW</span>'
        . '</div>'
        . '<div class="range-slider" data-bound-min="' . $kwBoundMin . '" data-bound-max="' . $kwBoundMax . '">'
            . '<div class="range-track"></div>'
            . '<div class="range-fill" id="flt-kw-fill"></div>'
            . '<input type="range" id="flt-kw-min" name="kw_min" class="range-input range-input-min"'
                . ' min="' . $kwBoundMin . '" max="' . $kwBoundMax . '" step="1"'
                . ' value="' . $getKwMin . '" aria-label="' . te('filters.power.aria.min') . '">'
            . '<input type="range" id="flt-kw-max" name="kw_max" class="range-input range-input-max"'
                . ' min="' . $kwBoundMin . '" max="' . $kwBoundMax . '" step="1"'
                . ' value="' . $getKwMax . '" aria-label="' . te('filters.power.aria.max') . '">'
        . '</div>'
        . '<div class="range-bounds">'
            . '<span>' . $kwBoundMin . ' kW</span>'
            . '<span>' . $kwBoundMax . ' kW</span>'
        . '</div>'
    . '</div>'
    . '<div class="filter-field filter-field-range">'
        . '<div class="range-header">'
            . '<span class="range-title">' . te('filters.priceMax') . '</span>'
            . '<span class="range-value" id="flt-price-display">'
                . htmlspecialchars($priceFmt($getPriceMin)) . ' – '
                . htmlspecialchars($priceFmt($getPriceMax))
            . '</span>'
        . '</div>'
        . '<div class="range-slider" data-bound-min="' . $priceBoundMin . '" data-bound-max="' . $priceBoundMax . '">'
            . '<div class="range-track"></div>'
            . '<div class="range-fill" id="flt-price-fill"></div>'
            . '<input type="range" id="flt-price-min" name="cena_min" class="range-input range-input-min"'
                . ' min="' . $priceBoundMin . '" max="' . $priceBoundMax . '" step="100"'
                . ' value="' . $getPriceMin . '" aria-label="' . te('filters.price.aria.min') . '">'
            . '<input type="range" id="flt-price-max" name="cena_max" class="range-input range-input-max"'
                . ' min="' . $priceBoundMin . '" max="' . $priceBoundMax . '" step="100"'
                . ' value="' . $getPriceMax . '" aria-label="' . te('filters.price.aria.max') . '">'
        . '</div>'
        . '<div class="range-bounds">'
            . '<span>' . $priceFmt($priceBoundMin) . '</span>'
            . '<span>' . $priceFmt($priceBoundMax) . '</span>'
        . '</div>'
    . '</div>'
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
    . '</div></form>'
    . '<script>(function(){'
    . 'var MAX_LABEL=' . json_encode(t('filters.rangeMax'), JSON_UNESCAPED_UNICODE) . ';'
    . 'var form=document.getElementById("katalog-filters");'
    // Generický helper pro double-thumb range slider. Volá se 2x — pro kW i cenu.
    . 'function bindRange(minId,maxId,displayId,fillId,unit,maxLabel){'
    . 'var minIn=document.getElementById(minId),maxIn=document.getElementById(maxId);'
    . 'var disp=document.getElementById(displayId),fill=document.getElementById(fillId);'
    . 'if(!minIn||!maxIn)return;'
    . 'var bMin=+minIn.min,bMax=+minIn.max;'
    . 'function fmt(v){return unit==="kw"?(v+" kW"):(v.toLocaleString("cs-CZ").replace(/,/g," ")+" Kč");}'
    . 'function update(src){'
    . 'var a=+minIn.value,b=+maxIn.value;'
    . 'if(a>b){if(src==="min"){maxIn.value=a;b=a;}else{minIn.value=b;a=b;}}'
    . 'if(disp)disp.textContent=fmt(a)+" – "+(b>=bMax&&maxLabel?maxLabel:fmt(b));'
    . 'if(fill&&bMax>bMin){var l=((a-bMin)/(bMax-bMin))*100;var r=100-((b-bMin)/(bMax-bMin))*100;fill.style.left=l+"%";fill.style.right=r+"%";}'
    . '}'
    . 'minIn.addEventListener("input",function(){update("min");});'
    . 'maxIn.addEventListener("input",function(){update("max");});'
    . 'if(form){form.addEventListener("submit",function(){'
    // Inputy ve výchozích polohách (= žádné filtrování) se disablují, aby se neposílaly do URL.
    . 'if(+minIn.value<=bMin)minIn.disabled=true;'
    . 'if(+maxIn.value>=bMax)maxIn.disabled=true;'
    . '});}'
    . 'update();'
    . '}'
    . 'bindRange("flt-kw-min","flt-kw-max","flt-kw-display","flt-kw-fill","kw",MAX_LABEL);'
    . 'bindRange("flt-price-min","flt-price-max","flt-price-display","flt-price-fill","price",null);'
    . '})();</script>';

// Počet výsledků
$countHtml = '<p class="katalog-count">' . t('filters.countLine', ['count' => count($filtered), 'total' => count($motos)]) . '</p>';

$h1AttrCms = $category ? '' : ' data-cms-key="web.katalog.h1"';
$outroHtml = '<section class="katalog-outro">'
    . '<h2 data-cms-key="web.katalog.outro.title">' . sanitizeHtml($outroTitle) . '</h2>'
    . '<p data-cms-key="web.katalog.outro.body1">' . sanitizeHtml($outroBody1) . '</p>'
    . '<p data-cms-key="web.katalog.outro.body2">' . sanitizeHtml($outroBody2) . '</p>'
    . '</section>';
$content = '<main id="content"><div class="container">'
    . renderBreadcrumb($bc)
    . '<div class="ccontent"><h1' . $h1AttrCms . '>' . htmlspecialchars($displayH1) . '</h1>'
    . '<p data-cms-key="web.katalog.intro">' . $displayIntro . '</p>'
    . $filterHtml
    . $countHtml
    . '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>'
    . $outroHtml
    . '</div></div></main>';

// ItemList JSON-LD — AI agent dostane kompletní katalog v jednom payload (max 50 položek per stránka)
$listItems = [];
foreach (array_slice($filtered, 0, 50) as $i => $m) {
    if (empty($m['id'])) continue;
    $listItems[] = '{"@type":"ListItem","position":' . ($i + 1)
        . ',"url":"https://www.motogo24.cz/katalog/' . htmlspecialchars($m['id']) . '"'
        . ',"name":' . json_encode($m['model'] ?? '', JSON_UNESCAPED_UNICODE)
        . '}';
}
$itemListSchema = '';
if (!empty($listItems)) {
    $itemListSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"ItemList","name":' . json_encode($title . ' — MotoGo24', JSON_UNESCAPED_UNICODE)
        . ',"numberOfItems":' . count($filtered)
        . ',"itemListOrder":"https://schema.org/ItemListOrderAscending"'
        . ',"itemListElement":[' . implode(',', $listItems) . ']}
  </script>';
}

// SEO: per-kategorie unikatni meta description (Seobility hlasil 5 'Duplicate
// meta description' na /katalog/{cestovni,naked,supermoto,detske} + /katalog).
// Misto jedne sablonove vety pro vsech 5 stranek dame kazde kategorii vlastni
// strucny popis se specifickymi klicovkami.
$catDescriptions = [
    'cestovni'  => 'Půjčovna cestovních motorek (touring, GT) na Vysočině. Adventure motorky pro dlouhé trasy a dálnice. Bez kauce, online rezervace.',
    'sportovni' => 'Půjčovna sportovních motorek na Vysočině. Supersport i sportovně-cestovní stroje. Bez kauce, výbava v ceně, online rezervace.',
    'naked'     => 'Půjčovna naked motorek na Vysočině. Sportovně-cestovní stroje pro každodenní jízdu. Bez kauce, výbava v ceně, online rezervace.',
    'supermoto' => 'Půjčovna supermoto motorek na Vysočině. Lehké městské stroje s vysokým posedem. Bez kauce, výbava v ceně, online rezervace.',
    'chopper'   => 'Půjčovna chopper a cruiser motorek na Vysočině. Pohodlné stroje na klidnou jízdu. Bez kauce, výbava v ceně, online rezervace.',
    'detske'    => 'Půjčovna dětských elektromotorek bez ŘP. Bezpečná zábava na zahradě i tábořištích. Doručení po ČR, online rezervace.',
];
$catDesc = $category && isset($catDescriptions[$category]) ? $catDescriptions[$category] : t('katalog.seo.description');

renderPage($title . ' | MotoGo24', $content, $path, [
    'description' => $catDesc,
    'keywords' => t('katalog.seo.keywords'),
    'schema' => $itemListSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.catalog'), 'url' => siteCanonicalUrl('/katalog')],
    ],
]);
