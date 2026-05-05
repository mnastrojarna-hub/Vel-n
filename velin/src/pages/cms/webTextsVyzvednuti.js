// Texty webu: Vyzvednutí + Co v ceně + Dokumenty
// Klíče odpovídají PHP `siteContent('jak_pujcit_vyzvednuti'/'jak_pujcit_cena'/'jak_pujcit_dokumenty')`.

const range = n => Array.from({ length: n });

export const PAGE_VYZVEDNUTI = {
  id: 'vyzvednuti', label: 'Vyzvednutí', icon: '🔑', url: '/jak-pujcit/vyzvednuti',
  description: 'Jak probíhá vyzvednutí motorky, kde, provozní doba, co si vzít, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.h1', label: 'H1 nadpis', default: 'Vyzvednutí motocyklu – rychle, jednoduše a nonstop' },
        { key: 'web.jak_pujcit_vyzvednuti.intro', label: 'Úvodní text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'top_cta', label: 'Horní CTA box', location: 'Zelený CTA box pod intrem',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.top_cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.top_cta.text', label: 'Text', type: 'textarea', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.top_cta.button.label', label: 'Tlačítko — text', default: '' },
      ]
    },
    {
      id: 'place', label: 'Kde probíhá vyzvednutí', location: 'Sekce s adresou, provozní dobou',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.place.title', label: 'Nadpis sekce', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.place.address', label: 'Adresa', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.place.hours_label', label: 'Štítek provozní doby', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.place.hours', label: 'Provozní doba', type: 'textarea', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.place.note', label: 'Poznámka', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'process', label: 'Jak probíhá převzetí (kroky)', location: 'Grid karet s kroky',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.process.title', label: 'Nadpis sekce', default: '' },
        ...range(8).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vyzvednuti.process.steps.${i}.title`, label: `Krok ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vyzvednuti.process.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'amenities', label: 'Co u nás najdeš', location: 'Vybavení provozovny',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.amenities.title', label: 'Nadpis', default: '' },
        ...range(8).map((_, i) => ({
          key: `web.jak_pujcit_vyzvednuti.amenities.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'bring', label: 'Co si vzít s sebou', location: 'Seznam dokumentů a věcí',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.bring.title', label: 'Nadpis', default: '' },
        ...range(6).map((_, i) => ({
          key: `web.jak_pujcit_vyzvednuti.bring.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'faq', label: 'FAQ', location: 'Časté dotazy',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.faq.title', label: 'Nadpis sekce', default: '' },
        ...range(4).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vyzvednuti.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.jak_pujcit_vyzvednuti.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'mid_cta', label: 'Prostřední CTA box', location: 'Mezi sekcemi',
      fields: [
        { key: 'web.jak_pujcit_vyzvednuti.mid_cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vyzvednuti.mid_cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
  ]
}

export const PAGE_CO_V_CENE = {
  id: 'co-v-cene', label: 'Co je v ceně', icon: '💎', url: '/jak-pujcit/co-v-cene',
  description: 'Přehled co je v ceně pronájmu: výbava, benefity, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a intro',
      fields: [
        { key: 'web.jak_pujcit_cena.h1', label: 'H1', default: 'Co je v ceně pronájmu motorky' },
        { key: 'web.jak_pujcit_cena.intro', label: 'Intro', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'gear_basic', label: 'Základní výbava (zdarma)', location: 'Levý sloupec',
      fields: [
        { key: 'web.jak_pujcit_cena.gear.basic.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_cena.gear.basic.lead', label: 'Úvodní věta', type: 'textarea', default: '' },
        ...range(8).map((_, i) => ({
          key: `web.jak_pujcit_cena.gear.basic.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
        { key: 'web.jak_pujcit_cena.gear.basic.note1', label: 'Poznámka 1', type: 'textarea', default: '' },
        { key: 'web.jak_pujcit_cena.gear.basic.note2', label: 'Poznámka 2', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'gear_extra', label: 'Nadstandardní výbava (příplatek)', location: 'Pravý sloupec — nahoře',
      fields: [
        { key: 'web.jak_pujcit_cena.gear.extra.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_cena.gear.extra.lead', label: 'Úvodní věta', type: 'textarea', default: '' },
        ...range(8).map((_, i) => ({
          key: `web.jak_pujcit_cena.gear.extra.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'gear_services', label: 'Doplňkové služby', location: 'Pravý sloupec — dole',
      fields: [
        { key: 'web.jak_pujcit_cena.gear.services.title', label: 'Nadpis', default: '' },
        ...range(6).map((_, i) => ({
          key: `web.jak_pujcit_cena.gear.services.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'benefits', label: 'Další výhody (boxy)', location: 'Ikonové boxy pod výbavou',
      fields: [
        { key: 'web.jak_pujcit_cena.benefits.title', label: 'Nadpis sekce', default: '' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.jak_pujcit_cena.benefits.items.${i}.title`, label: `Box ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_cena.benefits.items.${i}.text`, label: `Box ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'faq', label: 'FAQ', location: 'Časté dotazy',
      fields: [
        { key: 'web.jak_pujcit_cena.faq.title', label: 'Nadpis', default: '' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.jak_pujcit_cena.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.jak_pujcit_cena.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.jak_pujcit_cena.cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_cena.cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
  ]
}

export const PAGE_DOKUMENTY = {
  id: 'dokumenty', label: 'Dokumenty', icon: '📑', url: '/jak-pujcit/dokumenty',
  description: 'Nájemní smlouva, podmínky, platby, užívání, předání, GDPR.',
  sections: [
    {
      id: 'intro', label: 'Úvod', location: 'H1 a úvodní odstavec',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.h1', label: 'H1', default: 'Nájemní smlouva a kauce – férové podmínky bez zálohy' },
        { key: 'web.jak_pujcit_dokumenty.intro', label: 'Intro', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'top_cta', label: 'Horní CTA', location: 'CTA box pod intrem',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.top_cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_dokumenty.top_cta.text', label: 'Text', type: 'textarea', default: '' },
        { key: 'web.jak_pujcit_dokumenty.top_cta.button.label', label: 'Tlačítko', default: '' },
      ]
    },
    {
      id: 'summary', label: 'Shrnutí (boxy)', location: 'Hlavní body smlouvy',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.summary.title', label: 'Nadpis sekce', default: '' },
        ...range(6).flatMap((_, i) => ([
          { key: `web.jak_pujcit_dokumenty.summary.items.${i}.title`, label: `Box ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_dokumenty.summary.items.${i}.text`, label: `Box ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'required_docs', label: 'Co potřebujete (doklady)', location: 'Seznam dokumentů',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.required_docs.title', label: 'Nadpis', default: '' },
        ...range(5).map((_, i) => ({
          key: `web.jak_pujcit_dokumenty.required_docs.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'payments', label: 'Platby a storno', location: 'Tabulka plateb',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.payments.title', label: 'Nadpis', default: '' },
        ...range(8).flatMap((_, i) => ([
          { key: `web.jak_pujcit_dokumenty.payments.items.${i}.title`, label: `Řádek ${i + 1} — název`, default: '' },
          { key: `web.jak_pujcit_dokumenty.payments.items.${i}.text`, label: `Řádek ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'usage', label: 'Pravidla užívání', location: 'Sekce s pravidly',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.usage.title', label: 'Nadpis', default: '' },
        ...range(8).map((_, i) => ({
          key: `web.jak_pujcit_dokumenty.usage.items.${i}`, label: `Pravidlo ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'handover', label: 'Předání a vrácení', location: 'Co očekávat při předání',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.handover.title', label: 'Nadpis', default: '' },
        ...range(6).map((_, i) => ({
          key: `web.jak_pujcit_dokumenty.handover.items.${i}`, label: `Bod ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'privacy', label: 'GDPR / Soukromí', location: 'Informace o ochraně dat',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.privacy.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_dokumenty.privacy.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'documents', label: 'Dokumenty ke stažení', location: 'Odkazy na PDF',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.documents.title', label: 'Nadpis', default: '' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.jak_pujcit_dokumenty.documents.items.${i}.label`, label: `Dokument ${i + 1} — název`, default: '' },
          { key: `web.jak_pujcit_dokumenty.documents.items.${i}.text`, label: `Dokument ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'midcta', label: 'Prostřední CTA', location: 'Mezi sekcemi',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.midcta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_dokumenty.midcta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'cta', label: 'Závěrečná CTA', location: 'CTA box dole',
      fields: [
        { key: 'web.jak_pujcit_dokumenty.cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_dokumenty.cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
  ]
}
