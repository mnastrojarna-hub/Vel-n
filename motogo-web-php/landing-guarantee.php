<?php
// ===== MotoGo24 Web PHP — Landing v2: pruh garancí hned pod hero (viz landing.php) =====
// Zadání majitele 2026-10-22: hned pod hero bannerem garance — 0 Kč spoluúčast při
// dodržení smlouvy, posun termínu zdarma, prodloužení/zkrácení, úpravy kdykoliv.
// Texty: data/landing-trust.php (guar_*, guarantees) ← lang/v2/<lang>/landing.php ← CMS
// web.landing.common.guar_* / guarantees.N.*. Ikony lpIco2() (landing-trust.php).

/** Pruh garancí: nadpis, krátký lead, dlaždice [{icon,title,text}] a poznámka s hvězdičkou. */
function renderLpGuarantees($T) {
    $items = '';
    foreach ((array)($T['guarantees'] ?? []) as $i => $g) {
        if (!is_array($g) || lpPlain($g['title'] ?? '') === '') continue;
        $items .= '<li class="lp-guar-i"><span class="lp-guar-ico">' . lpIco2(lpS($g['icon'] ?? '')) . '</span>' .
            '<span class="lp-guar-t" data-cms-key="web.landing.common.guarantees.' . $i . '.title">' . he(lpPlain($g['title'])) . '</span>' .
            (lpPlain($g['text'] ?? '') !== '' ? '<span class="lp-guar-s" data-cms-key="web.landing.common.guarantees.' . $i . '.text">' . he(lpPlain($g['text'])) . '</span>' : '') . '</li>';
    }
    if ($items === '') return '';
    [$h2, $aria] = lpH2('lp-guar-h', $T['guar_title'] ?? '', 'web.landing.common.guar_title');
    return '<section class="lp-guar"' . $aria . '><div class="container"><div class="lp-guar-card">' . $h2 .
        (lpPlain($T['guar_lead'] ?? '') !== '' ? '<p class="lp-guar-lead" data-cms-key="web.landing.common.guar_lead">' . he(lpPlain($T['guar_lead'])) . '</p>' : '') .
        '<ul class="lp-guar-list">' . $items . '</ul>' .
        (lpPlain($T['guar_note'] ?? '') !== '' ? '<p class="lp-guar-note" data-cms-key="web.landing.common.guar_note">' . he(lpPlain($T['guar_note'])) . '</p>' : '') .
        '</div></div></section>';
}
