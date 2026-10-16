<?php
// ===== MotoGo24 Web PHP — /partneri =====
// Veřejná developer-facing stránka pro AI agenty, integrátory a partnery.
// Popisuje REST API, MCP server, llms.txt, agent.json + jak získat API klíč.
// Texty: čeština níže (výchozí), cizí jazyky lang/v2/<jazyk>/static-pages.php (pages.partneri).

$T = [
    'title' => 'Pro partnery a vývojáře | MotoGo24',
    'desc' => 'Veřejné REST API, MCP server, llms.txt a JSON-LD pro AI agenty a integrátory MotoGo24. Hybrid auth, 9 endpointů, OpenAPI 3.1 spec.',
    'keywords' => 'motopůjčovna, půjčovna motorek, REST API, MCP server, llms.txt, AI agenti, integrace MotoGo24',
    'crumb' => 'Pro partnery a vývojáře',
    'h1' => 'Pro partnery, vývojáře a AI agenty',
    'lead' => 'Otevřená integrační vrstva půjčovny MotoGo24 — REST API, MCP server pro AI agenty, strukturované metadata pro LLM a sitemap. Bez registrace pro čtení, s API klíčem pro vyšší rate-limity.',
    'api_text' => 'Veřejné REST API pro programovou rezervaci motorek. Hybrid auth: <strong>bez klíče</strong> nízký rate-limit per IP (60/min read, 30/h create_booking), <strong>s X-Api-Key</strong> per-partner rate-limit dle smlouvy.',
    'th_purpose' => 'Účel',
    'ep' => [
        'Katalog motorek (filtry: category, license_group, kw_min/max, price_max)',
        'Detail motorky včetně specifikací a cen',
        'Obsazené termíny pro kalendář',
        'Seznam poboček (s GPS)',
        'Katalog příslušenství',
        'Kalkulace ceny (bez vytvoření rezervace)',
        'Vytvoří rezervaci a vrátí Stripe payment URL',
        'Validace promo kódu',
        'Validace voucher kódu',
        'Kompletní OpenAPI 3.1 spec — agentní frameworky (LangChain, CrewAI, Claude Agent SDK) si načtou auto-tools',
    ],
    'example' => 'Příklad:',
    'mcp_text' => 'Implementuje {mcp} přes HTTP/JSON-RPC 2.0. Klient (Claude Desktop, Cursor, Cline, Smithery, vlastní agent) získá 9 nástrojů a 5 read-only zdrojů pro práci s naším katalogem.',
    'mcp_std' => 'MCP standard',
    'mcp_register' => '<strong>Registrace v Claude Desktop</strong> ({path} na macOS):',
    'tools' => 'Dostupné tools:',
    'llm_text' => 'Pro AI agenty bez API přístupu nabízíme strukturovaný markdown obsah, který lze nahrát do kontextu:',
    'llm_items' => [
        'krátký index všech URL webu (per jazyk)',
        'sloučený kompletní obsah všech statických stránek (~80 kB markdown)',
        'XML sitemap s hreflang a image extension',
        'manifest pro AI agenty (capabilities, endpoints, policies)',
        'explicitní allowlist 22 AI crawlerů',
    ],
    'ld_title' => '4. JSON-LD na webu',
    'ld_text' => 'Každá stránka obsahuje strukturovaná data Schema.org pro AI Overviews, Perplexity citations a ChatGPT Search:',
    'ld_items' => [
        '<strong>Globálně:</strong> Organization · WebSite + SearchAction · LocalBusiness + AutomotiveBusiness',
        '<strong>Detail motorky:</strong> Product + Motorcycle (Vehicle subtype) s engine, výkon, torque, weight, fuel, license + Offer s priceSpecification per den + AggregateRating',
        '<strong>Detail produktu:</strong> Product + AggregateRating',
        '<strong>Výpisy:</strong> ItemList',
        '<strong>Postup půjčení:</strong> HowTo + FAQPage',
        '<strong>Blog:</strong> Article + BlogPosting (s articleBody, dateModified, wordCount)',
        '<strong>Kontakt:</strong> per-branch LocalBusiness s GPS',
    ],
    'key_title' => '5. Jak získat API klíč',
    'key_subject' => 'API klíč — [tvůj projekt]',
    'key_text' => 'Pro vyšší rate-limity (1000 req/min místo 60) napiš na {email} s předmětem „API klíč" a uveď:',
    'key_items' => [
        'Název projektu / firmy',
        'URL nebo popis použití',
        'Očekávaný objem requestů',
        'Které scopes potřebuješ: <code>read</code> (motorky, pobočky, FAQ), <code>quote</code> (kalkulace), <code>book</code> (vytvoření rezervace)',
    ],
    'key_note' => 'Klíč obvykle vystavíme do 24 hodin. Klíč se posílá v hlavičce <code>X-Api-Key</code>.',
    'contact_title' => '6. Kontakt',
    'c_phone' => 'Telefon',
    'c_operator' => 'Provozovatel',
    'c_security' => 'Bezpečnostní kontakt',
    'comp_items' => [
        '<strong>GDPR:</strong> všechny IP adresy v logu jsou hashované (sha256+salt). Viz {a}Zásady ochrany osobních údajů{/a}.',
        '<strong>Stripe LIVE:</strong> platby jsou PCI DSS compliant.',
        '<strong>Rate limits:</strong> 429 status code + <code>Retry-After</code> header při překročení.',
        '<strong>Idempotency:</strong> POST <code>/bookings</code> přijímá <code>Idempotency-Key</code> header.',
    ],
];
$tr = function_exists('i18nDetectLanguage') && i18nDetectLanguage() !== 'cs' ? t('pages.partneri') : null;
if (is_array($tr)) $T = array_merge($T, $tr);

