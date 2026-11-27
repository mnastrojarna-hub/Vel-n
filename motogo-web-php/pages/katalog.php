<?php
// ===== MotoGo24 Web PHP — Katalog motorek s rozšířenými filtry =====
// Filtry přes GET: ?kategorie, ?ridicak, ?kw_min, ?kw_max, ?cena_max, ?abs, ?jezdci, ?q, ?sort

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

// Defensive normalize — Velín může uložit pole motorky jako array/object místo
// stringu (typicky při nedopečení JSON ve Velínu UI). htmlspecialchars(),
// strtolower(), string konkatenace v PHP 8 hází TypeError na non-string.
// `normalizeMoto()` všechna scalar pole cast-ne na string a array pole
// (features, images) ošetří separátně. Bez tohohle volání filtry padaly.
foreach ($motos as &$_m) { normalizeMoto($_m); }
unset($_m);

// Landing v2 (viz landing.php): podtitulek + kalkulačka ceny s kalendářem (pages/katalog-calc.php).
require_once __DIR__ . '/../landing.php';
$kcV2 = landingV2Enabled();
if ($kcV2) require_once __DIR__ . '/katalog-calc.php';
// Predikáty filtru (kategorie, fulltext) sdílené s v2 lištou filtrů (pages/katalog-v2-*.php)
require_once __DIR__ . '/katalog-v2-lib.php';

// REQUEST_URI obsahuje query string i případný trailing slash — normalizujeme,
// jinak by /katalog/supermoto/ neprošlo přes níže uvedené porovnání cest a
// kategorie by se nepoužila (katalog by ukázal všechny motorky).
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
if (is_string($path) && $path !== '/' && substr($path, -1) === '/') {
    $path = rtrim($path, '/');
}
if ($path === '' || $path === false) $path = '/katalog';
// Lokalizované slugy (/catalog/touring, /catalogo/turismo, …) → kanonická
// česká cesta, jinak by porovnání kategorií níže na cizí doméně neprošlo.
if (function_exists('i18nCanonicalPath')) $path = i18nCanonicalPath($path);
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
} elseif ($path === '/katalog/scootery') {
    $category = 'scootery';
    $title = t('menu.catalog.scooters');
} elseif ($path === '/katalog/detske') {
    $category = 'detske';
    $title = t('menu.catalog.kids');
} elseif ($path === '/katalog/ostatni') {
    $category = 'ostatni';
    $title = t('menu.catalog.other');
}

// CMS overlay (Velín) — editovatelné texty hlavičky katalogu
$katalogDefaults = [
    'h1'    => $title,
    'intro' => t('filters.catalogLead'),
    'outro' => [
        'title' => 'Jak si vybrat motorku v našem katalogu',
        'body1' => 'V katalogu motorek MotoGo24 najdeš pečlivě udržované stroje pro každý typ jízdy – od pohodlných <strong>cestovních motorek</strong> na dlouhé túry přes hbité <strong>naked stroje</strong> do města a ostré <strong>supermoto</strong> pro zábavu v zatáčkách až po <strong>dětské motorky</strong>. Filtrovat můžeš podle kategorie, řidičského oprávnění, pobočky, výkonu v kW, ceny za den i podle toho, jestli má motorka <strong>ABS</strong> nebo místo pro spolujezdce.',
        'body2' => 'Každá motorka v naší flotile má v detailu uvedené kompletní technické parametry, fotky i ceník po dnech. Půjčujeme <strong>bez kauce</strong>, výbava pro řidiče je <strong>v ceně nájmu</strong> a motorku si vyzvedneš i vrátíš <strong>nonstop</strong> podle rezervace. Když váháš s výběrem, ozvi se nám telefonicky nebo e-mailem – rádi ti poradíme, která motorka je pro tebe ta pravá.',
    ],
];

