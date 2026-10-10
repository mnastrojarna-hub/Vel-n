<?php
// ===== MotoGo24 Web PHP — Landing v2: informační stránky =====
// Sdílený „info page“ wrapper pro stránky z menu Jak si půjčit (postup, převzetí,
// vrácení ×2, co je v ceně, přistavení, dokumenty, FAQ) a Kontakt. Stránka si
// obsah vyrenderuje jako dřív a před renderPage() zavolá:
//   [$content, $lpiMeta] = lpInfoPage($content, '<klic>', $sb);
//   renderPage(…, $lpiMeta + [ …původní meta… ]);
// Mimo v2 (landingV2Enabled() = false, např. ?landing=v1) vrací obsah
// BEZE ZMĚNY a prázdná meta → výstup je bajtově shodný s původním.
// Ve v2 HTML <main> projde DOM post-procesorem (landing-info-dom.php):
// hero panel (H1 + intro + CTA + chipy), kroky jako časová osa, mřížky jako
// ikonové karty, tabulky jako karty, FAQ akordeon, CTA jako tmavá karta,
// závěrečný SEO text sbalený, bloky dle LPI_BLOCKS, sticky lišta. Text se NEMAŽE —
// jen se přeskupí/sbalí (v DOM zůstává celý). Výjimka = deduplikace: CTA se
// stejným cílem jako hero/závěrečná karta (lpiDedupeCtas) a drobeček = H1 (jen
// pro čtečky). FAQPage/HowTo schema a canonical řeší stránka mimo <main>,
// wrapper je nemění. Kontakt: landing-info-contact.php.
// Texty nových prvků: CS defaulty lpiDefaults() ← lang/v2/<lang>/info.php
// ('pages.landing_info') ← Velín CMS (web.landing_info.*).

require_once __DIR__ . '/landing.php';
require_once __DIR__ . '/landing-info-dom.php';
require_once __DIR__ . '/landing-info-blocks.php';
require_once __DIR__ . '/landing-info-contact.php';

/** Fotka do pozadí hero panelu (ztmavená) — podle stránky. */
const LPI_BG = [
    'postup' => 'gfx/hero-banner-768.webp',
    'prevzeti' => 'gfx/provozovna-2.jpg',
    'vraceni_pujcovna' => 'gfx/provozovna-1.jpg',
    'vraceni_jinde' => 'gfx/hero-banner-768.webp',
    'cena' => 'gfx/provozovna-4.jpg',
    'pristaveni' => 'gfx/provozovna-3.jpg',
    'dokumenty' => 'gfx/hero-banner-768.webp',
    'faq' => 'gfx/hero-banner-768.webp',
];

/**
 * Sdílené bloky landingu podle stránky — ne všude totéž (deduplikace, zadání majitele
 * „pozor na duplicity“): fleet = pruh motorek (živé ceny), reviews = recenze,
 * ai = výzva AI asistenta (FAQ: box pod otázkami, Kontakt: karta mezi kontakty).
 * Stránka bez recenzí odkazuje hodnocení v hero na recenze na úvodní stránce.
 */
const LPI_BLOCKS = [
    'postup' => ['fleet', 'reviews'],
    'prevzeti' => ['reviews'],
    'vraceni_pujcovna' => [],
    'vraceni_jinde' => [],
    'cena' => ['fleet'],
    'pristaveni' => ['fleet'],
    'dokumenty' => [],
    'faq' => ['reviews', 'ai'],
    'kontakt' => ['reviews', 'ai'],
];

