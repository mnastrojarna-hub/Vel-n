/**
 * MotoGo24 Velín — Analýza / Aplikace (instalace + používání)
 *
 * Ukazuje, kolik zákazníků má nainstalovanou mobilní appku a jak ji používají.
 * Přesný počet instalací z Google Play (Play Developer API) nemáme, ale od
 * buildu s `InstallationService` má appka vlastní přesnou evidenci:
 *   - Každá instalace má stabilní náhodné UUID (NE hardwarový identifikátor —
 *     Google Play safe) a posílá „heartbeat" do `app_installations`
 *     (device_id, user_id, platform, app_version, push_enabled, last_seen_at).
 *   - Z toho se počítá nezávisle na souhlasu s pushem:
 *       • „Aktivní zařízení" = MAU (instalace viděné za posledních 30 dní)
 *       • DAU / WAU = za 24 h / 7 dní
 *       • „Uživatelé appky" = unikátní účty (distinct user_id)
 *       • Android / iOS rozpad, „Push povoleno"
 *       • „Instalace celkem" = všechny evidované instalace
 *   - „Rezervace přes appku" = bookings.booking_source = 'app'.
 *
 * PŘECHOD: „Dle push tokenů (přechodně)" je starý odhad z `push_tokens`
 * (dedup přes user_id+platform). Než se nový build rozšíří mezi uživatele,
 * slouží jako referenční číslo — postupně ho nahradí přesná `app_installations`.
 *
 * Data čte server-side RPC `get_app_install_stats()` (SECURITY DEFINER, gate
 * is_admin()) — vrací jeden JSON s agregáty, nestahuje raw řádky.
 */
import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

const CARDS = [
  { key: 'active_devices', label: 'Aktivní zařízení (30 dní)', hint: 'MAU — instalace viděné za posledních 30 dní', big: true },
  { key: 'dau', label: 'Denně aktivní', hint: 'zařízení za posledních 24 h' },
  { key: 'wau', label: 'Týdně aktivní', hint: 'zařízení za posledních 7 dní' },
  { key: 'app_users', label: 'Uživatelé appky', hint: 'unikátní účty s evidovanou instalací' },
  { key: 'android', label: 'Android', hint: 'aktivní zařízení Android (30 dní)' },
  { key: 'ios', label: 'iOS', hint: 'aktivní zařízení iOS (30 dní)' },
  { key: 'push_enabled_devices', label: 'Push povoleno', hint: 'aktivní zařízení s povolenými notifikacemi' },
  { key: 'app_bookings', label: 'Rezervace přes appku', hint: "booking_source = 'app'" },
  { key: 'installs_total', label: 'Instalace celkem', hint: 'všechny evidované instalace' },
  { key: 'push_active_devices', label: 'Dle push tokenů (přechodně)', hint: 'starý odhad z push_tokens, než se rozšíří nový build' },
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

      <p style={{ fontSize: 12.5, color: '#7a8b82', lineHeight: 1.6, maxWidth: 760 }}>
        ℹ️ Čísla vychází z <strong>vlastní evidence instalací</strong> (každá instalace má stabilní
        náhodný identifikátor a hlásí „heartbeat", nezávisle na souhlasu s push notifikacemi).
        „Aktivní zařízení" = instalace aktivní za posledních 30 dní (MAU). Není to oficiální počet
        instalací z Google Play (ten by vyžadoval Play Developer API a nepokrývá iOS). Karta
        <strong> „Dle push tokenů (přechodně)"</strong> je starý odhad — slouží jako reference, než se
        nový build appky rozšíří mezi uživatele; pak ji přesná evidence plně nahradí.
      </p>
    </div>
  )
}
