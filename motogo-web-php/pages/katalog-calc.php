<?php
// ===== Katalog — kalkulačka ceny (landing v2, viz landing.php) =====
// Vkládá se z pages/katalog.php (a katalog-detail.php s předvybranou motorkou)
// JEN při landingV2Enabled(). Pobočka → motorka → termín → cena po dnech,
// orientační přepočet měny, sleva za vyzvednutí od 12:00 (jen informativně)
// a tlačítko do /rezervace?moto=&start=&end= (předvyplní formulář; bez motorky
// ?start=&end=&pobocka= → rezervace ukáže volné stroje). Výpočet zrcadlí
// MG.calcPriceBreakdown (js/api.js) a MG._latePickupDiscount
// (js/pages-rezervace-pricing.js), obsazenost z RPC get_moto_booked_dates.
// JS: js/landing-calc-core.js + js/landing-calc.js, CSS: css/landing-calc.css.
// Texty: CS defaulty kcDefaults() ← lang/v2/<lang>/katalog.php ← Velín web.landing_katalog.*.

function kcDefaults() {
    return [
        'subtitle' => 'Vyber si stroj a spočítej si cenu',
        'jump' => 'Zobrazit všech {n} motorek',
        'eyebrow' => 'Kalkulačka ceny',
        'title' => 'Spočítej si cenu',
        'lead' => 'Vyber pobočku, motorku a termín — ukážeme volné dny a přesnou cenu. Jedním klepnutím pak přejdeš do rezervace se vším předvyplněným.',
        'lead_detail' => 'Vyber termín — ukážeme volné dny a přesnou cenu této motorky. Jedním klepnutím pak přejdeš do rezervace se vším předvyplněným.',
        'step_branch' => 'Pobočka', 'step_moto' => 'Motorka', 'step_dates' => 'Termín',
        'branch_all' => 'Všechny', 'branch_count' => '{n} motorek',
        'branch_staffed' => 's obsluhou', 'branch_self' => 'samoobsluha nonstop',
        'moto_any' => 'Jakákoli volná motorka',
        'moto_maint' => 'v servisu', 'moto_unavail' => 'nedostupná',
        'from' => 'od {price}/den',
        'st_today' => 'Volná ještě dnes', 'st_from' => 'Volná od {date}',
        'st_maint' => 'V servisu — vyber si volné dny v kalendáři', 'st_unavail' => 'Momentálně nedostupná',
        'detail' => 'Detail motorky',
        'cal_any' => 'Bez vybrané motorky uvidíš dny, kdy je volná aspoň jedna motorka.',
        'cal_loading' => 'Načítám obsazenost…', 'cal_error' => 'Obsazenost se nepodařilo načíst.', 'retry' => 'Zkusit znovu',
        'hint_start' => 'Klepni na den vyzvednutí', 'hint_end' => 'Teď den vrácení (může být i stejný den)', 'hint_done' => 'Klepnutím na jiný den termín změníš',
        'legend_free' => 'Volno', 'legend_busy' => 'Obsazeno', 'legend_pending' => 'Čeká na potvrzení', 'legend_sel' => 'Tvůj termín',
        'legend_price' => 'Cena/den v {cur}',
        'range_busy' => 'V tomto rozmezí je obsazený den. Vyber jiný termín.',
        'moto_busy' => 'Tahle motorka v tvém termínu volná není — vyber jiný.',
        'min_days' => 'Tuhle motorku půjčujeme minimálně na {n} dní.',
        'prev' => 'Předchozí měsíc', 'next' => 'Další měsíc',
        'sum_title' => 'Tvoje cena',
        'sum_empty' => 'Vyber motorku a termín — cenu spočítáme hned, bez registrace.',
        'sum_dates' => 'Vyber termín v kalendáři — cenu spočítáme hned, bez registrace.',
        'sum_pick_end' => 'Vyber den vrácení a uvidíš celkovou cenu.',
        'pickup' => 'Vyzvednutí', 'return' => 'Vrácení',
        'days_one' => '{n} den', 'days_few' => '{n} dny', 'days_many' => '{n} dní',
        'avg' => 'průměrně {price} / den', 'chart' => 'Cena po dnech',
        'total' => 'Celkem za pronájem',
        'pay_czk' => 'Platíš v Kč: {price}',
        'fx' => 'Cena v {cur} je orientační (kurz ČNB), platba probíhá v Kč.',
        'late_title' => 'Vyzvedni od 12:00',
        'late_text' => 'a 1. den máš za půlku: ušetříš {amount}, zaplatíš {total}. Čas vyzvednutí zvolíš v rezervaci.',
        'late_one' => 'Při pronájmu na 2 a více dní vyzvedni od 12:00 a 1. den máš za půlku.',
        'includes' => ['Bez kauce', 'Výbava pro řidiče v ceně', 'Bez limitu km'],
        'cta' => 'Rezervovat tento termín', 'cta_moto' => 'Rezervovat tuto motorku', 'cta_any' => 'Zobrazit volné motorky a rezervovat',
        'assure' => 'Storno zdarma do 7 dní před začátkem · Bezpečná platba',
        'reset' => 'Zrušit termín',
        'free_title' => 'Volné v tvém termínu: {n}',
        'free_none' => 'V tomto termínu na pobočce žádná motorka volná není. Zkus jiný termín nebo pobočku.',
        'free_more' => 'a dalších {n} v rezervaci',
        'card_btn' => 'Spočítat cenu',
        'sticky' => 'Rezervovat',
    ];
}

