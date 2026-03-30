<?php
// ===== MotoGo24 Web PHP — Layout (Header + Footer) =====

$menuItems = [
    ['label'=>'Půjčovna motorek', 'route'=>'/pujcovna-motorek'],
    ['label'=>'Katalog motorek', 'route'=>'/katalog', 'children'=>[
        ['label'=>'Cestovní motorky', 'route'=>'/katalog/cestovni'],
        ['label'=>'Dětské motorky', 'route'=>'/katalog/detske']
    ]],
    ['label'=>'Jak si půjčit motorku', 'route'=>'/jak-pujcit', 'children'=>[
        ['label'=>'Postup půjčení', 'route'=>'/jak-pujcit/postup'],
        ['label'=>'Přistavení motocyklu', 'route'=>'/jak-pujcit/pristaveni'],
        ['label'=>'Vyzvednutí motocyklu', 'route'=>'/jak-pujcit/vyzvednuti'],
        ['label'=>'Co je v ceně', 'route'=>'/jak-pujcit/co-v-cene'],
        ['label'=>'Dokumenty a návody', 'route'=>'/jak-pujcit/dokumenty'],
        ['label'=>'Často kladené dotazy', 'route'=>'/jak-pujcit/faq']
    ]],
    ['label'=>'Poukazy', 'route'=>'/poukazy'],
    ['label'=>'Blog', 'route'=>'/blog'],
    ['label'=>'Kontakt', 'route'=>'/kontakt']
];

function renderHeader() {
    global $menuItems;
    $nav = '';
    foreach ($menuItems as $item) {
        $hasSub = !empty($item['children']);
        $arrow = $hasSub ? ' <img src="gfx/arrow-down.svg" alt="" loading="lazy" class="menu-arrow">' : '';
        $nav .= '<li' . ($hasSub ? ' class="has-sub"' : '') . '>';
        $nav .= '<a href="' . $item['route'] . '">' . $item['label'] . $arrow . '</a>';
        if ($hasSub) {
            $nav .= '<ul class="submenu bs">';
            foreach ($item['children'] as $ch) {
                $nav .= '<li><a href="' . $ch['route'] . '">' . $ch['label'] . '</a></li>';
            }
            $nav .= '</ul>';
        }
        $nav .= '</li>';
    }

    return '<header>' .
        '<ul class="focus"><li><a href="#main-menu">PŘEJDI NA HLAVNÍ MENU</a></li><li><a href="#content">PŘEJDI NA OBSAH</a></li><li><a href="#footer">PŘEJDI NA KONTAKT</a></li></ul>' .
        '<div class="header"><div class="container dfcs">' .
            '<div class="header-logo"><a href="/" aria-label="Motogo24"><img src="' . LOGO_SVG . '" alt="Půjčovna motorek Vysočina Motogo24" loading="lazy"></a></div>' .
            '<div class="header-phone"><p><a href="' . PHONE_LINK . '" aria-label="Zavolejte nám"><img alt="Zavolejte" src="gfx/telefon-header.svg" loading="lazy"></a>&nbsp;<a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
            '<div class="header-menu dfje">' .
                '<button class="nav-toggle" aria-label="Menu" onclick="MG.toggleMobile()">MENU ☰</button>' .
                '<nav id="mobile-menu" class="mobile-menu-overlay">' .
                    '<button class="mobile-menu-close" aria-label="Zavřít" onclick="MG.toggleMobile()">✕</button>' .
                    '<ul id="main-menu" class="main-menu df">' . $nav .
                        '<li class="menu-rez"><a class="btn btngreen-small pulse" href="/rezervace">REZERVACE</a></li>' .
                    '</ul>' .
                '</nav>' .
            '</div>' .
        '</div></div>' .
    '</header>';
}

function renderFooter() {
    global $menuItems;
    $menuHtml = '';
    foreach ($menuItems as $item) {
        $menuHtml .= '<li><a href="' . $item['route'] . '">' . $item['label'] . '</a></li>';
    }
    $menuHtml .= '<li><a href="/rezervace">REZERVACE</a></li>';

    return '<footer id="footer"><div class="container"><div class="gr4">' .
        '<div>' .
            '<p><a href="/" aria-label="Motogo24"><img src="' . LOGO_SVG . '" alt="Motogo24" loading="lazy"></a></p><p>&nbsp;</p>' .
            '<p>Vítejte u Motogo24, vaší <strong>půjčovny motorek v Pelhřimově</strong>! Nabízíme <strong>pronájem motorek</strong> pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.</p>' .
        '</div>' .
        '<div><h3>Půjčovna motorek</h3><ul>' . $menuHtml . '</ul></div>' .
        '<div><h3>Půjčovna motorek na sítích</h3>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Facebook" src="gfx/facebook.svg"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Instagram" src="gfx/instagram.svg"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p>' .
        '</div>' .
        '<div class="footer-contact"><h3>Potřebujete poradit?</h3>' .
            '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="gfx/telefon.svg" alt="Telefon" class="icon-small" loading="lazy"></div><div><p>ZAVOLEJTE NÁM<br><strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/email.svg" alt="E-mail" class="icon-small" loading="lazy"></div><div><p>' . EMAIL_USER . '@' . EMAIL_DOMAIN . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/adresa.svg" alt="Adresa" class="icon-small" loading="lazy"></div><div><p><strong>Půjčovna motorek Motogo24</strong><br>' . ADDRESS . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/provozni-doba.svg" alt="Provozní doba" class="icon-small" loading="lazy"></div><div><p><strong>PO - NE</strong> 00:00 – 24:00&nbsp;(nonstop)</p></div></div>' .
        '</div>' .
    '</div></div>' .
    '<div class="copyright"><div class="container">' .
        '<p>© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena</p>' .
        '<p><a href="/mapa-stranek">Mapa stránek</a><a href="#">Cookies</a><a href="/gdpr">GDPR</a><a href="/obchodni-podminky">Obchodní podmínky</a><a href="/smlouva">Smlouva o pronájmu</a></p>' .
    '</div></div>' .
    '</footer>' .
    '<a id="Up" href="#" aria-label="NAHORU" onclick="window.scrollTo({top:0,behavior:\'smooth\'});return false"><img src="gfx/arrow-top.svg" alt="NAHORU"></a>';
}

