<?php
// ===== MotoGo24 Web PHP — Landing v2: pruh garancí hned pod hero (viz landing.php) =====
// Zadání majitele 2026-10-22: hned pod hero bannerem garance — 0 Kč spoluúčast při
// dodržení smlouvy, posun termínu zdarma, prodloužení/zkrácení, úpravy kdykoliv.
// Texty: data/landing-trust.php (guar_*, guarantees, anchor_*) ← lang/v2/<lang>/landing.php ← CMS
// web.landing.common.guar_* / guarantees.N.* / anchor_*. Ikony lpIco2() (landing-trust.php).
// 2026-10-23: 3 velké garance nahoře (položky 'big'), menší pod nimi, cenová kotva (kauce) v hlavě
// karty, kompaktní varianta pro detail motorky. CSS: landing-guar.css (garance), landing-promo.css (kotva).
// lpAssure (uklidňující řádek s fajfkami) přesunut sem z landing-sections.php (limit velikosti souboru).

/**
 * Pruh garancí: [kotva] nadpis, lead, velké dlaždice ('big'), malé dlaždice a poznámka s hvězdičkou.
 * Položky [{icon,title,text,big?,pos?}] — pořadí ve skupině dle 'pos', jinak dle indexu (CMS klíč = index);
 * {zero} v titulku/textu = 0 v měně návštěvníka (jako kotva). Hvězdičky: * spoluúčast, ** posun/vratky (guar_note).
 * $o: 'only' => [...] jen vybrané položky (index int nebo název ikony, např. ['edit','swap','storno','shield']),
 *     'compact' => true (detail motorky: bez leadu a kotvy, menší nadpis a velké dlaždice),
 *     'anchor' => false (bez cenové kotvy; výchozí = jen v plné variantě).
 */
function renderLpGuarantees($T, $o = []) {
    $o = is_array($o) ? $o : [];
    $compact = !empty($o['compact']);
    $only = isset($o['only']) ? array_values((array)$o['only']) : null;
    $groups = ['big' => [], 'small' => []];
    foreach ((array)($T['guarantees'] ?? []) as $i => $g) {
        if (!is_array($g) || lpPlain($g['title'] ?? '') === '') continue;
        $ico = lpS($g['icon'] ?? '');
        if ($only !== null && !in_array($i, $only, true) && !in_array($ico, $only, true)) continue;
        $big = !empty($g['big']);
        $html = '<li class="lp-guar-i' . ($big ? ' lp-guar-i--big' : '') . '"><span class="lp-guar-ico">' . lpIco2($ico) . '</span>' .
            '<span class="lp-guar-t" data-cms-key="web.landing.common.guarantees.' . $i . '.title">' . lpNoBreakHyphen(lpAnchorFill($g['title'])) . '</span>' .
            (lpPlain($g['text'] ?? '') !== '' ? '<span class="lp-guar-s" data-cms-key="web.landing.common.guarantees.' . $i . '.text">' . lpAnchorFill($g['text']) . '</span>' : '') . '</li>';
        $groups[$big ? 'big' : 'small'][] = [is_numeric($g['pos'] ?? null) ? (float)$g['pos'] : 100 + (int)$i, (int)$i, $html];
    }
    if (!$groups['big'] && !$groups['small']) return '';
    $lists = '';
    foreach (['big' => 'lp-guar-top', 'small' => 'lp-guar-list'] as $k => $cls) {
        if (!$groups[$k]) continue;
        usort($groups[$k], function ($a, $b) { return [$a[0], $a[1]] <=> [$b[0], $b[1]]; });
        $lists .= '<ul class="' . $cls . '">' . implode('', array_column($groups[$k], 2)) . '</ul>';
    }
    [$h2, $aria] = lpH2('lp-guar-h', $T['guar_title'] ?? '', 'web.landing.common.guar_title');
    $anchor = (!$compact && ($o['anchor'] ?? true)) ? renderLpAnchor($T) : '';
    return '<section class="lp-guar' . ($compact ? ' lp-guar--compact' : '') . '"' . $aria . '><div class="container"><div class="lp-guar-card">' . $anchor . $h2 .
        (!$compact && lpPlain($T['guar_lead'] ?? '') !== '' ? '<p class="lp-guar-lead" data-cms-key="web.landing.common.guar_lead">' . he(lpPlain($T['guar_lead'])) . '</p>' : '') .
        $lists .
        (lpPlain($T['guar_note'] ?? '') !== '' ? '<p class="lp-guar-note" data-cms-key="web.landing.common.guar_note">' . he(lpNbspTxt($T['guar_note'])) . '</p>' : '') .
        '</div></div></section>';
}

