<?php
// ===== MotoGo24 Web PHP — Hlavní router + entry point =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/supabase.php';
require_once __DIR__ . '/components.php';
require_once __DIR__ . '/layout.php';

// Získání cesty z REQUEST_URI (bez query stringu)
$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
$path = parse_url($requestUri, PHP_URL_PATH);

// Odstraň trailing slash (kromě /)
if ($path !== '/' && substr($path, -1) === '/') {
    $path = rtrim($path, '/');
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
