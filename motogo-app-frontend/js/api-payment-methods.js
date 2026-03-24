// ===== API-PAYMENT-METHODS.JS – Stripe saved payment methods =====
// Cards are stored in Supabase `payment_methods` table (synced from Stripe via webhook).
// Listing reads from Supabase directly (fast, no edge function needed).
// Mutations (setup, delete, set_default) go through the edge function.

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

// Fetch payment methods from Supabase table (fast, no edge function)
async function apiFetchPaymentMethods(){
  if(!window.supabase || !window.supabase.from) {
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

    if(r.error){
      // Fallback to edge function if table doesn't exist or RLS blocks
      return await _callPaymentMethodsAPI({action:'list'});
    }

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

    // If no cards in Supabase, try edge function as fallback (first-time sync)
    if(methods.length === 0){
      var efResult = await _callPaymentMethodsAPI({action:'list'});
      if(efResult.success && efResult.methods && efResult.methods.length > 0){
        return efResult;
      }
    }

    return {success:true, methods:methods};
  } catch(e){
    // Fallback to edge function
    return await _callPaymentMethodsAPI({action:'list'});
  }
}

async function apiDeletePaymentMethod(pmId){
  var result = await _callPaymentMethodsAPI({action:'delete', payment_method_id:pmId});
  // Also remove from local Supabase table immediately for instant UI update
  if(result.success && window.supabase && window.supabase.from){
    try {
      await window.supabase.from('payment_methods').delete().eq('stripe_payment_method_id', pmId);
    } catch(e){}
  }
  return result;
}

async function apiSetDefaultPaymentMethod(pmId){
  var result = await _callPaymentMethodsAPI({action:'set_default', payment_method_id:pmId});
  // Update local Supabase table immediately
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

async function apiSetupNewCard(){
  return await _callPaymentMethodsAPI({action:'setup'});
}
