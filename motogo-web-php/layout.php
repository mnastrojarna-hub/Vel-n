<?php
// ===== MotoGo24 Web PHP — Shared Layout (Header + Footer + SEO) =====

require_once __DIR__ . '/config.php';

// Menu struktura
function getMenuItems() {
    return [
        ['label' => 'Půjčovna motorek', 'route' => '/pujcovna-motorek'],
        ['label' => 'Katalog motorek', 'route' => '/katalog', 'children' => [
            ['label' => 'Cestovní motorky', 'route' => '/katalog/cestovni'],
            ['label' => 'Dětské motorky', 'route' => '/katalog/detske'],
        ]],
        ['label' => 'Jak si půjčit motorku', 'route' => '/jak-pujcit', 'children' => [
            ['label' => 'Postup půjčení', 'route' => '/jak-pujcit/postup'],
            ['label' => 'Přistavení motocyklu', 'route' => '/jak-pujcit/pristaveni'],
            ['label' => 'Vyzvednutí motocyklu', 'route' => '/jak-pujcit/vyzvednuti'],
            ['label' => 'Co je v ceně', 'route' => '/jak-pujcit/co-v-cene'],
            ['label' => 'Dokumenty a návody', 'route' => '/jak-pujcit/dokumenty'],
            ['label' => 'Často kladené dotazy', 'route' => '/jak-pujcit/faq'],
        ]],
        ['label' => 'Poukazy', 'route' => '/poukazy'],
        ['label' => 'Blog', 'route' => '/blog'],
        ['label' => 'Kontakt', 'route' => '/kontakt'],
    ];
}

function renderHeader($currentPath = '/') {
    $menuItems = getMenuItems();
    $nav = '';
    foreach ($menuItems as $item) {
        $hasSub = !empty($item['children']);
        $arrow = $hasSub ? ' <img src="' . BASE_URL . '/gfx/arrow-down.svg" alt="" loading="lazy" class="menu-arrow">' : '';
        $isActive = ($currentPath !== '/' && strpos($currentPath, $item['route']) === 0);
        $nav .= '<li' . ($hasSub ? ' class="has-sub"' : '') . '>';
        $nav .= '<a' . ($isActive ? ' class="active"' : '') . ' data-route="' . $item['route'] . '" href="' . BASE_URL . $item['route'] . '">' . $item['label'] . $arrow . '</a>';
        if ($hasSub) {
            $nav .= '<ul class="submenu bs">';
            foreach ($item['children'] as $ch) {
                $nav .= '<li><a data-route="' . $ch['route'] . '" href="' . BASE_URL . $ch['route'] . '">' . $ch['label'] . '</a></li>';
            }
            $nav .= '</ul>';
        }
        $nav .= '</li>';
    }

    return '<header>' .
        '<ul class="focus"><li><a href="#main-menu">PŘEJDI NA HLAVNÍ MENU</a></li><li><a href="#content">PŘEJDI NA OBSAH</a></li><li><a href="#footer">PŘEJDI NA KONTAKT</a></li></ul>' .
        '<div class="header"><div class="container dfcs">' .
            '<div class="header-logo"><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="Půjčovna motorek Vysočina Motogo24" loading="lazy"></a></div>' .
            '<div class="header-phone"><p><a href="' . PHONE_LINK . '" aria-label="Zavolejte nám"><img alt="Zavolejte" src="' . BASE_URL . '/gfx/telefon-header.svg" loading="lazy"></a>&nbsp;<a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
            '<div class="header-menu dfje">' .
                '<button class="nav-toggle" aria-label="Menu" onclick="document.getElementById(\'mobile-menu\').classList.toggle(\'open\')">MENU ☰</button>' .
                '<nav id="mobile-menu" class="mobile-menu-overlay">' .
                    '<button class="mobile-menu-close" aria-label="Zavřít" onclick="document.getElementById(\'mobile-menu\').classList.toggle(\'open\')">✕</button>' .
                    '<ul id="main-menu" class="main-menu df">' . $nav .
                        '<li class="menu-rez"><a class="btn btngreen-small pulse" data-route="/rezervace" href="' . BASE_URL . '/rezervace">REZERVACE</a></li>' .
                    '</ul>' .
                '</nav>' .
            '</div>' .
        '</div></div>' .
    '</header>';
}

