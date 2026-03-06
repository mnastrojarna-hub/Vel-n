// i18n-aliases.js – Key aliases for compatibility between i18n definitions and source code
(function(){
for(var l in I18N){
  var a=I18N[l].auth;
  if(a){
    a.fpStep1Title=a.fpS1;a.fpStep1Sub=a.fpS1s;a.fpSendCode=a.fpSend;
    a.fpStep2Title=a.fpS2;a.fpStep2Sub=a.fpS2s;a.fpCodeLabel=a.fpCode;
    a.fpVerifyCode=a.fpVerify;a.fpStep3Title=a.fpS3;a.fpStep3Sub=a.fpS3s;
    a.fpNewPass=a.newPass;a.fpRepeatPass=a.repeatPass;a.fpSetPass=a.fpSet;
  }
  var r=I18N[l].res;
  if(r){
    r.policy7days=r.plus7days;r.policy2to7days=r.range2to7;r.policyUnder2days=r.under2days;
    r.refundNone=r.noRefund;r.restoredMsg=r.resRestored;r.daysRemaining=r.daysToStart;
    r.sent=I18N[l].common?I18N[l].common.sent:'Sent';
  }
  var c=I18N[l].cart;
  if(c){
    c.applied=({cs:'uplatněna',en:'applied',de:'angewendet',es:'aplicado',fr:'appliquée',nl:'toegepast',pl:'zastosowano'})[l]||'applied';
  }
}
})();
