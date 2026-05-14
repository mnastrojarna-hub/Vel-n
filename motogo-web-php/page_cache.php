<?php
// ===== MotoGo24 — Full-page HTML output cache =====
// SEO: Seobility hlasilo 65 stranek s 'Stredni doba odezvy' (0.5-1s). Pricina:
// kazdy GET request volal Supabase fetchSetting/fetchWebTexts/fetchMotos
// (i kdyz s file-cache 30 min), nasledne renderoval cely HTML s i18n,
// strukturovanymi daty, atd. — celkem 500-700 ms. Pro crawler/anonymni
// uzivatele toho neni potreba: vystup je deterministicky pro
// (host, path, lang, currency, tag) trojici.
//
// Tento modul nad temito klici zalohuje cely vyrendrovany HTML output do
// /tmp/motogo_pagecache/<key>.html (TTL 10 min). Cache HIT vraci HTML behem
// ~5-10 ms (jen readfile). Cache MISS bezi normalni rendering a vystup ulozi.
//
// Bezpecnostni omezeni — cache SE NEPOUZIVA pokud:
//   - request neni GET
//   - admin cookie mg_cms_admin (CMS editor vidi vlastni zmeny okamzite)
//   - prihlaseny uzivatel (mg_user / mg_auth / supabase session cookie)
//   - cesta zacina na /rezervace, /potvrzeni, /kosik, /checkout,
//     /upravit-rezervaci, /cms, /api, /order-confirm
//   - HTTP status code != 200 (cachujeme jen uspesne responsy)
//   - kratky output (sanity check < 200 znaku)
//
// Volat pred main route switch v index.php. setcookie() z i18nDetectLanguage
// se aplikuje pred cache-hit serve, takze Set-Cookie hlavicka sedi.

const PAGE_CACHE_TTL = 600; // 10 min

function _pageCacheDir() {
    $candidates = [__DIR__ . '/.cache/pages', sys_get_temp_dir() . '/motogo_pagecache'];
    foreach ($candidates as $dir) {
        if (is_dir($dir) && is_writable($dir)) return $dir;
        if (!is_dir($dir) && @mkdir($dir, 0755, true) && is_writable($dir)) return $dir;
    }
    return null;
}

function _pageCacheEnabled() {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') return false;
    if (!empty($_COOKIE['mg_cms_admin'])) return false;
    if (!empty($_COOKIE['mg_user'])) return false;
    if (!empty($_COOKIE['mg_auth'])) return false;
    // Supabase auth cookies (sb-* set client-side po prihlaseni)
    foreach ($_COOKIE as $name => $_) {
        if (strpos($name, 'sb-') === 0) return false;
    }
    return true;
}

function _pageCacheSkipPath($path) {
    $skipPrefixes = [
        '/rezervace', '/potvrzeni', '/kosik', '/checkout', '/upravit-rezervaci',
        '/cms', '/api/', '/order-confirm', '/.well-known/',
    ];
    foreach ($skipPrefixes as $p) {
        if ($path === $p || strpos($path, $p) === 0) return true;
    }
    return false;
}

function _pageCacheKey($path) {
    $host = strtolower($_SERVER['HTTP_HOST'] ?? '');
    parse_str($_SERVER['QUERY_STRING'] ?? '', $q);
    // Efektivni lang/currency: query > cookie > prazdne (= domain default)
    $lang = strtolower((string)($q['lang'] ?? ($_COOKIE['mg_web_lang'] ?? '')));
    $currency = strtoupper((string)($q['currency'] ?? ($_COOKIE['mg_web_currency'] ?? '')));
    $tag = (string)($q['tag'] ?? '');
    return md5($host . '|' . $path . '|' . $lang . '|' . $currency . '|' . $tag);
}

/**
 * Pokus o cache HIT. Pokud cache existuje a je fresh, posle ji a exit().
 * Jinak nastartuje output buffer a registruje shutdown hook pro ulozeni.
 */
function pageCacheMaybeServe($path) {
    if (!_pageCacheEnabled()) return;
    if (_pageCacheSkipPath($path)) return;

    $dir = _pageCacheDir();
    if (!$dir) return;

    $key = _pageCacheKey($path);
    $file = $dir . '/' . $key . '.html';

    // HIT?
    if (is_file($file) && filemtime($file) > time() - PAGE_CACHE_TTL) {
        // Set-Cookie z i18nDetectLanguage uz je v header queue, jen prida nase
        // Content-Type + cache marker.
        if (!headers_sent()) {
            header('Content-Type: text/html; charset=utf-8');
            header('X-Page-Cache: HIT');
            header('Cache-Control: public, max-age=' . PAGE_CACHE_TTL . ', stale-while-revalidate=60');
            header('Vary: Accept-Language, Cookie');
        }
        readfile($file);
        exit;
    }

    // MISS — start output buffer + register shutdown hook pro save.
    if (!headers_sent()) {
        header('X-Page-Cache: MISS');
    }
    ob_start();
    register_shutdown_function(function () use ($file) {
        $status = http_response_code();
        if ($status !== 200 && $status !== false) return; // necachuj chyby
        $out = ob_get_contents();
        if (!is_string($out) || strlen($out) < 200) return;
        // Sanity: musi vypadat jako HTML
        if (stripos($out, '</body>') === false) return;
        // Necachuj pokud bezi admin/login flow (cookies mohly byt nastaveny
        // pozdeji v requestu — re-check po renderingu)
        if (!_pageCacheEnabled()) return;
        @file_put_contents($file, $out, LOCK_EX);
        // Output flush probehne automaticky po shutdown.
    });
}
