import { useState, useEffect } from 'react'
import { supabase, supabaseUrl, supabaseAnonKey } from '../lib/supabase'

export function useAdmin(user) {
  const [admin, setAdmin] = useState(null)
  const [role, setRole] = useState(null)
  const [branchAccess, setBranchAccess] = useState(null)
  const [permissions, setPermissions] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!user) {
      setAdmin(null)
      setRole(null)
      setBranchAccess(null)
      setPermissions(null)
      setLoading(false)
      return
    }

    async function fetchAdmin() {
      setLoading(true)
      setError(null)
      try {
        // Načtení admin záznamu přes anon client (RLS: is_admin())
        const { data, error: fetchError } = await supabase
          .from('admin_users')
          .select('*')
          .eq('id', user.id)
          .single()

        if (fetchError) {
          if (fetchError.code === 'PGRST116') {
            // Auto-provision: první přihlášení — volání Edge Function admin-auth
            const { data: { session } } = await supabase.auth.getSession()
            const token = session?.access_token
            if (!token) {
              setError('Chybí autentizační token')
              setAdmin(null)
              setLoading(false)
              return
            }

            const resp = await fetch(`${supabaseUrl}/functions/v1/admin-auth`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`,
                'apikey': supabaseAnonKey,
              },
              body: JSON.stringify({ action: 'provision' }),
            })
            const result = await resp.json()

            if (result.success && result.admin) {
              setAdmin(result.admin)
              setRole(result.admin.role)
              setBranchAccess(result.admin.branch_access)
              setPermissions(result.admin.permissions)
            } else {
              console.error('Auto-provision failed:', result.error)
              setError(`Nepodařilo se vytvořit admin účet: ${result.error || 'Neznámá chyba'}`)
              setAdmin(null)
            }
          } else {
            console.error('Fetch admin failed:', JSON.stringify(fetchError))
            throw fetchError
          }
        } else {
          setAdmin(data)
          setRole(data.role)
          setBranchAccess(data.branch_access)
          setPermissions(data.permissions)
        }
      } catch (err) {
        setError(err.message || 'Chyba při ověřování oprávnění.')
      } finally {
        setLoading(false)
      }
    }

    fetchAdmin()
    // Závisíme na user.id, ne celém objektu — Supabase při TOKEN_REFRESHED
    // vytváří nový session objekt (stejný user.id), což jinak způsobuje
    // re-fetch admin záznamu, dočasné loading=true a UNMOUNT všech routes
    // (zavírá modaly a wizardy uprostřed práce uživatele).
  }, [user?.id])

  return { admin, role, branchAccess, permissions, loading, error }
}
