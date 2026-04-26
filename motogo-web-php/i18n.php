<?php
// ===== MotoGo24 Web PHP — i18n core =====
// Detekce jazyka, načítání slovníků, t() helper.
//
// Priorita: GET ?lang=xx → COOKIE mg_web_lang → Accept-Language → 'cs'
// Cookie se nastavuje při ?lang= a žije 365 dní.
// Podporované jazyky se shodují s Flutter appkou: cs, en, de, es, fr, nl, pl.

require_once __DIR__ . '/config.php';

const I18N_SUPPORTED = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl'];
const I18N_DEFAULT = 'cs';
const I18N_COOKIE = 'mg_web_lang';

const I18N_LANGUAGES = [
    'cs' => ['flag' => '🇨🇿', 'name' => 'Čeština'],
    'en' => ['flag' => '🇬🇧', 'name' => 'English'],
    'de' => ['flag' => '🇩🇪', 'name' => 'Deutsch'],
    'es' => ['flag' => '🇪🇸', 'name' => 'Español'],
    'fr' => ['flag' => '🇫🇷', 'name' => 'Français'],
    'nl' => ['flag' => '🇳🇱', 'name' => 'Nederlands'],
    'pl' => ['flag' => '🇵🇱', 'name' => 'Polski'],
];

/**
 * Detekuje a (případně) uloží jazyk pro aktuální request.
 * Volat co nejdřív v hlavním entry pointu (index.php, sitemap.php).
 */
function i18nDetectLanguage() {
    static $cached = null;
    if ($cached !== null) return $cached;

    // 1) ?lang=xx — explicitní volba (uloží do cookie a zruší query string)
    $fromQuery = isset($_GET['lang']) ? strtolower(substr((string)$_GET['lang'], 0, 2)) : '';
    if ($fromQuery && in_array($fromQuery, I18N_SUPPORTED, true)) {
        // Uložit cookie (365 dní, /, secure pokud HTTPS)
        $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        if (!headers_sent()) {
            setcookie(I18N_COOKIE, $fromQuery, [
                'expires' => time() + 365 * 24 * 3600,
                'path' => '/',
                'secure' => $secure,
                'httponly' => false,
                'samesite' => 'Lax',
            ]);
        }
        $_COOKIE[I18N_COOKIE] = $fromQuery;
        $cached = $fromQuery;
        return $cached;
    }

    // 2) Cookie
    $fromCookie = $_COOKIE[I18N_COOKIE] ?? '';
    if ($fromCookie && in_array($fromCookie, I18N_SUPPORTED, true)) {
        $cached = $fromCookie;
        return $cached;
    }

    // 3) Accept-Language hlavička
    $acceptLang = $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '';
    if ($acceptLang) {
        // Vezmi první 2 znaky první jazykové preference (např. "cs-CZ,cs;q=0.9,en;q=0.8" → "cs")
        $first = strtolower(substr(preg_replace('/[^a-zA-Z\-,;]/', '', $acceptLang), 0, 2));
        if (in_array($first, I18N_SUPPORTED, true)) {
            $cached = $first;
            return $cached;
        }
    }

    // 4) Default
    $cached = I18N_DEFAULT;
    return $cached;
}

/**
 * Vrátí celý slovník pro aktuální jazyk (s fallbackem na CS pro chybějící klíče).
 * Slovník se skládá ze 2 souborů per jazyk:
 *   - lang/<code>.php       — chrome / UI texty (header, footer, menu, common, atd.)
 *   - lang/pages_<code>.php — strukturované defaults velkých CMS stránek (pages.*)
 * Oba se rekurzivně mergují s CS fallbackem.
 */
