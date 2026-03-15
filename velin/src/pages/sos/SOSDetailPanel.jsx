import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSTimeline from './SOSTimeline'
import SOSWorkflowStepper, { WORKFLOWS, hasTimeline } from './SOSWorkflowStepper'
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
    // Safety: confirm resolve
    if (newStatus === 'resolved') {
      const pendingRepl = ['selecting', 'pending_payment', 'admin_review', 'approved', 'dispatched']
      if (pendingRepl.includes(incident.replacement_status)) {
        if (!window.confirm(`⚠️ POZOR: Tento incident má nedokončenou objednávku náhradní motorky!\n\nStav objednávky: ${incident.replacement_status}\n\nOpravdu chcete označit incident jako vyřešený?`)) return
      }
      if (!window.confirm('Označit incident jako VYŘEŠENÝ?\n\nZákazník nebude moci do incidentu dále přidávat informace.')) return
    }
    const updates = { status: newStatus }
    if (newStatus === 'resolved') {
      const { data: { user } } = await supabase.auth.getUser()
      updates.resolved_at = new Date().toISOString()
      updates.resolved_by = user?.id

      // === SOS RESOLVE: finalize booking swap (same logic as SOSPanel) ===
      const rd = incident?.replacement_data || {}

      // 1. If replacement exists but swap wasn't done yet, do it now
      if (rd.replacement_moto_id && !rd.replacement_booking_id && !incident?.replacement_booking_id) {
        try {
          const swapResult = await supabase.rpc('sos_swap_bookings', {
            p_incident_id: incident.id,
            p_replacement_moto_id: rd.replacement_moto_id,
            p_replacement_model: rd.replacement_model || null,
            p_delivery_fee: rd.delivery_fee || 0,
            p_daily_price: rd.daily_price || 0,
            p_is_free: !rd.customer_fault,
          })
          if (swapResult.data?.success) {
            rd.replacement_booking_id = swapResult.data.replacement_booking_id
            rd.original_booking_id = swapResult.data.original_booking_id
            updates.replacement_data = { ...rd, approved_by_admin: true }
          }
        } catch (e) { console.error('[SOS] swap on resolve:', e) }
      }

      // 2. Mark original booking as completed
      const origBookingId = rd.original_booking_id || incident?.original_booking_id
      if (origBookingId) {
        await supabase.from('bookings').update({
          status: 'completed',
          ended_by_sos: true,
          sos_incident_id: incident.id,
        }).eq('id', origBookingId)
      }

      // 3. Ensure replacement booking is active + paid
      const replBookingId = rd.replacement_booking_id || incident?.replacement_booking_id
      if (replBookingId) {
        await supabase.from('bookings').update({
          status: 'active',
          payment_status: 'paid',
        }).eq('id', replBookingId)
      }

      // 4. If no replacement but incident has a booking, just mark it with SOS flag
      if (!replBookingId && incident?.booking_id) {
        await supabase.from('bookings').update({
          ended_by_sos: true,
          sos_incident_id: incident.id,
        }).eq('id', incident.booking_id)
      }

      // 5. Send confirmation message to customer
      if (incident.user_id) {
        const replModel = rd.replacement_model
        const msgText = replModel
          ? `Váš SOS incident byl vyřešen. Náhradní motorka: ${replModel}. Původní rezervace ukončena, nová aktivní.`
          : 'Váš SOS incident byl vyřešen. Děkujeme za trpělivost.'
        await supabase.from('admin_messages').insert({
          user_id: incident.user_id,
          title: 'SOS vyřešeno',
          message: msgText,
          type: 'sos_response',
        })
      }
    }
    await supabase.from('sos_incidents').update(updates).eq('id', incident.id)
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Stav změněn na: ${STATUS_COLORS[newStatus]?.label || newStatus}`,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function setMotoToService() {
    let motoId = moto?.id || incident?.moto_id || booking?.moto_id || incident?.bookings?.moto_id || incident?.original_moto_id || incident?.replacement_data?.original_moto_id
    // Fallback: try to get moto_id from booking in DB
    if (!motoId && (incident?.booking_id || incident?.original_booking_id)) {
      const bId = incident.original_booking_id || incident.booking_id
      const { data: bk } = await supabase.from('bookings').select('moto_id').eq('id', bId).single()
      if (bk?.moto_id) motoId = bk.moto_id
    }
    if (!motoId) { alert('Chyba: Nelze určit ID motorky. Zkuste obnovit stránku.'); return }
    if (!window.confirm('Přesunout motorku do servisu (maintenance)?\n\nMotorka bude nedostupná pro nové rezervace.')) return
    try {
      const { error } = await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', motoId)
      if (error) { alert('Chyba: ' + error.message); return }
      const { data: { user } } = await supabase.auth.getUser()
      // Create maintenance_log entry (ignore errors — some columns may not exist)
      const sosType = incident?.type || 'other'
      const sosDesc = TYPE_LABELS[sosType] || sosType
      await supabase.from('maintenance_log').insert({
        moto_id: motoId,
        type: 'repair',
        description: `SOS incident: ${sosDesc}${incident?.description ? ' — ' + incident.description.slice(0, 200) : ''}`,
        status: 'in_service',
        performed_by: user?.email || 'Admin',
      }).then(() => {}).catch(() => {})
      // Get moto model for timeline
      let motoModel = moto?.model
      if (!motoModel) {
        const { data: motoData } = await supabase.from('motorcycles').select('model').eq('id', motoId).single()
        motoModel = motoData?.model || motoId.slice(0, 8)
      }
      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Motorka ${motoModel} přesunuta do servisu`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      setMotoInService(true)
      await loadTimelineActions()
      onRefresh?.()
    } catch (e) {
      console.error('[SOS] setMotoToService error:', e)
      alert('Chyba při přesunu do servisu: ' + e.message)
    }
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
    const rd = incident?.replacement_data || {}
    const hasSwap = (rd.original_booking_id && rd.replacement_booking_id) || (incident?.original_booking_id && incident?.replacement_booking_id)
    if (hasSwap || !rd.replacement_moto_id) return rd
    // Swap hasn't happened yet — trigger it now
    try {
      const swapResult = await supabase.rpc('sos_swap_bookings', {
        p_incident_id: incident.id,
        p_replacement_moto_id: rd.replacement_moto_id,
        p_replacement_model: rd.replacement_model || null,
        p_delivery_fee: rd.delivery_fee || 0,
        p_daily_price: rd.daily_price || 0,
        p_is_free: !rd.customer_fault,
      })
      if (swapResult.data?.success) {
        const updatedRd = {
          ...rd,
          original_booking_id: swapResult.data.original_booking_id,
          replacement_booking_id: swapResult.data.replacement_booking_id,
          original_end_date: swapResult.data.original_end_date,
        }
        await supabase.from('sos_incidents').update({ replacement_data: updatedRd }).eq('id', incident.id)
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('sos_timeline').insert({
          incident_id: incident.id,
          action: `Rezervace automaticky přepnuta (admin akce). Původní: #${swapResult.data.original_booking_id?.slice(-8)}, nová: #${swapResult.data.replacement_booking_id?.slice(-8)}`,
          performed_by: user?.email || 'Admin', admin_id: user?.id,
        })
        return updatedRd
      } else {
        console.error('[SOS] ensureBookingSwap RPC failed:', swapResult.data?.error || swapResult.error?.message)
      }
    } catch (e) {
      console.error('[SOS] ensureBookingSwap exception:', e)
    }
    return rd
  }

  async function loadAvailableMotos() {
    const { data } = await supabase.from('motorcycles')
      .select('id, model, spz, branch_id, branches(name), price_weekday, status, image_url, license_required')
      .eq('status', 'active')
    const currentMotoId = moto?.id || incident?.moto_id
    setAvailableMotos((data || []).filter(m => m.id !== currentMotoId))
    setShowMotoSelector(true)
  }

  async function adminInitiateReplacement(selectedMoto) {
    const isFree = !incident.customer_fault
    const dailyPrice = selectedMoto.price_weekday || 0
    if (!window.confirm(`Přiřadit náhradní motorku?\n\n🏍️ ${selectedMoto.model} (${selectedMoto.spz})\n💰 ${isFree ? 'ZDARMA' : dailyPrice + ' Kč/den'}\n\nBude vytvořena nová rezervace a původní ukončena.`)) return
    setSwapping(true)
    try {
      const swapResult = await supabase.rpc('sos_swap_bookings', {
        p_incident_id: incident.id,
        p_replacement_moto_id: selectedMoto.id,
        p_replacement_model: selectedMoto.model,
        p_delivery_fee: 0,
        p_daily_price: dailyPrice,
        p_is_free: isFree,
      })
      if (swapResult.data?.success) {
        const rd = {
          replacement_moto_id: selectedMoto.id,
          replacement_model: selectedMoto.model,
          daily_price: dailyPrice,
          delivery_fee: 0,
          payment_status: isFree ? 'free' : 'pending',
          payment_amount: 0,
          customer_fault: !!incident.customer_fault,
          original_booking_id: swapResult.data.original_booking_id,
          replacement_booking_id: swapResult.data.replacement_booking_id,
          original_end_date: swapResult.data.original_end_date,
          remaining_days: swapResult.data.remaining_days,
          admin_initiated: true,
          customer_confirmed_at: new Date().toISOString(),
        }
        await supabase.from('sos_incidents').update({
          replacement_data: rd,
          replacement_moto_id: selectedMoto.id,
          replacement_status: 'approved',
          customer_decision: 'replacement_moto',
        }).eq('id', incident.id)
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('sos_timeline').insert({
          incident_id: incident.id,
          action: `Admin přiřadil náhradní motorku: ${selectedMoto.model} (${selectedMoto.spz}). Rezervace přepnuta.`,
          performed_by: user?.email || 'Admin', admin_id: user?.id,
        })
        setShowMotoSelector(false)
        alert(`✅ Náhradní motorka přiřazena!\n\nNová rezervace: #${swapResult.data.replacement_booking_id?.slice(-8)}`)
      } else {
        alert('❌ Swap selhal: ' + (swapResult.data?.error || swapResult.error?.message || 'neznámá chyba'))
      }
    } catch (e) {
      console.error('[SOS] adminInitiateReplacement:', e)
      alert('❌ Chyba: ' + e.message)
    }
    setSwapping(false)
    onRefresh?.()
  }

  async function updateReplacementStatus(newStatus) {
    // SAFETY: Confirm dispatch/delivery status changes
    const label = REPLACEMENT_STATUS_LABELS[newStatus] || newStatus
    const rd = incident.replacement_data || {}
    if (newStatus === 'dispatched') {
      if (!window.confirm('Potvrdit že náhradní motorka je na cestě k zákazníkovi?\n\nZákazník bude informován v aplikaci.')) return
    }
    if (newStatus === 'delivered') {
      if (!window.confirm('Potvrdit doručení náhradní motorky zákazníkovi?\n\nPůvodní motorka bude odvezena do servisu.')) return
    }
    // Auto-trigger booking swap if it hasn't happened yet
    const rd = incident?.replacement_data || {}
    const hasSwap = (rd.original_booking_id && rd.replacement_booking_id) || (incident?.original_booking_id && incident?.replacement_booking_id)
    if (!hasSwap && rd.replacement_moto_id) {
      await ensureBookingSwap()
    }
    await debugAction('sos.updateReplacementStatus', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ replacement_status: newStatus }).eq('id', incident.id)
    , { incident_id: incident.id, replacement_status: newStatus })
    const { data: { user } } = await supabase.auth.getUser()

    // Send notification to customer app
    if (incident.user_id && (newStatus === 'dispatched' || newStatus === 'delivered')) {
      const notifMsg = newStatus === 'dispatched'
        ? `Vaše náhradní motorka ${rd.replacement_model || ''} je na cestě k vám. Předpokládaná adresa: ${rd.delivery_address || ''}, ${rd.delivery_city || ''}.`
        : `Vaše náhradní motorka ${rd.replacement_model || ''} byla úspěšně doručena. Šťastnou cestu!`
      await supabase.from('admin_messages').insert({
        user_id: incident.user_id,
        title: newStatus === 'dispatched' ? 'Náhradní motorka na cestě' : 'Náhradní motorka doručena',
        message: notifMsg,
        type: 'replacement',
      })
    }

    // Timeline entries
    let timelineAction = `Náhradní moto: ${label}`
    if (newStatus === 'dispatched') {
      timelineAction = `Náhradní motorka ${rd.replacement_model || ''} odeslána k zákazníkovi`
    }
    if (newStatus === 'delivered') {
      timelineAction = `Náhradní motorka ${rd.replacement_model || ''} doručena zákazníkovi, původní motorka odvezena`
    }
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: timelineAction,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    await loadTimelineActions()
    onRefresh?.()
  }

  async function retriggerSosFab() {
    if (!window.confirm('Znovu vyvolat FAB banner v aplikaci zákazníka?\n\nZákazník uvidí banner "SOS dokončit" i pokud ho dříve zavřel.')) return
    const rd = { ...(incident.replacement_data || {}), fab_retrigger_at: new Date().toISOString() }
    await supabase.from('sos_incidents').update({ replacement_data: rd }).eq('id', incident.id)
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: 'Admin znovu vyvolal FAB banner pro výběr náhradní motorky',
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

    // Info o swap bookings
    const hasSwap = rd.original_booking_id && rd.replacement_booking_id
    const swapInfo = hasSwap
      ? '\n\n✅ Rezervace již přepnuty automaticky.'
      : '\n\n🔄 Rezervace budou automaticky přepnuty (stará ukončena, nová vytvořena).'

    // SAFETY: Potvrzení schválení
    if (!window.confirm(`Schválit objednávku náhradní motorky?\n\n🏍️ ${rd.replacement_model || '?'}\n📍 ${rd.delivery_address || '?'}, ${rd.delivery_city || '?'}\n💰 ${rd.payment_amount || 0} Kč (${rd.payment_status === 'free' ? 'zdarma' : rd.payment_status || '?'})${swapInfo}\n\nPo schválení bude motorka připravena k přistavení.`)) {
      return
    }

    // If bookings haven't been swapped yet (e.g. RPC failed during customer flow), do it now
    if (!hasSwap && rd.replacement_moto_id) {
      const swapRd = await ensureBookingSwap()
      if (swapRd.original_booking_id) {
        rd.original_booking_id = swapRd.original_booking_id
        rd.replacement_booking_id = swapRd.replacement_booking_id
        rd.original_end_date = swapRd.original_end_date
      }
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
      description: `Adresa: ${rd.delivery_address || '?'}, ${rd.delivery_city || '?'}. Částka: ${rd.payment_amount || '?'} Kč (${rd.payment_status === 'free' ? 'zdarma' : 'zaplaceno'}).` +
        (rd.original_booking_id ? ` Původní rez.: #${rd.original_booking_id.slice(-8)}, nová: #${rd.replacement_booking_id?.slice(-8) || '?'}` : ''),
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
                <span className="text-sm font-bold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
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
            <button onClick={onClose} className="text-sm font-bold cursor-pointer"
              style={{ color: '#1a2e22', background: 'none', border: 'none' }}>✕</button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 text-sm">
          <InfoRow label="ID" value={incident.id?.slice(0, 8)} mono />
          <InfoRow label="Nahlášeno" value={incident.created_at ? new Date(incident.created_at).toLocaleString('cs-CZ') : '—'} />
          <InfoRow label="Kontakt" value={incident.contact_phone || customer?.phone || incident.profiles?.phone} />
          {incident.moto_rideable !== null && incident.moto_rideable !== undefined && (
            <InfoRow label="Pojízdná" value={incident.moto_rideable ? 'Ano' : 'NE — nepojízdná'} />
          )}
        </div>

        {/* Popis od zákazníka */}
        {incident.description && (
          <div className="mt-3 rounded-lg text-sm" style={{
            padding: '10px 14px', background: '#f8fcfa', color: '#1a2e22',
            borderLeft: '3px solid #d4e8e0', lineHeight: 1.6,
          }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
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
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{
              color: incident.customer_fault ? '#dc2626' : '#1a8a18'
            }}>
              Preference zákazníka
            </div>
            <div className="flex flex-wrap gap-2">
              {incident.customer_decision && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px',
                  background: incident.customer_fault ? '#fee2e2' : '#dcfce7',
                  color: incident.customer_fault ? '#b91c1c' : '#15803d',
                }}>
                  {DECISION_LABELS[incident.customer_decision] || incident.customer_decision}
                </span>
              )}
              {incident.customer_fault === true && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px', background: '#fee2e2', color: '#b91c1c',
                }}>
                  ⚠️ Zavinil zákazník (platí)
                </span>
              )}
              {incident.customer_fault === false && (
                <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                  padding: '4px 10px', background: '#dcfce7', color: '#15803d',
                }}>
                  Cizí zavinění (zdarma)
                </span>
              )}
              {incident.moto_rideable === false && (
                <>
                  <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                    padding: '4px 10px', background: '#fef3c7', color: '#b45309',
                  }}>
                    Motorka nepojízdná
                  </span>
                  {!motoInService && moto?.status !== 'maintenance' && (
                    <button onClick={setMotoToService} className="inline-block rounded-btn text-sm font-extrabold cursor-pointer" style={{
                      padding: '4px 10px', background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5',
                    }}>
                      🔧 Přesunout do servisu
                    </button>
                  )}
                  {(motoInService || moto?.status === 'maintenance') && (
                    <span className="inline-block rounded-btn text-sm font-extrabold" style={{
                      padding: '4px 10px', background: '#dcfce7', color: '#15803d',
                    }}>
                      ✅ V servisu
                    </span>
                  )}
                </>
              )}
            </div>
            {incident.replacement_status && (
              <div className="mt-2">
                <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{
                  padding: '3px 8px',
                  ...(REPLACEMENT_STATUS_COLORS[incident.replacement_status] || { bg: '#f1faf7', color: '#1a2e22' }),
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
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Přiřadit:</span>
          <select value={incident.assigned_to || ''} onChange={e => assignAdmin(e.target.value)}
            className="rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '4px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="">Nepřiřazeno</option>
            {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>

        {/* Status forward buttons */}
        {isActive && (() => {
          // Check if all workflow steps (except resolve itself) are complete
          const workflow = WORKFLOWS[incident?.type]
          let allPreResolveComplete = true
          if (workflow) {
            const enriched = {
              ...incident,
              _timelineActions: timelineActions || [],
              _motoInService: motoInService || moto?.status === 'maintenance' || false,
            }
            const activeSteps = workflow.steps.filter(s => s.id !== 'resolve' && (!s.skip || !s.skip(enriched)))
            allPreResolveComplete = activeSteps.every(s => s.check(enriched))
          }
          return (
            <div className="mt-3 flex flex-wrap gap-2">
              {incident.status === 'reported' && (
                <button onClick={() => updateIncidentStatus('acknowledged')}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{ padding: '8px 16px', background: '#fef3c7', color: '#b45309' }}>
                  Potvrdit příjem
                </button>
              )}
              {(incident.status === 'reported' || incident.status === 'acknowledged') && (
                <button onClick={() => updateIncidentStatus('in_progress')}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{ padding: '8px 16px', background: '#dbeafe', color: '#2563eb' }}>
                  Začít řešit
                </button>
              )}
              {incident.status !== 'resolved' && (
                <button
                  onClick={allPreResolveComplete ? () => updateIncidentStatus('resolved') : undefined}
                  disabled={!allPreResolveComplete}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '8px 16px',
                    background: allPreResolveComplete ? '#dcfce7' : '#e5e7eb',
                    color: allPreResolveComplete ? '#1a8a18' : '#9ca3af',
                    cursor: allPreResolveComplete ? 'pointer' : 'not-allowed',
                    opacity: allPreResolveComplete ? 1 : 0.6,
                  }}>
                  {allPreResolveComplete ? 'Vyřešeno' : 'Vyřešeno (dokončete kroky)'}
                </button>
              )}
            </div>
          )
        })()}
      </Card>

      {/* === POZNÁMKY K INCIDENTU — vlastní karta pro viditelnost === */}
      <Card>
        <div style={{
          padding: '2px',
          background: '#fffbeb',
          border: '2px solid #fbbf24',
          borderRadius: 8,
        }}>
          <div style={{ padding: '12px 14px' }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>
              Poznámky k incidentu (tel. komunikace apod.)
            </div>
            {incidentNotes.length > 0 && (
              <div className="space-y-2 mb-3">
                {incidentNotes.map(n => (
                  <div key={n.id} className="rounded-lg text-sm" style={{
                    padding: '8px 10px', background: '#fff', border: '1px solid #fde68a', lineHeight: 1.6,
                  }}>
                    <div style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{n.description}</div>
                    <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                      {n.created_at ? new Date(n.created_at).toLocaleString('cs-CZ') : ''}
                      {n.performed_by && ` · ${n.performed_by}`}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {incidentNotes.length === 0 && (
              <div className="text-sm mb-3" style={{ color: '#92400e', fontStyle: 'italic' }}>
                Zatím žádné poznámky.
              </div>
            )}
            <textarea value={noteText} onChange={e => setNoteText(e.target.value)}
              rows={2} placeholder="Napište poznámku (např. z telefonátu se zákazníkem)…"
              className="w-full rounded-btn text-sm outline-none mb-2"
              style={{ padding: '8px 12px', background: '#fff', border: '1px solid #fde68a', resize: 'vertical' }}
            />
            <Button onClick={addNote} disabled={savingNote || !noteText.trim()}
              style={{ background: '#fbbf24', color: '#78350f', fontSize: 13, padding: '6px 16px' }}>
              {savingNote ? 'Ukládám…' : 'Přidat poznámku'}
            </Button>
          </div>
        </div>
      </Card>

      {/* === WORKFLOW STEPPER === */}
      <SOSWorkflowStepper
        incident={incident}
        timelineActions={timelineActions}
        motoInService={motoInService || moto?.status === 'maintenance'}
      />

      {/* === AKČNÍ PANEL — kontextová tlačítka dle typu === */}
      {isActive && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wider mb-3" style={{ color: '#1a2e22' }}>
            Akce pro tento incident
          </h4>
          <div className="flex flex-wrap gap-2">
            {/* Kontaktovat zákazníka */}
            <WorkflowBtn
              label="Zákazník kontaktován"
              icon="📞"
              done={timelineActions.some(a => a.toLowerCase().includes('kontaktován') || a.toLowerCase().includes('zpráva odeslána'))}
              onClick={async () => {
                const { data: { user } } = await supabase.auth.getUser()
                await supabase.from('sos_timeline').insert({
                  incident_id: incident.id,
                  action: 'Zákazník telefonicky kontaktován',
                  performed_by: user?.email || 'Admin', admin_id: user?.id,
                })
                await loadTimelineActions()
                onRefresh?.()
              }}
            />

            {/* Odtah — pro těžké nehody a poruchy */}
            {(incident.type === 'accident_major' || incident.type === 'breakdown_major' || incident.type === 'theft') && (
              <WorkflowBtn
                label="Odeslat odtah"
                icon="🚛"
                done={!!incident.tow_requested || timelineActions.some(a => a.toLowerCase().includes('dtah'))}
                onClick={async () => {
                  if (!window.confirm('Potvrdit objednání odtahové služby?')) return
                  await supabase.from('sos_incidents').update({ tow_requested: true }).eq('id', incident.id)
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: 'Odtahová služba objednána — motorka bude odtažena do servisu',
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}

            {/* Policie — pro krádeže a nehody */}
            {(incident.type === 'theft' || isAccident) && (
              <WorkflowBtn
                label="Policie kontaktována"
                icon="🚔"
                done={!!incident.police_report_number || timelineActions.some(a => a.toLowerCase().includes('olicie'))}
                onClick={async () => {
                  const num = window.prompt('Zadejte číslo policejního spisu (nebo nechte prázdné):')
                  if (num === null) return
                  const updates = {}
                  if (num.trim()) updates.police_report_number = num.trim()
                  if (Object.keys(updates).length > 0) {
                    await supabase.from('sos_incidents').update(updates).eq('id', incident.id)
                    setPoliceNumber(num.trim())
                  }
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: `Policie ČR kontaktována${num.trim() ? `, číslo spisu: ${num.trim()}` : ''}`,
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}

            {/* Pojišťovna — pro nehody */}
            {isAccident && (() => {
              const insuranceDone = timelineActions.some(a => a.toLowerCase().includes('ojišťovn'))
              const insuranceSkipped = timelineActions.some(a => a.toLowerCase().includes('ojišťovna přeskočen'))
              if (insuranceSkipped) return (
                <WorkflowBtn label="Pojišťovna přeskočena" icon="⏭️" done={true} onClick={() => {}} />
              )
              return (
                <>
                  <WorkflowBtn
                    label="Kontaktovat pojišťovnu"
                    icon="🏦"
                    done={insuranceDone}
                    onClick={async () => {
                      if (!window.confirm('Potvrdit kontaktování pojišťovny?')) return
                      const { data: { user } } = await supabase.auth.getUser()
                      await supabase.from('sos_timeline').insert({
                        incident_id: incident.id,
                        action: 'Pojišťovna kontaktována, hlášena škodná událost',
                        performed_by: user?.email || 'Admin', admin_id: user?.id,
                      })
                      await loadTimelineActions()
                      onRefresh?.()
                    }}
                  />
                  {!insuranceDone && (
                    <WorkflowBtn
                      label="Přeskočit pojišťovnu"
                      icon="⏭️"
                      done={false}
                      onClick={async () => {
                        if (!window.confirm('Přeskočit kontaktování pojišťovny?\n\nTento krok bude přeskočen v postupu řešení.')) return
                        const { data: { user } } = await supabase.auth.getUser()
                        await supabase.from('sos_timeline').insert({
                          incident_id: incident.id,
                          action: 'Pojišťovna přeskočena — není potřeba kontaktovat',
                          performed_by: user?.email || 'Admin', admin_id: user?.id,
                        })
                        await loadTimelineActions()
                        onRefresh?.()
                      }}
                    />
                  )}
                </>
              )
            })()}

            {/* Motorka do servisu — pro těžké typy */}
            {(isMajor || incident.type === 'theft') && !motoInService && moto?.status !== 'maintenance' && (
              <WorkflowBtn
                label="Motorka do servisu"
                icon="🔧"
                done={false}
                onClick={setMotoToService}
              />
            )}
            {(isMajor || incident.type === 'theft') && (motoInService || moto?.status === 'maintenance') && (
              <WorkflowBtn label="V servisu" icon="✅" done={true} onClick={() => {}} />
            )}

            {/* Servis navigace — pro lehké poruchy */}
            {(incident.type === 'breakdown_minor' || incident.type === 'defect_question') && (
              <WorkflowBtn
                label="Navigovat na servis"
                icon="🗺️"
                done={!!incident.nearest_service_name || timelineActions.some(a => a.toLowerCase().includes('servis'))}
                onClick={async () => {
                  const { data: { user } } = await supabase.auth.getUser()
                  await supabase.from('sos_timeline').insert({
                    incident_id: incident.id,
                    action: 'Zákazník navigován na nejbližší servis',
                    performed_by: user?.email || 'Admin', admin_id: user?.id,
                  })
                  await loadTimelineActions()
                  onRefresh?.()
                }}
              />
            )}
          </div>

          {/* Číslo policejního spisu — inline input */}
          {(incident.type === 'theft' || isAccident) && (
            <div className="flex items-center gap-2 mt-3">
              <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>
                Číslo PČR spisu:
              </span>
              <input type="text" value={policeNumber} onChange={e => setPoliceNumber(e.target.value)}
                placeholder="KRPX-12345/ČJ-2026"
                onBlur={() => saveField('police_report_number', policeNumber)}
                className="flex-1 rounded-btn text-sm outline-none font-mono"
                style={{ padding: '5px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              />
            </div>
          )}
        </Card>
      )}

      {/* Rozhodnutí zákazníka (u nepojízdných) */}
      {isActive && isMajor && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
            Rozhodnutí zákazníka
          </h4>
          <div className="flex flex-wrap gap-2 mb-3">
            {Object.entries(DECISION_LABELS).map(([key, label]) => (
              <button key={key} onClick={() => updateDecision(key)}
                className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                style={{
                  padding: '6px 14px',
                  background: incident.customer_decision === key ? '#1a2e22' : '#f1faf7',
                  color: incident.customer_decision === key ? '#74FB71' : '#1a2e22',
                }}>
                {label}
              </button>
            ))}
          </div>

          {/* Zavinění (u nehod) */}
          {isAccident && (
            <div className="mt-3">
              <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Zavinění: </span>
              <div className="flex gap-2 mt-1">
                <button onClick={() => updateFault(true)}
                  className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === true ? '#dc2626' : '#f1faf7',
                    color: incident.customer_fault === true ? '#fff' : '#1a2e22',
                  }}>
                  Zákazník (platí)
                </button>
                <button onClick={() => updateFault(false)}
                  className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === false ? '#1a8a18' : '#f1faf7',
                    color: incident.customer_fault === false ? '#fff' : '#1a2e22',
                  }}>
                  Cizí zavinění
                </button>
              </div>
            </div>
          )}
        </Card>
      )}

      {/* Admin: Přiřadit náhradní motorku (pokud zákazník neobjednal z appky) */}
      {isActive && isMajor && incident.customer_decision === 'replacement_moto' && !incident.replacement_data?.replacement_moto_id && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#2563eb' }}>
            Přiřadit náhradní motorku
          </h4>
          <div className="rounded-lg text-sm mb-3" style={{
            padding: '10px 14px', background: '#eff6ff', color: '#1e40af', border: '1px solid #93c5fd',
          }}>
            Zákazník si zatím nevybral náhradní motorku z aplikace. Můžete ji přiřadit ručně.
          </div>
          {!showMotoSelector ? (
            <button onClick={loadAvailableMotos}
              className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
              style={{ padding: '8px 16px', background: '#2563eb', color: '#fff' }}>
              🏍️ Vybrat náhradní motorku
            </button>
          ) : (
            <div>
              <div className="text-sm font-extrabold mb-2" style={{ color: '#1a2e22' }}>
                Dostupné motorky ({availableMotos.length}):
              </div>
              <div className="space-y-2" style={{ maxHeight: 300, overflowY: 'auto' }}>
                {availableMotos.map(m => (
                  <div key={m.id} className="flex items-center justify-between rounded-lg cursor-pointer"
                    style={{ padding: '8px 12px', background: '#f8fcfa', border: '1px solid #d4e8e0' }}
                    onClick={() => !swapping && adminInitiateReplacement(m)}>
                    <div>
                      <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{m.model}</div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>
                        {m.spz} · {m.branches?.name || '—'} · {m.price_weekday || '?'} Kč/den
                      </div>
                    </div>
                    <span className="text-sm font-extrabold" style={{ color: '#2563eb' }}>
                      {swapping ? '⏳' : 'Vybrat →'}
                    </span>
                  </div>
                ))}
              </div>
              <button onClick={() => setShowMotoSelector(false)}
                className="mt-2 rounded-btn text-sm font-extrabold cursor-pointer border-none"
                style={{ padding: '6px 12px', background: '#f1faf7', color: '#1a2e22' }}>
                Zrušit
              </button>
            </div>
          )}
        </Card>
      )}

      {/* Objednávka náhradní motorky (zákazník zavinil) */}
      {incident.replacement_data && (
        <Card>
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#dc2626' }}>
              Objednávka náhradní motorky
            </h4>
            {incident.replacement_status && (
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase" style={{
                padding: '2px 7px',
                background: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).bg || '#f1faf7',
                color: (REPLACEMENT_STATUS_COLORS[incident.replacement_status] || {}).color || '#1a2e22',
              }}>
                {REPLACEMENT_STATUS_LABELS[incident.replacement_status] || incident.replacement_status}
              </span>
            )}
          </div>

          {/* Detaily objednávky */}
          <div className="rounded-lg text-sm" style={{
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
              <div className="mt-2 rounded-lg text-sm font-extrabold" style={{
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
                <div className="text-sm font-bold mt-1" style={{ color: '#dc2626' }}>
                  ⚠️ Zavinil zákazník — platí poplatek
                </div>
              )}
              {incident.replacement_data.customer_confirmed_at && (
                <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                  Objednáno: {new Date(incident.replacement_data.customer_confirmed_at).toLocaleString('cs-CZ')}
                </div>
              )}
            </div>
          </div>

          {/* Booking swap info */}
          {(incident.replacement_data.original_booking_id || incident.original_booking_id) && (
            <div className="mt-3 rounded-lg text-sm" style={{
              padding: '12px', background: '#f0fdf4', border: '1px solid #86efac', lineHeight: 1.8,
            }}>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>
                Přepnutí rezervace
              </div>
              <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                <InfoRow label="Původní rez." value={`#${(incident.replacement_data.original_booking_id || incident.original_booking_id || '').slice(-8)}`} mono />
                <InfoRow label="Nová rez." value={`#${(incident.replacement_data.replacement_booking_id || incident.replacement_booking_id || '').slice(-8)}`} mono />
                {incident.replacement_data.original_end_date && (
                  <InfoRow label="Pův. konec" value={new Date(incident.replacement_data.original_end_date).toLocaleDateString('cs-CZ')} />
                )}
                {incident.replacement_data.remaining_days && (
                  <InfoRow label="Zbývá dní" value={`${incident.replacement_data.remaining_days}`} />
                )}
              </div>
              <div className="text-sm mt-1" style={{ color: '#166534' }}>
                ✅ Původní rezervace ukončena ke dni incidentu. Nová rezervace s náhradní motorkou aktivní do konce původního termínu.
              </div>
            </div>
          )}

          {/* WARNING: Swap neproběhl — manuální tlačítko */}
          {incident.replacement_data?.replacement_moto_id &&
            !(incident.replacement_data.original_booking_id || incident.original_booking_id) &&
            !(incident.replacement_data.replacement_booking_id || incident.replacement_booking_id) && (
            <div className="mt-3 rounded-lg text-sm" style={{
              padding: '12px', background: '#fef2f2', border: '2px solid #dc2626', lineHeight: 1.8,
            }}>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#dc2626' }}>
                ⚠️ Rezervace NEBYLA přepnuta!
              </div>
              <div style={{ color: '#b91c1c' }}>
                Zákazník objednal náhradní motorku, ale automatický swap selhal. Původní rezervace je stále aktivní a nová nebyla vytvořena.
              </div>
              <button onClick={async () => {
                if (!window.confirm('Provést swap rezervací nyní?\n\nPůvodní rezervace bude ukončena a vytvoří se nová s náhradní motorkou.')) return
                const result = await ensureBookingSwap()
                if (result?.replacement_booking_id) {
                  alert('✅ Swap proveden úspěšně! Nová rezervace: #' + result.replacement_booking_id.slice(-8))
                } else {
                  alert('❌ Swap se nepodařil. Zkontrolujte konzoli pro detaily.')
                }
                onRefresh?.()
              }}
                className="mt-2 rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                style={{ padding: '8px 16px', background: '#dc2626', color: '#fff' }}>
                🔄 Provést swap rezervací nyní
              </button>
            </div>
          )}

          {/* Akce: Znovu vyvolat FAB v appce zákazníka */}
          {(incident.replacement_status === 'selecting' || incident.replacement_status === 'pending_payment') && (
            <div className="mt-3 flex gap-2">
              <button onClick={retriggerSosFab}
                className="flex-1 rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                style={{ padding: '8px 12px', background: '#d97706', color: '#fff' }}>
                🔔 Znovu vyvolat FAB v appce
              </button>
            </div>
          )}

          {/* Akce: Schválit / Zamítnout */}
          {incident.replacement_status === 'admin_review' && (
            <div className="mt-3">
              {!showRejectForm ? (
                <div className="flex gap-2">
                  <button onClick={approveReplacement}
                    className="flex-1 rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                    style={{ padding: '10px 16px', background: '#1a8a18', color: '#fff' }}>
                    Schválit objednávku
                  </button>
                  <button onClick={() => setShowRejectForm(true)}
                    className="flex-1 rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                    style={{ padding: '10px 16px', background: '#dc2626', color: '#fff' }}>
                    Zamítnout
                  </button>
                </div>
              ) : (
                <div>
                  <textarea value={rejectReason} onChange={e => setRejectReason(e.target.value)}
                    rows={2} placeholder="Důvod zamítnutí…"
                    className="w-full rounded-btn text-sm outline-none mb-2"
                    style={{ padding: '8px 10px', background: '#fff', border: '1px solid #fca5a5', resize: 'vertical' }}
                  />
                  <div className="flex gap-2">
                    <button onClick={() => { rejectReplacement(rejectReason); setShowRejectForm(false) }}
                      className="flex-1 rounded-btn text-sm font-extrabold cursor-pointer border-none"
                      style={{ padding: '8px 12px', background: '#dc2626', color: '#fff' }}>
                      Potvrdit zamítnutí
                    </button>
                    <button onClick={() => setShowRejectForm(false)}
                      className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
                      style={{ padding: '8px 12px', background: '#f1faf7', color: '#1a2e22' }}>
                      Zrušit
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Akce: Změnit status přistavení */}
          {incident.replacement_status === 'approved' && (
            <div className="mt-3 flex gap-2">
              <button onClick={() => updateReplacementStatus('dispatched')}
                className="flex-1 rounded-btn text-sm font-extrabold cursor-pointer border-none"
                style={{ padding: '8px 12px', background: '#2563eb', color: '#fff' }}>
                Motorka na cestě
              </button>
            </div>
          )}
          {incident.replacement_status === 'dispatched' && (
            <div className="mt-3 flex gap-2">
              <button onClick={() => updateReplacementStatus('delivered')}
                className="flex-1 rounded-btn text-sm font-extrabold cursor-pointer border-none"
                style={{ padding: '8px 12px', background: '#1a8a18', color: '#fff' }}>
                Doručeno zákazníkovi
              </button>
            </div>
          )}

          {/* Info o zamítnutí */}
          {incident.replacement_status === 'rejected' && incident.replacement_data.rejection_reason && (
            <div className="mt-3 rounded-lg text-sm" style={{
              padding: '8px 12px', background: '#fee2e2', color: '#b91c1c', fontWeight: 600,
            }}>
              Důvod zamítnutí: {incident.replacement_data.rejection_reason}
            </div>
          )}
        </Card>
      )}

      {/* Poškození motorky — pouze zobrazení pokud už bylo nastaveno (posouzení dělá servis) */}
      {isAccident && incident.damage_severity && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poškození motorky</h4>
          <span className="inline-block rounded-btn text-sm font-extrabold" style={{
            padding: '5px 12px', background: '#1a2e22', color: '#74FB71',
          }}>
            {DAMAGE_LABELS[incident.damage_severity] || incident.damage_severity}
          </span>
          {incident.damage_description && (
            <div className="text-sm rounded-lg mt-2" style={{ padding: '6px 10px', background: '#f8fcfa', color: '#1a2e22' }}>
              {incident.damage_description}
            </div>
          )}
        </Card>
      )}

      {/* Nejbližší servis (pro poruchy a dotazy) */}
      {(incident.type === 'breakdown_minor' || incident.type === 'breakdown_major' || incident.type === 'defect_question') && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Nejbližší servis</h4>
          <div className="grid grid-cols-1 gap-2">
            <input type="text" placeholder="Název servisu" defaultValue={incident.nearest_service_name || ''}
              onBlur={e => saveField('nearest_service_name', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Adresa servisu" defaultValue={incident.nearest_service_address || ''}
              onBlur={e => saveField('nearest_service_address', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Telefon servisu" defaultValue={incident.nearest_service_phone || ''}
              onBlur={e => saveField('nearest_service_phone', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          </div>
        </Card>
      )}

      {/* Zákazník */}
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Zákazník</h4>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <InfoRow label="Jméno" value={customer?.full_name || incident.profiles?.full_name} />
          <InfoRow label="Telefon" value={customer?.phone || incident.profiles?.phone} />
          <InfoRow label="Email" value={customer?.email || incident.profiles?.email} />
          <InfoRow label="Město" value={customer?.city} />
        </div>
      </Card>

      {/* Motorka */}
      {moto && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Motorka</h4>
          <div className="grid grid-cols-2 gap-2 text-sm">
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
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Rezervace</h4>
          <div className="grid grid-cols-2 gap-2 text-sm">
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
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poloha zákazníka</h4>
          {incident.address && (
            <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>{incident.address}</div>
          )}
          <div className="rounded-lg overflow-hidden" style={{ height: 200 }}>
            <iframe title="Poloha" width="100%" height="200" frameBorder="0" style={{ border: 0 }}
              src={`https://www.openstreetmap.org/export/embed.html?bbox=${incident.longitude - 0.01},${incident.latitude - 0.01},${incident.longitude + 0.01},${incident.latitude + 0.01}&layer=mapnik&marker=${incident.latitude},${incident.longitude}`}
            />
          </div>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>
              {Number(incident.latitude).toFixed(6)}, {Number(incident.longitude).toFixed(6)}
            </span>
            <a href={`https://www.google.com/maps?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#1a8a18' }}>
              Google Maps
            </a>
            <a href={`https://mapy.cz/zakladni?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#2563eb' }}>
              Mapy.cz
            </a>
            <a href={`https://www.google.com/maps/dir/?api=1&destination=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#b45309' }}>
              Navigovat
            </a>
          </div>
        </Card>
      )}

      {/* Poznámky admina */}
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poznámky admina</h4>
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
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Řešení incidentu</h4>
          <textarea value={resolution} onChange={e => setResolution(e.target.value)}
            rows={3} placeholder="Jak byl incident vyřešen…"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
            onBlur={() => saveField('resolution', resolution)}
          />
          {incident.resolved_at && (
            <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
              Vyřešeno: {new Date(incident.resolved_at).toLocaleString('cs-CZ')}
            </div>
          )}
        </Card>
      )}

      {/* Odeslat zprávu */}
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Odeslat zprávu zákazníkovi</h4>
        {['accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other'].includes(incident.type) && (
          <div className="rounded-lg text-sm font-semibold mb-3" style={{ padding: '8px 12px', background: '#f0fdf4', color: '#1a8a18', border: '1px solid #86efac' }}>
            Automatická zpráva odeslána: &quot;Děkujeme za nahlášení, šťastnou cestu!&quot; — další zprávu odesílejte jen pokud je potřeba.
          </div>
        )}
        <textarea value={message} onChange={e => setMessage(e.target.value)}
          rows={3} placeholder="Napište zprávu zákazníkovi…"
          className="w-full rounded-btn text-sm outline-none mb-3"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
        />
        <div className="flex items-center gap-3">
          <Button green onClick={sendMessage} disabled={sending || !message.trim()}>
            {sending ? 'Odesílám…' : 'Odeslat'}
          </Button>
          {msgSent && <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>Odesláno!</span>}
        </div>
      </Card>

      {/* Fotky */}
      {incident.photos && incident.photos.length > 0 && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Fotografie</h4>
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
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Timeline</h4>
        <SOSTimeline incidentId={incident.id} />
      </Card>
    </div>
  )
}

function WorkflowBtn({ label, icon, done, onClick }) {
  return (
    <button onClick={done ? undefined : onClick}
      className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none inline-flex items-center gap-1"
      style={{
        padding: '6px 14px',
        background: done ? '#dcfce7' : '#f1faf7',
        color: done ? '#15803d' : '#1a2e22',
        border: done ? '1px solid #86efac' : '1px solid #d4e8e0',
        opacity: done ? 0.7 : 1,
        cursor: done ? 'default' : 'pointer',
      }}>
      <span>{icon}</span>
      <span>{done ? `${label} ✓` : label}</span>
    </button>
  )
}

function InfoRow({ label, value, mono }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 55 }}>{label}</span>
      <span className={`text-sm font-medium ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}
