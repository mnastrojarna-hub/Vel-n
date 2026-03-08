import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSTimeline from './SOSTimeline'
import { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from '../SOSPanel'

const DECISION_LABELS = {
  replacement_moto: '🏍️ Chce náhradní motorku',
  end_ride: '🚛 Ukončuje jízdu (odtah)',
  continue: '✅ Pokračuje v jízdě',
  waiting: '⏳ Čeká na rozhodnutí',
}

const REPLACEMENT_STATUS_LABELS = {
  selecting: 'Zákazník vybírá motorku',
  pending_payment: 'Čeká na platbu',
  paid: 'Zaplaceno',
  admin_review: 'Čeká na schválení',
  approved: 'Schváleno – připravit přistavení',
  dispatched: 'Motorka na cestě',
  delivered: 'Doručeno zákazníkovi',
  rejected: 'Zamítnuto',
}

const REPLACEMENT_STATUS_COLORS = {
  selecting: { bg: '#fef3c7', color: '#b45309' },
  pending_payment: { bg: '#fef3c7', color: '#b45309' },
  paid: { bg: '#dbeafe', color: '#2563eb' },
  admin_review: { bg: '#fee2e2', color: '#dc2626' },
  approved: { bg: '#dcfce7', color: '#1a8a18' },
  dispatched: { bg: '#dbeafe', color: '#2563eb' },
  delivered: { bg: '#dcfce7', color: '#1a8a18' },
  rejected: { bg: '#fee2e2', color: '#dc2626' },
}

const DAMAGE_LABELS = {
  none: 'Žádné poškození',
  cosmetic: 'Kosmetické (škrábance, odřeniny)',
  functional: 'Funkční (ovlivňuje provoz)',
  totaled: 'Totální škoda',
}

export default function SOSDetailPanel({ incident, onClose, onRefresh }) {
  const [booking, setBooking] = useState(null)
  const [customer, setCustomer] = useState(null)
  const [moto, setMoto] = useState(null)
  const [admins, setAdmins] = useState([])
  const [message, setMessage] = useState('')
  const [adminNotes, setAdminNotes] = useState(incident?.admin_notes || '')
  const [resolution, setResolution] = useState(incident?.resolution || '')
  const [sending, setSending] = useState(false)
  const [msgSent, setMsgSent] = useState(false)
  const [rejectReason, setRejectReason] = useState('')
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [replacementMoto, setReplacementMoto] = useState(null)

  useEffect(() => {
    // Reset all state when incident changes to prevent stale view
    setBooking(null)
    setCustomer(null)
    setMoto(null)
    setMessage('')
    setMsgSent(false)
    setReplacementMoto(null)
    if (!incident) return
    loadDetails()
    loadAdmins()
    loadReplacementMoto()
    setAdminNotes(incident.admin_notes || '')
    setResolution(incident.resolution || '')
    setShowRejectForm(false)
    setRejectReason('')
  }, [incident?.id])

  async function loadReplacementMoto() {
    setReplacementMoto(null)
    const rd = incident?.replacement_data
    if (!rd?.replacement_moto_id) return
    const { data: m } = await supabase.from('motorcycles')
      .select('*, branches(name)').eq('id', rd.replacement_moto_id).single()
    if (m) setReplacementMoto(m)
  }

  async function loadDetails() {
    setCustomer(null)
    setMoto(null)
    setBooking(null)
    if (incident.booking_id || incident.bookings?.id) {
      const bookingId = incident.booking_id || incident.bookings?.id
      const { data: b } = await supabase.from('bookings')
        .select('*, motorcycles(*, branches(name)), profiles(*)')
        .eq('id', bookingId).single()
      if (b) {
        setBooking(b)
        setCustomer(b.profiles)
        setMoto(b.motorcycles)
        return
      }
    }
    if (incident.moto_id) {
      const { data: m } = await supabase.from('motorcycles').select('*, branches(name)').eq('id', incident.moto_id).single()
      if (m) setMoto(m)
    }
    if (incident.user_id) {
      const { data: p } = await supabase.from('profiles').select('*').eq('id', incident.user_id).single()
      if (p) setCustomer(p)
    }
  }

  async function loadAdmins() {
    const { data } = await supabase.from('admin_users').select('id, name').eq('active', true)
    setAdmins(data || [])
  }

  async function assignAdmin(adminId) {
    await debugAction('sos.assignAdmin', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ assigned_to: adminId || null }).eq('id', incident.id)
    , { incident_id: incident.id, admin_id: adminId })
    const { data: { user } } = await supabase.auth.getUser()
    const adminName = admins.find(a => a.id === adminId)?.name || 'admin'
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: adminId ? `Přiřazeno: ${adminName}` : 'Přiřazení odebráno',
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function updateDecision(decision) {
    // SAFETY: Confirm decision change — affects customer billing
    const label = DECISION_LABELS[decision] || decision
    if (!window.confirm(`Nastavit rozhodnutí zákazníka na:\n\n${label}\n\nTato informace se zaznamená do timeline.`)) return
    await debugAction('sos.updateDecision', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ customer_decision: decision }).eq('id', incident.id)
    , { incident_id: incident.id, decision })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Rozhodnutí zákazníka: ${label}`,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function updateFault(isFault) {
    // SAFETY: Fault assignment has financial impact — confirm
    const msg = isFault
      ? 'Nastavit zavinění na ZÁKAZNÍKA?\n\n⚠️ Zákazník bude platit náklady za náhradní moto a odtah.'
      : 'Nastavit jako CIZÍ ZAVINĚNÍ?\n\n💚 Zákazník nebude nic platit — náhradní moto a odtah zdarma.'
    if (!window.confirm(msg)) return
    await debugAction('sos.updateFault', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ customer_fault: isFault }).eq('id', incident.id)
    , { incident_id: incident.id, customer_fault: isFault })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: isFault ? 'Zavinění: zákazník (platí náklady)' : 'Zavinění: cizí (bez nákladů pro zákazníka)',
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function saveField(field, value) {
    await debugAction('sos.saveField', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ [field]: value }).eq('id', incident.id)
    , { incident_id: incident.id, field, value })
  }

  async function updateReplacementStatus(newStatus) {
    // SAFETY: Confirm dispatch/delivery status changes
    const label = REPLACEMENT_STATUS_LABELS[newStatus] || newStatus
    if (newStatus === 'dispatched') {
      if (!window.confirm('Potvrdit že motorka je na cestě k zákazníkovi?\n\nZákazník bude informován.')) return
    }
    if (newStatus === 'delivered') {
      if (!window.confirm('Potvrdit doručení motorky zákazníkovi?\n\nTuto akci nelze vrátit zpět.')) return
    }
    await debugAction('sos.updateReplacementStatus', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ replacement_status: newStatus }).eq('id', incident.id)
    , { incident_id: incident.id, replacement_status: newStatus })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Náhradní moto: ${label}`,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function approveReplacement() {
    const rd = incident.replacement_data || {}
    // SAFETY: Ověření že platba proběhla u zaviněných nehod
    if (rd.customer_fault && rd.payment_status !== 'paid' && rd.payment_status !== 'free') {
      if (!window.confirm('⚠️ POZOR: Zákazník ještě nezaplatil poplatek!\n\nPlatební stav: ' + (rd.payment_status || 'neznámý') + '\n\nOpravdu chcete schválit bez platby?')) {
        return
      }
    }
    // SAFETY: Potvrzení schválení
    if (!window.confirm(`Schválit objednávku náhradní motorky?\n\n🏍️ ${rd.replacement_model || '?'}\n📍 ${rd.delivery_address || '?'}, ${rd.delivery_city || '?'}\n💰 ${rd.payment_amount || 0} Kč (${rd.payment_status === 'free' ? 'zdarma' : rd.payment_status || '?'})\n\nPo schválení bude motorka připravena k přistavení.`)) {
      return
    }
    const updatedRd = { ...rd, approved_by_admin: true, approved_at: new Date().toISOString() }
    await debugAction('sos.approveReplacement', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({
        replacement_data: updatedRd,
        replacement_status: 'approved',
      }).eq('id', incident.id)
    , { incident_id: incident.id })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Objednávka náhradní motorky SCHVÁLENA: ${rd.replacement_model || '?'}`,
      description: `Adresa: ${rd.delivery_address || '?'}, ${rd.delivery_city || '?'}. Částka: ${rd.payment_amount || '?'} Kč (${rd.payment_status === 'free' ? 'zdarma' : 'zaplaceno'})`,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function rejectReplacement(reason) {
    if (!reason?.trim()) {
      alert('Vyplňte důvod zamítnutí — zákazník ho uvidí.')
      return
    }
    if (!window.confirm(`Opravdu zamítnout objednávku?\n\nDůvod: ${reason}\n\nZákazník bude informován.`)) {
      return
    }
    const rd = incident.replacement_data || {}
    const updatedRd = { ...rd, approved_by_admin: false, rejected_at: new Date().toISOString(), rejection_reason: reason }
    await debugAction('sos.rejectReplacement', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({
        replacement_data: updatedRd,
        replacement_status: 'rejected',
      }).eq('id', incident.id)
    , { incident_id: incident.id })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Objednávka náhradní motorky ZAMÍTNUTA`,
      description: reason || '',
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function sendMessage() {
    if (!message.trim() || !customer?.id) return
    setSending(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()

      let { data: thread } = await supabase.from('message_threads')
        .select('id').eq('customer_id', customer.id).eq('channel', 'web')
        .in('status', ['open']).order('created_at', { ascending: false }).limit(1).single()

      if (!thread) {
        const { data: newThread } = await supabase.from('message_threads').insert({
          customer_id: customer.id, channel: 'web', status: 'open',
          subject: `SOS: ${incident.title || TYPE_LABELS[incident.type] || 'Incident'}`,
          last_message_at: new Date().toISOString(),
        }).select().single()
        thread = newThread
      }

      if (thread) {
        const msgData = {
          thread_id: thread.id, direction: 'admin', sender_name: 'Admin (SOS)',
          content: message.trim(), read_at: new Date().toISOString(),
        }
        await debugAction('sos.sendMessage', 'SOSDetailPanel', () =>
          supabase.from('messages').insert(msgData)
        , { incident_id: incident.id, customer_id: customer.id, content: message.trim() })
        await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
      }

      // Insert into admin_messages for MotoG app fullscreen overlay
      const sosTitle = incident.title || TYPE_LABELS[incident.type] || 'SOS'
      await supabase.from('admin_messages').insert({
        user_id: customer.id,
        title: `SOS: ${sosTitle}`,
        message: message.trim(),
        type: 'sos_response',
        read: false,
      }).then(r => {
        if (r.error) console.warn('[SOSDetail] admin_messages insert failed:', r.error.message)
      })

      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Zpráva odeslána: "${message.slice(0, 50)}${message.length > 50 ? '...' : ''}"`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      setMessage('')
      setMsgSent(true)
      setTimeout(() => setMsgSent(false), 3000)
    } catch {}
    setSending(false)
  }

  if (!incident) return null

  const sev = SEVERITY_MAP[incident.severity] || SEVERITY_MAP.medium
  const sc = STATUS_COLORS[incident.status] || STATUS_COLORS.reported
  const displayTitle = incident.title || TYPE_LABELS[incident.type] || 'Incident'
  const isActive = !['resolved', 'closed'].includes(incident.status)
  const isAccident = incident.type?.startsWith('accident')
  const isMajor = incident.type === 'accident_major' || incident.type === 'breakdown_major'

  return (
    <div className="space-y-4">
      {/* Header */}
      <Card>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <span className="text-2xl">{TYPE_ICONS[incident.type] || '⚠️'}</span>
            <div>
              <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>{displayTitle}</h3>
              {incident.title && (
                <span className="text-[10px] font-bold uppercase tracking-wide" style={{ color: '#8aab99' }}>
                  {TYPE_LABELS[incident.type] || incident.type}
                </span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sev.bg, color: sev.color }}>{sev.label}</span>
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sc.bg, color: sc.color }}>{sc.label}</span>
            <button onClick={onClose} className="text-xs font-bold cursor-pointer"
              style={{ color: '#8aab99', background: 'none', border: 'none' }}>✕</button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="ID" value={incident.id?.slice(0, 8)} mono />
          <InfoRow label="Nahlášeno" value={incident.created_at ? new Date(incident.created_at).toLocaleString('cs-CZ') : '—'} />
          <InfoRow label="Kontakt" value={incident.contact_phone || customer?.phone || incident.profiles?.phone} />
          {incident.moto_rideable !== null && incident.moto_rideable !== undefined && (
            <InfoRow label="Pojízdná" value={incident.moto_rideable ? 'Ano' : 'NE — nepojízdná'} />
          )}
        </div>

        {/* Popis od zákazníka */}
        {incident.description && (
          <div className="mt-3 rounded-lg text-xs" style={{
            padding: '10px 14px', background: '#f8fcfa', color: '#4a6357',
            borderLeft: '3px solid #d4e8e0', lineHeight: 1.6,
          }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
              Popis od zákazníka
            </div>
            {incident.description}
          </div>
        )}

        {/* Preference zákazníka – prominentní zobrazení */}
        {(incident.customer_decision || incident.customer_fault !== null) && (
          <div className="mt-3 rounded-lg" style={{
            padding: '12px 14px',
            background: incident.customer_fault ? '#fef2f2' : '#f0fdf4',
            border: `2px solid ${incident.customer_fault ? '#fca5a5' : '#86efac'}`,
          }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{
              color: incident.customer_fault ? '#dc2626' : '#1a8a18'
            }}>
              Preference zákazníka
            </div>
            <div className="flex flex-wrap gap-2">
              {incident.customer_decision && (
                <span className="inline-block rounded-btn text-xs font-extrabold" style={{
                  padding: '4px 10px',
                  background: incident.customer_fault ? '#fee2e2' : '#dcfce7',
                  color: incident.customer_fault ? '#b91c1c' : '#15803d',
                }}>
                  {DECISION_LABELS[incident.customer_decision] || incident.customer_decision}
                </span>
              )}
              {incident.customer_fault === true && (
                <span className="inline-block rounded-btn text-xs font-extrabold" style={{
                  padding: '4px 10px', background: '#fee2e2', color: '#b91c1c',
                }}>
                  ⚠️ Zavinil zákazník (platí)
                </span>
              )}
              {incident.customer_fault === false && (
                <span className="inline-block rounded-btn text-xs font-extrabold" style={{
                  padding: '4px 10px', background: '#dcfce7', color: '#15803d',
                }}>
                  Cizí zavinění (zdarma)
                </span>
              )}
              {incident.moto_rideable === false && (
                <span className="inline-block rounded-btn text-xs font-extrabold" style={{
                  padding: '4px 10px', background: '#fef3c7', color: '#b45309',
                }}>
                  Motorka nepojízdná
                </span>
              )}
            </div>
            {incident.replacement_status && (
              <div className="mt-2">
                <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase" style={{
                  padding: '3px 8px',
                  ...(REPLACEMENT_STATUS_COLORS[incident.replacement_status] || { bg: '#f1faf7', color: '#4a6357' }),
                  background: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).bg,
                  color: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).color,
                }}>
                  {REPLACEMENT_STATUS_LABELS[incident.replacement_status] || incident.replacement_status}
                </span>
              </div>
            )}
          </div>
        )}

        {/* Přiřadit */}
        <div className="mt-3 flex items-center gap-2">
          <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Přiřadit:</span>
          <select value={incident.assigned_to || ''} onChange={e => assignAdmin(e.target.value)}
            className="rounded-btn text-[11px] outline-none cursor-pointer"
            style={{ padding: '4px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
            <option value="">Nepřiřazeno</option>
            {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>
      </Card>

      {/* Rozhodnutí zákazníka (u nepojízdných) */}
      {isActive && isMajor && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>
            Rozhodnutí zákazníka
          </h4>
          <div className="flex flex-wrap gap-2 mb-3">
            {Object.entries(DECISION_LABELS).map(([key, label]) => (
              <button key={key} onClick={() => updateDecision(key)}
                className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                style={{
                  padding: '6px 14px',
                  background: incident.customer_decision === key ? '#1a2e22' : '#f1faf7',
                  color: incident.customer_decision === key ? '#74FB71' : '#4a6357',
                }}>
                {label}
              </button>
            ))}
          </div>

          {/* Zavinění (u nehod) */}
          {isAccident && (
            <div className="mt-3">
              <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Zavinění: </span>
              <div className="flex gap-2 mt-1">
                <button onClick={() => updateFault(true)}
                  className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === true ? '#dc2626' : '#f1faf7',
                    color: incident.customer_fault === true ? '#fff' : '#4a6357',
                  }}>
                  Zákazník (platí)
                </button>
                <button onClick={() => updateFault(false)}
                  className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === false ? '#1a8a18' : '#f1faf7',
                    color: incident.customer_fault === false ? '#fff' : '#4a6357',
                  }}>
                  Cizí zavinění
                </button>
              </div>
            </div>
          )}
        </Card>
      )}

      {/* Objednávka náhradní motorky (zákazník zavinil) */}
      {incident.replacement_data && (
        <Card>
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#dc2626' }}>
              Objednávka náhradní motorky
            </h4>
            {incident.replacement_status && (
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase" style={{
                padding: '2px 7px',
                background: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).bg || '#f1faf7',
                color: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).color || '#4a6357',
              }}>
                {REPLACEMENT_STATUS_LABELS[incident.replacement_status] || incident.replacement_status}
              </span>
            )}
          </div>

          {/* Detaily objednávky */}
          <div className="rounded-lg text-xs" style={{
            padding: '12px', background: '#fef2f2', border: '1px solid #fecaca', lineHeight: 1.8,
          }}>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1">
              <InfoRow label="Motorka" value={incident.replacement_data.replacement_model} />
              {replacementMoto && <InfoRow label="SPZ" value={replacementMoto.spz} mono />}
              {replacementMoto?.branches?.name && <InfoRow label="Pobočka" value={replacementMoto.branches.name} />}
              <InfoRow label="Adresa" value={`${incident.replacement_data.delivery_address || '?'}, ${incident.replacement_data.delivery_city || '?'}`} />
              {incident.replacement_data.delivery_zip && <InfoRow label="PSČ" value={incident.replacement_data.delivery_zip} />}
              {incident.replacement_data.delivery_note && <InfoRow label="Poznámka" value={incident.replacement_data.delivery_note} />}
              <InfoRow label="Pronájem/den" value={incident.replacement_data.daily_price ? `${Number(incident.replacement_data.daily_price).toLocaleString('cs-CZ')} Kč` : '—'} />
              <InfoRow label="Přistavení" value={incident.replacement_data.delivery_fee ? `${Number(incident.replacement_data.delivery_fee).toLocaleString('cs-CZ')} Kč + km` : '—'} />
            </div>
            <div className="mt-2 pt-2" style={{ borderTop: '1px solid #fecaca' }}>
              <div className="flex justify-between items-center">
                <span className="font-extrabold text-sm" style={{ color: '#b91c1c' }}>Celkem k úhradě:</span>
                <span className="font-extrabold text-sm" style={{ color: '#b91c1c' }}>
                  {incident.replacement_data.payment_status === 'free' ? '0 Kč (zdarma)' :
                    incident.replacement_data.payment_amount ? `${Number(incident.replacement_data.payment_amount).toLocaleString('cs-CZ')} Kč` : '—'}
                </span>
              </div>
              {/* Výrazný platební status */}
              <div className="mt-2 rounded-lg text-xs font-extrabold" style={{
                padding: '6px 10px',
                background: incident.replacement_data.payment_status === 'paid' ? '#dcfce7' :
                  incident.replacement_data.payment_status === 'free' ? '#dcfce7' :
                  incident.replacement_data.payment_status === 'pending' ? '#fee2e2' : '#fef3c7',
                color: incident.replacement_data.payment_status === 'paid' ? '#1a8a18' :
                  incident.replacement_data.payment_status === 'free' ? '#1a8a18' :
                  incident.replacement_data.payment_status === 'pending' ? '#dc2626' : '#b45309',
              }}>
                {incident.replacement_data.payment_status === 'paid' && '✅ ZAPLACENO'}
                {incident.replacement_data.payment_status === 'free' && '💚 ZDARMA (nezaviněná nehoda / porucha)'}
                {incident.replacement_data.payment_status === 'pending' && '❌ NEZAPLACENO — zákazník ještě neuhradil poplatek'}
                {incident.replacement_data.payment_status === 'processing' && '⏳ Platba se zpracovává...'}
                {!incident.replacement_data.payment_status && '❓ Stav platby neznámý'}
                {incident.replacement_data.paid_at && ` · ${new Date(incident.replacement_data.paid_at).toLocaleString('cs-CZ')}`}
              </div>
              {incident.replacement_data.customer_fault && (
                <div className="text-[10px] font-bold mt-1" style={{ color: '#dc2626' }}>
                  ⚠️ Zavinil zákazník — platí poplatek
                </div>
              )}
              {incident.replacement_data.customer_confirmed_at && (
                <div className="text-[10px] mt-1" style={{ color: '#8aab99' }}>
                  Objednáno: {new Date(incident.replacement_data.customer_confirmed_at).toLocaleString('cs-CZ')}
                </div>
              )}
            </div>
          </div>

          {/* Akce: Schválit / Zamítnout */}
          {isActive && incident.replacement_status === 'admin_review' && (
            <div className="mt-3">
              {!showRejectForm ? (
                <div className="flex gap-2">
                  <button onClick={approveReplacement}
                    className="flex-1 rounded-btn text-xs font-extrabold tracking-wide cursor-pointer border-none"
                    style={{ padding: '10px 16px', background: '#1a8a18', color: '#fff' }}>
                    Schválit objednávku
                  </button>
                  <button onClick={() => setShowRejectForm(true)}
                    className="flex-1 rounded-btn text-xs font-extrabold tracking-wide cursor-pointer border-none"
                    style={{ padding: '10px 16px', background: '#dc2626', color: '#fff' }}>
                    Zamítnout
                  </button>
                </div>
              ) : (
                <div>
                  <textarea value={rejectReason} onChange={e => setRejectReason(e.target.value)}
                    rows={2} placeholder="Důvod zamítnutí…"
                    className="w-full rounded-btn text-xs outline-none mb-2"
                    style={{ padding: '8px 10px', background: '#fff', border: '1px solid #fca5a5', resize: 'vertical' }}
                  />
                  <div className="flex gap-2">
                    <button onClick={() => { rejectReplacement(rejectReason); setShowRejectForm(false) }}
                      className="flex-1 rounded-btn text-xs font-extrabold cursor-pointer border-none"
                      style={{ padding: '8px 12px', background: '#dc2626', color: '#fff' }}>
                      Potvrdit zamítnutí
                    </button>
                    <button onClick={() => setShowRejectForm(false)}
                      className="rounded-btn text-xs font-extrabold cursor-pointer border-none"
                      style={{ padding: '8px 12px', background: '#f1faf7', color: '#4a6357' }}>
                      Zrušit
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Akce: Změnit status přistavení */}
          {isActive && incident.replacement_status === 'approved' && (
            <div className="mt-3 flex gap-2">
              <button onClick={() => updateReplacementStatus('dispatched')}
                className="flex-1 rounded-btn text-xs font-extrabold cursor-pointer border-none"
                style={{ padding: '8px 12px', background: '#2563eb', color: '#fff' }}>
                Motorka na cestě
              </button>
            </div>
          )}
          {isActive && incident.replacement_status === 'dispatched' && (
            <div className="mt-3 flex gap-2">
              <button onClick={() => updateReplacementStatus('delivered')}
                className="flex-1 rounded-btn text-xs font-extrabold cursor-pointer border-none"
                style={{ padding: '8px 12px', background: '#1a8a18', color: '#fff' }}>
                Doručeno zákazníkovi
              </button>
            </div>
          )}

          {/* Info o zamítnutí */}
          {incident.replacement_status === 'rejected' && incident.replacement_data.rejection_reason && (
            <div className="mt-3 rounded-lg text-xs" style={{
              padding: '8px 12px', background: '#fee2e2', color: '#b91c1c', fontWeight: 600,
            }}>
              Důvod zamítnutí: {incident.replacement_data.rejection_reason}
            </div>
          )}
        </Card>
      )}

      {/* Poškození motorky */}
      {isAccident && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poškození motorky</h4>
          <div className="flex flex-wrap gap-2 mb-3">
            {Object.entries(DAMAGE_LABELS).map(([key, label]) => (
              <button key={key} onClick={() => saveField('damage_severity', key)}
                className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                style={{
                  padding: '5px 12px',
                  background: incident.damage_severity === key ? '#1a2e22' : '#f1faf7',
                  color: incident.damage_severity === key ? '#74FB71' : '#4a6357',
                }}>
                {label}
              </button>
            ))}
          </div>
          {incident.damage_description && (
            <div className="text-xs rounded-lg" style={{ padding: '6px 10px', background: '#f8fcfa', color: '#4a6357' }}>
              {incident.damage_description}
            </div>
          )}
        </Card>
      )}

      {/* Nejbližší servis (pro poruchy a dotazy) */}
      {(incident.type === 'breakdown_minor' || incident.type === 'defect_question') && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Nejbližší servis</h4>
          <div className="grid grid-cols-1 gap-2">
            <input type="text" placeholder="Název servisu" defaultValue={incident.nearest_service_name || ''}
              onBlur={e => saveField('nearest_service_name', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Adresa servisu" defaultValue={incident.nearest_service_address || ''}
              onBlur={e => saveField('nearest_service_address', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Telefon servisu" defaultValue={incident.nearest_service_phone || ''}
              onBlur={e => saveField('nearest_service_phone', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          </div>
        </Card>
      )}

      {/* Zákazník */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Zákazník</h4>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="Jméno" value={customer?.full_name || incident.profiles?.full_name} />
          <InfoRow label="Telefon" value={customer?.phone || incident.profiles?.phone} />
          <InfoRow label="Email" value={customer?.email || incident.profiles?.email} />
          <InfoRow label="Město" value={customer?.city} />
        </div>
      </Card>

      {/* Motorka */}
      {moto && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Motorka</h4>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="Model" value={moto.model} />
            <InfoRow label="SPZ" value={moto.spz} mono />
            <InfoRow label="VIN" value={moto.vin} mono />
            <InfoRow label="Pobočka" value={moto.branches?.name} />
            <InfoRow label="Km" value={moto.mileage?.toLocaleString('cs-CZ')} />
          </div>
        </Card>
      )}

      {/* Rezervace */}
      {booking && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Rezervace</h4>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="ID" value={booking.id?.slice(0, 8)} mono />
            <InfoRow label="Stav" value={booking.status} />
            <InfoRow label="Od" value={booking.start_date} />
            <InfoRow label="Do" value={booking.end_date} />
            <InfoRow label="Částka" value={booking.total_price ? `${Number(booking.total_price).toLocaleString('cs-CZ')} Kč` : '—'} />
          </div>
        </Card>
      )}

      {/* Mapa */}
      {incident.latitude && incident.longitude && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poloha zákazníka</h4>
          {incident.address && (
            <div className="text-xs font-bold mb-2" style={{ color: '#0f1a14' }}>{incident.address}</div>
          )}
          <div className="rounded-lg overflow-hidden" style={{ height: 200 }}>
            <iframe title="Poloha" width="100%" height="200" frameBorder="0" style={{ border: 0 }}
              src={`https://www.openstreetmap.org/export/embed.html?bbox=${incident.longitude - 0.01},${incident.latitude - 0.01},${incident.longitude + 0.01},${incident.latitude + 0.01}&layer=mapnik&marker=${incident.latitude},${incident.longitude}`}
            />
          </div>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-[10px] font-mono" style={{ color: '#8aab99' }}>
              {Number(incident.latitude).toFixed(6)}, {Number(incident.longitude).toFixed(6)}
            </span>
            <a href={`https://www.google.com/maps?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#1a8a18' }}>
              Google Maps
            </a>
            <a href={`https://mapy.cz/zakladni?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#2563eb' }}>
              Mapy.cz
            </a>
            <a href={`https://www.google.com/maps/dir/?api=1&destination=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#b45309' }}>
              Navigovat
            </a>
          </div>
        </Card>
      )}

      {/* Poznámky admina */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poznámky admina</h4>
        <textarea value={adminNotes} onChange={e => setAdminNotes(e.target.value)}
          rows={3} placeholder="Interní poznámky (zákazník je nevidí)…"
          className="w-full rounded-btn text-sm outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
          onBlur={() => saveField('admin_notes', adminNotes)}
        />
      </Card>

      {/* Řešení */}
      {['resolved', 'closed'].includes(incident.status) && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Řešení incidentu</h4>
          <textarea value={resolution} onChange={e => setResolution(e.target.value)}
            rows={3} placeholder="Jak byl incident vyřešen…"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
            onBlur={() => saveField('resolution', resolution)}
          />
          {incident.resolved_at && (
            <div className="text-[10px] mt-1" style={{ color: '#8aab99' }}>
              Vyřešeno: {new Date(incident.resolved_at).toLocaleString('cs-CZ')}
            </div>
          )}
        </Card>
      )}

      {/* Odeslat zprávu */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Odeslat zprávu zákazníkovi</h4>
        <textarea value={message} onChange={e => setMessage(e.target.value)}
          rows={3} placeholder="Napište zprávu zákazníkovi…"
          className="w-full rounded-btn text-sm outline-none mb-3"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
        />
        <div className="flex items-center gap-3">
          <Button green onClick={sendMessage} disabled={sending || !message.trim()}>
            {sending ? 'Odesílám…' : 'Odeslat'}
          </Button>
          {msgSent && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>Odesláno!</span>}
        </div>
      </Card>

      {/* Fotky */}
      {incident.photos && incident.photos.length > 0 && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Fotografie</h4>
          <div className="flex flex-wrap gap-2">
            {incident.photos.map((photo, i) => (
              <a key={i} href={photo} target="_blank" rel="noopener noreferrer">
                <img src={photo} alt={`Foto ${i + 1}`} className="rounded-lg object-cover" style={{ width: 100, height: 100 }} />
              </a>
            ))}
          </div>
        </Card>
      )}

      {/* Timeline */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Timeline</h4>
        <SOSTimeline incidentId={incident.id} />
      </Card>
    </div>
  )
}

function InfoRow({ label, value, mono }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99', minWidth: 55 }}>{label}</span>
      <span className={`text-sm font-medium ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}
