// Volání Anthropic API pro translate-document: tool-forced výstup, opakování přechodných chyb
// (síť / 429 / 5xx / 529 overloaded), kontrola stop_reason (max_tokens / refusal = NIKDY neuložit).

import { validateChunk } from './validate.ts'

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
// Sonnet pro právní texty (kvalita i instrukční stabilita u dlouhého HTML).
export const MODEL = 'claude-sonnet-4-6'
const MAX_TOKENS_CHUNK = 16000   // část ~9 tis. znaků HTML ≈ 3–6 tis. výstupních tokenů
const MAX_TOKENS_META = 2000
const MAX_TOKENS_PDF = 20000     // část PDF (4 strany) → HTML

export const LANG_NAMES: Record<string, string> = {
  en: 'English', de: 'German (Deutsch)', es: 'Spanish (Español)', fr: 'French (Français)',
  nl: 'Dutch (Nederlands)', pl: 'Polish (Polski)', uk: 'Ukrainian (Українська, uk-UA — NOT British English)',
}

// Ustálené pojmy (EDGE-DOC-17: „kukla“ se překládala jako přilba/helma).
const GLOSSARY: Record<string, string> = {
  en: 'kukla = balaclava (NOT helmet); helma/přilba = helmet; spoluúčast = excess; kauce = deposit; nájemce = lessee/renter; pronajímatel = lessor; zelená karta = green card; technický průkaz = vehicle registration certificate; tankvak = tank bag; kotoučový zámek = disc lock',
  de: 'kukla = Sturmhaube (NICHT Helm); helma/přilba = Helm; spoluúčast = Selbstbeteiligung; kauce = Kaution; nájemce = Mieter; pronajímatel = Vermieter; zelená karta = Grüne Versicherungskarte; technický průkaz = Fahrzeugschein; tankvak = Tankrucksack; kotoučový zámek = Bremsscheibenschloss',
  es: 'kukla = sotocasco (NO casco); helma/přilba = casco; spoluúčast = franquicia; kauce = fianza; nájemce = arrendatario; pronajímatel = arrendador; zelená karta = carta verde; technický průkaz = permiso de circulación; tankvak = bolsa sobredepósito; kotoučový zámek = candado de disco',
  fr: 'kukla = cagoule (PAS casque); helma/přilba = casque; spoluúčast = franchise; kauce = dépôt de garantie; nájemce = locataire; pronajímatel = loueur; zelená karta = carte verte; technický průkaz = certificat d’immatriculation; tankvak = sacoche de réservoir; kotoučový zámek = bloque-disque',
  nl: 'kukla = bivakmuts (GEEN helm); helma/přilba = helm; spoluúčast = eigen risico; kauce = borg; nájemce = huurder; pronajímatel = verhuurder; zelená karta = groene kaart; technický průkaz = kentekenbewijs; tankvak = tanktas; kotoučový zámek = schijfremslot',
  pl: 'kukla = kominiarka (NIE kask); helma/přilba = kask; spoluúčast = udział własny; kauce = kaucja; nájemce = najemca; pronajímatel = wynajmujący; zelená karta = zielona karta; technický průkaz = dowód rejestracyjny; tankvak = tankbag; kotoučový zámek = blokada tarczy hamulcowej',
  uk: 'kukla = балаклава (НЕ шолом); helma/přilba = шолом; spoluúčast = франшиза; kauce = застава; nájemce = орендар; pronajímatel = орендодавець; zelená karta = зелена карта; technický průkaz = свідоцтво про реєстрацію; tankvak = сумка на бак; kotoučový zámek = замок на гальмівний диск',
}

export function systemPrompt(lang: string): string {
  const name = LANG_NAMES[lang] || lang
  return [
    `You are a professional Czech-to-${name} legal/business document translator for MotoGo24, a Czech motorcycle rental company.`,
    `Translate the Czech input faithfully and completely into ${name} (${lang}): natural, native and fluent, but legally exact. Never summarize, shorten, add or omit anything.`,
    '- Preserve ALL HTML tags, attributes, inline styles and the structure EXACTLY; translate only human-readable text.',
    '- HTML comments like <!--mg:3--> are structural markers: keep every one exactly once, unchanged, in the same place.',
    '- Keep ALL template placeholders ({{customer_name}}, {today}, %s …) exactly as they are.',
    '- Keep clause numbering and letters exactly (e.g. "7 d)", "čl. 4" → same number/letter).',
    '- Keep every amount and percentage as digits followed by "Kč" or "%" (you may only change the thousands separator). Never convert currencies, never write "CZK" instead of "Kč".',
    '- Do not change URLs, e-mail addresses, phone numbers, IČO, DIČ, VIN, licence plates, brand names, postal codes or numeric dates. Keep "MotoGo24" and Czech place names (Mezná, Pelhřimov, Brno…) unchanged.',
    `- Terminology: ${GLOSSARY[lang] || ''}`,
    '- Call the submit_translation tool with the result.',
  ].join('\n')
}

export class TranslateError extends Error {
  code: string
  constructor(code: string, msg: string) { super(msg); this.code = code }
}

