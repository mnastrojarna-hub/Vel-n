<?php
// ===== MotoGo24 Web PHP — Reusable Components =====
// IDENTICKÝ HTML výstup jako components.js

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/supabase.php';

/**
 * Sanitizuje HTML content z DB (blog, CMS stránky, wysiwyg výstup).
 * Odstraní <script>, <iframe> (pokud nejsou whitelistnuté), on* event
 * handler atributy, javascript:/data: URL v href/src. Zachovává běžné
 * formátovací tagy.
 */
function sanitizeHtml($html, $allowIframe = false) {
    if (!$html || !is_string($html)) return '';
    // <script> bloky pryč
    $html = preg_replace('#<script\b[^>]*>.*?</script\s*>#is', '', $html);
    $html = preg_replace('#<script\b[^>]*/?>#is', '', $html);
    // <style> bloky pryč (nevíme, co by zanesly)
    $html = preg_replace('#<style\b[^>]*>.*?</style\s*>#is', '', $html);
    // <iframe> pryč pokud není povolen
    if (!$allowIframe) {
        $html = preg_replace('#<iframe\b[^>]*>.*?</iframe\s*>#is', '', $html);
        $html = preg_replace('#<iframe\b[^>]*/?>#is', '', $html);
    }
    // on* atributy (onclick=, onload=, ...)
    $html = preg_replace('#\son[a-z]+\s*=\s*"[^"]*"#i', '', $html);
    $html = preg_replace("#\son[a-z]+\s*=\s*'[^']*'#i", '', $html);
    $html = preg_replace('#\son[a-z]+\s*=\s*[^\s>]+#i', '', $html);
    // javascript: / vbscript: / data: (kromě data:image) v href/src
    $html = preg_replace_callback(
        '#\b(href|src|xlink:href)\s*=\s*(["\'])([^"\']*)\2#i',
        function ($m) {
            $url = trim($m[3]);
            $low = strtolower($url);
            if (preg_match('#^\s*(javascript|vbscript):#i', $low)) return $m[1] . '="#"';
            if (preg_match('#^\s*data:(?!image/)#i', $low)) return $m[1] . '="#"';
            return $m[0];
        },
        $html
    );
    return $html;
}

/**
 * Převede relativní cestu na Supabase storage URL.
 * Odpovídá MG.imgUrl() v components.js.
 */
function imgUrl($src) {
    if (!$src) return '';
    if (strpos($src, 'http://') === 0 || strpos($src, 'https://') === 0 || strpos($src, 'data:') === 0) {
        return $src;
    }
    return SUPABASE_URL . '/storage/v1/object/public/media/' . $src;
}

/**
 * HTML karta motorky — odpovídá MG.renderMotoCard() v components.js.
 * ZMĚNA: href z #/katalog/{id} na /katalog/{id}
 */
