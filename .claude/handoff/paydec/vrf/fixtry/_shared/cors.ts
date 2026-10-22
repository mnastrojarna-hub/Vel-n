/**
 * MotoGo24 — Sdílené CORS headers pro Edge Functions
 * Zajišťuje cross-origin přístup pro frontend aplikaci.
 */

/** Standardní CORS headers povolující přístup z libovolného originu. */
export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

/** Vrátí Response pro OPTIONS preflight request. */
export function corsResponse(): Response {
  return new Response('ok', { headers: corsHeaders });
}

/** Vrátí JSON response se správnými CORS headers. */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Vrátí chybovou JSON response. */
export function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ success: false, error: message }, status);
}