function classify(status: number, errText: string): TranslateError {
  const lower = errText.toLowerCase()
  if (lower.includes('credit balance') && lower.includes('too low')) return new TranslateError('insufficient_credits', 'Anthropic API: kredit vyčerpán. Doplň na console.anthropic.com → Plans & Billing.')
  if (status === 401 || lower.includes('invalid x-api-key')) return new TranslateError('invalid_api_key', 'Anthropic API: neplatný API klíč (sekret ANTHROPIC_API_KEY).')
  return new TranslateError('anthropic_error', `Anthropic API ${status}: ${errText.slice(0, 300)}`)
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/** Jedno tool-forced volání; přechodné chyby 3× s čekáním. Vrací input nástroje (nikdy useknutý). */
export async function callTool(system: string, content: unknown[], props: Record<string, unknown>, maxTokens: number): Promise<Record<string, unknown>> {
  if (!ANTHROPIC_API_KEY) throw new TranslateError('no_api_key', 'ANTHROPIC_API_KEY not configured')
  const tool = { name: 'submit_translation', description: 'Submit the translation.', input_schema: { type: 'object', properties: props, required: Object.keys(props) } }
  let last: TranslateError = new TranslateError('anthropic_error', 'no attempt')
  for (let attempt = 1; attempt <= 3; attempt++) {
    let res: Response
    try {
      res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, system, tools: [tool], tool_choice: { type: 'tool', name: 'submit_translation' }, messages: [{ role: 'user', content }] }),
      })
    } catch (e) {
      last = new TranslateError('network', 'síťová chyba: ' + (e instanceof Error ? e.message : String(e)))
      await sleep(2000 * attempt); continue
    }
    if (!res.ok) {
      const txt = await res.text().catch(() => '')
      last = classify(res.status, txt)
      if (res.status === 429 || res.status >= 500) {
        const ra = Number(res.headers.get('retry-after'))
        await sleep(Number.isFinite(ra) && ra > 0 ? Math.min(ra, 30) * 1000 : 3000 * attempt); continue
      }
      throw last
    }
    const data = await res.json()
    const stop = String(data?.stop_reason || '')
    if (stop === 'max_tokens') throw new TranslateError('truncated', `výstup useknutý (max_tokens=${maxTokens}) — neuloženo`)
    if (stop === 'refusal') throw new TranslateError('refusal', 'model odmítl překlad (stop_reason=refusal)')
    const tu = Array.isArray(data?.content) ? data.content.find((c: { type?: string; name?: string }) => c?.type === 'tool_use' && c?.name === 'submit_translation') : null
    if (!tu || !tu.input || typeof tu.input !== 'object') throw new TranslateError('no_tool_use', `model nevrátil tool_use (stop=${stop})`)
    return tu.input as Record<string, unknown>
  }
  throw last
}

/** Přeloží jednu část HTML a ověří ji (2 pokusy při neplatném výstupu). */
export async function translateChunk(text: string, lang: string, part: string): Promise<string> {
  const system = systemPrompt(lang)
  let why = ''
  for (let attempt = 1; attempt <= 2; attempt++) {
    const note = `This is part ${part} of a longer Czech document. Translate exactly this part (an HTML fragment) into ${LANG_NAMES[lang] || lang}.` +
      (why ? ` A previous attempt was rejected (${why}) — keep the structure, markers, placeholders and amounts identical.` : '')
    const input = await callTool(system, [{ type: 'text', text: `${note}\n\nCzech source HTML:\n${text}` }],
      { content_html: { type: 'string', description: 'The translated HTML fragment.' } }, MAX_TOKENS_CHUNK)
    const out = typeof input.content_html === 'string' ? input.content_html : ''
    const err = validateChunk(text, out)
    if (!err) return out
    why = err
  }
  throw new TranslateError('invalid_output', `část ${part}: ${why}`)
}

/** Krátká pole (název / titulek / popis). Přeložený název shodný s českým = chyba (EDGE-DOC-13) → null. */
export async function translateMeta(fields: Record<string, string>, lang: string): Promise<Record<string, string | null>> {
  const props: Record<string, unknown> = {}
  for (const k of Object.keys(fields)) props[k] = { type: 'string', description: `Translated ${k} (${LANG_NAMES[lang] || lang}); empty string if the source is empty.` }
  const out: Record<string, string | null> = {}
  let todo = Object.keys(fields).filter((k) => fields[k].trim())
  for (const k of Object.keys(fields)) out[k] = fields[k].trim() ? null : ''
  for (let attempt = 1; attempt <= 2 && todo.length; attempt++) {
    const input = await callTool(systemPrompt(lang), [{ type: 'text', text: `Translate these short Czech document fields: ${JSON.stringify(fields)}` }], props, MAX_TOKENS_META)
    for (const k of todo) {
      const v = typeof input[k] === 'string' ? (input[k] as string).trim() : ''
      if (v && v !== fields[k].trim()) out[k] = v
    }
    todo = todo.filter((k) => out[k] === null)
  }
  return out
}

/** Část PDF (base64) → přeložené HTML. */
export async function translatePdfPart(pdfB64: string, lang: string, part: string): Promise<{ html: string; stop?: string }> {
  const input = await callTool(systemPrompt(lang), [
    { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdfB64 } },
    { type: 'text', text: `This PDF is part ${part} of a Czech document. Translate its full text into ${LANG_NAMES[lang] || lang} as clean semantic HTML (<h1>-<h3>, <p>, <ul>/<ol>/<li>, <table>; no inline styles, no <html>/<body>). Drop only repeated page headers/footers and page numbers.` },
  ], { content_html: { type: 'string', description: 'Translated document part as clean semantic HTML.' } }, MAX_TOKENS_PDF)
  return { html: typeof input.content_html === 'string' ? input.content_html : '' }
}

/** Paralelně s omezenou souběžností (rate-limit Anthropic), pořadí výsledků zachováno. */
export async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T, i: number) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length)
  let next = 0, failed = false // po první chybě se další části už neposílají (jazyk stejně neuložíme)
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (!failed && next < items.length) {
      const i = next++
      try { results[i] = await fn(items[i], i) } catch (e) { failed = true; throw e }
    }
  })
  await Promise.all(workers)
  return results
}
