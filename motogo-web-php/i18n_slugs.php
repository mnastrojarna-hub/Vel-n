<?php
// ===== MotoGo24 Web PHP — Lokalizované URL slugy (SEO) =====
// Kanonické cesty = české (master, motogo24.cz beze změny). Na cizojazyčných
// jazycích/doménách se indexovatelné marketingové stránky servírují pod
// přeloženým slugem (/catalog, /motorradverleih, /alquiler-de-motos, …).
//
// 2026-06-12: 100% pokrytí — VŠECHNY routy (vč. transakčních /rezervace,
// /kosik, /objednavka*, /potvrzeni, /upravit-rezervaci a /eshop) mají slug
// ve všech 7 jazycích. Natvrdo zapsané české cesty v JS (Stripe success/
// cancel URL, resume QR z mailů, edge funkce) dál fungují — server je přes
// i18nSlugRedirectIfNeeded() 301-redirectne na lokalizovaný tvar SE
// zachováním query stringu. Jediná tvrdá závislost: `MG_I18N.cart_url`
// v layout.php MUSÍ zůstat '/kosik' (checkout.js z něj odvozuje BASE_URL
// přes cart_url.replace("/kosik","")). Kde je české/kanonické slovo zároveň
// správné i v cílovém jazyce (katalog/kontakt de+pl, naked/supermoto/
// chopper, blog ve všech jazycích), je záznam uveden explicitně (stejná
// hodnota) — mapa je tak auditovatelná na úplnost. Slugy DB entit
// (/blog/<slug>, /dokumenty/<slug>) zůstávají české — překládá se jen
// prefix; per-jazyk slugy entit by vyžadovaly backend.
//
// Tok:
//   příchozí request → i18nSlugRedirectIfNeeded() 301 na lokalizovaný tvar
//                    → i18nCanonicalPath() → router pracuje s českou cestou
//   odchozí odkazy   → i18nUrlForLang() (canonical, hreflang, sitemap, switcher)
//                    → i18nLocalizeHrefs() přepíše href="/..." v těle HTML
//
// Jazyk, který v mapě chybí, používá kanonický (český/mezinárodní) slug.

require_once __DIR__ . '/config.php';

