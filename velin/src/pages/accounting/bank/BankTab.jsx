import { useState, useEffect, useCallback, useRef } from 'react'
import { loadOverview } from './bankApi'
import { useBankTick, useNow } from './bankLive'
import { reportBankOverview } from './bankBadgeStore'
import BankStatus from './BankStatus'
import BankMovements from './BankMovements'
import BankWaiting from './BankWaiting'
import BankOrders from './BankOrders'

const VIEWS = [['movements', 'Pohyby na účtu'], ['waiting', 'Čekající platby'], ['orders', 'Platební příkazy (vratky)']]
const TOAST = { ok: ['#dcfce7', '#166534', '#86efac'], warn: ['#fef3c7', '#92400e', '#fcd34d'], bad: ['#fee2e2', '#b91c1c', '#fca5a5'] }

// Finance → Banka: pohyby na účtu u Fio, nespárované platby s návrhem ke spárování, čekající platby,
// platební příkazy a hlídání platnosti API tokenu.
// Dokud není nasazená databázová část (tabulky / RPC chybí nebo vracejí chybu), ukáže záložka JEN klidné
// upozornění: jeden dotaz při otevření, žádné opakování, žádný realtime kanál ani interval.
export default function BankTab() {
  const [gate, setGate] = useState('loading') // loading | ready | missing | forbidden
  const [overview, setOverview] = useState(null)
  const [view, setView] = useState('movements')
  const [toast, setToast] = useState(null)
  const toastTimer = useRef(null)
  const alive = useRef(true)
  const tick = useBankTick(gate === 'ready')
  const now = useNow()

  const refresh = useCallback(async (first = false) => {
    const r = await loadOverview()
    if (!alive.current) return
    if (r.ok) { setOverview(r.overview); setGate('ready'); reportBankOverview(r.overview) }
    else if (first) setGate(r.code === 'forbidden' ? 'forbidden' : 'missing')
    // pozdější chyba (výpadek sítě) → zůstává poslední známý stav, bez hlášek
  }, [])

  useEffect(() => {
    alive.current = true
    refresh(true)
    return () => { alive.current = false; clearTimeout(toastTimer.current) }
  }, [refresh])
  useEffect(() => { if (tick) refresh() }, [tick, refresh])

  const notify = useCallback((tone, text) => {
    clearTimeout(toastTimer.current)
    setToast({ tone, text })
    toastTimer.current = setTimeout(() => setToast(null), 7000)
  }, [])

  if (gate === 'loading') return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (gate !== 'ready') {
    return (
      <div className="p-5 rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22', fontSize: 14 }} data-bank="unavailable">
        {gate === 'forbidden' ? 'K bankovnímu přehledu nemáte oprávnění.' : 'Bankovní přehled bude dostupný po nasazení databázové části.'}
      </div>
    )
  }

  const tc = toast ? TOAST[toast.tone] || TOAST.ok : null
  return (
    <div data-bank="tab">
      <BankStatus overview={overview} now={now} onChanged={() => refresh()} notify={notify} />

      <div className="flex gap-1 mb-4 flex-wrap">
        {VIEWS.map(([k, l]) => (
          <button key={k} onClick={() => setView(k)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[36px]"
            style={{ padding: '6px 14px', border: 'none', background: view === k ? '#1a2e22' : '#f1faf7', color: view === k ? '#74FB71' : '#1a2e22', boxShadow: view === k ? '0 2px 8px rgba(26,46,34,.25)' : 'none' }}>
            {l}
          </button>
        ))}
      </div>

      {view === 'movements' && <BankMovements tick={tick} todoCount={overview.todo_count} notify={notify} onChanged={() => refresh()} />}
      {view === 'waiting' && <BankWaiting tick={tick} now={now} />}
      {view === 'orders' && <BankOrders tick={tick} />}

      {toast && (
        <div role="status" className="fixed z-[60] rounded-card shadow-card" data-bank="toast" onClick={() => setToast(null)}
          style={{ right: 16, bottom: 16, left: 16, maxWidth: 460, marginLeft: 'auto', padding: '12px 16px', fontSize: 13, fontWeight: 700, lineHeight: 1.5, cursor: 'pointer', background: tc[0], color: tc[1], border: `1px solid ${tc[2]}` }}>
          {toast.text}
        </div>
      )}
    </div>
  )
}
