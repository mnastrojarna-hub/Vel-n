// Fotky dokladů zákazníka po stranách (Líc / Rub / Další) — vyčleněno z
// CustomerVerificationSection. Strana a „skutečný soubor“ podle lib/docVerification
// (stejné pravidlo jako backend: marker `mindee_verified/…` = záznam BEZ fotky).
import Badge from '../../components/ui/Badge'
import { docSide, isMarkerPath, isRealDocFile } from '../../lib/docVerification'

const SIDE_LABEL = { front: 'Líc', back: 'Rub' }

const OCR_FIELD_LABELS = {
  document_number: 'Číslo dokladu',
  given_names: 'Jméno',
  surname: 'Příjmení',
  birth_date: 'Datum narození',
  expiry_date: 'Platnost do',
  issue_date: 'Datum vydání',
  nationality: 'Národnost',
  sex: 'Pohlaví',
  mrz: 'MRZ',
  categories: 'Skupiny',
  authority: 'Vydáno',
  address: 'Adresa',
}

function MindeeStatusBadge({ status }) {
  if (status === 'ok') return <Badge label="Mindee sken OK" color="#1a8a18" bg="#dcfce7" />
  if (status === 'failed') return <Badge label="Mindee selhal — manuální" color="#b45309" bg="#fef3c7" />
  return <Badge label="Foto v archivu" color="#1a2e22" bg="#f1faf7" />
}

