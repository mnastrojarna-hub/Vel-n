<?php
// ===== MotoGo24 Web PHP — Landing v2: „Máš vlastní motorku? Půjč si jen výbavu“ (viz landing.php) =====
// Zadání majitele 2026-10-22: dole na úvodní stránce (mezi CTA pásem a blogem) a na /pujcovna-motorek
// odkaz na půjčení samotné výbavy (/pujceni-obleceni) + zpětný odkaz „půjčuješ motorku? výbava je
// v ceně“ (/katalog). Vykreslí se JEN když je půjčení zapnuté (app_settings.gear_rental.enabled ≠ false)
// a existují aktivní ceny (gear_rental_prices) — stejná podmínka jako pages/pujceni-obleceni.php.
// Cena „Komplet od“ = nejlevnější aktivní komplet (kind=set), bez kompletu se cena nezobrazí.
// Texty: data/landing-trust.php ['gear_promo'] ← lang/v2/<lang>/landing.php ← CMS web.landing.common.gear_promo.*.
// CSS: css/landing-promo.css (.lp-gearp). Odkazy /pujceni-obleceni a /katalog lokalizuje i18nLocalizeHrefs.

/** Nejlevnější aktivní komplet [enabled, cena Kč/den] — file cache 30 min (dotaz jde mimo cache SupabaseClienta). */
function lpGearPromoData($sb) {
    static $memo = null;
    if ($memo !== null) return $memo;
    $file = __DIR__ . '/.cache/lp_gear_promo.json';
    $admin = function_exists('mgCmsAdminValid') && mgCmsAdminValid();
    if (!$admin && is_file($file) && filemtime($file) > time() - 1800) {
        $c = json_decode((string)@file_get_contents($file), true);
        if (is_array($c) && isset($c['on'], $c['p'])) return $memo = [(bool)$c['on'], (float)$c['p']];
    }
    $cfg = $sb->fetchSetting('gear_rental');
    $on = !(is_array($cfg) && ($cfg['enabled'] ?? true) === false);
    $min = 0.0;
    if ($on) {
        $rows = $sb->query('gear_rental_prices', 'kind,price_per_day', ['is_active=eq.true'], 'price_per_day.asc');
        $rows = is_array($rows) && array_is_list($rows) ? $rows : [];
        $on = count($rows) > 0;
        foreach ($rows as $r) {
            if (is_array($r) && ($r['kind'] ?? '') === 'set' && (float)($r['price_per_day'] ?? 0) > 0) { $min = (float)$r['price_per_day']; break; }
        }
    }
    if (!$admin && is_dir(dirname($file)) && is_writable(dirname($file))) @file_put_contents($file, json_encode(['on' => $on, 'p' => $min]), LOCK_EX);
    return $memo = [$on, $min];
}

/** Sekce promo výbavy. $TC = lpTexts()['common'], $sb = SupabaseClient. Vypnuté půjčení / bez cen = ''. */
function renderLpGearPromo($TC, $sb) {
    $G = is_array($TC['gear_promo'] ?? null) ? $TC['gear_promo'] : [];
    if (lpPlain($G['title'] ?? '') === '' || !$sb) return '';
    [$on, $min] = lpGearPromoData($sb);
    if (!$on) return '';
    $k = 'web.landing.common.gear_promo.';
    // Prostý text; mimo CMS admin s nezalomitelnou mezerou před „?“ (fr) a v částkách (lpNbsp, landing-guarantee.php)
    $v = function ($key) use ($G) { return lpNbspTxt($G[$key] ?? ''); };
    $t = function ($key, $tag, $cls) use ($v, $k) {
        return $v($key) !== '' ? '<' . $tag . ' class="' . $cls . '" data-cms-key="' . $k . $key . '">' . he($v($key)) . '</' . $tag . '>' : '';
    };
    // Cena dosazená do {price} → bez data-cms-key (inline editace by uložila číslo místo šablony)
    $price = ($min > 0 && $v('from') !== '')
        ? '<p class="lp-gearp-price"><span class="lp-chip lp-chip--hot">' . he(str_replace('{price}', lpMoneyFrom($min), $v('from'))) . '</span></p>' : '';
    [$h2] = lpH2('lp-gearp-h', he($v('title')), $k . 'title');
    return '<section class="lp-gearp" aria-labelledby="lp-gearp-h"><div class="container"><div class="lp-gearp-card">' .
        '<div class="lp-gearp-vis" aria-hidden="true">' . lpIco2('helmet') . '</div>' .
        '<div class="lp-gearp-body">' . $t('eyebrow', 'p', 'lp-gearp-eyebrow') . $h2 . $t('lead', 'p', 'lp-gearp-lead') . $price .
        '<div class="lp-gearp-cta">' .
            ($v('cta') !== '' ? '<a class="lp-btn lp-btn-primary" href="/pujceni-obleceni"><span data-cms-key="' . $k . 'cta">' . he($v('cta')) . '</span>' . lpIcon('arrow') . '</a>' : '') .
            ($v('moto') !== '' ? '<a class="lp-gearp-moto" href="/katalog">' . lpIcon('moto') . '<span data-cms-key="' . $k . 'moto">' . he($v('moto')) . '</span></a>' : '') .
        '</div></div></div></div></section>';
}
