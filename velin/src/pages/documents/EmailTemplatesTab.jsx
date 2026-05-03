import { useState, useEffect, useRef, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Badge from '../../components/ui/Badge'
import RichTextEditor from '../../components/ui/RichTextEditor'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const SAMPLE_VARS = {
  // Booking email vars
  booking_number: 'A1B2C3D4', customer_name: ' Jan Novák', moto_model: 'BMW R 1200 GS Adventure',
  motorcycle: 'BMW R 1200 GS Adventure', start_date: '15. 6. 2026', end_date: '18. 6. 2026',
  total_price: '7 800', pickup_location: 'Mezná 9, 393 01 Mezná',
  resume_link: 'https://motogo24.cz/#/rezervace?resume=abc123',
  voucher_code: 'MGABC123 (3 000 Kč)', voucher_amount: '3 000', voucher_value: '3 000',
  voucher_expiry: '15. 6. 2029', order_number: 'OBJ-2026-01001', discount_code: 'DIKY200',
  google_review_url: 'https://g.page/MotoGo24/review', facebook_review_url: 'https://facebook.com/MotoGo24/reviews',
  site_url: 'https://motogo24.cz', price_difference: '-1 200',
  // Invoice email vars
  invoice_number: 'ZF-2026-0001', invoice_type: 'Zálohová faktura',
  issue_date: '15. 6. 2026', due_date: '29. 6. 2026', variable_symbol: 'ZF-2026-0001',
  // Document template vars (smlouva, VOP)
  customer_email: 'jan.novak@email.cz', customer_phone: '+420 777 123 456',
  customer_address: 'Hlavní 123, 110 00 Praha 1', customer_street: 'Hlavní 123',
  customer_city: 'Praha 1', customer_zip: '110 00', customer_country: 'Česká republika',
  customer_ico: '12345678', customer_dic: 'CZ12345678',
  customer_license: 'EA123456', customer_license_expiry: '15. 6. 2030',
  customer_license_group: 'A2', customer_dob: '15. 3. 1990', customer_id_number: '123456789',
  moto_brand: 'BMW', moto_spz: '1A2 3456', moto_vin: 'WB10408C07ZE12345', moto_year: '2024',
  moto_category: 'Cestovní', moto_engine: '1170 ccm', moto_power: '92 kW', moto_color: 'Černá',
  days: '3', daily_rate: '2 600,00', rental_price: '7 800,00',
  extras_price: '500,00', extras_list: 'Helma L ×1 — 200,00 Kč, Rukavice M ×1 — 100,00 Kč',
  delivery_fee: '1 500,00', discount_amount: '200,00', deposit: '10 000,00',
  insurance: '500,00', insurance_type: 'Základní', pickup_time: '10:00',
  pickup_method: 'Přistavení', pickup_address: 'Hlavní 123, Praha 1',
  return_method: 'Na pobočce', return_address: 'Mezná 9, 393 01 Mezná',
  branch_name: 'Pobočka Mezná', branch_address: 'Mezná 9, 393 01 Mezná',
  today: '30. 3. 2026',
  company_name: 'Bc. Petra Semorádová', company_address: 'Mezná 9, 393 01 Mezná',
  company_ico: '21874263', company_dic: '',
  company_phone: '+420 774 256 271', company_email: 'info@motogo24.cz',
  company_web: 'www.motogo24.cz', company_bank: 'mBank', company_account: '670100-2225851630/6210',
  // Time & period
  start_time: '10:00', end_time: '10:00', rental_period: '3 dny',
  total_price_words: 'sedm tisíc osm set korun českých',
  pickup_location: 'Mezná 9, 393 01 Mezná', return_location: 'Mezná 9, 393 01 Mezná',
  // Cancellation vars
  cancellation_reason: 'Změna plánů', refund_amount: '7 800', refund_percent: '100',
}

const EMAIL_STATUS = {
  sent: { label: 'Odesláno', color: '#1a8a18', bg: '#dcfce7' },
  failed: { label: 'Chyba', color: '#dc2626', bg: '#fee2e2' },
  queued: { label: 'Ve frontě', color: '#b45309', bg: '#fef3c7' },
  bounced: { label: 'Nedoručeno', color: '#1a2e22', bg: '#f3f4f6' },
}

/** Metadata pro každý slug — kategorie, trigger, přílohy, popis */
const TEMPLATE_META = {
  booking_reserved: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Stripe webhook po platbě',
    attachments: 'ZF, DP, Smlouva, VOP',
    info: 'Odesílá se automaticky zákazníkovi po úspěšné platbě rezervace (web i app). Obsahuje informace k převzetí motorky.',
  },
  booking_abandoned: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Auto-cancel po 4h (web)',
    attachments: 'ZF',
    info: 'Odesílá se automaticky když zákazník na webu nedokončí platbu do 4 hodin. Obsahuje CTA tlačítko pro dokončení.',
  },
  booking_cancelled: {
    category: 'storno', categoryLabel: 'Storno',
    trigger: 'Změna stavu na cancelled (app/web/velín)',
    attachments: 'Dobropis',
    info: 'Odesílá se automaticky při stornování rezervace z jakéhokoliv zdroje. Auto Stripe refund dle storno podmínek (7+ dní=100%, 2-7=50%, <2=0%).',
  },
  booking_completed: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Změna stavu active → completed',
    attachments: 'KF (konečná faktura)',
    info: 'Odesílá se automaticky po dokončení pronájmu (vrácení motorky). Obsahuje žádost o recenzi a slevový kód na příští rezervaci.',
  },
  booking_modified: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Úprava termínu/motorky/místa/času (Velín, web, app)',
    attachments: 'ZF, DP, Smlouva, VOP, Dobropis (při zkrácení)',
    info: 'Odesílá se při jakékoliv změně rezervace — zkrácení, prodloužení, změna motorky, změna místa přistavení nebo času. DB trigger trg_booking_modified_email detekuje UPDATE bookings ze všech kanálů (Velín, web apply_booking_changes RPC, Flutter app) a pošle mail s diff tabulkou Původní vs Nové. Při doplatku se přiloží DP rozdílu, při vratce dobropis.',
  },
  voucher_purchased: {
    category: 'shop', categoryLabel: 'E-shop',
    trigger: 'Stripe webhook po platbě objednávky',
    attachments: 'ZF, DP, Voucher HTML, FV (elektronický)',
    info: 'Odesílá se po zakoupení dárkového poukazu nebo e-shop objednávky. Pro elektronické poukazy obsahuje i konečnou fakturu.',
  },
  sos_incident: {
    category: 'other', categoryLabel: 'Ostatní',
    trigger: 'Vytvoření SOS incidentu (app)',
    attachments: 'Žádné',
    info: 'Odesílá se automaticky zákazníkovi při nahlášení SOS incidentu. Obsahuje omluvu a kontakt na linku pomoci.',
  },
  invoice_advance: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Ruční odeslání z Velínu / automaticky',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail se zálohovou fakturou (ZF/proforma). Odesílá se s fakturou v příloze.',
  },
  invoice_payment_receipt: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Ruční odeslání z Velínu / automaticky',
    attachments: 'Doklad HTML v příloze',
    info: 'E-mail s dokladem o přijaté platbě (DP). Odesílá se s dokladem v příloze.',
  },
  invoice_final: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Dokončení pronájmu / ruční odeslání',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail s konečnou fakturou (FV/KF). Odesílá se po dokončení pronájmu nebo ručně z Velínu.',
  },
  invoice_shop_final: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Odeslání zboží z Velínu (shipped/delivered)',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail s konečnou fakturou za e-shop objednávku. Odesílá se při expedici fyzického zboží nebo poukazu z Velínu.',
  },
  // Web varianty
  web_booking_reserved: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Web platba', attachments: 'ZF, DP, Smlouva, VOP', info: 'Web varianta potvrzení rezervace. Pokud neexistuje, použije se booking_reserved.' },
  web_booking_modified: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Úprava rezervace na webu (apply_booking_changes RPC)', attachments: 'ZF, DP, Smlouva, VOP, Dobropis', info: 'Web varianta úpravy rezervace. Posílá se po UPDATE bookings z webu (apply_booking_changes / shorten_booking_with_refund). Pokud neexistuje, použije se booking_modified. DB trigger pokrývá všechny kanály (Velín, web, app, AI agent) jednotně.' },
  web_booking_abandoned: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Auto-cancel web 4h', attachments: 'ZF', info: 'Web varianta nedokončené rezervace. Pokud neexistuje, použije se booking_abandoned.' },
  web_booking_cancelled: { category: 'storno', categoryLabel: 'Storno', trigger: 'Storno web rezervace', attachments: 'Dobropis', info: 'Web varianta storna. Pokud neexistuje, použije se booking_cancelled.' },
  web_booking_completed: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Dokončení web pronájmu', attachments: 'KF', info: 'Web varianta dokončení. Pokud neexistuje, použije se booking_completed.' },
  web_voucher_purchased: { category: 'shop', categoryLabel: 'E-shop', trigger: 'Web nákup poukazu', attachments: 'ZF, DP, Voucher, FV', info: 'Web varianta nákupu poukazu. Pokud neexistuje, použije se voucher_purchased.' },
}

