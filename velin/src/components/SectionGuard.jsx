import { Navigate } from 'react-router-dom'
import { canSeeSection, firstAllowedPath } from '../lib/velinSections'

/**
 * Ochrana route podle oprávnění účtu (admin_users.permissions.sections).
 * Superadmin projde vždy. Uživatel bez oprávnění k sekci je přesměrován na
 * první sekci, kterou vidí; když nevidí žádnou, dostane vysvětlení místo stránky.
 * Sidebar stejné sekce skrývá — guard jen jistí přímé URL a odkazy napříč sekcemi.
 */
export default function SectionGuard({ admin, section, children }) {
  if (!admin) return children // ProtectedRoute už řeší nepřihlášeného / neadmina
  if (canSeeSection(admin, section)) return children

  const target = firstAllowedPath(admin)
  if (target) return <Navigate to={target} replace />

  return (
    <div className="flex items-center justify-center py-20 font-montserrat">
      <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '40px 48px', maxWidth: 440 }}>
        <div className="text-5xl mb-4">🔒</div>
        <h2 className="text-lg font-black mb-2" style={{ color: '#0f1a14' }}>Bez přístupu k sekcím</h2>
        <p className="text-sm font-medium" style={{ color: '#1a2e22' }}>
          Váš účet zatím nemá povolenou žádnou část Velína. Požádejte správce (superadmina),
          aby vám v „Uživatelé Velína“ zaškrtl sekce, které máte vidět.
        </p>
      </div>
    </div>
  )
}
