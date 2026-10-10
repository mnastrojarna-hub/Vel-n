// Součty e-shop objednávky na telefonu (< 768 px): jeden blok „Mezisoučet / Doprava / Sleva / Celkem“
// místo čtyř samostatných karet kartové tabulky (řádky součtů v tabulce skrývá mg-hide-phone).
// Od 768 px skryto (md:hidden) — tablet i desktop ukazují součty dál jako řádky tabulky.
const LABEL = { fontFamily: "'Montserrat', 'Segoe UI', sans-serif", fontSize: 11, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.03em', lineHeight: 1.5, color: '#4a6357' }
const ROW = { display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, padding: '7px 14px' }

export default function ShopOrderTotalsMobile({ order, fmt }) {
  const rows = [
    ['Mezisoučet', fmt(order.subtotal), { fontWeight: 700 }],
    Number(order.shipping_cost) > 0 && ['Doprava', fmt(order.shipping_cost)],
    Number(order.discount) > 0 && ['Sleva', `-${fmt(order.discount)}`, { color: '#dc2626' }],
  ].filter(Boolean)
  return (
    <div className="md:hidden bg-white" style={{ borderRadius: 14, boxShadow: '0 2px 10px rgba(15,26,20,.08)', padding: '6px 0' }}>
      {rows.map(([label, value, st]) => (
        <div key={label} style={ROW}>
          <span style={LABEL}>{label}</span>
          <span style={{ fontSize: 13, fontWeight: 500, color: '#0f1a14', whiteSpace: 'nowrap', ...st }}>{value}</span>
        </div>
      ))}
      <div style={{ ...ROW, marginTop: 4, paddingTop: 10, borderTop: '1px solid #d4e8e0' }}>
        <span style={{ ...LABEL, color: '#1a2e22' }}>Celkem</span>
        <span style={{ fontSize: 15, fontWeight: 800, color: '#0f1a14', whiteSpace: 'nowrap' }}>{fmt(order.total)}</span>
      </div>
    </div>
  )
}
