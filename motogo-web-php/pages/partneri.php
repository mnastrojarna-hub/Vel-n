<?php
// ===== MotoGo24 Web PHP — /partneri =====
// Veřejná developer-facing stránka pro AI agenty, integrátory a partnery.
// Popisuje REST API, MCP server, llms.txt, agent.json + jak získat API klíč.

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], 'Pro partnery a vývojáře']);

$content = '<main id="content"><div class="container">' . $bc .
'<div class="ccontent">

<h1>Pro partnery, vývojáře a AI agenty</h1>
<p>Otevřená integrační vrstva půjčovny MotoGo24 — REST API, MCP server pro AI agenty, strukturované metadata pro LLM a sitemap. Bez registrace pro čtení, s API klíčem pro vyšší rate-limity.</p>

<h2>1. REST API</h2>
<p>Veřejné REST API pro programovou rezervaci motorek. Hybrid auth: <strong>bez klíče</strong> nízký rate-limit per IP (60/min read, 30/h create_booking), <strong>s X-Api-Key</strong> per-partner rate-limit dle smlouvy.</p>

<table class="table" style="width:100%;border-collapse:collapse;margin:12px 0">
<thead><tr style="background:#f1faf7"><th style="padding:8px;text-align:left">Endpoint</th><th style="padding:8px;text-align:left">Účel</th></tr></thead>
<tbody>
<tr><td style="padding:8px"><code>GET /api/v1/motorcycles</code></td><td style="padding:8px">Katalog motorek (filtry: category, license_group, kw_min/max, price_max)</td></tr>
<tr><td style="padding:8px"><code>GET /api/v1/motorcycles/{id}</code></td><td style="padding:8px">Detail motorky včetně specifikací a cen</td></tr>
<tr><td style="padding:8px"><code>GET /api/v1/motorcycles/{id}/availability</code></td><td style="padding:8px">Obsazené termíny pro kalendář</td></tr>
<tr><td style="padding:8px"><code>GET /api/v1/branches</code></td><td style="padding:8px">Seznam poboček (s GPS)</td></tr>
<tr><td style="padding:8px"><code>GET /api/v1/extras</code></td><td style="padding:8px">Katalog příslušenství</td></tr>
<tr><td style="padding:8px"><code>POST /api/v1/quotes</code></td><td style="padding:8px">Kalkulace ceny (bez vytvoření rezervace)</td></tr>
<tr><td style="padding:8px"><code>POST /api/v1/bookings</code></td><td style="padding:8px">Vytvoří rezervaci a vrátí Stripe payment URL</td></tr>
<tr><td style="padding:8px"><code>POST /api/v1/promo/validate</code></td><td style="padding:8px">Validace promo kódu</td></tr>
<tr><td style="padding:8px"><code>POST /api/v1/voucher/validate</code></td><td style="padding:8px">Validace voucher kódu</td></tr>
<tr><td style="padding:8px"><code>GET /api/v1/openapi.json</code></td><td style="padding:8px">Kompletní OpenAPI 3.1 spec — agentní frameworky (LangChain, CrewAI, Claude Agent SDK) si načtou auto-tools</td></tr>
</tbody></table>

<p><strong>Base URL:</strong> <code>https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api</code></p>

<p><strong>Příklad:</strong></p>
<pre style="background:#1a2e22;color:#74FB71;padding:12px;border-radius:8px;overflow:auto">
curl https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/public-api/api/v1/motorcycles \
  -H "X-Api-Key: mk_live_..."
</pre>

<h2>2. MCP server (Model Context Protocol)</h2>
<p>Implementuje <a href="https://modelcontextprotocol.io" target="_blank" rel="noopener">MCP standard</a> přes HTTP/JSON-RPC 2.0. Klient (Claude Desktop, Cursor, Cline, Smithery, vlastní agent) získá 9 nástrojů a 5 read-only zdrojů pro práci s naším katalogem.</p>

<p><strong>Endpoint:</strong> <code>https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server</code></p>

<p><strong>Registrace v Claude Desktop</strong> (<code>~/Library/Application Support/Claude/claude_desktop_config.json</code> na macOS):</p>
<pre style="background:#1a2e22;color:#74FB71;padding:12px;border-radius:8px;overflow:auto">
{
  "mcpServers": {
    "motogo24": {
      "url": "https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server"
    }
  }
}
</pre>

<p><strong>Dostupné tools:</strong> <code>motogo_search_motorcycles</code>, <code>motogo_get_motorcycle</code>, <code>motogo_get_availability</code>, <code>motogo_quote</code>, <code>motogo_create_booking</code>, <code>motogo_get_branches</code>, <code>motogo_get_faq</code>, <code>motogo_validate_promo</code>, <code>motogo_validate_voucher</code>.</p>

