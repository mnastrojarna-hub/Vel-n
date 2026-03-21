// ===== MotoGo24 – Edge Function: Flexi Sync =====
// Transforms financial_events → Abra Flexi REST API calls.
// NO accounting logic — only data transformation + HTTP transport.
//
// Flexi API docs: https://www.flexibee.eu/api/
// Auth: HTTP Basic (username:password in Base64)
// Base URL: https://{FLEXI_URL}/c/{FLEXI_COMPANY}/
//
// DPH: Firma NENÍ plátcem DPH.
// Až bude plátce → změnit VAT_STATUS na "typSzbDph.dphZakl"

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── DPH KONSTANTA ───────────────────────────────────
const VAT_STATUS = 'typSzbDph.dphOsv' // neplátce DPH
// az bude platce: const VAT_STATUS = "typSzbDph.dphZakl"

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  const FLEXI_URL = Deno.env.get('FLEXI_URL') || ''
  const FLEXI_COMPANY = Deno.env.get('FLEXI_COMPANY') || ''
  const FLEXI_USERNAME = Deno.env.get('FLEXI_USERNAME') || ''
  const FLEXI_PASSWORD = Deno.env.get('FLEXI_PASSWORD') || ''

  const flexiBase = `${FLEXI_URL}/c/${FLEXI_COMPANY}`
  const flexiAuth = 'Basic ' + btoa(`${FLEXI_USERNAME}:${FLEXI_PASSWORD}`)

  try {
    // ── GET /flexi-sync?id={uuid} → status check ──
    if (req.method === 'GET') {
      const url = new URL(req.url)
      const id = url.searchParams.get('id')
      if (!id) {
        return jsonResponse({ error: 'Missing id parameter' }, 400)
      }

      const { data: event } = await supabase
        .from('financial_events')
        .select('*')
        .eq('id', id)
        .maybeSingle()

      const { data: logs } = await supabase
        .from('flexi_sync_log')
        .select('*')
        .eq('financial_event_id', id)
        .order('created_at', { ascending: false })

      return jsonResponse({ event, logs })
    }

    // ── POST: dispatch by action ──
    const body = await req.json()
    const { action, id, period, year, quarter, params } = body as {
      action: string
      id?: string
      period?: string
      year?: number
      quarter?: number
      params?: Record<string, unknown>
    }

    if (!action) {
      return jsonResponse({ error: 'Missing action' }, 400)
    }

    let result: Record<string, unknown>

    switch (action) {
      case 'pushInvoice':
        if (!id) return jsonResponse({ error: 'Missing id' }, 400)
        result = await pushInvoice(supabase, flexiBase, flexiAuth, id)
        break

      case 'pushExpense':
        if (!id) return jsonResponse({ error: 'Missing id' }, 400)
        result = await pushExpense(supabase, flexiBase, flexiAuth, id)
        break

      case 'pushAsset':
        if (!id) return jsonResponse({ error: 'Missing id' }, 400)
        result = await pushAsset(supabase, flexiBase, flexiAuth, id)
        break

      case 'pullVatReport':
        if (!period) return jsonResponse({ error: 'Missing period (e.g. 2026-Q1)' }, 400)
        result = await pullVatReport(flexiBase, flexiAuth, period)
        break

      case 'pullAccountingState':
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullAccountingState(flexiBase, flexiAuth, year)
        break

      // ─── PULL: Reports from Flexi → flexi_reports ──────────
      case 'pullVatReturn': {
        if (!year || !quarter) return jsonResponse({ error: 'Missing year or quarter' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'vat_return', year, quarter,
          `/dph-prizn.json?rok=${year}&ctvrtleti=${quarter}`)
        break
      }
      case 'pullIncomeTax': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'income_tax', year, null,
          `/danove-priznani.json?rok=${year}`)
        break
      }
      case 'pullBalanceSheet': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'balance_sheet', year, null,
          `/rozvaha.json?rok=${year}`)
        break
      }
      case 'pullProfitLoss': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'profit_loss', year, null,
          `/vysledovka.json?rok=${year}`)
        break
      }
      case 'pullOSSZ': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'ossz', year, null,
          `/prehled-ossz.json?rok=${year}`)
        break
      }
      case 'pullVZP': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        result = await pullReport(supabase, flexiBase, flexiAuth, 'vzp', year, null,
          `/prehled-vzp.json?rok=${year}`)
        break
      }
      case 'pullAll': {
        if (!year) return jsonResponse({ error: 'Missing year' }, 400)
        const results: Record<string, unknown> = {}
        const pullActions = [
          { type: 'balance_sheet', path: `/rozvaha.json?rok=${year}` },
          { type: 'profit_loss', path: `/vysledovka.json?rok=${year}` },
          { type: 'income_tax', path: `/danove-priznani.json?rok=${year}` },
          { type: 'ossz', path: `/prehled-ossz.json?rok=${year}` },
          { type: 'vzp', path: `/prehled-vzp.json?rok=${year}` },
        ]
        for (const pa of pullActions) {
          try {
            results[pa.type] = await pullReport(supabase, flexiBase, flexiAuth, pa.type, year, null, pa.path)
          } catch (e) {
            results[pa.type] = { ok: false, error: (e as Error).message }
          }
        }
        // VAT returns for each quarter
        for (let q = 1; q <= 4; q++) {
          try {
            results[`vat_return_Q${q}`] = await pullReport(supabase, flexiBase, flexiAuth, 'vat_return', year, q,
              `/dph-prizn.json?rok=${year}&ctvrtleti=${q}`)
          } catch (e) {
            results[`vat_return_Q${q}`] = { ok: false, error: (e as Error).message }
          }
        }
        result = { ok: true, year, results }
        break
      }
      case 'exportXml': {
        if (!id) return jsonResponse({ error: 'Missing id' }, 400)
        const { data: report } = await supabase.from('flexi_reports').select('*').eq('id', id).single()
        if (!report) return jsonResponse({ error: 'Report not found' }, 404)
        result = { ok: true, xml: JSON.stringify(report.raw_data, null, 2), report_type: report.report_type }
        break
      }

      default:
        return jsonResponse({ error: `Unknown action: ${action}` }, 400)
    }

    return jsonResponse(result)
  } catch (err) {
    console.error('flexi-sync error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

// ─── pushInvoice: Vydaná faktura (revenue → faktura-vydana) ──────

async function pushInvoice(
  supabase: ReturnType<typeof createClient>,
  flexiBase: string,
  flexiAuth: string,
  eventId: string
) {
  const event = await loadEvent(supabase, eventId)

  const payload = {
    'winstrom': {
      'faktura-vydana': {
        'typDokl': { 'code': 'FAKTURA' },
        'datVyst': event.duzp,
        'duzp': event.duzp,
        'sumCelkem': event.amount_czk,
        'sumZakl': event.amount_czk,
        'szbDphEnum': VAT_STATUS,
        'popis': `MotoGo24 ${event.linked_entity_type || 'platba'}`,
        'polozkyFaktury': [{
          'nazev': 'Pronájem motorky MotoGo24',
          'cenaMj': event.amount_czk,
          'szbDphEnum': VAT_STATUS,
        }],
      },
    },
  }

  const { responseBody, responseCode, error } = await flexiPost(
    `${flexiBase}/faktura-vydana.json`,
    flexiAuth,
    payload
  )

  const flexiId = responseBody?.winstrom?.results?.[0]?.id?.toString() || null

  // Log sync attempt
  await logSync(supabase, eventId, 'push', 'faktura-vydana', payload, responseCode, responseBody, error)

  if (error || !responseCode || responseCode >= 400) {
    await markError(supabase, eventId, responseCode, error || responseBody?.winstrom?.message || 'Flexi API error')
    return { ok: false, error: error || 'Flexi rejected request', responseCode }
  }

  // Update financial_event with flexi_id
  await supabase.from('financial_events').update({
    flexi_id: flexiId,
    status: 'exported',
  }).eq('id', eventId)

  // Create approval queue entry
  await supabase.from('approval_queue').insert({
    financial_event_id: eventId,
    approval_type: 'invoice_export',
    submitted_by: 'system',
    status: 'pending',
  })

  return { ok: true, flexi_id: flexiId }
}

// ─── pushExpense: Přijatá faktura (expense → faktura-prijata) ────

async function pushExpense(
  supabase: ReturnType<typeof createClient>,
  flexiBase: string,
  flexiAuth: string,
  eventId: string
) {
  const event = await loadEvent(supabase, eventId)

  const payload = {
    'winstrom': {
      'faktura-prijata': {
        'typDokl': { 'code': 'FAKTURA' },
        'datVyst': event.duzp,
        'duzp': event.duzp,
        'sumCelkem': event.amount_czk,
        'sumZakl': event.amount_czk,
        'szbDphEnum': VAT_STATUS,
        'popis': event.metadata?.description || `MotoGo24 náklad ${event.linked_entity_type || ''}`,
        'nazFirmy': event.metadata?.counterparty_name || '',
        'ic': event.metadata?.counterparty_ico || '',
        'polozkyFaktury': [{
          'nazev': event.metadata?.description || 'Přijatá faktura',
          'cenaMj': event.amount_czk,
          'szbDphEnum': VAT_STATUS,
        }],
      },
    },
  }

  const { responseBody, responseCode, error } = await flexiPost(
    `${flexiBase}/faktura-prijata.json`,
    flexiAuth,
    payload
  )

  const flexiId = responseBody?.winstrom?.results?.[0]?.id?.toString() || null

  await logSync(supabase, eventId, 'push', 'faktura-prijata', payload, responseCode, responseBody, error)

  if (error || !responseCode || responseCode >= 400) {
    await markError(supabase, eventId, responseCode, error || responseBody?.winstrom?.message || 'Flexi API error')
    return { ok: false, error: error || 'Flexi rejected request', responseCode }
  }

  await supabase.from('financial_events').update({
    flexi_id: flexiId,
    status: 'exported',
  }).eq('id', eventId)

  await supabase.from('approval_queue').insert({
    financial_event_id: eventId,
    approval_type: 'expense_export',
    submitted_by: 'system',
    status: 'pending',
  })

  return { ok: true, flexi_id: flexiId }
}

// ─── pushAsset: Registrace dlouhodobého majetku ──────────────────

async function pushAsset(
  supabase: ReturnType<typeof createClient>,
  flexiBase: string,
  flexiAuth: string,
  eventId: string
) {
  const event = await loadEvent(supabase, eventId)

  const payload = {
    'winstrom': {
      'majetek': {
        'nazev': event.metadata?.asset_name || `Majetek MotoGo24`,
        'datPorizeni': event.duzp,
        'porizCena': event.amount_czk,
        'odpisSkup': event.metadata?.depreciation_group || 2,
        'typOdpisuEnum': 'typOdpisu.rovnomerne',
      },
    },
  }

  const { responseBody, responseCode, error } = await flexiPost(
    `${flexiBase}/majetek.json`,
    flexiAuth,
    payload
  )

  const flexiId = responseBody?.winstrom?.results?.[0]?.id?.toString() || null

  await logSync(supabase, eventId, 'push', 'majetek', payload, responseCode, responseBody, error)

  if (error || !responseCode || responseCode >= 400) {
    await markError(supabase, eventId, responseCode, error || responseBody?.winstrom?.message || 'Flexi API error')
    return { ok: false, error: error || 'Flexi rejected request', responseCode }
  }

  await supabase.from('financial_events').update({
    flexi_id: flexiId,
    status: 'exported',
  }).eq('id', eventId)

  await supabase.from('approval_queue').insert({
    financial_event_id: eventId,
    approval_type: 'asset_registration',
    submitted_by: 'system',
    status: 'pending',
  })

  return { ok: true, flexi_id: flexiId }
}

// ─── pullVatReport: DPH přiznání (připraveno, neaktivní) ────────

async function pullVatReport(
  flexiBase: string,
  flexiAuth: string,
  period: string
) {
  // Firma není plátce DPH — vrátí prázdný výsledek
  // Až bude plátce, odkomentovat reálný pull
  // const { responseBody } = await flexiGet(`${flexiBase}/dph-prizn.json?obdobi=${period}`, flexiAuth)
  // return { ok: true, data: responseBody }

  return {
    ok: true,
    vat_payer: false,
    message: 'Firma není plátce DPH. Pull DPH přiznání je připraven ale neaktivní.',
    period,
    data: null,
  }
}

// ─── pullAccountingState: Účetní zásady ──────────────────────────

async function pullAccountingState(
  flexiBase: string,
  flexiAuth: string,
  year: number
) {
  const { responseBody, responseCode, error } = await flexiGet(
    `${flexiBase}/ucetni-zasady.json`,
    flexiAuth
  )

  if (error || !responseCode || responseCode >= 400) {
    return { ok: false, error: error || 'Flexi API error', responseCode }
  }

  return { ok: true, year, data: responseBody }
}

// ─── FLEXI HTTP HELPERS ──────────────────────────────────────────

async function flexiPost(
  url: string,
  auth: string,
  payload: Record<string, unknown>
): Promise<{ responseBody: any; responseCode: number | null; error: string | null }> {
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': auth,
      },
      body: JSON.stringify(payload),
    })

    const responseBody = await response.json().catch(() => null)
    return { responseBody, responseCode: response.status, error: null }
  } catch (err) {
    return { responseBody: null, responseCode: null, error: (err as Error).message }
  }
}

