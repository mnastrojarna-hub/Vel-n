// ===== fio-sync/ops-mail.ts =====
// Provozní e-maily obsluze (info@motogo24.cz) — jen při UDÁLOSTI u konkrétního pohybu (potvrzeno,
// nesedí, nespárováno, ke kontrole). Žádný e-mail „za běh“. Vzhled 1:1 s původním fio-sync.
import { type Env, edgePost, fmtAmount, short, type Tx } from './util.ts'

const OPS_EMAIL = 'info@motogo24.cz'

function opsRow(label: string, value: string): string {
  return `<tr><td style="padding:6px 0;color:#16a34a;font-weight:600;font-size:13px">${label}</td>
    <td style="padding:6px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px">${value}</td></tr>`
}

export async function sendOpsMail(env: Env, subject: string, html: string) {
  try {
    await edgePost(env, 'send-email', { to: OPS_EMAIL, subject, raw_html: html })
  } catch (e) { console.warn('[fio-sync] ops mail failed:', (e as Error).message) }
}

function txTable(p: Tx, extra: Array<[string, string]> = []): string {
  return `<table style="width:100%;border-collapse:collapse;margin:0 0 12px">
    ${opsRow('Částka', fmtAmount(p.amount) + ' ' + (p.currency || 'CZK'))}
    ${opsRow('Variabilní symbol', p.vs || '—')}
    ${opsRow('Datum', p.tx_date)}
    ${opsRow('Protiúčet', (p.counter_account ? p.counter_account + '/' + (p.counter_bank || '') : '—') + (p.counter_name ? ' · ' + p.counter_name : ''))}
    ${opsRow('Zpráva', p.message || '—')}
    ${opsRow('Fio ID pohybu', String(p.fio_id))}
    ${extra.map(([l, v]) => opsRow(l, v)).join('')}
  </table>`
}

export async function notifyConfirmed(env: Env, p: Tx, bookingId: string, expected: number, isSurcharge: boolean, overpay: boolean) {
  const bn = '#' + short(bookingId)
  const what = isSurcharge ? 'DOPLATEK' : 'platba'
  await sendOpsMail(env,
    `✅ Fio: ${what} VS ${p.vs || '—'} — ${fmtAmount(p.amount)} Kč potvrzena automaticky (rez. ${bn})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">✅ ${isSurcharge ? 'Doplatek potvrzen' : 'Platba potvrzena'} automaticky (Fio API)</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">Příchozí platba na Fio účtu byla automaticky spárována s rezervací <strong>${bn}</strong> a potvrzena stejným flow jako tlačítko „Potvrdit ${isSurcharge ? 'doplatek' : 'platbu'}" ve Velíně. Není potřeba nic dělat.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč']])}
     ${overpay ? '<p style="margin:0;color:#b45309;font-weight:700;font-size:13px">⚠️ Zákazník poslal víc, než měl — přeplatek vraťte převodem zpět.</p>' : ''}`
  )
}

export async function notifyMismatch(env: Env, p: Tx, bookingId: string, expected: number, what: string) {
  const bn = '#' + short(bookingId)
  await sendOpsMail(env,
    `⚠️ Fio: platba VS ${p.vs || '—'} NESEDÍ částkou (${fmtAmount(p.amount)} / ${fmtAmount(expected)} Kč, rez. ${bn})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">⚠️ Platba nesedí částkou — potvrďte ručně</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">Příchozí platba se páruje VS na ${what} <strong>${bn}</strong>, ale částka je NIŽŠÍ než očekávaná — automaticky se nepotvrzuje. Zkontrolujte a potvrďte ručně ve Velíně (detail rezervace), nebo platbu vraťte.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč']])}`
  )
}

export async function notifyUnmatched(env: Env, p: Tx, reason: string) {
  await sendOpsMail(env,
    `🔔 Fio: nespárovaná příchozí platba ${fmtAmount(p.amount)} ${p.currency || 'CZK'} (VS ${p.vs || '—'})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">🔔 Nespárovaná příchozí platba na Fio účtu</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">${reason}</p>
     ${txTable(p)}`
  )
}

// ── Nové události (jen s nasazeným SQL 20261130a1) ───────────────────────────

const BANK_HINT = 'Velín → Finance → Banka'

/** Nižší částka u cíle, kde se částečné platby sčítají (text i pro objednávky / úpravy). */
export async function notifyUnderpaid(env: Env, p: Tx, label: string, expected: number, received: number) {
  await sendOpsMail(env,
    `⚠️ Fio: platba VS ${p.vs || '—'} je NIŽŠÍ, než se čekalo (${fmtAmount(received)} / ${fmtAmount(expected)} Kč, ${label})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">⚠️ Přišlo méně, než se čekalo — nepotvrzeno</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">Platba patří k <strong>${label}</strong>, ale dohromady zatím přišlo jen ${fmtAmount(received)} Kč z ${fmtAmount(expected)} Kč. Až zákazník doplatí rozdíl se stejným variabilním symbolem, potvrdí se to samo. Jinak rozhodněte ručně (${BANK_HINT}): přijmout nižší částku, nebo platbu vrátit.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč'], ['Přijato celkem', fmtAmount(received) + ' Kč']])}`
  )
}

/** Platba, kterou stroj NESMÍ potvrdit sám (duplicita, pozdní platba, úpravu nešlo provést…). */
export async function notifyReview(env: Env, p: Tx, title: string, text: string) {
  await sendOpsMail(env,
    `🔔 Fio: platba ${fmtAmount(p.amount)} Kč (VS ${p.vs || '—'}) čeká na obsluhu — ${title}`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">🔔 ${title}</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">${text}</p>
     ${txTable(p)}
     <p style="margin:0;color:#6b7280;font-size:12px">Vyřízení: ${BANK_HINT} → pohyb ${p.fio_id}.</p>`
  )
}

/** Potvrzeno automaticky — objednávka / poukaz / úprava rezervace z webu. */
export async function notifyDone(env: Env, p: Tx, title: string, text: string, expected: number, overpay: boolean) {
  await sendOpsMail(env,
    `✅ Fio: ${title} — ${fmtAmount(p.amount)} Kč (VS ${p.vs || '—'})`,
    `<h2 style="margin:0 0 8px;font-size:18px;color:#0f1a14">✅ ${title}</h2>
     <p style="margin:0 0 12px;color:#374151;font-size:14px">${text} Není potřeba nic dělat.</p>
     ${txTable(p, [['Očekávaná částka', fmtAmount(expected) + ' Kč']])}
     ${overpay ? '<p style="margin:0;color:#b45309;font-weight:700;font-size:13px">⚠️ Zákazník poslal víc, než měl — přeplatek vraťte převodem zpět (' + BANK_HINT + ').</p>' : ''}`
  )
}
