import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Stat from '../../components/ui/Stat'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import CampaignCreateModal from './CampaignCreateModal'

const PAGE_SIZE = 15
const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

const STATUS_MAP = {
  draft:     { label: 'Koncept',    color: '#6b7280', bg: '#f3f4f6' },
  scheduled: { label: 'Naplánováno', color: '#2563eb', bg: '#dbeafe' },
  sending:   { label: 'Odesílá se', color: '#b45309', bg: '#fef3c7' },
  completed: { label: 'Dokončeno',  color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Zrušeno',    color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_OPTIONS = [
  { value: 'draft', label: 'Koncept' },
  { value: 'scheduled', label: 'Naplánováno' },
  { value: 'sending', label: 'Odesílá se' },
  { value: 'completed', label: 'Dokončeno' },
  { value: 'cancelled', label: 'Zrušeno' },
]

export default function CampaignsTab({ channel }) {
  const debugMode = useDebugMode()
  const [campaigns, setCampaigns] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [detail, setDetail] = useState(null)
  const [detailLogs, setDetailLogs] = useState([])
  const [detailLogsLoading, setDetailLogsLoading] = useState(false)
  const [showCreate, setShowCreate] = useState(false)
  const [confirm, setConfirm] = useState(null)

  const storageKey = `velin_campaigns_${channel}_filters`
  const defaultFilters = { search: '', statuses: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem(storageKey)
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })

  useEffect(() => { localStorage.setItem(storageKey, JSON.stringify(filters)) }, [filters, storageKey])
  useEffect(() => { setPage(1) }, [filters, channel])
  useEffect(() => { setFilters(defaultFilters); setPage(1) }, [channel])
  useEffect(() => { load() }, [page, filters, channel])

  const load = useCallback(async () => {
    setLoading(true); setError(null)
    try {
      debugLog('CampaignsTab', 'load', { channel, page, filters })
      let query = supabase
        .from('broadcast_campaigns')
        .select('*, message_templates(name, slug, body_template)', { count: 'exact' })
        .eq('channel', channel)

      if (filters.search) {
        query = query.ilike('name', `%${filters.search}%`)
      }
      if (filters.statuses?.length > 0) {
        query = query.in('status', filters.statuses)
      }

      query = query
        .order('created_at', { ascending: false })
        .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1)

      const { data, count, error: err } = await debugAction('campaigns.list', 'CampaignsTab', () => query)
      if (err) throw err
      setCampaigns(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('CampaignsTab', 'load', e)
      setError(e.message)
      setCampaigns([])
      setTotal(0)
    } finally { setLoading(false) }
  }, [channel, page, filters])

  async function loadDetailLogs(campaignId) {
    setDetailLogsLoading(true)
    try {
      const { data, error: err } = await debugAction('campaigns.detailLogs', 'CampaignsTab', () =>
        supabase
          .from('message_log')
          .select('*')
          .eq('metadata->>campaign_id', campaignId)
          .order('created_at', { ascending: false })
          .limit(20)
      )
      if (err) throw err
      setDetailLogs(data || [])
    } catch (e) {
      debugError('CampaignsTab', 'loadDetailLogs', e)
      setDetailLogs([])
    } finally { setDetailLogsLoading(false) }
  }

  function openDetail(campaign) {
    setDetail(campaign)
    loadDetailLogs(campaign.id)
  }

  async function handleDelete(campaignId) {
    try {
      const { error: err } = await debugAction('campaigns.delete', 'CampaignsTab', () =>
        supabase.from('broadcast_campaigns').delete().eq('id', campaignId)
      )
      if (err) throw err
      setDetail(null)
      load()
    } catch (e) {
      debugError('CampaignsTab', 'delete', e)
    }
    setConfirm(null)
  }

  async function handleCancel(campaignId) {
    try {
      const { error: err } = await debugAction('campaigns.cancel', 'CampaignsTab', () =>
        supabase.from('broadcast_campaigns').update({ status: 'cancelled' }).eq('id', campaignId)
      )
      if (err) throw err
      setDetail(prev => prev ? { ...prev, status: 'cancelled' } : null)
      load()
    } catch (e) {
      debugError('CampaignsTab', 'cancel', e)
    }
    setConfirm(null)
  }

  function formatDate(iso) {
    if (!iso) return '—'
    const d = new Date(iso)
    return d.toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' })
  }

  function formatDateTime(iso) {
    if (!iso) return '—'
    const d = new Date(iso)
    return d.toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  const totalPages = Math.ceil(total / PAGE_SIZE)

  return (
    <div>
      {/* Hlavička */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
            Kampaně
          </h2>
          <Badge label={String(total)} color="#1a2e22" bg="#f1faf7" />
        </div>
        <Button green onClick={() => setShowCreate(true)}>+ Nová kampaň</Button>
      </div>

      {/* Filtry */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput
          value={filters.search}
          onChange={v => setFilters(f => ({ ...f, search: v }))}
          placeholder="Hledat kampaň…"
        />

        <CheckboxFilterGroup
          label="Status"
          values={filters.statuses || []}
          onChange={v => setFilters(f => ({ ...f, statuses: v }))}
          options={STATUS_OPTIONS}
        />

        <button
          onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem(storageKey) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}
        >
          Reset
        </button>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA CampaignsTab ({channel})</strong><br/>
          <div>campaigns: {campaigns.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
          <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {/* Error */}
      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Tabulka */}
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : campaigns.length === 0 ? (
        <div className="text-center py-16">
          <div style={{ fontSize: 48, marginBottom: 12 }}>📢</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>
            Zatím žádné kampaně. Vytvořte první!
          </div>
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Název</TH>
                <TH>Status</TH>
                <TH>Příjemci</TH>
                <TH>Odesláno</TH>
                <TH>Selhalo</TH>
                <TH>Plán. odeslání</TH>
                <TH>Vytvořeno</TH>
              </TRow>
            </thead>
            <tbody>
              {campaigns.map(c => {
                const st = STATUS_MAP[c.status] || { label: c.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
                return (
                  <TRow key={c.id} onClick={() => openDetail(c)} style={{ cursor: 'pointer' }}>
                    <TD bold>{c.name || '—'}</TD>
                    <TD>
                      {c.status === 'sending' ? (
                        <span className="inline-flex items-center gap-1">
                          <span className="animate-pulse inline-block w-2 h-2 rounded-full" style={{ background: '#b45309' }} />
                          <Badge label={st.label} color={st.color} bg={st.bg} />
                        </span>
                      ) : (
                        <Badge label={st.label} color={st.color} bg={st.bg} />
                      )}
                    </TD>
                    <TD mono>{c.total_recipients ?? '—'}</TD>
                    <TD mono>{c.sent_count ?? '—'}</TD>
                    <TD mono>{c.failed_count ?? '—'}</TD>
                    <TD mono>{formatDateTime(c.scheduled_at)}</TD>
                    <TD mono>{formatDate(c.created_at)}</TD>
                  </TRow>
                )
              })}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail modal */}
      {detail && (
        <Modal open title="Detail kampaně" onClose={() => setDetail(null)} wide>
          {/* Hlavička */}
          <div className="flex items-center gap-2 mb-4">
            <span className="font-extrabold" style={{ fontSize: 16, color: '#0f1a14' }}>{detail.name}</span>
            <Badge label={(STATUS_MAP[detail.status] || {}).label || detail.status} color={(STATUS_MAP[detail.status] || {}).color || '#1a2e22'} bg={(STATUS_MAP[detail.status] || {}).bg || '#f3f4f6'} />
            <Badge label={CHANNEL_LABELS[channel] || channel} color="#2563eb" bg="#dbeafe" />
          </div>

          {/* Statistiky */}
          <div className="flex gap-3 mb-5">
            <Stat icon="👥" label="Celkem příjemců" value={detail.total_recipients ?? 0} color="#1a2e22" />
            <Stat icon="✅" label="Úspěšně odesláno" value={detail.sent_count ?? 0} color="#1a8a18" />
            <Stat icon="❌" label="Selhalo" value={detail.failed_count ?? 0} color="#dc2626" />
          </div>

          {/* Progress bar */}
          <div className="mb-5">
            <div className="flex items-center justify-between mb-1">
              <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Průběh odesílání</span>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                {detail.sent_count ?? 0} / {detail.total_recipients ?? 0}
              </span>
            </div>
            <div className="rounded-full" style={{ height: 10, background: '#f3f4f6', overflow: 'hidden' }}>
              <div
                className="rounded-full"
                style={{
                  height: '100%',
                  width: detail.total_recipients > 0 ? `${Math.min(100, ((detail.sent_count || 0) / detail.total_recipients) * 100)}%` : '0%',
                  background: '#74FB71',
                  transition: 'width 0.3s ease',
                }}
              />
            </div>
          </div>

          {/* Šablona */}
          {detail.message_templates && (
            <div className="mb-4">
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Šablona</div>
              <div className="rounded-card" style={{ padding: 12, background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 13, whiteSpace: 'pre-wrap', maxHeight: 200, overflow: 'auto' }}>
                {detail.message_templates.body_template || '—'}
              </div>
            </div>
          )}

          {/* Proměnné */}
          {detail.template_vars && Object.keys(detail.template_vars).length > 0 && (
            <div className="mb-4">
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Proměnné</div>
              <div className="rounded-card" style={{ padding: 12, background: '#f1faf7', border: '1px solid #d4e8e0', fontSize: 13 }}>
                {Object.entries(detail.template_vars).map(([key, val]) => (
                  <div key={key} className="flex gap-2">
                    <span className="font-bold" style={{ color: '#1a2e22' }}>{key}:</span>
                    <span style={{ color: '#1a2e22' }}>{String(val)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Log zpráv */}
          <div className="mb-4">
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Log zpráv</div>
            {detailLogsLoading ? (
              <div className="flex justify-center py-4"><div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
            ) : detailLogs.length === 0 ? (
              <div className="text-center py-4" style={{ color: '#6b7280', fontSize: 13 }}>Žádné záznamy</div>
            ) : (
              <>
                <Table>
                  <thead>
                    <TRow header>
                      <TH>Příjemce</TH>
                      <TH>Status</TH>
                      <TH>Čas</TH>
                    </TRow>
                  </thead>
                  <tbody>
                    {detailLogs.map(log => (
                      <TRow key={log.id}>
                        <TD>{log.recipient_email || log.recipient_phone || '—'}</TD>
                        <TD>
                          <Badge
                            label={log.status === 'sent' ? 'Odesláno' : log.status === 'delivered' ? 'Doručeno' : log.status === 'failed' ? 'Selhalo' : log.status || '—'}
                            color={log.status === 'sent' ? '#2563eb' : log.status === 'delivered' ? '#1a8a18' : log.status === 'failed' ? '#dc2626' : '#6b7280'}
                            bg={log.status === 'sent' ? '#dbeafe' : log.status === 'delivered' ? '#dcfce7' : log.status === 'failed' ? '#fee2e2' : '#f3f4f6'}
                          />
                        </TD>
                        <TD mono>{formatDateTime(log.created_at)}</TD>
                      </TRow>
                    ))}
                  </tbody>
                </Table>
                {detailLogs.length >= 20 && (
                  <div className="text-center mt-2">
                    <span className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb' }}>
                      Zobrazit vše →
                    </span>
                  </div>
                )}
              </>
            )}
          </div>

          {/* Akce */}
          <div className="flex justify-end gap-2 pt-3" style={{ borderTop: '1px solid #e5e7eb' }}>
            {detail.status === 'draft' && (
              <Button
                onClick={() => setConfirm({ type: 'delete', id: detail.id, name: detail.name })}
                style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}
              >
                Smazat
              </Button>
            )}
            {detail.status === 'sending' && (
              <Button
                onClick={() => setConfirm({ type: 'stop', id: detail.id, name: detail.name })}
                style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}
              >
                Zastavit
              </Button>
            )}
            {detail.status === 'scheduled' && (
              <Button
                onClick={() => setConfirm({ type: 'cancel', id: detail.id, name: detail.name })}
                style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}
              >
                Zrušit plán
              </Button>
            )}
            <Button onClick={() => setDetail(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}

      {/* Confirm dialog */}
      <ConfirmDialog
        open={!!confirm}
        danger
        title={
          confirm?.type === 'delete' ? 'Smazat kampaň?' :
          confirm?.type === 'stop' ? 'Zastavit odesílání?' :
          'Zrušit naplánované odeslání?'
        }
        message={
          confirm?.type === 'delete'
            ? `Opravdu chcete smazat kampaň "${confirm?.name}"? Tato akce je nevratná.`
            : confirm?.type === 'stop'
            ? `Opravdu chcete zastavit odesílání kampaně "${confirm?.name}"? Zbývající zprávy nebudou odeslány.`
            : `Opravdu chcete zrušit naplánované odeslání kampaně "${confirm?.name}"?`
        }
        onConfirm={() => {
          if (confirm?.type === 'delete') handleDelete(confirm.id)
          else handleCancel(confirm.id)
        }}
        onCancel={() => setConfirm(null)}
      />

      <CampaignCreateModal open={showCreate} channel={channel} onClose={() => setShowCreate(false)} onCreated={load} />
    </div>
  )
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
