import { useState } from 'react'
import { Btn, Chip, txt, num } from './BranchRpiUi'
import { NetworkDetail, obj } from './BranchRpiDiagNetwork'

// ─── Protokol kompletní diagnostiky pobočky (Raspberry) ─────────────────────
// Report (`kiosk_diagnostics.report`) obsahuje `protocol` = seznam sekcí s položkami (kontrakt §3):
//   section {key, title, status: ok|warn|fail|skip, items:[{id, label, status, value, message, hint}]}
// Zde: hlavička, „Kde je problém“ (fail), „Varování“ (warn), sekce s tabulkou (ok položky sbalené),
// sbalený „Technický detail sítě“ (BranchRpiDiagNetwork) a export do .txt / schránky.
// Vše defenzivně — protokol je JSON ze zařízení, tvar se nesmí předpokládat.

// @export-begin — čistá část bez Reactu (protokol → text); testuje se samostatně v Node
const S = v => (v == null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const L = v => (Array.isArray(v) ? v : [])
const O = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
const STATUSES = ['ok', 'warn', 'fail', 'skip']
const STATUS_CZ = { ok: 'OK', warn: 'Varování', fail: 'Chyba', skip: 'Přeskočeno' }
const STATUS_SYM = { ok: '✔', warn: '⚠', fail: '✖', skip: '–' }
const MODE_CZ = { full: 'kompletní', network: 'jen síť' }
// Hodnota položky: jednotka posílá i syrové booleany → česky
const valOf = v => (v === true ? 'ano' : v === false ? 'ne' : S(v))
const stOf = v => { const s = S(v).toLowerCase(); return STATUSES.includes(s) ? s : 'skip' }
const worst = items => (items.some(i => i.status === 'fail') ? 'fail' : items.some(i => i.status === 'warn') ? 'warn' : items.some(i => i.status === 'ok') ? 'ok' : 'skip')

// Sekce protokolu v pevném tvaru; status sekce = nejhorší z položek (skip neovlivňuje; bez položek = skip)
function normalizeProtocol(r) {
  return L(O(r).protocol).map((sv, si) => {
    const sec = O(sv)
    const items = L(sec.items).map((iv, ii) => {
      const it = O(iv)
      // group = souhrn zóny (jedna položka na zónu) — jednotka ji do summary.checks/problems NEpočítá, Velín také ne
      return { id: S(it.id) || `${S(sec.key) || si}.${ii}`, label: S(it.label) || S(it.id) || `Kontrola ${ii + 1}`, status: stOf(it.status),
        value: valOf(it.value), message: S(it.message), hint: S(it.hint), group: it.group === true }
    })
    return { key: S(sec.key) || String(si), title: S(sec.title) || S(sec.key) || `Sekce ${si + 1}`, status: STATUSES.includes(S(sec.status)) ? S(sec.status) : worst(items), items }
  })
}

function countChecks(sections) {
  const c = { total: 0, ok: 0, warn: 0, fail: 0, skip: 0 }
  sections.forEach(s => s.items.forEach(i => { if (i.group) return; c.total += 1; c[i.status] += 1 }))
  return c
}

// Položky daného stavu napříč sekcemi (pro „Kde je problém“ / „Varování“); souhrny zón (group) se nevypisují — každý nález má vlastní položku
const itemsOf = (sections, status) => sections.flatMap(s => s.items.filter(i => i.status === status && !i.group).map(i => ({ ...i, section: s.title })))

// Hlavička protokolu: report `r` (branch_name / config.branch_name, version, mode, duration_s, ts) + řádek tabulky `row` + název jednotky
function protocolMeta(r, row, deviceName, sections) {
  const rep = O(r), rw = O(row), cfg = O(rep.config)
  const ts = rw.created_at || rep.ts || null
  const d = ts ? new Date(ts) : null
  const dur = rep.duration_s != null ? Number(rep.duration_s) : (rw.started_at && rw.finished_at ? (new Date(rw.finished_at) - new Date(rw.started_at)) / 1000 : NaN)
  return {
    // branch_name: config je jen ve full běhu (a může selhat) → vždy je i na kořeni reportu, příp. v kroku supabase
    branch: S(cfg.branch_name) || S(rep.branch_name) || S(O(rep.supabase).branch_name) || '—', device: S(deviceName) || 'Raspberry', version: S(rep.version) || S(rw.app_version) || '—',
    date: d && Number.isFinite(d.getTime()) ? d.toLocaleString('cs-CZ') : '—', dateObj: d && Number.isFinite(d.getTime()) ? d : new Date(),
    durationS: Number.isFinite(dur) ? Math.round(dur) : null, mode: MODE_CZ[S(rep.mode)] || S(rep.mode) || 'kompletní',
    checks: countChecks(sections), fails: itemsOf(sections, 'fail'), warns: itemsOf(sections, 'warn'),
  }
}

// Textový protokol (formát dle kontraktu §5) — čistá funkce
function protocolToText(sections, meta) {
  const m = O(meta), c = O(m.checks)
  const out = ['MOTOGO24 — PROTOKOL DIAGNOSTIKY POBOČKY',
    `Pobočka: ${m.branch} | Jednotka: ${m.device} | Verze: ${m.version} | Datum: ${m.date} | Trvání: ${m.durationS == null ? '—' : `${m.durationS} s`} | Režim: ${m.mode}`,
    `VÝSLEDEK: ${L(m.fails).length} problémů, ${L(m.warns).length} varování (kontrol celkem ${c.total ?? 0}: ${c.ok ?? 0} ok / ${c.warn ?? 0} warn / ${c.fail ?? 0} fail / ${c.skip ?? 0} skip)`]
  const listBlock = (title, items) => {
    out.push('', title)
    if (!items.length) { out.push(' (žádné)'); return }
    items.forEach((i, n) => {
      out.push(` ${n + 1}. ${i.label}: ${i.message || i.value || STATUS_CZ[i.status]}${i.section ? `  [${i.section}]` : ''}`)
      if (i.hint) out.push(`    → Co s tím: ${i.hint}`)
    })
  }
  listBlock('KDE JE PROBLÉM', L(m.fails))
  listBlock('VAROVÁNÍ', L(m.warns))
  L(sections).forEach(sec => {
    out.push('', `[SEKCE] ${sec.title} — ${STATUS_CZ[sec.status] || sec.status}`)
    if (!sec.items.length) out.push(' (bez kontrol)')
    sec.items.forEach(i => {
      const detail = i.status === 'ok' ? (i.value || i.message) : [i.value, i.message].filter(Boolean).join(' — ')
      out.push(` ${STATUS_SYM[i.status]} ${i.label}${detail ? `: ${detail}` : ''}`)
      if (i.hint && i.status !== 'ok') out.push(`    → Co s tím: ${i.hint}`)
    })
  })
  return out.join('\n') + '\n'
}

// Název souboru `diagnostika-<pobocka>-<YYYYMMDD-HHMM>.txt` (bez diakritiky a mezer)
function exportFilename(branch, d) {
  const slug = S(branch).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'pobocka'
  const p = n => String(n).padStart(2, '0')
  return `diagnostika-${slug}-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}.txt`
}
// @export-end

const TONE = { ok: 'green', warn: 'amber', fail: 'red', skip: 'gray' }
const StatusChip = ({ status }) => <Chip tone={TONE[status] || 'gray'}>{STATUS_CZ[status] || txt(status)}</Chip>

function downloadText(name, text) {
  const blob = new Blob([text], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

async function copyText(text) {
  try { if (navigator.clipboard?.writeText) { await navigator.clipboard.writeText(text); return true } } catch { /* fallback níže */ }
  try {
    const ta = document.createElement('textarea')
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0'
    document.body.appendChild(ta); ta.select()
    const ok = document.execCommand('copy'); ta.remove(); return ok
  } catch { return false }
}

// Seznam položek fail/warn: kontrola — zjištění — co s tím
function FindingList({ title, items, color }) {
  if (!items.length) return null
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: `1px solid ${color}` }}>
      <div className="text-[11px] font-extrabold uppercase" style={{ color }}>{title} ({items.length})</div>
      <ol className="text-[12px] mt-1 ml-4" style={{ color: '#1a2e22', listStyle: 'decimal' }}>
        {items.map(i => (
          <li key={i.id} className="mb-1">
            <span className="font-bold">{i.label}</span>{i.message || i.value ? ` — ${i.message || i.value}` : ''}
            <span className="text-[11px]" style={{ color: '#6b8c7a' }}> [{i.section}]</span>
            {i.hint && <div style={{ color: '#2563eb' }}>→ Co s tím: {i.hint}</div>}
          </li>
        ))}
      </ol>
    </div>
  )
}

