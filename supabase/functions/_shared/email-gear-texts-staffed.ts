// Výpůjčka JEN výbavy na OBSLUŽNÉ pobočce (bez samoobsluhy, např. Mezná) — texty {{door_codes_block}}
// (FIX-R1, 2026-10-23). Kód se vydává stejně jako u motorky (obsluha ho ve Velínu bere jako identitu
// při předání), ale není to kód šatny a na pobočce není displej → „Kód výpůjčky“ + jedna věta, že ho
// zákazník při převzetí nahlásí obsluze. Tykání (styl živých šablon majitele); {branch} = název pobočky.

export type GearStaffedTexts = { title: string; label: string; hint: string; hintNoBranch: string }

export const GEAR_STAFFED_TEXTS: Record<string, GearStaffedTexts> = {
  cs: {
    title: 'Kód k výpůjčce výbavy', label: 'Kód výpůjčky',
    hint: 'Při převzetí ho nahlásíš obsluze na pobočce {branch}.',
    hintNoBranch: 'Při převzetí ho nahlásíš obsluze na pobočce.',
  },
  en: {
    title: 'Your gear rental code', label: 'Rental code',
    hint: 'When you pick up the gear, just tell it to the staff at the {branch} branch.',
    hintNoBranch: 'When you pick up the gear, just tell it to the staff at the branch.',
  },
  de: {
    title: 'Code für deinen Ausrüstungsverleih', label: 'Verleihcode',
    hint: 'Bei der Abholung nennst du ihn dem Personal in der Filiale {branch}.',
    hintNoBranch: 'Bei der Abholung nennst du ihn dem Personal in der Filiale.',
  },
  es: {
    title: 'Código de tu alquiler de equipo', label: 'Código de alquiler',
    hint: 'Al recoger el equipo, díselo al personal de la sucursal {branch}.',
    hintNoBranch: 'Al recoger el equipo, díselo al personal de la sucursal.',
  },
  fr: {
    title: 'Code de ta location d\'équipement', label: 'Code de location',
    hint: 'Au retrait, tu le donnes au personnel de l\'agence {branch}.',
    hintNoBranch: 'Au retrait, tu le donnes au personnel de l\'agence.',
  },
  nl: {
    title: 'Code voor je uitrustingshuur', label: 'Huurcode',
    hint: 'Bij het ophalen geef je hem door aan het personeel van vestiging {branch}.',
    hintNoBranch: 'Bij het ophalen geef je hem door aan het personeel van de vestiging.',
  },
  pl: {
    title: 'Kod do wypożyczenia wyposażenia', label: 'Kod wypożyczenia',
    hint: 'Przy odbiorze podasz go obsłudze w oddziale {branch}.',
    hintNoBranch: 'Przy odbiorze podasz go obsłudze w oddziale.',
  },
  uk: {
    title: 'Код для оренди спорядження', label: 'Код оренди',
    hint: 'Під час отримання назвеш його персоналу у філії {branch}.',
    hintNoBranch: 'Під час отримання назвеш його персоналу у філії.',
  },
}

export function gearStaffedTexts(lang: string): GearStaffedTexts {
  return Object.hasOwn(GEAR_STAFFED_TEXTS, lang) ? GEAR_STAFFED_TEXTS[lang] : GEAR_STAFFED_TEXTS.cs
}
