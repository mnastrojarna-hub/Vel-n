<?php
// ===== MotoGo24 Web PHP — Landing v2: render sekcí (viz landing.php) =====
// Odvozené hodnoty (cena v chipu / USP) nemají data-cms-key — inline editace
// by do CMS uložila vypočtenou cenu místo šablony {price}.

/** CMS admin (inline editace) — editovatelné prvky pak dostanou originální hodnotu. */
function lpAdmin() {
    return function_exists('mgCmsAdminValid') && mgCmsAdminValid();
}

/** Nadpis sekce: prázdný → nic (a sekce bez aria-labelledby). Vrací [h2Html, ariaAttr]. */
function lpH2($id, $title, $key) {
    if (lpPlain($title) === '' && !lpAdmin()) return ['', ''];
    return ['<h2 id="' . $id . '" data-cms-key="' . he($key) . '">' . sanitizeHtml(lpS($title)) . '</h2>', ' aria-labelledby="' . $id . '"'];
}

/**
 * Akční panel hned pod hero. Mobil: H1 → lead → 2 CTA → chipy; desktop: text vlevo, CTA vpravo.
 * $o: h1, h1Key, lead, leadKey, priceChip, primary{label,href}, secondary{…}, chips[], keyBase, bg, rating (HTML z lpPanelRating)
 */
function renderLpPanel($o) {
    $kb = $o['keyBase'];
    $p = (array)($o['primary'] ?? []);
    $s = (array)($o['secondary'] ?? []);
    $chips = '';
    if (!empty($o['priceChip'])) $chips .= '<li class="lp-chip lp-chip--hot">' . he($o['priceChip']) . '</li>';
    foreach ((array)($o['chips'] ?? []) as $i => $c) {
        if (lpPlain($c) === '') continue;
        $chips .= '<li class="lp-chip">' . lpIcon('check') . '<span data-cms-key="' . $kb . '.chips.' . $i . '">' . he(lpPlain($c)) . '</span></li>';
    }
    $h1Plain = lpPlain($o['h1'] ?? '');
    $bg = !empty($o['bg']) ? '<img class="lp-panel-bg" src="' . he($o['bg']) . '" alt="' . he($h1Plain) . '" aria-hidden="true" decoding="async" fetchpriority="low">' : '';
    $lead = lpPlain($o['lead'] ?? '') !== '' ? '<p class="lp-lead" data-cms-key="' . he($o['leadKey'] ?? '') . '">' . sanitizeHtml(lpS($o['lead'])) . '</p>' : '';
    return '<section class="lp-panel' . ($bg ? ' lp-panel--bg' : '') . '" aria-labelledby="lp-h1"><div class="container"><div class="lp-panel-card">' . $bg .
        '<div class="lp-panel-text"><h1 id="lp-h1" data-cms-key="' . he($o['h1Key']) . '">' . sanitizeHtml(lpS($o['h1'] ?? '')) . '</h1>' . $lead . '</div>' .
        '<div class="lp-cta-row" data-lp-sentinel>' .
            '<a class="lp-btn lp-btn-primary" href="' . he(lpS($p['href'] ?? '') ?: '/rezervace') . '">' . lpIcon('cal') . '<span data-cms-key="' . $kb . '.cta_primary.label">' . he(lpPlain($p['label'] ?? '')) . '</span></a>' .
            '<a class="lp-btn lp-btn-ghost" href="' . he(lpS($s['href'] ?? '') ?: '/katalog') . '">' . lpIcon('moto') . '<span data-cms-key="' . $kb . '.cta_secondary.label">' . he(lpPlain($s['label'] ?? '')) . '</span></a>' .
            (lpPlain($o['assurance'] ?? '') !== '' ? '<p class="lp-assure" data-cms-key="web.landing.common.assurance">' . lpIcon('check') . he(lpPlain($o['assurance'])) . '</p>' : '') .
            ($o['rating'] ?? '') .
        '</div>' .
        ($chips ? '<ul class="lp-chips">' . $chips . '</ul>' : '') .
        (lpPlain($o['season'] ?? '') !== '' ? '<p class="lp-season" data-cms-key="web.landing.common.season_note">' . lpIcon('cal') . he(lpPlain($o['season'])) . '</p>' : '') .
        '</div></div></section>';
}

