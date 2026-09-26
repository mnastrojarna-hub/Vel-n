// ===== ai-customer-messages-suggest/context.ts =====
// Načtení KOMPLETNÍHO kontextu vlákna: zákazník, jeho rezervace (stejný formát jako
// servisní agent v appce), historie vlákna a vzorové odpovědi týmu z jiných vláken.
// Dřívější verze četla rezervaci se sloupcem `deposit`, který v DB neexistuje →
// dotaz padal a AI si myslela, že zákazník žádnou rezervaci nemá.
import { formatBookingContext, formatMultipleBookingsContext } from '../ai-moto-agent/booking-context.ts';
export function dirLabel(d) {
  const x = (d || '').toLowerCase();
  if (x === 'customer' || x === 'inbound') return 'Zákazník';
  if (x === 'admin' || x === 'outbound') return 'MotoGo24 (tým)';
  if (x === 'system') return 'Systém';
  return x || '?';
}
export const isInbound = (d)=>[
    'customer',
    'inbound'
  ].includes((d || '').toLowerCase());
const isStaff = (d)=>[
    'admin',
    'outbound'
  ].includes((d || '').toLowerCase());
// Rezervace se čtou přes `*` — výčet sloupců už jednou shodil celý dotaz (neexistující `deposit`).
export const BOOKING_SELECT = '*, motorcycles!moto_id(*, branches!branch_id(*))';
export function bookingLine(b) {
  const m = b.motorcycles || {};
  const ref = String(b.id || '').slice(-8).toUpperCase();
  const disc = Number(b.discount_amount || 0) > 0 ? `, sleva ${b.discount_amount} Kč${b.discount_code ? ` (${b.discount_code})` : ''}` : '';
  const cancel = b.status === 'cancelled' ? `, zrušeno ${b.cancelled_at ? String(b.cancelled_at).slice(0, 10) : ''}${b.cancellation_reason ? ` — ${b.cancellation_reason}` : ''}` : '';
  return `- #${ref} [id=${b.id}] ${m.brand || ''} ${m.model || '?'} | ${b.start_date} – ${b.end_date} | stav ${b.status}, platba ${b.payment_status || '?'} | cena ${b.total_price ?? '?'} Kč${disc} | zdroj ${b.booking_source || '?'}${cancel}`;
}
async function loadBookings(sb, customerId) {
  const { data, error } = await sb.from('bookings').select(BOOKING_SELECT).eq('user_id', customerId).order('start_date', {
    ascending: false
  }).limit(20);
  if (error) return {
    ctx: `\n\n## KONTEXT REZERVACE: načtení selhalo (${error.message}) — použij get_customer_overview / get_active_booking.`,
    list: ''
  };
  const all = data || [];
  if (!all.length) return {
    ctx: '\n\n## KONTEXT REZERVACE:\nZákazník v DB nemá žádnou rezervaci (ani historickou).',
    list: ''
  };
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Prague'
  }).format(new Date());
  const live = all.filter((b)=>[
      'active',
      'reserved',
      'pending'
    ].includes(String(b.status)));
  const active = live.find((b)=>b.status === 'active');
  const upcoming = live.filter((b)=>b.status !== 'active' && String(b.end_date) >= today).sort((a, b)=>String(a.start_date).localeCompare(String(b.start_date)));
  let ctx = '';
  if (active) ctx = formatBookingContext(active, upcoming.length ? upcoming : null);
  else if (upcoming.length === 1) ctx = formatBookingContext(upcoming[0], null);
  else if (upcoming.length > 1) ctx = formatMultipleBookingsContext(upcoming);
  else ctx = '\n\n## KONTEXT REZERVACE:\nZákazník nemá žádnou aktivní ani nadcházející rezervaci — viz historie rezervací níže.';
  const list = `\n\n## VŠECHNY REZERVACE ZÁKAZNÍKA (Velín, nejnovější první — ${all.length}):\n${all.map(bookingLine).join('\n')}`;
  return {
    ctx,
    list
  };
}
// Páry „dotaz zákazníka → skutečná odpověď týmu" z posledních vláken = ustálené odpovědi
// firmy (např. „všechny motorky mají držák na telefon"). Jen jako znalost/styl.
async function loadStaffExamples(sb, excludeThread) {
  try {
    const { data } = await sb.from('messages').select('thread_id, direction, content, created_at').neq('thread_id', excludeThread).order('created_at', {
      ascending: false
    }).limit(600);
    const byThread = new Map();
    for (const m of (data || []).reverse()){
      if (!byThread.has(m.thread_id)) byThread.set(m.thread_id, []);
      byThread.get(m.thread_id).push(m);
    }
    const pairs = [];
    for (const msgs of byThread.values()){
      for(let i = 1; i < msgs.length; i++){
        const a = msgs[i], q = msgs[i - 1];
        if (!isStaff(a.direction) || !isInbound(q.direction)) continue;
        const qa = (q.content || '').trim(), aa = (a.content || '').trim();
        if (qa.length < 8 || aa.length < 15) continue;
        pairs.push({
          at: a.created_at,
          q: qa.slice(0, 300),
          a: aa.slice(0, 450)
        });
      }
    }
    pairs.sort((x, y)=>y.at.localeCompare(x.at));
    const top = pairs.slice(0, 30);
    if (!top.length) return '';
    return `## USTÁLENÉ ODPOVĚDI TÝMU (skutečné odpovědi MotoGo24 z jiných vláken, nejnovější první)
Ber je jako ZNALOST firmy a vzor stylu (co tým zákazníkům reálně říká — např. vybavení motorek, postupy). Při rozporu s živými daty (rezervace, ceny, dostupnost) platí živá data. Údaje JINÝCH zákazníků (jména, termíny, rezervace) NIKDY nepřenášej do odpovědi.
${top.map((p)=>`• Z: ${p.q.replace(/\s+/g, ' ')}\n  T: ${p.a.replace(/\s+/g, ' ')}`).join('\n')}`;
  } catch  {
    return '';
  }
}
export async function loadThreadContext(sb, threadId, focusMessageId) {
  const { data: thread } = await sb.from('message_threads').select('*').eq('id', threadId).maybeSingle();
  if (!thread) return null;
  const customerId = thread.customer_id || null;
  const [custRes, histRes, bookings, staffExamples] = await Promise.all([
    customerId ? sb.from('profiles').select('*').eq('id', customerId).maybeSingle() : Promise.resolve({
      data: null
    }),
    sb.from('messages').select('id, direction, content, created_at').eq('thread_id', threadId).order('created_at', {
      ascending: true
    }).limit(500),
    customerId ? loadBookings(sb, customerId) : Promise.resolve({
      ctx: '\n\n## KONTEXT REZERVACE:\nVlákno nemá přiřazeného zákazníka — pokud zpráva zmiňuje rezervaci, e-mail nebo telefon, dohledej ji nástrojem find_booking.',
      list: ''
    }),
    loadStaffExamples(sb, threadId)
  ]);
  let history = histRes.data || [];
  let focus = null;
  if (focusMessageId) {
    const idx = history.findIndex((m)=>m.id === focusMessageId);
    if (idx >= 0) {
      focus = history[idx];
      history = history.slice(0, idx + 1);
    }
  }
  if (!focus) focus = [
    ...history
  ].reverse().find((m)=>isInbound(m.direction)) || null;
  history = history.slice(-40);
  return {
    thread,
    customerId,
    channel: String(thread.channel || 'unknown').toLowerCase(),
    customer: custRes.data || null,
    bookingContext: bookings.ctx,
    bookingsList: bookings.list,
    history,
    focus,
    staffExamples
  };
}
