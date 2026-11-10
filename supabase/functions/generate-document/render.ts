// HTML dokumentu → kompletní stránka → PDF (PDFShift). Vyčleněno z index.ts.
const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || '';
/** HTML → PDF přes PDFShift API. Vrací Uint8Array nebo null při chybě / no key. */ export async function htmlToPdf(html) {
  if (!PDFSHIFT_API_KEY) return null;
  try {
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: {
        'X-API-Key': PDFSHIFT_API_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        source: html,
        format: 'A4',
        margin: '12mm',
        landscape: false,
        sandbox: false,
        use_print: false
      })
    });
    if (!res.ok) {
      console.warn('[htmlToPdf] PDFShift HTTP', res.status, await res.text().catch(()=>''));
      return null;
    }
    return new Uint8Array(await res.arrayBuffer());
  } catch (e) {
    console.warn('[htmlToPdf] PDFShift fetch failed:', e.message);
    return null;
  }
}
/** Velín RichTextEditor ukládá obsah jako fragment (<p>/<table>… bez <!DOCTYPE>). PDFShift potřebuje
 *  plný HTML dokument — fragment obalíme minimální stránkou (styly jako náhled RichTextEditoru).
 *  `lang` = jazyk TEXTU dokumentu (závazná česká verze = cs). */ export function wrapDocument(htmlContent, title, lang) {
  if (/^\s*(?:<!doctype|<html\b)/i.test(htmlContent)) return htmlContent;
  const t = String(title || '').replace(/[&<>"]/g, (c)=>({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;'
    })[c]);
  return `<!DOCTYPE html><html lang="${lang}"><head><meta charset="utf-8"><title>${t}</title><style>
body { margin: 0; padding: 24px; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 12px; line-height: 1.6; color: #0f1a14; background: #fff; }
p { margin: 0 0 10px; }
h1 { font-size: 1.8em; font-weight: 800; margin: 14px 0 8px; }
h2 { font-size: 1.45em; font-weight: 800; margin: 12px 0 6px; }
h3 { font-size: 1.2em; font-weight: 700; margin: 10px 0 6px; }
h4 { font-size: 1.05em; font-weight: 700; margin: 8px 0 4px; }
ul, ol { padding-left: 1.4em; margin: 0 0 10px; }
li { margin: 2px 0; }
blockquote { margin: 8px 0; padding: 8px 12px; border-left: 4px solid #74FB71; background: #f1faf7; color: #1a2e22; border-radius: 4px; }
a { color: #1d4ed8; text-decoration: underline; }
img { max-width: 100%; height: auto; }
hr { border: none; border-top: 1px solid #d4e8e0; margin: 12px 0; }
table { border-collapse: collapse; }
table td, table th { border: 1px solid #d4e8e0; padding: 4px 8px; }
</style></head><body>${htmlContent}</body></html>`;
}
