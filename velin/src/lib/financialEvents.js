/**
 * Financial Events Pipeline
 * Orchestrates: ingest → enrich → validate → classify → export → sync
 * NO accounting logic — only event routing to Abra Flexi.
 */
import { supabase } from './supabase'
import {
  isFlexiConfigured, getFlexiConfig,
  pushIssuedInvoice, pushReceivedInvoice, pushBankTransaction, pushAsset,
  mapEventToFlexiEntity, mapFlexiAccounts,
} from './abraFlexi'

// ─── CONFIDENCE THRESHOLD ─────────────────────────────
const DEFAULT_CONFIDENCE_THRESHOLD = 0.85

// ─── EVENT INGESTION ──────────────────────────────────

/** Create a financial event manually */
export async function ingestEvent(eventData) {
  const { data, error } = await supabase.from('financial_events').insert({
    ...eventData,
    pipeline_status: 'ingested',
    vat_rate: 0,      // firma neni platce DPH
    vat_amount: 0,
    amount_without_vat: eventData.amount,
  }).select().single()
  if (error) throw error
  return data
}

// ─── PIPELINE: Process single event ───────────────────

/** Run full pipeline on a single event */
export async function processEvent(eventId) {
  const { data: event, error } = await supabase.from('financial_events')
    .select('*').eq('id', eventId).single()
  if (error || !event) throw new Error('Event not found')

  try {
    // Step 1: Enrich
    const enriched = await enrichEvent(event)

    // Step 2: Validate
    const validation = validateEvent(enriched)
    if (!validation.valid) {
      await createException(eventId, 'validation_error', validation.errors.join('; '), 'high')
      await updateStatus(eventId, 'exception', { exception_reason: validation.errors.join('; ') })
      return { status: 'exception', errors: validation.errors }
    }

    // Step 3: Classify (map to Flexi)
    const classified = classifyEvent(enriched)
    await supabase.from('financial_events').update({
      pipeline_status: 'classified',
      flexi_entity_type: classified.flexi_entity_type,
      flexi_document_type: classified.flexi_document_type,
      flexi_account_debit: classified.flexi_account_debit,
      flexi_account_credit: classified.flexi_account_credit,
      ai_category: enriched.ai_category,
      ai_confidence: enriched.ai_confidence,
    }).eq('id', eventId)

    // Step 4: Check confidence
    const cfg = await getFlexiConfig()
    const threshold = cfg?.confidence_threshold || DEFAULT_CONFIDENCE_THRESHOLD
    if (enriched.ai_confidence < threshold && enriched.ai_confidence > 0) {
      await createException(eventId, 'low_confidence', `AI confidence ${(enriched.ai_confidence * 100).toFixed(0)}% < ${(threshold * 100).toFixed(0)}%`, 'medium')
      await updateStatus(eventId, 'exception', { exception_reason: 'Niska duvera AI klasifikace' })
      return { status: 'exception', reason: 'low_confidence' }
    }

    // Step 5: Export to Flexi (if configured)
    if (await isFlexiConfigured() && cfg?.auto_sync) {
      const exportResult = await exportToFlexi(enriched, classified)
      if (exportResult.ok) {
        await supabase.from('financial_events').update({
          pipeline_status: 'synced',
          flexi_id: exportResult.flexi_id,
          flexi_synced_at: new Date().toISOString(),
        }).eq('id', eventId)
        return { status: 'synced', flexi_id: exportResult.flexi_id }
      } else {
        await createException(eventId, 'flexi_error', exportResult.error, 'high')
        await updateStatus(eventId, 'exception', { flexi_error: exportResult.error })
        return { status: 'exception', reason: 'flexi_error', error: exportResult.error }
      }
    }

    // No auto-sync — mark as classified, ready for manual export
    await updateStatus(eventId, 'classified')
    return { status: 'classified' }

  } catch (e) {
    await createException(eventId, 'validation_error', e.message, 'high')
    await updateStatus(eventId, 'exception', { exception_reason: e.message })
    return { status: 'exception', error: e.message }
  }
}

// ─── BATCH PROCESSING ─────────────────────────────────

/** Process all ingested events */
export async function processAllPending() {
  const { data: events } = await supabase.from('financial_events')
    .select('id').eq('pipeline_status', 'ingested').order('created_at').limit(100)

  const results = { processed: 0, synced: 0, exceptions: 0 }
  for (const event of (events || [])) {
    const result = await processEvent(event.id)
    results.processed++
    if (result.status === 'synced') results.synced++
    if (result.status === 'exception') results.exceptions++
  }
  return results
}