async function flexiGet(
  url: string,
  auth: string
): Promise<{ responseBody: any; responseCode: number | null; error: string | null }> {
  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': auth,
      },
    })

    const responseBody = await response.json().catch(() => null)
    return { responseBody, responseCode: response.status, error: null }
  } catch (err) {
    return { responseBody: null, responseCode: null, error: (err as Error).message }
  }
}

// ─── PULL REPORT: Generic Flexi → flexi_reports ─────────────────

async function pullReport(
  supabase: ReturnType<typeof createClient>,
  flexiBase: string,
  flexiAuth: string,
  reportType: string,
  year: number,
  quarter: number | null,
  flexiPath: string
) {
  const { responseBody, responseCode, error } = await flexiGet(
    `${flexiBase}${flexiPath}`,
    flexiAuth
  )

  if (error || !responseCode || responseCode >= 400) {
    return { ok: false, error: error || `Flexi ${responseCode}`, report_type: reportType }
  }

  // Calculate period dates
  const periodFrom = quarter
    ? `${year}-${String((quarter - 1) * 3 + 1).padStart(2, '0')}-01`
    : `${year}-01-01`
  const periodTo = quarter
    ? `${year}-${String(quarter * 3).padStart(2, '0')}-${quarter === 1 || quarter === 4 ? '31' : quarter === 2 ? '30' : '30'}`
    : `${year}-12-31`

  // Upsert — use report_type + year + quarter as conflict key
  const record: Record<string, unknown> = {
    report_type: reportType,
    year,
    quarter: quarter || null,
    period_from: periodFrom,
    period_to: periodTo,
    raw_data: responseBody,
    status: 'draft',
  }

  // For reports with quarter, use the quarter-specific unique index
  // For reports without quarter, use the year-specific unique index
  const { error: upsertErr } = quarter
    ? await supabase.from('flexi_reports')
        .upsert(record, { onConflict: 'report_type,year,quarter', ignoreDuplicates: false })
    : await supabase.from('flexi_reports')
        .upsert(record, { onConflict: 'report_type,year', ignoreDuplicates: false })

  if (upsertErr) {
    console.error('flexi_reports upsert failed:', upsertErr.message)
    return { ok: false, error: upsertErr.message, report_type: reportType }
  }

  // Log the pull
  await logSync(supabase, null as any, 'pull', reportType, { path: flexiPath }, responseCode, null, null)

  return { ok: true, report_type: reportType, year, quarter }
}

