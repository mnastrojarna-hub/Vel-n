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

const SUPPORTED_LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl'] as const
const DOMAIN_CS = 'https://motogo24.cz'
const DOMAIN_INTL = 'https://motogo24.com'

/**
 * Build the absolute origin used for Stripe redirect URLs.
 * Prefers what the browser sent (so .com users return to .com and keep their
 * mg_web_lang cookie), falls back to per-language canonical domain, then SITE_URL.
 */
export function resolveReturnOrigin(origin: string | null | undefined, locale: string | null | undefined): string {
  const lang = (locale || '').toLowerCase()
  if (origin) {
    try {
      const u = new URL(origin)
      if (u.hostname.endsWith('motogo24.cz') || u.hostname.endsWith('motogo24.com')) {
        return `${u.protocol}//${u.host}`
      }
    } catch { /* ignore */ }
  }
  if (lang === 'cs') return DOMAIN_CS
  if (SUPPORTED_LANGS.includes(lang as typeof SUPPORTED_LANGS[number])) return DOMAIN_INTL
  return SITE_URL
}

/** Pick a Stripe Checkout `locale` value supported by Stripe; falls back to 'cs'. */
export function resolveStripeLocale(locale: string | null | undefined): string {
  const lang = (locale || '').toLowerCase()
  if (SUPPORTED_LANGS.includes(lang as typeof SUPPORTED_LANGS[number])) return lang
  return 'cs'
}

/** Append `&lang=xx` to a Stripe redirect URL if non-default. Default cs/en stay clean. */
export function withLangParam(url: string, locale: string | null | undefined): string {
  const lang = (locale || '').toLowerCase()
  if (!lang || lang === 'cs' || lang === 'en') return url
  if (!SUPPORTED_LANGS.includes(lang as typeof SUPPORTED_LANGS[number])) return url
  const sep = url.includes('?') ? '&' : '?'
  return `${url}${sep}lang=${lang}`
}

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
  /** Browser origin (https://motogo24.cz / https://motogo24.com) — Stripe redirects back here. */
  origin?: string
  /** Active website language (cs/en/de/es/fr/nl/pl) — propagates to thank-you page. */
  locale?: string
  /** Optional explicit Stripe redirect URLs — used by web extension flow to return to /upravit-rezervaci. */
  success_url?: string
  cancel_url?: string
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
