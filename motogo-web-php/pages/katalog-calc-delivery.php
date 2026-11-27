<?php
// ===== Kalkulačka ceny — přistavení na adresu / vrácení jinde (2026-11-27, zadání majitele) =====
// Doplněk pages/katalog-calc.php: krok „Přistavení“ v kalkulačce (katalog „Spočítat cenu“ i detail motorky).
// Pravidla, cenu ani trasu kalkulačka NEMÁ vlastní — volá funkce rezervačního formuláře
// (js/delivery-rules.js, js/pages-rezervace-pricing.js); stav js/landing-calc-delivery.js, vzhled
// js/landing-calc-delivery-ui.js + css/landing-calc-delivery.css. Volbu do /rezervace přenese
// ?delivery=1 / ?return_delivery=1 + sessionStorage (js/rezervace-delivery-carry.js).

/** Nové texty kroku (CS; tykání jako zbytek kalkulačky) ← lang/v2/<lang>/katalog.php ← Velín web.landing_katalog.*. */
function kcDvDefaults() {
    return [
        'step_delivery' => 'Přistavení',
        'dv_need_moto' => 'Vyber motorku — spočítáme ti i přistavení na adresu.',
        'dv_addr' => 'Adresa přistavení (ulice, město)',
        'dv_raddr' => 'Adresa vrácení (ulice, město)',
        // čas se v kalkulačce nevolí (jen ve formuláři) — formulář pak hlídá předstih 6 h
        'dv_lead' => 'Čas přistavení zvolíš v rezervaci.',
        'dv_today' => 'Na dnešek už přistavení nestihneme — vyber pozdější den, nebo vyzvednutí na pobočce.',
        // řádek souhrnu, dokud není spočítaná trasa (formulář do té doby počítá základní cenu)
        'dv_from' => 'od {price}',
        // řádky souhrnu = kanonické názvy položek rezervace (lang/<lang>.php rez.gear.item.delivery / .return).
        // Vlastní klíče: živý překlad těch dvou klíčů z Velínu je v části jazyků chybný (DE/PL přistavení = „vrácení“).
        'dv_row_d' => 'Přistavení motorky',
        'dv_row_r' => 'Vrácení motorky',
    ];
}

/**
 * Texty, které už má rezervační formulář (lang/<lang>.php, rez.*) — kalkulačka je bere přímo z něj,
 * aby volby, vysvětlení zámku samoobsluhy, řádek trasy i upozornění na předstih zněly v obou místech stejně.
 * Zástupné {…} doplní JS (ceny z MG._calcDeliveryFee, km a minuty z trasy).
 */
function kcDvFormTexts() {
    $map = [
        'dv_on' => 'rez.pickup.delivery', 'dv_sub' => 'rez.pickup.deliverySub', 'dv_same' => 'rez.pickup.sameAsDel',
        'dv_ro' => 'rez.pickup.returnOther',
        'dv_lock' => 'rez.pickup.selfServiceNoDelivery', 'dv_lock_text' => 'rez.pickup.selfServiceNoDeliveryText',
        'dv_kind_d' => 'rez.route.delivery', 'dv_kind_r' => 'rez.route.return',
        'dv_wait' => 'rez.route.loading', 'dv_err' => 'rez.route.error',
        'dv_fast' => 'rez.route.fastestFrom', 'dv_drive' => 'rez.route.driveTime', 'dv_calc' => 'rez.route.calc',
        'dv_soon' => 'rez.alert.minTimeDelivery',
    ];
    $out = [];
    foreach ($map as $k => $rk) $out[$k] = lpPlain(t($rk));
    // Součet s dopravou se jmenuje jako ve formuláři: „Celková cena: {price}“ → „Celková cena“
    $out['total_all'] = trim(preg_replace('/[\s:：]*\{price\}.*$/u', '', lpPlain(t('rez.totalPrice'))));
    return $out;
}

/** Assety kroku pro kcPageMeta() — pořadí skriptů: pravidlo → funkce formuláře → stav → vzhled (před landing-calc.js). */
function kcDvScripts() {
    return ['/js/delivery-rules.js', '/js/pages-rezervace-pricing.js', '/js/landing-calc-delivery.js', '/js/landing-calc-delivery-ui.js'];
}
