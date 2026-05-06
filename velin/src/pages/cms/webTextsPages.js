// Centrální index všech stránek webu pro textovou zprávu
import { PAGE_HOME } from './webTextsHome'
import { PAGE_KATALOG } from './webTextsKatalog'
import { PAGE_PUJCOVNA, PAGE_JAK_OVERVIEW } from './webTextsPujcovna'
import { PAGE_POSTUP, PAGE_PRISTAVENI } from './webTextsPostup'
import { PAGE_VYZVEDNUTI, PAGE_CO_V_CENE, PAGE_DOKUMENTY } from './webTextsVyzvednuti'
import { PAGE_VRACENI_PUJCOVNA, PAGE_VRACENI_JINDE } from './webTextsVraceni'
import { PAGE_KONTAKT, PAGE_POUKAZY, PAGE_REZERVACE } from './webTextsKontakt'
import { PAGE_UPRAVIT_REZERVACE } from './webTextsUpravit'
import { PAGE_KOSIK, PAGE_OBJEDNAVKA, PAGE_POTVRZENI } from './webTextsCheckout'
import { PAGE_LAYOUT } from './webTextsFaq'
// Pozn.: PAGE_FAQ byl odstraněn — FAQ má teď vlastní DB-driven UI
// (FaqSection.jsx → tabulka `faq_items`).

export const WEB_PAGES = [
  PAGE_HOME,
  PAGE_KATALOG,
  PAGE_PUJCOVNA,
  PAGE_JAK_OVERVIEW,
  PAGE_POSTUP,
  PAGE_PRISTAVENI,
  PAGE_VYZVEDNUTI,
  PAGE_VRACENI_PUJCOVNA,
  PAGE_VRACENI_JINDE,
  PAGE_CO_V_CENE,
  PAGE_DOKUMENTY,
  PAGE_POUKAZY,
  PAGE_KONTAKT,
  PAGE_REZERVACE,
  PAGE_UPRAVIT_REZERVACE,
  PAGE_KOSIK,
  PAGE_OBJEDNAVKA,
  PAGE_POTVRZENI,
  PAGE_LAYOUT,
]