/** Texty kalkulačky (CS default ← jazykový overlay ← DB ← Velín CMS). */
function kcTexts($sb) {
    static $c = null;
    if ($c === null) $c = $sb->siteContent('landing_katalog', kcDefaults());
    return $c;
}

/** Assety pro renderPage() meta. */
function kcPageMeta() {
    return ['styles' => ['/css/landing.css', '/css/landing-calc.css', '/css/landing-calc-sum.css'],'scripts' => ['/js/landing-calc-core.js', '/js/landing-calc-view.js', '/js/landing-calc.js'], 'body_class' => 'lp-v2'];
}

/** Podtitulek pod H1 katalogu + rychlý skok na mřížku motorek. */
function kcSubtitle($sb, $count) {
    $T = kcTexts($sb);
    return '<p class="kc-sub"><span data-cms-key="web.landing_katalog.subtitle">' . he(lpPlain($T['subtitle'] ?? '')) . '</span>' .
        ($count > 0 ? '<a class="kc-jump" href="#katalog-grid">' . he(str_replace('{n}', (string)(int)$count, lpPlain($T['jump'] ?? ''))) . lpIcon('arrow') . '</a>' : '') . '</p>';
}

/** Data pro JS: motorky (ceny po dnech dle rezervace), pobočky, kategorie, měna, texty. */
function kcData($motos, $T, $pre) {
    $out = [];
    $branches = [];
    $catOrder = ['cestovni', 'sportovni', 'naked', 'supermoto', 'chopper', 'scootery', 'detske', 'ostatni'];
    $cats = [];
    $dows = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    foreach ((array)$motos as $m) {
        if (!is_array($m) || empty($m['id'])) continue;
        normalizeMoto($m);
        // Stejně jako MG.calcPriceBreakdown: price_<den> || price_weekday || 0
        $p = [];
        foreach ($dows as $dw) {
            $v = (float)($m['price_' . $dw] ?? 0);
            if ($v <= 0) $v = (float)($m['price_weekday'] ?? 0);
            $p[] = $v > 0 ? $v : 0;
        }
        $br = is_array($m['branches'] ?? null) ? $m['branches'] : [];
        $bid = safeStr($m['branch_id'] ?? '');
        if ($bid !== '' && !isset($branches[$bid])) {
            $branches[$bid] = ['id' => $bid, 'n' => trim(preg_replace('/^MotoGo24\s*/i', '', safeStr($br['name'] ?? '') ?: safeStr($br['city'] ?? ''))) ?: $bid,
                'k' => safeStr($br['type'] ?? '') === 'samoobslužná' ? 'self' : 'staffed', 'c' => 0];
        }
        if ($bid !== '') $branches[$bid]['c']++;
        $cat = safeStr($m['category'] ?? '');
        if (!isset($cats[$cat])) $cats[$cat] = ['k' => $cat, 'l' => $cat !== '' ? categoryLabel($cat) : '—'];
        $img = ($m['image_url'] ?? '') ?: ($m['images'][0] ?? '');
        $out[] = [
            'id' => $m['id'], 'm' => trim(safeStr($m['model'] ?? '')) ?: t('card.unnamedMotorcycle'), 'c' => $cat, 'b' => $bid,
            'st' => safeStr($m['status'] ?? ''), 'na' => safeStr($m['next_available_date'] ?? ''), 'un' => !empty($m['available_unknown']),
            'min' => max(1, (int)($m['min_rental_days'] ?? 1)), 'tr' => !empty($m['is_trailer']), 'p' => $p, 'from' => getMinPrice($m),
            'img' => $img ? imgUrlSized($img, 240) : '',
        ];
    }
    uasort($branches, function ($a, $b) { return strnatcasecmp($a['n'], $b['n']); });
    uksort($cats, function ($a, $b) use ($catOrder) {
        $ia = array_search($a, $catOrder, true); $ib = array_search($b, $catOrder, true);
        return ($ia === false ? 99 : $ia) <=> ($ib === false ? 99 : $ib) ?: strcmp($a, $b);
    });
    // Měna jako web (currencyJsConfig); bez kurzu → raději Kč než špatné číslo
    $cur = ['code' => 'CZK', 'rate' => 1, 'dec' => 0, 'sym' => 'Kč'];
    if (function_exists('currencyJsConfig')) {
        $cc = currencyJsConfig();
        $code = strtoupper((string)($cc['current'] ?? 'CZK'));
        $rate = (float)($cc['rates'][$code] ?? 0);
        $meta = $cc['meta'][$code] ?? null;
        if ($code !== 'CZK' && $rate > 0 && is_array($meta)) $cur = ['code' => $code, 'rate' => $rate, 'dec' => (int)$meta['decimals'], 'sym' => $meta['symbol']];
    }
    $txt = [];
    foreach (kcDefaults() as $k => $v) $txt[$k] = is_array($T[$k] ?? null) ? array_map('lpPlain', $T[$k]) : lpPlain($T[$k] ?? $v);
    $loc = function ($p) { return BASE_URL . (function_exists('i18nLocalizePath') ? i18nLocalizePath($p) : $p); };
    return [
        'motos' => $out, 'branches' => array_values($branches), 'cats' => array_values($cats), 'cur' => $cur, 't' => $txt,
        'lang' => function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs',
        'sb' => ['url' => SUPABASE_URL, 'key' => SUPABASE_ANON_KEY],
        'rez' => $loc('/rezervace'), 'detail' => $loc('/katalog'), 'pre' => $pre,
    ];
}

