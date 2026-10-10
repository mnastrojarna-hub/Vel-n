<?php
// ===== Pobočky — landing v2: ikony a bloky (hero, fakta, info, video, mapa, karta) =====
// Průvodce „Jak to probíhá“, výbava, galerie a srovnání: pages/pobocky-v2-blocks.php.
// Texty z CMS jdou přes sanitizeHtml (mají <strong>/<br>), ostatní přes he().

require_once __DIR__ . '/pobocky-v2-blocks.php';

/** Inline SVG ikona (stroke, currentColor). Neznámý název → fajfka. */
function pbIcon($n, $cls = '') {
    static $p = [
        'check' => '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
        'x' => '<path d="M7 7l10 10M17 7 7 17"/>',
        'clock' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        'user' => '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
        'phone' => '<rect x="7" y="2.5" width="10" height="19" rx="2"/><path d="M11 18h2"/>',
        'parking' => '<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="M9.5 17V7.5h3.5a3 3 0 0 1 0 6H9.5"/>',
        'helmet' => '<path d="M4 16a8 8 0 1 1 16 0v1.5a1.5 1.5 0 0 1-1.5 1.5H8.5A4.5 4.5 0 0 1 4 14.5z"/><path d="M12.5 10.5H20M4.5 13H11"/>',
        'jacket' => '<path d="M9 3h6l5 3v6l-2 .5V21H6v-8.5L4 12V6z"/><path d="M12 6.5V21M9 3l3 3.5L15 3"/>',
        'pants' => '<path d="M7 3h10l1.5 18h-4.2L12 10l-2.3 11H5.5z"/><path d="M7 7h10"/>',
        'gloves' => '<path d="M8 21v-4.5L5.2 12.4a1.6 1.6 0 0 1 2.6-1.8L9 12V5.5a1.5 1.5 0 0 1 3 0V11V4.5a1.5 1.5 0 0 1 3 0V11V6.5a1.5 1.5 0 0 1 3 0V15a6 6 0 0 1-3 5.2V21"/>',
        'balaclava' => '<path d="M12 3a7 7 0 0 0-7 7v7a4 4 0 0 0 4 4h6a4 4 0 0 0 4-4v-7a7 7 0 0 0-7-7z"/><rect x="7.5" y="10" width="9" height="3.2" rx="1.6"/>',
        'boots' => '<path d="M7 3h6v10l5.8 2.9a2 2 0 0 1 1.2 1.8V20H5V5a2 2 0 0 1 2-2z"/><path d="M5 17h15M9 7h4"/>',
        'rain' => '<path d="M7 15a4 4 0 0 1-.4-8A6 6 0 0 1 18 8.5 3.5 3.5 0 0 1 17.5 15z"/><path d="m8 18-1 3M12 18l-1 3M16 18l-1 3"/>',
        'truck' => '<path d="M3 6h11v10H3zM14 9h4l3 3.5V16h-7"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
        'shield' => '<path d="M12 3 4.5 6v5.5c0 4.8 3.2 8.2 7.5 9.5 4.3-1.3 7.5-4.7 7.5-9.5V6z"/><path d="m8.8 12 2.3 2.3 4.2-4.6"/>',
        'percent' => '<path d="M18.5 5.5l-13 13"/><circle cx="7.5" cy="7.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/>',
        'moon' => '<path d="M20 14.5A8.5 8.5 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
        'pin' => '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
        'nav' => '<path d="m3.5 11 17-7.5-7.5 17-2-7.5z"/>',
        'play' => '<path d="M8 5.5v13l10.5-6.5z" fill="currentColor"/>',
        'tag' => '<path d="M3 12.5 12.5 3H21v8.5L11.5 21z"/><circle cx="16.5" cy="7.5" r="1.5"/>',
        'doc' => '<path d="M6 3h8.5L19 7.5V21H6z"/><path d="M14 3v5h5M9 12.5h7M9 16.5h7"/>',
        'lock' => '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11M12 15v2"/>',
        'gate' => '<path d="M3.5 21V4M20.5 21V4M3.5 8.5h17M3.5 15.5h17M8 8.5v7M12 8.5v7M16 8.5v7"/>',
        'vest' => '<path d="M8.5 3 4.5 6v15h6v-7.5M15.5 3l4 3v15h-6v-7.5M8.5 3 12 9l3.5-6"/><path d="M4.5 15.5h6M13.5 15.5h6"/>',
        'firstaid' => '<rect x="3" y="6.5" width="18" height="13.5" rx="2"/><path d="M9 6.5V4h6v2.5M12 10v6.5M8.8 13.2h6.4"/>',
        'car' => '<path d="M3 13.5 5 8h14l2 5.5V18h-2.5M5.5 18H3v-4.5h18"/><circle cx="7.5" cy="18" r="2"/><circle cx="16.5" cy="18" r="2"/>',
        'moto' => '<circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5 9 10h5l4.5 6.5M14 10l-2-4h3M9 10l-1.5-2.5"/>',
        'camera' => '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
        'zoom' => '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5M10.5 8v5M8 10.5h5"/>',
        'arrow' => '<path d="M5 12h14M13 6l6 6-6 6"/>',
        'kiosk' => '<rect x="5" y="2.5" width="14" height="11" rx="2"/><path d="M9 21h6M12 13.5V21M9.5 8l1.8 1.8L15 6.5"/>',
        'bolt' => '<path d="M13 2.5 4.5 13.5H11l-1 8 8.5-11H12z"/>',
    ];
    return '<svg class="pb-ico' . ($cls !== '' ? ' ' . $cls : '') . '" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' . ($p[$n] ?? $p['check']) . '</svg>';
}

