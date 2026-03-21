/**
 * Abra Flexi REST API Client
 * Handles all communication with external accounting system.
 * NO accounting logic here — only transport + mapping.
 *
 * Schema: financial_events (amount_czk, duzp, status, confidence_score)
 * DPH: INACTIVE — firma není plátcem. Sloupce existují, ale nepoužívají se.
 *
 * Flexi API: https://{instance}.flexibee.eu/c/{company}/{entity}.json
 */
import { supabase } from './supabase'

let _config = null

/** Load Flexi config from app_settings */
export async function getFlexiConfig() {
  if (_config) return _config
  const { data } = await supabase.from('app_settings').select('value').eq('key', 'flexi_config').maybeSingle()
  _config = data?.value || null
  return _config
}

/** Clear cached config (after settings change) */
export function clearFlexiConfigCache() { _config = null }

/** Check if Flexi is configured and connected */
export async function isFlexiConfigured() {
  const cfg = await getFlexiConfig()
  return !!(cfg?.url && cfg?.company && (cfg?.api_token || cfg?.username))
}

// ─── CORE API CALL ───────────────────────────────────

async function flexiRequest(method, endpoint, body = null, eventId = null) {
  const cfg = await getFlexiConfig()
  if (!cfg?.url || !cfg?.company) throw new Error('Abra Flexi neni nakonfigurovano')

  const url = `${cfg.url}/c/${cfg.company}/${endpoint}`
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  }
  if (cfg.api_token) {
    headers['X-FlexiBee-Authorization'] = `Bearer ${cfg.api_token}`
  } else if (cfg.username && cfg.password) {
    headers['Authorization'] = 'Basic ' + btoa(`${cfg.username}:${cfg.password}`)
  }

  const start = Date.now()
  let response, responseBody, error
  try {
    response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify({ [endpoint.split('.')[0].split('/').pop()]: body }) : undefined,
    })
    responseBody = await response.json().catch(() => null)
  } catch (e) {
    error = e.message
  }
  const duration = Date.now() - start

  // Log to flexi_sync_log (fire-and-forget)
  supabase.from('flexi_sync_log').insert({
    financial_event_id: eventId || null,
    direction: method === 'GET' ? 'pull' : 'push',
    flexi_entity_type: endpoint.split('.')[0].split('/').pop(),
    payload: body,
    response_code: response?.status,
    response_body: responseBody,
    status: error ? 'error' : (response?.ok ? 'success' : 'error'),
    error_message: error || (response?.ok ? null : responseBody?.winstrom?.message),
  }).then(() => {})

  if (error) throw new Error(`Flexi API error: ${error}`)
  if (!response.ok) {
    const msg = responseBody?.winstrom?.message || responseBody?.message || `HTTP ${response.status}`
    throw new Error(`Flexi: ${msg}`)
  }
  return responseBody
}

// ─── PUSH: Export events to Flexi ────────────────────

/** Export issued invoice (faktura-vydana) */
export async function pushIssuedInvoice(event, invoiceData) {
  const body = {
    'kod': invoiceData?.number || event.metadata?.invoice_number,
    'datVyst': event.duzp,
    'datSplat': event.metadata?.due_date || event.duzp,
    'sumCelkem': event.amount_czk,
    'mena': 'CZK',
    'popis': event.metadata?.description || '',
    'typDokl': mapDocumentType(event.metadata?.sub_type),
    // DPH — prepared but INACTIVE (firma neni platce)
    // 'typUcOp': 'code:FAKTURA_OUT',
    // 'sazbaDph': event.vat_rate, // always 0 for now
  }
  if (invoiceData?.customer_name) body['nazFirmy'] = invoiceData.customer_name
  if (invoiceData?.customer_ico) body['ic'] = invoiceData.customer_ico

  return flexiRequest('POST', 'faktura-vydana.json', body, event.id)
}

/** Export received invoice (faktura-prijata) */
export async function pushReceivedInvoice(event) {
  const body = {
    'kod': event.metadata?.invoice_number || '',
    'datVyst': event.duzp,
    'datSplat': event.metadata?.due_date || event.duzp,
    'sumCelkem': event.amount_czk,
    'mena': 'CZK',
    'popis': event.metadata?.description || '',
    'nazFirmy': event.metadata?.counterparty_name || '',
    'ic': event.metadata?.counterparty_ico || '',
  }
  return flexiRequest('POST', 'faktura-prijata.json', body, event.id)
}

