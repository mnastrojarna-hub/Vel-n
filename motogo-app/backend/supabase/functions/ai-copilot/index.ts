/**
 * MotoGo24 — Edge Function: AI Copilot
 * AI asistent pro admin dashboard (Claude API).
 * Sbírá kontext z DB dle stránky, sestaví prompt a vrátí odpověď.
 *
 * POST /functions/v1/ai-copilot
 * Auth: Bearer JWT (admin)
 * Body: { message, conversation_id?, context_page? }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { AiCopilotRequest, AiCopilotResponse, AiAction, AiContextPage } from '../_shared/types.ts';

// ─── Rate Limiting (in-memory, per-instance) ──────────
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 60;
const RATE_LIMIT_WINDOW_MS = 60_000;

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(userId);

  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(userId, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }

  if (entry.count >= RATE_LIMIT_MAX) {
    return false;
  }

  entry.count++;
  return true;
}

/** Načte kontextová data z DB dle stránky. */
async function loadContext(
  admin: ReturnType<typeof getAdminClient>,
  page: AiContextPage,
  branchId?: string,
): Promise<string> {
  const parts: string[] = [];
  const today = new Date().toISOString().split('T')[0];
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400_000).toISOString().split('T')[0];

  switch (page) {
    case 'dashboard': {
      // Aktivní rezervace
      const { data: activeBookings } = await admin
        .from('bookings')
        .select('id, status, payment_status')
        .in('status', ['pending', 'active'])
        .limit(100);
      parts.push(`Aktivní rezervace: ${activeBookings?.length ?? 0}`);

      // Tržby za posledních 30 dní
      const { data: revenue } = await admin
        .from('accounting_entries')
        .select('amount')
        .eq('type', 'income')
        .gte('date', thirtyDaysAgo);
      const totalRevenue = revenue?.reduce((sum, e) => sum + Number(e.amount), 0) ?? 0;
      parts.push(`Tržby (30 dní): ${totalRevenue.toLocaleString('cs-CZ')} Kč`);

      // SOS incidenty
      const { data: sosActive } = await admin
        .from('sos_incidents')
        .select('id, type, status')
        .in('status', ['reported', 'acknowledged', 'in_progress']);
      parts.push(`Aktivní SOS: ${sosActive?.length ?? 0}`);

      // Alerty
      const { data: alerts } = await admin
        .from('notification_log')
        .select('id, type, status')
        .eq('status', 'pending')
        .limit(10);
      parts.push(`Čekající notifikace: ${alerts?.length ?? 0}`);
      break;
    }

    case 'fleet': {
      const { data: motos } = await admin
        .from('motorcycles')
        .select('id, model, status, next_service_date, branch_id');
      const active = motos?.filter((m) => m.status === 'active').length ?? 0;
      const maintenance = motos?.filter((m) => m.status === 'maintenance').length ?? 0;
      const needsService = motos?.filter(
        (m) => m.next_service_date && m.next_service_date <= today,
      ).length ?? 0;
      parts.push(`Flotila: ${motos?.length ?? 0} motocyklů (${active} aktivních, ${maintenance} v servisu)`);
      parts.push(`Potřebuje servis: ${needsService}`);
      if (motos) {
        parts.push(`Modely: ${[...new Set(motos.map((m) => m.model))].join(', ')}`);
      }
      break;
    }

    case 'finance': {
      const { data: income } = await admin
        .from('accounting_entries')
        .select('amount')
        .eq('type', 'income')
        .gte('date', thirtyDaysAgo);
      const { data: expense } = await admin
        .from('accounting_entries')
        .select('amount')
        .eq('type', 'expense')
        .gte('date', thirtyDaysAgo);

      const totalIncome = income?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;
      const totalExpense = expense?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;
      parts.push(`Příjmy (30 dní): ${totalIncome.toLocaleString('cs-CZ')} Kč`);
      parts.push(`Výdaje (30 dní): ${totalExpense.toLocaleString('cs-CZ')} Kč`);
      parts.push(`Cashflow: ${(totalIncome - totalExpense).toLocaleString('cs-CZ')} Kč`);

      const { data: overdueInvoices } = await admin
        .from('invoices')
        .select('id')
        .eq('status', 'overdue');
      parts.push(`Faktury po splatnosti: ${overdueInvoices?.length ?? 0}`);
      break;
    }

    case 'bookings': {
      const { data: recentBookings } = await admin
        .from('bookings')
        .select('id, status, payment_status, start_date, end_date, total_price')
        .order('created_at', { ascending: false })
        .limit(50);

      const statusCounts: Record<string, number> = {};
      for (const b of recentBookings ?? []) {
        const s = b.status as string;
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
      }
      parts.push(`Posledních 50 rezervací: ${JSON.stringify(statusCounts)}`);

      const avgPrice =
        (recentBookings ?? []).reduce((s, b) => s + Number(b.total_price ?? 0), 0) /
        Math.max(recentBookings?.length ?? 1, 1);
      parts.push(`Průměrná cena: ${Math.round(avgPrice).toLocaleString('cs-CZ')} Kč`);
      break;
    }

    case 'inventory': {
      const { data: lowStock } = await admin
        .from('inventory')
        .select('name, stock, min_stock')
        .filter('stock', 'lte', 'min_stock');
      parts.push(`Položky pod minimem: ${lowStock?.length ?? 0}`);
      if (lowStock && lowStock.length > 0) {
        parts.push(
          `Detaily: ${lowStock.map((i) => `${i.name}: ${i.stock}/${i.min_stock}`).join(', ')}`,
        );
      }
      break;
    }

    case 'sos': {
      const { data: incidents } = await admin
        .from('sos_incidents')
        .select('id, type, status, created_at')
        .order('created_at', { ascending: false })
        .limit(20);
      parts.push(`Posledních 20 incidentů:`);
      for (const inc of incidents ?? []) {
        parts.push(`  - ${inc.type} (${inc.status}) — ${inc.created_at}`);
      }
      break;
    }

    case 'customers': {
      const { data: profiles } = await admin
        .from('profiles')
        .select('id')
        .limit(1000);
      parts.push(`Celkem zákazníků: ${profiles?.length ?? 0}`);
      break;
    }

    case 'reports': {
      const { data: stats } = await admin
        .from('daily_stats')
        .select('*')
        .order('date', { ascending: false })
        .limit(30);
      if (stats && stats.length > 0) {
        parts.push(`Denní statistiky (posledních ${stats.length} dní) k dispozici.`);
      }
      break;
    }
  }

  return parts.join('\n');
}

