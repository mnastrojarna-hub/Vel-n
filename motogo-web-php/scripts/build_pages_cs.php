<?php
// ===== MotoGo24 — Build lang/pages_cs.php =====
// Extrahuje strukturu defaults z vsech CMS stranek a vyrobi pages_cs.php
// jako referenci pro paralelni preklad do en/de/es/fr/nl/pl.
//
// Spusti: php motogo-web-php/scripts/build_pages_cs.php
// Vystup: motogo-web-php/lang/pages_cs.php

// Stub minimalnich konstant abychom se nezaviseli na config.php
if (!defined('BASE_URL')) define('BASE_URL', '');
if (!defined('PHONE')) define('PHONE', '+420 774 256 271');
if (!defined('PHONE_LINK')) define('PHONE_LINK', 'tel:+420774256271');
if (!defined('EMAIL_USER')) define('EMAIL_USER', 'info');
if (!defined('EMAIL_DOMAIN')) define('EMAIL_DOMAIN', 'motogo24.cz');
if (!defined('EMAIL_FULL')) define('EMAIL_FULL', 'info@motogo24.cz');
if (!defined('ADDRESS')) define('ADDRESS', 'Mezná 9, 393 01 Pelhřimov');
if (!defined('COMPANY_NAME')) define('COMPANY_NAME', 'Bc. Petra Semorádová');
if (!defined('COMPANY_ADDRESS')) define('COMPANY_ADDRESS', 'Mezná 9, 393 01 Pelhřimov');
if (!defined('COMPANY_ICO')) define('COMPANY_ICO', '21874263');
if (!defined('FB_URL')) define('FB_URL', '#');
if (!defined('IG_URL')) define('IG_URL', '#');
if (!defined('LOGO_SVG')) define('LOGO_SVG', 'gfx/logo.svg');
if (!defined('SUPABASE_URL')) define('SUPABASE_URL', '');
if (!defined('SUPABASE_ANON_KEY')) define('SUPABASE_ANON_KEY', '');

$dataDir = __DIR__ . '/../data/';
$pagesDir = __DIR__ . '/../pages/';

$pages = [];

// 1) jak_pujcit_cena (data/cena-content-1.php + 2.php)
$pages['jak_pujcit_cena'] = array_merge(
    require $dataDir . 'cena-content-1.php',
    require $dataDir . 'cena-content-2.php'
);

// 2) jak_pujcit_dokumenty
$pages['jak_pujcit_dokumenty'] = array_merge(
    require $dataDir . 'dokumenty-content-1.php',
    require $dataDir . 'dokumenty-content-2.php'
);

// 3) jak_pujcit_pristaveni
$pages['jak_pujcit_pristaveni'] = array_merge(
    require $dataDir . 'pristaveni-content-1.php',
    require $dataDir . 'pristaveni-content-2.php'
);

// 4) jak_pujcit_vraceni_jinde
$pages['jak_pujcit_vraceni_jinde'] = array_merge(
    require $dataDir . 'vraceni-jinde-content-1.php',
    require $dataDir . 'vraceni-jinde-content-2.php'
);

// 5) faq (3 faq-content-* soubory + meta z 3.)
$p1 = require $dataDir . 'faq-content-1.php';
$p2 = require $dataDir . 'faq-content-2.php';
$p3 = require $dataDir . 'faq-content-3.php';
$meta = $p3['__meta'];
unset($p3['__meta']);
$cats = [];
foreach ([$p1, $p2, $p3] as $part) {
    foreach ($part as $catKey => $catData) {
        if (!isset($cats[$catKey])) $cats[$catKey] = ['label' => $catData['label'], 'items' => []];
        $cats[$catKey]['items'] = array_merge($cats[$catKey]['items'], $catData['items']);
    }
}
$pages['faq'] = [
    'seo' => $meta['seo'],
    'h1' => $meta['h1'],
    'closing' => $meta['closing'],
    'cta' => $meta['cta'],
    'categories' => $cats,
];

// 6) Stranky kde je $defaults inline v page/*.php — extrahujeme regulárním výrazem
//    NEni cele bezpecne (PHP variabilni interpolace), ale staci pro konstantni strings.
$inlinePages = [
    'home' => 'home.php',
    'pujcovna' => 'pujcovna.php',
    'kontakt' => 'kontakt.php',
    'jak_pujcit' => 'jak-pujcit.php',
    'jak_pujcit_postup' => 'jak-pujcit-postup.php',
    'jak_pujcit_vyzvednuti' => 'jak-pujcit-vyzvednuti.php',
    'jak_pujcit_vraceni_pujcovna' => 'jak-pujcit-vraceni-pujcovna.php',
    'poukazy' => 'poukazy.php',
];

// Stub class deklarovat JEDNOU pred prvni evaluaci
class SupabaseClient {
    public function __call($name, $args) {
        if ($name === 'siteContent') return $args[1] ?? [];
        return [];
    }
    public function fetchMotos() { return []; }
    public function fetchCmsPages($tag = null) { return []; }
    public function fetchPublicReviews($limit = 6) { return []; }
}

