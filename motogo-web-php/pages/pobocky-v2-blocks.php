<?php
// ===== Pobočky — landing v2: průvodce „Jak to probíhá“, výbava, galerie, srovnání, CTA =====
// Kroky z CMS (`web.pobocky.branches.<i>.steps`: „1. … <br>2. …“) se rozparsují; text
// každého kroku zůstává celý. Krátké titulky + ikony/fotky kroků jen když počet kroků sedí
// s konfigurací (jinak titulek = začátek textu do „—“ / první věty). Bez JS: kroky pod sebou.

/** Kroky z CMS HTML → seznam HTML textů bez úvodního „N.“ */
function pbParseSteps($html) {
    $out = [];
    foreach (preg_split('~<br\s*/?>~i', lpS($html)) as $p) {
        if (lpPlain($p) === '') continue;
        $out[] = trim(preg_replace('~^((?:\s*<(?!/)[^>]+>)*)\s*\d+\.\s*~u', '$1', trim($p), 1));
    }
    return $out;
}

/** Záložní titulek kroku: text do „—“ / „:“ / konce první věty, max ~8 slov. */
function pbStepTitle($html) {
    $t = preg_split('~\s[—–-]\s|:\s|(?<=[a-zà-ž\)])\.\s~u', lpPlain($html))[0] ?? '';
    $w = preg_split('/\s+/u', trim($t));
    return count($w) > 8 ? implode(' ', array_slice($w, 0, 8)) . '…' : trim($t);
}

/** Interaktivní průvodce. $gal = pbGallery(), $cfg = pbBranchCfg()['guide'], $titles = texty v2. */
function pbGuideHtml($V, $b, $k, $titles, $cfg, $gal, $rezHref) {
    $steps = pbParseSteps($b['steps'] ?? '');
    $n = count($steps);
    if (!$n) return '';
    $fit = is_array($titles) && count($titles) === $n;
    $cfgFit = is_array($cfg) && count($cfg) === $n;
    $open = he(t('gallery.openImage'));
    $items = $dots = '';
    foreach ($steps as $i => $html) {
        $ttl = $fit && lpPlain($titles[$i]) !== '' ? lpPlain($titles[$i]) : pbStepTitle($html);
        $c = $cfgFit ? $cfg[$i] : ['check', []];
        $ph = '';
        foreach ((array)($c[1] ?? []) as $gi) {
            if (!isset($gal[$gi])) continue;
            $ph .= '<a href="/' . he($gal[$gi][1]) . '" data-gallery="branch" data-index="' . (int)$gi . '" aria-label="' . $open . '"><img src="/' . he($gal[$gi][0]) . '" alt="' . he($gal[$gi][2]) . '" width="320" height="240" loading="lazy" decoding="async">' . pbIcon('zoom') . '</a>';
        }
        $items .= '<li class="pb-gstep lp-reveal" id="krok-' . ($i + 1) . '" style="--i:' . $i . '" data-title="' . he($ttl) . '">' .
            '<div class="pb-gstep-rail"><span class="pb-gstep-n">' . ($i + 1) . '</span></div>' .
            '<div class="pb-gstep-card"><div class="pb-gstep-head"><span class="pb-gstep-ico">' . pbVisual($c[0] ?? 'check', $ttl) . '</span><h3>' . he($ttl) . '</h3></div>' .
            '<p>' . sanitizeHtml($html) . '</p>' . ($ph !== '' ? '<div class="pb-gstep-photos">' . $ph . '</div>' : '') . '</div></li>';
        $dots .= '<li><button type="button" data-step="' . $i . '" aria-label="' . he(($i + 1) . '. ' . $ttl) . '">' . ($i + 1) . '</button></li>';
    }
    $tpl = lpS($V['guide_step']);
    return '<section class="pb-guide" aria-labelledby="pb-guide-h" data-pb-guide><div class="container"><div class="pb-guide-card">' .
        '<div class="pb-guide-top"><h2 id="pb-guide-h" data-cms-key="' . $k . '.steps_title">' . he(lpPlain($b['steps_title'] ?? '')) . '</h2>' .
        '<p class="pb-guide-hint" data-cms-key="web.pobocky.v2.guide_hint">' . he(lpPlain($V['guide_hint'])) . '</p></div>' .
        '<div class="pb-guide-bar" hidden><p class="pb-guide-count" aria-live="polite" data-tpl="' . he($tpl) . '">' . he(str_replace(['{n}', '{total}'], ['1', (string)$n], $tpl)) . '</p>' .
        '<ol class="pb-guide-dots">' . $dots . '</ol><div class="pb-guide-prog" aria-hidden="true"><i></i></div></div>' .
        '<ol class="pb-guide-list">' . $items . '</ol>' .
        '<div class="pb-guide-nav"><button type="button" class="pb-guide-btn" data-dir="-1" hidden>' . lpIcon('arrow') . '<span>' . he(lpPlain($V['guide_prev'])) . '</span></button>' .
        '<button type="button" class="pb-guide-btn pb-guide-btn--next" data-dir="1" hidden><span>' . he(lpPlain($V['guide_next'])) . '</span>' . lpIcon('arrow') . '</button>' .
        '<a class="lp-btn lp-btn-primary pb-guide-done" href="' . he($rezHref) . '">' . lpIcon('cal') . '<span>' . he(lpPlain($V['guide_done'])) . '</span></a></div>' .
        (lpAdmin() ? '<div class="pb-admin-src" data-cms-key="' . $k . '.steps">' . sanitizeHtml(lpS($b['steps'] ?? '')) . '</div>' : '') .
        '</div></div></section>';
}