const CATEGORIES = [
  { value: 'reservation', label: 'Rezervace', color: '#2563eb', bg: '#dbeafe' },
  { value: 'storno', label: 'Storno', color: '#dc2626', bg: '#fee2e2' },
  { value: 'invoice', label: 'Faktura', color: '#b45309', bg: '#fef3c7' },
  { value: 'shop', label: 'E-shop', color: '#7c3aed', bg: '#ede9fe' },
  { value: 'other', label: 'Ostatní', color: '#1a2e22', bg: '#f3f4f6' },
]

const CHANNELS = [
  { value: 'app', label: 'App', color: '#0369a1', bg: '#e0f2fe' },
  { value: 'web', label: 'Web', color: '#7c2d12', bg: '#fed7aa' },
  { value: 'shared', label: 'Společné', color: '#374151', bg: '#e5e7eb' },
]

/** Katalog dostupných triggerů — admin si vybírá jaké události vyvolají šablonu.
 *  Ukládá se do email_templates.triggers jsonb jako array slugů.
 *  Edge funkce a DB triggery zatím rozlišují podle TYPE payloadu, tato data
 *  slouží jako reference + příprava na dynamický dispatcher. */
const TRIGGER_CATALOG = [
  { group: 'Stripe platby', items: [
    { slug: 'stripe_payment_confirmed_booking',    label: 'Po potvrzení Stripe platby — rezervace' },
    { slug: 'stripe_payment_confirmed_booking_web',label: 'Po potvrzení Stripe platby — web rezervace' },
    { slug: 'stripe_payment_confirmed_shop',       label: 'Po potvrzení Stripe platby — e-shop' },
    { slug: 'stripe_payment_confirmed_voucher',    label: 'Po potvrzení Stripe platby — dárkový poukaz' },
    { slug: 'stripe_payment_confirmed_voucher_web',label: 'Po potvrzení Stripe platby — voucher web' },
    { slug: 'stripe_payment_confirmed_edit',       label: 'Po potvrzení Stripe doplatku úpravy rezervace' },
    { slug: 'stripe_refund_processed',             label: 'Po zpracovaném Stripe refundu' },
    { slug: 'stripe_portal_refund',                label: 'Refund přes Stripe zákaznický portál (mimo naši flow)' },
  ]},
  { group: 'Stav rezervace', items: [
    { slug: 'booking_status_changed_to_pending',   label: 'Stav rezervace → Pending (vytvořeno)' },
    { slug: 'booking_status_changed_to_reserved',  label: 'Stav rezervace → Reserved (potvrzeno)' },
    { slug: 'booking_status_changed_to_active',    label: 'Stav rezervace → Active (převzato)' },
    { slug: 'booking_status_changed_to_completed', label: 'Stav rezervace → Completed (dokončeno)' },
    { slug: 'booking_status_changed_to_cancelled', label: 'Stav rezervace → Cancelled (zrušeno)' },
    { slug: 'booking_status_changed_to_cancelled_web', label: 'Stav rezervace → Cancelled (web)' },
    { slug: 'booking_updated',                     label: 'Úprava rezervace (jakákoliv změna polí)' },
  ]},
  { group: 'Cron (časované)', items: [
    { slug: 'cron_abandoned_payment_only',         label: 'Cron: Web nedokončená — chybí jen platba (10 min)' },
    { slug: 'cron_abandoned_payment_and_docs',     label: 'Cron: Web nedokončená — chybí platba + doklady' },
    { slug: 'cron_paid_missing_docs',              label: 'Cron: Zaplaceno, chybí doklady (5 min)' },
    { slug: 'cron_abandoned_web',                  label: 'Cron: Web nezaplaceno do 4h (auto-cancel)' },
    { slug: 'cron_abandoned_app',                  label: 'Cron: App nezaplaceno do 10 min (auto-cancel)' },
    { slug: 'cron_auto_complete',                  label: 'Cron: Auto-complete v půlnoci posledního dne' },
    { slug: 'cron_24h_before_pickup',              label: 'Cron: 24 hodin před převzetím (připomínka)' },
    { slug: 'cron_2h_before_pickup',               label: 'Cron: 2 hodiny před převzetím' },
  ]},
  { group: 'Faktury & doklady', items: [
    { slug: 'zf_invoice_created',                  label: 'Vystavena ZF (zálohová faktura)' },
    { slug: 'dp_invoice_created',                  label: 'Vystaven DP (doklad o platbě)' },
    { slug: 'kf_invoice_created',                  label: 'Vystavena KF (konečná faktura)' },
    { slug: 'kf_invoice_created_web',              label: 'Vystavena KF — web rezervace' },
    { slug: 'credit_note_created',                 label: 'Vystaven dobropis' },
    { slug: 'auto_after_zf_created',               label: 'Automaticky po vytvoření ZF' },
    { slug: 'auto_after_dp_created',               label: 'Automaticky po vytvoření DP' },
    { slug: 'auto_after_kf_created',               label: 'Automaticky po vytvoření KF' },
  ]},
  { group: 'E-shop', items: [
    { slug: 'shop_order_status_new',               label: 'E-shop objednávka → Nová' },
    { slug: 'shop_order_status_confirmed',         label: 'E-shop objednávka → Potvrzená (zaplacená)' },
    { slug: 'shop_order_status_processing',        label: 'E-shop objednávka → Zpracovává se' },
    { slug: 'shop_order_status_shipped',           label: 'E-shop objednávka → Odeslaná' },
    { slug: 'shop_order_status_delivered',         label: 'E-shop objednávka → Doručená' },
  ]},
  { group: 'Ručně z Velinu', items: [
    { slug: 'manual_send_from_velin',              label: 'Ruční odeslání z Velinu (tlačítko)' },
    { slug: 'manual_test_send',                    label: 'Test (admin si poslal sám sobě)' },
  ]},
  { group: 'Doklady & SOS', items: [
    { slug: 'door_codes_released',                 label: 'Uvolněné přístupové kódy (po ověření dokladů)' },
    { slug: 'sos_reported_app',                    label: 'SOS hlášení z appky' },
    { slug: 'sos_status_changed',                  label: 'Změna stavu SOS incidentu' },
  ]},
  { group: 'Web interakce', items: [
    { slug: 'web_click_continue_payment',          label: 'Web: klik na "Pokračovat k platbě"' },
    { slug: 'web_click_resume_booking',            label: 'Web: klik na "Pokračovat v rezervaci"' },
    { slug: 'web_form_step_completed',             label: 'Web: dokončen krok rezervačního formuláře' },
  ]},
]

