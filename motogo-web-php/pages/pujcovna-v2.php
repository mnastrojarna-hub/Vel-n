<?php
// ===== Půjčovna motorek — landing v2 (viz landing.php) =====
// Vkládá se z pages/pujcovna.php (require … vrací $content). Používá $sb, $C,
// $bc, $faqHtml z pujcovna.php. Pořadí pro mobil: drobečková
// navigace → akční panel s fotkou (H1 + 2 CTA) → motorky → výhody → postup →
// FAQ → CTA → SEO text (sbalený).

$T = lpTexts($sb);
$TC = $T['common'];
$TP = $T['pujcovna'];
$lpMotos = $sb->fetchMotos();

$lpPanel = renderLpPanel([
    'h1' => $C['intro']['h1'] ?? '',
    'h1Key' => 'web.pujcovna.intro.h1',
    'lead' => $TP['lead'] ?? '',
    'leadKey' => 'web.landing.pujcovna.lead',
    'priceChip' => ($lpMin = lpMinPrice($lpMotos)) > 0 ? str_replace('{price}', lpMoneyFrom($lpMin), (string)$TC['price_chip']) : '',
    'primary' => $TP['cta_primary'],
    'secondary' => $TP['cta_secondary'],
    'chips' => $TP['chips'] ?? [],
    'keyBase' => 'web.landing.pujcovna',
    'bg' => BASE_URL . '/gfx/hero-banner-768.webp',
]);

$lpAbout = renderLpMore(
    $TP['about_title'],
    'web.landing.pujcovna.about_title',
    '<p data-cms-key="web.pujcovna.intro.body">' . sanitizeHtml($C['intro']['body'] ?? '') . '</p>' .
    '<p data-cms-key="web.pujcovna.benefits.closing">' . sanitizeHtml($C['benefits']['closing'] ?? '') . '</p>',
    $TC,
    'lp-about'
);

$lpBenefitsTitle = is_array($C['benefits']['title'] ?? null) ? '' : (string)($C['benefits']['title'] ?? '');

return '<main id="content" class="lp-main lp-main--page"><div class="container">' . $bc . '</div>' .
    $lpPanel .
    renderLpFleet($lpMotos, $TC) .
    renderLpUsp($lpBenefitsTitle, 'web.pujcovna.benefits.title', $C['benefits']['items'] ?? [], 'web.pujcovna.benefits.items') .
    renderLpSteps($C['process']['title'] ?? '', 'web.pujcovna.process.title', $C['process']['steps'] ?? [], 'web.pujcovna.process.steps') .
    '<div class="container lp-flow">' . $faqHtml . '</div>' .
    renderLpCta($C['cta'] ?? [], 'web.pujcovna.cta') .
    $lpAbout .
    '</main>' .
    renderLpSticky($TC);
