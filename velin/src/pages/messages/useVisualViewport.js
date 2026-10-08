import { useEffect, useState } from 'react'

// Rozměr VIZUÁLNÍHO viewportu (bez klávesnice na displeji).
// Fixní překryv chatu se podle něj zmenší, takže pole pro odpověď zůstane nad klávesnicí (iOS i Android).
function read() {
  if (typeof window === 'undefined') return { height: 0, offsetTop: 0 }
  const vv = window.visualViewport
  if (vv) return { height: Math.round(vv.height), offsetTop: Math.round(vv.offsetTop) }
  return { height: window.innerHeight, offsetTop: 0 }
}

export default function useVisualViewport() {
  const [state, setState] = useState(read)
  useEffect(() => {
    const vv = window.visualViewport
    const update = () => {
      const next = read()
      setState(prev => (prev.height === next.height && prev.offsetTop === next.offsetTop ? prev : next))
    }
    update()
    if (vv) {
      vv.addEventListener('resize', update)
      vv.addEventListener('scroll', update)
    }
    window.addEventListener('resize', update)
    return () => {
      if (vv) {
        vv.removeEventListener('resize', update)
        vv.removeEventListener('scroll', update)
      }
      window.removeEventListener('resize', update)
    }
  }, [])
  return state
}
