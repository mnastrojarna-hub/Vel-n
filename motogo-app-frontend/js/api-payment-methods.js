// ===== API-PAYMENT-METHODS.JS – Stripe saved payment methods =====

async function _callPaymentMethodsAPI(body){
  var cfg = window.MOTOGO_CONFIG || {};
  var baseUrl = cfg.SUPABASE_URL;
  var anonKey = cfg.SUPABASE_ANON_KEY;
  if(!baseUrl) return {success:false, error:'No config'};
  var token = anonKey;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}
  try {
    var resp = await fetch(baseUrl + '/functions/v1/manage-payment-methods', {
      method: 'POST',
      headers: {'Content-Type':'application/json','Authorization':'Bearer '+token,'apikey':anonKey||''},
      body: JSON.stringify(body)
    });
    return await resp.json();
  } catch(e){ return {success:false, error:e.message}; }
}

async function apiFetchPaymentMethods(){
  return await _callPaymentMethodsAPI({action:'list'});
}

async function apiDeletePaymentMethod(pmId){
  return await _callPaymentMethodsAPI({action:'delete', payment_method_id:pmId});
}

async function apiSetDefaultPaymentMethod(pmId){
  return await _callPaymentMethodsAPI({action:'set_default', payment_method_id:pmId});
}
