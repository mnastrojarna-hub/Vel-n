<?php
// ===== MotoGo24 — Visitor Traffic (reální lidé) =====
// Loguje reálné lidské zobrazení stránky do `visitor_log` (přes Supabase REST
// anon — RLS politika INSERT WITH CHECK (true) insert dovolí). Doplněk k
// ai_traffic.php, který sleduje AI crawlery / boty zvlášť.
//
// GDPR: bez cookies, IP se hashuje (sha256 + salt), `visitor_hash` rotuje
// denně (salt = datum) → unikátní návštěvník jen v rámci dne, žádné
// cross-day/cross-site sledování. Model á la Plausible/Fathom.
//
// Výkon: insert se odkládá přes register_shutdown_function (+ volitelný
// fastcgi_finish_request), takže NIKDY nezdržuje render — ani při HIT v
// page cache (která dělá `exit`, shutdown funkce se přesto spustí).

require_once __DIR__ . '/config.php';

/**
 * Broad bot filter pro NE-AI boty (Googlebot, Bingbot, monitoring, scrapery…).
 * AI boti se řeší v ai_traffic.php a do human logu se nepočítají.
 * Vrací true = bot (nelogovat jako člověka).
 */
function visitorIsBot($ua) {
    if (!is_string($ua) || $ua === '') return true; // prázdné UA = skoro vždy bot/skript
    return (bool) preg_match(
        '/bot|crawl|spider|slurp|bingpreview|facebookexternalhit|embedly|quora|pinterest|vkshare|w3c_validator|'
        . 'baiduspider|yandex|sogou|exabot|ia_archiver|semrush|ahrefs|mj12|dotbot|petalbot|screaming|'
        . 'headless|phantomjs|python-requests|python-urllib|curl\/|wget|go-http|node-fetch|axios|java\/|'
        . 'okhttp|libwww|lighthouse|gtmetrix|pingdom|uptimerobot|statuscake|monitor|preview|fetch|scan/i',
        $ua
    );
}

/**
 * POZITIVNÍ allowlist reálných prohlížečů — klíč pro „100% reální lidé".
 * Denylist (`visitorIsBot`) vždy mine nové/neznámé scrapery, které se
 * netváří jako bot. Proto logujeme JEN UA, který vypadá jako skutečný
 * prohlížeč: musí obsahovat `Mozilla/` (společné všem moderním browserům
 * i in-app webview FB/IG) A ZÁROVEŇ token některého reálného renderovacího
 * jádra/prohlížeče. Holé knihovní/skriptové UA (i ty s vlastním názvem)
 * tím vypadnou, takže do konverze jdou výhradně lidé.
 * Vrací true = vypadá jako reálný lidský prohlížeč.
 */
function visitorIsHumanBrowser($ua) {
    if (!is_string($ua) || stripos($ua, 'Mozilla/') === false) return false;
    return (bool) preg_match(
        '/(Chrome|CriOS|Chromium|Firefox|FxiOS|Safari|Edg|EdgA|EdgiOS|OPR|Opera|OPiOS|'
        . 'SamsungBrowser|YaBrowser|Vivaldi|Brave|DuckDuckGo|UCBrowser|MiuiBrowser|'
        . 'HuaweiBrowser|SeaMonkey|Maxthon|Trident|MSIE|'
        // In-app prohlížeče reálných lidí (FB/IG/Google app/WeChat/Snapchat) —
        // jejich UA často nemá Chrome/Safari token, ale jsou to skuteční návštěvníci.
        . 'Instagram|FBAN|FBAV|FB_IAB|FBIOS|FB4A|MicroMessenger|GSA|Snapchat)/',
        $ua
    );
}

/** Hrubá detekce zařízení z User-Agent. */
function visitorDevice($ua) {
    if (preg_match('/iPad|Tablet|PlayBook|Silk|Kindle/i', $ua)) return 'tablet';
    if (preg_match('/Mobi|iPhone|iPod|Android.*Mobile|Windows Phone|BlackBerry|Opera Mini/i', $ua)) return 'mobile';
    return 'desktop';
}

/**
 * Whitelist hostů, které vůbec logujeme. Bez www. (to se ořezává předem).
 * Pouští jen reálné domény motogo24.* (+ volitelný mobilní prefix `m.`).
 * Vše ostatní = scanner smetí (UUID/slovníkové subdomény typu
 * `<uuid>.motogo24.es`, `webmail.`, `se.`, …) nebo poškozené Host hlavičky
 * (`httpswww.motogo24.com`) → nelogovat, ať nezaneřáďují filtr domén ve Velíně.
 * Vrací true = známý host (logovat).
 */
function visitorHostAllowed($host) {
    return is_string($host) && $host !== ''
        && (bool) preg_match('/^(m\.)?motogo24\.(cz|com|nl|fr|at|pl|es)$/', $host);
}

/**
 * Z referreru vyrobí [domena, typ]. Typ: direct/internal/search/social/referral.
 */