$h = function ($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); };
$mailLink = function ($subject = null) {
    return '<a href="mailto:info@motogo24.cz' . ($subject !== null ? '?subject=' . rawurlencode($subject) : '') . '">info&#64;motogo24&#46;cz</a>';
};
$fill = function ($s) use ($mailLink, $T) {
    return strtr((string)$s, [
        '{email}' => '<strong>' . $mailLink($T['key_subject']) . '</strong>',
        '{mcp}' => '<a href="https://modelcontextprotocol.io" target="_blank" rel="noopener">' . htmlspecialchars($T['mcp_std'], ENT_QUOTES, 'UTF-8') . '</a>',
        '{path}' => '<code>~/Library/Application Support/Claude/claude_desktop_config.json</code>',
        '{a}' => '<a href="/dokumenty/zasady-ochrany-osobnich-udaju">',
        '{/a}' => '</a>',
    ]);
};
$li = function ($items, $prefix = []) use ($fill) {
    $o = '';
    foreach (array_values((array)$items) as $i => $it) $o .= '<li>' . ($prefix[$i] ?? '') . $fill($it) . '</li>';
    return $o;
};

$endpoints = ['GET /api/v1/motorcycles', 'GET /api/v1/motorcycles/{id}', 'GET /api/v1/motorcycles/{id}/availability', 'GET /api/v1/branches',
    'GET /api/v1/extras', 'POST /api/v1/quotes', 'POST /api/v1/bookings', 'POST /api/v1/promo/validate', 'POST /api/v1/voucher/validate', 'GET /api/v1/openapi.json'];
$rows = '';
foreach ($endpoints as $i => $ep) {
    $rows .= '<tr><td style="padding:8px"><code>' . $ep . '</code></td><td style="padding:8px">' . $h($T['ep'][$i] ?? '') . '</td></tr>' . "\n";
}
$llmLinks = ['/llms.txt', '/llms-full.txt', '/sitemap.xml', '/.well-known/agent.json', '/robots.txt'];
$llmPrefix = array_map(function ($u) { return '<a href="' . $u . '">' . $u . '</a> — '; }, $llmLinks);
$pre = 'background:#1a2e22;color:#74FB71;padding:12px;border-radius:8px;overflow:auto';

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], $h($T['crumb'])]);

