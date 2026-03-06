import { supabase } from './supabase'

// In-memory log buffer (max 200 entries)
const LOG_BUFFER = []
const MAX_BUFFER = 200
let _listeners = []

export function addLogListener(fn) {
  _listeners.push(fn)
  return () => { _listeners = _listeners.filter(l => l !== fn) }
}

function _notify() {
  _listeners.forEach(fn => fn([...LOG_BUFFER]))
}

function _addEntry(entry) {
  LOG_BUFFER.unshift(entry)
  if (LOG_BUFFER.length > MAX_BUFFER) LOG_BUFFER.pop()
  _notify()
}

export function getLogBuffer() {
  return [...LOG_BUFFER]
}

export function clearLogBuffer() {
  LOG_BUFFER.length = 0
  _notify()
}

/**
 * Track a Supabase/API action with timing and error capture.
 * Usage: const result = await debugAction('fleet.save', 'FleetDetail', async () => { ... })
 */
export async function debugAction(action, component, fn, requestData) {
  const start = performance.now()
  const entry = {
    id: crypto.randomUUID(),
    action,
    component,
    source: 'velin',
    status: 'info',
    request_data: requestData || null,
    response_data: null,
    error_message: null,
    error_stack: null,
    duration_ms: 0,
    created_at: new Date().toISOString(),
  }

  try {
    const result = await fn()
    entry.duration_ms = Math.round(performance.now() - start)

    // Check for Supabase error in result
    if (result?.error) {
      entry.status = 'error'
      entry.error_message = typeof result.error === 'string' ? result.error : result.error.message || JSON.stringify(result.error)
      entry.response_data = { code: result.error.code, hint: result.error.hint, details: result.error.details }
    } else {
      entry.status = 'success'
      // Truncate response for log
      if (result?.data) {
        const d = result.data
        entry.response_data = Array.isArray(d) ? { count: d.length, sample: d[0] } : (typeof d === 'object' ? { id: d.id, ...Object.fromEntries(Object.entries(d).slice(0, 5)) } : d)
      }
    }

    _addEntry(entry)
    _persistLog(entry)
    return result
  } catch (err) {
    entry.duration_ms = Math.round(performance.now() - start)
    entry.status = 'error'
    entry.error_message = err.message || String(err)
    entry.error_stack = err.stack?.split('\n').slice(0, 4).join('\n') || null
    _addEntry(entry)
    _persistLog(entry)
    throw err
  }
}

/**
 * Log a simple event (button click, navigation, etc.)
 */
export function debugLog(action, component, data) {
  const entry = {
    id: crypto.randomUUID(),
    action,
    component,
    source: 'velin',
    status: 'info',
    request_data: data || null,
    response_data: null,
    error_message: null,
    error_stack: null,
    duration_ms: 0,
    created_at: new Date().toISOString(),
  }
  _addEntry(entry)
}

/**
 * Log an error from a catch block
 */
export function debugError(action, component, err, requestData) {
  const entry = {
    id: crypto.randomUUID(),
    action,
    component,
    source: 'velin',
    status: 'error',
    request_data: requestData || null,
    response_data: null,
    error_message: err?.message || String(err),
    error_stack: err?.stack?.split('\n').slice(0, 4).join('\n') || null,
    duration_ms: 0,
    created_at: new Date().toISOString(),
  }
  _addEntry(entry)
  _persistLog(entry)
}

// Persist error/warning logs to DB (async, fire-and-forget)
async function _persistLog(entry) {
  if (entry.status !== 'error' && entry.status !== 'warning') return
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('debug_log').insert({
      admin_id: user?.id,
      source: entry.source,
      action: entry.action,
      component: entry.component,
      status: entry.status,
      request_data: entry.request_data,
      response_data: entry.response_data,
      error_message: entry.error_message,
      error_stack: entry.error_stack,
      duration_ms: entry.duration_ms,
    })
  } catch {}
}

/**
 * Export log buffer as copyable text
 */
export function exportLogText() {
  return LOG_BUFFER.map(e => {
    const time = e.created_at?.slice(11, 19) || ''
    const dur = e.duration_ms ? ` ${e.duration_ms}ms` : ''
    const status = e.status === 'error' ? 'ERR' : e.status === 'success' ? 'OK' : e.status === 'warning' ? 'WARN' : 'INFO'
    let line = `[${time}] [${status}${dur}] ${e.component || '-'} > ${e.action}`
    if (e.error_message) line += `\n  ERROR: ${e.error_message}`
    if (e.response_data) line += `\n  RESP: ${JSON.stringify(e.response_data).slice(0, 200)}`
    if (e.request_data) line += `\n  REQ: ${JSON.stringify(e.request_data).slice(0, 200)}`
    if (e.error_stack) line += `\n  STACK: ${e.error_stack}`
    return line
  }).join('\n\n')
}
