// Sdílený překlad DB e-mailových šablon (send-booking-email, send-cancellation-email,
// send-invoice-email, send-email) — dřív 4 kopie, které se rozešly (uk jen v send-email).
// Velín edituje jen CZ; pro jiný jazyk se šablona přeloží (Haiku) a zacachuje do
// email_templates.{subject,body}_translations[lang] + otisk zdroje `__src_<lang>`.
// Audit 2026-10-10 (EDGE-DOC-11/12):
//  - otisk obsahuje verzi promptu + model → změna promptu přeloží šablony znovu (staré uk
//    překlady vznikly s promptem „Output language: uk (uk)“);
//  - tool-forced výstup, max_tokens 8192, useknutý výstup (stop_reason max_tokens) / odmítnutí /
//    změněné {{placeholdery}} se NEuloží;
//  - zápis cache sloučí jen vlastní jazyk do čerstvě načteného řádku (souběžné jazyky se nepřepíšou);
//  - když zákazník dostane češtinu místo svého jazyka → debug_log `email_translation_fallback`.

import { samePlaceholders, sha1Hex } from './doc-i18n.ts'

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
export const EMAIL_TRANSLATE_MODEL = 'claude-haiku-4-5-20251001'
export const EMAIL_TR_VERSION = 'v2'

export const EMAIL_LANG_NAMES: Record<string, string> = {
  en: 'English', de: 'German (Deutsch)', es: 'Spanish (Español)', fr: 'French (Français)',
  nl: 'Dutch (Nederlands)', pl: 'Polish (Polski)', uk: 'Ukrainian (Українська, uk-UA — NOT British English)',
}
/** Patička mailu „Sledujte nás“ (všech 8 jazyků). */
export const FOLLOW_US_LABELS: Record<string, string> = {
  cs: 'SLEDUJTE NÁS', en: 'FOLLOW US', de: 'FOLGEN SIE UNS', nl: 'VOLG ONS',
  es: 'SÍGUENOS', fr: 'SUIVEZ-NOUS', pl: 'OBSERWUJ NAS', uk: 'СТЕЖТЕ ЗА НАМИ',
}
/** Podnadpis loga v hlavičce mailu (dřív natvrdo „PŮJČOVNA MOTOREK“ ve všech jazycích). */
export const BRAND_TAGLINE: Record<string, string> = {
  cs: 'PŮJČOVNA MOTOREK', en: 'MOTORCYCLE RENTAL', de: 'MOTORRADVERLEIH', nl: 'MOTORVERHUUR',
  es: 'ALQUILER DE MOTOS', fr: 'LOCATION DE MOTOS', pl: 'WYPOŻYCZALNIA MOTOCYKLI', uk: 'ПРОКАТ МОТОЦИКЛІВ',
}
export function pickLang<T>(map: Record<string, T>, lang: string): T {
  return map[lang] ?? map.cs
}

export function emailSrcHash(subjectCz: string, bodyCz: string): Promise<string> {
  return sha1Hex(`${EMAIL_TR_VERSION}|${EMAIL_TRANSLATE_MODEL}|${subjectCz}\n${bodyCz}`)
}

