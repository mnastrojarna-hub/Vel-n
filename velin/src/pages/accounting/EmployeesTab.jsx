/**
 * Pipeline Dashboard — overview of all financial events flowing through the system
 * Shows: event counts by status, recent events, processing stats
 */
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { processAllPending, exportAllClassified, getPipelineStats, getRecentEvents } from '../../lib/financialEvents'
import { isFlexiConfigured } from '../../lib/abraFlexi'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const STATUS_LABELS = {
  ingested: 'Prijato', enriched: 'Obohaceno', validated: 'Validovano',
  classified: 'Klasifikovano', exported: 'Exportovano', synced: 'Synchronizovano',
  exception: 'Vyjimka', approved: 'Schvaleno', rejected: 'Zamitnuto', final: 'Finalni',
}
const STATUS_COLORS = {
  ingested: '#6b7280', enriched: '#2563eb', validated: '#0891b2',
  classified: '#7c3aed', exported: '#b45309', synced: '#1a8a18',
  exception: '#dc2626', approved: '#059669', rejected: '#dc2626', final: '#1a2e22',
}
const STATUS_BGS = {
  ingested: '#f3f4f6', enriched: '#dbeafe', validated: '#cffafe',
  classified: '#ede9fe', exported: '#fef3c7', synced: '#dcfce7',
  exception: '#fee2e2', approved: '#d1fae5', rejected: '#fee2e2', final: '#f1faf7',
}

const TYPE_LABELS = {
  revenue: 'Prijem', expense: 'Vydaj', asset: 'Majetek',
  payroll: 'Mzdy', liability: 'Zavazek', bank_transfer: 'Banka',
}
const SOURCE_LABELS = {
  stripe: 'Stripe', ocr: 'OCR', system: 'System', manual: 'Rucne', bank: 'Banka', fleet: 'Flotila',
}

export default function PipelineDashboard() {
  const [stats, setStats] = useState(null)
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [processing, setProcessing] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null)
  const [flexiOk, setFlexiOk] = useState(false)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [statusFilter, setStatusFilter] = useState('')

  useEffect(() => { load() }, [page, statusFilter])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const [s, flexiStatus] = await Promise.all([
        getPipelineStats(),
        isFlexiConfigured(),
      ])
      setStats(s)
      setFlexiOk(flexiStatus)

      let query = supabase.from('financial_events')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      if (statusFilter) query = query.eq('pipeline_status', statusFilter)
      const { data, count } = await query
      setEvents(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    finally { setLoading(false) }
  }

  async function handleProcess() {
    setProcessing(true); setResult(null); setError(null)
    try {
      const r = await processAllPending()
      setResult(`Zpracovano ${r.processed} udalosti: ${r.synced} synchronizovano, ${r.exceptions} vyjimek`)
      await load()
    } catch (e) { setError(e.message) }
    finally { setProcessing(false) }
  }

  async function handleExport() {
    setExporting(true); setResult(null); setError(null)
    try {
      const r = await exportAllClassified()
      setResult(`Exportovano ${r.exported} do Flexi, ${r.errors} chyb`)
      await load()
    } catch (e) { setError(e.message) }
    finally { setExporting(false) }
  }

  const fmt = n => (n || 0).toLocaleString('cs-CZ')
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      {/* Action bar */}
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Button green onClick={handleProcess} disabled={processing}>
          {processing ? 'Zpracovavam...' : `Zpracovat cekajici (${stats?.by_status?.ingested || 0})`}
        </Button>
        {flexiOk && (
          <Button onClick={handleExport} disabled={exporting}>
            {exporting ? 'Exportuji...' : `Export do Flexi (${stats?.by_status?.classified || 0})`}
          </Button>
        )}
        {!flexiOk && (
          <span className="text-sm font-bold" style={{ color: '#b45309' }}>
            Abra Flexi neni napojena — nastavte v Nastaveni
          </span>
        )}
        <select value={statusFilter} onChange={e => { setPage(1); setStatusFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny stavy</option>
          {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </div>

      {result && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{result}</div>}
      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Stats cards */}
      {stats && (
        <div className="grid grid-cols-6 gap-2 mb-4">
          <MiniStat label="Celkem" value={fmt(stats.total)} color="#1a2e22" />
          <MiniStat label="Cekajici" value={fmt(stats.by_status?.ingested || 0)} color="#6b7280" />
          <MiniStat label="Klasifikovano" value={fmt(stats.by_status?.classified || 0)} color="#7c3aed" />
          <MiniStat label="Synchronizovano" value={fmt(stats.by_status?.synced || 0)} color="#1a8a18" />
          <MiniStat label="Vyjimky" value={fmt(stats.needs_attention)} color="#dc2626" />
          <MiniStat label="Schvaleno" value={fmt(stats.by_status?.approved || 0)} color="#059669" />
        </div>
      )}

      {/* Events table */}
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH><TH>Typ</TH><TH>Zdroj</TH><TH>Popis</TH>
                <TH>Castka</TH><TH>Kategorie</TH><TH>Stav</TH><TH>Flexi</TH>
              </TRow>
            </thead>
            <tbody>
              {events.map(e => (
                <TRow key={e.id}>
                  <TD>{e.tax_date ? new Date(e.tax_date).toLocaleDateString('cs-CZ') : e.created_at ? new Date(e.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD><Badge label={TYPE_LABELS[e.event_type] || e.event_type} color={e.event_type === 'revenue' ? '#1a8a18' : '#dc2626'} bg={e.event_type === 'revenue' ? '#dcfce7' : '#fee2e2'} /></TD>
                  <TD><span className="text-sm font-bold" style={{ color: '#6b7280' }}>{SOURCE_LABELS[e.source] || e.source}</span></TD>
                  <TD>{e.description || e.sub_type || '—'}</TD>
                  <TD bold color={e.event_type === 'revenue' ? '#1a8a18' : '#dc2626'}>
                    {(e.amount || 0).toLocaleString('cs-CZ')} Kc
                  </TD>
                  <TD><span className="text-sm" style={{ color: '#6b7280' }}>{e.ai_category || '—'}</span></TD>
                  <TD>
                    <Badge label={STATUS_LABELS[e.pipeline_status] || e.pipeline_status}
                      color={STATUS_COLORS[e.pipeline_status] || '#6b7280'}
                      bg={STATUS_BGS[e.pipeline_status] || '#f3f4f6'} />
                  </TD>
                  <TD>
                    {e.flexi_id ? (
                      <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>{e.flexi_id}</span>
                    ) : e.pipeline_status === 'exception' ? (
                      <span className="text-sm font-bold" style={{ color: '#dc2626' }}>!</span>
                    ) : '—'}
                  </TD>
                </TRow>
              ))}
              {events.length === 0 && <TRow><TD>Zadne financni udalosti</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}

function MiniStat({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}
