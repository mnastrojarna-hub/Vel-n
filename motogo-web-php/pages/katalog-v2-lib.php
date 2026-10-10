<?php
// ===== Katalog v2 — data a texty filtrů (landing v2, viz landing.php) =====
// Sdílené predikáty filtru (kategorie, fulltext) používá i v1 (pages/katalog.php),
// aby JS filtr v2 (js/landing-catalog*.js nad JSON kf-data) dával stejné výsledky
// jako GET formulář. Render lišty, panelu a karet: pages/katalog-v2-ui.php.
// Texty: CS defaulty kfDefaults() ← lang/v2/<lang>/katalog.php (blok landing_katalog,
// klíče f_*) ← Velín web.landing_katalog.f_*. Sdílené texty: lpTexts() common
// (fleet_*, license*, card_book, more_*), kcTexts() (kalendář, cta, reset) a t('filters.*').

const KF_CATS = ['cestovni', 'sportovni', 'naked', 'supermoto', 'chopper', 'scootery', 'detske', 'ostatni'];

/** Shoda motorky s kategorií filtru (?kategorie= / cesta /katalog/<kat>). */
function katalogCategoryMatch($m, $category) {
    // Defensive cast — `category` může být v DB array nebo object (jsonb).
    $rawCat = $m['category'] ?? '';
    if (is_array($rawCat) || is_object($rawCat)) $rawCat = '';
    $cat = strtolower((string)$rawCat);
    $fc = strtolower((string)$category);
    $has = function ($needles) use ($cat) {
        foreach ($needles as $n) { if (strpos($cat, $n) !== false) return true; }
        return false;
    };
    switch ($fc) {
        case 'cestovni': return $has(['cestov', 'adventure', 'touring', 'enduro']);
        case 'sportovni': return $has(['sport', 'supersport', 'super sport']);
        case 'naked': return $has(['naked', 'street', 'roadster']);
        case 'supermoto': return $has(['supermoto', 'super moto', 'super-moto', 'motard']) || $cat === 'sm';
        case 'chopper': return $has(['chopper', 'cruiser', 'bobber']);
        case 'scootery': return $has(['scoot', 'skut', 'skút', 'moped']);
        case 'detske': return $has(['dets', 'dět']) || (isset($m['license_required']) && strtoupper($m['license_required']) === 'N');
        case 'ostatni': return $has(['ostatn', 'přívěs', 'privs', 'přív', 'trailer', 'other']);
    }
    return $cat === $fc;
}

/** Text, ve kterém hledá fulltext ?q= (model, značka, kategorie, popis, výbava). */
function katalogQueryHay($m) {
    // `features` z DB může být ARRAY (jsonb) — string konkatenace s polem v PHP 8 hází TypeError.
    $features = $m['features'] ?? '';
    if (is_array($features)) $features = implode(' ', array_map('strval', $features));
    $description = $m['description'] ?? '';
    if (is_array($description) || is_object($description)) $description = '';
    return mb_strtolower((string)($m['model'] ?? '') . ' ' . (string)($m['brand'] ?? '') . ' '
        . (string)($m['category'] ?? '') . ' ' . (string)$description . ' ' . (string)$features, 'UTF-8');
}

/** CS defaulty nových textů v2 katalogu (klíče f_* v bloku landing_katalog). */
function kfDefaults() {
    return [
        'f_dates' => 'Termín',
        'f_dates_title' => 'Kdy chceš vyrazit?',
        'f_dates_lead' => 'Vyber den vyzvednutí a vrácení — ukážeme jen motorky volné po celý termín i s cenou.',
        'f_filters' => 'Filtry',
        'f_calc' => 'Spočítat cenu',
        'f_close' => 'Zavřít',
        'f_any' => 'Nezáleží',
        'f_price' => 'Cena za den',
        'f_more' => 'Další možnosti',
        'f_sort_default' => 'Doporučené',
        'f_count_one' => '{n} motorka',
        'f_count_few' => '{n} motorky',
        'f_count_many' => '{n} motorek',
        'f_show' => 'Zobrazit {count}',
        'f_clear' => 'Zrušit vše',
        'f_remove' => 'Odebrat filtr: {label}',
        'f_active' => 'Aktivní filtry',
        'f_none_dates' => 'V tomto termínu teď podle filtrů nic volného není. Zkus jiné dny nebo uvolni filtry.',
        'f_calc_open' => 'Otevřít kalkulačku',
    ];
}

