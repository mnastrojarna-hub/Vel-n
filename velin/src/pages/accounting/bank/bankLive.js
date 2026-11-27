// Finance → Banka: živé obnovování. Realtime (postgres_changes) na fio_transactions a bank_payment_requests
// + pojistka 60 s (jen když je záložka prohlížeče vidět) — vzor hooks/useKioskAlerts.js.
// Zapíná se AŽ po ověření, že databázová část existuje (jinak žádný kanál ani interval).
import { useState, useEffect } from 'react'
import { supabase } from '../../../lib/supabase'

export function useBankTick(enabled) {
  const [tick, setTick] = useState(0)
  useEffect(() => {
    if (!enabled) return undefined
    let timer = null
    const bump = () => { clearTimeout(timer); timer = setTimeout(() => setTick(t => t + 1), 800) }
    const channel = supabase.channel('velin-bank-' + Math.random().toString(36).slice(2, 8))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'fio_transactions' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bank_payment_requests' }, bump)
      .subscribe()
    const poll = setInterval(() => { if (!document.hidden) setTick(t => t + 1) }, 60000)
    return () => { clearTimeout(timer); clearInterval(poll); supabase.removeChannel(channel) }
  }, [enabled])
  return tick
}

/** Hodiny pro „před X min“ / „za X min“ — překreslení každých 20 s. */
export function useNow(ms = 20000) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms)
    return () => clearInterval(t)
  }, [ms])
  return now
}
