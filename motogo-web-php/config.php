<?php
// ===== MotoGo24 Web PHP — Konfigurace =====

// DEBUG mode — pokud je true, PHP chyby se zobrazují v browseru.
// Pro production nech false.  Pro ladění nasazení dočasně přepni na true.
if (!defined('MOTOGO_DEBUG')) {
    define('MOTOGO_DEBUG', false);
}

// Supabase
define('SUPABASE_URL', 'https://vnwnqteskbykeucanlhk.supabase.co');
define('SUPABASE_ANON_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0OTEzNjMsImV4cCI6MjA4ODA2NzM2M30.AiHfmfEQK9KD9TvxX5XLWVGaOhEV7kiMwwMwMWp0Ruo');

// Base URL (bez trailing slash)
define('BASE_URL', '');

// Kontaktní údaje
define('PHONE', '+420 774 256 271');
define('PHONE_LINK', 'tel:+420774256271');
define('EMAIL_USER', 'info');
define('EMAIL_DOMAIN', 'motogo24.cz');
define('EMAIL_FULL', EMAIL_USER . '@' . EMAIL_DOMAIN);
define('ADDRESS', 'Mezná 9, 393 01 Pelhřimov');

// Sociální sítě
define('FB_URL', 'https://www.facebook.com/profile.php?id=61581614672839');
define('IG_URL', 'https://www.instagram.com/moto.go24/');

// Mobilní aplikace (uzavřené testování Google Play — opt-in odkaz pro testery)
define('PLAY_STORE_URL', 'https://play.google.com/apps/testing/com.motogo24.app');

// Logo
define('LOGO_SVG', 'gfx/logo.svg');

// ===== Webmaster Tools verifikační kódy =====
// Po registraci domény v každém z těchto nástrojů sem vlož content hodnotu z meta tagu.
// Hodnoty jdou nastavit i přes env vars (server config / .env), nesmí ale jít do gitu jako secret.
//   Google Search Console:  MOTOGO_VERIFY_GOOGLE_<TLD> (per doména) nebo MOTOGO_VERIFY_GOOGLE (fallback)
//   Bing Webmaster Tools:   MOTOGO_VERIFY_BING (msvalidate.01)
//   Seznam Webmaster:       MOTOGO_VERIFY_SEZNAM (seznam-wmt) — DŮLEŽITÉ pro CZ trh
//   Yandex Webmaster:       MOTOGO_VERIFY_YANDEX
//   Pinterest:              MOTOGO_VERIFY_PINTEREST
//   Facebook domain verif:  MOTOGO_VERIFY_FACEBOOK
// Pokud jsou prázdné, žádný meta tag se neemituje (viz layout.php).
//
// Google Search Console má každou doménu jako samostatnou property → každá má
// JINÝ verifikační kód. Render logika v layout.php vybere podle HTTP_HOST.
define('VERIFY_GOOGLE_CZ',  getenv('MOTOGO_VERIFY_GOOGLE_CZ')  ?: 'jGbt3Ej94_RHklqQwKGojKmaYFMkR9EGS2pisrZJuNM');
define('VERIFY_GOOGLE_COM', getenv('MOTOGO_VERIFY_GOOGLE_COM') ?: 'Sr-9VYMf3Ybg5XE0KJqW4KoOdXoUbrcLIkLue3MYS0A');
define('VERIFY_GOOGLE_PL',  getenv('MOTOGO_VERIFY_GOOGLE_PL')  ?: 'q41TuwifbZxhkJlkQHTAPgZ39KeRrWCuyN96wZZOF1E');
define('VERIFY_GOOGLE_AT',  getenv('MOTOGO_VERIFY_GOOGLE_AT')  ?: 'i9_XCKaWX1UrX95Ai5QwkAb1Kpdkp0i2SHE86Na9u1M');
define('VERIFY_GOOGLE_ES',  getenv('MOTOGO_VERIFY_GOOGLE_ES')  ?: 'aLjFnL9wsrl1kzd60Lkh5JgEmS6rWuvXj0Aiehfa8Ss');
// .fr a .nl 2026-05 — kódy doplň po vytvoření Search Console property pro
// motogo24.fr a motogo24.nl. Do té doby fallback na VERIFY_GOOGLE (CZ kód
// nezpůsobí škodu, jen na nových doménách neproběhne ownership ověření).
define('VERIFY_GOOGLE_FR',  getenv('MOTOGO_VERIFY_GOOGLE_FR')  ?: '');
define('VERIFY_GOOGLE_NL',  getenv('MOTOGO_VERIFY_GOOGLE_NL')  ?: '');
// Fallback pro neuvedené domény (např. lokální dev, alias). Zachová zpětnou kompat.
define('VERIFY_GOOGLE',    getenv('MOTOGO_VERIFY_GOOGLE')    ?: VERIFY_GOOGLE_CZ);
define('VERIFY_BING',      getenv('MOTOGO_VERIFY_BING')      ?: '');
define('VERIFY_SEZNAM',    getenv('MOTOGO_VERIFY_SEZNAM')    ?: '');
define('VERIFY_YANDEX',    getenv('MOTOGO_VERIFY_YANDEX')    ?: '');
define('VERIFY_PINTEREST', getenv('MOTOGO_VERIFY_PINTEREST') ?: '');
define('VERIFY_FACEBOOK',  getenv('MOTOGO_VERIFY_FACEBOOK')  ?: '');

