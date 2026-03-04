import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

const DEMO_ADMIN = {
  id: 'demo-user',
  name: 'Demo Admin',
  email: 'demo@motogo24.cz',
  role: 'superadmin',
  branch_access: ['all'],
  permissions: { all: true },
}

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

    if (user._demo) {
      setAdmin(DEMO_ADMIN)
      setRole(DEMO_ADMIN.role)
      setBranchAccess(DEMO_ADMIN.branch_access)
      setPermissions(DEMO_ADMIN.permissions)
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
            setError('Nemáte oprávnění pro přístup do Velínu.')
            setAdmin(null)
          } else {
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
