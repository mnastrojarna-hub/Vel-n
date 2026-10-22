<?php
// ===== MotoGo24 Web PHP — Půjčení oblečení (jen výbava, bez motorky) =====
// Tok: pobočka → termín (1 klik = 1 den) → výbava s velikostmi → kontakt →
// platba Stripe (process-payment kind=products, cena z DB). Objednávku zakládá
// RPC create_gear_rental_order (migrace 20261022_gear_rental.sql), návrat ze
// Stripe ?order_id=&session_id= ukáže potvrzení (get_gear_rental_confirmation).
// Ceník gear_rental_prices = Velín → Flotila → Půjčení oblečení.
// JS: js/gear-rental.js (+ kalendář z landing-calc-core/-view.js), CSS: css/gear-rental.css.

require_once __DIR__ . '/../landing.php';
require_once __DIR__ . '/../data/gear-rental-texts.php';

$sb = new SupabaseClient();
$T = $sb->siteContent('gear_rental', gearRentalDefaults());
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$k = 'web.gear_rental.';
$s = function ($key) use ($T) { return he(lpPlain($T[$key] ?? '')); };

// Ceník (jen aktivní; chybějící tabulka / chyba REST = prázdný ceník → kontakt)
$rows = $sb->query('gear_rental_prices', 'key,kind,label,description,includes,sizes,price_per_day,sort_order,translations', ['is_active=eq.true'], 'sort_order.asc');
$rows = (is_array($rows) && array_is_list($rows)) ? $rows : [];
$prices = [];
foreach ($rows as $r) {
    if (!is_array($r) || empty($r['key'])) continue;
    $tr = lpTr($r)[$lang] ?? [];
    $prices[] = [
        'key' => (string)$r['key'], 'kind' => $r['kind'] === 'set' ? 'set' : 'item',
        'label' => lpPlain($tr['label'] ?? '') ?: lpPlain($r['label'] ?? ''),
        'desc' => lpPlain($tr['description'] ?? '') ?: lpPlain($r['description'] ?? ''),
        'includes' => array_values(array_map('strval', (array)($r['includes'] ?? []))),
        'sizes' => array_values(array_map('strval', (array)($r['sizes'] ?? []))),
        'p' => (float)($r['price_per_day'] ?? 0),
    ];
}
$cfg = $sb->fetchSetting('gear_rental');
$cfg = is_array($cfg) ? $cfg : [];
$enabled = ($cfg['enabled'] ?? true) !== false && !empty($prices);

$branches = [];
foreach ((array)$sb->fetchBranches() as $b) {
    if (!is_array($b) || empty($b['id']) || (isset($b['active']) && !$b['active'])) continue;
    $branches[] = ['id' => $b['id'], 'n' => trim(preg_replace('/^MotoGo24\s*/i', '', (string)($b['name'] ?? ''))),
        'a' => trim(implode(', ', array_filter([(string)($b['address'] ?? ''), (string)($b['city'] ?? '')]))),
        'self' => ($b['type'] ?? '') === 'samoobslužná'];
}
$closures = $sb->query('branch_closures', 'branch_id,closed_from,closed_to', ['closed_to=gte.' . date('Y-m-d')]);
$closures = (is_array($closures) && array_is_list($closures)) ? array_map(function ($c) {
    return ['b' => $c['branch_id'] ?? '', 'f' => substr((string)($c['closed_from'] ?? ''), 0, 10), 't' => substr((string)($c['closed_to'] ?? ''), 0, 10)];
}, $closures) : [];

// Měna jako kalkulačka (katalog-calc.php kcData): platba vždy v Kč
$cur = ['code' => 'CZK', 'rate' => 1, 'dec' => 0, 'sym' => 'Kč'];
if (function_exists('currencyJsConfig')) {
    $cc = currencyJsConfig();
    $code = strtoupper((string)($cc['current'] ?? 'CZK'));
    $rate = (float)($cc['rates'][$code] ?? 0);
    $meta = $cc['meta'][$code] ?? null;
    if ($code !== 'CZK' && $rate > 0 && is_array($meta)) $cur = ['code' => $code, 'rate' => $rate, 'dec' => (int)$meta['decimals'], 'sym' => $meta['symbol']];
}
$money = function ($czk) { return he(lpMoneyFrom($czk)); };

