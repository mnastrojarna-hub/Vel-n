<?php
// ===== MotoGo24 Web PHP — Shared Layout (Header + Footer + SEO) =====

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
require_once __DIR__ . '/i18n_currency.php';

// Menu struktura — labels jsou klíče i18n, route zůstává stejná napříč jazyky.
// `tc()` obalí text spanem `data-cms-key="web.layout.<key>"` jen pro adminy
// (cookie mg_cms_admin) → inline edit přes overlay; běžní uživatelé dostanou plain text.
function getMenuItems() {
    return [
        ['label' => tc('menu.rental'), 'route' => '/pujcovna-motorek'],
        ['label' => tc('menu.catalog'), 'route' => '/katalog'],
        ['label' => tc('menu.howto'), 'route' => '/jak-pujcit', 'children' => [
            ['label' => tc('menu.howto.process'), 'route' => '/jak-pujcit/postup'],
            ['label' => tc('menu.howto.pickup'), 'route' => '/jak-pujcit/prevzeti'],
            ['label' => tc('menu.howto.returnHome'), 'route' => '/jak-pujcit/vraceni-pujcovna'],
            ['label' => tc('menu.howto.returnElsewhere'), 'route' => '/jak-pujcit/vraceni-jinde'],
            ['label' => tc('menu.howto.price'), 'route' => '/jak-pujcit/co-v-cene'],
            ['label' => tc('menu.howto.delivery'), 'route' => '/jak-pujcit/pristaveni'],
            ['label' => tc('menu.howto.documents'), 'route' => '/jak-pujcit/dokumenty'],
            ['label' => tc('menu.howto.faq'), 'route' => '/jak-pujcit/faq'],
        ]],
        ['label' => tc('menu.vouchers'), 'route' => '/poukazy'],
        ['label' => tc('menu.shop'), 'route' => '/eshop'],
        ['label' => tc('menu.blog'), 'route' => '/blog'],
        ['label' => tc('menu.contact'), 'route' => '/kontakt'],
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
        '<ul class="focus"><li><a href="#main-menu">' . tc('header.skip.menu') . '</a></li><li><a href="#content">' . tc('header.skip.content') . '</a></li><li><a href="#footer">' . tc('header.skip.contact') . '</a></li></ul>' .
        '<div class="header-topbar"><div class="container">' .
            '<div class="header-phone"><p><a href="' . PHONE_LINK . '" aria-label="' . te('header.callUs') . '"><img alt="' . te('header.callUs') . '" src="' . BASE_URL . '/gfx/telefon-header.svg" loading="lazy"></a>&nbsp;<a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
            '<div class="header-tools">' .
                '<a class="header-edit-rez" href="' . BASE_URL . '/upravit-rezervaci" aria-label="' . te('menu.editReservation.aria') . '" title="' . te('menu.editReservation') . '">' .
                    '<svg class="header-edit-rez-icon" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/></svg>' .
                '</a>' .
                '<a class="header-cart" href="' . BASE_URL . '/kosik" aria-label="' . te('cart.iconLabel') . '" title="' . te('cart.iconLabel') . '">' .
                    '<svg class="header-cart-icon" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6h15l-1.5 9h-12z"/><circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/><path d="M6 6L4 2H1"/></svg>' .
                    '<span class="header-cart-badge" data-cart-badge hidden aria-live="polite"></span>' .
                '</a>' .
                '<div class="header-lang">' . renderCurrencySwitcher() . renderLanguageSwitcher() . '</div>' .
            '</div>' .
        '</div></div>' .
        '<div class="header"><div class="container dfcs">' .
            '<div class="header-logo"><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="' . te('header.logoAlt') . '" loading="lazy"></a></div>' .
            '<div class="header-menu dfje">' .
                '<button class="nav-toggle" aria-label="' . te('header.menuOpen') . '" aria-expanded="false" aria-controls="mobile-menu" onclick="(function(){var m=document.getElementById(\'mobile-menu\');var open=!m.classList.contains(\'open\');m.classList.toggle(\'open\',open);document.body.classList.toggle(\'menu-open\',open);this.setAttribute(\'aria-expanded\',open?\'true\':\'false\');}).call(this)">' . tc('header.menuToggle') . '</button>' .
                '<nav id="mobile-menu" class="mobile-menu-overlay" aria-label="' . te('header.menuLabel') . '">' .
                    '<button class="mobile-menu-close" aria-label="' . te('header.menuClose') . '" onclick="document.getElementById(\'mobile-menu\').classList.remove(\'open\');document.body.classList.remove(\'menu-open\');var b=document.querySelector(\'.nav-toggle\');if(b)b.setAttribute(\'aria-expanded\',\'false\')">✕</button>' .
                    '<ul id="main-menu" class="main-menu">' . $nav .
                        '<li class="menu-rez"><a class="btn btngreen-small pulse" data-route="/rezervace" href="' . BASE_URL . '/rezervace">' . tc('menu.reservation') . '</a></li>' .
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
    $menuHtml .= '<li><a data-route="/rezervace" href="' . BASE_URL . '/rezervace">' . tc('menu.reservation') . '</a></li>';
    $menuHtml .= '<li><a data-route="/upravit-rezervaci" href="' . BASE_URL . '/upravit-rezervaci">' . tc('menu.editReservation') . '</a></li>';

    return '<footer id="footer"><div class="container"><div class="gr4">' .
        '<div>' .
            '<p><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="Motogo24" loading="lazy"></a></p><p>&nbsp;</p>' .
            '<p>' . tcRaw('footer.aboutText') . '</p>' .
        '</div>' .
        '<div><h3>' . tc('footer.aboutTitle') . '</h3><ul>' . $menuHtml . '</ul></div>' .
        '<div><h3>' . tc('footer.socialTitle') . '</h3>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Facebook" src="' . BASE_URL . '/gfx/facebook-footer.svg"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Instagram" src="' . BASE_URL . '/gfx/instagram-footer.svg"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p>' .
        '</div>' .
        '<div class="footer-contact"><h3>' . tc('footer.helpTitle') . '</h3>' .
            '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/telefon.svg" alt="' . te('footer.iconPhone') . '" class="icon-small" loading="lazy"></div><div><p>' . tc('footer.callUs') . '<br><strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/email.svg" alt="' . te('footer.iconEmail') . '" class="icon-small" loading="lazy"></div><div><p>' . EMAIL_USER . '@' . EMAIL_DOMAIN . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/adresa.svg" alt="' . te('footer.iconAddress') . '" class="icon-small" loading="lazy"></div><div><p><strong>' . tc('footer.companyLine1') . '</strong><br>' . ADDRESS . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/provozni-doba.svg" alt="' . te('footer.openHoursIcon') . '" class="icon-small" loading="lazy"></div><div><p>' . tc('footer.openHours') . '</p></div></div>' .
        '</div>' .
    '</div></div>' .
    '<div class="copyright"><div class="container">' .
        '<p>' . tc('footer.copyright') . '</p>' .
        '<p><a href="' . BASE_URL . '/mapa-stranek">' . tc('footer.sitemap') . '</a><a href="#">' . tc('footer.cookies') . '</a><a href="' . BASE_URL . '/gdpr">' . tc('footer.gdpr') . '</a><a href="' . BASE_URL . '/obchodni-podminky">' . tc('footer.terms') . '</a><a href="' . BASE_URL . '/smlouva">' . tc('footer.contract') . '</a></p>' .
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
 * Postaví pole "sameAs" URLs pro LocalBusiness JSON-LD. Kromě fixních
 * profilů (FB, IG, vlastní domény) připojí Seznam-ekosystém kartám, pokud
 * jsou nakonfigurované v env (SAMEAS_FIRMY_CZ, SAMEAS_MAPY_CZ, SAMEAS_HEUREKA,
 * SAMEAS_ZBOZI). NAP konzistence mezi webem a těmito katalogy je klíčová pro
 * lokální SEO v Seznam.cz.
 */
function buildSameAs() {
    $list = [FB_URL, IG_URL, 'https://motogo24.cz', 'https://motogo24.com'];
    $extras = [
        defined('SAMEAS_FIRMY_CZ') ? SAMEAS_FIRMY_CZ : '',
        defined('SAMEAS_MAPY_CZ')  ? SAMEAS_MAPY_CZ  : '',
        defined('SAMEAS_HEUREKA')  ? SAMEAS_HEUREKA  : '',
        defined('SAMEAS_ZBOZI')    ? SAMEAS_ZBOZI    : '',
    ];
    foreach ($extras as $u) {
        if (is_string($u) && $u !== '') $list[] = $u;
    }
    return $list;
}

/**
 * Sklik retargeting tag (Seznam reklamní systém). Emituje se jen pokud
 * je SKLIK_RETARGETING_ID nastaveno přes env. Pro Seznam ekvivalent
 * Google Ads remarketingu — bez kódu uživatele Sklik nenavidíme.
 *
 * Conversion tracking (rezervace, objednávka) se řeší zvlášť na confirmation
 * stránkách — tady jen univerzální retargeting na všech stránkách.
 */
function renderSklikRetargeting() {
    $id = defined('SKLIK_RETARGETING_ID') ? SKLIK_RETARGETING_ID : '';
    if ($id === '' || !ctype_digit((string)$id)) return '';
    $idEsc = htmlspecialchars((string)$id, ENT_QUOTES, 'UTF-8');
    return '
<!-- Sklik retargeting (Seznam.cz) -->
<script>
  var seznam_retargeting_id = ' . $idEsc . ';
</script>
<script async src="https://c.imedia.cz/js/retargeting.js"></script>';
}

/**
 * Webmaster Tools verifikační meta tagy. Emitují se jen ty, které mají
 * neprázdnou hodnotu v env / config — žádné prázdné <meta> v HTML.
 *
 * Hodnoty se konfigurují přes env vars (viz config.php):
 *   MOTOGO_VERIFY_GOOGLE / BING / SEZNAM / YANDEX / PINTEREST / FACEBOOK
 */
function renderWebmasterVerification() {
    $tags = [
        ['google-site-verification', defined('VERIFY_GOOGLE')    ? VERIFY_GOOGLE    : ''],
        ['msvalidate.01',            defined('VERIFY_BING')      ? VERIFY_BING      : ''],
        ['seznam-wmt',               defined('VERIFY_SEZNAM')    ? VERIFY_SEZNAM    : ''],
        ['yandex-verification',      defined('VERIFY_YANDEX')    ? VERIFY_YANDEX    : ''],
        ['p:domain_verify',          defined('VERIFY_PINTEREST') ? VERIFY_PINTEREST : ''],
        ['facebook-domain-verification', defined('VERIFY_FACEBOOK') ? VERIFY_FACEBOOK : ''],
    ];
    $out = '';
    foreach ($tags as [$name, $content]) {
        if ($content === '' || $content === null) continue;
        $out .= "\n  " . '<meta name="' . htmlspecialchars($name) . '" content="' . htmlspecialchars((string)$content) . '">';
    }
    return $out;
}

/**
 * Vyrenderuje <link rel="alternate" hreflang="…" href="…"> tagy pro všechny
 * podporované jazyky (cs, en, de, es, fr, nl, pl) + x-default.
 *
 * Cross-domain mapping (Google-friendly):
 *   hreflang="cs" → https://motogo24.cz{path}
 *   hreflang="en" → https://motogo24.com{path}
 *   hreflang="de|es|fr|nl|pl" → https://motogo24.com{path}?lang=xx
 *   hreflang="x-default" → https://motogo24.com{path}
 *
 * Reciproční hreflang mezi doménami je nutný — Google jinak hreflang ignoruje.
 *
 * @param string $path aktuální cesta (např. /blog/xy nebo /eshop)
 * @return string HTML <link> tagy
 */
function renderHreflangAlternates($path) {
    if (!defined('I18N_SUPPORTED')) return '';
    $out = '';
    foreach (I18N_SUPPORTED as $code) {
        $href = i18nUrlForLang($code, $path);
        $out .= "\n  " . '<link rel="alternate" hreflang="' . htmlspecialchars($code) . '" href="' . htmlspecialchars($href) . '">';
    }
    // x-default → mezinárodní (EN) verze na .com
    $out .= "\n  " . '<link rel="alternate" hreflang="x-default" href="' . htmlspecialchars(i18nUrlForLang('en', $path)) . '">';
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
    $keywords = $meta['keywords'] ?? 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle rental Prague, půjčovna motorek Praha';
    // Canonical = doménová home pro aktuální jazyk (cs → .cz, ostatní → .com).
    // Tím Google indexuje českou verzi výhradně z motogo24.cz a anglickou/další
    // z motogo24.com — žádný duplicate-content stejného jazyka přes obě domény.
    $canonical = $meta['canonical'] ?? siteCanonicalUrl($currentPath);
    $ogImage = $meta['og_image'] ?? ($siteOrigin . '/gfx/hero-banner.jpg');
    $ogType = $meta['og_type'] ?? 'website';
    // Default robots — povolíme rich snippets (velké náhledy obrázků a plný text v
    // SERP). max-image-preview:large je doporučeno Googlem pro Discover.
    $robots = $meta['robots'] ?? 'index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1';
    $extraSchema = $meta['schema'] ?? '';
    $breadcrumbs = $meta['breadcrumbs'] ?? [];
    $preload = $meta['preload'] ?? [];
    // AggregateRating injekce — pokud caller předá ['rating' => 4.9, 'count' => 42],
    // přidá se do LocalBusiness JSON-LD jako rich-snippet hvězdičky v SERP.
    $aggregateRating = $meta['aggregate_rating'] ?? null;
    // Speakable — voice asistenti (Google Assistant, Alexa, Siri) si přečtou
    // nahlas obsah z těchto CSS selektorů. Defaultně H1 + .home-intro.
    $speakableSelectors = $meta['speakable'] ?? null;
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

    // Speakable schema — když caller pošle CSS selektory, vygenerujeme samostatný
    // SpeakableSpecification blok. WebPage @id navazuje na canonical, takže voice
    // asistent ví, že selektory patří k této stránce.
    $speakableSchema = '';
    if (!empty($speakableSelectors) && is_array($speakableSelectors)) {
        $sel = json_encode(array_values($speakableSelectors), JSON_UNESCAPED_UNICODE);
        $speakableSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"WebPage","@id":' . json_encode($canonical, JSON_UNESCAPED_UNICODE) . ',"speakable":{"@type":"SpeakableSpecification","cssSelector":' . $sel . '}}
  </script>';
    }

    // AggregateRating fragment — injektuje se do LocalBusiness JSON-LD níže.
    $aggregateRatingFragment = '';
    if (is_array($aggregateRating) && !empty($aggregateRating['count']) && !empty($aggregateRating['rating'])) {
        $r = max(1, min(5, (float)$aggregateRating['rating']));
        $c = max(1, (int)$aggregateRating['count']);
        $aggregateRatingFragment = ',"aggregateRating":{"@type":"AggregateRating","ratingValue":"' . number_format($r, 1, '.', '') . '","reviewCount":' . $c . ',"bestRating":"5","worstRating":"1"}';
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
  <link rel="apple-touch-icon" href="' . BASE_URL . '/apple-touch-icon.png">
  <link rel="manifest" href="' . BASE_URL . '/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="MotoGo24 — Blog a tipy na trasy" href="' . $siteOrigin . '/feed.xml">
  <link rel="search" type="application/opensearchdescription+xml" title="MotoGo24" href="' . $siteOrigin . '/opensearch.xml">
  <link rel="alternate" type="application/json" title="MotoGo24 — AI Agent Manifest" href="' . $siteOrigin . '/.well-known/agent.json">
  <link rel="alternate" type="application/json" title="MotoGo24 — ChatGPT Plugin Manifest" href="' . $siteOrigin . '/.well-known/ai-plugin.json">
  <link rel="alternate" type="text/markdown" title="MotoGo24 — LLM Index" href="' . $siteOrigin . '/llms.txt">
  <meta name="application-name" content="MotoGo24">
  <meta name="geo.region" content="CZ-VY">
  <meta name="geo.placename" content="Pelhřimov, Vysočina, Česko">
  <meta name="geo.position" content="49.4147;15.2953">
  <meta name="ICBM" content="49.4147, 15.2953">
  <meta name="rating" content="general">
  <meta name="distribution" content="global">
  <meta name="revisit-after" content="3 days">
  <meta name="referrer" content="strict-origin-when-cross-origin">
' . renderWebmasterVerification() . renderHreflangAlternates($currentPath) . '
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
        "alternateName": ["Motogo24 Pelhřimov", "Půjčovna motorek Vysočina", "MotoGo24 motorcycle rental"],
        "description": "Půjčovna motorek na Vysočině — silniční, naked, supermoto, enduro i dětské motorky. Bez kauce, výbava v ceně, nonstop provoz.",
        "slogan": "Půjč si motorku bez kauce. Nonstop. Online.",
        "url": "' . $siteOrigin . '",
        "logo": "' . $siteOrigin . '/gfx/logo.svg",
        "image": ["' . $siteOrigin . '/gfx/hero-banner.jpg", "' . $siteOrigin . '/gfx/logo.svg"],
        "email": "info@motogo24.cz",
        "telephone": "+420 774 256 271",
        "priceRange": "990 – 5000 Kč/den",
        "currenciesAccepted": "CZK, EUR, USD",
        "paymentAccepted": "Cash, Credit Card, Debit Card, Apple Pay, Google Pay",
        "knowsLanguage": ["cs","en","de","es","fr","nl","pl"],
        "keywords": "půjčovna motorek, pronájem motorek, motorbike rental, motorcycle rental, Czech Republic, Vysočina, Pelhřimov, bez kauce, nonstop, enduro, supermoto, naked, sportovní, cestovní, A2 řidičák, A1 řidičák",
        "openingHoursSpecification": {"@type": "OpeningHoursSpecification","dayOfWeek": ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens": "00:00","closes": "23:59"},
        "address": {"@type": "PostalAddress","streetAddress": "Mezná 9","addressLocality": "Pelhřimov","postalCode": "393 01","addressRegion": "Vysočina","addressCountry": "CZ"},
        "geo": {"@type": "GeoCoordinates","latitude": 49.4147,"longitude": 15.2953},
        "hasMap": "https://mapy.cz/zakladni?q=Mezn%C3%A1%209%20Pelh%C5%99imov",
        "areaServed": [
          {"@type": "Country", "name": "Česko"},
          {"@type": "AdministrativeArea", "name": "Kraj Vysočina"},
          {"@type": "Country", "name": "Slovensko"},
          {"@type": "Country", "name": "Rakousko"},
          {"@type": "Country", "name": "Německo"},
          {"@type": "Country", "name": "Polsko"}
        ],
        "hasOfferCatalog": {
          "@type": "OfferCatalog",
          "name": "Katalog motorek k pronájmu",
          "url": "' . $siteOrigin . '/katalog",
          "itemListElement": [
            {"@type": "OfferCatalog", "name": "Cestovní motorky", "url": "' . $siteOrigin . '/katalog/cestovni"},
            {"@type": "OfferCatalog", "name": "Naked motorky", "url": "' . $siteOrigin . '/katalog/naked"},
            {"@type": "OfferCatalog", "name": "Supermoto", "url": "' . $siteOrigin . '/katalog/supermoto"},
            {"@type": "OfferCatalog", "name": "Dětské motorky", "url": "' . $siteOrigin . '/katalog/detske"}
          ]
        },
        "potentialAction": [
          {"@type": "ReserveAction", "target": {"@type": "EntryPoint", "urlTemplate": "' . $siteOrigin . '/rezervace?moto={moto_id}&start={start_date}&end={end_date}", "actionPlatform": ["http://schema.org/DesktopWebPlatform","http://schema.org/MobileWebPlatform","http://schema.org/IOSPlatform","http://schema.org/AndroidPlatform"]}, "result": {"@type": "Reservation", "name": "Rezervace motorky"}},
          {"@type": "OrderAction", "target": "' . $siteOrigin . '/eshop", "name": "Nákup výbavy a poukazů"}
        ],
        "parentOrganization": {"@id": "' . $siteOrigin . '/#organization"},
        "sameAs": ' . json_encode(buildSameAs(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . $aggregateRatingFragment . '
      },
      {
        "@type": "Service",
        "@id": "' . $siteOrigin . '/#service-rental",
        "serviceType": "Pronájem motocyklů (motorcycle rental)",
        "name": "Půjčovna motorek MotoGo24",
        "description": "Krátkodobý i dlouhodobý pronájem motocyklů v Česku. Cestovní, naked, supermoto, enduro, sportovní i dětské motorky. Bez kauce, motorkářská výbava v ceně, online rezervace s platbou kartou, nonstop dostupnost převzetí. Možnost přistavení mimo pobočku, sjezd do EU povolen, zelená karta v ceně.",
        "provider": {"@id": "' . $siteOrigin . '/#localbusiness"},
        "areaServed": [{"@type": "Country", "name": "Česko"},{"@type": "Country", "name": "Slovensko"},{"@type": "Country", "name": "Rakousko"},{"@type": "Country", "name": "Německo"},{"@type": "Country", "name": "Polsko"}],
        "audience": {"@type": "PeopleAudience", "audienceType": "Motorkáři, turisté, firmy, dárky pro blízké"},
        "availableChannel": [
          {"@type": "ServiceChannel", "serviceUrl": "' . $siteOrigin . '/rezervace", "name": "Online rezervační formulář"},
          {"@type": "ServiceChannel", "serviceUrl": "https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api", "name": "Veřejné REST API pro AI agenty a partnery"},
          {"@type": "ServiceChannel", "serviceUrl": "https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server", "name": "MCP server (Model Context Protocol) pro Claude Desktop, Cursor, Cline"},
          {"@type": "ServiceChannel", "servicePhone": "+420 774 256 271", "name": "Telefon (24/7)"},
          {"@type": "ServiceChannel", "serviceUrl": "https://wa.me/420774256271", "name": "WhatsApp"}
        ],
        "termsOfService": "' . $siteOrigin . '/obchodni-podminky",
        "offers": {
          "@type": "AggregateOffer",
          "priceCurrency": "CZK",
          "lowPrice": "990",
          "highPrice": "5000",
          "offerCount": 50,
          "availability": "https://schema.org/InStock",
          "seller": {"@id": "' . $siteOrigin . '/#localbusiness"}
        }
      }
    ]
  }
  </script>' . $breadcrumbSchema . $speakableSchema . ($extraSchema ? "\n" . $extraSchema : '') . '

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
  <link rel="stylesheet" href="' . assetUrl('/css/main.css') . '">
  <link rel="stylesheet" href="' . assetUrl('/css/pages.css') . '">
</head>
<body' . ($currentPath === '/' ? ' class="homepage"' : '') . '>
';
    echo renderHeader($currentPath);
    echo '<div id="app">';
    echo $content;
    echo '</div>';
    echo renderFooter();

    // Lightbox container (sdílený pro všechny galerie přes [data-gallery]).
    $lbPrev    = htmlspecialchars(t('gallery.prev'), ENT_QUOTES, 'UTF-8');
    $lbNext    = htmlspecialchars(t('gallery.next'), ENT_QUOTES, 'UTF-8');
    $lbClose   = htmlspecialchars(t('gallery.close'), ENT_QUOTES, 'UTF-8');
    $lbCounter = htmlspecialchars(t('gallery.counter'), ENT_QUOTES, 'UTF-8');
    echo '
<div id="mg-lightbox" class="mg-lb" role="dialog" aria-modal="true" aria-label="' . $lbClose . '" data-counter-tpl="' . $lbCounter . '" hidden>
  <button type="button" class="mg-lb-close" aria-label="' . $lbClose . '">&times;</button>
  <button type="button" class="mg-lb-prev" aria-label="' . $lbPrev . '">&#10094;</button>
  <div class="mg-lb-stage"><img class="mg-lb-img" alt=""></div>
  <button type="button" class="mg-lb-next" aria-label="' . $lbNext . '">&#10095;</button>
  <div class="mg-lb-counter" aria-live="polite"></div>
</div>
<script src="' . assetUrl('/js/lightbox.js') . '" defer></script>';

    // E-shop košík (lokální storage, sdílený mezi stránkami)
    $cartI18n = json_encode([
        'cart_added'  => t('cart.added'),
        'cart_url'    => BASE_URL . '/kosik',
        'cart_size'   => t('cart.size'),
        'cart_pcs'    => t('cart.pcs'),
        'cart_qty'    => t('cart.qty'),
        'cart_remove' => t('cart.remove'),
    ], JSON_UNESCAPED_UNICODE);
    echo '
<script>
window.MG_I18N = Object.assign(window.MG_I18N || {}, ' . $cartI18n . ');
</script>
<script src="' . assetUrl('/js/cart.js') . '" defer></script>';

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
<script src="' . assetUrl('/js/ai-widget.js') . '" defer></script>';
    }
    // CMS admin highlight overlay — JS se načte JEN když je nastavena cookie
    // `mg_cms_admin=1` (po úspěšném ověření tokenu z Velínu). Běžný návštěvník
    // overlay nikdy neuvidí. `?cms_highlight=<klíč>` v URL otevře cílový text.
    if (!empty($_COOKIE['mg_cms_admin'])) {
        $highlight = isset($_GET['cms_highlight']) ? (string)$_GET['cms_highlight'] : '';
        // Token re-fetchneme server-side z app_settings — admin už ho jednou
        // ověřil cookie; expozice ho do JS u admina neleakuje (každý kdo dorazí
        // sem už cookie má). Bez tokenu inline-edit nepůjde uložit.
        $cmsToken = '';
        try {
            $cmsSb = isset($sb) && $sb instanceof SupabaseClient ? $sb : new SupabaseClient();
            $tk = $cmsSb->fetchSetting('cms_admin_token');
            if (is_string($tk)) $cmsToken = $tk;
        } catch (\Throwable $e) { /* token zůstane prázdný — overlay info-only */ }
        $cmsCfg = json_encode([
            'highlight' => $highlight,
            'token' => $cmsToken,
            'apiUrl' => SUPABASE_URL . '/functions/v1/cms-save',
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        echo '
<script>window.MG_CMS_ADMIN = ' . $cmsCfg . ';</script>
<link rel="stylesheet" href="' . BASE_URL . '/css/cms-admin.css">
<script src="' . BASE_URL . '/js/cms-admin.js" defer></script>';
    }

    echo renderSklikRetargeting();

    echo '
</body>
</html>';
}