function renderFooter() {
    $menuItems = getMenuItems();
    $menuHtml = '';
    foreach ($menuItems as $item) {
        $menuHtml .= '<li><a data-route="' . $item['route'] . '" href="' . BASE_URL . $item['route'] . '">' . $item['label'] . '</a></li>';
    }
    $menuHtml .= '<li><a data-route="/rezervace" href="' . BASE_URL . '/rezervace">REZERVACE</a></li>';

    return '<footer id="footer"><div class="container"><div class="gr4">' .
        '<div>' .
            '<p><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="Motogo24" loading="lazy"></a></p><p>&nbsp;</p>' .
            '<p>Vítejte u Motogo24, vaší <strong>půjčovny motorek v Pelhřimově</strong>! Nabízíme <strong>pronájem motorek</strong> pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.</p>' .
        '</div>' .
        '<div><h3>Půjčovna motorek</h3><ul>' . $menuHtml . '</ul></div>' .
        '<div><h3>Půjčovna motorek na sítích</h3>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Facebook" src="' . BASE_URL . '/gfx/facebook.svg"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Instagram" src="' . BASE_URL . '/gfx/instagram.svg"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p>' .
        '</div>' .
        '<div class="footer-contact"><h3>Potřebujete poradit?</h3>' .
            '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/telefon.svg" alt="Telefon" class="icon-small" loading="lazy"></div><div><p>ZAVOLEJTE NÁM<br><strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/email.svg" alt="E-mail" class="icon-small" loading="lazy"></div><div><p>' . EMAIL_USER . '@' . EMAIL_DOMAIN . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/adresa.svg" alt="Adresa" class="icon-small" loading="lazy"></div><div><p><strong>Půjčovna motorek Motogo24</strong><br>' . ADDRESS . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/provozni-doba.svg" alt="Provozní doba" class="icon-small" loading="lazy"></div><div><p><strong>PO - NE</strong> 00:00 – 24:00&nbsp;(nonstop)</p></div></div>' .
        '</div>' .
    '</div></div>' .
    '<div class="copyright"><div class="container">' .
        '<p>© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena</p>' .
        '<p><a href="' . BASE_URL . '/mapa-stranek">Mapa stránek</a><a href="#">Cookies</a><a href="' . BASE_URL . '/gdpr">GDPR</a><a href="' . BASE_URL . '/obchodni-podminky">Obchodní podmínky</a><a href="' . BASE_URL . '/smlouva">Smlouva o pronájmu</a></p>' .
    '</div></div>' .
    '</footer>' .
    '<a id="Up" href="#" aria-label="NAHORU" onclick="window.scrollTo({top:0,behavior:\'smooth\'});return false"><img src="' . BASE_URL . '/gfx/arrow-top.svg" alt="NAHORU"></a>';
}

function renderInlineJs() {
    return '<script>
(function(){
  // Hash URL redirect (staré záložky #/katalog → /katalog)
  if(window.location.hash && window.location.hash.indexOf("#/")===0){
    window.location.replace(window.location.hash.substring(1));
  }
  // Scroll to top button
  var btn = document.getElementById("Up");
  if(btn){ window.addEventListener("scroll", function(){ btn.classList.toggle("visible", window.scrollY > 400); }); }
  // Submenu toggle (mobile)
  document.querySelectorAll(".has-sub > a").forEach(function(a){
    a.addEventListener("click", function(e){
      if(window.innerWidth <= 768){
        var li = a.parentElement;
        var wasOpen = li.classList.contains("show");
        document.querySelectorAll(".has-sub").forEach(function(el){ el.classList.remove("show"); });
        if(!wasOpen){ e.preventDefault(); li.classList.add("show"); }
      }
    });
  });
})();
</script>';
}

/**
 * Vykreslí kompletní HTML stránku s SEO.
 *
 * $meta klíče:
 *   description  — meta description
 *   keywords     — meta keywords (přepíše default)
 *   canonical    — canonical URL (default https://motogo24.cz{path})
 *   og_image     — OG image URL
 *   og_type      — OG type (default website)
 *   robots       — robots directive (default index,follow)
 *   schema       — extra JSON-LD schema string (přidá se vedle LocalBusiness)
 *   breadcrumbs  — pole pro BreadcrumbList schema [['name'=>'X','url'=>'Y'], ...]
 */