/** Kompaktní karta motorky pro karusel. */
function renderLpMotoCard($m, $T) {
    normalizeMoto($m);
    $imgRaw = ($m['image_url'] ?? '') ?: ($m['images'][0] ?? '');
    $model = trim(lpS($m['model'] ?? '')) ?: t('card.unnamedMotorcycle');
    $price = getMinPrice($m);
    $badge = '';
    $st = $m['status'] ?? '';
    $next = $m['next_available_date'] ?? null;
    if (($st === 'active' || $st === 'maintenance') && $next && $next > date('Y-m-d')) {
        $fmt = (function_exists('i18nDetectLanguage') && in_array(i18nDetectLanguage(), ['cs', 'de', 'pl', 'uk'], true)) ? 'd.m.' : 'd/m';
        $badge = '<span class="lp-moto-badge lp-moto-badge--later">' . te('card.availableFrom', ['date' => date($fmt, strtotime($next))]) . '</span>';
    } elseif ($st === 'active' && empty($m['available_unknown'])) {
        $badge = '<span class="lp-moto-badge"><i aria-hidden="true"></i>' . te('card.availableToday') . '</span>';
    }
    $meta = [];
    $branch = is_array($m['branches'] ?? null) ? trim(preg_replace('/^MotoGo24\s*/i', '', lpS($m['branches']['name'] ?? ''))) : '';
    if ($branch !== '') $meta[] = lpIcon('pin') . he($branch);
    $lic = array_values(array_diff(motoLicenseGroups($m), ['N']));
    if ($lic) $meta[] = he(str_replace('{g}', implode('/', $lic), lpS($T['license'])));
    elseif (motoLicenseGroups($m)) $meta[] = he(lpS($T['license_none'] ?? ''));
    $cat = categoryLabel($m['category'] ?? '');
    $id = he($m['id'] ?? '');
    return '<li class="lp-moto"><a class="lp-moto-link" href="/katalog/' . $id . '">' .
        '<div class="lp-moto-img"><img src="' . he(imgUrlSized($imgRaw, 600)) . '" srcset="' . he(imgSrcset($imgRaw, [400, 600, 900])) . '" sizes="(max-width:560px) 76vw, (max-width:768px) 44vw, 290px" alt="' . he(t('common.motorcycleAlt', ['model' => $model])) . '" loading="lazy" decoding="async" width="600" height="400">' .
        $badge . ($cat !== '' ? '<span class="lp-moto-cat">' . he($cat) . '</span>' : '') . '</div>' .
        '<div class="lp-moto-body"><h3>' . he($model) . '</h3>' .
        ($meta ? '<p class="lp-moto-meta">' . implode('<span aria-hidden="true">·</span>', $meta) . '</p>' : '') .
        '<p class="lp-moto-price">' . ($price > 0 ? '<span class="lp-moto-from">' . he(str_replace('{price}', lpMoneyFrom($price), lpS($T['fleet_from']))) . '</span> <span class="lp-moto-pd">' . he(lpS($T['fleet_per_day'])) . '</span>' : '') .
        '</p></div></a>' .
        // Rychlá rezervace rovnou s předvybranou motorkou (sourozenec karty, ne vnořený odkaz)
        '<a class="lp-moto-book" href="/rezervace?moto=' . $id . '">' . he(lpPlain($T['card_book'] ?? '')) . '</a></li>';
}

