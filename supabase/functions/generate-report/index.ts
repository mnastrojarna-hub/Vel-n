/**
 * MotoGo24 — Edge Function: Generate Report
 * Generování finančních a provozních reportů.
 *
 * POST /functions/v1/generate-report
 * Auth: Bearer JWT (admin, min. manager)
 * Body: { type, period_from, period_to, branch_id?, format? }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { ReportRequest, ReportResponse, ReportType } from '../_shared/types.ts';

interface ReportData {
  type: ReportType;
  period: { from: string; to: string };
  branch_id?: string;
  summary: Record<string, unknown>;
  details: unknown[];
  generated_at: string;
}

/** Generuje měsíční / roční report. */
async function generatePeriodReport(
  admin: ReturnType<typeof getAdminClient>,
  periodFrom: string,
  periodTo: string,
  branchId?: string,
): Promise<ReportData['summary']> {
  // Příjmy
  let incomeQuery = admin
    .from('accounting_entries')
    .select('amount, category, date')
    .eq('type', 'income')
    .gte('date', periodFrom)
    .lte('date', periodTo);
  if (branchId) incomeQuery = incomeQuery.eq('branch_id', branchId);
  const { data: income } = await incomeQuery;

  // Výdaje
  let expenseQuery = admin
    .from('accounting_entries')
    .select('amount, category, date')
    .eq('type', 'expense')
    .gte('date', periodFrom)
    .lte('date', periodTo);
  if (branchId) expenseQuery = expenseQuery.eq('branch_id', branchId);
  const { data: expenses } = await expenseQuery;

  // Rezervace
  let bookingQuery = admin
    .from('bookings')
    .select('id, status, total_price, start_date')
    .gte('start_date', periodFrom)
    .lte('start_date', periodTo);
  if (branchId) {
    bookingQuery = bookingQuery.eq('motorcycles.branch_id', branchId);
  }
  const { data: bookings } = await bookingQuery;

  const totalIncome = income?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;
  const totalExpense = expenses?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;

  // Kategorizace příjmů
  const incomeByCategory: Record<string, number> = {};
  for (const entry of income ?? []) {
    const cat = entry.category as string;
    incomeByCategory[cat] = (incomeByCategory[cat] ?? 0) + Number(entry.amount);
  }

  // Kategorizace výdajů
  const expenseByCategory: Record<string, number> = {};
  for (const entry of expenses ?? []) {
    const cat = entry.category as string;
    expenseByCategory[cat] = (expenseByCategory[cat] ?? 0) + Number(entry.amount);
  }

  return {
    total_income: totalIncome,
    total_expense: totalExpense,
    profit: totalIncome - totalExpense,
    margin_percent: totalIncome > 0 ? Math.round(((totalIncome - totalExpense) / totalIncome) * 100) : 0,
    income_by_category: incomeByCategory,
    expense_by_category: expenseByCategory,
    total_bookings: bookings?.length ?? 0,
    completed_bookings: bookings?.filter((b) => b.status === 'completed').length ?? 0,
    cancelled_bookings: bookings?.filter((b) => b.status === 'cancelled').length ?? 0,
    avg_booking_value: bookings && bookings.length > 0
      ? Math.round(bookings.reduce((s, b) => s + Number(b.total_price ?? 0), 0) / bookings.length)
      : 0,
  };
}

/** Generuje P&L (Výsledovka). */
async function generatePL(
  admin: ReturnType<typeof getAdminClient>,
  periodFrom: string,
  periodTo: string,
  branchId?: string,
): Promise<ReportData['summary']> {
  const base = await generatePeriodReport(admin, periodFrom, periodTo, branchId);

  // Servisní náklady
  let maintenanceQuery = admin
    .from('maintenance_log')
    .select('cost')
    .gte('date', periodFrom)
    .lte('date', periodTo);
  if (branchId) maintenanceQuery = maintenanceQuery.eq('branch_id', branchId);
  const { data: maintenance } = await maintenanceQuery;

  const maintenanceCost = maintenance?.reduce((s, m) => s + Number(m.cost ?? 0), 0) ?? 0;

  return {
    ...base,
    maintenance_cost: maintenanceCost,
    operating_profit: Number(base.profit) - maintenanceCost,
  };
}

