// ===== _shared/manual-texts/index.ts =====
// Registr PŘEDEXTRAHOVANÝCH textů návodů — pro návody, které nejdou přečíst
// strojově za běhu (naskenované PDF bez textové vrstvy, JS prohlížečky typu
// manua.ls/manualslib, CDN s bot-blokací). Text vznikl offline (OCR / ruční
// extrakce) a bundluje se s edge funkcí; dynamický import načte jen potřebný
// soubor, ostatní cold-start nezatěžují.
//
// Klíč = motorcycles.id (UUID z DB). Po naskladnění nové motorky se skenovaným
// návodem: OCR → soubor `<slug>.ts` s `export default JSON.parse('…')` → řádek
// v REGISTRY. Reálný případ 26. 7. 2026: Suzuki DL 650 V-strom má návod jako
// čistý sken (135 stran JPEG, 0 fontů) — agent bez OCR textu nemohl číst nikdy.
const REGISTRY: Record<string, () => Promise<{ default: string }>> = {
  // Suzuki DL 650 V-strom — OCR (tesseract ces, 150 dpi) z blog.bobhy.cz PDF
  '8f554a38-c3b3-4337-9d6a-899ea8e54b37': () => import('./suzuki-dl650-vstrom.ts'),
}

export async function getBundledManualText(motoId: string): Promise<string | null> {
  const loader = REGISTRY[String(motoId || '').trim()]
  if (!loader) return null
  try {
    return (await loader()).default
  } catch (e) {
    console.error('manual-texts: import failed for', motoId, (e as Error).message)
    return null
  }
}
