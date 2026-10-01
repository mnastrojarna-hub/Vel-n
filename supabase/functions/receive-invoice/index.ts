// ===== MotoGo24 – Edge Function: Receive Invoice =====
// Mobile -> image upload -> Claude Vision OCR -> financial_events + invoices + routing
// Replaces Mindee with Claude Vision for document understanding.
//
// Auth: X-Invoice-Api-Key header (secret: INVOICE_API_KEY)
// DPH: Firma NENÍ plátcem DPH. vat_rate = 0 vždy.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callClaudeVision } from './vision-ocr.ts';
import { routeDocument } from './document-routing.ts';
import { upsertSupplier } from './supplier-utils.ts';
import { requireAdminOrService } from '../_shared/auth.ts';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'x-invoice-api-key, authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const RATE_LIMIT_MAX = 100;
const rateLimitStore = new Map();
function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...CORS,
      'Content-Type': 'application/json'
    }
  });
}
// Konstantní-časové porovnání řetězců (zamezí timing útoku na API klíč).
function timingSafeEqualStr(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for(let i = 0; i < a.length; i++)diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
const round2 = (n)=>Math.round((n + Number.EPSILON) * 100) / 100;
// ČNB denní kurz pro převod do CZK ke dni faktury. Vrací { rate, date } kde CZK = částka * rate.
// ČNB při zadání data vrátí kurz daného (nebo nejbližšího předchozího) pracovního dne.
async function cnbRateToCzk(dateIso, currency) {
  const cur = (currency || '').toUpperCase();
  if (!cur || cur === 'CZK') return {
    rate: 1,
    date: dateIso
  };
  try {
    const [y, m, d] = (dateIso || '').split('-');
    const dd = d && m && y ? `${d}.${m}.${y}` : '';
    const url = `https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/denni_kurz.txt${dd ? `?date=${dd}` : ''}`;
    const r = await fetch(url);
    if (!r.ok) return null;
    const txt = await r.text();
    const lines = txt.trim().split('\n');
    const headerDate = (lines[0] || '').split(' ')[0] || dateIso;
    for(let i = 2; i < lines.length; i++){
      const p = lines[i].split('|');
      if (p.length >= 5 && p[3].trim().toUpperCase() === cur) {
        const amount = parseFloat(p[2].replace(',', '.')) || 1;
        const rate = parseFloat(p[4].replace(',', '.'));
        if (rate > 0) return {
          rate: rate / amount,
          date: headerDate
        };
      }
    }
    return null;
  } catch  {
    return null;
  }
}
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: CORS
    });
  }
  if (req.method !== 'POST') {
    return jsonResponse({
      error: 'Method not allowed'
    }, 405);
  }
  // -- 1. Auth --
  // Bezpečnostní fix 2026-06-10: odstraněn hardcoded FALLBACK_KEY (byl natvrdo
  // v doc-scanner bundlu i tady → kdokoli s APK mohl volat tuto service_role
  // funkci a vkládat falešné účetní doklady; rotace secretu ho neodvolala).
  // Nyní výhradně přes secret INVOICE_API_KEY (timing-safe porovnání).
  // Dvě cesty: a) doc-scanner mobile přes X-Invoice-Api-Key; b) Velín admin přes JWT
  // (Logistika → Naskladnění „Vyfotit fakturu"). Stačí jedna.
  const INVOICE_API_KEY = Deno.env.get('INVOICE_API_KEY') || '';
  const apiKey = req.headers.get('x-invoice-api-key') || '';
  const validKey = INVOICE_API_KEY.length > 0 && timingSafeEqualStr(apiKey, INVOICE_API_KEY);
  let authed = validKey;
  if (!authed) {
    const a = await requireAdminOrService(req);
    authed = a.ok;
  }
  if (!authed) {
    return jsonResponse({
      error: 'Unauthorized: invalid API key or admin token'
    }, 401);
  }
  // -- Rate limiting --
  const rlKey = apiKey || 'admin-jwt';
  const now = Date.now();
  const rl = rateLimitStore.get(rlKey) || {
    count: 0,
    resetAt: now + 3600_000
  };
  if (now > rl.resetAt) {
    rl.count = 0;
    rl.resetAt = now + 3600_000;
  }
  rl.count++;
  rateLimitStore.set(rlKey, rl);
  if (rl.count > RATE_LIMIT_MAX) {
    return jsonResponse({
      error: 'Rate limit exceeded (max 100/hour)'
    }, 429);
  }
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  try {
    const payload = await req.json();
    // mode: 'extract' = jen vyčíst (NIC nezapisovat), 'commit' = zapsat z opravených dat,
    // 'full' = vyčíst + zapsat (doc-scanner mobile, beze změny).
    const mode = payload.mode === 'extract' ? 'extract' : payload.mode === 'commit' ? 'commit' : 'full';
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || '';
    let parsed;
    let storagePath = null;
    let confidenceScore;
    let documentType;
    let currency;
    let amountOriginal;
    let fxRate = 1;
    let fxFailed = false;
    let fxDate = null;
    let amountCzk;
    let convertedItems;
    if (mode === 'commit') {
      const doc = payload.doc || {};
      parsed = doc;
      storagePath = doc.storage_path || null;
      confidenceScore = doc.confidence?.overall ?? doc.confidence_score ?? 0.9;
      documentType = doc.document_type || 'other';
      currency = (doc.currency || 'CZK').toUpperCase();
      amountOriginal = doc.amount_original ?? doc.amount_czk ?? 0;
      fxRate = doc.fx_rate || 1;
      fxFailed = !!doc.fx_failed;
      fxDate = doc.fx_date || null;
      amountCzk = doc.amount_czk ?? (currency === 'CZK' ? amountOriginal : round2(amountOriginal * fxRate));
      convertedItems = Array.isArray(doc.line_items) ? doc.line_items : [];
    } else {
      if (!payload.image_base64) return jsonResponse({
        error: 'image_base64 is required'
      }, 400);
      const base64Clean = payload.image_base64.replace(/^data:image\/\w+;base64,/, '');
      const imageDate = new Date();
      const yyyy = imageDate.getFullYear();
      const mm = String(imageDate.getMonth() + 1).padStart(2, '0');
      const fileId = crypto.randomUUID();
      storagePath = `${yyyy}/${mm}/${fileId}.jpg`;
      const binaryStr = atob(base64Clean);
      const bytes = new Uint8Array(binaryStr.length);
      for(let i = 0; i < binaryStr.length; i++)bytes[i] = binaryStr.charCodeAt(i);
      const { error: uploadErr } = await supabase.storage.from('invoices-received').upload(storagePath, bytes, {
        contentType: 'image/jpeg',
        upsert: false
      });
      if (uploadErr) {
        console.error('Image upload failed:', uploadErr.message);
        storagePath = null;
      }
      if (!ANTHROPIC_API_KEY) return jsonResponse({
        error: 'ANTHROPIC_API_KEY not configured'
      }, 500);
      let mediaType = 'image/jpeg';
      const dataUriMatch = payload.image_base64.match(/^data:(image\/\w+);base64,/);
      if (dataUriMatch) mediaType = dataUriMatch[1];
      const p = await callClaudeVision(ANTHROPIC_API_KEY, base64Clean, mediaType);
      if (!p) {
        try {
          await supabase.from('accounting_exceptions').insert({
            reason: 'Claude Vision neparsoval dokument — ruční kontrola',
            suggested_fix: {
              storage_path: storagePath,
              hint: 'Zkontrolujte obrázek ručně.'
            },
            assigned_to: 'admin'
          });
        } catch (e) {}
        return jsonResponse({
          error: 'Failed to parse document with Claude Vision'
        }, 500);
      }
      parsed = p;
      confidenceScore = parsed.confidence?.overall ?? 0.5;
      documentType = parsed.document_type || 'other';
      const issueDateForFx = parsed.issue_date || new Date().toISOString().slice(0, 10);
      currency = (parsed.currency || 'CZK').toUpperCase();
      amountOriginal = parsed.amount_czk || parsed.purchase?.amount_czk || 0;
      const fx = await cnbRateToCzk(issueDateForFx, currency);
      fxRate = fx ? fx.rate : 1;
      fxFailed = currency !== 'CZK' && !fx;
      fxDate = fx?.date || null;
      amountCzk = currency === 'CZK' ? amountOriginal : round2(amountOriginal * fxRate);
      convertedItems = (parsed.line_items || []).map((li)=>({
          description: li?.description_cs || li?.description || '',
          original_description: li?.description || null,
          quantity: li?.quantity ?? null,
          currency,
          unit_price_original: li?.unit_price ?? null,
          amount_original: li?.amount ?? null,
          unit_price: li?.unit_price != null ? round2(li.unit_price * fxRate) : null,
          amount: li?.amount != null ? round2(li.amount * fxRate) : null,
          size: li?.size || null,
          color: li?.color || null,
          sku_suggestion: li?.sku_suggestion || null,
          category_suggestion: li?.category_suggestion || null
        }));
    }
    const isProforma = documentType === 'proforma';
    const needsReview = confidenceScore < 0.80;
    const todayStr = new Date().toISOString().slice(0, 10);
    // -- EXTRACT: jen vyčíst, NIC nezapisovat (finance ani sklad). Zápis až přes 'commit'. --
    if (mode === 'extract') {
      return jsonResponse({
        success: true,
        mode: 'extract',
        document_type: documentType,
        is_proforma: isProforma,
        source_language: parsed.source_language || 'cs',
        currency,
        fx_rate: fxRate,
        fx_date: fxDate,
        fx_failed: fxFailed,
        needs_review: needsReview || fxFailed,
        confidence: parsed.confidence,
        amount_czk: amountCzk,
        amount_original: amountOriginal,
        line_items: convertedItems,
        extracted: {
          supplier: parsed.supplier_name_cs || parsed.supplier_name,
          supplier_original: parsed.supplier_name,
          supplier_ico: parsed.supplier_ico,
          supplier_bank_account: parsed.supplier_bank_account,
          amount: amountCzk,
          date: parsed.issue_date || null,
          due_date: parsed.due_date || null,
          received_date: parsed.received_date || todayStr,
          variable_symbol: parsed.variable_symbol,
          payment_method: parsed.payment_method,
          invoice_number: parsed.invoice_number,
          asset_classification: parsed.asset_classification
        },
        // doc = vše potřebné pro pozdější commit (frontend pošle zpět po „Uložit")
        doc: {
          document_type: documentType,
          is_proforma: isProforma,
          source_language: parsed.source_language || 'cs',
          currency,
          amount_original: amountOriginal,
          amount_czk: amountCzk,
          fx_rate: fxRate,
          fx_date: fxDate,
          fx_failed: fxFailed,
          confidence_score: confidenceScore,
          supplier_name: parsed.supplier_name,
          supplier_name_cs: parsed.supplier_name_cs || null,
          supplier_ico: parsed.supplier_ico,
          supplier_dic: parsed.supplier_dic,
          supplier_address: parsed.supplier_address,
          supplier_bank_account: parsed.supplier_bank_account,
          invoice_number: parsed.invoice_number,
          variable_symbol: parsed.variable_symbol,
          issue_date: parsed.issue_date,
          due_date: parsed.due_date,
          received_date: parsed.received_date,
          payment_method: parsed.payment_method,
          asset_classification: parsed.asset_classification,
          line_items: parsed.line_items,
          storage_path: storagePath,
          loan: parsed.loan,
          employment: parsed.employment,
          insurance: parsed.insurance,
          purchase: parsed.purchase,
          notes: parsed.notes
        }
      });
    }
    // -- 4. Determine event_type based on document_type --
    const eventTypeMap = {
      'invoice': 'expense',
      'receipt': 'expense',
      'contract_purchase': 'asset',
      'contract_loan': 'expense',
      'contract_employment': 'expense',
      'contract_service': 'expense',
      'delivery_note': 'expense',
      'insurance': 'expense',
      'leasing': 'expense',
      'other': 'expense'
    };
    const eventType = eventTypeMap[documentType] || 'expense';
    // -- 5. INSERT into financial_events --
    const today = new Date().toISOString().slice(0, 10);
    const eventStatus = confidenceScore >= 0.80 ? 'enriched' : 'pending';
    const { data: feData, error: feError } = await supabase.from('financial_events').insert({
      event_type: eventType,
      source: 'ocr',
      amount_czk: amountCzk,
      vat_rate: 0,
      duzp: parsed.issue_date || today,
      confidence_score: confidenceScore,
      status: eventStatus,
      metadata: {
        document_type: documentType,
        is_proforma: isProforma,
        source_language: parsed.source_language || 'cs',
        currency,
        amount_original: amountOriginal,
        fx_rate: fxRate,
        fx_date: fxDate,
        fx_failed: fxFailed,
        supplier_name: parsed.supplier_name,
        supplier_name_cs: parsed.supplier_name_cs || null,
        supplier_ico: parsed.supplier_ico,
        supplier_dic: parsed.supplier_dic,
        supplier_address: parsed.supplier_address,
        supplier_bank_account: parsed.supplier_bank_account,
        invoice_number: parsed.invoice_number,
        variable_symbol: parsed.variable_symbol,
        due_date: parsed.due_date,
        received_date: parsed.received_date || new Date().toISOString().slice(0, 10),
        payment_method: parsed.payment_method,
        asset_classification: parsed.asset_classification,
        line_items: parsed.line_items,
        storage_path: storagePath,
        source_app: 'mobile',
        loan: parsed.loan,
        employment: parsed.employment,
        insurance: parsed.insurance,
        purchase: parsed.purchase,
        notes: parsed.notes
      }
    }).select('id').single();
    if (feError) {
      console.error('financial_events insert failed:', feError.message);
      return jsonResponse({
        error: 'Failed to create financial event: ' + feError.message
      }, 500);
    }
    const financialEventId = feData.id;
    // -- 6. INSERT into invoices (for invoice/receipt types) --
    let invoiceId = null;
    if (documentType === 'invoice' || documentType === 'receipt') {
      const invoiceNumber = parsed.invoice_number || `MOB-${Date.now()}`;
      const { data: invData, error: invError } = await supabase.from('invoices').insert({
        number: invoiceNumber,
        type: 'received',
        total: amountCzk,
        subtotal: amountCzk,
        tax_amount: 0,
        issue_date: parsed.issue_date || today,
        due_date: parsed.due_date || null,
        status: 'issued',
        notes: parsed.supplier_name || null,
        metadata: {
          financial_event_id: financialEventId,
          source_app: 'mobile',
          ocr_confidence: confidenceScore
        }
      }).select('id').single();
      if (!invError && invData) {
        invoiceId = invData.id;
        await supabase.from('financial_events').update({
          linked_entity_type: 'invoice',
          linked_entity_id: invoiceId
        }).eq('id', financialEventId);
      }
    }
    // -- 7. AI classification (Haiku for speed) --
    let aiClassification = null;
    if (amountCzk > 0) {
      try {
        const lineItemsText = (parsed.line_items || []).filter((li)=>li?.description).map((li)=>`${li.description}: ${li.amount} Kč`).join(', ') || 'neuvedeno';
        const assetInfo = parsed.asset_classification || {};
        const aiResponse = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01'
          },
          body: JSON.stringify({
            model: 'claude-haiku-4-5-20251001',
            max_tokens: 500,
            messages: [
              {
                role: 'user',
                content: `Klasifikuj tento náklad pro malou českou firmu (půjčovna motorek, neplátce DPH).
Dodavatel: ${parsed.supplier_name || 'neuvedeno'}
Částka: ${amountCzk} Kč
Typ dokumentu: ${documentType}
Položky: ${lineItemsText}
Typ majetku z OCR: ${assetInfo.type || 'neurčeno'}
Odpisová skupina z OCR: ${assetInfo.depreciation_group || 'neurčeno'}

Vrať POUZE JSON bez markdown:
{
  "category": "string (phm/pojisteni/servis_opravy/najem/energie/telekomunikace/marketing/kancelar/mzdy/dane_odvody/ostatni_naklady/dlouhodoby_majetek/kratkodoby_majetek/zbozi/drobna_rezie/material)",
  "suggested_account": "string (číslo účtu dle české účtové osnovy)",
  "is_recurring": false,
  "classification_note": "string",
  "asset_type": "dlouhodoby_majetek|kratkodoby_majetek|zbozi|material|drobna_rezie|sluzba|null",
  "depreciation_group": "sk1|sk2|sk3|sk4|sk5|sk6|null",
  "depreciation_years": "number|null",
  "depreciation_method": "accelerated|linear|null",
  "asset_name": "string|null"
}

Pravidla:
- Motorky = vždy sk2 (5 let), zrychlené odpisy
- DM: pořizovací cena >= 80 000 Kč a životnost > 1 rok
- KM: cena < 80 000 Kč, životnost > 1 rok
- Zboží: k dalšímu prodeji
- Materiál: spotřební
- Drobná režie: poštovné, poplatky, dálniční známky`
              }
            ]
          })
        });
        if (aiResponse.ok) {
          const aiResult = await aiResponse.json();
          const aiText = aiResult?.content?.[0]?.text || '';
          try {
            aiClassification = JSON.parse(aiText);
          } catch  {
            const jsonMatch = aiText.match(/\{[\s\S]*\}/);
            if (jsonMatch) aiClassification = JSON.parse(jsonMatch[0]);
          }
        }
      } catch (aiErr) {
        console.error('AI classification failed:', aiErr);
      }
      if (aiClassification) {
        const { data: currentEvent } = await supabase.from('financial_events').select('metadata').eq('id', financialEventId).single();
        await supabase.from('financial_events').update({
          metadata: {
            ...currentEvent?.metadata || {},
            ai_classification: aiClassification
          }
        }).eq('id', financialEventId);
      }
    }
    // -- 8. Route document to appropriate tables --
    await routeDocument(parsed, financialEventId, supabase);
    // -- 8b. Upsert supplier --
    const supplierId = await upsertSupplier(parsed.supplier_name, aiClassification, supabase, {
      ico: parsed.supplier_ico,
      dic: parsed.supplier_dic,
      address: parsed.supplier_address,
      bank_account: parsed.supplier_bank_account
    });
    if (supplierId) {
      const { data: currentEvent } = await supabase.from('financial_events').select('metadata').eq('id', financialEventId).single();
      await supabase.from('financial_events').update({
        metadata: {
          ...currentEvent?.metadata || {},
          supplier_id: supplierId
        }
      }).eq('id', financialEventId);
    }
    // -- 9. Low confidence -> accounting_exceptions --
    if (needsReview) {
      try {
        await supabase.from('accounting_exceptions').insert({
          financial_event_id: financialEventId,
          reason: `Nízká přesnost OCR: ${(confidenceScore * 100).toFixed(0)}% — ${documentType}`,
          suggested_fix: {
            fields_to_check: [
              'amount_czk',
              'supplier_name',
              'invoice_number'
            ],
            hint: 'Zkontrolujte data ručně ve Velínu a potvrďte nebo opravte.'
          },
          assigned_to: 'admin'
        });
      } catch (err) {
        console.error('Failed to create exception:', err);
      }
    }
    // -- 10. Response --
    return jsonResponse({
      success: true,
      financial_event_id: financialEventId,
      invoice_id: invoiceId,
      document_type: documentType,
      status: eventStatus,
      ai_classification: aiClassification,
      confidence: parsed.confidence,
      needs_review: needsReview || fxFailed,
      source_language: parsed.source_language || 'cs',
      currency,
      fx_rate: fxRate,
      fx_date: fxDate,
      fx_failed: fxFailed,
      is_proforma: isProforma,
      amount_czk: amountCzk,
      // Položky pro naskladnění: přeložené do CZ + ceny v CZK (ČNB) + návrh SKU:
      line_items: convertedItems,
      extracted: {
        supplier: parsed.supplier_name_cs || parsed.supplier_name,
        supplier_original: parsed.supplier_name,
        supplier_ico: parsed.supplier_ico,
        supplier_bank_account: parsed.supplier_bank_account,
        amount: amountCzk,
        date: parsed.issue_date || null,
        due_date: parsed.due_date || null,
        received_date: parsed.received_date || today,
        variable_symbol: parsed.variable_symbol,
        payment_method: parsed.payment_method,
        invoice_number: parsed.invoice_number,
        asset_classification: parsed.asset_classification
      }
    });
  } catch (err) {
    console.error('receive-invoice error:', err);
    return jsonResponse({
      error: err.message
    }, 500);
  }
});
