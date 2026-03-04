import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'

const DEMO_USER = {
  id: 'demo-user',
  email: 'demo@motogo24.cz',
  user_metadata: { name: 'Demo Admin' },
  _demo: true,
}

export function useAuth() {
  const [user, setUser] = useState(null)
  const [session, setSession] = useState(null)
  const [loading, setLoading] = useState(true)
  const [demoMode, setDemoMode] = useState(false)

  useEffect(() => {
    if (sessionStorage.getItem('motogo_demo') === '1') {
      setUser(DEMO_USER)
      setDemoMode(true)
      setLoading(false)
      return
    }

    let sub
    const timeout = setTimeout(() => {
      setLoading(false)
    }, 4000)

    supabase.auth.getSession()
      .then(({ data: { session } }) => {
        clearTimeout(timeout)
        setSession(session)
        setUser(session?.user ?? null)
        setLoading(false)
      })
      .catch(() => {
        clearTimeout(timeout)
        setLoading(false)
      })

    try {
      const { data: { subscription } } = supabase.auth.onAuthStateChange(
        (_event, session) => {
          setSession(session)
          setUser(session?.user ?? null)
          setLoading(false)
        }
      )
      sub = subscription
    } catch {}

    return () => {
      clearTimeout(timeout)
      sub?.unsubscribe()
    }
  }, [])

  const signIn = useCallback(async (email, password) => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    if (error) throw error
    return data
  }, [])

  const signInDemo = useCallback(() => {
    sessionStorage.setItem('motogo_demo', '1')
    setUser(DEMO_USER)
    setDemoMode(true)
  }, [])

  const signOut = useCallback(async () => {
    sessionStorage.removeItem('motogo_demo')
    setDemoMode(false)
    setUser(null)
    setSession(null)
    try {
      await supabase.auth.signOut()
    } catch {}
  }, [])

  return { user, session, loading, demoMode, signIn, signInDemo, signOut }
}