/** Přeloží RAW šablonu (před dosazením proměnných → cache nezávislá na rezervaci). null = selhání. */
export async function translateEmailTemplate(subjectCz: string, bodyCz: string, lang: string): Promise<{ subject: string; body: string } | null> {
  if (!ANTHROPIC_API_KEY || !EMAIL_LANG_NAMES[lang]) return null
  const name = EMAIL_LANG_NAMES[lang]
  const system = [
    `You are a professional Czech-to-${name} translator for MotoGo24, a Czech motorcycle rental company.`,
    `Translate the e-mail subject and HTML body into ${name} (${lang}): natural, native, fluent, complete.`,
    '- Preserve ALL HTML tags, attributes, inline styles and structure EXACTLY.',
    '- Keep ALL template placeholders like {{booking_number}}, {{customer_name}}, {{door_codes_block}} EXACTLY unchanged.',
    '- Do not change URLs, e-mail addresses, phone numbers, prices, IČO, DIČ or brand names. Keep "MotoGo24" and currency "Kč" as is.',
    '- Call the submit_translation tool with the result.',
  ].join('\n')
  const tool = {
    name: 'submit_translation', description: 'Submit the translated e-mail.',
    input_schema: { type: 'object', properties: { subject: { type: 'string' }, body: { type: 'string' } }, required: ['subject', 'body'] },
  }
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({
          model: EMAIL_TRANSLATE_MODEL, max_tokens: 8192, system, tools: [tool], tool_choice: { type: 'tool', name: 'submit_translation' },
          messages: [{ role: 'user', content: `Czech source JSON: ${JSON.stringify({ subject: subjectCz, body: bodyCz })}` }],
        }),
      })
      if (!res.ok) {
        console.warn('[translateEmailTemplate] anthropic', res.status)
        if (res.status === 429 || res.status >= 500) { await new Promise((r) => setTimeout(r, 2000)); continue }
        return null
      }
      const data = await res.json()
      const stop = String(data?.stop_reason || '')
      if (stop === 'max_tokens' || stop === 'refusal') { console.warn('[translateEmailTemplate] stop_reason', stop); return null }
      const tu = Array.isArray(data?.content) ? data.content.find((c: { type?: string; name?: string }) => c?.type === 'tool_use' && c?.name === 'submit_translation') : null
      const subject = typeof tu?.input?.subject === 'string' ? tu.input.subject : ''
      const body = typeof tu?.input?.body === 'string' ? tu.input.body : ''
      if (body.trim() && (subject.trim() || !subjectCz.trim()) && samePlaceholders(subjectCz, subject) && samePlaceholders(bodyCz, body)) {
        return { subject: subject || subjectCz, body }
      }
      console.warn('[translateEmailTemplate] invalid output (empty / placeholders changed), attempt', attempt)
    } catch (e) { console.warn('[translateEmailTemplate]', (e as Error).message) }
  }
  return null
}

// deno-lint-ignore no-explicit-any
type Db = any
export interface EmailTpl { slug: string; subject: string | null; body_html: string; subject_translations?: unknown; body_translations?: unknown }

/** cs → CZ originál; jinak čerstvý cache překlad, nebo překlad přes API + cache. Selhání → CZ (mail vždy odejde). */
export async function resolveTemplateForLang(supabase: Db, tpl: EmailTpl, lang: string, source = 'email'): Promise<{ subject: string; body: string }> {
  const subjCz = tpl.subject || ''
  const bodyCz = tpl.body_html || ''
  if (lang === 'cs' || !EMAIL_LANG_NAMES[lang]) return { subject: subjCz, body: bodyCz }
  const obj = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? { ...(v as Record<string, string>) } : {}) as Record<string, string>
  const subjT = obj(tpl.subject_translations), bodyT = obj(tpl.body_translations)
  const srcHash = await emailSrcHash(subjCz, bodyCz)
  if (bodyT['__src_' + lang] === srcHash && typeof bodyT[lang] === 'string' && bodyT[lang]) {
    return { subject: (typeof subjT[lang] === 'string' && subjT[lang]) ? subjT[lang] : subjCz, body: bodyT[lang] }
  }
  const tr = await translateEmailTemplate(subjCz, bodyCz, lang)
  if (!tr) {
    try {
      await supabase.from('debug_log').insert({ source, action: 'email_translation_fallback', component: 'edge-function', status: 'warning',
        request_data: { slug: tpl.slug, lang }, error_message: 'translation failed — Czech template sent' })
    } catch { /* jen log */ }
    return { subject: subjCz, body: bodyCz }
  }
  try { // čerstvý řádek → sloučit jen vlastní jazyk (souběžné překlady jiných jazyků zůstanou)
    const { data: cur } = await supabase.from('email_templates').select('subject_translations, body_translations').eq('slug', tpl.slug).maybeSingle()
    const s2 = obj(cur?.subject_translations ?? subjT), b2 = obj(cur?.body_translations ?? bodyT)
    s2[lang] = tr.subject; s2['__src_' + lang] = srcHash
    b2[lang] = tr.body; b2['__src_' + lang] = srcHash
    await supabase.from('email_templates').update({ subject_translations: s2, body_translations: b2 }).eq('slug', tpl.slug)
  } catch { /* cache best-effort */ }
  return tr
}