function i18nDictionary() {
    static $cache = [];
    $lang = i18nDetectLanguage();
    if (isset($cache[$lang])) return $cache[$lang];

    $loadFile = function ($path) {
        if (!is_file($path)) return [];
        $data = require $path;
        return is_array($data) ? $data : [];
    };
    $loadLang = function ($code) use ($loadFile) {
        $base = $loadFile(__DIR__ . '/lang/' . $code . '.php');
        $pages = $loadFile(__DIR__ . '/lang/pages_' . $code . '.php');
        if (!empty($pages)) {
            // pages_xx.php vrací buď [ 'pages' => [...] ] nebo rovnou strom — sjednotíme.
            if (isset($pages['pages']) && is_array($pages['pages'])) {
                $base['pages'] = isset($base['pages']) && is_array($base['pages'])
                    ? _i18nDeepMerge($base['pages'], $pages['pages'])
                    : $pages['pages'];
            } else {
                $base['pages'] = isset($base['pages']) && is_array($base['pages'])
                    ? _i18nDeepMerge($base['pages'], $pages)
                    : $pages;
            }
        }
        return $base;
    };

    $current = $loadLang($lang);
    if ($lang === I18N_DEFAULT) {
        $cache[$lang] = $current;
        return $current;
    }

    // Hluboký merge nad CS fallbackem (aby chybějící klíče propadly na CS)
    $fallback = $loadLang(I18N_DEFAULT);
    $cache[$lang] = _i18nDeepMerge($fallback, $current);
    return $cache[$lang];
}

/** Hluboký merge: hodnoty z $b přepisují $a; lists se přepíší celé, asoc. pole se mergují. */
function _i18nDeepMerge($a, $b) {
    if (!is_array($a)) return $b;
    if (!is_array($b)) return $b;
    // List heuristika — array_is_list pro PHP 8.1+, jinak ruční check
    $isList = function ($arr) {
        if (function_exists('array_is_list')) return array_is_list($arr);
        if (empty($arr)) return true;
        $i = 0;
        foreach ($arr as $k => $_) { if ($k !== $i++) return false; }
        return true;
    };
    if ($isList($b)) return $b;
    $out = $a;
    foreach ($b as $k => $v) {
        $out[$k] = (isset($a[$k]) && is_array($a[$k]) && is_array($v))
            ? _i18nDeepMerge($a[$k], $v)
            : $v;
    }
    return $out;
}

/**
 * Překlad. $key je tečkový název klíče (např. 'menu.rental' nebo 'pages.home.h1').
 * Podporuje hluboké zanořené pole (vrací mixed: string nebo array).
 * $params: asociativní pole pro {placeholder} substituci (jen u stringu).
 * Pokud klíč neexistuje, vrátí samotný klíč (debug-friendly).
 */
function t($key, $params = null) {
    $dict = i18nDictionary();
    // Nejdřív rovný lookup (rychlá cesta pro existující klíče s tečkami v názvu)
    if (isset($dict[$key])) {
        $raw = $dict[$key];
    } else {
        // Zkus tečkovou navigaci do vnořeného pole (např. 'pages.home.h1')
        $parts = explode('.', $key);
        $node = $dict;
        $found = true;
        foreach ($parts as $p) {
            if (is_array($node) && array_key_exists($p, $node)) {
                $node = $node[$p];
            } else {
                $found = false; break;
            }
        }
        $raw = $found ? $node : $key;
    }
    if (is_string($raw) && is_array($params) && !empty($params)) {
        foreach ($params as $k => $v) {
            $raw = str_replace('{' . $k . '}', (string)$v, $raw);
        }
    }
    return $raw;
}

/**
 * HTML-safe překlad — htmlspecialchars-uje výsledek (pouze string).
 * Pole vrátí prázdný string (volat te() smí jen pro stringové klíče).
 */