function ProtocolSection({ sec }) {
  const [showOk, setShowOk] = useState(false)
  const oks = sec.items.filter(i => i.status === 'ok'), rest = sec.items.filter(i => i.status !== 'ok')
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: `1px solid ${sec.status === 'fail' ? '#fca5a5' : sec.status === 'warn' ? '#fcd34d' : '#d4e8e0'}` }}>
      <div className="flex items-center gap-2 flex-wrap">
        <StatusChip status={sec.status} />
        <span className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>{sec.title}</span>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>{sec.items.length} kontrol</span>
      </div>
      {rest.length > 0 && (
        <div className="overflow-x-auto mt-1">
          <table className="text-[12px]" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
            <thead><tr>{['Stav', 'Kontrola', 'Zjištění', 'Co s tím'].map(h => <th key={h} className="text-left font-extrabold uppercase" style={{ padding: '2px 8px', color: '#6b8c7a', fontSize: 10, borderBottom: '1px solid #d4e8e0' }}>{h}</th>)}</tr></thead>
            <tbody>{rest.map(i => (
              <tr key={i.id} style={{ opacity: i.status === 'skip' ? 0.6 : 1 }}>
                <td style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', verticalAlign: 'top' }}><StatusChip status={i.status} /></td>
                <td className="font-bold" style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#1a2e22', verticalAlign: 'top' }}>{i.label}</td>
                <td style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#1a2e22', verticalAlign: 'top' }}>{[i.value, i.message].filter(Boolean).join(' — ') || '—'}</td>
                <td style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#2563eb', verticalAlign: 'top' }}>{i.hint || '—'}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {oks.length > 0 && (
        <div className="mt-1">
          <Btn tone="gray" small onClick={() => setShowOk(x => !x)}>{showOk ? 'Skrýt' : 'Zobrazit'} {oks.length} kontrol OK</Btn>
          {showOk && <ul className="text-[12px] mt-1 ml-4" style={{ color: '#1a2e22', listStyle: 'disc' }}>{oks.map(i => <li key={i.id}>✔ {i.label}{i.value || i.message ? `: ${i.value || i.message}` : ''}</li>)}</ul>}
        </div>
      )}
    </div>
  )
}

// `r` = načtený report, `row` = řádek kiosk_diagnostics, `deviceName` = název jednotky
function ProtocolView({ r, row, deviceName }) {
  const [net, setNet] = useState(false)
  const [copied, setCopied] = useState(null)
  const sections = normalizeProtocol(r)
  const m = protocolMeta(r, row, deviceName, sections)
  const c = m.checks
  const text = () => protocolToText(sections, m)
  async function copy() { const ok = await copyText(text()); setCopied(ok ? 'Zkopírováno do schránky' : 'Kopírování se nezdařilo'); setTimeout(() => setCopied(null), 2500) }
  const verdict = m.fails.length === 0 && m.warns.length === 0 ? 'Pobočka je v pořádku' : `${m.fails.length} problémů, ${m.warns.length} varování`
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: m.fails.length ? '#fff7f7' : '#f8fcfa', border: `1px solid ${m.fails.length ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="flex items-center gap-2 flex-wrap text-[12px]" style={{ color: '#1a2e22' }}>
        <Chip tone={m.fails.length ? 'red' : m.warns.length ? 'amber' : 'green'}>{verdict}</Chip>
        <span>Pobočka <b>{m.branch}</b> · jednotka <b>{m.device}</b> · verze {m.version} · {m.date} · trvání {m.durationS == null ? '—' : `${m.durationS} s`} · režim {m.mode}</span>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>kontrol {num(c.total) ?? 0}: {num(c.ok) ?? 0} OK / {num(c.warn) ?? 0} varování / {num(c.fail) ?? 0} chyb / {num(c.skip) ?? 0} přeskočeno</span>
        <span className="ml-auto flex items-center gap-1 flex-wrap">
          <Btn tone="blue" small onClick={() => downloadText(exportFilename(m.branch, m.dateObj), text())} title="Uloží protokol jako textový soubor">⬇ Stáhnout protokol (.txt)</Btn>
          <Btn tone="gray" small onClick={copy} title="Zkopíruje textový protokol do schránky">Kopírovat</Btn>
          {copied && <span className="text-[11px] font-bold" style={{ color: '#1a8a18' }}>{copied}</span>}
        </span>
      </div>
      <FindingList title="Kde je problém" items={m.fails} color="#dc2626" />
      <FindingList title="Varování" items={m.warns} color="#b45309" />
      {sections.length === 0 && <div className="text-[12px] mt-2" style={{ color: '#b45309' }}>Protokol neobsahuje žádné sekce (neúplný report).</div>}
      {sections.map(sec => <ProtocolSection key={sec.key} sec={sec} />)}
      <div className="mt-2 flex items-center gap-2">
        <Btn tone="gray" small onClick={() => setNet(x => !x)}>{net ? 'Skrýt technický detail sítě' : 'Technický detail sítě'}</Btn>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>syrové tabulky: rozhraní, LTE, internet, moduly, scan LAN, ARP, kroky, celý JSON</span>
      </div>
      {net && <NetworkDetail r={obj(r)} />}
    </div>
  )
}

export { ProtocolView, protocolToText, normalizeProtocol, protocolMeta, exportFilename }
