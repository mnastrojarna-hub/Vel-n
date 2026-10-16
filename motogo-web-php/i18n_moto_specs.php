<?php
// ===== MotoGo24 Web PHP — překlad technických údajů motorek do jazyka stránky =====
// Velín ukládá barvu, typ motoru, převodovku, palivo, brzdy a popisky fotek (image_alts) jen česky
// (motorcycles.translations nese jen description/features/suitable_for). Na cizojazyčných stránkách
// se proto hodnota přeloží slovníkem lang/moto-specs/*.php (přesná shoda po normalizaci).
// Neznámá hodnota (nová/změněná ve Velínu) zůstane česky — nikdy se neukáže zastaralý překlad.
// Popisek fotky bez překladu → „foto N“ v jazyce stránky (alt zůstává unikátní a bez češtiny).
// Volá SupabaseClient::fetchMotos() — cache drží česká data, překládá se až při čtení.

const MG_SPEC_LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

/** Klíč slovníku: malá písmena, jednotné pomlčky a mezery, „6ti / 6 ti / 6sti stupňová“ = „6stupňová“. */
function mgSpecKey(string $s): string {
    $s = mb_strtolower(trim($s), 'UTF-8');
    $s = preg_replace('/[\x{2013}\x{2014}]/u', '-', $s);
    $s = preg_replace('/\s+/u', ' ', $s);
    return preg_replace('/(\d)\s*(?:s?ti)?\s*stupňov/u', '$1stupňov', $s);
}

/** Klíč popisku fotky: navíc bez diakritiky a interpunkce (Velín má „Prava strana“ i „pravá strana“). */
function mgPhotoKey(string $s): string {
    $s = strtr(mb_strtolower(trim($s), 'UTF-8'), [
        'á' => 'a', 'č' => 'c', 'ď' => 'd', 'é' => 'e', 'ě' => 'e', 'í' => 'i', 'ň' => 'n', 'ó' => 'o',
        'ř' => 'r', 'š' => 's', 'ť' => 't', 'ú' => 'u', 'ů' => 'u', 'ý' => 'y', 'ž' => 'z',
    ]);
    return trim(preg_replace('/[^a-z0-9]+/', ' ', $s));
}

/** Slovník [skupina => [klíč => [en, de, es, fr, nl, pl, uk]]] (klíče normalizované). */
function mgSpecDict(): array {
    static $dict = null;
    if ($dict !== null) return $dict;
    $dict = ['spec' => [], 'photo' => [], 'photoN' => []];
    // Chybějící slovník (neúplný upload) = hodnoty zůstanou česky, ne fatal error.
    $load = function ($f) { $p = __DIR__ . '/lang/moto-specs/' . $f . '.php'; return is_file($p) ? (require $p) : []; };
    foreach (['specs', 'engines', 'brakes'] as $f) {
        foreach ($load($f) as $k => $v) $dict['spec'][mgSpecKey($k)] = $v;
    }
    $ph = $load('photos');
    foreach (($ph['captions'] ?? []) as $concept => $keys) {
        foreach ($keys as $k) $dict['photo'][mgPhotoKey($k)] = $ph['concepts'][$concept];
    }
    $dict['photoN'] = $ph['photoN'] ?? [];
    return $dict;
}

function mgSpecTranslate(string $value, string $lang): string {
    $i = array_search($lang, MG_SPEC_LANGS, true);
    if ($i === false || trim($value) === '') return $value;
    $tr = mgSpecDict()['spec'][mgSpecKey($value)][$i] ?? null;
    if ($tr === null) return $value;
    // Velín píše hodnoty s velkým i malým písmenem — zachovat (velká písmena slovníku zůstávají).
    $first = mb_substr(trim($value), 0, 1, 'UTF-8');
    if ($first !== mb_strtolower($first, 'UTF-8')) $tr = mb_strtoupper(mb_substr($tr, 0, 1, 'UTF-8'), 'UTF-8') . mb_substr($tr, 1, null, 'UTF-8');
    return $tr;
}

/** Přeloží česká pole jedné motorky (řádek z fetchMotos) do jazyka $lang; čeština beze změny. */
function mgLocalizeMotoSpecs(array $m, string $lang): array {
    $i = array_search($lang, MG_SPEC_LANGS, true);
    if ($i === false) return $m;
    foreach (['color', 'engine_type', 'transmission', 'fuel_type', 'brake_type'] as $f) {
        if (isset($m[$f]) && is_string($m[$f])) $m[$f] = mgSpecTranslate($m[$f], $lang);
    }
    if (!empty($m['image_alts']) && is_array($m['image_alts'])) {
        $d = mgSpecDict();
        $seen = [];
        foreach ($m['image_alts'] as $n => $alt) {
            if (!is_string($alt) || trim($alt) === '') continue;
            $t = $d['photo'][mgPhotoKey($alt)][$i] ?? (isset($d['photoN'][$i]) ? str_replace('{n}', (string)($n + 1), $d['photoN'][$i]) : $alt);
            if (isset($seen[$t])) $t .= ' (' . ($n + 1) . ')';
            $seen[$t] = true;
            $m['image_alts'][$n] = $t;
        }
    }
    return $m;
}

function mgLocalizeMotos($motos) {
    if (!is_array($motos)) return $motos;
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    if (!in_array($lang, MG_SPEC_LANGS, true)) return $motos;
    foreach ($motos as $k => $m) {
        if (is_array($m)) $motos[$k] = mgLocalizeMotoSpecs($m, $lang);
    }
    return $motos;
}