// ─── DB HELPERS ──────────────────────────────────────────────────

async function loadEvent(
  supabase: ReturnType<typeof createClient>,
  eventId: string
) {
  const { data, error } = await supabase
    .from('financial_events')
    .select('*')
    .eq('id', eventId)
    .single()

  if (error || !data) {
    throw new Error(`Financial event ${eventId} not found: ${error?.message || 'no data'}`)
  }
  return data
}

async function logSync(
  supabase: ReturnType<typeof createClient>,
  eventId: string,
  direction: 'push' | 'pull',
  flexiEntityType: string,
  payload: Record<string, unknown>,
  responseCode: number | null,
  responseBody: unknown,
  errorMessage: string | null
) {
  await supabase.from('flexi_sync_log').insert({
    financial_event_id: eventId,
    direction,
    flexi_entity_type: flexiEntityType,
    payload,
    response_code: responseCode,
    response_body: responseBody,
    status: (errorMessage || !responseCode || responseCode >= 400) ? 'error' : 'success',
    error_message: errorMessage,
  }).catch((err) => {
    console.error('Failed to log sync:', err)
  })
}

async function markError(
  supabase: ReturnType<typeof createClient>,
  eventId: string,
  responseCode: number | null,
  errorDetail: string
) {
  // Mark event as error
  await supabase.from('financial_events').update({
    status: 'error',
  }).eq('id', eventId)

  // Create accounting exception
  await supabase.from('accounting_exceptions').insert({
    financial_event_id: eventId,
    reason: `Flexi API ${responseCode || 'network'}: ${errorDetail}`,
    suggested_fix: {
      action: 'retry_or_manual',
      hint: 'Zkontrolujte připojení k Flexi a data události, pak zkuste znovu.',
    },
    assigned_to: 'admin',
  }).catch((err) => {
    console.error('Failed to create exception:', err)
  })
}

// ─── RESPONSE HELPER ─────────────────────────────────────────────

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