// 2026-10-11: modely v textech z AKTUÁLNÍ flotily (Velín), ne napevno — {models} = až 3 modely kategorie
$kfModels = function ($cat) use ($motos) {
    $names = [];
    foreach ($motos as $m) {
        if (strtolower((string)($m['category'] ?? '')) !== $cat || !empty($m['is_trailer'])) continue;
        $n = trim((string)($m['model'] ?? ''));
        if ($n !== '' && !in_array($n, $names, true)) $names[] = $n;
        if (count($names) >= 3) break;
    }
    return $names ? implode(', ', array_map(function ($n) { return '<strong>' . htmlspecialchars($n, ENT_QUOTES) . '</strong>'; }, $names)) : '';
};

// Česky (2026-11-27, SEO revize): pobočky, na kterých motorky kategorie reálně stojí, a skupiny ŘP kategorie —
// do H1, titulku, meta popisku i textů (flotila se mezi pobočkami přesouvá, proto nic z toho není napevno).
$kfCat = $category ? array_values(array_filter($motos, function ($m) use ($category) { return katalogCategoryMatch($m, $category); })) : [];
$kfSlugs = katalogBranchSlugs($category ? $kfCat : $motos);
// Kategorie z cesty bez jediné motorky (dnes /katalog/sportovni) → noindex,follow, dokud v ní nic není
$kfEmptyCat = $category && !$kfCat;
$kfPathCat = (string)$category;
// Skupiny ŘP kategorie: „A2 i A“ / „A1 nebo B“ ('' = žádná motorka nebo jen bez ŘP)
$kfLic = function ($glue) use ($kfCat) {
    $have = [];
    foreach ($kfCat as $m) foreach (motoLicenseGroups($m) as $g) $have[$g] = true;
    $g = array_values(array_filter(['AM', 'A1', 'A2', 'A', 'B'], function ($x) use ($have) { return isset($have[$x]); }));
    $last = array_pop($g);
    return $last === null ? '' : ($g ? implode(', ', $g) . $glue . $last : $last);
};
// Věta o převzetí podle typu pobočky: v Mezné předáváme osobně, Velké Němčice jsou samoobslužné (nikdo nic nevysvětluje)
$kfPickup = '';
if (count($kfSlugs) > 1) $kfPickup = ' Na pobočce v Mezné u Pelhřimova ti motorku předáme osobně a všechno ti k ní vysvětlíme, na samoobslužné pobočce ve Velkých Němčicích u Brna si ji vyzvedneš bez obsluhy kódem z aplikace.';
elseif ($kfSlugs === ['mezna']) $kfPickup = ' Na pobočce v Mezné u Pelhřimova ti motorku předáme osobně a všechno ti k ní vysvětlíme.';
elseif ($kfSlugs === ['velke-nemcice']) $kfPickup = ' Na samoobslužné pobočce ve Velkých Němčicích u Brna si motorku vyzvedneš bez obsluhy kódem z aplikace.';
// Všechny skútry kategorie jdou řídit i se skupinou B (dnes A1/B) — jinak se „i na ŘP B“ netvrdí
$kfScootB = $category === 'scootery' && $kfCat && !array_filter($kfCat, function ($m) { return !in_array('B', motoLicenseGroups($m), true); });

