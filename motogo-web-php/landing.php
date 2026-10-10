<?php
// ===== MotoGo24 Web PHP — Landing v2 (mobilní, konverzní rozvržení) =====
// Nové pořadí sekcí pro klíčové stránky (/ a /pujcovna-motorek): hero bez
// tlačítek → akční panel (H1 + 2 CTA + USP chipy) → swipe karusel motorek →
// USP dlaždice → kroky → FAQ → CTA → … → SEO text sbalený dole.
// Zapíná se per jazyk (LANDING_V2_LANGS) — nejdřív jen ES na schválení,
// pak rozšířit o další jazyky (= přidat lang/v2/<lang>/landing.php).
// ?landing=v2 / ?landing=v1 = náhled/vypnutí (v2 jen v jazyce s překladem
// landing textů nebo v CS; page cache má query v klíči, canonical se nemění).
// Texty: siteContent('landing') — CS defaulty v lpDefaults(), překlady
// lang/v2/<lang>/landing.php ('pages.landing' — mimo pages_<lang>.php, aby je
// auto-překlad nepřepsal), Velín CMS klíče web.landing.*. Blok 'landing' NEDÁVAT
// do lang/pages_cs.php. Render sekcí: landing-sections.php, landing-trust.php
// (důvody, recenze, „jen u nás“, pobočky — defaulty data/landing-trust.php).

const LANDING_V2_LANGS = ['es'];

function landingV2Enabled() {
    static $on = null;
    if ($on !== null) return $on;
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $q = isset($_GET['landing']) ? (string)$_GET['landing'] : '';
    if ($q === 'v1') return $on = false;
    if ($q === 'v2') return $on = landingV2TextsReady($lang);
    return $on = in_array($lang, LANDING_V2_LANGS, true) && landingV2TextsReady($lang);
}

/**
 * v2 jen tam, kde má jazyk texty všech bloků stránky (lang/v2/<lang>/*.php) — jinak
 * zůstane přeložená v1 (nikdy české texty na cizí stránce). Stránka = kanonická
 * cesta z routeru ($path v index.php). CS má defaulty v kódu.
 */
function landingV2TextsReady($lang) {
    if ($lang === 'cs') return true;
    $p = (string)($GLOBALS['path'] ?? '/');
    $need = ['landing', 'reviews'];
    if (strpos($p, '/katalog') === 0) $need[] = 'katalog';
    elseif (strpos($p, '/pobocky') === 0) array_push($need, 'pobocky', 'pobocky-v2');
    elseif (strpos($p, '/jak-pujcit') === 0 || $p === '/kontakt') $need[] = 'info';
    foreach ($need as $f) {
        if (!is_file(__DIR__ . '/lang/v2/' . basename($lang) . '/' . $f . '.php')) return false;
    }
    return true;
}

/** Assety v2 pro renderPage() meta. */
function lpPageMeta() {
    return ['styles' => ['/css/landing.css', '/css/landing-trust.css', '/css/landing-routes.css'], 'scripts' => ['/js/landing.js'], 'body_class' => 'lp-v2'];
}

