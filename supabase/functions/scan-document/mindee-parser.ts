// ===== scan-document/mindee-parser.ts =====
// Mindee v2 result parsing, field extraction, license category extraction, and polling

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const MINDEE_BASE = 'https://api-v2.mindee.net'
export const MINDEE_ENQUEUE_URL = `${MINDEE_BASE}/v2/products/extraction/enqueue`
export const MINDEE_JOBS_URL = `${MINDEE_BASE}/v2/jobs`
export const MINDEE_RESULTS_URL = `${MINDEE_BASE}/v2/products/extraction/results`

interface MindeeField {
  value?: string | null
  confidence?: number
}

function extractField(field: MindeeField | undefined): string {
  if (!field || !field.value) return ''
  return String(field.value).trim()
}

// Parse fields from Mindee v2 inference result
export function parseV2Result(result: Record<string, any>, docType: string): Record<string, string> {
  const data: Record<string, string> = {}

  const fields = result.fields || result.prediction || result

  function getVal(key: string): string {
    const f = fields[key]
    if (!f) return ''
    if (typeof f === 'string') return f.trim()
    if (typeof f === 'object' && f.value !== undefined && f.value !== null) return String(f.value).trim()
    return ''
  }

  function getDateVal(key: string): string {
    const v = getVal(key)
    if (!v) return ''
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v
    const m = v.match(/(\d{2})[./](\d{2})[./](\d{4})/)
    if (m) return `${m[3]}-${m[2]}-${m[1]}`
    return v
  }

  // Names
  const surnames = fields.surnames || fields.surname || fields.last_name || fields.family_name
  const givenNames = fields.given_names || fields.given_name || fields.first_name

  if (surnames) {
    if (Array.isArray(surnames)) {
      data.lastName = surnames.map((s: any) => typeof s === 'string' ? s : extractField(s)).join(' ')
    } else {
      data.lastName = typeof surnames === 'string' ? surnames : extractField(surnames)
    }
  }
  if (givenNames) {
    if (Array.isArray(givenNames)) {
      data.firstName = givenNames.map((g: any) => typeof g === 'string' ? g : extractField(g)).join(' ')
    } else {
      data.firstName = typeof givenNames === 'string' ? givenNames : extractField(givenNames)
    }
  }

  const dob = getDateVal('birth_date') || getDateVal('date_of_birth')
  if (dob) data.dob = dob

  const docNum = getVal('document_number') || getVal('id_number') || getVal('number')
  if (docNum) data.idNumber = docNum

  // Address — try structured components first, fall back to flat string.
  // Czech OP back side: Mindee may return either "address" as one string
  // (e.g. "Rokycanova 123/45, 130 00 Praha 3") or separate fields.
  const rawStreet = getVal('street') || getVal('address_line_1') || getVal('street_name')
  const rawCity = getVal('city') || getVal('locality') || getVal('municipality')
  const rawZip = getVal('postal_code') || getVal('zip') || getVal('zip_code') || getVal('post_code')
  if (rawStreet) data.street = rawStreet
  if (rawCity) data.city = rawCity
  if (rawZip) data.zip = rawZip

  const addr = getVal('address') || getVal('birth_place')
  if (addr) {
    if (getVal('address')) {
      data.address = addr
      // If structured components are missing, parse flat address
      if (!data.street || !data.city || !data.zip) {
        const parsed = parseCzechAddress(addr)
        if (parsed.street && !data.street) data.street = parsed.street
        if (parsed.city && !data.city) data.city = parsed.city
        if (parsed.zip && !data.zip) data.zip = parsed.zip
      }
    } else {
      data.birthPlace = addr
    }
  }

  const sex = getVal('sex') || getVal('gender')
  if (sex) data.sex = sex

  const nat = getVal('nationality') || getVal('country')
  if (nat) data.nationality = nat

  // Expiry — try all common naming variants across Mindee models
  // (National ID, Driver's License, Passport have different schemas).
  const expiry = getDateVal('expiry_date') || getDateVal('expiration_date')
    || getDateVal('date_of_expiry') || getDateVal('valid_until')
    || getDateVal('validity_end') || getDateVal('end_of_validity')
  if (expiry) data.expiryDate = expiry
  const issued = getDateVal('issue_date') || getDateVal('issuance_date')
    || getDateVal('date_of_issue') || getDateVal('valid_from')
  if (issued) data.issuedDate = issued

  const mrz1 = getVal('mrz1') || getVal('mrz_line1')
  const mrz2 = getVal('mrz2') || getVal('mrz_line2')
  const mrz3 = getVal('mrz3') || getVal('mrz_line3')
  if (mrz1) data.mrz1 = mrz1
  if (mrz2) data.mrz2 = mrz2
  if (mrz3) data.mrz3 = mrz3

  const dt = getVal('document_type') || getVal('classification')
  if (dt) data.documentType = dt

  if (docType === 'dl') {
    const cats = getVal('license_categories') || getVal('categories') || getVal('vehicle_categories')
    if (cats) data.licenseCategory = cats

    // Try multiple field names for the DL number (Czech ŘP, EU formats)
    const dlNum = getVal('license_number') || getVal('permit_number') ||
      getVal('card_number') || getVal('dl_number') ||
      getVal('driving_license_number') || getVal('licence_number') ||
      data.idNumber || ''
    if (dlNum) {
      data.licenseNumber = dlNum
    }
  }

  return data
}

