<?php
// ===== Homepage — landing v2 (viz landing.php) =====
// Vkládá se z pages/home.php (require … vrací $content). Používá proměnné
// z home.php: $sb, $motos, $posts, $C, $bannerHtml, $faqHtml, $reviewsHtml.
// Pořadí pro mobil: hero (bez tlačítek) → akční panel → motorky → proč my →
// postup → recenze → FAQ → CTA → blog → rozcestník → SEO text (sbalený).

$T = lpTexts($sb);
$TC = $T['common'];
$TH = $T['home'];

// Krátký H1 z landing textů (ES) → dlouhé H1 z CMS se stane H2 sekce „O nás“ (klíčová slova zůstanou).
$lpShortH1 = trim(strip_tags((string)($TH['h1'] ?? ''))) !== '';
$lpMinPrice = lpMinPrice($motos);

$lpPanel = renderLpPanel([
    'h1' => $lpShortH1 ? $TH['h1'] : ($C['h1'] ?? ''),
    'h1Key' => $lpShortH1 ? 'web.landing.home.h1' : 'web.home.h1',
    'lead' => $TH['lead'] ?? '',
    'leadKey' => 'web.landing.home.lead',
    'priceChip' => $lpMinPrice > 0 ? str_replace('{price}', lpMoneyFrom($lpMinPrice), (string)$TC['price_chip']) : '',
    'primary' => $TH['cta_primary'],
    'secondary' => $TH['cta_secondary'],
    'chips' => $TH['chips'] ?? [],
    'keyBase' => 'web.landing.home',
]);

[$lpStepList, $lpStepKey] = lpSteps($T, 'home', $C['process']['steps'] ?? [], 'web.home.process.steps');
$lpOwnSteps = strpos($lpStepKey, 'web.landing.') === 0 && trim((string)($TH['steps_title'] ?? '')) !== '';

$lpAbout = renderLpMore(
    $lpShortH1 ? strip_tags((string)($C['h1'] ?? '')) : $TH['about_title'],
    $lpShortH1 ? 'web.home.h1' : 'web.landing.home.about_title',
    '<div class="home-intro" data-cms-key="web.home.intro">' . sanitizeHtml($C['intro'] ?? '') . '</div>',
    $TC,
    'lp-about'
);

return $bannerHtml .
    '<main id="content" class="lp-main">' .
    $lpPanel .
    renderLpFleet($motos, $TC) .
    renderLpUsp($TC['usp_title'], 'web.landing.common.usp_title', $TH['usp'] ?? [], 'web.landing.home.usp', $lpMinPrice) .
    renderLpSteps($lpOwnSteps ? $TH['steps_title'] : ($C['process']['title'] ?? ''), $lpOwnSteps ? 'web.landing.home.steps_title' : 'web.home.process.title', $lpStepList, $lpStepKey) .
    '<div class="container lp-flow">' . $reviewsHtml . $faqHtml . '</div>' .
    renderLpCta($C['cta'] ?? [], 'web.home.cta') .
    renderLpBlog($posts, $C['blog'] ?? [], $TC) .
    renderLpExplore($TC['explore_title'], 'web.landing.common.explore_title', $C['signposts'] ?? [], 'web.home.signposts') .
    $lpAbout .
    '</main>' .
    renderLpSticky($TC);