/**
 * Uklidňující řádek pod CTA („Rezervaci upravíš zdarma · Termín posuneš zdarma · Storno zdarma…“): části
 * oddělené „·“/„•“ → každá na vlastním řádku s fajfkou (ul.lp-assure.is-split). V CMS adminu nerozdělené
 * <p> s data-cms-key (inline editor ukládá innerHTML — nesmí uložit naši značku). $cls = doplňková třída.
 * Volají: akční panel (renderLpPanel), detail motorky, hero info stránek (landing-info.php). CSS: landing.css.
 */
function lpAssure($text, $key = 'web.landing.common.assurance', $cls = '') {
    $plain = lpPlain($text);
    if ($plain === '') return '';
    $c = 'lp-assure' . ($cls !== '' ? ' ' . $cls : '');
    $parts = array_values(array_filter(array_map('trim', preg_split('/\s+[·•]\s+/u', $plain)), 'strlen'));
    if (lpAdmin() || count($parts) < 2) return '<p class="' . he($c) . '" data-cms-key="' . he($key) . '">' . lpIcon('check') . he($plain) . '</p>';
    $li = '';
    foreach ($parts as $part) $li .= '<li class="lp-assure-i">' . lpIcon('check') . '<span>' . he($part) . '</span></li>';
    return '<ul class="' . he($c) . ' is-split">' . $li . '</ul>';
}

/** Slova se spojovníkem („будь-коли“) v titulku nezalamovat na spojovníku (mimo CMS admin — editor ukládá HTML). */
function lpNoBreakHyphen($escaped) {
    return lpAdmin() ? $escaped : preg_replace('/(?<![\p{L}\p{N}-])[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)+/u', '<span class="lp-nobr">$0</span>', $escaped);
}

/** Částka/rozpětí v měně návštěvníka. Symbol jako všude na webu (lpMoneyFrom, money()): za číslem
 *  „0 Kč“ / „0 €“ / „0 zł“ ve všech jazycích — ať se na jedné stránce nemíchá „€0“ s „21 €“. $iso = věty kotvy:
 *  CZK v cizím jazyce jako cizí texty kotvy („30.000 CZK“ → „0 CZK“, en „CZK 30,000“ → „CZK 0“) — ne „CZK“ i „Kč“ v jedné větě.
 *  Tisíce dle textu věty: en „,“, de/es/nl „.“, jinak NBSP — ať se v jedné větě nemíchají oddělovače. */
function lpAnchorMoney($nums, $cur, $iso = false) {
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $sep = ['en' => ',', 'de' => '.', 'es' => '.', 'nl' => '.'][$lang] ?? "\u{00A0}";
    $n = implode('–', array_map(function ($x) use ($sep) { return number_format($x, 0, ',', $sep); }, (array)$nums));
    if ($iso && $cur === 'CZK' && $lang !== 'cs') return $lang === 'en' ? "CZK\u{00A0}" . $n : $n . "\u{00A0}CZK";
    return $n . "\u{00A0}" . (defined('CURRENCY_META') ? (CURRENCY_META[$cur]['symbol'] ?? 'Kč') : 'Kč');
}

/** „0“ v měně návštěvníka („0 Kč“, „0 €“, „0 zł“) — kotva ani garance nesmí na EUR/PLN stránce tvrdit „0 Kč“. */
function lpZeroMoney($iso = false) {
    return lpAnchorMoney([0], function_exists('currencyDetect') ? strtoupper(currencyDetect()) : 'CZK', $iso);
}