/** Ikona: cesta k SVG v gfx/ (obrázek s popisným alt), jinak inline pbIcon. */
function pbVisual($icon, $label) {
    $icon = lpS($icon);
    if (strpos($icon, '/') === false) return pbIcon($icon);
    return '<img src="/' . he(ltrim($icon, '/')) . '" alt="' . he($label) . '" width="40" height="40" loading="lazy" decoding="async">';
}

/** Odznak pobočky (obslužná / samoobslužná). */
function pbBadge($badge, $key, $self) {
    return '<span class="pb-badge' . ($self ? ' pb-badge--self' : '') . '">' . pbIcon($self ? 'kiosk' : 'user') .
        '<span' . ($key !== '' ? ' data-cms-key="' . he($key) . '"' : '') . '>' . he(lpPlain($badge)) . '</span></span>';
}

/** Statistiky (velká čísla) — [['v','l']]. Čistě číselná hodnota dostane počítadlo (JS). */
function pbStatsHtml($stats, $cls = '') {
    $h = '';
    foreach ((array)$stats as $i => $s) {
        $v = lpPlain($s['v'] ?? '');
        if ($v === '') continue;
        $num = preg_match('/^(\d+)(.*)$/u', $v, $m) ? '<span data-pb-count="' . (int)$m[1] . '">' . he($m[1]) . '</span>' . he($m[2]) : he($v);
        $h .= '<li class="pb-stat lp-reveal" style="--i:' . (int)$i . '"><span class="pb-stat-v">' . $num . '</span><span class="pb-stat-l">' . he(lpPlain($s['l'] ?? '')) . '</span></li>';
    }
    return $h !== '' ? '<ul class="pb-stats' . ($cls !== '' ? ' ' . $cls : '') . '">' . $h . '</ul>' : '';
}

/** Klíčová fakta jako chipy s ikonou — [['i','t']]. */
function pbFactsHtml($facts) {
    $h = '';
    foreach ((array)$facts as $f) {
        if (!is_array($f) || lpPlain($f['t'] ?? '') === '') continue;
        $h .= '<li>' . pbIcon(lpS($f['i'] ?? 'check')) . '<span>' . he(lpPlain($f['t'])) . '</span></li>';
    }
    return $h !== '' ? '<ul class="pb-facts">' . $h . '</ul>' : '';
}

/**
 * Hero detailu pobočky. $o: img[src,srcset,w,h] (pbBranchCfg), alt, badge, badgeKey, self, title, titleKey,
 * highlight, address, addressKey, maps, stats, facts, primary[label,href], secondary[label,href], video(label|'').
 */
