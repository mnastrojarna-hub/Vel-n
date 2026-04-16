import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  parseV2Result, extractLicenseCategory, getModelId,
  debugLog, pollForResult, MINDEE_ENQUEUE_URL
} from './mindee-parser.ts'

const MINDEE_API_KEY = Deno.env.get('MINDEE_API_KEY') || ''
const MINDEE_MODEL_ID_ID = Deno.env.get('MINDEE_MODEL_ID') || ''
const MINDEE_MODEL_ID_DL = Deno.env.get('MINDEE_MODEL_DRIVERS_LICENSE') || ''
const MINDEE_MODEL_ID_PASSPORT = Deno.env.get('MINDEE_MODEL_PASSPORT') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
    const modelId = getModelId(docType, MINDEE_MODEL_ID_ID, MINDEE_MODEL_ID_DL, MINDEE_MODEL_ID_PASSPORT)

    await debugLog('invoke', docType, 'started', {
      document_type: docType, user_id: user_id || null,
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

    const binaryData = Uint8Array.from(atob(cleanBase64), (c) => c.charCodeAt(0))
    const blob = new Blob([binaryData], { type: 'image/jpeg' })

    // Step 1: Enqueue document to Mindee v2 API
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
          headers: { 'Authorization': MINDEE_API_KEY },
          body: formData,
        })

        if (resp.ok) {
          enqueueResult = await resp.json()
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
        success: false, error: 'Mindee API enqueue failed: ' + lastError,
      }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // Step 2: Extract job ID and poll for result
    const jobId = enqueueResult.job?.id || enqueueResult.id || enqueueResult.inference_id || enqueueResult.job_id || enqueueResult.inference?.id
    const pollingUrl = enqueueResult.job?.polling_url || enqueueResult.polling_url || enqueueResult.status_url || null

    console.log(`[scan-document] Enqueue response keys: ${JSON.stringify(Object.keys(enqueueResult))}`)
    if (enqueueResult.job) console.log(`[scan-document] job keys: ${JSON.stringify(Object.keys(enqueueResult.job))}`)
    if (enqueueResult.inference) console.log(`[scan-document] inference keys: ${JSON.stringify(Object.keys(enqueueResult.inference))}`)

    if (!jobId && !pollingUrl) {
      const maybeResult = enqueueResult.inference?.result || enqueueResult.result || enqueueResult.inference
      if (maybeResult && typeof maybeResult === 'object' && Object.keys(maybeResult).length > 0) {
        console.log('[scan-document] Enqueue returned immediate result — skipping polling')
        const inference = enqueueResult.inference || enqueueResult
        const prediction = inference?.result?.fields || inference?.prediction || inference?.fields || inference?.document?.inference?.prediction || inference
        if (prediction && typeof prediction === 'object' && Object.keys(prediction).length > 0) {
          const data = parseV2Result(prediction, docType)
          if (docType === 'dl') {
            const rawText = JSON.stringify(prediction)
            if (!data.licenseCategory) {
              const category = extractLicenseCategory(data, rawText)
              if (category) data.licenseCategory = category
            }
            if (!data.licenseNumber) {
              const dlMatch = rawText.match(/\b([A-Z]{2})\s*(\d{6})\b/)
              if (dlMatch) data.licenseNumber = dlMatch[1] + ' ' + dlMatch[2]
            }
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
        success: false, error: 'No job ID in Mindee response',
        raw_keys: Object.keys(enqueueResult),
      }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    console.log(`[scan-document] Job ID: ${jobId || 'none'}, polling_url: ${pollingUrl || 'default'}, polling for result...`)

    let mindeeResult: any
    try {
      mindeeResult = await pollForResult(jobId, MINDEE_API_KEY, pollingUrl)
    } catch (e) {
      const errMsg = String(e)
      await debugLog('mindee_poll', docType, 'error',
        { document_type: docType, job_id: jobId }, null, errMsg)
      return new Response(JSON.stringify({ success: false, error: errMsg }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Step 3: Parse the inference result
    const inference = mindeeResult.inference || mindeeResult.result || mindeeResult
    const prediction = inference?.result?.fields || inference?.prediction || inference?.fields || inference?.document?.inference?.prediction || inference

    if (!prediction || (typeof prediction === 'object' && Object.keys(prediction).length === 0)) {
      await debugLog('mindee_parse', docType, 'error',
        { document_type: docType, job_id: jobId },
        { raw_keys: Object.keys(mindeeResult || {}) },
        'No prediction in Mindee v2 response')
      return new Response(JSON.stringify({
        success: false, error: 'No prediction in Mindee v2 response',
        raw_keys: Object.keys(mindeeResult || {}),
      }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    const data = parseV2Result(prediction, docType)

    if (docType === 'dl') {
      let rawText = ''
      const pages = inference?.pages || mindeeResult?.pages || []
      for (const page of pages) {
        const extras = page?.extras?.full_text_ocr?.content || page?.raw_text || ''
        if (extras) rawText += ' ' + extras
      }
      rawText += ' ' + JSON.stringify(prediction)

      // Extract license category from raw text if not found in structured fields
      if (!data.licenseCategory) {
        const category = extractLicenseCategory(data, rawText)
        if (category) data.licenseCategory = category
      }

      // Try to extract license number from raw text if not found
      if (!data.licenseNumber) {
        // Czech ŘP number format: 2 letters + space + 6 digits (e.g. "EK 123456")
        const dlMatch = rawText.match(/\b([A-Z]{2})\s*(\d{6})\b/)
        if (dlMatch) {
          data.licenseNumber = dlMatch[1] + ' ' + dlMatch[2]
          console.log('[scan-document] Extracted DL number from raw text: ' + data.licenseNumber)
        }
      }

      console.log('[scan-document] DL fields: licenseNumber=' + (data.licenseNumber || 'null') +
        ', licenseCategory=' + (data.licenseCategory || 'null') +
        ', idNumber=' + (data.idNumber || 'null'))
    }

    const durationMs = Date.now() - startTime
    await debugLog('mindee_ocr', docType, 'success',
      { document_type: docType, user_id: user_id || null, job_id: jobId, api_version: 'v2' },
      { fields_found: Object.keys(data).length, fields: Object.keys(data), duration_ms: durationMs })

    return new Response(JSON.stringify({
      success: true, data,
      fields_count: Object.keys(data).filter(k => !!data[k]).length,
    }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })

  } catch (e) {
    console.error('[scan-document] Error:', e)
    await debugLog('invoke', 'unknown', 'error', null, null, 'Unhandled: ' + String(e))
    return new Response(JSON.stringify({ success: false, error: String(e) }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
