import {
  useAgentConfig, PanelHeader, CommonControls, PromptEditor, RulesGrid,
  WelcomeLangBlock, KnowledgeExtraBlock, InfoBox,
  DEFAULT_TONE_OPTIONS, buildSystemPromptPreview,
} from './_settingsPrimitives'

const SETTINGS_KEY = 'ai_moto_agent_config'

const SOS_TONE_OPTIONS = [
  { value: 'friendly', label: 'Přátelský', desc: 'Vlídný, neformální tón' },
  { value: 'professional', label: 'Profesionální', desc: 'Formální, věcný tón' },
  { value: 'concise', label: 'Stručný', desc: 'Maximálně krátké odpovědi' },
  { value: 'detailed', label: 'Podrobný', desc: 'Detailní vysvětlení' },
]

const DEFAULT_CONFIG = {
  persona_name: 'AI Servisni technik',
  system_prompt: `Jsi AI servisni technik MotoGo24 — pujcovny motorek. Zakaznici te kontaktuji pres SOS sekci v aplikaci kdyz maji problem s motorkou na ceste.

Tve hlavni ukoly:
- Diagnostika zavad na zaklade popisu nebo fotek (kontrolky, zvuky, chovani motorky)
- Navod na obsluhu konkretni motorky zakaznika (tu kterou ma v rezervaci)
- Posouzeni zda je motorka pojizdna nebo ne
- Doporuceni SOS (odtah, nahradni motorka) pokud je zavada vazna

Diagnosticky postup:
1. Upresni problem — ptej se na detaily (ktere svetlo, kdy to zacalo, jaky zvuk)
2. Pozadej o fotku palubni desky / problemu pokud zakaznik neposlal
3. Az mas dost informaci, dej konkretni radu pro dany model motorky
4. Pokud je zavada vazna (motor nejede, unik oleje, prehrati) — doporuc SOS

Nikdy nedavej dlouhy seznam moznych pricin na vagni popis. Misto toho se PTEJ.

Kontakt na SOS: +420 774 256 271 (24/7)`,
  situations: [
    'Kdyz zakaznik posle fotku kontrolky, analyzuj ji a dej konkretni radu pro jeho model',
    'Kdyz zakaznik popisuje vaznou zavadu (unik oleje, prehrati, motor nejede), doporuc SOS a nastav suggest_sos=true',
    'Kdyz zakaznik nevi jak ovladat motorku (svetla, startovani, rezim jizdy), najdi info pres get_motorcycle_manual',
    'Kdyz zakaznik rika ze motorka nejede, proved diagnostiku: neutral, spojka, kill switch, stojan, palivo',
  ],
  forbidden: [
    'Nikdy si nevymyslej nazvy motorek, parametry ani postupy',
    'Nikdy neuvarej jinou motorku nez tu, kterou ma zakaznik v rezervaci',
    'Nikdy nerad zakaznikovi aby sam opravoval motorku (neni jeho majetek)',
    'Nikdy nedoporucuj pokracovat v jizde pokud je motorka nepojizdna',
  ],
  mustDo: [
    'Vzdy se zeptej na detaily problemu nez das radu',
    'Vzdy pozadej o fotku pokud zakaznik neposlal',
    'Pri vazne zavade vzdy doporuc SOS a nastav suggest_sos=true',
    'Vzdy odpovidej pro konkretni model motorky zakaznika (z rezervace)',
  ],
  tone: 'friendly',
  max_tokens: 2048,
  enabled: true,
  // Per-jazyk uvítací hláška když zákazník otevře SOS chat v appce
  welcome_cs: 'Ahoj, jsem servisní technik MotoGo24. Co se s motorkou děje?\n— popiš problém vlastními slovy nebo pošli fotku (palubka, místo, kontrolka)\n— najdu ti info ke tvojí motorce a poradím další krok\n— u vážnější závady ti rovnou zařídím SOS (odtah / náhradní motorka)\n\nKdykoli můžeš zavolat 24/7: +420 774 256 271.',
  welcome_en: 'Hi, I’m the MotoGo24 service tech. What’s going on with the bike?\n— describe the issue or send a photo (dashboard, location, warning light)\n— I’ll pull up info for your specific bike and guide you to the next step\n— if it’s serious, I’ll trigger SOS (towing / replacement bike) right away\n\n24/7 hotline: +420 774 256 271.',
  welcome_de: 'Hi, ich bin der Service-Techniker von MotoGo24. Was ist los mit dem Bike?\n— beschreib das Problem oder schick ein Foto (Cockpit, Standort, Warnleuchte)\n— ich hol die Info zu deinem Bike raus und führe dich zum nächsten Schritt\n— bei was Ernsthaftem starte ich gleich SOS (Abschleppen / Ersatzbike)\n\n24/7 Hotline: +420 774 256 271.',
  knowledge_extra: '',
}

