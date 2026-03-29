import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { STATUS_COLORS } from './SOSDetailConstants'
import { TYPE_LABELS } from '../SOSPanel'

export async function handleUpdateIncidentStatus(incident, newStatus, onRefresh) {
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
          const sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data
          if (sr?.success) {
            rd.replacement_booking_id = sr.replacement_booking_id
            rd.original_booking_id = sr.original_booking_id
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

      // 4. If no replacement but incident has a booking, complete it with SOS flag
      if (!replBookingId && incident?.booking_id) {
        await supabase.from('bookings').update({
          status: 'completed',
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
}

export async function handleSetMotoToService(incident, moto, booking, onRefresh, setMotoInService, loadTimelineActions) {
  let motoId = moto?.id || incident?.moto_id || booking?.moto_id || incident?.bookings?.moto_id || incident?.original_moto_id || incident?.replacement_data?.original_moto_id
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
      try {
        const logDesc = `SOS incident: ${sosDesc}${incident?.description ? ' — ' + incident.description.slice(0, 200) : ''}`
        const { data: newLog } = await supabase.from('maintenance_log').insert({
          moto_id: motoId,
          type: 'repair',
          service_type: `SOS: ${sosDesc}`,
          description: logDesc,
          scheduled_date: new Date().toISOString().slice(0, 10),
          status: 'in_service',
          performed_by: user?.email || 'Admin',
        }).select('id').single()
        await supabase.from('service_orders').insert({
          moto_id: motoId, type: `SOS: ${sosDesc}`, notes: logDesc,
          status: 'in_service', maintenance_log_id: newLog?.id,
        })
      } catch {}
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

export async function handleEnsureBookingSwap(incident) {
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
      if (swapResult.error) {
        console.error('[SOS] ensureBookingSwap RPC error:', swapResult.error.message)
        alert('❌ Swap RPC chyba: ' + swapResult.error.message)
        return rd
      }
      const sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data
      console.log('[SOS] ensureBookingSwap RPC response:', sr)
      if (sr?.success) {
        const updatedRd = {
          ...rd,
          original_booking_id: sr.original_booking_id,
          replacement_booking_id: sr.replacement_booking_id,
          original_end_date: sr.original_end_date,
        }
        await supabase.from('sos_incidents').update({ replacement_data: updatedRd }).eq('id', incident.id)
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('sos_timeline').insert({
          incident_id: incident.id,
          action: `Rezervace automaticky přepnuta (admin akce). Původní: #${sr.original_booking_id?.slice(-8).toUpperCase()}, nová: #${sr.replacement_booking_id?.slice(-8).toUpperCase()}`,
          performed_by: user?.email || 'Admin', admin_id: user?.id,
        })
        return updatedRd
      } else {
        const errMsg = sr?.error || 'Neznámá chyba'
        const errDetail = sr?.step ? ` [krok: ${sr.step}]` : ''
        console.error('[SOS] ensureBookingSwap RPC failed:', sr)
        alert('❌ Swap selhal: ' + errMsg + errDetail)
      }
    } catch (e) {
      console.error('[SOS] ensureBookingSwap exception:', e)
      alert('❌ Swap výjimka: ' + e.message)
    }
    return rd
  }
}

export async function handleLoadAvailableMotos(moto, incident, setAvailableMotos, setShowMotoSelector) {
    const { data } = await supabase.from('motorcycles')
      .select('id, model, spz, branch_id, branches(name), price_weekday, status, image_url, license_required')
      .eq('status', 'active')
    const currentMotoId = moto?.id || incident?.moto_id
    setAvailableMotos((data || []).filter(m => m.id !== currentMotoId))
    setShowMotoSelector(true)
  setShowMotoSelector(true)
}

export async function handleAdminInitiateReplacement(selectedMoto, incident, setSwapping, setShowMotoSelector, onRefresh) {
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
      if (swapResult.error) {
        alert('❌ Swap selhal: ' + swapResult.error.message)
        setSwapping(false)
        return
      }
      const sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data
      if (sr?.success) {
        const rd = {
          replacement_moto_id: selectedMoto.id,
          replacement_model: selectedMoto.model,
          daily_price: dailyPrice,
          delivery_fee: 0,
          payment_status: isFree ? 'free' : 'pending',
          payment_amount: 0,
          customer_fault: !!incident.customer_fault,
          original_booking_id: sr.original_booking_id,
          replacement_booking_id: sr.replacement_booking_id,
          original_end_date: sr.original_end_date,
          remaining_days: sr.remaining_days,
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
        alert(`✅ Náhradní motorka přiřazena!\n\nNová rezervace: #${sr.replacement_booking_id?.slice(-8).toUpperCase()}`)
      } else {
        alert('❌ Swap selhal: ' + (sr?.error || 'neznámá chyba'))
      }
    } catch (e) {
      console.error('[SOS] adminInitiateReplacement:', e)
      alert('❌ Chyba: ' + e.message)
    }
    setSwapping(false)
    onRefresh?.()
  onRefresh?.()
}

export async function handleUpdateReplacementStatus(incident, newStatus, ensureBookingSwap, loadTimelineActions, onRefresh) {
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
    const replData = incident?.replacement_data || {}
    const swapDone = (replData.original_booking_id && replData.replacement_booking_id) || (incident?.original_booking_id && incident?.replacement_booking_id)
    if (!swapDone && replData.replacement_moto_id) {
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
  onRefresh?.()
}

export async function handleRetriggerSosFab(incident, onRefresh) {
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
  onRefresh?.()
}

export async function handleApproveReplacement(incident, ensureBookingSwap, onRefresh) {
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
        (rd.original_booking_id ? ` Původní rez.: #${rd.original_booking_id.slice(-8).toUpperCase()}, nová: #${(rd.replacement_booking_id?.slice(-8) || '?').toUpperCase()}` : ''),
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }
}

export async function handleRejectReplacement(incident, reason, onRefresh) {
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
}
