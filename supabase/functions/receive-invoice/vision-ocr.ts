// ===== receive-invoice/vision-ocr.ts =====
// Claude Vision OCR call + prompt definition

export const VISION_PROMPT = `Jsi účetní a právní asistent české malé firmy (půjčovna motorek, neplátce DPH).
Přečti dokument a vrať POUZE JSON, žádný markdown, žádný text navíc.
{
  "document_type": "invoice|proforma|receipt|contract_purchase|contract_loan|contract_employment|contract_service|delivery_note|insurance|leasing|other",
  "source_language": null,
  "currency": null,
  "supplier_name": null,
  "supplier_name_cs": null,
  "supplier_ico": null,
  "supplier_dic": null,
  "supplier_address": null,
  "supplier_bank_account": null,
  "invoice_number": null,
  "variable_symbol": null,
  "amount_czk": null,
  "issue_date": null,
  "due_date": null,
  "received_date": null,
  "payment_method": "bank_transfer|cash|card|null",
  "line_items": [{ "description": null, "description_cs": null, "quantity": null, "unit_price": null, "amount": null, "size": null, "color": null, "sku_suggestion": null, "category_suggestion": null }],
  "asset_classification": {
    "type": "dlouhodoby_majetek|kratkodoby_majetek|zbozi|drobna_rezie|sluzba|material|null",
    "depreciation_group": null,
    "depreciation_years": null,
    "depreciation_method": "accelerated|linear|null",
    "asset_name": null
  },
  "loan": {
    "provider": null,
    "contract_number": null,
    "principal_czk": null,
    "monthly_payment_czk": null,
    "interest_rate_pct": null,
    "total_to_pay_czk": null,
    "first_payment_date": null,
    "last_payment_date": null,
    "collateral": null,
    "purpose": null
  },
  "employment": {
    "employee_name": null,
    "employee_id": null,
    "contract_type": null,
    "position": null,
    "start_date": null,
    "end_date": null,
    "gross_salary_czk": null,
    "work_hours_weekly": null,
    "workplace": null,
    "trial_period_months": null
  },
  "insurance": {
    "provider": null,
    "contract_number": null,
    "insured_item": null,
    "annual_premium_czk": null,
    "valid_from": null,
    "valid_to": null,
    "coverage_type": null
  },
  "purchase": {
    "seller": null,
    "item_description": null,
    "amount_czk": null,
    "payment_date": null,
    "serial_number": null,
    "warranty_months": null
  },
  "confidence": {
    "overall": 0.0,
    "critical_fields": 0.0
  },
  "notes": null
}

PRAVIDLA pro asset_classification:
- dlouhodoby_majetek: pořizovací cena ≥ 80 000 Kč A životnost > 1 rok (motorky, auta, stroje, budovy). Urči odpisovou skupinu dle § 30 ZDP:
  sk1 = 3 roky (počítače, telefony), sk2 = 5 let (vozidla, motorky, nábytek), sk3 = 10 let (stroje, turbíny), sk4 = 20 let (budovy dřevěné), sk5 = 30 let (budovy zděné), sk6 = 50 let (administrativní budovy). Pro motorky vždy sk2. Preferuj zrychlené odpisy (accelerated).
- kratkodoby_majetek: cena < 80 000 Kč A životnost > 1 rok (drobný hmotný majetek — helmy, nářadí, drobná elektronika)
- zbozi: zboží k dalšímu prodeji (merch, náhradní díly na prodej)
- material: spotřební materiál (oleje, čistící prostředky, kancelářské potřeby)
- drobna_rezie: drobné provozní náklady (poštovné, parkovné, dálniční známky, poplatky)
- sluzba: služby (servis, účetnictví, právní služby, marketing, hosting, telekom)
- null: nelze určit

PRAVIDLA pro položky (line_items):
- Pro KAŽDOU položku vyplň quantity (počet kusů, default 1) a unit_price (cena za kus bez měny). Když cena za kus chybí, dopočítej z amount/quantity.
- size = velikost SAMOSTATNĚ, i když je součástí názvu (přesně: 43, XL, 2XL, UNI, M…). NIKDY ji nenechávej jen v description.
- color = barva SAMOSTATNĚ česky (černá, modrá…), i když je v názvu. description = čistý název produktu.
- amount/unit_price uváděj v PŮVODNÍ měně dokladu (nepřeváděj). Měnu uveď v poli "currency" (ISO kód, např. CZK/EUR/USD/PLN).

PRAVIDLA pro typ dokladu (document_type):
- "proforma" = zálohová/proforma/advance faktura (často text "zálohová faktura", "proforma", "advance", "anticipo", "Vorkasse", "no es factura"). Z proformy se NEnaskladňuje a NEúčtuje jako náklad — jen evidence.
- "delivery_note" = dodací list (text "dodací list", "delivery note", "albarán", "Lieferschein") — bez cen / není daňový doklad.
- "invoice" = daňový doklad / faktura.

PRAVIDLA pro SKU (sku_suggestion + category_suggestion) — konvence skladu MotoGo
(malá písmena, číslice, pomlčky, bez diakritiky; velikost přesně 43/XL/2XL/UNI):
- Gear s velikostí: prislusenstvi-{typ}-{velikost}; typ ∈ helmet/jacket/pants/boots/gloves/balaclava. NErozlišuj řidič/spolujezdce — boty/kalhoty/bunda jsou prostě boots/pants/jacket. (category_suggestion="prislusenstvi")
- Náhradní díly / servis (oleje na výměnu, filtry, brzdy…): dily-{slug} (category="dily")
- Materiál (čističe, mazadla, spreje, kanc. potřeby): material-{slug} (category="material")
- Zboží pro půjčovnu/prodej (kufry, sítě, držáky telefonů, tankvaky, zámky): zbozi-{slug} (category="zbozi")
- Spotřební provoz (ubrousky, rukavice jednorázové): spotrebni-{slug} (category="spotrebni")
slug = krátký výstižný název v češtině bez diakritiky (značka-typ-parametr).

PRAVIDLA pro PŘEKLAD (zahraniční doklady):
- source_language = ISO kód jazyka dokladu (cs/en/de/pl/sk/es/...).
- Pokud doklad NENÍ v češtině: přelož do češtiny supplier_name_cs a u KAŽDÉ položky description_cs; ORIGINÁL ponech v supplier_name a description. SKU vždy dle CZ názvu.
- Pokud JE v češtině: supplier_name_cs i description_cs nech null.

Pokud pole neexistuje nebo není čitelné: null.
Částky vždy jako číslo bez mezer a měny.
Data vždy jako YYYY-MM-DD.
Číslo účtu ve formátu "předčíslí-číslo/kód banky" nebo IBAN.
Variabilní symbol = číslo faktury pokud není VS uveden zvlášť.`