const I18N_SLUG_ROUTES = [
    '/katalog' => ['en' => '/catalog', 'de' => '/katalog', 'es' => '/catalogo', 'fr' => '/catalogue', 'nl' => '/catalogus', 'pl' => '/katalog', 'uk' => '/catalog'],
    '/katalog/cestovni' => ['en' => '/catalog/touring', 'de' => '/katalog/reise', 'es' => '/catalogo/turismo', 'fr' => '/catalogue/routieres', 'nl' => '/catalogus/toer', 'pl' => '/katalog/turystyczne', 'uk' => '/catalog/touring'],
    '/katalog/sportovni' => ['en' => '/catalog/sport', 'de' => '/katalog/sport', 'es' => '/catalogo/deportivas', 'fr' => '/catalogue/sportives', 'nl' => '/catalogus/sport', 'pl' => '/katalog/sportowe', 'uk' => '/catalog/sport'],
    '/katalog/naked' => ['en' => '/catalog/naked', 'de' => '/katalog/naked', 'es' => '/catalogo/naked', 'fr' => '/catalogue/naked', 'nl' => '/catalogus/naked', 'pl' => '/katalog/naked', 'uk' => '/catalog/naked'],
    '/katalog/supermoto' => ['en' => '/catalog/supermoto', 'de' => '/katalog/supermoto', 'es' => '/catalogo/supermoto', 'fr' => '/catalogue/supermoto', 'nl' => '/catalogus/supermoto', 'pl' => '/katalog/supermoto', 'uk' => '/catalog/supermoto'],
    '/katalog/chopper' => ['en' => '/catalog/chopper', 'de' => '/katalog/chopper', 'es' => '/catalogo/chopper', 'fr' => '/catalogue/chopper', 'nl' => '/catalogus/chopper', 'pl' => '/katalog/chopper', 'uk' => '/catalog/chopper'],
    '/katalog/detske' => ['en' => '/catalog/kids', 'de' => '/katalog/kinder', 'es' => '/catalogo/infantiles', 'fr' => '/catalogue/enfants', 'nl' => '/catalogus/kinder', 'pl' => '/katalog/dzieciece', 'uk' => '/catalog/kids'],
    '/pujcovna-motorek' => ['en' => '/motorcycle-rental', 'de' => '/motorradverleih', 'es' => '/alquiler-de-motos', 'fr' => '/location-de-motos', 'nl' => '/motorverhuur', 'pl' => '/wypozyczalnia-motocykli', 'uk' => '/motorcycle-rental'],
    // Oblasti (rozcestník krajů). Slugy krajů (/oblasti/vysocina…) jsou vlastní
    // jména — překládá se jen prefix (viz I18N_SLUG_PREFIXES níže).
    '/oblasti' => ['en' => '/areas', 'de' => '/regionen', 'es' => '/regiones', 'fr' => '/regions', 'nl' => '/regios', 'pl' => '/regiony', 'uk' => '/areas'],
    // /jak-pujcit (rozcestník) jen 301-redirectuje na /postup — lokalizujeme i jeho.
    '/jak-pujcit' => ['en' => '/how-to-rent', 'de' => '/mietanleitung', 'es' => '/como-alquilar', 'fr' => '/comment-louer', 'nl' => '/hoe-huren', 'pl' => '/jak-wypozyczyc', 'uk' => '/how-to-rent'],
    '/jak-pujcit/postup' => ['en' => '/how-to-rent/process', 'de' => '/mietanleitung/ablauf', 'es' => '/como-alquilar/proceso', 'fr' => '/comment-louer/procedure', 'nl' => '/hoe-huren/werkwijze', 'pl' => '/jak-wypozyczyc/proces', 'uk' => '/how-to-rent/process'],
    '/jak-pujcit/pristaveni' => ['en' => '/how-to-rent/delivery', 'de' => '/mietanleitung/lieferung', 'es' => '/como-alquilar/entrega', 'fr' => '/comment-louer/livraison', 'nl' => '/hoe-huren/bezorging', 'pl' => '/jak-wypozyczyc/dostawa', 'uk' => '/how-to-rent/delivery'],
    '/jak-pujcit/prevzeti' => ['en' => '/how-to-rent/pickup', 'de' => '/mietanleitung/abholung', 'es' => '/como-alquilar/recogida', 'fr' => '/comment-louer/retrait', 'nl' => '/hoe-huren/afhalen', 'pl' => '/jak-wypozyczyc/odbior', 'uk' => '/how-to-rent/pickup'],
    '/jak-pujcit/vraceni-pujcovna' => ['en' => '/how-to-rent/return-at-branch', 'de' => '/mietanleitung/rueckgabe-filiale', 'es' => '/como-alquilar/devolucion-sucursal', 'fr' => '/comment-louer/retour-agence', 'nl' => '/hoe-huren/terugbrengen-filiaal', 'pl' => '/jak-wypozyczyc/zwrot-w-wypozyczalni', 'uk' => '/how-to-rent/return-at-branch'],
    '/jak-pujcit/vraceni-jinde' => ['en' => '/how-to-rent/return-elsewhere', 'de' => '/mietanleitung/rueckgabe-anderswo', 'es' => '/como-alquilar/devolucion-otro-lugar', 'fr' => '/comment-louer/retour-ailleurs', 'nl' => '/hoe-huren/terugbrengen-elders', 'pl' => '/jak-wypozyczyc/zwrot-w-innym-miejscu', 'uk' => '/how-to-rent/return-elsewhere'],
    '/jak-pujcit/co-v-cene' => ['en' => '/how-to-rent/whats-included', 'de' => '/mietanleitung/was-ist-im-preis', 'es' => '/como-alquilar/que-incluye', 'fr' => '/comment-louer/ce-qui-est-inclus', 'nl' => '/hoe-huren/wat-is-inbegrepen', 'pl' => '/jak-wypozyczyc/co-w-cenie', 'uk' => '/how-to-rent/whats-included'],
    '/jak-pujcit/dokumenty' => ['en' => '/how-to-rent/documents', 'de' => '/mietanleitung/dokumente', 'es' => '/como-alquilar/documentos', 'fr' => '/comment-louer/documents', 'nl' => '/hoe-huren/documenten', 'pl' => '/jak-wypozyczyc/dokumenty', 'uk' => '/how-to-rent/documents'],
    '/jak-pujcit/faq' => ['en' => '/how-to-rent/faq', 'de' => '/mietanleitung/faq', 'es' => '/como-alquilar/faq', 'fr' => '/comment-louer/faq', 'nl' => '/hoe-huren/faq', 'pl' => '/jak-wypozyczyc/faq', 'uk' => '/how-to-rent/faq'],
    '/poukazy' => ['en' => '/vouchers', 'de' => '/gutscheine', 'es' => '/tarjetas-regalo', 'fr' => '/bons-cadeaux', 'nl' => '/cadeaubonnen', 'pl' => '/vouchery', 'uk' => '/vouchers'],
    '/koupit-darkovy-poukaz' => ['en' => '/buy-gift-voucher', 'de' => '/gutschein-kaufen', 'es' => '/comprar-tarjeta-regalo', 'fr' => '/acheter-bon-cadeau', 'nl' => '/cadeaubon-kopen', 'pl' => '/kup-voucher', 'uk' => '/buy-gift-voucher'],
    '/kontakt' => ['en' => '/contact', 'de' => '/kontakt', 'es' => '/contacto', 'fr' => '/contact', 'nl' => '/contact', 'pl' => '/kontakt', 'uk' => '/contact'],
    '/mapa-stranek' => ['en' => '/sitemap', 'de' => '/seitenuebersicht', 'es' => '/mapa-del-sitio', 'fr' => '/plan-du-site', 'nl' => '/sitemap', 'pl' => '/mapa-strony', 'uk' => '/sitemap'],
    '/partneri' => ['en' => '/partners', 'de' => '/partner', 'es' => '/socios', 'fr' => '/partenaires', 'nl' => '/partners', 'pl' => '/partnerzy', 'uk' => '/partners'],
    '/smazani-uctu' => ['en' => '/account-deletion', 'de' => '/konto-loeschen', 'es' => '/eliminar-cuenta', 'fr' => '/suppression-de-compte', 'nl' => '/account-verwijderen', 'pl' => '/usuniecie-konta', 'uk' => '/account-deletion'],
    // E-shop a blog (blog = stejné slovo ve všech 7 jazycích)
    '/eshop' => ['en' => '/shop', 'de' => '/shop', 'es' => '/tienda', 'fr' => '/boutique', 'nl' => '/winkel', 'pl' => '/sklep', 'uk' => '/shop'],
    '/blog' => ['en' => '/blog', 'de' => '/blog', 'es' => '/blog', 'fr' => '/blog', 'nl' => '/blog', 'pl' => '/blog', 'uk' => '/blog'],
    // Transakční cesty (noindex) — lokalizované od 2026-06-12. České URL
    // z JS/mailů/edge funkcí dál fungují přes 301 se zachovaným query
    // stringem (?resume=, ?order_id=, ?booking_id=, ?paid_booking=).
    // POZOR: nové lokalizované tvary /rezervace a /potvrzeni musí být
    // disallow-nuté i v robots.txt (jsou).
    '/rezervace' => ['en' => '/booking', 'de' => '/reservierung', 'es' => '/reserva', 'fr' => '/reservation', 'nl' => '/reservering', 'pl' => '/rezerwacja', 'uk' => '/booking'],
    '/upravit-rezervaci' => ['en' => '/manage-booking', 'de' => '/reservierung-verwalten', 'es' => '/gestionar-reserva', 'fr' => '/gerer-reservation', 'nl' => '/reservering-beheren', 'pl' => '/zarzadzaj-rezerwacja', 'uk' => '/manage-booking'],
    '/potvrzeni' => ['en' => '/confirmation', 'de' => '/bestaetigung', 'es' => '/confirmacion', 'fr' => '/confirmation', 'nl' => '/bevestiging', 'pl' => '/potwierdzenie', 'uk' => '/confirmation'],
    '/kosik' => ['en' => '/cart', 'de' => '/warenkorb', 'es' => '/cesta', 'fr' => '/panier', 'nl' => '/winkelwagen', 'pl' => '/koszyk', 'uk' => '/cart'],
    '/objednavka' => ['en' => '/checkout', 'de' => '/kasse', 'es' => '/pedido', 'fr' => '/commande', 'nl' => '/afrekenen', 'pl' => '/zamowienie', 'uk' => '/checkout'],
    '/objednavka/dokoncit' => ['en' => '/checkout/complete', 'de' => '/kasse/abgeschlossen', 'es' => '/pedido/completado', 'fr' => '/commande/terminee', 'nl' => '/afrekenen/voltooid', 'pl' => '/zamowienie/zakonczone', 'uk' => '/checkout/complete'],
];

