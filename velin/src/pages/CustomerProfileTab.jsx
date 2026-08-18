import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'

const C = {
  dark: '#1a2e22', text: '#0f1a14', muted: '#6b7280', faint: '#b6c2bb',
  g100: '#f1faf7', g200: '#d4e8e0', green: '#74FB71', gdk: '#1a8a18', red: '#dc2626',
}

function fmtDate(d) {
  if (!d) return null
  const x = new Date(d)
  if (isNaN(x.getTime())) return null
  return x.toLocaleDateString('cs-CZ')
}

function czAge(dob) {
  if (!dob) return null
  const d = new Date(dob)
  if (isNaN(d.getTime())) return null
  const now = new Date()
  let age = now.getFullYear() - d.getFullYear()
  const m = now.getMonth() - d.getMonth()
  if (m < 0 || (m === 0 && now.getDate() < d.getDate())) age--
  if (age < 0 || age > 150) return null
  const unit = age === 1 ? 'rok' : (age >= 2 && age <= 4 ? 'roky' : 'let')
  return `${age} ${unit}`
}

function SectionTitle({ children, right }) {
  return (
    <div className="flex items-center justify-between mb-3.5">
      <h3 className="flex items-center gap-2 text-xs font-extrabold uppercase tracking-widest" style={{ color: C.dark }}>
        <span style={{ width: 3, height: 14, borderRadius: 2, background: C.green, display: 'inline-block' }} />
        {children}
      </h3>
      {right}
    </div>
  )
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <label className="block">
      <span className="block text-[11px] font-bold uppercase tracking-wide mb-1" style={{ color: C.muted }}>{label}</span>
      <input
        type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled}
        className="w-full rounded-lg text-sm outline-none transition focus:border-[#86e3a3]"
        style={{ padding: '8px 11px', background: disabled ? '#f7faf9' : '#fff', border: `1px solid ${C.g200}`, color: disabled ? C.muted : C.text }}
      />
    </label>
  )
}

function Info({ label, value }) {
  return (
    <div>
      <div className="text-[11px] font-bold uppercase tracking-wide mb-0.5" style={{ color: C.muted }}>{label}</div>
      <div className="text-sm font-semibold" style={{ color: value ? C.text : C.faint }}>{value || '—'}</div>
    </div>
  )
}

function Chip({ label, value, tone }) {
  const map = {
    green: { bg: '#dcfce7', col: '#16a34a' },
    blue: { bg: '#dbeafe', col: '#2563eb' },
    plain: { bg: C.g100, col: C.dark },
  }
  const t = map[tone] || map.plain
  return (
    <div className="rounded-xl px-3 py-2 min-w-0" style={{ background: t.bg }}>
      <div className="text-[10px] font-bold uppercase tracking-wide truncate" style={{ color: t.col, opacity: 0.65 }}>{label}</div>
      <div className="text-sm font-extrabold truncate" style={{ color: t.col }}>{value}</div>
    </div>
  )
}

function VerifyBadge({ verified, date }) {
  if (verified) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full text-[11px] font-bold whitespace-nowrap" style={{ padding: '2px 9px', background: '#dcfce7', color: C.gdk }}>
        {'✓'} Ověřeno{date ? ` · ${date}` : ''}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-1 rounded-full text-[11px] font-bold whitespace-nowrap" style={{ padding: '2px 9px', background: '#f3f4f6', color: '#9ca3af' }}>
      {'✕'} Neověřeno
    </span>
  )
}