function renderMotoCard($m) {
    $img = imgUrl($m['image_url'] ?? ($m['images'][0] ?? ''));
    $desc = $m['ideal_usage'] ?? '';
    $cat = $m['category'] ?? '';
    $kw = !empty($m['power_kw']) ? ($m['power_kw'] . ' kW') : '';
    $price = getMinPrice($m);
    $license = $m['license_required'] ?? '';

    $features = [];
    if ($cat) $features[] = htmlspecialchars($cat);
    if ($license && $license !== 'N') $features[] = htmlspecialchars($license);
    if ($kw) $features[] = htmlspecialchars($kw);
    if (!empty($m['has_abs'])) $features[] = 'ABS';
    if ($desc && is_string($desc)) {
        foreach (explode(',', $desc) as $f) {
            $t = trim($f);
            if ($t && count($features) < 6) $features[] = htmlspecialchars($t);
        }
    } elseif (is_array($desc)) {
        foreach ($desc as $f) {
            $t = is_string($f) ? trim($f) : (string)$f;
            if ($t && count($features) < 6) $features[] = htmlspecialchars($t);
        }
    }

    $featHtml = '<ul>';
    foreach ($features as $f) { $featHtml .= '<li>' . $f . '</li>'; }
    $featHtml .= '</ul>';

    $priceText = $price > 0 ? ('Cena: od ' . formatPrice($price) . '/den') : '';
    $model = htmlspecialchars($m['model'] ?? '');
    $id = htmlspecialchars($m['id'] ?? '');

    // Branch info (pokud tabulka motorcycles byla joinnutá s branches)
    $branch = $m['branches'] ?? null;
    $branchLine = '';
    if (is_array($branch) && !empty($branch['name'])) {
        $branchLine = '<p class="moto-branch-line"><span aria-hidden="true">📍</span> ' . htmlspecialchars($branch['name']) . '</p>';
    }

    // Available badge — "k dispozici" pokud status=active (rezervační kalendář je v detailu)
    $badge = '';
    if (($m['status'] ?? '') === 'active') {
        $badge = '<span class="moto-card-badge">Dostupné</span>';
    }

    return '<a class="moto-wrapper" href="' . BASE_URL . '/katalog/' . $id . '" aria-label="' . $model . '">' .
        '<div class="moto-title"><h2>' . $model . '</h2></div>' .
        ($badge ? $badge : '') .
        '<div class="moto-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $model . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="moto-desc">' . $featHtml . $branchLine . ($priceText ? '<p class="moto-price">' . $priceText . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">DETAIL MOTORKY</span></div>' .
    '</a>';
}

/**
 * HTML karta blogu — odpovídá MG.renderBlogCard() v components.js.
 * Podporuje i relativní cesty začínající /gfx/ (lokální obrázky).
 */
function renderBlogCard($post) {
    $images = $post['images'] ?? [];
    $img = (!empty($images) ? $images[0] : '') ?: ($post['image_url'] ?? '');
    // Relativní lokální cesty: /gfx/... nebo gfx/...
    if ($img && strpos($img, 'http') !== 0 && strpos($img, 'data:') !== 0) {
        $img = BASE_URL . '/' . ltrim($img, '/');
    }
    $tags = $post['tags'] ?? [];
    $tag = !empty($tags) ? $tags[0] : '';
    $excerpt = $post['excerpt'] ?? ($post['description'] ?? '');
    $title = htmlspecialchars($post['title'] ?? '');
    $slug = htmlspecialchars($post['slug'] ?? '');

    return '<div><a class="blog-wrapper" href="' . BASE_URL . '/blog/' . $slug . '" aria-label="' . $title . '">' .
        '<div class="blog-title"><h2>' . $title . '</h2></div>' .
        '<div class="blog-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $title . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="blog-desc">' . ($tag ? '<p><span class="tag-label">' . htmlspecialchars($tag) . '</span></p>' : '') . '<p>' . htmlspecialchars($excerpt) . '</p></div>' .
        '<div class="blog-btn"><span class="btn btngreen-small">PŘEČÍST ČLÁNEK</span></div>' .
    '</a></div>';
}

/**
 * Ikona box — odpovídá MG.renderWbox() v components.js.
 */
function renderWbox($icon, $title, $text) {
    $iconSrc = $icon ? BASE_URL . '/' . ltrim($icon, '/') : '';
    return '<div class="wbox">' .
        ($icon ? '<div class="wbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . strip_tags($title) . '" loading="lazy"></div>' : '') .
        '<h3><p>' . $title . '</p></h3>' .
        '<p>' . $text . '</p></div>';
}

/**
 * FAQ accordion item — odpovídá MG.renderFaqItem() v components.js.
 */
function renderFaqItem($question, $answer) {
    return '<details class="faq-item"><summary>' . $question . '</summary><p>' . $answer . '</p></details>';
}

/**
 * FAQ sekce — odpovídá MG.renderFaqSection() v components.js.
 * ZMĚNA: moreLink bez # prefixu (čisté URL)
 */
function renderFaqSection($title, $items, $moreLink = null) {
    $html = '<section aria-labelledby="faq"><h2>' . $title . '</h2><div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
    foreach ($items as $faq) {
        $html .= renderFaqItem($faq['q'], $faq['a']);
    }
    $html .= '</div></div></div>';
    if ($moreLink) {
        $html .= '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $moreLink . '">Další často kladené otázky</a></p>';
    }
    $html .= '</section>';
    return $html;
}

/**
 * CTA sekce — odpovídá MG.renderCta() v components.js.
 * ZMĚNA: href bez # prefixu (čisté URL)
 */
function renderCta($title, $text, $buttons) {
    $html = '<section aria-labelledby="cta"><h2>' . $title . '</h2><p>' . $text . '</p><p>&nbsp;</p><p>';
    foreach ($buttons as $btn) {
        $cls = $btn['cls'] ?? 'btndark';
        $html .= '<a class="btn ' . $cls . '" href="' . BASE_URL . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
    }
    $html .= '</p></section>';
    return $html;
}

/**
 * Tabulka — odpovídá MG.renderTable() v components.js.
 */
function renderTable($headers, $rows) {
    $html = '<div class="table-responsive"><table class="table table-striped table-hover"><thead><tr>';
    foreach ($headers as $h) { $html .= '<th>' . $h . '</th>'; }
    $html .= '</tr></thead><tbody>';
    foreach ($rows as $row) {
        $html .= '<tr>';
        foreach ($row as $cell) { $html .= '<td>' . $cell . '</td>'; }
        $html .= '</tr>';
    }
    $html .= '</tbody></table></div>';
    return $html;
}

/**
 * Breadcrumb — odpovídá MG.renderBreadcrumb() v router.js.
 * ZMĚNA: href bez # prefixu (čisté URL)
 */
function renderBreadcrumb($items) {
    $html = '<nav class="breadcrumb" aria-label="breadcrumb"><ol>';
    foreach ($items as $item) {
        if (is_string($item)) {
            $html .= '<li>' . $item . '</li>';
        } else {
            $html .= '<li><a href="' . BASE_URL . $item['href'] . '">' . $item['label'] . '</a></li>';
        }
    }
    $html .= '</ol></nav>';
    return $html;
}
