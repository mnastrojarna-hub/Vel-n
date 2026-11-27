// ===== fio-sync/partials.ts =====
// Dřívější pohyby téhož cíle: (a) částečné platby (stav amount_mismatch) — sčítají se, dokud součet
// nedosáhne očekávané částky; (b) pohyb, který cíl už potvrdil — další platba je pak DUPLICITA.
// Jen s nasazeným SQL 20261130a1 (sloupce target_type / order_id / request_id); jinak nic (jako dřív).
import { type Ctx, type TargetType, type Tx, vsDigits } from './util.ts'

const COL: Record<TargetType, string> = { booking: 'booking_id', surcharge: 'booking_id', order: 'order_id', request: 'request_id' }

export async function priorPartial(ctx: Ctx, p: Tx, type: TargetType, id: string): Promise<{ sum: number; ids: number[] }> {
  if (!ctx.caps.state) return { sum: 0, ids: [] }
  try {
    const { data, error } = await ctx.sb.from('fio_transactions').select('fio_id, amount')
      .eq('status', 'amount_mismatch').eq('target_type', type).eq(COL[type], id).neq('fio_id', p.fio_id)
    if (error || !Array.isArray(data)) return { sum: 0, ids: [] }
    const rows = data as Array<{ fio_id: number; amount: number }>
    return { sum: Math.round(rows.reduce((s, r) => s + (Number(r.amount) || 0), 0) * 100) / 100, ids: rows.map((r) => Number(r.fio_id)) }
  } catch { return { sum: 0, ids: [] } }
}

/** ID jiného pohybu, který tento cíl už potvrdil (stav `confirmed`), jinak null. `vs` zúží na týž VS
 *  (doplatků může mít jedna rezervace postupně víc). */
export async function confirmedByOther(ctx: Ctx, p: Tx, type: TargetType, id: string, confirmed: string, vs?: string): Promise<number | null> {
  if (!ctx.caps.state) return null
  try {
    const { data, error } = await ctx.sb.from('fio_transactions').select('fio_id, vs')
      .eq('status', confirmed).eq(COL[type], id).neq('fio_id', p.fio_id).limit(20)
    if (error || !Array.isArray(data)) return null
    const hit = (data as Array<{ fio_id: number; vs: string | null }>).find((r) => !vs || vsDigits(r.vs) === vsDigits(vs))
    return hit ? Number(hit.fio_id) : null
  } catch { return null }
}

/** Po potvrzení: dřívější částečné platby převést do téhož stavu (zmizí z „K vyřízení“). */
export async function settleAbsorbed(ctx: Ctx, ids: number[] | undefined, status: string, byFioId: number, at: string) {
  if (!ctx.caps.state || !ids?.length) return
  try {
    await ctx.sb.from('fio_transactions')
      .update({ status, reason_code: 'partial_sum', note: `částečná platba — dorovnáno pohybem FIO ${byFioId}`, processed_at: at })
      .in('fio_id', ids).eq('status', 'amount_mismatch')
  } catch { /* ignore */ }
}