function ConsentRow({ label, desc, checked, onChange, required = false, readOnly = false, unknown = false }) {
  const stateLabel = unknown ? 'Neznámé' : (checked ? 'ANO' : 'NE')
  const bg = unknown ? '#f3f4f6' : (checked ? '#dcfce7' : '#fef2f2')
  const col = unknown ? '#9ca3af' : (checked ? C.gdk : C.red)
  const border = unknown ? '#e5e7eb' : (checked ? '#86e3a3' : '#fecaca')
  return (
    <div className="flex items-center justify-between gap-3 py-2.5" style={{ borderTop: `1px solid ${C.g200}` }}>
      <div className="min-w-0">
        <div className="flex items-center gap-2 text-sm font-bold" style={{ color: C.text }}>
          <span className="truncate">{label}</span>
          {required && (
            <span className="text-[9px] font-extrabold uppercase tracking-wide rounded px-1.5 py-0.5 whitespace-nowrap" style={{ background: '#fef9c3', color: '#a16207' }}>povinné</span>
          )}
        </div>
        {desc && <div className="text-[11px] mt-0.5" style={{ color: C.muted }}>{desc}</div>}
      </div>
      {readOnly ? (
        <span className="text-xs font-extrabold rounded-full px-3 py-1 whitespace-nowrap" style={{ background: bg, color: col, border: `1.5px solid ${border}` }}>{stateLabel}</span>
      ) : (
        <button type="button" onClick={() => onChange(!checked)} className="text-xs font-extrabold rounded-full px-3 py-1 cursor-pointer whitespace-nowrap transition" style={{ background: bg, color: col, border: `1.5px solid ${border}` }}>{stateLabel}</button>
      )}
    </div>
  )
}

function DocBox({ title, badge, children }) {
  return (
    <div className="rounded-xl p-3.5" style={{ background: C.g100, border: `1px solid ${C.g200}` }}>
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: C.dark }}>{title}</span>
        {badge}
      </div>
      <div className="space-y-2.5">{children}</div>
    </div>
  )
}

function GearSizes({ gearSizes }) {
  const empty = !gearSizes || (typeof gearSizes === 'object' && Object.keys(gearSizes).length === 0)
  if (empty) return <div className="text-sm" style={{ color: C.faint }}>{'—'} Nevyplněno</div>
  if (typeof gearSizes === 'object' && !Array.isArray(gearSizes)) {
    return (
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        {Object.entries(gearSizes).map(([k, v]) => (
          <div key={k} className="flex items-center justify-between gap-2 rounded-lg px-2.5 py-1.5" style={{ background: C.g100 }}>
            <span className="text-[11px] font-extrabold uppercase tracking-wide" style={{ color: C.muted }}>{k}</span>
            <span className="text-sm font-bold" style={{ color: C.text }}>{String(v)}</span>
          </div>
        ))}
      </div>
    )
  }
  return <span className="text-sm" style={{ color: C.dark }}>{JSON.stringify(gearSizes)}</span>
}

function PlatformChip({ userId, fallback }) {
  const [src, setSrc] = useState(null)
  useEffect(() => {
    if (!userId) return
    supabase.from('bookings').select('booking_source').eq('user_id', userId)
      .then(({ data }) => { if (data) setSrc(new Set(data.map(b => b.booking_source).filter(Boolean))) })
      .catch(() => {})
  }, [userId])
  let val = '—'
  if (src && src.size) {
    const a = src.has('app'), w = src.has('web')
    val = a && w ? 'WEB + APP' : a ? 'APP' : 'WEB'
  } else if (fallback === 'app' || fallback === 'web') {
    // Jen skutečné platformy — placeholder z auth triggeru ('auth_trigger')
    // ani jiné neznámé hodnoty nezobrazujeme, jinak by chip ukázal AUTH_TRIGGER.
    val = fallback.toUpperCase()
  }
  return <Chip label="Platforma" value={val} tone={val === '—' ? undefined : (val.includes('WEB') ? 'blue' : 'green')} />
}