/** Parsuje akce z AI odpovědi (hledá JSON bloky). */
function parseActions(response: string): AiAction[] {
  const actions: AiAction[] = [];
  const actionRegex = /\[ACTION:(\w+)\]\s*\{([^}]+)\}/g;
  let match: RegExpExecArray | null;

  while ((match = actionRegex.exec(response)) !== null) {
    try {
      const payload = JSON.parse(`{${match[2]}}`);
      actions.push({
        type: match[1],
        entity_type: payload.entity_type ?? 'unknown',
        entity_id: payload.entity_id,
        payload,
      });
    } catch {
      // Ignoruj nevalidní JSON v akci
    }
  }

  return actions;
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

    // Ověř JWT
    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    // Rate limiting
    if (!checkRateLimit(user.id)) {
      return errorResponse('Rate limit exceeded. Max 60 requests per minute.', 429);
    }

    // Ověř admin roli
    const adminClient = getAdminClient();
    const { data: adminUser, error: adminError } = await adminClient
      .from('admin_users')
      .select('id, role, branch_access')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single();

    if (adminError || !adminUser) {
      return errorResponse('Admin access required', 403);
    }

    const body = await req.json() as AiCopilotRequest;
    if (!body.message) {
      return errorResponse('Missing message');
    }

    // Načti kontext z DB
    const contextPage = body.context_page ?? 'dashboard';
    const branchAccess = adminUser.branch_access as string[] | null;
    const contextData = await loadContext(
      adminClient,
      contextPage,
      branchAccess?.[0],
    );

    // Načti historii konverzace (pokud existuje)
    let conversationHistory = '';
    if (body.conversation_id) {
      const { data: prevMessages } = await adminClient
        .from('ai_conversations')
        .select('role, content')
        .eq('conversation_id', body.conversation_id)
        .order('created_at', { ascending: true })
        .limit(20);

      if (prevMessages) {
        conversationHistory = prevMessages
          .map((m) => `${(m.role as string).toUpperCase()}: ${m.content}`)
          .join('\n');
      }
    }

    const conversationId = body.conversation_id ?? crypto.randomUUID();

    // Sestav system prompt
    const systemPrompt = `Jsi AI asistent MotoGo24 — systému pro pronájem motocyklů v ČR.
Odpovídej česky, stručně a věcně. Jsi expert na provoz půjčovny motorek.

Aktuální kontext (stránka: ${contextPage}):
${contextData}

${conversationHistory ? `Předchozí konverzace:\n${conversationHistory}\n` : ''}

Pokud chceš navrhnout akci (blokace motorky, odeslání zprávy, apod.), použij formát:
[ACTION:typ_akce] {"entity_type": "...", "entity_id": "...", "detail": "..."}

Dostupné akce: block_moto, unblock_moto, send_message, create_booking, cancel_booking, assign_task.`;

    // Zavolej Anthropic API
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
    const aiResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-5-20250929',
        max_tokens: 2000,
        system: systemPrompt,
        messages: [{ role: 'user', content: body.message }],
      }),
    });

    if (!aiResp.ok) {
      const errBody = await aiResp.text();
      console.error('Anthropic API error:', errBody);
      return errorResponse('AI service unavailable', 503);
    }

    const aiResult = await aiResp.json() as {
      content: Array<{ type: string; text: string }>;
    };
    const aiText = aiResult.content
      .filter((c) => c.type === 'text')
      .map((c) => c.text)
      .join('');

    // Parsuj akce z odpovědi
    const actions = parseActions(aiText);

    // Ulož akce do ai_actions
    for (const action of actions) {
      await adminClient.from('ai_actions').insert({
        conversation_id: conversationId,
        action_type: action.type,
        entity_type: action.entity_type,
        entity_id: action.entity_id,
        payload: action.payload,
        status: 'pending',
        created_by: user.id,
      });
    }

    // Ulož konverzaci
    await adminClient.from('ai_conversations').insert([
      {
        conversation_id: conversationId,
        role: 'user',
        content: body.message,
        context_page: contextPage,
        user_id: user.id,
      },
      {
        conversation_id: conversationId,
        role: 'assistant',
        content: aiText,
        context_page: contextPage,
        user_id: user.id,
      },
    ]);

    // Loguj do ai_logs
    await adminClient.from('ai_logs').insert({
      conversation_id: conversationId,
      user_id: user.id,
      context_page: contextPage,
      message_length: body.message.length,
      response_length: aiText.length,
      actions_count: actions.length,
      model: 'claude-sonnet-4-5-20250929',
    });

    const response: AiCopilotResponse = {
      success: true,
      response: aiText,
      actions: actions.length > 0 ? actions : undefined,
      conversation_id: conversationId,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('ai-copilot error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