function visitorReferrerInfo($ref, $selfHost) {
    if (!is_string($ref) || $ref === '') return ['', 'direct'];
    $host = parse_url($ref, PHP_URL_HOST);
    if (!$host) return ['', 'direct'];
    $host = strtolower(preg_replace('/^www\./', '', $host));

    if (strpos($host, 'motogo24') !== false || $host === $selfHost) return [$host, 'internal'];

    $search = ['google.', 'bing.', 'seznam.', 'duckduckgo.', 'yahoo.', 'ecosia.', 'yandex.', 'baidu.', 'centrum.cz', 'ask.com', 'startpage', 'qwant', 'brave'];
    foreach ($search as $s) if (strpos($host, $s) !== false) return [$host, 'search'];

    $social = ['facebook.', 'fb.com', 'l.facebook', 'instagram.', 't.co', 'twitter.', 'x.com', 'linkedin.', 'lnkd.in', 'youtube.', 'youtu.be', 'tiktok.', 'pinterest.', 'reddit.', 'snapchat.', 'telegram', 't.me', 'messenger.', 'whatsapp'];
    foreach ($social as $s) if (strpos($host, $s) !== false) return [$host, 'social'];

    return [$host, 'referral'];
}

/**
 * One-shot helper: rozhodne, jestli jde o reálného člověka, a pokud ano,
 * odloží insert na konec requestu. Volá se z index.php hned vedle
 * aiTrafficMaybeLog().
 */
function visitorTrafficMaybeLog($path, $lang) {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    if ($method !== 'GET') return; // logujeme jen page views, ne POST/API

    $ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
    // AI boti se logují v ai_traffic.php — sem nepatří
    if (function_exists('aiTrafficDetect') && aiTrafficDetect($ua)) return;
    if (visitorIsBot($ua)) return;
    // Pozitivní allowlist — logujeme jen UA reálného prohlížeče (100% lidé).
    if (!visitorIsHumanBrowser($ua)) return;

    // Jen známé domény motogo24.* — neznámý Host = scanner subdomén / překlep,
    // nelogovat (UA-filtr výše scannery s normálním browser UA nezachytí).
    $hostHdr = strtolower(preg_replace('/^www\./', '', $_SERVER['HTTP_HOST'] ?? ''));
    if (!visitorHostAllowed($hostHdr)) return;

    // Přeskoč assety a systémové cesty (favicon, sitemap, well-known, api, beacon…)
    if ($path === '' || $path === false) $path = '/';
    if (preg_match('#\.(css|js|mjs|map|png|jpe?g|gif|svg|webp|avif|ico|woff2?|ttf|eot|xml|txt|json|pdf|mp4|webm|mp3|webmanifest)$#i', $path)) return;
    if (preg_match('#^/(api|\.well-known|favicon|opensearch|manifest)#i', $path)) return;

    register_shutdown_function(function () use ($path, $lang, $ua) {
        if (function_exists('fastcgi_finish_request')) @fastcgi_finish_request();
        visitorTrafficSend($path, $lang, $ua);
    });
}

/** Vlastní fire-and-forget insert do visitor_log. */
function visitorTrafficSend($path, $lang, $ua) {
    if (!function_exists('curl_init')) return;

    $salt = '|motogo24';
    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
    if (strpos($ip, ',') !== false) $ip = trim(explode(',', $ip)[0]);
    $ipHash = $ip !== '' ? hash('sha256', $ip . $salt) : null;
    // Denně rotující hash → unikátní návštěvník v rámci dne (cookieless).
    $visitorHash = $ip !== '' ? hash('sha256', $ip . '|' . $ua . '|' . gmdate('Y-m-d') . $salt) : null;

    $selfHost = strtolower(preg_replace('/^www\./', '', $_SERVER['HTTP_HOST'] ?? ''));
    [$refDomain, $refType] = visitorReferrerInfo($_SERVER['HTTP_REFERER'] ?? '', $selfHost);

    $q = [];
    parse_str((string) parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_QUERY), $q);
    $utm = function ($k) use ($q) { return isset($q[$k]) && is_string($q[$k]) ? substr($q[$k], 0, 120) : null; };

    $country = $_SERVER['HTTP_CF_IPCOUNTRY'] ?? null; // Cloudflare 2-písmenný kód, pokud je za CF
    if ($country === 'XX' || $country === 'T1') $country = null;

    $payload = [
        'host'            => $selfHost ?: null,
        'path'            => substr($path, 0, 300),
        'referrer'        => ($r = substr($_SERVER['HTTP_REFERER'] ?? '', 0, 500)) !== '' ? $r : null,
        'referrer_domain' => $refDomain ?: null,
        'referrer_type'   => $refType,
        'lang'            => $lang,
        'device'          => visitorDevice($ua),
        'country'         => $country,
        'ip_hash'         => $ipHash,
        'visitor_hash'    => $visitorHash,
        'user_agent'      => substr($ua, 0, 500),
        'utm_source'      => $utm('utm_source'),
        'utm_medium'      => $utm('utm_medium'),
        'utm_campaign'    => $utm('utm_campaign'),
    ];

    $url = SUPABASE_URL . '/rest/v1/visitor_log';
    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => [
            'apikey: ' . SUPABASE_ANON_KEY,
            'Authorization: Bearer ' . SUPABASE_ANON_KEY,
            'Content-Type: application/json',
            'Prefer: return=minimal',
        ],
        CURLOPT_TIMEOUT => 3,
        CURLOPT_CONNECTTIMEOUT => 2,
    ]);
    @curl_exec($ch);
    @curl_close($ch);
}
