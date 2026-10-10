import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { generateDoorCode, Spinner, EmptyState } from './BranchHelpers'
import { fetchDocsGate } from '../lib/docsGate'
import ConfirmDialog from '../components/ui/ConfirmDialog'

// Důvod zadržení kódu šatny, který zapisuje DB trigger _sync_locker_code u rezervace bez zapůjčené výbavy
// (hodnota v DB — NEMĚNIT). Obsluze se ukazuje OWN_GEAR_LABEL: vlastní výbava i „nic nevybral“ (20261005g).
const OWN_GEAR_REASON = 'Vlastní výbava'
const OWN_GEAR_LABEL = 'Bez zapůjčené výbavy'

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
  const [notice, setNotice] = useState(null)
  // „Odeslat“ při neúplných dokladech: { code, missing[] } → potvrzení, že je obsluha ověřila osobně
  const [releaseConfirm, setReleaseConfirm] = useState(null)
  // Zadržené kódy šatny („Vlastní výbava“): booking_id → smí se znovu aktivovat? (nárok podle RPC)
  const [lockerAllowed, setLockerAllowed] = useState({})
  // Pobočka s vjezdovou bránou (branch_gate_access): ruční znovuodeslání dá kód brány na 1. řádek (brána → šatna → motorka)

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
      // Doklady = backendová brána (get_docs_gate_checklist, stejné pravidlo jako DB trigger
      // auto_generate_door_codes). Dřív stačil JAKÝKOLI řádek smlouvy/protokolu nebo číslo ŘP
      // (smlouvu má každá rezervace) → nouzové kódy šly zákazníkovi i bez dokladů. Nejde-li
      // brána vyhodnotit, kódy se zadrží (pojistka trg_zz_door_codes_docs_gate to vynutí i tak).
      const gate = await fetchDocsGate({ bookingId: booking.id })
      const hasDocuments = gate?.ok === true
      const withheldReason = hasDocuments ? null : (gate?.reason || 'Doklady nelze ověřit')
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
        new_data: { booking_id: booking.id, branch_id: branchId, withheld: !hasDocuments, docs_reason: withheldReason, locker: needsLocker },
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
      // (zákazník mezitím zadal velikost výbavy). Jinak by zákazník bez výbavy dostal funkční kód k šatně.
      const ownGearRow = code.code_type === 'accessories' && code.withheld_reason === OWN_GEAR_REASON
      if (ownGearRow) {
        if (!(await bookingNeedsLocker(code.booking_id))) { setError('Rezervace je bez zapůjčené výbavy — kód šatny nelze aktivovat. Kód šatny vznikne sám, až zákazník zadá velikost výbavy (appka / web → Upravit rezervaci → Výbava).'); return }
        upd.withheld_reason = null
      }
      const { data: updRows, error: uErr } = await supabase.from('branch_door_codes').update(upd).eq('id', code.id).select('sent_to_customer')
      if (uErr) throw uErr
      // Obnovený kód šatny, který už zákazník dřív dostal, oznámit v appce (push doplní trg_push_on_admin_message) —
      // reaktivace z Velína nejde přes trigger _sync_locker_code, který zprávu posílá sám. Neodeslaný kód
      // (sent_to_customer=false) nabídne tlačítko „Odeslat“. Stav bere z řádku PO zápisu: pojistka
      // trg_zz_door_codes_docs_gate kód bez kompletních dokladů zadrží → číslo kódu se neposílá.
      if (ownGearRow && updRows?.[0]?.sent_to_customer === true && code.bookings?.user_id) {
        await supabase.from('admin_messages').insert({
          user_id: code.bookings.user_id, booking_id: code.booking_id, title: 'Kód šatny',
          message: `Kód šatny byl obnoven: ${code.door_code}`, type: 'info',
        }).then(() => {}, () => {})   // builder nemá metodu catch → then(ok, err), best-effort
      }
      onRefresh()
    } catch (e) {
      setError(e.message)
    }
  }

  // „Odeslat“ u zadrženého kódu: RPC admin_release_door_codes (20261004f, audit 20261010c) uvolní
  // VŠECHNY zadržené aktivní kódy rezervace (kromě držených výměnou motorky — ty uvolní až vrácení
  // původní motorky) a pošle zákazníkovi zprávu v appce (+ push; u pobočky s bránou brána → šatna →
  // motorka + postup), SMS/WhatsApp a e-mail s kódy. RPC uvolní i BEZ kompletních dokladů (vědomé
  // ruční rozhodnutí) → Velín nejdřív načte bránu dokladů a při neúplných chce výslovné potvrzení,
  // že obsluha doklady ověřila osobně (co chybělo, zapíše RPC do admin_audit_log).
  async function resendCode(code) {
    setError(null); setNotice(null)
    const gate = await fetchDocsGate({ bookingId: code.booking_id })
    if (gate?.ok !== true) {
      setReleaseConfirm({ code, missing: gate ? (gate.missing || []) : ['Stav dokladů se nepodařilo ověřit'] })
      return
    }
    await doRelease(code)
  }

  async function doRelease(code) {
    setReleaseConfirm(null)
    try {
      const { data, error: rErr } = await supabase.rpc('admin_release_door_codes', { p_booking_id: code.booking_id })
      if (rErr) throw rErr
      if (!data?.success) throw new Error((data?.error || 'Kódy se nepodařilo uvolnit') + (data?.docs_reason ? ` (doklady: ${data.docs_reason})` : ''))

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_code_resent',
        new_data: { code_id: code.id, booking_id: code.booking_id, released: data.released, docs_reason: data.docs_reason || null },
      })

      if (data.docs_reason) setNotice(`Kódy odeslány (${data.released}×) na potvrzení obsluhy — doklady při odeslání neúplné: ${data.docs_reason}`)
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
      {notice && (
        <div className="mb-3 p-2 rounded-card text-sm" style={{ background: '#fef3c7', color: '#92400e' }}>{notice}</div>
      )}

      <ConfirmDialog
        open={!!releaseConfirm}
        danger
        title="Doklady neúplné — odeslat kódy?"
        message={releaseConfirm && (
          <>
            <span className="block mb-2">Zákazník podle kontroly dokladů nemá vše potřebné:</span>
            {releaseConfirm.missing.map(m => <span key={m} className="block" style={{ color: '#b45309' }}>• {m}</span>)}
            <span className="block mt-2 font-bold">Potvrzením prohlašuji, že jsem doklady zákazníka osobně ověřil(a).</span>
            <span className="block mt-1">Kódy (brána / šatna / motorka) se hned odešlou SMS/WhatsApp, e-mailem i v aplikaci; uvolnění i to, co chybělo, se zapíše do auditu.</span>
          </>
        )}
        onConfirm={() => doRelease(releaseConfirm.code)}
        onCancel={() => setReleaseConfirm(null)}
      />

      {/* Bookings without codes — trigger failure fallback */}
      {bookingsWithoutCodes.length > 0 && (
        <div className="mb-4">
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#dc2626' }}>
            Výpadek triggeru — rezervace bez kódů ({bookingsWithoutCodes.length})
          </div>
          <div className="space-y-1">
            {bookingsWithoutCodes.map(b => (
              <div key={b.id} className="flex items-center gap-2 rounded-lg max-lg:flex-wrap" style={{ padding: '6px 10px', background: '#fee2e2', border: '1px solid #fca5a5' }}>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                  {b.profiles?.full_name || 'Neznámý'}
                </span>
                <span className="text-sm" style={{ color: '#1a2e22' }}>
                  {new Date(b.start_date).toLocaleDateString('cs-CZ')} — {new Date(b.end_date).toLocaleDateString('cs-CZ')}
                </span>
                <span className="inline-block rounded-btn text-[9px] max-lg:text-[11px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '2px 6px', background: b.status === 'active' ? '#dcfce7' : '#dbeafe', color: b.status === 'active' ? '#1a8a18' : '#2563eb' }}>
                  {b.status === 'active' ? 'Aktivní' : 'Nadcházející'}
                </span>
                <button onClick={() => emergencyGenerateCodes(b)} disabled={generating}
                  className="ml-auto rounded-btn text-sm font-bold cursor-pointer border-none max-lg:min-h-[40px]"
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
          <div className="space-y-1 max-h-60 overflow-y-auto max-lg:max-h-none">
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
          <div className="space-y-1 max-h-40 overflow-y-auto max-lg:max-h-none">
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
    <div className="flex items-center gap-2 text-sm rounded-lg max-lg:flex-wrap max-lg:gap-y-1.5"
      style={{
        padding: '6px 10px',
        background: inactive ? '#f3f4f6' : (isMotorcycle ? '#f1faf7' : '#eff6ff'),
        border: `1px solid ${inactive ? '#e5e7eb' : (isMotorcycle ? '#d4e8e0' : '#bfdbfe')}`,
        opacity: inactive ? 0.6 : 1,
      }}>
      <span className="inline-block rounded-btn text-[8px] max-lg:text-[11px] font-extrabold tracking-wide uppercase"
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
        <span className="inline-block rounded-btn text-[8px] max-lg:text-[11px] font-bold"
          style={{ padding: '2px 6px', background: '#fef3c7', color: '#b45309' }}>
          Zadržen: {code.withheld_reason === OWN_GEAR_REASON ? OWN_GEAR_LABEL : code.withheld_reason}
        </span>
      )}
      {!code.sent_to_customer && !inactive && (
        <span className="inline-block rounded-btn text-[8px] max-lg:text-[11px] font-bold"
          style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>
          Neodesláno
        </span>
      )}
      {code.sent_to_customer && (
        <span className="inline-block rounded-btn text-[8px] max-lg:text-[11px] font-bold"
          style={{ padding: '2px 6px', background: '#dcfce7', color: '#1a8a18' }}>
          Odesláno
        </span>
      )}
      {awaitsProtocol && (
        <span className="inline-block rounded-btn text-[8px] max-lg:text-[11px] font-bold"
          title="Zákazník ještě nepodepsal předávací protokol. Kód motorky se ověří, ale kóje se otevře až po podpisu — na displeji pobočky (po zavření šatny nebo hned po zadání kódu motorky) nebo v aplikaci."
          style={{ padding: '2px 6px', background: '#ede9fe', color: '#6d28d9' }}>
          📝 Čeká na protokol
        </span>
      )}
      <div className="ml-auto flex gap-1">
        {!inactive && onResend && !code.sent_to_customer && (
          <button onClick={() => onResend(code)}
            title="Ruční uvolnění: uvolní všechny zadržené kódy rezervace (kromě držených výměnou motorky) a hned je pošle zákazníkovi (zpráva v aplikaci, SMS/WhatsApp, e-mail). Při neúplných dokladech se Velín zeptá na potvrzení, že je obsluha ověřila osobně — zapíše se do auditu."
            className="rounded-btn text-[10px] max-lg:text-[12px] max-lg:min-h-[36px] max-lg:!px-3 font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dbeafe', color: '#2563eb' }}>
            Odeslat
          </button>
        )}
        {!inactive && onDeactivate && (
          <button onClick={() => onDeactivate(code.id)}
            className="rounded-btn text-[10px] max-lg:text-[12px] max-lg:min-h-[36px] max-lg:!px-3 font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#fee2e2', color: '#dc2626' }}>
            Deaktivovat
          </button>
        )}
        {inactive && onActivate && canActivate && (
          <button onClick={() => onActivate(code)}
            className="rounded-btn text-[10px] max-lg:text-[12px] max-lg:min-h-[36px] max-lg:!px-3 font-bold cursor-pointer border-none"
            style={{ padding: '2px 8px', background: '#dcfce7', color: '#1a8a18' }}>
            Aktivovat
          </button>
        )}
      </div>
    </div>
  )
}

export { TabDoorCodes }
