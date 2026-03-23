// ===== API-PAYMENT-METHODS.JS – Stripe saved payment methods =====

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

async function apiFetchPaymentMethods(){
  return await _callPaymentMethodsAPI({action:'list'});
}

async function apiDeletePaymentMethod(pmId){
  return await _callPaymentMethodsAPI({action:'delete', payment_method_id:pmId});
}

async function apiSetDefaultPaymentMethod(pmId){
  return await _callPaymentMethodsAPI({action:'set_default', payment_method_id:pmId});
}

async function apiSetupNewCard(){
  return await _callPaymentMethodsAPI({action:'setup'});
}
