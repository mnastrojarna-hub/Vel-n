<?php
// ===== MotoGo24 Web PHP — Pobočky (CMS-driven) =====
// Přehled poboček: Mezná (obslužná) + Velké Němčice (samoobslužná).
// Všechny texty edituje Velín → Web CMS → Texty webu → „Pobočky“
// (klíče `web.pobocky.*` v `cms_variables`); defaults níže = výchozí znění.
// Fotky poboček doplníme (`photo` u pobočky = cesta v gfx/, prázdné = bez fotky).

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Pobočky | MotoGo24 – půjčovna motorek Pelhřimov a Brno',
        'description' => 'Pobočky půjčovny motorek MotoGo24: obslužná pobočka Mezná u Pelhřimova (Vysočina) a samoobslužná pobočka Velké Němčice u Brna — převzetí motorky nonstop.',
        'keywords' => 'pobočky MotoGo24, půjčovna motorek Pelhřimov, půjčovna motorek Brno, samoobslužná půjčovna motorek, Velké Němčice, Mezná',
    ],
    'h1' => 'Pobočky MotoGo24',
    'intro' => 'Motorku si u nás vyzvednete na <strong>dvou místech</strong> — na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde vás přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmete sami pomocí kódů.',
    'branches' => [
        [
            'badge' => 'Obslužná pobočka',
            'title' => 'Mezná u Pelhřimova',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'PO – NE nonstop, včetně víkendů a svátků. Čas převzetí a vrácení si zvolíte v rezervaci.',
            'text' => 'Naše hlavní pobočka na Vysočině. Motorku vám <strong>předáme osobně</strong> — vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud nabízíme i <strong>přistavení motorky</strong> na vámi zvolenou adresu.',
            'gear' => 'Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>.',
            'steps_title' => 'Jak to probíhá',
            'steps' => '1. Rezervujete a zaplatíte online (web nebo aplikace).<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese).',
            'map' => 'Mezná 9, 393 01 Pelhřimov',
            'photo' => '',
        ],
        [
            'badge' => 'Samoobslužná pobočka',
            'title' => 'Velké Němčice u Brna',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Nonstop 24/7 — motorku převezmete i vrátíte kdykoliv v termínu rezervace, bez domlouvání času.',
            'text' => 'Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí přímo na pobočce.',
            'gear' => 'Výbava pro řidiče v ceně — bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte.',
            'steps_title' => 'Jak to probíhá',
            'steps' => '1. Rezervujete a zaplatíte online, doplníte doklady — kódy najdete v aplikaci i v e-mailu.<br>2. Na pobočce zadáte kód šatny a vezmete si výbavu (s vlastní výbavou šatnu přeskočíte).<br>3. Na displeji podepíšete předávací protokol.<br>4. Kódem motorky otevřete kóji s motorkou a vyrazíte.<br>5. Po jízdě motorku vrátíte do kóje a výbavu do šatny.',
            'map' => '49.0046725,16.6721528',
            'photo' => '',
        ],
    ],
    'cta' => [
        'title' => 'Vyberte si motorku na své pobočce',
        'text' => 'V rezervaci uvidíte u každé motorky, na které pobočce je k dispozici.',
        'button' => 'REZERVOVAT ONLINE',
    ],
];

$C = $sb->siteContent('pobocky', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('menu.branches')]);

$css = '<style>'
    . '.branches-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px;margin:24px 0}'
    . '.branch-card{background:#fff;border-radius:20px;padding:24px;box-shadow:0 4px 18px rgba(0,0,0,.06)}'
    . '.branch-card img.branch-photo{width:100%;height:auto;border-radius:14px;margin-bottom:16px}'
    . '.branch-badge{display:inline-block;padding:4px 12px;border-radius:999px;background:#74FB71;color:#1a2e22;font-weight:800;font-size:.8rem;text-transform:uppercase;margin-bottom:10px}'
    . '.branch-card .map{width:100%;min-height:240px;border:0;border-radius:14px;margin-top:12px}'
    . '</style>';

