/**
 * MotoGo24 — Edge Function: seo-check
 *
 * Server-side SEO analyzer ŽIVÉ stránky motogo24.cz. Velin SEO Health dashboard
 * volá tuto funkci, protože browser-side fetch z velin domény na motogo24.cz
 * blokuje CORS. Server-side fetch CORS nemá.
 *
 * Pro každou předanou cestu fetchne `https://www.motogo24.cz<path>`, naparsuje
 * HTML a vrátí reálné SEO metriky (stejné co měří Seobility):
 *   - title (text + délka v znacích)
 *   - meta description (text + délka)
 *   - h1 (pole všech H1 textů — ideálně 1)
 *   - wordCount — počet slov v <main> (bez nav/footer/script/style)
 *   - paragraphCount — počet <p> s ≥100 znaky textu
 *   - imagesNoAlt — počet <img> bez alt nebo s prázdným alt (mimo aria-hidden)
 *   - canonical, robots — meta tagy
 *   - statusCode, redirected
 *
 * POST /functions/v1/seo-check
 * Body: { paths: string[] }   // např. ["/", "/katalog", "/jak-pujcit"]
 * Odpověď: { results: { [path]: { ...metriky } | { error } } }
 *
 * Bezpečnost: jen GET na motogo24.cz domény (whitelist), max 30 cest/request,
 * 8s timeout per page, verify_jwt=false (volá se z velin admin SPA bez Supabase JWT).
 */ import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
const BASE = 'https://www.motogo24.cz';
const MAX_PATHS = 30;
const FETCH_TIMEOUT_MS = 8000;
// Strip HTML tagy + entity + nadbytecne whitespace -> plain text
function stripHtml(html) {
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/gi, ' ').replace(/&[a-z]+;/gi, ' ').replace(/\s+/g, ' ').trim();
}
// Vrati obsah <main ...>...</main> nebo cely body pokud main neni
function extractMain(html) {
  const m = html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i);
  if (m) return m[1];
  const b = html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
  return b ? b[1] : html;
}
function decodeEntities(s) {
  return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#x27;/gi, "'").replace(/&nbsp;/gi, ' ').replace(/&[a-z]+;/gi, ' ').trim();
}
async function analyzePage(path) {
  const url = BASE + (path.startsWith('/') ? path : '/' + path);
  const ctrl = new AbortController();
  const tm = setTimeout(()=>ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      redirect: 'follow',
      headers: {
        'User-Agent': 'MotoGo24-SEO-Check/1.0'
      }
    });
    clearTimeout(tm);
    const finalUrl = res.url;
    const redirected = finalUrl !== url;
    const statusCode = res.status;
    if (!res.ok) {
      return {
        path,
        statusCode,
        redirected,
        finalUrl,
        error: `HTTP ${statusCode}`
      };
    }
    const html = await res.text();
    // <title>
    const titleM = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    const title = titleM ? decodeEntities(stripHtml(titleM[1])) : '';
    // <meta name="description">
    let description = '';
    const descM = html.match(/<meta\s+[^>]*name=["']description["'][^>]*content=["']([^"']*)["']/i) || html.match(/<meta\s+[^>]*content=["']([^"']*)["'][^>]*name=["']description["']/i);
    if (descM) description = decodeEntities(descM[1]);
    // canonical
    let canonical = '';
    const canM = html.match(/<link\s+[^>]*rel=["']canonical["'][^>]*href=["']([^"']*)["']/i);
    if (canM) canonical = canM[1];
    // robots
    let robots = '';
    const robM = html.match(/<meta\s+[^>]*name=["']robots["'][^>]*content=["']([^"']*)["']/i);
    if (robM) robots = robM[1];
    // <h1> — vsechny
    const h1s = [];
    const h1Re = /<h1\b[^>]*>([\s\S]*?)<\/h1>/gi;
    let h1m;
    while((h1m = h1Re.exec(html)) !== null){
      const t = decodeEntities(stripHtml(h1m[1]));
      h1s.push(t);
    }
    // Body content analysis (uvnitr <main>)
    const main = extractMain(html);
    const mainText = stripHtml(main);
    const wordCount = mainText ? mainText.split(/\s+/).filter(Boolean).length : 0;
    // <p> s >= 100 znaky textu
    let paragraphCount = 0;
    const pRe = /<p\b[^>]*>([\s\S]*?)<\/p>/gi;
    let pm;
    while((pm = pRe.exec(main)) !== null){
      const t = stripHtml(pm[1]);
      if (t.length >= 100) paragraphCount++;
    }
    // <img> bez alt nebo s prazdnym alt (mimo decorative aria-hidden)
    let imagesNoAlt = 0;
    const imgRe = /<img\b([^>]*)\/?>/gi;
    let im;
    while((im = imgRe.exec(main)) !== null){
      const attrs = im[1];
      if (/\baria-hidden\s*=\s*["']?true/i.test(attrs)) continue;
      if (/\brole\s*=\s*["']?presentation/i.test(attrs)) continue;
      const altM = attrs.match(/\balt\s*=\s*["']([^"']*)["']/i);
      if (!altM || !altM[1].trim()) imagesNoAlt++;
    }
    // <strong>/<b> count
    const strongCount = (main.match(/<strong\b/gi) || []).length + (main.match(/<b\b/gi) || []).length;
    return {
      path,
      statusCode,
      redirected,
      finalUrl,
      title,
      titleLen: title.length,
      description,
      descLen: description.length,
      h1: h1s,
      h1Count: h1s.length,
      canonical,
      robots,
      wordCount,
      paragraphCount,
      imagesNoAlt,
      strongCount
    };
  } catch (e) {
    clearTimeout(tm);
    return {
      path,
      error: e instanceof Error ? e.message : String(e)
    };
  }
}
serve(async (req)=>{
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: corsHeaders
  });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({
      error: 'POST only'
    }), {
      status: 405,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
  let body;
  try {
    body = await req.json();
  } catch  {
    body = {};
  }
  let paths = Array.isArray(body?.paths) ? body.paths : [];
  paths = paths.filter((p)=>typeof p === 'string' && p.startsWith('/')).slice(0, MAX_PATHS);
  if (paths.length === 0) {
    return new Response(JSON.stringify({
      error: 'No valid paths'
    }), {
      status: 400,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
  // Paralelne, max 6 najednou aby hosting neskrtil
  const results = {};
  const concurrency = 6;
  for(let i = 0; i < paths.length; i += concurrency){
    const batch = paths.slice(i, i + concurrency);
    const settled = await Promise.all(batch.map(analyzePage));
    settled.forEach((r)=>{
      results[r.path] = r;
    });
  }
  return new Response(JSON.stringify({
    results,
    baseUrl: BASE,
    checkedAt: new Date().toISOString()
  }), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
});
