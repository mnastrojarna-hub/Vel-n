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

// Logo
define('LOGO_SVG', 'gfx/logo.svg');

// ===== Webmaster Tools verifikační kódy =====
// Po registraci domény v každém z těchto nástrojů sem vlož content hodnotu z meta tagu.
// Hodnoty jdou nastavit i přes env vars (server config / .env), nesmí ale jít do gitu jako secret.
//   Google Search Console:  MOTOGO_VERIFY_GOOGLE
//   Bing Webmaster Tools:   MOTOGO_VERIFY_BING (msvalidate.01)
//   Seznam Webmaster:       MOTOGO_VERIFY_SEZNAM (seznam-wmt) — DŮLEŽITÉ pro CZ trh
//   Yandex Webmaster:       MOTOGO_VERIFY_YANDEX
//   Pinterest:              MOTOGO_VERIFY_PINTEREST
//   Facebook domain verif:  MOTOGO_VERIFY_FACEBOOK
// Pokud jsou prázdné, žádný meta tag se neemituje (viz layout.php).
define('VERIFY_GOOGLE',    getenv('MOTOGO_VERIFY_GOOGLE')    ?: '');
define('VERIFY_BING',      getenv('MOTOGO_VERIFY_BING')      ?: '');
define('VERIFY_SEZNAM',    getenv('MOTOGO_VERIFY_SEZNAM')    ?: '');
define('VERIFY_YANDEX',    getenv('MOTOGO_VERIFY_YANDEX')    ?: '');
define('VERIFY_PINTEREST', getenv('MOTOGO_VERIFY_PINTEREST') ?: '');
define('VERIFY_FACEBOOK',  getenv('MOTOGO_VERIFY_FACEBOOK')  ?: '');

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
