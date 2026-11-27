<?php
// ===== Detail motorky v2 — bloky nového pořadí (2026-10-22, zadání majitele) =====
// Volá jen pages/katalog-detail.php ve v2 (pořadí: hero → garance → recenze → „Vyber si termín“ → ceník →
// informace → podobné → outro). Nic nevypisuje, jen vrací HTML bloků:
// - garance: renderLpGuarantees($T, ['compact' => true]) z landing-guarantee.php,
// - recenze: renderLpReviews (landing-trust.php) — nejvýš 3, recenze zmiňující tenhle model napřed,
// - kalkulačka „Vyber si termín“: renderKatalogCalc (pages/katalog-calc.php, ctx detail).
// .lp-main = styly nadpisů, karuselu a hvězdiček jako na landingu (css/moto-detail-v2.css .md-guar/.md-rev).
// Navíc (v1 i v2): český <title> a meta description detailu — katalogMotoSeoCs() na konci souboru
// (místo pobočky a shoda kategorie: pages/katalog-v2-lib.php).

/** Slova z názvu modelu (malá písmena, bez interpunkce). */
function mdWords($s) {
    return preg_split('/[^\p{L}\p{N}]+/u', mb_strtolower(trim((string)$s), 'UTF-8'), -1, PREG_SPLIT_NO_EMPTY) ?: [];
}

/**
 * Slova, podle kterých poznáme recenzi právě této motorky. Zákazníci píšou zkráceně („RVM 500“,
 * „BMX GS 1200“), proto bez značky (sloupec brand, jinak 1. slovo modelu), bez obecných přívlastků
 * a bez jednopísmenných slov: „Jawa RVM 500 Adventure“ → rvm 500, „BMW R 1200 GS Adventure“ → 1200 gs,
 * „Triumph Tiger 1200 Explorer“ → tiger 1200. Zbudou-li jen čísla („Kawasaki Z 900“), přidá se značka,
 * jinak by sedla i recenze jiné motorky se stejným objemem.
 */
function mdReviewTokens(array $moto) {
    $w = mdWords($moto['model'] ?? '');
    if (!$w) return [];
    $brand = mdWords($moto['brand'] ?? '');
    if (!$brand) $brand = [$w[0]];
    $skip = array_merge($brand, ['adventure', 'explorer', 'abs', 'street', 'rally', 'replica', 'premium']);
    $out = [];
    foreach ($w as $x) if (mb_strlen($x, 'UTF-8') >= 2 && !in_array($x, $skip, true)) $out[] = $x;
    if ($out && !preg_grep('/\p{L}/u', $out)) $out = array_merge($brand, $out);
    return array_values(array_unique($out));
}

/** Recenze obsahuje všechna slova modelu (celá slova, na pořadí nezáleží). */
function mdReviewMentions(array $tokens, $text) {
    if (!$tokens) return false;
    $have = array_flip(mdWords($text));
    foreach ($tokens as $t) if (!isset($have[$t])) return false;
    return true;
}

/** HTML bloků v2: ['guar' => …, 'rev' => …, 'calc' => …] (prázdný řetězec = blok se nevykreslí). */
function mdV2Blocks($sb, array $motos, array $moto, array $T) {
    $g = function_exists('renderLpGuarantees') ? renderLpGuarantees($T, ['compact' => true]) : '';
    $R = lpReviewsData();
    if (!empty($R['items']) && is_array($R['items'])) {
        $tk = mdReviewTokens($moto);
        $hit = function ($x) use ($tk) { return is_array($x) && mdReviewMentions($tk, $x['text'] ?? '') ? 0 : 1; };
        usort($R['items'], function ($a, $b) use ($hit) { return $hit($a) <=> $hit($b); }); // stabilní (PHP 8)
        $R['items'] = array_slice($R['items'], 0, 3);
    }
    $rv = renderLpReviews($R, $T);
    return [
        'guar' => $g !== '' ? '<div class="lp-main md-guar">' . $g . '</div>' : '',
        'rev' => $rv !== '' ? '<div class="lp-main md-rev">' . $rv . '</div>' : '',
        'calc' => renderKatalogCalc($sb, $motos, ['moto' => (string)$moto['id'], 'ctx' => 'detail']),
    ];
}

