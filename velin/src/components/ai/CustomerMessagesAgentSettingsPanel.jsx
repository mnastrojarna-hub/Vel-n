import {
  useAgentConfig, PanelHeader, CommonControls, PromptEditor, RulesGrid,
  KnowledgeExtraBlock, InfoBox,
  DEFAULT_TONE_OPTIONS, buildSystemPromptPreview,
} from './_settingsPrimitives'

const SETTINGS_KEY = 'ai_customer_messages_config'

const CHANNELS = [
  { key: 'sms',       label: 'SMS',       icon: 'SMS', desc: 'Příchozí SMS od zákazníka' },
  { key: 'email',     label: 'E-mail',    icon: '@',   desc: 'Příchozí e-maily (Resend / IMAP)' },
  { key: 'whatsapp',  label: 'WhatsApp',  icon: 'WA',  desc: 'WhatsApp Business API' },
  { key: 'app_chat',  label: 'App chat',  icon: 'APP', desc: 'Chat ve Flutter aplikaci zákazníka' },
]

const MODES = [
  { value: 'suggest_only', label: 'Jen navrhuje (admin schvaluje)', desc: 'Agent vytvoří návrh, žádná odpověď neodejde, dokud ji admin ve Velíně neschválí. Tréninkový režim.' },
  { value: 'auto_send',    label: 'Plně automaticky (po natrénování)', desc: 'Agent odpovídá sám. Zapnout AŽ když je natrénovaný. Admin pořád může zasáhnout.' },
]

const DEFAULT_CONFIG = {
  persona_name: 'Lucka — správce zákaznických zpráv',
  system_prompt: `Jsi správce zákaznických zpráv MotoGo24 (půjčovna motorek, Mezná 9, 393 01 Pelhřimov). Tvým úkolem je na PŘÍCHOZÍ zprávu zákazníka navrhnout přesnou, lidskou a krátkou odpověď, kterou pak admin ve Velíně schválí, upraví nebo zamítne.

Tvoje role:
- Číst kontext zákazníka — rezervaci (motorka, datum, status platby, doklady), historii vlákna, SOS / reklamace, předchozí komunikaci.
- Navrhnout odpověď ve stejném jazyce a tónu, jakým zákazník píše. Krátce, věcně, bez AI frází.
- Identifikovat typ dotazu (dotaz na cenu/dostupnost / potvrzení rezervace / platba / doklady / vyzvednutí-vrácení / SOS / reklamace / obecná otázka).
- Zvolit formát vhodný pro daný kanál:
  * SMS — max ~320 znaků, jasná pointa, žádné dlouhé URL s parametry, bez podpisů typu „S pozdravem MotoGo24" (zbytečně žere znaky).
  * WhatsApp — krátké, lidské, smí emoji jen pokud zákazník píše s emoji.
  * E-mail — celá věta, případně strukturované, krátký podpis (jméno / firma).
  * App chat — stručné jako SMS, ale lze odkaz na hlubší stránku v appce.

Vždy:
- Zrcadli komunikační styl (tyká → tykej; vyká → vykej; krátká zpráva → krátká odpověď).
- Pokud nemáš dost dat na konkrétní odpověď, navrhni 1 doplňující otázku.
- U citlivých témat (peníze / refund / nehoda / právo / SOS) označ confidence=low a v poznámce pro admina napiš proč.

Nikdy:
- Nevymýšlej si konkrétní čísla (cena, datum, číslo rezervace, jméno) — vše z DB kontextu nebo se zeptej.
- Nezavírej rezervaci, neslibuj refund ani neoznamuj rozhodnutí o reklamaci — to rozhodne člověk.
- Neměň jazyk uprostřed odpovědi.
- Nedávej telefon (+420 774 256 271) ani e-mail firmy, pokud zákazník výslovně nechce mluvit s člověkem.
- Nepoužívej AI fráze („jako AI asistent…", „rád pomohu", „určitě, samozřejmě, rozumím").

Tvůj výstup je vždy NÁVRH. Admin má vždy poslední slovo.`,
  situations: [
    'Když zákazník píše poprvé bez kontextu („dobrý den, mám dotaz"), navrhni krátkou odpověď s otevřenou otázkou na konkrétní problém.',
    'Když zákazník urguje („proč ještě nic neslyším", „kde je platba"), zkontroluj historii a navrhni věcnou status-aktualizaci. Confidence=high jen pokud máš data.',
    'Když zákazník chce zrušit / přesunout rezervaci, navrhni zdvořilou odpověď s poznámkou pro admina (storno podmínky řeší člověk).',
    'Když zákazník hlásí problém s motorkou na cestě, NIKDY neradiž opravu. Navrhni odpověď s odkazem na SOS (+420 774 256 271) a označ confidence=high.',
    'Když zákazník píše v cizím jazyce, odpovídej ve stejném jazyce. Pokud je to jazyk, který firma nepokrývá (např. čínština), navrhni anglickou odpověď s krátkou omluvou.',
    'Když zákazník děkuje / chválí, navrhni krátkou lidskou odpověď bez marketingových frází.',
  ],
  forbidden: [
    'Nikdy si nevymýšlej cenu, datum, čísla rezervací — vše z kontextu DB.',
    'Nikdy neslibuj refund, výjimku ze storna ani jiné finanční rozhodnutí — označ pro admina.',
    'Nikdy nezveřejňuj interní údaje (kódy ke dveřím, čísla SPZ jiných motorek, jména jiných zákazníků).',
    'Nikdy nepřepínej jazyk uprostřed odpovědi.',
    'Nikdy nepoužívej dlouhé úvodní fráze („Dobrý den, děkujeme za vaši zprávu, vážíme si vás…") — rovnou věc.',
  ],
  mustDo: [
    'Vždy zrcadli ton (tyká/vyká, formální/neformální, krátké/delší).',
    'Vždy odpovídej ve stejném jazyce, ve kterém zákazník napsal poslední zprávu.',
    'Vždy uveď confidence (low/medium/high) a pro low krátký důvod, proč si admin musí dát pozor.',
    'Vždy respektuj limit kanálu (SMS 320 znaků, WA brief, email lze delší, app_chat krátké).',
    'Vždy ber data o zákazníkovi a rezervaci z kontextu, který ti edge funkce vloží.',
  ],
  tone: 'friendly',
  max_tokens: 600,
  enabled: false,
  channels: { sms: true, email: true, whatsapp: true, app_chat: true },
  mode: 'suggest_only',
  knowledge_extra: '',
}