/// Věrnostní rank — body sbírají dokončené rezervace z appky I webu
/// (1 bod; delší než 7 dní = 4 body), sleva se ale uplatňuje jen v appce.
/// Stejný výpočet jako RPC get_loyalty_status: pct = min(20, ceil((body+1)/2)).
/// Když tabulka loyalty_levels neexistuje (backend ještě nenasazen), chip se skryje.
function LoyaltyChip({ userId }) {
  const [rank, setRank] = useState(null)
  useEffect(() => {
    if (!userId) return
    ;(async () => {
      try {
        const { data: rows, error } = await supabase.from('bookings')
          .select('start_date, end_date, is_test')
          .eq('user_id', userId).eq('status', 'completed')
        if (error) return
        const points = (rows || []).reduce((sum, b) => {
          if (b.is_test) return sum
          const days = Math.round((new Date(b.end_date) - new Date(b.start_date)) / 86400000) + 1
          return sum + (days > 7 ? 4 : 1)
        }, 0)
        const pct = Math.min(20, Math.ceil((points + 1) / 2))
        const { data } = await supabase.from('loyalty_levels')
          .select('name, discount_percent, color_hex').eq('level', pct).maybeSingle()
        if (data) setRank(data)
      } catch { /* loyalty_levels nemusí existovat */ }
    })()
  }, [userId])
  if (!rank) return null
  return <Chip label="Věrnostní rank (app)" value={`${rank.name} · ${rank.discount_percent} %`} tone="green" />
}

