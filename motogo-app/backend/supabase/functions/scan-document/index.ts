/**
 * MotoGo24 — Edge Function: Scan Document via Mindee
 * POST /functions/v1/scan-document
 * Body: { image_base64: string, document_type: "id" | "dl" | "passport" }
 * Returns: { success: boolean, data: {...}, error?: string }
 */
import { corsHeaders } from '../_shared/cors.ts';

const MINDEE_API_KEY = Deno.env.get('MINDEE_API_KEY') ?? '';

const ENDPOINTS: Record<string, string> = {
  id: 'https://api.mindee.net/v1/products/mindee/international_id/v2/predict',
  dl: 'https://api.mindee.net/v1/products/mindee/international_id/v2/predict',
  passport: 'https://api.mindee.net/v1/products/mindee/international_id/v2/predict'
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { image_base64, document_type } = await req.json();
    if (!image_base64) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing image_base64' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const endpoint = ENDPOINTS[document_type] || ENDPOINTS.id;

    // Decode base64 to binary
    const binaryStr = atob(image_base64.replace(/^data:image\/\w+;base64,/, ''));
    const bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) {
      bytes[i] = binaryStr.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: 'image/jpeg' });

    // Build multipart form
    const formData = new FormData();
    formData.append('document', blob, 'scan.jpg');

    // Call Mindee API
    const resp = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Authorization': `Token ${MINDEE_API_KEY}` },
      body: formData
    });

    const result = await resp.json();

    if (!resp.ok) {
      return new Response(
        JSON.stringify({ success: false, error: result.api_request?.error || 'Mindee API error' }),
        { status: resp.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Extract prediction fields
    const prediction = result.document?.inference?.prediction || {};
    const data = {
      firstName: prediction.given_names?.map((n: any) => n.value).join(' ') || '',
      lastName: prediction.surnames?.map((n: any) => n.value).join(' ') || '',
      dob: prediction.birth_date?.value || '',
      idNumber: prediction.document_number?.value || '',
      issuedDate: prediction.issuance_date?.value || '',
      expiryDate: prediction.expiry_date?.value || '',
      nationality: prediction.nationality?.value || '',
      sex: prediction.sex?.value || '',
      address: prediction.address?.value || '',
      mrzLine1: prediction.mrz?.line1?.value || '',
      mrzLine2: prediction.mrz?.line2?.value || '',
      documentType: prediction.document_type?.value || '',
      // ŘP specifická pole
      licenseCategory: prediction.category?.value || '',
      // Confidence scores
      confidence: {
        firstName: prediction.given_names?.[0]?.confidence || 0,
        lastName: prediction.surnames?.[0]?.confidence || 0,
        dob: prediction.birth_date?.confidence || 0,
        idNumber: prediction.document_number?.confidence || 0
      }
    };

    // Spočítej kolik polí má data — partial flag pro frontend
    const filledFields = Object.values(data).filter(
      v => typeof v === 'string' ? v.length > 0 : false
    ).length;

    return new Response(
      JSON.stringify({ success: true, data, partial: filledFields < 3 }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ success: false, error: msg }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