/**
 * Blok kalkulačky. $opts: branch (předvybraná pobočka z filtru ?pobocka=),
 * moto (předvybraná motorka), ctx 'detail' (detail motorky: bez výběru pobočky,
 * vlastní úvodní text, bez odkazu na tentýž detail), id (kotva).
 */
function renderKatalogCalc($sb, $motos, $opts = []) {
    $T = kcTexts($sb);
    $det = ($opts['ctx'] ?? '') === 'detail';
    $data = kcData($motos, $T, ['branch' => (string)($opts['branch'] ?? ''), 'moto' => (string)($opts['moto'] ?? '')]);
    if (!$data['motos']) return '';
    $data['ctx'] = $det ? 'detail' : 'catalog';
    $k = 'web.landing_katalog.';
    $s = function ($key) use ($T, $k) { return '<span data-cms-key="' . $k . $key . '">' . he(lpPlain($T[$key] ?? '')) . '</span>'; };
    $n = function ($i) { return '<span class="kc-n">' . $i . '</span>'; };
    $o = $det ? 0 : 1; // detail: bez kroku „pobočka“ → Motorka = 1, Termín = 2
    $seg = '<label class="kc-opt"><input type="radio" name="kc-branch" value="" checked><span class="kc-opt-in"><span class="kc-opt-t">' . he(lpPlain($T['branch_all'])) . '</span>' .
        '<span class="kc-opt-s">' . he(str_replace('{n}', (string)count($data['motos']), lpPlain($T['branch_count']))) . '</span></span></label>';
    foreach ($data['branches'] as $b) {
        $seg .= '<label class="kc-opt kc-opt--' . $b['k'] . '"><input type="radio" name="kc-branch" value="' . he($b['id']) . '"><span class="kc-opt-in">' .
            '<span class="kc-opt-t">' . lpIcon('pin') . he($b['n']) . '</span><span class="kc-opt-s">' . he(lpPlain($T[$b['k'] === 'self' ? 'branch_self' : 'branch_staffed'])) . '</span></span></label>';
    }
    $calc = '<svg class="lp-ico" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8 11h2M12 11h2M16 11v6M8 15h2M12 15h2M8 18.5h2M12 18.5h2"/></svg>';
    $legend = '';
    foreach (['free', 'busy', 'pending', 'sel'] as $lg) $legend .= '<li class="kc-lg kc-lg--' . $lg . '"><i aria-hidden="true"></i>' . $s('legend_' . $lg) . '</li>';
    $lead = $det ? 'lead_detail' : 'lead';
    return '<section class="kc' . ($det ? ' kc--detail' : '') . '" id="' . he($opts['id'] ?? 'kalkulacka') . '" aria-labelledby="kc-h" data-kc><div class="kc-card">' .
        '<header class="kc-head"><p class="kc-eyebrow">' . $calc . $s('eyebrow') . '</p>' .
        '<h2 id="kc-h" data-cms-key="' . $k . 'title">' . he(lpPlain($T['title'])) . '</h2>' .
        '<p class="kc-lead" data-cms-key="' . $k . $lead . '">' . he(lpPlain($T[$lead])) . '</p>' .
        '<ol class="kc-steps" aria-hidden="true">' . ($det ? '' : '<li data-kc-step="1">' . $n(1) . $s('step_branch') . '</li>') .
            '<li data-kc-step="2">' . $n(1 + $o) . $s('step_moto') . '</li><li data-kc-step="3">' . $n(2 + $o) . $s('step_dates') . '</li></ol></header>' .
        '<div class="kc-grid"><div class="kc-pick">' .
            ($det ? '' : '<fieldset class="kc-branch"><legend class="kc-label">' . $n(1) . $s('step_branch') . '</legend><div class="kc-seg">' . $seg . '</div></fieldset>') .
            '<div class="kc-field"><label class="kc-label" for="kc-moto">' . $n(1 + $o) . $s('step_moto') . '</label>' .
            '<div class="kc-select"><select id="kc-moto"><option value="">' . he(lpPlain($T['moto_any'])) . '</option></select></div>' .
            '<div class="kc-moto" data-kc-moto hidden></div></div></div>' .
        '<div class="kc-cal"><p class="kc-label">' . $n(2 + $o) . $s('step_dates') . '<span class="kc-hint" data-kc-hint aria-live="polite"></span></p>' .
            '<div class="kc-cal-box" data-kc-cal></div>' .
            '<ul class="kc-legend">' . $legend . '</ul><p class="kc-note" data-kc-note></p></div>' .
        '<div class="kc-sum" data-kc-sum aria-live="polite"><div class="kc-sum-in"><p class="kc-sum-k">' . he(lpPlain($T['sum_title'])) . '</p><p class="kc-sum-p">' . he(lpPlain($T['sum_empty'])) . '</p></div></div>' .
        '</div></div>' .
        '<script type="application/json" id="kc-data">' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) . '</script></section>';
}