<p><strong>Resources:</strong> <code>motogo://about</code>, <code>motogo://motorcycles</code>, <code>motogo://branches</code>, <code>motogo://faq</code>, <code>motogo://policies</code>.</p>

<h2>3. LLM-friendly content</h2>
<p>Pro AI agenty bez API přístupu nabízíme strukturovaný markdown obsah, který lze nahrát do kontextu:</p>
<ul>
<li><a href="/llms.txt">/llms.txt</a> — krátký index všech URL webu (per jazyk)</li>
<li><a href="/llms-full.txt">/llms-full.txt</a> — sloučený kompletní obsah všech statických stránek (~80 kB markdown)</li>
<li><a href="/sitemap.xml">/sitemap.xml</a> — XML sitemap s hreflang a image extension</li>
<li><a href="/.well-known/agent.json">/.well-known/agent.json</a> — manifest pro AI agenty (capabilities, endpoints, policies)</li>
<li><a href="/robots.txt">/robots.txt</a> — explicitní allowlist 22 AI crawlerů</li>
</ul>

<h2>4. JSON-LD na webu</h2>
<p>Každá stránka obsahuje strukturovaná data Schema.org pro AI Overviews, Perplexity citations a ChatGPT Search:</p>
<ul>
<li><strong>Globálně:</strong> Organization · WebSite + SearchAction · LocalBusiness + AutomotiveBusiness</li>
<li><strong>Detail motorky:</strong> Product + Motorcycle (Vehicle subtype) s engine, výkon, torque, weight, fuel, license + Offer s priceSpecification per den + AggregateRating</li>
<li><strong>Detail produktu:</strong> Product + AggregateRating</li>
<li><strong>Výpisy:</strong> ItemList</li>
<li><strong>Postup půjčení:</strong> HowTo + FAQPage</li>
<li><strong>Blog:</strong> Article + BlogPosting (s articleBody, dateModified, wordCount)</li>
<li><strong>Kontakt:</strong> per-branch LocalBusiness s GPS</li>
</ul>

<h2>5. Jak získat API klíč</h2>
<p>Pro vyšší rate-limity (1000 req/min místo 60) napiš na <strong><a href="mailto:info@motogo24.cz?subject=API%20kl%C3%AD%C4%8D%20%E2%80%94%20%5Btv%C5%AFj%20projekt%5D">info@motogo24.cz</a></strong> s předmětem „API klíč" a uveď:</p>
<ul>
<li>Název projektu / firmy</li>
<li>URL nebo popis použití</li>
<li>Očekávaný objem requestů</li>
<li>Které scopes potřebuješ: <code>read</code> (motorky, pobočky, FAQ), <code>quote</code> (kalkulace), <code>book</code> (vytvoření rezervace)</li>
</ul>
<p>Klíč obvykle vystavíme do 24 hodin. Klíč se posílá v hlavičce <code>X-Api-Key</code>.</p>

<h2>6. Kontakt</h2>
<p><strong>E-mail:</strong> <a href="mailto:info@motogo24.cz">info@motogo24.cz</a><br>
<strong>Telefon:</strong> <a href="tel:+420774256271">+420 774 256 271</a><br>
<strong>Provozovatel:</strong> Bc. Petra Semorádová, IČO 21874263, Mezná 9, 393 01 Pelhřimov<br>
<strong>Bezpečnostní kontakt:</strong> <a href="/.well-known/security.txt">/.well-known/security.txt</a></p>

<h2>7. Compliance</h2>
<ul>
<li><strong>GDPR:</strong> všechny IP adresy v logu jsou hashované (sha256+salt). Viz <a href="/gdpr">Zásady ochrany osobních údajů</a>.</li>
<li><strong>Stripe LIVE:</strong> platby jsou PCI DSS compliant.</li>
<li><strong>Rate limits:</strong> 429 status code + <code>Retry-After</code> header při překročení.</li>
<li><strong>Idempotency:</strong> POST <code>/bookings</code> přijímá <code>Idempotency-Key</code> header.</li>
</ul>

</div></div></main>';

renderPage('Pro partnery a vývojáře | MotoGo24', $content, '/partneri', [
    'description' => 'Veřejné REST API, MCP server, llms.txt a JSON-LD pro AI agenty a integrátory MotoGo24. Hybrid auth, 9 endpointů, OpenAPI 3.1 spec.',
    'keywords' => 'MotoGo24 API, REST API půjčovna motorek, MCP server motorcycle rental, motogo24 developer, Schema.org Vehicle Motorcycle',
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => 'Pro partnery a vývojáře', 'url' => 'https://motogo24.cz/partneri'],
    ],
]);
