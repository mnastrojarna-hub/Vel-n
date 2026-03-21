import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function ExceptionsTab() {
  const [exceptions, setExceptions] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showResolved, setShowResolved] = useState(false)

  // Resolve modal
  const [resolveExc, setResolveExc] = useState(null)
  // Inline edit
  const [editingId, setEditingId] = useState(null)
  const [editForm, setEditForm] = useState({})

  useEffect(() => { load() }, [page, showResolved])

  async function load() {
    setLoading(true); setError(null)
    try {
      let query = supabase.from('accounting_exceptions')
        .select('*, financial_events(*)', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      if (!showResolved) {
        query = query.is('resolved_at', null)
      }

      const { data, count, error: err } = await query
      if (err) throw err
      setExceptions(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleResolve(excId, note) {
    try {
      const { error: err } = await supabase.from('accounting_exceptions')
        .update({
          resolved_at: new Date().toISOString(),
          resolution_note: note,
        }).eq('id', excId)
      if (err) throw err

      // Also update financial_event status to enriched (ready for re-processing)
      const exc = exceptions.find(e => e.id === excId)
      if (exc?.financial_event_id) {
        await supabase.from('financial_events')
          .update({ status: 'enriched' })
          .eq('id', exc.financial_event_id)
      }

      setResultMsg('Výjimka vyřešena')
      setResolveExc(null)
      await load()
    } catch (e) { setError(e.message) }
  }

  async function handleSaveEdit(excId) {
    const exc = exceptions.find(e => e.id === excId)
    if (!exc?.financial_event_id) return
    try {
      const updates = {}
      if (editForm.amount_czk !== undefined) updates.amount_czk = Number(editForm.amount_czk)
      if (editForm.duzp) updates.duzp = editForm.duzp

      // Update metadata fields
      if (editForm.supplier_name !== undefined) {
        const { data: current } = await supabase.from('financial_events')
          .select('metadata').eq('id', exc.financial_event_id).single()
        updates.metadata = { ...(current?.metadata || {}), supplier_name: editForm.supplier_name }
      }

      const { error: err } = await supabase.from('financial_events')
        .update(updates).eq('id', exc.financial_event_id)
      if (err) throw err

      setResultMsg('Událost aktualizována')
      setEditingId(null)
      setEditForm({})
      await load()
    } catch (e) { setError(e.message) }
  }

  function startEdit(exc) {
    const fe = exc.financial_events
    if (!fe) return
    setEditingId(exc.id)
    setEditForm({
      amount_czk: fe.amount_czk || '',
      duzp: fe.duzp || '',
      supplier_name: fe.metadata?.supplier_name || '',
    })
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Toggle resolved */}
      <div className="flex items-center gap-3 mb-4">
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={showResolved} onChange={e => { setPage(1); setShowResolved(e.target.checked) }}
            className="cursor-pointer" style={{ accentColor: '#1a8a18' }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Zobrazit vyřešené</span>
        </label>
        <span className="text-sm" style={{ color: '#6b7280' }}>
          {total} {showResolved ? 'celkem' : 'nevyřešených'}
        </span>
      </div>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH><TH>Důvod</TH><TH>Částka</TH><TH>Confidence</TH>
                <TH>Zdroj</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {exceptions.map(exc => {
                const fe = exc.financial_events
                const isResolved = !!exc.resolved_at
                const confidence = fe?.confidence_score ?? null
                const isEditing = editingId === exc.id

                return (
                  <>
                    <TRow key={exc.id}>
                      <TD>{exc.created_at ? new Date(exc.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD>
                        <span className="text-sm font-bold" style={{ color: '#dc2626' }}>{exc.reason || '—'}</span>
                        {exc.resolution_note && (
                          <div className="text-sm mt-0.5" style={{ color: '#059669' }}>Řešení: {exc.resolution_note}</div>
                        )}
                      </TD>
                      <TD bold>{fe ? fmt(fe.amount_czk) : '—'}</TD>
                      <TD>
                        {confidence !== null ? (
                          <ConfidenceBar score={confidence} />
                        ) : <span className="text-sm" style={{ color: '#d4d4d8' }}>—</span>}
                      </TD>
                      <TD>
                        <span className="text-sm font-bold" style={{ color: '#6b7280' }}>
                          {fe ? (fe.source === 'stripe' ? 'Stripe' : fe.source === 'ocr' ? 'OCR' : fe.source === 'manual' ? 'Ručně' : fe.source) : '—'}
                        </span>
                      </TD>
                      <TD>
                        {isResolved ? (
                          <Badge label="Vyřešeno" color="#059669" bg="#d1fae5" />
                        ) : (
                          <Badge label="Čeká" color="#dc2626" bg="#fee2e2" />
                        )}
                      </TD>
                      <TD>
                        {!isResolved && (
                          <div className="flex gap-1 flex-wrap">
                            <button onClick={() => setResolveExc(exc)}
                              className="text-sm font-bold cursor-pointer"
                              style={{ color: '#1a8a18', background: 'none', border: 'none', padding: '4px 6px' }}>
                              Vyřešit
                            </button>
                            <button onClick={() => isEditing ? setEditingId(null) : startEdit(exc)}
                              className="text-sm font-bold cursor-pointer"
                              style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px' }}>
                              {isEditing ? 'Zrušit' : 'Upravit'}
                            </button>
                          </div>
                        )}
                      </TD>
                    </TRow>
                    {/* Inline edit row */}
                    {isEditing && (
                      <tr key={exc.id + '-edit'} style={{ background: '#f0f9ff', borderBottom: '1px solid #d4e8e0' }}>
                        <td colSpan={7} style={{ padding: '12px 16px' }}>
                          <div className="flex flex-wrap items-end gap-4">
                            <div>
                              <MiniLabel>Částka (Kč)</MiniLabel>
                              <input type="number" value={editForm.amount_czk}
                                onChange={e => setEditForm(f => ({ ...f, amount_czk: e.target.value }))}
                                className="rounded-btn text-sm outline-none" style={inputStyle} />
                            </div>
                            <div>
                              <MiniLabel>DUZP</MiniLabel>
                              <input type="date" value={editForm.duzp}
                                onChange={e => setEditForm(f => ({ ...f, duzp: e.target.value }))}
                                className="rounded-btn text-sm outline-none" style={inputStyle} />
                            </div>
                            <div>
                              <MiniLabel>Dodavatel</MiniLabel>
                              <input type="text" value={editForm.supplier_name}
                                onChange={e => setEditForm(f => ({ ...f, supplier_name: e.target.value }))}
                                className="rounded-btn text-sm outline-none" style={inputStyle} placeholder="Název dodavatele" />
                            </div>
                            <Button green onClick={() => handleSaveEdit(exc.id)}>Uložit</Button>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
              {exceptions.length === 0 && <TRow><TD>{showResolved ? 'Žádné výjimky' : 'Žádné nevyřešené výjimky'}</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Resolve modal */}
      {resolveExc && <ResolveModal exc={resolveExc} onClose={() => setResolveExc(null)} onResolve={handleResolve} />}
    </div>
  )
}

function ResolveModal({ exc, onClose, onResolve }) {
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)
  const fe = exc.financial_events
  const ai = fe?.metadata?.ai_classification

  async function handleSubmit() {
    setSaving(true)
    await onResolve(exc.id, note)
    setSaving(false)
  }

  return (
    <Modal open title="Vyřešit výjimku" onClose={onClose}>
      {/* Invoice detail */}
      {fe && (
        <div className="mb-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Detail faktury</div>
          <div className="grid grid-cols-2 gap-2">
            <DetailItem label="Dodavatel" value={fe.metadata?.supplier_name || '—'} />
            <DetailItem label="Částka" value={`${(fe.amount_czk || 0).toLocaleString('cs-CZ')} Kč`} />
            <DetailItem label="Číslo faktury" value={fe.metadata?.invoice_number || '—'} />
            <DetailItem label="DUZP" value={fe.duzp ? new Date(fe.duzp).toLocaleDateString('cs-CZ') : '—'} />
            <DetailItem label="Confidence" value={fe.confidence_score != null ? `${(fe.confidence_score * 100).toFixed(0)}%` : '—'} />
            <DetailItem label="Zdroj" value={fe.source || '—'} />
          </div>
        </div>
      )}

      {/* AI classification suggestion */}
      {ai && (
        <div className="mb-4 p-3 rounded-lg" style={{ background: '#faf5ff', border: '1px solid #d8b4fe' }}>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI návrh klasifikace</div>
          <div className="grid grid-cols-2 gap-2">
            <DetailItem label="Kategorie" value={ai.category || '—'} />
            <DetailItem label="Účet" value={ai.suggested_account || '—'} />
            <DetailItem label="Opakující se" value={ai.is_recurring ? 'Ano' : 'Ne'} />
            <div className="col-span-2"><DetailItem label="Poznámka" value={ai.classification_note || '—'} /></div>
          </div>
        </div>
      )}

      {/* Reason */}
      <div className="mb-4 p-3 rounded-lg" style={{ background: '#fee2e2', border: '1px solid #fca5a5' }}>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#dc2626' }}>Důvod výjimky</div>
        <div className="text-sm font-bold" style={{ color: '#dc2626' }}>{exc.reason}</div>
      </div>

      {/* Resolution note */}
      <div className="mb-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Poznámka k řešení</label>
        <textarea value={note} onChange={e => setNote(e.target.value)}
          className="w-full rounded-btn text-sm outline-none" placeholder="Jak bylo vyřešeno…"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 80, resize: 'vertical' }} />
      </div>

      <div className="flex justify-end gap-3">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSubmit} disabled={saving}>{saving ? 'Ukládám…' : 'Vyřešit'}</Button>
      </div>
    </Modal>
  )
}

function ConfidenceBar({ score }) {
  const pct = Math.round(score * 100)
  const color = pct >= 85 ? '#1a8a18' : pct >= 70 ? '#b45309' : '#dc2626'
  const bg = pct >= 85 ? '#dcfce7' : pct >= 70 ? '#fef3c7' : '#fee2e2'

  return (
    <div className="flex items-center gap-2">
      <div className="w-16 h-2 rounded-full overflow-hidden" style={{ background: '#e5e7eb' }}>
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
      <span className="text-sm font-bold" style={{ color }}>{pct}%</span>
    </div>
  )
}

function DetailItem({ label, value }) {
  return (
    <div>
      <span className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>{label}: </span>
      <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{value}</span>
    </div>
  )
}

function MiniLabel({ children }) {
  return <label className="block text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{children}</label>
}

const inputStyle = { padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', minWidth: 140 }
