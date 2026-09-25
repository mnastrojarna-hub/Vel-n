// ===== _shared/agent-knowledge/knowledge-base.ts =====
// Přesunuto z ai-public-agent/index.ts (2026-09-25) beze změny obsahu — sdílí ho
// veřejný agent (web) i agent zákaznických zpráv ve Velínu (ai-customer-messages-suggest).

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Znalostní báze — přednačtená do „paměti" agenta (do system promptu)
// ============================================================================
// Agent musí mít KOMPLETNÍ FAQ + VOP + nájemní smlouvu + předávací protokol + GDPR + podmínky
// v kontextu od první zprávy — ne je jen dohledávat tooly. Tooly zůstávají na ŽIVÁ/dynamická data
// (dostupnost, cena, návody, ověření identity). Tohle je statický ZÁKLAD.
// Typ paměti: module-level cache s TTL. Edge isolate ji sdílí mezi requesty, takže se DB nehamruje
// ("načteno po zapnutí, periodicky aktualizováno"). Změny textů v CMS se projeví po vypršení TTL
// (max pár minut) nebo po studeném startu isolate.
// Verzovaná invalidace: Velín po každé změně FAQ/dokumentů/podmínek bumpne
// `app_settings.ai_kb_version` (helper `bumpKbVersion` v velin/src/lib/webCache.js).
// Při každé zprávě porovnáme tuto verzi proti té, se kterou byla KB postavena, a
// když se liší, načteme bázi znovu HNED (ne až po TTL). TTL zůstává jako pojistka
// (když verze chybí / bump selže / změní se dokumenty bez bumpu) — bez verze se
// chová přesně jako dřív (zpětně kompatibilní).
const KB_TTL_MS = 5 * 60 * 1000
let kbCache: { at: number; ver: string; byLang: Record<string, string> } | null = null

// Lehké čtení verze znalostní báze (1 řádek z app_settings dle PK). Prázdný
// řetězec = klíč není nastaven nebo DB nedostupná → fallback na čisté TTL chování.
async function loadKbVersion(sb: SupabaseClient): Promise<string> {
  try {
    const { data } = await sb.from('app_settings').select('value').eq('key', 'ai_kb_version').maybeSingle()
    return data?.value != null ? String(data.value) : ''
  } catch {
    return ''
  }
}

export function stripHtmlToText(html: string): string {
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

export async function loadKnowledgeBase(sb: SupabaseClient, lang: string): Promise<string> {
  const L = (lang || 'cs').slice(0, 2)
  const ver = await loadKbVersion(sb)
  if (kbCache && kbCache.ver === ver && (Date.now() - kbCache.at) < KB_TTL_MS && typeof kbCache.byLang[L] === 'string') {
    return kbCache.byLang[L]
  }
  let faqBlock = '', legalBlock = '', policiesBlock = ''
  try {
    const [faqRes, tplRes, polRes] = await Promise.all([
      sb.from('faq_items')
        .select('category_key, category_label, question, answer, translations, sort_order')
        .eq('published', true)
        .order('category_key', { ascending: true }).order('sort_order', { ascending: true }),
      sb.from('document_templates')
        .select('type, name, content_html, content_translations, name_translations')
        .eq('active', true).order('version', { ascending: false }),
      sb.from('app_settings').select('value').eq('key', 'site.policies').maybeSingle(),
    ])

    // FAQ — KOMPLETNÍ (jen published), lokalizované
    const faqs: string[] = []
    for (const r of (faqRes.data || []) as Record<string, unknown>[]) {
      const tr = (r.translations as Record<string, { question?: string; answer?: string; category_label?: string }> | null)?.[L] || {}
      const q = stripHtmlToText((L !== 'cs' && tr.question) ? tr.question : String(r.question || ''))
      const a = stripHtmlToText((L !== 'cs' && tr.answer) ? tr.answer : String(r.answer || ''))
      const cat = (L !== 'cs' && tr.category_label) ? tr.category_label : String(r.category_label || r.category_key || '')
      if (q && a) faqs.push(`• [${cat}] ${q}\n  ${a}`)
    }
    if (faqs.length) faqBlock = `ČASTÉ DOTAZY (FAQ) — KOMPLETNÍ, ${faqs.length} položek:\n${faqs.join('\n')}`

    // Smluvní/právní dokumenty — VOP, nájemní smlouva, předávací protokol, GDPR (nejvyšší aktivní verze)
    const WANT = new Set(['vop', 'rental_contract', 'handover_protocol', 'gdpr'])
    const seen = new Set<string>()
    const docs: string[] = []
    const PER_DOC = 16000
    for (const t of (tplRes.data || []) as Record<string, unknown>[]) {
      const key = String(t.type || '')
      if (!WANT.has(key) || seen.has(key)) continue
      seen.add(key)
      const ct = (t.content_translations as Record<string, string> | null)?.[L]
      const nt = (t.name_translations as Record<string, string> | null)?.[L]
      const title = String((L !== 'cs' && nt) || t.name || key)
      let text = stripHtmlToText((L !== 'cs' && ct) ? ct : String(t.content_html || ''))
      if (!text) continue
      let note = ''
      if (text.length > PER_DOC) { text = text.slice(0, PER_DOC); note = `\n  […zkráceno — doslovné úplné znění získáš přes get_legal_document(document='${key}')]` }
      docs.push(`### ${title} (klíč: ${key})\n${text}${note}`)
    }
    if (docs.length) legalBlock = `OFICIÁLNÍ SMLUVNÍ A PRÁVNÍ DOKUMENTY — PŘESNÉ ZNĚNÍ:\n${docs.join('\n\n')}`

    // Strukturované podmínky půjčovny (site.policies)
    const pol = (polRes.data?.value as Record<string, unknown>) || {}
    if (pol && Object.keys(pol).length) policiesBlock = `OFICIÁLNÍ PODMÍNKY PŮJČOVNY (strukturované):\n${JSON.stringify(pol, null, 1)}`
  } catch (e) {
    console.error('loadKnowledgeBase failed:', (e as Error).message)
  }

  const sections = [faqBlock, policiesBlock, legalBlock].filter(Boolean)
  const built = sections.length
    ? `ZNALOSTNÍ BÁZE (NAČTENA DO PAMĚTI — máš ji k dispozici od první zprávy, je to TVŮJ ZÁKLAD; tooly používej jen na živá/dynamická data nad rámec tohoto):\n\n${sections.join('\n\n')}`
    : '' // prázdné = DB nedostupná nebo nic publikováno; ošetří pravidla + tooly
  // Nový snapshot když cache chybí, vypršela, nebo se změnila verze KB (Velín
  // bumpnul ai_kb_version). Jinak jen doplníme jazyk do existujícího snapshotu.
  if (!kbCache || kbCache.ver !== ver || (Date.now() - kbCache.at) >= KB_TTL_MS) kbCache = { at: Date.now(), ver, byLang: {} }
  kbCache.byLang[L] = built
  return built
}
