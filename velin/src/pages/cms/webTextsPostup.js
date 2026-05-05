// Texty webu: Postup půjčení + Přistavení
// Klíče MUSÍ odpovídat PHP `siteContent('jak_pujcit_postup')` resp. `siteContent('jak_pujcit_pristaveni')`
// → prefix `web.jak_pujcit_postup.*` resp. `web.jak_pujcit_pristaveni.*`,
// vnořené klíče se skládají přes setNested (např. process.steps.0.title).
export const PAGE_POSTUP = {
  id: 'postup', label: 'Postup půjčení', icon: '📝', url: '/jak-pujcit/postup',
  description: '12 kroků půjčení motorky krok za krokem + FAQ. Editace ve Velíně i inline na webu.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1, perex a podnadpis',
      fields: [
        { key: 'web.jak_pujcit_postup.h1', label: 'H1 nadpis', default: 'Postup půjčení motorky' },
        { key: 'web.jak_pujcit_postup.intro_p1', label: 'Úvodní text (1. odstavec)', type: 'textarea', default: 'V Motogo24 – půjčovna motorek na Vysočině je půjčení jednoduché, rychlé a férové.' },
        { key: 'web.jak_pujcit_postup.intro_h2', label: 'Podnadpis', default: 'Jak si půjčit motorku – půjčovna Motogo24 – Vysočina' },
        { key: 'web.jak_pujcit_postup.intro_p2', label: 'Úvodní text (2. odstavec)', type: 'textarea', default: 'V naší motopůjčovně zvládneš vše online: vyber motorku, zvol termín a vyplň rezervační formulář.' },
      ]
    },
    {
      id: 'process_title', label: 'Nadpis procesu', location: 'Nad gridem 12 karet',
      fields: [
        { key: 'web.jak_pujcit_postup.process.title', label: 'Nadpis sekce kroků', default: 'Jak probíhá pronájem krok za krokem' },
      ]
    },
    {
      id: 'steps', label: 'Kroky procesu (12 karet)', location: 'Grid 12 obrázkových karet — title + popis',
      fields: Array.from({ length: 12 }).flatMap((_, i) => ([
        { key: `web.jak_pujcit_postup.process.steps.${i}.title`, label: `Krok ${i + 1} — nadpis`, default: '' },
        { key: `web.jak_pujcit_postup.process.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
      ]))
    },
    {
      id: 'faq', label: 'FAQ (4 otázky)', location: 'Časté dotazy pod kroky',
      fields: Array.from({ length: 4 }).flatMap((_, i) => ([
        { key: `web.jak_pujcit_postup.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
        { key: `web.jak_pujcit_postup.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
      ]))
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva k akci',
      fields: [
        { key: 'web.jak_pujcit_postup.cta.title', label: 'Nadpis', default: 'Připraven na jízdu?' },
        { key: 'web.jak_pujcit_postup.cta.text', label: 'Text', type: 'textarea', default: 'Rezervuj si motorku online ještě dnes a užij si svobodu na dvou kolech.' },
      ]
    },
  ]
}

export const PAGE_PRISTAVENI = {
  id: 'pristaveni', label: 'Přistavení', icon: '🚚', url: '/jak-pujcit/pristaveni',
  description: 'Doručení motorky na domluvené místo: kdy se hodí, výhody, postup, ceník, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.h1', label: 'H1 nadpis', default: 'Přistavení motocyklu – doručení až k tobě' },
        { key: 'web.jak_pujcit_pristaveni.intro', label: 'Úvodní text', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'when', label: 'Kdy se přistavení hodí (4 položky)', location: 'Bulletový seznam pod intrem',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.when.title', label: 'Nadpis sekce', default: 'Kdy se přistavení hodí' },
        ...Array.from({ length: 4 }).map((_, i) => ({
          key: `web.jak_pujcit_pristaveni.when.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
      ]
    },
    {
      id: 'why', label: 'Proč přistavení (5 boxů)', location: 'Grid s 5 ikonovými boxy',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.why.title', label: 'Nadpis sekce', default: 'Proč využít přistavení motorky' },
        ...Array.from({ length: 5 }).flatMap((_, i) => ([
          { key: `web.jak_pujcit_pristaveni.why.items.${i}.title`, label: `Box ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_pristaveni.why.items.${i}.text`, label: `Box ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'process', label: 'Jak přistavení probíhá (10 kroků)', location: 'Grid s 10 ikonovými boxy',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.process.title', label: 'Nadpis sekce', default: 'Jak přistavení probíhá' },
        ...Array.from({ length: 10 }).flatMap((_, i) => ([
          { key: `web.jak_pujcit_pristaveni.process.steps.${i}.title`, label: `Krok ${i + 1} — titulek`, default: '' },
          { key: `web.jak_pujcit_pristaveni.process.steps.${i}.text`, label: `Krok ${i + 1} — popis`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'pricing', label: 'Ceník přistavení (3 položky + příklad)', location: 'Sekce s rozpadem ceny',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.pricing.title', label: 'Nadpis', default: 'Ceník přistavení' },
        { key: 'web.jak_pujcit_pristaveni.pricing.lead', label: 'Úvodní věta', type: 'textarea', default: '' },
        ...Array.from({ length: 3 }).map((_, i) => ({
          key: `web.jak_pujcit_pristaveni.pricing.items.${i}`, label: `Položka ${i + 1}`, type: 'textarea', default: ''
        })),
        { key: 'web.jak_pujcit_pristaveni.pricing.example', label: 'Příklad výpočtu', type: 'textarea', default: '' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (5 otázek)', location: 'Časté dotazy k přistavení',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.faq.title', label: 'Nadpis sekce', default: 'Často kladené dotazy k přistavení' },
        ...Array.from({ length: 5 }).flatMap((_, i) => ([
          { key: `web.jak_pujcit_pristaveni.faq.items.${i}.q`, label: `Otázka ${i + 1}`, default: '' },
          { key: `web.jak_pujcit_pristaveni.faq.items.${i}.a`, label: `Odpověď ${i + 1}`, type: 'textarea', default: '' },
        ])),
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.jak_pujcit_pristaveni.cta.title', label: 'Nadpis', default: 'Přistavení motorky – půjčovna motorek Vysočina' },
        { key: 'web.jak_pujcit_pristaveni.cta.text', label: 'Text', type: 'textarea', default: 'Motogo24 nabízí přistavení motocyklu po regionu i mimo něj. Nonstop provoz, bez kauce, výbava v ceně.' },
      ]
    },
  ]
}
