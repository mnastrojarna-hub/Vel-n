import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'
import GearRentals from './GearRentals'

// Záložka „Výpůjčky“: od 2026-10-23 je výpůjčka výbavy běžná rezervace (bookings.booking_kind='gear')
// → spravuje se v Rezervacích (filtr „Jen výbava“, deep-link /rezervace?kind=gear).
// Starý seznam objednávek z e-shopové cesty (gear_rentals + shop_orders, create_gear_rental_order
// je vypnutá) se ukáže JEN, když v tabulce nějaké řádky jsou — kvůli dořešení starších objednávek.

async function countOf(query) {
  try {
    const { count, error } = await query
    return error ? null : (count ?? 0)
  } catch { return null }
}

export default function GearBookingsLink({ prices }) {
  const navigate = useNavigate()
  const [upcoming, setUpcoming] = useState(null)
  const [pending, setPending] = useState(null)
  const [legacy, setLegacy] = useState(null)

  useEffect(() => {
    const gear = () => supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('booking_kind', 'gear')
    countOf(gear().in('status', ['reserved', 'active'])).then(setUpcoming)
    countOf(gear().eq('status', 'pending')).then(setPending)
    countOf(supabase.from('gear_rentals').select('order_id', { count: 'exact', head: true })).then(setLegacy)
  }, [])

  return (
    <div className="space-y-4">
      <div className="bg-white rounded-card shadow-card" style={{ padding: 16 }}>
        <div className="font-extrabold uppercase tracking-wide text-sm mb-2" style={{ color: '#1a2e22' }}>Výpůjčky výbavy jsou v Rezervacích</div>
        <p className="text-sm mb-3" style={{ color: '#1a2e22', lineHeight: 1.6 }}>
          Každá výpůjčka výbavy bez motorky je rezervace se stejnými stavy jako rezervace motorky
          (čeká na platbu → rezervováno → aktivní → dokončeno / zrušeno). Detail, platby, doklady, kódy, předávací
          protokol i úpravy termínu najdeš v Rezervacích pod filtrem „Jen výbava“.
        </p>
        {(upcoming !== null || pending !== null) && (
          <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>
            {upcoming !== null && <>Rezervované a probíhající: <strong>{upcoming}</strong></>}
            {upcoming !== null && pending !== null && ' · '}
            {pending !== null && <>čeká na platbu: <strong>{pending}</strong></>}
          </p>
        )}
        <Button green onClick={() => navigate('/rezervace?kind=gear')} className="max-lg:min-h-[40px]">Otevřít výpůjčky výbavy</Button>
      </div>

      {legacy > 0 && (
        <div className="space-y-2">
          <div className="font-extrabold uppercase tracking-wide text-sm" style={{ color: '#1a2e22' }}>Starší objednávky výbavy (e-shop, před převodem na rezervace)</div>
          <p className="text-xs" style={{ color: '#6b7a72' }}>
            Objednávky vytvořené původní cestou přes e-shop ({legacy}). Nové výpůjčky už sem nepřibývají.
          </p>
          <GearRentals prices={prices} />
        </div>
      )}
    </div>
  )
}
