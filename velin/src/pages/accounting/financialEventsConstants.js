export const PER_PAGE = 25

export const STATUS_MAP = {
  pending:   { label: 'Ceka',        color: '#6b7280', bg: '#f3f4f6' },
  enriched:  { label: 'Ke schvaleni', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Pripraven',    color: '#2563eb', bg: '#dbeafe' },
  exported:  { label: 'Odeslano',     color: '#7c3aed', bg: '#ede9fe' },
  approved:  { label: 'Schvaleno',    color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Podano FU',   color: '#059669', bg: '#d1fae5' },
  error:     { label: 'Chyba',        color: '#dc2626', bg: '#fee2e2' },
}

export const TYPE_MAP = {
  revenue: { label: 'Prijem',  color: '#1a8a18', bg: '#dcfce7' },
  expense: { label: 'Vydaj',   color: '#dc2626', bg: '#fee2e2' },
  asset:   { label: 'Majetek', color: '#7c3aed', bg: '#ede9fe' },
  payroll: { label: 'Mzdy',    color: '#b45309', bg: '#fef3c7' },
}

export const SOURCE_LABELS = { stripe: 'Stripe', ocr: 'OCR', system: 'System', manual: 'Rucne', scanner: 'Skener' }

export const DOC_TYPE_MAP = {
  faktura_prijata: { label: 'Faktura prijata', color: '#2563eb', bg: '#dbeafe', route: 'Faktury prijate' },
  dodaci_list: { label: 'Dodaci list', color: '#0891b2', bg: '#cffafe', route: 'Dodaci listy' },
  zaloha: { label: 'Zalohova FA', color: '#7c3aed', bg: '#ede9fe', route: 'Faktury' },
  doklad_platby: { label: 'Doklad k platbe', color: '#059669', bg: '#d1fae5', route: 'Faktury' },
  smlouva: { label: 'Smlouva', color: '#b45309', bg: '#fef3c7', route: 'Smlouvy' },
  pracovni_smlouva: { label: 'Pracovni smlouva', color: '#92400e', bg: '#fef3c7', route: 'Smlouvy' },
  zadost_dovolena: { label: 'Zadost o dovolenou', color: '#0284c7', bg: '#e0f2fe', route: 'Zamestnanci' },
  objednavka: { label: 'Objednavka', color: '#1a8a18', bg: '#dcfce7', route: 'Objednavky' },
  skladovy_doklad: { label: 'Skladovy doklad', color: '#6d28d9', bg: '#ede9fe', route: 'Sklad' },
  pokladni_doklad: { label: 'Pokladni doklad', color: '#dc2626', bg: '#fee2e2', route: 'Pokladna' },
  other: { label: 'Nerozpoznano', color: '#6b7280', bg: '#f3f4f6', route: null },
}

export const STORAGE_FOLDERS = {
  faktura_prijata: 'faktury-prijate',
  dodaci_list: 'dodaci-listy',
  zaloha: 'faktury-prijate',
  doklad_platby: 'faktury-prijate',
  smlouva: 'smlouvy',
  pracovni_smlouva: 'zamestnanecke',
  zadost_dovolena: 'zamestnanecke',
  objednavka: 'objednavky',
  skladovy_doklad: 'sklad',
  pokladni_doklad: 'pokladna',
  other: 'ostatni',
}

export const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojisteni', servis_opravy: 'Servis', najem: 'Najem',
  energie: 'Energie', telekomunikace: 'Telekom', marketing: 'Marketing',
  kancelar: 'Kancelar', mzdy: 'Mzdy', dane_odvody: 'Dane', ostatni_naklady: 'Ostatni',
  pronajem_motorek: 'Pronajem', prodej_zbozi: 'E-shop', dlouhodoby_majetek: 'DM',
  kratkodoby_majetek: 'KM', zbozi: 'Zbozi', drobna_rezie: 'Rezie', material: 'Material',
  sluzba: 'Sluzba',
}

export const ASSET_TYPE_LABELS = {
  dlouhodoby_majetek: 'Dlouhodoby majetek',
  kratkodoby_majetek: 'Kratkodoby majetek',
  zbozi: 'Zbozi',
  material: 'Material',
  drobna_rezie: 'Drobna rezie',
  sluzba: 'Sluzba',
}

export const PAYMENT_LABELS = {
  bank_transfer: 'Bankovni prevod',
  cash: 'Hotovost',
  card: 'Karta',
}

export const ALL_STATUSES = ['pending', 'enriched', 'validated', 'exported', 'approved', 'submitted', 'error']
export const ALL_TYPES = ['revenue', 'expense', 'asset', 'payroll']
export const ALL_SOURCES = ['stripe', 'ocr', 'system', 'manual', 'scanner']
export const ALL_DOC_TYPES = Object.keys(DOC_TYPE_MAP)
