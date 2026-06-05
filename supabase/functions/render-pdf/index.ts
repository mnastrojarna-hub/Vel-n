import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

// ===== GENERIC HTML → PDF (PDFShift) =====
// Sjednocená serverová cesta pro generování PDF ve Velínu (Finance/Dokumenty),
// aby doklady vypadaly 1:1 jako e-shop/maily (které už PDFShift používají přes
// generate-invoice). Velín posílá hotové HTML (z invoiceTemplate.js / šablon
// dokumentů) a dostane zpět PDF byty. Klient má html2pdf.js fallback, takže když
// render-pdf selže (chybí klíč/HTTP chyba), flow nespadne.

const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    if (!PDFSHIFT_API_KEY) {
      return new Response(JSON.stringify({ error: 'PDFSHIFT_API_KEY není nastaven' }), {
        status: 503, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const { html, landscape, margin, format } = await req.json()
    if (!html || typeof html !== 'string') {
      return new Response(JSON.stringify({ error: 'Chybí HTML' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Stejné volby jako generate-invoice → identický výstup
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: { 'X-API-Key': PDFSHIFT_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: html,
        format: format || 'A4',
        margin: margin || '8mm',
        landscape: !!landscape,
        sandbox: false,
        use_print: false,
      }),
    })

    if (!res.ok) {
      const detail = await res.text().catch(() => '')
      console.warn('[render-pdf] PDFShift HTTP', res.status, detail)
      return new Response(JSON.stringify({ error: `PDFShift HTTP ${res.status}` }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const pdf = new Uint8Array(await res.arrayBuffer())
    return new Response(pdf, {
      status: 200,
      headers: { ...CORS, 'Content-Type': 'application/pdf', 'Content-Length': String(pdf.byteLength) },
    })
  } catch (e) {
    console.error('[render-pdf] failed:', (e as Error).message)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
