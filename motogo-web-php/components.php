<?php
// ===== MotoGo24 Web PHP — Reusable Components =====
// IDENTICKÝ HTML výstup jako components.js

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';
require_once __DIR__ . '/supabase.php';

/**
 * Bezpečný render nadpisu (h1-h6) — neemittuje prázdné heading tagy ani
 * defaultní fallback pro běžného návštěvníka. Externí SEO checker hlásil
 * desítky 'Chybí text titulku' (prázdné <h2>/<h3>) na homepage, kde CMS
 * klíče nebyly vyplněné z Velínu — render šablona slepě vypsala
 * `<h2>{$cms['title']}</h2>` i pro prázdný řetězec.
 *
 * Pravidla:
 *   - Pokud je `$text` prázdný a `$fallback` prázdný → vrátí '' (žádný tag).
 *   - Pokud je `$text` prázdný a `$fallback` vyplněný → použije fallback.
 *   - V CMS admin režimu (cookie `mg_cms_admin=1`) se prázdný heading
 *     vyrenderuje s placeholderem 'Doplňte titulek' kvůli inline edit
 *     overlayi (admin musí vidět co má vyplnit).
 *
 * @param int    $level  1-6
 * @param string $text   Hlavní text (CMS hodnota nebo statický fallback)
 * @param array  $opts   ['id'=>..., 'class'=>..., 'cmsKey'=>'web.home.foo',
 *                        'fallback'=>'Default text', 'allowHtml'=>false]
 * @return string  HTML <hN ...>...</hN> nebo '' pokud prázdné a není admin
 */
