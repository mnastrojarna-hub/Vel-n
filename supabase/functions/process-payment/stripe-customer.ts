// ===== process-payment/stripe-customer.ts =====
// Stripe customer management (user via auth.getUser) + types + constants
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
  'pl',
  'uk'
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
/** Jazyk webu/zákazníka (cs…uk) — pro uložené sloupce `language` (rezervace, objednávka); jinak 'cs'. */ export function resolveSiteLang(locale) {
  const lang = (locale || '').toLowerCase().slice(0, 2);
  if (SUPPORTED_LANGS.includes(lang)) return lang;
  return 'cs';
}
/** Stripe Checkout `locale`. Stripe ukrajinštinu nepodporuje (neplatná hodnota = chyba
 *  vytvoření session = zákazník nezaplatí) → 'auto' (jazyk prohlížeče). Bez jazyka 'cs'. */ export function resolveStripeLocale(locale) {
  const lang = (locale || '').toLowerCase().slice(0, 2);
  if (!lang) return 'cs';
  if (lang === 'uk') return 'auto';
  if (SUPPORTED_LANGS.includes(lang)) return lang;
  return 'auto';
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
// Get or create Stripe Customer for the authenticated user.
// BEZPEČNOST 2026-10-11: uživatele určuje VÝHRADNĚ auth.getUser (podpis ověří
// Auth server). Dřív se bral `sub` z nepodepsaně dekódovaného JWT — verify_jwt=false
// = gateway nic neověřuje, takže podvržený token s cizím `sub` dostal Stripe
// customer oběti (uložené karty, ephemeral key). Neplatný/expirovaný token → null.
export async function getOrCreateStripeCustomer(supabase, req) {
  try {
    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return null;
    let userId = null;
    let userEmail = null;
    try {
      const { data: { user: authUser } } = await supabase.auth.getUser(token);
      if (authUser) {
        userId = authUser.id;
        userEmail = authUser.email || null;
      }
    } catch (e) {
      console.warn('getUser failed:', e);
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