/** Výbava: ikonový seznam (texty v2) + celý text z CMS + „V motorce najdeš“. */
function pbGearHtml($V, $VB, $b, $k) {
    $list = function ($items) {
        $h = '';
        foreach ((array)$items as $i => $g) {
            if (!is_array($g) || lpPlain($g['t'] ?? '') === '') continue;
            $h .= '<li class="lp-reveal" style="--i:' . (int)$i . '"><span class="pb-gear-ico">' . pbIcon(lpS($g['i'] ?? 'check')) . '</span><span>' . he(lpPlain($g['t'])) . '</span></li>';
        }
        return $h;
    };
    $gear = $list($VB['gear'] ?? []);
    $bike = $list($VB['in_bike'] ?? []);
    if ($gear === '' && lpPlain($b['gear'] ?? '') === '') return '';
    return '<section class="pb-gear" aria-labelledby="pb-gear-h"><div class="container"><div class="pb-gear-card">' .
        '<h2 id="pb-gear-h" data-cms-key="web.pobocky.v2.gear_title">' . he(lpPlain($V['gear_title'])) . '</h2>' .
        ($gear !== '' ? '<ul class="pb-gear-grid">' . $gear . '</ul>' : '') .
        (lpPlain($VB['sizes'] ?? '') !== '' ? '<p class="pb-gear-size">' . pbIcon('tag') . '<span>' . he(lpPlain($VB['sizes'])) . '</span></p>' : '') .
        '<p class="pb-gear-text" data-cms-key="' . $k . '.gear">' . sanitizeHtml(lpS($b['gear'] ?? '')) . '</p>' .
        ($bike !== '' ? '<h3 data-cms-key="web.pobocky.v2.in_bike_title">' . he(lpPlain($V['in_bike_title'])) . '</h3><ul class="pb-gear-grid pb-gear-grid--sm">' . $bike . '</ul>' : '') .
        '</div></div></section>';
}

/** Fotogalerie jako swipe karusel (sdílený lightbox přes data-gallery, ovládání js/landing.js). */
function pbGalleryHtml($gal, $title, $key, $T) {
    if (!$gal) return '';
    $open = he(t('gallery.openImage'));
    $h = '';
    foreach ($gal as $i => $g) {
        $h .= '<li class="pb-shot"><a href="/' . he($g[1]) . '" data-gallery="branch" data-index="' . (int)$i . '" aria-label="' . $open . '">' .
            '<img src="/' . he($g[0]) . '" alt="' . he($g[2]) . '" width="640" height="480" loading="lazy" decoding="async">' .
            '<span class="pb-shot-cap">' . he($g[2]) . '</span><span class="pb-shot-zoom">' . pbIcon('zoom') . '</span></a></li>';
    }
    return '<section class="pb-gallery" aria-labelledby="pb-gal-h"><div class="container"><div class="lp-head">' .
        '<h2 id="pb-gal-h" data-cms-key="' . he($key) . '">' . he(lpPlain($title)) . '</h2><span class="pb-gal-n">' . pbIcon('camera') . count($gal) . '</span></div></div>' .
        '<div class="lp-track-wrap"><button type="button" class="lp-nav lp-nav-prev" aria-label="' . he(lpS($T['fleet_prev'])) . '" hidden>' . lpIcon('arrow') . '</button>' .
        '<ul class="lp-track pb-track" data-lp-track>' . $h . '</ul>' .
        '<button type="button" class="lp-nav lp-nav-next" aria-label="' . he(lpS($T['fleet_next'])) . '" hidden>' . lpIcon('arrow') . '</button></div>' .
        '<div class="container"><div class="lp-progress" aria-hidden="true"><i></i></div></div></section>';
}