// Per-kategorie outro — Seobility hlásil 'Duplicate content' na /katalog/{cestovni,
// naked,detske} + /katalog protože všechny sdílely stejný outro text. Každá kategorie
// dostává vlastní unikátní outro (řeší duplicate i SEO klíčovku per cíl).
// Texty tykají (jako zbytek webu) a neslibují nic, co neplatí pro obě pobočky.
$categoryOutros = [
    'cestovni' => [
        'title' => 'Cestovní motorky k pronájmu – pro dlouhé túry a dovolené',
        'body1' => 'Cestovní (touring) a adventure motorky v naší flotile jsou stavěné na dlouhé vzdálenosti – vyšší posed, pohodlné sedlo pro řidiče i spolujezdce, velká nádrž a u vybraných modelů i kufry na zavazadla. ' . (($mm = $kfModels('cestovni')) ? 'Aktuálně u nás najdeš například ' . $mm . ' – všechny pravidelně servisované a připravené na cestu po Česku i do zahraničí.' : 'Všechny jsou pravidelně servisované a připravené na cestu po Česku i do zahraničí.'),
        'body2' => 'Půjčujeme bez kauce, zelenou kartu i mezinárodní doklady dáváme automaticky a v ceně máš kompletní výbavu pro řidiče. Pro spolujezdce si můžeš doobjednat výbavu (helma, bunda, kukla) za příplatek.',
    ],
    'naked' => [
        'title' => 'Naked motorky – sportovně laděné stroje pro každodenní jízdu',
        'body1' => 'Naked motorky bez kapotáže nabízejí <strong>nezaměnitelný pocit svobody</strong> a přímé spojení s motorem. Hodí se na svižnou jízdu městem, víkendové výlety i na zábavu v zatáčkách. ' . (($mm = $kfModels('naked')) ? 'V naší flotile najdeš například ' . $mm . ' – všechny ve výborném technickém stavu a s pravidelným servisem.' : 'Všechny jsou ve výborném technickém stavu a s pravidelným servisem.'),
        'body2' => 'Půjčujeme bez kauce a výbava pro řidiče je vždy v ceně.' . $kfPickup . ' Když váháš, jaký výkon zvolit, rádi ti s výběrem poradíme.',
    ],
    'supermoto' => [
        'title' => 'Supermoto – lehké a hbité motorky do města i do zatáček',
        'body1' => 'Supermoto kombinuje výhody endura (lehkost, dlouhé pružení, vysoký posed) se silničními pneumatikami a kotoučovými brzdami. Výsledkem je <strong>velmi hbitý stroj</strong>, který si rozumí s městským provozem, polními cestami i kratšími výlety. ' . (($mm = $kfModels('supermoto')) ? 'V katalogu najdeš například ' . $mm . '.' : ''),
        'body2' => (($lg = $kfLic(' nebo ')) !== '' ? 'Tyto motorky řídíš s řidičským oprávněním skupiny ' . $lg . ' (podle modelu) a hodí se' : 'Tyto motorky se hodí') . ' spíš zkušenějším jezdcům, kteří si chtějí užít hravost a lehkost stroje. Půjčujeme bez kauce a výbavu pro řidiče máš v ceně.' . $kfPickup,
    ],
    'chopper' => [
        'title' => 'Choppery a cruisery pro pohodovou jízdu',
        'body1' => 'Choppery a cruisery jsou stavěné na <strong>pohodlnou jízdu na dlouhé vzdálenosti</strong> – nízký posed, uvolněné držení těla, charakteristický zvuk dvouválce a klasický vzhled. Hodí se na nedělní výlet i na delší cestu po Česku.',
        'body2' => 'Nabídku průběžně rozšiřujeme – pokud máš na mysli konkrétní model, ozvi se nám. Půjčujeme bez kauce a výbavu pro řidiče máš v ceně.' . $kfPickup,
    ],
    'detske' => [
        'title' => 'Dětské motorky – bezpečná zábava pro malé jezdce',
        'body1' => 'Dětské motorky si půjčíš <strong>bez řidičského oprávnění</strong>. Dítě s nimi smí jezdit jen v uzavřeném, bezpečném prostoru mimo silnice, stezky a chodníky a vždy pod dohledem dospělého.' . (($mm = $kfModels('detske')) ? ' V katalogu najdeš například ' . $mm . '.' : ''),
        'body2' => 'Před každou jízdou projdi s dítětem základní bezpečnostní pravidla a vždy ho vybav helmou, rukavicemi, moto kalhotami a pevnou obuví. Nájemcem je vždy rodič nebo zákonný zástupce starší 18 let. Termín i případné přistavení zvolíš přímo v rezervaci.',
    ],
    'sportovni' => [
        'title' => 'Sportovní motorky – adrenalin a výkon pro zkušené jezdce',
        'body1' => 'Sportovní (supersport) motorky jsou určené pro <strong>zkušené jezdce</strong>, kteří hledají vysoký výkon, ostrou geometrii a sportovní posed. Hodí se na klikaté silnice a víkendové výlety.',
        'body2' => 'Půjčujeme bez kauce a výbavu pro řidiče máš v ceně. Stačí ti 18 let a řidičák odpovídající skupiny.',
    ],
    'scootery' => [
        'title' => 'Skútry k pronájmu – pohodlná jízda městem' . ($kfScootB ? ' na ŘP A1 i B' : ''),
        'body1' => 'Skútry jsou ideální volbou pro <strong>pohodlnou a nenáročnou jízdu městem</strong> – automatická převodovka, nízký posed a úložný prostor pod sedlem. ' . ($kfScootB ? 'Naše skútry řídíš s ŘP <strong>A1</strong> i s ŘP <strong>B</strong> (řidičák na auto). ' : '') . 'Skupinu ŘP najdeš vždy v detailu každého stroje.',
        'body2' => 'Půjčujeme bez kauce a výbavu pro řidiče (helma, rukavice) máš v ceně. Skútr je skvělý na dojíždění, výlety po okolí i jako první seznámení s jednostopým vozidlem.' . $kfPickup,
    ],
    'ostatni' => [
        'title' => 'Přívěsy na motorky a další vybavení k pronájmu',
        'body1' => 'V kategorii Ostatní najdeš <strong>přívěsy na přepravu motorek</strong> a další doplňkové vybavení k zapůjčení. Přívěs na motorku oceníš při převozu stroje na okruh, na dovolenou nebo do servisu. K tažení přívěsu stačí běžné řidičské oprávnění <strong>skupiny B</strong> (podle hmotnosti soupravy).',
        'body2' => 'Půjčujeme bez kauce a rádi poradíme s výběrem i se správným naložením a zajištěním motorky. Konkrétní parametry (nosnost, rozměry, požadovaná skupina ŘP) najdeš v detailu každé položky. Termín a místo vyzvednutí si domluvíš přímo při rezervaci.',
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
// 2026-10-11: lokalizovaně a z poboček, kde motorky kategorie reálně stojí (dřív česky natvrdo „na Vysočině“)
$kfLang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$kfRent = ['cs' => 'k pronájmu', 'en' => 'for rent', 'de' => 'zur Miete', 'es' => 'en alquiler', 'fr' => 'à louer', 'nl' => 'te huur', 'pl' => 'do wynajęcia', 'uk' => 'в оренду'][$kfLang] ?? 'k pronájmu';
$kfCities = [];
foreach ($motos as $m) {
    if ($category && strtolower((string)($m['category'] ?? '')) !== $category) continue;
    $city = trim((string)($m['branches']['city'] ?? ''));
    if ($city !== '' && !in_array($city, $kfCities, true)) $kfCities[] = $city;
}
$h1Suffix = ' ' . $kfRent . ($kfCities ? ' — ' . implode(', ', $kfCities) : '');
$h1Base = $title;
if ($kfLang === 'cs') {
    // Česky přirozeně „… k pronájmu u Pelhřimova“ / „u Brna“ / „u Pelhřimova a Brna“ místo surového branches.city
    // („Pelhřimov, Brno - Velké Němčice“); vlastní základ H1 tam, kde popisek z menu není hledaný dotaz.
    $h1Suffix = rtrim(' ' . $kfRent . ' ' . katalogPlaceCs($kfSlugs, 'u'));
    $h1Base = ['chopper' => 'Choppery a cruisery', 'ostatni' => 'Přívěs na motorku'][(string)$category] ?? $title;
}
$displayH1 = $category ? ($h1Base . $h1Suffix) : ($C['h1'] ?? $title);
$displayIntro = $C['intro'] ?? t('filters.catalogLead');
$outroTitle = $C['outro']['title'] ?? $katalogDefaults['outro']['title'];
$outroBody1 = $C['outro']['body1'] ?? $katalogDefaults['outro']['body1'];
$outroBody2 = $C['outro']['body2'] ?? $katalogDefaults['outro']['body2'];
// Cizí jazyky (lang/v2/<jazyk>/katalog-kategorie.php): věta s modely aktuální flotily ({models}) se připojí k body1
// jen u kategorie s motorkami, jinak 'nomodels' — stejně jako česká $categoryOutros výše.
if ($category && isset($C['outro']['models']) && is_string($C['outro']['models'])) {
    $kfMm = $kfModels($category);
    $kfExtra = $kfMm !== '' ? str_replace('{models}', $kfMm, $C['outro']['models']) : (string)($C['outro']['nomodels'] ?? '');
    if (trim($kfExtra) !== '') $outroBody1 = rtrim((string)$outroBody1) . ' ' . $kfExtra;
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
$getBranch  = trim($_GET['pobocka'] ?? ''); // filtr dle pobočky (motorcycles.branch_id)

if ($getCat) $category = $getCat;

$bc = [['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.catalog'), 'href' => '/katalog']];
if ($category) { $bc[] = $title; } else { $bc[1] = $title; }

// ---- Filtrování ----
$filtered = $motos;

if ($category) {
    // Shoda kategorie (substring pravidla pro cestovní/naked/… + defensive cast): katalog-v2-lib.php
    $filtered = array_filter($filtered, function ($m) use ($category) {
        return katalogCategoryMatch($m, $category);
    });
}
if ($getLic) {
    $wantLic = strtoupper(trim((string)$getLic));
    $filtered = array_filter($filtered, function ($m) use ($wantLic) {
        // OR-match: motorka projde, pokud přijímanou skupinu obsahuje v poli
        // license_groups (fallback na legacy license_required řeší helper).
        return in_array($wantLic, motoLicenseGroups($m), true);
    });
}
if ($getBranch !== '') {
    $filtered = array_filter($filtered, function ($m) use ($getBranch) {
        return (string)($m['branch_id'] ?? '') === $getBranch;
    });
}
if ($getKwMin > $kwBoundMin || $getKwMax < $kwBoundMax) {
    $filtered = array_filter($filtered, function ($m) use ($getKwMin, $getKwMax) {
        // Nevyplněný výkon filtrem PROJDE — stejně jako u ceny níž. Dřív se
        // bral jako 0 kW, takže při posunu spodní hranice takové motorky
        // z nabídky tiše zmizely.
        if (!isset($m['power_kw']) || $m['power_kw'] === null || $m['power_kw'] === '') return true;
        $kw = (float)$m['power_kw'];
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
    // Prohledávaný text (model, značka, kategorie, popis, výbava; jsonb-safe): katalog-v2-lib.php
    $filtered = array_filter($filtered, function ($m) use ($q) {
        return strpos(katalogQueryHay($m), $q) !== false;
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
    'scootery'  => t('menu.catalog.scooters'),
    'detske'    => t('menu.catalog.kids'),
    'ostatni'   => t('menu.catalog.other'),
];
// Skupiny ŘP do filtru — sbíráme ze všech přijímaných skupin (license_groups),
// aby se A1 i B nabídly i u skútrů/přívěsů, ne jen z legacy license_required.
$lics = [];
foreach ($motos as $m) {
    foreach (motoLicenseGroups($m) as $g) { $lics[$g] = true; }
}
// Pevné pořadí: AM, A1, A2, A, B, N (zbytek abecedně za nimi).
$licOrder = ['AM' => 0, 'A1' => 1, 'A2' => 2, 'A' => 3, 'B' => 4, 'N' => 5];
uksort($lics, function ($a, $b) use ($licOrder) {
    $ra = $licOrder[$a] ?? 99; $rb = $licOrder[$b] ?? 99;
    return $ra === $rb ? strcmp($a, $b) : $ra - $rb;
});

// Pobočky do filtru — z motorek (branch_id + branches.name / city z fetchMotos).
$branchOpts = [];
foreach ($motos as $m) {
    $bid = (string)($m['branch_id'] ?? '');
    if ($bid === '' || isset($branchOpts[$bid])) continue;
    $br = $m['branches'] ?? null;
    $bn = is_array($br) ? safeStr(($br['name'] ?? '') ?: ($br['city'] ?? '')) : '';
    $branchOpts[$bid] = $bn !== '' ? $bn : $bid;
}
asort($branchOpts, SORT_NATURAL | SORT_FLAG_CASE);

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
$filterHtml .= '</select></div>';
if (!empty($branchOpts)) {
    $filterHtml .= '<div class="filter-field"><label class="sr-only" for="flt-branch">' . te('filters.branch') . '</label>'
        . '<select id="flt-branch" name="pobocka"><option value="">' . te('filters.branchAll') . '</option>';
    foreach ($branchOpts as $bId => $bName) { $filterHtml .= $opt($bId, $bName, $getBranch); }
    $filterHtml .= '</select></div>';
}
$filterHtml .= '<div class="filter-field filter-field-range">'
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
    . ($kcV2 ? kcSubtitle($sb, count($filtered)) : '')
    . ($kcV2
        // v2: karta s přepínačem [Najít motorku (filtr) | Spočítat cenu (kalkulačka)] + kompaktní karty
        ? '<p class="kf-intro" data-cms-key="web.katalog.intro">' . $displayIntro . '</p>'
            . renderKatalogV2($sb, [
                'motos' => $motos, 'filtered' => $filtered, 'path' => $path, 'cat' => (string)$category, 'getCat' => $getCat,
                'q' => $getQuery, 'lic' => $getLic, 'branch' => $getBranch, 'abs' => $getAbs, 'riders' => $getRiders, 'sort' => $getSort,
                'kw' => [$getKwMin, $getKwMax, $kwBoundMin, $kwBoundMax], 'pr' => [$getPriceMin, $getPriceMax, $priceBoundMin, $priceBoundMax],
                'lics' => array_keys($lics), 'branches' => $branchOpts,
                'calc' => renderKatalogCalc($sb, $motos, ['branch' => $getBranch]),
            ])
        : '<p data-cms-key="web.katalog.intro">' . $displayIntro . '</p>'
            . $filterHtml
            . $countHtml
            . '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>')
    . $outroHtml
    . '</div></div></main>';

// ItemList JSON-LD — AI agent dostane kompletní katalog v jednom payload (max 50 položek per stránka)
$listItems = [];
foreach (array_slice($filtered, 0, 50) as $i => $m) {
    if (empty($m['id'])) continue;
    $listItems[] = '{"@type":"ListItem","position":' . ($i + 1)
        . ',"url":' . json_encode(siteCanonicalUrl('/katalog/' . $m['id']), JSON_UNESCAPED_SLASHES)
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
// strucny popis se specifickymi klicovkami. Česky (cizí jazyky: lang/v2/<jazyk>/katalog-kategorie.php);
// místo a skupiny ŘP se berou z aktuální flotily kategorie, popis se vejde do 155 znaků.
$kfV = katalogPlaceCs($kfSlugs, 'v');                                   // „v Mezné u Pelhřimova“ / „… nebo ve Velkých Němčicích u Brna“
$kfVs = count($kfSlugs) > 1 ? 'v Mezné nebo u Brna' : $kfV;             // kratší tvar pro obě pobočky
$kfPob = katalogPlaceCs($kfSlugs, 'pobocka');                           // „Mezná i Velké Němčice“ / „Pobočka Mezná u Pelhřimova“
$kfLicI = $kfLic(' i ');
// Skútry: „125“ jen když jsou všechny do 125 ccm
$kfSc125 = $kfPathCat === 'scootery' && $kfCat && !array_filter($kfCat, function ($m) { $cc = (float)($m['engine_cc'] ?? 0); return $cc <= 0 || $cc > 125; });
// První varianta, která se vejde do 155 znaků (jinak poslední = nejkratší)
$kfFit = function (array $variants) { foreach ($variants as $v) { if (mb_strlen($v, 'UTF-8') <= 155) return $v; } return end($variants); };
$catDescriptions = [
    'cestovni'  => $kfFit(['Cestovní a adventure motorky na víkend i dovolenou: neomezené km, cesty do zahraničí, výbava pro řidiče v ceně, bez kauce.' . ($kfPob !== '' ? ' ' . $kfPob . '.' : '')]),
    'sportovni' => 'Sportovní motorky k pronájmu u MotoGo24. Bez kauce, výbava pro řidiče v ceně, rezervace online.',
    'naked'     => $kfFit(array_map(function ($pl) { return 'Naked motorky k pronájmu pro svižnou jízdu v zatáčkách. Bez kauce, výbava pro řidiče v ceně' . ($pl !== '' ? ', vyzvednutí ' . $pl : '') . '.'; }, [$kfV, $kfVs])),
    'supermoto' => $kfFit(array_map(function ($pl) use ($kfLicI) { return 'Supermoto k pronájmu' . ($kfLicI !== '' ? ' na ŘP ' . $kfLicI : '') . ': lehké a hbité stroje do zatáček. Bez kauce, výbava pro řidiče v ceně' . ($pl !== '' ? ', vyzvednutí ' . $pl : '') . '.'; }, [$kfV, $kfVs])),
    'chopper'   => $kfFit(array_map(function ($pl) use ($kfLicI) { return 'Chopper nebo cruiser k pronájmu' . ($pl !== '' ? ' ' . $pl : '') . ($kfLicI !== '' ? ', na ŘP ' . $kfLicI : '') . '. Bez kauce, výbava pro řidiče v ceně, rezervace online.'; }, [$kfV, $kfVs])),
    'scootery'  => $kfFit(['Skútry' . ($kfSc125 ? ' 125' : '') . ' k pronájmu' . ($kfLicI !== '' ? ', řídíš je s ŘP ' . $kfLicI : '') . '. Automat, úložný prostor pod sedlem, bez kauce a s výbavou pro řidiče v ceně.' . ($kfPob !== '' ? ' ' . $kfPob . '.' : '')]),
    'detske'    => $kfFit(array_map(function ($pl) { return 'Dětské motorky k pronájmu' . ($pl !== '' ? ' ' . $pl : '') . ', řidičák nepotřebuješ. Jezdí se jen mimo silnice a pod dohledem dospělého. Rezervace online.'; }, [$kfV, $kfVs])),
    'ostatni'   => $kfFit(array_map(function ($pl) { return 'Přívěsný vozík na motorky k pronájmu' . ($pl !== '' ? ' ' . $pl : '') . ' – na převoz do servisu, na okruh i na dovolenou. Bez kauce, rezervace online.'; }, [$kfV, $kfVs])),
];
// Popis kategorie jen na její stránce (/katalog/<kat>); filtr ?kategorie= má canonical /katalog → obecný popis katalogu
$catDesc = isset($catDescriptions[$kfPathCat]) ? $catDescriptions[$kfPathCat] : t('katalog.seo.description');
if ($category && !empty($C['description']) && is_string($C['description'])) $catDesc = $C['description']; // překlad (cizí jazyky)

// <title>: česky podle hledaného dotazu (kategorie + „k pronájmu“ / „půjčovna …“, u kategorií na obou pobočkách
// i místo, pokud se vejde do 60 znaků); ostatní jazyky beze změny (popisek kategorie | MotoGo24).
$seoTitle = $title . ' | MotoGo24';
if ($kfLang === 'cs') {
    $kfTitles = [
        'cestovni' => 'Cestovní motorky k pronájmu', 'naked' => 'Naked motorky k pronájmu', 'supermoto' => 'Supermoto k pronájmu',
        'chopper' => 'Půjčovna chopperů a cruiserů', 'detske' => 'Půjčovna dětských motorek', 'ostatni' => 'Přívěs na motorku k pronájmu',
        'scootery' => 'Půjčovna skútrů' . ($kfSc125 ? ' 125' : '') . ($kfScootB ? ' – i na ŘP B' : ''),
    ];
    if ($kfPathCat === '') {
        $seoTitle = t('katalog.seo.title');
    } elseif (isset($kfTitles[$kfPathCat]) && !$kfEmptyCat) {
        $kfLoc = in_array($kfPathCat, ['cestovni', 'naked', 'supermoto'], true) ? katalogPlaceCs($kfSlugs, 'titul') : '';
        $seoTitle = $kfTitles[$kfPathCat] . ($kfLoc !== '' ? ' ' . $kfLoc : '') . ' | MotoGo24';
        if (mb_strlen($seoTitle, 'UTF-8') > 60) $seoTitle = $kfTitles[$kfPathCat] . ' | MotoGo24';
    }
}

renderPage($seoTitle, $content, $path, ($kcV2 ? kfPageMeta() : []) + ($kfEmptyCat ? ['robots' => 'noindex,follow'] : []) + [
    'description' => $catDesc,
    'keywords' => t('katalog.seo.keywords'),
    'schema' => $itemListSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.catalog'), 'url' => siteCanonicalUrl('/katalog')],
    ],
]);
