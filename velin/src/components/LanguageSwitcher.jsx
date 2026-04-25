import { useState, useRef, useEffect } from 'react'
import { useLang } from '../i18n/LanguageProvider'

export default function LanguageSwitcher({ variant = 'topbar' }) {
  const { lang, setLang, languages, t } = useLang()
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    function onClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const current = languages.find((l) => l.code === lang) || languages[0]

  const isLight = variant === 'light'
  const triggerBg = isLight ? '#f1faf7' : '#f1faf7'
  const triggerBorder = isLight ? '#d4e8e0' : '#d4e8e0'
  const triggerColor = isLight ? '#0f1a14' : '#0f1a14'

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        title={t('lang.select')}
        aria-label={t('lang.select')}
        className="flex items-center gap-2 cursor-pointer transition-colors"
        style={{
          padding: '6px 10px',
          borderRadius: 999,
          border: `1px solid ${triggerBorder}`,
          background: triggerBg,
          color: triggerColor,
          fontSize: 13,
          fontWeight: 700,
          fontFamily: 'inherit',
          lineHeight: 1,
        }}
      >
        <span style={{ fontSize: 16 }}>{current.flag}</span>
        <span className="hidden sm:inline" style={{ textTransform: 'uppercase', letterSpacing: 1 }}>
          {current.code}
        </span>
        <span style={{ fontSize: 10, opacity: 0.6 }}>▾</span>
      </button>

      {open && (
        <div
          className="absolute right-0 top-full mt-2 z-50 rounded-card shadow-card bg-white"
          style={{ width: 220, border: '1px solid #d4e8e0', overflow: 'hidden' }}
        >
          <div
            className="text-sm font-extrabold uppercase tracking-wide"
            style={{
              padding: '10px 14px',
              color: '#1a2e22',
              borderBottom: '1px solid #d4e8e0',
              letterSpacing: 1.5,
            }}
          >
            {t('lang.select')}
          </div>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0, maxHeight: 320, overflowY: 'auto' }}>
            {languages.map((l) => {
              const active = l.code === lang
              return (
                <li key={l.code}>
                  <button
                    type="button"
                    onClick={() => {
                      setLang(l.code)
                      setOpen(false)
                    }}
                    className="w-full flex items-center gap-3 cursor-pointer transition-colors hover:bg-[#f1faf7]"
                    style={{
                      padding: '10px 14px',
                      border: 'none',
                      background: active ? '#ecfdf5' : 'transparent',
                      color: '#0f1a14',
                      fontFamily: 'inherit',
                      fontSize: 14,
                      fontWeight: active ? 800 : 600,
                      textAlign: 'left',
                    }}
                  >
                    <span style={{ fontSize: 20 }}>{l.flag}</span>
                    <span className="flex-1">{l.name}</span>
                    {active && (
                      <span style={{ color: '#13C14E', fontWeight: 900, fontSize: 14 }}>✓</span>
                    )}
                  </button>
                </li>
              )
            })}
          </ul>
        </div>
      )}
    </div>
  )
}