// Parse Czech address string ("Ulice 123/45, 130 00 Praha 3") into
// { street, city, zip } components. Tolerant to missing commas.
export function parseCzechAddress(raw: string): { street?: string; city?: string; zip?: string } {
  const out: { street?: string; city?: string; zip?: string } = {}
  const trimmed = raw.trim()
  if (!trimmed) return out

  const zipMatch = trimmed.match(/(\d{3})\s?(\d{2})/)
  let zip: string | undefined
  let withoutZip = trimmed
  if (zipMatch) {
    zip = `${zipMatch[1]} ${zipMatch[2]}`
    withoutZip = trimmed.slice(0, zipMatch.index!) + '|' +
      trimmed.slice(zipMatch.index! + zipMatch[0].length)
  }

  if (withoutZip.includes(',')) {
    const parts = withoutZip.split(',').map(p => p.trim())
    if (parts.length >= 2) {
      out.street = parts[0].replace(/\|/g, '').trim() || undefined
      const cityRaw = parts.slice(1).join(' ').replace(/\|/g, '').trim()
      if (cityRaw) out.city = cityRaw
    } else {
      out.street = withoutZip.replace(/\|/g, '').trim() || undefined
    }
  } else if (zip) {
    const parts = withoutZip.split('|').map(p => p.trim())
    if (parts.length === 2) {
      if (parts[0]) out.street = parts[0]
      if (parts[1]) out.city = parts[1]
    } else if (parts.length === 1 && parts[0]) {
      out.street = parts[0]
    }
  } else {
    out.street = trimmed
  }

  if (zip) out.zip = zip
  return out
}

export function extractLicenseCategory(data: Record<string, string>, rawText: string): string {
  const categories = ['AM', 'A1', 'A2', 'A', 'B1', 'B', 'C1', 'C', 'D1', 'D', 'BE', 'CE', 'DE', 'T']
  const found: string[] = []
  const searchText = (data.documentType || '') + ' ' + (data.licenseCategory || '') + ' ' + rawText
  for (const cat of categories) {
    const regex = new RegExp('\\b' + cat + '\\b', 'i')
    if (regex.test(searchText)) found.push(cat)
  }
  return found.length > 0 ? found.join(', ') : ''
}

export function getModelId(
  docType: string,
  modelIdId: string,
  modelIdDl: string,
  modelIdPassport: string
): string {
  switch (docType) {
    case 'dl': return modelIdDl
    case 'passport': return modelIdPassport
    case 'id': default: return modelIdId
  }
}

