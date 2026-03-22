/**
 * DataBoxTab — Datová schránka
 * Konfigurace DS ID + odeslání schválených výkazů z flexi_reports
 */
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
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

const RECIPIENT_LABELS = {
  vat_return: 'Finanční úřad',
  income_tax: 'Finanční úřad',
  balance_sheet: 'Finanční úřad',
  profit_loss: 'Finanční úřad',
  ossz: 'ČSSZ',
  vzp: 'VZP',
}

export default function DataBoxTab() {
  const [dsId, setDsId] = useState('')
  const [saving, setSaving] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const [reports, setReports] = useState([])
  const [submittedReports, setSubmittedReports] = useState([])
  const [loadingReports, setLoadingReports] = useState(true)
  const [sending, setSending] = useState(null)
  const [error, setError] = useState(null)
  const [confirmReport, setConfirmReport] = useState(null)
  const [result, setResult] = useState(null)

  useEffect(() => { load(); loadReports() }, [])

  async function load() {
    const { data } = await supabase.from('cms_variables').select('value').eq('key', 'datove_schranky_id').single()
    if (data) setDsId(data.value || '')
    setLoaded(true)
  }

  async function loadReports() {
    setLoadingReports(true)
    const [approved, submitted] = await Promise.all([
      supabase.from('flexi_reports').select('*').eq('status', 'approved').order('year', { ascending: false }),
      supabase.from('flexi_reports').select('*').eq('status', 'submitted').order('submitted_at', { ascending: false }).limit(20),
    ])
    setReports(approved.data || [])
    setSubmittedReports(submitted.data || [])
    setLoadingReports(false)
  }

  async function save() {
    setSaving(true)
    const { data: existing } = await supabase.from('cms_variables').select('id').eq('key', 'datove_schranky_id').single()
    if (existing) {
      await debugAction('dataBox.update', 'DataBoxTab', () =>
        supabase.from('cms_variables').update({ value: dsId }).eq('id', existing.id)
      , { key: 'datove_schranky_id', value: dsId })
    } else {
      await debugAction('dataBox.create', 'DataBoxTab', () =>
        supabase.from('cms_variables').insert({ key: 'datove_schranky_id', value: dsId, group: 'general' })
      , { key: 'datove_schranky_id', value: dsId })
    }
    setSaving(false)
  }

  async function handleSend(report) {
    setSending(report.id); setError(null); setResult(null)
    try {
      const { data, error: fnErr } = await supabase.functions.invoke('datova-schranka', {
        body: { report_id: report.id },
      })
      if (fnErr) throw fnErr
      if (data?.error) throw new Error(data.error)
      setResult(data)
      await loadReports()
    } catch (e) {
      setError('Odeslání selhalo: ' + e.message)
    }
    setSending(null); setConfirmReport(null)
  }

  const fmt = (d) => d ? new Date(d).toLocaleString('cs-CZ') : '—'

  return (
    <div>
      {/* DS configuration */}
      <Card className="mb-4">
        <div className="text-sm font-bold mb-3" style={{ color: '#0f1a14' }}>Nastavení datové schránky</div>
        {loaded && (
          <div className="flex items-end gap-3">
            <div className="flex-1">
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>ID datové schránky</label>
              <input value={dsId} onChange={e => setDsId(e.target.value)}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                placeholder="např. abc1234" />
            </div>
            <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
          </div>
        )}
      </Card>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {result && (
        <Card className="mb-4" style={{ background: '#dcfce7' }}>
          <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>
            {result.method === 'api' ? 'Odesláno přes ISDS' : 'Připraveno k ručnímu odeslání'}
          </div>
          <div className="text-sm mt-1" style={{ color: '#166534' }}>
            Příjemce: {result.recipient} | ID: {result.message_id}
          </div>
          {result.instructions && (
            <div className="text-sm mt-1" style={{ color: '#92400e' }}>{result.instructions}</div>
          )}
          <button onClick={() => setResult(null)} className="text-sm mt-2 underline cursor-pointer" style={{ color: '#166534', background: 'none', border: 'none' }}>Zavřít</button>
        </Card>
      )}

      {/* Approved reports ready to send */}
      <Card className="mb-4">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
          Schválené výkazy k odeslání
        </h3>
        {loadingReports ? (
          <div className="flex justify-center py-4">
            <div className="animate-spin rounded-full h-6 w-6 border-t-2" style={{ borderColor: '#74FB71' }} />
          </div>
        ) : reports.length === 0 ? (
          <p className="text-sm py-2" style={{ color: '#6b7280' }}>Žádné schválené výkazy. Schvalte je nejdřív v záložce Státní správa → Výkazy a přiznání.</p>
        ) : (
          <Table>
            <thead>
              <TRow header>
                <TH>Výkaz</TH>
                <TH>Období</TH>
                <TH>Příjemce</TH>
                <TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {reports.map(r => (
                <TRow key={r.id}>
                  <TD><span className="font-bold text-sm">{REPORT_LABELS[r.report_type] || r.report_type}</span></TD>
                  <TD>{r.quarter ? `Q${r.quarter} ${r.year}` : r.year}</TD>
                  <TD><span className="text-sm" style={{ color: '#6b7280' }}>{RECIPIENT_LABELS[r.report_type] || '—'}</span></TD>
                  <TD>
                    <button onClick={() => setConfirmReport(r)}
                      disabled={sending === r.id}
                      className="rounded-btn text-xs font-bold cursor-pointer"
                      style={{ padding: '4px 12px', background: '#2563eb', border: 'none', color: '#fff' }}>
                      {sending === r.id ? 'Odesílám...' : 'Odeslat datovkou'}
                    </button>
                  </TD>
                </TRow>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      {/* Submitted reports history */}
      {submittedReports.length > 0 && (
        <Card>
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
            Odeslané výkazy
          </h3>
          <Table>
            <thead>
              <TRow header>
                <TH>Výkaz</TH>
                <TH>Období</TH>
                <TH>Odesláno</TH>
                <TH>ID zprávy</TH>
              </TRow>
            </thead>
            <tbody>
              {submittedReports.map(r => (
                <TRow key={r.id}>
                  <TD><span className="font-bold text-sm">{REPORT_LABELS[r.report_type] || r.report_type}</span></TD>
                  <TD>{r.quarter ? `Q${r.quarter} ${r.year}` : r.year}</TD>
                  <TD><span className="text-sm" style={{ color: '#6b7280' }}>{fmt(r.submitted_at)}</span></TD>
                  <TD><span className="text-sm font-mono" style={{ color: '#6b7280' }}>{r.datova_schranka_message_id || '—'}</span></TD>
                </TRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}

      {/* Confirmation dialog */}
      {confirmReport && (
        <Modal open title="Odeslat datovou schránkou" onClose={() => setConfirmReport(null)}>
          <div className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            <p className="font-bold mb-2">Odeslat {REPORT_LABELS[confirmReport.report_type]} za {confirmReport.quarter ? `Q${confirmReport.quarter} ` : ''}{confirmReport.year}?</p>
            <p>Příjemce: <strong>{RECIPIENT_LABELS[confirmReport.report_type] || '—'}</strong></p>
            <p className="mt-2 p-2 rounded-lg" style={{ background: '#fef3c7', color: '#92400e' }}>
              Tato akce je nevratná. Výkaz bude odeslán přes datovou schránku.
            </p>
          </div>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setConfirmReport(null)}>Zrušit</Button>
            <Button green onClick={() => handleSend(confirmReport)} disabled={!!sending}>
              {sending ? 'Odesílám...' : 'Odeslat'}
            </Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