/** Export all classified events to Flexi */
export async function exportAllClassified() {
  const { data: events } = await supabase.from('financial_events')
    .select('*').eq('pipeline_status', 'classified').order('created_at').limit(100)

  const results = { exported: 0, errors: 0 }
  for (const event of (events || [])) {
    const classified = classifyEvent(event)
    const result = await exportToFlexi(event, classified)
    if (result.ok) {
      await supabase.from('financial_events').update({
        pipeline_status: 'synced',
        flexi_id: result.flexi_id,
        flexi_synced_at: new Date().toISOString(),
      }).eq('id', event.id)
      results.exported++
    } else {
      results.errors++
    }
  }
  return results
}

// ─── ENRICHMENT (AI + RULES) ──────────────────────────

async function enrichEvent(event) {
  const enriched = { ...event }

  // Rule-based classification (deterministic, high confidence)
  if (event.source === 'stripe') {
    enriched.ai_category = event.sub_type === 'booking_payment' ? 'pronajem_motorek' : 'prodej_zbozi'
    enriched.ai_confidence = 1.0
  } else if (event.source === 'fleet') {
    enriched.ai_category = 'dlouhodoby_majetek'
    enriched.ai_confidence = 1.0
  } else if (event.source === 'system' && event.sub_type === 'salary') {
    enriched.ai_category = 'mzdove_naklady'
    enriched.ai_confidence = 1.0
  } else if (event.source === 'ocr') {
    // OCR events get lower confidence — need AI classification
    enriched.ai_category = guessCategory(event.description, event.counterparty_name)
    enriched.ai_confidence = 0.7
  } else if (event.source === 'manual') {
    enriched.ai_category = event.ai_category || 'ostatni'
    enriched.ai_confidence = 0.9
  } else {
    enriched.ai_category = 'nezarazeno'
    enriched.ai_confidence = 0.5
  }

  // DPH — firma neni platce, vse bez DPH
  enriched.vat_rate = 0
  enriched.vat_amount = 0
  enriched.amount_without_vat = enriched.amount

  return enriched
}

/** Simple rule-based category guesser for OCR invoices */
function guessCategory(description, counterparty) {
  const text = ((description || '') + ' ' + (counterparty || '')).toLowerCase()
  const rules = [
    { keywords: ['benzin', 'phm', 'nafta', 'cerpaci', 'shell', 'omv', 'mol', 'orlen'], category: 'phm' },
    { keywords: ['pojist', 'generali', 'allianz', 'kooper', 'ceska_pojistovna'], category: 'pojisteni' },
    { keywords: ['servis', 'oprava', 'udrzba', 'pneu', 'olej', 'filtr'], category: 'servis_opravy' },
    { keywords: ['najem', 'pronajem', 'rent'], category: 'najem' },
    { keywords: ['elektr', 'plyn', 'voda', 'teplo', 'energie'], category: 'energie' },
    { keywords: ['telefon', 'mobil', 'internet', 'hosting', 'domena'], category: 'telekomunikace' },
    { keywords: ['reklam', 'market', 'propagac', 'inzer', 'google', 'facebook', 'meta'], category: 'marketing' },
    { keywords: ['kancelar', 'papir', 'toner', 'tisk'], category: 'kancelar' },
    { keywords: ['mzd', 'plat', 'odmena'], category: 'mzdy' },
    { keywords: ['dan', 'cssz', 'vzp', 'pojistn'], category: 'dane_odvody' },
  ]
  for (const rule of rules) {
    if (rule.keywords.some(k => text.includes(k))) return rule.category
  }
  return 'ostatni_naklady'
}

// ─── VALIDATION ───────────────────────────────────────

function validateEvent(event) {
  const errors = []
  if (!event.amount || event.amount <= 0) errors.push('Castka musi byt kladna')
  if (!event.event_type) errors.push('Chybi typ udalosti')
  if (!event.source) errors.push('Chybi zdroj')
  if (!event.tax_date && !event.issue_date) errors.push('Chybi datum (DUZP nebo datum vystaveni)')

  // Check for duplicates
  // (handled async in processEvent if needed)

  return { valid: errors.length === 0, errors }
}

// ─── CLASSIFICATION (MAP TO FLEXI) ───────────────────

function classifyEvent(event) {
  const mapping = mapEventToFlexiEntity(event)
  const accounts = mapFlexiAccounts(event)
  return {
    flexi_entity_type: mapping.entity,
    flexi_document_type: mapping.docType,
    flexi_account_debit: accounts.debit,
    flexi_account_credit: accounts.credit,
  }
}

// ─── EXPORT TO FLEXI ──────────────────────────────────

