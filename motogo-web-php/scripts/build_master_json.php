<?php
// CLI: zregeneruje supabase/functions/translate-pages-master/master_cs.ts
// ze všech CS masterů (data/*.php + lang/pages_cs.php). Edge fn z toho čte
// jako fallback, když je live `/api/master.php` endpoint nedostupný.
//
// Spuštění z root repa:
//   php motogo-web-php/scripts/build_master_json.php

$root = realpath(__DIR__ . '/..');
$dataDir = $root . '/data/';
$pagesCsPath = $root . '/lang/pages_cs.php';
$outPath = realpath(__DIR__ . '/../..') . '/supabase/functions/translate-pages-master/master_cs.ts';

$dataPages = [
    'jak_pujcit_postup'             => ['postup-content-1.php',           'postup-content-2.php'],
    'jak_pujcit_vyzvednuti'         => ['prevzeti-content-1.php',         'prevzeti-content-2.php'],
    'jak_pujcit_vraceni_pujcovna'   => ['vraceni-pujcovna-content-1.php', 'vraceni-pujcovna-content-2.php'],
    'jak_pujcit_vraceni_jinde'      => ['vraceni-jinde-content-1.php',    'vraceni-jinde-content-2.php'],
    'jak_pujcit_cena'               => ['cena-content-1.php',             'cena-content-2.php'],
    'jak_pujcit_pristaveni'         => ['pristaveni-content-1.php',       'pristaveni-content-2.php'],
    'jak_pujcit_dokumenty'          => ['dokumenty-content-1.php',        'dokumenty-content-2.php'],
];

$result = [];
foreach ($dataPages as $slug => $files) {
    $merged = [];
    foreach ($files as $f) {
        $p = $dataDir . $f;
        if (!is_file($p)) continue;
        $arr = require $p;
        if (is_array($arr)) $merged = array_merge($merged, $arr);
    }
    $result[$slug] = $merged;
}

if (is_file($pagesCsPath)) {
    $pagesCs = require $pagesCsPath;
    $tree = $pagesCs['pages'] ?? [];
    foreach ($tree as $slug => $sub) {
        if (!isset($result[$slug]) && is_array($sub)) {
            $result[$slug] = $sub;
        }
    }
}

$json = json_encode([
    'ok' => true,
    'lang' => 'cs',
    'count' => count($result),
    'pages' => $result,
    'generated_at' => date('c'),
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);

$ts = "// AUTO-GENEROVÁNO z motogo-web-php/scripts/build_master_json.php\n"
    . "// Nezapisuj ručně. Regeneruj příkazem:\n"
    . "//   php motogo-web-php/scripts/build_master_json.php\n"
    . "// Slouží jako bundled fallback pro translate-pages-master, když live\n"
    . "// `/api/master.php` endpoint není dostupný (deploy lag, SSL cert mismatch, …).\n\n"
    . "export const MASTER_CS_BUNDLED = " . $json . " as const\n";

file_put_contents($outPath, $ts);

echo "OK: zapsáno {$outPath}\n";
echo "Stránky: " . implode(', ', array_keys($result)) . "\n";
echo "Velikost: " . round(strlen($ts) / 1024, 1) . " KB\n";
