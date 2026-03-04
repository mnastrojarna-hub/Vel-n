export default function Button({
  children,
  green = false,
  outline = false,
  onClick,
  className = '',
  style = {},
  type = 'button',
  disabled = false,
}) {
  const base =
    'inline-flex items-center gap-1.5 rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer transition-all'

  const variant = green
    ? 'text-white border-none'
    : outline
      ? 'bg-transparent border-2'
      : 'border-none'

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`${base} ${variant} ${className} disabled:opacity-50 disabled:cursor-not-allowed`}
      style={{
        padding: '10px 22px',
        background: green ? '#74FB71' : outline ? 'transparent' : '#f1faf7',
        color: green ? '#1a2e22' : outline ? '#3dba3a' : '#4a6357',
        borderColor: outline ? '#74FB71' : undefined,
        boxShadow: green ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
        ...style,
      }}
    >
      {children}
    </button>
  )
}
