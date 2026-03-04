import Card from '../components/ui/Card'

const MODULES = {
  '/flotila': { title: 'Flotila', icon: '🏍️', features: ['Přehled strojů', 'Stav a lokace', 'Údržba', 'Dokumenty', 'Fotogalerie', 'Pojištění', 'STK', 'Odpisy'] },
  '/rezervace': { title: 'Rezervace', icon: '📅', features: ['Kalendář', 'Nové rezervace', 'Správa termínů', 'Storno', 'Kauce', 'Předávací protokol', 'Cenové balíčky'] },
  '/zakaznici': { title: 'CRM — Zákazníci', icon: '👥', features: ['Databáze', 'Historie pronájmů', 'Reliability skóre', 'Blacklist / VIP', 'Gear velikosti', 'Doklady a ŘP', 'Segmentace'] },
  '/finance': { title: 'Finance', icon: '💰', features: ['Tržby', 'Náklady', 'Zisk', 'Cashflow', 'Faktury', 'Kauce', 'Přehledy'] },
  '/ucetnictvi': { title: 'Účetnictví', icon: '📒', features: ['Výsledovka', 'Rozvaha', 'DPH', 'Daň z příjmu', 'Kontrolní hlášení', 'EPO export'] },
  '/dokumenty': { title: 'Dokumenty', icon: '📄', features: ['Šablony', 'Smlouvy', 'Faktury', 'Předávací protokoly', 'GDPR', 'VOP', 'Auto-generace'] },
  '/sklady': { title: 'Sklady', icon: '📦', features: ['Příslušenství', 'Spotřební materiál', 'Minimum zásoby', 'Objednávky', 'Inventura'] },
  '/servis': { title: 'Servis', icon: '🔧', features: ['Plánované servisy', 'Historie oprav', 'Náklady', 'Dodavatelé', 'Záruky'] },
  '/zpravy': { title: 'Zprávy', icon: '💬', features: ['Web chat', 'WhatsApp', 'E-mail', 'Instagram DM', 'FB Messenger', 'SMS', 'AI auto-reply', 'Šablony'] },
  '/cms': { title: 'Web CMS', icon: '🌐', features: ['Editace textů', 'Editace cen', 'SEO', 'Promo bannery', 'Slevové kódy', 'Feature toggles'] },
  '/statistiky': { title: 'Statistiky & Predikce', icon: '📊', features: ['KPI dashboard', 'Heatmapy poptávky', 'Sezónní trendy', 'Prediktivní modely', 'Export'] },
  '/nakupy': { title: 'Nákupy & Plánování', icon: '🛒', features: ['Auto-objednávky', 'Schvalování', 'Dodavatelé', 'Historie', 'Budget tracking'] },
  '/statni-sprava': { title: 'Státní správa', icon: '🏛️', features: ['DPH přiznání', 'Kontrolní hlášení', 'Daň z příjmu PO', 'Datové schránky', 'ARES', 'EPO export'] },
  '/ai-copilot': { title: 'AI Copilot', icon: '🤖', features: ['Analýza flotily', 'Generování reportů', 'Predikce poptávky', 'Cenová optimalizace', 'Odpovědi zákazníkům'] },
}

export default function Placeholder() {
  const path = window.location.pathname
  const module = MODULES[path] || { title: 'Modul', icon: '📋', features: ['Připravujeme'] }

  return (
    <Card style={{ textAlign: 'center', padding: 40 }}>
      <div className="text-6xl mb-3">{module.icon}</div>
      <h2 className="text-xl font-black mb-2" style={{ color: '#0f1a14' }}>
        {module.title}
      </h2>
      <p className="text-[13px] font-medium mb-5" style={{ color: '#8aab99' }}>
        Modul připravený pro backend
      </p>
      <div className="flex flex-wrap gap-2 justify-center">
        {module.features.map((f, i) => (
          <div
            key={i}
            className="text-xs font-bold"
            style={{
              padding: '7px 16px',
              background: '#f1faf7',
              borderRadius: 50,
              color: '#4a6357',
              border: '1px solid #d4e8e0',
            }}
          >
            {f}
          </div>
        ))}
      </div>
    </Card>
  )
}
