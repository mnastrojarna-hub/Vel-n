// Lišta Rezervací na telefonu (< 768 px): přepínač pohledů jako segmenty přes celou šířku,
// hledání přes celou šířku, „☰ Filtry“ + „Nová rezervace“. Rychlé filtry (stav, platba,
// řazení, jen budoucí, skrýt testovací) jsou v rozbaleném panelu Filtry (BookingsExtendedFilters),
// ať nezabírají celou obrazovku. Hromadná správa je u výběru karet (BookingsListMobile).
import Button from '../../components/ui/Button'
import SearchInput from '../../components/ui/SearchInput'

export default function BookingsToolbarPhone({ views, view, setView, search, onSearch, showFilters, setShowFilters, filterCount, onNew }) {
  const list = view === 'Seznam'
  return (
    <div className="mb-4 space-y-2.5">
      {/* inline mřížka — třídu .grid-cols-3 globální CSS na telefonu láme na 2 sloupce */}
      <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(3, minmax(0, 1fr))' }}>
        {views.map(v => (
          <button key={v} onClick={() => setView(v)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer leading-tight"
            style={{ padding: '6px 8px', minHeight: 44, background: view === v ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: view === v ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {v}
          </button>
        ))}
      </div>
      {list && <SearchInput value={search} onChange={onSearch} placeholder="Hledat zákazníka, motorku…" fullWidth />}
      <div className="grid gap-2" style={{ gridTemplateColumns: list ? 'minmax(0, 1fr) minmax(0, 1.4fr)' : '1fr' }}>
        {list && (
          <button onClick={() => setShowFilters(!showFilters)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer inline-flex items-center justify-center gap-1.5"
            style={{ minHeight: 44, padding: '8px 12px', background: showFilters ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            ☰ Filtry {filterCount > 0 && <span className="inline-block rounded-full text-sm" style={{ background: showFilters ? '#fff' : '#74FB71', color: '#1a2e22', padding: '1px 7px' }}>{filterCount}</span>}
          </button>
        )}
        <Button green onClick={onNew} className="justify-center" style={{ minHeight: 44, padding: '8px 12px' }}>+ Nová rezervace</Button>
      </div>
    </div>
  )
}