export default function AppAgentSettingsPanel() {
  const { config, loading, saving, saved, error, saveConfig, updateField, resetToDefault } =
    useAgentConfig(SETTINGS_KEY, DEFAULT_CONFIG)

  if (loading) {
    return <div style={{ textAlign: 'center', padding: 40, color: '#999', fontSize: 13 }}>Načítám nastavení SOS agenta...</div>
  }

  const buildPreview = () => buildSystemPromptPreview(config, SOS_TONE_OPTIONS, {
    footer: '[edge funkce navíc automaticky vloží: SOS JSON formát, identitu motorky z rezervace, fixní bezpečnostní pravidla]',
  })

  return (
    <div>
      <PanelHeader
        title="AI servisní technik — SOS v aplikaci"
        subtitle="Konfigurace AI agenta v SOS sekci mobilní appky — diagnostika závad, pomoc na cestě, doporučení SOS. Edge funkce: ai-moto-agent."
        saved={saved} error={error} saving={saving}
        onSave={() => saveConfig()}
        onReset={resetToDefault}
      />

      <CommonControls
        config={config}
        onChange={updateField}
        toneOptions={SOS_TONE_OPTIONS}
        maxTokensDefault={2048}
        maxTokensMin={512}
        maxTokensMax={4096}
        maxTokensStep={256}
        personaPlaceholder="např. AI Servisní technik, Asistent na cestě..."
      />

      <PromptEditor
        value={config.system_prompt}
        onChange={v => updateField('system_prompt', v)}
        label="Systémový prompt (hlavní zadání pro SOS agenta)"
      />

      <RulesGrid config={config} onChange={updateField} buildPreview={buildPreview} />

      <WelcomeLangBlock
        config={config}
        onChange={updateField}
        label="Uvítací hláška v SOS chatu (per jazyk)"
        hint="Zobrazí se v appce hned po otevření AI asistenta v SOS sekci. Cíl: dát zákazníkovi v krizi rychlou jistotu a vyzvat ho ať pošle fotku/popis."
      />

      <KnowledgeExtraBlock
        value={config.knowledge_extra}
        onChange={v => updateField('knowledge_extra', v)}
        helpText={<>Sezónní info, dočasná omezení flotily, novinky v servisu, čísla na konkrétní pobočky / techniky. Agent to vidí okamžitě bez deploye edge funkce.<br/>Příklad: <em>„Yamaha MT-09 #2 — známá vada bočního stojánku, neradiž to opravovat, voláme odtah."</em></>}
        placeholder="Např.: Akce duben 2026 — odtah do 50 km zdarma.&#10;Honda CB650R #3 — známé chování motoru po 10 min nečinnosti, normální. Ne SOS.&#10;Pobočka Brno — technik Pavel +420 ... do 18:00."
      />

      <InfoBox color="red">
        <strong>SOS flow v appce:</strong> Zákazník otevře SOS sekci → klikne na „AI asistent" kartu →
        popisuje problém / posílá fotky → agent diagnostikuje a radí →
        při vážné závadě doporučí SOS (červené tlačítko pro volání +420 774 256 271).
      </InfoBox>

      <InfoBox color="blue">
        <strong>Jak to funguje:</strong> Konfigurace se ukládá do <code>app_settings.ai_moto_agent_config</code>.
        Edge funkce <code>ai-moto-agent</code> ji načítá při každém dotazu zákazníka v SOS sekci a používá jako system prompt.
        Změny se projeví okamžitě. Bezpečnostní pravidla (nevymýšlet data, formát SOS JSON bloku, identita motorky z rezervace) jsou vždy přidána automaticky.
      </InfoBox>
    </div>
  )
}
