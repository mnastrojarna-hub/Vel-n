// ===== flexi-sync/flexi-pushers.ts =====
// Push functions: pushInvoice, pushExpense, pushAsset + pull helpers

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { VAT_STATUS, flexiPost, flexiGet, loadEvent, logSync, markError } from './flexi-api.ts'

// ─── pushInvoice: Vydaná faktura (revenue -> faktura-vydana) ──────

export async function pushInvoice(
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

  await logSync(supabase, eventId, 'push', 'faktura-vydana', payload, responseCode, responseBody, error)

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
    approval_type: 'invoice_export',
    submitted_by: 'system',
    status: 'pending',
  })

  return { ok: true, flexi_id: flexiId }
}

// ─── pushExpense: Přijatá faktura (expense -> faktura-prijata) ────

export async function pushExpense(
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

export async function pushAsset(
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

export async function pullVatReport(
  flexiBase: string,
  flexiAuth: string,
  period: string
) {
  return {
    ok: true,
    vat_payer: false,
    message: 'Firma není plátce DPH. Pull DPH přiznání je připraven ale neaktivní.',
    period,
    data: null,
  }
}

// ─── pullAccountingState: Účetní zásady ──────────────────────────

export async function pullAccountingState(
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
