import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import { Spinner, EmptyState } from './BranchHelpers'

// Zavírací období pobočky (od–do, inkluzivně). V termínu nelze rezervovat
// žádnou motorku pobočky — hlídá DB (branch_is_closed → kalendář, kontroly
// dostupnosti i trigger na bookings), tohle je jen jeho správa.

const INPUT_STYLE = {
  padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0',
  color: '#0f1a14', borderRadius: 8, fontSize: 14, outline: 'none',
}

export function fmtDate(d) {
  if (!d) return '—'
  const [y, m, day] = String(d).slice(0, 10).split('-')
  return `${Number(day)}. ${Number(m)}. ${y}`
}

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

export function TabClosures({ branch }) {
  const branchId = branch.id
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [conflictNote, setConflictNote] = useState(null)
  const [deleteRow, setDeleteRow] = useState(null)

  useEffect(() => { load() }, [branchId])

  async function load() {
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('branch_closures')
        .select('*')
        .eq('branch_id', branchId)
        .order('closed_from')
      if (error) throw error
      setRows(data || [])
    } catch (e) {
      setErr(`Načtení období selhalo: ${e.message}`)
      setRows([])
    }
    setLoading(false)
  }

  // Rezervace, které už v zavíraném termínu na této pobočce existují.
  // Období se kvůli nim NEblokuje — obsluha je musí vyřešit ručně (přesun/storno).
  async function countConflicts(f, t) {
    try {
      const { data, error } = await supabase
        .from('bookings')
        .select('id, motorcycles!inner(branch_id)')
        .eq('motorcycles.branch_id', branchId)
        .in('status', ['pending', 'reserved', 'active'])
        .lte('start_date', `${t}T23:59:59`)
        .gte('end_date', `${f}T00:00:00`)
      if (error) throw error
      return (data || []).length
    } catch {
      return null
    }
  }

  async function handleAdd() {
    setErr(null); setConflictNote(null)
    if (!from || !to) { setErr('Vyplňte datum od i do.'); return }
    if (to < from) { setErr('Datum „do“ nesmí být dříve než „od“.'); return }
    setSaving(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        branch_id: branchId,
        closed_from: from,
        closed_to: to,
        reason: reason.trim() || null,
        created_by: user?.id || null,
      }
      const result = await debugAction('branch_closures.create', 'BranchClosures', () =>
        supabase.from('branch_closures').insert(payload).select().single()
      , payload)
      if (result?.error) throw new Error(result.error.message)
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'branch_closure_created',
        details: { branch: branch.name, from, to, reason: payload.reason },
      })
      const conflicts = await countConflicts(from, to)
      if (conflicts > 0) {
        setConflictNote(`Pozor: v tomto termínu už je na pobočce ${conflicts} živých rezervací. Období je uložené, ale stávající rezervace se samy neruší — přesuňte je, nebo stornujte.`)
      }
      setFrom(''); setTo(''); setReason('')
      load()
    } catch (e) {
      setErr(`Uložení selhalo: ${e.message}`)
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(row) {
    setDeleteRow(null); setErr(null)
    try {
      const { error } = await supabase.from('branch_closures').delete().eq('id', row.id)
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'branch_closure_deleted',
        details: { branch: branch.name, from: row.closed_from, to: row.closed_to },
      })
      load()
    } catch (e) {
      setErr(`Smazání selhalo: ${e.message}`)
    }
  }

  const today = todayIso()

  return (
    <div>
      <div className="rounded-lg mb-3 text-sm" style={{ padding: '10px 12px', background: '#f1faf7', color: '#1a2e22' }}>
        <strong>Zavírací období</strong> = termín, kdy pobočka nefunguje (zimní sezona, rekonstrukce, dovolená).
        V těchto dnech <strong>nelze zarezervovat žádnou motorku této pobočky</strong> — dny jsou v kalendáři webu
        i appky obsazené a rezervaci odmítne i databáze. Termín je včetně obou krajních dnů.
      </div>

      {branch.is_open !== true && (
        <div className="rounded-lg mb-3 text-sm" style={{ padding: '10px 12px', background: '#fee2e2', color: '#dc2626' }}>
          Pobočka je přepínačem nastavená jako <strong>ZAVŘENÁ</strong> — motorky na ní nejdou rezervovat v <strong>žádném</strong> termínu,
          bez ohledu na období níže. Pro běžný provoz ji přepněte na „Otevřená“ (Pobočky → sloupec Provoz nebo Upravit).
        </div>
      )}

      {/* Nové období */}
      <div className="flex flex-wrap items-end gap-2 mb-3">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zavřeno od</label>
          <input type="date" value={from} onChange={e => setFrom(e.target.value)} style={INPUT_STYLE} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zavřeno do</label>
          <input type="date" value={to} min={from || undefined} onChange={e => setTo(e.target.value)} style={INPUT_STYLE} />
        </div>
        <div className="flex-1" style={{ minWidth: 180 }}>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod (nepovinné)</label>
          <input type="text" value={reason} placeholder="např. zimní sezona"
            onChange={e => setReason(e.target.value)} style={{ ...INPUT_STYLE, width: '100%' }} />
        </div>
        <button onClick={handleAdd} disabled={saving || !from || !to}
          className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
          style={{ padding: '8px 16px', background: '#1a2e22', color: '#74FB71', opacity: saving || !from || !to ? 0.5 : 1 }}>
          {saving ? 'Ukládám…' : 'Přidat období'}
        </button>
      </div>

      {err && <p className="mb-2 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      {conflictNote && <p className="mb-2 text-sm font-bold" style={{ color: '#b45309' }}>{conflictNote}</p>}

      {loading ? <Spinner /> : rows.length === 0 ? (
        <EmptyState text="Žádné zavírací období — pobočka je celoročně v provozu" />
      ) : (
        <div className="space-y-1">
          {rows.map((r, i) => {
            const past = r.closed_to < today
            const now = r.closed_from <= today && r.closed_to >= today
            return (
              <div key={r.id} className="flex items-center gap-2 text-sm"
                style={{ padding: '8px 10px', background: i % 2 === 0 ? '#f8fcfa' : '#fff', borderRadius: 8, opacity: past ? 0.55 : 1 }}>
                <span className="font-bold font-mono" style={{ color: '#0f1a14' }}>
                  {fmtDate(r.closed_from)} – {fmtDate(r.closed_to)}
                </span>
                <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                  style={{
                    padding: '2px 6px',
                    background: now ? '#fee2e2' : past ? '#f3f4f6' : '#fef3c7',
                    color: now ? '#dc2626' : past ? '#1a2e22' : '#b45309',
                  }}>
                  {now ? 'Zavřeno teď' : past ? 'Proběhlo' : 'Naplánováno'}
                </span>
                {r.reason && <span style={{ color: '#1a2e22' }}>{r.reason}</span>}
                <button onClick={() => setDeleteRow(r)}
                  className="ml-auto rounded-btn text-sm font-bold cursor-pointer border-none"
                  style={{ padding: '3px 10px', background: '#fee2e2', color: '#dc2626' }}>
                  Smazat
                </button>
              </div>
            )
          })}
        </div>
      )}

      {deleteRow && (
        <ConfirmDialog
          open danger title="Smazat zavírací období?"
          message={`${fmtDate(deleteRow.closed_from)} – ${fmtDate(deleteRow.closed_to)} — motorky pobočky půjde v tomto termínu zase rezervovat.`}
          onConfirm={() => handleDelete(deleteRow)}
          onCancel={() => setDeleteRow(null)}
        />
      )}
    </div>
  )
}

export default TabClosures
