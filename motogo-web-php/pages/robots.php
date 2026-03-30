<?php
// ===== MotoGo24 Web PHP — robots.txt =====

header('Content-Type: text/plain; charset=utf-8');
echo "User-agent: *\n";
echo "Allow: /\n";
echo "\n";
echo "# Private/transactional pages\n";
echo "Disallow: /potvrzeni\n";
echo "\n";
echo "# Sitemap\n";
echo "Sitemap: " . SITE_URL . "/sitemap.xml\n";