function renderHead($title, $description = '', $canonical = '', $ogImage = '') {
    $defaultDesc = 'Půjčovna motorek Vysočina – silniční, sportovní, enduro i dětské. Nonstop pronájem bez kauce, online rezervace a motorkářská výbava zdarma.';
    $desc = $description ?: $defaultDesc;
    $canon = $canonical ?: SITE_URL . $_SERVER['REQUEST_URI'];
    $ogImg = $ogImage ?: SITE_URL . '/gfx/logo.svg';

    return '<!DOCTYPE html>
<html lang="cs" dir="ltr" prefix="og: https://ogp.me/ns#">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="' . e($desc) . '">
  <meta name="robots" content="index,follow">
  <meta name="author" content="MotoGo24">
  <meta property="og:url" content="' . e($canon) . '">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="cs_CZ">
  <meta property="og:title" content="' . e($title) . '">
  <meta property="og:site_name" content="Půjčovna motorek Vysočina">
  <meta property="og:description" content="' . e($desc) . '">
  <meta property="og:image" content="' . e($ogImg) . '">
  <link rel="canonical" href="' . e($canon) . '">
  <link rel="icon" type="image/svg+xml" href="favicon.svg">
  <link rel="apple-touch-icon" href="apple-touch-icon.png">
  <title>' . e($title) . '</title>

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    "name": "Motogo24 – půjčovna motorek Vysočina",
    "url": "https://motogo24.cz",
    "logo": "https://motogo24.cz/gfx/logo.svg",
    "image": "https://motogo24.cz/gfx/logo.svg",
    "email": "info@motogo24.cz",
    "telephone": "+420 774 256 271",
    "address": {
      "@type": "PostalAddress",
      "streetAddress": "Mezná 9",
      "addressLocality": "Pelhřimov",
      "postalCode": "393 01",
      "addressCountry": "CZ"
    }
  }
  </script>

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Jost:ital,wght@0,100..900;1,100..900&family=Montserrat:wght@600;800&display=swap" rel="stylesheet">

  <link rel="stylesheet" href="/css/main.css">
  <link rel="stylesheet" href="/css/pages.css">

  <script>
  // Hash URL redirect (old SPA links)
  if(window.location.hash && window.location.hash.indexOf("#/")===0){
    window.location.replace(window.location.hash.substring(1));
  }
  </script>
</head>
<body>
';
}

function renderPageEnd($needsSupabase = false) {
    $js = '';
    if ($needsSupabase) {
        $js .= '<script src="/js/supabase-sdk.js"></script>
<script>
  window.MOTOGO_CONFIG = {
    SUPABASE_URL: \'' . SUPABASE_URL . '\',
    SUPABASE_ANON_KEY: \'' . SUPABASE_ANON_KEY . '\'
  };
</script>
<script src="/js/supabase-init.js"></script>
<script src="/js/api.js"></script>
<script src="/js/components.js"></script>
';
    }
    $js .= '<script>
var MG = window.MG || {};
window.MG = MG;
MG.toggleMobile = function(){
  var m = document.getElementById("mobile-menu");
  if(m) m.classList.toggle("open");
};
MG.initScrollTop = function(){
  var btn = document.getElementById("Up");
  if(!btn) return;
  window.addEventListener("scroll", function(){
    btn.classList.toggle("visible", window.scrollY > 400);
  });
};
MG.initSubmenus = function(){
  document.querySelectorAll(".has-sub > a").forEach(function(a){
    a.addEventListener("click", function(e){
      if(window.innerWidth <= 768){
        var li = a.parentElement;
        var wasOpen = li.classList.contains("show");
        document.querySelectorAll(".has-sub").forEach(function(el){ el.classList.remove("show"); });
        if(!wasOpen){
          e.preventDefault();
          li.classList.add("show");
        }
      }
    });
  });
};
MG.initScrollTop();
MG.initSubmenus();
</script>
</body>
</html>';
    return $js;
}
