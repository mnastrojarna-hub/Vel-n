// Chyba Anthropic API → srozumitelný důvod (2026-10-01).
// Dřív AI Copilot na každou chybu vrátil jen „AI service error“ (Velín: „Chyba. Zkuste to znovu.“)
// a nešlo poznat, že např. došel kredit nebo je zneplatněný klíč. Typy dle docs Anthropic:
// 401 authentication_error, 402 billing_error, 403 permission_error, 404 not_found_error,
// 413 request_too_large, 429 rate_limit_error, 529 overloaded_error; došlý kredit chodí i jako
// 400 invalid_request_error „Your credit balance is too low…“.
export function classifyAnthropicError(status, body) {
  let type = '';
  let detail = '';
  try {
    const j = JSON.parse(body);
    type = String(j?.error?.type || '');
    detail = String(j?.error?.message || '');
  } catch  {
    detail = String(body || '');
  }
  detail = detail.slice(0, 300);
  const low = detail.toLowerCase();
  const base = {
    type,
    detail
  };
  if (status === 402 || type === 'billing_error' || low.includes('credit balance')) {
    return {
      ...base,
      code: 'credit_exhausted',
      retryable: false,
      message: 'Došel kredit na Anthropic API (Claude). Dobijte ho na console.anthropic.com → Settings → Billing (doporučeno zapnout automatické dobíjení); AI pak hned znovu funguje.'
    };
  }
  if (status === 401 || type === 'authentication_error') {
    return {
      ...base,
      code: 'invalid_api_key',
      retryable: false,
      message: 'API klíč Anthropic je neplatný nebo zrušený. Vytvořte nový na console.anthropic.com → API Keys a vložte ho do Supabase → Edge Functions → Secrets jako ANTHROPIC_API_KEY.'
    };
  }
  if (status === 403 || type === 'permission_error') {
    return {
      ...base,
      code: 'permission',
      retryable: false,
      message: 'API klíč Anthropic nemá oprávnění k použitému modelu nebo funkci (zkontrolujte workspace klíče na console.anthropic.com).'
    };
  }
  if (status === 404 || type === 'not_found_error') {
    return {
      ...base,
      code: 'model_not_found',
      retryable: false,
      message: `Model AI není dostupný${detail ? ` (${detail})` : ''}.`
    };
  }
  if (status === 413 || type === 'request_too_large') {
    return {
      ...base,
      code: 'too_large',
      retryable: false,
      message: 'Konverzace je pro AI příliš dlouhá — začněte novou konverzaci.'
    };
  }
  if (status === 429 || type === 'rate_limit_error') {
    return {
      ...base,
      code: 'rate_limited',
      retryable: true,
      message: 'Překročen limit požadavků na Anthropic API — zkuste to za minutu.'
    };
  }
  if (status === 529 || status === 503 || type === 'overloaded_error') {
    return {
      ...base,
      code: 'overloaded',
      retryable: true,
      message: 'AI služba je přetížená. Zkuste to za minutu.'
    };
  }
  return {
    ...base,
    code: 'ai_error',
    retryable: status >= 500,
    message: `AI služba vrátila chybu ${status}${detail ? `: ${detail}` : ''}.`
  };
}
