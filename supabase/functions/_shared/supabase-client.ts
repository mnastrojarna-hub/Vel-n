/**
 * MotoGo24 — Factory pro Supabase klienty
 * Admin client používá SERVICE_ROLE_KEY (plný přístup).
 * User client používá ANON_KEY s předaným JWT tokenem (RLS).
 */

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/** Vrátí Supabase admin klienta (SERVICE_ROLE_KEY, bypass RLS). */
export function getAdminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );
}

/** Vrátí Supabase klienta s uživatelským JWT (respektuje RLS). */
export function getUserClient(authHeader: string): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );
}
