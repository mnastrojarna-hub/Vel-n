// ===== _shared/manual-reader.ts =====
// Robustní čtení návodu motorky (PDF z bucketu `media` / externí web výrobce).
// Sdíleno mezi ai-moto-agent a ai-public-agent — každý dřív měl vlastní kopii,
// která uměla JEDEN pokus s bot User-Agentem „MotoGo24-AI/1.0": stránky výrobců
// takový UA běžně blokují (403), rozcestník s odkazem na PDF neuměla projít a
// při selhání PDF se externí odkaz už vůbec nezkusil. Reálný dopad 26. 7. 2026:
// zákazník s kontrolkou motoru dostal „návod se nepodařilo načíst" + obecné rady.
//
// Co tahle verze umí navíc:
//  - browser-like User-Agent + Accept hlavičky, timeout, retry na 5xx/429/síť
//  - zkouší VŠECHNY zdroje (PDF i externí web), ne jen první neprázdný
//  - PDF pozná i podle magic bytes `%PDF` (špatný content-type serveru nevadí)
//  - z tenké HTML stránky (rozcestník/JS viewer) vytáhne odkazy na PDF a
//    stáhne nejnadějnější z nich (skóruje „manual/navod/owner/handbook…")

const BROWSER_HEADERS: Record<string, string> = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/pdf,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'cs,en;q=0.8,de;q=0.6',
}

// Strop textu do kontextu modelu — běžný manuál se vejde celý, delší se okénkuje.
const MAX_TEXT = 60000
const MAX_PDF_BYTES = 40_000_000

export function stripHtml(html: string): string {
  return String(html || '')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#3[49];/g, "'")
    .replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
}

async function fetchUrl(url: string, timeoutMs = 20000): Promise<Response> {
  let lastErr = ''
  for (let attempt = 0; attempt < 2; attempt++) {
    const ctrl = new AbortController()
    const t = setTimeout(() => ctrl.abort(), timeoutMs)
    try {
      const resp = await fetch(url, { headers: BROWSER_HEADERS, redirect: 'follow', signal: ctrl.signal })
      clearTimeout(t)
      if (resp.ok) return resp
      lastErr = `HTTP ${resp.status}`
      if (resp.status < 500 && resp.status !== 429) break // 4xx (mimo 429) se retry nespraví
    } catch (e) {
      clearTimeout(t)
      lastErr = (e as Error).message
    }
    await new Promise((r) => setTimeout(r, 400 * (attempt + 1)))
  }
  throw new Error(lastErr || 'fetch failed')
}

