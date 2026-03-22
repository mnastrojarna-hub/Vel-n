import { FField, FLabel, FSelWrap } from './BookingsFilters'

export default function BookingsExtendedFilters({ filters, setF, branches, resetFilters }) {
  return (
    <div className="mb-5 p-4 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center justify-between mb-3">
        <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rozšířené filtry rezervací</span>
        <button onClick={resetFilters} className="text-sm font-bold cursor-pointer underline" style={{ color: '#1a2e22' }}>Resetovat</button>
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <FField label="Zákazník" value={filters.customer} onChange={v => setF('customer', v)} />
        <FField label="Model motorky" value={filters.motoModel} onChange={v => setF('motoModel', v)} />
        <div><FLabel>Pobočka</FLabel>
          <FSelWrap value={filters.branch} onChange={v => setF('branch', v)}
            options={[{ value: '', label: 'Všechny' }, ...branches.map(b => ({ value: b.id, label: b.name }))]} />
        </div>
        <div><FLabel>Země zákazníka</FLabel>
          <FSelWrap value={filters.country} onChange={v => setF('country', v)}
            options={[{ value: '', label: 'Všechny' }, { value: 'CZ', label: 'Česko' }, { value: 'SK', label: 'Slovensko' }, { value: 'DE', label: 'Německo' }, { value: 'AT', label: 'Rakousko' }]} />
        </div>
        <FField label="Datum od" value={filters.dateFrom} onChange={v => setF('dateFrom', v)} type="date" />
        <FField label="Datum do" value={filters.dateTo} onChange={v => setF('dateTo', v)} type="date" />
        <FField label="Cena od (Kč)" value={filters.priceMin} onChange={v => setF('priceMin', v)} type="number" />
        <FField label="Cena do (Kč)" value={filters.priceMax} onChange={v => setF('priceMax', v)} type="number" />
        <FField label="Min. dní" value={filters.durationMin} onChange={v => setF('durationMin', v)} type="number" />
        <FField label="Max. dní" value={filters.durationMax} onChange={v => setF('durationMax', v)} type="number" />
        <div><FLabel>Skupina ŘP</FLabel>
          <FSelWrap value={filters.licenseGroup} onChange={v => setF('licenseGroup', v)}
            options={[{ value: '', label: 'Všechny' }, ...['A', 'A1', 'A2', 'AM', 'B'].map(g => ({ value: g, label: g }))]} />
        </div>
        <div><FLabel>Řadit dle</FLabel>
          <FSelWrap value={filters.sortBy} onChange={v => setF('sortBy', v)}
            options={[{ value: 'start_date', label: 'Datum začátku' }, { value: 'end_date', label: 'Datum konce' }, { value: 'total_price', label: 'Částka' }, { value: 'created_at', label: 'Vytvořeno' }]} />
        </div>
      </div>
    </div>
  )
}