$content = '<main id="content"><div class="container">' . $bc .
'<div class="ccontent">

<h1>' . $h($T['h1']) . '</h1>
<p>' . $h($T['lead']) . '</p>

<h2>1. REST API</h2>
<p>' . $fill($T['api_text']) . '</p>

<div style="overflow-x:auto;-webkit-overflow-scrolling:touch;margin:12px 0">
<table class="table" style="width:100%;border-collapse:collapse;margin:0">
<thead><tr style="background:#f1faf7"><th style="padding:8px;text-align:left">Endpoint</th><th style="padding:8px;text-align:left">' . $h($T['th_purpose']) . '</th></tr></thead>
<tbody>
' . $rows . '</tbody></table>
</div>

<p><strong>Base URL:</strong> <code style="overflow-wrap:anywhere">https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api</code></p>

<p><strong>' . $h($T['example']) . '</strong></p>
<pre style="' . $pre . '">
curl https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api/api/v1/motorcycles \\
  -H "X-Api-Key: mk_live_..."
</pre>

<h2>2. MCP server (Model Context Protocol)</h2>
<p>' . $fill($T['mcp_text']) . '</p>

<p><strong>Endpoint:</strong> <code style="overflow-wrap:anywhere">https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server</code></p>

<p>' . $fill($T['mcp_register']) . '</p>
<pre style="' . $pre . '">
{
  "mcpServers": {
    "motogo24": {
      "url": "https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server"
    }
  }
}
</pre>

<p><strong>' . $h($T['tools']) . '</strong> <code>motogo_search_motorcycles</code>, <code>motogo_get_motorcycle</code>, <code>motogo_get_availability</code>, <code>motogo_quote</code>, <code>motogo_create_booking</code>, <code>motogo_get_branches</code>, <code>motogo_get_faq</code>, <code>motogo_validate_promo</code>, <code>motogo_validate_voucher</code>.</p>

<p><strong>Resources:</strong> <code>motogo://about</code>, <code>motogo://motorcycles</code>, <code>motogo://branches</code>, <code>motogo://faq</code>, <code>motogo://policies</code>.</p>

<h2>3. LLM-friendly content</h2>
<p>' . $h($T['llm_text']) . '</p>
<ul>
' . $li($T['llm_items'], $llmPrefix) . '
</ul>

<h2>' . $h($T['ld_title']) . '</h2>
<p>' . $h($T['ld_text']) . '</p>
<ul>
' . $li($T['ld_items']) . '
</ul>

<h2>' . $h($T['key_title']) . '</h2>
<p>' . $fill($T['key_text']) . '</p>
<ul>
' . $li($T['key_items']) . '
</ul>
<p>' . $fill($T['key_note']) . '</p>

<h2>' . $h($T['contact_title']) . '</h2>
<p><strong>E-mail:</strong> ' . $mailLink() . '<br>
<strong>' . $h($T['c_phone']) . ':</strong> <a href="tel:+420774256271">+420 774 256 271</a><br>
<strong>' . $h($T['c_operator']) . ':</strong> Bc. Petra Semorádová, IČO 21874263, Mezná 9, 393 01 Pelhřimov<br>
<strong>' . $h($T['c_security']) . ':</strong> <a href="/.well-known/security.txt">/.well-known/security.txt</a></p>

<h2>7. Compliance</h2>
<ul>
' . $li($T['comp_items']) . '
</ul>

</div></div></main>';

renderPage($T['title'], $content, '/partneri', [
    'description' => $T['desc'],
    'keywords' => $T['keywords'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => $T['crumb'], 'url' => siteCanonicalUrl('/partneri')],
    ],
]);
