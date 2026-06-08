import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'

// Mapování jazyka na vlaječku/label pro náhled (informativní).
const LANG_LABEL = { cs: '🇨🇿 Čeština', en: '🇬🇧 English', de: '🇩🇪 Deutsch', es: '🇪🇸 Español', fr: '🇫🇷 Français', nl: '🇳🇱 Nederlands', pl: '🇵🇱 Polski' }
const langLabel = (l) => LANG_LABEL[String(l || 'cs').slice(0, 2)] || (l || 'cs')

const STATUS_LABEL = {
  pending: 'Čeká', reserved: 'Rezervováno', active: 'Aktivní', completed: 'Dokončeno', cancelled: 'Zrušeno',
  new: 'Nová', confirmed: 'Potvrzeno', processing: 'Zpracovává se', shipped: 'Odesláno', delivered: 'Doručeno', returned: 'Vráceno', refunded: 'Refundováno',
}

/**
 * Znovu zaslat e-mail zákazníkovi.
 *
 * Flow dle zadání: vyber zákazníka (jméno/e-mail/telefon) → zobrazí se jeho
 * rezervace + objednávky → vyber jednu → vyber e-mailovou šablonu → odeslat.
 * E-mail odešle edge fn `send-booking-email`, která sama:
 *   - detekuje jazyk zákazníka (profiles.language → bookings.language → shop_orders.language → cs)
 *     a přeloží Velín šablonu + vygeneruje přílohy (smlouva/VOP) v jazyce zákazníka,
 *   - vyzvedne/přiloží aktuální faktury (ZF/DP/KF) a smlouvu/VOP.
 *
 * Volitelný přepínač „Přegenerovat přílohy" před odesláním přepíše stávající
 * doklady aktuálními daty (generate-invoice regenerate:true + generate-document,
 * který staré verze přemaže) — případ aktualizace smlouvy / úpravy rezervace.
 */
