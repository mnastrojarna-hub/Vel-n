<?php
// ===== MotoGo24 Web PHP — Homepage (CMS-driven) =====
// Kompletní obsah je editovatelný přes app_settings klíč 'site.home' (JSONB).
// Defaults níže jsou fallback, pokud v DB není nic.

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();
$posts = $sb->fetchCmsPages();
$reviews = $sb->fetchPublicReviews(6);

$defaults = [
    'seo' => [
        'title' => 'Motopůjčovna a půjčovna motorek na Vysočině | MotoGo24',
        'description' => 'Motopůjčovna na Vysočině – půjčte si motorku bez kauce, s výbavou v ceně a nonstop provozem. Cestovní, sportovní, enduro i dětské motorky. Online rezervace.',
        'keywords' => 'motopůjčovna, motopůjčovna Vysočina, motopůjčovna Pelhřimov, půjčovna motorek, půjčovna motorek Vysočina, půjčit motorku, pronájem motorky, půjčovna motocyklů, motorka bez kauce, nonstop motopůjčovna, online rezervace motorky, cestovní motorky, enduro motorky, dětské motorky, MotoGo24',
        // og_image necháme na default v renderPage() — ten použije aktuální doménu
        'og_image' => null,
    ],
    'hero' => [
        'image' => 'gfx/hero-banner.jpg',
        'alt' => 'Motopůjčovna a půjčovna motorek Vysočina',
        'eyebrow' => '<strong>Motopůjčovna</strong> a <strong>půjčovna motorek</strong> na Vysočině',
        'body' => 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z cestovních, sportovních i enduro modelů.<br>Rezervace s platbou kartou a rychlým převzetím.',
        'cta_primary' => ['label' => 'VYBER SI MOTORKU', 'href' => '/katalog', 'cls' => 'btngreen'],
        'cta_secondary' => ['label' => 'JAK TO FUNGUJE', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
    ],
    'h1' => 'Motopůjčovna Vysočina Motogo24 – půjčovna motorek bez kauce a nonstop',
    'intro' => 'Vítejte v <strong>Motogo24</strong> – vaší <strong>motopůjčovně</strong> a půjčovně motorek na Vysočině. U nás si půjčíte motorku <strong>bez kauce</strong>, s výbavou v ceně a v režimu <strong>nonstop</strong>. Ať hledáte cestovní, sportovní, enduro nebo dětskou motorku, Motogo24 vám v srdci Vysočiny nabídne motorku na míru.',
    'signposts_title' => 'Rychlý rozcestník po Motogo24',
    'signposts' => [
        ['icon' => 'gfx/vyber-motorku.svg', 'title' => 'Katalog motorek', 'text' => 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.', 'btn' => 'KATALOG MOTOREK', 'href' => '/katalog'],
        ['icon' => 'gfx/potvrzeni-rezervace.svg', 'title' => 'Jak si půjčit motorku', 'text' => 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte a vyjeďte.', 'btn' => 'JAK SI PŮJČIT MOTORKU', 'href' => '/jak-pujcit'],
        ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online rezervace motorky', 'text' => 'Zarezervujte si motorku na pronájem přes snadný online systém.', 'btn' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace'],
        ['icon' => 'gfx/kontakt.svg', 'title' => 'Kontakty a mapa', 'text' => 'Navštivte naši půjčovnu motorek v Pelhřimově nebo nás kontaktujte.', 'btn' => 'KONTAKT', 'href' => '/kontakt'],
        ['icon' => 'gfx/faq.svg', 'title' => 'Často kladené dotazy', 'text' => 'Nejčastější dotazy k půjčení motorky přehledně na jednom místě.', 'btn' => 'ČASTÉ DOTAZY', 'href' => '/jak-pujcit/faq'],
        ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => 'Motocyklové výlety', 'text' => 'Objevte nejlepší motocyklové trasy v Česku pro turisty i místní.', 'btn' => 'MOTOCYKLOVÉ TRASY', 'href' => '/blog'],
    ],
    'motos_section' => [
        'title' => 'Naše motorky k pronájmu na Vysočině',
        'intro' => 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší půjčovny motorek na Vysočině.',
        'empty' => 'Momentálně nemáme žádné motorky v nabídce.',
        'cta_label' => 'KATALOG MOTOREK',
        'cta_href' => '/katalog',
        'limit' => 4,
    ],
    'process' => [
        'title' => 'Jak probíhá půjčení motorky na Vysočině',
        'steps' => [
            ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Vyber', 'text' => 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.'],
            ['icon' => 'gfx/rezervace-online.svg', 'title' => '2. Rezervuj', 'text' => 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.'],
            ['icon' => 'gfx/predani-motorky.svg', 'title' => '3. Převzetí', 'text' => 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.'],
            ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => '4. Užij jízdu', 'text' => 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        // items se naplní z DB (faq_items WHERE featured_home=true) — viz níže
        'items' => [],
    ],
    'cta' => [
        'title' => 'Rezervuj svou motorku online',
        'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.',
        'buttons' => [
            ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
            ['label' => 'Dárkový poukaz', 'href' => '/poukazy', 'cls' => 'btndark'],
            ['label' => 'Tipy na trasy', 'href' => '/blog', 'cls' => 'btndark'],
        ],
    ],
    'blog' => [
        'title' => 'Blog a tipy',
        'empty' => 'Zatím nemáme žádné články.',
        'cta_label' => 'ČÍST VÍCE V BLOGU',
        'cta_href' => '/blog',
        'limit' => 3,
    ],
    'reviews' => [
        'title' => 'Co o nás říkají zákazníci',
        'intro' => 'Reálné recenze od motorkářů, kteří si u nás půjčili. Děkujeme za každé hodnocení.',
    ],
];

$C = $sb->siteContent('home', $defaults);

// ---- Signpost
// SEO: pouzivame renderHeading() ktery prazdny <h2>/<h3> neemittuje (externi
// SEO checker hlasil 'Chybi text titulku' u prazdnych signpost karet kdyz
// CMS klic neni vyplneny). Fallback hodnota zajisti, ze pri uplnem prazdnem
// CMS dostane visitor aspon nazev tlacitka jako titulek karty.
$signpostTitle = $C['signposts_title'] ?? 'Rychlý rozcestník po Motogo24';
$signHtml = '<section aria-labelledby="signpost-h">' . renderHeading(2, $signpostTitle, ['id'=>'signpost-h', 'cmsKey'=>'web.home.signposts_title', 'fallback'=>'Rychlý rozcestník po Motogo24']) . '<p>&nbsp;</p><div class="gr3">';
foreach ($C['signposts'] as $i => $s) {
    $iconSrc = BASE_URL . '/' . ltrim($s['icon'], '/');
    $titleText = trim(strip_tags($s['title'] ?? ''));
    $btnText = trim(strip_tags($s['btn'] ?? ''));
    if ($titleText === '' && $btnText !== '') $titleText = $btnText;
    $kBase = 'web.home.signposts.' . $i;
    $signHtml .= '<a class="gbox" href="' . BASE_URL . $s['href'] . '">' .
        '<div class="gr2"><div class="gbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="" aria-hidden="true" loading="lazy" width="36" height="36"></div><div>' .
        renderHeading(3, $titleText, ['cmsKey'=>$kBase.'.title', 'fallback'=>$btnText, 'allowHtml'=>true]) .
        '<p data-cms-key="' . $kBase . '.text">' . sanitizeHtml($s['text']) . '</p>' .
        '<div class="btn btngreen-small" data-cms-key="' . $kBase . '.btn">' . sanitizeHtml($s['btn']) . '</div></div></div></a>';
}
$signHtml .= '</div></section>';

// ---- Motorky
$mo = $C['motos_section'];
$motosHtml = '<section aria-labelledby="catalogue">' . renderHeading(2, $mo['title'] ?? '', ['id'=>'catalogue', 'cmsKey'=>'web.home.motos_section.title', 'fallback'=>'Naše motorky', 'allowHtml'=>true]) .
    '<p data-cms-key="web.home.motos_section.intro">' . sanitizeHtml($mo['intro']) . '</p><p>&nbsp;</p>' .
    '<div id="home-motos" class="gr4">';
if (!empty($motos)) {
    foreach (array_slice($motos, 0, (int)($mo['limit'] ?? 4)) as $m) {
        $motosHtml .= '<section aria-labelledby="catalogue">' . renderMotoCard($m) . '</section>';
    }
} else {
    $motosHtml .= '<p data-cms-key="web.home.motos_section.empty">' . htmlspecialchars($mo['empty']) . '</p>';
}
$motosHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $mo['cta_href'] . '" data-cms-key="web.home.motos_section.cta_label">' . $mo['cta_label'] . '</a></p></section>';

// ---- Proces
$processHtml = '<section aria-labelledby="process">' . renderHeading(2, $C['process']['title'] ?? '', ['id'=>'process', 'cmsKey'=>'web.home.process.title', 'fallback'=>'Jak si půjčit motorku', 'allowHtml'=>true]) . '<div class="gr4">';
foreach ($C['process']['steps'] as $i => $s) {
    $kBase = 'web.home.process.steps.' . $i;
    $processHtml .= renderWbox(
        $s['icon'],
        '<span data-cms-key="' . $kBase . '.title">' . $s['title'] . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . $s['text'] . '</span>'
    );
}
$processHtml .= '</div></section>';

// ---- FAQ — featured items z DB (faq_items WHERE featured_home=true)
// Položky se spravují ve Velíně v záložce „Časté dotazy"; admin označí 4 (nebo víc)
// otázek jako ⭐ a tady se zobrazí prvních N podle sort_order.
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$featuredFaq = $sb->fetchFaqItems(['featured_only' => true, 'limit' => 4]);
$faqItemsKeyed = [];
foreach ($featuredFaq as $r) {
    $q = function_exists('localized') ? (localized($r, 'question', $lang) ?: $r['question']) : $r['question'];
    $a = function_exists('localized') ? (localized($r, 'answer', $lang) ?: $r['answer']) : $r['answer'];
    $faqItemsKeyed[] = ['q' => $q, 'a' => $a];
}
$faqTitleKeyed = '<span data-cms-key="web.home.faq.title">' . ($C['faq']['title'] ?? '') . '</span>';
$faqHtml = !empty($faqItemsKeyed)
    ? renderFaqSection($faqTitleKeyed, $faqItemsKeyed, $C['faq']['more_link'] ?? null)
    : '';

// ---- CTA
$ctaButtonsKeyed = [];
foreach (($C['cta']['buttons'] ?? []) as $i => $btn) {
    $b = $btn;
    $b['label'] = '<span data-cms-key="web.home.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</span>';
    $ctaButtonsKeyed[] = $b;
}
$ctaHtml = renderCta(
    '<span data-cms-key="web.home.cta.title">' . ($C['cta']['title'] ?? '') . '</span>',
    '<span data-cms-key="web.home.cta.text">' . ($C['cta']['text'] ?? '') . '</span>',
    $ctaButtonsKeyed
);

// ---- Reviews (zobrazí se jen pokud data existují)
$reviewsHtml = '';
if (!empty($reviews)) {
    $reviewsHtml = '<section aria-labelledby="reviews">' . renderHeading(2, $C['reviews']['title'] ?? '', ['id'=>'reviews', 'cmsKey'=>'web.home.reviews.title', 'fallback'=>'Hodnocení zákazníků'])
        . '<p data-cms-key="web.home.reviews.intro">' . htmlspecialchars($C['reviews']['intro']) . '</p><p>&nbsp;</p>'
        . '<div class="gr3">';
    foreach ($reviews as $r) {
        $rating = (int)($r['rating'] ?? 0);
        $stars = str_repeat('★', max(0, min(5, $rating))) . str_repeat('☆', max(0, 5 - $rating));
        $author = htmlspecialchars($r['author_name'] ?? 'Spokojený zákazník');
        $comment = htmlspecialchars($r['comment'] ?? '');
        $reviewsHtml .= '<div class="review-card">'
            . '<div class="review-stars" aria-label="Hodnocení ' . $rating . ' z 5">' . $stars . '</div>'
            . '<p class="review-comment">„' . $comment . '"</p>'
            . '<p class="review-author">— <strong>' . $author . '</strong></p>'
            . '</div>';
    }
    $reviewsHtml .= '</div></section>';
}

// ---- Blog
$bl = $C['blog'];
$blogHtml = '<section aria-labelledby="blog">' . renderHeading(2, $bl['title'] ?? '', ['id'=>'blog', 'cmsKey'=>'web.home.blog.title', 'fallback'=>'Z blogu', 'allowHtml'=>true]) . '<div id="home-blog" class="gr3">';
if (!empty($posts)) {
    foreach (array_slice($posts, 0, (int)($bl['limit'] ?? 3)) as $p) {
        $blogHtml .= renderBlogCard($p);
    }
} else {
    $blogHtml .= '<p data-cms-key="web.home.blog.empty">' . htmlspecialchars($bl['empty']) . '</p>';
}
$blogHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $bl['cta_href'] . '" data-cms-key="web.home.blog.cta_label">' . $bl['cta_label'] . '</a></p></section>';

// ---- Banner (hero)
$hero = $C['hero'];
$heroImgUrl = BASE_URL . '/' . ltrim($hero['image'], '/');
$heroWebp = preg_replace('/\.(png|jpg|jpeg)$/i', '.webp', $heroImgUrl);
$ctaP = $hero['cta_primary'];
$ctaS = $hero['cta_secondary'];

// Caption overlay je IDENTICKÝ pro slideshow i statický fallback — texty
// (eyebrow/body/CTA) se nemění, mění se jen obrazové pozadí banneru.
$heroCaption = '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' .
    '<p data-cms-key="web.home.hero.eyebrow">' . sanitizeHtml($hero['eyebrow']) . '</p><p>&nbsp;</p>' .
    '<p data-cms-key="web.home.hero.body">' . sanitizeHtml($hero['body']) . '</p><p>&nbsp;</p>' .
    '<p><a class="btn ' . ($ctaP['cls'] ?? 'btngreen') . '" href="' . BASE_URL . $ctaP['href'] . '" data-cms-key="web.home.hero.cta_primary.label">' . $ctaP['label'] . '</a> <a class="btn ' . ($ctaS['cls'] ?? 'btndark') . '" href="' . BASE_URL . $ctaS['href'] . '" data-cms-key="web.home.hero.cta_secondary.label">' . $ctaS['label'] . '</a></p>' .
'</div></div></div>';

// Hero slideshow — automatický CSS crossfade hlavních fotek CELÉ aktuální
// flotily. Zdroj = $motos (fetchMotos), takže nová motorka přidaná ve Velíně
// se v hero objeví sama. Hlavní foto = image_url, fallback images[0]; motorky
// bez fotky přeskočíme. Když žádná motorka foto nemá → původní statický banner.
$heroSlides = [];
$heroHasVideo = false;
foreach ($motos as $hm) {
    // Videa TÉ motorky (volitelné). Když existují → slide je video a přepne se až
    // po dovysílání VŠECH videí (čas zobrazení = délka videí). Bez videa → foto slide.
    $vids = [];
    if (is_array($hm['videos'] ?? null)) {
        foreach ($hm['videos'] as $v) {
            if (is_string($v) && $v !== '') { $u = imgUrl($v); if ($u !== '' && !in_array($u, $vids, true)) $vids[] = $u; }
        }
    }
    // Pool všech DISTINCT fotek TÉ motorky: image_url (cover) + images[] galerie.
    $pool = [];
    $cover = (!empty($hm['image_url']) && is_string($hm['image_url'])) ? $hm['image_url'] : '';
    if ($cover !== '') $pool[] = $cover;
    if (is_array($hm['images'] ?? null)) {
        foreach ($hm['images'] as $u) {
            if (is_string($u) && $u !== '' && !in_array($u, $pool, true)) $pool[] = $u;
        }
    }
    if (empty($pool) && empty($vids)) continue;
    $modelName = trim((string)($hm['model'] ?? ''));
    if (!empty($vids)) {
        // Video slide. Poster = hlavní foto (když je), jinak žádný. `photos` = celý
        // pool fotek TÉ motorky → loading fotky se mezi videi střídají (ne pořád ta hlavní).
        $heroHasVideo = true;
        $heroSlides[] = ['type' => 'video', 'videos' => $vids, 'poster' => ($pool[0] ?? ''), 'photos' => $pool, 'model' => $modelName];
        continue;
    }
    $main = $pool[0];
    $rest = array_slice($pool, 1);
    if (!empty($rest)) {
        // 2+ fotky → druhá je náhodná DALŠÍ fotka stejné motorky.
        $secondary = $rest[array_rand($rest)];
        $split = false;
    } else {
        // Jen jedna fotka → na desktopu ji rozdělíme do dvou panelů (levá/pravá část),
        // ať je layout „dvě vedle sebe" konzistentní. Na mobilu se ukáže celá jako cover.
        $secondary = $main;
        $split = true;
    }
    $heroSlides[] = ['type' => 'image', 'main' => $main, 'secondary' => $secondary, 'split' => $split, 'model' => $modelName];
}

if (!empty($heroSlides) && $heroHasVideo) {
    // ---- JS-driven slideshow (aspoň jedna motorka má video) ----
    // Video slide se přepne až po skončení všech svých videí; foto slide po $per s.
    // Crossfade přes .is-active class (opacity transition v main.css).
    $per = 5;
    $slidesHtml = '';
    foreach ($heroSlides as $i => $s) {
        $modelName = $s['model'] !== '' ? $s['model'] : t('card.unnamedMotorcycle');
        $altText = he(t('common.motorcycleAlt', ['model' => $modelName]));
        $activeCls = ($i === 0) ? ' is-active' : '';
        if ($s['type'] === 'video') {
            $videosJson = htmlspecialchars(json_encode(array_values($s['videos']), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8');
            // Loading fotky TÉ motorky — vždy aspoň jedna (fallback = statický hero
            // banner). JS jimi mezi videi rotuje, ať se neukazuje pořád ta hlavní.
            $posterList = [];
            foreach (($s['photos'] ?? []) as $ph) {
                if (is_string($ph) && $ph !== '') { $u = imgUrlSized($ph, 1400, 70); if ($u !== '' && !in_array($u, $posterList, true)) $posterList[] = $u; }
            }
            if (empty($posterList)) $posterList[] = $heroImgUrl;
            $posterSrc = $posterList[0];
            $postersJson = htmlspecialchars(json_encode(array_values($posterList), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8');
            $posterAttr = ' poster="' . htmlspecialchars($posterSrc, ENT_QUOTES, 'UTF-8') . '"';
            // První (aktivní) slide dostane `src` přímo v HTML — přehraje se i bez JS
            // (stejně jako fotky mají src deklarativně). Ostatní slide-videa nechává
            // bez src; JS controller jim ho doplní, až na ně přijde řada.
            $srcAttr = ($i === 0 && !empty($s['videos'])) ? ' src="' . htmlspecialchars($s['videos'][0], ENT_QUOTES, 'UTF-8') . '"' : '';
            // Poster <img> leží PŘES video (z-index výš) a přepíná se přes opacity
            // (plynulý fade, žádné bliknutí). Navíc je stejná fotka i jako CSS pozadí
            // <video> elementu → i kdyby fade ne/zaostal, nikdy neprobleskne zelená.
            $bgStyle = ' style="background:#0e0e0e url(\'' . htmlspecialchars($posterSrc, ENT_QUOTES, 'UTF-8') . '\') center/cover no-repeat"';
            $slidesHtml .= '<div class="mg-hero-slide mg-hero-slide-video' . $activeCls . '" data-type="video" data-videos="' . $videosJson . '" data-posters="' . $postersJson . '">'
                . '<video class="mg-hero-video" muted autoplay playsinline webkit-playsinline preload="' . ($i === 0 ? 'auto' : 'metadata') . '"' . $posterAttr . $srcAttr . $bgStyle . ' aria-label="' . $altText . '"></video>'
                . '<img class="mg-hero-vposter" src="' . htmlspecialchars($posterSrc, ENT_QUOTES, 'UTF-8') . '" alt="' . $altText . '" decoding="async" aria-hidden="true" width="960" height="480">'
                . '</div>';
        } else {
            $eager = ($i === 0);
            $imgMain = '<img class="mg-hero-img mg-hero-img-main" src="' . htmlspecialchars(imgUrlSized($s['main'], 1000, 70)) . '"'
                . ' srcset="' . htmlspecialchars(imgSrcset($s['main'], [600, 1000, 1400], 70)) . '" sizes="(max-width:768px) 100vw, 50vw" alt="' . $altText . '"'
                . ($eager ? ' fetchpriority="high" decoding="async"' : ' loading="lazy" decoding="async"')
                . ' width="960" height="480">';
            $imgSecondary = '<img class="mg-hero-img mg-hero-img-alt" src="' . htmlspecialchars(imgUrlSized($s['secondary'], 1000, 70)) . '"'
                . ' srcset="' . htmlspecialchars(imgSrcset($s['secondary'], [600, 1000, 1400], 70)) . '" sizes="50vw" alt="' . $altText . '"'
                . ' loading="lazy" decoding="async" width="960" height="480">';
            $cls = 'mg-hero-slide' . (!empty($s['split']) ? ' mg-hero-split' : '') . $activeCls;
            $slidesHtml .= '<div class="' . $cls . '" data-type="image" data-duration="' . ($per * 1000) . '">' . $imgMain . $imgSecondary . '</div>';
        }
    }
    // Inline controller (stejný vzor inline <script> jako kalendář v katalog-detail.php).
    // Předčítání: skrytý <video preload="auto"> bufferuje VŽDY další video v pořadí,
    // takže než na něj přijde řada, je už načtené → přechod video→video je plynulý
    // a poster (fotka) se vůbec neukáže. Když video reálně nestihne naběhnout
    // (GRACE_MS), teprve pak se přes plynulý fade objeví fotka a zůstane MIN. 1 s
    // (MIN_POSTER_MS) → nikdy nic nebliká a nikdy není vidět zelená.
    $heroJs = '<script>(function(){var w=document.querySelector(".banner-slideshow-js");if(!w)return;'
        . 'var GRACE=220,MINP=1000;'
        . 'var sl=Array.prototype.slice.call(w.querySelectorAll(".mg-hero-slide"));if(!sl.length)return;'
        . 'var pf=document.createElement("video");pf.muted=true;pf.defaultMuted=true;pf.preload="auto";pf.setAttribute("muted","");pf.setAttribute("playsinline","");pf.style.cssText="position:absolute;left:-9999px;width:1px;height:1px;opacity:0;pointer-events:none";w.appendChild(pf);var lastPf="";'
        . 'function prefetch(u){if(!u||u===lastPf)return;lastPf=u;try{pf.src=u;pf.load();}catch(e){}}'
        . 'function vids(el){var l=[];try{l=JSON.parse(el.getAttribute("data-videos")||"[]");}catch(e){}return l;}'
        . 'function nextUrl(i,vi){var cur=sl[i];if(cur.getAttribute("data-type")==="video"){var l=vids(cur);if(vi+1<l.length)return l[vi+1];}for(var k=1;k<=sl.length;k++){var el=sl[(i+k)%sl.length];if(el.getAttribute("data-type")==="video"){var l2=vids(el);if(l2.length)return l2[0];}}return "";}'
        . 'var idx=0,timer=null;'
        . 'function clearT(){if(timer){clearTimeout(timer);timer=null;}}'
        . 'function next(){idx=(idx+1)%sl.length;show(idx);}'
        . 'function show(i){clearT();sl.forEach(function(el,k){el.classList.toggle("is-active",k===i);if(k!==i){var v=el.querySelector("video");if(v){try{v.pause();}catch(e){}}}el.classList.remove("vid-ready");});'
        . 'var cur=sl[i];if(cur.getAttribute("data-type")==="video"){playVid(cur,i,next);}else{var d=parseInt(cur.getAttribute("data-duration"),10)||5000;timer=setTimeout(next,d);prefetch(nextUrl(i,-1));}}'
        . 'function playVid(el,i,onDone){var v=el.querySelector("video");if(!v){timer=setTimeout(onDone,5000);return;}'
        . 'var list=vids(el);if(!list.length){timer=setTimeout(onDone,5000);return;}'
        . 'var img=el.querySelector(".mg-hero-vposter");var posters=[];try{posters=JSON.parse(el.getAttribute("data-posters")||"[]");}catch(e){}if(typeof el._pi!=="number")el._pi=0;'
        . 'var vi=0,safety=null,grace=null,reveal=null,posterAt=Date.now();'
        // poster ZOBRAZ (fade in) — rotuj loading fotku (další foto stejné motorky,
        // ne pořád ta hlavní), zapamatuj čas, ať vydrží min. 1 s, a přednačti další
        . 'function cover(){clearTimeout(reveal);if(el.classList.contains("vid-ready")){if(img&&posters.length>1){el._pi=(el._pi+1)%posters.length;img.src=posters[el._pi];v.style.backgroundImage="url(\'"+posters[el._pi]+"\')";var nx=new Image();nx.src=posters[(el._pi+1)%posters.length];}el.classList.remove("vid-ready");posterAt=Date.now();}}'
        // poster SKRYJ (fade out na video), ale nejdřív po MIN. 1 s viditelnosti
        . 'function uncover(){clearTimeout(grace);if(el.classList.contains("vid-ready"))return;var held=Date.now()-posterAt;if(held<MINP){clearTimeout(reveal);reveal=setTimeout(function(){el.classList.add("vid-ready");},MINP-held);}else{el.classList.add("vid-ready");}}'
        . 'v.onplaying=function(){clearTimeout(grace);uncover();};v.onwaiting=cover;v.onstalled=cover;'
        . 'function arm(){clearTimeout(safety);safety=setTimeout(step,30000);}'
        . 'function step(){clearTimeout(safety);vi++;if(vi>=list.length){onDone();return;}load();}'
        // při přepnutí zdroje neukazuj fotku hned: dej videu GRACE ms, ať plynule navazá
        . 'function load(){clearTimeout(grace);grace=setTimeout(cover,GRACE);v.muted=true;v.defaultMuted=true;v.playsInline=true;v.setAttribute("muted","");v.setAttribute("playsinline","");v.src=list[vi];var p=v.play();if(p&&p.catch){p.catch(function(){timer=setTimeout(onDone,5000);});}arm();prefetch(nextUrl(i,vi));}'
        . 'v.onended=step;v.onerror=function(){clearTimeout(safety);clearTimeout(grace);onDone();};load();}'
        . 'show(0);})();</script>';
    $bannerHtml = '<div class="banner banner-slideshow banner-slideshow-js">' . $slidesHtml . $heroCaption . '</div>' . $heroJs;
} elseif (!empty($heroSlides)) {
    // CSS-only crossfade: každý snímek viditelný $per s, celý cyklus = $per*N.
    // Per-snímek animation-delay fázuje snímky za sebe; poslední se prolne zpět
    // do prvního (bezešvá smyčka). Klíčové snímky závisí na počtu motorek →
    // generují se inline. (CSP povoluje inline <style>, viz blog.php.)
    $per = 5;
    $count = count($heroSlides);
    $cycle = $per * $count;
    $fadePct = $cycle > 0 ? round((0.8 / $cycle) * 100, 3) : 0; // ~0.8 s crossfade
    $onePct = round(100 / $count, 3);
    $kIn = $fadePct;                       // fade-in hotový
    $kHold = $onePct;                      // konec viditelnosti snímku
    $kOut = round($onePct + $fadePct, 3);  // fade-out hotový
    $heroStyle = '<style>'
        . '@keyframes mgHeroFade{0%{opacity:0}' . $kIn . '%{opacity:1}' . $kHold . '%{opacity:1}' . $kOut . '%{opacity:0}100%{opacity:0}}'
        . '.banner-slideshow .mg-hero-slide{animation:mgHeroFade ' . $cycle . 's linear infinite both}'
        . '</style>';

    $slidesHtml = '';
    foreach ($heroSlides as $i => $s) {
        $modelName = $s['model'] !== '' ? $s['model'] : t('card.unnamedMotorcycle');
        $altText = he(t('common.motorcycleAlt', ['model' => $modelName]));
        $eager = ($i === 0);
        // Hlavní foto — na mobilu jediné (plný cover), na desktopu levá polovina.
        $imgMain = '<img class="mg-hero-img mg-hero-img-main" src="' . htmlspecialchars(imgUrlSized($s['main'], 1000, 70)) . '"'
            . ' srcset="' . htmlspecialchars(imgSrcset($s['main'], [600, 1000, 1400], 70)) . '" sizes="(max-width:768px) 100vw, 50vw" alt="' . $altText . '"'
            . ($eager ? ' fetchpriority="high" decoding="async"' : ' loading="lazy" decoding="async"')
            . ' width="960" height="480">';
        // Pravá polovina — druhá fotka stejné motorky (nebo druhá část téže fotky
        // při split). Jen desktop (na mobilu skryté přes CSS).
        $imgSecondary = '<img class="mg-hero-img mg-hero-img-alt" src="' . htmlspecialchars(imgUrlSized($s['secondary'], 1000, 70)) . '"'
            . ' srcset="' . htmlspecialchars(imgSrcset($s['secondary'], [600, 1000, 1400], 70)) . '" sizes="50vw" alt="' . $altText . '"'
            . ' loading="lazy" decoding="async" width="960" height="480">';
        $cls = 'mg-hero-slide' . (!empty($s['split']) ? ' mg-hero-split' : '');
        $slidesHtml .= '<div class="' . $cls . '" style="animation-delay:' . ($i * $per) . 's">' . $imgMain . $imgSecondary . '</div>';
    }

    $bannerHtml = $heroStyle . '<div class="banner banner-slideshow">' . $slidesHtml . $heroCaption . '</div>';
} else {
    // Fallback: původní statický banner (responsive srcset, beze změny).
    $heroBase = preg_replace('/\.webp$/i', '', $heroWebp);
    $heroSrcset = $heroBase . '-480.webp 480w, ' . $heroBase . '-768.webp 768w, ' . $heroBase . '-1500.webp 1500w, ' . $heroWebp . ' 1920w';
    $bannerHtml = '<div class="banner">' .
        '<picture>' .
            '<source srcset="' . htmlspecialchars($heroSrcset) . '" type="image/webp" sizes="100vw">' .
            '<img fetchpriority="high" decoding="async" alt="' . htmlspecialchars($hero['alt']) . '" src="' . htmlspecialchars($heroImgUrl) . '" width="1920" height="480">' .
        '</picture>' . $heroCaption . '</div>';
}

$introHtml = !empty($C['intro']) ? '<p class="home-intro" data-cms-key="web.home.intro">' . sanitizeHtml($C['intro']) . '</p>' : '';

$content = $bannerHtml .
    '<main id="content"><div class="container"><h1 data-cms-key="web.home.h1">' . $C['h1'] . '</h1>' . $introHtml .
    $signHtml . $motosHtml . $processHtml . $faqHtml . $reviewsHtml . $ctaHtml . $blogHtml .
    '</div></main>';

// ---- Strukturovaná data: FAQ + HowTo + AggregateRating ze sekcí výše ----

// FAQPage schema z $faqItemsKeyed (DB-driven) — stripuje HTML, zachycuje strong/em jako text.
$faqSchemaItems = [];
if (!empty($faqItemsKeyed) && is_array($faqItemsKeyed)) {
    foreach ($faqItemsKeyed as $f) {
        $q = trim(strip_tags($f['q'] ?? ''));
        $a = trim(strip_tags($f['a'] ?? ''));
        if ($q === '' || $a === '') continue;
        $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode($q, JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode($a, JSON_UNESCAPED_UNICODE) . '}}';
    }
}
$faqSchema = '';
if (!empty($faqSchemaItems)) {
    $faqSchema = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}</script>';
}

// HowTo schema z $C['process']['steps'] — návod "Jak si půjčit motorku v Motogo24".
$howToSteps = [];
if (!empty($C['process']['steps']) && is_array($C['process']['steps'])) {
    foreach ($C['process']['steps'] as $i => $s) {
        $name = trim(strip_tags($s['title'] ?? ''));
        $text = trim(strip_tags($s['text'] ?? ''));
        if ($name === '' || $text === '') continue;
        $howToSteps[] = '{"@type":"HowToStep","position":' . ($i + 1) . ',"name":' . json_encode($name, JSON_UNESCAPED_UNICODE) . ',"text":' . json_encode($text, JSON_UNESCAPED_UNICODE) . ',"url":' . json_encode(siteCanonicalUrl('/jak-pujcit#krok-' . ($i + 1)), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . '}';
    }
}
$howToSchema = '';
if (!empty($howToSteps)) {
    $howToSchema = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"HowTo","name":"Jak si půjčit motorku v MotoGo24","description":"Snadný 4krokový postup — výběr motorky, online rezervace, převzetí na pobočce v Pelhřimově, jízda.","totalTime":"PT10M","estimatedCost":{"@type":"MonetaryAmount","currency":"CZK","value":"990"},"supply":[{"@type":"HowToSupply","name":"Řidičský průkaz odpovídající skupiny (AM/A1/A2/A nebo B)"},{"@type":"HowToSupply","name":"Občanský průkaz nebo pas"},{"@type":"HowToSupply","name":"Platební karta (Visa/Mastercard, Apple/Google Pay)"}],"tool":[{"@type":"HowToTool","name":"Online rezervační formulář"}],"step":[' . implode(',', $howToSteps) . ']}</script>';
}

// AggregateRating z reálných reviews — pokud máme aspoň 1 recenzi s ratingem.
$aggRating = null;
if (!empty($reviews) && is_array($reviews)) {
    $rated = array_filter($reviews, function ($r) { return !empty($r['rating']); });
    if (count($rated) > 0) {
        $sum = array_sum(array_map(function ($r) { return (int)$r['rating']; }, $rated));
        $cnt = count($rated);
        $avg = round($sum / $cnt, 1);
        $aggRating = ['rating' => $avg, 'count' => $cnt];
    }
}

// Pro non-CZ jazyky preferuj prelozenou seo.home.description/keywords pred CZ defaultem
// (Velin CMS ma jen CZ texty; bez fallbacku Google indexuje EN/DE/FR... s CZ popiskem).
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$homeDesc = ($lang !== 'cs' && function_exists('t')) ? t('seo.home.description') : $C['seo']['description'];
$homeKw   = ($lang !== 'cs' && function_exists('t')) ? t('seo.home.keywords')    : $C['seo']['keywords'];

renderPage($C['seo']['title'], $content, '/', [
    'description' => $homeDesc,
    'keywords' => $homeKw,
    'og_image' => $C['seo']['og_image'] ?? null,
    'schema' => $faqSchema . $howToSchema,
    'aggregate_rating' => $aggRating,
    'speakable' => ['h1', '.home-intro', '[aria-labelledby="catalogue"] > h2', '[aria-labelledby="process"]'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
    ],
]);
