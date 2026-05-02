// Texty webu: Header / Footer (chrome).
// Pozn.: dříve tu bylo i `PAGE_FAQ` (ručně udržované Q&A pole),
// FAQ má teď vlastní DB-driven UI (`FaqSection.jsx` → tabulka `faq_items`).
export const PAGE_LAYOUT = {
  id: 'layout', label: 'Header & Footer', icon: '🧩', url: '(celý web)',
  description: 'Globální texty zobrazené na všech stránkách – hlavička a patička.',
  sections: [
    {
      id: 'header', label: 'Header (hlavička)', location: 'Horní lišta s logem, telefonem a menu',
      fields: [
        { key: 'web.layout.phone', label: 'Telefon', default: '+420 774 256 271' },
        { key: 'web.layout.logo.alt', label: 'Logo alt text', default: 'Půjčovna motorek Vysočina Motogo24' },
      ]
    },
    {
      id: 'footer', label: 'Footer (patička)', location: 'Dolní část webu na každé stránce',
      fields: [
        { key: 'web.layout.footer.intro', label: 'Úvodní text', type: 'textarea', default: 'Vítejte u Motogo24, vaší půjčovny motorek v Pelhřimově! Nabízíme pronájem motorek pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.' },
        { key: 'web.layout.footer.help', label: 'Nadpis pomoc', default: 'Potřebujete poradit?' },
        { key: 'web.layout.footer.social', label: 'Nadpis sociální sítě', default: 'Půjčovna motorek na sítích' },
        { key: 'web.layout.footer.hours', label: 'Provozní doba', default: 'PO - NE 00:00 – 24:00 (nonstop)' },
        { key: 'web.layout.footer.copy', label: 'Copyright', default: '© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena' },
      ]
    },
  ]
}
