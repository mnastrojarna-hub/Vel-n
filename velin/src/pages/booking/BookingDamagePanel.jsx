import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'

// Ruční zápis poškození k rezervaci (RPC `admin_set_booking_damage`).
// Poškozené zapůjčení se NEPOČÍTÁ do „km bez nehody a škrábnutí" ve
// věrnostním žebříčku. Rank tím sám o sobě neklesá — degradace je
// samostatné tlačítko u zákazníka (Zákazníci → detail → Věrnostní rank).
export default function BookingDamagePanel({ booking, onSaved }) {
  const [open, setOpen] = useState(false)
  const [note, setNote] = useState(booking?.damage_note || '')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const on = !!booking?.damage_flag

  async function save(damage) {
    setSaving(true); setError(null)
    const { error: err } = await supabase.rpc('admin_set_booking_damage', {
      p_booking_id: booking.id, p_damage: damage, p_note: damage ? note : null,
    })
    setSaving(false)
    if (err) { setError(err.message); return }
    setOpen(false)
    onSaved?.()
  }

  return (
    <Card className="mb-4">
      <div className="flex items-center gap-3 flex-wrap">
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>Poškození / nehoda</span>
        {on ? (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5' }}
            title={booking.damage_note || 'Zapsáno ručně ve Velíně'}>
            POŠKOZENO
          </span>
        ) : (
          <span className="text-sm" style={{ color: '#1a2e22' }}>Bez zápisu — zapůjčení se počítá jako čisté.</span>
        )}
        <div className="ml-auto flex gap-2">
          {on
            ? <Button small outline onClick={() => save(false)} disabled={saving}>Zrušit zápis</Button>
            : <Button small onClick={() => setOpen(o => !o)} disabled={saving}>Zapsat poškození</Button>}
        </div>
      </div>
      {on && booking.damage_note && (
        <div className="mt-2 text-sm" style={{ color: '#1a2e22' }}>{booking.damage_note}</div>
      )}
      {open && !on && (
        <div className="mt-3 flex gap-2 items-start flex-wrap">
          <textarea value={note} onChange={e => setNote(e.target.value)} rows={2}
            placeholder="Co se stalo (škrábnutí, pád, nehoda…) — nepovinné"
            className="flex-1 rounded-card text-sm"
            style={{ minWidth: 240, padding: '8px 10px', border: '1px solid #b6dccb', color: '#0f1a14' }} />
          <Button small green onClick={() => save(true)} disabled={saving}>
            {saving ? 'Ukládám…' : 'Uložit'}
          </Button>
        </div>
      )}
      {error && <div className="mt-2 text-sm" style={{ color: '#dc2626' }}>{error}</div>}
    </Card>
  )
}
