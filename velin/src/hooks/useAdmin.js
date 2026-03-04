import { useState, useEffect } from 'react'
import { createClient } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

// Service role klient pro auto-provision (obchází RLS) — dočasné řešení
const supabaseAdmin = createClient(
  'https://vnwnqteskbykeucanlhk.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjQ5MTM2MywiZXhwIjoyMDg4MDY3MzYzfQ.mTFJQZzsBBosMycHLr0pj06HrHElTQtXSUIp0UwasGs'
)

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
            // Auto-provision: první přihlášení — vytvořit admin záznam
            const newAdmin = {
              id: user.id,
              name: user.user_metadata?.name || user.email.split('@')[0],
              email: user.email,
              role: 'superadmin',
              branch_access: [],
              permissions: { all: true },
            }
            const { data: created, error: insertErr } = await supabaseAdmin
              .from('admin_users')
              .insert(newAdmin)
              .select()
              .single()

            if (!insertErr && created) {
              setAdmin(created)
              setRole(created.role)
              setBranchAccess(created.branch_access)
              setPermissions(created.permissions)
            } else {
              console.error('Auto-provision failed:', insertErr)
              setError(`Nepodařilo se vytvořit admin účet: ${insertErr?.message || 'Neznámá chyba'}`)
              setAdmin(null)
            }
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
