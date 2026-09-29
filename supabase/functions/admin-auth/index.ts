import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
serve(async (req)=>{
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: CORS
  });
  try {
    const { action } = await req.json();
    // Ověření JWT tokenu uživatele
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({
        error: 'Missing authorization header'
      }), {
        status: 401,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    // Vytvoříme anon client pro ověření uživatele z JWT
    const supabaseAnon = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({
        error: 'Unauthorized'
      }), {
        status: 401,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    // Service role client pro admin operace (obchází RLS)
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    if (action === 'provision') {
      // BEZPEČNOST (2026-05-29): Auto-provisioning ODSTRANĚN. Dříve tato větev
      // vytvořila admin_users řádek s výchozí rolí 'admin' KAŽDÉMU přihlášenému
      // uživateli — jakýkoli zákazník s platným účtem se tak prvním přihlášením
      // do Velína sám povýšil na admina a obešel RLS. Nově funkce pouze vrátí
      // EXISTUJÍCÍ admin záznam; nového admina smí přidat výhradně superadmin
      // ručně do admin_users. Žádné self-provisioning.
      const { data: existing } = await supabaseAdmin.from('admin_users').select('*').eq('id', user.id).single();
      if (existing) {
        return new Response(JSON.stringify({
          success: true,
          admin: existing
        }), {
          headers: {
            ...CORS,
            'Content-Type': 'application/json'
          }
        });
      }
      return new Response(JSON.stringify({
        error: 'not_authorized'
      }), {
        status: 403,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    return new Response(JSON.stringify({
      error: 'Unknown action'
    }), {
      status: 400,
      headers: {
        ...CORS,
        'Content-Type': 'application/json'
      }
    });
  } catch (err) {
    console.error('Error:', err);
    return new Response(JSON.stringify({
      error: err.message
    }), {
      status: 500,
      headers: {
        ...CORS,
        'Content-Type': 'application/json'
      }
    });
  }
});