function renderHeading($level, $text, $opts = []) {
    $level = max(1, min(6, (int)$level));
    $tag = 'h' . $level;
    $raw = is_string($text) ? trim(strip_tags($text)) : '';
    $isAdmin = !empty($_COOKIE['mg_cms_admin']);
    $fallback = isset($opts['fallback']) ? trim(strip_tags((string)$opts['fallback'])) : '';
    $cmsKey = $opts['cmsKey'] ?? '';
    $allowHtml = !empty($opts['allowHtml']);

    if ($raw === '' && $fallback !== '') {
        $text = $fallback;
        $raw = $fallback;
    }
    if ($raw === '' && !$isAdmin) {
        return '';
    }
    $attrs = '';
    if (!empty($opts['id']))    $attrs .= ' id="' . htmlspecialchars($opts['id']) . '"';
    if (!empty($opts['class'])) $attrs .= ' class="' . htmlspecialchars($opts['class']) . '"';
    if ($cmsKey !== '')         $attrs .= ' data-cms-key="' . htmlspecialchars($cmsKey) . '"';

    if ($raw === '' && $isAdmin) {
        return '<' . $tag . $attrs . ' data-cms-empty="1"><span style="opacity:.4;font-style:italic">[Doplňte titulek]</span></' . $tag . '>';
    }
    $body = $allowHtml ? sanitizeHtml((string)$text) : htmlspecialchars((string)$text);
    return '<' . $tag . $attrs . '>' . $body . '</' . $tag . '>';
}

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
    // SEO: nesemanticke <b>/<i>/<font> -> semanticke <strong>/<em>/span (zachovat obsah).
    // Tyto tagy generuje legacy execCommand('bold'/'italic'/'fontSize') v CMS editoru.
    $html = preg_replace('#<b(\s[^>]*)?>#i', '<strong>', $html);
    $html = preg_replace('#</b\s*>#i', '</strong>', $html);
    $html = preg_replace('#<i(\s[^>]*)?>#i', '<em>', $html);
    $html = preg_replace('#</i\s*>#i', '</em>', $html);
    $html = preg_replace('#<font\b[^>]*>#i', '<span>', $html);
    $html = preg_replace('#</font\s*>#i', '</span>', $html);
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
 * Vrátí URL na transformovaný obrázek přes Supabase Image Transformation
 * (vyžaduje Pro plán). Server zmenší + komprimuje + autodetekuje WebP/AVIF
 * z `Accept` hlavičky prohlížeče, takže místo 2-5 MB originálu pošle 50-200 kB.
 *
 * Pro absolutní URL (http(s)://, data:) vrátí původní src beze změny.
 * Pro relativní storage cesty přepne z `object/public/media/` na
 * `render/image/public/media/` s `width` a `quality` query paramy.
 *
 * @param string $src     Relativní storage cesta nebo absolutní URL.
 * @param int    $width   Cílová šířka v px (zachová se poměr stran).
 * @param int    $quality 1-100, default 75 (vizuálně shodné s 90 ale ~50% velikost).
 */
function imgUrlSized($src, $width, $quality = 75) {
    if (!$src) return '';
    if (strpos($src, 'data:') === 0) return $src;
    $w = max(1, (int)$width);
    $q = min(100, max(1, (int)$quality));
    $path = $src;
    // Pokud už je $src absolutní URL na Supabase storage `object/public/media/...`,
    // přepiš na transformační endpoint místo abychom vrátili neoptimalizovaný original.
    if (strpos($src, 'http://') === 0 || strpos($src, 'https://') === 0) {
        $marker = '/storage/v1/object/public/media/';
        $pos = strpos($src, $marker);
        if ($pos === false) {
            $marker = '/storage/v1/render/image/public/media/';
            $pos = strpos($src, $marker);
        }
        if ($pos === false) return $src; // cizí URL, nechceme rozbít
        // Vyříznout query (?token=...) a vzít čistou cestu
        $path = substr($src, $pos + strlen($marker));
        $qmark = strpos($path, '?');
        if ($qmark !== false) $path = substr($path, 0, $qmark);
    }
    return SUPABASE_URL . '/storage/v1/render/image/public/media/' . $path
        . '?width=' . $w . '&quality=' . $q . '&resize=contain';
}

/**
 * Build srcset value for responsive images. Generates sized URLs for the
 * given list of widths and joins them with their pixel descriptors.
 */
function imgSrcset($src, $widths, $quality = 75) {
    if (!$src) return '';
    $parts = [];
    foreach ($widths as $w) {
        $parts[] = imgUrlSized($src, $w, $quality) . ' ' . (int)$w . 'w';
    }
    return implode(', ', $parts);
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
        'manual_url','manual_external_url','color','year','power_kw','power_hp','torque_nm',
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
    $imgRaw = $m['image_url'] ?? ($m['images'][0] ?? '');
    // Karta — render přes Supabase Image Transformation: ~600 px WebP/AVIF místo 2-5 MB originálu.
    $img = $imgRaw ? imgUrlSized($imgRaw, 600) : '';
    $imgSrcset = $imgRaw ? imgSrcset($imgRaw, [400, 600, 900]) : '';
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
    // SEO: karty motorek jsou uvnitř <section> s vlastním <h2>, takze nazev
    // motorky je sub-heading -> <h3>. Externi SEO checker hlasil 'Benelli TRK
    // 502 X' jako h2, ktery konkuruje h2 sekce 'Nase motorky'. Hierarchia
    // h1 (page) > h2 (section) > h3 (card) je teď konzistentni.
    $featHtml .= '<li class="moto-card-model"><h3>' . $model . '</h3></li>';
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
            ($img ? '<img src="' . htmlspecialchars($img) . '"'
                . ($imgSrcset ? ' srcset="' . htmlspecialchars($imgSrcset) . '" sizes="(max-width: 768px) 100vw, 33vw"' : '')
                . ' alt="' . $imgAlt . '" class="imgres" loading="lazy" decoding="async">' : '') .
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
    $imgSrcset = '';
    $img = (!empty($images) ? $images[0] : '') ?: ($post['image_url'] ?? '');
    // Relativní lokální cesty: /gfx/... nebo gfx/...
    if ($img && strpos($img, 'http') !== 0 && strpos($img, 'data:') !== 0) {
        $img = BASE_URL . '/' . ltrim($img, '/');
    } elseif ($img) {
        // DB-uploaded blog images jdou přes Supabase storage → použij transformaci.
        $imgSrcset = imgSrcset($img, [400, 600, 900]);
        $img = imgUrlSized($img, 600);
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
        '<div class="blog-title"><h3>' . $title . '</h3></div>' .
        '<div class="blog-img">' . ($img ? '<img src="' . htmlspecialchars($img) . '"'
            . ($imgSrcset ? ' srcset="' . htmlspecialchars($imgSrcset) . '" sizes="(max-width: 768px) 100vw, 33vw"' : '')
            . ' alt="' . $imgAlt . '" class="imgres" loading="lazy" decoding="async">' : '') . '</div>' .
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
    $imgSrcset = '';
    if ($img && strpos($img, 'http') !== 0 && strpos($img, 'data:') !== 0 && strpos($img, '/') !== 0) {
        $imgSrcset = imgSrcset($img, [300, 600]);
        $img = imgUrlSized($img, 600);
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
        $stockBadge = '<span class="moto-card-badge moto-card-badge--soldout">' . te('shop.soldOut') . '</span>';
    }

    return '<a class="moto-wrapper" href="' . BASE_URL . '/eshop/' . $id . '" aria-label="' . $name . '">' .
        '<div class="moto-img">' .
            ($img ? '<img src="' . htmlspecialchars($img) . '"'
                . ($imgSrcset ? ' srcset="' . htmlspecialchars($imgSrcset) . '" sizes="(max-width: 768px) 50vw, 25vw"' : '')
                . ' alt="' . $imgAlt . '" class="imgres" loading="lazy" decoding="async">' : '') .
            $stockBadge .
            '<div class="moto-title"><h3>' . $name . '</h3></div>' .
        '</div>' .
        '<div class="moto-desc">' . ($shortDesc ? '<p>' . htmlspecialchars($shortDesc) . '</p>' : '') . ($priceText ? '<p class="moto-price">' . htmlspecialchars($priceText) . '</p>' : '') . '</div>' .
        '<div class="moto-btn"><span class="btn btngreen-small">' . te('shop.detailButton') . '</span></div>' .
    '</a>';
}

/**
 * Ikona box — odpovídá MG.renderWbox() v components.js.
 *
 * Ikona je sice dekorativní (význam přenáší <h3> + <p>), ale prázdný alt=""
 * SEO crawlery hlásí jako "missing alt". Generujeme proto alt z titulku boxu
 * (po strip_tags), zatímco aria-hidden=true ponechá ikonu skrytou pro screen
 * readery — uživatelé asistivních technologií tak neslyší titulek dvakrát.
 */
function renderWbox($icon, $title, $text) {
    $iconSrc = $icon ? BASE_URL . '/' . ltrim($icon, '/') : '';
    $iconAlt = trim(strip_tags((string)$title));
    return '<div class="wbox">' .
        ($icon ? '<div class="wbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . htmlspecialchars($iconAlt) . '" aria-hidden="true" loading="lazy"></div>' : '') .
        '<h3>' . sanitizeHtml($title) . '</h3>' .
        '<p>' . sanitizeHtml($text) . '</p></div>';
}

/**
 * FAQ accordion item — odpovídá MG.renderFaqItem() v components.js.
 */
function renderFaqItem($question, $answer) {
    return '<details class="faq-item"><summary>' . sanitizeHtml($question) . '</summary><p>' . sanitizeHtml($answer) . '</p></details>';
}

/**
 * FAQ sekce — odpovídá MG.renderFaqSection() v components.js.
 * ZMĚNA: moreLink bez # prefixu (čisté URL)
 */
function renderFaqSection($title, $items, $moreLink = null) {
    // SEO: pouzij renderHeading aby prazdny FAQ titulek nedostal prazdny <h2>.
    // $title muze byt string nebo HTML span s data-cms-key wrapem - zachovame
    // raw rendering, jen guardneme prazdny pripad.
    $rawTitle = trim(strip_tags(is_string($title) ? $title : ''));
    if ($rawTitle === '' && empty($_COOKIE['mg_cms_admin'])) {
        $title = 'Často kladené otázky';
    }
    $html = '<section aria-labelledby="faq"><h2 id="faq">' . $title . '</h2><div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
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
    // SEO: prazdny CTA titulek -> fallback (pri admin rezimu placeholder, jinak skrytý h2 bohuzel zlomi structure;
    // takze pouzijeme nestranny default).
    $rawTitle = trim(strip_tags(is_string($title) ? $title : ''));
    if ($rawTitle === '' && empty($_COOKIE['mg_cms_admin'])) {
        $title = 'Rezervujte si motorku';
    }
    $html = '<section aria-labelledby="cta"><h2 id="cta">' . sanitizeHtml($title) . '</h2><p>' . sanitizeHtml($text) . '</p><p>&nbsp;</p><p>';
    foreach ($buttons as $btn) {
        $cls = $btn['cls'] ?? 'btndark';
        $html .= '<a class="btn ' . $cls . '" href="' . BASE_URL . $btn['href'] . '">' . sanitizeHtml($btn['label']) . '</a>&nbsp;';
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
