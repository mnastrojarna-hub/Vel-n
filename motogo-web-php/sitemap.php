<?php
// ===== MotoGo24 Web PHP — Dynamický XML Sitemap =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/supabase.php';

header('Content-Type: application/xml; charset=utf-8');

$base = 'https://motogo24.cz';
$today = date('Y-m-d');
$sb = new SupabaseClient();

// Statické URL
$static = [
    ['loc' => '/',                       'priority' => '1.0',  'changefreq' => 'weekly'],
    ['loc' => '/katalog',                'priority' => '0.9',  'changefreq' => 'weekly'],
    ['loc' => '/katalog/cestovni',       'priority' => '0.8',  'changefreq' => 'weekly'],
    ['loc' => '/katalog/detske',         'priority' => '0.8',  'changefreq' => 'weekly'],
    ['loc' => '/pujcovna-motorek',       'priority' => '0.8',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit',             'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/postup',      'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/pristaveni',  'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/vyzvednuti',  'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/co-v-cene',   'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/dokumenty',   'priority' => '0.7',  'changefreq' => 'monthly'],
    ['loc' => '/jak-pujcit/faq',         'priority' => '0.8',  'changefreq' => 'monthly'],
    ['loc' => '/poukazy',                'priority' => '0.8',  'changefreq' => 'monthly'],
    ['loc' => '/blog',                   'priority' => '0.7',  'changefreq' => 'weekly'],
    ['loc' => '/kontakt',                'priority' => '0.8',  'changefreq' => 'monthly'],
    ['loc' => '/obchodni-podminky',      'priority' => '0.3',  'changefreq' => 'yearly'],
    ['loc' => '/gdpr',                   'priority' => '0.3',  'changefreq' => 'yearly'],
    ['loc' => '/smlouva',                'priority' => '0.3',  'changefreq' => 'yearly'],
];

echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . "\n";

// Statické stránky
foreach ($static as $s) {
    echo '  <url><loc>' . $base . htmlspecialchars($s['loc']) . '</loc><lastmod>' . $today . '</lastmod><changefreq>' . $s['changefreq'] . '</changefreq><priority>' . $s['priority'] . '</priority></url>' . "\n";
}

// Dynamické: motorky z DB
$motos = $sb->fetchMotos();
foreach ($motos as $m) {
    echo '  <url><loc>' . $base . '/katalog/' . htmlspecialchars($m['id']) . '</loc><lastmod>' . $today . '</lastmod><changefreq>weekly</changefreq><priority>0.8</priority></url>' . "\n";
}

// Dynamické: blog posty z DB
$posts = $sb->fetchCmsPages();
foreach ($posts as $p) {
    if (empty($p['slug'])) continue;
    $lastmod = !empty($p['updated_at']) ? substr($p['updated_at'], 0, 10) : $today;
    echo '  <url><loc>' . $base . '/blog/' . htmlspecialchars($p['slug']) . '</loc><lastmod>' . $lastmod . '</lastmod><changefreq>monthly</changefreq><priority>0.7</priority></url>' . "\n";
}

echo '</urlset>';
