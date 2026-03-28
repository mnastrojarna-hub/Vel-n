import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'

export function findBestMatch(dl, invoices) {
  let bestMatch = null
  let bestScore = 0

  for (const inv of invoices) {
    let score = 0
    const invNotes = (inv.notes || '').toLowerCase()
    const invNumber = (inv.number || '').toLowerCase()

    if (inv.total && dl.total_amount && Math.abs(inv.total - dl.total_amount) < 1) {
      score += 40
    } else if (inv.total && dl.total_amount && Math.abs(inv.total - dl.total_amount) < inv.total * 0.05) {
      score += 20
    }

    if (dl.supplier_name && invNotes.includes(dl.supplier_name.toLowerCase())) {
      score += 30
    } else if (dl.supplier_name) {
      const words = dl.supplier_name.toLowerCase().split(/\s+/).filter(w => w.length > 2)
      const wordMatches = words.filter(w => invNotes.includes(w)).length
      if (wordMatches > 0) score += Math.min(wordMatches * 10, 25)
    }

    if (dl.supplier_ico && invNotes.includes(dl.supplier_ico)) {
      score += 25
    }

    if (dl.variable_symbol && (inv.variable_symbol === dl.variable_symbol || invNotes.includes(dl.variable_symbol))) {
      score += 20
    }

    if (dl.dl_number && (invNotes.includes(dl.dl_number.toLowerCase()) || invNumber.includes(dl.dl_number.toLowerCase()))) {
      score += 15
    }

    if (dl.delivery_date && inv.issue_date) {
      const daysDiff = Math.abs(new Date(dl.delivery_date) - new Date(inv.issue_date)) / (1000 * 60 * 60 * 24)
      if (daysDiff <= 7) score += 10
      else if (daysDiff <= 30) score += 5
    }

    if (Array.isArray(dl.items) && Array.isArray(inv.items)) {
      if (dl.items.length === inv.items.length) score += 5
    }

    if (score > bestScore && score >= 50) {
      bestScore = score
      bestMatch = { ...inv, confidence: Math.min(score / 100, 1.0) }
    }
  }

  return bestMatch
}

export function StatCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

export function MiniField({ label, value, mono }) {
  return (
    <div>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#6b7280' }}>{label}</div>
      <div className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</div>
    </div>
  )
}

export function DeliveryNoteDetailModal({ detail, setDetail, fmt }) {
  if (!detail) return null
  return (
    <Modal open title={detail._isInvoice ? 'Detail faktury bez DL' : 'Detail dodacího listu'} onClose={() => setDetail(null)}>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <MiniField label={detail._isInvoice ? 'Číslo faktury' : 'Číslo DL'} value={detail.dl_number || detail.number || '—'} mono />
        <MiniField label="Dodavatel" value={detail.supplier_name || '—'} />
        <MiniField label="IČO" value={detail.supplier_ico || '—'} mono />
        <MiniField label="Částka" value={fmt(detail.total_amount)} />
        <MiniField label="Datum" value={(detail.issue_date || detail.delivery_date) ? new Date(detail.issue_date || detail.delivery_date).toLocaleDateString('cs-CZ') : '—'} />
        <MiniField label="VS" value={detail.variable_symbol || '—'} mono />
      </div>

      {Array.isArray(detail.items) && detail.items.length > 0 && (
        <div className="mb-4">
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Položky</div>
          <Table>
            <thead>
              <TRow header><TH>Popis</TH><TH>Množství</TH><TH>Cena/ks</TH><TH>Celkem</TH></TRow>
            </thead>
            <tbody>
              {detail.items.map((item, i) => (
                <TRow key={i}>
                  <TD>{item.description || item.name || '—'}</TD>
                  <TD>{item.quantity || '—'}</TD>
                  <TD>{item.unit_price ? fmt(item.unit_price) : '—'}</TD>
                  <TD bold>{item.total ? fmt(item.total) : '—'}</TD>
                </TRow>
              ))}
            </tbody>
          </Table>
        </div>
      )}

      {detail.extracted_data && (
        <div className="mb-4">
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI extrahovaná data</div>
          <pre className="text-xs p-3 rounded" style={{ background: '#f1faf7', color: '#1a2e22', whiteSpace: 'pre-wrap', maxHeight: 200, overflow: 'auto' }}>
            {JSON.stringify(detail.extracted_data, null, 2)}
          </pre>
        </div>
      )}

      {detail.photo_url && (
        <div className="mb-4">
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Sken dokladu</div>
          <a href={detail.photo_url} target="_blank" rel="noopener noreferrer">
            <img src={detail.photo_url} alt="DL sken" style={{ maxWidth: '100%', maxHeight: 300, borderRadius: 8, border: '1px solid #d4e8e0' }} />
          </a>
        </div>
      )}

      {detail.notes && (
        <div className="mb-4">
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#6b7280' }}>Poznámky</div>
          <p className="text-sm" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}>{detail.notes}</p>
        </div>
      )}

      <div className="flex justify-end">
        <Button onClick={() => setDetail(null)}>Zavřít</Button>
      </div>
    </Modal>
  )
}

