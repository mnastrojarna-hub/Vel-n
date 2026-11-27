<?php
// ===== MotoGo24 — SEO stránky poboček (majitel 2026-11-26) =====
// „Motopůjčovna Brno a jižní Morava“ (/motopujcovna-brno → pobočka Velké Němčice) a
// „Motopůjčovna Vysočina“ (/motopujcovna-vysocina → pobočka Mezná). Nahradily krajské
// stránky /oblasti (šablonový text pro kraje bez pobočky); staré adresy /oblasti* vedou
// 301 sem (index.php). Stránky jsou jen česky — v cizím jazyce 301 na detail pobočky.
// Texty: data/seo-<id>.php (CS defaulty) ← Velín CMS / inline editace (web.seo_<id>.*).
// Odkazy: menu Pobočky (layout.php), sitemap.php, mapa stránek, stránky poboček.

/** id => path (kanonická CS cesta), key (siteContent / CMS), file (texty), branch (index v pobockyDefaults()), menu (popisek v menu). */
function seoPobockyPages() {
    return [
        'brno' => ['path' => '/motopujcovna-brno', 'key' => 'seo_brno', 'file' => 'seo-brno.php', 'branch' => 1, 'menu' => 'Motopůjčovna Brno a jižní Morava'],
        'vysocina' => ['path' => '/motopujcovna-vysocina', 'key' => 'seo_vysocina', 'file' => 'seo-vysocina.php', 'branch' => 0, 'menu' => 'Motopůjčovna Vysočina'],
    ];
}

/** Id SEO stránky podle kanonické cesty (null = není SEO stránka pobočky). */
function seoPobockyIdByPath($path) {
    foreach (seoPobockyPages() as $id => $p) if ($p['path'] === $path) return $id;
    return null;
}

/** Kam vede 301 ze zrušené /oblasti/<kraj> — nejbližší pobočka, jinak přehled poboček. */
function seoPobockyRegionTarget($regionSlug) {
    $map = ['vysocina' => '/motopujcovna-vysocina', 'jihocesky-kraj' => '/motopujcovna-vysocina', 'jihomoravsky-kraj' => '/motopujcovna-brno'];
    return $map[(string)$regionSlug] ?? '/pobocky';
}
