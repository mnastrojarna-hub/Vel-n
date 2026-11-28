import { useState, useEffect } from 'react'
import Button from '../../../components/ui/Button'
import { formatIban } from '../../../lib/company'
import { syncNow } from './bankApi'
import { errorText, fmtAgo, fmtDate, fmtDateTime, daysWord } from './bankFormat'
import BankTokenModal from './BankTokenModal'

const COOLDOWN_MS = 30000 // banka: jeden dotaz na token za 30 s
const TONE = { ok: '#1a8a18', warn: '#b45309', bad: '#dc2626', mute: '#4a6357' }

const SYNC = {
  ok: { label: 'OK', tone: 'ok' },
  failing: { label: 'Chyba', tone: 'bad' },
  stale: { label: 'Neběží', tone: 'bad' },
  never: { label: 'Zatím neproběhla', tone: 'warn' },
}

/** Platnost tokenu → { text, sub, tone } (oranžově pod 30 dní, červeně pod 7). */
export function tokenInfo(validUntil, days) {
  if (!validUntil || days === null || days === undefined) return { text: 'Datum neznámé', sub: 'Doplňte, do kdy token platí — Velín vás včas upozorní.', tone: 'warn', unknown: true }
  const tone = days < 7 ? 'bad' : days < 30 ? 'warn' : 'ok'
  if (days < 0) return { text: `Platnost skončila ${fmtDate(validUntil)}`, sub: `před ${-days} ${-days === 1 ? 'dnem' : 'dny'} — vystavte v bance nový token`, tone }
  return { text: `Platí do ${fmtDate(validUntil)}`, sub: days === 0 ? 'platí už jen dnes' : `zbývá ${days} ${daysWord(days)}`, tone }
}

function Tile({ label, children }) {
  return (
    <div className="p-3 rounded-card min-w-0" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      {children}
    </div>
  )
}
const Sub = ({ children, tone = 'mute', title }) => (
  <div title={title} style={{ fontSize: 12, lineHeight: 1.5, color: TONE[tone], fontWeight: tone === 'mute' ? 500 : 700, overflowWrap: 'anywhere' }}>{children}</div>
)