function te($key, $params = null) {
    $v = t($key, $params);
    if (!is_string($v)) return '';
    return htmlspecialchars($v, ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

/**
 * BCP 47 locale tag pro <html lang="..."> a meta og:locale.
 */
function i18nHtmlLang() {
    $lang = i18nDetectLanguage();
    $map = [
        'cs' => 'cs-CZ', 'en' => 'en-GB', 'de' => 'de-DE', 'es' => 'es-ES',
        'fr' => 'fr-FR', 'nl' => 'nl-NL', 'pl' => 'pl-PL',
    ];
    return $map[$lang] ?? 'cs-CZ';
}

/**
 * og:locale ve formátu "xx_YY"
 */
function i18nOgLocale() {
    return str_replace('-', '_', i18nHtmlLang());
}

/**
 * Vyrenderuje language switcher tlačítko + dropdown.
 * Cílová URL = aktuální cesta + ?lang=xx.
 */
function renderLanguageSwitcher() {
    $current = i18nDetectLanguage();
    $cur = I18N_LANGUAGES[$current] ?? I18N_LANGUAGES[I18N_DEFAULT];

    // Aktuální URL bez ?lang=, abychom mohli přidat náš param
    $reqUri = $_SERVER['REQUEST_URI'] ?? '/';
    $parts = parse_url($reqUri);
    $path = $parts['path'] ?? '/';
    $existingQuery = [];
    if (!empty($parts['query'])) {
        parse_str($parts['query'], $existingQuery);
        unset($existingQuery['lang']);
    }
    $baseQuery = !empty($existingQuery) ? ('&' . http_build_query($existingQuery)) : '';

    $items = '';
    foreach (I18N_LANGUAGES as $code => $info) {
        $href = htmlspecialchars($path . '?lang=' . $code . $baseQuery);
        $isActive = ($code === $current);
        $cls = 'lang-item' . ($isActive ? ' active' : '');
        $check = $isActive ? '<span class="lang-check" aria-hidden="true">✓</span>' : '';
        $items .= '<li><a class="' . $cls . '" href="' . $href . '" hreflang="' . $code . '" lang="' . $code . '">'
            . '<span class="lang-flag" aria-hidden="true">' . $info['flag'] . '</span>'
            . '<span class="lang-name">' . htmlspecialchars($info['name']) . '</span>'
            . $check
            . '</a></li>';
    }

    $globe = '<svg class="sw-icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="9"></circle><path d="M3 12h18"></path><path d="M12 3a14 14 0 0 1 0 18"></path><path d="M12 3a14 14 0 0 0 0 18"></path></svg>';
    return '<div class="lang-switcher" data-lang-switcher>'
        . '<button type="button" class="lang-toggle" aria-haspopup="true" aria-expanded="false" aria-label="' . te('lang.select') . '" title="' . te('lang.select') . '">'
            . $globe
            . '<span class="lang-code">' . strtoupper($current) . '</span>'
            . '<span class="lang-arrow" aria-hidden="true">▾</span>'
        . '</button>'
        . '<ul class="lang-dropdown" role="menu">' . $items . '</ul>'
    . '</div>';
}

/**
 * Vrátí přeloženou hodnotu pole z DB řádku, který má JSONB sloupec `translations`
 * (struktura `{ "en": {"title":"..."}, "de": {...}, ... }`). Český text v původním
 * sloupci slouží jako fallback. Auto-překlady plní edge funkce `translate-content`
 * po uložení dat z Velínu.
 *
 * @param array|null $row    Řádek z DB (asociativní pole), např. cms_pages, products...
 * @param string     $field  Název sloupce (title, content, description, value, ...)
 * @param string|null $lang  Cílový jazyk (default: aktuální detekovaný)
 * @return string            Přeložený text nebo český fallback (nikdy null)
 */
function localized($row, $field, $lang = null) {
    if (!is_array($row)) return '';
    $fallback = isset($row[$field]) ? (string)$row[$field] : '';
    $lang = $lang ?: i18nDetectLanguage();
    // Pro češtinu vždy fallback (původní sloupec).
    if ($lang === I18N_DEFAULT) return $fallback;
    $tr = $row['translations'] ?? null;
    if (is_string($tr)) {
        // Pokud DB klient vrátil JSON jako string (REST), dekódujeme.
        $decoded = json_decode($tr, true);
        if (is_array($decoded)) $tr = $decoded; else $tr = null;
    }
    if (is_array($tr) && isset($tr[$lang]) && is_array($tr[$lang]) && isset($tr[$lang][$field])) {
        $val = $tr[$lang][$field];
        if (is_string($val) && $val !== '') return $val;
    }
    return $fallback;
}

/**
 * HTML-safe varianta `localized()` (htmlspecialchars).
 * Pozor: NEPOUŽÍVAT pro pole obsahující povolené HTML (např. blog content) — pro ta volat
 * `localized()` + `sanitizeHtml()` (z components.php).
 */
function localizedEsc($row, $field, $lang = null) {
    return htmlspecialchars(localized($row, $field, $lang), ENT_QUOTES | ENT_HTML5, 'UTF-8');
}
