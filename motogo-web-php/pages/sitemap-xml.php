<?php
header('Content-Type: application/xml; charset=utf-8');
echo '<?xml version="1.0" encoding="UTF-8"?>';
?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://motogo24.cz/</loc><priority>1.0</priority><changefreq>weekly</changefreq></url>
  <url><loc>https://motogo24.cz/katalog</loc><priority>0.9</priority><changefreq>weekly</changefreq></url>
  <url><loc>https://motogo24.cz/katalog/cestovni</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>
  <url><loc>https://motogo24.cz/katalog/detske</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>
  <url><loc>https://motogo24.cz/pujcovna-motorek</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/postup</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/pristaveni</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/vyzvednuti</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/co-v-cene</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/dokumenty</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/jak-pujcit/faq</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/poukazy</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/blog</loc><priority>0.7</priority><changefreq>weekly</changefreq></url>
  <url><loc>https://motogo24.cz/kontakt</loc><priority>0.8</priority><changefreq>monthly</changefreq></url>
  <url><loc>https://motogo24.cz/obchodni-podminky</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
  <url><loc>https://motogo24.cz/gdpr</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
  <url><loc>https://motogo24.cz/smlouva</loc><priority>0.3</priority><changefreq>yearly</changefreq></url>
<?php
// Dynamic motorcycle pages
$motos = $sb->fetchMotos();
foreach ($motos as $m) {
    echo '  <url><loc>https://motogo24.cz/katalog/' . htmlspecialchars($m['id']) . '</loc><priority>0.8</priority><changefreq>weekly</changefreq></url>' . "\n";
}
// Dynamic blog pages
$posts = $sb->fetchCmsPages();
foreach ($posts as $p) {
    echo '  <url><loc>https://motogo24.cz/blog/' . htmlspecialchars($p['slug']) . '</loc><priority>0.7</priority><changefreq>monthly</changefreq></url>' . "\n";
}
?>
</urlset>