// ---- Ceník (statický, indexovatelný) ----
$sets = array_values(array_filter($prices, function ($p) { return $p['kind'] === 'set'; }));
$items = array_values(array_filter($prices, function ($p) { return $p['kind'] === 'item'; }));
$priceHtml = '';
foreach ($sets as $p) {
    $priceHtml .= '<li class="gr-set"><span class="gr-set-t">' . he($p['label']) . '</span>' .
        ($p['desc'] !== '' ? '<span class="gr-set-d">' . he($p['desc']) . '</span>' : '') .
        '<span class="gr-set-p"><span class="gr-pv">' . $money($p['p']) . '</span> ' . $s('per_day') . '</span></li>';
}
$itemList = '';
foreach ($items as $p) $itemList .= '<li><span>' . he($p['label']) . '</span><span class="gr-pv">' . $money($p['p']) . ' <small>' . $s('per_day') . '</small></span></li>';
$chips = '';
foreach ((array)($T['chips'] ?? []) as $i => $c) if (lpPlain($c) !== '') $chips .= '<li class="lp-chip">' . lpIcon('check') . '<span data-cms-key="' . $k . 'chips.' . $i . '">' . he(lpPlain($c)) . '</span></li>';
$faq = '';
foreach ((array)($T['faq'] ?? []) as $f) {
    if (!is_array($f) || lpPlain($f['q'] ?? '') === '') continue;
    $faq .= '<details class="gr-faq-i"><summary>' . he(lpPlain($f['q'])) . '</summary><p>' . he(lpPlain($f['a'] ?? '')) . '</p></details>';
}

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], lpPlain($T['h1'] ?? '')]);
$sec = function ($n, $key, $body, $id) use ($s, $k) {
    return '<section class="gr-step" id="' . $id . '"><h2><span class="gr-n">' . $n . '</span><span data-cms-key="' . $k . $key . '">' . $s($key) . '</span></h2>' . $body . '</section>';
};
$form = $enabled ? '<form class="gr-form" id="gr-form" novalidate>' .
    $sec(1, 'step_branch', '<div class="gr-branches" data-gr-branches></div><p class="gr-note" data-gr-selfnote hidden>' . $s('self_note') . '</p>', 'gr-s1') .
    $sec(2, 'step_dates', '<p class="gr-hint" data-gr-hint aria-live="polite"></p><div class="kc-cal-box gr-cal" data-gr-cal></div>' .
        '<label class="gr-time" data-gr-time hidden><span>' . $s('pickup_time') . '</span><select id="gr-time"></select></label>', 'gr-s2') .
    $sec(3, 'step_gear', '<p class="gr-hint">' . $s('gear_hint') . '</p><div class="gr-quick" data-gr-quick></div><div class="gr-items" data-gr-items></div>', 'gr-s3') .
    $sec(4, 'step_contact', '<div class="gr-fields">' .
        '<input id="gr-name" autocomplete="name" maxlength="200" placeholder="' . $s('name') . '" aria-label="' . $s('name') . '" required>' .
        '<input id="gr-email" type="email" autocomplete="email" maxlength="200" placeholder="' . $s('email') . '" aria-label="' . $s('email') . '" required>' .
        '<input id="gr-phone" type="tel" autocomplete="tel" maxlength="30" placeholder="' . $s('phone') . '" aria-label="' . $s('phone') . '" required>' .
        '<input id="gr-street" autocomplete="street-address" maxlength="200" placeholder="' . $s('street') . '" aria-label="' . $s('street') . '">' .
        '<div class="gr-row"><input id="gr-zip" autocomplete="postal-code" maxlength="12" placeholder="' . $s('zip') . '" aria-label="' . $s('zip') . '">' .
        '<input id="gr-city" autocomplete="address-level2" maxlength="100" placeholder="' . $s('city') . '" aria-label="' . $s('city') . '"></div>' .
        '<label class="gr-check"><input type="checkbox" id="gr-company-on"> ' . $s('company_toggle') . '</label>' .
        '<div class="gr-company" id="gr-company" hidden><input id="gr-company-name" maxlength="200" placeholder="' . $s('company') . '" aria-label="' . $s('company') . '">' .
        '<div class="gr-row"><input id="gr-ico" maxlength="20" placeholder="' . $s('ico') . '" aria-label="' . $s('ico') . '"><input id="gr-dic" maxlength="20" placeholder="' . $s('dic') . '" aria-label="' . $s('dic') . '"></div></div>' .
        '<textarea id="gr-note" maxlength="500" rows="2" placeholder="' . $s('note') . '" aria-label="' . $s('note') . '"></textarea>' .
        '<label class="gr-check gr-agree"><input type="checkbox" id="gr-agree"> <span>' . sanitizeHtml(lpS($T['agree'] ?? '')) . '</span></label></div>', 'gr-s4') .
    '<div class="gr-sum" data-gr-sum aria-live="polite"></div>' .
    '<p class="gr-err" data-gr-err role="alert" hidden></p>' .
    '<button type="submit" class="lp-btn lp-btn-primary gr-go" data-gr-go>' . lpIcon('arrow') . '<span>' . $s('cta') . '</span></button>' .
    '<p class="gr-assure">' . lpIcon('check') . '<span data-cms-key="' . $k . 'assure">' . $s('assure') . '</span></p>' .
    '</form>' : '<p class="gr-unavail">' . he(lpPlain(($cfg['enabled'] ?? true) === false ? ($T['err_disabled'] ?? '') : ($T['unavailable'] ?? ''))) . '</p>';

