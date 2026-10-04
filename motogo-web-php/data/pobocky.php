<?php
// ===== MotoGo24 — Pobočky: výchozí texty + sdílené helpery =====
// Používá přehled /pobocky (pages/pobocky.php) i detail /pobocky/<slug>
// (pages/pobocka-detail.php). Texty edituje Velín → Web CMS → Texty webu →
// „Pobočky – přehled“ / „Pobočka Mezná“ / „Pobočka Velké Němčice“ (klíče
// `web.pobocky.*` v `cms_variables`). Shodné defaulty drží Velín
// (velin/src/pages/cms/webTextsPobocky.js) a appka (features/branches).
// `slug`, `branch_id` (= branches.id — předvyplnění pobočky v /rezervace?pobocka=<id>), `map`, `photo` a `gallery`
// (fotky v gfx/pobocky/<slug>/) jdou jen z kódu; `video` = URL nahraná ve Velínu
// (bucket media) nebo odkaz na YouTube, prázdné = bez videa.

function pobockyDefaults() {
    return [
    'seo' => [
        'title' => 'Pobočky | MotoGo24 – půjčovna motorek Pelhřimov a Brno',
        'description' => 'Pobočky půjčovny motorek MotoGo24: obslužná pobočka Mezná u Pelhřimova (Vysočina) a samoobslužná pobočka Velké Němčice u Brna — převzetí motorky nonstop.',
        'keywords' => 'pobočky MotoGo24, půjčovna motorek Pelhřimov, půjčovna motorek Brno, samoobslužná půjčovna motorek, Velké Němčice, Mezná',
    ],
    'h1' => 'Pobočky MotoGo24',
    'intro' => 'Motorku si u nás vyzvednete na <strong>dvou místech</strong> — na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde vás přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmete sami pomocí kódů.',
    'branches' => [
        [
            'slug' => 'mezna',
            'branch_id' => '11111111-1111-1111-1111-111111111111',
            'badge' => 'Obslužná pobočka',
            'title' => 'Mezná u Pelhřimova',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'PO – NE nonstop, včetně víkendů a svátků. Čas převzetí a vrácení si zvolíte v rezervaci.',
            'text' => 'Naše hlavní pobočka na Vysočině. Motorku vám <strong>předáme osobně</strong> — vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud nabízíme i <strong>přistavení motorky</strong> na vámi zvolenou adresu.',
            'gear' => 'Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>. Jen tady si můžete zapůjčit i <strong>nepromoky</strong> a další doplňkovou výbavu.',
            'steps_title' => 'Jak to probíhá',
            'steps' => '1. Rezervujete a zaplatíte online (web nebo aplikace).<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese).',
            'map' => 'Mezná 9, 393 01 Pelhřimov',
            'photo' => '',
            'video' => '',
            'video_title' => 'Video: jak to na pobočce probíhá',
            'gallery' => [],
            'gallery_title' => 'Fotogalerie pobočky',
            'seo_title' => 'Pobočka Mezná u Pelhřimova | MotoGo24 – obslužná půjčovna motorek',
            'seo_description' => 'Obslužná pobočka půjčovny motorek MotoGo24 v Mezné u Pelhřimova (Vysočina): osobní předání motorky nonstop, výbava v ceně, přistavení na adresu.',
        ],
        [
            'slug' => 'velke-nemcice',
            'branch_id' => '22222222-2222-2222-2222-222222222222',
            'badge' => 'Samoobslužná pobočka',
            'title' => 'Velké Němčice u Brna',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Nonstop 24/7 kódem z aplikace. Čas vyzvednutí si zvolíte v rezervaci — při vyzvednutí od 12:00 (výpůjčka 2 a více dní) máte 1. den za polovinu a kiosk vám motorku vydá až od 12:00. Čas vrácení nevolíte: motorku vrátíte kdykoliv poslední den výpůjčky do 24:00.',
            'text' => 'Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme. U pobočky můžete po celou dobu výpůjčky <strong>parkovat zdarma</strong>.',
            'gear' => 'K dispozici je jen <strong>helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty</strong> — výbava pro řidiče je v ceně, motocyklové boty za příplatek. Bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). <strong>Nepromoky</strong> ani další doplňkovou výbavu na samoobslužné pobočce nepůjčujeme — ty jsou jen na obslužné pobočce v Mezné. Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte. Reflexní vestu, lékárničku, záznam o nehodě, kotoučový zámek a klíček k držáku telefonu najdete v motorce.',
            'steps_title' => 'Jak to probíhá',
            'steps' => '1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a doplníte doklady. V aplikaci, e-mailu a SMS pak dostanete kódy v pořadí, v jakém je budete zadávat: <strong>1) kód schránky s klíčem od brány, 2) kód šatny</strong> (máte-li zapůjčenou výbavu) <strong>a 3) kód motorky</strong>.<br>2. <strong>Je-li vjezdová brána zavřená</strong>, otevřete kódem z aplikace <strong>horní schránku na pravém sloupku vrat</strong> — je v ní klíč od visacího zámku. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě <strong>1–7 vpravo u plotu</strong> (viz fotka parkoviště). Auto tu může zdarma stát po celou dobu výpůjčky. Je-li brána otevřená, kód schránky nepotřebujete.<br>3. Na displeji zadáte kód šatny — <strong>šatna jsou dveře č. 8</strong>. Převléknete se a vezmete si výbavu (s vlastní výbavou šatnu přeskočíte). Máte-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>4. Na displeji v předávacím protokolu upravíte velikosti, protokol podepíšete a zadáte kód motorky — otevře se kóje s motorkou. Šatnu i kóji zavřete a vyrazíte.<br>5. <strong>Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník.</strong> Otevřenou bránu nechte otevřenou — stav brány nikdy neměňte.<br>6. Po jízdě motorku vrátíte do kóje a výbavu do šatny — kdykoliv poslední den výpůjčky do 24:00. Je-li brána zavřená, postupujete stejně: odemknete ji klíčem ze schránky a po odjezdu ji zase zamknete a klíč vrátíte.',
            'map' => '49.0046725,16.6721528',
            'photo' => '',
            'video' => '',
            'video_title' => 'Video: jak se obsloužit na samoobslužné pobočce',
            // [soubor bez .webp v gfx/pobocky/velke-nemcice/ (+ náhled -640), popisek]
            'gallery' => [
                ['vydejni-box', 'Výdejní box samoobslužné pobočky — kóje s motorkami'],
                ['vydejni-box-2', 'Výdejní box s kójemi 1–8 a šatnou'],
                ['displej-kiosk', 'Dotykový displej pro zadání kódu z aplikace'],
                ['parkoviste', 'Parkoviště pro zákazníky — místa 1–7 vpravo u plotu, parkování zdarma po dobu výpůjčky'],
            ],
            'gallery_title' => 'Fotogalerie pobočky',
            'seo_title' => 'Samoobslužná pobočka Velké Němčice u Brna | MotoGo24',
            'seo_description' => 'Samoobslužná pobočka půjčovny motorek MotoGo24 ve Velkých Němčicích u Brna: převzetí i vrácení 24/7 kódem z aplikace, čas vyzvednutí volíte v rezervaci (od 12:00 je 1. den za polovinu), parkování zdarma.',
        ],
    ],
    'detail_button' => 'Detail pobočky',
    'back_link' => '← Všechny pobočky',
    'cta' => [
        'title' => 'Vyberte si motorku na své pobočce',
        'text' => 'V rezervaci uvidíte u každé motorky, na které pobočce je k dispozici.',
        'button' => 'REZERVOVAT ONLINE',
    ],
];
}