function renderPage($title, $content, $currentPath = '/', $meta = []) {
    $description = $meta['description'] ?? 'Půjčovna motorek Vysočina – silniční, sportovní, enduro i dětské. Nonstop pronájem bez kauce, online rezervace a motorkářská výbava zdarma.';
    $keywords = $meta['keywords'] ?? 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic';
    $canonical = $meta['canonical'] ?? ('https://motogo24.cz' . $currentPath);
    $ogImage = $meta['og_image'] ?? 'https://motogo24.cz/gfx/hero-banner.png';
    $ogType = $meta['og_type'] ?? 'website';
    $robots = $meta['robots'] ?? 'index,follow';
    $extraSchema = $meta['schema'] ?? '';
    $breadcrumbs = $meta['breadcrumbs'] ?? [];

    // BreadcrumbList schema
    $breadcrumbSchema = '';
    if (!empty($breadcrumbs)) {
        $items = [];
        foreach ($breadcrumbs as $i => $bc) {
            $items[] = '{"@type":"ListItem","position":' . ($i + 1) . ',"name":' . json_encode($bc['name'], JSON_UNESCAPED_UNICODE) . ',"item":' . json_encode($bc['url'], JSON_UNESCAPED_UNICODE) . '}';
        }
        $breadcrumbSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[' . implode(',', $items) . ']}
  </script>';
    }

    echo '<!DOCTYPE html>
<html lang="cs" dir="ltr" prefix="og: https://ogp.me/ns#">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="' . htmlspecialchars($description) . '">
  <meta name="keywords" content="' . htmlspecialchars($keywords) . '">
  <meta name="robots" content="' . htmlspecialchars($robots) . '">
  <meta name="author" content="MotoGo24">
  <meta property="og:url" content="' . htmlspecialchars($canonical) . '">
  <meta property="og:type" content="' . htmlspecialchars($ogType) . '">
  <meta property="og:locale" content="cs_CZ">
  <meta property="og:title" content="' . htmlspecialchars($title) . '">
  <meta property="og:site_name" content="Půjčovna motorek Vysočina MotoGo24">
  <meta property="og:description" content="' . htmlspecialchars($description) . '">
  <meta property="og:image" content="' . htmlspecialchars($ogImage) . '">
  <link rel="canonical" href="' . htmlspecialchars($canonical) . '">
  <link rel="icon" type="image/svg+xml" href="' . BASE_URL . '/favicon.svg">
  <link rel="apple-touch-icon" href="' . BASE_URL . '/apple-touch-icon.png">
  <title>' . htmlspecialchars($title) . '</title>

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    "name": "Motogo24 – půjčovna motorek Vysočina",
    "url": "https://motogo24.cz",
    "logo": "https://motogo24.cz/gfx/logo.svg",
    "image": "https://motogo24.cz/gfx/hero-banner.png",
    "email": "info@motogo24.cz",
    "telephone": "+420 774 256 271",
    "priceRange": "od 990 Kč/den",
    "openingHoursSpecification": {"@type": "OpeningHoursSpecification","dayOfWeek": ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens": "00:00","closes": "23:59"},
    "address": {"@type": "PostalAddress","streetAddress": "Mezná 9","addressLocality": "Pelhřimov","postalCode": "393 01","addressRegion": "Vysočina","addressCountry": "CZ"},
    "geo": {"@type": "GeoCoordinates","latitude": 49.4147,"longitude": 15.2953},
    "sameAs": ["' . FB_URL . '","' . IG_URL . '"]
  }
  </script>' . $breadcrumbSchema . ($extraSchema ? "\n" . $extraSchema : '') . '

  <!-- Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Jost:ital,wght@0,100..900;1,100..900&family=Montserrat:wght@600;800&display=swap" rel="stylesheet">

  <!-- Styles -->
  <link rel="stylesheet" href="' . BASE_URL . '/css/main.css">
  <link rel="stylesheet" href="' . BASE_URL . '/css/pages.css">
</head>
<body>
';
    echo renderHeader($currentPath);
    echo '<div id="app">';
    echo $content;
    echo '</div>';
    echo renderFooter();
    echo renderInlineJs();
    echo '
</body>
</html>';
}
