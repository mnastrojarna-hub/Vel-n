/**
 * ReportsTab — Výkazy a přiznání z Abra Flexi
 * Pull z Flexi → flexi_reports → schválení → odeslání datovkou (ve Státní správě)
 */
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const REPORT_LABELS = {
  vat_return: 'Přiznání k DPH',
  income_tax: 'Daňové přiznání',
  balance_sheet: 'Rozvaha',
  profit_loss: 'Výsledovka',
  ossz: 'Přehled OSSZ',
  vzp: 'Přehled VZP',
  cash_flow: 'Výkaz cash flow',
  accounting_closing: 'Účetní uzávěrka',
}

const STATUS_CONFIG = {
  draft:     { label: 'Ke schválení', bg: '#f3f4f6', color: '#374151' },
  approved:  { label: 'Schváleno',    bg: '#dcfce7', color: '#1a8a18' },
  submitted: { label: 'Odesláno',     bg: '#dbeafe', color: '#2563eb' },
  rejected:  { label: 'Odmítnuto',    bg: '#fee2e2', color: '#dc2626' },
}

export default function ReportsTab() {
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(true)
  const [pulling, setPulling] = useState(false)
  const [error, setError] = useState(null)
  const [year, setYear] = useState(new Date().getFullYear())
  const [detail, setDetail] = useState(null)

  useEffect(() => { load() }, [year])

  async function load() {
    setLoading(true); setError(null)
    const { data, error: err } = await supabase
      .from('flexi_reports')
      .select('*')
      .eq('year', year)
      .order('report_type')
      .order('quarter', { ascending: true, nullsFirst: false })
    if (err) setError(err.message)
    setReports(data || [])
    setLoading(false)
  }

  async function handlePullAll() {
    setPulling(true); setError(null)
    try {
      const { data, error: fnErr } = await supabase.functions.invoke('flexi-sync', {
        body: { action: 'pullAll', year },
      })
      if (fnErr) throw fnErr
      if (data?.error) throw new Error(data.error)
      await load()
    } catch (e) {
      setError('Pull selhal: ' + e.message)
    }
    setPulling(false)
  }

  async function handleApprove(id) {
    const { error: err } = await supabase.from('flexi_reports').update({
      status: 'approved',
      approved_by: 'admin',
      approved_at: new Date().toISOString(),
    }).eq('id', id)
    if (err) { setError(err.message); return }
    await load()
  }

  async function handleExportXml(id) {
    try {
      const { data, error: fnErr } = await supabase.functions.invoke('flexi-sync', {
        body: { action: 'exportXml', id },
      })
      if (fnErr) throw fnErr
      const blob = new Blob([data.xml || ''], { type: 'application/xml' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${data.report_type}_${year}.xml`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) {
      setError('Export selhal: ' + e.message)
    }
  }

  const fmt = (d) => d ? new Date(d).toLocaleString('cs-CZ') : '—'

  return (
    <div>
      {/* Pull panel */}
      <Card className="mb-4">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <label className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rok:</label>
            <select value={year} onChange={e => setYear(Number(e.target.value))}
              className="rounded-btn text-sm font-bold outline-none"
              style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              {[2024, 2025, 2026, 2027].map(y => <option key={y} value={y}>{y}</option>)}
            </select>
          </div>
          <Button green onClick={handlePullAll} disabled={pulling}>
            {pulling ? 'Stahuji...' : 'Stáhnout vše z Flexi'}
          </Button>
        </div>
      </Card>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Reports table */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          Výkazy a přiznání — {year}
        </h3>
        {loading ? (
          <div className="flex justify-center py-8">
            <div className="animate-spin rounded-full h-6 w-6 border-t-2" style={{ borderColor: '#74FB71' }} />
          </div>
        ) : reports.length === 0 ? (
          <p className="text-sm py-4" style={{ color: '#6b7280' }}>
            Žádné výkazy. Klikněte "Stáhnout vše z Flexi" pro import.
          </p>
        ) : (
          <Table>
            <thead>
              <TRow header>
                <TH>Typ</TH>
                <TH>Období</TH>
                <TH>Stav</TH>
                <TH>Staženo</TH>
                <TH>Schváleno</TH>
                <TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {reports.map(r => {
                const sc = STATUS_CONFIG[r.status] || STATUS_CONFIG.draft
                return (
                  <TRow key={r.id}>
                    <TD><span className="font-bold text-sm">{REPORT_LABELS[r.report_type] || r.report_type}</span></TD>
                    <TD>{r.quarter ? `Q${r.quarter} ${r.year}` : r.year}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-xs font-extrabold uppercase tracking-wide"
                        style={{ padding: '3px 10px', background: sc.bg, color: sc.color }}>
                        {sc.label}
                      </span>
                    </TD>
                    <TD><span className="text-sm" style={{ color: '#6b7280' }}>{fmt(r.created_at)}</span></TD>
                    <TD><span className="text-sm" style={{ color: '#6b7280' }}>{fmt(r.approved_at)}</span></TD>
                    <TD>
                      <div className="flex gap-1 flex-wrap">
                        <button onClick={() => setDetail(r)}
                          className="rounded-btn text-xs font-bold cursor-pointer"
                          style={{ padding: '4px 10px', background: '#f1faf7', border: 'none', color: '#1a2e22' }}>
                          Zobrazit
                        </button>
                        {r.status === 'draft' && (
                          <button onClick={() => handleApprove(r.id)}
                            className="rounded-btn text-xs font-bold cursor-pointer"
                            style={{ padding: '4px 10px', background: '#dcfce7', border: 'none', color: '#1a8a18' }}>
                            Schválit
                          </button>
                        )}
                        <button onClick={() => handleExportXml(r.id)}
                          className="rounded-btn text-xs font-bold cursor-pointer"
                          style={{ padding: '4px 10px', background: '#e0e7ff', border: 'none', color: '#4338ca' }}>
                          XML
                        </button>
                      </div>
                    </TD>
                  </TRow>
                )
              })}
            </tbody>
          </Table>
        )}
      </Card>

      {/* Detail modal */}
      {detail && (
        <Modal open title={`${REPORT_LABELS[detail.report_type] || detail.report_type} — ${detail.quarter ? 'Q' + detail.quarter + ' ' : ''}${detail.year}`} onClose={() => setDetail(null)}>
          <div className="mb-3">
            <span className="inline-block rounded-btn text-xs font-extrabold uppercase tracking-wide"
              style={{ padding: '3px 10px', background: STATUS_CONFIG[detail.status]?.bg, color: STATUS_CONFIG[detail.status]?.color }}>
              {STATUS_CONFIG[detail.status]?.label}
            </span>
            {detail.datova_schranka_message_id && (
              <span className="ml-2 text-sm" style={{ color: '#6b7280' }}>
                DS ID: {detail.datova_schranka_message_id}
              </span>
            )}
          </div>
          {detail.rendered_html ? (
            <div dangerouslySetInnerHTML={{ __html: detail.rendered_html }} className="max-h-96 overflow-auto text-sm" />
          ) : (
            <pre className="p-3 rounded-lg max-h-96 overflow-auto text-xs"
              style={{ background: '#f1faf7', color: '#1a2e22', fontFamily: 'monospace', whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>
              {JSON.stringify(detail.raw_data, null, 2)}
            </pre>
          )}
          <div className="flex justify-end gap-2 mt-4">
            {detail.status === 'draft' && (
              <Button green onClick={() => { handleApprove(detail.id); setDetail(null) }}>Schválit</Button>
            )}
            <Button onClick={() => setDetail(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
