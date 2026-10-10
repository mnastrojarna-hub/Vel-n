<?php
// ===== Detail pobočky — landing v2 (viz landing.php, pages/pobocky-v2-lib.php) =====
// Vkládá se z pages/pobocka-detail.php ($content = require …) a používá jeho proměnné
// ($sb, $C, $defaults, $idx, $b, $k, $title, $bc, $mapQ, $mapSrc, $videoTop, $cta, $branchId, $rezHref).
// Pořadí (mobil): drobečky → hero (foto, odznak, adresa, dojezd, 2 CTA, fakta) → video (Velké
// Němčice nahoře, zadání 2026-10-07) → o pobočce + provozní doba → průvodce „Jak to probíhá“
// → výbava → fotogalerie → mapa → motorky pobočky → CTA → druhá pobočka → sticky lišta.

require_once __DIR__ . '/pobocky-v2-lib.php';

$T = lpTexts($sb);
$TC = $T['common'];
$V = pbV2Texts($C);
$VB = is_array($V['branches'][$idx] ?? null) ? $V['branches'][$idx] : [];
$pbCfg = pbBranchCfg($b['slug']);
$pbGal = pbGallery($b, $VB);
$pbKat = preg_match('/^[0-9a-f-]{36}$/', $branchId) ? '/katalog?pobocka=' . $branchId : '';
$pbMaps = pbMapsHref($mapQ);

// Motorky pobočky (karusel + počet ve statistikách)
$pbMotos = pbBranchMotos($sb->fetchMotos(), $branchId);
$pbCount = count(lpFleet($pbMotos));
$pbStats = is_array($VB['stats'] ?? null) ? $VB['stats'] : [];
if ($pbCount > 0) $pbStats[] = ['v' => (string)$pbCount, 'l' => $V['motos_label']];

// Video: URL je jazykově nezávislá, ale CMS klíč bez překladu se v cizím jazyce přeskočí → vezmeme CS hodnotu.
$pbVideoUrl = lpS($b['video'] ?? '');
if ($pbVideoUrl === '' && i18nDetectLanguage() !== 'cs') {
    $pbCs = $sb->fetchWebTexts('pobocky', 'cs');
    $pbVideoUrl = lpS($pbCs['branches'][$idx]['video'] ?? '');
}
$pbVideo = pbVideoHtml($pbVideoUrl, $b['video_title'] ?? '', $k . '.video_title', $pbGal[0][0] ?? '', $V['video_lead'] ?? '');

$pbHero = pbHeroHtml([
    'img' => $pbCfg['hero'],
    'alt' => $title,
    'badge' => $b['badge'] ?? '',
    'badgeKey' => $k . '.badge',
    'self' => $pbCfg['self'],
    'title' => $b['title'] ?? '',
    'titleKey' => $k . '.title',
    'highlight' => $VB['highlight'] ?? '',
    'address' => $b['address'] ?? '',
    'addressKey' => $k . '.address',
    'maps' => $pbMaps,
    'stats' => $pbStats,
    'facts' => $VB['facts'] ?? [],
    'primary' => ['label' => $V['book_branch'], 'href' => $rezHref],
    'secondary' => ['label' => $V['motos_branch'], 'href' => $pbKat !== '' ? $pbKat : '/katalog'],
    'video' => $pbVideo !== '' ? lpPlain($V['video_badge']) : '',
]);

// Karusel motorek pobočky: vlastní nadpis + odkazy na katalog filtrovaný na pobočku
$TCb = $TC;
$TCb['fleet_title'] = $V['fleet_title'];
$pbFleet = pbFleetForBranch(str_replace('data-cms-key="web.landing.common.fleet_title"', 'data-cms-key="web.pobocky.v2.fleet_title"', renderLpFleet($pbMotos, $TCb)), $branchId);

// Druhá pobočka (cross-sell)
$pbOi = $idx === 0 ? 1 : 0;
$pbOther = '';
if (isset($defaults['branches'][$pbOi])) {
    $ob = pobockyBranch($C, $defaults, $pbOi);
    $oc = pbBranchCfg($ob['slug']);
    $oVB = is_array($V['branches'][$pbOi] ?? null) ? $V['branches'][$pbOi] : [];
    $pbOther = '<section class="pb-other" aria-labelledby="pb-other-h"><div class="container"><h2 id="pb-other-h" data-cms-key="web.pobocky.v2.other_title">' . he(lpPlain($V['other_title'])) . '</h2>' .
        '<a class="pb-other-card lp-reveal" href="/pobocky/' . he($ob['slug']) . '">' .
        ($oc['card'] !== '' ? '<img src="/' . he($oc['card']) . '" alt="' . he(lpPlain($ob['title'])) . '" width="320" height="240" loading="lazy" decoding="async">' : '') .
        '<span class="pb-other-body">' . pbBadge($ob['badge'], '', $oc['self']) . '<span class="pb-other-t">' . he(lpPlain($ob['title'])) . '</span>' .
        (lpPlain($oVB['highlight'] ?? '') !== '' ? '<span class="pb-other-hl">' . he(lpPlain($oVB['highlight'])) . '</span>' : '') . '</span>' .
        '<span class="pb-other-go">' . lpIcon('arrow') . '</span></a></div></section>';
}

return '<main id="content" class="lp-main lp-main--page pb-main"><div class="container">' . $bc . '</div>' .
    $pbHero .
    ($videoTop ? $pbVideo : '') .
    pbInfoHtml($V, $b, $k) .
    pbGuideHtml($V, $b, $k, $VB['guide'] ?? [], $pbCfg['guide'], $pbGal, $rezHref) .
    pbGearHtml($V, $VB, $b, $k) .
    pbGalleryHtml($pbGal, $b['gallery_title'] ?? '', $k . '.gallery_title', $TC) .
    ($videoTop ? '' : $pbVideo) .
    pbMapHtml($V, $VB, $b, $k, $mapQ !== '' ? $mapSrc : '', $pbMaps, $title) .
    $pbFleet .
    pbCtaHtml($cta, $V, $rezHref, $pbKat, lpS($C['back_link'] ?? $defaults['back_link'])) .
    $pbOther .
    '</main>' .
    renderLpSticky($TC, $rezHref, $pbKat !== '' ? $pbKat : '/katalog');
