import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const MINDEE_API_KEY = Deno.env.get('MINDEE_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Mindee API endpoints per document type
const MINDEE_ENDPOINTS: Record<string, string> = {
  id: 'https://api.mindee.net/v1/products/mindee/international_id/v2/predict',
  dl: 'https://api.mindee.net/v1/products/mindee/international_id/v2/predict',
  passport: 'https://api.mindee.net/v1/products/mindee/passport/v1/predict',
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
  // Already ISO format YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(val)) return val
  // Try DD/MM/YYYY or DD.MM.YYYY
  const m = val.match(/(\d{2})[./](\d{2})[./](\d{4})/)
  if (m) return `${m[3]}-${m[2]}-${m[1]}`
  return val
}

// Parse Mindee international_id response
function parseInternationalId(prediction: Record<string, any>): Record<string, string> {
  const result: Record<string, string> = {}

  // Names
  const surnames = prediction.surnames || []
  const givenNames = prediction.given_names || []
  if (surnames.length > 0) result.lastName = surnames.map((s: MindeeField) => extractField(s)).join(' ')
  if (givenNames.length > 0) result.firstName = givenNames.map((g: MindeeField) => extractField(g)).join(' ')

  // Date of birth
  if (prediction.birth_date) result.dob = extractDate(prediction.birth_date)

  // Document number
  if (prediction.document_number) result.idNumber = extractField(prediction.document_number)

  // Address
  if (prediction.address) result.address = extractField(prediction.address)
  // Some docs return birth_place instead
  if (!result.address && prediction.birth_place) result.birthPlace = extractField(prediction.birth_place)

  // Sex
  if (prediction.sex) result.sex = extractField(prediction.sex)

  // Nationality
  if (prediction.nationality) result.nationality = extractField(prediction.nationality)

  // Expiry & issue dates
  if (prediction.expiry_date) result.expiryDate = extractDate(prediction.expiry_date)
  if (prediction.issue_date) result.issuedDate = extractDate(prediction.issue_date)

  // MRZ (Machine Readable Zone)
  if (prediction.mrz1) result.mrz1 = extractField(prediction.mrz1)
  if (prediction.mrz2) result.mrz2 = extractField(prediction.mrz2)
  if (prediction.mrz3) result.mrz3 = extractField(prediction.mrz3)

  // Document type (for DL: extract license category)
  if (prediction.document_type) result.documentType = extractField(prediction.document_type)

  return result
}

// Parse Mindee passport response
function parsePassport(prediction: Record<string, any>): Record<string, string> {
  const result: Record<string, string> = {}

  if (prediction.surname) result.lastName = extractField(prediction.surname)
  if (prediction.given_names && prediction.given_names.length > 0) {
    result.firstName = prediction.given_names.map((g: MindeeField) => extractField(g)).join(' ')
  }
  if (prediction.birth_date) result.dob = extractDate(prediction.birth_date)
  if (prediction.id_number) result.idNumber = extractField(prediction.id_number)
  if (prediction.gender) result.sex = extractField(prediction.gender)
  if (prediction.nationality) result.nationality = extractField(prediction.nationality)
  if (prediction.expiry_date) result.expiryDate = extractDate(prediction.expiry_date)
  if (prediction.issuance_date) result.issuedDate = extractDate(prediction.issuance_date)
  if (prediction.birth_place) result.birthPlace = extractField(prediction.birth_place)

  return result
}

// Extract license categories from DL scan (from raw text or document_type)
function extractLicenseCategory(data: Record<string, string>, rawText: string): string {
  // Common Czech/EU license categories
  const categories = ['AM', 'A1', 'A2', 'A', 'B1', 'B', 'C1', 'C', 'D1', 'D', 'BE', 'CE', 'DE', 'T']
  const found: string[] = []

  const searchText = (data.documentType || '') + ' ' + rawText
  for (const cat of categories) {
    // Match standalone category (not part of another word)
    const regex = new RegExp('\\b' + cat + '\\b', 'i')
    if (regex.test(searchText)) found.push(cat)
  }

  return found.length > 0 ? found.join(', ') : ''
}

// Helper: log to debug_log (best-effort, non-blocking)
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

    // Log entry — so we can see the function WAS called even if it fails later
    await debugLog('invoke', document_type || 'id', 'started', {
      document_type: document_type || 'id',
      user_id: user_id || null,
      image_length: image_base64 ? image_base64.length : 0,
      mindee_key_set: !!MINDEE_API_KEY,
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

    const docType = document_type || 'id'
    const endpoint = MINDEE_ENDPOINTS[docType] || MINDEE_ENDPOINTS.id

    // Strip data URI prefix if present
    let cleanBase64 = image_base64
    if (cleanBase64.includes(',')) {
      cleanBase64 = cleanBase64.split(',')[1]
    }

    // Convert base64 to binary for multipart upload
    const binaryData = Uint8Array.from(atob(cleanBase64), (c) => c.charCodeAt(0))
    const blob = new Blob([binaryData], { type: 'image/jpeg' })

    // Build multipart form data
    const formData = new FormData()
    formData.append('document', blob, 'document.jpg')

    // Call Mindee API with retry
    let mindeeResult: any = null
    let lastError = ''

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const resp = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'Authorization': `Token ${MINDEE_API_KEY}`,
          },
          body: formData,
        })

        if (resp.ok) {
          mindeeResult = await resp.json()
          break
        } else {
          const errBody = await resp.text()
          lastError = `HTTP ${resp.status}: ${errBody}`
          console.error(`[scan-document] Mindee attempt ${attempt + 1} failed:`, lastError)

          // Don't retry on auth errors
          if (resp.status === 401 || resp.status === 403) break

          // Wait before retry
          if (attempt < 2) await new Promise(r => setTimeout(r, 1000 * (attempt + 1)))
        }
      } catch (e) {
        lastError = String(e)
        console.error(`[scan-document] Mindee network error attempt ${attempt + 1}:`, e)
        if (attempt < 2) await new Promise(r => setTimeout(r, 1000 * (attempt + 1)))
      }
    }

    if (!mindeeResult) {
      await debugLog('mindee_call', docType, 'error',
        { document_type: docType, user_id: user_id || null, endpoint },
        null, 'Mindee API failed: ' + lastError)
      return new Response(JSON.stringify({
        success: false,
        error: 'Mindee API failed: ' + lastError,
      }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Extract prediction from Mindee response
    const prediction = mindeeResult?.document?.inference?.prediction
    if (!prediction) {
      await debugLog('mindee_parse', docType, 'error',
        { document_type: docType, user_id: user_id || null },
        { raw_keys: Object.keys(mindeeResult || {}) },
        'No prediction in Mindee response')
      return new Response(JSON.stringify({
        success: false,
        error: 'No prediction in Mindee response',
        raw: mindeeResult,
      }), {
        status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Parse based on document type
    let data: Record<string, string>
    if (docType === 'passport') {
      data = parsePassport(prediction)
    } else {
      data = parseInternationalId(prediction)
    }

    // Extract license category for DL scans
    if (docType === 'dl') {
      const rawPages = mindeeResult?.document?.inference?.pages || []
      let rawText = ''
      for (const page of rawPages) {
        const extras = page?.extras?.full_text_ocr?.content
        if (extras) rawText += ' ' + extras
      }
      const category = extractLicenseCategory(data, rawText)
      if (category) data.licenseCategory = category

      // For DL, the document number is the license number
      if (data.idNumber) data.licenseNumber = data.idNumber
    }

    // Log success to debug_log
    const durationMs = Date.now() - startTime
    await debugLog('mindee_ocr', docType, 'success',
      { document_type: docType, user_id: user_id || null },
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
