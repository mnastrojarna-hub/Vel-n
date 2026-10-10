<?php
// ===== Půjčovna motorek — landing v2 (viz landing.php) =====
// Vkládá se z pages/pujcovna.php (require … vrací $content). Používá $sb, $C,
// $bc, $faqHtml z pujcovna.php. Pořadí pro mobil: drobečková navigace →
// akční panel s fotkou (H1 + 2 CTA) → nabídka → motorky → důvody (10 + rozbalení
// na 20; bez nich USP dlaždice) → recenze → postup → pobočky → FAQ → CTA → SEO text.

$T = lpTexts($sb);
$TC = $T['common'];
$TP = $T['pujcovna'];
$lpMotos = $sb->fetchMotos();
$lpMin = lpMinPrice($lpMotos);

// Krátký H1 z landing textů → CMS H1 se stane H2 sekce „Více o nás“.
$lpShortH1 = lpPlain($TP['h1'] ?? '') !== '';

$lpPanel = renderLpPanel([
    'h1' => $lpShortH1 ? $TP['h1'] : ($C['intro']['h1'] ?? ''),
    'h1Key' => $lpShortH1 ? 'web.landing.pujcovna.h1' : 'web.pujcovna.intro.h1',
    'lead' => $TP['lead'] ?? '',
    'leadKey' => 'web.landing.pujcovna.lead',
    'priceChip' => $lpMin > 0 ? str_replace('{price}', lpMoneyFrom($lpMin), lpS($TC['price_chip'])) : '',
    'primary' => $TP['cta_primary'],
    'secondary' => $TP['cta_secondary'],
    'chips' => $TP['chips'] ?? [],
    'assurance' => $TC['assurance'] ?? '',
    'season' => $TC['season_note'] ?? '',
    'keyBase' => 'web.landing.pujcovna',
    'rating' => lpPanelRating($TC),
    'bg' => BASE_URL . '/gfx/hero-banner-768.webp',
]);

[$lpStepList, $lpStepKey] = lpSteps($T, 'pujcovna', $C['process']['steps'] ?? [], 'web.pujcovna.process.steps');
$lpOwnSteps = strpos($lpStepKey, 'web.landing.') === 0 && lpPlain($TP['steps_title'] ?? '') !== '';
[$lpCtaData, $lpCtaKey] = lpCta($T, $C['cta'] ?? [], 'web.pujcovna.cta');

// Výhody: vlastní kurátorované USP (ES), jinak CMS benefity stránky.
$lpOwnUsp = is_array($TP['usp'] ?? null) && count(array_filter($TP['usp'], 'is_array')) > 0;
$lpUsp = $lpOwnUsp
    ? renderLpUsp($TC['usp_title'], 'web.landing.common.usp_title', $TP['usp'], 'web.landing.pujcovna.usp', $lpMin)
    : renderLpUsp(is_array($C['benefits']['title'] ?? null) ? '' : ($C['benefits']['title'] ?? ''), 'web.pujcovna.benefits.title', $C['benefits']['items'] ?? [], 'web.pujcovna.benefits.items');

$lpReasons = renderLpReasons($TC['reasons_title'] ?? '', 'web.landing.common.reasons_title', $TC['reasons_lead'] ?? '', $TC['reasons'] ?? [], 'web.landing.common.reasons', $TC, 10);

$lpAbout = renderLpMore(
    $lpShortH1 ? ($C['intro']['h1'] ?? '') : $TP['about_title'],
    $lpShortH1 ? 'web.pujcovna.intro.h1' : 'web.landing.pujcovna.about_title',
    '<p data-cms-key="web.pujcovna.intro.body">' . sanitizeHtml($C['intro']['body'] ?? '') . '</p>' .
    '<p data-cms-key="web.pujcovna.benefits.closing">' . sanitizeHtml($C['benefits']['closing'] ?? '') . '</p>',
    $TC,
    'lp-about'
);

return '<main id="content" class="lp-main lp-main--page"><div class="container">' . $bc . '</div>' .
    $lpPanel .
    renderLpOffer($TC) .
    renderLpFleet($lpMotos, $TC) .
    ($lpReasons !== '' ? $lpReasons : $lpUsp) .
    renderLpReviews(lpReviewsData(), $TC) .
    renderLpSteps($lpOwnSteps ? $TP['steps_title'] : ($C['process']['title'] ?? ''), $lpOwnSteps ? 'web.landing.pujcovna.steps_title' : 'web.pujcovna.process.title', $lpStepList, $lpStepKey) .
    renderLpBranches($TC['branches_title'] ?? '', 'web.landing.common.branches_title', $TC['branches'] ?? [], 'web.landing.common.branches', $TC) .
    '<div class="container lp-flow">' . $faqHtml . '</div>' .
    renderLpCta($lpCtaData, $lpCtaKey) .
    $lpAbout .
    '</main>' .
    renderLpSticky($TC);
