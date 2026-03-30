<?php
// ===== MotoGo24 Web PHP — Reusable Components =====

function renderMotoCard($m) {
    $img = imgUrl($m['image_url'] ?? ($m['images'][0] ?? ''));
    $desc = $m['ideal_usage'] ?? '';
    $cat = $m['category'] ?? '';
    $kw = !empty($m['power_kw']) ? ($m['power_kw'] . ' kW') : '';
    $price = getMinPrice($m);
    $license = $m['license_required'] ?? '';
    $model = e($m['model'] ?? '');
    $id = e($m['id'] ?? '');

    $features = [];
    if ($cat) $features[] = e($cat);
    if ($license && $license !== 'N') $features[] = e($license);
    if ($kw) $features[] = e($kw);
    if ($desc && is_string($desc)) {
        foreach (explode(',', $desc) as $f) {
            $t = trim($f);
            if ($t && count($features) < 6) $features[] = e($t);
        }
    } elseif (is_array($desc)) {
        foreach ($desc as $f) {
            $t = is_string($f) ? trim($f) : (string)$f;
            if ($t && count($features) < 6) $features[] = e($t);
        }
    }

    $featHtml = '<ul>';
    foreach ($features as $f) $featHtml .= '<li>' . $f . '</li>';
    $featHtml .= '</ul>';

    $priceText = $price > 0 ? ('Cena: od ' . formatPrice($price) . '/den') : '';

    return '<a class="moto-wrapper" href="/katalog/' . $id . '" aria-label="' . $model . '">' .
        '<div class="moto-title"><h2>' . $model . '</h2></div>' .
        '<div class="moto-img">' . ($img ? '<img src="' . e($img) . '" alt="' . $model . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="moto-desc">' . $featHtml . ($priceText ? '<p class="moto-price">' . $priceText . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">DETAIL MOTORKY</span></div>' .
    '</a>';
}

function renderBlogCard($post) {
    $img = ($post['images'][0] ?? '') ?: ($post['image_url'] ?? '');
    $tag = $post['tags'][0] ?? '';
    $excerpt = e($post['excerpt'] ?? $post['description'] ?? '');
    $title = e($post['title'] ?? '');
    $slug = e($post['slug'] ?? '');

    return '<div><a class="blog-wrapper" href="/blog/' . $slug . '" aria-label="' . $title . '">' .
        '<div class="blog-title"><h2>' . $title . '</h2></div>' .
        '<div class="blog-img">' . ($img ? '<img src="' . e($img) . '" alt="' . $title . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="blog-desc">' . ($tag ? '<p><span class="tag-label">' . e($tag) . '</span></p>' : '') . '<p>' . $excerpt . '</p></div>' .
        '<div class="blog-btn"><span class="btn btngreen-small">PŘEČÍST ČLÁNEK</span></div>' .
    '</a></div>';
}

function renderWbox($icon, $title, $text) {
    return '<div class="wbox">' .
        ($icon ? '<div class="wbox-img"><img src="' . e($icon) . '" class="icon" alt="' . strip_tags($title) . '" loading="lazy"></div>' : '') .
        '<h3><p>' . $title . '</p></h3>' .
        '<p>' . $text . '</p></div>';
}

function renderFaqItem($question, $answer) {
    return '<details class="faq-item"><summary>' . $question . '</summary><p>' . $answer . '</p></details>';
}

function renderFaqSection($title, $items, $moreLink = null) {
    $html = '<section aria-labelledby="faq"><h2>' . $title . '</h2><div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
    foreach ($items as $faq) {
        $html .= renderFaqItem($faq['q'], $faq['a']);
    }
    $html .= '</div></div></div>';
    if ($moreLink) {
        $html .= '<p>&nbsp;</p><p><a class="btn btngreen" href="' . $moreLink . '">Další často kladené otázky</a></p>';
    }
    $html .= '</section>';
    return $html;
}

function renderCta($title, $text, $buttons) {
    $html = '<section aria-labelledby="cta"><h2>' . $title . '</h2><p>' . $text . '</p><p>&nbsp;</p><p>';
    foreach ($buttons as $btn) {
        $cls = $btn['cls'] ?? 'btndark';
        $html .= '<a class="btn ' . $cls . '" href="' . $btn['href'] . '">' . $btn['label'] . '</a>&nbsp;';
    }
    $html .= '</p></section>';
    return $html;
}

function renderTable($headers, $rows) {
    $html = '<div class="table-responsive"><table class="table table-striped table-hover"><thead><tr>';
    foreach ($headers as $h) $html .= '<th>' . $h . '</th>';
    $html .= '</tr></thead><tbody>';
    foreach ($rows as $row) {
        $html .= '<tr>';
        foreach ($row as $cell) $html .= '<td>' . $cell . '</td>';
        $html .= '</tr>';
    }
    $html .= '</tbody></table></div>';
    return $html;
}

function renderBreadcrumb($items) {
    $html = '<nav class="breadcrumb" aria-label="breadcrumb"><ol>';
    foreach ($items as $item) {
        if (is_string($item)) {
            $html .= '<li>' . $item . '</li>';
        } else {
            $html .= '<li><a href="' . $item['href'] . '">' . $item['label'] . '</a></li>';
        }
    }
    $html .= '</ol></nav>';
    return $html;
}
