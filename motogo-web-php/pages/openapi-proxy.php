<?php
// ===== /.well-known/openapi.yaml + /.well-known/openapi.json + /openapi.json =====
// Proxy + 1h file cache pro OpenAPI 3.1 spec hostovaný v Supabase Edge Function
// public-api. Účelem je dát AI agentům (ChatGPT plugins, Claude tools) jednu
// důvěryhodnou URL na motogo24.cz origin, takže nemusí bouncovat na Supabase
// doménu (lepší pro CSP whitelisty agentů a pro důvěru).
//
// Pokud Supabase nedostupný, fallback na minimální stub s externalDocs odkazem.

require_once __DIR__ . '/../config.php';

$wantYaml = (strpos($_SERVER['REQUEST_URI'] ?? '', '.yaml') !== false);
$cacheDir = sys_get_temp_dir();
$cacheFile = $cacheDir . '/motogo24_openapi_' . ($wantYaml ? 'yaml' : 'json') . '.cache';
$cacheTtl = 3600; // 1 hodina

$src = SUPABASE_URL . '/functions/v1/public-api/api/v1/openapi.json';

function _proxy_send($content, $contentType) {
    header('Content-Type: ' . $contentType . '; charset=utf-8');
    header('Cache-Control: public, max-age=3600');
    header('Access-Control-Allow-Origin: *');
    header('X-Robots-Tag: noindex, follow');
    echo $content;
    exit;
}

function _proxy_fallback($wantYaml) {
    $stub = [
        'openapi' => '3.1.0',
        'info' => [
            'title' => 'MotoGo24 Public API',
            'version' => '1.0',
            'description' => 'Veřejné REST API pro programové rezervace motorek. Aktuální spec je hostován na Supabase Edge Function.',
            'contact' => ['email' => 'info@motogo24.cz', 'url' => 'https://motogo24.cz/partneri'],
            'license' => ['name' => 'Proprietary']
        ],
        'externalDocs' => [
            'description' => 'Kanonický OpenAPI spec',
            'url' => SUPABASE_URL . '/functions/v1/public-api/api/v1/openapi.json'
        ],
        'servers' => [
            ['url' => SUPABASE_URL . '/functions/v1/public-api', 'description' => 'Production']
        ]
    ];
    $content = $wantYaml ? _array_to_yaml($stub) : json_encode($stub, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    _proxy_send($content, $wantYaml ? 'application/yaml' : 'application/json');
}

// Minimální YAML serializer — handles nested arrays + scalars. Pro plný spec by
// bylo lepší použít Symfony Yaml, ale to by znamenalo composer dependency. Tohle
// stačí pro běžný OpenAPI dokument.
function _array_to_yaml($data, $indent = 0) {
    $out = '';
    $pad = str_repeat('  ', $indent);
    if (is_array($data)) {
        $isList = (array_keys($data) === range(0, count($data) - 1));
        foreach ($data as $k => $v) {
            if ($isList) {
                if (is_array($v)) {
                    $out .= $pad . "-\n" . _array_to_yaml($v, $indent + 1);
                } else {
                    $out .= $pad . '- ' . _yaml_scalar($v) . "\n";
                }
            } else {
                if (is_array($v)) {
                    $out .= $pad . $k . ":\n" . _array_to_yaml($v, $indent + 1);
                } else {
                    $out .= $pad . $k . ': ' . _yaml_scalar($v) . "\n";
                }
            }
        }
    } else {
        $out .= $pad . _yaml_scalar($data) . "\n";
    }
    return $out;
}

function _yaml_scalar($v) {
    if (is_bool($v)) return $v ? 'true' : 'false';
    if ($v === null) return 'null';
    if (is_int($v) || is_float($v)) return (string)$v;
    $s = (string)$v;
    // Quote pokud obsahuje speciální znaky
    if (preg_match('/[:#\n"\']|^[\s\-?@&*!|>]/', $s) || $s === '' || ctype_digit($s)) {
        return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $s) . '"';
    }
    return $s;
}

// 1) Try cache
if (is_file($cacheFile) && (time() - filemtime($cacheFile)) < $cacheTtl) {
    $cached = @file_get_contents($cacheFile);
    if ($cached !== false && $cached !== '') {
        _proxy_send($cached, $wantYaml ? 'application/yaml' : 'application/json');
    }
}

// 2) Fetch fresh — krátký timeout (2s), aby nezablokoval render při výpadku
$ctx = stream_context_create([
    'http' => [
        'timeout' => 2,
        'header' => "Accept: application/json\r\nUser-Agent: motogo24-openapi-proxy/1.0\r\n",
        'ignore_errors' => true,
    ],
    'ssl' => ['verify_peer' => true, 'verify_peer_name' => true],
]);
$json = @file_get_contents($src, false, $ctx);

if ($json === false || $json === '' || $json[0] !== '{') {
    // Fallback s X-Cache hintem
    header('X-Cache: MISS-FALLBACK');
    _proxy_fallback($wantYaml);
}

$decoded = json_decode($json, true);
if (!is_array($decoded)) {
    header('X-Cache: MISS-FALLBACK');
    _proxy_fallback($wantYaml);
}

$content = $wantYaml ? _array_to_yaml($decoded) : json_encode($decoded, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
@file_put_contents($cacheFile, $content);
header('X-Cache: MISS-FRESH');
_proxy_send($content, $wantYaml ? 'application/yaml' : 'application/json');