/** Srovnání poboček (tabulka; na mobilu karty řádků). $heads = [[title, href, badge, self]], $counts = [n, n]. */
function pbCompareHtml($V, $heads, $counts) {
    $th = '';
    foreach ($heads as $hd) $th .= '<th scope="col"><a href="' . he($hd[1]) . '">' . he(lpPlain($hd[0])) . '</a>' . pbBadge($hd[2], '', $hd[3]) . '</th>';
    $rows = '';
    foreach ((array)($V['compare'] ?? []) as $r) {
        if (!is_array($r) || lpPlain($r['label'] ?? '') === '') continue;
        $tds = '';
        foreach ([0, 1] as $c) {
            $v = (array)($r['v'][$c] ?? []);
            $t = lpPlain($v['t'] ?? '');
            if (!empty($r['count'])) $t = str_replace('{n}', (string)(int)($counts[$c] ?? 0), $t);
            $ok = array_key_exists('ok', $v) ? ((int)$v['ok'] ? '<span class="pb-yes">' . pbIcon('check') . '</span>' : '<span class="pb-no">' . pbIcon('x') . '</span>') : '';
            $tds .= '<td data-label="' . he(lpPlain($heads[$c][0] ?? '')) . '"' . (!empty($r['count']) ? ' class="pb-cmp-big"' : '') . '>' . $ok . '<span>' . he($t) . '</span></td>';
        }
        $rows .= '<tr class="lp-reveal"><th scope="row">' . pbIcon(lpS($r['i'] ?? 'check')) . '<span>' . he(lpPlain($r['label'])) . '</span></th>' . $tds . '</tr>';
    }
    if ($rows === '') return '';
    return '<section class="pb-cmp" aria-labelledby="pb-cmp-h"><div class="container"><div class="pb-cmp-card">' .
        '<h2 id="pb-cmp-h" data-cms-key="web.pobocky.v2.compare_title">' . he(lpPlain($V['compare_title'])) . '</h2>' .
        (lpPlain($V['compare_intro'] ?? '') !== '' ? '<p class="pb-cmp-intro" data-cms-key="web.pobocky.v2.compare_intro">' . he(lpPlain($V['compare_intro'])) . '</p>' : '') .
        '<table class="pb-cmp-t"><thead><tr><td></td>' . $th . '</tr></thead><tbody>' . $rows . '</tbody></table></div></div></section>';
}

/** Závěrečné CTA detailu: CMS texty web.pobocky.cta.* + motorky pobočky + odkaz zpět. */
function pbCtaHtml($cta, $V, $rezHref, $katHref, $back) {
    return '<section class="lp-cta" aria-labelledby="lp-cta-h"><div class="container"><div class="lp-cta-card">' .
        '<h2 id="lp-cta-h" data-cms-key="web.pobocky.cta.title">' . sanitizeHtml(lpS($cta['title'] ?? '')) . '</h2>' .
        (lpPlain($cta['text'] ?? '') !== '' ? '<p data-cms-key="web.pobocky.cta.text">' . sanitizeHtml(lpS($cta['text'])) . '</p>' : '') .
        '<div class="lp-cta-btns"><a class="lp-btn lp-btn-primary" href="' . he($rezHref) . '">' . lpIcon('cal') . '<span data-cms-key="web.pobocky.cta.button">' . he(lpPlain($cta['button'] ?? '')) . '</span></a>' .
        ($katHref !== '' ? '<a class="lp-btn lp-btn-ghost" href="' . he($katHref) . '"><span>' . he(lpPlain($V['motos_branch'])) . '</span></a>' : '') .
        ($back !== '' ? '<a class="lp-btn lp-btn-ghost" href="/pobocky"><span data-cms-key="web.pobocky.back_link">' . he(lpPlain($back)) . '</span></a>' : '') .
        '</div></div></div></section>';
}
