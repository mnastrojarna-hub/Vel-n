/**
 * MotoGo24 — Edge Function: translate-document
 *
 * Překlad celých dokumentů (Velín → Dokumenty) do 7 jazyků (en, de, es, fr, nl, pl, uk) přes
 * Anthropic Claude API:
 *   - smluvní šablony `document_templates` (VOP, smlouva, GDPR, protokoly) — obsah i název,
 *     {placeholder} proměnné zůstávají nepřeložené;
 *   - vlastní dokumenty `custom_documents` typu `html` (RTE) i `pdf` (PDF → přeložené HTML,
 *     český originál PDF zůstává) — obsah, titulek i popis.
 *
 * Audit 2026-10-10 (EDGE-DOC-02/08/13/14/17/18):
 *   - dlouhé HTML se překládá po částech (~9 tis. znaků, hranice bloků — chunker.ts), PDF po 4 stranách;
 *     každá část se ověří (stop_reason ≠ max_tokens/refusal, stejné placeholdery, značky, vyvážené tagy,
 *     stejný počet odstavců/řádků, stejné částky Kč / %, rozumná délka — validate.ts); useknutý nebo
 *     neplatný překlad jazyka se NEULOŽÍ (celé, nebo nic);
 *   - s překladem se uloží otisk českého zdroje `translation_src[lang]` (_shared/doc-i18n.ts) —
 *     překlad bez shodného otisku je zastaralý a nikde se nepoužije;
 *   - název shodný s českým se jako „překlad“ neukládá (dřívější české name_translations se smažou);
 *   - glosář pojmů (kukla = balaclava …); jen service_role nebo účet Velína (admin_users).
 *
 * POST /functions/v1/translate-document
 * Body: { table: 'custom_documents' | 'document_templates', id, target_langs? | languages?,
 *         force?: boolean  — přeložit i jazyk s čerstvým překladem (jinak se čerstvý přeskočí),
 *         async?: boolean  — jen service_role: odpověď 202 hned, překlad na pozadí (generate-document),
 *                            s pojistkou max. 1 automatický pokus / dokument / jazyk / 6 h,
 *         reason?: string }
 * Odpověď: { success, translations: {lang: {...}}, errors?, warnings?, skipped?: string[], src_saved? }
 * (translations[lang] je i u přeskočeného čerstvého jazyka — Velín bere jako úspěch.)
 */ import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { authClassify } from '../_shared/auth.ts';