async function exportToFlexi(event, classified) {
  try {
    let result
    switch (classified.flexi_entity_type) {
      case 'faktura-vydana':
        result = await pushIssuedInvoice(event, {
          number: event.source_ref,
          customer_name: event.counterparty_name,
          customer_ico: event.counterparty_ico,
        })
        break
      case 'faktura-prijata':
        result = await pushReceivedInvoice(event)
        break
      case 'majetek':
        result = await pushAsset(event, event.metadata)
        break
      case 'banka':
      default:
        result = await pushBankTransaction(event)
        break
    }
    const flexiId = result?.winstrom?.results?.[0]?.id || result?.id || null
    return { ok: true, flexi_id: flexiId?.toString() }
  } catch (e) {
    return { ok: false, error: e.message }
  }
}

// ─── HELPERS ──────────────────────────────────────────

async function updateStatus(eventId, status, extra = {}) {
  await supabase.from('financial_events').update({ pipeline_status: status, ...extra }).eq('id', eventId)
}

async function createException(eventId, type, description, severity = 'medium') {
  await supabase.from('flexi_exceptions').insert({
    event_id: eventId,
    exception_type: type,
    severity,
    description,
    suggested_action: getSuggestedAction(type),
  })
}

function getSuggestedAction(type) {
  const actions = {
    'low_confidence': 'Zkontrolujte AI klasifikaci a potvrdte nebo opravte kategorii',
    'validation_error': 'Doplnte chybejici udaje nebo opravte neplatne hodnoty',
    'flexi_error': 'Zkontrolujte pripojeni k Abra Flexi a zkuste znovu',
    'duplicate': 'Zkontrolujte, zda se nejedna o duplicitni udalost',
    'missing_data': 'Doplnte povinne udaje (castka, datum, typ)',
    'amount_mismatch': 'Zkontrolujte castky — nesouhlasi se zdrojem',
    'manual_review': 'Udalost vyzaduje rucni kontrolu',
  }
  return actions[type] || 'Zkontrolujte a schvalte nebo zamitnete'
}

// ─── STATS ────────────────────────────────────────────

/** Get pipeline statistics */
export async function getPipelineStats() {
  const { data } = await supabase.from('financial_events')
    .select('pipeline_status, event_type')

  const stats = {
    total: 0,
    by_status: {},
    by_type: {},
    needs_attention: 0,
  }
  for (const e of (data || [])) {
    stats.total++
    stats.by_status[e.pipeline_status] = (stats.by_status[e.pipeline_status] || 0) + 1
    stats.by_type[e.event_type] = (stats.by_type[e.event_type] || 0) + 1
    if (e.pipeline_status === 'exception') stats.needs_attention++
  }
  return stats
}

/** Get recent events for dashboard */
export async function getRecentEvents(limit = 50) {
  const { data } = await supabase.from('financial_events')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit)
  return data || []
}

/** Get exceptions queue */
export async function getExceptions(resolvedToo = false) {
  let query = supabase.from('flexi_exceptions')
    .select('*, financial_events(*)')
    .order('created_at', { ascending: false })
  if (!resolvedToo) query = query.eq('resolved', false)
  const { data } = await query
  return data || []
}

/** Resolve an exception */
export async function resolveException(exceptionId, note, action = 'approved') {
  const { data: { user } } = await supabase.auth.getUser()
  const { data: exc } = await supabase.from('flexi_exceptions')
    .select('event_id').eq('id', exceptionId).single()

  await supabase.from('flexi_exceptions').update({
    resolved: true,
    resolved_by: user?.id,
    resolved_at: new Date().toISOString(),
    resolution_note: note,
  }).eq('id', exceptionId)

  if (exc?.event_id) {
    await supabase.from('financial_events').update({
      pipeline_status: action === 'approved' ? 'approved' : 'rejected',
      approved_by: user?.id,
      approved_at: new Date().toISOString(),
      exception_resolved_at: new Date().toISOString(),
      exception_resolved_by: user?.id,
    }).eq('id', exc.event_id)
  }
}

/** Approve event and push to Flexi */
export async function approveAndSync(eventId) {
  const { data: { user } } = await supabase.auth.getUser()
  await supabase.from('financial_events').update({
    pipeline_status: 'approved',
    approved_by: user?.id,
    approved_at: new Date().toISOString(),
  }).eq('id', eventId)

  // Try to sync to Flexi
  if (await isFlexiConfigured()) {
    const { data: event } = await supabase.from('financial_events')
      .select('*').eq('id', eventId).single()
    if (event) {
      const classified = classifyEvent(event)
      const result = await exportToFlexi(event, classified)
      if (result.ok) {
        await supabase.from('financial_events').update({
          pipeline_status: 'synced',
          flexi_id: result.flexi_id,
          flexi_synced_at: new Date().toISOString(),
        }).eq('id', eventId)
      }
    }
  }
}
