// ===== _shared/agent-knowledge/snapshots.ts =====
// Přesunuto z ai-public-agent/index.ts (2026-09-25) beze změny obsahu — sdílí ho
// veřejný agent (web) i agent zákaznických zpráv ve Velínu (ai-customer-messages-suggest).

export type CompanyInfo = {
  name?: string
  ico?: string
  dic?: string | null
  address?: string
  phone?: string
  email?: string
  web?: string
  bank_account?: string
}

export type FleetMoto = {
  id: string
  brand: string | null
  model: string
  category: string | null
  license_required: string | null
  status?: string | null
  branch_id?: string | null
  branches?: { name?: string | null; type?: string | null } | null
  power_kw: number | null
  engine_cc: number | null
  weight_kg: number | null
  price_mon: number | null
  price_tue: number | null
  price_wed: number | null
  price_thu: number | null
  price_fri: number | null
  price_sat: number | null
  price_sun: number | null
}

export type BranchRow = {
  name: string | null
  address: string | null
  city: string | null
  zip: string | null
  type: string | null       // 'samoobslužná' | 'obslužná' (viz velin/src/pages/BranchModal.jsx)
  opening_hours: string | null
  notes: string | null
}

// Sestaví zobrazované jméno motorky bez duplikace značky.
// V DB mají některé řádky `model`, který už značku obsahuje (např. brand="Benelli",
// model="Benelli TRK 502 X") → naivní `${brand} ${model}` vyrobí "Benelli Benelli TRK 502 X"
// a agent to pak takhle zdvojeně předá zákazníkovi. Když model už začíná značkou, vrať jen model.
export function motoDisplayName(brand: string | null | undefined, model: string | null | undefined): string {
  const b = (brand || '').trim()
  const m = (model || '').trim()
  if (!b) return m
  if (!m) return b
  if (m.toLowerCase().startsWith(b.toLowerCase())) return m
  return `${b} ${m}`
}

