import { SelectAllCheckbox, RowCheckbox } from '../components/ui/BulkActionsBar'

// Slevové kódy na telefonu a tabletu (< 1024 px): kompaktní karty místo 8–9sloupcových
// tabulek (sloupec Akce by byl mimo obraz). Stejná data i akce jako tabulka na PC;
// klepnutí na kód otevře detail. Tablet = 2 karty vedle sebe.

const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : null

function SelectAll({ items, selectedIds, setSelectedIds }) {
  return (
    <label className="inline-flex items-center gap-2 mb-3 rounded-btn bg-white cursor-pointer text-sm font-extrabold uppercase tracking-wide"
      style={{ padding: '8px 14px', minHeight: 40, color: '#1a2e22', boxShadow: '0 2px 8px rgba(15,26,20,.08)' }}>
      <SelectAllCheckbox items={items} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
      Vybrat vše
    </label>
  )
}

function Empty({ children }) {
  return <div className="bg-white rounded-card shadow-card text-sm" style={{ padding: '16px 18px', color: '#0f1a14' }}>{children}</div>
}

function CardShell({ id, selectedIds, setSelectedIds, code, onCode, status, children, actions }) {
  return (
    <div className="rounded-card shadow-card flex flex-col gap-2" style={{ padding: 12, background: selectedIds.has(id) ? '#fef9c3' : '#fff' }}>
      <div className="flex items-center gap-2">
        <label className="flex items-center justify-center cursor-pointer shrink-0" style={{ width: 32, height: 40 }}>
          <RowCheckbox id={id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
        </label>
        <button type="button" onClick={onCode} className="font-mono font-bold text-sm cursor-pointer text-left min-w-0"
          style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0, minHeight: 40, overflowWrap: 'anywhere' }}>
          {code}
        </button>
        <div className="ml-auto shrink-0">{status}</div>
      </div>
      <div className="flex flex-col gap-1" style={{ paddingLeft: 40 }}>{children}</div>
      <div className="flex flex-wrap gap-2" style={{ paddingLeft: 40 }}>{actions}</div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div className="flex items-baseline gap-2 text-sm" style={{ color: '#0f1a14' }}>
      <span className="text-xs font-extrabold uppercase tracking-wide shrink-0" style={{ color: '#4a6357', minWidth: 84 }}>{label}</span>
      <span className="min-w-0" style={{ overflowWrap: 'anywhere' }}>{children}</span>
    </div>
  )
}

export function CardAction({ color, onClick, children }) {
  return (
    <button type="button" onClick={onClick} className="rounded-btn text-sm font-bold cursor-pointer"
      style={{ color, background: '#f1faf7', border: '1px solid #d4e8e0', padding: '6px 14px', minHeight: 40 }}>
      {children}
    </button>
  )
}

export function PromoCardsMobile({ codes, owners, selectedIds, setSelectedIds, onDetail, onOwner, onToggle, onEdit, onDelete }) {
  if (codes.length === 0) return <Empty>Žádné promo kódy</Empty>
  return (
    <div>
      <SelectAll items={codes} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {codes.map(c => {
          const isActive = c.active && (!c.valid_to || new Date(c.valid_to) >= new Date())
          const isExpired = c.valid_to && new Date(c.valid_to) < new Date()
          const isLimitReached = c.max_uses && (c.used_count || 0) >= c.max_uses
          const status = (
            <button type="button" onClick={() => onToggle(c)}
              className="rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
              style={{ padding: '6px 12px', minHeight: 36, border: 'none', background: isActive ? '#dcfce7' : isExpired ? '#fee2e2' : '#f3f4f6', color: isActive ? '#1a8a18' : isExpired ? '#dc2626' : '#6b7280' }}
              title={isExpired ? 'Expirovaný' : isActive ? 'Klikni pro deaktivaci' : 'Klikni pro aktivaci'}>
              {isExpired ? 'Expirovaný' : isActive ? 'Aktivní' : 'Neaktivní'}
            </button>
          )
          return (
            <CardShell key={c.id} id={c.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} code={c.code} onCode={() => onDetail(c)} status={status}
              actions={<>
                <CardAction color="#2563eb" onClick={() => onEdit(c)}>Upravit</CardAction>
                <CardAction color="#b45309" onClick={() => onToggle(c)}>{c.active ? 'Deaktivovat' : 'Aktivovat'}</CardAction>
                <CardAction color="#dc2626" onClick={() => onDelete(c)}>Smazat</CardAction>
              </>}>
              <Field label="Sleva"><strong>{c.type === 'percent' ? `${c.value}%` : `${(c.value || 0).toLocaleString('cs-CZ')} Kč`}</strong></Field>
              <Field label="Platnost">
                {fmtDate(c.valid_from) || '—'}{' → '}
                {c.valid_to ? <span style={{ color: isExpired ? '#dc2626' : undefined, fontWeight: isExpired ? 700 : undefined }}>{fmtDate(c.valid_to)}</span> : '∞'}
              </Field>
              <Field label="Použití">
                <span style={{ color: isLimitReached ? '#dc2626' : undefined, fontWeight: isLimitReached ? 700 : undefined }}>{c.used_count ?? 0} / {c.max_uses ?? '∞'}</span>
                {isLimitReached && <span className="ml-1" style={{ color: '#dc2626' }}>(vyčerpáno)</span>}
              </Field>
              {owners[c.code] && (
                <Field label="Zákazník">
                  <button type="button" onClick={() => onOwner(owners[c.code])} className="text-sm font-bold cursor-pointer text-left"
                    style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0, minHeight: 28 }}>
                    {owners[c.code].name || 'Zákazník'}
                  </button>
                </Field>
              )}
            </CardShell>
          )
        })}
      </div>
    </div>
  )
}

export function VoucherCardsMobile({ vouchers, selectedIds, setSelectedIds, onDetail, onRedeem, onEdit, onCancel, renderStatus, categoryLabel, sourceLabel }) {
  if (vouchers.length === 0) return <Empty>Žádné dárkové poukazy</Empty>
  return (
    <div>
      <SelectAll items={vouchers} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {vouchers.map(v => (
          <CardShell key={v.id} id={v.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} code={v.code} onCode={() => onDetail(v)} status={renderStatus(v.status)}
            actions={<>
              {v.status === 'active' && <CardAction color="#1a8a18" onClick={() => onRedeem(v)}>Uplatnit</CardAction>}
              <CardAction color="#2563eb" onClick={() => onEdit(v)}>Upravit</CardAction>
              {v.status === 'active' && <CardAction color="#dc2626" onClick={() => onCancel(v)}>Zrušit</CardAction>}
            </>}>
            <Field label="Hodnota"><strong>{Number(v.amount || 0).toLocaleString('cs-CZ')} {v.currency}</strong></Field>
            <Field label="Kupující">{v.buyer_name || v.buyer_email || '—'}</Field>
            <Field label="Platnost">{fmtDate(v.valid_from) || '—'}{' → '}{fmtDate(v.valid_until) || '∞'}</Field>
            <Field label="Kategorie">{categoryLabel(v)}</Field>
            <Field label="Zdroj">{sourceLabel(v)}</Field>
          </CardShell>
        ))}
      </div>
    </div>
  )
}
