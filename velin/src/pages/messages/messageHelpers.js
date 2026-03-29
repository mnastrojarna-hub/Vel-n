export const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }
export const CHAR_LIMITS = { sms: 160, whatsapp: 1600 }

export const BULK_SEGMENTS = [
  { value: 'all', icon: '\ud83d\udccb', label: 'Vsichni zakaznici', desc: 'Vsichni s kontaktnimi udaji' },
  { value: 'vip', icon: '\u2b50', label: 'VIP zakaznici', desc: 'Reliability skore > 80' },
  { value: 'past_customers', icon: '\ud83c\udfcd\ufe0f', label: 'Minuli zakaznici', desc: 'Alespon 1 dokoncena rezervace' },
  { value: 'new_no_booking', icon: '\ud83d\udc4b', label: 'Novi bez rezervace', desc: 'Registrovani bez pujceni' },
]

export const COUNTRY_OPTIONS = [
  { value: '', label: 'Vsechny zeme' },
  { value: 'CZ', label: 'Cesko' },
  { value: 'SK', label: 'Slovensko' },
  { value: 'DE', label: 'Nemecko' },
  { value: 'AT', label: 'Rakousko' },
  { value: 'PL', label: 'Polsko' },
]

export const LANGUAGE_OPTIONS = [
  { value: '', label: 'Vsechny jazyky' },
  { value: 'cs', label: 'Cestina' },
  { value: 'en', label: 'English' },
  { value: 'de', label: 'Deutsch' },
]

const GSM7 = /^[A-Za-z0-9 @\u00a3\$\u00a5\u00e8\u00e9\u00f9\u00ec\u00f2\u00c7\n\u00d8\u00f8\r\u00c5\u00e5\u0394_\u03a6\u0393\u039b\u03a9\u03a0\u03a8\u03a3\u0398\u039e\u00c6\u00e6\u00df\u00c9 !"#\u00a4%&'()*+,\-./:;<=>?\u00a1\u00c4\u00d6\u00d1\u00dc\u00a7\u00bf\u00e4\u00f6\u00f1\u00fc\u00e0^{}\\[~\]|\u20ac]*$/

export function calcSmsSegments(text) {
  if (!text) return { chars: 0, segments: 0, perSegment: 160, isUcs2: false }
  const isUcs2 = !GSM7.test(text)
  const perSegment = isUcs2 ? (text.length > 70 ? 67 : 70) : (text.length > 160 ? 153 : 160)
  const segments = text.length === 0 ? 0 : Math.ceil(text.length / perSegment)
  return { chars: text.length, segments, perSegment, isUcs2 }
}

export function extractVariables(templateContent) {
  if (!templateContent) return []
  const matches = templateContent.match(/\{\{(\w+)\}\}/g)
  if (!matches) return []
  return [...new Set(matches.map(m => m.replace(/\{\{|\}\}/g, '')))]
}

export function replaceVariables(templateContent, vars) {
  if (!templateContent) return ''
  let result = templateContent
  Object.entries(vars).forEach(([key, val]) => {
    result = result.replaceAll(`{{${key}}}`, val || `{{${key}}}`)
  })
  return result
}
