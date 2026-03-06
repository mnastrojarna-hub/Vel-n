/**
 * MotoGo24 — Edge Function: Prediction Engine
 * Predikce poptávky, tržeb, servisu a zásob na základě historických dat.
 * Model: průměr posledních 12 měsíců * sezónní koeficient * trend.
 *
 * POST /functions/v1/prediction-engine
 * Auth: Bearer JWT (admin)
 * Body: { type, period_months, branch_id? }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { PredictionRequest, PredictionResponse, PredictionType } from '../_shared/types.ts';

/** Sezónní koeficienty pro ČR (motocykly — peak sezóna květen–září). */
const SEASONAL_COEFFICIENTS: Record<number, number> = {
  1: 0.15,  // leden
  2: 0.20,  // únor
  3: 0.35,  // březen
  4: 0.60,  // duben
  5: 1.00,  // květen
  6: 1.30,  // červen
  7: 1.50,  // červenec
  8: 1.45,  // srpen
  9: 1.10,  // září
  10: 0.55, // říjen
  11: 0.25, // listopad
  12: 0.15, // prosinec
};

interface MonthlyData {
  month: string; // YYYY-MM
  value: number;
}

/** Načte měsíční historická data dle typu predikce. */
async function loadHistoricalData(
  admin: ReturnType<typeof getAdminClient>,
  type: PredictionType,
  branchId?: string,
): Promise<MonthlyData[]> {
  const twelveMonthsAgo = new Date();
  twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12);
  const fromDate = twelveMonthsAgo.toISOString().split('T')[0];

  switch (type) {
    case 'demand': {
      let query = admin
        .from('bookings')
        .select('id, start_date')
        .gte('start_date', fromDate);
      if (branchId) {
        query = query.eq('motorcycles.branch_id', branchId);
      }
      const { data: bookings } = await query;

      const monthly: Record<string, number> = {};
      for (const b of bookings ?? []) {
        const month = (b.start_date as string).substring(0, 7);
        monthly[month] = (monthly[month] ?? 0) + 1;
      }

      return Object.entries(monthly)
        .map(([month, value]) => ({ month, value }))
        .sort((a, b) => a.month.localeCompare(b.month));
    }

    case 'revenue': {
      let query = admin
        .from('accounting_entries')
        .select('amount, date')
        .eq('type', 'income')
        .gte('date', fromDate);
      if (branchId) query = query.eq('branch_id', branchId);
      const { data: entries } = await query;

      const monthly: Record<string, number> = {};
      for (const e of entries ?? []) {
        const month = (e.date as string).substring(0, 7);
        monthly[month] = (monthly[month] ?? 0) + Number(e.amount);
      }

      return Object.entries(monthly)
        .map(([month, value]) => ({ month, value }))
        .sort((a, b) => a.month.localeCompare(b.month));
    }

    case 'maintenance': {
      let query = admin
        .from('maintenance_log')
        .select('cost, date')
        .gte('date', fromDate);
      if (branchId) query = query.eq('branch_id', branchId);
      const { data: logs } = await query;

      const monthly: Record<string, number> = {};
      for (const l of logs ?? []) {
        const month = (l.date as string).substring(0, 7);
        monthly[month] = (monthly[month] ?? 0) + Number(l.cost ?? 0);
      }

      return Object.entries(monthly)
        .map(([month, value]) => ({ month, value }))
        .sort((a, b) => a.month.localeCompare(b.month));
    }

    case 'stock': {
      let query = admin
        .from('inventory')
        .select('stock, min_stock, unit_price');
      if (branchId) query = query.eq('branch_id', branchId);
      const { data: items } = await query;

      // Pro stock predikce — aktuální stav jako baseline
      const totalValue = (items ?? []).reduce(
        (s, i) => s + Number(i.stock ?? 0) * Number(i.unit_price ?? 0),
        0,
      );
      const now = new Date();
      return [{ month: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`, value: totalValue }];
    }
  }
}

/** Vypočítá trend (lineární regrese). */
function calculateTrend(data: MonthlyData[]): number {
  if (data.length < 2) return 1.0;

  const n = data.length;
  const xMean = (n - 1) / 2;
  const yMean = data.reduce((s, d) => s + d.value, 0) / n;

  let numerator = 0;
  let denominator = 0;
  for (let i = 0; i < n; i++) {
    numerator += (i - xMean) * (data[i].value - yMean);
    denominator += (i - xMean) ** 2;
  }

  if (denominator === 0 || yMean === 0) return 1.0;

  const slope = numerator / denominator;
  // Trend jako procentuální změna za měsíc
  const trendPerMonth = slope / yMean;

  // Omez trend na rozumné hodnoty (-30% až +30% za měsíc)
  return Math.max(0.7, Math.min(1.3, 1 + trendPerMonth));
}

/** Generuje predikce na N měsíců dopředu. */
function generatePredictions(
  historicalData: MonthlyData[],
  periodMonths: number,
): Array<{ month: string; value: number; confidence: number }> {
  if (historicalData.length === 0) {
    return [];
  }

  // Průměr posledních 12 měsíců
  const avgValue =
    historicalData.reduce((s, d) => s + d.value, 0) / historicalData.length;

  // Trend
  const trend = calculateTrend(historicalData);

  const predictions = [];
  const now = new Date();

  for (let i = 1; i <= periodMonths; i++) {
    const futureDate = new Date(now);
    futureDate.setMonth(futureDate.getMonth() + i);
    const month = futureDate.getMonth() + 1;
    const yearMonth = `${futureDate.getFullYear()}-${String(month).padStart(2, '0')}`;

    const seasonalCoeff = SEASONAL_COEFFICIENTS[month] ?? 1.0;
    const trendCoeff = Math.pow(trend, i);
    const predictedValue = Math.round(avgValue * seasonalCoeff * trendCoeff);

    // Confidence klesá s vzdáleností od současnosti
    const confidence = Math.max(0.3, 1.0 - i * 0.08);

    predictions.push({
      month: yearMonth,
      value: Math.max(0, predictedValue),
      confidence: Math.round(confidence * 100) / 100,
    });
  }

  return predictions;
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

    const body = await req.json() as PredictionRequest;
    if (!body.type || !body.period_months) {
      return errorResponse('Missing required fields: type, period_months');
    }

    const validTypes: PredictionType[] = ['demand', 'revenue', 'maintenance', 'stock'];
    if (!validTypes.includes(body.type)) {
      return errorResponse(`Invalid type. Valid: ${validTypes.join(', ')}`);
    }

    if (body.period_months < 1 || body.period_months > 24) {
      return errorResponse('period_months must be between 1 and 24');
    }

    // Načti historická data
    const historicalData = await loadHistoricalData(admin, body.type, body.branch_id);

    // Generuj predikce
    const predictions = generatePredictions(historicalData, body.period_months);

    // Ulož predikce do DB
    for (const pred of predictions) {
      await admin.from('predictions').upsert(
        {
          type: body.type,
          month: pred.month,
          value: pred.value,
          confidence: pred.confidence,
          branch_id: body.branch_id ?? null,
          generated_at: new Date().toISOString(),
        },
        { onConflict: 'type,month,branch_id' },
      );
    }

    const response: PredictionResponse = {
      success: true,
      predictions,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('prediction-engine error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
