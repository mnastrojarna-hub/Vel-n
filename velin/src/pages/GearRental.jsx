import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugLog } from '../lib/debugLog'
import GearPriceList from '../components/gear/GearPriceList'
import GearBookingsLink from '../components/gear/GearBookingsLink'

// Flotila → Půjčení oblečení: půjčení JEN výbavy (bez motorky) z webu /pujceni-obleceni.
// Ceník gear_rental_prices + nastavení app_settings.gear_rental / gear_stock_check.
// Výpůjčky = rezervace bookings.booking_kind='gear' (od 20261023a) → záložka „Výpůjčky“
// odkazuje do Rezervací (/rezervace?kind=gear); starý seznam gear_rentals jen pro dřívější objednávky.

const TABS = ['Ceník', 'Výpůjčky']
const TAB_STORE = 'velin_gear_rental_tab'

function initialTab() {
  try {
    const t = localStorage.getItem(TAB_STORE)
    if (TABS.includes(t)) return t
  } catch { /* blokované úložiště */ }
  return TABS[0]
}

export default function GearRental() {
  const navigate = useNavigate()
  const [tab, setTab] = useState(initialTab)
  const [prices, setPrices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => { debugLog('page.mount', 'GearRental'); loadPrices() }, [])

  async function loadPrices() {
    setError(null)
    try {
      const { data, error: e } = await supabase.from('gear_rental_prices').select('*')
        .order('sort_order').order('key')
      if (e) throw e
      setPrices(data || [])
    } catch (e) {
      setError(`Načtení ceníku selhalo: ${e.message}`)
    }
    setLoading(false)
  }

  function switchTab(t) {
    debugLog('tab.switch', 'GearRental', { tab: t })
    setTab(t)
    try { localStorage.setItem(TAB_STORE, t) } catch { /* ignore */ }
  }

  return (
    <div>
      <button type="button" onClick={() => navigate('/flotila')}
        className="text-sm font-bold cursor-pointer bg-transparent border-none p-0 mb-2 max-lg:min-h-[36px]" style={{ color: '#1a2e22' }}>
        ← Flotila
      </button>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Půjčení oblečení</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>
        Půjčení jen výbavy bez motorky (web → Půjčení oblečení) · ceník za den a přehled výpůjček
      </p>

      <div className="flex flex-wrap gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => switchTab(t)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap max-lg:min-h-[40px]"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Výpůjčky' && <GearBookingsLink prices={prices} />}
      {tab === 'Ceník' && <GearPriceList prices={prices} loading={loading} error={error} reload={loadPrices} />}
    </div>
  )
}
