// Replacement for https://esm.sh/stripe@14 — every call is forwarded to the current fake World.
// deno-lint-ignore-file no-explicit-any
import { world } from './world.ts'
class Stripe {
  static createFetchHttpClient() { return {} }
  constructor(_k?: string, _o?: unknown) {}
  get paymentIntents() { return world().api().paymentIntents }
  get refunds() { return world().api().refunds }
  get charges() { return world().api().charges }
  get checkout() { return world().api().checkout }
  get webhooks() { return world().api().webhooks }
  get customers() { return world().api().customers }
}
// deno-lint-ignore no-namespace
declare namespace Stripe { type Event = any; type Charge = any; type Refund = any; type PaymentIntent = any; type RefundCreateParams = any
  namespace Checkout { type Session = any } type Payout = any }
export default Stripe
