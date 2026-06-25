/**
 * MotoGo24 — Slevomat Partner API klient
 * --------------------------------------
 * Ověření (voucherCheck) a uplatnění (voucherApply) Slevomat voucherů.
 * Dokumentace: https://www.slevomat.cz/api  (HTTP GET, JSON odpověď).
 *
 * Flow na webu (rezervace, pole „Kód poukazu"):
 *   1) action='check'  → ověří voucher u Slevomatu; je-li zaplacený a nepoužitý,
 *      namapuje variant/product → Kč hodnotu a založí řádek v `vouchers`
 *      (source='slevomat', status='active'). Web pak pokračuje jako u běžného
 *      dárkového poukazu (hodnota se odečte z ceny, zbytek se doplatí).
 *   2) action='apply'  → po zaplacení rezervace uplatní voucher u Slevomatu
 *      (voucherApply) a nastaví náš voucher na status='redeemed'.
 *
 * ⚠️ POZOR (z dokumentace): voucherCheck/voucherApply se NEVZTAHUJE na vouchery
 *    v kategorii „cestování" (chyba 1112/1212 = „voucher musí být uplatněn pouze
 *    skrze rezervaci"). Pokud Slevomat zařadí naši akci do cestování, tato cesta
 *    nefunguje a uplatnění musí jít přes jejich rezervační systém — NUTNO OVĚŘIT.
 *
 * Secret:   SLEVOMAT_PARTNER_TOKEN  (unikátní partnerský token)
 * Config:   app_settings.slevomat_voucher_map = { "<variant|product id>": <Kč>, ... }
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';

const SLEVOMAT_API = 'https://www.slevomat.cz/api';

/** Slevomat chybové kódy → české hlášky (check 11xx, apply 12xx). */
const ERR: Record<number, string> = {
  1101: 'Chybí token nebo kód voucheru',
  1102: 'Neplatný partnerský token',
  1103: 'Voucher s tímto kódem neexistuje',
  1104: 'Objednávka voucheru nebyla zaplacena',
  1105: 'Voucher už byl uplatněn',
  1106: 'Voucher byl refundován',
  1107: 'Voucher nebo objednávka byly stornovány',
  1108: 'Akce už byla vyúčtována — nelze uplatnit další vouchery',
  1109: 'Platnost voucherů této akce ještě nezačala',
  1111: 'Interní chyba Slevomatu',
  1112: 'Voucher musí být uplatněn pouze přes rezervaci (kategorie cestování)',
};
/** Apply kódy 12xx mají stejný význam jako 11xx — namapuj na stejné hlášky. */
function errMsg(code: number): string {
  return ERR[code] ?? ERR[code - 100] ?? `Slevomat chyba ${code}`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return corsResponse();

  try {
    const token = Deno.env.get('SLEVOMAT_PARTNER_TOKEN');
    if (!token) return errorResponse('SLEVOMAT_PARTNER_TOKEN není nastaven', 500);

    const body = await req.json().catch(() => ({})) as { action?: string; code?: string };
    const action = (body.action ?? 'check').toLowerCase();
    const code = (body.code ?? '').trim();
    if (!code) return errorResponse('Chybí kód voucheru', 400);
    if (action !== 'check' && action !== 'apply') return errorResponse('Neznámá akce (check|apply)', 400);

    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 1) Volání Slevomat Partner API (GET).
    const endpoint = action === 'apply' ? 'voucherapply' : 'vouchercheck';
    const url = `${SLEVOMAT_API}/${endpoint}?code=${encodeURIComponent(code)}&token=${encodeURIComponent(token)}`;
    const res = await fetch(url);
    const json = await res.json().catch(() => null) as
      | { result?: boolean; data?: { voucherData?: Record<string, unknown> }; error?: { code?: number; message?: string } }
      | null;

    await sb.from('debug_log').insert({
      source: 'slevomat-voucher', action, component: endpoint,
      status: json?.result ? 'ok' : 'error',
      request_data: { code }, response_data: json,
      error_message: json?.error?.message ?? (json ? null : 'no-json'),
    });

    if (!json || json.result !== true) {
      const ecode = json?.error?.code ?? 0;
      return jsonResponse({ valid: false, slevomat_error_code: ecode, error: ecode ? errMsg(ecode) : 'Voucher se nepodařilo ověřit' }, 200);
    }

    const vd = (json.data?.voucherData ?? {}) as Record<string, unknown>;

    // 2) Mapování variant/product → Kč hodnota (app_settings.slevomat_voucher_map).
    const { data: mapRow } = await sb.from('app_settings').select('value').eq('key', 'slevomat_voucher_map').maybeSingle();
    const map = (mapRow?.value ?? {}) as Record<string, number>;
    const amount = map[String(vd.variant)] ?? map[String(vd.product)] ?? null;
    if (amount == null) {
      return jsonResponse({
        valid: false,
        error: 'Hodnota voucheru není namapována — doplňte product/variant do slevomat_voucher_map.',
        product: vd.product ?? null, variant: vd.variant ?? null, voucherData: vd,
      }, 200);
    }

    // 3) Zápis do našich `vouchers` (Velín = dárkový poukaz, source='slevomat').
    const nowIso = new Date().toISOString();
    const status = action === 'apply' ? 'redeemed' : 'active';
    const row: Record<string, unknown> = {
      code, amount, currency: 'CZK', status, source: 'slevomat', category: 'experience',
      description: (vd.productName ?? vd.title ?? 'Slevomat voucher') as string,
    };
    if (vd.validFrom) row.valid_from = String(vd.validFrom).slice(0, 10);
    if (vd.validTo) row.valid_until = String(vd.validTo).slice(0, 10);
    if (action === 'apply') row.redeemed_at = nowIso;

    const { data: voucher, error: upErr } = await sb
      .from('vouchers')
      .upsert(row, { onConflict: 'code' })
      .select('id, code, amount, status')
      .maybeSingle();

    if (upErr) {
      return jsonResponse({ valid: true, action, amount, status, voucher_id: null, warning: `Voucher ověřen, ale zápis selhal: ${upErr.message}`, voucherData: vd }, 200);
    }

    return jsonResponse({ valid: true, action, voucher_id: voucher?.id ?? null, amount, status, voucherData: vd });
  } catch (e) {
    return errorResponse(`Chyba: ${(e as Error).message}`, 500);
  }
});
