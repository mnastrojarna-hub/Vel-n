import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'

const DAY_LABELS = ['Pondělí', 'Úterý', 'Středa', 'Čtvrtek', 'Pátek', 'Sobota', 'Neděle']
const DAY_KEYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']

export default function PricingTab({ motoId }) {
  const [prices, setPrices] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(false)

  useEffect(() => { loadPrices() }, [motoId])

  async function loadPrices() {
    setLoading(true)
    const { data } = await supabase.from('moto_day_prices').select('*').eq('moto_id', motoId).single()

    if (data) {
      setPrices(data)
    } else {
      // Fallback: load day prices from motorcycles table (price_mon..price_sun)
      const { data: moto } = await supabase.from('motorcycles')
        .select('price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
        .eq('id', motoId).single()
      const defaults = { moto_id: motoId }
      if (moto) {
        defaults.price_monday = Number(moto.price_mon) || 0
        defaults.price_tuesday = Number(moto.price_tue) || 0
        defaults.price_wednesday = Number(moto.price_wed) || 0
        defaults.price_thursday = Number(moto.price_thu) || 0
        defaults.price_friday = Number(moto.price_fri) || 0
        defaults.price_saturday = Number(moto.price_sat) || 0
        defaults.price_sunday = Number(moto.price_sun) || 0
      } else {
        DAY_KEYS.forEach(k => { defaults[`price_${k}`] = 0 })
      }
      setPrices(defaults)
    }
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true)
    setError(null)
    setSuccess(false)
    try {
      const payload = { moto_id: motoId }
      DAY_KEYS.forEach(k => {
        payload[`price_${k}`] = Number(prices[`price_${k}`]) || 0
      })

      if (prices.id) {
        const { error: err } = await supabase
          .from('moto_day_prices')
          .update(payload)
          .eq('id', prices.id)
        if (err) throw err
      } else {
        const { data, error: err } = await supabase
          .from('moto_day_prices')
          .insert(payload)
          .select()
          .single()
        if (err) throw err
        setPrices(data)
      }

      // Sync prices to motorcycles table so MotoGo app picks them up immediately
      const weekdayAvg = Math.round((
        (Number(payload.price_monday) || 0) +
        (Number(payload.price_tuesday) || 0) +
        (Number(payload.price_wednesday) || 0) +
        (Number(payload.price_thursday) || 0) +
        (Number(payload.price_friday) || 0)
      ) / 5)
      const weekendAvg = Math.round((
        (Number(payload.price_saturday) || 0) +
        (Number(payload.price_sunday) || 0)
      ) / 2)
      await supabase.from('motorcycles').update({
        price_mon: Number(payload.price_monday) || 0,
        price_tue: Number(payload.price_tuesday) || 0,
        price_wed: Number(payload.price_wednesday) || 0,
        price_thu: Number(payload.price_thursday) || 0,
        price_fri: Number(payload.price_friday) || 0,
        price_sat: Number(payload.price_saturday) || 0,
        price_sun: Number(payload.price_sunday) || 0,
        price_weekday: weekdayAvg,
        price_weekend: weekendAvg,
      }).eq('id', motoId)

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'moto_pricing_updated',
        details: { moto_id: motoId },
      })
      setSuccess(true)
      setTimeout(() => setSuccess(false), 3000)
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  function setPrice(key, value) {
    setPrices(p => ({ ...p, [`price_${key}`]: value }))
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>
        Ceník podle dne v týdnu
      </h3>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Ceny za den pronájmu. Změny se projeví na všech frontech (web, aplikace).
      </p>
      <div className="space-y-2">
        {DAY_KEYS.map((key, i) => {
          const isWeekend = i >= 5
          return (
            <div key={key} className="flex items-center gap-3 p-3 rounded-lg" style={{
              background: isWeekend ? '#fef3c7' : '#f1faf7',
              border: `1px solid ${isWeekend ? '#fde68a' : '#d4e8e0'}`,
            }}>
              <span className="text-sm font-extrabold w-20" style={{ color: '#0f1a14' }}>
                {DAY_LABELS[i]}
              </span>
              {isWeekend && (
                <span className="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded"
                  style={{ background: '#fde68a', color: '#92400e' }}>Víkend</span>
              )}
              <div className="ml-auto flex items-center gap-2">
                <input
                  type="number"
                  value={prices[`price_${key}`] || ''}
                  onChange={e => setPrice(key, e.target.value)}
                  className="rounded-btn text-sm font-bold text-right outline-none"
                  style={{ width: 100, padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#0f1a14' }}
                  placeholder="0"
                />
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Kč</span>
              </div>
            </div>
          )
        })}
      </div>
      {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      {success && <p className="mt-3 text-sm font-bold" style={{ color: '#1a8a18' }}>Ceník uložen a aktualizován na všech frontech.</p>}
      <div className="flex justify-end mt-5">
        <Button green onClick={handleSave} disabled={saving}>
          {saving ? 'Ukládám...' : 'Uložit ceník'}
        </Button>
      </div>
    </Card>
  )
}