/** CS defaulty textů nových prvků (cizí jazyky: lang/v2/<lang>/info.php). */
function lpiDefaults() {
    return [
        'cta_primary' => 'REZERVOVAT',
        'cta_secondary' => 'VYBRAT MOTORKU',
        'cta_call' => 'ZAVOLAT',
        'reserve' => 'Rezervovat motorku',
        'steps_title' => 'Jak to probíhá krok za krokem',
        'read_more' => 'Číst dál',
        'read_less' => 'Zobrazit méně',
        'chips' => [
            'postup' => ['Bez kauce', 'Výbava v ceně', 'Rezervace online za pár minut'],
            'prevzeti' => ['Převzetí v čase dle rezervace', 'Parkování zdarma', 'Bez kauce'],
            'vraceni_pujcovna' => ['Poslední den do 24:00', 'Bez tankování', 'Bez kauce'],
            'vraceni_jinde' => ['Kdekoliv v Česku', 'Jasný ceník za km', 'Bez kauce'],
            'cena' => ['0 Kč kauce', 'Výbava řidiče v ceně', 'Bez skrytých poplatků'],
            'pristaveni' => ['Domů, na hotel i na nádraží', 'Po celém Česku', 'Bez kauce'],
            'dokumenty' => ['Bez kauce', 'Srozumitelná smlouva', 'Bezpečná platba online'],
            'faq' => ['Bez kauce', 'Výbava řidiče v ceně', 'AI asistent 24/7'],
            'kontakt' => ['2 pobočky: Vysočina a Brno', 'Samoobsluha 24/7 u Brna', 'Rezervace online'],
        ],
        'ai' => [
            'title' => 'AI asistent 24/7',
            'text' => 'Nenašel jsi odpověď? Zeptej se Tomáše — odpoví hned, ve dne i v noci.',
            'card' => 'Zeptej se Tomáše — odpoví hned',
            'btn' => 'Zeptat se',
        ],
        'contact' => [
            'branches_title' => 'Naše pobočky',
            'detail' => 'Detail pobočky',
            'route' => 'Navigovat',
            'branches' => [
                ['badge' => 'Obslužná pobočka', 'title' => 'Mezná u Pelhřimova', 'text' => 'Motorku ti předáme osobně v čase dle rezervace — každý den, i o víkendech a svátcích.', 'chips' => ['Cca 90 min z Prahy', 'Přistavení na adresu'], 'detail' => 'Detail pobočky Mezná', 'route' => 'Navigovat do Mezné'],
                ['badge' => 'Samoobsluha 24/7', 'title' => 'Velké Němčice u Brna', 'text' => 'Motorku i výbavu převezmeš a vrátíš sám kódy z aplikace — nonstop, bez čekání.', 'chips' => ['30 min z Brna', '35 min z letiště Brno'], 'detail' => 'Detail pobočky Velké Němčice', 'route' => 'Navigovat do Velkých Němčic'],
            ],
        ],
    ];
}

/** Sloučené texty (CS default ← jazykový overlay ← DB ← Velín CMS). */
function lpiTexts($sb) {
    static $c = null;
    if ($c === null) $c = $sb->siteContent('landing_info', lpiDefaults());
    return $c;
}

/** Hook stránky → [content, meta]. Mimo v2 nebo při chybě: původní obsah, prázdná meta. */
function lpInfoPage($content, $page, $sb) {
    if (!landingV2Enabled() || !class_exists('DOMDocument') || !is_string($content)) return [$content, []];
    // Cizí jazyk bez textů wrapperu (lang/v2/<lang>/info.php) → raději v1 než české chipy na cizí stránce
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    if ($lang !== 'cs' && !is_array(t('pages.landing_info'))) return [$content, []];
    try {
        $out = lpInfoWrap($content, (string)$page, $sb);
    } catch (\Throwable $e) {
        error_log('lpInfoWrap(' . $page . '): ' . $e->getMessage());
        $out = '';
    }
    if ($out === '') return [$content, []];
    $m = lpPageMeta();
    $m['styles'][] = '/css/landing-info.css';
    $m['styles'][] = '/css/landing-info-parts.css';
    if ($page === 'kontakt') $m['styles'][] = '/css/landing-info-contact.css';
    $m['scripts'][] = '/js/landing-info.js';
    $m['body_class'] .= ' lpi-page';
    return [$out, $m];
}

