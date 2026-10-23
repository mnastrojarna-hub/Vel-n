<?php
// ===== Detail motorky v2 — bloky nového pořadí (2026-10-22, zadání majitele) =====
// Volá jen pages/katalog-detail.php ve v2 (pořadí: hero → garance → recenze → „Vyber si termín“ → ceník →
// informace → podobné → outro). Nic nevypisuje, jen vrací HTML bloků:
// - garance: renderLpGuarantees($T, ['compact' => true]) z landing-guarantee.php,
// - recenze: renderLpReviews (landing-trust.php) — nejvýš 3, recenze zmiňující tenhle model napřed,
// - kalkulačka „Vyber si termín“: renderKatalogCalc (pages/katalog-calc.php, ctx detail).
// .lp-main = styly nadpisů, karuselu a hvězdiček jako na landingu (css/moto-detail-v2.css .md-guar/.md-rev).

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
