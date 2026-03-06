/**
 * MotoGo24 — Edge Function: Admin Auth
 * Ověření admin přístupu, získání rolí a oprávnění.
 *
 * POST /functions/v1/admin-auth
 * Body: { action: 'login'|'verify'|'permissions' }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { AdminAuthRequest, AdminAuthResponse, AdminRole, AdminPermissions } from '../_shared/types.ts';

/** Vrátí permission mapu podle admin role. */
function getPermissionsByRole(role: AdminRole): AdminPermissions {
  const fullAccess = { read: true, write: true, delete: true };
  const readOnly = { read: true, write: false, delete: false };
  const readWrite = { read: true, write: true, delete: false };
  const noAccess = { read: false, write: false, delete: false };

  switch (role) {
    case 'superadmin':
      return {
        bookings: fullAccess,
        motorcycles: fullAccess,
        customers: fullAccess,
        finance: fullAccess,
        sos: fullAccess,
        settings: fullAccess,
        reports: fullAccess,
        ai_copilot: fullAccess,
      };
    case 'manager':
      return {
        bookings: fullAccess,
        motorcycles: fullAccess,
        customers: readWrite,
        finance: readWrite,
        sos: fullAccess,
        settings: readOnly,
        reports: fullAccess,
        ai_copilot: readWrite,
      };
    case 'operator':
      return {
        bookings: readWrite,
        motorcycles: readOnly,
        customers: readOnly,
        finance: readOnly,
        sos: readWrite,
        settings: noAccess,
        reports: readOnly,
        ai_copilot: readOnly,
      };
    case 'viewer':
      return {
        bookings: readOnly,
        motorcycles: readOnly,
        customers: readOnly,
        finance: noAccess,
        sos: readOnly,
        settings: noAccess,
        reports: readOnly,
        ai_copilot: noAccess,
      };
    default:
      return {
        bookings: noAccess,
        motorcycles: noAccess,
        customers: noAccess,
        finance: noAccess,
        sos: noAccess,
        settings: noAccess,
        reports: noAccess,
        ai_copilot: noAccess,
      };
  }
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

    const body = await req.json() as AdminAuthRequest;
    const validActions = ['login', 'verify', 'permissions'];
    if (!body.action || !validActions.includes(body.action)) {
      return errorResponse(`Invalid action. Valid actions: ${validActions.join(', ')}`);
    }

    // Načti admin záznam z DB
    const admin = getAdminClient();
    const { data: adminUser, error: adminError } = await admin
      .from('admin_users')
      .select('id, user_id, role, branch_access, is_active, profiles!inner(full_name, email)')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single();

    if (adminError || !adminUser) {
      if (body.action === 'verify') {
        return jsonResponse({ success: true, is_admin: false });
      }
      return errorResponse('Admin access denied', 403);
    }

    const profile = adminUser.profiles as unknown as { full_name: string; email: string };
    const role = adminUser.role as AdminRole;
    const branchAccess = adminUser.branch_access as string[] | null;

    switch (body.action) {
      case 'login': {
        // Loguj přihlášení
        await admin.from('admin_audit_log').insert({
          admin_id: adminUser.id as string,
          action: 'login',
          entity_type: 'admin_users',
          entity_id: adminUser.id as string,
          ip_address: req.headers.get('x-forwarded-for') ?? req.headers.get('cf-connecting-ip') ?? 'unknown',
        });

        const response: AdminAuthResponse = {
          success: true,
          user: {
            id: user.id,
            email: profile.email,
            full_name: profile.full_name,
          },
          role,
          branch_access: branchAccess ?? [],
          permissions: getPermissionsByRole(role),
        };
        return jsonResponse(response);
      }

      case 'verify': {
        return jsonResponse({
          success: true,
          is_admin: true,
          role,
        });
      }

      case 'permissions': {
        const response: AdminAuthResponse = {
          success: true,
          user: {
            id: user.id,
            email: profile.email,
            full_name: profile.full_name,
          },
          role,
          branch_access: branchAccess ?? [],
          permissions: getPermissionsByRole(role),
        };
        return jsonResponse(response);
      }

      default:
        return errorResponse('Unknown action');
    }
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('admin-auth error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
