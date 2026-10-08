import { useState, useEffect, useRef } from 'react'

// fullWidth: pole přes celou šířku rodiče (mobilní rozvržení); výchozí 260 px beze změny.
export default function SearchInput({ value, onChange, placeholder = 'Hledat…', fullWidth = false }) {
  const [local, setLocal] = useState(value || '')
  const timer = useRef(null)

  useEffect(() => {
    setLocal(value || '')
  }, [value])

  const handleChange = (e) => {
    const v = e.target.value
    setLocal(v)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => onChange(v), 300)
  }

  return (
    <div className="relative" style={fullWidth ? { width: '100%' } : undefined}>
      <span
        className="absolute left-3 top-1/2 -translate-y-1/2"
        style={{ fontSize: 14, color: '#1a2e22' }}
      >
        🔍
      </span>
      <input
        type="text"
        value={local}
        onChange={handleChange}
        placeholder={placeholder}
        className="rounded-btn text-sm font-medium outline-none"
        style={{
          padding: '8px 14px 8px 34px',
          background: '#f1faf7',
          border: '1px solid #d4e8e0',
          color: '#0f1a14',
          width: fullWidth ? '100%' : 260,
          maxWidth: '100%',
        }}
      />
    </div>
  )
}
