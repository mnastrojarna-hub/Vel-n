/**
 * MotoGo24 — Edge Function: admin-users
 * Správa uživatelů Velína (jen SUPERADMIN). Volá Velín → Uživatelé Velína.
 *
 * POST { action, ... }  (verify_jwt=false → volajícího ověřuje funkce sama)
 *  - create       { email, password, name, phone?, role?, sections? }
 *                 → auth.admin.createUser (email potvrzen) + řádek admin_users.
 *                   Existuje-li auth účet s tím e-mailem (zákazník), jen se mu
 *                   založí admin_users řádek (heslo se přenastaví na zadané).
 *  - update       { user_id, name?, phone?, role?, sections?, active? }
 *  - set_password { user_id, new_password }
 *  - delete       { user_id }  → smaže JEN admin_users řádek (přístup do Velína);
 *                   auth účet zůstává (může být i zákazník s rezervacemi).
 *
 * Oprávnění sekcí: admin_users.permissions = { "sections": [ids] } — čte
 * velin/src/lib/velinSections.js (Sidebar + SectionGuard). Superadmin vidí vše.
 * Pojistky: nelze deaktivovat/smazat sám sebe ani si odebrat roli superadmina.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const ROLES = ['superadmin', 'manager', 'operator', 'viewer'] // ENUM admin_role (živá DB)

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function cleanSections(v: unknown): string[] {
  if (!Array.isArray(v)) return []
  return [...new Set(v.filter(s => typeof s === 'string' && /^[a-z-]{1,40}$/.test(s)))]
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const auth = req.headers.get('Authorization') || ''
  const token = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : ''
  if (!token) return json({ error: 'Chybí přihlášení' }, 401)

  const admin = createClient(SUPABASE_URL, SERVICE_KEY)
  const { data: { user: caller }, error: callerErr } = await admin.auth.getUser(token)
  if (callerErr || !caller) return json({ error: 'Neplatné přihlášení' }, 401)

  const { data: callerRow } = await admin
    .from('admin_users').select('id, role, active, name, email').eq('id', caller.id).maybeSingle()
  if (!callerRow || callerRow.role !== 'superadmin' || callerRow.active === false) {
    return json({ error: 'Správa uživatelů je jen pro superadmina' }, 403)
  }

  let body: Record<string, unknown> = {}
  try { body = await req.json() } catch { return json({ error: 'Neplatný požadavek' }, 400) }
  const action = String(body.action || '')

  const audit = async (act: string, entityId: string | null, newData: Record<string, unknown>) => {
    try {
      await admin.from('admin_audit_log').insert({
        admin_id: caller.id, action: act, entity_type: 'admin_users', entity_id: entityId, new_data: newData,
      })
    } catch (e) { console.warn('[admin-users] audit failed', e) }
  }

  try {
    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase()
      const password = String(body.password || '')
      const name = String(body.name || '').trim()
      const phone = body.phone ? String(body.phone).trim() : null
      const role = ROLES.includes(String(body.role)) ? String(body.role) : 'operator'
      const sections = cleanSections(body.sections)
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'Neplatný e-mail' }, 400)
      if (password.length < 8) return json({ error: 'Heslo musí mít alespoň 8 znaků' }, 400)
      if (!name) return json({ error: 'Chybí jméno' }, 400)

      let userId: string | null = null
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { full_name: name, velin_user: true },
      })
      if (createErr) {
        const msg = (createErr.message || '').toLowerCase()
        if (!msg.includes('already') && !msg.includes('exists') && !msg.includes('registered')) {
          return json({ error: `Účet se nepodařilo založit: ${createErr.message}` }, 400)
        }
        // Auth účet existuje (např. zákazník) → dohledat a jen přidat přístup do Velína
        const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
        const existing = list?.users?.find(u => (u.email || '').toLowerCase() === email)
        if (!existing) return json({ error: 'E-mail je už registrován, ale účet se nepodařilo dohledat' }, 400)
        userId = existing.id
        const { data: already } = await admin.from('admin_users').select('id').eq('id', userId).maybeSingle()
        if (already) return json({ error: 'Tento e-mail už má přístup do Velína' }, 409)
        const { error: pwErr } = await admin.auth.admin.updateUserById(userId, { password, email_confirm: true })
        if (pwErr) return json({ error: `Heslo se nepodařilo nastavit: ${pwErr.message}` }, 400)
      } else {
        userId = created.user?.id ?? null
      }
      if (!userId) return json({ error: 'Účet se nepodařilo založit' }, 500)

      const row = { id: userId, email, name, phone, role, active: true, permissions: { sections } }
      const { error: insErr } = await admin.from('admin_users').upsert(row, { onConflict: 'id' })
      if (insErr) return json({ error: `Záznam uživatele Velína se nepodařilo uložit: ${insErr.message}` }, 500)
      await audit('velin_user_created', userId, { email, name, role, sections })
      return json({ success: true, user_id: userId })
    }

    const userId = String(body.user_id || '')
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return json({ error: 'Chybí user_id' }, 400)
    const { data: target } = await admin.from('admin_users').select('id, role, active, email').eq('id', userId).maybeSingle()
    if (!target) return json({ error: 'Uživatel Velína nenalezen' }, 404)
    const self = userId === caller.id

    if (action === 'update') {
      const patch: Record<string, unknown> = {}
      if (typeof body.name === 'string' && body.name.trim()) patch.name = body.name.trim()
      if ('phone' in body) patch.phone = body.phone ? String(body.phone).trim() : null
      if (typeof body.role === 'string') {
        if (!ROLES.includes(body.role)) return json({ error: 'Neplatná role' }, 400)
        if (self && body.role !== 'superadmin') return json({ error: 'Sami sobě nemůžete odebrat roli superadmina' }, 400)
        patch.role = body.role
      }
      if ('sections' in body) patch.permissions = { sections: cleanSections(body.sections) }
      if (typeof body.active === 'boolean') {
        if (self && !body.active) return json({ error: 'Sami sebe nemůžete deaktivovat' }, 400)
        patch.active = body.active
      }
      if (Object.keys(patch).length === 0) return json({ error: 'Nic ke změně' }, 400)
      const { error: updErr } = await admin.from('admin_users').update(patch).eq('id', userId)
      if (updErr) return json({ error: updErr.message }, 500)
      await audit('velin_user_updated', userId, patch)
      return json({ success: true })
    }

    if (action === 'set_password') {
      const pw = String(body.new_password || '')
      if (pw.length < 8) return json({ error: 'Heslo musí mít alespoň 8 znaků' }, 400)
      const { error: pwErr } = await admin.auth.admin.updateUserById(userId, { password: pw })
      if (pwErr) return json({ error: pwErr.message }, 400)
      await audit('velin_user_password_set', userId, { email: target.email })
      return json({ success: true })
    }

    if (action === 'delete') {
      if (self) return json({ error: 'Sami sobě nemůžete odebrat přístup' }, 400)
      const { error: delErr } = await admin.from('admin_users').delete().eq('id', userId)
      if (delErr) return json({ error: delErr.message }, 500)
      await audit('velin_user_removed', userId, { email: target.email })
      return json({ success: true })
    }

    return json({ error: 'Neznámá akce' }, 400)
  } catch (err) {
    console.error('[admin-users]', err)
    return json({ error: (err as Error).message }, 500)
  }
})
