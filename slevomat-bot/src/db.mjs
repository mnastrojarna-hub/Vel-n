// Supabase vrstva — výběr poukazů k uplatnění a zápis výsledku.
import { createClient } from '@supabase/supabase-js';

// Stavy, které znamenají "už není co dělat" (poukaz je na Slevomatu vyřízen).
export const DONE_STATUSES = new Set(['applied', 'already_redeemed']);
// Přechodné chyby — má smysl zkoušet znovu (do vyčerpání pokusů).
export const RETRY_STATUSES = new Set(['failed']);

export function makeDb(env) {
  const sb = createClient(env.supabaseUrl, env.supabaseKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  /**
   * Poukazy k uplatnění: Slevomat poukazy uplatněné u nás (status='redeemed'),
   * které ještě nejsou potvrzené na portálu (slevomat_applied_at IS NULL) a
   * buď nebyly zkoušeny, nebo skončily přechodnou chybou a nedošly pokusy.
   */
  async function fetchPending(limit) {
    let q = sb
      .from('vouchers')
      .select(
        'id, code, amount, status, slevomat_apply_status, slevomat_apply_attempts, redeemed_at'
      )
      .eq('source', 'slevomat')
      .eq('status', 'redeemed')
      .is('slevomat_applied_at', null)
      .lt('slevomat_apply_attempts', env.maxAttempts)
      .or('slevomat_apply_status.is.null,slevomat_apply_status.eq.failed')
      .order('redeemed_at', { ascending: true });
    if (limit && limit > 0) q = q.limit(limit);
    const { data, error } = await q;
    if (error) throw new Error(`Supabase fetchPending: ${error.message}`);
    return data || [];
  }

  /** Zápis výsledku jednoho poukazu zpět do DB. */
  async function recordResult(voucher, { status, message }) {
    const patch = {
      slevomat_apply_status: status,
      slevomat_apply_error: DONE_STATUSES.has(status) ? null : message || null,
      slevomat_apply_attempts: (voucher.slevomat_apply_attempts || 0) + 1,
      slevomat_apply_last_at: new Date().toISOString(),
    };
    if (DONE_STATUSES.has(status)) patch.slevomat_applied_at = new Date().toISOString();

    const { error } = await sb.from('vouchers').update(patch).eq('id', voucher.id);
    if (error) throw new Error(`Supabase recordResult(${voucher.code}): ${error.message}`);
  }

  /** Souhrn stavu fronty pro `status` příkaz / Velín panel. */
  async function summary() {
    const base = () =>
      sb.from('vouchers').select('id', { count: 'exact', head: true }).eq('source', 'slevomat');
    const [pending, applied, failed] = await Promise.all([
      base().eq('status', 'redeemed').is('slevomat_applied_at', null),
      base().not('slevomat_applied_at', 'is', null),
      base().eq('slevomat_apply_status', 'failed'),
    ]);
    return {
      pending: pending.count ?? 0,
      applied: applied.count ?? 0,
      failed: failed.count ?? 0,
    };
  }

  return { sb, fetchPending, recordResult, summary };
}
