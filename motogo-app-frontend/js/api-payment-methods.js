// ===== API-PAYMENT-METHODS.JS – Stripe saved payment methods =====
// In-app card form via Stripe Elements (PCI-compliant, no redirect).
// Cards stored in Supabase `payment_methods` + Stripe Customer.

// ── Stripe.js instance (lazy init) ──
var _stripeInstance = null;
function _getStripe(){
  if(_stripeInstance) return _stripeInstance;
  var cfg = window.MOTOGO_CONFIG || {};
  if(cfg.STRIPE_PUBLISHABLE_KEY && typeof Stripe === 'function'){
    _stripeInstance = Stripe(cfg.STRIPE_PUBLISHABLE_KEY, {locale:'cs'});
  }
  return _stripeInstance;
}

// ── Stripe Elements state ──
var _cardElement = null;
var _stripeElements = null;

function _initCardElement(containerId){
  var s = _getStripe();
  if(!s) return null;
  _stripeElements = s.elements();
  _cardElement = _stripeElements.create('card', {
    style: {
      base: {
        fontSize: '15px',
        fontFamily: 'Montserrat, sans-serif',
        color: '#1a1a1a',
        '::placeholder': { color: '#9ca3af' },
        fontWeight: '500'
      },
      invalid: { color: '#dc2626' }
    },
    hidePostalCode: true
  });
  var el = document.getElementById(containerId);
  if(el) _cardElement.mount('#' + containerId);
  return _cardElement;
}

function _destroyCardElement(){
  if(_cardElement){ try { _cardElement.destroy(); } catch(e){} _cardElement = null; }
  _stripeElements = null;
}

// ── Edge function call helper ──
async function _callPaymentMethodsAPI(body){
  var cfg = window.MOTOGO_CONFIG || {};
  var baseUrl = cfg.SUPABASE_URL;
  var anonKey = cfg.SUPABASE_ANON_KEY;
  if(!baseUrl) return {success:false, error:'No config'};
  var token = null;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}
  if(!token){
    try {
      var ref = await window.supabase.auth.refreshSession();
      if(ref.data && ref.data.session){
        await window.supabase.auth.setSession({
          access_token: ref.data.session.access_token,
          refresh_token: ref.data.session.refresh_token
        });
        token = ref.data.session.access_token;
      }
    } catch(e){}
  }
  if(!token) return {success:false, error:'Nejste přihlášeni. Přihlaste se prosím znovu.'};
  try {
    var resp = await fetch(baseUrl + '/functions/v1/manage-payment-methods', {
      method: 'POST',
      headers: {'Content-Type':'application/json','Authorization':'Bearer '+token,'apikey':anonKey||''},
      body: JSON.stringify(body)
    });
    var result = await resp.json();
    if(resp.status === 401){
      return {success:false, error:'Platnost přihlášení vypršela. Přihlaste se znovu.'};
    }
    return result;
  } catch(e){ return {success:false, error:e.message}; }
}

// ── Fetch cards from Supabase table (fast, no edge function) ──
async function apiFetchPaymentMethods(){
  if(!window.supabase || !window.supabase.from){
    return await _callPaymentMethodsAPI({action:'list'});
  }
  try {
    var sess = await window.supabase.auth.getSession();
    var userId = sess && sess.data && sess.data.session ? sess.data.session.user.id : null;
    if(!userId) return {success:false, error:'Nejste přihlášeni', methods:[]};
    var r = await window.supabase
      .from('payment_methods')
      .select('stripe_payment_method_id, brand, last4, exp_month, exp_year, holder_name, is_default')
      .eq('user_id', userId)
      .order('is_default', {ascending: false});
    if(r.error) return await _callPaymentMethodsAPI({action:'list'});
    var methods = (r.data || []).map(function(m){
      return {
        id: m.stripe_payment_method_id,
        brand: m.brand || 'unknown',
        last4: m.last4 || '****',
        exp_month: m.exp_month,
        exp_year: m.exp_year,
        holder_name: m.holder_name,
        is_default: m.is_default
      };
    });
    if(methods.length === 0){
      var efResult = await _callPaymentMethodsAPI({action:'list'});
      if(efResult.success && efResult.methods && efResult.methods.length > 0) return efResult;
    }
    return {success:true, methods:methods};
  } catch(e){ return await _callPaymentMethodsAPI({action:'list'}); }
}

// ── Create payment method via Stripe.js + attach via edge function ──
async function apiCreatePaymentMethod(holderName){
  var s = _getStripe();
  if(!s || !_cardElement) return {success:false, error:'Stripe není inicializován'};
  try {
    var result = await s.createPaymentMethod({
      type: 'card',
      card: _cardElement,
      billing_details: { name: holderName || undefined }
    });
    if(result.error) return {success:false, error:result.error.message};
    var pmId = result.paymentMethod.id;
    // Attach to Stripe Customer via edge function
    var attachResult = await _callPaymentMethodsAPI({action:'attach', payment_method_id: pmId});
    return attachResult;
  } catch(e){ return {success:false, error:e.message}; }
}

// ── Delete card ──
async function apiDeletePaymentMethod(pmId){
  var result = await _callPaymentMethodsAPI({action:'delete', payment_method_id:pmId});
  if(result.success && window.supabase && window.supabase.from){
    try { await window.supabase.from('payment_methods').delete().eq('stripe_payment_method_id', pmId); } catch(e){}
  }
  return result;
}

// ── Set default card ──
async function apiSetDefaultPaymentMethod(pmId){
  var result = await _callPaymentMethodsAPI({action:'set_default', payment_method_id:pmId});
  if(result.success && window.supabase && window.supabase.from){
    try {
      var sess = await window.supabase.auth.getSession();
      var userId = sess && sess.data && sess.data.session ? sess.data.session.user.id : null;
      if(userId){
        await window.supabase.from('payment_methods').update({is_default:false}).eq('user_id', userId);
        await window.supabase.from('payment_methods').update({is_default:true}).eq('stripe_payment_method_id', pmId);
      }
    } catch(e){}
  }
  return result;
}