/** Pobočka i: CMS hodnoty přes defaulty (slug/branch_id/map/photo/gallery vždy z kódu). */
function pobockyBranch($C, $D, $i) {
    $d = $D['branches'][$i] ?? [];
    $b = (is_array($C['branches'][$i] ?? null)) ? array_merge($d, $C['branches'][$i]) : $d;
    foreach (['slug', 'branch_id', 'map', 'photo', 'gallery'] as $k) $b[$k] = $d[$k] ?? '';
    return $b;
}

/** Video pobočky — YouTube odkaz → embed, jinak <video> (mp4/webm z Velína). */
function pobockyVideoHtml($url, $title, $key) {
    $url = trim(strip_tags((string)$url));
    if ($url === '' || !preg_match('#^https://#i', $url)) return '';
    $t = sanitizeHtml((string)$title);
    $alt = htmlspecialchars(strip_tags((string)$title));
    if (preg_match('#(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{6,})#', $url, $m)) {
        $player = '<div class="branch-video-yt"><iframe src="https://www.youtube-nocookie.com/embed/' . $m[1] . '" title="' . $alt . '" loading="lazy" allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen></iframe></div>';
    } else {
        $player = '<video class="branch-video" controls playsinline preload="metadata" src="' . htmlspecialchars($url) . '"></video>';
    }
    return '<section class="branch-video-wrap"><h2 data-cms-key="' . $key . '.video_title">' . $t . '</h2>' . $player . '</section>';
}

