import { useEffect, useState } from 'react'

// Telefon + tablet = šířka ≤ 1023 px — stejná hranice jako RESPONSIVE LAYER v index.css.
// Desktop (≥ 1024 px) zůstává vykreslený beze změny; mobilní rozvržení se větví až podle tohoto hooku.
export const MOBILE_QUERY = '(max-width: 1023px)'

function matches(query) {
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia(query).matches
}

export function useMediaQuery(query) {
  const [value, setValue] = useState(() => matches(query))
  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return undefined
    const mql = window.matchMedia(query)
    const onChange = () => setValue(mql.matches)
    onChange()
    if (mql.addEventListener) mql.addEventListener('change', onChange)
    else mql.addListener(onChange)
    return () => {
      if (mql.removeEventListener) mql.removeEventListener('change', onChange)
      else mql.removeListener(onChange)
    }
  }, [query])
  return value
}

export function useIsMobile() {
  return useMediaQuery(MOBILE_QUERY)
}