/** Povolené přílohy (multi-select v editaci šablony, sloupec attachments jsonb) */
const ATTACHMENT_OPTIONS = [
  { value: 'ZF',       label: 'ZF — Zálohová faktura' },
  { value: 'DP',       label: 'DP — Doklad o platbě' },
  { value: 'KF',       label: 'KF — Konečná faktura' },
  { value: 'Smlouva',  label: 'Smlouva — Nájemní smlouva' },
  { value: 'VOP',      label: 'VOP — Všeobecné obchodní podmínky' },
  { value: 'Dobropis', label: 'Dobropis — Credit note (storno/zkrácení)' },
  { value: 'Voucher',  label: 'Voucher — Dárkový poukaz' },
  { value: 'eshop_DP', label: 'eshop DP — Doklad o platbě (e-shop)' },
  { value: 'eshop_KF', label: 'eshop KF — Konečná faktura (e-shop)' },
]

/** Zdroj rozliší podle slug prefixu */
function getChannel(slug) {
  if (!slug) return 'shared'
  if (slug.startsWith('web_')) return 'web'
  // Slugy které jsou výhradně pro app/Velin — ostatní jsou shared (faktury, sos, e-shop)
  const appSlugs = ['booking_reserved','booking_abandoned','booking_completed','booking_modified','booking_cancelled','voucher_purchased']
  if (appSlugs.includes(slug)) return 'app'
  return 'shared'
}

function getTemplateMeta(slug) {
  return TEMPLATE_META[slug] || { category: 'other', categoryLabel: 'Ostatní', trigger: '—', attachments: '—', info: '' }
}

/** Zabalí body šablony do zjednodušeného (přesto autentického) MotoGo24 brand layoutu
 *  shodného s send-booking-email/wrapInBrandedLayout. Použito v náhledu modálu. */