function ChannelsCard({ config, onChange }) {
  const channels = config.channels || {}
  const toggle = (key) => onChange('channels', { ...channels, [key]: !channels[key] })
  return (
    <div style={{ marginBottom: 16, padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: '#0f1a14', marginBottom: 4 }}>Kanály, kde agent navrhuje odpovědi</div>
      <div style={{ fontSize: 11, color: '#666', marginBottom: 10, lineHeight: 1.4 }}>
        Vypni kanál, kde zatím nechceš, aby agent zasahoval. Vypnutý kanál Velín ve frontě zpráv ignoruje.
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 8 }}>
        {CHANNELS.map(ch => {
          const on = !!channels[ch.key]
          return (
            <button
              key={ch.key}
              type="button"
              onClick={() => toggle(ch.key)}
              style={{
                textAlign: 'left', padding: '10px 12px', borderRadius: 8, cursor: 'pointer',
                border: `2px solid ${on ? '#22c55e' : '#e5e7eb'}`,
                background: on ? '#f0fdf4' : '#fafafa',
                opacity: on ? 1 : 0.6,
                transition: 'all 0.15s',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 2 }}>
                <span style={{ fontSize: 12, fontWeight: 800, color: on ? '#166534' : '#666' }}>
                  <span style={{ display: 'inline-block', minWidth: 30, fontSize: 9, padding: '1px 5px', borderRadius: 4, background: on ? '#dcfce7' : '#e5e7eb', color: on ? '#166534' : '#666', marginRight: 6, fontWeight: 700 }}>{ch.icon}</span>
                  {ch.label}
                </span>
                <span style={{ fontSize: 10, color: on ? '#22c55e' : '#9ca3af', fontWeight: 700 }}>
                  {on ? 'ON' : 'OFF'}
                </span>
              </div>
              <div style={{ fontSize: 10, color: '#666', lineHeight: 1.3 }}>{ch.desc}</div>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function ModeCard({ config, onChange }) {
  const mode = config.mode || 'suggest_only'
  return (
    <div style={{ marginBottom: 16, padding: '12px 16px', borderRadius: 10, border: `2px solid ${mode === 'auto_send' ? '#dc2626' : '#fbbf24'}`, background: mode === 'auto_send' ? '#fef2f2' : '#fffbeb' }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: mode === 'auto_send' ? '#991b1b' : '#92400e', marginBottom: 8 }}>
        Režim práce {mode === 'auto_send' ? '— POZOR: AUTO ODESÍLÁNÍ' : '— Bezpečný (jen návrhy)'}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        {MODES.map(m => {
          const active = mode === m.value
          return (
            <button
              key={m.value}
              type="button"
              onClick={() => onChange('mode', m.value)}
              style={{
                textAlign: 'left', padding: '10px 12px', borderRadius: 8, cursor: 'pointer',
                border: `2px solid ${active ? (m.value === 'auto_send' ? '#dc2626' : '#22c55e') : '#e5e7eb'}`,
                background: active ? '#fff' : '#fafafa',
              }}
            >
              <div style={{ fontSize: 12, fontWeight: 800, color: active ? '#0f1a14' : '#666', marginBottom: 4 }}>
                {m.label}
              </div>
              <div style={{ fontSize: 10, color: '#555', lineHeight: 1.4 }}>{m.desc}</div>
            </button>
          )
        })}
      </div>
      {mode === 'auto_send' && (
        <div style={{ marginTop: 10, padding: '8px 10px', borderRadius: 6, background: '#fef2f2', border: '1px solid #fca5a5', fontSize: 11, color: '#991b1b' }}>
          <strong>Auto režim odesílá zprávy bez schválení.</strong> Zapínej až po důkladném natrénování v režimu „Jen navrhuje". Edge funkce stále loguje vše do <code>messages.ai_suggested_reply</code> + <code>ai_traffic_log</code>.
        </div>
      )}
    </div>
  )
}

export default function CustomerMessagesAgentSettingsPanel() {
  const { config, loading, saving, saved, error, saveConfig, updateField, resetToDefault } =
    useAgentConfig(SETTINGS_KEY, DEFAULT_CONFIG)

  if (loading) {
    return <div style={{ textAlign: 'center', padding: 40, color: '#999', fontSize: 13 }}>Načítám nastavení správce zpráv...</div>
  }

  const buildPreview = () => buildSystemPromptPreview(config, DEFAULT_TONE_OPTIONS, {
    footer: '[edge funkce ai-customer-messages-suggest navíc vloží: kontext zákazníka (rezervace, doklady, platby, historie vlákna), info o kanálu, dnešní datum, identitu firmy, fixní bezpečnostní pravidla]',
  })

  return (
    <div>
      <PanelHeader
        title="Správce zákaznických zpráv (SMS / e-mail / WhatsApp / app chat)"
        subtitle="Agent, který navrhuje odpověď na každou příchozí zprávu zákazníka. Admin ve Velíně Návrh schválí / upraví / zamítne. Po natrénování se přepne na auto."
        saved={saved} error={error} saving={saving}
        onSave={() => saveConfig()}
        onReset={resetToDefault}
      />

      <CommonControls
        config={config}
        onChange={updateField}
        toneOptions={DEFAULT_TONE_OPTIONS}
        maxTokensDefault={600}
        maxTokensMin={256}
        maxTokensMax={2048}
        maxTokensStep={128}
        personaPlaceholder="např. Lucka — správce zpráv MotoGo24"
      />

      <ChannelsCard config={config} onChange={updateField} />

      <ModeCard config={config} onChange={updateField} />

      <PromptEditor
        value={config.system_prompt}
        onChange={v => updateField('system_prompt', v)}
        label="Systémový prompt (jak má agent přemýšlet o příchozích zprávách)"
        minHeight={220}
      />

      <RulesGrid config={config} onChange={updateField} buildPreview={buildPreview} />

      <KnowledgeExtraBlock
        value={config.knowledge_extra}
        onChange={v => updateField('knowledge_extra', v)}
        helpText={<>Sezónní info, dočasná omezení, aktuální problémy ve flotile, info pro VIP. Agent to vidí okamžitě bez deploye edge funkce.<br/>Příklad: <em>„Tento týden zpoždění odpovědí na e-maily kvůli dovolené účetní — info zákazníkovi že odpovíme do 48h."</em></>}
        placeholder="Např.: 1.5.-3.5. zavřená kancelář, e-maily vyřizujeme s 2denní prodlevou.&#10;Reklamace #B-2026-04-XYZ — VŽDY eskalovat na Petru, neslibovat nic.&#10;Akce duben 2026 — naked motorky -20 %, voucher kód SPRING20."
      />

      <InfoBox color="amber">
        <strong>Tréninkový workflow:</strong>
        <ol style={{ margin: '4px 0 0 18px', padding: 0 }}>
          <li>Režim <strong>„Jen navrhuje"</strong> — agent generuje návrhy, admin je vidí ve Velíně u každé příchozí zprávy a klikne <em>Schválit / Upravit / Zamítnout</em>.</li>
          <li>Z editovaných / zamítnutých návrhů se učí (situations, forbidden, knowledge_extra ladíš tady).</li>
          <li>Když confidence agenta + procento schválených bez úprav stoupne nad rozumnou hranici (typicky &gt;90 % na daném kanálu), přepneš ten kanál v Channels OFF a v Mode na auto, případně jen pro vybrané typy zpráv (zatím jednoduše: Mode=auto se týká všech ON kanálů).</li>
        </ol>
      </InfoBox>

      <InfoBox color="blue">
        <strong>Jak to funguje:</strong> Konfigurace se ukládá do <code>app_settings.ai_customer_messages_config</code>.
        Edge funkce <code>ai-customer-messages-suggest</code> (pošle se v etapě 3) si při každé příchozí zprávě (nebo na vyžádání ze Velína) načte tuto konfiguraci a kontext zákazníka z DB (rezervace, historie zpráv, doklady, platby).
        Návrh ukládá do <code>messages.ai_suggested_reply</code> + status; až admin klikne „Schválit", existující edge fn <code>send-message</code> ho odešle správným kanálem.
        <br/><br/>
        Auditní stopa: každý vygenerovaný návrh + výsledek (schváleno / editováno / zamítnuto / odesláno) se loguje do <code>ai_traffic_log</code> (source=&apos;customer_messages&apos;).
      </InfoBox>
    </div>
  )
}