/** Export bank transaction (banka) */
export async function pushBankTransaction(event) {
  const body = {
    'datVyst': event.duzp,
    'sumCelkem': event.amount_czk,
    'mena': 'CZK',
    'popis': event.metadata?.description || '',
    'typPohybuK': event.event_type === 'revenue' ? 'typPohybu.prijem' : 'typPohybu.vydej',
  }
  return flexiRequest('POST', 'banka.json', body, event.id)
}

/** Export asset (majetek) */
export async function pushAsset(event) {
  const body = {
    'nazev': event.metadata?.asset_name || event.metadata?.description || '',
    'cenaPor': event.amount_czk,
    'datPor': event.duzp,
    'skupMaj': mapDepreciationGroup(event.metadata?.depreciation_group),
    'zpusOdpisu': event.metadata?.depreciation_method === 'accelerated' ? 'zpusOdpisu.zrychlene' : 'zpusOdpisu.rovnomerne',
  }
  return flexiRequest('POST', 'majetek.json', body, event.id)
}

// ─── PULL: Get data from Flexi ───────────────────────

/** Pull VAT summary (pripraveno pro budouci registraci k DPH) */
export async function pullVATReport(year, quarter) {
  const cfg = await getFlexiConfig()
  if (!cfg?.vat_payer) return { status: 'not_vat_payer', message: 'Firma neni platce DPH', data: null }
  return flexiRequest('GET', `evidence-dph/(datVyst >= '${year}-${(quarter-1)*3+1}-01' and datVyst <= '${year}-${quarter*3}-31').json`)
}

/** Pull account balances */
export async function pullAccountBalances() {
  return flexiRequest('GET', 'ucet.json')
}

/** Pull asset depreciation schedule */
export async function pullDepreciationSchedule(year) {
  return flexiRequest('GET', `majetek-odpis/(rok = ${year}).json`)
}

/** Test connection to Flexi */
export async function testFlexiConnection() {
  try {
    const result = await flexiRequest('GET', 'status.json')
    return { ok: true, version: result?.winstrom?.version, company: result?.winstrom?.nazevFirmy }
  } catch (e) {
    return { ok: false, error: e.message }
  }
}

// ─── MAPPING HELPERS ─────────────────────────────────

function mapDocumentType(subType) {
  const map = {
    'booking_payment': 'code:FAKTURA',
    'shop_payment': 'code:FAKTURA',
    'advance_invoice': 'code:ZALOHA',
    'payment_receipt': 'code:DOKLAD',
    'final_invoice': 'code:FAKTURA',
  }
  return map[subType] || 'code:FAKTURA'
}

function mapDepreciationGroup(group) {
  const map = { 1: 'skupMaj.sk1', 2: 'skupMaj.sk2', 3: 'skupMaj.sk3', 4: 'skupMaj.sk4', 5: 'skupMaj.sk5', 6: 'skupMaj.sk6' }
  return map[group] || 'skupMaj.sk2'
}

/** Map financial event to Flexi entity type */
export function mapEventToFlexiEntity(event) {
  const subType = event.metadata?.sub_type
  const mapping = {
    'revenue:booking_payment': 'faktura-vydana',
    'revenue:shop_payment': 'faktura-vydana',
    'expense:received_invoice': 'faktura-prijata',
    'expense:salary': 'mzda',
    'asset:fleet_purchase': 'majetek',
  }
  const key = `${event.event_type}:${subType}`
  return mapping[key] || 'banka'
}

/** Map Flexi account codes for double-entry */
export function mapFlexiAccounts(event) {
  const subType = event.metadata?.sub_type
  const accounts = {
    'revenue:booking_payment': { debit: '221000', credit: '602001' },
    'revenue:shop_payment': { debit: '221000', credit: '604001' },
    'expense:received_invoice': { debit: '518000', credit: '321000' },
    'expense:salary': { debit: '521000', credit: '331000' },
    'asset:fleet_purchase': { debit: '022000', credit: '321000' },
  }
  const key = `${event.event_type}:${subType}`
  return accounts[key] || { debit: '395000', credit: '395000' }
}
