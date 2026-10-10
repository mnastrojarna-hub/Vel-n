<?php
// ===== MotoGo24 Web PHP — Landing v2 (mobilní, konverzní rozvržení) =====
// Nové pořadí sekcí pro klíčové stránky (/ a /pujcovna-motorek): hero bez
// tlačítek → akční panel (H1 + 2 CTA + USP chipy) → swipe karusel motorek →
// USP dlaždice → kroky → CTA → FAQ → … → SEO text sbalený dole.
// Zapíná se per jazyk (LANDING_V2_LANGS) — nejdřív jen ES na schválení,
// pak rozšířit o další jazyky. ?landing=v2 / ?landing=v1 = náhled/vypnutí
// pro libovolný jazyk (page cache má query v klíči, canonical se nemění).
// Texty: siteContent('landing') — CS defaulty níže, překlady lang/pages_<lang>.php
// ('pages.landing'), Velín CMS klíče web.landing.*.

const LANDING_V2_LANGS = ['es'];

function landingV2Enabled() {
    static $on = null;
    if ($on !== null) return $on;
    $q = isset($_GET['landing']) ? (string)$_GET['landing'] : '';
    if ($q === 'v2') return $on = true;
    if ($q === 'v1') return $on = false;
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    return $on = in_array($lang, LANDING_V2_LANGS, true);
}

/** Assety v2 pro renderPage() meta. */
function lpPageMeta() {
    return ['styles' => ['/css/landing.css'], 'scripts' => ['/js/landing.js'], 'body_class' => 'lp-v2'];
}

/** CS defaulty textů v2 (master pro překlad). */
function lpDefaults() {
    return [
        'common' => [
            'usp_title' => 'Proč MotoGo24',
            'fleet_title' => 'Vyber si motorku',
            'fleet_all' => 'Zobrazit vše',
            'fleet_all_card' => 'Všech {n} motorek v katalogu',
            'fleet_from' => 'od {price}',
            'fleet_per_day' => '/ den',
            'fleet_all_cats' => 'Vše',
            'fleet_prev' => 'Předchozí motorky',
            'fleet_next' => 'Další motorky',
            'license' => 'ŘP {g}',
            'explore_title' => 'Prozkoumej MotoGo24',
            'more_open' => 'Číst dál',
            'more_close' => 'Zobrazit méně',
            'sticky_reserve' => 'Rezervovat',
            'sticky_motos' => 'Motorky',
            'price_chip' => 'Motorky od {price} / den',
        ],
        'home' => [
            // Krátký H1 do akčního panelu (prázdné = H1 z web.home.h1; pak dlouhé H1 → H2 sekce „O nás“)
            'h1' => '',
            'lead' => '',
            'cta_primary' => ['label' => 'REZERVOVAT', 'href' => '/rezervace'],
            'cta_secondary' => ['label' => 'VYBRAT MOTORKU', 'href' => '/katalog'],
            'chips' => ['Bez kauce', 'Výbava v ceně', 'Vyzvednutí nonstop'],
            'usp' => [
                ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'a bez skrytých poplatků'],
                ['icon' => 'gfx/vyber-vybavu.svg', 'title' => 'Výbava v ceně', 'text' => 'helma, bunda, kalhoty a rukavice'],
                ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop', 'text' => 'vyzvednutí i vrácení dle rezervace'],
                ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => 'Bez limitu km', 'text' => 'i do zahraničí'],
                ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online rezervace', 'text' => 'na pár kliknutí'],
                ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Od {price}', 'text' => 'za den', 'price' => true],
            ],
            'about_title' => 'O půjčovně MotoGo24',
        ],
        'pujcovna' => [
            'lead' => 'Bez kauce, s výbavou v ceně a vyzvednutím nonstop. Rezervuj online na pár kliknutí.',
            'cta_primary' => ['label' => 'REZERVOVAT', 'href' => '/rezervace'],
            'cta_secondary' => ['label' => 'VYBRAT MOTORKU', 'href' => '/katalog'],
            'chips' => ['Bez kauce', 'Výbava v ceně', 'Vyzvednutí nonstop'],
            'about_title' => 'Více o naší půjčovně',
        ],
    ];
}

/** Sloučené texty v2 (CS default ← jazykový overlay ← DB ← Velín CMS). */
function lpTexts($sb) {
    static $c = null;
    if ($c === null) $c = $sb->siteContent('landing', lpDefaults());
    return $c;
}