export function formatFleetSnapshot(fleet: FleetMoto[]): string {
  if (!fleet || fleet.length === 0) {
    return `KOMPLETNÍ FLOTILA (live snapshot z DB):
- Žádné motorky v DB. NESLIBUJ ŽÁDNOU motorku — řekni zákazníkovi, že momentálně žádnou nepronajímáme, a doporuč kontakt firmy.`
  }
  const fmtLine = (m: FleetMoto, i: number, extra = ''): string => {
    const name = motoDisplayName(m.brand, m.model)
    const cat = m.category || '—'
    const lic = m.license_required || '—'
    const kw = m.power_kw ? `${m.power_kw} kW` : '— kW'
    const cc = m.engine_cc ? `${m.engine_cc} ccm` : '— ccm'
    const br = m.branches?.name
      ? `, pobočka ${m.branches.name}${m.branches.type ? ` (${m.branches.type})` : ''}`
      : ''
    return `${i + 1}. **${name}** [id=${m.id}] — kat. ${cat}, ŘP ${lic}, ${cc}, ${kw}${br}${extra}`
  }
  const active = fleet.filter((m) => !m.status || m.status === 'active')
  const inService = fleet.filter((m) => m.status === 'maintenance' || m.status === 'unavailable')
  const lines = active.map((m, i) => fmtLine(m, i, ', ceník dle dne v týdnu (zjistíš přes `calculate_price` pro konkrétní termín)'))
  const serviceLines = inService.map((m, i) =>
    fmtLine(m, i, m.status === 'maintenance' ? ' — V SERVISU' : ' — DOČASNĚ MIMO NABÍDKU'))
  const serviceBlock = inService.length === 0 ? '' : `

STROJE FLOTILY DOČASNĚ MIMO NABÍDKU (v servisu / mimo provoz — MÁME je, jen teď nejdou rezervovat):
${serviceLines.join('\n')}
- Tyto stroje ve flotile EXISTUJÍ — NIKDY netvrď, že je nemáme, a NIKDY se za jejich zmínku dodatečně neomlouvej. Správná odpověď: „máme, ale momentálně je v servisu / dočasně mimo nabídku" + nabídni alternativu z aktivního seznamu výše, pozdější termín, nebo (u dárků) poukaz — ten platí 3 roky a obdarovaný si stroj vybere, až bude zpět v nabídce.
- Přesný termín návratu do nabídky neznáš — neslibuj konkrétní datum, dokud ho nepotvrdí půjčovna.`
  return `KOMPLETNÍ FLOTILA (live snapshot z DB v okamžiku tohoto requestu, ${active.length} aktivních motorek — JEDINÝ AUTORITATIVNÍ SEZNAM; + ${inService.length} dočasně mimo nabídku níže):
${lines.join('\n')}${serviceBlock}

PRAVIDLA NAD TÍMTO SEZNAMEM (BEZPODMÍNEČNÁ):
- Pokud zákazník zmíní značku/model, který NENÍ v žádném z výše uvedených seznamů (ani jako substring v "brand model") — řekni rovně "tuhle motorku momentálně nemáme" a nabídni ALTERNATIVU ze seznamu (stejná kategorie nebo skupina ŘP).
- Pokud zákazník zmíní značku/model, který V seznamu JE — NIKDY neřekni "nemáme". Vždy potvrď, že máme, a pokračuj přes \`search_motorcycles\` (s brand/model_query a available_on/from/to) pro ověření dostupnosti v termínu + \`calculate_price\` pro cenu.
- Pro doporučení ("co máte na A2", "něco do hor", "naked", …) volej \`search_motorcycles\` s odpovídajícími filtry — ten respektuje filtraci dostupnosti. NIKDY nevybírej z paměti modely, které tu nejsou v seznamu.
- CENU NIKDY NEUVÁDÍŠ JAKO „od X Kč/den" — zákazníka „od" ceny nezajímá a zní to jako nalákání. Když zákazník zmíní termín nebo den, MUSÍŠ rovnou zavolat \`calculate_price\` (po předchozím \`get_availability\`) a sdělit přesnou částku za konkrétní den nebo období. Pokud termín ještě nemáš, požádej o něj jednou větou — neotevírej cenu, dokud termín neznáš.
- Cenu, dostupnost a kompletní specs konkrétního kusu řeš VÝHRADNĚ přes tooly (\`calculate_price\`, \`get_availability\`, \`search_motorcycles\`). Tento seznam je orientace co existuje, ne ceník.
- „JE V SERVISU" JEN PODLE SKUTEČNOSTI A DATUMŮ: že je motorka v servisu, smíš tvrdit VÝHRADNĚ když (a) je v sekci „mimo nabídku" výše (aktuální stav DB), NEBO (b) dnešek či zákazníkem požadovaný den spadá do servisního bloku ze \`get_availability\` (\`service_blocks\`, rozsah from–to). Budoucí PLÁNOVANÝ servis (např. zimní) NIKDY nevydávej za „je v servisu" — do jeho začátku je stroj normálně dostupný a rezervovatelný; správná formulace: „v termínu od–do má plánovaný servis, do té doby je k dispozici". Stroj z aktivního seznamu výše NIKDY neoznač za „v servisu" bez ověření datumů přes \`get_availability\`.
- Tento seznam je generován z DB při každém requestu — pokud uživatel tvrdí "měli jste tam Hondu", ale Honda v seznamu výše není, znamená to, že už ji nemáme. Reaguj profesionálně, neslibuj a nabídni alternativu.
- TYP STROJE (skútr, naked, cestovní, supermoto, dětská…) ŘEŠ VÝHRADNĚ PODLE TOHOTO SEZNAMU, NE z paměti. Když se zákazník zeptá „máte skútry / cestovky / …", podívej se na pole „kat." u položek výše: je-li tam aspoň jeden kus dané kategorie (skútr = kat. „scootery"), MÁME ho — potvrď a nabídni ho. Není-li tam žádný, řekni rovně, že tu kategorii teď nemáme. NIKDY netvrď paušálně „skútry nepronajímáme" — to platí jen tehdy, když v seznamu výše opravdu žádný skútr není.
- ZÁKAZ PROTIŘEČENÍ: co v jedné větě potvrdíš, nesmíš v další popřít. Když skútr (nebo jakákoli kategorie) v seznamu výše JE, drž se toho — že ho máme.`
}

