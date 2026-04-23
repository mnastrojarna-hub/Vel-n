<?php
// ===== MotoGo24 Web PHP — Hlavní router + entry point =====

require_once __DIR__ . '/config.php';

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
        echo '<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Chyba serveru – MotoGo24</title><meta name="robots" content="noindex"></head><body style="font-family:sans-serif;max-width:640px;margin:3rem auto;padding:1rem;text-align:center;">'
            . '<h1>Dočasná chyba serveru</h1>'
            . '<p>Omlouváme se, na stránce došlo k technické chybě. Zkuste to prosím za chvíli znovu.</p>'
            . '<p><a href="/">Zpět na úvod</a> · <a href="tel:+420774256271">+420 774 256 271</a></p>'
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

// Sitemap.xml (dynamický)
if ($path === '/sitemap.xml') {
    require __DIR__ . '/sitemap.php';
    exit;
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
        require __DIR__ . '/pages/jak-pujcit-vyzvednuti.php';
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
