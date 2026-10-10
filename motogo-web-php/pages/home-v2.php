<?php
// ===== Homepage — landing v2 (viz landing.php) =====
// Vkládá se z pages/home.php (require … vrací $content). Používá proměnné
// z home.php: $sb, $motos, $posts, $C, $bannerHtml, $faqHtml, $reviewsHtml.
// Pořadí pro mobil: hero (bez tlačítek) → akční panel → nabídka → motorky →
// důvody (10 + rozbalení na 20) → recenze → „jen u nás“ → postup → pobočky →
// FAQ → CTA → blog → rozcestník → SEO text (sbalený). Recenze z data/reviews.php
// nahrazují starou sekci $reviewsHtml (DB tabulka recenzí).
// Bez textů důvodů (prázdný seznam) zůstávají původní USP dlaždice.

$T = lpTexts($sb);
$TC = $T['common'];
$TH = $T['home'];

// Krátký H1 z landing textů (ES) → dlouhé H1 z CMS se stane H2 sekce „O nás“ (klíčová slova zůstanou).
$lpShortH1 = lpPlain($TH['h1'] ?? '') !== '';
$lpMinPrice = lpMinPrice($motos);

$lpPanel = renderLpPanel([
    'h1' => $lpShortH1 ? $TH['h1'] : ($C['h1'] ?? ''),
    'h1Key' => $lpShortH1 ? 'web.landing.home.h1' : 'web.home.h1',
    'lead' => $TH['lead'] ?? '',
    'leadKey' => 'web.landing.home.lead',
    'priceChip' => $lpMinPrice > 0 ? str_replace('{price}', lpMoneyFrom($lpMinPrice), lpS($TC['price_chip'])) : '',
    'primary' => $TH['cta_primary'],
    'secondary' => $TH['cta_secondary'],
    'chips' => $TH['chips'] ?? [],
    'assurance' => $TC['assurance'] ?? '',
    'season' => $TC['season_note'] ?? '',
    'keyBase' => 'web.landing.home',
]);

[$lpStepList, $lpStepKey] = lpSteps($T, 'home', $C['process']['steps'] ?? [], 'web.home.process.steps');
$lpOwnSteps = strpos($lpStepKey, 'web.landing.') === 0 && lpPlain($TH['steps_title'] ?? '') !== '';
[$lpCtaData, $lpCtaKey] = lpCta($T, $C['cta'] ?? [], 'web.home.cta');

$lpAbout = renderLpMore(
    $lpShortH1 ? ($C['h1'] ?? '') : $TH['about_title'],
    $lpShortH1 ? 'web.home.h1' : 'web.landing.home.about_title',
    '<div class="home-intro" data-cms-key="web.home.intro">' . sanitizeHtml($C['intro'] ?? '') . '</div>',
    $TC,
    'lp-about'
);

$lpReasons = renderLpReasons($TC['reasons_title'] ?? '', 'web.landing.common.reasons_title', $TC['reasons_lead'] ?? '', $TC['reasons'] ?? [], 'web.landing.common.reasons', $TC, 10);
$lpReviews = renderLpReviews(lpReviewsData(), $TC);

return $bannerHtml .
    '<main id="content" class="lp-main">' .
    $lpPanel .
    renderLpOffer($TC) .
    renderLpFleet($motos, $TC) .
    ($lpReasons !== '' ? $lpReasons : renderLpUsp($TC['usp_title'], 'web.landing.common.usp_title', $TH['usp'] ?? [], 'web.landing.home.usp', $lpMinPrice)) .
    $lpReviews .
    renderLpHighlights($TC['hl_title'] ?? '', 'web.landing.common.hl_title', $TC['highlights'] ?? [], 'web.landing.common.highlights') .
    renderLpSteps($lpOwnSteps ? $TH['steps_title'] : ($C['process']['title'] ?? ''), $lpOwnSteps ? 'web.landing.home.steps_title' : 'web.home.process.title', $lpStepList, $lpStepKey) .
    renderLpBranches($TC['branches_title'] ?? '', 'web.landing.common.branches_title', $TC['branches'] ?? [], 'web.landing.common.branches', $TC) .
    '<div class="container lp-flow">' . ($lpReviews !== '' ? '' : $reviewsHtml) . $faqHtml . '</div>' .
    renderLpCta($lpCtaData, $lpCtaKey) .
    renderLpBlog($posts, $C['blog'] ?? [], $TC) .
    renderLpExplore($TC['explore_title'], 'web.landing.common.explore_title', $C['signposts'] ?? [], 'web.home.signposts') .
    $lpAbout .
    '</main>' .
    renderLpSticky($TC);
