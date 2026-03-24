// Hook that provides current page context for AI Copilot
import { useLocation, useParams } from 'react-router-dom'

// Page context mapping — what AI should know about current page
const PAGE_CONTEXT = {
  '/': { page: 'dashboard', agent: 'analytics', label: 'Dashboard', desc: 'Přehled celého systému' },
  '/flotila': { page: 'fleet', agent: 'fleet', label: 'Flotila', desc: 'Seznam všech motorek' },
  '/rezervace': { page: 'bookings', agent: 'bookings', label: 'Rezervace', desc: 'Seznam všech rezervací' },
  '/zakaznici': { page: 'customers', agent: 'customers', label: 'Zákazníci', desc: 'Seznam zákazníků' },
  '/finance': { page: 'finance', agent: 'finance', label: 'Finance', desc: 'Finanční přehled, faktury, účetnictví' },
  '/dokumenty': { page: 'documents', agent: 'cms', label: 'Dokumenty', desc: 'Smlouvy, šablony, vygenerované dokumenty' },
  '/pobocky': { page: 'branches', agent: 'fleet', label: 'Pobočky', desc: 'Správa poboček' },
  '/servis': { page: 'service', agent: 'service', label: 'Servis', desc: 'Servisní plány a objednávky' },
  '/zpravy': { page: 'messages', agent: 'customers', label: 'Zprávy', desc: 'Komunikace se zákazníky' },
  '/cms': { page: 'cms', agent: 'cms', label: 'Web CMS', desc: 'Správa webu, nastavení, feature flagy' },
  '/analyza': { page: 'analyza', agent: 'analytics', label: 'Analýza', desc: 'Výkon poboček, motorek, zákazníků' },
  '/slevove-kody': { page: 'promos', agent: 'eshop', label: 'Slevové kódy', desc: 'Promo kódy a vouchery' },
  '/e-shop': { page: 'eshop', agent: 'eshop', label: 'E-shop', desc: 'Objednávky a produkty' },
  '/statni-sprava': { page: 'government', agent: 'government', label: 'Státní správa', desc: 'STK, pojistky, daně' },
  '/ai-copilot': { page: 'ai', agent: null, label: 'AI Copilot', desc: 'AI asistent' },
  '/sos': { page: 'sos', agent: 'sos', label: 'SOS Panel', desc: 'Nouzové incidenty' },
  '/zamestnanci': { page: 'employees', agent: 'hr', label: 'Zaměstnanci', desc: 'Zaměstnanci, směny, docházka' },
  '/sklady': { page: 'inventory', agent: 'service', label: 'Sklady', desc: 'Skladové zásoby a pohyby' },
}

// Detail page patterns
const DETAIL_PATTERNS = [
  { pattern: /^\/flotila\/(.+)$/, page: 'fleet_detail', agent: 'fleet', label: 'Detail motorky' },
  { pattern: /^\/rezervace\/(.+)$/, page: 'booking_detail', agent: 'bookings', label: 'Detail rezervace' },
  { pattern: /^\/zakaznici\/(.+)$/, page: 'customer_detail', agent: 'customers', label: 'Detail zákazníka' },
  { pattern: /^\/sklady\/(.+)$/, page: 'inventory_detail', agent: 'service', label: 'Detail skladové položky' },
]

export function useAiContext() {
  const location = useLocation()
  const params = useParams()
  const path = location.pathname

  // Check exact match first
  let ctx = PAGE_CONTEXT[path]

  // Check detail patterns
  if (!ctx) {
    for (const dp of DETAIL_PATTERNS) {
      const match = path.match(dp.pattern)
      if (match) {
        ctx = { ...dp, entityId: match[1] }
        break
      }
    }
  }

  return {
    path,
    page: ctx?.page || 'unknown',
    agent: ctx?.agent || null,
    label: ctx?.label || 'Neznámá stránka',
    desc: ctx?.desc || '',
    entityId: ctx?.entityId || params?.id || null,
  }
}

// Quick actions per page context
export const PAGE_QUICK_ACTIONS = {
  dashboard: [
    'Kompletní denní přehled',
    'Jak jsme na tom vs. minulý měsíc?',
    'Co je dnes potřeba vyřešit?',
    'Spusť denní test integrity dat',
  ],
  fleet: [
    'Stav celé flotily',
    'Které motorky potřebují servis?',
    'Ranking motorek dle výkonu',
    'Přesuň motorku XY na jinou pobočku',
  ],
  fleet_detail: [
    'Kompletní historie této motorky',
    'Naplánuj servis pro tuto motorku',
    'Změň stav motorky',
    'Kolik tato motorka vydělala?',
  ],
  bookings: [
    'Aktivní rezervace',
    'Nezaplacené rezervace',
    'Stornované tento měsíc',
    'Vytvoř novou rezervaci',
  ],
  booking_detail: [
    'Detail této rezervace',
    'Potvrď platbu',
    'Uprav termín rezervace',
    'Stornuj rezervaci',
  ],
  customers: [
    'Noví zákazníci tento měsíc',
    'VIP zákazníci',
    'Segmentace zákazníků',
    'Zablokovaní zákazníci',
  ],
  customer_detail: [
    'Historie rezervací tohoto zákazníka',
    'Odešli zprávu zákazníkovi',
    'Zablokuj/odblokuj zákazníka',
  ],
  finance: [
    'Finanční přehled měsíce',
    'Nezaplacené faktury',
    'Přehled tržeb',
    'Párování dodacích listů s fakturami',
  ],
  service: [
    'Blížící se servisy (30 dní)',
    'Aktivní servisní objednávky',
    'Vytvoř servisní objednávku',
    'Stav skladu náhradních dílů',
  ],
  eshop: [
    'Nové objednávky',
    'Změň stav objednávky',
    'Vytvoř promo kód',
    'Přehled produktů',
  ],
  sos: [
    'Aktivní SOS incidenty',
    'Nevyřešené incidenty',
    'Přiřaď technika k incidentu',
  ],
  employees: [
    'Přehled docházky tento týden',
    'Naplánuj směny na příští týden',
    'Nevyřízené žádosti o dovolenou',
  ],
  government: [
    'STK které brzy expirují',
    'Přehled pojistek',
    'Celkové náklady na pojistky',
  ],
  promos: [
    'Aktivní promo kódy',
    'Aktivní vouchery',
    'Vytvoř nový promo kód',
  ],
  messages: [
    'Nepřečtené zprávy',
    'Otevřená vlákna',
  ],
  cms: [
    'Feature flagy',
    'App nastavení',
    'Změň header banner',
  ],
  analyza: [
    'Výkon poboček',
    'Ranking motorek',
    'Optimální složení flotily',
    'Prognóza tržeb na 3 měsíce',
  ],
  inventory: [
    'Nízké zásoby',
    'Pohyby na skladě',
  ],
}