$content = '<main id="content" class="gr-page"><div class="container">' . $bc .
    '<header class="gr-head"><h1 data-cms-key="' . $k . 'h1">' . $s('h1') . '</h1><p class="gr-lead" data-cms-key="' . $k . 'lead">' . $s('lead') . '</p>' .
    ($chips ? '<ul class="lp-chips gr-chips">' . $chips . '</ul>' : '') . '</header>' .
    '<div class="gr-done" data-gr-done hidden></div>' .
    '<div class="gr-grid" data-gr-main><div class="gr-main">' .
    (isset($_GET['payfail']) ? '<p class="gr-err gr-payfail" role="alert">' . $s('payfail') . '</p>' : '') . $form . '</div>' .
    '<aside class="gr-side">' . ($priceHtml || $itemList ? '<section class="gr-prices" aria-labelledby="gr-prices-h"><h2 id="gr-prices-h" data-cms-key="' . $k . 'prices_title">' . $s('prices_title') . '</h2>' .
        ($priceHtml ? '<ul class="gr-sets">' . $priceHtml . '</ul>' : '') .
        ($itemList ? '<h3 data-cms-key="' . $k . 'items_title">' . $s('items_title') . '</h3><ul class="gr-itemlist">' . $itemList . '</ul>' : '') . lpFxNote(lpTexts($sb)['common']) . '</section>' : '') .
    ($faq ? '<section class="gr-faq" aria-labelledby="gr-faq-h"><h2 id="gr-faq-h" data-cms-key="' . $k . 'faq_title">' . $s('faq_title') . '</h2>' . $faq . '</section>' : '') .
    '</aside></div></div></main>';

$txt = [];
foreach (gearRentalDefaults() as $key => $v) if (!is_array($v)) $txt[$key] = lpPlain($T[$key] ?? $v);
// Kalendář (landing-calc-view.js K.calHtml) čte legend_* / prev / next z T
$txt['legend_busy'] = $txt['legend_closed'];
$txt['legend_pending'] = $txt['legend_closed'];
$loc = function ($p) { return BASE_URL . (function_exists('i18nLocalizePath') ? i18nLocalizePath($p) : $p); };
$data = [
    'sb' => ['url' => SUPABASE_URL, 'key' => SUPABASE_ANON_KEY], 'lang' => $lang, 'cur' => $cur, 't' => $txt,
    'prices' => $prices, 'branches' => $branches, 'closures' => $closures,
    'maxDays' => max(1, min(366, (int)($cfg['max_days'] ?? 30))), 'maxAhead' => max(1, min(800, (int)($cfg['max_ahead_days'] ?? 400))),
    'home' => $loc('/'), 'katalog' => $loc('/katalog'), 'enabled' => $enabled,
];
$content .= '<script type="application/json" id="gr-data">' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) . '</script>';

renderPage(lpPlain($T['seo_title'] ?? ''), $content, '/pujceni-obleceni', [
    'description' => lpPlain($T['seo_description'] ?? ''),
    'styles' => ['/css/landing.css', '/css/landing-calc.css', '/css/gear-rental.css'],
    'scripts' => ['/js/landing-calc-core.js', '/js/landing-calc-view.js', '/js/gear-rental.js'],
    'body_class' => 'lp-v2 gr-v2',
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => lpPlain($T['h1'] ?? ''), 'url' => siteCanonicalUrl('/pujceni-obleceni')],
    ],
]);