/** Cena „od“ bez haléřů/centů — zaokrouhleno NAHORU (nikdy nižší než skutečná). */
function lpMoneyFrom($czk) {
    $czk = (float)$czk;
    if ($czk <= 0) return '';
    if (!function_exists('currencyConvert') || !function_exists('currencyDetect')) return formatPrice($czk);
    $cur = strtoupper(currencyDetect());
    $meta = CURRENCY_META[$cur] ?? CURRENCY_META['CZK'];
    $v = currencyConvert($czk, $cur);
    if ($v === null) return formatPrice($czk);
    return number_format(ceil((float)$v), 0, ',', "\u{00A0}") . "\u{00A0}" . $meta['symbol'];
}

/** Motorky pro karusel — bez kategorie „ostatní“ (vozík) a bez fotky. */
function lpFleet($motos) {
    $out = [];
    foreach ((array)$motos as $m) {
        if (!is_array($m) || ($m['category'] ?? '') === 'ostatni') continue;
        if (empty($m['image_url']) && empty($m['images'][0])) continue;
        $out[] = $m;
    }
    return $out;
}

/** Cenová kotva „od X / den“ — bez dětských motorek (jinak by lákala na cenu, kterou dospělý nedostane). */
function lpMinPrice($motos) {
    $min = 0;
    foreach (lpFleet($motos) as $m) {
        if (($m['category'] ?? '') === 'detske') continue;
        $p = getMinPrice($m);
        if ($p > 0 && ($min === 0 || $p < $min)) $min = $p;
    }
    return $min;
}

function lpIcon($name) {
    $p = [
        'cal' => '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>',
        'moto' => '<circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5 9 10h5l4.5 6.5M14 10l-2-4h3M9 10l-1.5-2.5"/>',
        'check' => '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
        'arrow' => '<path d="M5 12h14M13 6l6 6-6 6"/>',
        'pin' => '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
    ];
    return '<svg class="lp-ico" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . ($p[$name] ?? '') . '</svg>';
}

/**
 * Akční panel hned pod hero (H1 + 2 výrazná CTA + USP chipy).
 * $o: h1, h1Key, lead, leadKey, primary{label,href}, secondary{…}, chips[], keyBase, bg (URL fotky na pozadí — volitelně)
 */
function renderLpPanel($o) {
    $kb = $o['keyBase'];
    $p = $o['primary']; $s = $o['secondary'];
    $chips = '';
    if (!empty($o['priceChip'])) {
        $chips .= '<li class="lp-chip lp-chip--hot"><span data-cms-key="web.landing.common.price_chip">' . htmlspecialchars($o['priceChip']) . '</span></li>';
    }
    foreach ((array)($o['chips'] ?? []) as $i => $c) {
        if (!is_string($c) || trim($c) === '') continue;
        $chips .= '<li class="lp-chip">' . lpIcon('check') . '<span data-cms-key="' . $kb . '.chips.' . $i . '">' . htmlspecialchars($c) . '</span></li>';
    }
    $bg = !empty($o['bg']) ? '<img class="lp-panel-bg" src="' . htmlspecialchars($o['bg']) . '" alt="" aria-hidden="true" decoding="async" fetchpriority="high">' : '';
    return '<section class="lp-panel' . ($bg ? ' lp-panel--bg' : '') . '" aria-labelledby="lp-h1"><div class="container"><div class="lp-panel-card">' . $bg .
        '<div class="lp-panel-text"><h1 id="lp-h1" data-cms-key="' . htmlspecialchars($o['h1Key']) . '">' . sanitizeHtml($o['h1']) . '</h1>' .
        (!empty($o['lead']) ? '<p class="lp-lead" data-cms-key="' . htmlspecialchars($o['leadKey']) . '">' . sanitizeHtml($o['lead']) . '</p>' : '') .
        ($chips ? '<ul class="lp-chips">' . $chips . '</ul>' : '') . '</div>' .
        '<div class="lp-cta-row" data-lp-sentinel>' .
            '<a class="lp-btn lp-btn-primary" href="' . htmlspecialchars($p['href'] ?? '/rezervace') . '">' . lpIcon('cal') . '<span data-cms-key="' . $kb . '.cta_primary.label">' . htmlspecialchars($p['label'] ?? '') . '</span></a>' .
            '<a class="lp-btn lp-btn-ghost" href="' . htmlspecialchars($s['href'] ?? '/katalog') . '">' . lpIcon('moto') . '<span data-cms-key="' . $kb . '.cta_secondary.label">' . htmlspecialchars($s['label'] ?? '') . '</span></a>' .
        '</div></div></div></section>';
}

