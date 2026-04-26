<?php
// ===== MotoGo24 Web PHP — Shared Layout (Header + Footer + SEO) =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
require_once __DIR__ . '/i18n_currency.php';

// Menu struktura — labels jsou klíče i18n, route zůstává stejná napříč jazyky
function getMenuItems() {
    return [
        ['label' => t('menu.rental'), 'route' => '/pujcovna-motorek'],
        ['label' => t('menu.catalog'), 'route' => '/katalog'],
        ['label' => t('menu.howto'), 'route' => '/jak-pujcit', 'children' => [
            ['label' => t('menu.howto.process'), 'route' => '/jak-pujcit/postup'],
            ['label' => t('menu.howto.pickup'), 'route' => '/jak-pujcit/prevzeti'],
            ['label' => t('menu.howto.returnHome'), 'route' => '/jak-pujcit/vraceni-pujcovna'],
            ['label' => t('menu.howto.returnElsewhere'), 'route' => '/jak-pujcit/vraceni-jinde'],
            ['label' => t('menu.howto.price'), 'route' => '/jak-pujcit/co-v-cene'],
            ['label' => t('menu.howto.delivery'), 'route' => '/jak-pujcit/pristaveni'],
            ['label' => t('menu.howto.documents'), 'route' => '/jak-pujcit/dokumenty'],
            ['label' => t('menu.howto.faq'), 'route' => '/jak-pujcit/faq'],
        ]],
        ['label' => t('menu.vouchers'), 'route' => '/poukazy'],
        ['label' => t('menu.shop'), 'route' => '/eshop'],
        ['label' => t('menu.blog'), 'route' => '/blog'],
        ['label' => t('menu.contact'), 'route' => '/kontakt'],
    ];
}

