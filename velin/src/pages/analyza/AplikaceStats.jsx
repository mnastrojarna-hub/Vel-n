/**
 * MotoGo24 Velín — Analýza / Aplikace (instalace + používání)
 *
 * Ukazuje, kolik zákazníků má nainstalovanou mobilní appku — BEZ nového buildu
 * appky. Přesný počet instalací z Google Play (Play Developer API) nemáme, takže
 * používáme nejbližší proxy z dat, která appka už dnes posílá:
 *   - „Aktivní zařízení" = počet unikátních (user_id, platform) mezi aktivními
 *     push tokeny. FCM token se rotuje (onTokenRefresh → nový řádek), takže
 *     count(*) řádků reálná zařízení nadhodnocuje; dedup přes (účet, platforma)
 *     rotované tokeny téhož zařízení sloučí → nejbližší odhad počtu instalací.
 *   - Android / iOS rozpad = unikátní účty (distinct user_id) dané platformy.
 *   - „Uživatelé appky" = unikátní účty (distinct user_id) s aktivním zařízením.
 *   - „Rezervace přes appku" = bookings.booking_source = 'app'.
 *
 * Data čte server-side RPC `get_app_install_stats()` (SECURITY DEFINER, gate
 * is_admin()) — vrací jeden JSON s agregáty, nestahuje raw řádky.
 */
import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

const CARDS = [
  { key: 'active_devices', label: 'Aktivní zařízení', hint: '≈ počet instalací appky (unikátní účet × platforma, rotované tokeny sloučeny)', big: true },
  { key: 'android', label: 'Android', hint: 'aktivní účty na Androidu' },
  { key: 'ios', label: 'iOS', hint: 'aktivní účty na iOS' },
  { key: 'app_users', label: 'Uživatelé appky', hint: 'unikátní účty s aktivním zařízením' },
  { key: 'app_bookings', label: 'Rezervace přes appku', hint: "booking_source = 'app'" },
  { key: 'total_devices', label: 'Zařízení celkem', hint: 'vč. odhlášených (unikátní účet × platforma)' },
]

export default function AplikaceStats() {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, error } = await supabase.rpc('get_app_install_stats')
      if (error) throw error
      setData(typeof data === 'string' ? JSON.parse(data) : data)
    } catch (e) {
      setError(e?.message || String(e))
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div style={{ padding: 20, color: '#888' }}>Načítám statistiky aplikace…</div>

  if (error) return (
    <div style={{ padding: 16, background: '#fff3f3', border: '1px solid #f0c0c0', borderRadius: 10, color: '#9a2a2a', maxWidth: 560 }}>
      <strong>Statistiku se nepodařilo načíst.</strong>
      <div style={{ fontSize: 13, marginTop: 6 }}>{error}</div>
      <div style={{ fontSize: 13, marginTop: 8, color: '#666' }}>
        Zkontroluj, že je v Supabase vytvořená RPC <code>get_app_install_stats()</code>.
      </div>
      <button
        onClick={load}
        style={{ marginTop: 10, padding: '6px 14px', background: '#74FB71', border: 'none', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }}
      >
        Zkusit znovu
      </button>
    </div>
  )

  const val = (k) => Number(data?.[k] ?? 0).toLocaleString('cs-CZ')

  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14, marginBottom: 16 }}>
        {CARDS.map((c) => (
          <div
            key={c.key}
            style={{
              background: c.big ? '#1a2e22' : '#fff',
              color: c.big ? '#fff' : '#1a2e22',
              border: c.big ? 'none' : '1px solid #e3ece8',
              borderRadius: 14,
              padding: '16px 18px',
              boxShadow: c.big ? '0 8px 24px rgba(26,46,34,.18)' : '0 2px 10px rgba(26,46,34,.05)',
            }}
          >
            <div style={{ fontSize: c.big ? 38 : 30, fontWeight: 800, lineHeight: 1.1, color: c.big ? '#74FB71' : '#1a2e22' }}>
              {val(c.key)}
            </div>
            <div style={{ fontSize: 14, fontWeight: 700, marginTop: 4 }}>{c.label}</div>
            <div style={{ fontSize: 12, color: c.big ? 'rgba(255,255,255,.7)' : '#7a8b82', marginTop: 3 }}>{c.hint}</div>
          </div>
        ))}
      </div>

      <p style={{ fontSize: 12.5, color: '#7a8b82', lineHeight: 1.6, maxWidth: 720 }}>
        ℹ️ Čísla jsou <strong>odhad bez nového buildu appky</strong> — vychází z registrovaných zařízení
        (push tokeny) a rezervací přes appku. „Aktivní zařízení" se počítá jako unikátní kombinace
        účtu a platformy, takže rotace FCM tokenu (po reinstalaci/obnově) totéž zařízení nezdvojuje.
        Není to oficiální počet instalací z Google Play (ten by vyžadoval Play Developer API).
      </p>
    </div>
  )
}