// Helper: log to debug_log
export async function debugLog(
  action: string, component: string, status: string,
  requestData: any, responseData: any, errorMessage?: string
) {
  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
    const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    await supabase.from('debug_log').insert({
      source: 'scan-document',
      action,
      component,
      status,
      request_data: requestData,
      response_data: responseData,
      error_message: errorMessage || null,
      duration_ms: 0,
    })
  } catch (e) {
    console.warn('[scan-document] debugLog failed:', e)
  }
}

// Mindee v2 polling
export async function pollForResult(
  jobId: string,
  mindeeApiKey: string,
  pollingUrl?: string,
  maxAttempts: number = 25
): Promise<any> {
  let pollUrl = pollingUrl || `${MINDEE_JOBS_URL}/${jobId}`
  if (!pollUrl.includes('redirect=')) pollUrl += (pollUrl.includes('?') ? '&' : '?') + 'redirect=false'
  console.log(`[scan-document] pollForResult: pollUrl=${pollUrl}`)

  for (let i = 0; i < maxAttempts; i++) {
    await new Promise(r => setTimeout(r, i === 0 ? 2000 : 1500))

    console.log(`[scan-document] Poll ${i + 1}/${maxAttempts}`)

    let resp: Response
    try {
      resp = await fetch(pollUrl, {
        method: 'GET',
        headers: { 'Authorization': mindeeApiKey },
        redirect: 'manual',
      })
    } catch (e) {
      console.warn(`[scan-document] Poll ${i + 1} network error:`, e)
      continue
    }

    if (resp.status === 302) {
      const location = resp.headers.get('Location') || resp.headers.get('location')
      console.log(`[scan-document] 302 -> ${location}`)
      if (location) {
        const rr = await fetch(location, { method: 'GET', headers: { 'Authorization': mindeeApiKey } })
        if (rr.ok) return await rr.json()
        console.warn(`[scan-document] Redirect fetch: ${rr.status}`)
      }
      continue
    }

    if (!resp.ok) {
      const errBody = await resp.text()
      console.warn(`[scan-document] Poll ${i + 1}: HTTP ${resp.status}: ${errBody.substring(0, 200)}`)
      if (resp.status === 401 || resp.status === 403) throw new Error(`Auth error: ${errBody}`)
      if (resp.status === 404 && i < 8) continue
      if (resp.status === 404) throw new Error(`Job not found: ${errBody}`)
      continue
    }

    const data = await resp.json()
    const job = data.job || data
    const status = job.status || ''
    console.log(`[scan-document] Poll ${i + 1}: status="${status}", result_url=${job.result_url || 'null'}`)

    if (status === 'Processed' || status === 'processed' || status === 'completed' || status === 'succeeded') {
      if (job.result_url) {
        console.log(`[scan-document] Fetching result from result_url: ${job.result_url}`)
        const resultResp = await fetch(job.result_url, {
          method: 'GET',
          headers: { 'Authorization': mindeeApiKey },
        })
        if (resultResp.ok) return await resultResp.json()
        console.warn(`[scan-document] result_url failed: ${resultResp.status}`)
      }
      const inferenceId = job.inference_id || job.id || jobId
      const resultsUrl = `${MINDEE_RESULTS_URL}/${inferenceId}`
      console.log(`[scan-document] Fetching result from constructed URL: ${resultsUrl}`)
      const resultResp2 = await fetch(resultsUrl, {
        method: 'GET',
        headers: { 'Authorization': mindeeApiKey },
      })
      if (resultResp2.ok) return await resultResp2.json()
      return data
    }
    if (status === 'Failed' || status === 'failed') {
      throw new Error('Mindee inference failed: ' + JSON.stringify(job.error || data))
    }
  }
  throw new Error('Mindee polling timeout after ' + maxAttempts + ' attempts')
}
