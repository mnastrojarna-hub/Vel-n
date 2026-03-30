<?php
// ===== MotoGo24 Web PHP — Dynamic XML Sitemap =====

header('Content-Type: application/xml; charset=utf-8');
echo '<?xml version="1.0" encoding="UTF-8"?>';
?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc><?php echo SITE_URL; ?>/</loc><priority>1.0</priority><changefreq>weekly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/katalog</loc><priority>0.9</priority><changefreq>weekly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/katalog/cestovni</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/katalog/detske</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/pujcovna-motorek</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/postup</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/pristaveni</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/vyzvednuti</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/co-v-cene</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/dokumenty</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/jak-pujcit/faq</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/poukazy</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/blog</loc><priority>0.7</priority><changefreq>weekly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/kontakt</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/rezervace</loc><priority>0.9</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/mapa-stranek</loc><priority>0.4</priority><changefreq>monthly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/obchodni-podminky</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/gdpr</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
  <url><loc><?php echo SITE_URL; ?>/smlouva</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
<?php
// Dynamic motorcycle detail pages
$motos = $sb->fetchMotos();
foreach ($motos as $m) {
    $id = htmlspecialchars($m['id'] ?? '', ENT_XML1, 'UTF-8');
    if ($id) {
        echo '  <url><loc>' . SITE_URL . '/katalog/' . $id . '</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>' . "\n";
    }
}

// Dynamic blog post pages
$posts = $sb->fetchCmsPages();
foreach ($posts as $p) {
    $slug = htmlspecialchars($p['slug'] ?? '', ENT_XML1, 'UTF-8');
    if ($slug) {
        echo '  <url><loc>' . SITE_URL . '/blog/' . $slug . '</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>' . "\n";
    }
}
?>
</urlset>
