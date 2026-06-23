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
        // "Vyber si stroj" = katalog. Menu-popisek `menu.catalogShort` je oddělený
        // od `menu.catalog`, který slouží jako H1/<title> stránky /katalog —
        // přejmenování položky v menu tak nezasáhne SEO katalogu.
        ['label' => tc('menu.catalogShort'), 'route' => '/katalog', 'highlight' => true],
        // Rozcestník (dříve "Jak si půjčit motorku", nyní obecná "Navigace") —
        // neklikací rodič; sdružuje how-to podstránky + Půjčovnu motorek + E-shop.
        // `no_link => true`: mobil tap rozbalí podmenu, desktop hover ukáže submenu.
        ['label' => tc('menu.howto'), 'no_link' => true, 'children' => [
            ['label' => tc('menu.howto.process'), 'route' => '/jak-pujcit/postup'],
            ['label' => tc('menu.howto.pickup'), 'route' => '/jak-pujcit/prevzeti'],
            ['label' => tc('menu.howto.returnHome'), 'route' => '/jak-pujcit/vraceni-pujcovna'],
            ['label' => tc('menu.howto.returnElsewhere'), 'route' => '/jak-pujcit/vraceni-jinde'],
            ['label' => tc('menu.howto.price'), 'route' => '/jak-pujcit/co-v-cene'],
            ['label' => tc('menu.howto.delivery'), 'route' => '/jak-pujcit/pristaveni'],
            ['label' => tc('menu.howto.documents'), 'route' => '/jak-pujcit/dokumenty'],
            ['label' => tc('menu.howto.faq'), 'route' => '/jak-pujcit/faq'],
            ['label' => tc('menu.rental'), 'route' => '/pujcovna-motorek'],
        ]],
        ['label' => tc('menu.vouchers'), 'route' => '/poukazy', 'highlight' => true],
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
        $noLink = !empty($item['no_link']);
        $arrow = $hasSub ? ' <img src="' . BASE_URL . '/gfx/arrow-down.svg" alt="" aria-hidden="true" loading="lazy" class="menu-arrow" width="12" height="12">' : '';
        $route = $item['route'] ?? '';
        $isActive = !$noLink && $route !== '' && $currentPath !== '/' && strpos($currentPath, $route) === 0;
        $nav .= '<li' . ($hasSub ? ' class="has-sub"' : '') . '>';
        if ($noLink) {
            // Rozcestník: <a href="#"> ať CSS hover a stávající mobile expand JS
            // (`.has-sub > a` selektor) fungují beze změny. onclick zabrání
            // navigaci na desktopu — na mobilu existující JS preventDefault dělá toggle.
            $nav .= '<a class="menu-section" href="#" onclick="event.preventDefault();return false;" aria-haspopup="true">' . $item['label'] . $arrow . '</a>';
        } else {
            // Zvýrazněné položky (highlight => true): brand zelená + tučně přes .menu-highlight.
            $linkCls = [];
            if ($isActive) $linkCls[] = 'active';
            if (!empty($item['highlight'])) $linkCls[] = 'menu-highlight';
            $clsAttr = $linkCls ? ' class="' . implode(' ', $linkCls) . '"' : '';
            $nav .= '<a' . $clsAttr . ' data-route="' . $route . '" href="' . BASE_URL . $route . '">' . $item['label'] . $arrow . '</a>';
        }
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
            '<div class="header-phone"><p><a href="' . PHONE_LINK . '" aria-label="' . te('header.callUs') . '"><img alt="' . te('footer.iconPhone') . '" src="' . BASE_URL . '/gfx/telefon-header.svg" loading="lazy" width="24" height="24"></a>&nbsp;<a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
            '<div class="header-tools">' .
                '<div class="header-auth" data-mg-auth hidden>' .
                    '<svg class="header-auth-icon" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>' .
                    '<span class="header-auth-email" data-mg-auth-email></span>' .
                    '<button type="button" class="header-auth-logout" data-mg-auth-logout>' . te('menu.logout') . '</button>' .
                '</div>' .
                '<a class="header-edit-rez" href="' . BASE_URL . '/upravit-rezervaci" aria-label="' . te('menu.editReservation.aria') . '" title="' . te('menu.editReservation') . '">' .
                    '<svg class="header-edit-rez-icon" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/></svg>' .
                    '<span class="header-edit-rez-label">' . te('menu.editReservation') . '</span>' .
                '</a>' .
                '<a class="header-cart" href="' . BASE_URL . '/kosik" aria-label="' . te('cart.iconLabel') . '" title="' . te('cart.iconLabel') . '">' .
                    '<svg class="header-cart-icon" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6h15l-1.5 9h-12z"/><circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/><path d="M6 6L4 2H1"/></svg>' .
                    '<span class="header-cart-badge" data-cart-badge hidden aria-live="polite"></span>' .
                '</a>' .
                '<div class="header-app" data-mg-app>' .
                    '<button type="button" class="header-app-btn" data-mg-app-toggle aria-expanded="false" aria-haspopup="dialog" aria-label="' . te('header.app.aria') . '" title="' . te('header.app.title') . '">' .
                        '<svg class="header-app-icon" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 11 5 4 5-4"/><path d="M5 21h14"/></svg>' .
                        '<span class="header-app-label">' . te('header.app.label') . '</span>' .
                    '</button>' .
                    '<div class="header-app-pop" data-mg-app-pop hidden role="dialog" aria-label="' . te('header.app.title') . '">' .
                        '<button type="button" class="header-app-close" data-mg-app-close aria-label="' . te('header.menuClose') . '">✕</button>' .
                        '<h3 class="header-app-h">' . tc('header.app.heading') . '</h3>' .
                        '<div class="header-app-body">' .
                            '<img class="header-app-qr" src="' . BASE_URL . '/gfx/qr-google-play.svg" alt="' . te('header.app.qrAlt') . '" width="120" height="120" loading="lazy">' .
                            '<div class="header-app-col">' .
                                '<a class="header-app-cta" href="' . PLAY_STORE_URL . '" target="_blank" rel="noopener">' . tc('header.app.getPlay') . '</a>' .
                                '<p class="header-app-note">' . t('header.app.whitelist', ['email' => '<a href="mailto:' . EMAIL_FULL . '">' . EMAIL_FULL . '</a>']) . '</p>' .
                            '</div>' .
                        '</div>' .
                        '<p class="header-app-loyalty"><strong>' . tc('header.app.loyaltyTitle') . '</strong> ' . tc('header.app.loyaltyText') . '</p>' .
                    '</div>' .
                '</div>' .
                '<div class="header-lang">' . renderCurrencySwitcher() . renderLanguageSwitcher() . '</div>' .
            '</div>' .
        '</div></div>' .
        '<div class="header"><div class="container dfcs">' .
            '<div class="header-logo"><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="' . te('header.logoAlt') . '" loading="eager" fetchpriority="high" width="168" height="44"></a></div>' .
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
        // Položky bez route (no_link rozcestníky) ve footeru přeskakujeme — místo
        // toho v patičce ukážeme přímo děti, aby uživatel viděl všechny smysluplné cíle.
        if (!empty($item['no_link']) && !empty($item['children'])) {
            foreach ($item['children'] as $ch) {
                $menuHtml .= '<li><a data-route="' . $ch['route'] . '" href="' . BASE_URL . $ch['route'] . '">' . $ch['label'] . '</a></li>';
            }
            continue;
        }
        $menuHtml .= '<li><a data-route="' . $item['route'] . '" href="' . BASE_URL . $item['route'] . '">' . $item['label'] . '</a></li>';
    }
    $menuHtml .= '<li><a data-route="/rezervace" href="' . BASE_URL . '/rezervace">' . tc('menu.reservation') . '</a></li>';
    $menuHtml .= '<li><a data-route="/upravit-rezervaci" href="' . BASE_URL . '/upravit-rezervaci">' . tc('menu.editReservation') . '</a></li>';

    $helpTitleRaw = trim((string)t('footer.helpTitle'));
    $callUsRaw = trim((string)t('footer.callUs'));
    $helpTitleHtml = $helpTitleRaw !== '' ? '<h3>' . tc('footer.helpTitle') . '</h3>' : '';
    $callUsHtml = $callUsRaw !== '' ? tc('footer.callUs') . '<br>' : '';

    return '<footer id="footer"><div class="container"><div class="gr4">' .
        '<div>' .
            '<p><a href="' . BASE_URL . '/" aria-label="Motogo24"><img src="' . BASE_URL . '/' . LOGO_SVG . '" alt="Motogo24" loading="lazy" width="168" height="44"></a></p><p>&nbsp;</p>' .
            '<p>' . tcRaw('footer.aboutText') . '</p>' .
        '</div>' .
        '<div><h3>' . tc('footer.aboutTitle') . '</h3><ul>' . $menuHtml . '</ul></div>' .
        '<div><h3>' . tc('footer.socialTitle') . '</h3>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Facebook ikona" src="' . BASE_URL . '/gfx/facebook-footer.svg" width="18" height="18"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
            '<p class="dfc"><span class="footer-social-icon"><img alt="Instagram ikona" src="' . BASE_URL . '/gfx/instagram-footer.svg" width="18" height="18"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p>' .
        '</div>' .
        '<div class="footer-contact">' . $helpTitleHtml .
            '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/telefon.svg" alt="' . te('footer.iconPhone') . '" class="icon-small" loading="lazy" width="20" height="20"></div><div><p>' . $callUsHtml . '<strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/email.svg" alt="' . te('footer.iconEmail') . '" class="icon-small" loading="lazy" width="20" height="20"></div><div><p><a href="mailto:' . EMAIL_FULL . '">' . EMAIL_USER . '&#64;' . EMAIL_DOMAIN . '</a></p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/adresa.svg" alt="' . te('footer.iconAddress') . '" class="icon-small" loading="lazy" width="20" height="20"></div><div><p><strong>' . tc('footer.companyLine1') . '</strong><br>' . ADDRESS . '</p></div></div>' .
            '<div class="dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/provozni-doba.svg" alt="' . te('footer.iconHours') . '" class="icon-small" loading="lazy" width="20" height="20"></div><div><p>' . preg_replace('/\)\s+(?=\S)/', ')<br>', tc('footer.openHours'), 1) . '</p></div></div>' .
        '</div>' .
    '</div></div>' .
    '<div class="footer-partners"><div class="container">' .
        '<span class="footer-partners-label">' . tc('footer.partnersTitle') . '</span>' .
        '<a class="footer-partner" href="https://www.kudyznudy.cz/?utm_source=kzn&amp;utm_medium=partneri_kzn&amp;utm_campaign=banner" target="_blank" rel="noopener" aria-label="Kudy z nudy"><img src="https://www.kudyznudy.cz/getmedia/e258ea1e-6a92-4443-940f-fdafe8da106e/1012102023-online-bannery-hq-180x150.jpg.aspx" alt="Kudyznudy.cz – nejlepší začátek výletu" loading="lazy" width="180" height="150"></a>' .
        '<a class="footer-partner" href="https://www.tripadvisor.com/Attraction_Review-g1600819-d34461468-Reviews-MotoGo24-Pelhrimov_Vysocina_Region_Moravia.html" target="_blank" rel="noopener" aria-label="MotoGo24 na Tripadvisoru"><img src="' . BASE_URL . '/gfx/tripadvisor-footer.svg" alt="MotoGo24 na Tripadvisoru" loading="lazy" width="180" height="150"></a>' .
    '</div></div>' .
    '<div class="copyright"><div class="container">' .
        '<p>' . tc('footer.copyright') . '</p>' .
        '<p><a href="' . BASE_URL . '/mapa-stranek">' . tc('footer.sitemap') . '</a><a href="#" data-cookie-prefs>' . tc('footer.cookies') . '</a><a href="' . BASE_URL . '/dokumenty/zasady-ochrany-osobnich-udaju">' . tc('footer.gdpr') . '</a><a href="' . BASE_URL . '/dokumenty/obchodni-podminky">' . tc('footer.terms') . '</a><a href="' . BASE_URL . '/dokumenty/smlouva-o-pronajmu">' . tc('footer.contract') . '</a><a href="' . BASE_URL . '/partneri">' . tc('footer.partners') . '</a></p>' .
        '<p class="footer-toplist"><a href="https://www.toplist.cz/stat/1841683" target="_blank" rel="nofollow noopener" aria-label="TOPlist"><img src="https://toplist.cz/count.asp?ID=1841683&amp;logo=mc" alt="TOPlist" width="88" height="31" loading="lazy"></a></p>' .
    '</div></div>' .
    '</footer>' .
    '<a id="Up" href="#" aria-label="' . te('footer.toTop') . '" onclick="window.scrollTo({top:0,behavior:\'smooth\'});return false"><img src="' . BASE_URL . '/gfx/arrow-top.svg" alt="' . te('footer.toTop') . '" width="20" height="20"></a>';
}

