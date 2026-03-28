import { TRow, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import EventDetail from './FinancialEventDetail'

export default function EvRow({ ev, st, tp, dt, catLabel, supplierName, isExpanded, isActing, fmt, onExpand, onApprove, onFlexi, onEdit, onDelete }) {
  const canApprove = ev.status === 'enriched' || ev.status === 'exported'
  const canFlexi = ev.status === 'validated'

  return (
    <>
      <TRow>
        <TD>{ev.duzp ? new Date(ev.duzp).toLocaleDateString('cs-CZ') : '\u2014'}</TD>
        <TD><Badge label={tp.label} color={tp.color} bg={tp.bg} /></TD>
        <TD>
          {dt ? <Badge label={dt.label} color={dt.color} bg={dt.bg} /> : <span style={{ color: '#d4d4d8' }}>{'\u2014'}</span>}
          {dt?.route && <div className="text-[8px] font-bold mt-0.5" style={{ color: '#6b7280' }}>{'\u2192'} {dt.route}</div>}
        </TD>
        <TD><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{supplierName}</span></TD>
        <TD bold color={ev.event_type === 'revenue' ? '#1a8a18' : '#dc2626'}>{fmt(ev.amount_czk)}</TD>
        <TD>
          {catLabel ? <Badge label={catLabel} color="#7c3aed" bg="#ede9fe" /> : <span style={{ color: '#d4d4d8' }}>{'\u2014'}</span>}
        </TD>
        <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
        <TD>
          <div className="flex gap-1 flex-wrap">
            {canApprove && (
              <button onClick={onApprove} disabled={isActing}
                className="text-sm font-bold cursor-pointer rounded"
                style={{ color: '#fff', background: '#1a8a18', border: 'none', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
                {isActing ? '\u2026' : 'Schvalit'}
              </button>
            )}
            {canFlexi && (
              <button onClick={onFlexi} disabled={isActing}
                className="text-sm font-bold cursor-pointer rounded"
                style={{ color: '#fff', background: '#2563eb', border: 'none', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
                {isActing ? '\u2026' : '\u2192 Flexi'}
              </button>
            )}
            <button onClick={onEdit}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ color: '#b45309', background: '#fef3c7', border: '1px solid #fcd34d', padding: '4px 10px' }}>
              Upravit
            </button>
            <button onClick={onDelete} disabled={isActing}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
              Smazat
            </button>
            <button onClick={onExpand}
              className="text-sm font-bold cursor-pointer"
              style={{ color: '#6b7280', background: 'none', border: 'none', padding: '4px 6px' }}>
              {isExpanded ? 'Skryt \u25b4' : 'Detail \u25be'}
            </button>
          </div>
        </TD>
      </TRow>
      {isExpanded && (
        <tr style={{ background: '#f9fafb', borderBottom: '1px solid #d4e8e0' }}>
          <td colSpan={8} style={{ padding: '12px 16px' }}>
            <EventDetail event={ev} />
          </td>
        </tr>
      )}
    </>
  )
}
