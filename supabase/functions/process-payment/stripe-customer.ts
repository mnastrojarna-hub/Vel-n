// ===== process-payment/stripe-customer.ts =====
// Stripe customer management + JWT decode + types + constants
import Stripe from 'https://esm.sh/stripe@14';
export const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY'), {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient()
});
export const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz';
const SUPPORTED_LANGS = [
  'cs',
  'en',
  'de',
  'es',
  'fr',
  'nl',
  'pl'
];
const DOMAIN_CS = 'https://www.motogo24.cz';
const DOMAIN_INTL = 'https://motogo24.com';
/**
 * Build the absolute origin used for Stripe redirect URLs.
 * Prefers what the browser sent (so .com users return to .com and keep their
 * mg_web_lang cookie), falls back to per-language canonical domain, then SITE_URL.
 */ export function resolveReturnOrigin(origin, locale) {
  const lang = (locale || '').toLowerCase();
  if (origin) {
    try {
      const u = new URL(origin);
      if (u.hostname.endsWith('motogo24.cz') || u.hostname.endsWith('motogo24.com')) {
        return `${u.protocol}//${u.host}`;
      }
    } catch  {}
  }
  if (lang === 'cs') return DOMAIN_CS;
  if (SUPPORTED_LANGS.includes(lang)) return DOMAIN_INTL;
  return SITE_URL;
}
/** Pick a Stripe Checkout `locale` value supported by Stripe; falls back to 'cs'. */ export function resolveStripeLocale(locale) {
  const lang = (locale || '').toLowerCase();
  if (SUPPORTED_LANGS.includes(lang)) return lang;
  return 'cs';
}
/** Append `&lang=xx` to a Stripe redirect URL if non-default. Default cs/en stay clean. */ export function withLangParam(url, locale) {
  const lang = (locale || '').toLowerCase();
  if (!lang || lang === 'cs' || lang === 'en') return url;
  if (!SUPPORTED_LANGS.includes(lang)) return url;
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}lang=${lang}`;
}
export const PRODUCT_NAMES = {
  booking: 'MotoGo24 — Pronájem motorky',
  shop: 'MotoGo24 — E-shop objednávka',
  extension: 'MotoGo24 — Prodloužení rezervace',
  sos: 'MotoGo24 — SOS náhradní motorka'
};
export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
// Decode JWT payload without verification (gateway already verified)
export function decodeJwtPayload(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    return payload;
  } catch  {
    return null;
  }
}
// Get or create Stripe Customer for the authenticated user
export async function getOrCreateStripeCustomer(supabase, req) {
  try {
    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return null;
    const jwtPayload = decodeJwtPayload(token);
    let userId = jwtPayload?.sub;
    let userEmail = jwtPayload?.email || null;
    if (!userId) {
      try {
        const { data: { user: authUser } } = await supabase.auth.getUser(token);
        if (authUser) {
          userId = authUser.id;
          userEmail = authUser.email || null;
        }
      } catch (e) {
        console.warn('getUser fallback failed:', e);
      }
    }
    if (!userId) return null;
    const { data: profile } = await supabase.from('profiles').select('stripe_customer_id, full_name, email, phone').eq('id', userId).single();
    if (profile?.stripe_customer_id) {
      return profile.stripe_customer_id;
    }
    const customer = await stripe.customers.create({
      email: userEmail || profile?.email || undefined,
      name: profile?.full_name || undefined,
      phone: profile?.phone || undefined,
      metadata: {
        supabase_user_id: userId
      }
    });
    await supabase.from('profiles').update({
      stripe_customer_id: customer.id
    }).eq('id', userId);
    return customer.id;
  } catch (e) {
    console.warn('getOrCreateStripeCustomer error:', e);
    return null;
  }
}