function wrapPreview(bodyHtml) {
  // 1:1 layout s edge fn wrapInBrandedLayout (vertikální logo nahoře,
  // text pod ním, vše centrované). Reálné logo z motogo24.cz/gfx/logo-icon.png.
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased">
  <div style="max-width:780px;margin:0 auto;background:#ffffff">
    <div style="background:#000000;padding:36px 24px;text-align:center">
      <img src="https://motogo24.cz/gfx/logo-icon.png" alt="MotoGo24" width="110" height="110" style="display:inline-block;border:0;margin-bottom:16px"/>
      <div style="color:#ffffff;font-size:32px;font-weight:900;letter-spacing:3px;line-height:1">MOTO GO 24</div>
      <div style="color:#ffffff;font-size:11px;font-weight:400;letter-spacing:6px;margin-top:8px">PŮJČOVNA MOTOREK</div>
    </div>
    <div style="padding:32px;color:#0f1a14;font-size:14px;line-height:1.7">${bodyHtml}</div>
    <div style="margin:24px 32px 0;background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px">
      <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">Máte dotaz?</div>
      <div style="color:#ffffff;font-size:13px;margin:0 0 16px">Pokud budete mít jakýkoliv dotaz, jsme vám k dispozici.</div>
      <a href="mailto:info@motogo24.cz" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">info@motogo24.cz</a>
    </div>
    <div style="background:#000000;padding:24px 32px;margin-top:24px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
        <td style="vertical-align:top;padding-right:16px">
          <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
            <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
            <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semorádová</div>
            <div style="color:#9ca3af">Mezná 9, 393 01 Pelhřimov</div>
            <div style="color:#9ca3af">IČO: 21874263</div>
            <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
            <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
            <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">motogo24.cz</span></div>
          </div>
        </td>
        <td style="vertical-align:top;width:130px;text-align:center">
          <a href="https://motogo24.cz" style="text-decoration:none"><img src="https://api.qrserver.com/v1/create-qr-code/?size=220x220&amp;margin=8&amp;data=https%3A%2F%2Fmotogo24.cz" alt="motogo24.cz" width="120" height="120" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/></a>
          <div style="color:#9ca3af;font-size:10px;margin-top:6px">motogo24.cz</div>
        </td>
      </tr></table>
    </div>
  </div>
</body></html>`
}

export default function EmailTemplatesTab() {
  const [templates, setTemplates] = useState([])
  const [sentEmails, setSentEmails] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [creating, setCreating] = useState(false)
  const defaultFilters = { search: '', statuses: [], categories: [], channels: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_emailtemplates_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_emailtemplates_filters', JSON.stringify(filters)) }, [filters])

  useEffect(() => { load(); loadSent() }, [])

  async function load() {
    setLoading(true)
    try {
      const { data, error: err } = await supabase.from('email_templates').select('*').order('name')
      if (err) throw err
      setTemplates(data || [])
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function loadSent() {
    try {
      const { data } = await supabase.from('sent_emails').select('*').order('created_at', { ascending: false }).limit(30)
      setSentEmails(data || [])
    } catch {}
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error) return <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  const filteredTemplates = templates.filter(t => {
    const meta = getTemplateMeta(t.slug)
    const chan = getChannel(t.slug)
    if (filters.categories?.length > 0 && !filters.categories.includes(meta.category)) return false
    if (filters.channels?.length > 0 && !filters.channels.includes(chan)) return false
    if (filters.search) {
      const s = filters.search.toLowerCase()
      if (!(t.name || '').toLowerCase().includes(s) && !(t.slug || '').toLowerCase().includes(s) && !(t.description || '').toLowerCase().includes(s) && !(meta.info || '').toLowerCase().includes(s)) return false
    }
    return true
  })

  const filteredEmails = sentEmails.filter(e => {
    if (filters.statuses?.length > 0 && !filters.statuses.includes(e.status)) return false
    if (filters.search) {
      const s = filters.search.toLowerCase()
      if (!(e.recipient_email || '').toLowerCase().includes(s) && !(e.subject || '').toLowerCase().includes(s) && !(e.template_slug || '').toLowerCase().includes(s)) return false
    }
    return true
  })

  // Group templates by category
  const grouped = {}
  filteredTemplates.forEach(t => {
    const meta = getTemplateMeta(t.slug)
    if (!grouped[meta.category]) grouped[meta.category] = []
    grouped[meta.category].push(t)
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <h2 className="text-lg font-extrabold" style={{ color: '#1a2e22' }}>E-mailové šablony</h2>
        <button onClick={() => setCreating(true)}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '10px 18px', background: '#74FB71', border: '1px solid #1a8a18', color: '#0a1f15' }}>
          + Nová šablona
        </button>
      </div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
          placeholder="Hledat šablonu, e-mail…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 200 }} />
        <CheckboxFilterGroup label="Kategorie" values={filters.categories || []}
          onChange={v => setFilters(f => ({ ...f, categories: v }))}
          options={CATEGORIES.map(c => ({ value: c.value, label: c.label }))} />
        <CheckboxFilterGroup label="Zdroj" values={filters.channels || []}
          onChange={v => setFilters(f => ({ ...f, channels: v }))}
          options={CHANNELS.map(c => ({ value: c.value, label: c.label }))} />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => setFilters(f => ({ ...f, statuses: v }))}
          options={[{ value: 'sent', label: 'Odesláno' }, { value: 'failed', label: 'Chyba' }, { value: 'queued', label: 'Ve frontě' }]} />
        {(filters.search || filters.statuses?.length > 0 || filters.categories?.length > 0 || filters.channels?.length > 0) && (
          <button onClick={() => { setFilters({ ...defaultFilters }); localStorage.removeItem('velin_emailtemplates_filters') }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
      </div>

      {filteredTemplates.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné e-mailové šablony odpovídající filtru</p></Card>
      ) : (
        CATEGORIES.filter(c => grouped[c.value]?.length > 0).map(cat => (
          <div key={cat.value} className="mb-6">
            <div className="flex items-center gap-2 mb-3">
              <span className="inline-block rounded-btn text-xs font-extrabold uppercase tracking-wide"
                style={{ padding: '4px 10px', background: cat.bg, color: cat.color }}>{cat.label}</span>
              <span className="text-sm" style={{ color: '#6b7280' }}>{grouped[cat.value].length} {grouped[cat.value].length === 1 ? 'šablona' : grouped[cat.value].length < 5 ? 'šablony' : 'šablon'}</span>
            </div>
            <div className="grid grid-cols-2 gap-4">
              {grouped[cat.value].map(t => (
                <TemplateCard key={t.id} template={t} onEdit={() => setEditing(t)} />
              ))}
            </div>
          </div>
        ))
      )}

      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3 mt-8" style={{ color: '#1a2e22' }}>Poslední odeslané e-maily</h3>
      <SentEmailsTable emails={filteredEmails} />

      {editing && (
        <EditEmailTemplateModal
          template={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}

      {creating && (
        <EditEmailTemplateModal
          template={{
            id: null,
            name: '',
            slug: '',
            subject: '',
            body_html: '',
            active: true,
            attachments: [],
            triggers: [],
          }}
          isNew
          onClose={() => setCreating(false)}
          onSaved={() => { setCreating(false); load() }}
        />
      )}
    </div>
  )
}

function TemplateCard({ template, onEdit }) {
  const vars = template.variables || extractVars(template.body_html)
  const meta = getTemplateMeta(template.slug)
  const catDef = CATEGORIES.find(c => c.value === meta.category) || CATEGORIES[4]
  const chanDef = CHANNELS.find(c => c.value === getChannel(template.slug)) || CHANNELS[2]
  const attachmentsList = Array.isArray(template.attachments) ? template.attachments : []

  return (
    <Card>
      <div className="flex items-center justify-between mb-1">
        <h4 className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{template.name}</h4>
        <div className="flex items-center gap-1">
          <Badge label={chanDef.label} color={chanDef.color} bg={chanDef.bg} />
          <Badge label={catDef.label} color={catDef.color} bg={catDef.bg} />
          <Badge label={template.active ? 'Aktivní' : 'Neaktivní'} color={template.active ? '#1a8a18' : '#6b7280'} bg={template.active ? '#dcfce7' : '#f3f4f6'} />
        </div>
      </div>
      <div className="text-xs font-mono mb-2" style={{ color: '#6b7280' }}>{template.slug}</div>

      {/* Info box */}
      <div className="rounded-btn text-xs mb-2" style={{ padding: '8px 10px', background: '#f8faf9', border: '1px solid #e5e7eb', lineHeight: 1.6, color: '#374151' }}>
        {meta.info && <div className="mb-1">{meta.info}</div>}
        <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1" style={{ fontSize: 11 }}>
          <span><strong style={{ color: '#1a2e22' }}>Trigger:</strong> {Array.isArray(template.triggers) && template.triggers.length > 0 ? `${template.triggers.length} přiřazen${template.triggers.length === 1 ? '' : (template.triggers.length < 5 ? 'y' : 'o')}` : (meta.trigger || '—')}</span>
          <span><strong style={{ color: '#1a2e22' }}>Přílohy:</strong> {attachmentsList.length > 0 ? attachmentsList.join(', ') : (meta.attachments || '—')}</span>
        </div>
      </div>

      {vars.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-2">
          {vars.map(v => (
            <span key={v} className="inline-block rounded-btn text-[9px] font-mono font-bold"
              style={{ padding: '2px 6px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              {`{{${v}}}`}
            </span>
          ))}
        </div>
      )}
      <Button onClick={onEdit} style={{ padding: '4px 14px', fontSize: 13 }}>Upravit</Button>
    </Card>
  )
}

function extractVars(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  return matches ? [...new Set(matches.map(m => m.replace(/[{}]/g, '')))] : []
}

function SentEmailsTable({ emails }) {
  if (emails.length === 0) return <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné odeslané e-maily</p></Card>
  return (
    <Table>
      <thead><TRow header><TH>Příjemce</TH><TH>Šablona</TH><TH>Předmět</TH><TH>Stav</TH><TH>Datum</TH></TRow></thead>
      <tbody>
        {emails.map(e => {
          const st = EMAIL_STATUS[e.status] || EMAIL_STATUS.queued
          return (
            <TRow key={e.id}>
              <TD>{e.recipient_email || '—'}</TD>
              <TD><span className="font-mono text-xs">{e.template_slug || '—'}</span></TD>
              <TD>{e.subject || '—'}</TD>
              <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
              <TD>{e.created_at ? new Date(e.created_at).toLocaleString('cs-CZ') : '—'}</TD>
            </TRow>
          )
        })}
      </tbody>
    </Table>
  )
}

function EditEmailTemplateModal({ template, onClose, onSaved, isNew = false }) {
  const [name, setName] = useState(template.name || '')
  const [slug, setSlug] = useState(template.slug || '')
  const [subject, setSubject] = useState(template.subject || '')
  const [bodyHtml, setBodyHtml] = useState(template.body_html || '')
  const [active, setActive] = useState(template.active ?? true)
  const [category, setCategory] = useState(getTemplateMeta(template.slug || '').category || 'other')
  const [channel, setChannel] = useState(getChannel(template.slug || ''))
  const [attachmentsSel, setAttachmentsSel] = useState(
    Array.isArray(template.attachments) ? template.attachments : []
  )
  const [triggersSel, setTriggersSel] = useState(
    Array.isArray(template.triggers) ? template.triggers : []
  )

  function toggleTrigger(slug) {
    setTriggersSel(prev =>
      prev.includes(slug) ? prev.filter(s => s !== slug) : [...prev, slug]
    )
  }
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [err, setErr] = useState(null)
  const [showPreview, setShowPreview] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  const fileInputRef = useRef(null)
  const meta = getTemplateMeta(template.slug)

  function toggleAttachment(val) {
    setAttachmentsSel(prev =>
      prev.includes(val) ? prev.filter(v => v !== val) : [...prev, val]
    )
  }

  const vars = template.variables || extractVars(bodyHtml)
  const variableOptions = vars.map(v => ({ label: `{{${v}}}`, value: `{{${v}}}` }))

  const handleFileDrop = useCallback((e) => {
    e.preventDefault(); setDragOver(false)
    const file = e.dataTransfer?.files?.[0] || e.target?.files?.[0]
    if (!file) return
    if (file.name.endsWith('.html') || file.name.endsWith('.htm') || file.type === 'text/html') {
      const reader = new FileReader()
      reader.onload = (ev) => setBodyHtml(ev.target.result)
      reader.readAsText(file)
    } else { setErr('Podporované formáty: .html, .htm') }
  }, [])

  function getPreviewHtml() {
    let html = bodyHtml
    for (const [k, v] of Object.entries(SAMPLE_VARS)) html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v)
    return html
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      if (isNew) {
        if (!slug || !slug.trim()) throw new Error('Slug je povinný (kód šablony, např. booking_reminder)')
        if (!/^[a-z0-9_]+$/.test(slug.trim())) throw new Error('Slug může obsahovat jen malá písmena, čísla a podtržítka')
      }
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        name,
        slug: slug.trim() || template.slug,
        subject,
        body_html: bodyHtml,
        active,
        attachments: attachmentsSel,
        triggers: triggersSel,
        updated_by: user?.id,
      }
      if (isNew) {
        const result = await debugAction('emailTemplate.insert', 'EditEmailTemplateModal', () =>
          supabase.from('email_templates').insert(payload).select().single()
        , payload)
        if (result?.error) throw result.error
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'email_template_created', details: { template_id: result.data?.id, slug: payload.slug } })
      } else {
        const result = await debugAction('emailTemplate.update', 'EditEmailTemplateModal', () =>
          supabase.from('email_templates').update(payload).eq('id', template.id)
        , payload)
        if (result?.error) throw result.error
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'email_template_updated', details: { template_id: template.id } })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function handleTestSend() {
    setTesting(true); setErr(null)
    try {
      const result = await debugAction('emailTemplate.testSend', 'EditEmailTemplateModal', () =>
        supabase.functions.invoke('send-email', { body: { template_slug: template.slug, test: true } })
      , { template_slug: template.slug, test: true })
      if (result?.error) throw result.error
    } catch (e) { setErr(`Test e-mail se nepodařilo odeslat: ${e.message || 'Edge Function nemusí být nasazena.'}`) }
    setTesting(false)
  }

  return (
    <Modal open title={isNew ? 'Nová e-mailová šablona' : `Upravit: ${template.name}`} onClose={onClose} wide>
      {/* Info panel */}
      <div className="rounded-btn mb-4" style={{ padding: '12px 14px', background: '#f8faf9', border: '1px solid #d4e8e0' }}>
        <div className="text-sm mb-1" style={{ color: '#374151', lineHeight: 1.6 }}>{meta.info}</div>
        <div className="flex flex-wrap gap-x-4 gap-y-1" style={{ fontSize: 12 }}>
          <span><strong style={{ color: '#1a2e22' }}>Trigger:</strong> {meta.trigger}</span>
          <span><strong style={{ color: '#1a2e22' }}>Přílohy:</strong> {meta.attachments}</span>
          <span><strong style={{ color: '#1a2e22' }}>Slug:</strong> <code style={{ background: '#e5e7eb', padding: '1px 4px', borderRadius: 4 }}>{template.slug}</code></span>
        </div>
      </div>

      <div className="space-y-3">
        <div><Label>Název</Label><input type="text" value={name} onChange={e => setName(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="např. Připomínka 24h před převzetím" /></div>
        {isNew && (
          <div>
            <Label>Slug (kód šablony)</Label>
            <input type="text" value={slug} onChange={e => setSlug(e.target.value.toLowerCase().replace(/\s+/g, '_'))}
              className="w-full rounded-btn text-sm outline-none font-mono"
              style={inputStyle} placeholder="např. booking_reminder_24h" />
            <div className="text-xs mt-1" style={{ color: '#6b7280' }}>
              Malá písmena, čísla, podtržítka. Slug je trvalý identifikátor — nelze později změnit.
            </div>
          </div>
        )}
        <div><Label>Předmět</Label><input type="text" value={subject} onChange={e => setSubject(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Použijte {{booking_number}} apod. pro proměnné" /></div>

        <div className="rounded-lg text-center cursor-pointer transition-colors"
          style={{ padding: '16px', border: `2px dashed ${dragOver ? '#74FB71' : '#d4e8e0'}`, background: dragOver ? '#f0fff4' : '#f9fdfb' }}
          onDragOver={e => { e.preventDefault(); setDragOver(true) }} onDragLeave={() => setDragOver(false)}
          onDrop={handleFileDrop} onClick={() => fileInputRef.current?.click()}>
          <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>Přetáhněte HTML soubor sem nebo klikněte pro výběr</div>
          <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Podporované formáty: .html, .htm</div>
          <input ref={fileInputRef} type="file" accept=".html,.htm" onChange={handleFileDrop} className="hidden" />
        </div>

        <div><Label>Tělo e-mailu</Label>
          <RichTextEditor
            value={bodyHtml}
            onChange={setBodyHtml}
            placeholder="Začněte psát obsah e-mailu… Pomocí lišty můžete formátovat text, vkládat nadpisy, seznamy, odkazy, obrázky a proměnné."
            minHeight={320}
            variables={variableOptions}
          />
        </div>

        <div>
          <Label>Přílohy</Label>
          <div className="text-xs mb-2" style={{ color: '#6b7280' }}>
            Vyberte které dokumenty se k tomuto e-mailu automaticky přiloží. Edge funkce je vygeneruje (nebo dohledá v invoices/documents) podle booking/order ID.
          </div>
          <div className="flex flex-wrap gap-2">
            {ATTACHMENT_OPTIONS.map(opt => {
              const checked = attachmentsSel.includes(opt.value)
              return (
                <label key={opt.value}
                  className="flex items-center gap-2 cursor-pointer rounded-btn"
                  style={{
                    padding: '6px 10px',
                    background: checked ? '#dcfce7' : '#f9fafb',
                    border: `1px solid ${checked ? '#86efac' : '#e5e7eb'}`,
                    color: checked ? '#166534' : '#374151',
                    fontSize: 12,
                  }}>
                  <input type="checkbox" checked={checked} onChange={() => toggleAttachment(opt.value)}
                    className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
                  <span style={{ fontWeight: checked ? 700 : 500 }}>{opt.label}</span>
                </label>
              )
            })}
          </div>
        </div>

        <div>
          <Label>Triggery — kdy se šablona pošle</Label>
          <div className="text-xs mb-2" style={{ color: '#6b7280' }}>
            Vyberte události které vyvolají odeslání této šablony. Můžete kombinovat libovolné množství.
            <br/><strong>Pozn.:</strong> dispatcher v edge funkcích zatím rozhoduje podle <code>type</code> v payloadu — tato data slouží jako reference + příprava na dynamický dispatcher (změna typu šablony bude později řízená přímo z této tabulky).
          </div>
          <div className="space-y-3">
            {TRIGGER_CATALOG.map(group => (
              <div key={group.group} className="rounded-btn" style={{ padding: '10px 12px', background: '#f8faf9', border: '1px solid #e5e7eb' }}>
                <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{group.group}</div>
                <div className="flex flex-wrap gap-2">
                  {group.items.map(item => {
                    const checked = triggersSel.includes(item.slug)
                    return (
                      <label key={item.slug}
                        className="flex items-center gap-2 cursor-pointer rounded-btn"
                        style={{
                          padding: '5px 9px',
                          background: checked ? '#dbeafe' : '#ffffff',
                          border: `1px solid ${checked ? '#60a5fa' : '#e5e7eb'}`,
                          color: checked ? '#1e3a8a' : '#374151',
                          fontSize: 11.5,
                        }}>
                        <input type="checkbox" checked={checked} onChange={() => toggleTrigger(item.slug)}
                          className="accent-[#2563eb]" style={{ width: 13, height: 13 }} />
                        <span style={{ fontWeight: checked ? 700 : 500 }}>{item.label}</span>
                      </label>
                    )
                  })}
                </div>
              </div>
            ))}
            {triggersSel.length > 0 && (
              <div className="text-xs" style={{ color: '#6b7280' }}>
                Vybráno: <strong style={{ color: '#1a2e22' }}>{triggersSel.length}</strong> trigger{triggersSel.length === 1 ? '' : 'ů'}
                <button onClick={() => setTriggersSel([])}
                  className="ml-3 text-xs cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>
                  Vymazat výběr
                </button>
              </div>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2">
          <input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} id="tpl-active" />
          <label htmlFor="tpl-active" className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní</label>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-between gap-3 mt-5">
        <div className="flex gap-2">
          <Button onClick={() => setShowPreview(true)}>Náhled</Button>
          <Button onClick={handleTestSend} disabled={testing}>{testing ? 'Odesílám…' : 'Odeslat test'}</Button>
        </div>
        <div className="flex gap-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        </div>
      </div>

      {showPreview && (
        <FullEmailPreviewModal
          subject={subject.replace(/\{\{(\w+)\}\}/g, (_, k) => SAMPLE_VARS[k] || `{{${k}}}`)}
          bodyHtml={getPreviewHtml()}
          attachments={attachmentsSel}
          fromEmail="noreply@motogo24.cz"
          toEmail="zakaznik@example.cz"
          replyTo="info@motogo24.cz"
          onClose={() => setShowPreview(false)}
        />
      )}
    </Modal>
  )
}

/** Plný náhled e-mailu — branded wrap (hlavička + footer + helpcard) v iframe
 *  + seznam příloh, klik → otevře iframe s ukázkovou přílohou (HTML preview).
 *  Účel: admin uvidí přesně to, co dorazí zákazníkovi (UI + obrázky + přílohy). */
function FullEmailPreviewModal({ subject, bodyHtml, attachments, fromEmail, toEmail, replyTo, onClose }) {
  const [openAtt, setOpenAtt] = useState(null)
  const fullHtml = wrapPreview(bodyHtml)

  // Mapping příloh na ikony + popisek pro UI
  const attMeta = {
    ZF:       { icon: '📄', label: 'Zálohová faktura',    file: 'Zalohova-faktura-ZF-2026-0001.pdf' },
    DP:       { icon: '🧾', label: 'Doklad o platbě',     file: 'Doklad-platby-DP-2026-0001.pdf' },
    KF:       { icon: '🧮', label: 'Konečná faktura',     file: 'Konecna-faktura-KF-2026-0001.pdf' },
    Smlouva:  { icon: '📑', label: 'Nájemní smlouva',     file: 'Najemni-smlouva.pdf' },
    VOP:      { icon: '📋', label: 'VOP',                  file: 'VOP.pdf' },
    Dobropis: { icon: '↩️', label: 'Dobropis',             file: 'Dobropis-DB-2026-0001.pdf' },
    Voucher:  { icon: '🎁', label: 'Dárkový poukaz',      file: 'Voucher.pdf' },
    eshop_DP: { icon: '🛒', label: 'DP — e-shop',         file: 'Eshop-DP-2026-0001.pdf' },
    eshop_KF: { icon: '🛍️', label: 'KF — e-shop',         file: 'Eshop-KF-2026-0001.pdf' },
  }

  return (
    <Modal open title="Náhled e-mailu — jak ho uvidí zákazník" onClose={onClose} wide>
      {/* Resend-like meta panel */}
      <div className="rounded-btn mb-3" style={{ padding: 12, background: '#f8faf9', border: '1px solid #d4e8e0', fontSize: 12, lineHeight: 1.7 }}>
        <div><strong style={{ color: '#1a2e22' }}>Od:</strong> <span className="font-mono" style={{ color: '#374151' }}>{fromEmail}</span></div>
        <div><strong style={{ color: '#1a2e22' }}>Komu:</strong> <span className="font-mono" style={{ color: '#374151' }}>{toEmail}</span></div>
        <div><strong style={{ color: '#1a2e22' }}>Reply-To:</strong> <span className="font-mono" style={{ color: '#374151' }}>{replyTo}</span></div>
        <div><strong style={{ color: '#1a2e22' }}>Předmět:</strong> <span style={{ color: '#0f1a14', fontWeight: 600 }}>{subject || '—'}</span></div>
      </div>

      {/* Branded HTML preview v iframe (autentický rendering — žádné style úniky) */}
      <div className="rounded-card mb-3" style={{ background: '#d9dee2', border: '1px solid #d4e8e0', overflow: 'hidden' }}>
        <iframe
          title="Email preview"
          srcDoc={fullHtml}
          style={{ width: '100%', height: 600, border: 0, background: '#d9dee2', display: 'block' }}
          sandbox=""
        />
      </div>

      {/* Přílohy — seznam s klik-na-otevři */}
      {attachments && attachments.length > 0 ? (
        <div className="rounded-btn mb-3" style={{ padding: 12, background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
            Přílohy ({attachments.length})
          </div>
          <div className="flex flex-wrap gap-2">
            {attachments.map(att => {
              const m = attMeta[att] || { icon: '📎', label: att, file: `${att}.pdf` }
              return (
                <button key={att}
                  onClick={() => setOpenAtt(att)}
                  className="rounded-btn text-xs cursor-pointer flex items-center gap-2"
                  style={{
                    padding: '8px 12px', background: '#fff', border: '1px solid #d4e8e0',
                    color: '#1a2e22', fontWeight: 600,
                  }}>
                  <span style={{ fontSize: 14 }}>{m.icon}</span>
                  <span>{m.label}</span>
                  <span style={{ color: '#9ca3af', fontSize: 10, fontFamily: 'monospace' }}>{m.file}</span>
                </button>
              )
            })}
          </div>
          <div className="text-[10px] mt-2" style={{ color: '#6b7280' }}>
            Klikni na přílohu pro náhled. V reálném e-mailu jsou tyto soubory generovány v okamžiku odeslání podle booking/order ID — zde zobrazujeme ukázkový obsah.
          </div>
        </div>
      ) : (
        <div className="rounded-btn mb-3 text-xs" style={{ padding: 8, background: '#fef3c7', border: '1px solid #fde68a', color: '#78350f' }}>
          ℹ️ Tato šablona neobsahuje žádné přílohy.
        </div>
      )}

      <div className="flex justify-end mt-2"><Button onClick={onClose}>Zavřít</Button></div>

      {openAtt && (
        <Modal open title={`Náhled přílohy: ${attMeta[openAtt]?.label || openAtt}`} onClose={() => setOpenAtt(null)} wide>
          <div className="text-xs mb-2" style={{ color: '#6b7280' }}>
            Toto je ukázkový obsah přílohy. V reálném e-mailu se generuje per-rezervace podle aktuálních dat z DB.
          </div>
          <div className="rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', overflow: 'hidden', height: 500 }}>
            <iframe
              title="Attachment preview"
              srcDoc={renderAttachmentSample(openAtt)}
              style={{ width: '100%', height: '100%', border: 0, display: 'block' }}
              sandbox=""
            />
          </div>
          <div className="flex justify-end mt-4"><Button onClick={() => setOpenAtt(null)}>Zavřít</Button></div>
        </Modal>
      )}
    </Modal>
  )
}

/** Ukázkový HTML obsah přílohy pro náhled v EmailTemplatesTab.
 *  V reálu se generuje přes generate-invoice / generate-document edge funkce. */
function renderAttachmentSample(att) {
  const labels = {
    ZF: 'ZÁLOHOVÁ FAKTURA',
    DP: 'DOKLAD O PŘIJATÉ PLATBĚ',
    KF: 'KONEČNÁ FAKTURA',
    Dobropis: 'DOBROPIS',
    Smlouva: 'NÁJEMNÍ SMLOUVA',
    VOP: 'VŠEOBECNÉ OBCHODNÍ PODMÍNKY',
    Voucher: 'DÁRKOVÝ POUKAZ',
    eshop_DP: 'DOKLAD O PŘIJATÉ PLATBĚ — E-SHOP',
    eshop_KF: 'KONEČNÁ FAKTURA — E-SHOP',
  }
  const title = labels[att] || att
  return `<!DOCTYPE html><html><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,'Segoe UI',Arial,sans-serif">
  <div style="max-width:780px;margin:0 auto;background:#fff;min-height:100vh">
    <div style="background:#000;padding:28px 32px">
      <table width="100%" cellpadding="0" cellspacing="0"><tr>
        <td style="vertical-align:middle">
          <div style="color:#fff;font-size:24px;font-weight:900;letter-spacing:2px">MOTO GO 24</div>
          <div style="color:#fff;font-size:10px;letter-spacing:4px;margin-top:6px">PŮJČOVNA MOTOREK</div>
        </td>
        <td style="vertical-align:middle;text-align:right">
          <div style="display:inline-block;background:#74FB71;color:#000;font-size:10px;font-weight:800;letter-spacing:1px;padding:5px 9px;border-radius:3px">${title}</div>
          <div style="color:#fff;font-size:18px;font-weight:600;margin-top:8px">${title === 'NÁJEMNÍ SMLOUVA' || title === 'VŠEOBECNÉ OBCHODNÍ PODMÍNKY' ? 'Smlouva' : 'č. 2026-0001'}</div>
        </td>
      </tr></table>
    </div>
    <div style="padding:24px 32px;color:#0f1a14;font-size:13px;line-height:1.7">
      <p><strong>Dodavatel:</strong> Bc. Petra Semorádová · Mezná 9, 393 01 Pelhřimov · IČO: 21874263</p>
      <p><strong>Odběratel:</strong> Jan Novák · Hlavní 123, 110 00 Praha 1</p>
      <hr style="border:0;border-top:1px solid #e5e7eb;margin:16px 0">
      <p style="color:#6b7280;font-size:12px">Toto je ukázkový obsah. Reálný dokument generuje edge funkce <code>generate-invoice</code> nebo <code>generate-document</code> v okamžiku vytvoření rezervace / objednávky a obsahuje konkrétní data zákazníka.</p>
      <table style="width:100%;border-collapse:collapse;margin:16px 0;border:1px solid #e5e7eb;font-size:13px">
        <tr style="background:#000;color:#fff"><th style="padding:10px 12px;text-align:left">Položka</th><th style="padding:10px 12px;text-align:right">Částka</th></tr>
        <tr><td style="padding:10px 12px;border-top:1px solid #e5e7eb">Pronájem motorky BMW R 1200 GS Adventure (3 dny)</td><td style="padding:10px 12px;border-top:1px solid #e5e7eb;text-align:right">7 800 Kč</td></tr>
        <tr style="background:#dcfce7"><td style="padding:14px 12px;font-weight:800">Celkem</td><td style="padding:14px 12px;text-align:right;font-weight:800">7 800 Kč</td></tr>
      </table>
    </div>
    <div style="background:#000;padding:14px 32px;color:#fff;font-size:11px">
      Bc. Petra Semorádová · Mezná 9, 393 01 Pelhřimov · IČO: 21874263 · <span style="color:#74FB71">+420 774 256 271</span> · <span style="color:#74FB71">info@motogo24.cz</span> · <span style="color:#74FB71">motogo24.cz</span>
    </div>
  </div>
</body></html>`
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
