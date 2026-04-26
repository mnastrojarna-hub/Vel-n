<?php
// ===== /feed.xml — RSS 2.0 feed pro blog =====
// Pomáhá Google Discover a AI agentům s aktualizovaným obsahem.
// Cachuje se na úrovni Supabase clienta (5 min TTL).

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../supabase.php';

$sb = new SupabaseClient();
$posts = $sb->fetchCmsPages();
if (!is_array($posts)) $posts = [];

// Dynamická base URL podle aktuální domény (motogo24.com / motogo24.cz)
$host = $_SERVER['HTTP_HOST'] ?? 'motogo24.cz';
$host = preg_replace('#^www\.#i', '', strtolower($host));
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
$siteOrigin = ($isHttps ? 'https://' : 'http://') . $host;

header('Content-Type: application/rss+xml; charset=utf-8');
header('Cache-Control: public, max-age=1800');
header('Access-Control-Allow-Origin: *');
header('X-Robots-Tag: noindex, follow');

$now = gmdate('D, d M Y H:i:s') . ' GMT';
$lastBuild = $now;
if (!empty($posts) && !empty($posts[0]['updated_at'])) {
    $ts = strtotime($posts[0]['updated_at']);
    if ($ts) $lastBuild = gmdate('D, d M Y H:i:s', $ts) . ' GMT';
}

echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
echo '<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">' . "\n";
echo '  <channel>' . "\n";
echo '    <title>MotoGo24 — Blog a tipy na motorkářské trasy</title>' . "\n";
echo '    <link>' . $siteOrigin . '/blog</link>' . "\n";
echo '    <atom:link href="' . $siteOrigin . '/feed.xml" rel="self" type="application/rss+xml" />' . "\n";
echo '    <description>Tipy na motorkářské trasy v Česku, návody, recenze motorek a novinky z půjčovny MotoGo24.</description>' . "\n";
echo '    <language>cs-CZ</language>' . "\n";
echo '    <copyright>Bc. Petra Semorádová, IČO 21874263</copyright>' . "\n";
echo '    <managingEditor>info@motogo24.cz (MotoGo24)</managingEditor>' . "\n";
echo '    <webMaster>info@motogo24.cz (MotoGo24)</webMaster>' . "\n";
echo '    <generator>MotoGo24 Web PHP</generator>' . "\n";
echo '    <lastBuildDate>' . $lastBuild . '</lastBuildDate>' . "\n";
echo '    <pubDate>' . $now . '</pubDate>' . "\n";
echo '    <ttl>30</ttl>' . "\n";
echo '    <image>' . "\n";
echo '      <url>' . $siteOrigin . '/gfx/logo.svg</url>' . "\n";
echo '      <title>MotoGo24</title>' . "\n";
echo '      <link>' . $siteOrigin . '</link>' . "\n";
echo '    </image>' . "\n";

foreach ($posts as $p) {
    $slug = $p['slug'] ?? '';
    if (!$slug) continue;
    $title = $p['title'] ?? 'Nový článek';
    $excerpt = $p['excerpt'] ?? $p['summary'] ?? '';
    $body = $p['content'] ?? $p['body'] ?? '';
    $createdAt = $p['created_at'] ?? $p['published_at'] ?? null;
    $pubDate = $createdAt ? gmdate('D, d M Y H:i:s', strtotime($createdAt)) . ' GMT' : $now;
    $url = $siteOrigin . '/blog/' . $slug;
    $author = $p['author'] ?? 'MotoGo24';
    $imageUrl = $p['image_url'] ?? $p['thumbnail'] ?? '';

    echo '    <item>' . "\n";
    echo '      <title>' . htmlspecialchars($title, ENT_XML1) . '</title>' . "\n";
    echo '      <link>' . $url . '</link>' . "\n";
    echo '      <guid isPermaLink="true">' . $url . '</guid>' . "\n";
    echo '      <pubDate>' . $pubDate . '</pubDate>' . "\n";
    echo '      <dc:creator>' . htmlspecialchars($author, ENT_XML1) . '</dc:creator>' . "\n";
    if ($excerpt) {
        echo '      <description>' . htmlspecialchars($excerpt, ENT_XML1) . '</description>' . "\n";
    }
    if ($body) {
        echo '      <content:encoded><![CDATA[' . $body . ']]></content:encoded>' . "\n";
    }
    if ($imageUrl) {
        $absImg = (strpos($imageUrl, 'http') === 0) ? $imageUrl : ($siteOrigin . '/' . ltrim($imageUrl, '/'));
        echo '      <enclosure url="' . htmlspecialchars($absImg, ENT_XML1) . '" type="image/jpeg" />' . "\n";
    }
    echo '    </item>' . "\n";
}

echo '  </channel>' . "\n";
echo '</rss>' . "\n";
