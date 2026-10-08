import { useMediaQuery } from '../../hooks/useIsMobile'
import { BULK_SEGMENTS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS } from './messageHelpers'

// Příjemce ruční zprávy na telefonu/tabletu (≤ 1023 px): hledání přes celou šířku,
// výsledky jako velké řádky pro prst, skupiny pod sebou. Stav i dotazy drží ManualSendTab.
export const MS_LABEL = 'block font-extrabold uppercase tracking-wide'
export const MS_LABEL_STYLE = { fontSize: 13, color: '#1a2e22', marginBottom: 6 }
export const MS_INPUT = { padding: '10px 12px', minHeight: 44, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }

// Texty s diakritikou pro mobilní zobrazení (hodnoty zůstávají z messageHelpers)
const SEG_TEXT = {
  all: ['Všichni zákazníci', 'Všichni s kontaktními údaji'],
  vip: ['VIP zákazníci', 'Reliability skóre > 80'],
  past_customers: ['Minulí zákazníci', 'Alespoň 1 dokončená rezervace'],
  new_no_booking: ['Noví bez rezervace', 'Registrovaní bez půjčení'],
}
const COUNTRY_TEXT = { '': 'Všechny země', CZ: 'Česko', SK: 'Slovensko', DE: 'Německo', AT: 'Rakousko', PL: 'Polsko' }
const LANG_TEXT = { '': 'Všechny jazyky', cs: 'Čeština', en: 'English', de: 'Deutsch' }

const WRAP = { overflowWrap: 'anywhere', minWidth: 0 }
const Spinner = () => <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd shrink-0" />

function plural(n) {
  return n === 1 ? 'příjemce' : n >= 2 && n <= 4 ? 'příjemci' : 'příjemců'
}

function Contacts({ c, size }) {
  if (!c.phone && !c.email) return null
  return (
    <span className="flex flex-wrap" style={{ columnGap: 12, rowGap: 2, marginTop: 2, fontSize: size, color: '#1a2e22' }}>
      {c.phone && <span style={WRAP}>📱 {c.phone}</span>}
      {c.email && <span style={WRAP}>📧 {c.email}</span>}
    </span>
  )
}

export function ManualSendMobileSingle({
  selectedCustomer, clearCustomer, customerSearch, setCustomerSearch,
  customers, loadingCustomers, selectCustomer, recipientWarning,
}) {
  const showList = customerSearch.trim() && (loadingCustomers || customers.length > 0)
  return (
    <div>
      <div className={MS_LABEL} style={MS_LABEL_STYLE}>Příjemce</div>
      {selectedCustomer ? (
        <div className="flex items-center rounded-card" style={{ gap: 10, padding: '10px 12px', background: '#e8fee7', border: '1px solid #74FB71' }}>
          <div style={{ flex: 1, ...WRAP }}>
            <div className="font-bold" style={{ fontSize: 15, color: '#0f1a14', ...WRAP }}>{selectedCustomer.full_name || 'Bez jména'}</div>
            <Contacts c={selectedCustomer} size={13} />
          </div>
          <button type="button" onClick={clearCustomer}
            className="shrink-0 rounded-btn font-bold cursor-pointer border-none"
            style={{ minHeight: 40, padding: '8px 14px', fontSize: 14, background: '#fee2e2', color: '#dc2626' }}>
            Změnit
          </button>
        </div>
      ) : (
        <>
          <div className="relative">
            <span className="absolute" style={{ left: 12, top: '50%', transform: 'translateY(-50%)', fontSize: 14, pointerEvents: 'none' }}>🔍</span>
            <input
              type="text" inputMode="search" enterKeyHint="search" autoComplete="off"
              placeholder="Hledat jméno, e-mail, telefon…"
              value={customerSearch}
              onChange={e => setCustomerSearch(e.target.value)}
              className="w-full rounded-btn text-sm outline-none"
              style={{ ...MS_INPUT, paddingLeft: 36, paddingRight: customerSearch ? 44 : 12 }}
            />
            {customerSearch && (
              <button type="button" aria-label="Vymazat hledání" onClick={() => setCustomerSearch('')}
                className="absolute flex items-center justify-center cursor-pointer border-none rounded-btn"
                style={{ right: 2, top: '50%', transform: 'translateY(-50%)', width: 40, height: 40, background: 'transparent', color: '#1a2e22', fontSize: 16 }}>
                ✕
              </button>
            )}
          </div>
          {showList && (
            <div className="bg-white rounded-card shadow-card" style={{ marginTop: 6, border: '1px solid #d4e8e0', maxHeight: 'min(360px, 55vh)', overflowY: 'auto', overscrollBehavior: 'contain' }}>
              {loadingCustomers ? (
                <div className="flex items-center justify-center" style={{ gap: 10, padding: 14, fontSize: 14, color: '#1a2e22' }}>
                  <Spinner /> Hledám…
                </div>
              ) : customers.map(c => (
                <button key={c.id} type="button" onClick={() => selectCustomer(c)}
                  className="block w-full text-left cursor-pointer border-none"
                  style={{ minHeight: 52, padding: '10px 14px', background: '#fff', borderBottom: '1px solid #f1faf7' }}>
                  <span className="block font-bold" style={{ fontSize: 15, color: '#0f1a14', ...WRAP }}>{c.full_name || 'Bez jména'}</span>
                  <Contacts c={c} size={12} />
                </button>
              ))}
            </div>
          )}
        </>
      )}
      {recipientWarning && (
        <div className="font-bold" style={{ marginTop: 6, fontSize: 14, color: '#dc2626' }}>⚠ {recipientWarning}</div>
      )}
    </div>
  )
}