/** Kompaktní karta motorky pro karusel. */
function renderLpMotoCard($m, $T) {
    normalizeMoto($m);
    $imgRaw = ($m['image_url'] ?? '') ?: ($m['images'][0] ?? '');
    $model = trim((string)($m['model'] ?? '')) ?: t('card.unnamedMotorcycle');
    $price = getMinPrice($m);
    $badge = '';
    $st = $m['status'] ?? '';
    $next = $m['next_available_date'] ?? null;
    if (($st === 'active' || $st === 'maintenance') && $next && $next > date('Y-m-d')) {
        $badge = '<span class="lp-moto-badge lp-moto-badge--later">' . te('card.availableFrom', ['date' => date('d.m.', strtotime($next))]) . '</span>';
    } elseif ($st === 'active' && empty($m['available_unknown'])) {
        $badge = '<span class="lp-moto-badge"><i aria-hidden="true"></i>' . te('card.availableToday') . '</span>';
    }
    $meta = [];
    $branch = is_array($m['branches'] ?? null) ? trim(preg_replace('/^MotoGo24\s*/i', '', (string)($m['branches']['name'] ?? ''))) : '';
    if ($branch !== '') $meta[] = lpIcon('pin') . htmlspecialchars($branch);
    $lic = motoLicenseGroups($m);
    if ($lic) $meta[] = htmlspecialchars(str_replace('{g}', implode('/', $lic), (string)$T['license']));
    $cat = categoryLabel($m['category'] ?? '');
    return '<li class="lp-moto"><a href="/katalog/' . htmlspecialchars($m['id'] ?? '') . '">' .
        '<div class="lp-moto-img"><img src="' . htmlspecialchars(imgUrlSized($imgRaw, 600)) . '" srcset="' . htmlspecialchars(imgSrcset($imgRaw, [400, 600, 900])) . '" sizes="(max-width:768px) 78vw, 300px" alt="' . he(t('common.motorcycleAlt', ['model' => $model])) . '" loading="lazy" decoding="async" width="600" height="400">' .
        $badge . ($cat !== '' ? '<span class="lp-moto-cat">' . htmlspecialchars($cat) . '</span>' : '') . '</div>' .
        '<div class="lp-moto-body"><h3>' . htmlspecialchars($model) . '</h3>' .
        ($meta ? '<p class="lp-moto-meta">' . implode('<span aria-hidden="true">·</span>', $meta) . '</p>' : '') .
        '<p class="lp-moto-price">' . ($price > 0 ? '<span class="lp-moto-from">' . htmlspecialchars(str_replace('{price}', lpMoneyFrom($price), (string)$T['fleet_from'])) . '</span> <span class="lp-moto-pd">' . htmlspecialchars($T['fleet_per_day']) . '</span>' : '') .
        '<span class="lp-moto-go">' . lpIcon('arrow') . '</span></p></div></a></li>';
}

