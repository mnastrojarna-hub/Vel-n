<?php
// ===== MotoGo24 Web PHP — Router =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/supabase.php';
require_once __DIR__ . '/components.php';
require_once __DIR__ . '/layout.php';

$requestUri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestUri = rtrim($requestUri, '/') ?: '/';

// Simple cache for Supabase data (within single request)
$sb = new SupabaseClient();

// Route matching
$routes = [
    '/' => 'pages/home.php',
    '/katalog' => 'pages/katalog.php',
    '/katalog/cestovni' => 'pages/katalog.php',
    '/katalog/detske' => 'pages/katalog.php',
    '/pujcovna-motorek' => 'pages/pujcovna.php',
    '/jak-pujcit' => 'pages/jak-pujcit.php',
    '/jak-pujcit/postup' => 'pages/jak-pujcit-postup.php',
    '/jak-pujcit/pristaveni' => 'pages/jak-pujcit-pristaveni.php',
    '/jak-pujcit/vyzvednuti' => 'pages/jak-pujcit-vyzvednuti.php',
    '/jak-pujcit/co-v-cene' => 'pages/jak-pujcit-cena.php',
    '/jak-pujcit/dokumenty' => 'pages/jak-pujcit-dokumenty.php',
    '/jak-pujcit/faq' => 'pages/faq.php',
    '/poukazy' => 'pages/poukazy.php',
    '/blog' => 'pages/blog.php',
    '/kontakt' => 'pages/kontakt.php',
    '/obchodni-podminky' => 'pages/cms.php',
    '/gdpr' => 'pages/cms.php',
    '/smlouva' => 'pages/cms.php',
    '/mapa-stranek' => 'pages/sitemap-page.php',
    '/rezervace' => 'pages/rezervace.php',
    '/potvrzeni' => 'pages/potvrzeni.php',
    '/sitemap.xml' => 'pages/sitemap-xml.php',
    '/robots.txt' => 'pages/robots.php',
];

// Exact match
if (isset($routes[$requestUri])) {
    require __DIR__ . '/' . $routes[$requestUri];
    exit;
}

// Parametric routes
if (preg_match('#^/katalog/([a-f0-9\-]+)$#', $requestUri, $m) && $m[1] !== 'cestovni' && $m[1] !== 'detske') {
    $motoId = $m[1];
    require __DIR__ . '/pages/katalog-detail.php';
    exit;
}

if (preg_match('#^/blog/([a-z0-9\-]+)$#', $requestUri, $m)) {
    $blogSlug = $m[1];
    require __DIR__ . '/pages/blog-detail.php';
    exit;
}

// 404
http_response_code(404);
require __DIR__ . '/pages/404.php';