/**
 * Český <title> a meta description detailu motorky (jen CS; šablona ze SEO revize 2026-11-27). Vrací [title, description].
 * Titulek „{model} k pronájmu u Pelhřimova | MotoGo24“ (u Brna podle pobočky; nad 60 znaků bez místa).
 * Popis „Pronájem motorky {model} ({ccm} ccm, {kW} kW, {typ}) v Mezné u Pelhřimova od {cena} Kč/den. Bez kauce, výbava pro
 * řidiče v ceně, online rezervace.“ — skútr „Pronájem skútru …“, dětská „Dětská motorka … k půjčení …“, vozík „… k pronájmu …“.
 * Typ v jednotném čísle, místo z pobočky motorky (ne surové branches.city), cena = nejnižší denní cena (getMinPrice).
 * Do 155 znaků se krátí vypouštěním částí (závěr → typ → parametry), nikdy useknutím; popis z DB se nepřipojuje.
 */
function katalogMotoSeoCs($moto) {
    $name = trim(safeStr($moto['model'] ?? ''));
    $model = $name !== '' ? $name : 'Motorka'; // bez názvu: „Motorka k pronájmu …“
    $nm = $name !== '' ? ' ' . $name : '';
    $slug = katalogBranchSlug($moto);
    $near = katalogPlaceCs($slug, 'u');
    $title = $model . ' k pronájmu' . ($near !== '' ? ' ' . $near : '') . ' | MotoGo24';
    if (mb_strlen($title, 'UTF-8') > 60) $title = $model . ' k pronájmu | MotoGo24';
    if (mb_strlen($title, 'UTF-8') > 60) $title = $model . ' | MotoGo24';

    // čísla jako na stránce (desetinná čárka, mezera v tisících u ccm), do meta bez entit a s obyčejnou mezerou
    $num = function ($v, $th = false) { return str_replace("\u{00A0}", ' ', html_entity_decode(numLoc($v, $th), ENT_QUOTES | ENT_HTML5, 'UTF-8')); };
    $price = getMinPrice($moto);
    $where = trim(katalogPlaceCs($slug, 'v') . ($price > 0 ? ' od ' . number_format(ceil((float)$price), 0, ',', ' ') . ' Kč/den' : ''));
    $where = $where !== '' ? ' ' . $where : '';
    $lg = motoLicenseGroups($moto);
    if (!empty($moto['is_trailer']) || katalogCategoryMatch($moto, 'ostatni')) {
        $leads = [(preg_match('/^přívěs/iu', $name) ? $name : 'Přívěs na motorky' . $nm) . ' k pronájmu'];
        $tails = [(in_array('B', $lg, true) ? 'Stačí ŘP B, bez kauce' : 'Bez kauce') . ', rezervace online.'];
    } elseif (katalogCategoryMatch($moto, 'detske')) {
        $leads = ['Dětská motorka' . $nm . ' k půjčení'];
        $tails = [((!$lg || $lg === ['N']) ? 'Bez řidičáku, jen' : 'Jen') . ' mimo silnice a pod dohledem dospělého.'];
    } else {
        $scooter = katalogCategoryMatch($moto, 'scootery');
        $base = 'Pronájem ' . ($scooter ? 'skútru' : 'motorky') . $nm;
        $specs = [];
        if (!empty($moto['engine_cc'])) $specs[] = $num($moto['engine_cc'], true) . ' ccm';
        if (!empty($moto['power_kw'])) $specs[] = $num($moto['power_kw']) . ' kW';
        $type = '';
        foreach (['cestovni' => 'cestovní', 'sportovni' => 'sportovní', 'naked' => 'naked', 'supermoto' => 'supermoto', 'chopper' => 'chopper'] as $k => $one) {
            if (!$scooter && katalogCategoryMatch($moto, $k)) { $type = $one; break; }
        }
        $leads = [];
        if ($specs && $type !== '') $leads[] = $base . ' (' . implode(', ', array_merge($specs, [$type])) . ')';
        if ($specs) $leads[] = $base . ' (' . implode(', ', $specs) . ')';
        $leads[] = $base;
        $tails = ['Bez kauce, výbava pro řidiče v ceně, online rezervace.', 'Bez kauce, výbava v ceně, online rezervace.'];
    }
    // první varianta (od nejúplnější), která se vejde do 155 znaků; krajní možnost = jen první věta
    foreach ($leads as $l) {
        foreach ($tails as $tl) {
            $desc = $l . $where . '. ' . $tl;
            if (mb_strlen($desc, 'UTF-8') <= 155) return [$title, $desc];
        }
    }
    return [$title, end($leads) . $where . '.'];
}
