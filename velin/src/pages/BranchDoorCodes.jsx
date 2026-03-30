import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { generateDoorCode, Spinner, EmptyState } from './BranchHelpers'

// ─── Tab: Door Codes ──────────────────────────────────────────────
// Kódy se generují AUTOMATICKY v DB triggerem při změně bookingu na active.
// Velín jen zobrazuje stav a umožňuje nouzový zásah admina.
function TabDoorCodes({ doorCodes, loading, branchId, motos, activeBookings, onRefresh }) {
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState(null)

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

      const codes = [
        {
          branch_id: branchId,
          booking_id: booking.id,
          moto_id: booking.moto_id,
          code_type: 'motorcycle',
          door_code: generateDoorCode(),
          is_active: booking.status === 'active',
          valid_from: booking.start_date,
          valid_until: booking.end_date,
          sent_to_customer: hasDocuments && booking.status === 'active',
          sent_at: hasDocuments && booking.status === 'active' ? new Date().toISOString() : null,
          withheld_reason: withheldReason,
        },
        {
          branch_id: branchId,
          booking_id: booking.id,
          moto_id: booking.moto_id,
          code_type: 'accessories',
          door_code: generateDoorCode(),
          is_active: booking.status === 'active',
          valid_from: booking.start_date,
          valid_until: booking.end_date,
          sent_to_customer: hasDocuments && booking.status === 'active',
          sent_at: hasDocuments && booking.status === 'active' ? new Date().toISOString() : null,
          withheld_reason: withheldReason,
        },
      ]

      const { error: insertErr } = await supabase.from('branch_door_codes').insert(codes)
      if (insertErr) throw insertErr

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'door_codes_emergency_generated',
        details: { booking_id: booking.id, branch_id: branchId, withheld: !hasDocuments },
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

  async function activateCode(codeId) {
    try {
      await supabase.from('branch_door_codes').update({ is_active: true }).eq('id', codeId)
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
          message: `Váš kód k ${code.code_type === 'motorcycle' ? 'motorce' : 'příslušenství'}: ${code.door_code}`,
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
              <DoorCodeRow key={c.id} code={c} onDeactivate={deactivateCode} onResend={resendCode} />
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
              <DoorCodeRow key={c.id} code={c} onActivate={activateCode} inactive />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function DoorCodeRow({ code, onDeactivate, onActivate, onResend, inactive }) {
  const isMotorcycle = code.code_type === 'motorcycle'
  const booking = code.bookings
  const moto = code.motorcycles

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
        {isMotorcycle ? 'Motorka' : 'Přísluš.'}
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
        {inactive && onActivate && (
          <button onClick={() => onActivate(code.id)}
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