function pbHeroHtml($o) {
    $img = (array)$o['img'];
    $p = (array)$o['primary'];
    $s = (array)$o['secondary'];
    return '<section class="pb-hero" aria-labelledby="lp-h1"><div class="container"><div class="pb-hero-card">' .
        '<div class="pb-hero-media"><img src="/' . he($img[0]) . '" srcset="' . he($img[1]) . '" sizes="(min-width:900px) 46vw, 100vw" alt="' . he($o['alt']) . '" width="' . (int)$img[2] . '" height="' . (int)$img[3] . '" fetchpriority="high" decoding="async">' .
            pbBadge($o['badge'], $o['badgeKey'], $o['self']) .
            ($o['video'] !== '' ? '<a class="pb-hero-play" href="#pb-video" aria-label="' . he($o['video']) . '">' . pbIcon('play') . '<span aria-hidden="true">' . he($o['video']) . '</span></a>' : '') . '</div>' .
        '<div class="pb-hero-body">' .
            '<h1 id="lp-h1" data-cms-key="' . he($o['titleKey']) . '">' . sanitizeHtml(lpS($o['title'])) . '</h1>' .
            (lpPlain($o['highlight']) !== '' ? '<p class="pb-hl">' . pbIcon('bolt') . '<span>' . he(lpPlain($o['highlight'])) . '</span></p>' : '') .
            '<a class="pb-addr" href="' . he($o['maps']) . '" target="_blank" rel="noopener">' . pbIcon('pin') . '<span data-cms-key="' . he($o['addressKey']) . '">' . he(lpPlain($o['address'])) . '</span></a>' .
            pbStatsHtml($o['stats']) .
            '<div class="lp-cta-row" data-lp-sentinel>' .
                '<a class="lp-btn lp-btn-primary" href="' . he($p['href']) . '">' . lpIcon('cal') . '<span>' . he(lpPlain($p['label'])) . '</span></a>' .
                '<a class="lp-btn lp-btn-ghost" href="' . he($s['href']) . '">' . lpIcon('moto') . '<span>' . he(lpPlain($s['label'])) . '</span></a></div>' .
            pbFactsHtml($o['facts']) .
        '</div></div></div></section>';
}

/** Dvě info karty: o pobočce (text) + provozní doba (hours) — celé texty z CMS. */
function pbInfoHtml($V, $b, $k) {
    $card = function ($cls, $icon, $id, $h2, $h2Key, $html, $key) {
        if (lpPlain($html) === '') return '';
        return '<article class="pb-info-card' . $cls . ' lp-reveal" aria-labelledby="' . $id . '"><span class="pb-info-ico">' . pbIcon($icon) . '</span>' .
            '<h2 id="' . $id . '" data-cms-key="' . $h2Key . '">' . he(lpPlain($h2)) . '</h2><p data-cms-key="' . $key . '">' . sanitizeHtml(lpS($html)) . '</p></article>';
    };
    $h = $card('', 'pin', 'pb-about-h', $V['about_title'], 'web.pobocky.v2.about_title', $b['text'] ?? '', $k . '.text') .
        $card(' pb-info-card--dark', 'clock', 'pb-hours-h', $V['hours_title'], 'web.pobocky.v2.hours_title', $b['hours'] ?? '', $k . '.hours');
    return $h !== '' ? '<section class="pb-info"><div class="container"><div class="pb-info-grid">' . $h . '</div></div></section>' : '';
}

/** Video pobočky (YouTube → embed, jinak <video>), plakát = první fotka galerie. */
function pbVideoHtml($url, $title, $key, $poster, $lead = '') {
    $url = trim(strip_tags(lpS($url)));
    if ($url === '' || !preg_match('#^https://#i', $url)) return '';
    $alt = he(lpPlain($title));
    if (preg_match('#(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{6,})#', $url, $m)) {
        $player = '<iframe src="https://www.youtube-nocookie.com/embed/' . $m[1] . '" title="' . $alt . '" loading="lazy" allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen></iframe>';
    } else {
        $player = '<video controls playsinline preload="metadata"' . ($poster !== '' ? ' poster="/' . he($poster) . '"' : '') . ' src="' . he($url) . '" aria-label="' . $alt . '"></video>';
    }
    return '<section class="pb-video" id="pb-video" aria-labelledby="pb-video-h"><div class="container"><div class="pb-video-card lp-reveal">' .
        '<div class="pb-video-txt"><h2 id="pb-video-h"><span class="pb-video-ico">' . pbIcon('play') . '</span><span data-cms-key="' . he($key) . '">' . $alt . '</span></h2>' .
        (lpPlain($lead) !== '' ? '<p data-cms-key="web.pobocky.v2.video_lead">' . he(lpPlain($lead)) . '</p>' : '') . '</div>' .
        '<div class="pb-video-frame">' . $player . '</div></div></div></section>';
}

