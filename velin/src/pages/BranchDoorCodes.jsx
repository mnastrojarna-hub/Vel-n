import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { generateDoorCode, Spinner, EmptyState } from './BranchHelpers'

// Důvod zadržení kódu šatny, který zapisuje DB trigger _sync_locker_code u rezervace s vlastní výbavou
const OWN_GEAR_REASON = 'Vlastní výbava'

// Má rezervace v šatně co vyzvednout? RPC booking_needs_locker (20260925a) — stejné pravidlo jako DB trigger
// (půjčená výbava řidiče NEBO boty NEBO výbava spolujezdce). Když RPC v DB ještě není, chováme se jako
// před migrací (kód šatny se vydá) — nouzové generování nesmí kvůli tomu spadnout.
async function bookingNeedsLocker(bookingId) {
  const { data, error } = await supabase.rpc('booking_needs_locker', { p_booking_id: bookingId })
  if (error) { console.warn('[DoorCodes] booking_needs_locker failed:', error.message); return true }
  return data !== false
}

// ─── Tab: Door Codes ──────────────────────────────────────────────
// Kódy se generují AUTOMATICKY v DB triggerem při změně bookingu na active.
// Velín jen zobrazuje stav a umožňuje nouzový zásah admina.
// `selfService` — pobočka je samoobslužná (hradlo protokolu má jen jednotka; na obslužné pobočce
// kódy sice vznikají také, ale protokol podepisuje obsluha → badge „Čeká na protokol“ tam nepatří).
function TabDoorCodes({ doorCodes, loading, branchId, motos, activeBookings, onRefresh, selfService = false }) {
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState(null)
  // Zadržené kódy šatny („Vlastní výbava“): booking_id → smí se znovu aktivovat? (nárok podle RPC)
  const [lockerAllowed, setLockerAllowed] = useState({})

  const ownGearRows = doorCodes.filter(c => !c.is_active && c.code_type === 'accessories' && c.withheld_reason === OWN_GEAR_REASON)
  const ownGearKey = ownGearRows.map(c => c.booking_id).join(',')
  useEffect(() => {
    let alive = true
    const ids = [...new Set(ownGearRows.map(c => c.booking_id).filter(Boolean))]
    if (ids.length === 0) { setLockerAllowed({}); return }
    Promise.all(ids.map(async id => {
      const { data, error: e } = await supabase.rpc('booking_needs_locker', { p_booking_id: id })
      return [id, !e && data === true]   // bez RPC / při chybě se tlačítko neukáže (fail closed)
    })).then(pairs => { if (alive) setLockerAllowed(Object.fromEntries(pairs)) })
    return () => { alive = false }
  }, [ownGearKey])   // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) return <Spinner />

  const activeCodes = doorCodes.filter(c => c.is_active)
  const inactiveCodes = doorCodes.filter(c => !c.is_active).slice(0, 20)

  // Nouzové manuální generování — pouze při výpadku DB triggeru
  async function emergencyGenerateCodes(booking) {
    setGenerating(true)
    setError(null)
    try {
      const { data: docs } = await supabase
        .from('documents')
        .select('id, type')
        .eq('user_id', booking.user_id)
        .in('type', ['contract', 'protocol'])
      const { data: profile } = await supabase
        .from('profiles')
        .select('license_number')
        .eq('id', booking.user_id)
        .maybeSingle()

      const hasDocuments = (docs && docs.length > 0) || profile?.license_number
      const withheldReason = hasDocuments ? null : 'Chybí doklady (OP/pas/ŘP)'
      // Kód šatny JEN když má zákazník v šatně co vyzvednout (parita s auto_generate_door_codes)
      const needsLocker = await bookingNeedsLocker(booking.id)

      // Parita s DB triggerem auto_generate_door_codes: kódy platí od potvrzení
      // rezervace (reserved), ne až od aktivace — rezervace se nově překlápí na
      // 'active' teprve zadáním kódu do boxu, takže vazba na 'active' by tu
      // vyrobila mrtvé kódy a zákazník by se do kóje nedostal.
      const row = code_type => ({
        branch_id: branchId,
        booking_id: booking.id,
        moto_id: booking.moto_id,
        code_type,
        door_code: generateDoorCode(),
        is_active: true,
        valid_from: booking.start_date,
        valid_until: booking.end_date,
        sent_to_customer: !!hasDocuments,
        sent_at: hasDocuments ? new Date().toISOString() : null,
        withheld_reason: withheldReason,
      })
      const codes = needsLocker ? [row('motorcycle'), row('accessories')] : [row('motorcycle')]

      const { error: insertErr } = await supabase.from('branch_door_codes').insert(codes)
      if (insertErr) throw insertErr

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_codes_emergency_generated',
        details: { booking_id: booking.id, branch_id: branchId, withheld: !hasDocuments, locker: needsLocker },
      })

      onRefresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function deactivateCode(codeId) {
    try {
      await supabase.from('branch_door_codes').update({ is_active: false }).eq('id', codeId)
      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  async function activateCode(code) {
    try {
      const upd = { is_active: true }
      // Kód šatny zadržený kvůli vlastní výbavě: aktivovat jde jen, když rezervace šatnu opravdu potřebuje
      // (změna výbavy / own_gear ve Velíně). Jinak by zákazník bez výbavy dostal funkční kód k šatně.
      const ownGearRow = code.code_type === 'accessories' && code.withheld_reason === OWN_GEAR_REASON
      if (ownGearRow) {
        if (!(await bookingNeedsLocker(code.booking_id))) { setError('Rezervace má vlastní výbavu — kód šatny nelze aktivovat. Nejdřív upravte výbavu / volbu „Vlastní výbava“ v rezervaci.'); return }
        upd.withheld_reason = null
      }
      const { error: uErr } = await supabase.from('branch_door_codes').update(upd).eq('id', code.id)
      if (uErr) throw uErr
      // Obnovený kód šatny, který už zákazník dřív dostal, oznámit v appce (push doplní trg_push_on_admin_message) —
      // reaktivace z Velína nejde přes trigger _sync_locker_code, který zprávu posílá sám. Neodeslaný kód
      // (sent_to_customer=false) nabídne tlačítko „Odeslat“.
      if (ownGearRow && code.sent_to_customer && code.bookings?.user_id) {
        await supabase.from('admin_messages').insert({
          user_id: code.bookings.user_id, booking_id: code.booking_id, title: 'Kód šatny',
          message: `Kód šatny byl obnoven: ${code.door_code}`, type: 'info',
        }).catch(() => {})
      }
      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  async function resendCode(code) {
    try {
      await supabase.from('branch_door_codes').update({
        sent_to_customer: true,
        sent_at: new Date().toISOString(),
        withheld_reason: null,
      }).eq('id', code.id)

      if (code.bookings?.user_id) {
        await supabase.from('admin_messages').insert({
          user_id: code.bookings.user_id,
          title: 'Přístupový kód k pobočce',
          message: `Váš kód ${code.code_type === 'motorcycle' ? 'k motorce' : 'šatny'}: ${code.door_code}`,
          type: 'info',
        }).catch(() => {})
      }

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_code_resent',
        details: { code_id: code.id, booking_id: code.booking_id },
      })

      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  // Rezervace bez kódů = trigger nestihl / selhal
  const bookingsWithCodes = new Set(doorCodes.map(c => c.booking_id))
  const bookingsWithoutCodes = activeBookings.filter(b => !bookingsWithCodes.has(b.id))

  return (
    <div>
      {/* Info banner */}
      <div className="mb-3 p-2 rounded-card text-sm" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        Kódy se generují <strong>automaticky při změně rezervace na aktivní</strong> (DB trigger).
        Nouzové ruční generování pouze při výpadku triggeru.
      </div>

      {error && (
        <div className="mb-3 p-2 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
      )}

      {/* Bookings without codes — trigger failure fallback */}
      {bookingsWithoutCodes.length > 0 && (
        <div className="mb-4">
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#dc2626' }}>
            Výpadek triggeru — rezervace bez kódů ({bookingsWithoutCodes.length})
          </div>
          <div className="space-y-1">
            {bookingsWithoutCodes.map(b => (
              <div key={b.id} className="flex items-center gap-2 rounded-lg" style={{ padding: '6px 10px', background: '#fee2e2', border: '1px solid #fca5a5' }}>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                  {b.profiles?.full_name || 'Neznámý'}
                </span>
                <span className="text-sm" style={{ color: '#1a2e22' }}>
                  {new Date(b.start_date).toLocaleDateString('cs-CZ')} — {new Date(b.end_date).toLocaleDateString('cs-CZ')}
                </span>
                <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '2px 6px', background: b.status === 'active' ? '#dcfce7' : '#dbeafe', color: b.status === 'active' ? '#1a8a18' : '#2563eb' }}>
                  {b.status === 'active' ? 'Aktivní' : 'Nadcházející'}
                </span>
                <button onClick={() => emergencyGenerateCodes(b)} disabled={generating}
                  className="ml-auto rounded-btn text-sm font-bold cursor-pointer border-none"
                  style={{ padding: '4px 10px', background: '#dc2626', color: '#fff', opacity: generating ? 0.5 : 1 }}>
                  {generating ? 'Generuji...' : 'Nouzově generovat'}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Active codes */}
      <div className="mb-4">
        <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>
          Aktivní kódy ({activeCodes.length})
        </div>
        {activeCodes.length === 0 ? (
          <EmptyState text="Žádné aktivní kódy — kódy se vytvoří automaticky při aktivaci rezervace" />
        ) : (
          <div className="space-y-1 max-h-60 overflow-y-auto">
            {activeCodes.map(c => (
              <DoorCodeRow key={c.id} code={c} onDeactivate={deactivateCode} onResend={resendCode} selfService={selfService} />
            ))}
          </div>
        )}
      </div>

      {/* Inactive (history) */}
      {inactiveCodes.length > 0 && (
        <div>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
            Historie kódů (posledních {inactiveCodes.length})
          </div>
          <div className="space-y-1 max-h-40 overflow-y-auto">
            {inactiveCodes.map(c => (
              <DoorCodeRow key={c.id} code={c} onActivate={activateCode} inactive
                canActivate={!(c.code_type === 'accessories' && c.withheld_reason === OWN_GEAR_REASON) || lockerAllowed[c.booking_id] === true} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function DoorCodeRow({ code, onDeactivate, onActivate, onResend, inactive, canActivate = true, selfService = false }) {
  const isMotorcycle = code.code_type === 'motorcycle'
  const booking = code.bookings
  const moto = code.motorcycles
  // Kód motorky kóji neotevře, dokud není podepsaný předávací protokol (hradlo v jednotce, §1 návrhu) —
  // platí jen na SAMOOBSLUŽNÉ pobočce (na obslužné protokol podepisuje obsluha, hradlo tam není).
  // `handover_protocol_filled_at` přijde jen po migraci 20260925 — bez sloupce se badge neukazuje.
  const awaitsProtocol = selfService && isMotorcycle && !inactive && booking && 'handover_protocol_filled_at' in booking
    && booking.handover_protocol_filled_at == null && ['reserved', 'active'].includes(booking.status)

  return (
    <div className="flex items-center gap-2 text-sm rounded-lg"
      style={{
        padding: '6px 10px',
        background: inactive ? '#f3f4f6' : (isMotorcycle ? '#f1faf7' : '#eff6ff'),
        border: `1px solid ${inactive ? '#e5e7eb' : (isMotorcycle ? '#d4e8e0' : '#bfdbfe')}`,
        opacity: inactive ? 0.6 : 1,
      }}>
      <span className="inline-block rounded-btn text-[8px] font-extrabold tracking-wide uppercase"
        style={{
          padding: '2px 6px',
          background: isMotorcycle ? '#dcfce7' : '#dbeafe',
          color: isMotorcycle ? '#1a8a18' : '#2563eb',
          minWidth: 60,
          textAlign: 'center',
        }}>
        {isMotorcycle ? 'Motorka' : 'Šatna'}
      </span>
      <span className="font-mono font-extrabold text-base tracking-widest" style={{ color: '#0f1a14', letterSpacing: 3 }}>
        {code.door_code}
      </span>
      <span className="text-sm" style={{ color: '#1a2e22' }}>
        {moto ? `${moto.model} (${moto.spz || '?'})` : ''}
      </span>
      <span className="text-sm" style={{ color: '#1a2e22' }}>
        {booking?.profiles?.full_name || ''}
      </span>
      {code.withheld_reason && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#fef3c7', color: '#b45309' }}>
          Zadržen: {code.withheld_reason}
        </span>
      )}
      {!code.sent_to_customer && !inactive && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>
          Neodesláno
        </span>
      )}
      {code.sent_to_customer && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          style={{ padding: '2px 6px', background: '#dcfce7', color: '#1a8a18' }}>
          Odesláno
        </span>
      )}
      {awaitsProtocol && (
        <span className="inline-block rounded-btn text-[8px] font-bold"
          title="Zákazník ještě nepodepsal předávací protokol. Kód motorky se ověří, ale kóje se otevře až po podpisu — na displeji pobočky (po zavření šatny nebo hned po zadání kódu motorky) nebo v aplikaci."
          style={{ padding: '2px 6px', background: '#ede9fe', color: '#6d28d9' }}>
          📝 Čeká na protokol
        </span>
      )}
      <div className="ml-auto flex gap-1">
        {!inactive && onResend && !code.sent_to_customer && (
          <button onClick={() => onResend(code)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dbeafe', color: '#2563eb' }}>
            Odeslat
          </button>
        )}
        {!inactive && onDeactivate && (
          <button onClick={() => onDeactivate(code.id)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#fee2e2', color: '#dc2626' }}>
            Deaktivovat
          </button>
        )}
        {inactive && onActivate && canActivate && (
          <button onClick={() => onActivate(code)}
            className="rounded-btn text-[10px] font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dcfce7', color: '#1a8a18' }}>
            Aktivovat
          </button>
        )}
      </div>
    </div>
  )
}

export { TabDoorCodes }
