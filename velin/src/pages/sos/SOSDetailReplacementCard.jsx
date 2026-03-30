import Card from '../../components/ui/Card'
import { DECISION_LABELS, REPLACEMENT_STATUS_LABELS, REPLACEMENT_STATUS_COLORS, InfoRow } from './SOSDetailConstants'

export function DecisionCard({ incident, isActive, isMajor, isAccident, updateDecision, updateFault }) {
  if (!isActive || !isMajor) return null
  return (
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
  )
}

export function MotoSelectorCard({ incident, isActive, isMajor, showMotoSelector, availableMotos, swapping, loadAvailableMotos, adminInitiateReplacement, setShowMotoSelector }) {
  if (!isActive || !isMajor || incident.customer_decision !== 'replacement_moto' || incident.replacement_data?.replacement_moto_id) return null
  return (
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
  )
}

export function ReplacementOrderCard({ incident, replacementMoto, showRejectForm, setShowRejectForm, rejectReason, setRejectReason, approveReplacement, rejectReplacement, updateReplacementStatus, retriggerSosFab, ensureBookingSwap, onRefresh }) {
  if (!incident.replacement_data) return null
  return (
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
                <InfoRow label="Původní rez." value={`#${(incident.replacement_data.original_booking_id || incident.original_booking_id || '').slice(-8).toUpperCase()}`} mono />
                <InfoRow label="Nová rez." value={`#${(incident.replacement_data.replacement_booking_id || incident.replacement_booking_id || '').slice(-8).toUpperCase()}`} mono />
                {incident.replacement_data.original_end_date && (
                  <InfoRow label="Pův. konec" value={new Date(incident.replacement_data.original_end_date).toLocaleDateString('cs-CZ')} />
                )}
                {(incident.replacement_data.original_end_date || incident.replacement_data.remaining_days) && (() => {
                  const endDate = incident.replacement_data.original_end_date ? new Date(incident.replacement_data.original_end_date + (incident.replacement_data.original_end_date.includes('T') ? '' : 'T23:59:59')) : null
                  if (endDate && !isNaN(endDate)) {
                    const now = new Date()
                    const remainMs = endDate - now
                    if (remainMs <= 0) return <InfoRow label="Zbývající čas" value="Vypršelo" />
                    const remainH = Math.floor(remainMs / 3600000)
                    if (remainH < 24) return <InfoRow label="Zbývající čas" value={`${remainH} h ${Math.floor((remainMs % 3600000) / 60000)} min`} />
                    const d = Math.ceil(remainMs / 86400000)
                    return <InfoRow label="Zbývá dní" value={`${d} ${d === 1 ? 'den' : d < 5 ? 'dny' : 'dní'}`} />
                  }
                  const d = incident.replacement_data.remaining_days
                  return d ? <InfoRow label="Zbývá dní" value={`${d}`} /> : null
                })()}
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
                  alert('✅ Swap proveden úspěšně! Nová rezervace: #' + result.replacement_booking_id.slice(-8).toUpperCase())
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
  )
}