/** Swipe karusel flotily + chipy kategorií (odkazy na katalog). */
function renderLpFleet($motos, $T) {
    $fleet = lpFleet($motos);
    if (!$fleet) return '';
    // Pořadí: střídavě po kategoriích (pestrost hned na prvních kartách místo
    // 4 nejdražších cestovních), v kategorii pořadí z Velínu; dětské na konec.
    $byCat = [];
    foreach ($fleet as $m) $byCat[lpS($m['category'] ?? '')][] = $m;
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
    $chips = '<a class="lp-cat is-on" href="/katalog">' . he(lpS($T['fleet_all_cats'])) . ' <span class="lp-cat-p">' . count($fleet) . '</span></a>';
    foreach ($byCat as $c => $list) {
        if ($c === '') continue;
        $min = 0;
        foreach ($list as $m) { $p = getMinPrice($m); if ($p > 0 && ($min === 0 || $p < $min)) $min = $p; }
        $chips .= '<a class="lp-cat" href="' . he(lpCategoryHref($c)) . '">' . he(categoryLabel($c)) .
            ($min > 0 ? ' <span class="lp-cat-p">' . he(str_replace('{price}', lpMoneyFrom($min), lpS($T['fleet_from']))) . '</span>' : '') . '</a>';
    }
    $cards = '';
    foreach ($ordered as $m) $cards .= renderLpMotoCard($m, $T);
    $cards .= '<li class="lp-moto lp-moto--all"><a href="/katalog"><span>' . he(str_replace('{n}', (string)count($fleet), lpS($T['fleet_all_card']))) . '</span>' . lpIcon('arrow') . '</a></li>';
    return '<section class="lp-fleet" aria-labelledby="catalogue"><div class="container">' .
        '<div class="lp-head"><h2 id="catalogue" data-cms-key="web.landing.common.fleet_title">' . he(lpPlain($T['fleet_title'])) . '</h2>' .
        '<a class="lp-head-link" href="/katalog"><span data-cms-key="web.landing.common.fleet_all">' . he(lpPlain($T['fleet_all'])) . '</span>' . lpIcon('arrow') . '</a></div>' .
        '<nav class="lp-cats" aria-label="' . he(lpPlain($T['fleet_title'])) . '">' . $chips . '</nav></div>' .
        '<div class="lp-track-wrap"><button type="button" class="lp-nav lp-nav-prev" aria-label="' . he(lpS($T['fleet_prev'])) . '" hidden>' . lpIcon('arrow') . '</button>' .
        '<ul class="lp-track" data-lp-track>' . $cards . '</ul>' .
        '<button type="button" class="lp-nav lp-nav-next" aria-label="' . he(lpS($T['fleet_next'])) . '" hidden>' . lpIcon('arrow') . '</button></div>' .
        '<div class="container"><div class="lp-progress" aria-hidden="true"><i></i></div>' . lpFxNote($T) . '</div></section>';
}

