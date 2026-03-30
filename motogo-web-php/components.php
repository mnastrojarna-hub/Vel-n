<?php
// ===== MotoGo24 Web PHP — Reusable Components =====
// IDENTICKÝ HTML výstup jako components.js

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/supabase.php';

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

    return '<a class="moto-wrapper" href="' . BASE_URL . '/katalog/' . $id . '" aria-label="' . $model . '">' .
        '<div class="moto-title"><h2>' . $model . '</h2></div>' .
        '<div class="moto-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $model . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="moto-desc">' . $featHtml . ($priceText ? '<p class="moto-price">' . $priceText . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">DETAIL MOTORKY</span></div>' .
    '</a>';
}

/**
 * HTML karta blogu — odpovídá MG.renderBlogCard() v components.js.
 * ZMĚNA: href z #/blog/{slug} na /blog/{slug}
 */
function renderBlogCard($post) {
    $images = $post['images'] ?? [];
    $img = (!empty($images) ? $images[0] : '') ?: ($post['image_url'] ?? '');
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
    return '<div class="wbox">' .
        ($icon ? '<div class="wbox-img"><img src="' . htmlspecialchars($icon) . '" class="icon" alt="' . strip_tags($title) . '" loading="lazy"></div>' : '') .
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
