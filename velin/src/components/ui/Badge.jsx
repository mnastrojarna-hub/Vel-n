export default function Badge({ label, color, bg }) {
  return (
    <span
      className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
      style={{
        padding: '4px 12px',
        color,
        background: bg,
      }}
    >
      {label}
    </span>
  )
}