export async function callClaudeVision(
  apiKey: string,
  imageBase64: string,
  mediaType: string,
  isRetry = false
): Promise<Record<string, any> | null> {
  const prompt = isRetry
    ? 'Vrať pouze validní JSON, nic jiného. Žádný markdown.\n\n' + VISION_PROMPT
    : VISION_PROMPT

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-opus-4-5',
        max_tokens: 2048,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: mediaType, data: imageBase64 },
            },
            { type: 'text', text: prompt },
          ],
        }],
      }),
    })

    if (!response.ok) {
      console.error('Claude Vision API error:', response.status, await response.text())
      return null
    }

    const result = await response.json()
    const text = result?.content?.[0]?.text || ''

    try {
      return JSON.parse(text)
    } catch {
      // Try to extract JSON from response
      const jsonMatch = text.match(/\{[\s\S]*\}/)
      if (jsonMatch) {
        try { return JSON.parse(jsonMatch[0]) } catch { /* fall through */ }
      }
    }

    // Retry once with stricter prompt
    if (!isRetry) {
      console.warn('Claude Vision returned non-JSON, retrying...')
      return callClaudeVision(apiKey, imageBase64, mediaType, true)
    }

    return null
  } catch (err) {
    console.error('Claude Vision call failed:', err)
    return null
  }
}