function renderInlineJs() {
    return '<script src="' . assetUrl('/js/ui.js') . '" defer></script>';
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
    $list = [FB_URL, IG_URL, 'https://www.tripadvisor.com/Attraction_Review-g1600819-d34461468-Reviews-MotoGo24-Pelhrimov_Vysocina_Region_Moravia.html', 'https://www.motogo24.cz', 'https://www.motogo24.com', 'https://www.motogo24.at', 'https://www.motogo24.es', 'https://www.motogo24.pl', 'https://www.motogo24.fr', 'https://www.motogo24.nl'];
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
 * Cookie consent manager — GDPR/ePrivacy lišta + JS injektor pro GTM a Sklik.
 *
 * Klíčový princip (právní compliance):
 *   GTM ANI Sklik se NIKDY nenačítají přímo ze zdrojového HTML. Až po výslovném
 *   souhlasu uživatele je banner JS dynamicky injektne do DOM. Bez souhlasu
 *   se ven na google-analytics.com / googletagmanager.com / c.imedia.cz nevolá
 *   ani jeden request. Tím je web v souladu se zákonem 110/2019 Sb. (§ 89)
 *   a GDPR čl. 6.
 *
 * Persistence: cookie `mg_cookie_consent` (1 rok, JSON {analytics:0/1, marketing:0/1, v, ts}).
 * Re-otevření: jakýkoliv prvek s `data-cookie-prefs` (footer link) banner zobrazí znovu.
 *
 * Dynamicky načtené:
 *   - analytics=1  → GTM container (gtm.js + noscript iframe) → uvnitř GTM se aktivuje
 *                    Google Analytics 4 + Google Ads Conversion Tag (na purchase event).
 *   - marketing=1  → Sklik retargeting (c.imedia.cz/js/retargeting.js).
 *
 * Purchase event (po Stripe platbě) je v `js/pages-potvrzeni.js` jako prostý
 * `dataLayer.push({event:'purchase', …})`. Pokud GTM není načten (uživatel
 * odmítl), je to no-op — buffer se zahodí. Pokud souhlasil, GTM trigger
 * "purchase" vystřelí Google Ads conversion tag.
 */
function renderConsentManager() {
    $gtmId   = defined('GTM_CONTAINER_ID') ? GTM_CONTAINER_ID : '';
    $sklikId = defined('SKLIK_RETARGETING_ID') ? SKLIK_RETARGETING_ID : '';
    $hasGtm   = $gtmId !== '';
    $hasSklik = $sklikId !== '' && ctype_digit((string)$sklikId);

    // Pokud nemáme co měřit, banner ani nezobrazujeme — žádné rušení uživatele.
    if (!$hasGtm && !$hasSklik) return '';

    $cfg = json_encode([
        'gtmId'   => $hasGtm ? $gtmId : null,
        'sklikId' => $hasSklik ? (int)$sklikId : null,
    ], JSON_UNESCAPED_SLASHES);

    $title         = te('cookies.title');
    $intro         = tcRaw('cookies.intro'); // může obsahovat <a href="/gdpr">…</a>
    $btnAccept     = te('cookies.acceptAll');
    $btnReject     = te('cookies.rejectAll');
    $btnSettings   = te('cookies.settings');
    $btnSave       = te('cookies.save');
    $catNecessary  = te('cookies.cat.necessary');
    $catNecessaryDesc = te('cookies.cat.necessaryDesc');
    $catAnalytics  = te('cookies.cat.analytics');
    $catAnalyticsDesc = te('cookies.cat.analyticsDesc');
    $catMarketing  = te('cookies.cat.marketing');
    $catMarketingDesc = te('cookies.cat.marketingDesc');
    $always        = te('cookies.always');

    // Settings panel — kategorie analytics/marketing se renderují jen pokud
    // pro ně je co zapínat (jinak by byl checkbox bez efektu).
    $rowAnalytics = $hasGtm ? '<label class="mg-consent-row"><span><strong>' . $catAnalytics . '</strong><br><small>' . $catAnalyticsDesc . '</small></span><input type="checkbox" id="mg-consent-analytics"></label>' : '';
    $rowMarketing = $hasSklik ? '<label class="mg-consent-row"><span><strong>' . $catMarketing . '</strong><br><small>' . $catMarketingDesc . '</small></span><input type="checkbox" id="mg-consent-marketing"></label>' : '';

    $html = '
<div id="mg-consent" class="mg-consent" role="dialog" aria-modal="false" aria-labelledby="mg-consent-title" aria-live="polite" hidden>
  <div class="mg-consent-inner">
    <h2 id="mg-consent-title" class="mg-consent-title">' . $title . '</h2>
    <div class="mg-consent-intro">' . $intro . '</div>
    <div id="mg-consent-settings" class="mg-consent-settings" hidden>
      <label class="mg-consent-row mg-consent-row--locked">
        <span><strong>' . $catNecessary . '</strong><br><small>' . $catNecessaryDesc . '</small></span>
        <span class="mg-consent-pill">' . $always . '</span>
      </label>
      ' . $rowAnalytics . '
      ' . $rowMarketing . '
    </div>
    <div id="mg-consent-buttons" class="mg-consent-buttons">
      <button type="button" class="btn btngreen-small" data-consent-action="accept-all">' . $btnAccept . '</button>
      <button type="button" class="btn btn-outline" data-consent-action="reject-all">' . $btnReject . '</button>
      <button type="button" class="btn btn-link" data-consent-action="settings">' . $btnSettings . '</button>
      <button type="button" class="btn btngreen-small" data-consent-action="save" hidden>' . $btnSave . '</button>
    </div>
  </div>
</div>
<script>window.MG_CONSENT_CFG=' . $cfg . ';</script>
<script src="' . assetUrl('/js/consent.js') . '" defer></script>';

    return $html;
}

/**
 * Webmaster Tools verifikační meta tagy. Emitují se jen ty, které mají
 * neprázdnou hodnotu v env / config — žádné prázdné <meta> v HTML.
 *
 * Google Search Console: každá doména je samostatná property s vlastním kódem.
 * Vybíráme podle HTTP_HOST (motogo24.cz/.com/.pl/.at/.es/.fr/.nl). Pro neznámou
 * doménu fallback na VERIFY_GOOGLE (typicky .cz hodnota).
 *
 * Hodnoty se konfigurují přes env vars (viz config.php):
 *   MOTOGO_VERIFY_GOOGLE_<TLD> (CZ/COM/PL/AT/ES/FR/NL) / MOTOGO_VERIFY_GOOGLE (fallback)
 *   MOTOGO_VERIFY_BING / SEZNAM / YANDEX / PINTEREST / FACEBOOK
 */
function renderWebmasterVerification() {
    // Doménově-specifický Google Search Console kód
    $host = $_SERVER['HTTP_HOST'] ?? '';
    $host = preg_replace('#^www\.#i', '', strtolower($host));
    $googleCode = defined('VERIFY_GOOGLE') ? VERIFY_GOOGLE : '';
    $perDomain = [
        'motogo24.cz'  => defined('VERIFY_GOOGLE_CZ')  ? VERIFY_GOOGLE_CZ  : '',
        'motogo24.com' => defined('VERIFY_GOOGLE_COM') ? VERIFY_GOOGLE_COM : '',
        'motogo24.pl'  => defined('VERIFY_GOOGLE_PL')  ? VERIFY_GOOGLE_PL  : '',
        'motogo24.at'  => defined('VERIFY_GOOGLE_AT')  ? VERIFY_GOOGLE_AT  : '',
        'motogo24.es'  => defined('VERIFY_GOOGLE_ES')  ? VERIFY_GOOGLE_ES  : '',
        'motogo24.fr'  => defined('VERIFY_GOOGLE_FR')  ? VERIFY_GOOGLE_FR  : '',
        'motogo24.nl'  => defined('VERIFY_GOOGLE_NL')  ? VERIFY_GOOGLE_NL  : '',
    ];
    if (!empty($perDomain[$host])) {
        $googleCode = $perDomain[$host];
    }

    $tags = [
        ['google-site-verification', $googleCode],
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
 *   hreflang="cs" → https://www.motogo24.cz{path}
 *   hreflang="en" → https://www.motogo24.com{path}
 *   hreflang="de" → https://www.motogo24.at{path}
 *   hreflang="es" → https://www.motogo24.es{path}
 *   hreflang="pl" → https://www.motogo24.pl{path}
 *   hreflang="fr" → https://www.motogo24.fr{path}
 *   hreflang="nl" → https://www.motogo24.nl{path}
 *   hreflang="x-default" → https://www.motogo24.com{path}
 *
 * Reciproční hreflang mezi doménami je nutný — Google jinak hreflang ignoruje.
 *
 * @param string $path aktuální cesta (např. /blog/xy nebo /eshop)
 * @return string HTML <link> tagy
 */
function renderHreflangAlternates($path) {
    if (!defined('I18N_SUPPORTED')) return '';
    $live = defined('I18N_HREFLANG_LIVE') ? I18N_HREFLANG_LIVE : [];
    $out = '';
    foreach (I18N_SUPPORTED as $code) {
        // SEO: hreflang odkazy jen na domeny ktere jsou ZIVE. Mrtve domeny
        // (motogo24.es, .nl) by Seobility hlasilo jako 'External link problem
        // - Page is down' (tisice errors). I18N_HREFLANG_LIVE = ['es'=>false,
        // 'nl'=>false] -> ten kod se preskoci dokud se domeny nerozjedou.
        if (isset($live[$code]) && $live[$code] === false) continue;
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
 *   canonical    — canonical URL (default https://www.motogo24.cz{path} pro cs)
 *   og_image     — OG image URL
 *   og_type      — OG type (default website)
 *   robots       — robots directive (default index,follow)
 *   schema       — extra JSON-LD schema string (přidá se vedle LocalBusiness)
 *   breadcrumbs  — pole pro BreadcrumbList schema [['name'=>'X','url'=>'Y'], ...]
 */
function renderPage($title, $content, $currentPath = '/', $meta = []) {
    // Origin podle aktuálního jazyka (přes i18nOriginForLang) — vždy www
    // varianta: Forpsi (.cz) vynucuje www, Hosting90 (.com/.pl/.at/.es/.fr/.nl)
    // má Let's Encrypt cert jen na www. variantě → jakákoli non-www URL by se
    // 301-redirectovala. Bez tohoto fixu og:image, twitter:image, manifest,
    // RSS feed link, apple-touch-icon a všechny další $siteOrigin reference
    // emitujou non-www URL → Seobility hlásí ~600 stránek × 8 different
    // resources = 5000+ 'Internal redirects' a 'Image redirected'.
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $siteOrigin = function_exists('i18nOriginForLang') ? i18nOriginForLang($lang) : 'https://www.motogo24.cz';
    // Lokalizované slugy pro absolutní URL ve strukturovaných datech (JSON-LD)
    // — na cizojazyčné doméně musí katalog/dokumenty mířit na přeložený slug.
    $lp = function ($p) { return function_exists('i18nLocalizePath') ? i18nLocalizePath($p) : $p; };

    // Default description per-jazyk (cs/en/de/fr/es/nl/pl) — bez tohoto fallbacku
    // by Google na .com indexoval cizojazycne stranky s ceskym defaultnim popiskem.
    $defaultDesc = function_exists('t') ? t('seo.default.description') : 'Půjčovna motorek Vysočina – silniční, sportovní, enduro i dětské. Nonstop pronájem bez kauce, online rezervace a motorkářská výbava zdarma.';
    $description = $meta['description'] ?? $defaultDesc;
    $keywords = $meta['keywords'] ?? (function_exists('t') ? t('seo.default.keywords') : 'motopůjčovna');

    // POZN: drivejsi auto-truncate / pattern-shortening title+description bylo
    // odstraneno — menilo viditelne texty. Title a meta description se nyni
    // renderuji 1:1 jak jsou v CMS / data souborech. Pripadne 'too long'
    // upravi admin rucne ve Velin SEO Health dashboardu (ukaze konkretni
    // pole + delku + doporuceni).
    // Canonical = doménová home pro aktuální jazyk (cs → www.motogo24.cz,
    // ostatní → www.motogo24.<tld>). Tím Google indexuje každý jazyk výhradně
    // z jeho kanonické domény — žádný duplicate-content přes víc domén ani
    // www/non-www.
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
        // Responsive preload — browser vybere nejmensi vhodnou variantu
        // podle viewportu (mobil 480w, tablet 768w, desktop 1500w, 4K 1920w).
        $preload[] = [
            'href' => BASE_URL . '/gfx/hero-banner-1500.webp',
            'as' => 'image',
            'type' => 'image/webp',
            'fetchpriority' => 'high',
            'imagesrcset' => BASE_URL . '/gfx/hero-banner-480.webp 480w, ' . BASE_URL . '/gfx/hero-banner-768.webp 768w, ' . BASE_URL . '/gfx/hero-banner-1500.webp 1500w, ' . BASE_URL . '/gfx/hero-banner.webp 1920w',
            'imagesizes' => '100vw',
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
  <meta property="og:logo" content="' . $siteOrigin . '/gfx/logo.svg">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="' . htmlspecialchars($title) . '">
  <meta name="twitter:description" content="' . htmlspecialchars($description) . '">
  <meta name="twitter:image" content="' . htmlspecialchars($ogImage) . '">
  <link rel="canonical" href="' . htmlspecialchars($canonical) . '">
  <!-- Favicon: PNG první (Google Ads, starší crawlery), SVG druhý (moderní prohlížeče
       — vector, ostré na všech rozlišeních). Apple touch icon stejný PNG. -->
  <link rel="icon" type="image/png" sizes="120x120" href="' . $siteOrigin . '/apple-touch-icon.png">
  <link rel="icon" type="image/svg+xml" href="' . $siteOrigin . '/favicon.svg">
  <link rel="apple-touch-icon" sizes="120x120" href="' . $siteOrigin . '/apple-touch-icon.png">
  <link rel="shortcut icon" href="' . $siteOrigin . '/favicon.ico">  <link rel="manifest" href="' . BASE_URL . '/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="MotoGo24 — Blog a tipy na trasy" href="' . $siteOrigin . '/feed.xml">
  <link rel="sitemap" type="application/xml" title="Sitemap" href="' . $siteOrigin . '/sitemap.xml">
  <link rel="search" type="application/opensearchdescription+xml" title="MotoGo24" href="' . $siteOrigin . '/opensearch.xml">
  <link rel="alternate" type="application/json" title="MotoGo24 — AI Agent Manifest" href="' . $siteOrigin . '/.well-known/agent.json">
  <link rel="alternate" type="application/json" title="MotoGo24 — ChatGPT Plugin Manifest" href="' . $siteOrigin . '/.well-known/ai-plugin.json">
  <link rel="alternate" type="text/markdown" title="MotoGo24 — LLM Index" href="' . $siteOrigin . '/llms.txt">
  <meta name="application-name" content="MotoGo24">
  <meta name="geo.region" content="CZ-VY">
  <meta name="geo.placename" content="Pelhřimov, Vysočina, Česko">
  <meta name="geo.position" content="49.3464;15.2119">
  <meta name="ICBM" content="49.3464, 15.2119">
  <meta name="referrer" content="strict-origin-when-cross-origin">
' . renderWebmasterVerification() . renderHreflangAlternates($currentPath) . '
  <title>' . htmlspecialchars($title) . '</title>

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": ["LocalBusiness", "AutomotiveBusiness", "Organization"],
        "@id": "' . $siteOrigin . '/#organization",
        "name": "MotoGo24 — půjčovna motorek Vysočina",
        "alternateName": ["MotoGo24","Motogo24 Pelhřimov","Motopůjčovna MotoGo24","Motopůjčovna Vysočina","Motopůjčovna Pelhřimov","Půjčovna motorek Vysočina","MotoGo24 motorcycle rental"],
        "legalName": "Bc. Petra Semorádová",
        "description": "Motopůjčovna a půjčovna motorek na Vysočině — silniční, naked, supermoto, enduro i dětské motorky. Bez kauce, výbava v ceně, nonstop provoz.",
        "slogan": "Půjč si motorku bez kauce. Nonstop. Online.",
        "url": "' . $siteOrigin . '",
        "logo": {"@type":"ImageObject","url":"' . $siteOrigin . '/gfx/logo.svg","width":512,"height":512},
        "image": "' . $siteOrigin . '/gfx/hero-banner.jpg",
        "email": "info@motogo24.cz",
        "telephone": "+420 774 256 271",
        "taxID": "21874263",
        "vatID": "CZ21874263",
        "foundingDate": "2024-07-31",
        "founder": {"@type":"Person","name":"Bc. Petra Semorádová"},
        "priceRange": "990 – 5000 Kč/den",
        "currenciesAccepted": "CZK, EUR, USD",
        "paymentAccepted": "Cash, Credit Card, Debit Card, Apple Pay, Google Pay",
        "knowsLanguage": ["cs","en","de","es","fr","nl","pl"],
        "keywords": "motopůjčovna, motopůjčovna Vysočina, motopůjčovna Pelhřimov, půjčovna motorek, půjčovna motorek Vysočina, pronájem motorek, půjčovna motocyklů, motorka bez kauce, MotoGo24",
        "address": {"@type":"PostalAddress","streetAddress":"Mezná 9","addressLocality":"Pelhřimov","postalCode":"393 01","addressRegion":"Vysočina","addressCountry":"CZ"},
        "geo": {"@type":"GeoCoordinates","latitude":49.3464,"longitude":15.2119},
        "hasMap": "https://mapy.cz/zakladni?q=Mezn%C3%A1%209%20Pelh%C5%99imov",
        "openingHoursSpecification": {"@type":"OpeningHoursSpecification","dayOfWeek":["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens":"00:00","closes":"23:59"},
        "areaServed": [
          {"@type":"Country","name":"Česko"},
          {"@type":"AdministrativeArea","name":"Kraj Vysočina"},
          {"@type":"Country","name":"Slovensko"},
          {"@type":"Country","name":"Rakousko"},
          {"@type":"Country","name":"Německo"},
          {"@type":"Country","name":"Polsko"},
          {"@type":"Country","name":"Francie"},
          {"@type":"Country","name":"Belgie"},
          {"@type":"Country","name":"Nizozemsko"},
          {"@type":"Country","name":"Španělsko"}
        ],
        "contactPoint": [
          {"@type":"ContactPoint","telephone":"+420 774 256 271","email":"info@motogo24.cz","contactType":"customer service","areaServed":["CZ","SK","AT","DE","PL","FR","BE","NL","ES"],"availableLanguage":["cs","en","de","pl","sk","fr","nl","es"]}
        ],
        "hasOfferCatalog": {
          "@type":"OfferCatalog",
          "name":"Katalog motorek k pronájmu",
          "url":"' . $siteOrigin . $lp('/katalog') . '",
          "itemListElement":[
            {"@type":"OfferCatalog","name":"Cestovní motorky","url":"' . $siteOrigin . $lp('/katalog/cestovni') . '"},
            {"@type":"OfferCatalog","name":"Naked motorky","url":"' . $siteOrigin . $lp('/katalog/naked') . '"},
            {"@type":"OfferCatalog","name":"Supermoto","url":"' . $siteOrigin . $lp('/katalog/supermoto') . '"},
            {"@type":"OfferCatalog","name":"Dětské motorky","url":"' . $siteOrigin . $lp('/katalog/detske') . '"}
          ]
        },
        "potentialAction": [
          {"@type":"ReserveAction","target":{"@type":"EntryPoint","urlTemplate":"' . $siteOrigin . $lp('/rezervace') . '?moto={moto_id}&start={start_date}&end={end_date}","actionPlatform":["http://schema.org/DesktopWebPlatform","http://schema.org/MobileWebPlatform","http://schema.org/IOSPlatform","http://schema.org/AndroidPlatform"]},"result":{"@type":"Reservation","name":"Rezervace motorky"}},
          {"@type":"OrderAction","target":"' . $siteOrigin . $lp('/eshop') . '","name":"Nákup výbavy a poukazů"}
        ],
        "sameAs": ' . json_encode(buildSameAs(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . $aggregateRatingFragment . '
      },
      {
        "@type": "WebSite",
        "@id": "' . $siteOrigin . '/#website",
        "url": "' . $siteOrigin . '",
        "name": "MotoGo24 — půjčovna motorek Vysočina",
        "inLanguage": "' . htmlspecialchars($htmlLang) . '",
        "publisher": {"@id":"' . $siteOrigin . '/#organization"},
        "potentialAction": {"@type":"SearchAction","target":{"@type":"EntryPoint","urlTemplate":"' . $siteOrigin . $lp('/katalog') . '?q={search_term_string}"},"query-input":"required name=search_term_string"}
      },
      {
        "@type": "Service",
        "@id": "' . $siteOrigin . '/#service-rental",
        "serviceType": "Pronájem motocyklů (motorcycle rental)",
        "name": "Motopůjčovna MotoGo24 — půjčovna motorek Vysočina",
        "description": "Motopůjčovna na Vysočině. Krátkodobý i dlouhodobý pronájem motocyklů v Česku. Cestovní, naked, supermoto, enduro, sportovní i dětské motorky. Bez kauce, motorkářská výbava v ceně, online rezervace s platbou kartou, nonstop dostupnost převzetí. Možnost přistavení mimo pobočku, sjezd do EU povolen, zelená karta v ceně.",
        "provider": {"@id":"' . $siteOrigin . '/#organization"},
        "areaServed": [{"@type":"Country","name":"Česko"},{"@type":"Country","name":"Slovensko"},{"@type":"Country","name":"Rakousko"},{"@type":"Country","name":"Německo"},{"@type":"Country","name":"Polsko"},{"@type":"Country","name":"Francie"},{"@type":"Country","name":"Belgie"},{"@type":"Country","name":"Nizozemsko"},{"@type":"Country","name":"Španělsko"}],
        "audience": {"@type":"PeopleAudience","audienceType":"Motorkáři, turisté, firmy, dárky pro blízké"},
        "availableChannel": [
          {"@type":"ServiceChannel","serviceUrl":"' . $siteOrigin . $lp('/rezervace') . '","name":"Online rezervační formulář"},
          {"@type":"ServiceChannel","serviceUrl":"https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api","name":"Veřejné REST API pro AI agenty a partnery"},
          {"@type":"ServiceChannel","serviceUrl":"https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server","name":"MCP server (Model Context Protocol)"},
          {"@type":"ServiceChannel","servicePhone":"+420 774 256 271","name":"Telefon (24/7)"},
          {"@type":"ServiceChannel","serviceUrl":"https://wa.me/420774256271","name":"WhatsApp"}
        ],
        "termsOfService": "' . $siteOrigin . $lp('/dokumenty/obchodni-podminky') . '",
        "offers": {"@type":"AggregateOffer","priceCurrency":"CZK","lowPrice":"990","highPrice":"5000","offerCount":50,"availability":"https://schema.org/InStock","seller":{"@id":"' . $siteOrigin . '/#organization"}}
      }
    ]
  }
  </script>' . $breadcrumbSchema . $speakableSchema . ($extraSchema ? "\n" . $extraSchema : '') . '

  <link rel="preconnect" href="' . SUPABASE_URL . '" crossorigin>
  <link rel="preload" href="' . assetUrl('/gfx/fonts/montserrat-vf-latin-ext.woff2') . '" as="font" type="font/woff2" crossorigin>';

    foreach ($preload as $p) {
        $attrs = '';
        foreach (['href', 'as', 'type', 'fetchpriority', 'imagesrcset', 'imagesizes', 'media'] as $a) {
            if (!empty($p[$a])) $attrs .= ' ' . $a . '="' . htmlspecialchars($p[$a]) . '"';
        }
        echo '
  <link rel="preload"' . $attrs . '>';
    }

    // Critical CSS — inline above-the-fold rezervace prostoru pro banner.
    // Bez tohoto by browser pred nactenim main.css pouzil width/height attrs
    // hero <img> (1920x480 = 4:1), na mobilu ~360x90, pak by main.css zvedl
    // banner na 380px → CLS 0.241. Inline blok zaridi rezervaci hned.
    echo '
  <style>
body{font-family:Montserrat,"Segoe UI",sans-serif;margin:0;color:#1a2e22;background:#fff}
.banner{position:relative;width:100%;min-height:380px;overflow:hidden;background:#1a3a2a}
.banner>picture,.banner>picture>img,.banner>img{width:100%;height:380px;object-fit:cover;display:block}
@media(min-width:769px){.banner{min-height:480px}.banner>picture,.banner>picture>img,.banner>img{height:480px}}
  </style>
  <link rel="stylesheet" href="' . assetUrl('/css/main.css') . '">
</head>
<body' . ($currentPath === '/' ? ' class="homepage"' : '') . '>
';
    // GTM/Sklik se NIKDY nevkládá přímo do HTML — banner JS je injektne
    // až po souhlasu. Viz renderConsentManager() na konci stránky.
    // Lokalizace interních odkazů (menu, footer, CMS obsah) na slug aktuálního
    // jazyka — i18nLocalizeHrefs() přepisuje jen root-relativní href="/...",
    // absolutní hreflang/switcher URL nesahá. Pro cs no-op.
    echo i18nLocalizeHrefs(renderHeader($currentPath));
    echo '<div id="app">';
    // SEO defensive enhancers — pojistka napric celym webem aby cokoliv
    // pridaneho z Velin CMS (motorky, blog, faq, texty stranek) prochazelo
    // SEO checkem rovnou bez admin micromanage. Na non-admin requestu:
    //  1) Strip prazdnych <hN></hN> (nech jen ne-prazdne)
    //  2) Auto-extend kratke <h1> (<25 chars) o " | MotoGo24" pro context
    //  3) Auto-set alt na <img> bez alt (z H1 textu nebo filename)
    //  4) Cap pocet <strong> na 8 per stranka (preda zbytecne na <span>)
    //  5) Auto-promote h3->h2 / h4->h3 kdyz chybi mezikrok
    if (!mgCmsAdminValid() && !empty($content)) {
        $content = seoEnhanceHtml($content);
    }
    echo i18nLocalizeHrefs($content);
    echo '</div>';
    echo i18nLocalizeHrefs(renderFooter());

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
    // POZOR: cart_url MUSÍ zůstat český '/kosik' — checkout.js z něj odvozuje
    // BASE_URL přes cart_url.replace("/kosik",""). Lokalizaci URL v adresním
    // řádku zajistí 301 v i18nSlugRedirectIfNeeded() (/kosik → /cart, /panier…).
    $cartI18n = json_encode([
        'cart_added'  => t('cart.added'),
        'cart_url'    => BASE_URL . '/kosik',
        'cart_size'   => t('cart.size'),
        'cart_pcs'    => t('cart.pcs'),
        'cart_qty'    => t('cart.qty'),
        'cart_remove' => t('cart.remove'),
        'idle.logout' => t('idle.logout'),
    ], JSON_UNESCAPED_UNICODE);
    echo '
<script>
window.MG_I18N = Object.assign(window.MG_I18N || {}, ' . $cartI18n . ');
</script>
<script src="' . assetUrl('/js/cart.js') . '" defer></script>
<script src="' . assetUrl('/js/header-auth.js') . '" defer></script>
<script src="' . assetUrl('/js/header-app.js') . '" defer></script>';

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
    if (mgCmsAdminValid()) {
        $highlight = isset($_GET['cms_highlight']) ? (string)$_GET['cms_highlight'] : '';
        // #5 fix: do JS posíláme PODEPSANOU capability `r1.…` (cms-save ji ověří
        // veřejným klíčem) — raw token tak NIKDY neopustí server. Jen ve
        // fallbacku (edge cms-admin-auth ještě nenasazená → cookie je legacy
        // HMAC, ne cap) pošleme raw token, aby web overlay save fungoval i v
        // přechodu (token je tou dobou ještě anon-čitelný).
        $cmsCookieCred = isset($_COOKIE['mg_cms_sig']) ? (string)$_COOKIE['mg_cms_sig'] : '';
        if (strncmp($cmsCookieCred, 'r1.', 3) !== 0) {
            $cmsCookieCred = '';
            try {
                $cmsSb = isset($sb) && $sb instanceof SupabaseClient ? $sb : new SupabaseClient();
                $tk = $cmsSb->fetchSetting('cms_admin_token');
                if (is_string($tk)) $cmsCookieCred = $tk;
            } catch (\Throwable $e) { /* prázdné → overlay info-only */ }
        }
        $cmsCfg = json_encode([
            'highlight' => $highlight,
            'token' => $cmsCookieCred,
            'apiUrl' => SUPABASE_URL . '/functions/v1/cms-save',
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        echo '
<script>window.MG_CMS_ADMIN = ' . $cmsCfg . ';</script>
<link rel="stylesheet" href="' . BASE_URL . '/css/cms-admin.css?v=' . @filemtime(__DIR__ . '/css/cms-admin.css') . '">
<script src="' . BASE_URL . '/js/cms-admin.js?v=' . @filemtime(__DIR__ . '/js/cms-admin.js') . '" defer></script>';
    }

    // Cookie consent manager — banner + JS injektor pro GTM/Sklik.
    // Musí být POSLEDNÍ v <body>, aby běžel po načtení DOM a měl k dispozici
    // header/footer (re-open přes [data-cookie-prefs]).
    echo i18nLocalizeHrefs(renderConsentManager());

    echo '
</body>
</html>';
}
