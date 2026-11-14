// Výběr jazykové verze šablony (audit EDGE-DOC-01/02/08): překlad JEN čerstvý (otisk českého
// zdroje sedí — _shared/doc-i18n.ts). Jinak AKTUÁLNÍ závazný český text s upozorněním v jazyce
// zákazníka a na pozadí se vyžádá nový překlad (translate-document, service role, async). Žádný
// synchronní strojový překlad celého dokumentu při odesílání mailu (timeouty, useknutý text v cache).
import { bindingNoticeHtml, freshTemplateTranslation, hasTranslationSrc } from '../_shared/doc-i18n.ts';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
export async function pickContent(template, slug, lang) {
  const cz = String(template.content_html || template.html_content || '');
  const czName = String(template.name || slug);
  if (lang === 'cs') return {
    content: cz,
    title: czName,
    docLang: 'cs',
    mode: 'cs'
  };
  const fresh = await freshTemplateTranslation(template, lang);
  if (fresh) return {
    content: fresh.content,
    title: fresh.name || czName,
    docLang: lang,
    mode: 'fresh'
  };
  return {
    content: cz,
    title: czName,
    docLang: 'cs',
    mode: 'cs_binding'
  };
}
/** Upozornění „závazná je česká verze, překlad připravujeme“ na začátek těla dokumentu. */ export function applyNotice(html, lang) {
  const notice = bindingNoticeHtml(lang);
  if (!notice) return html;
  const m = /<body\b[^>]*>/i.exec(html);
  if (m) return html.slice(0, m.index + m[0].length) + notice + html.slice(m.index + m[0].length);
  return notice + html;
}
/** <html lang="cs"> plného dokumentu → jazyk přeloženého textu. */ export function setHtmlLang(html, lang) {
  return html.replace(/(<html\b[^>]*?\blang=)(["'])[^"']*\2/i, `$1$2${lang}$2`);
}
// Nejvýš jednou na šablonu + jazyk v rámci běhu workeru (opakované pokusy hlídá translate-document
// přes debug_log: max. 1 automatický pokus / 6 h).
const queued = new Set();
/** Na pozadí vyžádá překlad šablony do jazyka. Bez sloupce translation_src (SQL ještě nenasazené)
 *  NE — otisk by nešel uložit a překlad by se zbytečně opakoval s každým dokumentem. */ export function enqueueRetranslation(template, lang) {
  if (!template?.id || lang === 'cs' || !hasTranslationSrc(template) || !SUPABASE_URL || !SERVICE_KEY) return false;
  const key = `${template.id}:${lang}`;
  if (queued.has(key)) return false;
  queued.add(key);
  const job = (async ()=>{
    const ctrl = new AbortController();
    const timer = setTimeout(()=>ctrl.abort(), 15000);
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/translate-document`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${SERVICE_KEY}`,
          'apikey': SERVICE_KEY
        },
        body: JSON.stringify({
          table: 'document_templates',
          id: template.id,
          target_langs: [
            lang
          ],
          async: true,
          reason: 'generate-document'
        }),
        signal: ctrl.signal
      });
      await res.text().catch(()=>'');
    } catch (e) {
      console.warn('[generate-document] enqueue translate-document failed:', e.message);
    } finally{
      clearTimeout(timer);
    }
  })();
  if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) EdgeRuntime.waitUntil(job);
  return true;
}