export function formatBranchesSnapshot(branches: BranchRow[]): string {
  if (!branches || branches.length === 0) {
    return `POBOČKY (live snapshot z DB): snapshot se nepodařilo načíst — na dotazy o pobočkách zavolej \`get_branches\` a řiď se výhradně jeho výsledkem. NIKDY zákazníkovi netvrď, že žádné pobočky nemáme nebo že je seznam v databázi prázdný — když i tool vrátí prázdno/chybu, pošli ho na adresu firmy z FIREMNÍCH ÚDAJŮ (hlavní výdejní místo) a nabídni telefon/e-mail.`
  }
  const lines = branches.map((b, i) => {
    const addr = [b.address, `${b.zip || ''} ${b.city || ''}`.trim()].filter(Boolean).join(', ')
    const typ = b.type === 'samoobslužná'
      ? 'SAMOOBSLUŽNÁ (výdej i vrácení 24/7 přístupovým kódem, doklady se ověřují předem online)'
      : b.type === 'obslužná'
        ? 'OBSLUŽNÁ (motorku předává a přebírá OBSLUHA osobně, čas dle otevírací doby / domluvy — NENÍ to samoobslužný výdej kódem. Přístupové kódy z e-mailu tu ale zákazník DOSTÁVÁ taky a NEJSOU omyl: slouží jako IDENTIFIKACE — při převzetí je řekne obsluze, ta podle nich rezervaci dohledá a zákazníka ověří. Sken/foto dokladů předem není povinný, ale DOPORUČUJE se: kdo si vše vyřídí předem, má vše připravené, u obsluhy jen nahlásí kódy a předání zabere ~2 minuty — zvlášť když odjíždí víc motorek najednou)'
        : `typ neuveden — režim výdeje ověř přes \`get_branches\`/firmu, netvrď samoobsluhu`
    const oh = b.opening_hours ? `; otevírací doba: ${b.opening_hours}` : ''
    const notes = b.notes ? `; pozn.: ${b.notes}` : ''
    return `${i + 1}. **${b.name || addr || 'pobočka'}** — ${addr || 'adresa v `get_branches`'} — ${typ}${oh}${notes}`
  })
  return `POBOČKY (live snapshot z DB v okamžiku tohoto requestu — JEDINÝ AUTORITATIVNÍ zdroj o REŽIMU výdeje/vrácení):
${lines.join('\n')}

PRAVIDLA NAD TÍMTO SEZNAMEM (BEZPODMÍNEČNÁ):
- Režim výdeje a vrácení (samoobslužně kódem 24/7 vs. předání s obsluhou) říkej VÝHRADNĚ podle typu KONKRÉTNÍ pobočky výše. NIKDY netvrď paušálně „výdej je samoobslužný a nonstop" — platí to JEN pro pobočku typu SAMOOBSLUŽNÁ.
- Přístupové kódy chodí e-mailem ke KAŽDÉ rezervaci bez ohledu na typ pobočky — NIKDY netvrď, že zákazník s rezervací na OBSLUŽNÉ pobočce kódy nedostane, že jde o omyl nebo o „jiný kód" (reálný incident 2026-08-23: agent v Mezné kódy popřel a pak se zmateně opravoval). Liší se jen POUŽITÍ kódů: u SAMOOBSLUŽNÉ pobočky otvírají dveře/box 24/7; u OBSLUŽNÉ nic neotvírají — jsou to IDENTIFIKAČNÍ kódy: zákazník je při převzetí řekne obsluze, ta podle nich rezervaci dohledá a identifikuje ho, nic dalšího netřeba a za ~2 minuty odjíždí. Sken/foto dokladů předem tam není povinný, ale DOPORUČ ho: urychlí odbavení (zvlášť když odjíždí víc motorek najednou) — zákazník si tak vše vyřídí sám předem a na místě jen nahlásí kódy.
- Rezervaci lze VYTVOŘIT kdykoliv 24/7 bez ohledu na typ pobočky — to s režimem výdeje nezaměňuj.
- Zákazník BEZ rezervace (i hypotetický dotaz „kdybych si zarezervoval, kde si motorku vyzvednu?", „kde jste", „kde je pobočka"): odpověz ROVNOU adresou pobočky z tohoto seznamu — vyzvednutí probíhá na pobočce (je-li jich víc, volí se při rezervaci). NIKDY netvrď, že seznam poboček je prázdný, že adresa bude až v rezervaci, nebo že informace není dostupná.
- GPS, telefon a detail pobočky nad rámec snapshotu → \`get_branches\`.`
}