/** USP dlaždice. $items: [{icon,title,text,price?}], $keyBase CMS (web.landing.home.usp / web.pujcovna.benefits.items). */
function renderLpUsp($title, $titleKey, $items, $keyBase, $minPrice = 0) {
    $html = '';
    foreach ((array)$items as $i => $u) {
        if (!is_array($u)) continue;
        $isPrice = !empty($u['price']);
        if ($isPrice && $minPrice <= 0) continue;
        $ttl = lpS($u['title'] ?? '');
        if ($isPrice) $ttl = str_replace('{price}', lpMoneyFrom($minPrice), $ttl);
        if (lpPlain($ttl) === '') continue;
        $icon = !empty($u['icon']) ? '<span class="lp-usp-ico"><img src="/' . he(ltrim(lpS($u['icon']), '/')) . '" alt="' . he(lpPlain($ttl)) . '" aria-hidden="true" loading="lazy" width="40" height="40"></span>' : '';
        $html .= '<li class="lp-usp-item' . ($isPrice ? ' lp-usp-item--hot' : '') . ' lp-reveal" style="--i:' . (int)$i . '">' . $icon .
            '<span class="lp-usp-t"' . ($isPrice ? '' : ' data-cms-key="' . $keyBase . '.' . $i . '.title"') . '>' . sanitizeHtml($ttl) . '</span>' .
            (lpPlain($u['text'] ?? '') !== '' ? '<span class="lp-usp-s" data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml(lpS($u['text'])) . '</span>' : '') . '</li>';
    }
    if ($html === '') return '';
    [$h2, $aria] = lpH2('lp-usp-h', $title, $titleKey);
    return '<section class="lp-usp"' . $aria . '><div class="container">' . $h2 . '<ul class="lp-usp-grid">' . $html . '</ul></div></section>';
}

/** Kroky jako kompaktní časová osa (číslo kroku vykreslí CSS, z titulku se „1.“ odstraní). */
function renderLpSteps($title, $titleKey, $steps, $keyBase) {
    $html = '';
    $n = 0;
    foreach ((array)$steps as $i => $s) {
        if (!is_array($s)) continue;
        $ttl = trim(preg_replace('/^\s*\d+\.\s*/u', '', lpPlain($s['title'] ?? '')));
        if ($ttl === '' && lpPlain($s['text'] ?? '') === '') continue;
        $n++;
        $icon = !empty($s['icon']) ? '<img src="/' . he(ltrim(lpS($s['icon']), '/')) . '" alt="' . he($ttl) . '" aria-hidden="true" loading="lazy" width="36" height="36">' : '';
        $h3 = lpAdmin() ? sanitizeHtml(lpS($s['title'] ?? '')) : he($ttl);
        $html .= '<li class="lp-step lp-reveal" style="--i:' . (int)$i . '" id="krok-' . $n . '"><span class="lp-step-n">' . $n . '</span>' .
            '<div class="lp-step-body">' . $icon . '<h3 data-cms-key="' . $keyBase . '.' . $i . '.title">' . $h3 . '</h3>' .
            '<p data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml(lpS($s['text'] ?? '')) . '</p></div></li>';
    }
    if ($html === '') return '';
    [$h2, $aria] = lpH2('lp-process', $title, $titleKey);
    return '<section class="lp-steps"' . $aria . '><div class="container"><div class="lp-steps-card">' . $h2 .
        '<ol class="lp-steps-list">' . $html . '</ol></div></div></section>';
}

/** Kompaktní rozcestník (ikona + název). $items: [{icon,title,btn,href}] */
function renderLpExplore($title, $titleKey, $items, $keyBase) {
    $html = '';
    foreach ((array)$items as $i => $s) {
        if (!is_array($s)) continue;
        $label = lpPlain($s['title'] ?? '') ?: lpPlain($s['btn'] ?? '');
        if ($label === '') continue;
        $href = lpS($s['href'] ?? '') ?: '/';
        if ($href === '/jak-pujcit') $href = '/jak-pujcit/postup'; // bez 301 hopu
        $icon = lpS($s['icon'] ?? '') !== '' ? '<img src="/' . he(ltrim(lpS($s['icon']), '/')) . '" alt="' . he($label) . '" aria-hidden="true" loading="lazy" width="32" height="32">' : '';
        $html .= '<li><a href="' . he($href) . '">' . $icon . '<span data-cms-key="' . $keyBase . '.' . $i . '.title">' . he($label) . '</span></a></li>';
    }
    if ($html === '') return '';
    [$h2, $aria] = lpH2('signpost-h', $title, $titleKey);
    return '<section class="lp-explore"' . $aria . '><div class="container">' . $h2 . '<ul>' . $html . '</ul></div></section>';
}

/** SEO text dole — v DOM celý (indexovatelný), JS ho sbalí s „Číst dál“. */
function renderLpMore($title, $titleKey, $bodyHtml, $T, $id = 'lp-more') {
    if (lpPlain($bodyHtml) === '') return '';
    [$h2, $aria] = lpH2($id . '-h', $title, $titleKey);
    return '<section class="lp-more"' . $aria . ' data-lp-more><div class="container"><div class="lp-more-card">' . $h2 .
        '<div class="lp-more-body" id="' . $id . '-b">' . $bodyHtml . '</div>' .
        '<button type="button" class="lp-more-btn" aria-controls="' . $id . '-b" aria-expanded="true" data-open="' . he(lpS($T['more_open'])) . '" data-close="' . he(lpS($T['more_close'])) . '" hidden>' . he(lpS($T['more_close'])) . '</button>' .
        '</div></div></section>';
}

/** Sticky spodní CTA lišta (jen mobil; zobrazí JS po odscrollování akčního panelu). */
function renderLpSticky($T, $primaryHref = '/rezervace', $secondaryHref = '/katalog') {
    return '<div class="lp-sticky" data-lp-sticky aria-hidden="true">' .
        '<a class="lp-btn lp-btn-primary" href="' . he($primaryHref) . '" tabindex="-1">' . lpIcon('cal') . '<span>' . he(lpS($T['sticky_reserve'])) . '</span></a>' .
        '<a class="lp-btn lp-btn-ghost" href="' . he($secondaryHref) . '" tabindex="-1">' . lpIcon('moto') . '<span>' . he(lpS($T['sticky_motos'])) . '</span></a></div>';
}

/** CTA pás — data jako legacy renderCta() ($C['cta']), první tlačítko velké. */
function renderLpCta($cta, $keyBase) {
    $btns = '';
    $first = true;
    foreach ((array)($cta['buttons'] ?? []) as $i => $b) {
        if (!is_array($b) || lpPlain($b['label'] ?? '') === '') continue;
        $btns .= '<a class="lp-btn ' . ($first ? 'lp-btn-primary' : 'lp-btn-ghost') . '" href="' . he(lpS($b['href'] ?? '') ?: '/rezervace') . '">' .
            ($first ? lpIcon('cal') : '') . '<span data-cms-key="' . $keyBase . '.buttons.' . $i . '.label">' . sanitizeHtml(lpS($b['label'])) . '</span></a>';
        $first = false;
    }
    [$h2, $aria] = lpH2('lp-cta-h', $cta['title'] ?? '', $keyBase . '.title');
    if ($btns === '' && $h2 === '') return '';
    return '<section class="lp-cta"' . $aria . '><div class="container"><div class="lp-cta-card">' . $h2 .
        (lpPlain($cta['text'] ?? '') !== '' ? '<p data-cms-key="' . $keyBase . '.text">' . sanitizeHtml(lpS($cta['text'])) . '</p>' : '') .
        ($btns !== '' ? '<div class="lp-cta-btns">' . $btns . '</div>' : '') . '</div></div></section>';
}

/** Blog jako swipe řada kompaktních karet. $bl = $C['blog'] (title, cta_href, limit). */
function renderLpBlog($posts, $bl, $T) {
    if (empty($posts)) return '';
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $limit = (int)($bl['limit'] ?? 3) ?: 3;
    $cards = '';
    $shown = 0;
    foreach ((array)$posts as $p) {
        if (!is_array($p) || $shown >= $limit) continue;
        // Na cizím jazyce nepřeložené (české) články vynecháme
        if ($lang !== 'cs' && lpPlain(lpTr($p)[$lang]['title'] ?? '') === '') continue;
        $shown++;
        $title = lpPlain(localized($p, 'title')) ?: t('card.unnamedArticle');
        $img = lpS((!empty($p['images'][0]) ? $p['images'][0] : '') ?: ($p['image_url'] ?? ''));
        if ($img && strpos($img, 'http') !== 0) $img = BASE_URL . '/' . ltrim($img, '/'); elseif ($img) $img = imgUrlSized($img, 600);
        $cards .= '<li class="lp-blog-card"><a href="/blog/' . he($p['slug'] ?? '') . '">' .
            '<div class="lp-blog-img">' . ($img ? '<img src="' . he($img) . '" alt="' . he(t('common.blogAlt', ['title' => $title])) . '" loading="lazy" decoding="async" width="600" height="375">' : '') . '</div>' .
            '<h3>' . he($title) . '</h3></a></li>';
    }
    if ($cards === '') return '';
    [$h2, $aria] = lpH2('blog', $bl['title'] ?? '', 'web.home.blog.title');
    return '<section class="lp-blog"' . $aria . '><div class="container"><div class="lp-head">' . $h2 .
        '<a class="lp-head-link" href="' . he(lpS($bl['cta_href'] ?? '') ?: '/blog') . '"><span>' . he(lpPlain($T['fleet_all'])) . '</span>' . lpIcon('arrow') . '</a></div></div>' .
        '<ul class="lp-track lp-track--blog">' . $cards . '</ul></section>';
}

/**
 * Hero slideshow (JS varianta) — fotky/plakáty slidů 2+ se nestahují hned
 * (dřív ~27 obrázků / 7 MB na mobilu i u neviditelných slidů), ale až těsně
 * před zobrazením: src/srcset/poster → data-lp-*, JS je doplní pro aktivní
 * a dva následující slidy. Když se kotva v JS z home.php změní, nic nepřepisuje.
 */
function lpHeroLazy($slidesHtml, $heroJs) {
    $anchor = 'function show(i){clearT();';
    if (strpos($heroJs, $anchor) === false) return [$slidesHtml, $heroJs];
    $parts = preg_split('/(?=<div class="mg-hero-slide)/', $slidesHtml);
    $out = '';
    $n = 0;
    foreach ($parts as $p) {
        if (strpos($p, '<div class="mg-hero-slide') === 0 && $n++ > 0) {
            $p = preg_replace('/ (src|srcset|poster)="/', ' data-lp-$1="', $p);
        }
        $out .= $p;
    }
    $hy = 'function hy(el){if(!el)return;Array.prototype.forEach.call(el.querySelectorAll("[data-lp-src],[data-lp-srcset],[data-lp-poster]"),function(m){'
        . '["srcset","src","poster"].forEach(function(a){var v=m.getAttribute("data-lp-"+a);if(v!==null){m.setAttribute(a,v);m.removeAttribute("data-lp-"+a);}});});}';
    $js = str_replace($anchor, $hy . 'function show(i){hy(sl[i]);hy(sl[(i+1)%sl.length]);hy(sl[(i+2)%sl.length]);clearT();', $heroJs);
    return [$out, $js];
}

/** Pruh s nabídkou (např. sleva za vyzvednutí od 12:00) — jen když je text vyplněný. */
function renderLpOffer($T) {
    if (lpPlain($T['offer'] ?? '') === '') return '';
    return '<aside class="lp-offer"><div class="container"><p class="lp-offer-in" data-cms-key="web.landing.common.offer"><span class="lp-offer-pct" aria-hidden="true">%</span><span>' . he(lpPlain($T['offer'])) . '</span></p></div></aside>';
}
