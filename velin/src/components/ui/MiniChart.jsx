export default function MiniChart({ data, color = '#1a8a18', height = 50 }) {
  if (!data || data.length === 0) return null

  const max = Math.max(...data)
  const min = Math.min(...data)
  const range = max - min || 1
  const w = 100 / data.length
  const gradientId = `cg${color.replace('#', '')}`

  const points = data
    .map((v, i) => `${i * w + w / 2},${height - ((v - min) / range) * (height - 6) - 3}`)
    .join(' ')

  const areaPath = `M0,${height} ${data
    .map((v, i) => `L${i * w + w / 2},${height - ((v - min) / range) * (height - 6) - 3}`)
    .join(' ')} L100,${height} Z`

  return (
    <svg viewBox={`0 0 100 ${height}`} className="w-full" style={{ height }} preserveAspectRatio="none">
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity=".25" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={areaPath} fill={`url(#${gradientId})`} />
      <polyline
        fill="none"
        stroke={color}
        strokeWidth="1.8"
        strokeLinejoin="round"
        points={points}
      />
    </svg>
  )
}
