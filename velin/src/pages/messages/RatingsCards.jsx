// Zprávy → Hodnocení na telefonu/tabletu (≤ 1023 px): karty místo tabulky (vzor MessageLogMobile).
import { MobileCardList, MobileCard, MobileField, MobileActions, MobileActionButton } from './MobileCard'
import { Stars, LowBadge, StatusPill, Comments, BookingLink, CustomerLink, LOW_BG, LOW_BORDER } from './RatingsParts'
import { branchName, fmtDateTime, fmtRange } from './ratingsData'

export default function RatingsCards({ rows, busy, opening, onReply, onHandled, onUnhandled }) {
  return (
    <MobileCardList tabletGrid empty="Žádná hodnocení pro zvolený filtr">
      {rows.map(r => {
        const b = r.booking
        const hot = r.low && !r.handled
        return (
          <MobileCard key={r.id} style={{
            // vždy definovaný (jinak React varuje při přepnutí vedle zkratky `border` z MobileCard)
            borderLeft: r.low ? `5px solid ${hot ? LOW_BORDER : '#fca5a5'}` : '2px solid transparent',
            background: hot ? LOW_BG : undefined,
          }}>
            <div className="flex items-center flex-wrap" style={{ gap: 8 }}>
              <Stars value={r.rating} size={18} />
              {r.low && <LowBadge />}
              <span style={{ marginLeft: 'auto' }}><StatusPill row={r} /></span>
            </div>
            <MobileField label="Hodnoceno">{fmtDateTime(b.rated_at)}</MobileField>
            <MobileField label="Zákazník"><CustomerLink booking={b} /></MobileField>
            <MobileField label="Rezervace"><BookingLink row={r} /> · {fmtRange(b.start_date, b.end_date)}</MobileField>
            <MobileField label="Motorka">{[b.motorcycles?.model, b.motorcycles?.spz].filter(Boolean).join(' · ') || '—'}</MobileField>
            <MobileField label="Pobočka">{branchName(b) || '—'}</MobileField>
            <div style={{ marginTop: 8, padding: '8px 10px', borderRadius: 8, background: '#fff', border: '1px solid #d4e8e0' }}>
              <div style={{ fontSize: 11, fontWeight: 800, textTransform: 'uppercase', color: '#1a2e22', marginBottom: 4 }}>Co máme zlepšit</div>
              <Comments row={r} clamp={5} />
            </div>
            <MobileActions>
              <MobileActionButton onClick={() => onReply(r)} disabled={opening === r.id} bg="#74FB71" border="#74FB71">
                {opening === r.id ? 'Otevírám…' : r.thread ? 'Odpovědět' : 'Napsat zákazníkovi'}
              </MobileActionButton>
              {r.manual
                ? <MobileActionButton onClick={() => onUnhandled(r)} disabled={busy}>Vrátit mezi nevyřízené</MobileActionButton>
                : r.attention && <MobileActionButton onClick={() => onHandled(r)} disabled={busy}>✓ Vyřízeno</MobileActionButton>}
            </MobileActions>
          </MobileCard>
        )
      })}
    </MobileCardList>
  )
}
