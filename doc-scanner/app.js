// ═══════════════════════════════════════════════════════
// MotoGo24 Document Scanner — app.js
// Ultra-simple: scan → send to receive-invoice → done
// ═══════════════════════════════════════════════════════

const CONFIG = {
  EDGE_FUNCTION_URL: 'https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/receive-invoice',
  API_KEY: 'a745cb2badbe46899e16447c092299fe9447ef520523a0f5b379605c8e884829',
  MAX_IMAGE_SIZE_MB: 4
}

// Capacitor plugins
const { Camera, Network } = Capacitor.Plugins
const CameraSource = { CAMERA: 'CAMERA', PHOTOS: 'PHOTOS' }

// State
let currentPhoto = null

// ── Document scanning ──────────────────────────────────

async function scanDocument(source) {
  try {
    const photo = await Camera.getPhoto({
      quality: 85,
      allowEditing: false,
      resultType: 'base64',
      source: CameraSource[source],
      correctOrientation: true
    })

    // Check size (base64 is ~33% larger than binary)
    const sizeKB = (photo.base64String.length * 0.75) / 1024
    if (sizeKB > CONFIG.MAX_IMAGE_SIZE_MB * 1024) {
      alert('Soubor je příliš velký (max ' + CONFIG.MAX_IMAGE_SIZE_MB + ' MB). Zkuste nižší kvalitu fotky.')
      return
    }

    // Show preview
    showScreen('preview')
    document.getElementById('preview-img').src =
      'data:image/jpeg;base64,' + photo.base64String
    document.getElementById('error-box').hidden = true
    currentPhoto = photo.base64String
  } catch (err) {
    // User cancelled camera — do nothing
    if (err.message && err.message.includes('cancelled')) return
    console.error('Camera error:', err)
  }
}

// ── Send document ──────────────────────────────────────

async function sendDocument() {
  if (!currentPhoto) return

  // Check network
  try {
    const status = await Network.getStatus()
    if (!status.connected) {
      showError('Není připojení k internetu. Zkuste to znovu.')
      return
    }
  } catch (_) {
    // Network plugin may not be available in browser — continue
  }

  showLoading('Analyzuji doklad…')
  document.getElementById('btn-send').disabled = true

  try {
    const response = await fetch(CONFIG.EDGE_FUNCTION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Invoice-Api-Key': CONFIG.API_KEY
      },
      body: JSON.stringify({
        image_base64: currentPhoto,
        file_name: 'scan_' + Date.now() + '.jpg'
      })
    })

    const data = await response.json()

    if (!response.ok) {
      throw new Error(data.error || 'Chyba serveru (' + response.status + ')')
    }

    // Show result
    showResult(data)

    // Save to history
    saveToHistory({
      document_type: data.document_type,
      supplier: data.extracted?.supplier || data.ai_classification?.classification_note,
      amount: data.extracted?.amount,
      date: data.extracted?.date,
      timestamp: new Date().toISOString(),
      needs_review: data.needs_review
    })
  } catch (err) {
    hideLoading()
    showError('Nepodařilo se odeslat: ' + err.message)
    document.getElementById('btn-send').disabled = false
  }
}

// ── Result display ─────────────────────────────────────

const DOC_TYPES = {
  invoice: 'Faktura',
  receipt: 'Paragon',
  contract_purchase: 'Kupní smlouva',
  contract_loan: 'Úvěrová smlouva',
  contract_employment: 'Pracovní smlouva',
  contract_service: 'Smlouva o službách',
  insurance: 'Pojistná smlouva',
  delivery_note: 'Dodací list',
  leasing: 'Leasingová smlouva',
  other: 'Jiný dokument'
}

function showResult(data) {
  hideLoading()
  showScreen('result')

  var icon = data.needs_review ? '⚠️' : '✅'
  var docType = DOC_TYPES[data.document_type] || data.document_type
  var conf = data.confidence
  var supplier = '—'
  var amount = '—'
  var date = '—'

  // Extract supplier/amount/date from response metadata
  if (data.extracted) {
    supplier = data.extracted.supplier || '—'
    amount = data.extracted.amount ? data.extracted.amount + ' Kč' : '—'
    date = data.extracted.date || '—'
  }

  document.getElementById('result-icon').textContent = icon
  document.getElementById('result-message').textContent = data.needs_review
    ? 'Doklad odeslan — ke kontrole'
    : 'Doklad úspěšně zpracován'
  document.getElementById('result-type').textContent = docType
  document.getElementById('result-supplier').textContent = supplier
  document.getElementById('result-amount').textContent = amount
  document.getElementById('result-date').textContent = date

  var banner = document.getElementById('review-banner')
  if (data.needs_review) {
    banner.hidden = false
    banner.textContent = '⚠️ Nízká čitelnost — ke kontrole ve Velínu'
  } else {
    banner.hidden = true
  }
}

// ── History ────────────────────────────────────────────

function saveToHistory(item) {
  var history = JSON.parse(localStorage.getItem('doc_history') || '[]')
  history.unshift(item)
  if (history.length > 5) history = history.slice(0, 5)
  localStorage.setItem('doc_history', JSON.stringify(history))
  renderHistory()
}

function renderHistory() {
  var history = JSON.parse(localStorage.getItem('doc_history') || '[]')
  var container = document.getElementById('history-list')

  if (history.length === 0) {
    container.innerHTML = '<div class="history-empty">Zatím žádné odeslané doklady</div>'
    return
  }

  container.innerHTML = history.map(function(item) {
    var type = DOC_TYPES[item.document_type] || item.document_type || '?'
    var supplier = item.supplier || '—'
    var amount = item.amount ? item.amount + ' Kč' : ''
    var reviewIcon = item.needs_review ? ' ⚠️' : ''
    return '<div class="history-item">' +
      '<div class="hi-left">' +
        '<span class="hi-type">' + type + reviewIcon + '</span>' +
        '<span class="hi-supplier">' + supplier + '</span>' +
      '</div>' +
      (amount ? '<span class="hi-amount">' + amount + '</span>' : '') +
    '</div>'
  }).join('')
}

// ── Screen navigation ──────────────────────────────────

function showScreen(name) {
  document.getElementById('screen-main').hidden = name !== 'main'
  document.getElementById('screen-preview').hidden = name !== 'preview'
  document.getElementById('screen-result').hidden = name !== 'result'
}

function resetToMain() {
  currentPhoto = null
  document.getElementById('btn-send').disabled = false
  document.getElementById('error-box').hidden = true
  showScreen('main')
  renderHistory()
}

// ── Helpers ────────────────────────────────────────────

function showLoading(text) {
  document.getElementById('loading-text').textContent = text || 'Načítám…'
  document.getElementById('loading-overlay').hidden = false
}

function hideLoading() {
  document.getElementById('loading-overlay').hidden = true
}

function showError(msg) {
  var box = document.getElementById('error-box')
  box.textContent = msg
  box.hidden = false
}

// ── Init ───────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', function() {
  renderHistory()
})
