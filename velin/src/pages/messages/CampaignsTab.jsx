import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const PAGE_SIZE = 15
const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

export default function CampaignsTab({ channel }) {
  const [campaigns, setCampaigns] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showNew, setShowNew] = useState(false)

  // New campaign form
  const [name, setName] = useState('')
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [targetGroup, setTargetGroup] = useState('all')
  const [saving, setSaving] = useState(false)

  useEffect(() => { setPage(1) }, [channel, search])
  useEffect(() => { load() }, [channel, search, page])

  async function load() {
    setLoading(true)
    try {
      let query = supabase
        .from('notification_log')
        .select('*', { count: 'exact' })
        .eq('channel', channel)
        .eq('type', 'campaign')
        .order('created_at', { ascending: false })
        .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1)

      if (search) {
        query = query.or(`subject.ilike.%${search}%,content.ilike.%${search}%`)
      }

      const { data, count, error } = await debugAction('campaigns.load', 'CampaignsTab', () => query)
      if (error) throw error
      setCampaigns(data || [])
      setTotal(count || 0)
    } catch {
      setCampaigns([])
      setTotal(0)
    }
    setLoading(false)
  }

  function openNew() {
    setName('')
    setSubject('')
    setBody('')
    setTargetGroup('all')
    setShowNew(true)
  }

  async function handleCreate() {
    if (!name.trim() || !body.trim()) return
    setSaving(true)
    try {
      // Fetch target customers
      let query = supabase.from('profiles').select('id, full_name, email, phone')
      if (targetGroup === 'marketing') query = query.eq('marketing_consent', true)

      const { data: recipients } = await debugAction('campaigns.fetchRecipients', 'CampaignsTab', () => query)

      if (recipients && recipients.length > 0) {
        const entries = recipients.map(r => ({
          user_id: r.id,
          channel,
          type: 'campaign',
          subject: subject || name,
          content: body.trim(),
          recipient: channel === 'email' ? r.email : r.phone,
          status: 'pending',
          created_at: new Date().toISOString(),
        }))

        await debugAction('campaigns.insert', 'CampaignsTab', () =>
          supabase.from('notification_log').insert(entries)
        )
      }

      setShowNew(false)
      load()
    } catch {}
    setSaving(false)
  }

  const totalPages = Math.ceil(total / PAGE_SIZE)

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
          {CHANNEL_LABELS[channel]} Kampaně
        </h2>
        <div className="flex items-center gap-3">
          <SearchInput value={search} onChange={setSearch} placeholder="Hledat kampaň…" />
          <Button green onClick={openNew}>+ Nová kampaň</Button>
        </div>
      </div>

      {loading && campaigns.length === 0 ? (
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
        </div>
      ) : campaigns.length === 0 ? (
        <div className="text-center py-8" style={{ color: '#1a2e22', fontSize: 13 }}>
          Žádné {CHANNEL_LABELS[channel]} kampaně
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH>
                <TH>Název / Předmět</TH>
                <TH>Příjemce</TH>
                <TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {campaigns.map(c => (
                <TRow key={c.id}>
                  <TD mono>{c.created_at ? new Date(c.created_at).toLocaleString('cs-CZ') : '—'}</TD>
                  <TD bold>{c.subject || '—'}</TD>
                  <TD>{c.recipient || '—'}</TD>
                  <TD>
                    <Badge
                      label={c.status === 'sent' ? 'Odesláno' : c.status === 'failed' ? 'Chyba' : 'Čeká'}
                      color={c.status === 'sent' ? '#1a6a18' : c.status === 'failed' ? '#991b1b' : '#92400e'}
                      bg={c.status === 'sent' ? '#dcfce7' : c.status === 'failed' ? '#fee2e2' : '#fef3c7'}
                    />
                  </TD>
                </TRow>
              ))}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      <div className="mt-3 text-right" style={{ fontSize: 11, color: '#1a2e22' }}>
        Celkem: {total} záznamů
      </div>

      {/* New campaign modal */}
      <Modal open={showNew} title={`Nová ${CHANNEL_LABELS[channel]} kampaň`} onClose={() => setShowNew(false)}>
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Název kampaně
            </label>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="Např. Letní akce 2026"
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
            />
          </div>

          {channel === 'email' && (
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                Předmět e-mailu
              </label>
              <input
                type="text"
                value={subject}
                onChange={e => setSubject(e.target.value)}
                placeholder="Předmět…"
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              />
            </div>
          )}

          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Cílová skupina
            </label>
            <select
              value={targetGroup}
              onChange={e => setTargetGroup(e.target.value)}
              className="w-full rounded-btn text-sm outline-none cursor-pointer"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            >
              <option value="all">Všichni zákazníci</option>
              <option value="marketing">Zákazníci se souhlasem s marketingem</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Text zprávy
            </label>
            <textarea
              value={body}
              onChange={e => setBody(e.target.value)}
              placeholder={`Text ${CHANNEL_LABELS[channel]} kampaně…`}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 120, resize: 'vertical' }}
            />
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button onClick={() => setShowNew(false)}>Zrušit</Button>
            <Button green onClick={handleCreate} disabled={saving || !name.trim() || !body.trim()}>
              {saving ? 'Odesílám…' : 'Spustit kampaň'}
            </Button>
          </div>
        </div>
      </Modal>
    </Card>
  )
}
