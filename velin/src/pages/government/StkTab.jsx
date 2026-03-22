import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

export default function StkTab() {
  const [motos, setMotos] = useState([])
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState(null) // moto id being edited
  const [editVal, setEditVal] = useState('')
  const [saving, setSaving] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('StkTab', 'load')
      const { data, error } = await debugAction('motorcycles.stk', 'StkTab', () =>
        supabase
          .from('motorcycles')
          .select('id, model, spz, stk_valid_until, license_required')
          .neq('license_required', 'N')
          .order('stk_valid_until')
      )
      if (error) throw error
      setMotos(data || [])
    } catch (e) {
      debugError('StkTab', 'load', e)
    }
    setLoading(false)
  }

  function daysUntil(dateStr) {
    if (!dateStr) return null
    const diff = Math.ceil((new Date(dateStr) - new Date()) / (1000 * 60 * 60 * 24))
    return diff
  }

  function daysColor(days) {
    if (days === null) return '#1a2e22'
    if (days < 0) return '#dc2626'
    if (days < 30) return '#dc2626'
    if (days < 90) return '#b45309'
    return '#1a8a18'
  }

  function startEdit(moto) {
    setEditing(moto.id)
    setEditVal(moto.stk_valid_until || '')
  }

  async function saveStk(motoId) {
    setSaving(motoId)
    try {
      const { error } = await supabase.from('motorcycles')
        .update({ stk_valid_until: editVal || null })
        .eq('id', motoId)
      if (error) throw error
      setMotos(prev => prev.map(m => m.id === motoId ? { ...m, stk_valid_until: editVal || null } : m))
      setEditing(null)
      // Audit log
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'stk_updated',
          details: { moto_id: motoId, stk_valid_until: editVal || null },
        })
      } catch {}
    } catch (e) {
      debugError('StkTab', 'saveStk', e)
    }
    setSaving(null)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <Table>
      <thead>
        <TRow header>
          <TH>Motorka</TH><TH>SPZ</TH><TH>STK do</TH><TH>Dní do STK</TH><TH></TH>
        </TRow>
      </thead>
      <tbody>
        {motos.map(m => {
          const stkDays = daysUntil(m.stk_valid_until)
          const isEditing = editing === m.id
          return (
            <TRow key={m.id}>
              <TD bold>{m.model}</TD>
              <TD mono>{m.spz}</TD>
              <TD>
                {isEditing ? (
                  <input type="date" value={editVal} onChange={e => setEditVal(e.target.value)}
                    className="rounded-btn text-sm outline-none"
                    style={{ padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0', width: 150 }} />
                ) : (
                  m.stk_valid_until ? new Date(m.stk_valid_until).toLocaleDateString('cs-CZ') : '—'
                )}
              </TD>
              <TD>
                <span style={{ color: daysColor(stkDays), fontWeight: 700 }}>
                  {stkDays !== null ? (stkDays < 0 ? `${Math.abs(stkDays)} dní po` : `${stkDays} dní`) : '—'}
                </span>
              </TD>
              <TD>
                {isEditing ? (
                  <div className="flex items-center gap-1">
                    <button onClick={() => saveStk(m.id)} disabled={saving === m.id}
                      className="text-xs font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>
                      {saving === m.id ? '…' : '✓ Uložit'}
                    </button>
                    <button onClick={() => setEditing(null)}
                      className="text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>✕</button>
                  </div>
                ) : (
                  <button onClick={() => startEdit(m)}
                    className="text-xs font-bold cursor-pointer"
                    style={{ color: '#2563eb', background: 'none', border: 'none' }}>
                    Upravit
                  </button>
                )}
              </TD>
            </TRow>
          )
        })}
        {motos.length === 0 && <TRow><TD colSpan={5}>Žádné motorky</TD></TRow>}
      </tbody>
    </Table>
  )
}
