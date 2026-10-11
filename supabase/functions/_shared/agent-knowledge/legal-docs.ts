// ===== _shared/agent-knowledge/legal-docs.ts =====
// Smluvní a právní dokumenty pro AI agenty (audit i18n 2026-10-10, AI-01/AI-08).
// Zdroj pravdy = ČESKÝ master (document_templates.content_html). Uložené překlady
// (content_translations) byly stará právní verze (spoluúčast 30 000 Kč místo 0 Kč) →
// překlad se použije JEN když je ČERSTVÝ: translation_src[lang] == sha1(zdroj), kde zdroj =
// document_templates: content_html; custom_documents: coalesce(content_html,'')||'|'||coalesce(pdf_path,'')
// (stejné pravidlo jako RPC get_document_translation, migrace 20261011_i18n_customer_language;
// implementace v ../doc-i18n.ts).
// Bez sloupce translation_src (před migrací) = žádný otisk = zastaralé → jen čeština.
// Čteme select('*'), aby chybějící sloupec neshodil dotaz (PostgREST 42703).

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { normLang, siteUrl, TEMPLATE_DOC_SLUG } from './site-url.ts'
import { stripHtmlToText } from './knowledge-base.ts'
// Pravidlo čerstvosti sdílí generate-document, web i appka (EDGE-DOC-02) — jedna implementace.
import { freshCustomTranslation, freshTemplateTranslation } from '../doc-i18n.ts'

type Row = Record<string, unknown>

type Doc = { key: string; title: string; text: string; translation?: string; kind: string; url?: string; pdf_url?: string }

async function loadDocs(sb: SupabaseClient, lang: string): Promise<Doc[]> {
  const L = normLang(lang)
  const [{ data: tpls }, { data: customs }] = await Promise.all([
    sb.from('document_templates').select('*').eq('active', true).order('version', { ascending: false }),
    sb.from('custom_documents').select('*').eq('active', true).eq('show_on_web', true).order('sort_order', { ascending: true }),
  ])
  const docs: Doc[] = []
  const seen = new Set<string>()
  for (const t of (tpls || []) as Row[]) {
    const key = String(t.type || '')
    if (!key || seen.has(key)) continue // jen nejvyšší aktivní verze (order desc)
    seen.add(key)
    const tr = await freshTemplateTranslation(t, L) // {content, name} jen když čerstvý, jinak null
    const slug = TEMPLATE_DOC_SLUG[key]
    docs.push({
      key, title: String(tr?.name || t.name || key), kind: 'html',
      text: stripHtmlToText(String(t.content_html || '')),
      ...(tr?.content ? { translation: stripHtmlToText(tr.content) } : {}),
      ...(slug ? { url: siteUrl(L, `/dokumenty/${slug}`) } : {}),
    })
  }
  for (const c of (customs || []) as Row[]) {
    const key = String(c.slug || '')
    if (!key || seen.has(key)) continue
    seen.add(key)
    const tr = await freshCustomTranslation(c, L)
    docs.push({
      // Název nenese právní fakta → přeložený titulek smí i bez čerstvého otisku (obsah ne).
      key, title: String(tr?.title || (L !== 'cs' && (c.translations as Record<string, { title?: string }> | null)?.[L]?.title) || c.title || key), kind: String(c.kind || 'html'),
      text: stripHtmlToText(String(c.content_html || '')),
      ...(tr?.content_html ? { translation: stripHtmlToText(tr.content_html) } : {}),
      url: siteUrl(L, `/dokumenty/${key}`),
      ...(c.pdf_path ? { pdf_url: String(c.pdf_path) } : {}),
    })
  }
  return docs
}

const BINDING = 'ZÁVAZNÉ je české znění (`text`). Částky, odpovědnost/spoluúčast, lhůty a čísla článků ber jen z něj; zákazníkovi odpověz v JEHO jazyce, uveď článek a že závazná je česká verze. `translation` (je-li) = ověřený aktuální překlad jen pro formulaci. Odkaz = `url` (web v jazyce zákazníka).'

