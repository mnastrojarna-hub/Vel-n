<?php
// ===== MotoGo24 — Oblasti (kraje + města) =====
// Datový zdroj pro SEO landing stránky "motopůjčovna {město}" (/oblasti).
// Obsahuje pouze STRUKTURU (vlastní jména krajů a měst) — texty (intro, SEO
// titulky, CTA) jsou editovatelné z webu přes siteContent('oblasti') a
// lang/pages_*.php, viz pages/oblasti.php a pages/oblasti-detail.php.
//
// Pravidlo výběru měst: VŠECHNA města v kraji nad 10 000 obyvatel
// (ČSÚ, počet obyvatel k 1. 1. 2024). Při změně počtu obyvatel / přidání
// dalšího kraje stačí upravit tento jeden soubor.
//
// Pole regionu:
//   slug      — URL slug (/oblasti/<slug>), beze změny napříč jazyky (vlastní jméno)
//   name      — plný název kraje ("Kraj Vysočina")
//   seoName   — krátký tvar pro frázi "Motopůjčovna {seoName}" ("Vysočina")
//   inRegion  — český lokativ pro "motopůjčovna {inRegion}" ("na Vysočině")
//   cities    — [['name' => 'Jihlava', 'pop' => 51000], ...] (řazeno sestupně dle počtu obyvatel)

/**
 * Bezpečný slug z názvu města (pro kotvy / budoucí per-město stránky).
 * Odstraní diakritiku, malá písmena, mezery → pomlčky.
 */
function oblastiCitySlug($name) {
    $map = [
        'á'=>'a','č'=>'c','ď'=>'d','é'=>'e','ě'=>'e','í'=>'i','ň'=>'n','ó'=>'o','ř'=>'r',
        'š'=>'s','ť'=>'t','ú'=>'u','ů'=>'u','ý'=>'y','ž'=>'z',
        'Á'=>'a','Č'=>'c','Ď'=>'d','É'=>'e','Ě'=>'e','Í'=>'i','Ň'=>'n','Ó'=>'o','Ř'=>'r',
        'Š'=>'s','Ť'=>'t','Ú'=>'u','Ů'=>'u','Ý'=>'y','Ž'=>'z',
    ];
    $s = strtr($name, $map);
    $s = strtolower($s);
    $s = preg_replace('/[^a-z0-9]+/', '-', $s);
    return trim($s, '-');
}

/**
 * Vrátí všechny kraje + města (>10 000 obyvatel).
 * @return array<int,array{slug:string,name:string,seoName:string,inRegion:string,cities:array}>
 */
function oblastiRegions() {
    static $regions = null;
    if ($regions !== null) return $regions;

    $regions = [
        [
            'slug' => 'vysocina',
            'name' => 'Kraj Vysočina',
            'seoName' => 'Vysočina',
            'inRegion' => 'na Vysočině',
            'cities' => [
                ['name' => 'Jihlava',            'pop' => 51000],
                ['name' => 'Třebíč',             'pop' => 34000],
                ['name' => 'Havlíčkův Brod',     'pop' => 23000],
                ['name' => 'Žďár nad Sázavou',   'pop' => 20000],
                ['name' => 'Pelhřimov',          'pop' => 16000],
                ['name' => 'Velké Meziříčí',     'pop' => 11500],
                ['name' => 'Humpolec',           'pop' => 11000],
            ],
        ],
        [
            'slug' => 'jihomoravsky-kraj',
            'name' => 'Jihomoravský kraj',
            'seoName' => 'Jihomoravský kraj',
            'inRegion' => 'v Jihomoravském kraji',
            'cities' => [
                ['name' => 'Brno',               'pop' => 400000],
                ['name' => 'Znojmo',             'pop' => 33000],
                ['name' => 'Hodonín',            'pop' => 24000],
                ['name' => 'Břeclav',            'pop' => 24000],
                ['name' => 'Vyškov',             'pop' => 20000],
                ['name' => 'Blansko',            'pop' => 20000],
                ['name' => 'Boskovice',          'pop' => 11500],
                ['name' => 'Kyjov',              'pop' => 11000],
                ['name' => 'Veselí nad Moravou', 'pop' => 11000],
            ],
        ],
        [
            'slug' => 'jihocesky-kraj',
            'name' => 'Jihočeský kraj',
            'seoName' => 'Jihočeský kraj',
            'inRegion' => 'v Jihočeském kraji',
            'cities' => [
                ['name' => 'České Budějovice',   'pop' => 95000],
                ['name' => 'Tábor',              'pop' => 34000],
                ['name' => 'Písek',              'pop' => 30000],
                ['name' => 'Strakonice',         'pop' => 22000],
                ['name' => 'Jindřichův Hradec',  'pop' => 21000],
                ['name' => 'Český Krumlov',      'pop' => 13000],
                ['name' => 'Prachatice',         'pop' => 11000],
            ],
        ],
    ];

    // Doplň city slug pro každé město (pro kotvy a strukturovaná data).
    foreach ($regions as &$r) {
        foreach ($r['cities'] as &$c) {
            $c['slug'] = oblastiCitySlug($c['name']);
        }
        unset($c);
    }
    unset($r);

    return $regions;
}

/**
 * Najde kraj podle slugu. Vrátí null, pokud neexistuje.
 */
function oblastiFindRegion($slug) {
    foreach (oblastiRegions() as $r) {
        if ($r['slug'] === $slug) return $r;
    }
    return null;
}
