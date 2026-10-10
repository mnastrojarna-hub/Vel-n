<?php
// ===== Pobočky — landing v2: CS defaulty textů v2 + konfigurace poboček =====
// Používají pages/pobocky-v2.php (přehled) a pages/pobocka-detail-v2.php (detail),
// render bloků je v pages/pobocky-v2-ui.php. Zapíná se přes landingV2Enabled().
// Texty v2 = $C['v2'] (siteContent('pobocky') → lang/v2/<lang>/pobocky-v2.php
// 'pages.pobocky.v2', případně Velín CMS web.pobocky.v2.*) přes CS defaulty níže.
// Fakta jen z textů poboček (web.pobocky.*) a FAQ (parkování zdarma na obou
// pobočkách, přistavení za příplatek); dojezdové časy ověřené routováním OSRM
// (2026-10-10): Praha → Mezná ~92 min, jih Brna → VN ~19 min, centrum Brna ~28 min,
// letiště Brno-Tuřany ~36 min, Vídeň ~100 min (majitelem uváděných „15 min z letiště“ nesedí).

require_once __DIR__ . '/../landing.php';
require_once __DIR__ . '/pobocky-v2-ui.php';

/** Assety v2 pro renderPage() meta (landing + pobočky). $page: 'list' = přehled, 'detail' = detail pobočky. */
function pbV2Meta($page = 'detail') {
    $m = lpPageMeta();
    $m['styles'][] = '/css/landing-branch.css';
    $m['styles'][] = $page === 'list' ? '/css/landing-branch-list.css' : '/css/landing-branch-guide.css';
    $m['scripts'][] = '/js/landing-branch.js';
    return $m;
}

/** Merge: asociativní pole rekurzivně, seznam z overlaye nahradí celý; skalár přes pole se ignoruje. */
function pbMerge($a, $b) {
    if (!is_array($a)) return $b === null ? $a : $b;
    if (!is_array($b)) return $a;
    if ($b && array_keys($b) === range(0, count($b) - 1)) return $b;
    foreach ($b as $k => $v) $a[$k] = array_key_exists($k, $a) ? pbMerge($a[$k], $v) : $v;
    return $a;
}

/** Texty v2 (CS default ← jazykový overlay / CMS). */
function pbV2Texts($C) {
    return pbMerge(pbV2Defaults(), is_array($C['v2'] ?? null) ? $C['v2'] : []);
}

/** Konfigurace z kódu (jazykově nezávislá): foto, ikony a fotky kroků průvodce, záložní galerie. */
function pbBranchCfg($slug) {
    // hero: [src, srcset, šířka, výška]
    $hero = ['gfx/hero-banner-768.webp', '/gfx/hero-banner-768.webp 768w, /gfx/hero-banner-1500.webp 1500w', 768, 320];
    $cfg = [
        'mezna' => [
            'self' => false,
            'hero' => $hero,
            'card' => 'gfx/provozovna-1.jpg',
            // Mezná nemá v data/pobocky.php galerii → fotky provozovny (stejné jako na /kontakt)
            'gallery' => [['gfx/provozovna-1.jpg', 'gfx/provozovna-1.jpg', 'Showroom půjčovny motorek MotoGo24 v Pelhřimově'],
                ['gfx/provozovna-2.jpg', 'gfx/provozovna-2.jpg', 'Provozovna MotoGo24 — motorky připravené k zapůjčení'],
                ['gfx/provozovna-3.jpg', 'gfx/provozovna-3.jpg', 'Adventure motorky v půjčovně MotoGo24'],
                ['gfx/provozovna-4.jpg', 'gfx/provozovna-4.jpg', 'Sklad výbavy — helmy a oblečení v ceně zápůjčky']],
            // [ikona, indexy fotek galerie] — jen když počet kroků z CMS sedí
            'guide' => [['gfx/rezervace-online.svg', []], ['gfx/adresa.svg', [0]], ['gfx/predani-motorky.svg', [3]], ['gfx/vrat-motorku-vcas.svg', []]],
        ],
        'velke-nemcice' => [
            'self' => true,
            'hero' => ['gfx/pobocky/velke-nemcice/vydejni-box-640.webp', '/gfx/pobocky/velke-nemcice/vydejni-box-640.webp 640w, /gfx/pobocky/velke-nemcice/vydejni-box.webp 1600w', 640, 480],
            'card' => 'gfx/pobocky/velke-nemcice/vydejni-box-640.webp',
            'gallery' => [],
            'guide' => [['gfx/rezervace-online.svg', []], ['gate', [3, 4]], ['gfx/vyber-vybavu.svg', [1]], ['gfx/podpis-dokumentu.svg', [2]], ['lock', [3]], ['gfx/vrat-motorku-vcas.svg', [0]]],
        ],
    ];
    return $cfg[$slug] ?? ['self' => false, 'hero' => $hero, 'card' => '', 'gallery' => [], 'guide' => []];
}

/** Fotky pobočky: [[náhled, plná, popisek]] — z data/pobocky.php `gallery`, jinak záložní z konfigurace. Popisky z textů v2. */
function pbGallery($b, $VB) {
    $out = [];
    $dir = 'gfx/pobocky/' . rawurlencode(lpS($b['slug'] ?? '')) . '/';
    foreach ((is_array($b['gallery'] ?? null) ? array_values($b['gallery']) : []) as $it) {
        $f = rawurlencode(lpS($it[0] ?? ''));
        if ($f !== '') $out[] = [$dir . $f . '-640.webp', $dir . $f . '.webp', lpS($it[1] ?? '')];
    }
    if (!$out) $out = pbBranchCfg(lpS($b['slug'] ?? ''))['gallery'];
    $caps = is_array($VB['gallery'] ?? null) ? $VB['gallery'] : [];
    foreach ($out as $i => $g) if (lpPlain($caps[$i] ?? '') !== '') $out[$i][2] = lpPlain($caps[$i]);
    return $out;
}

/** Motorky dané pobočky (motorcycles.branch_id). */
function pbBranchMotos($motos, $branchId) {
    return array_values(array_filter((array)$motos, function ($m) use ($branchId) {
        return is_array($m) && $branchId !== '' && (string)($m['branch_id'] ?? '') === $branchId;
    }));
}

/** Odkazy karuselu motorek (Vše / kategorie / Zobrazit vše) → katalog filtrovaný na pobočku. */
function pbFleetForBranch($html, $branchId) {
    if (!preg_match('/^[0-9a-f-]{36}$/', $branchId)) return $html;
    return preg_replace_callback('~href="/katalog(/(?:cestovni|sportovni|naked|supermoto|chopper|scootery|detske|ostatni))?(\?[^"]*)?"~', function ($m) use ($branchId) {
        return 'href="/katalog' . ($m[1] ?? '') . (!empty($m[2]) ? $m[2] . '&amp;' : '?') . 'pobocka=' . $branchId . '"';
    }, $html);
}

/** Odkaz na Google Maps (navigace k pobočce). */
function pbMapsHref($q) {
    return 'https://www.google.com/maps/dir/?api=1&destination=' . rawurlencode(lpS($q));
}

/** CS defaulty textů v2 (ES překlad: lang/v2/es/pobocky-v2.php). */
function pbV2Defaults() {
    return require __DIR__ . '/pobocky-v2-texts.php';
}