/** CS defaulty textů v2. */
function lpDefaults() {
    $cta = ['cta_primary' => ['label' => 'REZERVOVAT', 'href' => '/rezervace'], 'cta_secondary' => ['label' => 'VYBRAT MOTORKU', 'href' => '/katalog']];
    $chips = ['Bez kauce', 'Výbava v ceně', 'Vyzvednutí nonstop'];
    return [
        'common' => [
            'usp_title' => 'Proč MotoGo24',
            'fleet_title' => 'Vyber si motorku',
            'fleet_all' => 'Zobrazit vše',
            'fleet_all_card' => 'Všech {n} motorek v katalogu',
            'fleet_from' => 'od {price}',
            'fleet_per_day' => '/ den',
            'fleet_all_cats' => 'Vše',
            'fleet_prev' => 'Předchozí motorky',
            'fleet_next' => 'Další motorky',
            'license' => 'ŘP {g}',
            'explore_title' => 'Prozkoumej MotoGo24',
            'more_open' => 'Číst dál',
            'more_close' => 'Zobrazit méně',
            'sticky_reserve' => 'Rezervovat',
            'sticky_motos' => 'Motorky',
            'price_chip' => 'Motorky od {price} / den',
            // Jen u jiné měny než CZK: ceny jsou orientační přepočet, platí se v Kč
            'fx_note' => 'Ceny v cizí měně jsou orientační, platba probíhá v Kč.',
            'card_book' => 'Rezervovat',
            'license_none' => 'Bez ŘP',
            // Volitelné (prázdné = nezobrazí se): mikrotext pod CTA, nabídka pod panelem, sezónní poznámka
            'assurance' => '',
            'offer' => '',
            'season_note' => '',
            // Volitelná náhrada CTA pásu (prázdný title = CTA z CMS stránky)
            'cta' => ['title' => '', 'text' => '', 'buttons' => []],
        ] + lpTrustDefaults(),
        'home' => $cta + [
            // Krátký H1 do panelu (prázdné = H1 z web.home.h1; vyplněné → dlouhé H1 jde do H2 sekce „O nás“)
            'h1' => '',
            'lead' => '',
            // Volitelná náhrada eyebrow textu v hero (prázdné = web.home.hero.eyebrow)
            'hero_eyebrow' => '',
            'chips' => $chips,
            'usp' => [
                ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'a bez skrytých poplatků'],
                ['icon' => 'gfx/vyber-vybavu.svg', 'title' => 'Výbava v ceně', 'text' => 'helma, bunda, kalhoty a rukavice'],
                ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop', 'text' => 'vyzvednutí i vrácení dle rezervace'],
                ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => 'Bez limitu km', 'text' => 'i do zahraničí'],
                ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online rezervace', 'text' => 'na pár kliknutí'],
                ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Od {price}', 'text' => 'za den', 'price' => true],
            ],
            'about_title' => 'O půjčovně MotoGo24',
            // Vlastní krátké kroky (prázdné = kroky z CMS web.home.process.*)
            'steps_title' => '',
            'steps' => [],
        ],
        'pujcovna' => $cta + [
            // Krátký H1 (prázdné = web.pujcovna.intro.h1; vyplněné → CMS H1 jde do H2 sekce „Více o nás“)
            'h1' => '',
            // Vlastní USP dlaždice (prázdné = CMS web.pujcovna.benefits.items)
            'usp' => [],
            'lead' => 'Bez kauce, s výbavou v ceně a vyzvednutím nonstop. Rezervuj online na pár kliknutí.',
            'chips' => $chips,
            'about_title' => 'Více o naší půjčovně',
            'steps_title' => '',
            'steps' => [],
        ],
    ];
}

/** Sloučené texty v2 (CS default ← jazykový overlay ← DB ← Velín CMS). */
function lpTexts($sb) {
    static $c = null;
    if ($c === null) $c = $sb->siteContent('landing', lpDefaults());
    return $c;
}

/** Skalár → string (poškozená CMS hodnota typu pole nesmí shodit stránku). */
function lpS($v) {
    return is_scalar($v) ? (string)$v : '';
}