export default function ProfileTab({ customer, set, error, saving, onSave, onDelete, onBlock }) {
  const age = czAge(customer.date_of_birth)
  const groups = customer.license_group || []
  // NULL/undefined souhlas = zákazník ho nikdy explicitně nenastavil (stará
  // verze appky / řádek před sjednocením defaultů). Zbytek systému (app, web)
  // bere NULL jako zapnuto, proto ho nezobrazujeme jako červené „NE", ale jako
  // šedé „Neznámé". Explicitní false zůstává „NE".
  const unknownC = (v) => v === null || v === undefined

  return (
    <div className="space-y-5">
      {/* Rychlý přehled */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2.5">
        <PlatformChip userId={customer.id} fallback={customer.registration_source} />
        <Chip label="Registrace přes"
          value={customer.registration_source === 'app' ? 'APP' : customer.registration_source === 'web' ? 'WEB' : '—'}
          tone={customer.registration_source === 'app' ? 'green' : customer.registration_source === 'web' ? 'blue' : undefined} />
        <LoyaltyChip userId={customer.id} />
        <Chip label="Jazyk" value={(customer.language || '—').toUpperCase()} />
        <Chip label="Registrace" value={fmtDate(customer.created_at) || '—'} />
        <Chip label="Věk" value={age || '—'} />
        <Chip label="Doklad" value={customer.id_verified_at ? 'Ověřen' : (customer.id_number ? 'Zadán' : '—')} tone={customer.id_verified_at ? 'green' : undefined} />
        <Chip label="Řidičák" value={customer.license_verified_at ? 'Ověřen' : (customer.license_number ? 'Zadán' : '—')} tone={customer.license_verified_at ? 'green' : undefined} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 items-start">
        {/* Osobní údaje */}
        <Card>
          <SectionTitle>Osobní údaje</SectionTitle>
          <div className="grid grid-cols-2 gap-3.5">
            <div className="col-span-2"><Field label="Jméno" value={customer.full_name} onChange={v => set('full_name', v)} /></div>
            <div className="col-span-2"><Field label="Email" value={customer.email} disabled /></div>
            <Field label="Telefon" value={customer.phone} onChange={v => set('phone', v)} />
            <Field label={`Datum narození${age ? ` · ${age}` : ''}`} value={customer.date_of_birth} onChange={v => set('date_of_birth', v)} type="date" />
          </div>
        </Card>

        {/* Adresa */}
        <Card>
          <SectionTitle>Adresa</SectionTitle>
          <div className="grid grid-cols-2 gap-3.5">
            <div className="col-span-2"><Field label="Ulice" value={customer.street} onChange={v => set('street', v)} /></div>
            <Field label="Město" value={customer.city} onChange={v => set('city', v)} />
            <Field label="PSČ" value={customer.zip} onChange={v => set('zip', v)} />
            <div className="col-span-2"><Field label="Země" value={customer.country || 'CZ'} onChange={v => set('country', v)} /></div>
          </div>
        </Card>

        {/* Firemní údaje (web rezervace — checkbox „Firemní údaje" v kroku 3) */}
        <Card>
          <SectionTitle>Firemní údaje</SectionTitle>
          <div className="grid grid-cols-2 gap-3.5">
            <div className="col-span-2"><Field label="Název firmy" value={customer.company_name} onChange={v => set('company_name', v)} /></div>
            <Field label="IČO" value={customer.ico} onChange={v => set('ico', v)} />
            <Field label="DIČ" value={customer.dic} onChange={v => set('dic', v)} />
            <div className="col-span-2"><Field label="Adresa firmy (sídlo)" value={customer.company_address} onChange={v => set('company_address', v)} /></div>
          </div>
        </Card>

        {/* Doklady a oprávnění */}
        <Card className="lg:col-span-2">
          <SectionTitle>Doklady a oprávnění</SectionTitle>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3.5">
            <DocBox title="Doklad totožnosti" badge={<VerifyBadge verified={!!customer.id_verified_at} date={fmtDate(customer.id_verified_at)} />}>
              <Field label="Číslo dokladu" value={customer.id_number} onChange={v => set('id_number', v)} />
              <Info label="Platnost do" value={fmtDate(customer.id_verified_until)} />
            </DocBox>

            <DocBox title="Řidičský průkaz" badge={<VerifyBadge verified={!!customer.license_verified_at} date={fmtDate(customer.license_verified_at)} />}>
              <Field label="Číslo ŘP" value={customer.license_number} onChange={v => set('license_number', v)} />
              <div>
                <div className="text-[11px] font-bold uppercase tracking-wide mb-1" style={{ color: C.muted }}>Skupiny</div>
                <div className="flex flex-wrap gap-1">
                  {groups.length > 0 ? groups.map(g => <Badge key={g} label={g} color={C.gdk} bg="#dcfce7" />) : <span className="text-sm" style={{ color: C.faint }}>{'—'}</span>}
                </div>
              </div>
              <Field label="Platnost ŘP do" value={customer.license_expiry} onChange={v => set('license_expiry', v)} type="date" />
            </DocBox>

            <DocBox title="Cestovní pas" badge={<VerifyBadge verified={!!customer.passport_verified_at} date={fmtDate(customer.passport_verified_at)} />}>
              <Info label="Ověřeno" value={fmtDate(customer.passport_verified_at)} />
              <Info label="Platnost do" value={fmtDate(customer.passport_verified_until)} />
            </DocBox>
          </div>
        </Card>

        {/* Výbava */}
        <Card>
          <SectionTitle>Výbava (velikosti)</SectionTitle>
          <GearSizes gearSizes={customer.gear_sizes} />
        </Card>

        {/* Admin poznámky */}
        <Card>
          <SectionTitle>Admin poznámky</SectionTitle>
          <Field label="Poznámka k zákazníkovi" value={customer.reliability_score?.notes} onChange={v => set('reliability_score', { ...customer.reliability_score, notes: v })} />
        </Card>

        {/* Komunikace a notifikace — položkově */}
        <Card>
          <SectionTitle right={<span className="text-[11px]" style={{ color: C.muted }}>Klikem přepneš</span>}>Komunikace a notifikace</SectionTitle>
          <ConsentRow label="Email" desc="Transakční vždy · marketing jen se souhlasem" checked={!!customer.consent_email} unknown={unknownC(customer.consent_email)} onChange={v => set('consent_email', v)} />
          <ConsentRow label="SMS" desc="Transakční vždy · marketing jen se souhlasem" checked={!!customer.consent_sms} unknown={unknownC(customer.consent_sms)} onChange={v => set('consent_sms', v)} />
          <ConsentRow label="WhatsApp" desc="Transakční vždy · marketing jen se souhlasem" checked={!!customer.consent_whatsapp} unknown={unknownC(customer.consent_whatsapp)} onChange={v => set('consent_whatsapp', v)} />
          <ConsentRow label="Push" desc="Při vypnutí se push neodešle (mimo rezervaci)" checked={!!customer.consent_push} unknown={unknownC(customer.consent_push)} onChange={v => set('consent_push', v)} />
          <ConsentRow label="Marketing" desc="Hromadné kampaně (broadcast)" checked={!!customer.marketing_consent} unknown={unknownC(customer.marketing_consent)} onChange={v => set('marketing_consent', v)} />
        </Card>

        {/* Soukromí a souhlasy — položkově */}
        <Card>
          <SectionTitle right={<span className="text-[11px]" style={{ color: C.muted }}>Klikem přepneš</span>}>Soukromí a souhlasy</SectionTitle>
          <ConsentRow label="VOP" required desc="Obchodní podmínky — nutné pro rezervaci" checked={!!customer.consent_vop} unknown={unknownC(customer.consent_vop)} onChange={v => set('consent_vop', v)} />
          <ConsentRow label="GDPR" required desc="Souhlas se zpracováním osobních údajů" checked={!!customer.consent_gdpr} unknown={unknownC(customer.consent_gdpr)} onChange={v => set('consent_gdpr', v)} />
          <ConsentRow label="Zpracování dat" required desc="Nutné pro vyřízení rezervace" checked={!!customer.consent_data_processing} unknown={unknownC(customer.consent_data_processing)} onChange={v => set('consent_data_processing', v)} />
          <ConsentRow label="Smlouva" desc="Souhlas s nájemní smlouvou" checked={!!customer.consent_contract} unknown={unknownC(customer.consent_contract)} onChange={v => set('consent_contract', v)} />
          <ConsentRow label="Foto" desc="Souhlas s fotodokumentací" checked={!!customer.consent_photo} unknown={unknownC(customer.consent_photo)} onChange={v => set('consent_photo', v)} />
        </Card>

        {/* OS oprávnění z telefonu (zrcadlí app_permissions) */}
        {(() => {
          const ap = customer.app_permissions || null
          const has = ap && typeof ap === 'object'
          const reported = has && ap.reported_at ? fmtDate(ap.reported_at) : null
          const permRow = (lbl, key) => (
            <ConsentRow key={key} label={lbl} readOnly unknown={!has || ap[key] === undefined || ap[key] === null} checked={!!(has && ap[key])} />
          )
          return (
            <Card className="lg:col-span-2">
              <SectionTitle right={reported ? <span className="text-[11px]" style={{ color: C.muted }}>z telefonu · {reported}{has && ap.platform ? ` · ${ap.platform}` : ''}</span> : null}>
                Oprávnění aplikace (telefon)
              </SectionTitle>
              {!has && (
                <div className="text-[12px] mb-1" style={{ color: C.muted }}>
                  Zatím nenahlášeno z aplikace — zákazník buď nemá appku, nebo má starší verzi (oprávnění se hlásí od v1.0.8).
                </div>
              )}
              <div className="grid sm:grid-cols-2 gap-x-6">
                {permRow('Poloha', 'location')}
                {permRow('Fotoaparát', 'camera')}
                {permRow('Galerie / fotky', 'photos')}
                {permRow('Notifikace', 'notification')}
              </div>
            </Card>
          )
        })()}
      </div>

      {error && <p className="text-sm" style={{ color: C.red }}>{error}</p>}

      <div className="flex flex-wrap items-center gap-3 pt-1">
        <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit změny'}</Button>
        <button
          onClick={onBlock}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '10px 18px', background: customer.is_blocked ? '#dcfce7' : '#fff', color: customer.is_blocked ? C.gdk : C.red, border: `1.5px solid ${customer.is_blocked ? '#86e3a3' : '#f3c2c2'}` }}
        >
          {customer.is_blocked ? 'Odblokovat' : 'Zablokovat'}
        </button>
        <div className="flex-1" />
        <button onClick={onDelete} className="text-sm font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: C.red, opacity: 0.8 }}>
          Smazat zákazníka
        </button>
      </div>
    </div>
  )
}
