// ===== MotoGo24 – Edge Function: Datová Schránka =====
// Prepares and optionally sends approved reports to Czech government
// via ISDS (Informační systém datových schránek).
//
// Two-stage process:
//   1. Always: Generate XML, store in Storage bucket
//   2. If ISDS credentials exist: Send via API
//   3. If not: Return file path for manual upload

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Report type → recipient mapping
const RECIPIENT_MAP: Record<string, { envKey: string; label: string }> = {
  'vat_return':    { envKey: 'DS_FINANCNI_URAD', label: 'Finanční úřad' },
  'income_tax':    { envKey: 'DS_FINANCNI_URAD', label: 'Finanční úřad' },
  'balance_sheet': { envKey: 'DS_FINANCNI_URAD', label: 'Finanční úřad' },
  'profit_loss':   { envKey: 'DS_FINANCNI_URAD', label: 'Finanční úřad' },
  'ossz':          { envKey: 'DS_CSSZ',          label: 'ČSSZ' },
  'vzp':           { envKey: 'DS_VZP',           label: 'VZP' },
}

const REPORT_LABELS: Record<string, string> = {
  'vat_return': 'Přiznání k DPH',
  'income_tax': 'Daňové přiznání',
  'balance_sheet': 'Rozvaha',
  'profit_loss': 'Výsledovka',
  'ossz': 'Přehled OSSZ',
  'vzp': 'Přehled VZP',
  'cash_flow': 'Výkaz cash flow',
  'accounting_closing': 'Účetní uzávěrka',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const { report_id } = await req.json() as { report_id: string }

    if (!report_id) {
      return jsonResponse({ error: 'Missing report_id' }, 400)
    }

    // ── 1. Load report ──
    const { data: report, error: loadErr } = await supabase
      .from('flexi_reports')
      .select('*')
      .eq('id', report_id)
      .single()

    if (loadErr || !report) {
      return jsonResponse({ error: 'Report not found' }, 404)
    }

    if (report.status !== 'approved') {
      return jsonResponse({ error: `Report must be approved before submission (current: ${report.status})` }, 400)
    }

    // ── 2. Determine recipient ──
    const recipientConfig = RECIPIENT_MAP[report.report_type]
    if (!recipientConfig) {
      return jsonResponse({ error: `No recipient configured for report type: ${report.report_type}` }, 400)
    }

    const recipientDsId = Deno.env.get(recipientConfig.envKey) || ''
    const reportLabel = REPORT_LABELS[report.report_type] || report.report_type

    // ── 3. Generate XML envelope ──
    const xmlContent = generateIsdsXml(report, recipientDsId, reportLabel)
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
    const fileName = `${report.report_type}_${report.year}${report.quarter ? '_Q' + report.quarter : ''}_${timestamp}.xml`
    const storagePath = `${report.year}/${fileName}`

    // ── 4. Upload to Storage ──
    const xmlBytes = new TextEncoder().encode(xmlContent)

    const { error: uploadErr } = await supabase.storage
      .from('datova-schranka-outbox')
      .upload(storagePath, xmlBytes, { contentType: 'application/xml', upsert: true })

    if (uploadErr) {
      console.error('Storage upload failed:', uploadErr.message)
      return jsonResponse({ error: 'Failed to store XML: ' + uploadErr.message }, 500)
    }

    // ── 5. Try ISDS API if credentials exist ──
    const dsApiUrl = Deno.env.get('DS_API_URL') || ''
    const dsLogin = Deno.env.get('DS_LOGIN') || ''
    const dsPassword = Deno.env.get('DS_PASSWORD') || ''

    let messageId: string
    let method: 'api' | 'manual'

    if (dsApiUrl && dsLogin && dsPassword && recipientDsId) {
      // Send via ISDS API
      try {
        const isdsResult = await sendViaIsds(
          dsApiUrl, dsLogin, dsPassword,
          recipientDsId, reportLabel, report, xmlContent
        )
        messageId = isdsResult.messageId
        method = 'api'
      } catch (isdsErr) {
        console.error('ISDS API failed:', isdsErr)
        // Fallback to manual
        messageId = `MANUAL-${timestamp}`
        method = 'manual'
      }
    } else {
      messageId = `MANUAL-${timestamp}`
      method = 'manual'
    }

    // ── 6. Update report status ──
    await supabase.from('flexi_reports').update({
      status: 'submitted',
      submitted_at: new Date().toISOString(),
      datova_schranka_message_id: messageId,
    }).eq('id', report_id)

    // ── 7. Response ──
    return jsonResponse({
      success: true,
      method,
      message_id: messageId,
      recipient: recipientConfig.label,
      recipient_ds_id: recipientDsId || null,
      file_path: storagePath,
      instructions: method === 'manual'
        ? 'Soubor je připraven v úložišti. Nahrajte ho ručně do datové schránky na mojedatovaschranka.cz'
        : null,
    })
  } catch (err) {
    console.error('datova-schranka error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

// ─── XML Generator ─────────────────────────────────────────────

function generateIsdsXml(
  report: Record<string, any>,
  recipientDsId: string,
  reportLabel: string
): string {
  const periodStr = report.quarter
    ? `${report.year} Q${report.quarter}`
    : `${report.year}`

  const rawDataXml = escapeXml(JSON.stringify(report.raw_data, null, 2))

  return `<?xml version="1.0" encoding="UTF-8"?>
<isds:CreateMessage xmlns:isds="http://isds.czechpoint.cz/v20">
  <isds:dmEnvelope>
    <isds:dbIDRecipient>${escapeXml(recipientDsId)}</isds:dbIDRecipient>
    <isds:dmAnnotation>${escapeXml(reportLabel)} za ${escapeXml(periodStr)} — MotoGo24</isds:dmAnnotation>
    <isds:dmSenderOrgUnit>MotoGo24 / Bc. Petra Semorádová, IČO: 21874263</isds:dmSenderOrgUnit>
  </isds:dmEnvelope>
  <isds:dmFiles>
    <isds:dmFile dmFileDescr="${escapeXml(reportLabel)}_${report.year}.xml" dmMimeType="application/xml">
      <isds:dmEncodedContent>${btoa(rawDataXml)}</isds:dmEncodedContent>
    </isds:dmFile>
  </isds:dmFiles>
</isds:CreateMessage>`
}

function escapeXml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

// ─── ISDS API Call ─────────────────────────────────────────────

async function sendViaIsds(
  apiUrl: string,
  login: string,
  password: string,
  recipientDsId: string,
  subject: string,
  report: Record<string, any>,
  xmlContent: string
): Promise<{ messageId: string }> {
  // ISDS uses SOAP — wrap in SOAP envelope
  const soapBody = `<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:isds="http://isds.czechpoint.cz/v20">
  <soap:Body>
    <isds:CreateMessage>
      <isds:dmEnvelope>
        <isds:dbIDRecipient>${escapeXml(recipientDsId)}</isds:dbIDRecipient>
        <isds:dmAnnotation>${escapeXml(subject)} ${report.year}</isds:dmAnnotation>
      </isds:dmEnvelope>
      <isds:dmFiles>
        <isds:dmFile dmFileDescr="${report.report_type}_${report.year}.xml" dmMimeType="application/xml">
          <isds:dmEncodedContent>${btoa(xmlContent)}</isds:dmEncodedContent>
        </isds:dmFile>
      </isds:dmFiles>
    </isds:CreateMessage>
  </soap:Body>
</soap:Envelope>`

  const response = await fetch(apiUrl + '/dx', {
    method: 'POST',
    headers: {
      'Content-Type': 'text/xml; charset=utf-8',
      'Authorization': 'Basic ' + btoa(`${login}:${password}`),
      'SOAPAction': 'CreateMessage',
    },
    body: soapBody,
  })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(`ISDS API ${response.status}: ${body.slice(0, 200)}`)
  }

  const responseText = await response.text()
  // Parse message ID from SOAP response
  const idMatch = responseText.match(/<isds:dmID>(\d+)<\/isds:dmID>/)
  const messageId = idMatch?.[1] || `API-${Date.now()}`

  return { messageId }
}

// ─── Helpers ───────────────────────────────────────────────────

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
