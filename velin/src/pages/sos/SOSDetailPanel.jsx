import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { DECISION_LABELS, SEVERITY_MAP, STATUS_COLORS, TYPE_LABELS, TYPE_ICONS } from './SOSDetailConstants'
import { handleUpdateIncidentStatus, handleSetMotoToService, handleEnsureBookingSwap, handleLoadAvailableMotos, handleAdminInitiateReplacement, handleUpdateReplacementStatus, handleRetriggerSosFab, handleApproveReplacement, handleRejectReplacement } from './SOSDetailHandlers'
import { HeaderCard, NotesCard, WorkflowStepperCard } from './SOSDetailHeaderCard'
import { ActionsCard } from './SOSDetailActionsCard'
import { DecisionCard, MotoSelectorCard, ReplacementOrderCard } from './SOSDetailReplacementCard'
import { DamageCard, NearestServiceCard, CustomerCard, MotoCard, BookingCard, MapCard, AdminNotesCard, ResolutionCard, MessageCard, PhotosCard, TimelineCard } from './SOSDetailInfoCards'

export default function SOSDetailPanel({ incident, onClose, onRefresh }) {
  const [booking, setBooking] = useState(null)
  const [customer, setCustomer] = useState(null)
  const [moto, setMoto] = useState(null)
  const [admins, setAdmins] = useState([])
  const [message, setMessage] = useState('')
  const [adminNotes, setAdminNotes] = useState(incident?.admin_notes || '')
  const [resolution, setResolution] = useState(incident?.resolution || '')
  const [noteText, setNoteText] = useState('')
  const [savingNote, setSavingNote] = useState(false)
  const [incidentNotes, setIncidentNotes] = useState([])
  const [sending, setSending] = useState(false)
  const [msgSent, setMsgSent] = useState(false)
  const [rejectReason, setRejectReason] = useState('')
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [replacementMoto, setReplacementMoto] = useState(null)
  const [motoInService, setMotoInService] = useState(false)
  const [timelineActions, setTimelineActions] = useState([])
  const [policeNumber, setPoliceNumber] = useState(incident?.police_report_number || '')
  const [availableMotos, setAvailableMotos] = useState([])
  const [showMotoSelector, setShowMotoSelector] = useState(false)
  const [swapping, setSwapping] = useState(false)
  const [relatedIncidents, setRelatedIncidents] = useState([])
  const [showLinkPhotos, setShowLinkPhotos] = useState(false)
  const [linkingPhotos, setLinkingPhotos] = useState(false)


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
    loadIncidentNotes()
    loadTimelineActions()
    loadRelatedIncidents()
    setAdminNotes(incident.admin_notes || '')
    setResolution(incident.resolution || '')
    setPoliceNumber(incident.police_report_number || '')
    setShowRejectForm(false)
    setRejectReason('')
    setNoteText('')
  }, [incident?.id])

  async function loadTimelineActions() {
    const { data } = await supabase
      .from('sos_timeline')
      .select('action')
      .eq('incident_id', incident.id)
    setTimelineActions((data || []).map(d => d.action || ''))
  }

  async function loadRelatedIncidents() {
    setRelatedIncidents([])
    if (!incident?.booking_id) return
    const { data } = await supabase.from('sos_incidents')
      .select('id, type, title, description, status, photos, created_at')
      .eq('booking_id', incident.booking_id)
      .neq('id', incident.id)
      .order('created_at', { ascending: false })
    setRelatedIncidents(data || [])
  }

  async function linkPhotosToIncident(targetIncidentId) {
    if (!incident?.photos?.length || linkingPhotos) return
    if (!window.confirm('Přiřadit fotky z této fotodokumentace k vybranému incidentu?\n\nFotky budou zkopírovány (zůstanou i zde).')) return
    setLinkingPhotos(true)
    try {
      const { data: target } = await supabase.from('sos_incidents')
        .select('photos').eq('id', targetIncidentId).single()
      const existingPhotos = target?.photos || []
      const mergedPhotos = [...existingPhotos, ...incident.photos]
      await supabase.from('sos_incidents')
        .update({ photos: mergedPhotos }).eq('id', targetIncidentId)
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: targetIncidentId,
        action: `Přiřazena fotodokumentace (${incident.photos.length} fotek) z informativního hlášení #${incident.id?.slice(0, 8).toUpperCase()}`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Fotky přiřazeny k incidentu #${targetIncidentId?.slice(0, 8).toUpperCase()}`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      setShowLinkPhotos(false)
      alert('✅ Fotky úspěšně přiřazeny!')
      onRefresh?.()
    } catch (e) {
      console.error('[SOS] linkPhotos error:', e)
      alert('❌ Chyba: ' + e.message)
    }
    setLinkingPhotos(false)
  }

  async function loadIncidentNotes() {
    setIncidentNotes([])
    const { data } = await supabase
      .from('sos_timeline')
      .select('*')
      .eq('incident_id', incident.id)
      .eq('action', 'admin_note')
      .order('created_at', { ascending: false })
    setIncidentNotes(data || [])
  }

  async function addNote() {
    if (!noteText.trim()) return
    setSavingNote(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: 'admin_note',
        description: noteText.trim(),
        performed_by: user?.email || 'Admin',
        admin_id: user?.id,
      })
      setNoteText('')
      loadIncidentNotes()
    } catch (e) {
      console.error('[SOSDetail] addNote failed:', e)
    }
    setSavingNote(false)
  }

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
    let foundMoto = false
    if (incident.booking_id || incident.bookings?.id) {
      const bookingId = incident.booking_id || incident.bookings?.id
      const { data: b } = await supabase.from('bookings')
        .select('*, motorcycles(*, branches(name)), profiles(*)')
        .eq('id', bookingId).single()
      if (b) {
        setBooking(b)
        if (b.profiles) setCustomer(b.profiles)
        if (b.motorcycles) {
          setMoto(b.motorcycles); foundMoto = true
        } else if (b.moto_id) {
          // Booking has moto_id but join failed — load motorcycle directly
          const { data: m } = await supabase.from('motorcycles').select('*, branches(name)').eq('id', b.moto_id).single()
          if (m) { setMoto(m); foundMoto = true }
        }
      }
    }
    // Fallback: load moto directly from incident fields
    if (!foundMoto) {
      const directMotoId = incident.moto_id || incident.original_moto_id || incident.replacement_data?.original_moto_id
      if (directMotoId) {
        const { data: m } = await supabase.from('motorcycles').select('*, branches(name)').eq('id', directMotoId).single()
        if (m) { setMoto(m); foundMoto = true }
      }
    }
    if (!customer && incident.user_id) {
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

  async function updateIncidentStatus(newStatus) {
    await handleUpdateIncidentStatus(incident, newStatus, onRefresh)
  }

  async function setMotoToService() {
    await handleSetMotoToService(incident, moto, booking, onRefresh, setMotoInService, loadTimelineActions)
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

  async function ensureBookingSwap() {
    return await handleEnsureBookingSwap(incident)
  }

  async function loadAvailableMotos() {
    await handleLoadAvailableMotos(moto, incident, setAvailableMotos, setShowMotoSelector)
  }

  async function adminInitiateReplacement(selectedMoto) {
    await handleAdminInitiateReplacement(selectedMoto, incident, setSwapping, setShowMotoSelector, onRefresh)
  }

  async function updateReplacementStatus(newStatus) {
    await handleUpdateReplacementStatus(incident, newStatus, ensureBookingSwap, loadTimelineActions, onRefresh)
  }

  async function retriggerSosFab() {
    await handleRetriggerSosFab(incident, onRefresh)
  }

  async function approveReplacement() {
    await handleApproveReplacement(incident, ensureBookingSwap, onRefresh)
  }

  async function rejectReplacement(reason) {
    await handleRejectReplacement(incident, reason, onRefresh)
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

      // admin_messages is handled by bridge trigger (trg_bridge_admin_message)
      // on messages table insert — no direct insert needed here

      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Zpráva odeslána zákazníkovi: "${message.slice(0, 50)}${message.length > 50 ? '...' : ''}"`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      setMessage('')
      setMsgSent(true)
      await loadTimelineActions()
      setTimeout(() => setMsgSent(false), 3000)
    } catch (e) { console.error('[SOS] sendMessage error:', e) }
    setSending(false)
  }

  if (!incident) return null

  const sev = SEVERITY_MAP[incident.severity] || SEVERITY_MAP.medium
  const sc = STATUS_COLORS[incident.status] || STATUS_COLORS.reported
  const displayTitle = incident.title || TYPE_LABELS[incident.type] || 'Incident'
  const isActive = !['resolved', 'closed'].includes(incident.status)
  const isAccident = incident.type?.startsWith('accident')
  const isMajor = incident.type === 'accident_major' || incident.type === 'breakdown_major'
  const isPhotoOnly = incident.type === 'other' && incident.description?.toLowerCase().includes('fotodokumentace')


  return (
    <div className="space-y-4">
      <HeaderCard incident={incident} sev={sev} sc={sc} displayTitle={displayTitle} isActive={isActive} admins={admins} assignAdmin={assignAdmin} updateIncidentStatus={updateIncidentStatus} timelineActions={timelineActions} motoInService={motoInService} moto={moto} />
      <NotesCard incidentNotes={incidentNotes} noteText={noteText} setNoteText={setNoteText} addNote={addNote} savingNote={savingNote} />
      <WorkflowStepperCard incident={incident} timelineActions={timelineActions} motoInService={motoInService} moto={moto} />
      <ActionsCard incident={incident} isActive={isActive} isAccident={isAccident} isMajor={isMajor} motoInService={motoInService} moto={moto} timelineActions={timelineActions} loadTimelineActions={loadTimelineActions} setMotoToService={setMotoToService} onRefresh={onRefresh} policeNumber={policeNumber} setPoliceNumber={setPoliceNumber} saveField={saveField} />
      <DecisionCard incident={incident} isActive={isActive} isMajor={isMajor} isAccident={isAccident} updateDecision={updateDecision} updateFault={updateFault} />
      <MotoSelectorCard incident={incident} isActive={isActive} isMajor={isMajor} showMotoSelector={showMotoSelector} availableMotos={availableMotos} swapping={swapping} loadAvailableMotos={loadAvailableMotos} adminInitiateReplacement={adminInitiateReplacement} setShowMotoSelector={setShowMotoSelector} />
      <ReplacementOrderCard incident={incident} replacementMoto={replacementMoto} showRejectForm={showRejectForm} setShowRejectForm={setShowRejectForm} rejectReason={rejectReason} setRejectReason={setRejectReason} approveReplacement={approveReplacement} rejectReplacement={rejectReplacement} updateReplacementStatus={updateReplacementStatus} retriggerSosFab={retriggerSosFab} ensureBookingSwap={ensureBookingSwap} onRefresh={onRefresh} />
      <DamageCard incident={incident} isAccident={isAccident} />
      <NearestServiceCard incident={incident} saveField={saveField} />
      <CustomerCard customer={customer} incident={incident} />
      <MotoCard moto={moto} />
      <BookingCard booking={booking} />
      <MapCard incident={incident} />
      <AdminNotesCard adminNotes={adminNotes} setAdminNotes={setAdminNotes} saveField={saveField} />
      <ResolutionCard incident={incident} resolution={resolution} setResolution={setResolution} saveField={saveField} />
      <MessageCard incident={incident} message={message} setMessage={setMessage} sending={sending} msgSent={msgSent} sendMessage={sendMessage} />
      <PhotosCard incident={incident} isPhotoOnly={isPhotoOnly} relatedIncidents={relatedIncidents} showLinkPhotos={showLinkPhotos} setShowLinkPhotos={setShowLinkPhotos} linkingPhotos={linkingPhotos} linkPhotosToIncident={linkPhotosToIncident} />
      <TimelineCard incident={incident} />
    </div>
  )
}
