<?php
// ===== MotoGo24 Web PHP — Landing v2: důvěra a výhody (viz landing.php) =====
// Sekce: důvody „Proč jezdit s námi“ (8 viditelných + rozbalení až na 20),
// slider skutečných recenzí (data/reviews.php — jen ověřené texty, nic
// vymyšleného), „Jen u MotoGo24“ (samoobsluha 24/7, AI asistent, aplikace,
// věrnostní program) a dvě pobočky se vzdálenostmi.

/** Ikony výhod (inline SVG, currentColor). */
function lpIco2($name) {
    $p = [
        'card' => '<rect x="2.5" y="5" width="19" height="14" rx="2"/><path d="M2.5 10h19M6 15h4"/><path d="m15 13 5 5M20 13l-5 5"/>',
        'shield' => '<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6L12 3z"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
        'helmet' => '<path d="M4 15a8 8 0 0 1 16-1v3H9.5L4 15z"/><path d="M13 9.5h7M4 15v3h5"/>',
        'infinity' => '<path d="M6.5 8.5C3 8.5 3 15.5 6.5 15.5c3.2 0 7.8-7 11-7 3.5 0 3.5 7 0 7-3.2 0-7.8-7-11-7z"/>',
        'fuel' => '<path d="M4 20V5a1.5 1.5 0 0 1 1.5-1.5h7A1.5 1.5 0 0 1 14 5v15M3 20h12M4 10h10"/><path d="M14 8h2l2.5 2.5V17a1.5 1.5 0 0 0 3 0v-7"/>',
        'phone' => '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M10.5 18.5h3"/>',
        'app' => '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M9.5 8h5M9.5 11.5h5M9.5 15h3"/>',
        'coffee' => '<path d="M4 9h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V9zM16 10.5h1.5a2.5 2.5 0 0 1 0 5H16"/><path d="M8 3v3M12 3v3"/>',
        'kiosk' => '<rect x="5" y="2.5" width="14" height="19" rx="2"/><rect x="8" y="5.5" width="8" height="6" rx="1"/><path d="M9 15h.01M12 15h.01M15 15h.01M9 18h.01M12 18h.01M15 18h.01"/>',
        'bot' => '<rect x="4" y="7.5" width="16" height="11" rx="3"/><path d="M12 3.5v4M9 12.5h.01M15 12.5h.01M9.5 15.5h5"/>',
        'route' => '<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h6.5"/>',
        'star' => '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3z"/>',
        'gift' => '<rect x="3.5" y="8.5" width="17" height="12" rx="1.5"/><path d="M3.5 12.5h17M12 8.5v12M12 8.5c-1.5-4-6-4-6-1.5 0 1.5 6 1.5 6 1.5zM12 8.5c1.5-4 6-4 6-1.5 0 1.5-6 1.5-6 1.5z"/>',
        'truck' => '<path d="M2.5 6.5h11v10h-11zM13.5 10h4l3 3v3.5h-7z"/><circle cx="6.5" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
        'percent' => '<path d="m6 18 12-12"/><circle cx="7" cy="7" r="2.5"/><circle cx="17" cy="17" r="2.5"/>',
        'child' => '<circle cx="12" cy="5.5" r="2.5"/><path d="M8 21v-6l-2-3 3-3.5h6L18 12l-2 3v6M10 15h4"/>',
        'clock' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
        'pin' => '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
        'moto' => '<circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5 9 10h5l4.5 6.5M14 10l-2-4h3M9 10l-1.5-2.5"/>',
        'calendar' => '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18M8 14l2.5 2.5L16 11"/>',
        'check' => '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    ];
    return '<svg class="lp-ico2" viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . ($p[$name] ?? $p['check']) . '</svg>';
}

/** Důvody „Proč jezdit s námi“: $items [{icon,title,text}], prvních $visible vidět, zbytek po rozbalení. */
function renderLpReasons($title, $titleKey, $lead, $items, $keyBase, $T, $visible = 8, $id = 'lp-reasons') {
    $html = '';
    $n = 0;
    foreach ((array)$items as $i => $r) {
        if (!is_array($r) || lpPlain($r['title'] ?? '') === '') continue;
        $n++;
        $extra = $n > $visible ? ' lp-reason--extra' : '';
        $html .= '<li class="lp-reason lp-reveal' . $extra . '" style="--i:' . (($n - 1) % 8) . '">' .
            '<span class="lp-reason-n" aria-hidden="true">' . str_pad((string)$n, 2, '0', STR_PAD_LEFT) . '</span>' .
            '<span class="lp-reason-ico">' . lpIco2(lpS($r['icon'] ?? '')) . '</span>' .
            '<span class="lp-reason-t" data-cms-key="' . $keyBase . '.' . $i . '.title">' . he(lpPlain($r['title'])) . '</span>' .
            (lpPlain($r['text'] ?? '') !== '' ? '<span class="lp-reason-s" data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml(lpS($r['text'])) . '</span>' : '') .
            '</li>';
    }
    if ($n === 0) return '';
    [$h2, $aria] = lpH2($id . '-h', $title, $titleKey);
    $more = $n > $visible
        ? '<button type="button" class="lp-reasons-more" data-lp-reasons aria-expanded="false" data-open="' . he(str_replace('{n}', (string)$n, lpS($T['reasons_more'] ?? ''))) . '" data-close="' . he(lpS($T['reasons_less'] ?? '')) . '" hidden>' . he(str_replace('{n}', (string)$n, lpS($T['reasons_more'] ?? ''))) . '</button>'
        : '';
    return '<section class="lp-reasons" id="' . $id . '"' . $aria . '><div class="container">' . $h2 .
        (lpPlain($lead) !== '' ? '<p class="lp-reasons-lead">' . sanitizeHtml(lpS($lead)) . '</p>' : '') .
        '<ol class="lp-reasons-list">' . $html . '</ol>' . $more .
        (lpPlain($T['reasons_note'] ?? '') !== '' ? '<p class="lp-reasons-note" data-cms-key="web.landing.common.reasons_note">' . he(lpPlain($T['reasons_note'])) . '</p>' : '') . '</div></section>';
}

/** Hvězdičky 0–5 (SVG, přístupný popisek). */
function lpStars($rating) {
    $r = max(0, min(5, (float)$rating));
    $full = (int)round($r);
    $s = '';
    for ($i = 1; $i <= 5; $i++) $s .= '<i class="' . ($i <= $full ? 'on' : '') . '"></i>';
    return '<span class="lp-stars" role="img" aria-label="' . he(str_replace('.', ',', (string)$r)) . ' / 5">' . $s . '</span>';
}

/**
 * Slider skutečných recenzí. $R = lpReviewsData() (data/reviews.php): aggregates [{label,rating|recommend,count,url}],
 * items [{source,author,rating|recommends,date Y-m-d,text,text_<lang>?}].
 * Na cizím jazyce se ukáže překlad (text_<lang>) s poznámkou „přeloženo“, jinak originál.
 */
function renderLpReviews($R, $T) {
    $items = array_values(array_filter((array)($R['items'] ?? []), function ($x) { return is_array($x) && lpPlain($x['text'] ?? '') !== ''; }));
    $aggs = array_values(array_filter((array)($R['aggregates'] ?? []), 'is_array'));
    if (!$items && !$aggs) return '';
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $badges = '';
    foreach ($aggs as $a) {
        $label = he(lpS($a['label'] ?? ''));
        $score = isset($a['rating'])
            ? '<span class="lp-rbadge-r">' . he(number_format((float)$a['rating'], 1, ',', '')) . '</span>' . lpStars($a['rating'])
            : (isset($a['recommend']) ? '<span class="lp-rbadge-r">' . he(str_replace('{p}', (string)(int)$a['recommend'], lpS($T['reviews_recommend_pct'] ?? '{p} %'))) . '</span><span class="lp-rec">' . he(lpS($T['reviews_recommends'] ?? '')) . '</span>' : '');
        $inner = '<span class="lp-rbadge-src">' . $label . '</span>' . $score .
            (isset($a['count']) ? '<span class="lp-rbadge-c">' . he(str_replace('{n}', (string)(int)$a['count'], lpS($T['reviews_count'] ?? '{n}'))) . '</span>' : '');
        $badges .= !empty($a['url']) ? '<a class="lp-rbadge" href="' . he($a['url']) . '" target="_blank" rel="noopener">' . $inner . '</a>' : '<span class="lp-rbadge">' . $inner . '</span>';
    }
    $cards = '';
    foreach ($items as $x) {
        $tr = lpS($x['text_' . $lang] ?? '');
        $text = ($lang !== 'cs' && $tr !== '') ? $tr : lpS($x['text']);
        $note = ($lang !== 'cs' && $tr !== '') ? '<span class="lp-review-tr">' . he(lpS($T['reviews_translated'] ?? '')) . '</span>' : '';
        $ts = strtotime(lpS($x['date'] ?? ''));
        $date = $ts ? date($lang === 'cs' ? 'j. n. Y' : 'd/m/Y', $ts) : '';
        $score = isset($x['rating']) ? lpStars($x['rating']) : (!empty($x['recommends']) ? '<span class="lp-rec">' . he(lpS($T['reviews_recommends'] ?? '')) . '</span>' : '');
        $cards .= '<li class="lp-review"><figure>' . $score .
            '<blockquote>' . he(lpPlain($text)) . '</blockquote>' .
            '<figcaption><span class="lp-review-a">' . he(lpPlain($x['author'] ?? '')) . '</span>' .
            '<span class="lp-review-m">' . he(lpPlain($x['source'] ?? '')) . ($date !== '' ? ' · ' . $date : '') . '</span>' . $note . '</figcaption></figure></li>';
    }
    [$h2, $aria] = lpH2('lp-reviews-h', $T['reviews_title'] ?? '', 'web.landing.common.reviews_title');
    return '<section class="lp-reviews"' . $aria . '><div class="container">' . $h2 .
        ($badges ? '<div class="lp-rbadges">' . $badges . '</div>' : '') . '</div>' .
        ($cards ? '<div class="lp-track-wrap"><button type="button" class="lp-nav lp-nav-prev" aria-label="' . he(lpS($T['reviews_prev'] ?? '')) . '" hidden>' . lpIcon('arrow') . '</button>' .
            '<ul class="lp-track lp-track--reviews" data-lp-track data-lp-autoplay>' . $cards . '</ul>' .
            '<button type="button" class="lp-nav lp-nav-next" aria-label="' . he(lpS($T['reviews_next'] ?? '')) . '" hidden>' . lpIcon('arrow') . '</button></div>' .
            '<div class="container"><div class="lp-progress" aria-hidden="true"><i></i></div></div>' : '') . '</section>';
}

/** „Jen u MotoGo24“ — karty s animovaným vizuálem. $items [{kind,title,text,href?,cta?,stores?}] kind: kiosk|ai|app|loyalty */
function renderLpHighlights($title, $titleKey, $items, $keyBase) {
    $vis = [
        'kiosk' => '<div class="lp-hl-vis lp-hl-vis--kiosk" aria-hidden="true"><span class="lp-hl-ring"></span><b>24/7</b></div>',
        'ai' => '<div class="lp-hl-vis lp-hl-vis--ai" aria-hidden="true"><span class="lp-hl-bubble"><i></i><i></i><i></i></span>' . lpIco2('bot') . '</div>',
        'app' => '<div class="lp-hl-vis lp-hl-vis--app" aria-hidden="true"><svg viewBox="0 0 120 70" width="120" height="70"><path class="lp-hl-route" d="M8 58 C30 58 28 20 52 22 S78 52 96 40 112 12 112 12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/><circle cx="8" cy="58" r="5"/><circle cx="112" cy="12" r="5"/></svg></div>',
        'loyalty' => '<div class="lp-hl-vis lp-hl-vis--loyalty" aria-hidden="true"><span style="--h:30%"></span><span style="--h:52%"></span><span style="--h:74%"></span><span style="--h:100%"></span></div>',
    ];
    $html = '';
    foreach ((array)$items as $i => $h) {
        if (!is_array($h) || lpPlain($h['title'] ?? '') === '') continue;
        $k = lpS($h['kind'] ?? '');
        $html .= '<li class="lp-hl lp-reveal lp-hl--' . he($k) . '" style="--i:' . (int)$i . '">' . ($vis[$k] ?? '') .
            '<h3 data-cms-key="' . $keyBase . '.' . $i . '.title">' . he(lpPlain($h['title'])) . '</h3>' .
            '<p data-cms-key="' . $keyBase . '.' . $i . '.text">' . sanitizeHtml(lpS($h['text'] ?? '')) . '</p>' .
            (lpS($h['href'] ?? '') !== '' && lpPlain($h['cta'] ?? '') !== '' ? '<a class="lp-hl-link" href="' . he($h['href']) . '">' . he(lpPlain($h['cta'])) . lpIcon('arrow') . '</a>' : '') .
            (!empty($h['stores']) && defined('PLAY_STORE_LIVE_URL') && defined('APP_STORE_LIVE_URL')
                ? '<span class="lp-hl-stores"><a href="' . he(APP_STORE_LIVE_URL) . '" target="_blank" rel="noopener">App Store</a><a href="' . he(PLAY_STORE_LIVE_URL) . '" target="_blank" rel="noopener">Google Play</a></span>' : '') . '</li>';
    }
    if ($html === '') return '';
    [$h2, $aria] = lpH2('lp-hl-h', $title, $titleKey);
    return '<section class="lp-hls"' . $aria . '><div class="container"><div class="lp-hls-card">' . $h2 . '<ul class="lp-hls-grid">' . $html . '</ul></div></div></section>';
}

/** Dvě pobočky s fotkou a dojezdem. $items [{badge,title,text,img,href,book_href,times[]}] */
function renderLpBranches($title, $titleKey, $items, $keyBase, $T) {
    $html = '';
    foreach ((array)$items as $i => $b) {
        if (!is_array($b) || lpPlain($b['title'] ?? '') === '') continue;
        $times = '';
        foreach ((array)($b['times'] ?? []) as $t) if (lpPlain($t) !== '') $times .= '<li>' . lpIco2('clock') . he(lpPlain($t)) . '</li>';
        $img = lpS($b['img'] ?? '');
        $html .= '<li class="lp-br lp-reveal" style="--i:' . (int)$i . '">' .
            ($img !== '' ? '<div class="lp-br-img"><img src="' . he($img) . '" alt="' . he(lpPlain($b['title'])) . '" loading="lazy" decoding="async" width="640" height="400"><span class="lp-br-badge">' . he(lpPlain($b['badge'] ?? '')) . '</span></div>' : '') .
            '<div class="lp-br-body"><h3>' . he(lpPlain($b['title'])) . '</h3><p>' . sanitizeHtml(lpS($b['text'] ?? '')) . '</p>' .
            ($times ? '<ul class="lp-br-times">' . $times . '</ul>' : '') .
            '<div class="lp-br-cta"><a class="lp-btn lp-btn-primary" href="' . he(lpS($b['book_href'] ?? '') ?: '/rezervace') . '">' . he(lpPlain($T['branch_book'] ?? '')) . '</a>' .
            '<a class="lp-br-more" href="' . he(lpS($b['href'] ?? '') ?: '/pobocky') . '">' . he(lpPlain($T['branch_more'] ?? '')) . lpIcon('arrow') . '</a></div></div></li>';
    }
    if ($html === '') return '';
    [$h2, $aria] = lpH2('lp-br-h', $title, $titleKey);
    return '<section class="lp-brs"' . $aria . '><div class="container">' . $h2 . '<ul class="lp-brs-grid">' . $html . '</ul></div></section>';
}
