// Sdílená i18n pravidla smluvních dokumentů (VOP, smlouva, GDPR, protokoly, vlastní dokumenty).
// Audit 2026-10-10 (EDGE-DOC-02): překlad smí být použit JEN když je ČERSTVÝ — vznikl z aktuálního
// českého zdroje. Otisk zdroje drží sloupec `translation_src` = {"<lang>": "<sha1 hex>"} (migrace
// 20261011_i18n_customer_language.sql):
//   document_templates: sha1(content_html)
//   custom_documents:   sha1(coalesce(content_html,'') || '|' || coalesce(pdf_path,''))
// Shodně počítá SQL get_document_translation (encode(digest(convert_to(…,'UTF8'),'sha1'),'hex'))
// i web (PHP sha1()). Chybí-li sloupec (SQL ještě nenasazené) nebo otisk nesedí → překlad je
// ZASTARALÝ a nikde se nepoužije; místo něj závazná česká verze s upozorněním (BINDING_NOTICE).

export const DOC_LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] as const
export type DocLang = typeof DOC_LANGS[number]
/** Cílové jazyky překladu (vše kromě češtiny = zdroj). */
export const DOC_TARGET_LANGS: DocLang[] = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']

export function isDocLang(l: unknown): l is DocLang {
  return typeof l === 'string' && (DOC_LANGS as readonly string[]).includes(l)
}
/** 'en-GB' / 'EN' / 'uk_UA' → 'en' / 'uk'; nepodporované / prázdné → null. */
export function parseDocLang(l: unknown): DocLang | null {
  const s = String(l ?? '').trim().toLowerCase().slice(0, 2)
  return isDocLang(s) ? s : null
}
export function normDocLang(l: unknown): DocLang {
  return parseDocLang(l) ?? 'cs'
}

/** SHA-1 hex UTF-8 řetězce (= PHP sha1(), SQL encode(digest(convert_to(s,'UTF8'),'sha1'),'hex')). */
export async function sha1Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('')
}
export function srcHashTemplate(contentHtml: unknown): Promise<string> {
  return sha1Hex(typeof contentHtml === 'string' ? contentHtml : '')
}
export function srcHashCustom(contentHtml: unknown, pdfPath: unknown): Promise<string> {
  const c = typeof contentHtml === 'string' ? contentHtml : ''
  const p = typeof pdfPath === 'string' ? pdfPath : ''
  return sha1Hex(`${c}|${p}`)
}

function rec(v: unknown): Record<string, unknown> {
  return v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {}
}
/** Má řádek sloupec translation_src? (před nasazením SQL ne → otisk nelze ani uložit). */
export function hasTranslationSrc(row: unknown): boolean {
  return !!row && typeof row === 'object' && Object.prototype.hasOwnProperty.call(row, 'translation_src')
}

/** Čerstvý překlad šablony document_templates, jinak null (cs → null: český originál). Název jen
 *  přeložený (≠ český název — EDGE-DOC-13: v DB leží české „překlady“ názvů), jinak null. */
export async function freshTemplateTranslation(row: Record<string, unknown> | null | undefined, lang: string): Promise<{ content: string; name: string | null } | null> {
  if (!row || lang === 'cs' || !isDocLang(lang)) return null
  const content = rec(row.content_translations)[lang]
  if (typeof content !== 'string' || !content.trim()) return null
  const src = rec(row.translation_src)[lang]
  if (typeof src !== 'string' || src !== await srcHashTemplate(row.content_html)) return null
  const nt = rec(row.name_translations)[lang]
  const name = typeof nt === 'string' && nt.trim() && nt.trim() !== String(row.name ?? '').trim() ? nt.trim() : null
  return { content, name }
}

/** Čerstvý překlad vlastního dokumentu custom_documents ({title, description, content_html}), jinak null. */
export async function freshCustomTranslation(row: Record<string, unknown> | null | undefined, lang: string): Promise<Record<string, string> | null> {
  if (!row || lang === 'cs' || !isDocLang(lang)) return null
  const tr = rec(rec(row.translations)[lang])
  if (typeof tr.content_html !== 'string' || !tr.content_html.trim()) return null
  const src = rec(row.translation_src)[lang]
  if (typeof src !== 'string' || src !== await srcHashCustom(row.content_html, row.pdf_path)) return null
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(tr)) if (typeof v === 'string') out[k] = v
  return out
}

