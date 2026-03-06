/**
 * MotoGo24 — Edge Function: Cron Monthly
 * Měsíční automatizované úlohy — spouští se 1. den v měsíci v 8:00.
 *
 * POST /functions/v1/cron-monthly
 * Auth: SERVICE_ROLE_KEY
 *
 * Úlohy:
 * 1. Měsíční výkonnostní report (motorky + pobočky)
 * 2. Aktualizace predikcí na 3 měsíce dopředu
 * 3. Logování
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import type { CronResult } from '../_shared/types.ts';

/** Ověří SERVICE_ROLE_KEY. */
function verifyServiceRole(authHeader: string | null): boolean {
  if (!authHeader) return false;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return authHeader === `Bearer ${serviceRoleKey}`;
}

interface TaskResult {
  name: string;
  status: 'ok' | 'error';
  detail?: string;
}

/** 1. Měsíční výkonnostní report — motorky a pobočky za předchozí měsíc. */
async function generateMonthlyPerformance(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const now = new Date();
    const firstDayLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const lastDayLastMonth = new Date(now.getFullYear(), now.getMonth(), 0);
    const periodFrom = firstDayLastMonth.toISOString().split('T')[0];
    const periodTo = lastDayLastMonth.toISOString().split('T')[0];
    const periodLabel = `${firstDayLastMonth.getFullYear()}-${String(firstDayLastMonth.getMonth() + 1).padStart(2, '0')}`;

    // Výkonnost motorek
    const { data: motos } = await admin
      .from('motorcycles')
      .select('id, model, license_plate, branch_id');

    const motoPerformance = [];
    for (const moto of motos ?? []) {
      const { data: bookings } = await admin
        .from('bookings')
        .select('total_price, start_date, end_date, status')
        .eq('moto_id', moto.id)
        .gte('start_date', periodFrom)
        .lte('start_date', periodTo);

      const completedBookings = (bookings ?? []).filter((b) => b.status === 'completed');
      const revenue = completedBookings.reduce((s, b) => s + Number(b.total_price ?? 0), 0);

      // Počet dnů pronájmu
      const rentalDays = completedBookings.reduce((s, b) => {
        const start = new Date(b.start_date as string);
        const end = new Date(b.end_date as string);
        return s + Math.ceil((end.getTime() - start.getTime()) / 86400_000);
      }, 0);

      const daysInMonth = lastDayLastMonth.getDate();
      const utilizationPercent = Math.round((rentalDays / daysInMonth) * 100);

      motoPerformance.push({
        moto_id: moto.id,
        model: moto.model,
        license_plate: moto.license_plate,
        branch_id: moto.branch_id,
        total_bookings: bookings?.length ?? 0,
        completed_bookings: completedBookings.length,
        revenue,
        rental_days: rentalDays,
        utilization_percent: utilizationPercent,
      });
    }

    // Uložení výkonnosti motorek
    for (const perf of motoPerformance) {
      await admin.from('moto_performance').upsert(
        {
          moto_id: perf.moto_id as string,
          period: periodLabel,
          total_bookings: perf.total_bookings,
          completed_bookings: perf.completed_bookings,
          revenue: perf.revenue,
          rental_days: perf.rental_days,
          utilization_percent: perf.utilization_percent,
        },
        { onConflict: 'moto_id,period' },
      );
    }

    // Výkonnost poboček
    const { data: branches } = await admin
      .from('branches')
      .select('id, name');

    for (const branch of branches ?? []) {
      const branchMotos = motoPerformance.filter(
        (m) => m.branch_id === branch.id,
      );
      const branchRevenue = branchMotos.reduce((s, m) => s + m.revenue, 0);
      const branchBookings = branchMotos.reduce((s, m) => s + m.completed_bookings, 0);
      const avgUtilization = branchMotos.length > 0
        ? Math.round(branchMotos.reduce((s, m) => s + m.utilization_percent, 0) / branchMotos.length)
        : 0;

      // Výdaje pobočky
      const { data: expenses } = await admin
        .from('accounting_entries')
        .select('amount')
        .eq('type', 'expense')
        .eq('branch_id', branch.id)
        .gte('date', periodFrom)
        .lte('date', periodTo);

      const totalExpenses = expenses?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;

      await admin.from('branch_performance').upsert(
        {
          branch_id: branch.id as string,
          period: periodLabel,
          revenue: branchRevenue,
          expenses: totalExpenses,
          profit: branchRevenue - totalExpenses,
          total_bookings: branchBookings,
          avg_utilization: avgUtilization,
          moto_count: branchMotos.length,
        },
        { onConflict: 'branch_id,period' },
      );
    }

    return {
      name: 'monthly_performance',
      status: 'ok',
      detail: `${motoPerformance.length} motorek, ${branches?.length ?? 0} poboček za ${periodLabel}`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Monthly performance error:', msg);
    return { name: 'monthly_performance', status: 'error', detail: msg };
  }
}

/** 2. Aktualizace predikcí — spustí prediction-engine pro 3 měsíce. */
async function updatePredictions(): Promise<TaskResult> {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    const predictionTypes = ['demand', 'revenue', 'maintenance', 'stock'] as const;

    for (const type of predictionTypes) {
      const resp = await fetch(`${supabaseUrl}/functions/v1/prediction-engine`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceRoleKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ type, period_months: 3 }),
      });

      if (!resp.ok) {
        const errBody = await resp.text();
        console.error(`Prediction ${type} failed:`, errBody);
      }
    }

    return {
      name: 'prediction_update',
      status: 'ok',
      detail: `${predictionTypes.length} typů predikcí aktualizováno pro 3 měsíce`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Prediction update error:', msg);
    return { name: 'prediction_update', status: 'error', detail: msg };
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!verifyServiceRole(authHeader)) {
      return errorResponse('Service role key required', 401);
    }

    const admin = getAdminClient();
    const tasks: TaskResult[] = [];

    console.log('=== CRON MONTHLY START ===', new Date().toISOString());

    tasks.push(await generateMonthlyPerformance(admin));
    tasks.push(await updatePredictions());

    const hasErrors = tasks.some((t) => t.status === 'error');

    // Loguj výsledek
    await admin.from('notification_log').insert({
      type: 'system',
      template: 'cron_monthly',
      recipient: 'system',
      status: hasErrors ? 'partial' : 'sent',
      metadata: { tasks, executed_at: new Date().toISOString() },
    });

    console.log('=== CRON MONTHLY END ===', tasks);

    const response: CronResult = {
      success: true,
      tasks,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('cron-monthly error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
