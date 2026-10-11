/**
 * MotoGo24 — Edge Function: Generate Report
 * Generování finančních a provozních reportů (JSON).
 *
 * POST /functions/v1/generate-report
 * Auth: Bearer JWT (admin_users.id = uživatel, role manager / superadmin, active)
 * Body: { type, period_from: 'YYYY-MM-DD', period_to: 'YYYY-MM-DD', branch_id? }
 *
 * Pobočka = pobočka REZERVACE (bookings.branch_id — kde zákazník převzal; u NULL aktuální pobočka motorky).
 *  • Příjmy/vratky pobočky přes accounting_entries.booking_id → pobočka rezervace (sloupec
 *    accounting_entries.branch_id nikdo neplní, dřív tím report pobočky vycházel vždy 0). Záznamy bez
 *    rezervace a bez branch_id pobočce přiřadit nelze → `unassigned_income` / `unassigned_expense`.
 *  • Vratky (category 'refund', záporná částka u expense) snižují příjem — dřív zvyšovaly zisk.
 *  • Servis: maintenance_log.service_date, náklad = invoiced_amount > 0 ? invoiced_amount : cost
 *    (= Velín serviceBook.effectiveCost); pobočka = kde motorka v den servisu stála (poslední zalogovaný
 *    přesun / rezervace před tím dnem, jinak první po něm, jinak aktuální pobočka).
 *  • Tržby motorek (moto_roi) = ukončené zaplacené rezervace (jako Velín Výkon motorek).
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';

type ReportType = 'monthly' | 'annual' | 'pl' | 'balance_sheet' | 'cashflow' | 'moto_roi';
interface ReportRequest { type: ReportType; period_from: string; period_to: string; branch_id?: string }
// deno-lint-ignore no-explicit-any
type R = Record<string, any>;
type Admin = ReturnType<typeof getAdminClient>;

const PAID = ['paid', 'partial_refund', 'refund_pending', 'refunded'];
const isRealized = (b: R) => b.status !== 'cancelled' && b.is_test !== true && PAID.includes(b.payment_status);
const UUID = /^[0-9a-f-]{36}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const nextDay = (d: string) => new Date(Date.parse(d + 'T00:00:00Z') + 86400000).toISOString().slice(0, 10);
const round = (n: number) => Math.round(n * 100) / 100;

/** Všechny řádky (PostgREST vrací max. 1000 na dotaz). */
// deno-lint-ignore no-explicit-any
async function fetchAll(makeQuery: () => any): Promise<R[]> {
  const out: R[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await makeQuery().range(from, from + 999);
    if (error) throw new Error(error.message);
    out.push(...(data ?? []));
    if (!data || data.length < 1000) return out;
  }
}

/** Kontext poboček: motorky (aktuální pobočka) + pobočka rezervací dle id. */
async function loadBranchCtx(admin: Admin) {
  const motos = await fetchAll(() => admin.from('motorcycles').select('id, model, spz, purchase_price, status, branch_id').order('id'));
  const motoBranch: R = Object.fromEntries(motos.map((m) => [m.id, m.branch_id]));
  const bookingBranch = async (ids: string[]): Promise<R> => {
    const out: R = {};
    const uniq = [...new Set(ids.filter(Boolean))];
    for (let i = 0; i < uniq.length; i += 200) {
      const { data, error } = await admin.from('bookings').select('id, branch_id, moto_id').in('id', uniq.slice(i, i + 200));
      if (error) throw new Error(error.message);
      for (const b of data ?? []) out[b.id] = b.branch_id || motoBranch[b.moto_id] || null;
    }
    return out;
  };
  return { motos, motoBranch, bookingBranch };
}
type BranchCtx = Awaited<ReturnType<typeof loadBranchCtx>>;