/** Přestavba <main id="content"> stránky do v2 vzhledu. Prázdný řetězec = nelze (stránka zůstane v1). */
function lpInfoWrap($html, $page, $sb) {
    $a = strpos($html, '<main id="content"');
    $b = strrpos($html, '</main>');
    if ($a === false || $b === false || $b < $a) return '';
    $doc = lpiLoad(substr($html, $a, $b + 7 - $a));
    $x = new DOMXPath($doc);
    $main = $x->query('//main')->item(0);
    $cc = $main ? $x->query('.//div[contains(concat(" ",normalize-space(@class)," ")," ccontent ")]', $main)->item(0) : null;
    $h1 = $cc ? $x->query('.//h1', $cc)->item(0) : null;
    if (!$cc || !$h1) return '';
    $bc = $x->query('.//nav[contains(@class,"breadcrumb")]', $main)->item(0);

    $T = lpTexts($sb);
    $TC = $T['common'];
    $L = lpiTexts($sb);
    $admin = lpAdmin();
    $motos = $sb->fetchMotos();
    $on = array_flip(LPI_BLOCKS[$page] ?? ['fleet', 'reviews']);
    // Chipy hero, které už nese karta pobočky (Kontakt), se v hero neopakují
    $skip = [];
    if ($page === 'kontakt') foreach ((array)($L['contact']['branches'] ?? []) as $br) foreach ((array)($br['chips'] ?? []) as $c) $skip[mb_strtolower(lpPlain($c))] = 1;
    $opt = ['reviews' => isset($on['reviews']), 'skip' => $skip,
        // Kontakt: „Zavolat“ v hero jen když obsah nemá vlastní telefonní kartu (jinak by se volání opakovalo hned pod ním)
        'call' => $page === 'kontakt' && !$x->query('.//a[starts-with(@href,"tel:")]', $cc)->length];

    lpiFixBlockP($doc, $x, $cc);
    lpiStripSpacers($x, $cc);
    lpiCrumb($x, $bc, $h1);
    [$hero, $heroCtas] = lpiHero($doc, $x, $h1, $page, $L, $TC, $motos, $opt);
    lpiButtons($doc, $x, $cc);
    if ($page === 'kontakt') lpiContact($doc, $x, $cc, $L, $TC, isset($on['ai']));
    lpiLists($x, $cc, $admin);
    lpiTables($x, $cc);
    lpiGrids($doc, $x, $cc, $admin, $L);
    lpiFaqStyle($doc, $x, $cc);
    [$blocks, $cut] = lpiBlocks($doc, $x, $cc, $L, $TC, isset($on['ai']) && $page !== 'kontakt');
    // Editor Velínu (inline CMS) vidí všechna tlačítka — i ta skrytá deduplikací, aby šla upravit
    if (!$admin) lpiDedupeCtas($x, $cc, $heroCtas);

    $mid = (isset($on['fleet']) ? renderLpFleet($motos, $TC) : '') .
        (isset($on['reviews']) && function_exists('renderLpReviews') && function_exists('lpReviewsData') ? renderLpReviews(lpReviewsData(), $TC) : '');
    if ($mid === '') $cut = PHP_INT_MAX;
    $partA = $partB = '';
    foreach ($blocks as $i => $s) {
        if (!$s->parentNode) continue; // sekce vyprázdněná deduplikací
        if ($i < $cut) $partA .= lpiHtml($doc, $s); else $partB .= lpiHtml($doc, $s);
    }
    $tag = $cc->getAttribute('data-tag');
    $open = '<div class="container"><div' . ($tag !== '' ? ' data-tag="' . he($tag) . '"' : '') . ' class="sections ccontent lpi-body' . ($mid === '' ? ' lpi-body--end' : '') . '">';
    $out = '<main id="content" class="lp-main lp-main--page lpi lpi--' . he(str_replace('_', '-', $page)) . '">' .
        ($bc ? '<div class="container">' . lpiHtml($doc, $bc) . '</div>' : '') .
        $hero .
        ($partA !== '' ? $open . $partA . '</div></div>' : '') .
        $mid .
        ($partB !== '' ? '<div class="container"><div class="ccontent lpi-body lpi-body--end">' . $partB . '</div></div>' : '') .
        '</main>' . renderLpSticky($TC);
    return substr($html, 0, $a) . lpiFinish($out) . substr($html, $b + 7);
}

/**
 * Hero panel: H1 + intro + CTA (případné horní tlačítko stránky jako primární) + chipy. Prvky vyjme z DOM.
 * Vrací [html, [[kanonická cesta, popisek] tlačítek]] — pro deduplikaci CTA v obsahu.
 */