/** Implementace toolu get_legal_document (web agent i agent v appce). */
export async function getLegalDocument(sb: SupabaseClient, args: Record<string, unknown>, lang: string): Promise<unknown> {
  try {
    const want = typeof args.document === 'string' ? String(args.document).trim().toLowerCase() : ''
    const query = typeof args.query === 'string' ? String(args.query).trim() : ''
    const MAX = 12000
    const docs = await loadDocs(sb, lang)
    if (docs.length === 0) {
      return {
        source: 'empty', documents: [],
        notice: 'V systému nejsou publikované žádné smluvní dokumenty. NEPŘEBÍREJ smluvní detaily z hlavy — řekni, že přesné znění zákazník dostane ve smlouvě/VOP před vyzvednutím, nebo odkaž na kontakt firmy (telefon/e-mail viz KONTAKTY v promptu).',
      }
    }
    if (!want) {
      return {
        source: 'documents', binding_language: 'cs',
        available: docs.map((d) => ({ key: d.key, title: d.title, kind: d.kind, has_text: d.text.length > 0, url: d.url, pdf_url: d.pdf_url })),
        hint: 'Zavolej znovu s parametrem `document` = jeden z těchto `key` (a volitelně `query`), ať dostaneš znění. Cituj jen to, co tool vrátí.',
      }
    }
    const match = docs.find((d) => d.key.toLowerCase() === want)
      || docs.find((d) => d.key.toLowerCase().includes(want) || d.title.toLowerCase().includes(want))
    if (!match) return { source: 'documents', error: `Dokument "${want}" nenalezen.`, available: docs.map((d) => ({ key: d.key, title: d.title })) }
    const head = { source: 'documents', key: match.key, title: match.title, kind: match.kind, url: match.url, pdf_url: match.pdf_url, binding_language: 'cs' }
    if (!match.text) {
      return { ...head, notice: 'Česká (závazná) verze dokumentu je jen jako PDF — strojový text k citaci nemám. Konkrétní ujednání necituj; odkaž zákazníka na `url` / `pdf_url` nebo na kontakt.' }
    }
    if (query) {
      const text = match.text
      const lc = text.toLowerCase()
      const terms = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3)
      const hits: number[] = []
      for (const term of terms) {
        for (let from = 0; ;) {
          const i = lc.indexOf(term, from)
          if (i < 0 || hits.length > 40) break
          hits.push(i); from = i + term.length
        }
      }
      if (hits.length > 0) {
        hits.sort((a, b) => a - b)
        const win: Array<[number, number]> = []
        for (const i of hits) {
          const s = Math.max(0, i - 400), e = Math.min(text.length, i + 400)
          const last = win[win.length - 1]
          if (last && s <= last[1]) last[1] = Math.max(last[1], e)
          else win.push([s, e])
        }
        let excerpt = win.map(([s, e]) => (s > 0 ? '…' : '') + text.slice(s, e).trim() + (e < text.length ? '…' : '')).join('\n\n———\n\n')
        if (excerpt.length > MAX) excerpt = excerpt.slice(0, MAX) + '…'
        return { ...head, mode: 'excerpts', query, text: excerpt, instruction: `Odpověz výhradně z tohoto znění. Pokud konkrétní odpověď v úryvcích NENÍ, přiznej to a odkaž na plný text / kontakt — nedomýšlej. Dotazuj se česky (dokument je česky). ${BINDING}` }
      }
      // query nic nenašlo → plný (zkrácený) text, ať rozhodne model
    }
    const cut = (s: string, n: number) => s.length > n ? s.slice(0, n) + '\n…[zkráceno — plné znění na webu]' : s
    return {
      ...head, mode: 'full', text: cut(match.text, MAX),
      ...(match.translation ? { translation: cut(match.translation, 8000) } : {}),
      instruction: `Cituj a parafrázuj VÝHRADNĚ z tohoto znění. Co tu výslovně není, si nedomýšlej — přiznej, že to dokument neuvádí, a odkaž na kontakt. ${BINDING}`,
    }
  } catch (e) {
    return { error: `Nepodařilo se načíst dokumenty: ${(e as Error).message}` }
  }
}
