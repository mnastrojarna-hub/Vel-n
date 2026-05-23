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
    // BUGFIX 2026-05-18: Předchozí implementace zahrnovala jen `lang`,`currency`,`tag`
    // do cache key. Filter stránky jako `/katalog?ridicak=B&razeni=cena_asc` měly
    // STEJNÝ klíč jako `/katalog` (bez filtrů) → kdo přišel první, jeho výsledek
    // se zacachoval a všichni další viděli stejný HTML. Filtr "nefungoval", protože
    // URL params se sice měnily, ale page_cache servila stále stejný HTML.
    //
    // FIX: kompletní query string (řazený abecedně pro deterministický klíč napříč
    // pořadím params, tj. `?a=1&b=2` má stejný klíč jako `?b=2&a=1`). Identifikuje
    // unikátní kombinace všech filtrů, řazení i pagingu.
    // BUGFIX 2026-05-23: Jazyk a měna chodí i z COOKIE (mg_web_lang / mg_currency)
    // nebo doménového defaultu — ne nutně z query stringu. Předchozí klíč
    // (host|path|qstr) je proto NEzohledňoval: kdo na motogo24.com (kam míří i .es
    // přes ?lang=es redirect) vyrenderoval /katalog-detail jako první, jeho jazyk
    // se zacachoval a ostatní dostali cizí jazyk (např. španěl viděl české názvy
    // dnů v kalendáři, který se renderuje serverově). Lang/currency proto z query
    // odebereme (ať se ?lang=es a cookie nerozcházejí do dvou klíčů) a přidáme
    // skutečně detekovanou hodnotu jako samostatnou složku klíče.
    unset($q['lang'], $q['currency']);
    if (!empty($q)) {
        ksort($q);
        $qstr = http_build_query($q);
    } else {
        $qstr = '';
    }
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $cur  = function_exists('currencyDetect') ? currencyDetect() : '';
    return md5($host . '|' . $path . '|' . $qstr . '|' . $lang . '|' . $cur);
}

/**
 * Pokus o cache HIT. Pokud cache existuje a je fresh, posle ji a exit().
 * Jinak nastartuje output buffer a registruje shutdown hook pro ulozeni.
 */
function pageCacheMaybeServe($path) {
    if (_pageCacheSkipPath($path)) return;

    $dir = _pageCacheDir();
    if (!$dir) return;

    // Admin režim: aktivně mazat stale cache soubory pro tuto cestu napříč
    // všemi jazyk/měna kombinacemi, aby anonymní uživatel po admin návštěvě
    // (s ?cms_admin=<token>) hned viděl nově uložené CMS změny. Bez tohoto
    // byla cache TTL až 10 min — admin uloží ve Velíně, navštíví web s tokenem
    // (cache bypass), ale anonymní uživatel pořád dostane starou kopii.
    if (!empty($_COOKIE['mg_cms_admin'])) {
        // Smaž všechny page-cache soubory pro `host|path|*` (různé lang/currency).
        // Klíč je md5(host|path|lang|currency|tag) — nemůžeme přesně cílit,
        // ale můžeme smazat všechny soubory novější než 1 hodina (limit cache TTL).
        $host = strtolower($_SERVER['HTTP_HOST'] ?? '');
        $prefix = md5($host . '|' . $path . '|'); // hex prefix, ale md5 je distinct...
        // md5 není prefix-friendly, takže mažeme heuristicky — všechny soubory.
        // Bezpečné protože TTL stejně mažeme staré, a vzniknou znova při příští
        // anonymní návštěvě. Limit: smaže max 200 souborů per request (perf).
        $count = 0;
        foreach (glob($dir . '/*.html') as $f) {
            if ($count++ > 200) break;
            @unlink($f);
        }
        return; // Admin nikdy nečte/nepíše cache
    }

    if (!_pageCacheEnabled()) return;

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