/** Swipe karusel flotily + chipy kategorií (odkazy na katalog). */
function renderLpFleet($motos, $T) {
    $fleet = lpFleet($motos);
    if (!$fleet) return '';
    // Pořadí: střídavě po kategoriích (pestrost hned na prvních kartách místo
    // 4 nejdražších cestovních), v kategorii pořadí z Velínu; dětské na konec.
    $byCat = [];
    foreach ($fleet as $m) $byCat[$m['category'] ?? ''][] = $m;
    uksort($byCat, function ($a, $b) use ($byCat) {
        if (($a === 'detske') !== ($b === 'detske')) return $a === 'detske' ? 1 : -1;
        return count($byCat[$b]) <=> count($byCat[$a]);
    });
    $ordered = [];
    for ($i = 0, $left = true; $left; $i++) {
        $left = false;
        foreach ($byCat as $c => $list) {
            if ($c === 'detske') continue;
            if (isset($list[$i])) { $ordered[] = $list[$i]; $left = true; }
        }
    }
    foreach ($byCat['detske'] ?? [] as $m) $ordered[] = $m;
    $chips = '<a class="lp-cat is-on" href="/katalog">' . htmlspecialchars($T['fleet_all_cats']) . ' <b>' . count($fleet) . '</b></a>';
    foreach ($byCat as $c => $list) {
        if ($c === '') continue;
        $min = 0;
        foreach ($list as $m) { $p = getMinPrice($m); if ($p > 0 && ($min === 0 || $p < $min)) $min = $p; }
        $chips .= '<a class="lp-cat" href="/katalog/' . htmlspecialchars($c) . '">' . htmlspecialchars(categoryLabel($c)) .
            ($min > 0 ? ' <b>' . htmlspecialchars(str_replace('{price}', lpMoneyFrom($min), (string)$T['fleet_from'])) . '</b>' : '') . '</a>';
    }
    $cards = '';
    foreach ($ordered as $m) $cards .= renderLpMotoCard($m, $T);
    $cards .= '<li class="lp-moto lp-moto--all"><a href="/katalog"><span>' . htmlspecialchars(str_replace('{n}', (string)count($fleet), (string)$T['fleet_all_card'])) . '</span>' . lpIcon('arrow') . '</a></li>';
    return '<section class="lp-fleet" aria-labelledby="catalogue"><div class="container">' .
        '<div class="lp-head"><h2 id="catalogue" data-cms-key="web.landing.common.fleet_title">' . htmlspecialchars($T['fleet_title']) . '</h2>' .
        '<a class="lp-head-link" href="/katalog"><span data-cms-key="web.landing.common.fleet_all">' . htmlspecialchars($T['fleet_all']) . '</span>' . lpIcon('arrow') . '</a></div>' .
        '<nav class="lp-cats">' . $chips . '</nav></div>' .
        '<div class="lp-track-wrap"><button type="button" class="lp-nav lp-nav-prev" aria-label="' . he($T['fleet_prev']) . '" hidden>' . lpIcon('arrow') . '</button>' .
        '<ul class="lp-track" data-lp-track>' . $cards . '</ul>' .
        '<button type="button" class="lp-nav lp-nav-next" aria-label="' . he($T['fleet_next']) . '" hidden>' . lpIcon('arrow') . '</button></div>' .
        '<div class="container"><div class="lp-progress" aria-hidden="true"><i></i></div></div></section>';
}