export function MatchModal({ matchModal, setMatchModal, matchSearch, setMatchSearch, invoices, matchDlToInvoice, fmt }) {
  if (!matchModal) return null
  return (
    <Modal open title={`Párovat DL ${matchModal.dl_number || ''} s fakturou`} onClose={() => setMatchModal(null)}>
      <div className="mb-3 p-3 rounded" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>
          DL: {matchModal.dl_number || '—'} | {matchModal.supplier_name || '—'} | {fmt(matchModal.total_amount)}
        </div>
      </div>

      <input type="text" value={matchSearch} onChange={e => setMatchSearch(e.target.value)}
        placeholder="Hledat fakturu…"
        className="rounded-btn text-sm outline-none w-full mb-3"
        style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />

      <div style={{ maxHeight: 300, overflow: 'auto' }}>
        {invoices
          .filter(inv => {
            if (!matchSearch) return true
            const s = matchSearch.toLowerCase()
            return (inv.number || '').toLowerCase().includes(s) ||
              (inv.notes || '').toLowerCase().includes(s)
          })
          .map(inv => {
            const amountMatch = Math.abs((inv.total || 0) - (matchModal.total_amount || 0)) < 1
            const supplierMatch = matchModal.supplier_name &&
              (inv.notes || '').toLowerCase().includes((matchModal.supplier_name || '').toLowerCase())
            return (
              <div key={inv.id} className="flex items-center justify-between p-2 rounded mb-1 cursor-pointer hover:bg-[#e8fde8]"
                style={{ background: amountMatch && supplierMatch ? '#dcfce7' : amountMatch ? '#fef3c7' : '#f9fafb', border: '1px solid #d4e8e0' }}
                onClick={() => matchDlToInvoice(matchModal, inv.id)}>
                <div>
                  <span className="text-sm font-mono font-bold" style={{ color: '#1a2e22' }}>{inv.number || '—'}</span>
                  <span className="ml-2 text-sm" style={{ color: '#6b7280' }}>{inv.notes?.split('\n')[0]?.slice(0, 40) || ''}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold" style={{ color: amountMatch ? '#1a8a18' : '#b45309' }}>{fmt(inv.total)}</span>
                  {amountMatch && <Badge label="Částka OK" color="#1a8a18" bg="#dcfce7" />}
                  {supplierMatch && <Badge label="Dodavatel OK" color="#2563eb" bg="#dbeafe" />}
                </div>
              </div>
            )
          })}
        {invoices.length === 0 && (
          <div className="text-sm p-3" style={{ color: '#6b7280' }}>Žádné nenapárované faktury přijaté</div>
        )}
      </div>

      <div className="flex justify-end mt-3">
        <button onClick={() => setMatchModal(null)}
          className="text-sm font-bold cursor-pointer rounded"
          style={{ padding: '8px 20px', background: '#f3f4f6', border: '1px solid #d4d4d8', color: '#6b7280' }}>
          Zavřít
        </button>
      </div>
    </Modal>
  )
}
