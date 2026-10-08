// Sekce hlavního menu Velína — JEDINÝ zdroj pravdy pro Sidebar, ochranu routes
// (SectionGuard) i zaškrtávací seznam oprávnění u uživatele (Uživatelé Velína).
//
// Oprávnění: `admin_users.permissions` jsonb ve tvaru `{ "sections": ["service", "finance"] }`.
//  - role `superadmin` vidí VŽDY vše (bez ohledu na permissions),
//  - chybějící `permissions.sections` (starší účty) = vše (zpětná kompatibilita),
//  - pole `sections` = jen vyjmenované sekce (i detaily pod nimi: /flotila/:id → fleet …),
//  - sekce `users` (správa účtů) je VÝHRADNĚ pro superadmina, i kdyby byla v poli.

export const VELIN_SECTIONS = [
  { id: 'dashboard', path: '/', label: 'Velín', icon: '⚡' },
  { id: 'fleet', path: '/flotila', label: 'Flotila', icon: '🏍️' },
  { id: 'bookings', path: '/rezervace', label: 'Rezervace', icon: '📅' },
  { id: 'customers', path: '/zakaznici', label: 'Zákazníci', icon: '👥' },
  { id: 'finance', path: '/finance', label: 'Finance', icon: '💰' },
  { id: 'documents', path: '/dokumenty', label: 'Dokumenty', icon: '📄' },
  { id: 'branches', path: '/pobocky', label: 'Pobočky', icon: '🏢', badgeKey: 'kiosk' },   // poplach samoobsluhy (kiosk_alerts)
  { id: 'logistics', path: '/logistika', label: 'Logistika zboží', icon: '📦', badgeKey: 'gear', extraPaths: ['/sklady'] },
  { id: 'trasy', path: '/trasy', label: 'Trasy', icon: '🛣️' },
  { id: 'service', path: '/servis', label: 'Servis', icon: '🔧', badgeKey: 'service' },   // servisní intervaly po termínu (get_service_due_count)
  { id: 'messages', path: '/zpravy', label: 'Zprávy', icon: '💬', badgeKey: 'messages' },
  { id: 'cms', path: '/cms', label: 'Texty webu', icon: '🌐' },
  { id: 'analyza', path: '/analyza', label: 'Analýza', icon: '🧠' },
  { id: 'discount-codes', path: '/slevove-kody', label: 'Slevové kódy', icon: '🏷️' },
  { id: 'eshop', path: '/e-shop', label: 'E-shop', icon: '🛒' },
  { id: 'government', path: '/statni-sprava', label: 'Státní správa', icon: '🏛️' },
  { id: 'ai', path: '/ai-copilot', label: 'AI Copilot', icon: '🤖' },
  { id: 'orchestrator', path: '/orchestrator', label: 'AI Ředitel', icon: '👔' },
  { id: 'sos', path: '/sos', label: 'SOS Panel', icon: '🚨', badgeKey: 'sos' },
  { id: 'employees', path: '/zamestnanci', label: 'Zaměstnanci', icon: '👷' },
  { id: 'users', path: '/uzivatele', label: 'Uživatelé Velína', icon: '🔑', superadminOnly: true },
]

/** Sekce, které lze zaškrtnout uživateli (bez superadmin-only). */
export const ASSIGNABLE_SECTIONS = VELIN_SECTIONS.filter(s => !s.superadminOnly)

export function isSuperadmin(admin) {
  return admin?.role === 'superadmin'
}

/** Pole povolených id sekcí, nebo null = bez omezení (superadmin / starý účet bez permissions). */
export function allowedSectionIds(admin) {
  if (!admin) return []
  if (isSuperadmin(admin)) return null
  const sections = admin.permissions?.sections
  if (!Array.isArray(sections)) return null
  return sections.filter(id => typeof id === 'string')
}

export function canSeeSection(admin, sectionId) {
  if (!admin) return false
  const def = VELIN_SECTIONS.find(s => s.id === sectionId)
  if (!def) return isSuperadmin(admin)
  if (def.superadminOnly) return isSuperadmin(admin)
  const allowed = allowedSectionIds(admin)
  return allowed === null || allowed.includes(sectionId)
}

/** Sekce viditelné v menu pro daného admina (v pořadí menu). */
export function visibleSections(admin) {
  return VELIN_SECTIONS.filter(s => canSeeSection(admin, s.id))
}

/** Id sekce pro cestu (`/flotila/abc` → fleet, `/sklady` → logistics, `/` → dashboard). */
export function sectionForPath(pathname) {
  if (!pathname || pathname === '/') return 'dashboard'
  for (const s of VELIN_SECTIONS) {
    if (s.path !== '/' && (pathname === s.path || pathname.startsWith(s.path + '/'))) return s.id
    for (const p of s.extraPaths || []) {
      if (pathname === p || pathname.startsWith(p + '/')) return s.id
    }
  }
  return null
}

/** První cesta, kam smí admin (pro přesměrování z nepovolené sekce); null = nikam. */
export function firstAllowedPath(admin) {
  const first = visibleSections(admin)[0]
  return first ? first.path : null
}

/** Popis sekcí do seznamu uživatelů („Flotila, Servis, +3“). */
export function describeSections(admin) {
  if (isSuperadmin(admin)) return 'Vše (superadmin)'
  const allowed = allowedSectionIds(admin)
  if (allowed === null) return 'Vše'
  const labels = ASSIGNABLE_SECTIONS.filter(s => allowed.includes(s.id)).map(s => s.label)
  if (labels.length === 0) return 'Nic (bez přístupu)'
  if (labels.length <= 3) return labels.join(', ')
  return `${labels.slice(0, 3).join(', ')} +${labels.length - 3}`
}
