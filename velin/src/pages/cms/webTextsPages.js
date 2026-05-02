// Centrální index všech stránek webu pro textovou zprávu
import { PAGE_HOME } from './webTextsHome'
import { PAGE_PUJCOVNA, PAGE_JAK_OVERVIEW } from './webTextsPujcovna'
import { PAGE_POSTUP, PAGE_PRISTAVENI } from './webTextsPostup'
import { PAGE_VYZVEDNUTI, PAGE_CO_V_CENE, PAGE_DOKUMENTY } from './webTextsVyzvednuti'
import { PAGE_KONTAKT, PAGE_POUKAZY, PAGE_REZERVACE } from './webTextsKontakt'
import { PAGE_LAYOUT } from './webTextsFaq'
// Pozn.: PAGE_FAQ byl odstraněn — FAQ má teď vlastní DB-driven UI
// (FaqSection.jsx → tabulka `faq_items`).

export const WEB_PAGES = [
  PAGE_HOME,
  PAGE_PUJCOVNA,
  PAGE_JAK_OVERVIEW,
  PAGE_POSTUP,
  PAGE_PRISTAVENI,
  PAGE_VYZVEDNUTI,
  PAGE_CO_V_CENE,
  PAGE_DOKUMENTY,
  PAGE_POUKAZY,
  PAGE_KONTAKT,
  PAGE_REZERVACE,
  PAGE_LAYOUT,
]