export function OcrFieldsSummary({ fields }) {
  if (!fields || typeof fields !== 'object') return null
  const entries = Object.entries(fields).filter(([_, v]) => v != null && v !== '')
  if (!entries.length) return null
  return (
    <div className="mt-2 p-2 rounded text-xs" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="font-bold mb-1" style={{ color: '#1a2e22' }}>Naskenované údaje:</div>
      {/* Telefon (< 640 px): 1 sloupec; < 1024 px se dlouhé hodnoty (MRZ, adresa) zalamují místo „…" */}
      <div className="grid gap-x-3 gap-y-0.5 grid-cols-1 sm:grid-cols-[1fr_1fr]" style={{ color: '#1a2e22' }}>
        {entries.map(([k, v]) => (
          <div key={k} className="truncate max-lg:whitespace-normal max-lg:break-words">
            <span style={{ color: '#5a6b63' }}>{OCR_FIELD_LABELS[k] || k}:</span>{' '}
            <span className="font-medium">{typeof v === 'object' ? JSON.stringify(v) : String(v)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

const swapBtn = { color: '#b45309', background: 'none', border: 'none' }

function DocPageRow({ doc, onPreview, onDelete, onSwapSide }) {
  const status = doc?.metadata?.mindee_status
  const captured = doc?.metadata?.captured_at || doc?.created_at
  const ocr = doc?.metadata?.ocr_fields
  const side = docSide(doc)
  // Marker appky (`mindee_verified/<uid>/<typ>`) = řádek bez souboru v úložišti → bez náhledu, nepočítá se
  const marker = isMarkerPath(doc?.file_path)
  const icon = marker ? '⛔' : status === 'ok' ? '✅' : status === 'failed' ? '⚠️' : '📷'
  return (
    <div className="p-2 rounded-lg" style={{ background: '#fff', border: marker ? '1px solid #fca5a5' : status === 'failed' ? '1px solid #fcd34d' : '1px solid #d4e8e0' }}>
      <div className="flex items-center gap-2 flex-wrap">
        <span style={{ fontSize: 16 }}>{icon}</span>
        {/* < 1024 px: název + datum na vlastním řádku (název se zalomí, ne „…"), odznak a akce pod ním */}
        <div className="flex-1 min-w-0 max-lg:basis-[calc(100%-32px)]">
          <div className="text-sm font-bold truncate max-lg:whitespace-normal max-lg:break-words" style={{ color: '#1a2e22' }}>
            {doc.name || doc.file_name || doc.type}
          </div>
          <div className="text-xs" style={{ color: '#5a6b63' }}>
            {captured ? new Date(captured).toLocaleString('cs-CZ') : '—'}
          </div>
        </div>
        {marker ? <Badge label="Záznam bez fotky" color="#b91c1c" bg="#fee2e2" /> : <MindeeStatusBadge status={status} />}
        {/* Oprava špatně označené strany (např. rub uložený jako líc) — přepíše metadata.side
            i popisek; backend pak přepočte bránu dokladů (zadržené kódy uvolní sám), reload
            přeskupí sloty. Fotka BEZ strany: dvě explicitní volby (dřív 1. klik vždy „rub“). */}
        {onSwapSide && !marker && (side === 'front' || side === 'back') && (
          <button onClick={() => onSwapSide(doc, side === 'back' ? 'front' : 'back')} className="text-sm font-bold cursor-pointer max-lg:py-2" style={swapBtn}>
            {side === 'back' ? '⇄ Je to líc' : '⇄ Je to rub'}
          </button>
        )}
        {onSwapSide && !marker && side !== 'front' && side !== 'back' && (
          <>
            <button onClick={() => onSwapSide(doc, 'front')} className="text-sm font-bold cursor-pointer max-lg:py-2" style={swapBtn}>⇄ Je to líc</button>
            <button onClick={() => onSwapSide(doc, 'back')} className="text-sm font-bold cursor-pointer max-lg:py-2" style={swapBtn}>⇄ Je to rub</button>
          </>
        )}
        {doc.file_path && !marker && (
          <button onClick={() => onPreview(doc)} className="text-sm font-bold cursor-pointer max-lg:py-2"
            style={{ color: '#2563eb', background: 'none', border: 'none' }}>Náhled</button>
        )}
        <button onClick={() => onDelete(doc)} className="text-sm font-bold cursor-pointer max-lg:py-2"
          style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button>
      </div>
      {marker && (
        <div className="mt-2 text-xs italic" style={{ color: '#991b1b' }}>
          Záznam z aplikace bez uložené fotky — do ověření se nepočítá, doklad je potřeba nahrát znovu.
        </div>
      )}
      {!marker && status === 'ok' && <OcrFieldsSummary fields={ocr} />}
      {!marker && status === 'failed' && (
        <div className="mt-2 text-xs italic" style={{ color: '#92400e' }}>
          Mindee OCR selhal — fotka je uložená v archivu, údaje doplňte ručně do profilu zákazníka.
        </div>
      )}
    </div>
  )
}

// Do slotu Líc / Rub jen skutečné soubory se stranou (rub = jiný soubor než líc,
// jako backend); markery bez fotky a fotky bez strany jdou do „Další / starší“.
function groupDocsBySide(docs) {
  const out = { front: null, back: null, other: [] }
  // newest first (callers should pre-sort DESC); pick the most recent per slot
  for (const d of docs) {
    const side = isRealDocFile(d) ? docSide(d) : null
    if (side === 'front' && !out.front) out.front = d
    else if (side === 'back' && !out.back) out.back = d
    else out.other.push(d)
  }
  if (out.front && out.back && out.front.file_path === out.back.file_path) { out.other.unshift(out.back); out.back = null }
  return out
}

function ScanCounts({ docs }) {
  if (!docs || !docs.length) return null
  const ok = docs.filter(d => d?.metadata?.mindee_status === 'ok').length
  const fail = docs.filter(d => d?.metadata?.mindee_status === 'failed').length
  const legacy = docs.length - ok - fail
  const markers = docs.filter(d => isMarkerPath(d?.file_path)).length
  return (
    <div className="text-xs mb-2" style={{ color: '#1a2e22' }}>
      Celkem skenů: <strong>{docs.length}</strong>
      {' '}• Mindee OK: <strong style={{ color: ok > 0 ? '#1a8a18' : '#1a2e22' }}>{ok}</strong>
      {' '}• Manuálně (Mindee selhal): <strong style={{ color: fail > 0 ? '#b45309' : '#1a2e22' }}>{fail}</strong>
      {legacy > 0 && <> • Legacy: <strong>{legacy}</strong></>}
      {markers > 0 && <> • Bez fotky: <strong style={{ color: '#dc2626' }}>{markers}</strong></>}
    </div>
  )
}

export function DocSlots({ docs, requireBothSides, onPreview, onDelete, onSwapSide, emptyNote }) {
  if (!docs || !docs.length) {
    return (
      <div className="text-xs italic mt-2" style={{ color: '#5a6b63' }}>
        {emptyNote || 'Žádné nahrané fotky.'}
      </div>
    )
  }
  const grouped = groupDocsBySide(docs)
  return (
    <div className="space-y-2 mt-2">
      <ScanCounts docs={docs} />
      {requireBothSides ? (
        <>
          <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#5a6b63' }}>{SIDE_LABEL.front}</div>
          {grouped.front
            ? <DocPageRow doc={grouped.front} onPreview={onPreview} onDelete={onDelete} onSwapSide={onSwapSide} />
            : <div className="p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>⚠️ Chybí líc</div>}
          <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#5a6b63' }}>{SIDE_LABEL.back}</div>
          {grouped.back
            ? <DocPageRow doc={grouped.back} onPreview={onPreview} onDelete={onDelete} onSwapSide={onSwapSide} />
            : <div className="p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>⚠️ Chybí rub</div>}
          {grouped.other.length > 0 && (
            <>
              <div className="text-xs font-extrabold uppercase tracking-wide pt-1" style={{ color: '#5a6b63' }}>Další / starší fotky</div>
              {grouped.other.map(d => <DocPageRow key={d.id} doc={d} onPreview={onPreview} onDelete={onDelete} onSwapSide={onSwapSide} />)}
            </>
          )}
        </>
      ) : (
        [grouped.front, grouped.back, ...grouped.other]
          .filter(Boolean)
          .map(d => <DocPageRow key={d.id} doc={d} onPreview={onPreview} onDelete={onDelete} />)
      )}
    </div>
  )
}