// ===== Seznam.cz ekosystém — externí profily pro NAP konzistenci =====
// Vlož URL profilu/karty firmy v každé z těchto Seznam služeb. Použijí se v
// LocalBusiness JSON-LD jako "sameAs" — Seznam tak propojí web s firemní kartou
// a posílí lokální vyhledávání. Pokud prázdné, do sameAs se nepřidá.
//   Firmy.cz       — firemní karta (https://www.firmy.cz/detail/...)
//   Mapy.cz        — pin firmy na Mapy.cz (https://mapy.cz/zakladni?source=firm&id=...)
//   Heureka.cz     — e-shop profil (https://obchody.heureka.cz/...)
//   Zbozi.cz       — feed/profil v Seznam Zbozi (https://www.zbozi.cz/shop/...)
//   Seznam Hodnoceni — recenze obchodu (https://obchody.heureka.cz/...recenze/)
define('SAMEAS_FIRMY_CZ',   getenv('MOTOGO_SAMEAS_FIRMY_CZ')   ?: '');
define('SAMEAS_MAPY_CZ',    getenv('MOTOGO_SAMEAS_MAPY_CZ')    ?: '');
define('SAMEAS_HEUREKA',    getenv('MOTOGO_SAMEAS_HEUREKA')    ?: '');
define('SAMEAS_ZBOZI',      getenv('MOTOGO_SAMEAS_ZBOZI')      ?: '');

// ===== Sklik (Seznam reklamní systém) =====
// SKLIK_RETARGETING_ID — ID retargetingového kódu (číslo z Sklik admin → Měření).
// Pokud prázdné, žádný měřící kód se neemituje.
// Conversion tracking se řeší zvlášť na confirmation stránkách (rezervace,
// objednávka) — tady je jen univerzální retargeting visible na všech stránkách.
define('SKLIK_RETARGETING_ID', getenv('MOTOGO_SKLIK_RETARGETING_ID') ?: '');

// ===== Google Tag Manager =====
// GTM_CONTAINER_ID — kontejner ID (např. GTM-XXXXXXX). Načítá se na všech
// stránkách napříč doménami (motogo24.cz i motogo24.com). Konverzní cíle
// (Google Ads — potvrzená rezervace/platba Stripe, objednávka, poukaz) se
// posílají přes dataLayer event `purchase` (GA4 ecommerce schéma) na
// /potvrzeni stránce po potvrzení Stripe platby. V GTM se pak namapuje
// trigger event=purchase → Google Ads Conversion Tag (vlastní conversion ID
// + label dodá inzerent v GTM, ne v kódu).
define('GTM_CONTAINER_ID', getenv('MOTOGO_GTM_CONTAINER_ID') ?: 'GTM-WP9CHL59');

