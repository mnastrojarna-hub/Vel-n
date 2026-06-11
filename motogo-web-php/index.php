<?php
// ===== MotoGo24 Web PHP — Hlavní router + entry point =====

require_once __DIR__ . '/config.php';

// SEO bulletproof — robots.txt a sitemap.xml MUSI fungovat za vsech okolnosti.
// Nektere externi SEO checkery hlasily 'robots.txt Neexistuje' / 'Sitemap
// Neexistuje' — root cause: pokud kterakoliv linka pred routou (i18n init,
// Supabase fetch, exception handler) selze, fail vrati 500/HTML chybovou
// stranku misto plain-text/XML. Proto routujeme robots/sitemap PRED vsim
// ostatnim, bez Supabase, bez i18n, bez session.
//
// Tyto dve routy nepotrebuji nic z runtimu krome `robots.txt` souboru a
// `sitemap.php` (ktery si i18n nacte sam).
$_seoEarlyPath = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
if ($_seoEarlyPath === '/robots.txt') {
    $f = __DIR__ . '/robots.txt';
    if (is_file($f)) {
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: public, max-age=3600');
        header('X-Robots-Tag: noindex, follow');
        readfile($f);
        exit;
    }
    // Fallback: minimalni inline robots pokud soubor chybi
    header('Content-Type: text/plain; charset=utf-8');
    echo "User-agent: *\nAllow: /\nDisallow: /rezervace\nDisallow: /potvrzeni\n";
    echo "Sitemap: https://www.motogo24.cz/sitemap.xml\n";
    exit;
}

// Android App Links — Google Play ověření (Digital Asset Links).
// MUSÍ vrátit HTTP 200 + Content-Type application/json BEZ přesměrování
// (autoVerify intent-filter pro https://motogo24.cz/app v com.motogo24.app).
// Routujeme PŘED i18n/Supabase/page cache stejně jako robots.txt, aby ověření
// nemohlo spadnout na žádném runtime failu ani jazykovém redirectu.
// .htaccess navíc vyjímá /.well-known/ z kanonických 301 na www/https.
if ($_seoEarlyPath === '/.well-known/assetlinks.json') {
    header('Content-Type: application/json');
    header('Cache-Control: public, max-age=3600');
    header('Access-Control-Allow-Origin: *');
    header('X-Robots-Tag: noindex, follow');
    $f = __DIR__ . '/.well-known/assetlinks.json';
    if (is_file($f)) {
        readfile($f);
        exit;
    }
    // Inline fallback, kdyby fyzický soubor na hostingu chyběl
    echo '[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":"com.motogo24.app","sha256_cert_fingerprints":["16:89:96:54:BC:4C:02:5D:78:2C:B2:F2:5C:51:71:0F:09:51:5C:86:41:68:0E:FE:48:85:B7:26:AE:69:88:77","14:93:78:18:0A:07:61:1B:7F:A4:89:25:B3:85:50:B2:ED:49:14:C2:32:7F:59:16:5B:39:35:37:82:6B:DA:8E"]}}]';
    exit;
}

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
require_once __DIR__ . '/visitor_traffic.php';

