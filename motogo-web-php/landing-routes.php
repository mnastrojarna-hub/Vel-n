<?php
// ===== MotoGo24 Web PHP — Landing v2: sekce „Trasy a záznam jízdy“ (aplikace) =====
// Marketing funkcí appky ověřených v kódu (features/routes: ride_recorder — vzdálenost,
// celkový čas, čas jízdy/stání, Ø a max. rychlost, nastoupáno, fotky zastávek, sdílení;
// doporučené trasy s navigací — DB routes 1 174 aktivních; points_of_interest 49 948;
// vlastní trasy v route_builder). Texty: $T['routes'] (data/landing-trust.php,
// lang/v2/<lang>/landing.php). Hodnoty v telefonu jsou ilustrační (aria-hidden).

function renderLpRoutes($T) {
    $R = is_array($T['routes'] ?? null) ? $T['routes'] : [];
    if (lpPlain($R['title'] ?? '') === '') return '';
    $kb = 'web.landing.common.routes';
    $items = '';
    foreach ((array)($R['items'] ?? []) as $i => $it) {
        if (!is_array($it) || lpPlain($it['title'] ?? '') === '') continue;
        $items .= '<li class="lp-rt-item lp-reveal" style="--i:' . (int)$i . '"><span class="lp-rt-ico">' . lpIco2(lpS($it['icon'] ?? 'route')) . '</span>' .
            '<span><b data-cms-key="' . $kb . '.items.' . $i . '.title">' . he(lpPlain($it['title'])) . '</b>' .
            '<span data-cms-key="' . $kb . '.items.' . $i . '.text">' . he(lpPlain($it['text'] ?? '')) . '</span></span></li>';
    }
    $stats = '';
    foreach ((array)($R['stats'] ?? []) as $i => $st) {
        if (!is_array($st) || lpPlain($st['v'] ?? '') === '') continue;
        $stats .= '<li><b>' . he(lpPlain($st['v'])) . '</b><span>' . he(lpPlain($st['l'] ?? '')) . '</span></li>';
    }
    $m = is_array($R['mock'] ?? null) ? $R['mock'] : [];
    $chip = function ($k) use ($m) { return lpPlain($m[$k] ?? '') !== '' ? '<i>' . he(lpPlain($m[$k])) . '</i>' : ''; };
    $phone = '<div class="lp-rt-phone" aria-hidden="true"><div class="lp-rt-screen">' .
        '<svg class="lp-rt-map" viewBox="0 0 220 300" preserveAspectRatio="xMidYMid slice"><path class="lp-rt-water" d="M-10 140 C40 150 70 120 110 132 S190 160 240 140"/><path class="lp-rt-road" d="M-10 60 C60 40 90 110 150 90 S240 40 240 40 M-10 210 C50 190 80 250 140 230 S230 170 240 180 M60 -10 C70 80 40 160 70 310 M170 -10 C150 90 190 200 160 310"/>' .
        '<g class="lp-rt-pois"><circle cx="66" cy="168" r="5"/><circle cx="64" cy="96" r="5"/><circle cx="136" cy="64" r="5"/><circle cx="150" cy="200" r="4"/><circle cx="110" cy="250" r="4"/></g>' .
        '<path class="lp-rt-path" d="M40 262 C30 220 70 205 66 168 S30 120 64 96 S128 92 136 64 S168 30 186 44"/><circle class="lp-rt-a" cx="40" cy="262" r="7"/><circle class="lp-rt-b" cx="186" cy="44" r="7"/></svg>' .
        '<div class="lp-rt-card"><span class="lp-rt-card-t">' . he(lpPlain($m['title'] ?? '')) . '</span><span class="lp-rt-chips">' . $chip('km') . $chip('time') . $chip('avg') . $chip('climb') . '</span></div>' .
        '</div></div>';
    $stores = defined('PLAY_STORE_LIVE_URL') && defined('APP_STORE_LIVE_URL')
        ? '<div class="lp-rt-stores"><a class="lp-btn lp-btn-primary" href="' . he(APP_STORE_LIVE_URL) . '" target="_blank" rel="noopener">App Store</a><a class="lp-btn lp-btn-ghost lp-rt-ghost" href="' . he(PLAY_STORE_LIVE_URL) . '" target="_blank" rel="noopener">Google Play</a></div>'
        : '';
    [$h2, $aria] = lpH2('lp-rt-h', $R['title'], $kb . '.title');
    return '<section class="lp-rt"' . $aria . '><div class="container"><div class="lp-rt-box">' .
        '<div class="lp-rt-text">' . (lpPlain($R['eyebrow'] ?? '') !== '' ? '<p class="lp-rt-eyebrow" data-cms-key="' . $kb . '.eyebrow">' . he(lpPlain($R['eyebrow'])) . '</p>' : '') . $h2 .
        (lpPlain($R['lead'] ?? '') !== '' ? '<p class="lp-rt-lead" data-cms-key="' . $kb . '.lead">' . he(lpPlain($R['lead'])) . '</p>' : '') .
        ($stats ? '<ul class="lp-rt-stats">' . $stats . '</ul>' : '') .
        ($items ? '<ul class="lp-rt-list">' . $items . '</ul>' : '') . $stores . '</div>' . $phone .
        '</div></div></section>';
}
