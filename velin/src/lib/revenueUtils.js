// Kategorie, které jsou VŽDY příjmy (i když type = 'expense')
export const REVENUE_CATEGORIES = ['pronájem', 'pronajem', 'rezervace', 'booking', 'rental']

// Popisy, které indikují příjem
export const REVENUE_DESCRIPTIONS = ['platba za rezervaci', 'platba za pronájem', 'příjem z pronájmu']

/**
 * Klasifikuje účetní záznam jako 'revenue', 'expense' nebo 'unknown'.
 */
export function classifyEntry(entry) {
  const cat = (entry.category || '').toLowerCase()
  const desc = (entry.description || '').toLowerCase()
  if (entry.type === 'revenue') return 'revenue'
  if (REVENUE_CATEGORIES.some(rc => cat.includes(rc)) ||
      REVENUE_DESCRIPTIONS.some(rd => desc.includes(rd))) {
    return 'revenue'
  }
  return entry.type || 'expense'
}

/**
 * Vrací true pokud je záznam příjmový.
 */
export function isRevenueEntry(entry) {
  return classifyEntry(entry) === 'revenue'
}
