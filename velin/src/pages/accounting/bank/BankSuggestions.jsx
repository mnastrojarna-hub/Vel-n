import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import Button from '../../../components/ui/Button'
import Badge from '../../../components/ui/Badge'
import { suggestTargets } from './bankApi'
import { searchTargets } from './bankSearch'
import { fmtMoney, fmtDateTime, fmtUntil } from './bankFormat'

const CONFIDENCE = {
  high: { label: 'Vysoká shoda', color: '#1a8a18', bg: '#dcfce7' },
  medium: { label: 'Střední shoda', color: '#b45309', bg: '#fef3c7' },
  low: { label: 'Jen stejná částka', color: '#1a2e22', bg: '#f3f4f6' },
}
const STATE = {
  expired: { label: 'Po lhůtě', color: '#b45309', bg: '#fef3c7' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
}
const H = ({ children }) => <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{children}</h3>
const Note = ({ children }) => <p className="mb-2" style={{ fontSize: 13, color: '#4a6357', lineHeight: 1.55 }}>{children}</p>

/** Jeden možný cíl (návrh serveru nebo výsledek ručního hledání) s JEDNÍM tlačítkem „Spárovat“. */
function TargetRow({ t, received, onPair }) {
  const conf = CONFIDENCE[t.confidence]
  const st = STATE[t.state]
  const same = Math.abs(Number(t.amount) - Number(received)) < 0.005
  const open = t.booking_id ? `/rezervace/${t.booking_id}` : t.order_id ? '/e-shop' : null
  return (
    <div className="p-3 rounded-card mb-2" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }} data-target={`${t.target_type}:${t.target_id}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{t.label}</span>
            {conf && <Badge label={conf.label} color={conf.color} bg={conf.bg} />}
            {st && <Badge label={st.label} color={st.color} bg={st.bg} />}
          </div>
          <div style={{ fontSize: 13, color: '#1a2e22', overflowWrap: 'anywhere' }}>
            {[t.customer_name, t.customer_email].filter(Boolean).join(' · ') || 'zákazník neuveden'}
          </div>
          <div style={{ fontSize: 12, color: '#4a6357' }}>
            čeká se <b style={{ color: same ? '#1a8a18' : '#b45309' }}>{fmtMoney(t.amount)}</b>
            {t.vs ? <> · VS <span className="font-mono">{t.vs}</span></> : null}
            {t.info ? <> · {t.info}</> : null}
            {t.created_at ? <> · vytvořeno {fmtDateTime(t.created_at)}</> : null}
            {t.expires_at ? <> · lhůta {fmtUntil(t.expires_at)}</> : null}
          </div>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {open && <Link to={open} target="_blank" rel="noreferrer" className="text-sm font-bold" style={{ color: '#2563eb' }}>Otevřít ↗</Link>}
          {t.disabled
            ? <span className="text-sm font-bold" style={{ color: '#4a6357' }}>{t.disabled}</span>
            : <Button green small onClick={() => onPair(t)} className="max-lg:min-h-[36px]">Spárovat</Button>}
        </div>
      </div>
      {Array.isArray(t.reasons) && t.reasons.length > 0 && (
        <ul className="mt-2" style={{ fontSize: 12, color: '#1a2e22', paddingLeft: 18, listStyle: 'disc', lineHeight: 1.5 }}>
          {t.reasons.map((r, i) => <li key={i}>{r}</li>)}
        </ul>
      )}
    </div>
  )
}

// Návrhy serveru (akce suggest: stejná částka mezi čekajícími platbami + podobnost jména / VS / zprávy)
// a ruční hledání jiného cíle. Samo se NIKDY nic nespáruje — vždy až po kliknutí a potvrzení.
export default function BankSuggestions({ tx, onPair }) {
  const [state, setState] = useState('loading') // loading | ready | missing | error
  const [candidates, setCandidates] = useState([])
  const [q, setQ] = useState('')
  const [searching, setSearching] = useState(false)
  const [found, setFound] = useState(null)

  useEffect(() => {
    let on = true
    setState('loading')
    suggestTargets(tx.fio_id).then(r => {
      if (!on) return
      if (r.ok) { setCandidates(Array.isArray(r.data.candidates) ? r.data.candidates.map(c => ({ ...c, source: 'suggest' })) : []); setState('ready') }
      else setState(r.missing ? 'missing' : 'error')
    })
    return () => { on = false }
  }, [tx.fio_id, tx.status])

  async function search(e) {
    e?.preventDefault?.()
    if (q.trim().length < 2) return
    setSearching(true)
    const list = await searchTargets(q)
    const amt = Number(tx.amount)
    list.sort((a, b) => (Math.abs(a.amount - amt) < 0.005 ? 0 : 1) - (Math.abs(b.amount - amt) < 0.005 ? 0 : 1))
    setFound(list); setSearching(false)
  }

  const inp = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14, color: '#1a2e22' }

  return (
    <div>
      <H>Návrhy ke spárování</H>
      {state === 'loading' && <Note>Hledám čekající platby se stejnou částkou…</Note>}
      {state === 'missing' && <Note>Návrhy budou dostupné po nasazení serverové části. Cíl zatím najdete ručním hledáním níže.</Note>}
      {state === 'error' && <Note>Návrhy se nepodařilo načíst — použijte ruční hledání níže.</Note>}
      {state === 'ready' && candidates.length === 0 && (
        <Note>Žádná čekající platba na stejnou částku {fmtMoney(tx.amount, tx.currency)}. Zkuste ruční hledání, nebo pohyb ignorujte s poznámkou.</Note>
      )}
      {state === 'ready' && candidates.length > 0 && (
        <div data-bank="suggestions">
          <Note>Čekající platby na stejnou částku, seřazené podle shody. Nic se nespáruje samo — vyberte a potvrďte.</Note>
          {candidates.map(c => <TargetRow key={`${c.target_type}:${c.target_id}`} t={c} received={tx.amount} onPair={onPair} />)}
        </div>
      )}

      <div className="mt-4" data-bank="manual-search">
        <H>Najít jiný cíl ručně</H>
        <form onSubmit={search} className="flex flex-wrap items-center gap-2 mb-2">
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Číslo rezervace, VS, jméno zákazníka, číslo objednávky…"
            className="flex-1 min-w-0" style={{ ...inp, minWidth: 180 }} aria-label="Hledat cíl spárování" />
          <Button small type="submit" disabled={searching || q.trim().length < 2} className="max-lg:min-h-[36px]">{searching ? 'Hledám…' : 'Hledat'}</Button>
        </form>
        {found && found.length === 0 && <Note>Nic nenalezeno. Zkuste jiné jméno, celé číslo rezervace (8 znaků) nebo VS.</Note>}
        {found && found.map(t => <TargetRow key={`${t.target_type}:${t.target_id}`} t={t} received={tx.amount} onPair={onPair} />)}
      </div>
    </div>
  )
}
