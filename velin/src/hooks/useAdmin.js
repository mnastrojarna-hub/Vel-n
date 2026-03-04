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
        const { data, error: fetchError } = await supabase
          .from('admin_users')
          .select('*')
          .eq('id', user.id)
          .single()

        if (fetchError) {
          if (fetchError.code === 'PGRST116') {
            // Auto-provision: první přihlášení — vytvořit admin záznam
            const { data: created, error: insertErr } = await supabase
              .from('admin_users')
              .insert({ id: user.id })
              .select()
              .single()

            if (!insertErr && created) {
              setAdmin(created)
              setRole(created.role)
              setBranchAccess(created.branch_access)
              setPermissions(created.permissions)
            } else {
              console.error('Auto-provision failed:', JSON.stringify(insertErr))
              setError(`Nepodařilo se vytvořit admin účet: ${insertErr?.message || JSON.stringify(insertErr)}`)
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
  }, [user])

  return { admin, role, branchAccess, permissions, loading, error }
}
