import { TR_LANGS, translationStatus } from './docTranslations'

// Stav překladu po jazycích (jen skutečné jazyky — interní klíče se nikdy nevypisují)
// + u každého jazyka „Přeložit znovu“ / „Přeložit“.
const LOOK = {
  fresh: { bg: '#dcfce7', color: '#166534', text: 'aktuální', title: 'Překlad odpovídá současnému českému znění.' },
  stale: { bg: '#fee2e2', color: '#b91c1c', text: 'ZASTARALÝ', title: 'Česká verze se od překladu změnila (nebo chybí záznam, ze kterého znění překlad vznikl) — web, aplikace, PDF ani AI ho nepoužijí, zobrazí závaznou češtinu.' },
  missing: { bg: '#f1f5f4', color: '#6b7a72', text: 'chybí', title: 'Překlad neexistuje — zákazník dostane závaznou českou verzi.' },
  checking: { bg: '#f1f5f4', color: '#6b7a72', text: '…', title: 'Ověřuji aktuálnost překladu…' },
}

export default function TranslationStatusChips({ table, row, srcHash, busy, onTranslateLang }) {
  return (
    <div className="flex items-center gap-1.5 mt-2 flex-wrap">
      <span className="text-sm" style={{ color: '#1a2e22' }}>🌍 Překlady:</span>
      {TR_LANGS.map(lang => {
        const st = translationStatus(table, row, lang, srcHash)
        const look = LOOK[st] || LOOK.checking
        return (
          <span key={lang} title={look.title} className="inline-flex items-center gap-1 rounded-btn text-sm"
            style={{ padding: '2px 8px', background: look.bg, color: look.color }}>
            <strong>{lang.toUpperCase()}</strong>
            <span style={{ fontWeight: st === 'stale' ? 800 : 500 }}>{look.text}</span>
            <button type="button" disabled={busy} onClick={() => onTranslateLang(lang)}
              className="disabled:opacity-50 disabled:cursor-not-allowed"
              style={{ background: 'none', border: 'none', padding: 0, marginLeft: 4, color: 'inherit', cursor: 'pointer', textDecoration: 'underline', fontWeight: 700 }}>
              {st === 'missing' ? 'Přeložit' : 'Přeložit znovu'}
            </button>
          </span>
        )
      })}
    </div>
  )
}