/** Generuje ROI analýzu motorek. */
async function generateMotoROI(
  admin: ReturnType<typeof getAdminClient>,
  periodFrom: string,
  periodTo: string,
  branchId?: string,
): Promise<unknown[]> {
  let motoQuery = admin
    .from('motorcycles')
    .select('id, model, license_plate, purchase_price, status, branch_id');
  if (branchId) motoQuery = motoQuery.eq('branch_id', branchId);
  const { data: motos } = await motoQuery;

  const results = [];
  for (const moto of motos ?? []) {
    // Tržby z motorky
    const { data: bookings } = await admin
      .from('bookings')
      .select('total_price')
      .eq('moto_id', moto.id)
      .eq('status', 'completed')
      .gte('start_date', periodFrom)
      .lte('start_date', periodTo);

    const revenue = bookings?.reduce((s, b) => s + Number(b.total_price ?? 0), 0) ?? 0;

    // Náklady servisu
    const { data: maintenanceLogs } = await admin
      .from('maintenance_log')
      .select('cost')
      .eq('moto_id', moto.id)
      .gte('date', periodFrom)
      .lte('date', periodTo);

    const maintenanceCost = maintenanceLogs?.reduce((s, m) => s + Number(m.cost ?? 0), 0) ?? 0;
    const purchasePrice = Number(moto.purchase_price ?? 0);

    results.push({
      moto_id: moto.id,
      model: moto.model,
      license_plate: moto.license_plate,
      purchase_price: purchasePrice,
      revenue,
      maintenance_cost: maintenanceCost,
      profit: revenue - maintenanceCost,
      roi_percent: purchasePrice > 0
        ? Math.round(((revenue - maintenanceCost) / purchasePrice) * 100)
        : 0,
      bookings_count: bookings?.length ?? 0,
    });
  }

  return results.sort((a, b) => b.roi_percent - a.roi_percent);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }

    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    // Ověř admin roli (min. manager)
    const admin = getAdminClient();
    const { data: adminUser, error: adminError } = await admin
      .from('admin_users')
      .select('id, role')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single();

    if (adminError || !adminUser) {
      return errorResponse('Admin access required', 403);
    }

    const role = adminUser.role as string;
    if (!['superadmin', 'manager'].includes(role)) {
      return errorResponse('Manager or superadmin role required', 403);
    }

    const body = await req.json() as ReportRequest;
    if (!body.type || !body.period_from || !body.period_to) {
      return errorResponse('Missing required fields: type, period_from, period_to');
    }

    const validTypes: ReportType[] = ['monthly', 'annual', 'pl', 'balance_sheet', 'cashflow', 'moto_roi'];
    if (!validTypes.includes(body.type)) {
      return errorResponse(`Invalid type. Valid types: ${validTypes.join(', ')}`);
    }

    let reportData: ReportData;

    switch (body.type) {
      case 'monthly':
      case 'annual': {
        const summary = await generatePeriodReport(admin, body.period_from, body.period_to, body.branch_id);
        reportData = {
          type: body.type,
          period: { from: body.period_from, to: body.period_to },
          branch_id: body.branch_id,
          summary,
          details: [],
          generated_at: new Date().toISOString(),
        };
        break;
      }

      case 'pl':
      case 'balance_sheet':
      case 'cashflow': {
        const summary = await generatePL(admin, body.period_from, body.period_to, body.branch_id);
        reportData = {
          type: body.type,
          period: { from: body.period_from, to: body.period_to },
          branch_id: body.branch_id,
          summary,
          details: [],
          generated_at: new Date().toISOString(),
        };
        break;
      }

      case 'moto_roi': {
        const details = await generateMotoROI(admin, body.period_from, body.period_to, body.branch_id);
        const totalRevenue = details.reduce((s, d) => s + (d as { revenue: number }).revenue, 0);
        const totalCost = details.reduce((s, d) => s + (d as { maintenance_cost: number }).maintenance_cost, 0);
        reportData = {
          type: body.type,
          period: { from: body.period_from, to: body.period_to },
          branch_id: body.branch_id,
          summary: {
            total_motos: details.length,
            total_revenue: totalRevenue,
            total_maintenance_cost: totalCost,
            total_profit: totalRevenue - totalCost,
          },
          details,
          generated_at: new Date().toISOString(),
        };
        break;
      }
    }

    const response: ReportResponse = {
      success: true,
      data: reportData as unknown as Record<string, unknown>,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('generate-report error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