// Firemní údaje
define('COMPANY_NAME', 'Bc. Petra Semorádová');
define('COMPANY_ICO', '21874263');
define('COMPANY_ADDRESS', 'Mezná 9, 393 01 Pelhřimov');

// ===== Cache busting pro statické assety =====
// assetUrl('/css/main.css') → '/css/main.css?v=1714338472'
// Verze je modifikační čas souboru — každá změna automaticky invaliduje
// browser cache, takže uživatelé nikdy nemusí dělat hard-refresh.
function assetUrl($path) {
    $abs = __DIR__ . $path;
    $v = @filemtime($abs);
    if (!$v) return BASE_URL . $path;
    return BASE_URL . $path . '?v=' . $v;
}

// ===== CMS admin — ověření podepsané cookie =====
// Bezpečnostní fix 2026-06-10: admin režim se NEODVOZUJE z holého `mg_cms_admin=1`
// (kdokoli si ho mohl nastavit a server mu pak vydal pravý cms_admin_token).
//
// Cookie nese buď:
//   a) podepsanou capability `r1.<exp>.<base64url(RSA-SHA256 sig)>` (#5 fix) —
//      ověřitelnou VEŘEJNÝM klíčem níže, BEZ čtení tokenu (token je skrytý z anon),
//   b) NEBO legacy `<exp>.<HMAC(cms_admin_token)>` — fallback, dokud není nasazená
//      edge funkce `cms-admin-auth` a token ještě je anon-čitelný.
// Útočník bez privátního klíče / bez znalosti tokenu platnou cookie nevyrobí.
//
// VEŘEJNÝ RSA klíč (pár k privátnímu CMS_ADMIN_SIGN_KEY v Supabase secretu).
// Veřejný klíč není tajný — smí být v gitu.
define('CMS_ADMIN_PUBLIC_KEY', "-----BEGIN PUBLIC KEY-----\n" .
    "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2wVCAaAGj67bn+XkGpVC\n" .
    "I82zXzvL4JdN819ETIPUKEHROuMCJVDH+br9KULULnaXszi5CplRcjPGh//kwZob\n" .
    "MA0WbaNlZr1UJV8Ty7VB/3wUmX18kTrWCjtx6iOXAMU1PfGwIbdsqPis48PYR2mW\n" .
    "X8rHA9P/o16pJM25SIjepgNOSLUvGDWvSNyQLn5HkANMDFPMi89R1NN9WDsNtz5t\n" .
    "mhcJIA79G+ztYCgx0qcPkzaxT87/jFNgTU2jFK6jBLMu9tgVHK/pIDzmUOFjyCVl\n" .
    "2YhTqsZfLv2zvHV2VTFJaH2v5dLV3NHUeOHRYSIi4Z5VYWRLw7roq5pipfjJ22E6\n" .
    "/wIDAQAB\n" .
    "-----END PUBLIC KEY-----\n");

function mgBase64UrlDecode($s) {
    $s = strtr($s, '-_', '+/');
    $pad = strlen($s) % 4;
    if ($pad) $s .= str_repeat('=', 4 - $pad);
    return base64_decode($s, true);
}

// Ověří podepsanou capability `r1.<exp>.<b64url sig>` veřejným klíčem (RS256).
function mgCmsVerifyCap($cap) {
    if (!is_string($cap) || strncmp($cap, 'r1.', 3) !== 0) return false;
    $parts = explode('.', $cap);
    if (count($parts) !== 3) return false;
    $exp = $parts[1]; $sigB64 = $parts[2];
    if (!ctype_digit($exp) || (int)$exp < time()) return false;
    $sig = mgBase64UrlDecode($sigB64);
    if ($sig === false || $sig === '') return false;
    if (!function_exists('openssl_verify')) return false;
    $ok = openssl_verify('cms|' . $exp, $sig, CMS_ADMIN_PUBLIC_KEY, OPENSSL_ALGO_SHA256);
    return $ok === 1;
}

