import { createContext, useContext, useState, useEffect, useCallback, useMemo } from 'react'
import cs from './locales/cs'
import en from './locales/en'
import de from './locales/de'
import es from './locales/es'
import fr from './locales/fr'
import nl from './locales/nl'
import pl from './locales/pl'

const STORAGE_KEY = 'mg_velin_language'
const DEFAULT_LANG = 'cs'

export const AVAILABLE_LANGUAGES = [
  { code: 'cs', flag: '🇨🇿', name: 'Čeština' },
  { code: 'en', flag: '🇬🇧', name: 'English' },
  { code: 'de', flag: '🇩🇪', name: 'Deutsch' },
  { code: 'es', flag: '🇪🇸', name: 'Español' },
  { code: 'fr', flag: '🇫🇷', name: 'Français' },
  { code: 'nl', flag: '🇳🇱', name: 'Nederlands' },
  { code: 'pl', flag: '🇵🇱', name: 'Polski' },
]

const DICTIONARIES = { cs, en, de, es, fr, nl, pl }

const LangContext = createContext(null)

function detectInitialLang() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored && DICTIONARIES[stored]) return stored
    const browser = (navigator.language || '').slice(0, 2).toLowerCase()
    if (DICTIONARIES[browser]) return browser
  } catch {}
  return DEFAULT_LANG
}

function format(template, params) {
  if (!params) return template
  return template.replace(/\{(\w+)\}/g, (_, k) =>
    params[k] !== undefined ? String(params[k]) : `{${k}}`,
  )
}

export function LanguageProvider({ children }) {
  const [lang, setLangState] = useState(() => detectInitialLang())

  const setLang = useCallback((code) => {
    if (!DICTIONARIES[code]) return
    setLangState(code)
    try { localStorage.setItem(STORAGE_KEY, code) } catch {}
    try { document.documentElement.lang = code } catch {}
  }, [])

  useEffect(() => {
    try { document.documentElement.lang = lang } catch {}
  }, [lang])

  const t = useCallback(
    (key, params) => {
      const dict = DICTIONARIES[lang] || DICTIONARIES[DEFAULT_LANG]
      const fallback = DICTIONARIES[DEFAULT_LANG]
      const raw = (dict && dict[key]) ?? (fallback && fallback[key]) ?? key
      return format(raw, params)
    },
    [lang],
  )

  const value = useMemo(
    () => ({ lang, setLang, t, languages: AVAILABLE_LANGUAGES }),
    [lang, setLang, t],
  )

  return <LangContext.Provider value={value}>{children}</LangContext.Provider>
}

export function useLang() {
  const ctx = useContext(LangContext)
  if (!ctx) {
    return {
      lang: DEFAULT_LANG,
      setLang: () => {},
      t: (k) => DICTIONARIES[DEFAULT_LANG][k] ?? k,
      languages: AVAILABLE_LANGUAGES,
    }
  }
  return ctx
}

export function useT() {
  return useLang().t
}
