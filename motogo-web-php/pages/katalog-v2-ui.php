<?php
// ===== Katalog v2 — lišta (termín / filtry / kalkulačka), chipy kategorií, panel filtrů,
// aktivní filtry a mřížka kompaktních karet. Data a texty: pages/katalog-v2-lib.php.
// Bez JS: panel = obyčejný GET formulář (stejné parametry jako v1), kategorie = odkazy.
// S JS (js/landing-catalog*.js): okamžité filtrování nad kf-data, bottom sheet / rozbalovací
// panel, filtr termínu s cenou za termín na kartách. CSS: css/landing-catalog*.css.

function kfIcon($n) {
    $p = [
        'sliders' => '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
        'calc' => '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8 11h2M12 11h2M16 11v6M8 15h2M12 15h2M8 18.5h2M12 18.5h2"/>',
        'search' => '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4-4"/>',
        'x' => '<path d="M6 6l12 12M18 6 6 18"/>',
    ];
    if (!isset($p[$n])) return lpIcon($n);
    return '<svg class="lp-ico" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $p[$n] . '</svg>';
}

/** Chip s radio/checkboxem (funguje i bez JS — stav přes :checked). */
function kfChip($type, $name, $val, $label, $on) {
    return '<label class="kf-chip"><input type="' . $type . '" name="' . $name . '" value="' . he($val) . '"' . ($on ? ' checked' : '') . '><span>' . he($label) . '</span></label>';
}

/** Dvojitý posuvník (třídy range-* z main.css). $r = [min, max, boundMin, boundMax]. */
function kfRange($key, $title, $names, $r, $step, $fmt, $aria, $maxLabel = '') {
    $span = max(1, $r[3] - $r[2]);
    $l = round(($r[0] - $r[2]) / $span * 100, 2);
    $rt = round(100 - ($r[1] - $r[2]) / $span * 100, 2);
    $in = function ($i, $cls) use ($names, $r, $step, $aria) {
        return '<input type="range" name="' . $names[$i] . '" class="range-input range-input-' . $cls . '" min="' . $r[2] . '" max="' . $r[3] . '" step="' . $step . '" value="' . $r[$i] . '" aria-label="' . he($aria[$i]) . '">';
    };
    return '<div class="kf-sec kf-range" data-kf-range="' . $key . '"><div class="range-header"><span class="range-title">' . he($title) . '</span>' .
        '<span class="range-value" data-kf-rv>' . he($fmt($r[0]) . ' – ' . ($maxLabel !== '' && $r[1] >= $r[3] ? $maxLabel : $fmt($r[1]))) . '</span></div>' .
        '<div class="range-slider"><div class="range-track"></div><div class="range-fill" style="left:' . $l . '%;right:' . $rt . '%"></div>' . $in(0, 'min') . $in(1, 'max') . '</div>' .
        '<div class="range-bounds"><span>' . he($fmt($r[2])) . '</span><span>' . he($fmt($r[3])) . '</span></div></div>';
}