/** Mapa + adresa + dojezd + navigace. */
function pbMapHtml($V, $VB, $b, $k, $mapSrc, $maps, $title) {
    $dist = '';
    foreach ((array)($VB['dist'] ?? []) as $d) if (lpPlain($d) !== '') $dist .= '<li>' . pbIcon('car') . '<span>' . he(lpPlain($d)) . '</span></li>';
    return '<section class="pb-map" aria-labelledby="pb-map-h"><div class="container"><div class="pb-map-card lp-reveal">' .
        '<div class="pb-map-info"><h2 id="pb-map-h" data-cms-key="web.pobocky.v2.map_title">' . he(lpPlain($V['map_title'])) . '</h2>' .
        '<p class="pb-map-addr">' . pbIcon('pin') . '<span>' . he(lpPlain($b['address'] ?? '')) . '</span></p>' .
        ($dist !== '' ? '<ul class="pb-dist">' . $dist . '</ul>' : '') .
        '<a class="lp-btn lp-btn-ghost pb-map-btn" href="' . he($maps) . '" target="_blank" rel="noopener">' . pbIcon('nav') . '<span>' . he(lpPlain($V['map_open'])) . '</span></a></div>' .
        ($mapSrc !== '' ? '<div class="pb-map-frame"><iframe loading="lazy" referrerpolicy="no-referrer-when-downgrade" allowfullscreen title="' . he($title) . '" src="' . he($mapSrc) . '"></iframe></div>' : '') .
        '</div></div></section>';
}

/** Karta pobočky (přehled) — $o: href, rez, img, alt, badge, badgeKey, self, title, titleKey, hl, stats, facts, address, addressKey, hours, hoursKey, detail, detailKey, book. */
function pbCardHtml($o, $i) {
    return '<article class="pb-card' . ($o['self'] ? ' pb-card--self' : '') . ' lp-reveal" style="--i:' . (int)$i . '">' .
        '<a class="pb-card-media" href="' . he($o['href']) . '" tabindex="-1" aria-hidden="true">' .
            ($o['img'] !== '' ? '<img src="/' . he($o['img']) . '" alt="' . he($o['alt']) . '" width="640" height="480" loading="lazy" decoding="async">' : '') . '</a>' .
        '<div class="pb-card-body">' . pbBadge($o['badge'], $o['badgeKey'], $o['self']) .
            '<h2><a href="' . he($o['href']) . '" data-cms-key="' . he($o['titleKey']) . '">' . sanitizeHtml(lpS($o['title'])) . '</a></h2>' .
            (lpPlain($o['hl']) !== '' ? '<p class="pb-hl">' . pbIcon('bolt') . '<span>' . he(lpPlain($o['hl'])) . '</span></p>' : '') .
            pbStatsHtml($o['stats'], 'pb-stats--sm') . pbFactsHtml($o['facts']) .
            '<p class="pb-card-line">' . pbIcon('pin') . '<span data-cms-key="' . he($o['addressKey']) . '">' . he(lpPlain($o['address'])) . '</span></p>' .
            '<p class="pb-card-line">' . pbIcon('clock') . '<span data-cms-key="' . he($o['hoursKey']) . '">' . sanitizeHtml(lpS($o['hours'])) . '</span></p>' .
            '<div class="pb-card-cta"><a class="lp-btn lp-btn-primary" href="' . he($o['rez']) . '">' . lpIcon('cal') . '<span>' . he(lpPlain($o['book'])) . '</span></a>' .
            '<a class="lp-btn lp-btn-ghost" href="' . he($o['href']) . '"><span data-cms-key="' . he($o['detailKey']) . '">' . he(lpPlain($o['detail'])) . '</span>' . lpIcon('arrow') . '</a></div>' .
        '</div></article>';
}