import { DOC_TARGET_LANGS, freshCustomTranslation, freshTemplateTranslation, hasTranslationSrc, srcHashCustom, srcHashTemplate } from '../_shared/doc-i18n.ts';
import { MODEL } from './claude.ts';
import { translateDoc } from './pipeline.ts';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || '';
const ALL_ADMIN_ROLES = [
  'superadmin',
  'manager',
  'operator',
  'viewer',
  'admin'
];
const AUTO_THROTTLE_MS = 6 * 3600_000;
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS,
      'Content-Type': 'application/json'
    }
  });
}
async function log(admin, action, status, request, response, err, ms) {
  try {
    await admin.from('debug_log').insert({
      source: 'translate-document',
      action,
      component: 'edge-function',
      status,
      request_data: request,
      response_data: response,
      error_message: err,
      duration_ms: ms != null ? Math.round(ms) : null
    });
  } catch  {}
}
async function buildSource(admin, table, row) {
  if (table === 'document_templates') return {
    meta: {
      name: String(row.name || '')
    },
    html: String(row.content_html || '')
  };
  const meta = {
    title: String(row.title || ''),
    description: String(row.description || '')
  };
  if (String(row.kind || 'html') !== 'pdf') return {
    meta,
    html: String(row.content_html || '')
  };
  const pdfPath = String(row.pdf_path || '');
  const m = pdfPath.match(/\/object\/public\/media\/(.+)$/) // veřejná URL bucketu media → cesta
  ;
  if (!m) throw new Error('PDF path není v bucketu media nebo má neočekávaný formát: ' + pdfPath);
  const { data: blob, error } = await admin.storage.from('media').download(decodeURIComponent(m[1]));
  if (error || !blob) throw new Error('Stažení PDF z storage selhalo: ' + (error?.message || 'no data'));
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (bytes.length > 20 * 1024 * 1024) throw new Error('PDF je příliš velké pro překlad (max 20 MB).');
  return {
    meta,
    pdf: bytes
  };
}
/** Uloží přeložené jazyky: znovu načte řádek (souběžné překlady jiných jazyků se nepřepíšou) a sloučí. */ async function save(admin, table, id, done, srcHash) {
  const { data: cur, error: rErr } = await admin.from(table).select('*').eq('id', id).maybeSingle();
  if (rErr || !cur) return {
    ok: false,
    srcSaved: false,
    error: 'DB read failed: ' + (rErr?.message || 'row gone')
  };
  const obj = (v)=>v && typeof v === 'object' && !Array.isArray(v) ? {
      ...v
    } : {};
  const src = obj(cur.translation_src);
  const payload = {};
  if (table === 'document_templates') {
    const ct = obj(cur.content_translations), nt = obj(cur.name_translations);
    for (const [lang, r] of Object.entries(done)){
      ct[lang] = r.content_html;
      // Nový název; když překlad názvu selhal, zůstane dosavadní — jen český „překlad“ názvu pryč (EDGE-DOC-13).
      if (r.meta.name) nt[lang] = r.meta.name;
      else if (String(nt[lang] ?? '').trim() === String(cur.name ?? '').trim()) delete nt[lang];
      src[lang] = srcHash;
    }
    payload.content_translations = ct;
    payload.name_translations = nt;
  } else {
    const tr = obj(cur.translations);
    for (const [lang, r] of Object.entries(done)){
      // Selhal-li překlad titulku/popisu, zůstane dosavadní přeložený (ne český) — obsah je vždy nový.
      const prev = obj(tr[lang]), meta = {
        ...r.meta
      };
      for (const k of [
        'title',
        'description'
      ]){
        const p = String(prev[k] ?? '').trim();
        if (!(k in meta) && p && p !== String(cur[k] ?? '').trim()) meta[k] = prev[k];
      }
      tr[lang] = {
        ...meta,
        content_html: r.content_html
      };
      src[lang] = srcHash;
    }
    payload.translations = tr;
  }
  const withSrc = hasTranslationSrc(cur);
  const { error } = await admin.from(table).update(withSrc ? {
    ...payload,
    translation_src: src
  } : payload).eq('id', id);
  if (error) return {
    ok: false,
    srcSaved: false,
    error: 'DB update failed: ' + error.message
  };
  return {
    ok: true,
    srcSaved: withSrc
  };
}
async function run(admin, table, id, row, langs, reason) {
  const t0 = performance.now();
  const srcHash = table === 'document_templates' ? await srcHashTemplate(row.content_html) : await srcHashCustom(row.content_html, row.pdf_path);
  const src = await buildSource(admin, table, row);
  const done = {};
  const errors = {};
  const warnings = {};
  for (const lang of langs){
    try {
      done[lang] = await translateDoc(src, lang);
      if (done[lang].warnings.length) warnings[lang] = done[lang].warnings;
    } catch (e) {
      errors[lang] = e instanceof Error ? e.message : String(e);
      console.error(`translate-document ${table}/${id} ${lang} failed:`, errors[lang]);
    }
  }
  const saved = Object.keys(done).length ? await save(admin, table, id, done, srcHash) : {
    ok: true,
    srcSaved: false
  };
  await log(admin, 'doc_translate', Object.keys(errors).length || !saved.ok ? 'error' : 'ok', {
    table,
    id,
    langs,
    reason,
    model: MODEL,
    src: srcHash
  }, {
    done: Object.keys(done),
    chunks: Object.fromEntries(Object.entries(done).map(([l, r])=>[
        l,
        r.chunks
      ])),
    errors,
    warnings,
    src_saved: saved.srcSaved
  }, saved.ok ? Object.values(errors)[0] || null : saved.error || null, performance.now() - t0);
  return {
    done,
    errors,
    warnings,
    saved
  };
}
serve(async (req)=>{
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: CORS
  });
  try {
    if (!ANTHROPIC_API_KEY) return jsonResponse({
      error: 'ANTHROPIC_API_KEY not configured'
    }, 500);
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return jsonResponse({
      error: 'Supabase env not configured'
    }, 500);
    // Jen service_role (generate-document) nebo účet Velína — dřív stačil JWT libovolného zákazníka (EDGE-DOC-18).
    const who = await authClassify(req, {
      adminRoles: ALL_ADMIN_ROLES
    });
    if (who.kind === 'none') return jsonResponse({
      error: 'Unauthorized'
    }, 401);
    if (who.kind === 'user') return jsonResponse({
      error: 'Forbidden: Velín account required'
    }, 403);
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const body = await req.json().catch(()=>null);
    if (!body) return jsonResponse({
      error: 'Invalid JSON body'
    }, 400);
    const table = String(body.table || '').trim();
    const id = String(body.id || '').trim();
    const reqLangs = Array.isArray(body.target_langs) ? body.target_langs : Array.isArray(body.languages) ? body.languages : [];
    const wanted = reqLangs.length ? DOC_TARGET_LANGS.filter((l)=>reqLangs.includes(l)) : [
      ...DOC_TARGET_LANGS
    ];
    const force = body.force === true;
    const isAsync = body.async === true && who.kind === 'service';
    const reason = String(body.reason || (who.kind === 'service' ? 'service' : 'velin')).slice(0, 60);
    if (table !== 'custom_documents' && table !== 'document_templates') return jsonResponse({
      error: `Table not allowed: ${table}`
    }, 400);
    if (!id) return jsonResponse({
      error: 'Missing id'
    }, 400);
    if (!wanted.length) return jsonResponse({
      error: 'No supported target language'
    }, 400);
    const { data: row, error: readErr } = await admin.from(table).select('*').eq('id', id).maybeSingle();
    if (readErr) return jsonResponse({
      error: 'DB read failed: ' + readErr.message
    }, 500);
    if (!row) return jsonResponse({
      error: 'Row not found'
    }, 404);
    const hasContent = String(row.content_html || '').trim() || table === 'custom_documents' && row.kind === 'pdf' && row.pdf_path;
    if (!hasContent) return jsonResponse({
      success: true,
      translations: {},
      skipped: 'no_content'
    });
    // Čerstvý překlad (otisk = aktuální český zdroj) se bez `force` nepřekládá znovu.
    const translations = {};
    const skipped = [];
    const langs = [];
    for (const lang of wanted){
      if (!force) {
        const fresh = table === 'document_templates' ? await freshTemplateTranslation(row, lang) : await freshCustomTranslation(row, lang);
        if (fresh) {
          skipped.push(lang);
          translations[lang] = 'content' in fresh ? {
            name: fresh.name || '',
            content_html: fresh.content
          } : fresh;
          continue;
        }
      }
      langs.push(lang);
    }
    if (!langs.length) return jsonResponse({
      success: true,
      translations,
      skipped
    });
    if (isAsync) {
      // Automatický překlad z generate-document: max. 1 pokus / dokument / jazyk / 6 h (selhávající
      // překlad nesmí běžet s každým e-mailem znovu). Chyba dotazu = raději nepřekládat.
      const since = new Date(Date.now() - AUTO_THROTTLE_MS).toISOString();
      const todo = [];
      for (const lang of langs){
        const { data: recent, error } = await admin.from('debug_log').select('id').eq('action', 'doc_translate_auto').gte('created_at', since).contains('request_data', {
          table,
          id,
          lang
        }).limit(1);
        if (error || recent?.length) continue;
        await log(admin, 'doc_translate_auto', 'info', {
          table,
          id,
          lang,
          reason
        }, null, null);
        todo.push(lang);
      }
      if (!todo.length) return jsonResponse({
        success: true,
        queued: [],
        throttled: langs
      }, 202);
      const job = run(admin, table, id, row, todo, reason).catch((e)=>console.error('translate-document async:', e));
      if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) {
        EdgeRuntime.waitUntil(job);
        return jsonResponse({
          success: true,
          queued: todo
        }, 202);
      }
      await job;
      return jsonResponse({
        success: true,
        queued: todo
      }, 202);
    }
    const { done, errors, warnings, saved } = await run(admin, table, id, row, langs, reason);
    if (!saved.ok) return jsonResponse({
      error: saved.error,
      details: errors
    }, 500);
    if (!Object.keys(done).length) return jsonResponse({
      error: 'All translations failed',
      details: errors
    }, 502);
    for (const [lang, r] of Object.entries(done)){
      translations[lang] = table === 'document_templates' ? {
        name: r.meta.name || '',
        content_html: r.content_html
      } : {
        ...r.meta,
        content_html: r.content_html
      };
    }
    return jsonResponse({
      success: true,
      translations,
      src_saved: saved.srcSaved,
      ...Object.keys(errors).length ? {
        errors
      } : {},
      ...Object.keys(warnings).length ? {
        warnings
      } : {},
      ...skipped.length ? {
        skipped
      } : {}
    });
  } catch (e) {
    console.error('translate-document fatal:', e);
    return jsonResponse({
      error: e instanceof Error ? e.message : String(e)
    }, 500);
  }
});
