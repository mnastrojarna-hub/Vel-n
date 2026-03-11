import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'

const DAY_LABELS = ['Pondělí', 'Úterý', 'Středa', 'Čtvrtek', 'Pátek', 'Sobota', 'Neděle']
const DAY_KEYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']

// Katalogové ceny z aplikace MotoGo24 (po, út, st, čt, pá, so, ne)
const CATALOG_PRICES = {
  'BMW R 1200 GS Adventure':   { monday: 4208, tuesday: 3788, wednesday: 3367, thursday: 3788, friday: 4208, saturday: 4882, sunday: 4629 },
  'Jawa RVM 500 Adventure':    { monday: 1986, tuesday: 1788, wednesday: 1589, thursday: 1788, friday: 1986, saturday: 2383, sunday: 2185 },
  'Benelli TRK 702 X':         { monday: 2951, tuesday: 2725, wednesday: 2422, thursday: 2725, friday: 2892, saturday: 3541, sunday: 3331 },
  'CF MOTO 800 MT':            { monday: 3941, tuesday: 3663, wednesday: 3256, thursday: 3663, friday: 3892, saturday: 4729, sunday: 4476 },
  'Yamaha Niken GT':            { monday: 3931, tuesday: 3538, wednesday: 3144, thursday: 3538, friday: 3931, saturday: 4717, sunday: 4252 },
  'Yamaha XT 660 X':            { monday: 1986, tuesday: 1788, wednesday: 1589, thursday: 1788, friday: 1986, saturday: 2383, sunday: 2185 },
  'Kawasaki Z 900':             { monday: 3514, tuesday: 3163, wednesday: 2811, thursday: 3163, friday: 3514, saturday: 4217, sunday: 3865 },
  'Yamaha MT-09':               { monday: 3097, tuesday: 2788, wednesday: 2478, thursday: 2788, friday: 3097, saturday: 3717, sunday: 3407 },
  'Yamaha XTZ 1200 Super Ténéré': { monday: 4417, tuesday: 3975, wednesday: 3533, thursday: 3975, friday: 4417, saturday: 5300, sunday: 4858 },
  'Ducati Multistrada 1200 ABS': { monday: 3486, tuesday: 3138, wednesday: 2789, thursday: 3138, friday: 3486, saturday: 4183, sunday: 3835 },
  'KTM 1290 Super Adventure':   { monday: 4625, tuesday: 4163, wednesday: 3700, thursday: 4163, friday: 4625, saturday: 5550, sunday: 5088 },
  'Yamaha PW 50':               { monday: 1333, tuesday: 1200, wednesday: 1067, thursday: 1200, friday: 1333, saturday: 1600, sunday: 1467 },
  'KTM SX 65':                  { monday: 1000, tuesday: 1000, wednesday: 1000, thursday: 1000, friday: 1200, saturday: 1200, sunday: 1200 },
  'Triumph Tiger 1200 Explorer': { monday: 4208, tuesday: 3788, wednesday: 3367, thursday: 3788, friday: 4208, saturday: 5050, sunday: 4629 },
}

function findCatalogPrices(modelName) {
  if (!modelName) return null
  const lower = modelName.toLowerCase()
  for (const [key, val] of Object.entries(CATALOG_PRICES)) {
    if (lower.includes(key.toLowerCase()) || key.toLowerCase().includes(lower)) return val
  }
  const words = lower.split(/\s+/).filter(w => w.length > 2)
  for (const [key, val] of Object.entries(CATALOG_PRICES)) {
    const keyLower = key.toLowerCase()
    if (words.filter(w => keyLower.includes(w)).length >= 2) return val
  }
  return null
}

export default function PricingTab({ motoId }) {
  const [prices, setPrices] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(false)
  const [motoModel, setMotoModel] = useState(null)

  useEffect(() => { loadPrices() }, [motoId])

  async function loadPrices() {
    setLoading(true)
    const [priceRes, motoRes] = await Promise.all([
      supabase.from('moto_day_prices').select('*').eq('moto_id', motoId).single(),
      supabase.from('motorcycles').select('model').eq('id', motoId).single(),
    ])
    setMotoModel(motoRes.data?.model || null)

    if (priceRes.data) {
      setPrices(priceRes.data)
    } else {
      const catalog = findCatalogPrices(motoRes.data?.model)
      const defaults = { moto_id: motoId }
      DAY_KEYS.forEach(k => { defaults[`price_${k}`] = catalog?.[k] || 0 })
      setPrices(defaults)
    }
    setLoading(false)
  }

  function handleFillFromCatalog() {
    const catalog = findCatalogPrices(motoModel)
    if (!catalog) { setError('Katalogové ceny pro tento model nenalezeny'); return }
    setPrices(p => {
      const updated = { ...p }
      DAY_KEYS.forEach(k => { updated[`price_${k}`] = catalog[k] })
      return updated
    })
    setSuccess(false)
    setError(null)
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

  const hasCatalog = !!findCatalogPrices(motoModel)
  const allZero = DAY_KEYS.every(k => !prices[`price_${k}`] || Number(prices[`price_${k}`]) === 0)

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>
          Ceník podle dne v týdnu
        </h3>
        {hasCatalog && (
          <button onClick={handleFillFromCatalog}
            className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
            style={{ padding: '5px 12px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
            Naplnit z katalogu
          </button>
        )}
      </div>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Ceny za den pronájmu. Změny se projeví na všech frontech (web, aplikace).
        {allZero && hasCatalog && <span className="ml-2 font-bold" style={{ color: '#b45309' }}>Ceník je prázdný – klikněte "Naplnit z katalogu" a uložte.</span>}
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