/** USP dlaždice. $items: [{icon,title,text,price?}], $keyBase CMS (web.landing.home.usp / web.pujcovna.benefits.items). */
function renderLpUsp($title, $titleKey, $items, $keyBase, $minPrice = 0) {
    $html = '';
    foreach ((array)$items as $i => $u) {
        if (!is_array($u)) continue;
        $isPrice = !empty($u['price']);
        if ($isPrice && $minPrice <= 0) continue;
        $ttl = (string)($u['title'] ?? '');
        if ($isPrice) $ttl = str_replace('{price}', lpMoneyFrom($minPrice), $ttl);
        $icon = !empty($u['icon']) ? '<span class="lp-usp-ico"><img src="/' . htmlspecialchars(ltrim($u['icon'], '/')) . '" alt="" aria-hidden="true" loading="lazy" width="40" height="40"></span>' : '';
        $html .= '<li class="lp-usp-item' . ($isPrice ? ' lp-usp-item--hot' : '') . ' lp-reveal" style="--i:' . $i . '">' . $icon .
            '<span class="lp-usp-t" data-cms-key="' . $keyBase . '.' . $i . '.title">' . sanitizeHtml($ttl) . '</span>' .
            (!empty($u['text']) ? '<span class="lp-usp-s" data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml($u['text']) . '</span>' : '') . '</li>';
    }
    if ($html === '') return '';
    return '<section class="lp-usp" aria-labelledby="lp-usp-h"><div class="container"><h2 id="lp-usp-h" data-cms-key="' . htmlspecialchars($titleKey) . '">' . htmlspecialchars($title) . '</h2><ul class="lp-usp-grid">' . $html . '</ul></div></section>';
}

/** Kroky jako kompaktní časová osa. */
function renderLpSteps($title, $titleKey, $steps, $keyBase) {
    $html = '';
    $n = 0;
    foreach ((array)$steps as $i => $s) {
        if (!is_array($s)) continue;
        $n++;
        $ttl = trim(preg_replace('/^\s*\d+\.\s*/', '', strip_tags((string)($s['title'] ?? ''))));
        $icon = !empty($s['icon']) ? '<img src="/' . htmlspecialchars(ltrim($s['icon'], '/')) . '" alt="" aria-hidden="true" loading="lazy" width="36" height="36">' : '';
        $html .= '<li class="lp-step lp-reveal" style="--i:' . $i . '" id="krok-' . $n . '"><span class="lp-step-n">' . $n . '</span>' .
            '<div class="lp-step-body">' . $icon . '<h3 data-cms-key="' . $keyBase . '.' . $i . '.title">' . htmlspecialchars($ttl) . '</h3>' .
            '<p data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml((string)($s['text'] ?? '')) . '</p></div></li>';
    }
    if ($html === '') return '';
    return '<section class="lp-steps" aria-labelledby="lp-process"><div class="container"><div class="lp-steps-card">' .
        '<h2 id="lp-process" data-cms-key="' . htmlspecialchars($titleKey) . '">' . sanitizeHtml($title) . '</h2>' .
        '<ol class="lp-steps-list' . ($n > 4 ? ' lp-steps-list--long' : '') . '">' . $html . '</ol></div></div></section>';
}

/** Kompaktní rozcestník (ikona + název). $items: [{icon,title,btn,href}] */
function renderLpExplore($title, $titleKey, $items, $keyBase) {
    $html = '';
    foreach ((array)$items as $i => $s) {
        if (!is_array($s)) continue;
        $label = trim(strip_tags((string)($s['title'] ?? ''))) ?: trim(strip_tags((string)($s['btn'] ?? '')));
        if ($label === '') continue;
        $html .= '<li><a href="' . htmlspecialchars($s['href'] ?? '/') . '"><img src="/' . htmlspecialchars(ltrim((string)($s['icon'] ?? ''), '/')) . '" alt="" aria-hidden="true" loading="lazy" width="32" height="32">' .
            '<span data-cms-key="' . $keyBase . '.' . $i . '.title">' . htmlspecialchars($label) . '</span></a></li>';
    }
    if ($html === '') return '';
    return '<section class="lp-explore" aria-labelledby="signpost-h"><div class="container"><h2 id="signpost-h" data-cms-key="' . htmlspecialchars($titleKey) . '">' . htmlspecialchars($title) . '</h2><ul>' . $html . '</ul></div></section>';
}

/** SEO text dole — v DOM celý (indexovatelný), JS ho sbalí s „Číst dál“. */
function renderLpMore($title, $titleKey, $bodyHtml, $T, $id = 'lp-more') {
    if (trim(strip_tags((string)$bodyHtml)) === '') return '';
    return '<section class="lp-more" aria-labelledby="' . $id . '-h" data-lp-more><div class="container"><div class="lp-more-card">' .
        '<h2 id="' . $id . '-h" data-cms-key="' . htmlspecialchars($titleKey) . '">' . htmlspecialchars($title) . '</h2>' .
        '<div class="lp-more-body" id="' . $id . '-b">' . $bodyHtml . '</div>' .
        '<button type="button" class="lp-more-btn" aria-controls="' . $id . '-b" aria-expanded="true" data-open="' . he($T['more_open']) . '" data-close="' . he($T['more_close']) . '" hidden>' . htmlspecialchars($T['more_close']) . '</button>' .
        '</div></div></section>';
}

/** Sticky spodní CTA lišta (jen mobil; zobrazí JS po odscrollování akčního panelu). */
function renderLpSticky($T, $primaryHref = '/rezervace', $secondaryHref = '/katalog') {
    return '<div class="lp-sticky" data-lp-sticky aria-hidden="true">' .
        '<a class="lp-btn lp-btn-primary" href="' . htmlspecialchars($primaryHref) . '" tabindex="-1">' . lpIcon('cal') . '<span>' . htmlspecialchars($T['sticky_reserve']) . '</span></a>' .
        '<a class="lp-btn lp-btn-ghost" href="' . htmlspecialchars($secondaryHref) . '" tabindex="-1">' . lpIcon('moto') . '<span>' . htmlspecialchars($T['sticky_motos']) . '</span></a></div>';
}

/** CTA pás — data stejná jako legacy renderCta() ($C['cta']), první tlačítko velké. */
function renderLpCta($cta, $keyBase) {
    $btns = '';
    foreach ((array)($cta['buttons'] ?? []) as $i => $b) {
        if (!is_array($b) || trim(strip_tags((string)($b['label'] ?? ''))) === '') continue;
        $btns .= '<a class="lp-btn ' . ($i === 0 ? 'lp-btn-primary' : 'lp-btn-ghost') . '" href="' . htmlspecialchars($b['href'] ?? '/rezervace') . '">' .
            ($i === 0 ? lpIcon('cal') : '') . '<span data-cms-key="' . $keyBase . '.buttons.' . $i . '.label">' . sanitizeHtml((string)$b['label']) . '</span></a>';
    }
    return '<section class="lp-cta" aria-labelledby="lp-cta-h"><div class="container"><div class="lp-cta-card">' .
        '<h2 id="lp-cta-h" data-cms-key="' . $keyBase . '.title">' . sanitizeHtml((string)($cta['title'] ?? '')) . '</h2>' .
        (!empty($cta['text']) ? '<p data-cms-key="' . $keyBase . '.text">' . sanitizeHtml((string)$cta['text']) . '</p>' : '') .
        '<div class="lp-cta-btns">' . $btns . '</div></div></div></section>';
}

/** Blog jako swipe řada kompaktních karet. $bl = $C['blog'] (title, cta_label, cta_href, limit). */
function renderLpBlog($posts, $bl, $T) {
    if (empty($posts)) return '';
    $cards = '';
    foreach (array_slice((array)$posts, 0, max(3, (int)($bl['limit'] ?? 3))) as $p) {
        $title = trim((string)localized($p, 'title')) ?: t('card.unnamedArticle');
        $img = (!empty($p['images'][0]) ? $p['images'][0] : '') ?: ($p['image_url'] ?? '');
        if ($img && strpos($img, 'http') !== 0) $img = BASE_URL . '/' . ltrim($img, '/'); elseif ($img) $img = imgUrlSized($img, 600);
        $cards .= '<li class="lp-blog-card"><a href="/blog/' . htmlspecialchars($p['slug'] ?? '') . '">' .
            '<div class="lp-blog-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . he(t('common.blogAlt', ['title' => $title])) . '" loading="lazy" decoding="async" width="600" height="375">' : '') . '</div>' .
            '<h3>' . htmlspecialchars($title) . '</h3></a></li>';
    }
    return '<section class="lp-blog" aria-labelledby="blog"><div class="container"><div class="lp-head"><h2 id="blog" data-cms-key="web.home.blog.title">' . sanitizeHtml((string)($bl['title'] ?? '')) . '</h2>' .
        '<a class="lp-head-link" href="' . htmlspecialchars($bl['cta_href'] ?? '/blog') . '"><span>' . htmlspecialchars($T['fleet_all']) . '</span>' . lpIcon('arrow') . '</a></div></div>' .
        '<ul class="lp-track lp-track--blog">' . $cards . '</ul></section>';
}

/**
 * Hero slideshow (JS varianta) — fotky/plakáty slidů 2+ se nestahují hned
 * (dřív ~27 obrázků / 7 MB na mobilu i u neviditelných slidů), ale až těsně
 * před zobrazením: src/srcset/poster → data-lp-*, JS je doplní pro aktivní
 * a následující slide.
 */
function lpHeroLazy($slidesHtml, $heroJs) {
    $parts = preg_split('/(?=<div class="mg-hero-slide)/', $slidesHtml);
    $out = '';
    $n = 0;
    foreach ($parts as $p) {
        if (strpos($p, '<div class="mg-hero-slide') === 0) {
            if ($n++ > 0) $p = preg_replace('/ (src|srcset|poster)="/', ' data-lp-$1="', $p);
        }
        $out .= $p;
    }
    $hy = 'function hy(el){if(!el)return;Array.prototype.forEach.call(el.querySelectorAll("[data-lp-src],[data-lp-srcset],[data-lp-poster]"),function(m){'
        . '["srcset","src","poster"].forEach(function(a){var v=m.getAttribute("data-lp-"+a);if(v!==null){m.setAttribute(a,v);m.removeAttribute("data-lp-"+a);}});});}';
    $js = str_replace('function show(i){clearT();', $hy . 'function show(i){hy(sl[i]);hy(sl[(i+1)%sl.length]);clearT();', $heroJs);
    return [$out, $js];
}
