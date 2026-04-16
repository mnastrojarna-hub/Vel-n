// ===== flexi-sync/flexi-api.ts =====
// Flexi HTTP helpers, DB helpers (loadEvent, logSync, markError), pullReport, jsonResponse

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── DPH KONSTANTA ───────────────────────────────────
export const VAT_STATUS = 'typSzbDph.dphOsv' // neplátce DPH

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

export function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// ─── FLEXI HTTP HELPERS ──────────────────────────────────────────

export async function flexiPost(
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

export async function flexiGet(
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

// ─── DB HELPERS ──────────────────────────────────────────────────

export async function loadEvent(
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

export async function logSync(
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

export async function markError(
  supabase: ReturnType<typeof createClient>,
  eventId: string,
  responseCode: number | null,
  errorDetail: string
) {
  await supabase.from('financial_events').update({
    status: 'error',
  }).eq('id', eventId)

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

// ─── PULL REPORT: Generic Flexi -> flexi_reports ─────────────────

export async function pullReport(
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

  const periodFrom = quarter
    ? `${year}-${String((quarter - 1) * 3 + 1).padStart(2, '0')}-01`
    : `${year}-01-01`
  const periodTo = quarter
    ? `${year}-${String(quarter * 3).padStart(2, '0')}-${quarter === 1 || quarter === 4 ? '31' : quarter === 2 ? '30' : '30'}`
    : `${year}-12-31`

  const record: Record<string, unknown> = {
    report_type: reportType,
    year,
    quarter: quarter || null,
    period_from: periodFrom,
    period_to: periodTo,
    raw_data: responseBody,
    status: 'draft',
  }

  const { error: upsertErr } = quarter
    ? await supabase.from('flexi_reports')
        .upsert(record, { onConflict: 'report_type,year,quarter', ignoreDuplicates: false })
    : await supabase.from('flexi_reports')
        .upsert(record, { onConflict: 'report_type,year', ignoreDuplicates: false })

  if (upsertErr) {
    console.error('flexi_reports upsert failed:', upsertErr.message)
    return { ok: false, error: upsertErr.message, report_type: reportType }
  }

  await logSync(supabase, null as any, 'pull', reportType, { path: flexiPath }, responseCode, null, null)

  return { ok: true, report_type: reportType, year, quarter }
}
