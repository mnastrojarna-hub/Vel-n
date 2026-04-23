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

// Firemní údaje
define('COMPANY_NAME', 'Bc. Petra Semorádová');
define('COMPANY_ICO', '21874263');
define('COMPANY_ADDRESS', 'Mezná 9, 393 01 Pelhřimov');
