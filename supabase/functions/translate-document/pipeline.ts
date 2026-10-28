// Překlad jednoho dokumentu do jednoho jazyka — celé, nebo nic (useknutý / neplatný výstup se neuloží).
//   HTML (document_templates, custom_documents kind=html): části po ~9 tis. znaků (chunker.ts),
//        paralelně, každá ověřená (validate.ts), spojení ve stejném pořadí.
//   PDF  (custom_documents kind=pdf): rozdělení po PDF_PAGES stranách přes pdf-lib, paralelně,
//        každá část ověřená; český originál PDF zůstává.
//   Krátká pole (název / titulek / popis) zvlášť; jejich selhání obsah neshodí (jen chybí název).
import { PDFDocument } from 'npm:pdf-lib@1.17.1';
import { assemble, chunkHtml } from './chunker.ts';
import { mapLimit, translateChunk, translateMeta, translatePdfPart, TranslateError } from './claude.ts';
import { validatePdfPart } from './validate.ts';
const CONCURRENCY = 5;
const PDF_PAGES = 4;
function b64(bytes) {
  let bin = '';
  for(let i = 0; i < bytes.length; i += 0x8000)bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
async function translateHtml(html, lang) {
  const segs = chunkHtml(html);
  const chunks = segs.filter((s)=>s.chunk).map((s)=>s.chunk.text);
  const out = await mapLimit(chunks, CONCURRENCY, (text, i)=>translateChunk(text, lang, `${i + 1}/${chunks.length}`));
  return {
    html: assemble(segs, out),
    chunks: chunks.length
  };
}
async function translatePdf(bytes, lang) {
  let src = null;
  try {
    src = await PDFDocument.load(bytes, {
      ignoreEncryption: true
    });
  } catch (_) {
    src = null;
  }
  const pages = src ? src.getPageCount() : 0;
  const parts = [];
  if (!src || pages <= PDF_PAGES) parts.push(b64(bytes));
  else {
    for(let from = 0; from < pages; from += PDF_PAGES){
      const doc = await PDFDocument.create();
      const idx = Array.from({
        length: Math.min(PDF_PAGES, pages - from)
      }, (_, k)=>from + k);
      for (const p of (await doc.copyPages(src, idx)))doc.addPage(p);
      parts.push(b64(await doc.save()));
    }
  }
  const out = await mapLimit(parts, CONCURRENCY, async (part, i)=>{
    let why = '';
    for(let attempt = 1; attempt <= 2; attempt++){
      const { html } = await translatePdfPart(part, lang, `${i + 1}/${parts.length}`);
      why = validatePdfPart(html) || '';
      if (!why) return html;
    }
    throw new TranslateError('invalid_output', `PDF část ${i + 1}/${parts.length}: ${why}`);
  });
  return {
    html: out.join('\n'),
    chunks: parts.length
  };
}
export async function translateDoc(src, lang) {
  const warnings = [];
  const metaP = translateMeta(src.meta, lang).catch((e)=>{
    warnings.push('meta: ' + e.message);
    return {};
  });
  const bodyP = src.pdf ? translatePdf(src.pdf, lang) : src.html ? translateHtml(src.html, lang) : Promise.resolve({
    html: '',
    chunks: 0
  });
  const [metaRaw, body] = await Promise.all([
    metaP,
    bodyP
  ]);
  if (!body.html.trim()) throw new TranslateError('empty_output', 'prázdný překlad obsahu');
  const meta = {};
  for (const [k, v] of Object.entries(metaRaw)){
    if (typeof v === 'string') meta[k] = v;
    else warnings.push(`${k}: překlad chybí nebo je shodný s češtinou`);
  }
  return {
    content_html: body.html,
    meta,
    warnings,
    chunks: body.chunks
  };
}