export function ManualSendMobileBulk({
  bulkSegment, setBulkSegment, bulkCountry, setBulkCountry, bulkLanguage, setBulkLanguage,
  bulkCountLoading, bulkRecipientCount,
}) {
  const twoCols = useMediaQuery('(min-width: 640px)')
  const selectStyle = { ...MS_INPUT, color: '#1a2e22' }
  return (
    <div className="flex flex-col" style={{ gap: 14 }}>
      <div>
        <div className={MS_LABEL} style={MS_LABEL_STYLE}>Skupina příjemců</div>
        <div role="radiogroup" style={{ display: 'grid', gridTemplateColumns: twoCols ? 'repeat(2, minmax(0, 1fr))' : 'minmax(0, 1fr)', gap: 8 }}>
          {BULK_SEGMENTS.map(s => {
            const on = bulkSegment === s.value
            const [label, desc] = SEG_TEXT[s.value] || [s.label, s.desc]
            return (
              <button key={s.value} type="button" role="radio" aria-checked={on} onClick={() => setBulkSegment(s.value)}
                className="flex items-center text-left cursor-pointer rounded-card"
                style={{ gap: 10, minHeight: 56, padding: '10px 12px', border: on ? '2px solid #74FB71' : '2px solid #d4e8e0', background: on ? '#f0fdf0' : '#fff' }}>
                <span className="shrink-0" style={{ fontSize: 20 }}>{s.icon}</span>
                <span style={{ flex: 1, ...WRAP }}>
                  <span className="block font-bold" style={{ fontSize: 14, color: '#0f1a14' }}>{label}</span>
                  <span className="block" style={{ fontSize: 12, color: '#4b5563', marginTop: 1 }}>{desc}</span>
                </span>
                {on && <span className="shrink-0 font-black" style={{ fontSize: 16, color: '#1a8a18' }}>✓</span>}
              </button>
            )
          })}
        </div>
      </div>

      {/* Filtry: vedle sebe, na úzkém displeji pod sebou */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', gap: 10 }}>
        <label className="block" style={{ minWidth: 0 }}>
          <span className="block font-bold" style={{ fontSize: 13, color: '#1a2e22', marginBottom: 4 }}>Země</span>
          <select value={bulkCountry} onChange={e => setBulkCountry(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={selectStyle}>
            {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{COUNTRY_TEXT[o.value] ?? o.label}</option>)}
          </select>
        </label>
        <label className="block" style={{ minWidth: 0 }}>
          <span className="block font-bold" style={{ fontSize: 13, color: '#1a2e22', marginBottom: 4 }}>Jazyk</span>
          <select value={bulkLanguage} onChange={e => setBulkLanguage(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={selectStyle}>
            {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{LANG_TEXT[o.value] ?? o.label}</option>)}
          </select>
        </label>
      </div>

      {/* Počet příjemců */}
      <div className="flex items-center rounded-btn" style={{ gap: 10, minHeight: 52, padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        {bulkCountLoading ? (
          <><Spinner /><span style={{ fontSize: 14, color: '#1a2e22' }}>Počítám příjemce…</span></>
        ) : (
          <>
            <span style={{ fontSize: 20 }}>👥</span>
            <span className="font-black" style={{ fontSize: 22, color: '#1a8a18' }}>{bulkRecipientCount}</span>
            <span className="font-bold" style={{ fontSize: 14, color: '#1a2e22' }}>{plural(bulkRecipientCount)}</span>
          </>
        )}
      </div>
    </div>
  )
}
