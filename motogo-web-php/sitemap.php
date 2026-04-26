<?php
// ===== MotoGo24 Web PHP — Dynamický XML Sitemap =====
// Pro každou URL se emitují <xhtml:link rel="alternate" hreflang="…">
// pro všech 7 podporovaných jazyků (cs/en/de/es/fr/nl/pl) + x-default.
// Tím Google ví, že existují ekvivalentní jazykové verze.

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
require_once __DIR__ . '/supabase.php';

header('Content-Type: application/xml; charset=utf-8');

$base = 'https://motogo24.cz';
$today = date('Y-m-d');
$sb = new SupabaseClient();

// Vyrenderuje <xhtml:link rel="alternate"...> pro všechny jazyky pro daný path.
function sitemapAlternates($base, $path) {
    if (!defined('I18N_SUPPORTED')) return '';
    $out = '';
    foreach (I18N_SUPPORTED as $code) {
        $href = $base . $path . ($code === I18N_DEFAULT ? '' : ('?lang=' . $code));
        $out .= '    <xhtml:link rel="alternate" hreflang="' . htmlspecialchars($code) . '" href="' . htmlspecialchars($href) . '"/>' . "\n";
    }
    $out .= '    <xhtml:link rel="alternate" hreflang="x-default" href="' . htmlspecialchars($base . $path) . '"/>' . "\n";
    return $out;
}

function sitemapEntry($base, $path, $changefreq, $priority, $lastmod, $alternates = true) {
    $alt = $alternates ? sitemapAlternates($base, $path) : '';
    return '  <url>' . "\n"
         . '    <loc>' . $base . htmlspecialchars($path) . '</loc>' . "\n"
         . '    <lastmod>' . $lastmod . '</lastmod>' . "\n"
         . '    <changefreq>' . $changefreq . '</changefreq>' . "\n"
         . '    <priority>' . $priority . '</priority>' . "\n"
         . $alt
         . '  </url>' . "\n";
}

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
    ['loc' => '/eshop',                  'priority' => '0.8',  'changefreq' => 'weekly'],
    ['loc' => '/blog',                   'priority' => '0.7',  'changefreq' => 'weekly'],
    ['loc' => '/kontakt',                'priority' => '0.8',  'changefreq' => 'monthly'],
    ['loc' => '/obchodni-podminky',      'priority' => '0.3',  'changefreq' => 'yearly'],
    ['loc' => '/gdpr',                   'priority' => '0.3',  'changefreq' => 'yearly'],
    ['loc' => '/smlouva',                'priority' => '0.3',  'changefreq' => 'yearly'],
];

echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">' . "\n";

// Statické stránky
foreach ($static as $s) {
    echo sitemapEntry($base, $s['loc'], $s['changefreq'], $s['priority'], $today);
}

// Dynamické: motorky z DB
$motos = $sb->fetchMotos();
foreach ($motos as $m) {
    if (empty($m['id'])) continue;
    echo sitemapEntry($base, '/katalog/' . $m['id'], 'weekly', '0.8', $today);
}

// Dynamické: produkty z DB (e-shop)
$products = $sb->fetchProducts();
if (is_array($products)) {
    foreach ($products as $p) {
        if (empty($p['id'])) continue;
        $lastmod = !empty($p['updated_at']) ? substr($p['updated_at'], 0, 10) : $today;
        echo sitemapEntry($base, '/eshop/' . $p['id'], 'weekly', '0.7', $lastmod);
    }
}

// Dynamické: blog posty z DB + fallback když DB prázdná
$posts = $sb->fetchCmsPages();
if (!$posts || empty($posts)) {
    require_once __DIR__ . '/pages/blog_fallback.php';
    $posts = getBlogFallbackPosts();
}
foreach ($posts as $p) {
    if (empty($p['slug'])) continue;
    $lastmod = !empty($p['updated_at']) ? substr($p['updated_at'], 0, 10)
        : (!empty($p['created_at']) ? substr($p['created_at'], 0, 10) : $today);
    echo sitemapEntry($base, '/blog/' . $p['slug'], 'monthly', '0.7', $lastmod);
}

echo '</urlset>';