/** Kompaktní karta motorky (2 sloupce na mobilu). */
function renderKatalogV2Card($m, $T, $hidden, $eager) {
    $imgRaw = ($m['image_url'] ?? '') ?: ($m['images'][0] ?? '');
    $model = trim(lpS($m['model'] ?? '')) ?: t('card.unnamedMotorcycle');
    $id = he($m['id'] ?? '');
    $badge = '';
    $st = $m['status'] ?? '';
    $next = $m['next_available_date'] ?? null;
    if (($st === 'active' || $st === 'maintenance') && $next && $next > date('Y-m-d')) {
        $fmt = (function_exists('i18nDetectLanguage') && in_array(i18nDetectLanguage(), ['cs', 'de', 'pl', 'uk'], true)) ? 'd.m.' : 'd/m';
        $badge = '<span class="kf-badge-av is-later">' . te('card.availableFrom', ['date' => date($fmt, strtotime($next))]) . '</span>';
    } elseif ($st === 'active' && empty($m['available_unknown'])) {
        $badge = '<span class="kf-badge-av"><i aria-hidden="true"></i>' . te('card.availableToday') . '</span>';
    }
    $lg = motoLicenseGroups($m);
    $lic = array_values(array_diff($lg, ['N']));
    $licTxt = $lic ? str_replace('{g}', implode('/', $lic), $T['license']) : ($lg ? $T['license_none'] : '');
    $tags = (($c = categoryLabel($m['category'] ?? '')) !== '' ? '<span class="kf-tag">' . he($c) . '</span>' : '') .
        ($licTxt !== '' ? '<span class="kf-tag kf-tag--lic">' . he($licTxt) . '</span>' : '');
    $specs = '';
    $n = 0;
    foreach (buildShortDescItems($m) as $it) {
        if ($n >= 3 || in_array($it['key'], ['category', 'license_required'], true) || $it['card'] === '') continue;
        $specs .= '<li>' . $it['card'] . '</li>'; // 'card' je už escapované (buildShortDescItems)
        $n++;
    }
    $br = is_array($m['branches'] ?? null) ? trim(preg_replace('/^MotoGo24\s*/i', '', lpS($m['branches']['name'] ?? ''))) : '';
    $price = getMinPrice($m);
    $img = $imgRaw ? '<img src="' . he(imgUrlSized($imgRaw, 600)) . '" srcset="' . he(imgSrcset($imgRaw, [400, 600, 900])) . '" sizes="(max-width:599px) 50vw, (max-width:999px) 33vw, 290px" alt="' .
        he(t('common.motorcycleAlt', ['model' => $model])) . '"' . ($eager ? '' : ' loading="lazy"') . ' decoding="async" width="600" height="400">' : '';
    return '<li class="kf-card" data-id="' . $id . '"' . ($hidden ? ' hidden' : '') . '><a class="kf-card-link" href="' . BASE_URL . '/katalog/' . $id . '">' .
        '<div class="kf-card-img">' . $img . $badge . ($tags ? '<p class="kf-tags">' . $tags . '</p>' : '') . '</div>' .
        '<div class="kf-card-body"><h3>' . he($model) . '</h3>' .
        ($specs ? '<ul class="kf-specs">' . $specs . '</ul>' : '') .
        ($br !== '' ? '<p class="kf-br">' . lpIcon('pin') . he($br) . '</p>' : '') .
        '<p class="kf-price" data-kf-price>' . ($price > 0 ? '<span class="kf-from">' . he(str_replace('{price}', lpMoneyFrom($price), $T['fleet_from'])) . '</span> <span class="kf-pd">' . he($T['fleet_per_day']) . '</span>' : '') . '</p>' .
        '</div></a><div class="kf-act"><a class="kf-book" href="' . BASE_URL . '/rezervace?moto=' . $id . '" data-kf-book>' . lpIcon('cal') . '<span>' . he($T['card_book']) . '</span></a></div></li>';
}

/**
 * Celý blok v2 katalogu. $o: motos (vše), filtered (výsledek PHP filtru, seřazený), path (kanonická),
 * cat (efektivní kategorie), getCat, q, lic, branch, kw/pr [min,max,bmin,bmax], abs, riders, sort, lics, branches.
 */