// ---- CMS admin režim (zvýraznění editovatelných textů) ----
// Velín posílá uživatele na URL s ?cms_admin=<token>. Token se ověří proti
// app_settings.cms_admin_token; při shodě nastavíme PODEPSANOU cookie
// 'mg_cms_admin=<expiry>.<HMAC(token)>' (30 dní, HttpOnly) a redirectneme na URL
// bez parametru, ať se token neukládá v historii. Cookie ověřuje mgCmsAdminValid()
// proti tokenu — bez znalosti tokenu ji nelze zfalšovat.
// Logout: ?cms_admin_logout=1 → smaže cookie.
(function () {
    $reqUri = $_SERVER['REQUEST_URI'] ?? '/';
    $parts = parse_url($reqUri);
    $reqPath = $parts['path'] ?? '/';
    $existing = [];
    if (!empty($parts['query'])) parse_str($parts['query'], $existing);

    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');

    // Nastaví/zruší obě cookie najednou: `mg_cms_sig` (podepsaná, HttpOnly =
    // skutečná autorizace) + `mg_cms_admin` ("1", JS-čitelný kosmetický flag pro
    // overlay; bez platného sig nemá žádnou moc).
    $setAdminCookies = function ($sigValue, $exp) use ($secure) {
        if (headers_sent()) return;
        if ($sigValue === '') {
            setcookie('mg_cms_sig', '', ['expires' => time() - 3600, 'path' => '/', 'secure' => $secure, 'httponly' => true, 'samesite' => 'Lax']);
            setcookie('mg_cms_admin', '', ['expires' => time() - 3600, 'path' => '/', 'secure' => $secure, 'httponly' => false, 'samesite' => 'Lax']);
        } else {
            setcookie('mg_cms_sig', $sigValue, ['expires' => $exp, 'path' => '/', 'secure' => $secure, 'httponly' => true, 'samesite' => 'Lax']);
            setcookie('mg_cms_admin', '1', ['expires' => $exp, 'path' => '/', 'secure' => $secure, 'httponly' => false, 'samesite' => 'Lax']);
        }
    };

    if (isset($_GET['cms_admin_logout'])) {
        $setAdminCookies('', 0);
        $_COOKIE['mg_cms_sig'] = ''; $_COOKIE['mg_cms_admin'] = '';
        unset($existing['cms_admin_logout'], $existing['cms_admin'], $existing['cms_highlight']);
        $qs = !empty($existing) ? ('?' . http_build_query($existing)) : '';
        if (!headers_sent()) { header('Location: ' . $reqPath . $qs); exit; }
    }

    // Cross-domain SSO: switcher na cizí doméně přiloží ?cms_admin_sso=<cap>
    // (podepsaná capability). Cílová doména ji ověří VEŘEJNÝM klíčem lokálně a
    // nastaví si vlastní cookie — bez raw tokenu, bez edge volání.
    if (isset($_GET['cms_admin_sso']) && $_GET['cms_admin_sso'] !== '') {
        $cap = (string)$_GET['cms_admin_sso'];
        if (mgCmsVerifyCap($cap)) {
            $exp = 0; $p = explode('.', $cap); if (count($p) === 3 && ctype_digit($p[1])) $exp = (int)$p[1];
            if ($exp > time()) {
                $setAdminCookies($cap, $exp);
                $_COOKIE['mg_cms_sig'] = $cap; $_COOKIE['mg_cms_admin'] = '1';
            }
        }
        unset($existing['cms_admin_sso']);
        $qs = !empty($existing) ? ('?' . http_build_query($existing)) : '';
        if (!headers_sent()) { header('Location: ' . $reqPath . $qs); exit; }
    }

    if (isset($_GET['cms_admin']) && $_GET['cms_admin'] !== '') {
        $provided = (string)$_GET['cms_admin'];
        $sigVal = '';
        $exp = time() + 30 * 24 * 3600;

        // PRIMÁRNÍ cesta (#5 fix): vyměň raw token za podepsanou capability přes
        // edge funkci `cms-admin-auth`. PHP token sám nečte — token tak smí být
        // skrytý z anon RLS. Edge ověří token (service_role) a vrátí `cap`.
        $cap = '';
        $ch = @curl_init(SUPABASE_URL . '/functions/v1/cms-admin-auth');
        if ($ch) {
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 6,
                CURLOPT_HTTPHEADER => [
                    'Content-Type: application/json',
                    'apikey: ' . SUPABASE_ANON_KEY,
                    'Authorization: Bearer ' . SUPABASE_ANON_KEY,
                ],
                CURLOPT_POSTFIELDS => json_encode(['token' => $provided]),
            ]);
            $resp = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($resp !== false && $code === 200) {
                $j = json_decode($resp, true);
                if (is_array($j) && !empty($j['cap']) && mgCmsVerifyCap($j['cap'])) $cap = $j['cap'];
            }
        }

        if ($cap !== '') {
            $sigVal = $cap;
            $p = explode('.', $cap); if (count($p) === 3 && ctype_digit($p[1])) $exp = (int)$p[1];
        } else {
            // FALLBACK (dokud není nasazená edge funkce / secret): ověř token
            // přímo proti app_settings (anon read) a nastav legacy HMAC sig.
            $sb = new SupabaseClient();
            $expected = $sb->fetchSetting('cms_admin_token');
            if (is_string($expected) && $expected !== '' && hash_equals($expected, $provided)) {
                $sigVal = mgCmsAdminCookieValue($expected, $exp);
            }
        }

        if ($sigVal !== '') {
            $setAdminCookies($sigVal, $exp);
            $_COOKIE['mg_cms_sig'] = $sigVal; $_COOKIE['mg_cms_admin'] = '1';
        }
        // Token vždy odstraníme z URL — i při shodě i při neshodě (ať neleakuje).
        unset($existing['cms_admin']);
        $qs = !empty($existing) ? ('?' . http_build_query($existing)) : '';
        if (!headers_sent()) { header('Location: ' . $reqPath . $qs); exit; }
    }
})();

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