$cards = '';
foreach ((is_array($C['branches'] ?? null) ? $C['branches'] : []) as $i => $b) {
    if (!is_array($b)) continue;
    $d = $defaults['branches'][$i] ?? [];
    $b = array_merge($d, $b);
    $k = 'web.pobocky.branches.' . $i;
    $photo = trim(strip_tags((string)($b['photo'] ?? '')));
    // Mapu a fotku bereme z kódu (defaults), CMS řídí jen texty.
    $mapQ = (string)($d['map'] ?? $b['address'] ?? '');
    $mapSrc = 'https://www.google.com/maps?q=' . rawurlencode($mapQ) . '&hl=' . i18nDetectLanguage() . '&z=14&output=embed';
    $cards .= '<section class="branch-card">'
        . ($photo !== '' ? '<img class="branch-photo" src="' . htmlspecialchars(BASE_URL . '/' . ltrim($photo, '/')) . '" alt="' . htmlspecialchars(strip_tags((string)$b['title'])) . '" loading="lazy">' : '')
        . '<span class="branch-badge" data-cms-key="' . $k . '.badge">' . sanitizeHtml((string)$b['badge']) . '</span>'
        . '<h2 data-cms-key="' . $k . '.title">' . sanitizeHtml((string)$b['title']) . '</h2>'
        . '<p>📍 <span data-cms-key="' . $k . '.address">' . sanitizeHtml((string)$b['address']) . '</span></p>'
        . '<p>🕑 <span data-cms-key="' . $k . '.hours">' . sanitizeHtml((string)$b['hours']) . '</span></p><p>&nbsp;</p>'
        . '<p data-cms-key="' . $k . '.text">' . sanitizeHtml((string)$b['text']) . '</p><p>&nbsp;</p>'
        . '<p>🧥 <span data-cms-key="' . $k . '.gear">' . sanitizeHtml((string)$b['gear']) . '</span></p><p>&nbsp;</p>'
        . '<h3 data-cms-key="' . $k . '.steps_title">' . sanitizeHtml((string)$b['steps_title']) . '</h3>'
        . '<p data-cms-key="' . $k . '.steps">' . sanitizeHtml((string)$b['steps']) . '</p>'
        . ($mapQ !== '' ? '<iframe class="map" loading="lazy" referrerpolicy="no-referrer-when-downgrade" allowfullscreen aria-label="' . htmlspecialchars(strip_tags((string)$b['title'])) . '" src="' . htmlspecialchars($mapSrc) . '"></iframe>' : '')
        . '</section>';
}

$cta = is_array($C['cta'] ?? null) ? array_merge($defaults['cta'], $C['cta']) : $defaults['cta'];
$ctaHtml = '<section class="cta-green-box"><h2 data-cms-key="web.pobocky.cta.title">' . sanitizeHtml((string)$cta['title']) . '</h2>'
    . '<p data-cms-key="web.pobocky.cta.text">' . sanitizeHtml((string)$cta['text']) . '</p><p>&nbsp;</p>'
    . '<p><a class="btn btndark" href="' . BASE_URL . '/rezervace" data-cms-key="web.pobocky.cta.button">' . sanitizeHtml((string)$cta['button']) . '</a></p></section>';

$content = $css . '<main id="content"><div class="container">' . $bc
    . '<div class="ccontent">'
    . '<h1 data-cms-key="web.pobocky.h1">' . sanitizeHtml((string)$C['h1']) . '</h1>'
    . '<p data-cms-key="web.pobocky.intro">' . sanitizeHtml((string)$C['intro']) . '</p>'
    . '<div class="branches-list">' . $cards . '</div>'
    . $ctaHtml
    . '</div></div></main>';

renderPage(strip_tags((string)$C['seo']['title']), $content, '/pobocky', [
    'description' => strip_tags((string)$C['seo']['description']),
    'keywords' => strip_tags((string)$C['seo']['keywords']),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('menu.branches'), 'url' => siteCanonicalUrl('/pobocky')],
    ],
]);
