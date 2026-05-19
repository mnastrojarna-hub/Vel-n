<?php
// ===== MotoGo24 Web PHP — Cache purge endpoint =====
// Volá Velin po `Uložit` v Texty webu, aby anonymní uživatel viděl změny
// okamžitě (bez čekání na 30-min TTL webtexts cache nebo 10-min page_cache).
// Autorizace: hash_equals s `cms_admin_token` z `app_settings`.

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, X-CMS-Admin-Token');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$token = $_SERVER['HTTP_X_CMS_ADMIN_TOKEN'] ?? ($_GET['token'] ?? '');
if (!is_string($token) || $token === '') {
    http_response_code(401);
    echo 'no token';
    exit;
}

$sb = new SupabaseClient();
$expected = $sb->fetchSetting('cms_admin_token');
if (!is_string($expected) || $expected === '' || !hash_equals($expected, $token)) {
    http_response_code(403);
    echo 'invalid token';
    exit;
}

$purged = 0;
$cacheDirs = [
    __DIR__ . '/../.cache',
    sys_get_temp_dir() . '/motogo_cache',
];
foreach ($cacheDirs as $dir) {
    if (!is_dir($dir)) continue;
    foreach (glob($dir . '/*.json') as $f) {
        if (@unlink($f)) $purged++;
    }
}

$pageCacheDirs = [
    __DIR__ . '/../.cache/pages',
    sys_get_temp_dir() . '/motogo_pagecache',
];
foreach ($pageCacheDirs as $dir) {
    if (!is_dir($dir)) continue;
    foreach (glob($dir . '/*.html') as $f) {
        if (@unlink($f)) $purged++;
    }
}

echo 'ok purged=' . $purged;