/** Prostý text z CMS HTML (&nbsp;, entity, tagy) — pro escapované výstupy. */
function lpPlain($v) {
    $s = html_entity_decode(strip_tags(lpS($v)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
    return trim(preg_replace('/[\s\x{00A0}]+/u', ' ', $s));
}

/** Cena „od“ bez haléřů/centů — zaokrouhleno NAHORU (nikdy nižší než skutečná). */
function lpMoneyFrom($czk) {
    $czk = (float)$czk;
    if ($czk <= 0) return '';
    if (!function_exists('currencyConvert') || !function_exists('currencyDetect')) return formatPrice($czk);
    $cur = strtoupper(currencyDetect());
    $meta = CURRENCY_META[$cur] ?? CURRENCY_META['CZK'];
    $v = currencyConvert($czk, $cur);
    if ($v === null) return formatPrice($czk);
    return number_format(ceil((float)$v), 0, ',', "\u{00A0}") . "\u{00A0}" . $meta['symbol'];
}

/** Motorky pro karusel — bez kategorie „ostatní“ (vozík) a bez fotky. */
function lpFleet($motos) {
    $out = [];
    foreach ((array)$motos as $m) {
        if (!is_array($m) || ($m['category'] ?? '') === 'ostatni') continue;
        if (empty($m['image_url']) && empty($m['images'][0])) continue;
        $out[] = $m;
    }
    return $out;
}

/** Cenová kotva „od X / den“ — bez dětských motorek (jinak by lákala na cenu, kterou dospělý nedostane). */
function lpMinPrice($motos) {
    $min = 0;
    foreach (lpFleet($motos) as $m) {
        if (($m['category'] ?? '') === 'detske') continue;
        $p = getMinPrice($m);
        if ($p > 0 && ($min === 0 || $p < $min)) $min = $p;
    }
    return $min;
}

/** Kategorie, které má router (index.php) — jiné odkazujeme přes filtr katalogu. */
function lpCategoryHref($cat) {
    $known = ['cestovni', 'sportovni', 'naked', 'supermoto', 'chopper', 'scootery', 'detske', 'ostatni'];
    return in_array($cat, $known, true) ? '/katalog/' . $cat : '/katalog?kategorie=' . rawurlencode($cat);
}

/** Kroky pro v2: vlastní krátké z landing textů, jinak CMS kroky stránky. Vrací [steps, keyBase]. */
function lpSteps($T, $page, $cmsSteps, $cmsKeyBase) {
    $own = $T[$page]['steps'] ?? [];
    if (is_array($own) && count(array_filter($own, 'is_array')) > 0) return [$own, 'web.landing.' . $page . '.steps'];
    return [is_array($cmsSteps) ? $cmsSteps : [], $cmsKeyBase];
}

/** translations JSONB jako pole (REST může vrátit string). */
function lpTr($row) {
    $tr = $row['translations'] ?? [];
    if (is_string($tr)) $tr = json_decode($tr, true);
    return is_array($tr) ? $tr : [];
}

/** Poznámka k orientačním cenám v cizí měně (u CZK nic). */
function lpFxNote($T) {
    if (!function_exists('currencyDetect') || strtoupper(currencyDetect()) === 'CZK' || lpPlain($T['fx_note'] ?? '') === '') return '';
    return '<p class="lp-fx" data-cms-key="web.landing.common.fx_note">' . he(lpS($T['fx_note'])) . '</p>';
}

function lpIcon($name) {
    $p = [
        'cal' => '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>',
        'moto' => '<circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5 9 10h5l4.5 6.5M14 10l-2-4h3M9 10l-1.5-2.5"/>',
        'check' => '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
        'arrow' => '<path d="M5 12h14M13 6l6 6-6 6"/>',
        'pin' => '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
    ];
    return '<svg class="lp-ico" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . ($p[$name] ?? '') . '</svg>';
}

require_once __DIR__ . '/landing-sections.php';
require_once __DIR__ . '/landing-trust.php';
require_once __DIR__ . '/landing-routes.php';
require_once __DIR__ . '/data/landing-trust.php';
require_once __DIR__ . '/data/reviews.php';

/** CTA pás: vlastní z landing textů (vyplněný title), jinak CMS stránky. Vrací [cta, keyBase]. */
function lpCta($T, $cmsCta, $cmsKeyBase) {
    $own = $T['common']['cta'] ?? [];
    if (is_array($own) && lpPlain($own['title'] ?? '') !== '') return [$own, 'web.landing.common.cta'];
    return [is_array($cmsCta) ? $cmsCta : [], $cmsKeyBase];
}