// Stuby pro i18n helpery — vrati klic jako string aby se eval nezadrhl
if (!function_exists('t')) { function t($k, $params = null) { return is_array($k) ? $k : (string)$k; } }
if (!function_exists('te')) { function te($k, $params = null) { return (string)$k; } }
if (!function_exists('i18nDetectLanguage')) { function i18nDetectLanguage() { return 'cs'; } }
if (!function_exists('i18nDictionary')) { function i18nDictionary() { return []; } }
if (!function_exists('i18nHtmlLang')) { function i18nHtmlLang() { return 'cs-CZ'; } }
if (!function_exists('i18nOgLocale')) { function i18nOgLocale() { return 'cs_CZ'; } }
if (!function_exists('renderLanguageSwitcher')) { function renderLanguageSwitcher() { return ''; } }

// Pomocne globalne potrebne funkce ktere stranky volaji (renderBreadcrumb / renderPage)
function renderBreadcrumb($items) { return ''; }
function renderPage(...$args) { /* no-op */ }
function renderWbox(...$args) { return ''; }
function renderMotoCard(...$args) { return ''; }
function renderBlogCard(...$args) { return ''; }
function renderFaqSection(...$args) { return ''; }
function renderFaqItem(...$args) { return ''; }
function renderCta(...$args) { return ''; }
function renderTable(...$args) { return ''; }
function imgUrl($x) { return ''; }
function sanitizeHtml($x) { return $x; }
function getMinPrice($x) { return 0; }
function calcPrice(...$a) { return 0; }
function formatDate($x) { return $x; }
function formatPrice($x) { return $x; }

/** Extract '$defaults = [...]' jako string s respektovanim parovych [] (bracket-aware) */
function extractDefaultsBlock($source) {
    $needle = '$defaults = [';
    $pos = strpos($source, $needle);
    if ($pos === false) return null;
    $start = $pos + strlen('$defaults = ');
    $i = $start;
    $depth = 0;
    $len = strlen($source);
    $inStr = false; $strCh = ''; $esc = false;
    while ($i < $len) {
        $c = $source[$i];
        if ($inStr) {
            if ($esc) { $esc = false; $i++; continue; }
            if ($c === '\\') { $esc = true; $i++; continue; }
            if ($c === $strCh) { $inStr = false; }
            $i++;
            continue;
        }
        if ($c === "'" || $c === '"') { $inStr = true; $strCh = $c; $i++; continue; }
        if ($c === '[') { $depth++; $i++; continue; }
        if ($c === ']') { $depth--; $i++; if ($depth === 0) return substr($source, $start, $i - $start); continue; }
        $i++;
    }
    return null;
}

foreach ($inlinePages as $slug => $file) {
    $path = $pagesDir . $file;
    if (!is_file($path)) continue;
    $source = file_get_contents($path);
    $block = extractDefaultsBlock($source);
    if ($block === null) {
        fwrite(STDERR, "[WARN] No \$defaults block found in {$slug}\n");
        continue;
    }
    // Eval JEN samotny array literal — prostredi je clean, zadne side effecty
    try {
        $evaluated = null;
        eval('$evaluated = ' . $block . ';');
        if (is_array($evaluated)) {
            $pages[$slug] = $evaluated;
        } else {
            fwrite(STDERR, "[WARN] Evaluated block not array for {$slug}\n");
        }
    } catch (\Throwable $e) {
        fwrite(STDERR, "[WARN] Eval failed for {$slug}: " . $e->getMessage() . "\n");
    }
}

// Vystup do pages_cs.php — var_export s normalizaci
$out = "<?php\n// ====== MotoGo24 — pages_cs.php (vygenerovano build_pages_cs.php) ======\n";
$out .= "// CS reference strom — slouzi jako template pro paralelni preklad do ostatnich jazyku.\n";
$out .= "// Pro CS samotne se nepouziva (defaults se nactou primo z pages/*.php a data/*.php),\n";
$out .= "// ale je-li primitomny, deep_merge prebije CS hodnoty stejnymi (tj. neni rozdilu).\n";
$out .= "// Pro non-CS jazyky vytvor stejnou strukturu v pages_<lang>.php s prelozenymi hodnotami.\n\n";
$out .= "return [\n    'pages' => " . _exportArray($pages, 1) . ",\n];\n";

file_put_contents(__DIR__ . '/../lang/pages_cs.php', $out);
echo "OK: lang/pages_cs.php zapsan (" . count($pages) . " stranek)\n";

/** Pekne formatovany var_export nahrada (pres rekurzi). */
function _exportArray($v, $indent = 0) {
    $pad = str_repeat('    ', $indent);
    if (is_array($v)) {
        if (empty($v)) return '[]';
        $isList = function_exists('array_is_list') ? array_is_list($v) : (function ($a) {
            $i = 0; foreach ($a as $k => $_) if ($k !== $i++) return false; return true;
        })($v);
        $lines = [];
        foreach ($v as $k => $vv) {
            $line = $pad . '    ';
            if (!$isList) {
                $line .= var_export((string)$k, true) . ' => ';
            }
            $line .= _exportArray($vv, $indent + 1);
            $lines[] = $line;
        }
        return "[\n" . implode(",\n", $lines) . ",\n" . $pad . ']';
    }
    return var_export($v, true);
}
