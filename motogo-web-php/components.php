<?php
// ===== MotoGo24 Web PHP — Reusable Components =====
// IDENTICKÝ HTML výstup jako components.js

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
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
 * Bezpečný cast na string. Pokud hodnota je array/object, vrátí ''.
 * Účel: chránit `htmlspecialchars()` před fatal TypeError v PHP 8 — ten hází
 * chybu, když dostane non-string. Velín / admin může nechtěně uložit pole nebo
 * objekt místo stringu, což by ji dříve crashlo (500). Teď se prostě vrátí
 * prázdný řetězec.
 */
function safeStr($v) {
    if (is_string($v)) return $v;
    if (is_numeric($v)) return (string)$v;
    if (is_bool($v)) return $v ? '1' : '';
    return '';
}

/**
 * `htmlspecialchars` s fail-safe — pokud vstup není string, escape prázdný.
 * Náhrada za `htmlspecialchars($x)` na místech, kde $x může být malformovaná
 * hodnota z DB / CMS (např. pole motorky uložené přes Velín jako array).
 */
function he($v) {
    return htmlspecialchars(safeStr($v), ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

/**
 * Normalizuje řádek motorky — všechny scalar fields přetypuje na string,
 * arrays nechá arrays, malformované hodnoty na bezpečné defaulty. Volá se
 * po fetchMotos() / katalog-detail před renderem, aby se eliminovaly TypeError
 * z `htmlspecialchars()` na neočekávané typy.
 */
function normalizeMoto(&$m) {
    if (!is_array($m)) return;
    $stringFields = [
        'id','model','brand','description','category','engine_cc','engine_type',
        'transmission','drivetrain','fuel_consumption_l100km','ideal_usage',
        'manual_url','color','year','power_kw','power_hp','torque_nm',
        'top_speed_kmh','fuel_type','fuel_tank_l','brake_type','weight_kg',
        'seat_height_mm','seats_count','license_required','min_rental_days',
        'max_rental_days','image_url','status','suitable_for',
        'price_min','price_mon','price_tue','price_wed','price_thu',
        'price_fri','price_sat','price_sun','price_weekday','price_weekend',
    ];
    foreach ($stringFields as $f) {
        if (!isset($m[$f])) continue;
        if (is_array($m[$f]) || is_object($m[$f])) $m[$f] = '';
    }
    // features je legit string nebo array — pouze zahodíme objekt
    if (isset($m['features']) && is_object($m['features'])) $m['features'] = '';
    // Pokud features array obsahuje non-skalární prvky, převést na strings
    if (is_array($m['features'] ?? null)) {
        $m['features'] = array_values(array_filter(array_map(function ($x) {
            return safeStr($x);
        }, $m['features']), function ($s) { return $s !== ''; }));
    }
    if (!is_array($m['images'] ?? null)) $m['images'] = [];
    // Image entries musí být strings (URL nebo storage path)
    $m['images'] = array_values(array_filter(array_map(function ($x) {
        return safeStr($x);
    }, $m['images']), function ($s) { return $s !== ''; }));
    // branches je joined object s name/address/city — pokud není array, nechť je null
    if (isset($m['branches']) && !is_array($m['branches'])) $m['branches'] = null;
    // translations je jsonb — pokud není array, vyhoď
    if (isset($m['translations']) && !is_array($m['translations'])) {
        $decoded = is_string($m['translations']) ? json_decode($m['translations'], true) : null;
        $m['translations'] = is_array($decoded) ? $decoded : [];
    }
}

/**
 * HTML karta motorky — odpovídá MG.renderMotoCard() v components.js.
 * ZMĚNA: href z #/katalog/{id} na /katalog/{id}
 */
function renderMotoCard($m) {
    if (!is_array($m)) return '';
    normalizeMoto($m);
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

    $priceText = $price > 0 ? t('card.priceFromPerDay', ['price' => formatPrice($price)]) : '';
    $modelRaw = trim((string)($m['model'] ?? ''));
    if ($modelRaw === '') $modelRaw = t('card.unnamedMotorcycle');
    $model = htmlspecialchars($modelRaw);
    $id = htmlspecialchars($m['id'] ?? '');
    $imgAlt = htmlspecialchars(t('common.motorcycleAlt', ['model' => $modelRaw]));

    $featHtml = '<ul>';
    $featHtml .= '<li class="moto-card-model"><h2>' . $model . '</h2></li>';
    foreach ($features as $f) { $featHtml .= '<li>' . $f . '</li>'; }
    $featHtml .= '</ul>';

    // Branch info (pokud tabulka motorcycles byla joinnutá s branches)
    $branch = $m['branches'] ?? null;
    $branchLine = '';
    if (is_array($branch) && !empty($branch['name'])) {
        $branchLine = '<p class="moto-branch-line"><span aria-hidden="true">📍</span> ' . htmlspecialchars($branch['name']) . '</p>';
    }

    // Available badge — "Dostupné dnes" pokud je motorka volná dnes,
    // jinak "Dostupné od DD.MM.YYYY" podle nejbližšího volného data z RPC.
    $badge = '';
    if (($m['status'] ?? '') === 'active') {
        $today = date('Y-m-d');
        $nextAvail = $m['next_available_date'] ?? null;
        if ($nextAvail && $nextAvail > $today) {
            $dateFmt = date('d.m.Y', strtotime($nextAvail));
            $badge = '<span class="moto-card-badge">' . te('card.availableFrom', ['date' => $dateFmt]) . '</span>';
        } else {
            $badge = '<span class="moto-card-badge">' . te('card.availableToday') . '</span>';
        }
    }

    return '<a class="moto-wrapper" href="' . BASE_URL . '/katalog/' . $id . '" aria-label="' . $model . '">' .
        '<div class="moto-img">' .
            ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $imgAlt . '" class="imgres" loading="lazy">' : '') .
            ($badge ? $badge : '') .
        '</div>' .
        '<div class="moto-desc">' . $featHtml . $branchLine . ($priceText ? '<p class="moto-price">' . $priceText . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">' . te('card.detailButton') . '</span></div>' .
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
    // Auto-překlady z `translations` JSONB sloupce s CZ fallbackem
    $excerpt = localized($post, 'excerpt');
    if ($excerpt === '') $excerpt = $post['description'] ?? '';
    $titleRaw = trim((string)localized($post, 'title'));
    if ($titleRaw === '') $titleRaw = t('card.unnamedArticle');
    $title = htmlspecialchars($titleRaw);
    $slug = htmlspecialchars($post['slug'] ?? '');
    $imgAlt = htmlspecialchars(t('common.blogAlt', ['title' => $titleRaw]));

    return '<div><a class="blog-wrapper" href="' . BASE_URL . '/blog/' . $slug . '" aria-label="' . $title . '">' .
        '<div class="blog-title"><h2>' . $title . '</h2></div>' .
        '<div class="blog-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $imgAlt . '" class="imgres" loading="lazy">' : '') . '</div>' .
        '<div class="blog-desc">' . ($tag ? '<p><span class="tag-label">' . htmlspecialchars($tag) . '</span></p>' : '') . '<p>' . htmlspecialchars($excerpt) . '</p></div>' .
        '<div class="blog-btn"><span class="btn btngreen-small">' . te('card.readArticle') . '</span></div>' .
    '</a></div>';
}

/**
 * HTML karta produktu (e-shop).
 * Kompatibilní stylem s renderMotoCard / renderBlogCard.
 * Auto-překlad name + (volitelně) description z `translations` JSONB sloupce.
 */
function renderProductCard($p) {
    $images = $p['images'] ?? [];
    $img = (!empty($images) ? $images[0] : '') ?: ($p['image_url'] ?? '');
    if ($img && strpos($img, 'http') !== 0 && strpos($img, 'data:') !== 0 && strpos($img, '/') !== 0) {
        $img = imgUrl($img);
    } elseif ($img && strpos($img, '/') === 0 && strpos($img, '//') !== 0) {
        $img = BASE_URL . $img;
    }
    $nameRaw = trim((string)localized($p, 'name'));
    if ($nameRaw === '') $nameRaw = t('shop.unnamedProduct');
    $name = htmlspecialchars($nameRaw);
    $price = isset($p['price']) ? (float)$p['price'] : 0;
    $priceText = $price > 0 ? formatPrice($price) : '';
    $id = htmlspecialchars($p['id'] ?? '');
    $imgAlt = htmlspecialchars(t('shop.productAlt', ['name' => $nameRaw]));

    // Krátký popisek (z description, max 120 znaků)
    $descRaw = trim((string)localized($p, 'description'));
    $shortDesc = '';
    if ($descRaw !== '') {
        $stripped = trim(strip_tags($descRaw));
        $shortDesc = mb_strlen($stripped) > 120 ? mb_substr($stripped, 0, 117) . '…' : $stripped;
    }

    $stock = (int)($p['stock_quantity'] ?? 0);
    $stockBadge = '';
    if ($stock <= 0) {
        $stockBadge = '<span class="moto-card-badge" style="background:#fee2e2;color:#dc2626;">' . te('shop.soldOut') . '</span>';
    }

    return '<a class="moto-wrapper" href="' . BASE_URL . '/eshop/' . $id . '" aria-label="' . $name . '">' .
        '<div class="moto-img">' .
            ($img ? '<img src="' . htmlspecialchars($img) . '" alt="' . $imgAlt . '" class="imgres" loading="lazy">' : '') .
            $stockBadge .
            '<div class="moto-title"><h2>' . $name . '</h2></div>' .
        '</div>' .
        '<div class="moto-desc">' . ($shortDesc ? '<p>' . htmlspecialchars($shortDesc) . '</p>' : '') . ($priceText ? '<p class="moto-price">' . htmlspecialchars($priceText) . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">' . te('shop.detailButton') . '</span></div>' .
    '</a>';
}

/**
 * Ikona box — odpovídá MG.renderWbox() v components.js.
 */
function renderWbox($icon, $title, $text) {
    $iconSrc = $icon ? BASE_URL . '/' . ltrim($icon, '/') : '';
    return '<div class="wbox">' .
        ($icon ? '<div class="wbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="" aria-hidden="true" loading="lazy"></div>' : '') .
        '<h3>' . $title . '</h3>' .
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
        $html .= '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $moreLink . '">' . te('common.moreFaq') . '</a></p>';
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