export default function ResendMailTab() {
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [customers, setCustomers] = useState([])
  const [selectedCustomer, setSelectedCustomer] = useState(null)

  const [bookings, setBookings] = useState([])
  const [orders, setOrders] = useState([])
  const [loadingItems, setLoadingItems] = useState(false)
  const [selected, setSelected] = useState(null) // { kind:'booking'|'order', data }

  const [templates, setTemplates] = useState([])
  const [slug, setSlug] = useState('')
  const [regenAttach, setRegenAttach] = useState(false)

  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => { debugLog('tab.mount', 'ResendMailTab'); loadTemplates() }, [])

  async function loadTemplates() {
    try {
      const { data } = await supabase.from('email_templates').select('slug, name, active, attachments').eq('active', true).order('name')
      setTemplates(data || [])
    } catch (e) { debugError('ResendMailTab', 'loadTemplates', e) }
  }

  async function handleSearch(e) {
    e?.preventDefault?.()
    const q = query.trim()
    if (q.length < 2) { setError('Zadejte alespoň 2 znaky (jméno, e-mail nebo telefon).'); return }
    setError(null); setResult(null); setSearching(true); setSelectedCustomer(null); setSelected(null)
    try {
      const like = `%${q}%`
      const { data, error: err } = await debugAction('profiles.search', 'ResendMailTab', () =>
        supabase.from('profiles').select('id, full_name, email, phone, language').or(`full_name.ilike.${like},email.ilike.${like},phone.ilike.${like}`).limit(25))
      if (err) throw err
      setCustomers(data || [])
      if (!(data || []).length) setError('Žádný zákazník nenalezen.')
    } catch (e) { setError(`Hledání selhalo: ${e.message}`) }
    setSearching(false)
  }

  async function selectCustomer(c) {
    setSelectedCustomer(c); setSelected(null); setResult(null); setError(null); setLoadingItems(true)
    try {
      const [bRes, oRes] = await Promise.all([
        supabase.from('bookings').select('id, start_date, end_date, total_price, status, booking_source, language, motorcycles(model)').eq('user_id', c.id).order('start_date', { ascending: false }).limit(50),
        supabase.from('shop_orders').select('id, order_number, total, status, language, created_at').eq('customer_id', c.id).order('created_at', { ascending: false }).limit(50),
      ])
      setBookings(bRes.data || [])
      setOrders(oRes.data || [])
    } catch (e) { setError(`Načtení rezervací selhalo: ${e.message}`) }
    setLoadingItems(false)
  }

  // Jazyk, který edge fn pravděpodobně použije (mirror detect_customer_language priority).
  function effectiveLang() {
    if (selectedCustomer?.language) return selectedCustomer.language
    if (selected?.kind === 'booking') return selected.data.language || 'cs'
    if (selected?.kind === 'order') return selected.data.language || 'cs'
    return 'cs'
  }

  async function regenerateAttachments() {
    const warnings = []
    const inv = (body) => supabase.functions.invoke('generate-invoice', { body: { ...body, send_email: false } })
    if (selected.kind === 'booking') {
      const bid = selected.data.id
      const tasks = [
        inv({ regenerate: true, booking_id: bid, type: 'advance' }),
        inv({ regenerate: true, booking_id: bid, type: 'payment_receipt' }),
        supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: bid } }),
        supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: bid } }),
      ]
      // KF (konečná faktura) vystavuje DB trigger s číslem KF-… — generate-invoice
      // s type='final' by vyrobil JINÝ doklad (prefix FV, přepočítané položky).
      // Pro přílohu jen dorenderujeme PDF stávající KF z uložených položek.
      if (selected.data.status === 'completed') tasks.push(inv({ render_existing: true, booking_id: bid, type: 'final' }))
      const res = await Promise.allSettled(tasks)
      res.forEach((r, i) => { if (r.status === 'rejected') warnings.push(`příloha #${i + 1}: ${r.reason?.message || 'chyba'}`) })
    } else {
      const oid = selected.data.id
      const res = await Promise.allSettled([
        inv({ regenerate: true, order_id: oid, type: 'shop_proforma', source: 'shop' }),
        inv({ regenerate: true, order_id: oid, type: 'payment_receipt', source: 'shop' }),
        inv({ regenerate: true, order_id: oid, type: 'shop_final', source: 'shop' }),
      ])
      res.forEach((r, i) => { if (r.status === 'rejected') warnings.push(`příloha #${i + 1}: ${r.reason?.message || 'chyba'}`) })
    }
    return warnings
  }

  async function handleSend() {
    if (!selected) { setError('Vyberte rezervaci nebo objednávku.'); return }
    if (!slug) { setError('Vyberte e-mailovou šablonu.'); return }
    const email = selectedCustomer?.email
    if (!email) { setError('Zákazník nemá uložený e-mail.'); return }
    setSending(true); setError(null); setResult(null)
    let warnings = []
    try {
      if (regenAttach) {
        try { warnings = await regenerateAttachments() } catch (e) { warnings.push(`regenerace: ${e.message}`) }
      }
      // type = logický typ; source rozhodne web_/app variantu (edge fn fallbackuje na base slug).
      const type = slug.replace(/^web_/, '')
      let body
      if (selected.kind === 'booking') {
        const b = selected.data
        const source = slug.startsWith('web_') ? 'web' : (b.booking_source || 'app')
        body = {
          type, booking_id: b.id, source,
          customer_email: email, customer_name: selectedCustomer.full_name,
          motorcycle: b.motorcycles?.model || '', start_date: b.start_date, end_date: b.end_date, total_price: b.total_price,
        }
      } else {
        const o = selected.data
        // E-shop/voucher objednávky jsou webové; edge fn fallbackuje na base slug, když web_ varianta chybí.
        body = {
          type, order_id: o.id, source: 'web',
          customer_email: email, customer_name: selectedCustomer.full_name,
          order_number: o.order_number, total_price: o.total,
        }
      }
      const { data, error: err } = await debugAction('functions.send-booking-email', 'ResendMailTab', () =>
        supabase.functions.invoke('send-booking-email', { body }), { type, slug })
      if (err) throw err
      if (data && data.success === false) throw new Error(data.error || 'send-booking-email vrátila success=false')
      setResult({ ok: true, email, lang: effectiveLang(), warnings })
    } catch (e) {
      debugError('ResendMailTab', 'handleSend', e)
      setError(`Odeslání selhalo: ${e.message}`)
    }
    setSending(false)
  }

  const inputStyle = { padding: '9px 12px', background: '#f1faf7', border: '1px solid #b6dccb', borderRadius: 10, color: '#0f1a14' }
  const rowSel = (isSel) => ({ background: isSel ? '#dcfce7' : '#f1faf7', border: isSel ? '2px solid #74FB71' : '1px solid transparent', cursor: 'pointer' })

  return (
    <div className="space-y-5">
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Znovu zaslat e-mail</h3>
        <p style={{ fontSize: 13, color: '#1a2e22', marginBottom: 12 }}>
          Najdi zákazníka, vyber jeho rezervaci nebo objednávku a e-mailovou šablonu. Mail se odešle v jazyce zákazníka s aktuálními přílohami.
          Hodí se pro aktualizaci smlouvy, telefonickou úpravu rezervace nebo úpravu na místě.
        </p>
        <form onSubmit={handleSearch} className="flex gap-2 flex-wrap">
          <input autoFocus value={query} onChange={e => setQuery(e.target.value)} placeholder="Jméno, e-mail nebo telefon zákazníka…"
            className="flex-1 text-sm outline-none" style={{ ...inputStyle, minWidth: 280 }} />
          <Button green type="submit" disabled={searching}>{searching ? 'Hledám…' : 'Hledat'}</Button>
        </form>
      </Card>

      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {customers.length > 0 && !selectedCustomer && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Zákazníci ({customers.length})</h4>
          {customers.map(c => (
            <div key={c.id} onClick={() => selectCustomer(c)} className="flex items-center gap-3 p-3 rounded-lg mb-2 hover:shadow-sm transition-shadow" style={rowSel(false)}>
              <div className="flex-1">
                <span className="text-sm font-bold">{c.full_name || '(bez jména)'}</span>
                <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{c.email || '—'}</span>
                {c.phone && <span className="text-sm ml-3" style={{ color: '#6b7280' }}>{c.phone}</span>}
              </div>
              <Badge label={langLabel(c.language)} color="#1a2e22" bg="#e2f5ec" />
            </div>
          ))}
        </Card>
      )}

      {selectedCustomer && (
        <Card>
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
              {selectedCustomer.full_name} · {selectedCustomer.email}
            </h4>
            <button onClick={() => { setSelectedCustomer(null); setSelected(null) }} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>← Zpět na výsledky</button>
          </div>

          {loadingItems ? <div className="py-6 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div> : (
            <>
              <div className="text-xs font-bold uppercase tracking-wide mb-2" style={{ color: '#6b7280' }}>Rezervace ({bookings.length})</div>
              {bookings.length === 0 ? <p style={{ fontSize: 13, color: '#9ca3af', marginBottom: 10 }}>Žádné rezervace</p> : bookings.map(b => {
                const isSel = selected?.kind === 'booking' && selected.data.id === b.id
                return (
                  <div key={b.id} onClick={() => setSelected({ kind: 'booking', data: b })} className="flex items-center gap-3 p-3 rounded-lg mb-2 transition-shadow" style={rowSel(isSel)}>
                    <span style={{ fontSize: 16 }}>🏍️</span>
                    <span className="text-sm font-bold font-mono">{b.id.slice(-8).toUpperCase()}</span>
                    <span className="text-sm">{b.motorcycles?.model || '—'}</span>
                    <span className="text-sm" style={{ color: '#1a2e22' }}>{(b.start_date || '').slice(0, 10)} → {(b.end_date || '').slice(0, 10)}</span>
                    <Badge label={STATUS_LABEL[b.status] || b.status} color="#1a2e22" bg="#e2f5ec" />
                    <span className="text-sm font-bold ml-auto">{Number(b.total_price || 0).toLocaleString('cs-CZ')} Kč</span>
                  </div>
                )
              })}

              {orders.length > 0 && <div className="text-xs font-bold uppercase tracking-wide mt-3 mb-2" style={{ color: '#6b7280' }}>Objednávky e-shop ({orders.length})</div>}
              {orders.map(o => {
                const isSel = selected?.kind === 'order' && selected.data.id === o.id
                return (
                  <div key={o.id} onClick={() => setSelected({ kind: 'order', data: o })} className="flex items-center gap-3 p-3 rounded-lg mb-2 transition-shadow" style={rowSel(isSel)}>
                    <span style={{ fontSize: 16 }}>📦</span>
                    <span className="text-sm font-bold font-mono">{o.order_number || o.id.slice(-8).toUpperCase()}</span>
                    <span className="text-sm" style={{ color: '#1a2e22' }}>{(o.created_at || '').slice(0, 10)}</span>
                    <Badge label={STATUS_LABEL[o.status] || o.status} color="#1a2e22" bg="#e2f5ec" />
                    <span className="text-sm font-bold ml-auto">{Number(o.total || 0).toLocaleString('cs-CZ')} Kč</span>
                  </div>
                )
              })}
            </>
          )}
        </Card>
      )}

      {selected && (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Odeslání e-mailu</h4>
          <div className="flex flex-col gap-3">
            <div>
              <label className="text-xs font-bold uppercase tracking-wide block mb-1" style={{ color: '#6b7280' }}>E-mailová šablona</label>
              <select value={slug} onChange={e => setSlug(e.target.value)} className="w-full text-sm outline-none" style={inputStyle}>
                <option value="">— vyber šablonu —</option>
                {templates.map(t => <option key={t.slug} value={t.slug}>{t.name} ({t.slug})</option>)}
              </select>
            </div>

            <label className="flex items-center gap-2 cursor-pointer" style={{ fontSize: 13, color: '#1a2e22' }}>
              <input type="checkbox" checked={regenAttach} onChange={e => setRegenAttach(e.target.checked)} />
              <span>Přegenerovat přílohy před odesláním (aktuální smlouva / DP / ZF{selected.kind === 'booking' && selected.data.status === 'completed' ? ' / KF' : ''}) — přepíše staré verze</span>
            </label>

            <div className="flex items-center gap-3 flex-wrap p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <span style={{ fontSize: 13, color: '#1a2e22' }}>Příjemce: <strong>{selectedCustomer.email}</strong></span>
              <span style={{ fontSize: 13, color: '#1a2e22' }}>Jazyk mailu: <strong>{langLabel(effectiveLang())}</strong></span>
            </div>

            <div>
              <Button green onClick={handleSend} disabled={sending || !slug}>{sending ? 'Odesílám…' : 'Odeslat e-mail'}</Button>
            </div>
          </div>

          {result?.ok && (
            <div className="p-3 rounded-card mt-3" style={{ background: '#dcfce7', color: '#166534', fontSize: 13 }}>
              ✓ E-mail odeslán na <strong>{result.email}</strong> ({langLabel(result.lang)}). Najdeš ho v záložce „Zaslané emaily".
              {result.warnings?.length > 0 && <div style={{ color: '#92400e', marginTop: 6 }}>Pozn. k přílohám: {result.warnings.join('; ')}</div>}
            </div>
          )}
        </Card>
      )}
    </div>
  )
}