/** Upozornění nad závazným českým textem, když čerstvý překlad chybí (EDGE-DOC-01/08). */
export const BINDING_NOTICE: Record<DocLang, { title: string; body: string }> = {
  cs: { title: 'Závazná česká verze', body: 'Tento dokument je k dispozici v češtině, která je právně závazným zněním. Překlad do vašeho jazyka připravujeme.' },
  en: { title: 'Binding Czech version', body: 'This document is provided in Czech, which is the legally binding version. A translation into English is being prepared and will be available soon. If anything is unclear, write to us at info@motogo24.cz.' },
  de: { title: 'Verbindliche tschechische Fassung', body: 'Dieses Dokument liegt auf Tschechisch vor; die tschechische Fassung ist rechtlich verbindlich. Eine Übersetzung ins Deutsche wird vorbereitet und ist in Kürze verfügbar. Bei Fragen schreiben Sie uns an info@motogo24.cz.' },
  es: { title: 'Versión checa vinculante', body: 'Este documento se facilita en checo, que es la versión jurídicamente vinculante. Estamos preparando la traducción al español, que estará disponible en breve. Si tiene alguna duda, escríbanos a info@motogo24.cz.' },
  fr: { title: 'Version tchèque faisant foi', body: 'Ce document est fourni en tchèque, version qui fait foi juridiquement. Une traduction en français est en cours de préparation et sera bientôt disponible. Pour toute question, écrivez-nous à info@motogo24.cz.' },
  nl: { title: 'Bindende Tsjechische versie', body: 'Dit document wordt in het Tsjechisch verstrekt; de Tsjechische versie is juridisch bindend. Een Nederlandse vertaling wordt voorbereid en is binnenkort beschikbaar. Vragen? Mail ons via info@motogo24.cz.' },
  pl: { title: 'Wiążąca wersja czeska', body: 'Niniejszy dokument jest udostępniony w języku czeskim, który stanowi wersję prawnie wiążącą. Tłumaczenie na język polski jest w przygotowaniu i wkrótce będzie dostępne. W razie pytań napisz do nas na info@motogo24.cz.' },
  uk: { title: 'Обов’язкова чеська версія', body: 'Цей документ надано чеською мовою — саме чеська версія є юридично обов’язковою. Переклад українською мовою готується і незабаром буде доступний. Якщо маєте запитання, напишіть нам на info@motogo24.cz.' },
}

/** HTML blok upozornění (vkládá se na začátek dokumentu, lang= jazyk zákazníka). cs → ''. */
export function bindingNoticeHtml(lang: string): string {
  if (!isDocLang(lang) || lang === 'cs') return ''
  const n = BINDING_NOTICE[lang]
  return `<div lang="${lang}" style="margin:0 0 16px;padding:12px 14px;border:1px solid #f59e0b;background:#fffbeb;border-radius:6px;font-family:'Segoe UI',system-ui,sans-serif;font-size:12px;line-height:1.5;color:#78350f"><strong>${n.title}</strong><br>${n.body}</div>`
}

/** Placeholdery šablon ({{var}}, {var}, %s) jako seřazený seznam — kontrola, že je překlad zachoval.
 *  Porovnává se PŘESNÝ zápis: dosazení (generate-document, send-*) hledá doslova `{{var}}`, takže
 *  `{{ var }}` z překladu by zůstal v dokumentu / mailu nevyplněný (resp. by se vymazal). */
export function placeholderList(s: string): string[] {
  return (String(s || '').match(/\{\{\s*[A-Za-z0-9_.]+\s*\}\}|\{[A-Za-z0-9_]+\}|%s/g) || []).sort()
}
export function samePlaceholders(a: string, b: string): boolean {
  const x = placeholderList(a), y = placeholderList(b)
  return x.length === y.length && x.every((v, i) => v === y[i])
}