function renderHeader($currentPath = '/') {
    $menuItems = getMenuItems();
    $nav = '';
    foreach ($menuItems as $item) {
        $hasSub = !empty($item['children']);
        $arrow = $hasSub ? ' <img src="' . BASE_URL . '/gfx/arrow-down.svg" alt="Rozbalit podmenu" aria-hidden="true" loading="lazy" class="menu-arrow">' : '';
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

    // Submenu šipka — překlad přes htmlspecialchars
    $submenuArrowAlt = htmlspecialchars(t('header.expandSubmenu'), ENT_QUOTES, 'UTF-8');
    // Záměna alt atributů v $nav (konzervativní replace pouze v naší šabloně)
    $nav = str_replace(' alt="Rozbalit podmenu" ', ' alt="' . $submenuArrowAlt . '" ', $nav);

    return '<header>' .
        '<ul class="focus"><li><a href="#main-menu">' . te('header.skip.menu') . '</a></li><li><a href="#content">' . te('header.skip.content') . '</a></li><li><a href="#footer">' . te('header.skip.contact') . '</a></li></ul>' .
        '<div class="header-topbar"><div class="container">' .
            '<div class="header-lang">' . renderCurrencySwitcher() . renderLanguageSwitcher() . '</div>' .
        '</div></div>' .
        '<div class="header"><div class="container dfcs">' .
            '<div class="header-logo"><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="' . te('header.logoAlt') . '" loading="lazy"></a></div>' .
            '<div class="header-phone"><p><a href="' . PHONE_LINK . '" aria-label="' . te('header.callUs') . '"><img alt="' . te('header.callUs') . '" src="' . BASE_URL . '/gfx/telefon-header.svg" loading="lazy"></a>&nbsp;<a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
            '<div class="header-menu dfje">' .
                '<button class="nav-toggle" aria-label="' . te('header.menuOpen') . '" aria-expanded="false" aria-controls="mobile-menu" onclick="(function(){var m=document.getElementById(\'mobile-menu\');var open=!m.classList.contains(\'open\');m.classList.toggle(\'open\',open);document.body.classList.toggle(\'menu-open\',open);this.setAttribute(\'aria-expanded\',open?\'true\':\'false\');}).call(this)">' . te('header.menuToggle') . '</button>' .
                '<nav id="mobile-menu" class="mobile-menu-overlay" aria-label="' . te('header.menuLabel') . '">' .
                    '<button class="mobile-menu-close" aria-label="' . te('header.menuClose') . '" onclick="document.getElementById(\'mobile-menu\').classList.remove(\'open\');document.body.classList.remove(\'menu-open\');var b=document.querySelector(\'.nav-toggle\');if(b)b.setAttribute(\'aria-expanded\',\'false\')">✕</button>' .
                    '<ul id="main-menu" class="main-menu">' . $nav .
                        '<li class="menu-rez"><a class="btn btngreen-small pulse" data-route="/rezervace" href="' . BASE_URL . '/rezervace">' . te('menu.reservation') . '</a></li>' .
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
    $menuHtml .= '<li><a data-route="/rezervace" href="' . BASE_URL . '/rezervace">' . te('menu.reservation') . '</a></li>';

    return '<footer id="footer"><div class="container"><div class="gr4">' .
        '<div>' .
            '<p><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="Motogo24" loading="lazy"></a></p><p>&nbsp;</p>' .
            '<p>' . t('footer.aboutText') . '</p>' .
        '</div>' .
        '<div><h3>' . te('footer.aboutTitle') . '</h3><ul>' . $menuHtml . '</ul></div>' .
        '<div><h3>' . te('footer.socialTitle') . '</h3>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Facebook" src="' . BASE_URL . '/gfx/facebook.svg"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Instagram" src="' . BASE_URL . '/gfx/instagram.svg"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p>' .
        '</div>' .
        '<div class="footer-contact"><h3>' . te('footer.helpTitle') . '</h3>' .
            '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/telefon.svg" alt="' . te('footer.iconPhone') . '" class="icon-small" loading="lazy"></div><div><p>' . te('footer.callUs') . '<br><strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/email.svg" alt="' . te('footer.iconEmail') . '" class="icon-small" loading="lazy"></div><div><p>' . EMAIL_USER . '@' . EMAIL_DOMAIN . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/adresa.svg" alt="' . te('footer.iconAddress') . '" class="icon-small" loading="lazy"></div><div><p><strong>' . te('footer.companyLine1') . '</strong><br>' . ADDRESS . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/provozni-doba.svg" alt="' . te('footer.openHoursIcon') . '" class="icon-small" loading="lazy"></div><div><p>' . te('footer.openHours') . '</p></div></div>' .
        '</div>' .
    '</div></div>' .
    '<div class="copyright"><div class="container">' .
        '<p>' . te('footer.copyright') . '</p>' .
        '<p><a href="' . BASE_URL . '/mapa-stranek">' . te('footer.sitemap') . '</a><a href="#">' . te('footer.cookies') . '</a><a href="' . BASE_URL . '/gdpr">' . te('footer.gdpr') . '</a><a href="' . BASE_URL . '/obchodni-podminky">' . te('footer.terms') . '</a><a href="' . BASE_URL . '/smlouva">' . te('footer.contract') . '</a></p>' .
    '</div></div>' .
    '</footer>' .
    '<a id="Up" href="#" aria-label="' . te('footer.toTop') . '" onclick="window.scrollTo({top:0,behavior:\'smooth\'});return false"><img src="' . BASE_URL . '/gfx/arrow-top.svg" alt="' . te('footer.toTop') . '"></a>';
}

function renderInlineJs() {
    return '<script>
(function(){
  // Hash URL redirect (staré záložky #/katalog → /katalog)
  if(window.location.hash && window.location.hash.indexOf("#/")===0){
    window.location.replace(window.location.hash.substring(1));
  }
  // Scroll to top button (passive listener pro lepší scroll perf na mobilu)
  var btn = document.getElementById("Up");
  if(btn){ window.addEventListener("scroll", function(){ btn.classList.toggle("visible", window.scrollY > 400); }, {passive:true}); }
  // Mobilní menu — zamyká body scroll, zavírá na ESC, na klik mimo a po výběru
  var menu = document.getElementById("mobile-menu");
  var toggleBtn = document.querySelector(".nav-toggle");
  function setMenu(open){
    if(!menu) return;
    menu.classList.toggle("open", open);
    document.body.classList.toggle("menu-open", open);
    if(toggleBtn) toggleBtn.setAttribute("aria-expanded", open?"true":"false");
  }
  if(toggleBtn){ toggleBtn.setAttribute("aria-expanded","false"); toggleBtn.setAttribute("aria-controls","mobile-menu"); }
  if(menu){
    // klik na overlay (ne na menu items) zavře
    menu.addEventListener("click", function(e){ if(e.target===menu) setMenu(false); });
    // klik na nepodmenu odkaz zavře menu
    menu.querySelectorAll("a").forEach(function(a){
      if(a.closest(".has-sub")) return;
      a.addEventListener("click", function(){ setMenu(false); });
    });
  }
  document.addEventListener("keydown", function(e){
    if(e.key==="Escape" && menu && menu.classList.contains("open")) setMenu(false);
  });
  // Při resize na desktop zavři mobil menu
  window.addEventListener("resize", function(){
    if(window.innerWidth>768 && menu && menu.classList.contains("open")) setMenu(false);
  }, {passive:true});
  // Language + Currency switcher dropdown toggle (sdílená logika)
  function bindSwitcher(sw, toggleSel, dropSel){
    var toggle = sw.querySelector(toggleSel);
    var dropdown = sw.querySelector(dropSel);
    if(!toggle || !dropdown) return;
    toggle.addEventListener("click", function(e){
      e.stopPropagation();
      var open = sw.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    document.addEventListener("click", function(e){
      if(!sw.contains(e.target)){ sw.classList.remove("open"); toggle.setAttribute("aria-expanded","false"); }
    });
    document.addEventListener("keydown", function(e){
      if(e.key==="Escape" && sw.classList.contains("open")){ sw.classList.remove("open"); toggle.setAttribute("aria-expanded","false"); }
    });
  }
  document.querySelectorAll("[data-lang-switcher]").forEach(function(sw){ bindSwitcher(sw, ".lang-toggle", ".lang-dropdown"); });
  document.querySelectorAll("[data-cur-switcher]").forEach(function(sw){ bindSwitcher(sw, ".cur-toggle", ".cur-dropdown"); });
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
/**
 * Vyrenderuje <link rel="alternate" hreflang="…" href="…"> tagy pro všechny
 * podporované jazyky (cs, en, de, es, fr, nl, pl) + x-default.
 * Pro jazykové varianty používá ?lang=xx parametr.
 *
 * @param string $siteOrigin např. https://motogo24.cz
 * @param string $path aktuální cesta (např. /blog/xy nebo /eshop)
 * @return string HTML <link> tagy
 */
function renderHreflangAlternates($siteOrigin, $path) {
    if (!defined('I18N_SUPPORTED')) return '';
    $out = '';
    foreach (I18N_SUPPORTED as $code) {
        $href = $siteOrigin . $path . ($code === I18N_DEFAULT ? '' : ('?lang=' . $code));
        $out .= "\n  " . '<link rel="alternate" hreflang="' . htmlspecialchars($code) . '" href="' . htmlspecialchars($href) . '">';
    }
    // x-default → CZ verze (default)
    $out .= "\n  " . '<link rel="alternate" hreflang="x-default" href="' . htmlspecialchars($siteOrigin . $path) . '">';
    return $out;
}

/**
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
    // Dynamická base URL podle aktuální domény (motogo24.com nová /
    // motogo24.cz stará) — www se strippuje, schéma dle HTTPS/proxy.
    $host = $_SERVER['HTTP_HOST'] ?? 'motogo24.cz';
    $host = preg_replace('#^www\.#i', '', strtolower($host));
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    $siteOrigin = ($isHttps ? 'https://' : 'http://') . $host;

    $description = $meta['description'] ?? 'Půjčovna motorek Vysočina – silniční, sportovní, enduro i dětské. Nonstop pronájem bez kauce, online rezervace a motorkářská výbava zdarma.';
    $keywords = $meta['keywords'] ?? 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic';
    $canonical = $meta['canonical'] ?? ($siteOrigin . $currentPath);
    $ogImage = $meta['og_image'] ?? ($siteOrigin . '/gfx/hero-banner.jpg');
    $ogType = $meta['og_type'] ?? 'website';
    $robots = $meta['robots'] ?? 'index,follow';
    $extraSchema = $meta['schema'] ?? '';
    $breadcrumbs = $meta['breadcrumbs'] ?? [];
    $preload = $meta['preload'] ?? [];
    // Automatický preload hero banneru na homepage (LCP optimalizace).
    // Preferujeme WebP — moderní prohlížeče (~95 %) ho podpoří, ostatní
    // si stáhnou JPEG fallback z <picture> v home.php.
    if ($currentPath === '/' && empty($preload)) {
        $preload[] = [
            'href' => BASE_URL . '/gfx/hero-banner.webp',
            'as' => 'image',
            'type' => 'image/webp',
            'fetchpriority' => 'high',
        ];
    }

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

    $htmlLang = i18nHtmlLang();
    $ogLocale = i18nOgLocale();
    echo '<!DOCTYPE html>
<html lang="' . htmlspecialchars($htmlLang) . '" dir="ltr" prefix="og: https://ogp.me/ns#">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#1a2e22">
  <meta name="color-scheme" content="light">
  <meta name="format-detection" content="telephone=yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="MotoGo24">
  <meta name="description" content="' . htmlspecialchars($description) . '">
  <meta name="keywords" content="' . htmlspecialchars($keywords) . '">
  <meta name="robots" content="' . htmlspecialchars($robots) . '">
  <meta name="author" content="MotoGo24">
  <meta property="og:url" content="' . htmlspecialchars($canonical) . '">
  <meta property="og:type" content="' . htmlspecialchars($ogType) . '">
  <meta property="og:locale" content="' . htmlspecialchars($ogLocale) . '">
  <meta property="og:title" content="' . htmlspecialchars($title) . '">
  <meta property="og:site_name" content="Půjčovna motorek Vysočina MotoGo24">
  <meta property="og:description" content="' . htmlspecialchars($description) . '">
  <meta property="og:image" content="' . htmlspecialchars($ogImage) . '">
  <meta property="og:image:width" content="1920">
  <meta property="og:image:height" content="1080">
  <meta property="og:image:alt" content="' . htmlspecialchars($title) . '">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="' . htmlspecialchars($title) . '">
  <meta name="twitter:description" content="' . htmlspecialchars($description) . '">
  <meta name="twitter:image" content="' . htmlspecialchars($ogImage) . '">
  <link rel="canonical" href="' . htmlspecialchars($canonical) . '">
  <link rel="icon" type="image/svg+xml" href="' . BASE_URL . '/favicon.svg">
  <link rel="apple-touch-icon" href="' . BASE_URL . '/apple-touch-icon.png">' . renderHreflangAlternates($siteOrigin, $currentPath) . '
  <title>' . htmlspecialchars($title) . '</title>

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": "' . $siteOrigin . '/#organization",
        "name": "MotoGo24",
        "legalName": "Bc. Petra Semorádová",
        "url": "' . $siteOrigin . '",
        "logo": {"@type": "ImageObject", "url": "' . $siteOrigin . '/gfx/logo.svg", "width": 512, "height": 512},
        "image": "' . $siteOrigin . '/gfx/hero-banner.jpg",
        "email": "info@motogo24.cz",
        "telephone": "+420 774 256 271",
        "taxID": "21874263",
        "vatID": "CZ21874263",
        "foundingDate": "2024-07-31",
        "founder": {"@type": "Person", "name": "Bc. Petra Semorádová"},
        "address": {"@type": "PostalAddress","streetAddress": "Mezná 9","addressLocality": "Pelhřimov","postalCode": "393 01","addressRegion": "Vysočina","addressCountry": "CZ"},
        "contactPoint": [
          {"@type": "ContactPoint", "telephone": "+420 774 256 271", "contactType": "customer service", "email": "info@motogo24.cz", "areaServed": ["CZ","SK","AT","DE","PL"], "availableLanguage": ["cs","en","de","pl","sk"], "hoursAvailable": {"@type": "OpeningHoursSpecification", "dayOfWeek": ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"], "opens": "00:00", "closes": "23:59"}},
          {"@type": "ContactPoint", "telephone": "+420 774 256 271", "contactType": "emergency", "email": "info@motogo24.cz", "availableLanguage": ["cs","en"]}
        ],
        "sameAs": ["' . FB_URL . '","' . IG_URL . '"]
      },
      {
        "@type": "WebSite",
        "@id": "' . $siteOrigin . '/#website",
        "url": "' . $siteOrigin . '",
        "name": "MotoGo24 — půjčovna motorek Vysočina",
        "description": "Online rezervace motorek, e-shop, dárkové poukazy. Půjčovna v Pelhřimově, nonstop, bez kauce.",
        "inLanguage": "' . htmlspecialchars($htmlLang) . '",
        "publisher": {"@id": "' . $siteOrigin . '/#organization"},
        "potentialAction": {
          "@type": "SearchAction",
          "target": {"@type": "EntryPoint", "urlTemplate": "' . $siteOrigin . '/katalog?q={search_term_string}"},
          "query-input": "required name=search_term_string"
        }
      },
      {
        "@type": ["LocalBusiness", "AutomotiveBusiness"],
        "@id": "' . $siteOrigin . '/#localbusiness",
        "name": "MotoGo24 — půjčovna motorek Vysočina",
        "alternateName": ["Motogo24 Pelhřimov", "Půjčovna motorek Vysočina"],
        "description": "Půjčovna motorek na Vysočině — silniční, naked, supermoto, enduro i dětské motorky. Bez kauce, výbava v ceně, nonstop provoz.",
        "url": "' . $siteOrigin . '",
        "logo": "' . $siteOrigin . '/gfx/logo.svg",
        "image": ["' . $siteOrigin . '/gfx/hero-banner.jpg", "' . $siteOrigin . '/gfx/logo.svg"],
        "email": "info@motogo24.cz",
        "telephone": "+420 774 256 271",
        "priceRange": "990 – 5000 Kč/den",
        "currenciesAccepted": "CZK, EUR, USD",
        "paymentAccepted": "Cash, Credit Card, Debit Card, Apple Pay, Google Pay",
        "openingHoursSpecification": {"@type": "OpeningHoursSpecification","dayOfWeek": ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens": "00:00","closes": "23:59"},
        "address": {"@type": "PostalAddress","streetAddress": "Mezná 9","addressLocality": "Pelhřimov","postalCode": "393 01","addressRegion": "Vysočina","addressCountry": "CZ"},
        "geo": {"@type": "GeoCoordinates","latitude": 49.4147,"longitude": 15.2953},
        "areaServed": [
          {"@type": "Country", "name": "Česko"},
          {"@type": "AdministrativeArea", "name": "Kraj Vysočina"}
        ],
        "hasOfferCatalog": {
          "@type": "OfferCatalog",
          "name": "Katalog motorek k pronájmu",
          "url": "' . $siteOrigin . '/katalog"
        },
        "parentOrganization": {"@id": "' . $siteOrigin . '/#organization"},
        "sameAs": ["' . FB_URL . '","' . IG_URL . '"]
      }
    ]
  }
  </script>' . $breadcrumbSchema . ($extraSchema ? "\n" . $extraSchema : '') . '

  <!-- Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="preconnect" href="' . SUPABASE_URL . '" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Montserrat:ital,wght@0,300..900;1,300..900&display=swap" rel="stylesheet">';

    foreach ($preload as $p) {
        $attrs = '';
        foreach (['href', 'as', 'type', 'fetchpriority', 'imagesrcset', 'imagesizes', 'media'] as $a) {
            if (!empty($p[$a])) $attrs .= ' ' . $a . '="' . htmlspecialchars($p[$a]) . '"';
        }
        echo '
  <link rel="preload"' . $attrs . '>';
    }

    echo '

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

    // AI booking widget — floating bubble. Skryt na /rezervace a /potvrzeni
    // (tam má uživatel vlastní formulář a nepotřebuje agenta nahoru). Konfig
    // se sype do window.MOTOGO_CONFIG před načtením skriptu.
    $hideAi = ($currentPath === '/rezervace' || $currentPath === '/potvrzeni');
    if (!$hideAi) {
        echo '
<script>
window.MOTOGO_CONFIG = window.MOTOGO_CONFIG || {};
window.MOTOGO_CONFIG.SUPABASE_URL = ' . json_encode(SUPABASE_URL) . ';
window.MOTOGO_CONFIG.SUPABASE_ANON_KEY = ' . json_encode(SUPABASE_ANON_KEY) . ';
</script>
<script src="' . BASE_URL . '/js/ai-widget.js" defer></script>';
    }
    echo '
</body>
</html>';
}
