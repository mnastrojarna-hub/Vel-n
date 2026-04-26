<?php
// ===== MotoGo24 Web PHP — Hlavní router + entry point =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
// Detekuj jazyk co nejdřív (kvůli set-cookie hlavičce při ?lang=xx)
i18nDetectLanguage();

// ---- Production-safe error handling ----
// V MOTOGO_DEBUG režimu chyby propadnou do browseru (pro ladění nasazení).
// Jinak: chyby se logují server-side, browser dostane přátelský HTML výstup.
if (defined('MOTOGO_DEBUG') && MOTOGO_DEBUG) {
    @ini_set('display_errors', '1');
    @ini_set('display_startup_errors', '1');
    error_reporting(E_ALL);
} else {
    @ini_set('display_errors', '0');
    @ini_set('log_errors', '1');
    error_reporting(E_ALL);

    set_exception_handler(function ($e) {
        @error_log('[MotoGo24] Uncaught: ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
        if (!headers_sent()) {
            http_response_code(500);
            header('Content-Type: text/html; charset=utf-8');
        }
        $lang = function_exists('i18nHtmlLang') ? i18nHtmlLang() : 'cs-CZ';
        $title = function_exists('te') ? te('err500.title') : 'Chyba serveru – MotoGo24';
        $heading = function_exists('te') ? te('err500.heading') : 'Dočasná chyba serveru';
        $msg = function_exists('te') ? te('err500.message') : 'Omlouváme se, na stránce došlo k technické chybě. Zkuste to prosím za chvíli znovu.';
        $back = function_exists('te') ? te('common.backHome') : 'Zpět na úvod';
        echo '<!DOCTYPE html><html lang="' . htmlspecialchars($lang) . '"><head><meta charset="utf-8"><title>' . $title . '</title><meta name="robots" content="noindex"></head><body style="font-family:sans-serif;max-width:640px;margin:3rem auto;padding:1rem;text-align:center;">'
            . '<h1>' . $heading . '</h1>'
            . '<p>' . $msg . '</p>'
            . '<p><a href="/">' . $back . '</a> · <a href="tel:+420774256271">+420 774 256 271</a></p>'
            . '</body></html>';
    });

    set_error_handler(function ($severity, $message, $file, $line) {
        // Non-fatal chyby (warning/notice/deprecated) jen logujeme, nešlapem na ně
        if (!(error_reporting() & $severity)) return false;
        if (in_array($severity, [E_NOTICE, E_DEPRECATED, E_USER_DEPRECATED, E_WARNING, E_USER_WARNING, E_USER_NOTICE, E_STRICT], true)) {
            @error_log("[MotoGo24] {$message} @ {$file}:{$line}");
            return true;
        }
        return false;
    });
}

require_once __DIR__ . '/supabase.php';
require_once __DIR__ . '/components.php';
require_once __DIR__ . '/layout.php';
require_once __DIR__ . '/ai_traffic.php';

// Získání cesty z REQUEST_URI (bez query stringu)
$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
$path = parse_url($requestUri, PHP_URL_PATH);

// Odstraň BASE_URL prefix z cesty
if (BASE_URL !== '' && strpos($path, BASE_URL) === 0) {
    $path = substr($path, strlen(BASE_URL));
}
if ($path === '' || $path === false) $path = '/';

// Odstraň trailing slash (kromě /)
if ($path !== '/' && substr($path, -1) === '/') {
    $path = rtrim($path, '/');
}

// AI traffic logging — detekuje AI crawlery (GPTBot, ClaudeBot, PerplexityBot ad.)
// a loguje request do ai_traffic_log. Fire-and-forget, nezablokuje render.
// Pro lidi je no-op (žádné DB volání).
aiTrafficMaybeLog($path, function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs');

// Sitemap.xml (dynamický)
if ($path === '/sitemap.xml') {
    require __DIR__ . '/sitemap.php';
    exit;
}

// llms.txt — LLM-friendly katalog stránek (Jeremy Howard standard)
// Per-language přes ?lang= nebo cookie. Vrací text/markdown.
if ($path === '/llms.txt') {
    require __DIR__ . '/pages/llms-txt.php';
    exit;
}

// llms-full.txt — sloučený plný obsah pro LLM (statické stránky + DB).
// AI agent dostane kompletní kontext webu v jednom requestu (~80 kB markdown).
if ($path === '/llms-full.txt') {
    require __DIR__ . '/pages/llms-full-txt.php';
    exit;
}

// .well-known/agent.json — manifest pro AI agenty (capabilities, endpoints).
// Statický soubor; pokud existuje fyzicky, server ho doručí přes .htaccess.
// Tento fallback je pro hosting, kde .well-known/ není přímo dostupné.
if ($path === '/.well-known/agent.json') {
    $f = __DIR__ . '/.well-known/agent.json';
    if (is_file($f)) {
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: public, max-age=3600');
        readfile($f);
        exit;
    }
}

// .well-known/security.txt — RFC 9116 (statický soubor v .well-known/)
// .htaccess nepřesměrovává requesty na existující soubory, takže pokud je soubor
// k dispozici, server ho doručí přímo. Tento fallback řeší případ, kdy
// .well-known/ na hostingu není přístupné — vrátíme obsah ze stejného repozitáře.
if ($path === '/.well-known/security.txt' || $path === '/security.txt') {
    $f = __DIR__ . '/.well-known/security.txt';
    if (is_file($f)) {
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: public, max-age=86400');
        readfile($f);
        exit;
    }
}

// Favicon.ico — servírujeme SVG favicon jako fallback.
// (.htaccess rewrite pošle tenhle request sem, pokud fyzický soubor chybí.)
if ($path === '/favicon.ico') {
    $svg = __DIR__ . '/favicon.svg';
    if (is_file($svg)) {
        header('Content-Type: image/svg+xml');
        header('Cache-Control: public, max-age=86400');
        readfile($svg);
        exit;
    }
    http_response_code(204);
    exit;
}

// Routování
switch (true) {
    // Domovská stránka
    case $path === '/' || $path === '':
        require __DIR__ . '/pages/home.php';
        break;

    // Katalog
    case $path === '/katalog':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/cestovni':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/naked':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/supermoto':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/detske':
        require __DIR__ . '/pages/katalog.php';
        break;

    case preg_match('#^/katalog/([a-f0-9\-]+)$#', $path, $matches) === 1:
        $_GET['id'] = $matches[1];
        require __DIR__ . '/pages/katalog-detail.php';
        break;

    // Půjčovna
    case $path === '/pujcovna-motorek':
        require __DIR__ . '/pages/pujcovna.php';
        break;

    // Jak si půjčit
    case $path === '/jak-pujcit':
        require __DIR__ . '/pages/jak-pujcit.php';
        break;

    case $path === '/jak-pujcit/postup':
        require __DIR__ . '/pages/jak-pujcit-postup.php';
        break;

    case $path === '/jak-pujcit/pristaveni':
        require __DIR__ . '/pages/jak-pujcit-pristaveni.php';
        break;

    case $path === '/jak-pujcit/vyzvednuti':
    case $path === '/jak-pujcit/prevzeti':
        require __DIR__ . '/pages/jak-pujcit-vyzvednuti.php';
        break;

    case $path === '/jak-pujcit/vraceni-pujcovna':
        require __DIR__ . '/pages/jak-pujcit-vraceni-pujcovna.php';
        break;

    case $path === '/jak-pujcit/vraceni-jinde':
        require __DIR__ . '/pages/jak-pujcit-vraceni-jinde.php';
        break;

    case $path === '/jak-pujcit/co-v-cene':
        require __DIR__ . '/pages/jak-pujcit-cena.php';
        break;

    case $path === '/jak-pujcit/dokumenty':
        require __DIR__ . '/pages/jak-pujcit-dokumenty.php';
        break;

    case $path === '/jak-pujcit/faq':
        require __DIR__ . '/pages/faq.php';
        break;

    // Poukazy
    case $path === '/poukazy':
        require __DIR__ . '/pages/poukazy.php';
        break;

    case $path === '/koupit-darkovy-poukaz':
        require __DIR__ . '/pages/poukazy-objednat.php';
        break;

    // E-shop (produkty z Velínu, texty lokalizované přes helper localized())
    case $path === '/eshop' || $path === '/e-shop':
        require __DIR__ . '/pages/shop.php';
        break;

    case preg_match('#^/eshop/([a-f0-9\-]+)$#', $path, $matches) === 1:
        $_GET['id'] = $matches[1];
        require __DIR__ . '/pages/shop-detail.php';
        break;

    // Blog
    case $path === '/blog':
        require __DIR__ . '/pages/blog.php';
        break;

    case preg_match('#^/blog/([a-z0-9\-]+)$#', $path, $matches) === 1:
        $_GET['slug'] = $matches[1];
        require __DIR__ . '/pages/blog-detail.php';
        break;

    // Kontakt
    case $path === '/kontakt':
        require __DIR__ . '/pages/kontakt.php';
        break;

    // CMS stránky
    case $path === '/obchodni-podminky':
        $_GET['cms_slug'] = 'obchodni-podminky';
        $_GET['cms_title'] = 'Obchodní podmínky';
        require __DIR__ . '/pages/cms.php';
        break;

    case $path === '/gdpr':
        $_GET['cms_slug'] = 'gdpr';
        $_GET['cms_title'] = 'Zásady ochrany osobních údajů';
        require __DIR__ . '/pages/cms.php';
        break;

    case $path === '/smlouva':
        $_GET['cms_slug'] = 'smlouva-o-pronajmu';
        $_GET['cms_title'] = 'Smlouva o pronájmu';
        require __DIR__ . '/pages/cms.php';
        break;

    // Mapa stránek
    case $path === '/mapa-stranek':
        require __DIR__ . '/pages/sitemap-page.php';
        break;

    // Developer / partner stránka — REST API, MCP, llms.txt
    case $path === '/partneri' || $path === '/api':
        require __DIR__ . '/pages/partneri.php';
        break;

    // Rezervace
    case $path === '/rezervace':
        require __DIR__ . '/pages/rezervace.php';
        break;

    // Potvrzení
    case $path === '/potvrzeni':
        require __DIR__ . '/pages/potvrzeni.php';
        break;

    // 404
    default:
        http_response_code(404);
        require __DIR__ . '/pages/404.php';
        break;
}
