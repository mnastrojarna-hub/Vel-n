// ===== ai-moto-agent/tools-definitions.ts =====
// Tool definitions for Anthropic tool_use format

import { PUBLIC_READ_TOOLS } from './public-tools.ts'

const APP_TOOLS = [
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
    description: 'OTEVŘE A PŘEČTE skutečný návod konkrétní motorky (nahrané PDF, externí odkaz výrobce i předpřipravený OCR text) a vrátí z něj relevantní pasáže + základní specifikace. Volej OKAMŽITĚ při PRVNÍ zmínce o kontrolce (query „kontrolky palubní deska") — z návodu zjistíš, jaké kontrolky stroj má, a doptáš se konkrétně. Dále když zákazník neví, jak motorku ovládat (světla, startování, režim jízdy), nebo se ptá na technické detaily (tlak v pneu, olej, servisní intervaly, pojistky, momenty). Hledání dle brand/model je TOLERANTNÍ (překlepy, pomlčky — „v strom" najde „V-strom"); když si zákazník není jistý modelem, stačí přibližný název. Odpovídej VÝHRADNĚ z toho, co tool vrátí — nedomýšlej.',
    input_schema: {
      type: 'object' as const,
      properties: {
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky (z výsledku get_active_booking nebo search_motorcycles) — preferovaný způsob identifikace. Alias `moto_id` funguje také.',
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
          description: 'Popis problému nebo hledaný výraz (česky). Bez čárek a závorek — prostá klíčová slova.',
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

// SOS servisní agent v appce má stejné MOŽNOSTI jako veřejný agent (search/cena/
// dostupnost/FAQ/policies/právní dokumenty/příslušenství/pobočky/promo) — jen
// netvoří ani neupravuje rezervace a není prodejce. App tooly (booking kontext +
// návod + troubleshooting) + převzaté informační tooly z ai-public-agent.
export const TOOLS = [...APP_TOOLS, ...PUBLIC_READ_TOOLS]
