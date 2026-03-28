import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Badge from '../components/ui/Badge'
import { classifyEntry } from '../lib/revenueUtils'
import { DetailRow, SummaryCard, MiniStat, CheckboxFilterGroup, TypeBadge } from './financeHelpers'

const PERIODS = [{ value: 'month', label: 'Mesic' }, { value: 'quarter', label: 'Kvartal' }, { value: 'year', label: 'Rok' }]

export default function FinanceOverview({ filters, setFilters, defaultFilters, categories, summary, chartData, transactions, recentInvoices, shopPayments, invoiceSums, loading, error, detailTx, setDetailTx, fmt, handleExport, debugMode }) {
  const profit = summary.revenue - summary.expense
  return (<>
    <div className="flex flex-wrap items-center gap-3 mb-5">
      {PERIODS.map(p => <button key={p.value} onClick={() => setFilters(f => ({ ...f, period: p.value }))} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 16px', background: filters.period === p.value ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: filters.period === p.value ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{p.label}</button>)}
      <CheckboxFilterGroup label="Typ" values={filters.types || []} onChange={v => setFilters(f => ({ ...f, types: v }))} options={[{ value: 'revenue', label: 'Prijmy' }, { value: 'expense', label: 'Vydaje' }]} />
      {categories.length > 0 && <select value={filters.category} onChange={e => setFilters(f => ({ ...f, category: e.target.value }))} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}><option value="">Vsechny kategorie</option>{categories.map(c => <option key={c} value={c}>{c}</option>)}</select>}
      <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))} placeholder="Hledat popis..." className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 150 }} />
      <select value={filters.sort} onChange={e => setFilters(f => ({ ...f, sort: e.target.value }))} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        <option value="date_desc">Datum {'\u2193'} nejnovejsi</option><option value="date_asc">Datum {'\u2191'} nejstarsi</option>
        <option value="amount_desc">Castka {'\u2193'} nejvyssi</option><option value="amount_asc">Castka {'\u2191'} nejnizsi</option>
      </select>
      <button onClick={() => { setFilters({ ...defaultFilters }); localStorage.removeItem('velin_finance_filters') }} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>Reset</button>
      <div className="ml-auto flex gap-2"><Button onClick={() => handleExport('csv')}>CSV</Button><Button onClick={() => handleExport('xlsx')}>XLSX</Button></div>
    </div>

    {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

    {loading ? <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div> : (<>
      <div className="grid grid-cols-4 gap-4 mb-5">
        <SummaryCard label="Mesicni trzby" value={fmt(summary.revenue)} color="#1a8a18" />
        <SummaryCard label="Mesicni naklady" value={fmt(summary.expense)} color="#dc2626" />
        <SummaryCard label="Zisk" value={fmt(profit)} color={profit >= 0 ? '#1a8a18' : '#dc2626'} />
        <SummaryCard label="Neuhrazene zalohy" value={fmt(summary.unpaid)} count={summary.unpaidCount} color="#b45309" />
      </div>

      {chartData.length > 0 && <Card className="mb-5"><h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Trzby vs. naklady (12 mesicu)</h3>
        <div className="flex items-end gap-1" style={{ height: 120 }}>{chartData.map((m, i) => { const max = Math.max(...chartData.map(c => Math.max(c.revenue, c.expense)), 1); return (<div key={i} className="flex-1 flex flex-col items-center gap-0.5"><div className="w-full flex gap-0.5" style={{ height: 100 }}><div className="flex-1 rounded-t" style={{ background: '#74FB71', height: `${(m.revenue / max) * 100}%`, marginTop: 'auto' }} /><div className="flex-1 rounded-t" style={{ background: '#fee2e2', height: `${(m.expense / max) * 100}%`, marginTop: 'auto' }} /></div><span className="text-[8px] font-bold" style={{ color: '#1a2e22' }}>{m.label}</span></div>) })}</div>
      </Card>}

      {debugMode && <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}><strong>DIAGNOSTIKA Finance</strong><br/><div>invoices: {recentInvoices.length}</div><div>accounting_entries: {transactions.length}</div><div>shop_orders (paid): {shopPayments.length}</div></div>}

      <Card className="mb-5"><h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Prehled dle typu</h3>
        <div className="grid grid-cols-4 gap-3 mb-3"><MiniStat label="Zalohy (ZF)" value={fmt(invoiceSums.zf)} color="#2563eb" /><MiniStat label="Doklady k platbe (DP)" value={fmt(invoiceSums.dp)} color="#0891b2" /><MiniStat label="Konecne (KF)" value={fmt(invoiceSums.kf)} color="#1a8a18" /><MiniStat label="Pronajem (dokonceno)" value={fmt(invoiceSums.rental)} color="#059669" /></div>
        <div className="grid grid-cols-4 gap-3"><MiniStat label="E-shop prodeje" value={fmt(invoiceSums.eshop)} color="#8b5cf6" /><MiniStat label="Shop ZF" value={fmt(invoiceSums.shopZf)} color="#7c3aed" /><MiniStat label="Shop KF" value={fmt(invoiceSums.shopKf)} color="#059669" /><MiniStat label="Poukazy (slevy)" value={fmt(invoiceSums.vouchers)} color="#b45309" /></div>
      </Card>

      <Card className="mb-5"><h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Faktury (ZF, DP, KF)</h3>
        {recentInvoices.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Zadne faktury</p> : (
          <Table><thead><TRow header><TH>Cislo</TH><TH>Typ</TH><TH>Zakaznik</TH><TH>Castka</TH><TH>Stav</TH><TH>Datum</TH></TRow></thead>
            <tbody>{recentInvoices.map(inv => { const typeLabels = { advance: 'ZF', proforma: 'ZF', payment_receipt: 'DP', final: 'KF', shop_proforma: 'Shop ZF', shop_final: 'Shop KF' }; const typeColors = { advance: '#2563eb', proforma: '#2563eb', payment_receipt: '#0891b2', final: '#1a8a18', shop_proforma: '#8b5cf6', shop_final: '#059669' }; const typeBgs = { advance: '#dbeafe', proforma: '#dbeafe', payment_receipt: '#cffafe', final: '#dcfce7', shop_proforma: '#ede9fe', shop_final: '#d1fae5' }; const statusLabels = { draft: 'Koncept', issued: 'Vystavena', paid: 'Zaplacena', cancelled: 'Storno', refunded: 'Refund' }; const statusColors = { draft: '#6b7280', issued: '#b45309', paid: '#1a8a18', cancelled: '#dc2626', refunded: '#6b7280' }; return (<TRow key={inv.id}><TD mono bold>{inv.number || '\u2014'}</TD><TD><Badge label={typeLabels[inv.type] || inv.type} color={typeColors[inv.type] || '#6b7280'} bg={typeBgs[inv.type] || '#f3f4f6'} /></TD><TD>{inv.profiles?.full_name || '\u2014'}</TD><TD bold>{fmt(inv.total)}</TD><TD><span className="text-sm font-bold" style={{ color: statusColors[inv.status] || '#6b7280' }}>{statusLabels[inv.status] || inv.status}</span></TD><TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '\u2014'}</TD></TRow>) })}</tbody></Table>
        )}
      </Card>

      {shopPayments.length > 0 && <Card className="mb-5"><h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Platby z e-shopu</h3>
        <Table><thead><TRow header><TH>Objednavka</TH><TH>Zakaznik</TH><TH>Castka</TH><TH>Zpusob</TH><TH>Datum</TH></TRow></thead>
          <tbody>{shopPayments.map(o => (<TRow key={o.id}><TD mono bold>{o.order_number || o.id?.slice(-8).toUpperCase() || '\u2014'}</TD><TD>{o.profiles?.full_name || '\u2014'}</TD><TD bold color="#1a8a18">{fmt(o.total_amount)}</TD><TD>{o.payment_method || '\u2014'}</TD><TD>{o.created_at ? new Date(o.created_at).toLocaleDateString('cs-CZ') : '\u2014'}</TD></TRow>)}</tbody></Table>
      </Card>}

      <Card className="mb-5"><h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Ucetni zaznamy</h3>
        <Table><thead><TRow header><TH>Datum</TH><TH>Typ</TH><TH>Popis</TH><TH>Castka</TH><TH>Kategorie</TH><TH>Rezervace</TH></TRow></thead>
          <tbody>{transactions.map(t => (<tr key={t.id} onClick={() => setDetailTx(t)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
            <TD>{t.date ? new Date(t.date).toLocaleDateString('cs-CZ') : '\u2014'}</TD><TD><TypeBadge type={t._classified || classifyEntry(t)} /></TD><TD>{t.description || '\u2014'}</TD><TD bold color={(t._classified || classifyEntry(t)) === 'revenue' ? '#1a8a18' : '#dc2626'}>{fmt(Math.abs(t.amount))}</TD><TD>{t.category || '\u2014'}</TD><TD mono>{t.booking_id ? t.booking_id.slice(-8).toUpperCase() : '\u2014'}</TD>
          </tr>))}
          {transactions.length === 0 && <TRow><TD>Zadne transakce</TD></TRow>}</tbody></Table>
      </Card>
    </>)}

    {detailTx && <Modal open title="Detail transakce" onClose={() => setDetailTx(null)}>
      <div className="grid grid-cols-2 gap-4">
        <DetailRow label="Datum" value={detailTx.date ? new Date(detailTx.date).toLocaleDateString('cs-CZ') : '\u2014'} />
        <DetailRow label="Typ" value={classifyEntry(detailTx) === 'revenue' ? 'Prijem' : 'Vydaj'} />
        <DetailRow label="Castka" value={fmt(detailTx.amount)} />
        <DetailRow label="Kategorie" value={detailTx.category || '\u2014'} />
        <div className="col-span-2"><DetailRow label="Popis" value={detailTx.description || '\u2014'} /></div>
        {detailTx.booking_id && <DetailRow label="ID rezervace" value={detailTx.booking_id} mono />}
        <DetailRow label="Vytvoreno" value={detailTx.created_at ? new Date(detailTx.created_at).toLocaleString('cs-CZ') : '\u2014'} />
      </div>
      <div className="flex justify-end mt-5"><Button onClick={() => setDetailTx(null)}>Zavrit</Button></div>
    </Modal>}
  </>)
}