/** Texty v2 katalogu: f_* (CS default ← jazyk ← Velín) + sdílené z landing/kalkulačky. */
function kfTexts($sb) {
    static $c = null;
    if ($c !== null) return $c;
    $own = $sb->siteContent('landing_katalog', kfDefaults());
    $T = [];
    foreach (kfDefaults() as $k => $v) $T[$k] = lpPlain($own[$k] ?? $v) ?: $v;
    $lp = lpTexts($sb)['common'] ?? [];
    foreach (['fleet_title', 'fleet_all_cats', 'fleet_from', 'fleet_per_day', 'license', 'license_none', 'card_book', 'more_open', 'more_close'] as $k) {
        $T[$k] = lpPlain($lp[$k] ?? '');
    }
    return $c = $T;
}

/** Počet motorek s českým/jazykovým tvarem (1 / 2–4 / 5+). */
function kfCount($T, $n) {
    $k = $n === 1 ? 'f_count_one' : ($n >= 2 && $n <= 4 ? 'f_count_few' : 'f_count_many');
    return str_replace('{n}', (string)$n, $T[$k]);
}

/** Cena v měně návštěvníka bez desetinných míst (popisky slideru). */
function kfMoney($czk) {
    if (!function_exists('currencyConvert') || !function_exists('currencyDetect')) return number_format((float)$czk, 0, ',', "\u{00A0}") . "\u{00A0}Kč";
    $cur = strtoupper(currencyDetect());
    $meta = CURRENCY_META[$cur] ?? CURRENCY_META['CZK'];
    $v = currencyConvert($czk, $cur);
    return number_format(round((float)$v), 0, ',', "\u{00A0}") . "\u{00A0}" . $meta['symbol'];
}

/** Pevná kategorie z cesty (/katalog/<kat>) — jinde '' (hlavní katalog). */
function kfPathCategory($path) {
    return preg_match('#^/katalog/([a-z]+)$#', (string)$path, $mm) && in_array($mm[1], KF_CATS, true) ? $mm[1] : '';
}

/**
 * Filtrační data všech motorek pro JS (stejné predikáty jako PHP filtr v katalog.php).
 * c = kategorie z KF_CATS, rc = surová kategorie, l = skupiny ŘP, b = pobočka, kw = výkon
 * (null = nevyplněno → filtrem výkonu projde), pr = min. cena/den v Kč, kid = dětská
 * (neprojde filtrem „2 osoby“), qm = shoda s aktuálním ?q= (fulltext filtruje server).
 */
function kfMotoData($motos, $q) {
    $out = [];
    $ql = $q !== '' ? mb_strtolower($q, 'UTF-8') : '';
    $i = 0;
    foreach ((array)$motos as $m) {
        $idx = $i++;
        if (!is_array($m) || empty($m['id'])) continue;
        $cats = [];
        foreach (KF_CATS as $k) { if (katalogCategoryMatch($m, $k)) $cats[] = $k; }
        $raw = $m['category'] ?? '';
        if (is_array($raw) || is_object($raw)) $raw = '';
        $lc = strtolower((string)$raw);
        $pk = $m['power_kw'] ?? null;
        $out[] = [
            'id' => (string)$m['id'], 'i' => $idx, 'c' => $cats, 'rc' => $lc, 'l' => motoLicenseGroups($m),
            'b' => (string)($m['branch_id'] ?? ''), 'kw' => ($pk === null || $pk === '') ? null : (float)$pk,
            'pr' => getMinPrice($m), 'abs' => !empty($m['has_abs']),
            'kid' => strpos($lc, 'dets') !== false || strpos($lc, 'dět') !== false,
            'qm' => $ql === '' || strpos(katalogQueryHay($m), $ql) !== false,
        ];
    }
    return $out;
}

/** Assety v2 katalogu (kalkulačka + filtry) pro renderPage() meta. */
function kfPageMeta() {
    $m = kcPageMeta();
    $m['styles'][] = '/css/landing-catalog.css';
    $m['styles'][] = '/css/landing-catalog-cards.css';
    foreach (['/js/landing-catalog-sheet.js', '/js/landing-catalog-dates.js', '/js/landing-catalog.js'] as $s) $m['scripts'][] = $s;
    $m['body_class'] = trim(($m['body_class'] ?? '') . ' kf-page');
    return $m;
}

require_once __DIR__ . '/katalog-v2-ui.php';
