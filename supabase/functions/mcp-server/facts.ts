// ===== mcp-server/facts.ts =====
// Fakta pro externí AI nástroje (MCP) — audit i18n 2026-10-10 (AI-09): dřívější statické texty
// tvrdily „24/7 nonstop přes kódy" pro Mezná, jen jednu pobočku, výjezd do zahraničí bez omezení,
// storno „individuálně", A od 24 / 21 let a byly jen česky. Zdroj: závazná fakta majitele
// (_shared/agent-knowledge/owner-facts.ts), site.policies (foreign_travel) a FAQ z DB v jazyce
// klienta. Anglicky (MCP klient je mezinárodní); závazné je české znění VOP.
import { normLang, siteUrl } from '../_shared/agent-knowledge/site-url.ts';
export const LANG_ENUM = [
  'cs',
  'en',
  'de',
  'es',
  'fr',
  'nl',
  'pl',
  'uk'
];
export function keyFacts(lang, foreignTravelCs) {
  const L = normLang(lang, 'en');
  return [
    {
      q: 'Deposit?',
      a: 'None — MotoGo24 takes no deposit and blocks nothing on the card (0 CZK).'
    },
    {
      q: 'Damage / excess?',
      a: '100 % contractual damage cover: the renter\'s excess is 0 CZK when the rental conditions are kept (General Terms art. 7). Exceptions and theft rules are in art. 7 of the binding Czech General Terms — never promise "no liability whatsoever".'
    },
    {
      q: 'Branches and opening hours?',
      a: 'Two branches, both NONSTOP (pick-up and return any time 0–24 h according to the booking): Mezná 9, Pelhřimov — staffed (handover by staff at the booked time; earliest 1–6 h after booking and payment); Velké Němčice — 100 % self-service with access codes from the app/e-mail, 24/7.'
    },
    {
      q: 'Phone support?',
      a: '+420 774 256 271, Mon–Fri 8:00–17:00 (CET). The AI assistant on the website answers 24/7. Breakdown/accident during a rental: SOS button in the MotoGo24 app.'
    },
    {
      q: 'Return conditions?',
      a: 'Staffed branch Mezná (also when returning at another agreed place): no washing and no refuelling needed. Self-service branch Velké Němčice: no refuelling needed (a full tank is not required), but the motorcycle must be returned washed and the fuel reserve warning light must not be on.'
    },
    {
      q: 'Mileage / travel abroad?',
      a: `Unlimited kilometres within the Green Card countries. Binding Czech rule: ${foreignTravelCs || 'travel to Russia, Ukraine and Kosovo is forbidden.'}`
    },
    {
      q: 'Cancellation?',
      a: 'Per the binding Czech General Terms (art. 3): free up to 7 days (168 h) before the start; 2–7 days before = fee up to 50 %; less than 2 days or no-show = 100 %. A paid booking that has not been picked up can be moved free of charge to other dates of the same length (at the latest on the start day, if the motorcycle is available).'
    },
    {
      q: 'Payment and currency?',
      a: 'Charged in CZK only, paid in advance online (Stripe: card, Apple Pay, Google Pay; on the website also QR / bank transfer). EUR/PLN prices on the website are approximate. No cash.'
    },
    {
      q: 'Driving licence?',
      a: 'A1 from 16 (≤ 11 kW / 125 cc), A2 from 18 (≤ 35 kW), A from 24 (or from 20 with 2 years of A2); B allows 125 cc automatic scooters under Czech legal conditions; kids/off-road bikes need no licence (off public roads only). The renter must be 18+.'
    },
    {
      q: 'Gear?',
      a: 'Rider gear (helmet, jacket, trousers, gloves) is included; boots and passenger gear cost extra.'
    },
    {
      q: 'Languages and legal documents?',
      a: `Website and documents in cs, en, de, es, fr, nl, pl, uk — the Czech version of the General Terms, rental contract and GDPR policy is binding (translations are informative). General Terms: ${siteUrl(L, '/dokumenty/obchodni-podminky')}`
    },
    {
      q: 'How to book?',
      a: `Online: ${siteUrl(L, '/katalog')} or the MCP tool motogo_create_booking (requires the customer's explicit consent to the General Terms and GDPR, date of birth and language).`
    }
  ];
}
/** FAQ z DB (faq_items, jen published) v jazyce klienta, filtr dle klíčového slova. */ export async function dbFaq(sb, lang, query) {
  const L = normLang(lang, 'en');
  const strip = (s)=>String(s || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  try {
    const { data } = await sb.from('faq_items').select('question, answer, translations, sort_order').eq('published', true).order('category_key').order('sort_order');
    const out = (data || []).map((r)=>{
      const tr = r.translations?.[L] || {};
      return {
        q: strip(L !== 'cs' && tr.question ? tr.question : r.question),
        a: strip(L !== 'cs' && tr.answer ? tr.answer : r.answer)
      };
    }).filter((f)=>f.q && f.a);
    const q = query.toLowerCase().trim();
    return q ? out.filter((f)=>(f.q + ' ' + f.a).toLowerCase().includes(q)) : out;
  } catch  {
    return [];
  }
}
export async function foreignTravelCs(sb) {
  try {
    const { data } = await sb.from('app_settings').select('value').eq('key', 'site.policies').maybeSingle();
    const v = data?.value?.foreign_travel;
    return typeof v === 'string' && v.trim() ? v.trim() : undefined;
  } catch  {
    return undefined;
  }
}
/** Markdown pro resources motogo://about a motogo://policies. */ export function factsMarkdown(title, facts) {
  return `# ${title}\n\n` + facts.map((f)=>`## ${f.q}\n\n${f.a}\n`).join('\n');
}