function renderKatalogV2($sb, $o) {
    $T = kfTexts($sb);
    $C = kcTexts($sb);
    $pathCat = kfPathCategory($o['path']);
    $action = BASE_URL . (function_exists('i18nLocalizePath') ? i18nLocalizePath($pathCat ? '/katalog/' . $pathCat : '/katalog') : '/katalog');
    $vis = [];
    foreach ($o['filtered'] as $m) $vis[(string)($m['id'] ?? '')] = true;
    // Rozsah karet: na stránce kategorie jen ta kategorie, jinak všechny (skryté = neprošly filtrem)
    $scope = [];
    foreach ($o['filtered'] as $m) if (!empty($m['id'])) $scope[] = $m;
    foreach ($o['motos'] as $m) {
        if (empty($m['id']) || isset($vis[(string)$m['id']])) continue;
        if ($pathCat !== '' && !katalogCategoryMatch($m, $o['cat'])) continue;
        $scope[] = $m;
    }
    $cards = '';
    foreach ($scope as $i => $m) $cards .= renderKatalogV2Card($m, $T, !isset($vis[(string)$m['id']]), $i < 4);
    // Chipy kategorií (odkazy na SEO stránky kategorií; na hlavním katalogu filtruje JS okamžitě)
    $cnt = [];
    foreach ($o['motos'] as $m) foreach (KF_CATS as $k) if (katalogCategoryMatch($m, $k)) $cnt[$k] = ($cnt[$k] ?? 0) + 1;
    $active = strtolower((string)$o['cat']);
    $cats = '<a class="kf-cat' . ($active === '' ? ' is-on" aria-current="true' : '') . '" href="' . BASE_URL . '/katalog" data-kf-cat="">' . he($T['fleet_all_cats']) . ' <span class="kf-cat-n">' . count($o['motos']) . '</span></a>';
    foreach (KF_CATS as $k) {
        if (empty($cnt[$k])) continue;
        $cats .= '<a class="kf-cat' . ($active === $k ? ' is-on" aria-current="true' : '') . '" href="' . BASE_URL . '/katalog/' . $k . '" data-kf-cat="' . $k . '">' . he(categoryLabel($k)) . ' <span class="kf-cat-n">' . $cnt[$k] . '</span></a>';
    }
    // Panel filtrů
    $lic = kfChip('radio', 'ridicak', '', $T['f_any'], $o['lic'] === '');
    foreach ($o['lics'] as $g) $lic .= kfChip('radio', 'ridicak', $g, $g === 'N' ? $T['license_none'] : $g, strtoupper($o['lic']) === $g);
    $brs = '';
    if ($o['branches']) {
        $brs = kfChip('radio', 'pobocka', '', lpPlain($C['branch_all'] ?? ''), $o['branch'] === '');
        foreach ($o['branches'] as $id => $name) $brs .= kfChip('radio', 'pobocka', $id, trim(preg_replace('/^MotoGo24\s*/i', '', $name)) ?: $name, $o['branch'] === (string)$id);
        $brs = '<fieldset class="kf-sec"><legend>' . te('filters.branch') . '</legend><div class="kf-chips">' . $brs . '</div></fieldset>';
    }
    $sort = '';
    foreach (['default' => $T['f_sort_default'], 'cena_asc' => t('filters.sortPriceAsc'), 'cena_desc' => t('filters.sortPriceDesc'), 'vykon_desc' => t('filters.sortPowerDesc'), 'vykon_asc' => t('filters.sortPowerAsc')] as $v => $l) {
        $sort .= kfChip('radio', 'razeni', $v, $l, $o['sort'] === $v || ($v === 'default' && !in_array($o['sort'], ['cena_asc', 'cena_desc', 'vykon_desc', 'vykon_asc'], true)));
    }
    $kwFmt = function ($v) { return $v . ' kW'; };
    $nVis = count($o['filtered']);
    $panel = '<form class="kf-panel" id="kf-panel" method="get" action="' . he($action) . '" aria-labelledby="kf-panel-t" data-kf-panel>' .
        '<div class="kf-sheet-head"><p class="kf-sheet-t" id="kf-panel-t">' . kfIcon('sliders') . he($T['f_filters']) . '</p><button type="button" class="kf-x" data-kf-close aria-label="' . he($T['f_close']) . '">' . kfIcon('x') . '</button></div>' .
        '<div class="kf-sheet-body">' .
        ($pathCat === '' && $o['getCat'] !== '' ? '<input type="hidden" name="kategorie" value="' . he($o['getCat']) . '" data-kf-hcat>' : '') .
        '<div class="kf-sec kf-search"><label class="sr-only" for="kf-q">' . te('filters.search') . '</label>' . kfIcon('search') .
        '<input type="search" id="kf-q" name="q" value="' . he($o['q']) . '" placeholder="' . te('filters.searchPlaceholder') . '" enterkeyhint="search"></div>' .
        '<fieldset class="kf-sec"><legend>' . te('filters.license') . '</legend><div class="kf-chips">' . $lic . '</div></fieldset>' . $brs .
        kfRange('pr', $T['f_price'], ['cena_min', 'cena_max'], $o['pr'], 100, 'kfMoney', [t('filters.price.aria.min'), t('filters.price.aria.max')]) .
        kfRange('kw', t('filters.power'), ['kw_min', 'kw_max'], $o['kw'], 1, $kwFmt, [t('filters.power.aria.min'), t('filters.power.aria.max')], t('filters.rangeMax')) .
        '<fieldset class="kf-sec"><legend>' . he($T['f_more']) . '</legend><div class="kf-chips">' .
            kfChip('checkbox', 'abs', '1', t('filters.absOnly'), $o['abs']) . kfChip('checkbox', 'jezdci', '2', t('filters.ridersTwo'), $o['riders'] === 2) . '</div></fieldset>' .
        '<fieldset class="kf-sec"><legend>' . te('filters.sort') . '</legend><div class="kf-chips">' . $sort . '</div></fieldset>' .
        '</div><div class="kf-foot"><a class="kf-reset" href="' . he($action) . '" data-kf-reset>' . he($T['f_clear']) . '</a>' .
        '<button type="submit" class="lp-btn lp-btn-primary kf-apply"><span data-kf-show>' . he(str_replace('{count}', kfCount($T, $nVis), $T['f_show'])) . '</span></button></div></form>';
    $btn = function ($attrs, $ico, $label, $extra = '') {
        return '<button type="button" class="kf-btn" ' . $attrs . '>' . $ico . '<span class="kf-btn-l">' . he($label) . '</span>' . $extra . '</button>';
    };
    $bar = '<div class="kf-bar" data-kf-bar><div class="kf-bar-in">' .
        $btn('data-kf-open="dates" aria-haspopup="dialog" aria-expanded="false" aria-controls="kf-dates" hidden', lpIcon('cal'), $T['f_dates']) .
        $btn('data-kf-open="panel" aria-expanded="false" aria-controls="kf-panel" hidden', kfIcon('sliders'), $T['f_filters'], '<span class="kf-nf" data-kf-nf hidden></span>') .
        '<a class="kf-btn kf-btn--calc" href="#kalkulacka" data-kf-calc hidden>' . kfIcon('calc') . '<span class="kf-btn-l">' . he($T['f_calc']) . '</span></a>' .
        '</div>' . $panel . '</div>';
    $data = [
        'motos' => kfMotoData($o['motos'], $o['q']), 'base' => $pathCat === '', 'action' => $action,
        'b' => ['kw' => [$o['kw'][2], $o['kw'][3]], 'pr' => [$o['pr'][2], $o['pr'][3]]],
        's' => ['cat' => $active, 'lic' => strtoupper($o['lic']), 'br' => $o['branch'], 'kw' => [$o['kw'][0], $o['kw'][1]], 'pr' => [$o['pr'][0], $o['pr'][1]],
            'abs' => $o['abs'], 'two' => $o['riders'] === 2, 'q' => $o['q'], 'sort' => $o['sort']],
        'br' => (object)array_map(function ($n) { return trim(preg_replace('/^MotoGo24\s*/i', '', $n)) ?: $n; }, $o['branches']),
        't' => $T + ['absOnly' => t('filters.absOnly'), 'ridersTwo' => t('filters.ridersTwo'), 'power' => t('filters.power'), 'max' => t('filters.rangeMax'), 'empty' => t('filters.empty')],
    ];
    return '<script>document.documentElement.classList.add("kf-js")</script>' .
        '<div class="kf" data-kf>' . $bar . '<nav class="kf-cats" aria-label="' . te('filters.category') . '">' . $cats . '</nav>' .
        '<div class="kf-res"><p class="kf-count" data-kf-count aria-live="polite">' . he(kfCount($T, $nVis)) . '</p><div class="kf-active" role="group" data-kf-active aria-label="' . he($T['f_active']) . '" hidden></div></div>' .
        '<ul id="katalog-grid" class="kf-grid" data-kf-grid aria-label="' . te('filters.aria.catalog') . '">' . $cards . '</ul>' .
        '<div class="kf-empty" data-kf-empty' . ($nVis ? ' hidden' : '') . '><p data-kf-empty-t>' . te('filters.empty') . '</p><p><a class="kf-reset kf-reset--btn" href="' . he($action) . '" data-kf-reset>' . te('filters.clearFilters') . '</a></p></div>' .
        '<script type="application/json" id="kf-data">' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) . '</script></div>';
}