/** Měsíční / roční report. */
async function generatePeriodReport(admin: Admin, from: string, to: string, branchId?: string, ctxIn?: BranchCtx): Promise<R> {
  const ctx = ctxIn ?? await loadBranchCtx(admin);
  const entries = await fetchAll(() => admin.from('accounting_entries')
    .select('id, type, amount, category, date, booking_id, branch_id').gte('date', from).lte('date', to).order('id'));
  const entryBranch = branchId ? await ctx.bookingBranch(entries.map((e) => e.booking_id)) : {};

  let income = 0, refunds = 0, expense = 0, unassignedIncome = 0, unassignedExpense = 0;
  const incomeByCategory: R = {}, expenseByCategory: R = {};
  for (const e of entries) {
    const amt = Number(e.amount) || 0;
    const isRefund = String(e.category || '').toLowerCase() === 'refund';
    if (branchId) {
      const br = e.booking_id ? entryBranch[e.booking_id] : e.branch_id;
      if (!br) { if (e.type === 'income' && !isRefund) unassignedIncome += amt; else unassignedExpense += isRefund ? Math.abs(amt) : amt; continue; }
      if (br !== branchId) continue;
    }
    if (isRefund) { refunds += Math.abs(amt); continue; }
    if (e.type === 'income') { income += amt; incomeByCategory[e.category] = (incomeByCategory[e.category] ?? 0) + amt; }
    else { expense += amt; expenseByCategory[e.category] = (expenseByCategory[e.category] ?? 0) + amt; }
  }

  // Rezervace se začátkem v období (bez testovacích), pobočka rezervace
  const bookings = (await fetchAll(() => admin.from('bookings')
    .select('id, status, payment_status, total_price, start_date, moto_id, branch_id, is_test')
    .gte('start_date', from).lt('start_date', nextDay(to)).not('is_test', 'is', true).order('id')))
    .filter((b) => !branchId || (b.branch_id || ctx.motoBranch[b.moto_id]) === branchId);
  const realized = bookings.filter(isRealized);
  const netIncome = income - refunds;

  return {
    total_income: round(income),
    refunds: round(refunds),
    net_income: round(netIncome),
    total_expense: round(expense),
    profit: round(netIncome - expense),
    margin_percent: netIncome > 0 ? Math.round(((netIncome - expense) / netIncome) * 100) : 0,
    income_by_category: incomeByCategory,
    expense_by_category: expenseByCategory,
    ...(branchId ? { unassigned_income: round(unassignedIncome), unassigned_expense: round(unassignedExpense) } : {}),
    total_bookings: bookings.length,
    completed_bookings: bookings.filter((b) => b.status === 'completed').length,
    cancelled_bookings: bookings.filter((b) => b.status === 'cancelled').length,
    realized_bookings: realized.length,
    realized_revenue: round(realized.reduce((s, b) => s + (Number(b.total_price) || 0), 0)),
    avg_booking_value: realized.length > 0
      ? Math.round(realized.reduce((s, b) => s + (Number(b.total_price) || 0), 0) / realized.length)
      : 0,
  };
}

/** Servisní záznamy v období s náklady a pobočkou motorky v den servisu. */
async function maintenanceInPeriod(admin: Admin, from: string, to: string, motoBranch: R) {
  const logs = await fetchAll(() => admin.from('maintenance_log')
    .select('id, moto_id, service_date, cost, invoiced_amount, is_test').gte('service_date', from).lte('service_date', to)
    .not('is_test', 'is', true).order('id'));
  const motoIds = [...new Set(logs.map((l) => l.moto_id).filter(Boolean))];
  const ev: Record<string, Array<{ t: number; from: string | null; to: string | null }>> = {};
  if (motoIds.length) {
    const [moves, anchors] = await Promise.all([
      fetchAll(() => admin.from('admin_audit_log').select('entity_id, created_at, old_data, new_data').eq('action', 'motorcycle_migrated').order('created_at').order('id')),
      fetchAll(() => admin.from('bookings').select('moto_id, branch_id, start_date, status, is_test').in('moto_id', motoIds).neq('status', 'cancelled').not('is_test', 'is', true).order('id')),
    ]);
    for (const a of moves) if (a.new_data && 'branch_id' in a.new_data && motoBranch[a.entity_id] !== undefined) (ev[a.entity_id] ||= []).push({ t: Date.parse(a.created_at), from: a.old_data?.branch_id ?? null, to: a.new_data.branch_id ?? null });
    for (const b of anchors) { const br = b.branch_id || motoBranch[b.moto_id] || null; (ev[b.moto_id] ||= []).push({ t: Date.parse(b.start_date), from: br, to: br }); }
    for (const k in ev) ev[k].sort((x, y) => x.t - y.t);
  }
  const branchAt = (motoId: string, date: string): string | null => {
    const list = ev[motoId] || [], t = Date.parse(date + 'T23:59:59Z');
    let prev = null, next = null;
    for (const e of list) { if (e.t <= t) prev = e; else { next = e; break; } }
    return prev ? prev.to : next ? next.from : (motoBranch[motoId] ?? null);
  };
  return logs.map((l) => ({
    moto_id: l.moto_id,
    cost: Number(l.invoiced_amount) > 0 ? Number(l.invoiced_amount) : (Number(l.cost) || 0),
    branch_id: l.moto_id ? branchAt(l.moto_id, l.service_date) : null,
  }));
}

