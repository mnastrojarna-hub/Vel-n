/**
 * MotoGo24 — Edge Function: Admin Reset Password
 * Umožňuje admin uživatelům resetovat heslo zákazníka.
 * Vyžaduje admin roli (ověření přes admin_users).
 *
 * POST /functions/v1/admin-reset-password
 * Body: { user_id: string, new_password?: string }
 * - Pokud new_password je zadáno → přímo změní heslo
 * - Pokud ne → pošle reset email zákazníkovi
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Ověř volajícího admina
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const adminClient = createClient(supabaseUrl, serviceKey)

    // Ověř JWT token volajícího přes service role
    const token = authHeader.replace('Bearer ', '')
    const { data: { user: caller }, error: authErr } = await adminClient.auth.getUser(token)
    if (authErr || !caller) {
      return new Response(JSON.stringify({ error: 'Unauthorized', detail: authErr?.message }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Zkontroluj admin oprávnění
    const { data: adminUser } = await adminClient
      .from('admin_users')
      .select('id, role')
      .eq('id', caller.id)
      .single()

    if (!adminUser || !['superadmin', 'admin'].includes(adminUser.role)) {
      return new Response(JSON.stringify({ error: 'Admin access required' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json()
    const { user_id, new_password } = body

    if (!user_id) {
      return new Response(JSON.stringify({ error: 'user_id is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (new_password) {
      // Přímo změní heslo pomocí service_role
      const { error: updateErr } = await adminClient.auth.admin.updateUserById(user_id, {
        password: new_password,
      })
      if (updateErr) {
        return new Response(JSON.stringify({ error: updateErr.message }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      // Audit log
      await adminClient.from('admin_audit_log').insert({
        admin_id: adminUser.id,
        action: 'customer_password_reset',
        details: { customer_user_id: user_id, method: 'direct' },
      })

      return new Response(JSON.stringify({ success: true, method: 'direct' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } else {
      // Pošle reset email
      const { data: profile } = await adminClient
        .from('profiles')
        .select('email')
        .eq('id', user_id)
        .single()

      if (!profile?.email) {
        // Zkus auth.users
        const { data: authUser } = await adminClient.auth.admin.getUserById(user_id)
        const email = authUser?.user?.email
        if (!email) {
          return new Response(JSON.stringify({ error: 'Email zákazníka nenalezen' }), {
            status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          })
        }
        // Generate password reset link
        const { data: linkData, error: linkErr } = await adminClient.auth.admin.generateLink({
          type: 'recovery',
          email: email,
        })
        if (linkErr) {
          return new Response(JSON.stringify({ error: linkErr.message }), {
            status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          })
        }

        await adminClient.from('admin_audit_log').insert({
          admin_id: adminUser.id,
          action: 'customer_password_reset_email',
          details: { customer_user_id: user_id, email, method: 'email' },
        })

        return new Response(JSON.stringify({ success: true, method: 'email', email }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { error: linkErr } = await adminClient.auth.admin.generateLink({
        type: 'recovery',
        email: profile.email,
      })
      if (linkErr) {
        return new Response(JSON.stringify({ error: linkErr.message }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      await adminClient.from('admin_audit_log').insert({
        admin_id: adminUser.id,
        action: 'customer_password_reset_email',
        details: { customer_user_id: user_id, email: profile.email, method: 'email' },
      })

      return new Response(JSON.stringify({ success: true, method: 'email', email: profile.email }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: msg }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
