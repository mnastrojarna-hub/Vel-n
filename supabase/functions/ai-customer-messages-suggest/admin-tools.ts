// ===== ai-customer-messages-suggest/admin-tools.ts =====
// Nástroje agenta ve Velíně = VŠECHNY nástroje servisního agenta z appky (rezervace
// zákazníka, přístupové kódy, návody, troubleshooting, flotila) + informační nástroje
// veřejného agenta (katalog, cena, dostupnost, FAQ, podmínky, VOP, příslušenství,
// pobočky, promo) + Velínské read-only nástroje nad celou DB (přehled zákazníka,
// dohledání rezervace). Nic nezapisuje — návrh odpovědi vždy schvaluje člověk.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TOOLS as SERVICE_TOOLS } from '../ai-moto-agent/tools-definitions.ts'
import { executeTool as execServiceTool } from '../ai-moto-agent/tools-executor.ts'
import { BOOKING_SELECT, bookingLine } from './context.ts'

const ADMIN_TOOLS = [
  {
    name: 'get_customer_overview',
    description: 'Kompletní Velínský přehled zákazníka z tohoto vlákna (nebo dle customer_id): profil, VŠECHNY rezervace (stav, platba, ceny, slevy, storna, úpravy termínu, převzetí/vrácení, poškození), SOS incidenty, reklamace, objednávky e-shopu/poukazů a posledních 15 odeslaných e-mailů. Volej, když potřebuješ víc než kontext v promptu (urgence, platby, storno, „nepřišel mi e-mail", historie).',
    input_schema: { type: 'object' as const, properties: { customer_id: { type: 'string', description: 'UUID zákazníka (volitelné — výchozí je zákazník vlákna)' } }, required: [] },
  },
  {
    name: 'find_booking',
    description: 'Dohledá rezervace podle čísla rezervace (#XXXXXXXX = posledních 8 znaků id, nebo celé UUID), e-mailu, telefonu nebo jména zákazníka. Použij, když vlákno nemá přiřazeného zákazníka nebo zákazník zmiňuje jinou rezervaci.',
    input_schema: { type: 'object' as const, properties: { query: { type: 'string', description: 'Číslo rezervace, e-mail, telefon nebo jméno' } }, required: ['query'] },
  },
]

export const AGENT_TOOLS = [...SERVICE_TOOLS, ...ADMIN_TOOLS]
const NEEDS_CUSTOMER = new Set(['get_active_booking', 'get_booking_history', 'get_access_status'])

async function customerOverview(sb: SupabaseClient, cid: string): Promise<unknown> {
  const [prof, bk, sos, compl, orders] = await Promise.all([
    sb.from('profiles').select('id, full_name, email, phone, city, language, license_group, license_expiry, riding_experience, is_blocked, created_at').eq('id', cid).maybeSingle(),
    sb.from('bookings').select(BOOKING_SELECT).eq('user_id', cid).order('start_date', { ascending: false }).limit(30),
    sb.from('sos_incidents').select('id, booking_id, type, title, description, severity, status, moto_rideable, resolution, created_at').eq('user_id', cid).order('created_at', { ascending: false }).limit(10),
    sb.from('booking_complaints').select('booking_id, subject, description, status, resolution, created_at').eq('customer_id', cid).order('created_at', { ascending: false }).limit(10),
    sb.from('shop_orders').select('order_number, status, payment_status, total, created_at, shipped_at, tracking_number').eq('customer_id', cid).order('created_at', { ascending: false }).limit(10),
  ])
  const email = (prof.data as { email?: string } | null)?.email
  const mails = email
    ? await sb.from('sent_emails').select('template_slug, subject, status, sent_at, booking_id').eq('recipient_email', email).order('created_at', { ascending: false }).limit(15)
    : { data: [] }
  const bookings = ((bk.data || []) as Array<Record<string, unknown>>).map((b) => ({
    summary: bookingLine(b).slice(2),
    pickup: [b.pickup_method, b.pickup_address, b.pickup_time].filter(Boolean).join(' '),
    return: [b.return_method, b.return_address, b.return_time].filter(Boolean).join(' '),
    picked_up_at: b.picked_up_at, returned_at: b.returned_at, mileage_start: b.mileage_start, mileage_end: b.mileage_end,
    handover_protocol_filled_at: b.handover_protocol_filled_at, docs_completed_at: b.docs_completed_at,
    extras_price: b.extras_price, delivery_fee: b.delivery_fee, payment_method: b.payment_method, pay_channel: b.pay_channel,
    damage_flag: b.damage_flag, damage_note: b.damage_note, complaint_status: b.complaint_status,
    modification_history: b.modification_history, notes: b.notes,
    moto_box_number: (b.motorcycles as Record<string, unknown> | null)?.box_number,
    branch: ((b.motorcycles as Record<string, unknown> | null)?.branches as Record<string, unknown> | null)?.name,
  }))
  return { profile: prof.data, bookings, sos_incidents: sos.data || [], complaints: compl.data || [], shop_orders: orders.data || [], sent_emails: mails.data || [] }
}

async function findBooking(sb: SupabaseClient, query: string): Promise<unknown> {
  const q = query.trim().replace(/^#/, '')
  if (!q) return { error: 'prázdný dotaz' }
  if (/^[0-9a-f-]{36}$/i.test(q)) {
    const { data } = await sb.from('bookings').select(BOOKING_SELECT).eq('id', q).limit(1)
    return { bookings: (data || []).map((b) => ({ user_id: b.user_id, line: bookingLine(b) })) }
  }
  if (/^[0-9a-f]{8}$/i.test(q)) {
    const { data } = await sb.from('bookings').select(BOOKING_SELECT).order('created_at', { ascending: false }).limit(1500)
    const hit = ((data || []) as Array<Record<string, unknown>>).filter((b) => String(b.id).toLowerCase().endsWith(q.toLowerCase()))
    return { bookings: hit.map((b) => ({ user_id: b.user_id, line: bookingLine(b) })) }
  }
  const safe = q.replace(/[,()%*]/g, ' ').trim()
  const { data: profs } = await sb.from('profiles').select('id, full_name, email, phone')
    .or(`email.ilike.%${safe}%,phone.ilike.%${safe.replace(/\s/g, '')}%,full_name.ilike.%${safe}%`).limit(5)
  const out = []
  for (const p of (profs || []) as Array<Record<string, unknown>>) {
    const { data } = await sb.from('bookings').select(BOOKING_SELECT).eq('user_id', p.id as string).order('start_date', { ascending: false }).limit(10)
    out.push({ customer: p, bookings: ((data || []) as Array<Record<string, unknown>>).map(bookingLine) })
  }
  return out.length ? { matches: out } : { matches: [], note: 'Nic nenalezeno.' }
}

export async function executeAgentTool(sb: SupabaseClient, name: string, input: Record<string, unknown>, customerId: string | null, lang: string): Promise<unknown> {
  try {
    if (name === 'get_customer_overview') {
      const cid = (typeof input.customer_id === 'string' && input.customer_id) || customerId
      return cid ? await customerOverview(sb, cid) : { error: 'Vlákno nemá přiřazeného zákazníka — použij find_booking.' }
    }
    if (name === 'find_booking') return await findBooking(sb, String(input.query || ''))
    if (NEEDS_CUSTOMER.has(name) && !customerId) return { error: 'Vlákno nemá přiřazeného zákazníka — nejdřív find_booking.' }
    return await execServiceTool(name, input, sb, customerId || '', lang)
  } catch (e) {
    return { error: (e as Error).message }
  }
}
