// Combined tool definitions: 77 read (vč. univerzálního query_table + get_system_guide) + write tools
import { WRITE_TOOLS_DEFINITION } from './tools-def-write.ts';
const T = 'object';
const READ_TOOLS = [
  {
    name: 'get_bookings_summary',
    description: 'Počty rezervací podle stavu + tržby za aktuální a minulý měsíc',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_bookings_detail',
    description: 'Seznam rezervací s filtrem',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string',
          description: 'Filtr dle stavu'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        },
        date_from: {
          type: 'string',
          description: 'Od data (YYYY-MM-DD)'
        },
        date_to: {
          type: 'string',
          description: 'Do data (YYYY-MM-DD)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_fleet_overview',
    description: 'Všechny motorky se stavem, nájezdem, pobočkou',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string',
          description: 'Filtr dle stavu'
        },
        branch_id: {
          type: 'string',
          description: 'Filtr dle ID pobočky'
        }
      },
      required: []
    }
  },
  {
    name: 'get_motorcycle_detail',
    description: 'Detail jedné motorky + její rezervace a servis',
    input_schema: {
      type: T,
      properties: {
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky'
        },
        spz: {
          type: 'string',
          description: 'SPZ motorky'
        },
        model_search: {
          type: 'string',
          description: 'Hledání dle modelu'
        }
      },
      required: []
    }
  },
  {
    name: 'get_sos_incidents',
    description: 'SOS incidenty s detaily',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string',
          description: 'Filtr dle stavu'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_branches',
    description: 'Pobočky s počty motorek',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_customers',
    description: 'Přehled zákazníků',
    input_schema: {
      type: T,
      properties: {
        search: {
          type: 'string',
          description: 'Hledání dle jména/emailu'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_customer_detail',
    description: 'Kompletní profil zákazníka + rezervace + dokumenty',
    input_schema: {
      type: T,
      properties: {
        customer_id: {
          type: 'string',
          description: 'UUID zákazníka'
        },
        email: {
          type: 'string',
          description: 'Email'
        },
        name_search: {
          type: 'string',
          description: 'Hledání dle jména'
        }
      },
      required: []
    }
  },
  {
    name: 'get_financial_overview',
    description: 'Tržby, faktury, platby, vouchery',
    input_schema: {
      type: T,
      properties: {
        period: {
          type: 'string',
          description: 'Období: today/week/month/quarter'
        }
      },
      required: []
    }
  },
  {
    name: 'get_invoices',
    description: 'Seznam faktur',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string',
          description: 'Filtr dle stavu'
        },
        type: {
          type: 'string',
          description: 'Filtr dle typu'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_shop_orders',
    description: 'E-shop objednávky',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string',
          description: 'Filtr dle stavu'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_vouchers_and_promos',
    description: 'Aktivní vouchery a promo kódy',
    input_schema: {
      type: T,
      properties: {
        active_only: {
          type: 'boolean',
          description: 'Pouze aktivní (default true)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_service_status',
    description: 'Blížící se servisy + aktivní servisní objednávky',
    input_schema: {
      type: T,
      properties: {
        days_ahead: {
          type: 'number',
          description: 'Počet dní dopředu (default 30)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_messages_overview',
    description: 'Přehled zpráv se zákazníky',
    input_schema: {
      type: T,
      properties: {
        unread_only: {
          type: 'boolean',
          description: 'Pouze nepřečtené'
        },
        limit: {
          type: 'number',
          description: 'Max počet (default 20)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_daily_stats',
    description: 'Denní statistiky za období',
    input_schema: {
      type: T,
      properties: {
        days: {
          type: 'number',
          description: 'Počet dní zpět (default 7)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_inventory',
    description: 'Sklady — položky, zásoby, nízké stavy, dodavatelé',
    input_schema: {
      type: T,
      properties: {
        search: {
          type: 'string'
        },
        low_stock_only: {
          type: 'boolean'
        },
        category: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_inventory_movements',
    description: 'Pohyby skladu',
    input_schema: {
      type: T,
      properties: {
        item_id: {
          type: 'string'
        },
        type: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_branch_detail',
    description: 'Kompletní detail pobočky',
    input_schema: {
      type: T,
      properties: {
        branch_id: {
          type: 'string',
          description: 'UUID pobočky'
        }
      },
      required: [
        'branch_id'
      ]
    }
  },
  {
    name: 'get_documents',
    description: 'Dokumenty — smlouvy, šablony, vygenerované, e-maily',
    input_schema: {
      type: T,
      properties: {
        type: {
          type: 'string'
        },
        search: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_reviews',
    description: 'Hodnocení zákazníků',
    input_schema: {
      type: T,
      properties: {
        moto_id: {
          type: 'string'
        },
        min_rating: {
          type: 'number'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_cms_settings',
    description: 'CMS nastavení — feature flagy, proměnné, app_settings',
    input_schema: {
      type: T,
      properties: {
        section: {
          type: 'string'
        }
      },
      required: []
    }
  },
  {
    name: 'get_audit_log',
    description: 'Audit log — historie akcí adminů',
    input_schema: {
      type: T,
      properties: {
        admin_id: {
          type: 'string'
        },
        action: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_government_overview',
    description: 'Státní správa — STK termíny, pojistky celé flotily',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_sos_detail',
    description: 'Detail SOS incidentu včetně timeline',
    input_schema: {
      type: T,
      properties: {
        incident_id: {
          type: 'string'
        }
      },
      required: [
        'incident_id'
      ]
    }
  },
  {
    name: 'get_pricing_overview',
    description: 'Ceník — denní ceny motorek',
    input_schema: {
      type: T,
      properties: {
        motorcycle_id: {
          type: 'string'
        }
      },
      required: []
    }
  },
  {
    name: 'analyze_branch_performance',
    description: 'Analýza výkonnosti poboček',
    input_schema: {
      type: T,
      properties: {
        period_months: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'analyze_motorcycle_performance',
    description: 'Analýza výkonnosti motorek',
    input_schema: {
      type: T,
      properties: {
        period_months: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'analyze_category_demand',
    description: 'Analýza poptávky dle kategorie',
    input_schema: {
      type: T,
      properties: {
        period_months: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'analyze_optimal_fleet',
    description: 'Optimální složení flotily',
    input_schema: {
      type: T,
      properties: {
        branch_id: {
          type: 'string'
        },
        period_months: {
          type: 'number'
        }
      },
      required: [
        'branch_id'
      ]
    }
  },
  {
    name: 'analyze_customers',
    description: 'Analýza zákazníků — segmentace',
    input_schema: {
      type: T,
      properties: {
        period_months: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'forecast_predictions',
    description: 'Predikce tržeb a obsazenosti',
    input_schema: {
      type: T,
      properties: {
        months_ahead: {
          type: 'number'
        },
        branch_id: {
          type: 'string'
        }
      },
      required: []
    }
  },
  // HR tools
  {
    name: 'get_employees',
    description: 'Seznam zaměstnanců s pozicemi a mzdami',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_employee_detail',
    description: 'Detail zaměstnance — docházka, dovolená, směny, dokumenty, mzdy',
    input_schema: {
      type: T,
      properties: {
        employee_id: {
          type: 'string'
        }
      },
      required: [
        'employee_id'
      ]
    }
  },
  {
    name: 'get_attendance_overview',
    description: 'Přehled docházky za období',
    input_schema: {
      type: T,
      properties: {
        days: {
          type: 'number',
          description: 'Počet dní zpět (default 7)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_pending_vacations',
    description: 'Nevyřízené žádosti o dovolenou',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_shifts_overview',
    description: 'Přehled směn',
    input_schema: {
      type: T,
      properties: {
        days_ahead: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_payrolls',
    description: 'Přehled výplatních pásek',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  // Accounting tools
  {
    name: 'get_accounting_entries',
    description: 'Účetní záznamy',
    input_schema: {
      type: T,
      properties: {
        type: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_cash_register',
    description: 'Pokladna — záznamy a zůstatek',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_long_term_assets',
    description: 'Dlouhodobý majetek — vozidla, stroje, odpisy',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_short_term_assets',
    description: 'Krátkodobý majetek — materiál, zásoby, pohledávky',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_depreciation',
    description: 'Odpisy dlouhodobého majetku za rok',
    input_schema: {
      type: T,
      properties: {
        year: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_liabilities',
    description: 'Závazky — dodavatelé, daně, SP, ZP, mzdy',
    input_schema: {
      type: T,
      properties: {
        unpaid_only: {
          type: 'boolean'
        }
      },
      required: []
    }
  },
  {
    name: 'get_vat_returns',
    description: 'DPH přiznání — čtvrtletní přehledy',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_tax_returns',
    description: 'Daňová přiznání',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_tax_records',
    description: 'Daňové záznamy',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_flexi_reports',
    description: 'Výkazy z Abra Flexi — DPH, daně, rozvaha, výsledovka',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  // Extra tools
  {
    name: 'get_contracts',
    description: 'Smlouvy — nájemní, servisní, zaměstnanecké',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string'
        },
        contract_type: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_purchase_orders',
    description: 'Nákupní objednávky s položkami',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_booking_extras',
    description: 'Příslušenství k rezervaci + katalog',
    input_schema: {
      type: T,
      properties: {
        booking_id: {
          type: 'string'
        }
      },
      required: [
        'booking_id'
      ]
    }
  },
  {
    name: 'get_booking_complaints',
    description: 'Reklamace zákazníků',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_booking_cancellations',
    description: 'Storna rezervací s refundy',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_payment_methods',
    description: 'Uložené platební karty zákazníků',
    input_schema: {
      type: T,
      properties: {
        user_id: {
          type: 'string'
        }
      },
      required: []
    }
  },
  {
    name: 'get_service_parts',
    description: 'Díly potřebné pro servisní plány',
    input_schema: {
      type: T,
      properties: {
        schedule_id: {
          type: 'string'
        }
      },
      required: []
    }
  },
  {
    name: 'get_moto_locations',
    description: 'GPS pozice motorek',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_auto_order_rules',
    description: 'Pravidla automatických objednávek',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_notification_log',
    description: 'Log odeslaných notifikací',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_message_templates',
    description: 'Šablony SMS/email zpráv',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_accessory_types',
    description: 'Typy příslušenství (dynamické)',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_performance_stats',
    description: 'Výkonnostní statistiky motorek a poboček',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_suppliers',
    description: 'Seznam dodavatelů',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_delivery_notes',
    description: 'Dodací listy s párováním na faktury',
    input_schema: {
      type: T,
      properties: {
        unmatched_only: {
          type: 'boolean'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  // Analýza+ (návštěvnost, funnely, AI, aplikace, km, servisní plán, loyalty, trasy)
  {
    name: 'get_web_traffic',
    description: 'Návštěvnost webu motogo24.cz (visitor_log) — zdroje, země, zařízení, timeline, hodiny/dny',
    input_schema: {
      type: T,
      properties: {
        days: {
          type: 'number',
          description: 'Období zpět (default 30)'
        },
        host: {
          type: 'string',
          description: 'Filtr domény (motogo24.cz/.com/...)'
        },
        granularity: {
          type: 'string',
          description: 'day/week/month/year'
        }
      },
      required: []
    }
  },
  {
    name: 'get_web_funnel',
    description: 'Web rezervační funnel — konverze krok 1→platba→doklady, zařízení, časy vyplnění, odpady',
    input_schema: {
      type: T,
      properties: {
        days: {
          type: 'number',
          description: 'Období zpět (default 30)'
        }
      },
      required: []
    }
  },
  {
    name: 'get_ai_agents_analytics',
    description: 'AI konverzace a provoz — web widget, appka agent, AI traffic (crawleři/API), citace, rezervace přes AI',
    input_schema: {
      type: T,
      properties: {
        days: {
          type: 'number'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_app_stats',
    description: 'Mobilní aplikace — instalace, DAU/WAU/MAU, platformy, push, pády appky',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_km_analytics',
    description: 'Nájezd km z předávacích protokolů — per motorka i top zákazníci',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_service_plan',
    description: 'Servisní plán per motorka × typ (olej/pneu/komplet) — due_soon, overdue, odhad termínu',
    input_schema: {
      type: T,
      properties: {
        default_daily_km: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_loyalty_overview',
    description: 'Věrnostní program — úrovně 1-20, měsíční výherci, čerpání app slev',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  {
    name: 'get_routes_overview',
    description: 'Trasy a komunitní obsah — počty, návrhy ke schválení, recenze, body zájmu',
    input_schema: {
      type: T,
      properties: {},
      required: []
    }
  },
  // Provoz+ (detail rezervace, logistika, finanční události, komunikace, kiosk)
  {
    name: 'get_booking_detail',
    description: 'KOMPLETNÍ detail jedné rezervace — zákazník, motorka, slevy, výbava, faktury, storno, reklamace, door codes, protokol, doplatek',
    input_schema: {
      type: T,
      properties: {
        booking_id: {
          type: 'string',
          description: 'UUID rezervace'
        }
      },
      required: [
        'booking_id'
      ]
    }
  },
  {
    name: 'get_gear_logistics',
    description: 'Logistika výbavy — deficity (gear_shortages) + naskladnění (stock_receipts, chybějící DL)',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_financial_events',
    description: 'Finanční události (účetní pipeline) — stavy, výjimky, schvalovací fronta, Flexi sync chyby',
    input_schema: {
      type: T,
      properties: {
        status: {
          type: 'string'
        },
        event_type: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_message_log',
    description: 'Log odeslané komunikace (SMS/WhatsApp/email) + hromadné kampaně',
    input_schema: {
      type: T,
      properties: {
        channel: {
          type: 'string'
        },
        status: {
          type: 'string'
        },
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  {
    name: 'get_kiosk_status',
    description: 'Samoobslužné pobočky — kiosk zařízení online, FV elektrárna, otevření dveří',
    input_schema: {
      type: T,
      properties: {
        limit: {
          type: 'number'
        }
      },
      required: []
    }
  },
  // Univerzální — VŽDY dostupné
  {
    name: 'query_table',
    description: 'UNIVERZÁLNÍ čtení KTERÉKOLIV tabulky v DB (100+ tabulek) s filtry — použij, když neexistuje specializovaný nástroj. NIKDY neříkej, že k datům nemáš přístup.',
    input_schema: {
      type: T,
      properties: {
        table: {
          type: 'string',
          description: 'Název tabulky (public schema)'
        },
        columns: {
          type: 'string',
          description: 'Sloupce oddělené čárkou (default *)'
        },
        filters: {
          type: 'array',
          description: 'Filtry [{column, op: eq/neq/gt/gte/lt/lte/like/in/is_null/not_null, value}]',
          items: {
            type: 'object'
          }
        },
        order_by: {
          type: 'string'
        },
        ascending: {
          type: 'boolean'
        },
        limit: {
          type: 'number',
          description: 'Max 100 (default 20)'
        },
        count_only: {
          type: 'boolean',
          description: 'Vrátit jen počet řádků'
        }
      },
      required: [
        'table'
      ]
    }
  },
  {
    name: 'get_system_guide',
    description: 'ENCYKLOPEDIE + NÁVOD K OBSLUZE celého MotoGo24 — sekce Velína, web flow, mobilní appka, procesy (platby, storna, výměny, SOS, sklad), integrace, pojmy. Použij na KAŽDOU otázku „jak funguje / jak udělám / kde najdu".',
    input_schema: {
      type: T,
      properties: {
        topic: {
          type: 'string',
          description: 'Konkrétní téma (bez topic vrátí obsah)'
        },
        query: {
          type: 'string',
          description: 'Fulltext hledání v témách'
        }
      },
      required: []
    }
  }
];
export const TOOLS_DEFINITION = [
  ...READ_TOOLS,
  ...WRITE_TOOLS_DEFINITION
];
// Nástroje dostupné VŽDY, bez ohledu na zapnuté agenty (fallback + nápověda)
const ALWAYS_ON_TOOLS = [
  'query_table',
  'get_system_guide'
];
// Filter tools by enabled list
export function filterToolsByEnabled(enabledTools) {
  if (!enabledTools || enabledTools.length === 0) return TOOLS_DEFINITION;
  return TOOLS_DEFINITION.filter((t)=>enabledTools.includes(t.name) || ALWAYS_ON_TOOLS.includes(t.name));
}
