import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const MINDEE_API_KEY = Deno.env.get('MINDEE_API_KEY') || ''
// 3 separate model IDs for each document type (matching Supabase secret names)
const MINDEE_MODEL_ID_ID = Deno.env.get('MINDEE_MODEL_ID') || ''
const MINDEE_MODEL_ID_DL = Deno.env.get('MINDEE_MODEL_DRIVERS_LICENSE') || ''
const MINDEE_MODEL_ID_PASSPORT = Deno.env.get('MINDEE_MODEL_PASSPORT') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

// Map document_type to correct model ID
function getModelId(docType: string): string {
  switch (docType) {
    case 'dl': return MINDEE_MODEL_ID_DL
    case 'passport': return MINDEE_MODEL_ID_PASSPORT
    case 'id': default: return MINDEE_MODEL_ID_ID
  }
}

// Mindee v2 API endpoints (matching official SDK: /v2/products/extraction/)
const MINDEE_BASE = 'https://api-v2.mindee.net'
const MINDEE_ENQUEUE_URL = `${MINDEE_BASE}/v2/products/extraction/enqueue`
const MINDEE_JOBS_URL = `${MINDEE_BASE}/v2/jobs`
const MINDEE_RESULTS_URL = `${MINDEE_BASE}/v2/products/extraction/results`

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface MindeeField {
  value?: string | null
  confidence?: number
}

function extractField(field: MindeeField | undefined): string {
  if (!field || !field.value) return ''
  return String(field.value).trim()
}

function extractDate(field: MindeeField | undefined): string {
  const val = extractField(field)
  if (!val) return ''
  if (/^\d{4}-\d{2}-\d{2}$/.test(val)) return val
  const m = val.match(/(\d{2})[./](\d{2})[./](\d{4})/)
  if (m) return `${m[3]}-${m[2]}-${m[1]}`
  return val
}

// Parse fields from Mindee v2 inference result
// v2 returns a unified structure — fields may be in result.fields or result.prediction
function parseV2Result(result: Record<string, any>, docType: string): Record<string, string> {
  const data: Record<string, string> = {}

  // v2 may nest fields differently — try multiple paths
  const fields = result.fields || result.prediction || result

  // Helper to get field value from various formats
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

  // Names — try various field name conventions
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

  // Date of birth
  const dob = getDateVal('birth_date') || getDateVal('date_of_birth')
  if (dob) data.dob = dob

  // Document number
  const docNum = getVal('document_number') || getVal('id_number') || getVal('number')
  if (docNum) data.idNumber = docNum

  // Address
  const addr = getVal('address') || getVal('birth_place')
  if (addr) {
    if (getVal('address')) data.address = addr
    else data.birthPlace = addr
  }

  // Sex / Gender
  const sex = getVal('sex') || getVal('gender')
  if (sex) data.sex = sex

  // Nationality
  const nat = getVal('nationality') || getVal('country')
  if (nat) data.nationality = nat

  // Dates
  const expiry = getDateVal('expiry_date') || getDateVal('expiration_date')
  if (expiry) data.expiryDate = expiry
  const issued = getDateVal('issue_date') || getDateVal('issuance_date')
  if (issued) data.issuedDate = issued

  // MRZ
  const mrz1 = getVal('mrz1') || getVal('mrz_line1')
  const mrz2 = getVal('mrz2') || getVal('mrz_line2')
  const mrz3 = getVal('mrz3') || getVal('mrz_line3')
  if (mrz1) data.mrz1 = mrz1
  if (mrz2) data.mrz2 = mrz2
  if (mrz3) data.mrz3 = mrz3

  // Document type (for classification: IDENTIFICATION_CARD, PASSPORT, DRIVER_LICENCE, etc.)
  const dt = getVal('document_type') || getVal('classification')
  if (dt) data.documentType = dt

  // License categories for DL
  if (docType === 'dl') {
    const cats = getVal('license_categories') || getVal('categories') || getVal('vehicle_categories')
    if (cats) data.licenseCategory = cats
    if (data.idNumber) data.licenseNumber = data.idNumber
  }

  return data
}