// Prefixy pro dynamické cesty (UUID/slug za prefixem se nepřekládá).
const I18N_SLUG_PREFIXES = [
    '/katalog/' => ['en' => '/catalog/', 'de' => '/katalog/', 'es' => '/catalogo/', 'fr' => '/catalogue/', 'nl' => '/catalogus/', 'pl' => '/katalog/', 'uk' => '/catalog/'],
    '/dokumenty/' => ['en' => '/documents/', 'de' => '/dokumente/', 'es' => '/documentos/', 'fr' => '/documents/', 'nl' => '/documenten/', 'pl' => '/dokumenty/', 'uk' => '/documents/'],
    '/eshop/' => ['en' => '/shop/', 'de' => '/shop/', 'es' => '/tienda/', 'fr' => '/boutique/', 'nl' => '/winkel/', 'pl' => '/sklep/', 'uk' => '/shop/'],
    '/blog/' => ['en' => '/blog/', 'de' => '/blog/', 'es' => '/blog/', 'fr' => '/blog/', 'nl' => '/blog/', 'pl' => '/blog/', 'uk' => '/blog/'],
    '/oblasti/' => ['en' => '/areas/', 'de' => '/regionen/', 'es' => '/regiones/', 'fr' => '/regions/', 'nl' => '/regios/', 'pl' => '/regiony/', 'uk' => '/areas/'],
];

