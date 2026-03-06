/**
 * MotoGo24 — Edge Function: Cron Daily
 * Denní automatizované úlohy — spouští se v 6:00 přes pg_cron.
 *
 * POST /functions/v1/cron-daily
 * Auth: SERVICE_ROLE_KEY
 *
 * Úlohy:
 * 1. Servisní alerty (motorky blízko servisu)
 * 2. Inventory check (zásoby pod minimem)
 * 3. Daily stats snapshot
 * 4. Booking reminders (připomínky zítra)
 * 5. Overdue invoices (po splatnosti)
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

/** 1. Servisní alerty — motorky s next_service_date < NOW() + 14 dní. */
async function checkServiceAlerts(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const fourteenDaysFromNow = new Date();
    fourteenDaysFromNow.setDate(fourteenDaysFromNow.getDate() + 14);
    const cutoffDate = fourteenDaysFromNow.toISOString().split('T')[0];

    const { data: motos, error } = await admin
      .from('motorcycles')
      .select('id, model, license_plate, next_service_date, status')
      .eq('status', 'active')
      .lte('next_service_date', cutoffDate)
      .order('next_service_date');

    if (error) throw error;

    for (const moto of motos ?? []) {
      // Zkontroluj jestli alert pro tuto motorku neexistuje
      const { data: existingAlert } = await admin
        .from('notification_log')
        .select('id')
        .eq('template', 'service_alert')
        .eq('metadata->>moto_id', moto.id as string)
        .eq('status', 'pending')
        .maybeSingle();

      if (existingAlert) continue;

      await admin.from('notification_log').insert({
        type: 'system',
        template: 'service_alert',
        recipient: Deno.env.get('ADMIN_EMAIL') ?? '',
        status: 'pending',
        metadata: {
          moto_id: moto.id,
          model: moto.model,
          license_plate: moto.license_plate,
          next_service_date: moto.next_service_date,
        },
      });
    }

    return {
      name: 'service_alerts',
      status: 'ok',
      detail: `${motos?.length ?? 0} motorek blízko servisu`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Service alerts error:', msg);
    return { name: 'service_alerts', status: 'error', detail: msg };
  }
}

/** 2. Inventory check — zavolá inventory-check endpoint interně. */
async function runInventoryCheck(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    const resp = await fetch(`${supabaseUrl}/functions/v1/inventory-check`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({}),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      throw new Error(`Inventory check failed: ${errBody}`);
    }

    const result = await resp.json() as { items_below_min: number; orders_created: number };
    return {
      name: 'inventory_check',
      status: 'ok',
      detail: `${result.items_below_min} položek pod minimem, ${result.orders_created} objednávek vytvořeno`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Inventory check error:', msg);
    return { name: 'inventory_check', status: 'error', detail: msg };
  }
}

/** 3. Daily stats snapshot — zavolá SQL funkci snapshot_daily_stats(). */
async function runDailyStatsSnapshot(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const { error } = await admin.rpc('snapshot_daily_stats');
    if (error) throw error;

    return { name: 'daily_stats_snapshot', status: 'ok' };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Daily stats snapshot error:', msg);
    return { name: 'daily_stats_snapshot', status: 'error', detail: msg };
  }
}

/** 4. Booking reminders — rezervace kde start_date = ZÍTRA. */
async function sendBookingReminders(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const tomorrowStr = tomorrow.toISOString().split('T')[0];

    const { data: bookings, error } = await admin
      .from('bookings')
      .select(`
        id, start_date,
        profiles!inner ( full_name, email ),
        motorcycles!inner ( model, license_plate,
          branches!inner ( name, address )
        )
      `)
      .eq('start_date', tomorrowStr)
      .in('status', ['pending', 'active']);

    if (error) throw error;

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    let sentCount = 0;

    for (const booking of bookings ?? []) {
      const profile = booking.profiles as unknown as { full_name: string; email: string };
      const moto = booking.motorcycles as unknown as {
        model: string;
        license_plate: string;
        branches: { name: string; address: string };
      };

      try {
        await fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${serviceRoleKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'booking_reminder',
            recipient_email: profile.email,
            data: {
              customer_name: profile.full_name,
              moto_model: moto.model,
              start_date: tomorrowStr,
              start_time: '09:00',
              branch_name: moto.branches.name,
              branch_address: moto.branches.address,
              booking_id: (booking.id as string).substring(0, 8).toUpperCase(),
            },
          }),
        });
        sentCount++;
      } catch (emailErr: unknown) {
        const msg = emailErr instanceof Error ? emailErr.message : String(emailErr);
        console.error(`Reminder email failed for booking ${booking.id}:`, msg);
      }
    }

    return {
      name: 'booking_reminders',
      status: 'ok',
      detail: `${sentCount}/${bookings?.length ?? 0} připomínek odesláno`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Booking reminders error:', msg);
    return { name: 'booking_reminders', status: 'error', detail: msg };
  }
}

/** 5. Overdue invoices — faktury po splatnosti. */
async function checkOverdueInvoices(
  admin: ReturnType<typeof getAdminClient>,
): Promise<TaskResult> {
  try {
    const today = new Date().toISOString().split('T')[0];

    const { data: overdue, error } = await admin
      .from('invoices')
      .select('id')
      .eq('status', 'issued')
      .lt('due_date', today);

    if (error) throw error;

    if (overdue && overdue.length > 0) {
      const ids = overdue.map((i) => i.id as string);
      const { error: updateError } = await admin
        .from('invoices')
        .update({ status: 'overdue' })
        .in('id', ids);

      if (updateError) throw updateError;
    }

    return {
      name: 'overdue_invoices',
      status: 'ok',
      detail: `${overdue?.length ?? 0} faktur označeno jako po splatnosti`,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Overdue invoices error:', msg);
    return { name: 'overdue_invoices', status: 'error', detail: msg };
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

    console.log('=== CRON DAILY START ===', new Date().toISOString());

    // Spusť všechny úlohy sekvenčně (abychom nepřetížili DB)
    tasks.push(await checkServiceAlerts(admin));
    tasks.push(await runInventoryCheck(admin));
    tasks.push(await runDailyStatsSnapshot(admin));
    tasks.push(await sendBookingReminders(admin));
    tasks.push(await checkOverdueInvoices(admin));

    const hasErrors = tasks.some((t) => t.status === 'error');

    // Loguj výsledek
    await admin.from('notification_log').insert({
      type: 'system',
      template: 'cron_daily',
      recipient: 'system',
      status: hasErrors ? 'partial' : 'sent',
      metadata: { tasks, executed_at: new Date().toISOString() },
    });

    console.log('=== CRON DAILY END ===', tasks);

    const response: CronResult = {
      success: true,
      tasks,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('cron-daily error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
