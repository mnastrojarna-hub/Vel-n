import { BULK_SEGMENTS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS } from './messageHelpers'

export function BulkSegmentSelector({ bulkSegment, setBulkSegment, bulkCountry, setBulkCountry, bulkLanguage, setBulkLanguage, bulkCountLoading, bulkRecipientCount }) {
  return (
    <div className="space-y-3">
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Skupina prijemcu</label>
      <div className="grid grid-cols-2 gap-2">
        {BULK_SEGMENTS.map(s => (
          <div key={s.value} onClick={() => setBulkSegment(s.value)} className="cursor-pointer rounded-card"
            style={{ padding: 10, border: bulkSegment === s.value ? '2px solid #74FB71' : '2px solid #d4e8e0', background: bulkSegment === s.value ? '#f0fdf0' : '#fff' }}>
            <div className="flex items-center gap-2 mb-0.5"><span style={{ fontSize: 16 }}>{s.icon}</span><span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{s.label}</span></div>
            <div style={{ fontSize: 11, color: '#6b7280' }}>{s.desc}</div>
          </div>
        ))}
      </div>
      <div className="flex gap-3">
        <div className="flex-1"><label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Zeme</label>
          <select value={bulkCountry} onChange={e => setBulkCountry(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}</select></div>
        <div className="flex-1"><label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Jazyk</label>
          <select value={bulkLanguage} onChange={e => setBulkLanguage(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}</select></div>
      </div>
      <div className="flex items-center gap-2">
        {bulkCountLoading ? <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" /> : (
          <><span style={{ fontSize: 20 }}>{'\ud83d\udc65'}</span><span className="text-xl font-black" style={{ color: '#1a8a18' }}>{bulkRecipientCount}</span><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>prijemcu</span></>
        )}
      </div>
    </div>
  )
}

export function SingleCustomerField({ selectedCustomer, clearCustomer, customerSearch, setCustomerSearch, customers, loadingCustomers, selectCustomer, recipientWarning }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Prijemce</label>
      {selectedCustomer ? (
        <div className="flex items-center gap-3 rounded-btn" style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex-1">
            <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{selectedCustomer.full_name || 'Bez jmena'}</div>
            <div className="flex gap-4 mt-0.5" style={{ fontSize: 12, color: '#1a2e22' }}>
              {selectedCustomer.phone && <span>{'\ud83d\udcf1'} {selectedCustomer.phone}</span>}
              {selectedCustomer.email && <span>{'\ud83d\udce7'} {selectedCustomer.email}</span>}
            </div>
          </div>
          <button onClick={clearCustomer} className="cursor-pointer border-none rounded-btn text-sm font-bold" style={{ padding: '4px 10px', background: '#fee2e2', color: '#dc2626' }}>Zmenit</button>
        </div>
      ) : (
        <div className="relative">
          <input type="text" placeholder="Hledat jmeno, email, telefon..." value={customerSearch} onChange={e => setCustomerSearch(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          {(customers.length > 0 || loadingCustomers) && customerSearch.trim() && (
            <div className="absolute left-0 right-0 top-full mt-1 bg-white rounded-card shadow-card z-10" style={{ border: '1px solid #d4e8e0', maxHeight: 240, overflow: 'auto' }}>
              {loadingCustomers ? <div className="flex justify-center py-3"><div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div> : (
                customers.map(c => (
                  <div key={c.id} onClick={() => selectCustomer(c)} className="cursor-pointer transition-colors" style={{ padding: '8px 12px', borderBottom: '1px solid #f1faf7' }}
                    onMouseEnter={e => e.currentTarget.style.background = '#f1faf7'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                    <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{c.full_name || 'Bez jmena'}</div>
                    <div style={{ fontSize: 11, color: '#1a2e22' }}>{c.phone && `\ud83d\udcf1 ${c.phone}`}{c.phone && c.email && ' \u00b7 '}{c.email && `\ud83d\udce7 ${c.email}`}</div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      )}
      {recipientWarning && <div className="mt-1 text-sm font-bold" style={{ color: '#dc2626' }}>{'\u26a0'} {recipientWarning}</div>}
    </div>
  )
}
