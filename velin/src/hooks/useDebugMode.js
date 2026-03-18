import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

let cachedDebugMode = null

export function useDebugMode() {
  const [debug, setDebug] = useState(() => {
    if (cachedDebugMode !== null) return cachedDebugMode
    // URL parametr ?debug=1
    const params = new URLSearchParams(window.location.search)
    if (params.get('debug') === '1') {
      localStorage.setItem('debug_mode', '1')
      return true
    }
    // localStorage klíč
    return localStorage.getItem('debug_mode') === '1'
  })

  useEffect(() => {
    // Zkontrolovat feature flag z DB
    supabase
      .from('feature_flags')
      .select('enabled')
      .eq('key', 'debug_mode')
      .limit(1)
      .then(({ data }) => {
        if (data?.[0]?.enabled) {
          cachedDebugMode = true
          setDebug(true)
        }
      })
      .catch(() => {})
  }, [])

  useEffect(() => {
    cachedDebugMode = debug
  }, [debug])

  return debug
}
