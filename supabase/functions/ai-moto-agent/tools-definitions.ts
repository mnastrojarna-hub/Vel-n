// ===== ai-moto-agent/tools-definitions.ts =====
// Tool definitions for Anthropic tool_use format

export const TOOLS = [
  {
    name: 'get_active_booking',
    description: 'Vrátí aktivní nebo nadcházející rezervaci zákazníka s kompletními detaily motorky. Volej jako první krok při každém dotazu, abys zjistil jakou motorku zákazník právě má.',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
  {
    name: 'get_booking_history',
    description: 'Vrátí všechny rezervace zákazníka (aktivní, dokončené, zrušené). Užitečné když se zákazník ptá na předchozí pronájmy.',
    input_schema: {
      type: 'object' as const,
      properties: {
        limit: {
          type: 'number',
          description: 'Maximální počet rezervací (default 10)',
        },
      },
      required: [],
    },
  },
  {
    name: 'get_motorcycle_manual',
    description: 'OTEVŘE A PŘEČTE skutečný návod konkrétní motorky (nahrané PDF i externí odkaz výrobce) a vrátí z něj relevantní pasáže + základní specifikace. Volej, když zákazník neví, jak motorku ovládat (světla, startování, režim jízdy), nebo se ptá na technické super-detaily (tlak v pneu, druh/množství oleje, význam kontrolek, servisní intervaly, pojistky, momenty). Odpovídej VÝHRADNĚ z toho, co tool vrátí — nedomýšlej. Zadej parametr query s tím, co v návodu hledáš.',
    input_schema: {
      type: 'object' as const,
      properties: {
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky (z výsledku get_active_booking) — preferovaný způsob identifikace',
        },
        brand: {
          type: 'string',
          description: 'Značka motorky (alternativa k motorcycle_id)',
        },
        model: {
          type: 'string',
          description: 'Model motorky (alternativa k motorcycle_id)',
        },
        query: {
          type: 'string',
          description: 'Co v návodu hledáš, česky (např. „tlak v pneumatikách", „startování", „kontrolka oleje", „přepnutí jízdního režimu"). Bez query vrátí zkrácený celý text návodu.',
        },
      },
      required: [],
    },
  },
  {
    name: 'search_troubleshooting',
    description: 'Hledá v troubleshooting databázi — diagnostika závad, kontrolky, postup při poruše. Volej když zákazník popisuje problém nebo se ptá na kontrolku.',
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'Popis problému nebo hledaný výraz (česky)',
        },
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky pro filtraci výsledků (volitelné)',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'get_fleet_overview',
    description: 'Vrátí přehled všech dostupných motorek ve flotile — značka, model, kategorie, objem motoru, ABS. Volej když se zákazník ptá na nabídku nebo srovnání.',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
]
