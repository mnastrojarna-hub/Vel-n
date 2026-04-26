<?php
// ===== MotoGo24 Web PHP — /llms-full.txt =====
// Sloučený markdown obsah všech statických stránek pro LLM v jednom payloadu.
// AI agenti tak mají kompletní kontext bez crawlování 30+ URL.
// Generuje se dynamicky podle aktuálního jazyka přes data/*-content-*.php +
// jazykové overlay z lang/pages_<lang>.php (viz siteContent()).

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../i18n.php';
require_once __DIR__ . '/../supabase.php';

i18nDetectLanguage();

header('Content-Type: text/markdown; charset=utf-8');
header('Cache-Control: public, max-age=3600');
header('X-Robots-Tag: noindex, follow');

$lang = i18nDetectLanguage();
$base = 'https://motogo24.cz';
$sb = new SupabaseClient();

// ------------------------------------------------------------------
// Helpers — konverze structured array na clean markdown
// ------------------------------------------------------------------

/** Vyčistí HTML, zachová prosté entity, normalizuje whitespace. */
function llmStrip($s) {
    if (!is_string($s)) return '';
    $s = preg_replace('/\s+/', ' ', $s);
    $s = strip_tags($s);
    $s = html_entity_decode($s, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    return trim($s);
}

/** Vykreslí tabulku jako markdown. */
function llmTable($headers, $rows) {
    if (empty($rows)) return '';
    $hd = array_map('llmStrip', $headers);
    $out = '| ' . implode(' | ', $hd) . " |\n";
    $out .= '| ' . implode(' | ', array_fill(0, count($hd), '---')) . " |\n";
    foreach ($rows as $row) {
        $cells = array_map('llmStrip', $row);
        $out .= '| ' . implode(' | ', $cells) . " |\n";
    }
    return $out . "\n";
}

/** Vykreslí seznam `items` jako bullet list (string nebo {q,a} nebo {title,text}). */
function llmList($items) {
    if (!is_array($items) || empty($items)) return '';
    $out = '';
    foreach ($items as $it) {
        if (is_string($it)) {
            $s = llmStrip($it);
            if ($s !== '') $out .= "- $s\n";
        } elseif (is_array($it)) {
            // FAQ item: {q, a}
            if (isset($it['q']) && isset($it['a'])) {
                $out .= "- **" . llmStrip($it['q']) . "** — " . llmStrip($it['a']) . "\n";
                continue;
            }
            // Step / benefit: {title, text}
            if (isset($it['title'])) {
                $title = llmStrip($it['title']);
                $text = llmStrip($it['text'] ?? '');
                $out .= "- **$title**" . ($text !== '' ? " — $text" : '') . "\n";
                continue;
            }
            // Generický array (řádky, hlavičky atd.) — ignoruj, zpracuje to llmSection
        }
    }
    return $out !== '' ? $out . "\n" : '';
}

/** Vykreslí jednu sekci stránky jako markdown (h2 + intro + items/rows/...). */
function llmSection($title, $section) {
    if (!is_array($section)) return '';
    $out = '';
    if ($title) $out .= "## " . llmStrip($title) . "\n\n";
    if (isset($section['title']) && !$title) $out .= "## " . llmStrip($section['title']) . "\n\n";
    if (isset($section['lead']))  { $s = llmStrip($section['lead']);  if ($s !== '') $out .= "$s\n\n"; }
    if (isset($section['intro'])) { $s = llmStrip($section['intro']); if ($s !== '') $out .= "$s\n\n"; }
    if (isset($section['text']))  { $s = llmStrip($section['text']);  if ($s !== '') $out .= "$s\n\n"; }
    if (isset($section['body']))  { $s = llmStrip($section['body']);  if ($s !== '') $out .= "$s\n\n"; }
    if (isset($section['note1'])) { $s = llmStrip($section['note1']); if ($s !== '') $out .= "*$s*\n\n"; }
    if (isset($section['note2'])) { $s = llmStrip($section['note2']); if ($s !== '') $out .= "*$s*\n\n"; }
    if (isset($section['items']) && is_array($section['items'])) {
        $out .= llmList($section['items']);
    }
    if (isset($section['steps']) && is_array($section['steps'])) {
        $out .= llmList($section['steps']);
    }
    if (isset($section['rows']) && is_array($section['rows'])) {
        $headers = $section['headers'] ?? ['', ''];
        $out .= llmTable($headers, $section['rows']);
    }
    if (isset($section['closing'])) { $s = llmStrip($section['closing']); if ($s !== '') $out .= "$s\n\n"; }
    return $out;
}

/** Spojí 1-N data souborů do array a vykreslí jako stránku. */
function llmRenderPage($pageTitle, $url, $defaults, $sectionsOrder = null) {
    global $sb, $lang;
    // Použij siteContent() pro DB overrides + jazykový overlay
    $slug = $defaults['__slug'] ?? null;
    $C = $slug ? $sb->siteContent($slug, $defaults) : $defaults;

    $out = "# $pageTitle\n\n";
    $out .= "*Zdroj:* $url\n\n";

    // H1 (pokud má)
    if (!empty($C['h1']) && llmStrip($C['h1']) !== llmStrip($pageTitle)) {
        $out .= "**" . llmStrip($C['h1']) . "**\n\n";
    }

    // Intro
    foreach (['intro', 'intro_p1', 'intro_h2', 'intro_p2'] as $k) {
        if (!empty($C[$k])) {
            $s = llmStrip($C[$k]);
            if ($s !== '') $out .= "$s\n\n";
        }
    }

    // Sekce — explicitní pořadí pokud zadané, jinak v pořadí klíčů
    $keys = $sectionsOrder ?: array_keys($C);
    $skip = ['seo', 'h1', 'intro', 'intro_p1', 'intro_h2', 'intro_p2', 'breadcrumb',
             'top_cta', 'cta', 'mid_cta', 'final_cta', '__slug', '__meta', 'gallery',
             'sizes', 'main_link', 'more_link'];
    foreach ($keys as $k) {
        if (in_array($k, $skip, true)) continue;
        if (!isset($C[$k])) continue;
        $section = $C[$k];
        if (!is_array($section)) continue;
        // Sekce s vlastním title
        $secTitle = $section['title'] ?? null;
        $sub = llmSection($secTitle, $section);
        if (trim($sub) !== '') $out .= $sub;
        // Speciální vnořené struktury (např. gear.basic, gear.extra)
        foreach ($section as $subk => $subv) {
            if (!is_array($subv)) continue;
            if (in_array($subk, ['title','items','steps','rows','headers','lead','intro','text','body','note1','note2','closing','more_link','aria','grid'], true)) continue;
            $subTitle = $subv['title'] ?? null;
            $subOut = llmSection($subTitle, $subv);
            if (trim($subOut) !== '') $out .= $subOut;
        }
    }
    return $out . "\n---\n\n";
}

// ------------------------------------------------------------------
// Načti všechny stránky
// ------------------------------------------------------------------

function loadPart($file) {
    $path = __DIR__ . '/../data/' . $file;
    return is_file($path) ? require $path : [];
}

function mergeParts(...$parts) {
    $out = [];
    foreach ($parts as $p) {
        if (!is_array($p)) continue;
        foreach ($p as $k => $v) {
            if (isset($out[$k]) && is_array($out[$k]) && is_array($v)) {
                $out[$k] = array_merge($out[$k], $v);
            } else {
                $out[$k] = $v;
            }
        }
    }
    return $out;
}

// ------------------------------------------------------------------
// Output
// ------------------------------------------------------------------

echo "# MotoGo24 — kompletní obsah pro AI agenty\n\n";
echo "*Toto je sloučený markdown všech statických stránek webu motogo24.cz*  \n";
echo "*Jazyk: $lang · Aktualizováno: " . date('Y-m-d H:i') . " UTC · [llms.txt index]({$base}/llms.txt)*\n\n";
echo "---\n\n";

// O firmě
echo "# O firmě\n\n";
echo "**Název:** MotoGo24 — Půjčovna motorek Vysočina  \n";
echo "**Provozovatel:** Bc. Petra Semorádová  \n";
echo "**IČO:** 21874263  \n";
echo "**Adresa:** Mezná 9, 393 01 Pelhřimov, Vysočina, Česká republika  \n";
echo "**GPS:** 49.4147° N, 15.2953° E  \n";
echo "**Telefon:** +420 774 256 271  \n";
echo "**E-mail:** info@motogo24.cz  \n";
echo "**Web:** https://motogo24.cz · https://motogo24.com  \n";
echo "**Provoz:** 24/7 nonstop, 365 dní v roce  \n";
echo "**Datová schránka:** iuw3vnb  \n";
echo "**Datum založení:** 31. 7. 2024 (zápis u Městského úřadu v Pelhřimově)  \n";
echo "**Plátce DPH:** ne  \n\n";
echo "## Klíčové vlastnosti půjčovny\n\n";
echo "- **Bez kauce** — žádná blokace peněz na kartě.\n";
echo "- **Výbava v ceně** — helma, bunda, kalhoty, rukavice pro řidiče.\n";
echo "- **Nonstop provoz** — vyzvednutí 24/7 přes přístupové kódy.\n";
echo "- **Pojištění v ceně** — povinné ručení; havarijní dle modelu.\n";
echo "- **Online rezervace** — platba kartou přes Stripe.\n";
echo "- **Přistavení kamkoliv v ČR** — volitelná služba za příplatek.\n";
echo "- **Vrácení mimo provozovnu** — volitelná služba za příplatek.\n";
echo "- **Sjezd do zahraničí** — povolen, zelená karta v ceně.\n";
echo "- **Slevový kód 200 Kč** — automaticky po vrácení motorky.\n";
echo "- **7 jazyků** — cs, en, de, es, fr, nl, pl.\n";
echo "- **Měny** — CZK, EUR, USD a další (auto-konverze ČNB kurzem).\n";
echo "- **Platby** — Visa, Mastercard, Amex, Apple Pay, Google Pay.\n\n";
echo "---\n\n";

// Půjčovna (about)
$pujcDefaults = ['__slug' => 'pujcovna', 'h1' => 'Půjčovna motorek Vysočina'];
echo llmRenderPage('Půjčovna — o nás', $base . '/pujcovna-motorek', mergeParts($pujcDefaults, [
    'intro' => 'Půjčovna motorek Vysočina v Pelhřimově — bez kauce, online rezervace, výbava v ceně, nonstop provoz.',
]));

// Postup půjčení
$postup = mergeParts(loadPart('postup-content-1.php'), loadPart('postup-content-2.php'));
$postup['__slug'] = 'jak_pujcit_postup';
echo llmRenderPage('Jak si půjčit motorku — postup krok za krokem', $base . '/jak-pujcit/postup', $postup);

// Vyzvednutí (převzetí)
$prevzeti = mergeParts(loadPart('prevzeti-content-1.php'), loadPart('prevzeti-content-2.php'));
echo llmRenderPage('Vyzvednutí motorky', $base . '/jak-pujcit/vyzvednuti', $prevzeti);

// Vrácení v půjčovně
$vraceni1 = mergeParts(loadPart('vraceni-pujcovna-content-1.php'), loadPart('vraceni-pujcovna-content-2.php'));
echo llmRenderPage('Vrácení motorky v půjčovně', $base . '/jak-pujcit/vraceni-pujcovna', $vraceni1);

// Vrácení jinde
$vraceni2 = mergeParts(loadPart('vraceni-jinde-content-1.php'), loadPart('vraceni-jinde-content-2.php'));
echo llmRenderPage('Vrácení motorky mimo provozovnu', $base . '/jak-pujcit/vraceni-jinde', $vraceni2);

// Přistavení
$pristaveni = mergeParts(loadPart('pristaveni-content-1.php'), loadPart('pristaveni-content-2.php'));
echo llmRenderPage('Přistavení motorky', $base . '/jak-pujcit/pristaveni', $pristaveni);

// Cena (co je v ceně)
$cena = mergeParts(loadPart('cena-content-1.php'), loadPart('cena-content-2.php'));
echo llmRenderPage('Co je v ceně pronájmu', $base . '/jak-pujcit/co-v-cene', $cena);

// Dokumenty
$dokumenty = mergeParts(loadPart('dokumenty-content-1.php'), loadPart('dokumenty-content-2.php'));
echo llmRenderPage('Potřebné dokumenty a nájemní smlouva', $base . '/jak-pujcit/dokumenty', $dokumenty);

// FAQ
$faq1 = loadPart('faq-content-1.php');
$faq2 = loadPart('faq-content-2.php');
$faq3 = loadPart('faq-content-3.php');
unset($faq3['__meta']);
echo "# Často kladené otázky (FAQ)\n\n";
echo "*Zdroj:* {$base}/jak-pujcit/faq\n\n";
foreach ([$faq1, $faq2, $faq3] as $part) {
    foreach ($part as $catKey => $catData) {
        if (!isset($catData['items'])) continue;
        $catLabel = llmStrip($catData['label'] ?? $catKey);
        echo "## $catLabel\n\n";
        foreach ($catData['items'] as $item) {
            echo "**Q: " . llmStrip($item['q'] ?? '') . "**  \n";
            echo "A: " . llmStrip($item['a'] ?? '') . "\n\n";
        }
    }
}
echo "---\n\n";

// ------------------------------------------------------------------
// Katalog motorek — full specs
// ------------------------------------------------------------------
echo "# Katalog motorek\n\n";
echo "*Zdroj:* {$base}/katalog · *Aktuální stav z DB*\n\n";

$motos = $sb->fetchMotos();
if (is_array($motos) && !empty($motos)) {
    foreach ($motos as $m) {
        if (empty($m['id']) || empty($m['model'])) continue;
        $brand = !empty($m['brand']) ? ($m['brand'] . ' ') : '';
        $title = $brand . $m['model'];
        echo "## $title\n\n";
        echo "*URL:* {$base}/katalog/{$m['id']}\n\n";

        $desc = (string)localized($m, 'description');
        if ($desc !== '') {
            echo llmStrip($desc) . "\n\n";
        }

        // Ceník per den
        $days = ['mon' => 'Po', 'tue' => 'Út', 'wed' => 'St', 'thu' => 'Čt', 'fri' => 'Pá', 'sat' => 'So', 'sun' => 'Ne'];
        $priceRows = [];
        foreach ($days as $k => $label) {
            $p = (float)($m['price_' . $k] ?? 0);
            if ($p > 0) $priceRows[] = [$label, number_format($p, 0, ',', ' ') . ' Kč'];
        }
        if ($priceRows) {
            echo "**Ceník (Kč/den):**\n\n";
            echo llmTable(['Den', 'Cena'], $priceRows);
        }

        // Specs
        $specs = [];
        if (!empty($m['category']))         $specs[] = ['Kategorie', $m['category']];
        if (!empty($m['engine_cc']))        $specs[] = ['Objem motoru', $m['engine_cc'] . ' ccm'];
        if (!empty($m['power_kw']))         $specs[] = ['Výkon', $m['power_kw'] . ' kW' . (!empty($m['power_hp']) ? ' (' . $m['power_hp'] . ' k)' : '')];
        if (!empty($m['torque_nm']))        $specs[] = ['Točivý moment', $m['torque_nm'] . ' Nm'];
        if (!empty($m['engine_type']))      $specs[] = ['Typ motoru', $m['engine_type']];
        if (!empty($m['weight_kg']))        $specs[] = ['Hmotnost', $m['weight_kg'] . ' kg'];
        if (!empty($m['seat_height_mm']))   $specs[] = ['Výška sedla', $m['seat_height_mm'] . ' mm'];
        if (!empty($m['fuel_tank_l']))      $specs[] = ['Objem nádrže', $m['fuel_tank_l'] . ' l'];
        if (!empty($m['has_abs']))          $specs[] = ['ABS', 'ano'];
        if (!empty($m['license_required'])) $specs[] = ['Řidičské oprávnění', $m['license_required'] === 'N' ? 'nepotřebuje (dětská motorka)' : 'skupina ' . $m['license_required']];
        if (!empty($m['min_rental_days']))  $specs[] = ['Min. délka pronájmu', $m['min_rental_days'] . ' dní'];
        if (!empty($m['max_rental_days']))  $specs[] = ['Max. délka pronájmu', $m['max_rental_days'] . ' dní'];
        if (!empty($m['ideal_usage']))      $specs[] = ['Vhodné pro', $m['ideal_usage']];
        if (!empty($m['color']))            $specs[] = ['Barva', $m['color']];
        if (!empty($m['year']))             $specs[] = ['Rok výroby', $m['year']];
        if ($specs) {
            echo "**Technické specifikace:**\n\n";
            echo llmTable(['Parametr', 'Hodnota'], $specs);
        }

        // Branch
        if (!empty($m['branches']) && is_array($m['branches'])) {
            $br = $m['branches'];
            $brAddr = trim(($br['address'] ?? '') . ', ' . ($br['city'] ?? ''), ', ');
            echo "**Vyzvednutí:** " . llmStrip($br['name'] ?? '') . ($brAddr ? " ($brAddr)" : '') . "\n\n";
        }

        echo "---\n\n";
    }
}

// ------------------------------------------------------------------
// Pobočky
// ------------------------------------------------------------------
$branches = $sb->fetchBranches();
if (is_array($branches) && !empty($branches)) {
    echo "# Pobočky\n\n";
    foreach ($branches as $br) {
        if (empty($br['name'])) continue;
        echo "## " . llmStrip($br['name']) . "\n\n";
        if (!empty($br['address'])) echo "**Adresa:** " . llmStrip($br['address']) . (!empty($br['city']) ? ', ' . llmStrip($br['city']) : '') . (!empty($br['zip']) ? ' ' . llmStrip($br['zip']) : '') . "\n";
        if (!empty($br['phone']))   echo "**Telefon:** " . llmStrip($br['phone']) . "\n";
        if (!empty($br['email']))   echo "**E-mail:** " . llmStrip($br['email']) . "\n";
        if (isset($br['latitude']) && isset($br['longitude'])) echo "**GPS:** {$br['latitude']}, {$br['longitude']}\n";
        if (!empty($br['type']))    echo "**Typ:** " . llmStrip($br['type']) . "\n";
        echo "**Provoz:** " . (!empty($br['is_open']) ? '24/7 nonstop' : '08:00 – 20:00') . "\n";
        $notes = trim((string)localized($br, 'notes'));
        if ($notes !== '') echo "\n" . llmStrip($notes) . "\n";
        echo "\n---\n\n";
    }
}

// ------------------------------------------------------------------
// Blog posty
// ------------------------------------------------------------------
$posts = $sb->fetchCmsPages();
if (is_array($posts) && !empty($posts)) {
    echo "# Blog\n\n";
    echo "*Zdroj:* {$base}/blog\n\n";
    foreach ($posts as $p) {
        if (empty($p['slug']) || empty($p['title'])) continue;
        echo "## " . llmStrip(localized($p, 'title')) . "\n\n";
        echo "*URL:* {$base}/blog/{$p['slug']}\n\n";
        $excerpt = (string)localized($p, 'excerpt');
        if ($excerpt === '') $excerpt = (string)($p['description'] ?? '');
        if ($excerpt !== '') echo llmStrip($excerpt) . "\n\n";
        $body = (string)localized($p, 'content');
        if ($body !== '') {
            $body = llmStrip($body);
            if (mb_strlen($body) > 3000) $body = mb_substr($body, 0, 2997) . '...';
            echo $body . "\n\n";
        }
        echo "---\n\n";
    }
}

// Footer
echo "# Pro AI agenty — strukturované zdroje + API\n\n";
echo "**Developer dokumentace:** {$base}/partneri\n\n";
echo "## REST API (LIVE)\n\n";
echo "- **Base URL:** https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api\n";
echo "- **OpenAPI 3.1 spec:** https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api/api/v1/openapi.json\n";
echo "- **9 endpointů:** GET /api/v1/motorcycles, GET /api/v1/motorcycles/{id}, GET /api/v1/motorcycles/{id}/availability, GET /api/v1/branches, GET /api/v1/extras, POST /api/v1/quotes, POST /api/v1/bookings, POST /api/v1/promo/validate, POST /api/v1/voucher/validate\n";
echo "- **Hybrid auth:** bez klíče = 60 req/min/IP read, 30 req/h/IP create_booking. S X-Api-Key = per-partner rate-limit (typ. 1000 req/min).\n";
echo "- **API klíč:** info@motogo24.cz s předmětem \"API klíč\"\n\n";
echo "## MCP server (LIVE)\n\n";
echo "- **Endpoint:** https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server\n";
echo "- **Protocol:** Model Context Protocol (HTTP + JSON-RPC 2.0), spec https://modelcontextprotocol.io\n";
echo "- **9 tools:** motogo_search_motorcycles, motogo_get_motorcycle, motogo_get_availability, motogo_quote, motogo_create_booking, motogo_get_branches, motogo_get_faq, motogo_validate_promo, motogo_validate_voucher\n";
echo "- **5 resources:** motogo://about, motogo://motorcycles, motogo://branches, motogo://faq, motogo://policies\n";
echo "- **Klient (Claude Desktop):** přidej do `claude_desktop_config.json` → `\"mcpServers\": { \"motogo24\": { \"url\": \"...mcp-server\" } }`\n\n";
echo "## Strukturované zdroje\n\n";
echo "- **Sitemap XML s hreflang + image extension:** {$base}/sitemap.xml\n";
echo "- **Krátký LLM index:** {$base}/llms.txt\n";
echo "- **robots.txt s allowlistem 22 AI botů:** {$base}/robots.txt\n";
echo "- **Manifest pro AI agenty:** {$base}/.well-known/agent.json\n";
echo "- **Bezpečnostní kontakt:** {$base}/.well-known/security.txt\n";
echo "- **JSON-LD Schema.org** na každé stránce: Organization, WebSite (+SearchAction), AutomotiveBusiness, Product/Vehicle/Motorcycle, Offer, FAQPage, HowTo, Article, BreadcrumbList\n\n";
echo "*Generováno: " . date('Y-m-d H:i') . " UTC · jazyk: $lang · délka kontextu: ~80 kB*\n";