/** P&L (Výsledovka). */
async function generatePL(admin: Admin, from: string, to: string, branchId?: string): Promise<R> {
  const ctx = await loadBranchCtx(admin);
  const base = await generatePeriodReport(admin, from, to, branchId, ctx);
  const logs = (await maintenanceInPeriod(admin, from, to, ctx.motoBranch)).filter((l) => !branchId || l.branch_id === branchId);
  const maintenanceCost = round(logs.reduce((s, l) => s + l.cost, 0));
  return { ...base, maintenance_cost: maintenanceCost, operating_profit: round(Number(base.profit) - maintenanceCost) };
}

/** ROI analýza motorek (tržby jen z rezervací pobočky, je-li zadaná). */
async function generateMotoROI(admin: Admin, from: string, to: string, branchId?: string): Promise<R[]> {
  const ctx = await loadBranchCtx(admin);
  const bookings = (await fetchAll(() => admin.from('bookings')
    .select('id, moto_id, branch_id, total_price, status, payment_status, is_test')
    .eq('status', 'completed').gte('start_date', from).lt('start_date', nextDay(to)).not('is_test', 'is', true).order('id')))
    .filter((b) => isRealized(b) && (!branchId || (b.branch_id || ctx.motoBranch[b.moto_id]) === branchId));
  const logs = (await maintenanceInPeriod(admin, from, to, ctx.motoBranch)).filter((l) => !branchId || l.branch_id === branchId);
  const rev: R = {}, cnt: R = {}, mc: R = {};
  for (const b of bookings) { rev[b.moto_id] = (rev[b.moto_id] ?? 0) + (Number(b.total_price) || 0); cnt[b.moto_id] = (cnt[b.moto_id] ?? 0) + 1; }
  for (const l of logs) if (l.moto_id) mc[l.moto_id] = (mc[l.moto_id] ?? 0) + l.cost;
  const motos = ctx.motos.filter((m) => !branchId || m.branch_id === branchId || rev[m.id] || mc[m.id]);
  return motos.map((moto) => {
    const revenue = round(rev[moto.id] ?? 0), maintenanceCost = round(mc[moto.id] ?? 0);
    const purchasePrice = Number(moto.purchase_price ?? 0);
    return {
      moto_id: moto.id, model: moto.model, spz: moto.spz, license_plate: moto.spz,
      purchase_price: purchasePrice, revenue, maintenance_cost: maintenanceCost, profit: round(revenue - maintenanceCost),
      roi_percent: purchasePrice > 0 ? Math.round(((revenue - maintenanceCost) / purchasePrice) * 100) : 0,
      bookings_count: cnt[moto.id] ?? 0,
    };
  }).sort((a, b) => b.roi_percent - a.roi_percent);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return corsResponse();

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return errorResponse('Missing Authorization header', 401);

    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return errorResponse('Unauthorized', 401);

    // Admin = admin_users.id je id uživatele (sloupce user_id / is_active tabulka nemá → dřív vždy 403)
    const admin = getAdminClient();
    const { data: adminUser } = await admin.from('admin_users').select('id, role, active').eq('id', user.id).maybeSingle();
    if (!adminUser || adminUser.active === false) return errorResponse('Admin access required', 403);
    if (!['superadmin', 'manager'].includes(String(adminUser.role))) return errorResponse('Manager or superadmin role required', 403);

    const body = await req.json() as ReportRequest;
    if (!body.type || !body.period_from || !body.period_to) {
      return errorResponse('Missing required fields: type, period_from, period_to');
    }
    if (!DATE.test(body.period_from) || !DATE.test(body.period_to)) return errorResponse('period_from/period_to: YYYY-MM-DD');
    if (body.branch_id && !UUID.test(body.branch_id)) return errorResponse('Neplatné branch_id');

    const validTypes: ReportType[] = ['monthly', 'annual', 'pl', 'balance_sheet', 'cashflow', 'moto_roi'];
    if (!validTypes.includes(body.type)) return errorResponse(`Invalid type. Valid types: ${validTypes.join(', ')}`);

    const { period_from: from, period_to: to, branch_id: branchId } = body;
    let summary: R, details: unknown[] = [];
    if (body.type === 'monthly' || body.type === 'annual') summary = await generatePeriodReport(admin, from, to, branchId);
    else if (body.type === 'moto_roi') {
      const rows = await generateMotoROI(admin, from, to, branchId);
      details = rows;
      const totalRevenue = rows.reduce((s, d) => s + d.revenue, 0), totalCost = rows.reduce((s, d) => s + d.maintenance_cost, 0);
      summary = { total_motos: rows.length, total_revenue: round(totalRevenue), total_maintenance_cost: round(totalCost), total_profit: round(totalRevenue - totalCost) };
    } else summary = await generatePL(admin, from, to, branchId);

    return jsonResponse({
      success: true,
      data: { type: body.type, period: { from, to }, branch_id: branchId, summary, details, generated_at: new Date().toISOString() },
    });
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('generate-report error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
