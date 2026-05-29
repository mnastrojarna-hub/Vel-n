import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

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
            // Žádný viditelný admin_users záznam → uživatel NENÍ aktivní admin
            // (zákazník nebo deaktivovaný účet — RLS is_admin() ho odfiltruje).
            // Auto-provisioning byl ODSTRANĚN (bezpečnostní díra: kdokoli s platným
            // účtem se prvním přihlášením do Velína sám povýšil na admina s rolí
            // 'admin' a obešel tím RLS). Fail-closed — přístup zamítnut; nového
            // admina přidává výhradně superadmin ručně do admin_users.
            setError('Přístup odepřen — tento účet nemá oprávnění do Velína.')
            setAdmin(null)
            setRole(null)
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