/** Reverzní mapa: lokalizovaný slug (libovolný jazyk) → kanonický. */
function _i18nSlugReverseExact() {
    static $rev = null;
    if ($rev !== null) return $rev;
    $rev = [];
    foreach (I18N_SLUG_ROUTES as $canonical => $byLang) {
        foreach ($byLang as $localized) {
            if ($localized !== $canonical) $rev[$localized] = $canonical;
        }
    }
    return $rev;
}

/** Reverzní prefix mapa seřazená od nejdelší (longest-prefix match). */
function _i18nSlugReversePrefixes() {
    static $rev = null;
    if ($rev !== null) return $rev;
    $rev = [];
    foreach (I18N_SLUG_PREFIXES as $canonical => $byLang) {
        foreach ($byLang as $localized) {
            if ($localized !== $canonical) $rev[$localized] = $canonical;
        }
    }
    uksort($rev, function ($a, $b) { return strlen($b) - strlen($a); });
    return $rev;
}

/**
 * Převede lokalizovanou cestu (libovolný jazyk) na kanonickou českou.
 * Neznámé cesty vrací beze změny — bezpečné volat na cokoliv.
 */
function i18nCanonicalPath($path) {
    if (!is_string($path) || $path === '' || $path[0] !== '/') return $path;
    $rev = _i18nSlugReverseExact();
    if (isset($rev[$path])) return $rev[$path];
    foreach (_i18nSlugReversePrefixes() as $localized => $canonical) {
        if (strpos($path, $localized) === 0) {
            return $canonical . substr($path, strlen($localized));
        }
    }
    return $path;
}

/**
 * Převede KANONICKOU českou cestu na lokalizovaný tvar pro daný jazyk.
 * (Vstup v cizím jazyce nejdřív prožeň přes i18nCanonicalPath().)
 */
function i18nLocalizePath($path, $lang = null) {
    if (!is_string($path) || $path === '' || $path[0] !== '/') return $path;
    $lang = $lang ?: (function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs');
    if ($lang === 'cs') return $path;
    if (isset(I18N_SLUG_ROUTES[$path])) {
        return I18N_SLUG_ROUTES[$path][$lang] ?? $path;
    }
    foreach (I18N_SLUG_PREFIXES as $canonical => $byLang) {
        if (isset($byLang[$lang]) && strpos($path, $canonical) === 0) {
            return $byLang[$lang] . substr($path, strlen($canonical));
        }
    }
    return $path;
}

/**
 * 301 redirect na lokalizovaný tvar cesty pro aktuálně detekovaný jazyk,
 * pokud se request liší (česká URL na .com → /catalog; anglická na .cz →
 * /katalog; po přepnutí jazyka cookie). Query string se zachovává — JS
 * (Stripe redirecty, ?resume=, ?order_id=) tak funguje beze změny.
 * Volat z index.php PŘED page cache. Pro neznámé cesty no-op.
 */
function i18nSlugRedirectIfNeeded($requestPath) {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    if ($method !== 'GET' && $method !== 'HEAD') return;
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $target = i18nLocalizePath(i18nCanonicalPath($requestPath), $lang);
    if ($target === $requestPath || headers_sent()) return;
    $qs = (string)($_SERVER['QUERY_STRING'] ?? '');
    header('Location: ' . BASE_URL . $target . ($qs !== '' ? '?' . $qs : ''), true, 301);
    exit;
}

/**
 * Přepíše root-relativní href="/..." odkazy v HTML na lokalizované slugy pro
 * aktuální jazyk. Catch-all pro interní odkazy v menu, footeru, CMS obsahu
 * i přeložených slovnících — žádná stránka nemusí lokalizovat ručně.
 * Absolutní URL (https://… — hreflang, language switcher) nesahá.
 */
function i18nLocalizeHrefs($html) {
    if (!is_string($html) || $html === '') return $html;
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    if ($lang === 'cs') return $html;
    return preg_replace_callback('~href="(/[^"?#]*)([^"]*)"~', function ($m) use ($lang) {
        $p = $m[1];
        $base = '';
        if (BASE_URL !== '' && strpos($p, BASE_URL) === 0) {
            $base = BASE_URL;
            $p = substr($p, strlen(BASE_URL));
        }
        $localized = i18nLocalizePath(i18nCanonicalPath($p), $lang);
        if ($localized === $p) return $m[0];
        return 'href="' . $base . $localized . $m[2] . '"';
    }, $html);
}
