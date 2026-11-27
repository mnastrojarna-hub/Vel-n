// Starší verze vygenerovaného dokumentu (generated_documents téže rezervace a šablony).
// generate-document po vygenerování nové verze starší přemazává (řádek i soubor) — s JEDNOU výjimkou:
// dokument vystavený jiným provozovatelem (jiné IČO / název ve filled_data) nebo před začátkem
// platnosti aktuálního (app_settings.company_info.valid_from) se NIKDY nemaže ani nepřepisuje.
// Už vydaná smlouva / VOP / protokol zůstává, nová verze vznikne vedle ní.
import type { Company } from '../_shared/company.ts'

export interface OldDoc { id: string; pdf_path: string | null; created_at?: string | null; filled_data?: Record<string, unknown> | null }

/** true = verzi nelze smazat (vystavil ji jiný provozovatel / vznikla před změnou provozovatele). */
export function isFrozenVersion(doc: OldDoc, company: Pick<Company, 'ico' | 'name' | 'validFrom'>): boolean {
  const fd = (doc.filled_data && typeof doc.filled_data === 'object' ? doc.filled_data : {}) as Record<string, unknown>
  const ico = String(fd.company_ico ?? '').trim()
  const name = String(fd.company_name ?? '').trim()
  if (ico ? ico !== company.ico : (!!name && name !== company.name)) return true
  const from = Date.parse(String(company.validFrom || ''))
  const made = Date.parse(String(doc.created_at || ''))
  return Number.isFinite(from) && Number.isFinite(made) && made < from
}

/** Rozdělí starší verze na smazatelné a zamražené. */
export function splitOldVersions(docs: OldDoc[], company: Pick<Company, 'ico' | 'name' | 'validFrom'>): { removable: OldDoc[]; frozen: OldDoc[] } {
  const removable: OldDoc[] = [], frozen: OldDoc[] = []
  for (const d of docs) (isFrozenVersion(d, company) ? frozen : removable).push(d)
  return { removable, frozen }
}