// Stavový pruh: poslední synchronizace, účet, platnost tokenu, ruční synchronizace.
export default function BankStatus({ overview, now, onChanged, notify }) {
  const [busy, setBusy] = useState(false)
  const [coolUntil, setCoolUntil] = useState(0)
  const [clock, setClock] = useState(() => Date.now())
  const [msg, setMsg] = useState(null)
  const [editToken, setEditToken] = useState(false)

  useEffect(() => {
    if (coolUntil <= Date.now()) return undefined
    const t = setInterval(() => setClock(Date.now()), 1000)
    return () => clearInterval(t)
  }, [coolUntil])

  const s = overview.state || {}
  const sync = SYNC[overview.sync] || SYNC.never
  const token = tokenInfo(s.token_valid_until, overview.token_days_left)
  const payToken = s.pay_token_valid_until ? tokenInfo(s.pay_token_valid_until, overview.pay_token_days_left) : null
  const wait = Math.max(0, Math.ceil((coolUntil - clock) / 1000))

  async function doSync() {
    setBusy(true); setMsg(null)
    const r = await syncNow()
    setBusy(false)
    setCoolUntil(Date.now() + COOLDOWN_MS); setClock(Date.now())
    if (r.ok) {
      const d = r.data
      if (d.skipped === 'rate_limited') setMsg({ tone: 'warn', text: 'Banka dovoluje jeden dotaz za 30 s — zkuste to za 30 s.' })
      else if (d.skipped === 'busy') setMsg({ tone: 'warn', text: 'Právě běží automatická synchronizace — výsledek uvidíte za chvíli.' })
      else {
        const done = (d.confirmed || 0) + (d.surcharge || 0) + (d.orders || 0) + (d.changes || 0)
        const todo = (d.no_match || 0) + (d.mismatch || 0) + (d.review || 0) + (d.errors || 0)
        setMsg({ tone: 'ok', text: `Hotovo — nových pohybů: ${d.fetched || 0}, spárováno: ${done}, k vyřešení: ${todo}.` })
      }
    } else if (r.missing) setMsg({ tone: 'warn', text: 'Ruční synchronizace bude dostupná po nasazení serverové části.' })
    else if (r.lost) setMsg({ tone: 'warn', text: 'Odpověď nedorazila — synchronizace možná ještě běží, stav se obnoví sám.' })
    else setMsg({ tone: 'bad', text: errorText(r.code) })
    onChanged()
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3 mb-4">
      <Tile label="Synchronizace s bankou">
        <div className="text-lg font-extrabold" style={{ color: TONE[sync.tone] }}>{sync.label}</div>
        <Sub title={s.last_ok_at ? fmtDateTime(s.last_ok_at) : undefined}>
          Poslední úspěšná: {s.last_ok_at ? fmtAgo(s.last_ok_at, now) : 'zatím žádná'}
        </Sub>
        {overview.sync === 'failing' && (
          <Sub tone="bad">{errorText(s.last_error)}{s.last_error_at ? ` (od ${fmtDateTime(s.last_error_at)})` : ''}</Sub>
        )}
        {overview.sync === 'stale' && <Sub tone="bad">Pohyby se déle než 20 minut nestáhly — automatická synchronizace se nespouští.</Sub>}
        {overview.sync === 'never' && <Sub>Pohyby se začnou stahovat po nastavení API tokenu banky.</Sub>}
      </Tile>

      <Tile label="Účet">
        <div className="text-sm font-extrabold font-mono" style={{ color: '#0f1a14', overflowWrap: 'anywhere' }}>
          {overview.company_account || formatIban(overview.company_iban) || '—'}
        </div>
        <Sub>Účet z firemních údajů (na něj platí zákazníci)</Sub>
        {s.account_iban
          ? <Sub>Token čte: <span className="font-mono">{formatIban(s.account_iban)}</span></Sub>
          : <Sub>Účet tokenu se zjistí při první synchronizaci.</Sub>}
        {overview.account_match === true && <Sub tone="ok">✓ Token patří ke stejnému účtu</Sub>}
        {overview.account_match === false && <Sub tone="bad">Pozor: token čte JINÝ účet, než na který platí zákazníci — platby se nespárují.</Sub>}
      </Tile>

      <Tile label="API token banky">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="text-sm font-extrabold" style={{ color: TONE[token.tone] }}>{token.text}</div>
            <Sub tone={token.tone === 'ok' ? 'mute' : token.tone}>{token.sub}</Sub>
          </div>
          <Button small onClick={() => setEditToken(true)} className="shrink-0 max-lg:min-h-[36px]">Upravit</Button>
        </div>
        {payToken && <Sub tone={payToken.tone === 'ok' ? 'mute' : payToken.tone}>Token pro příkazy: {payToken.text.replace(/^P/, 'p')} ({payToken.sub})</Sub>}
        {s.token_auto_prolong === true && <Sub>Automatické prodlužování je zapnuté.</Sub>}
      </Tile>

      <Tile label="Ruční synchronizace">
        <Button green small onClick={doSync} disabled={busy || wait > 0} className="max-lg:min-h-[36px]">
          {busy ? 'Synchronizuji…' : wait > 0 ? `Synchronizovat teď (za ${wait} s)` : 'Synchronizovat teď'}
        </Button>
        {msg ? <div className="mt-1"><Sub tone={msg.tone}>{msg.text}</Sub></div>
          : <div className="mt-1"><Sub>Pohyby se stahují samy každou minutu. Banka dovoluje jeden dotaz za 30 s.</Sub></div>}
      </Tile>

      {editToken && (
        <BankTokenModal state={s} onClose={() => setEditToken(false)}
          onSaved={() => { setEditToken(false); notify('ok', 'Platnost tokenů uložena.'); onChanged() }} />
      )}
    </div>
  )
}
