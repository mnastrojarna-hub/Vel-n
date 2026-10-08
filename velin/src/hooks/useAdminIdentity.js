import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

// Identita přihlášeného účtu Velína (admin_users: id, name, email, role) — technik v servisu
// = kdo je přihlášen (zadání majitele: „jméno technika se mění podle toho, kdo je login“).
// Cache na úrovni modulu: jeden dotaz na session, další komponenty čtou z paměti.
let cached = null
let pending = null

export async function fetchAdminIdentity() {
  if (cached) return cached
  if (pending) return pending
  pending = (async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return null
      const { data } = await supabase.from('admin_users').select('id, name, email, role').eq('id', user.id).maybeSingle()
      const name = (data?.name || '').trim() || data?.email || user.email || ''
      cached = { id: user.id, name, email: data?.email || user.email || '', role: data?.role || null }
      return cached
    } catch { return null } finally { pending = null }
  })()
  return pending
}

export function resetAdminIdentityCache() { cached = null }

export function useAdminIdentity() {
  const [me, setMe] = useState(cached)
  useEffect(() => {
    let on = true
    if (!cached) fetchAdminIdentity().then(v => { if (on) setMe(v) })
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') { cached = null; if (on) setMe(null) }
      if (event === 'SIGNED_IN') { cached = null; fetchAdminIdentity().then(v => { if (on) setMe(v) }) }
    })
    return () => { on = false; sub?.subscription?.unsubscribe?.() }
  }, [])
  return me
}

/** Seznam účtů Velína (pro výběr technika) — RLS: admin vidí všechny aktivní účty. */
export async function fetchVelinAccounts() {
  const { data } = await supabase.from('admin_users').select('id, name, email, role, active').eq('active', true).order('name')
  return (data || []).map(a => ({ ...a, label: (a.name || '').trim() || a.email }))
}
