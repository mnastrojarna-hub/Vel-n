// ===== process-payment/stripe-customer.ts =====
// Stripe customer management + JWT decode + types + constants

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

export const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

export const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

export type PaymentType = 'booking' | 'shop' | 'extension' | 'sos'

export interface PaymentRequest {
  booking_id?: string
  order_id?: string
  incident_id?: string
  /** Optional bundled e-shop order to attach to a web booking checkout (single Stripe session, two invoices). */
  shop_order_id?: string
  amount: number
  currency?: string
  method?: string
  type?: PaymentType
  mode?: 'intent' | 'checkout'
  source?: string
}

export const PRODUCT_NAMES: Record<PaymentType, string> = {
  booking: 'MotoGo24 — Pronájem motorky',
  shop: 'MotoGo24 — E-shop objednávka',
  extension: 'MotoGo24 — Prodloužení rezervace',
  sos: 'MotoGo24 — SOS náhradní motorka',
}

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Decode JWT payload without verification (gateway already verified)
export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')))
    return payload
  } catch { return null }
}

// Get or create Stripe Customer for the authenticated user
export async function getOrCreateStripeCustomer(
  supabase: ReturnType<typeof createClient>,
  req: Request
): Promise<string | null> {
  try {
    const authHeader = req.headers.get('authorization') || ''
    const token = authHeader.replace('Bearer ', '')
    if (!token) return null

    const jwtPayload = decodeJwtPayload(token)
    let userId = jwtPayload?.sub as string | null
    let userEmail = (jwtPayload?.email as string) || null

    if (!userId) {
      try {
        const { data: { user: authUser } } = await supabase.auth.getUser(token)
        if (authUser) {
          userId = authUser.id
          userEmail = authUser.email || null
        }
      } catch (e) {
        console.warn('getUser fallback failed:', e)
      }
    }

    if (!userId) return null

    const { data: profile } = await supabase
      .from('profiles')
      .select('stripe_customer_id, full_name, email, phone')
      .eq('id', userId)
      .single()

    if (profile?.stripe_customer_id) {
      return profile.stripe_customer_id
    }

    const customer = await stripe.customers.create({
      email: userEmail || profile?.email || undefined,
      name: profile?.full_name || undefined,
      phone: profile?.phone || undefined,
      metadata: { supabase_user_id: userId },
    })

    await supabase
      .from('profiles')
      .update({ stripe_customer_id: customer.id })
      .eq('id', userId)

    return customer.id
  } catch (e) {
    console.warn('getOrCreateStripeCustomer error:', e)
    return null
  }
}