// Extract license categories from raw text
function extractLicenseCategory(data: Record<string, string>, rawText: string): string {
  const categories = ['AM', 'A1', 'A2', 'A', 'B1', 'B', 'C1', 'C', 'D1', 'D', 'BE', 'CE', 'DE', 'T']
  const found: string[] = []
  const searchText = (data.documentType || '') + ' ' + (data.licenseCategory || '') + ' ' + rawText
  for (const cat of categories) {
    const regex = new RegExp('\\b' + cat + '\\b', 'i')
    if (regex.test(searchText)) found.push(cat)
  }
  return found.length > 0 ? found.join(', ') : ''
}

// Helper: log to debug_log
async function debugLog(action: string, component: string, status: string, requestData: any, responseData: any, errorMessage?: string) {
  try {
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

// Mindee v2 polling per OpenAPI spec:
// GET /v2/jobs/{id}?redirect=false → always 200 with job status
// Status: "Processing" | "Failed" | "Processed" (capital P!)
// When "Processed": result_url is filled → GET result_url for inference data
async function pollForResult(jobId: string, pollingUrl?: string, maxAttempts: number = 25): Promise<any> {
  // CRITICAL: ?redirect=false prevents 302 which loses auth header on redirect
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
        headers: { 'Authorization': MINDEE_API_KEY },
        redirect: 'manual', // Don't auto-follow 302 (loses auth header)
      })
    } catch (e) {
      console.warn(`[scan-document] Poll ${i + 1} network error:`, e)
      continue
    }

    // Handle 302 manually (in case redirect=false didn't work)
    if (resp.status === 302) {
      const location = resp.headers.get('Location') || resp.headers.get('location')
      console.log(`[scan-document] 302 → ${location}`)
      if (location) {
        const rr = await fetch(location, { method: 'GET', headers: { 'Authorization': MINDEE_API_KEY } })
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

    // OpenAPI Status enum: "Processing", "Failed", "Processed"
    if (status === 'Processed' || status === 'processed' || status === 'completed' || status === 'succeeded') {
      // Try result_url from job first
      if (job.result_url) {
        console.log(`[scan-document] Fetching result from result_url: ${job.result_url}`)
        const resultResp = await fetch(job.result_url, {
          method: 'GET',
          headers: { 'Authorization': MINDEE_API_KEY },
        })
        if (resultResp.ok) return await resultResp.json()
        console.warn(`[scan-document] result_url failed: ${resultResp.status}`)
      }
      // Fallback: construct results URL (SDK pattern)
      const inferenceId = job.inference_id || job.id || jobId
      const resultsUrl = `${MINDEE_RESULTS_URL}/${inferenceId}`
      console.log(`[scan-document] Fetching result from constructed URL: ${resultsUrl}`)
      const resultResp2 = await fetch(resultsUrl, {
        method: 'GET',
        headers: { 'Authorization': MINDEE_API_KEY },
      })
      if (resultResp2.ok) return await resultResp2.json()
      // Last fallback: return job data itself
      return data
    }
    if (status === 'Failed' || status === 'failed') {
      throw new Error('Mindee inference failed: ' + JSON.stringify(job.error || data))
    }
    // "Processing" — continue polling
  }
  throw new Error('Mindee polling timeout after ' + maxAttempts + ' attempts')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const startTime = Date.now()

  try {
    const body = await req.json()
    const { image_base64, document_type, user_id } = body

    console.log('[scan-document] Invoked: document_type=' + (document_type || 'id') +
      ' user_id=' + (user_id || 'anon') +
      ' image_len=' + (image_base64 ? image_base64.length : 0) +
      ' MINDEE_KEY_SET=' + (!!MINDEE_API_KEY))

    const docType = document_type || 'id'
    const modelId = getModelId(docType)

    await debugLog('invoke', docType, 'started', {
      document_type: docType,
      user_id: user_id || null,
      image_length: image_base64 ? image_base64.length : 0,
      mindee_key_set: !!MINDEE_API_KEY,
      model_id: modelId ? '***' + modelId.slice(-4) : 'MISSING',
      api_version: 'v2',
    }, null)

    if (!image_base64) {
      await debugLog('invoke', document_type || 'id', 'error', null, null, 'Missing image_base64')
      return new Response(JSON.stringify({ success: false, error: 'Missing image_base64' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    if (!MINDEE_API_KEY) {
      await debugLog('invoke', document_type || 'id', 'error', null, null, 'MINDEE_API_KEY not configured')
      return new Response(JSON.stringify({ success: false, error: 'MINDEE_API_KEY not configured' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    if (!modelId) {
      await debugLog('invoke', docType, 'error', null, null, `MINDEE_MODEL_ID_${docType.toUpperCase()} not configured`)
      return new Response(JSON.stringify({ success: false, error: `Model ID not configured for type '${docType}' — set MINDEE_MODEL_ID_ID, MINDEE_MODEL_ID_DL, MINDEE_MODEL_ID_PASSPORT in Supabase Secrets` }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Strip data URI prefix if present
    let cleanBase64 = image_base64
    if (cleanBase64.includes(',')) {
      cleanBase64 = cleanBase64.split(',')[1]
    }

    // Convert base64 to binary for multipart upload
    const binaryData = Uint8Array.from(atob(cleanBase64), (c) => c.charCodeAt(0))
    const blob = new Blob([binaryData], { type: 'image/jpeg' })

    // ═══════════════════════════════════════════════
    // Step 1: Enqueue document to Mindee v2 API
    // ═══════════════════════════════════════════════
    const formData = new FormData()
    formData.append('file', blob, 'document.jpg')
    formData.append('model_id', modelId)
    formData.append('rag', 'false')

    let enqueueResult: any = null
    let lastError = ''

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        console.log(`[scan-document] Enqueue attempt ${attempt + 1}/3 to ${MINDEE_ENQUEUE_URL}`)

        const resp = await fetch(MINDEE_ENQUEUE_URL, {
          method: 'POST',
          headers: {
            'Authorization': MINDEE_API_KEY,
          },
          body: formData,
        })

        if (resp.ok) {
          enqueueResult = await resp.json()
          // Log FULL enqueue response for debugging
          const fullJson = JSON.stringify(enqueueResult)
          console.log('[scan-document] Enqueue OK (full):', fullJson.substring(0, 500))
          await debugLog('mindee_enqueue', docType, 'success',
            { document_type: docType, model_id: modelId },
            { enqueue_response: enqueueResult, response_keys: Object.keys(enqueueResult) })
          break
        } else {
          const errBody = await resp.text()
          lastError = `HTTP ${resp.status}: ${errBody}`
          console.error(`[scan-document] Enqueue attempt ${attempt + 1} failed:`, lastError)
          if (resp.status === 401 || resp.status === 403) break
          if (attempt < 2) await new Promise(r => setTimeout(r, 1000 * (attempt + 1)))
        }
      } catch (e) {
        lastError = String(e)
        console.error(`[scan-document] Enqueue network error attempt ${attempt + 1}:`, e)
        if (attempt < 2) await new Promise(r => setTimeout(r, 1000 * (attempt + 1)))
      }
    }

    if (!enqueueResult) {
      await debugLog('mindee_enqueue', docType, 'error',
        { document_type: docType, user_id: user_id || null, model_id: modelId },
        null, 'Mindee v2 enqueue failed: ' + lastError)
      return new Response(JSON.stringify({
        success: false,
        error: 'Mindee API enqueue failed: ' + lastError,
      }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // ═══════════════════════════════════════════════
    // Step 2: Extract job ID and poll for result
    // ═══════════════════════════════════════════════
    // Try all known response formats for job ID and polling URL
    const jobId = enqueueResult.job?.id || enqueueResult.id || enqueueResult.inference_id || enqueueResult.job_id || enqueueResult.inference?.id
    // Polling URL: prefer explicit from response, fallback to constructed URL
    const pollingUrl = enqueueResult.job?.polling_url || enqueueResult.polling_url || enqueueResult.status_url || null

    console.log(`[scan-document] Enqueue response keys: ${JSON.stringify(Object.keys(enqueueResult))}`)
    if (enqueueResult.job) console.log(`[scan-document] job keys: ${JSON.stringify(Object.keys(enqueueResult.job))}`)
    if (enqueueResult.inference) console.log(`[scan-document] inference keys: ${JSON.stringify(Object.keys(enqueueResult.inference))}`)

    if (!jobId && !pollingUrl) {
      // Maybe the response already contains the result (synchronous mode?)
      const maybeResult = enqueueResult.inference?.result || enqueueResult.result || enqueueResult.inference
      if (maybeResult && typeof maybeResult === 'object' && Object.keys(maybeResult).length > 0) {
        console.log('[scan-document] Enqueue returned immediate result — skipping polling')
        // Jump directly to parsing
        const inference = enqueueResult.inference || enqueueResult
        const prediction = inference?.result?.fields || inference?.prediction || inference?.fields || inference?.document?.inference?.prediction || inference
        if (prediction && typeof prediction === 'object' && Object.keys(prediction).length > 0) {
          const data = parseV2Result(prediction, docType)
          if (docType === 'dl' && !data.licenseCategory) {
            const rawText = JSON.stringify(prediction)
            const category = extractLicenseCategory(data, rawText)
            if (category) data.licenseCategory = category
            if (data.idNumber && !data.licenseNumber) data.licenseNumber = data.idNumber
          }
          const durationMs = Date.now() - startTime
          await debugLog('mindee_ocr', docType, 'success',
            { document_type: docType, user_id: user_id || null, api_version: 'v2', mode: 'immediate' },
            { fields_found: Object.keys(data).length, fields: Object.keys(data), duration_ms: durationMs })
          return new Response(JSON.stringify({ success: true, data, fields_count: Object.keys(data).filter(k => !!data[k]).length }), {
            status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
          })
        }
      }

      await debugLog('mindee_enqueue', docType, 'error',
        { document_type: docType },
        { raw: enqueueResult, raw_keys: Object.keys(enqueueResult) },
        'No job ID or polling URL in Mindee enqueue response')
      return new Response(JSON.stringify({
        success: false,
        error: 'No job ID in Mindee response',
        raw_keys: Object.keys(enqueueResult),
      }), {
        status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    console.log(`[scan-document] Job ID: ${jobId || 'none'}, polling_url: ${pollingUrl || 'default'}, polling for result...`)

    let mindeeResult: any
    try {
      mindeeResult = await pollForResult(jobId, pollingUrl)
    } catch (e) {
      const errMsg = String(e)
      await debugLog('mindee_poll', docType, 'error',
        { document_type: docType, job_id: jobId },
        null, errMsg)
      return new Response(JSON.stringify({
        success: false,
        error: errMsg,
      }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // ═══════════════════════════════════════════════
    // Step 3: Parse the inference result
    // ═══════════════════════════════════════════════
    // v2 response structure may vary — try multiple paths
    const inference = mindeeResult.inference || mindeeResult.result || mindeeResult
    const prediction = inference?.result?.fields || inference?.prediction || inference?.fields || inference?.document?.inference?.prediction || inference

    if (!prediction || (typeof prediction === 'object' && Object.keys(prediction).length === 0)) {
      await debugLog('mindee_parse', docType, 'error',
        { document_type: docType, job_id: jobId },
        { raw_keys: Object.keys(mindeeResult || {}) },
        'No prediction in Mindee v2 response')
      return new Response(JSON.stringify({
        success: false,
        error: 'No prediction in Mindee v2 response',
        raw_keys: Object.keys(mindeeResult || {}),
      }), {
        status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Parse using unified v2 parser
    const data = parseV2Result(prediction, docType)

    // Extract license category for DL scans from raw text if not already found
    if (docType === 'dl' && !data.licenseCategory) {
      // Try to get raw text from v2 response
      let rawText = ''
      const pages = inference?.pages || mindeeResult?.pages || []
      for (const page of pages) {
        const extras = page?.extras?.full_text_ocr?.content || page?.raw_text || ''
        if (extras) rawText += ' ' + extras
      }
      // Also search in the full JSON for category patterns
      rawText += ' ' + JSON.stringify(prediction)
      const category = extractLicenseCategory(data, rawText)
      if (category) data.licenseCategory = category
      if (data.idNumber && !data.licenseNumber) data.licenseNumber = data.idNumber
    }

    // Log success
    const durationMs = Date.now() - startTime
    await debugLog('mindee_ocr', docType, 'success',
      { document_type: docType, user_id: user_id || null, job_id: jobId, api_version: 'v2' },
      { fields_found: Object.keys(data).length, fields: Object.keys(data), duration_ms: durationMs })

    return new Response(JSON.stringify({
      success: true,
      data,
      fields_count: Object.keys(data).filter(k => !!data[k]).length,
    }), {
      status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (e) {
    console.error('[scan-document] Error:', e)
    await debugLog('invoke', 'unknown', 'error', null, null, 'Unhandled: ' + String(e))
    return new Response(JSON.stringify({
      success: false,
      error: String(e),
    }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
