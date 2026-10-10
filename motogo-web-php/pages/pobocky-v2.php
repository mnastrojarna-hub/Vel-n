<?php
// ===== Pobočky (přehled) — landing v2 (viz landing.php, pages/pobocky-v2-lib.php) =====
// Vkládá se z pages/pobocky.php ($content = require …), používá jeho $sb, $C, $defaults, $bc.
// Pořadí (mobil): drobečky → akční panel (H1 + intro + 2 CTA + chipy) → 2 velké karty
// poboček → srovnání Mezná vs Velké Němčice → motorky → CTA → sticky lišta.

require_once __DIR__ . '/pobocky-v2-lib.php';

$T = lpTexts($sb);
$TC = $T['common'];
$V = pbV2Texts($C);
$pbAll = $sb->fetchMotos();

$pbCards = '';
$pbHeads = [];
$pbCounts = [];
foreach (array_keys($defaults['branches']) as $i) {
    $b = pobockyBranch($C, $defaults, $i);
    $k = 'web.pobocky.branches.' . $i;
    $cfg = pbBranchCfg($b['slug']);
    $VB = is_array($V['branches'][$i] ?? null) ? $V['branches'][$i] : [];
    $bid = strtolower(trim(lpS($b['branch_id'] ?? '')));
    $n = count(lpFleet(pbBranchMotos($pbAll, $bid)));
    $pbCounts[] = $n;
    $stats = is_array($VB['stats'] ?? null) ? $VB['stats'] : [];
    if ($n > 0) $stats[] = ['v' => (string)$n, 'l' => $V['motos_label']];
    $href = '/pobocky/' . $b['slug'];
    $pbHeads[] = [$VB['short'] ?? $b['title'], $href, $b['badge'], $cfg['self']];
    $pbCards .= pbCardHtml([
        'href' => $href,
        'rez' => '/rezervace' . (preg_match('/^[0-9a-f-]{36}$/', $bid) ? '?pobocka=' . $bid : ''),
        'img' => $cfg['card'],
        'alt' => lpPlain($b['title']),
        'badge' => $b['badge'],
        'badgeKey' => $k . '.badge',
        'self' => $cfg['self'],
        'title' => $b['title'],
        'titleKey' => $k . '.title',
        'hl' => $VB['highlight'] ?? '',
        'stats' => $stats,
        'facts' => $VB['facts'] ?? [],
        'address' => $b['address'],
        'addressKey' => $k . '.address',
        'hours' => $b['hours'],
        'hoursKey' => $k . '.hours',
        'detail' => $C['detail_button'] ?? $defaults['detail_button'],
        'detailKey' => 'web.pobocky.detail_button',
        'book' => $V['book_here'],
    ], $i);
}

$pbPanel = renderLpPanel([
    'h1' => $C['h1'] ?? '',
    'h1Key' => 'web.pobocky.h1',
    'lead' => $C['intro'] ?? '',
    'leadKey' => 'web.pobocky.intro',
    'primary' => $V['panel']['cta_primary'],
    'secondary' => $V['panel']['cta_secondary'],
    'chips' => $V['panel']['chips'] ?? [],
    'keyBase' => 'web.pobocky.v2.panel',
    'bg' => '/gfx/pobocky/velke-nemcice/vydejni-box-640.webp',
]);

$cta = is_array($C['cta'] ?? null) ? array_merge($defaults['cta'], $C['cta']) : $defaults['cta'];

return '<main id="content" class="lp-main lp-main--page pb-main"><div class="container">' . $bc . '</div>' .
    $pbPanel .
    '<section class="pb-cards" aria-labelledby="pb-cards-h"><div class="container"><h2 id="pb-cards-h" data-cms-key="web.pobocky.v2.cards_title">' . he(lpPlain($V['cards_title'])) . '</h2>' .
    '<div class="pb-cards-grid">' . $pbCards . '</div></div></section>' .
    pbCompareHtml($V, $pbHeads, $pbCounts) .
    renderLpFleet($pbAll, $TC) .
    pbCtaHtml($cta, $V, '/rezervace', '', '') .
    '</main>' .
    renderLpSticky($TC);