/** Fotogalerie pobočky — náhledy (-640.webp) otevírají sdílený lightbox. */
function pobockyGalleryHtml($b, $key) {
    $items = is_array($b['gallery'] ?? null) ? $b['gallery'] : [];
    if (!$items) return '';
    $dir = BASE_URL . '/gfx/pobocky/' . rawurlencode((string)$b['slug']) . '/';
    $open = htmlspecialchars(t('gallery.openImage'));
    $h = '';
    foreach (array_values($items) as $i => $it) {
        $f = rawurlencode((string)($it[0] ?? ''));
        $alt = htmlspecialchars((string)($it[1] ?? ''));
        $h .= '<a href="' . $dir . $f . '.webp" data-gallery="branch" data-index="' . $i . '" aria-label="' . $open . '">'
            . '<img src="' . $dir . $f . '-640.webp" alt="' . $alt . '" loading="lazy" decoding="async"></a>';
    }
    return '<section class="branch-gallery-wrap"><h2 data-cms-key="' . $key . '.gallery_title">'
        . sanitizeHtml((string)($b['gallery_title'] ?? '')) . '</h2><div class="branch-gallery">' . $h . '</div></section>';
}

function pobockyCss() {
    return '<style>'
        . '.branches-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px;margin:24px 0}'
        . '.branch-card{background:#fff;border-radius:20px;padding:24px;box-shadow:0 4px 18px rgba(0,0,0,.06)}'
        . '.branch-card img.branch-photo{width:100%;height:auto;border-radius:14px;margin-bottom:16px}'
        . '.branch-badge{display:inline-block;padding:4px 12px;border-radius:999px;background:#74FB71;color:#1a2e22;font-weight:800;font-size:.8rem;text-transform:uppercase;margin-bottom:10px}'
        . '.branch-card .map{width:100%;min-height:240px;border:0;border-radius:14px;margin-top:12px}'
        . '.branch-video-wrap{margin:24px 0}.branch-video{width:100%;max-height:70vh;border-radius:14px;background:#000}'
        . '.branch-video-yt{position:relative;padding-top:56.25%}.branch-video-yt iframe{position:absolute;inset:0;width:100%;height:100%;border:0;border-radius:14px}'
        . '.branch-gallery-wrap{margin:24px 0}.branch-gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}'
        . '.branch-gallery a{display:block;border-radius:14px;overflow:hidden;aspect-ratio:4/3;background:#eef2ef}'
        . '.branch-gallery img{width:100%;height:100%;object-fit:cover;display:block;transition:transform .2s}.branch-gallery a:hover img{transform:scale(1.04)}'
        . '</style>';
}
