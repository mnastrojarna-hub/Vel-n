/**
 * MotoGo24 — Edge Function: CMS Sync
 * Načtení CMS proměnných pro frontend/web konfiguraci.
 *
 * POST /functions/v1/cms-sync
 * Auth: SERVICE_ROLE_KEY nebo Bearer JWT (admin)
 * Body: { keys?: string[] }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { CmsSyncRequest, CmsSyncResponse } from '../_shared/types.ts';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }

    // Ověř autorizaci — service role key NEBO admin JWT
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const isServiceRole = authHeader === `Bearer ${serviceRoleKey}`;

    if (!isServiceRole) {
      const userClient = getUserClient(authHeader);
      const { data: { user }, error: authError } = await userClient.auth.getUser();
      if (authError || !user) {
        return errorResponse('Unauthorized', 401);
      }

      // Ověř admin roli
      const adminCheck = getAdminClient();
      const { data: adminUser, error: adminError } = await adminCheck
        .from('admin_users')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .maybeSingle();

      if (adminError || !adminUser) {
        return errorResponse('Admin access required', 403);
      }
    }

    const admin = getAdminClient();

    // Parse request body (může být prázdné pro GET-like chování)
    let keys: string[] | undefined;
    try {
      const body = await req.json() as CmsSyncRequest;
      keys = body.keys;
    } catch {
      // Prázdné body — vrátíme všechny proměnné
    }

    // Načti CMS proměnné
    let query = admin
      .from('cms_variables')
      .select('key, value, type, category, description, updated_at')
      .eq('is_active', true)
      .order('category')
      .order('key');

    if (keys && keys.length > 0) {
      query = query.in('key', keys);
    }

    const { data: variables, error: queryError } = await query;

    if (queryError) {
      console.error('CMS query error:', queryError);
      return errorResponse('Failed to load CMS variables', 500);
    }

    // Transformuj do key-value mapy s metadata
    const variablesMap: Record<string, unknown> = {};
    for (const v of variables ?? []) {
      const key = v.key as string;
      let value: unknown = v.value;

      // Parsuj hodnotu dle typu
      const varType = v.type as string;
      switch (varType) {
        case 'number':
          value = Number(v.value);
          break;
        case 'boolean':
          value = v.value === 'true' || v.value === '1';
          break;
        case 'json':
          try {
            value = JSON.parse(v.value as string);
          } catch {
            value = v.value;
          }
          break;
        case 'array':
          try {
            value = JSON.parse(v.value as string);
          } catch {
            value = (v.value as string).split(',').map((s: string) => s.trim());
          }
          break;
        default:
          value = v.value;
      }

      variablesMap[key] = {
        value,
        type: varType,
        category: v.category,
        description: v.description,
        updated_at: v.updated_at,
      };
    }

    // Načti i feature flags
    const { data: featureFlags } = await admin
      .from('feature_flags')
      .select('key, enabled, description, metadata')
      .eq('is_active', true);

    const flags: Record<string, unknown> = {};
    for (const flag of featureFlags ?? []) {
      flags[flag.key as string] = {
        enabled: flag.enabled,
        description: flag.description,
        metadata: flag.metadata,
      };
    }

    const response: CmsSyncResponse = {
      success: true,
      variables: {
        ...variablesMap,
        _feature_flags: flags,
        _synced_at: new Date().toISOString(),
        _total_variables: variables?.length ?? 0,
        _total_flags: featureFlags?.length ?? 0,
      },
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('cms-sync error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
