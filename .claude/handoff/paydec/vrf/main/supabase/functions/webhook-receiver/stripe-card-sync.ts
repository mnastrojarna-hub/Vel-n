// ===== webhook-receiver/stripe-card-sync.ts =====
// Card sync functions for Stripe setup sessions and customer cards

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

/** Sync card details from a setup session (add card flow) to Supabase */
export async function syncCardFromSetupSession(
  supabase: ReturnType<typeof createClient>,
  session: Stripe.Checkout.Session
) {
  try {
    const customerId = session.customer as string
    const userId = session.metadata?.user_id
    if (!customerId || !userId) return

    // Get the SetupIntent to find the payment method
    const setupIntentId = typeof session.setup_intent === 'string'
      ? session.setup_intent
      : (session.setup_intent as any)?.id
    if (!setupIntentId) return

    const setupIntent = await stripe.setupIntents.retrieve(setupIntentId)
    const pmId = typeof setupIntent.payment_method === 'string'
      ? setupIntent.payment_method
      : (setupIntent.payment_method as any)?.id
    if (!pmId) return

    const pm = await stripe.paymentMethods.retrieve(pmId)

    // Upsert card into payment_methods table
    await supabase.from('payment_methods').upsert({
      user_id: userId,
      stripe_payment_method_id: pm.id,
      brand: pm.card?.brand || 'unknown',
      last4: pm.card?.last4 || '****',
      exp_month: pm.card?.exp_month || null,
      exp_year: pm.card?.exp_year || null,
      holder_name: pm.billing_details?.name || null,
      is_default: false,
    }, { onConflict: 'stripe_payment_method_id' })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'card_saved_from_setup',
        component: 'stripe',
        status: 'ok',
        request_data: { user_id: userId, pm_id: pm.id, brand: pm.card?.brand, last4: pm.card?.last4 },
      })
    } catch (e) { /* ignore */ }
  } catch (e) {
    console.error('syncCardFromSetupSession error:', e)
  }
}

/** Sync all cards for a Stripe customer to Supabase payment_methods table */
export async function syncCardsForCustomer(
  supabase: ReturnType<typeof createClient>,
  customerId: string
) {
  try {
    // Find user_id from profiles
    const { data: profile } = await supabase
      .from('profiles')
      .select('id')
      .eq('stripe_customer_id', customerId)
      .maybeSingle()
    if (!profile) return

    const customer = await stripe.customers.retrieve(customerId) as Stripe.Customer
    const methods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    })

    const defaultPmId = (customer.invoice_settings?.default_payment_method as string) || null

    // Remove old cards and insert fresh
    await supabase.from('payment_methods').delete().eq('user_id', profile.id)

    if (methods.data.length > 0) {
      const cards = methods.data.map((pm) => ({
        user_id: profile.id,
        stripe_payment_method_id: pm.id,
        brand: pm.card?.brand || 'unknown',
        last4: pm.card?.last4 || '****',
        exp_month: pm.card?.exp_month || null,
        exp_year: pm.card?.exp_year || null,
        holder_name: pm.billing_details?.name || null,
        is_default: pm.id === defaultPmId,
      }))
      await supabase.from('payment_methods').insert(cards)
    }
  } catch (e) {
    console.error('syncCardsForCustomer error:', e)
  }
}
