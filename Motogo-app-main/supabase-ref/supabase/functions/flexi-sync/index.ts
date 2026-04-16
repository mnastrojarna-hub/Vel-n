// ===== MotoGo24 – Edge Function: Flexi Sync =====
// Transforms financial_events -> Abra Flexi REST API calls.
// NO accounting logic — only data transformation + HTTP transport.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { CORS, jsonResponse, pullReport } from './flexi-api.ts'
import { pushInvoice, pushExpense, pushAsset, pullVatReport, pullAccountingState } from './flexi-pushers.ts'

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
    // -- GET /flexi-sync?id={uuid} -> status check --
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

    // -- POST: dispatch by action --
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