// Funkce je v config.php (načten první), ale SupabaseClient instancuje až za
// běhu (v té době už je supabase.php načten). Re-entrancy guard brání rekurzi
// přes cacheGet()→isCmsAdmin().
// POZOR: skutečné ověření čte PODEPSANOU cookie `mg_cms_sig` (HttpOnly), NIKDY
// ne JS-čitelný flag `mg_cms_admin=1` (ten je jen kosmetický spínač overlaye —
// kdokoli si ho může nastavit, ale bez platného `mg_cms_sig` layout.php overlay
// JS vůbec nevloží a žádný token do stránky nepošle).
function mgCmsAdminValid() {
    static $cached = null;
    static $computing = false;
    if ($cached !== null) return $cached;
    if ($computing) return false;
    $cookie = isset($_COOKIE['mg_cms_sig']) ? (string)$_COOKIE['mg_cms_sig'] : '';
    if ($cookie === '') return $cached = false;

    // a) Nová podepsaná capability — ověř veřejným klíčem, žádné čtení tokenu/DB.
    if (strncmp($cookie, 'r1.', 3) === 0) {
        return $cached = mgCmsVerifyCap($cookie);
    }

    // b) Legacy HMAC `<exp>.<hmac>` — fallback, ověř proti tokenu (anon read).
    if (strpos($cookie, '.') === false) return $cached = false;
    $bits = explode('.', $cookie, 2);
    $exp = $bits[0]; $sig = isset($bits[1]) ? $bits[1] : '';
    if (!ctype_digit($exp) || (int)$exp < time() || $sig === '') return $cached = false;
    if (!class_exists('SupabaseClient')) return false;
    $computing = true;
    $token = null;
    try {
        $sb = new SupabaseClient();
        $token = $sb->fetchSetting('cms_admin_token');
    } catch (\Throwable $e) { $computing = false; return $cached = false; }
    $computing = false;
    if (!is_string($token) || $token === '') return $cached = false;
    $expected = hash_hmac('sha256', 'cms_admin|' . $exp, $token);
    return $cached = hash_equals($expected, $sig);
}

// Legacy HMAC cookie (fallback, dokud není nasazená cms-admin-auth edge funkce).
function mgCmsAdminCookieValue($token, $expiry) {
    $sig = hash_hmac('sha256', 'cms_admin|' . $expiry, (string)$token);
    return $expiry . '.' . $sig;
}

// Ověří RAW cms_admin_token. Primárně přes edge `cms-admin-auth` (čte token
// service_role klíčem → funguje i když je token skrytý z anon). Fallback: přímé
// porovnání proti app_settings (anon read) — dokud edge funkce není nasazená.
// Vrací bool. Použito v cms-cache-purge / master-export (server-to-server volání).
function mgCmsVerifyRawToken($token) {
    if (!is_string($token) || $token === '') return false;
    // 1) edge exchange (token → 200 = platný)
    if (function_exists('curl_init')) {
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
                CURLOPT_POSTFIELDS => json_encode(['token' => $token]),
            ]);
            $resp = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($code === 200 && $resp !== false) {
                $j = json_decode($resp, true);
                if (is_array($j) && !empty($j['ok'])) return true;
            }
            // 403/invalid_token → token nesedí (a edge je nasazená) → false.
            if ($code === 403) return false;
            // jiný kód (503 sign_key_not_configured / síť) → spadni na fallback.
        }
    }
    // 2) fallback: přímé porovnání (anon read) — funguje dokud token není skrytý.
    if (!class_exists('SupabaseClient')) return false;
    try {
        $sb = new SupabaseClient();
        $expected = $sb->fetchSetting('cms_admin_token');
    } catch (\Throwable $e) { return false; }
    return is_string($expected) && $expected !== '' && hash_equals($expected, $token);
}