// ---- Lokalizované URL slugy (SEO) ----
// Cizojazyčné mutace mají vlastní slugy (/catalog, /motorradverleih, …).
// Pokud request nesedí na slug detekovaného jazyka (česká URL na .com, cizí
// URL na .cz, změna jazyka cookie), 301 na správný tvar (query se zachová —
// Stripe/resume/order_id odkazy z JS a mailů fungují dál). Běží PŘED
// logováním návštěvnosti (redirect není pageview) i před page cache.
// Viz i18n_slugs.php.
i18nSlugRedirectIfNeeded($path);

// AI traffic logging — detekuje AI crawlery (GPTBot, ClaudeBot, PerplexityBot ad.)
// a loguje request do ai_traffic_log. Fire-and-forget, nezablokuje render.
// Pro lidi je no-op (žádné DB volání).
aiTrafficMaybeLog($path, function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs');

// Visitor traffic logging — reální lidé (ne AI/boti). Insert se odkládá na
// konec requestu přes register_shutdown_function, takže nezdržuje render ani
// HIT v page cache. Cookieless, hashovaná IP (GDPR friendly).
visitorTrafficMaybeLog($path, function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs');

// Router (i page cache) níže pracuje vždy s kanonickou (českou) cestou —
// lokalizovaný request je po redirectu výše už jen 1:1 alias pro daný jazyk.
$path = i18nCanonicalPath($path);

// Sitemap.xml (dynamický)
if ($path === '/sitemap.xml') {
    require __DIR__ . '/sitemap.php';
    exit;
}

// robots.txt — fail-safe fallback (hosting normalne servis fyzicky soubor pres .htaccess,
// ale nektere SEO testery zachycuji false-positive 404, pokud server returns text/html.
// Tento route emituje text/plain s cache headers i kdyz fyzicky soubor nedostupny.)
if ($path === '/robots.txt') {
    $f = __DIR__ . '/robots.txt';
    if (is_file($f)) {
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: public, max-age=3600');
        header('X-Robots-Tag: noindex, follow');
        readfile($f);
        exit;
    }
}

// llms.txt — LLM-friendly katalog stránek (Jeremy Howard standard)
// Per-language přes ?lang= nebo cookie. Vrací text/markdown.
if ($path === '/llms.txt') {
    require __DIR__ . '/pages/llms-txt.php';
    exit;
}

// /api/master.php — JSON export CS masteru pro multilingvní překlad
// (volá edge fn translate-pages-master, autorizuje cms_admin_token).
if ($path === '/api/master.php') {
    require __DIR__ . '/pages/master-export.php';
    exit;
}

// /api/cms-cache-purge — invalidace webtexts/page cache po Velin save.
// Autorizace: X-CMS-Admin-Token header (nebo ?token=…) vs. app_settings.cms_admin_token.
if ($path === '/api/cms-cache-purge') {
    require __DIR__ . '/pages/cms-cache-purge.php';
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
        header('Access-Control-Allow-Origin: *');
        header('X-Robots-Tag: noindex, follow');
        readfile($f);
        exit;
    }
}

// .well-known/ai-plugin.json — OpenAI ChatGPT plugin manifest (legacy formát).
// Některé GPT integrace ho stále hledají vedle agent.json — duální podpora
// zvyšuje šanci, že nás AI agent najde a použije pro booking.
if ($path === '/.well-known/ai-plugin.json') {
    $f = __DIR__ . '/.well-known/ai-plugin.json';
    if (is_file($f)) {
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: public, max-age=3600');
        header('Access-Control-Allow-Origin: *');
        header('X-Robots-Tag: noindex, follow');
        readfile($f);
        exit;
    }
}

// .well-known/openapi.yaml + .well-known/openapi.json + /openapi.json + /openapi.yaml
// Proxy s 1h cache na Supabase public-api OpenAPI spec. Dává AI agentům jednu
// důvěryhodnou URL na motogo24.cz origin, fallback na stub při výpadku Supabase.
if ($path === '/.well-known/openapi.yaml' || $path === '/.well-known/openapi.json'
    || $path === '/openapi.yaml' || $path === '/openapi.json') {
    require __DIR__ . '/pages/openapi-proxy.php';
    exit;
}

// /ai.txt — alternativní konvence vedle /llms.txt (spirit2.com/ai.txt formát).
// Některé AI tooly hledají specificky tenhle soubor.
if ($path === '/ai.txt') {
    $f = __DIR__ . '/ai.txt';
    if (is_file($f)) {
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: public, max-age=3600');
        header('Access-Control-Allow-Origin: *');
        header('X-Robots-Tag: noindex, follow');
        readfile($f);
        exit;
    }
}

// /feed.xml — RSS 2.0 feed pro blog. Pomáhá Google Discover, Seznam Novinkám,
// AI agentům s aktualizovaným obsahem (články o motorkách a trasách).
if ($path === '/feed.xml' || $path === '/rss.xml') {
    require __DIR__ . '/pages/feed.php';
    exit;
}

// /opensearch.xml — OpenSearch description pro browser searchbar a Seznam Webmaster.
if ($path === '/opensearch.xml') {
    require __DIR__ . '/pages/opensearch-xml.php';
    exit;
}

// /manifest.webmanifest — PWA manifest (offline UX, "Přidat na plochu").
if ($path === '/manifest.webmanifest') {
    $f = __DIR__ . '/manifest.webmanifest';
    if (is_file($f)) {
        header('Content-Type: application/manifest+json; charset=utf-8');
        header('Cache-Control: public, max-age=86400');
        header('Access-Control-Allow-Origin: *');
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

// SEO/Perf: full-page HTML output cache pro anonymni GET requesty.
// Resi Seobility 'Stredni doba odezvy' (65 stranek 0.5-1s) — Supabase fetche
// + i18n + rendering trvaji 500-700 ms, ale vystup je deterministicky pro
// (host, path, lang, currency, tag). Pri cache HIT vraci HTML behem ~5 ms.
// TTL 10 min, automaticky se obchazi pro admin/login a citlive cesty.
require_once __DIR__ . '/page_cache.php';
pageCacheMaybeServe($path);

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

    case $path === '/katalog/sportovni':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/naked':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/supermoto':
        require __DIR__ . '/pages/katalog.php';
        break;

    case $path === '/katalog/chopper':
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

    // Jak si půjčit — rozcestníková stránka /jak-pujcit byla odstraněna
    // (obsahově duplicitní s podstránkami). Přesměrováváme 301 na /jak-pujcit/postup,
    // aby ~550 backlinků (Google + externí) neztratilo SEO juice. V menu zůstává
    // rodičovský label jako neklickatelný rozcestník (no_link), který rozbalí
    // podmenu — viz layout.php::getMenuItems().
    case $path === '/jak-pujcit':
        // Cíl redirectu lokalizujeme — jinak by na cizí doméně vznikl
        // řetěz 301 (/how-to-rent → /jak-pujcit/postup → /how-to-rent/process).
        header('Location: ' . BASE_URL . i18nLocalizePath('/jak-pujcit/postup'), true, 301);
        exit;

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

    // E-shop košík (klient-side render z localStorage)
    case $path === '/kosik' || $path === '/cart':
        require __DIR__ . '/pages/cart.php';
        break;

    // E-shop pokladna
    case $path === '/objednavka' || $path === '/objednavka/':
        require __DIR__ . '/pages/checkout.php';
        break;

    // E-shop potvrzení objednávky
    case $path === '/objednavka/dokoncit' || $path === '/objednavka/dokonceno':
        require __DIR__ . '/pages/order-confirm.php';
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

    // Smazání účtu a dat — veřejná stránka pro Google Play Data safety
    // (URL ke smazání účtu). Statická, bez závislosti na DB/CMS.
    case $path === '/smazani-uctu':
        require __DIR__ . '/pages/smazani-uctu.php';
        break;

    // CMS stránky (legacy fallback — nově preferujeme /dokumenty/<slug>, který
    // čte rovnou z `document_templates` ve Velíně). Krátké aliasy /gdpr, /smlouva,
    // /obchodni-podminky řeší .htaccess přímým 301 redirectem na /dokumenty/<slug>
    // — žádný PHP hop, žádný redirect-chain. Tady už nic není potřeba.

    // Veřejné dokumenty z Velínu (document_templates) — VOP, smlouva, GDPR,
    // protokoly. `/dokumenty/<slug>` zobrazí obsah, `?format=pdf` vrátí print
    // verzi (Ctrl+P → Save as PDF). Stará /cms/<slug> URL z dokumenty-content
    // je teď přesměrována sem.
    case preg_match('#^/dokumenty/([a-z0-9\-]+)$#', $path, $matches) === 1:
        $_GET['doc_slug'] = $matches[1];
        require __DIR__ . '/pages/dokumenty-detail.php';
        break;
    case preg_match('#^/cms/([a-z0-9\-]+)$#', $path, $matches) === 1:
        header('Location: ' . BASE_URL . '/dokumenty/' . $matches[1], true, 301);
        exit;

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

    // Úprava rezervace (login + prodloužit / zkrátit / storno)
    case $path === '/upravit-rezervaci':
        require __DIR__ . '/pages/upravit-rezervaci.php';
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
