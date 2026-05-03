<?php
// ===== MotoGo24 — Master export pro Velín multilingvní překlad =====
// Endpoint: GET /api/master.php?token=<cms_admin_token>[&page=<slug>]
// Vrací JSON s CS masterem pro 1 nebo všechny CMS-driven stránky.
// Volá se z edge fn `translate-pages-master`, která pak posílá master
// na Anthropic API a uloží přeložené stromy do app_settings.pages_overlay.

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Robots-Tag: noindex, nofollow');

$sb = new SupabaseClient();

$expectedToken = (string)($sb->fetchSetting('cms_admin_token') ?? '');
$givenToken = (string)($_GET['token'] ?? '');
if ($expectedToken === '' || !hash_equals($expectedToken, $givenToken)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

// Mapa <page slug> → loader funkce, která vrátí CS master strom.
// Některé stránky mají master v data/*.php (jak-pujcit family),
// jiné v lang/pages_cs.php['pages'][slug] (home, kontakt, pujcovna, ...).
$dataDir = __DIR__ . '/../data/';
$loadDataPages = function (array $files) use ($dataDir) {
    $merged = [];
    foreach ($files as $f) {
        $path = $dataDir . $f;
        if (!is_file($path)) continue;
        $arr = require $path;
        if (is_array($arr)) $merged = array_merge($merged, $arr);
    }
    return $merged;
};

$dataPages = [
    'jak_pujcit_postup'             => ['postup-content-1.php',           'postup-content-2.php'],
    'jak_pujcit_vyzvednuti'         => ['prevzeti-content-1.php',         'prevzeti-content-2.php'],
    'jak_pujcit_vraceni_pujcovna'   => ['vraceni-pujcovna-content-1.php', 'vraceni-pujcovna-content-2.php'],
    'jak_pujcit_vraceni_jinde'      => ['vraceni-jinde-content-1.php',    'vraceni-jinde-content-2.php'],
    'jak_pujcit_cena'               => ['cena-content-1.php',             'cena-content-2.php'],
    'jak_pujcit_pristaveni'         => ['pristaveni-content-1.php',       'pristaveni-content-2.php'],
    'jak_pujcit_dokumenty'          => ['dokumenty-content-1.php',        'dokumenty-content-2.php'],
];

// Fallback master z lang/pages_cs.php pro stránky bez data/ souborů
$pagesCs = require __DIR__ . '/../lang/pages_cs.php';
$pagesCsTree = $pagesCs['pages'] ?? [];

$wantPage = $_GET['page'] ?? '';
$result = [];

if ($wantPage) {
    if (isset($dataPages[$wantPage])) {
        $result[$wantPage] = $loadDataPages($dataPages[$wantPage]);
    } elseif (isset($pagesCsTree[$wantPage])) {
        $result[$wantPage] = $pagesCsTree[$wantPage];
    } else {
        http_response_code(404);
        echo json_encode(['error' => 'unknown_page', 'page' => $wantPage]);
        exit;
    }
} else {
    // Vrátit všechny dostupné CMS-driven stránky.
    foreach ($dataPages as $slug => $files) {
        $result[$slug] = $loadDataPages($files);
    }
    // Zbývající stránky z pages_cs.php, které nemají data/ soubory
    foreach ($pagesCsTree as $slug => $tree) {
        if (!isset($result[$slug]) && is_array($tree)) {
            $result[$slug] = $tree;
        }
    }
}

echo json_encode([
    'ok' => true,
    'lang' => 'cs',
    'count' => count($result),
    'pages' => $result,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