async function pdfToText(buf: Uint8Array): Promise<string> {
  // Dynamický import — unpdf se načte jen když opravdu parsujeme PDF (šetří cold-start).
  const { extractText, getDocumentProxy } = await import('https://esm.sh/unpdf@0.12.1')
  const pdf = await getDocumentProxy(buf)
  const res = await extractText(pdf, { mergePages: true }) as { text?: string }
  return String(res.text || '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
}

function isPdfBytes(buf: Uint8Array): boolean {
  return buf.length > 4 && buf[0] === 0x25 && buf[1] === 0x50 && buf[2] === 0x44 && buf[3] === 0x46 // %PDF
}

// Odkazy na PDF z HTML stránky (href/src, i iframe/embed viewery), seřazené
// podle nadějnosti názvu. Relativní cesty se resolvují proti finální URL stránky.
function findPdfLinks(html: string, baseUrl: string): string[] {
  const urls = new Set<string>()
  const re = /(?:href|src|data)\s*=\s*["']([^"']+)["']/gi
  let m: RegExpExecArray | null
  while ((m = re.exec(html)) && urls.size < 40) {
    const raw = m[1].trim()
    if (!raw || /^(javascript:|mailto:|#)/i.test(raw)) continue
    try {
      const abs = new URL(raw, baseUrl).href
      if (/\.pdf(\?|#|$)/i.test(abs)) urls.add(abs)
    } catch { /* nevalidní URL přeskočit */ }
  }
  const score = (u: string) => {
    const s = decodeURIComponent(u).toLowerCase()
    let n = 0
    for (const k of ['manual', 'navod', 'návod', 'owner', 'handbook', 'prirucka', 'příručka', 'uzivatel', 'user', 'bedienung']) {
      if (s.includes(k)) n += 2
    }
    return n
  }
  return [...urls].sort((a, b) => score(b) - score(a))
}

// Přečte jeden zdroj (PDF nebo web). U tenké HTML stránky zkusí PDF odkazy z ní.
async function readSource(url: string, forcePdf: boolean): Promise<{ text: string; sourceType: string; url: string }> {
  const resp = await fetchUrl(url)
  const finalUrl = resp.url || url
  const ctype = (resp.headers.get('content-type') || '').toLowerCase()
  const buf = new Uint8Array(await resp.arrayBuffer())
  if (forcePdf || ctype.includes('pdf') || /\.pdf(\?|#|$)/i.test(finalUrl) || isPdfBytes(buf)) {
    return { text: await pdfToText(buf), sourceType: 'pdf', url: finalUrl }
  }
  const html = new TextDecoder().decode(buf)
  const text = stripHtml(html)
  // Stránka bez použitelného textu (rozcestník, JS viewer) → projdi PDF odkazy z ní.
  // I u stránky s textem zkus PDF, pokud je text podezřele krátký na celý manuál.
  if (text.length < 10000) {
    for (const pdfLink of findPdfLinks(html, finalUrl).slice(0, 3)) {
      try {
        const r2 = await fetchUrl(pdfLink)
        const b2 = new Uint8Array(await r2.arrayBuffer())
        if (b2.length > MAX_PDF_BYTES || !(isPdfBytes(b2) || (r2.headers.get('content-type') || '').includes('pdf'))) continue
        const t2 = await pdfToText(b2)
        if (t2.length >= Math.max(1000, text.length)) return { text: t2, sourceType: 'pdf', url: pdfLink }
      } catch { /* zkus další odkaz */ }
    }
  }
  return { text, sourceType: 'web', url: finalUrl }
}

// Okénkování dlouhého textu na pasáže kolem výskytů slov z dotazu.
function windowExcerpts(text: string, query: string): string | null {
  const lc = text.toLowerCase()
  const terms = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3)
  const hits: number[] = []
  for (const term of terms) {
    let from = 0
    for (;;) {
      const i = lc.indexOf(term, from)
      if (i < 0 || hits.length > 60) break
      hits.push(i); from = i + term.length
    }
  }
  if (hits.length === 0) return null
  hits.sort((a, b) => a - b)
  const win: Array<[number, number]> = []
  for (const i of hits) {
    const s = Math.max(0, i - 1500), e = Math.min(text.length, i + 1500)
    const last = win[win.length - 1]
    if (last && s <= last[1]) last[1] = Math.max(last[1], e)
    else win.push([s, e])
  }
  let excerpt = win.map(([s, e]) => (s > 0 ? '…' : '') + text.slice(s, e).trim() + (e < text.length ? '…' : '')).join('\n\n———\n\n')
  if (excerpt.length > MAX_TEXT) excerpt = excerpt.slice(0, MAX_TEXT) + '…'
  return excerpt
}

/**
 * Přečte návod motorky. Zkouší postupně PDF (`pdfUrl`, priorita) a externí
 * odkaz (`extUrl`) — použije PRVNÍ zdroj s použitelným textem. Při `query` a
 * dlouhém textu vrátí relevantní pasáže, jinak celý (zkrácený) text.
 * `instruction` = pokyn pro model přiložený k úspěšnému výsledku (agenti se
 * liší: app zakazuje žádat o fotku, veřejný web o ni žádat smí).
 */
export async function readManual(opts: {
  modelName: string; pdfUrl?: string; extUrl?: string; query?: string; instruction: string; contactHint?: string
}): Promise<Record<string, unknown>> {
  const { modelName, query = '', instruction } = opts
  const pdfUrl = String(opts.pdfUrl || '').trim()
  const extUrl = String(opts.extUrl || '').trim()
  const contact = opts.contactHint || 'kontakt MotoGo24 (+420 774 256 271)'
  const candidates = [...new Set([pdfUrl, extUrl].filter(Boolean))]
  if (candidates.length === 0) {
    return {
      found: false, model: modelName,
      notice: `K motorce ${modelName} není v systému nahraný návod ani externí odkaz. NEVYMÝŠLEJ si technické údaje (tlak v pneu, druh oleje, kontrolky, postup startování apod.) — řekni, že návod k téhle motorce nemáš k dispozici, a nabídni ${contact}.`,
    }
  }

  let best: { text: string; sourceType: string; url: string } | null = null
  let lastErr = ''
  for (const u of candidates) {
    try {
      const r = await readSource(u, u === pdfUrl && !!pdfUrl)
      if (r.text.length >= 200) { best = r; break } // použitelný text → dál nezkoušet
      if (!best || r.text.length > best.text.length) best = r
    } catch (e) {
      lastErr = (e as Error).message
    }
  }

  if (!best || best.text.length < 30) {
    const link = extUrl || pdfUrl
    return {
      found: true, model: modelName, url: link, fetch_failed: true, tried: candidates,
      notice: `Návod k ${modelName} se nepodařilo strojově přečíst (${lastErr || 'nepodařilo se vytáhnout čitelný text — nejspíš skenované PDF nebo JS stránka'}). POVINNĚ vlož zákazníkovi do odpovědi přímý odkaz na návod: ${link} — ať si ho otevře sám. PŘÍSNÝ ZÁKAZ vymýšlet obsah návodu nebo radit „z obecných znalostí" konkrétní technické údaje tohoto modelu; smíš dát jen univerzální bezpečnostní rady (zastavit, nepokračovat při vážných příznacích) a nabídni ${contact}.`,
    }
  }

  const { text, sourceType, url } = best
  if (query && text.length > MAX_TEXT) {
    const excerpt = windowExcerpts(text, query)
    if (excerpt) {
      return {
        found: true, model: modelName, source_type: sourceType, url, mode: 'excerpts', query,
        total_chars: text.length, text: excerpt, instruction,
      }
    }
  }
  const full = text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) + `\n…[zkráceno kvůli délce — celý návod: ${url}]` : text
  return {
    found: true, model: modelName, source_type: sourceType, url, mode: 'full',
    query: query || undefined, total_chars: text.length, text: full, instruction,
  }
}