/** „ (≈ 820–1 240 €)“ = 20–30 tis. Kč v cizí měně (zaokrouhleno na desítky); u CZK / bez kurzu prázdné. */
function lpAnchorApprox() {
    if (!function_exists('currencyDetect') || !function_exists('currencyRates')) return '';
    $cur = strtoupper(currencyDetect());
    $rate = (float)(currencyRates()['rates'][$cur] ?? 0);
    if ($cur === 'CZK' || $rate <= 0 || !isset(CURRENCY_META[$cur])) return '';
    $f = function ($czk) use ($rate) { return round($czk / $rate / 10) * 10; };
    return ' (≈' . "\u{00A0}" . lpAnchorMoney([$f(20000), $f(30000)], $cur) . ')';
}

/** Nezalomitelné mezery v částkách („30 000 Kč“, „CZK 30 000“), datech („22. 10. 2026“, „22 Oct 2026“)
 *  a před ?!:; (francouzština); pomlčka v rozpětí čísel („20.000–30.000“) se nezalomí (U+2060). */
function lpNbsp($s) {
    $s = preg_replace('/(?<=\d) (?=\d{3}(?!\d))/u', "\u{00A0}", $s);
    $s = preg_replace('/(?<=\d) (?=Kč|CZK|€|zł|%)|(?<=CZK|€) (?=\d)/u', "\u{00A0}", $s);
    $s = preg_replace('/(?<=\d\.) (?=\d{1,2}\. ?\d{4}\b|\d{4}\b)|(?<=\d) (?=[A-Z][a-z]{2} \d{4}\b)|(?<=\d [A-Z][a-z]{2}) (?=\d{4}\b)/u', "\u{00A0}", $s);
    $s = preg_replace('/(?<=\d)–(?=\d)/u', "\u{2060}–\u{2060}", $s);
    return preg_replace('/ (?=[?!:;](?:\s|$))/u', "\u{00A0}", $s);
}

/** CMS hodnota → prostý text; mimo CMS admin s lpNbsp (admin edituje syrový text). */
function lpNbspTxt($v) {
    $s = lpPlain($v);
    return lpAdmin() ? $s : lpNbsp($s);
}

/** Šablona s {zero}/{approx} → HTML (escapováno); {zero} zvýrazněné. V CMS adminu syrová šablona. $iso viz lpAnchorMoney. */
function lpAnchorFill($tpl, $zeroCls = '', $iso = false) {
    $tpl = lpPlain($tpl);
    if (lpAdmin()) return he($tpl);
    if (strpos($tpl, '{approx}') !== false) $tpl = str_replace('{approx}', lpAnchorApprox(), $tpl);
    $zero = he(lpZeroMoney($iso));
    if ($zeroCls !== '') $zero = '<b class="' . $zeroCls . '">' . $zero . '</b>';
    return implode($zero, array_map(function ($p) { return he(lpNbsp($p)); }, explode('{zero}', $tpl)));
}

/** Cenová kotva „30 000 Kč kauce? U nás 0 Kč.“ + vysvětlení + datovaný zdroj (prázdný anchor_big = nic). */
function renderLpAnchor($T) {
    if (lpPlain($T['anchor_big'] ?? '') === '') return '';
    $k = 'web.landing.common.';
    $txt = function ($key) use ($T) { return he(lpNbspTxt($T[$key] ?? '')); };
    $el = function ($tag, $key, $cls, $html) use ($T, $k) {
        return lpPlain($T[$key] ?? '') !== '' ? '<' . $tag . ' class="' . $cls . '" data-cms-key="' . $k . $key . '">' . $html . '</' . $tag . '>' : '';
    };
    return '<div class="lp-anchor"><p class="lp-anchor-h">' .
        $el('span', 'anchor_big', 'lp-anchor-was', $txt('anchor_big')) . ' ' .
        $el('span', 'anchor_ours', 'lp-anchor-now', lpAnchorFill($T['anchor_ours'] ?? '', 'lp-anchor-zero', true)) . '</p>' .
        $el('p', 'anchor_sub', 'lp-anchor-sub', lpAnchorFill($T['anchor_sub'] ?? '', '', true)) .
        $el('p', 'anchor_src', 'lp-anchor-src', $txt('anchor_src')) . '</div>';
}
