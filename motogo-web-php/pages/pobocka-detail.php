<?php
// ===== MotoGo24 Web PHP — Detail pobočky /pobocky/<slug> (CMS-driven) =====
// $_GET['slug'] nastaví index.php. Obsah = karta pobočky z data/pobocky.php
// přes CMS (`web.pobocky.branches.<i>.*`) + mapa + volitelné video (nahrané
// ve Velínu → Texty webu → pobočka → „Video“, nebo odkaz na YouTube).

require_once __DIR__ . '/../data/pobocky.php';
$sb = new SupabaseClient();
$defaults = pobockyDefaults();
$C = $sb->siteContent('pobocky', $defaults);

$slug = (string)($_GET['slug'] ?? '');
$idx = null;
foreach ($defaults['branches'] as $i => $d) { if (($d['slug'] ?? '') === $slug) { $idx = $i; break; } }
if ($idx === null) { http_response_code(404); require __DIR__ . '/404.php'; return; }

$b = pobockyBranch($C, $defaults, $idx);
$k = 'web.pobocky.branches.' . $idx;
$title = strip_tags((string)$b['title']);
$path = '/pobocky/' . $b['slug'];

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('menu.branches'), 'href' => '/pobocky'], htmlspecialchars($title)]);

$mapQ = (string)$b['map'];
$mapSrc = 'https://www.google.com/maps?q=' . rawurlencode($mapQ) . '&hl=' . i18nDetectLanguage() . '&z=14&output=embed';
$photo = trim((string)$b['photo']);

$cta = is_array($C['cta'] ?? null) ? array_merge($defaults['cta'], $C['cta']) : $defaults['cta'];

$content = pobockyCss() . '<main id="content"><div class="container">' . $bc
    . '<div class="ccontent"><section class="branch-card">'
    . ($photo !== '' ? '<img class="branch-photo" src="' . htmlspecialchars(BASE_URL . '/' . ltrim($photo, '/')) . '" alt="' . htmlspecialchars($title) . '">' : '')
    . '<span class="branch-badge" data-cms-key="' . $k . '.badge">' . sanitizeHtml((string)$b['badge']) . '</span>'
    . '<h1 data-cms-key="' . $k . '.title">' . sanitizeHtml((string)$b['title']) . '</h1>'
    . '<p>📍 <span data-cms-key="' . $k . '.address">' . sanitizeHtml((string)$b['address']) . '</span></p>'
    . '<p>🕑 <span data-cms-key="' . $k . '.hours">' . sanitizeHtml((string)$b['hours']) . '</span></p><p>&nbsp;</p>'
    . '<p data-cms-key="' . $k . '.text">' . sanitizeHtml((string)$b['text']) . '</p><p>&nbsp;</p>'
    . '<p>🧥 <span data-cms-key="' . $k . '.gear">' . sanitizeHtml((string)$b['gear']) . '</span></p><p>&nbsp;</p>'
    . '<h2 data-cms-key="' . $k . '.steps_title">' . sanitizeHtml((string)$b['steps_title']) . '</h2>'
    . '<p data-cms-key="' . $k . '.steps">' . sanitizeHtml((string)$b['steps']) . '</p>'
    . pobockyVideoHtml($b['video'] ?? '', $b['video_title'] ?? '', $k)
    . ($mapQ !== '' ? '<iframe class="map" loading="lazy" referrerpolicy="no-referrer-when-downgrade" allowfullscreen aria-label="' . htmlspecialchars($title) . '" src="' . htmlspecialchars($mapSrc) . '"></iframe>' : '')
    . '</section>'
    . '<section class="cta-green-box"><h2 data-cms-key="web.pobocky.cta.title">' . sanitizeHtml((string)$cta['title']) . '</h2>'
    . '<p data-cms-key="web.pobocky.cta.text">' . sanitizeHtml((string)$cta['text']) . '</p><p>&nbsp;</p>'
    . '<p><a class="btn btndark" href="' . BASE_URL . '/rezervace" data-cms-key="web.pobocky.cta.button">' . sanitizeHtml((string)$cta['button']) . '</a></p></section>'
    . '<p>&nbsp;</p><p><a href="' . BASE_URL . '/pobocky" data-cms-key="web.pobocky.back_link">' . sanitizeHtml((string)($C['back_link'] ?? $defaults['back_link'])) . '</a></p>'
    . '</div></div></main>';

renderPage(strip_tags((string)$b['seo_title']), $content, $path, [
    'description' => strip_tags((string)$b['seo_description']),
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('menu.branches'), 'url' => siteCanonicalUrl('/pobocky')],
        ['name' => $title, 'url' => siteCanonicalUrl($path)],
    ],
]);
