// Texty webu: Vrácení v půjčovně + Vrácení jinde
// Klíče odpovídají PHP `siteContent('jak_pujcit_vraceni_pujcovna')` a `siteContent('jak_pujcit_vraceni_jinde')`.

const range = n => Array.from({ length: n });

export const PAGE_VRACENI_PUJCOVNA = {
  id: 'vraceni-pujcovna', label: 'Vrácení v půjčovně', icon: '🏠', url: '/jak-pujcit/vraceni-pujcovna',
  description: 'Vrácení motorky v Pelhřimově: kdy, jak probíhá, problémy, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.h1', label: 'H1 nadpis', default: 'Vrácení motorky v půjčovně' },
        { key: 'web.jak_pujcit_vraceni_pujcovna.intro', label: 'Úvodní text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'process', label: 'Jak probíhá vrácení (kroky)', location: 'Grid kroků',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.process.title', label: 'Nadpis sekce', default: '' },
        ...range(8).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_pujcovna.process.steps.${i}.title`, label: `Krok ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vraceni_pujcovna.process.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'time', label: 'Kdy vracet', location: 'Sekce s časovými instrukcemi',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.time.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vraceni_pujcovna.time.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'issues', label: 'Co když nastane problém', location: 'Sekce řešení nečekaných situací',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.issues.title', label: 'Nadpis', default: '' },
        ...range(6).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_pujcovna.issues.items.${i}.title`, label: `Bod ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vraceni_pujcovna.issues.items.${i}.text`, label: `Bod ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'faq', label: 'FAQ (6 otázek)', location: 'Časté dotazy',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.faq.title', label: 'Nadpis sekce', default: '' },
        ...range(6).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_pujcovna.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.jak_pujcit_vraceni_pujcovna.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.jak_pujcit_vraceni_pujcovna.cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vraceni_pujcovna.cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
  ]
}

export const PAGE_VRACENI_JINDE = {
  id: 'vraceni-jinde', label: 'Vrácení jinde', icon: '🚛', url: '/jak-pujcit/vraceni-jinde',
  description: 'Vrácení motorky mimo Pelhřimov: kdy se hodí, výhody, postup, ceník, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.h1', label: 'H1 nadpis', default: 'Vrácení motorky kdekoli v ČR' },
        { key: 'web.jak_pujcit_vraceni_jinde.intro', label: 'Úvodní text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'when', label: 'Kdy se hodí (4 položky)', location: 'Bulletový seznam',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.when.title', label: 'Nadpis sekce', default: '' },
        ...range(4).map((_, i) => ({
          key: `web.jak_pujcit_vraceni_jinde.when.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'why', label: 'Proč vrátit jinde (5 boxů)', location: 'Grid s 5 ikonovými boxy',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.why.title', label: 'Nadpis sekce', default: '' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_jinde.why.items.${i}.title`, label: `Box ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vraceni_jinde.why.items.${i}.text`, label: `Box ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'process', label: 'Jak probíhá svoz (kroky)', location: 'Grid kroků',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.process.title', label: 'Nadpis sekce', default: '' },
        ...range(10).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_jinde.process.steps.${i}.title`, label: `Krok ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vraceni_jinde.process.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'pricing', label: 'Ceník svozu', location: 'Sekce s rozpadem ceny',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.pricing.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vraceni_jinde.pricing.lead', label: 'Úvodní věta', type: 'textarea', default: '' },
        ...range(3).map((_, i) => ({
          key: `web.jak_pujcit_vraceni_jinde.pricing.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
        { key: 'web.jak_pujcit_vraceni_jinde.pricing.example', label: 'Příklad výpočtu', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'issues', label: 'Co když problém', location: 'Řešení nečekaných situací',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.issues.title', label: 'Nadpis', default: '' },
        ...range(5).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_jinde.issues.items.${i}.title`, label: `Bod ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_vraceni_jinde.issues.items.${i}.text`, label: `Bod ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'faq', label: 'FAQ (10 otázek)', location: 'Časté dotazy',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.faq.title', label: 'Nadpis sekce', default: '' },
        ...range(10).flatMap((_, i) => ([
          { key: `web.jak_pujcit_vraceni_jinde.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.jak_pujcit_vraceni_jinde.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.jak_pujcit_vraceni_jinde.cta.title', label: 'Nadpis', default: '' },
        { key: 'web.jak_pujcit_vraceni_jinde.cta.text', label: 'Text', type: 'textarea', default: '' },
      ]
    },
  ]
}
