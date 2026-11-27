// ===== fio-sync/handler.ts =====
// Vstup edge funkce fio-sync: ověření volajícího + akce.
//   {} / {action:'sync'}          běh synchronizace (cron fio_sync_tick každou minutu; Velín „Synchronizovat teď“)
//   {action:'process', fio_id}    zpracovat jeden pohyb hned (po vrácení ke zpracování / ručním spárování přes RPC)
//   {action:'pair', fio_id, target_type, target_id, accept_amount?, note?}
//                                 ruční spárování jedním voláním: RPC admin_fio_pair_transaction JMÉNEM
//                                 volajícího admina (audit) + okamžité potvrzení stejnou rutinou jako automatika
//   {action:'suggest', fio_id}    návrhy cíle pro nespárovanou platbu (stejná částka + podobnost) — nic nepotvrzuje
//   {action:'waiting'}            vše, na co se čeká (Velín → Banka → Čekající platby)
//   {action:'set_marker', date|id} ruční nastavení zarážky banky (jen superadmin / server)
// Auth: service key / service_role JWT / klíč z app_settings / admin JWT (beze změny proti dřívějšku).
// Secret: FIO_API_TOKEN (Supabase Edge secrets). Párovací logika: dispatch.ts; běh: run.ts.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isServiceRole } from '../_shared/auth.ts'
import { isMissing, type Row } from './util.ts'
import { processOne, runSync } from './run.ts'
import { loadWaiting, suggestFor } from './suggest.ts'
import { setMarker } from './fio-api.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
  const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || ''
  const FIO_TOKEN = Deno.env.get('FIO_API_TOKEN') || ''
  const sb = createClient(SUPABASE_URL, SERVICE_KEY)

  // ── Auth: service key / service_role claim / klíč z app_settings / admin JWT ──
  let bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (bearer.length > 1 && bearer.startsWith('"') && bearer.endsWith('"')) bearer = bearer.slice(1, -1)
  const svcMatch = bearer.length > 0 && bearer === SERVICE_KEY
  const roleMatch = !svcMatch && await isServiceRole(bearer)
  let appMatch = false
  if (!svcMatch && !roleMatch && bearer.length > 0) {
    const { data: row } = await sb.from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
    appMatch = !!row && bearer === String((row as { value: unknown }).value ?? '').replace(/^"|"$/g, '')
  }
  let adminMatch = false
  const callerClient = () => createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${bearer}` } } })
  if (!svcMatch && !roleMatch && !appMatch && bearer.length > 0) {
    try {
      const { data: isAdmin } = await callerClient().rpc('is_admin')
      adminMatch = isAdmin === true
    } catch (_) { /* ne */ }
  }
  if (!svcMatch && !roleMatch && !appMatch && !adminMatch) return json({ success: false, error: 'forbidden' }, 403)
  const service = svcMatch || roleMatch || appMatch

  const body = (await req.json().catch(() => ({}))) as Row
  const action = typeof body?.action === 'string' ? body.action : 'sync'
  const env = { url: SUPABASE_URL, key: SERVICE_KEY }
  const fioId = Number(body?.fio_id)

  try {
    if (action === 'sync') {
      const r = await runSync(sb, { token: FIO_TOKEN, env })
      return json(r.body, r.status)
    }
    if (action === 'process') {
      if (!Number.isFinite(fioId) || fioId <= 0) return json({ success: false, error: 'missing_fio_id' }, 400)
      return json(await processOne(sb, env, fioId))
    }
    if (action === 'pair') {
      if (!Number.isFinite(fioId) || fioId <= 0) return json({ success: false, error: 'missing_fio_id' }, 400)
      // RPC běží pod JWT volajícího → is_admin() + auth.uid() do auditu; server sám nepáruje
      const { data, error } = await callerClient().rpc('admin_fio_pair_transaction', {
        p_fio_id: fioId, p_target_type: body.target_type ?? null, p_target_id: body.target_id ?? null,
        p_accept_amount: body.accept_amount === true, p_note: typeof body.note === 'string' ? body.note : null,
      })
      if (error) return json({ success: false, error: isMissing(error) ? 'bank_unavailable' : 'pair_failed', detail: isMissing(error) ? undefined : error.message })
      if ((data as Row | null)?.success !== true) return json(data || { success: false, error: 'pair_failed' })
      return json(await processOne(sb, env, fioId))
    }
    if (action === 'suggest') {
      if (!Number.isFinite(fioId) || fioId <= 0) return json({ success: false, error: 'missing_fio_id' }, 400)
      const limit = Math.min(Math.max(Number(body.limit) || 8, 1), 30)
      return json(await suggestFor(sb, fioId, limit))
    }
    if (action === 'waiting') {
      const items = (await loadWaiting(sb, { wide: false })).filter((c) => c.target_type !== 'order' || c.request_id)
        .map(({ user_id: _u, ...pub }) => pub)
      return json({ success: true, items })
    }
    if (action === 'set_marker') {
      if (!service) {
        const { data: { user } } = await sb.auth.getUser(bearer)
        const { data: adm } = user ? await sb.from('admin_users').select('role, active').eq('id', user.id).maybeSingle() : { data: null }
        const a = adm as { role?: string; active?: boolean } | null
        if (!a || a.active === false || a.role !== 'superadmin') return json({ success: false, error: 'forbidden' }, 403)
      }
      if (!FIO_TOKEN) return json({ success: false, error: 'missing_fio_token' })
      const date = typeof body.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.date) ? body.date : null
      const id = Number(body.id) > 0 ? Math.floor(Number(body.id)) : null
      if (!date && !id) return json({ success: false, error: 'missing_date_or_id' }, 400)
      const r = await setMarker(FIO_TOKEN, id ? { id } : { date: date! })
      try {
        await sb.from('admin_audit_log').insert({ admin_id: null, action: 'fio_marker_set', entity_type: 'fio_sync_state', new_data: { date, id, ok: r.ok, error: r.error ?? null } })
      } catch { /* ignore */ }
      return json(r.ok ? { success: true } : { success: false, error: r.error })
    }
    return json({ success: false, error: 'unknown_action' }, 400)
  } catch (err) {
    console.error('[fio-sync] action error:', err)
    return json({ success: false, error: (err as Error).message }, 500)
  }
}