function lpiHero($doc, $x, $h1, $page, $L, $TC, $motos, $opt) {
    $par = $h1->parentNode;
    $lead = $top = null;
    for ($n = $h1->nextSibling; $n; $n = $n->nextSibling) {
        if (!($n instanceof DOMElement)) continue;
        if ($n->nodeName !== 'p' && !lpiHas($n, 'lpi-p')) break;
        $btn = $x->query('.//a[contains(concat(" ",normalize-space(@class)," ")," btn ")]', $n)->item(0);
        if ($btn && lpiText($n) === lpiText($btn)) { if (!$top) { $top = $btn; $topP = $n; } continue; }
        if (!$lead && lpiText($n) !== '') { $lead = $n; continue; }
        break;
    }
    if (!$h1->getAttribute('id')) $h1->setAttribute('id', 'lpi-h1');
    $h1Id = $h1->getAttribute('id');
    $h1Plain = lpiText($h1);
    $txt = lpiHtml($doc, $h1);
    $par->removeChild($h1);
    if ($lead) {
        lpiAdd($lead, 'lp-lead lpi-lead');
        $lead->setAttribute('data-lpi-clamp', '');
        $lead->setAttribute('data-more', lpS($L['read_more'] ?? ''));
        $lead->setAttribute('data-less', lpS($L['read_less'] ?? ''));
        $txt .= lpiHtml($doc, $lead);
        $lead->parentNode->removeChild($lead);
    }
    if ($top) {
        $top->setAttribute('class', 'lp-btn lp-btn-primary');
        $top->insertBefore(lpiMark($doc, 'cal'), $top->firstChild);
        $ctas = [[lpiPath($top->getAttribute('href')), lpiText($top)]];
        $primary = lpiHtml($doc, $top);
        $topP->parentNode->removeChild($topP);
    } else {
        $ctas = [['/rezervace', lpPlain($L['cta_primary'] ?? '')]];
        $primary = '<a class="lp-btn lp-btn-primary" href="/rezervace">' . lpIcon('cal') . '<span>' . he($ctas[0][1]) . '</span></a>';
    }
    $call = !empty($opt['call']);
    $ctas[] = [$call ? PHONE_LINK : '/katalog', lpPlain($L[$call ? 'cta_call' : 'cta_secondary'] ?? '')];
    $secondary = '<a class="lp-btn lp-btn-ghost" href="' . he($ctas[1][0]) . '">' . ($call ? lpiIcon('phone') : lpIcon('moto')) . '<span>' . he($ctas[1][1]) . '</span></a>';
    if ($par instanceof DOMElement && $par->nodeName === 'section' && lpiText($par) === '' && !$x->query('.//img|.//iframe', $par)->length) {
        $par->parentNode->removeChild($par);
    }
    $chips = '';
    $min = lpMinPrice($motos);
    if ($min > 0 && lpS($TC['price_chip'] ?? '') !== '') $chips .= '<li class="lp-chip lp-chip--hot">' . he(str_replace('{price}', lpMoneyFrom($min), lpS($TC['price_chip']))) . '</li>';
    $seen = (array)($opt['skip'] ?? []);
    foreach ((array)($L['chips'][$page] ?? []) as $c) {
        $k = mb_strtolower(lpPlain($c));
        if ($k === '' || isset($seen[$k])) continue;
        $seen[$k] = 1;
        $chips .= '<li class="lp-chip">' . lpIcon('check') . '<span>' . he(lpPlain($c)) . '</span></li>';
    }
    $bg = '';
    if (isset(LPI_BG[$page])) {
        $src = LPI_BG[$page];
        $set = strpos($src, 'hero-banner') !== false ? ' srcset="/gfx/hero-banner-480.webp 480w, /gfx/hero-banner-768.webp 768w, /gfx/hero-banner-1500.webp 1500w" sizes="(min-width:900px) 60vw, 100vw"' : '';
        $bg = '<img class="lp-panel-bg" src="/' . he($src) . '"' . $set . ' alt="' . he($h1Plain) . '" aria-hidden="true" decoding="async" fetchpriority="low">';
    }
    $assure = lpPlain($TC['assurance'] ?? '') !== '' ? '<p class="lp-assure">' . lpIcon('check') . he(lpPlain($TC['assurance'])) . '</p>' : '';
    $rating = function_exists('lpPanelRating') ? lpPanelRating($TC) : '';
    // Bez sekce recenzí na stránce vede hodnocení na recenze na úvodní stránce (kotva by jinak nikam nevedla)
    if (empty($opt['reviews'])) $rating = str_replace('href="#lp-reviews-h"', 'href="/#lp-reviews-h"', $rating);
    return ['<section class="lp-panel lpi-hero' . ($bg ? ' lp-panel--bg' : '') . '" aria-labelledby="' . he($h1Id) . '"><div class="container"><div class="lp-panel-card">' . $bg .
        '<div class="lp-panel-text">' . $txt . '</div>' .
        '<div class="lp-cta-row" data-lp-sentinel>' . $primary . $secondary . $assure . $rating . '</div>' .
        ($chips !== '' ? '<ul class="lp-chips">' . $chips . '</ul>' : '') .
        '</div></div></section>', $ctas];
}
