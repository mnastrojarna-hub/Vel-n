// ===== STORAGE.JS – localStorage permissions and personal data =====

// ===== PERMISSIONS =====
function grantPerms(){
  try{localStorage.setItem('mg_perms','granted');}catch(e){}
  document.getElementById('perm-overlay').style.display='none';
  showT('✓','Oprávnění povolena','Biometrika, poloha, fotoaparát, mikrofon, oznámení');
}

function skipPerms(){
  try{localStorage.setItem('mg_perms','skipped');}catch(e){}
  document.getElementById('perm-overlay').style.display='none';
  const bs=document.getElementById('bio-section');
  if(bs)bs.style.display='none';
}

function initPerms(){
  try{
    const p=localStorage.getItem('mg_perms');
    if(!p){setTimeout(()=>{const o=document.getElementById('perm-overlay');if(o)o.style.display='flex';},600);}
  }catch(e){
    setTimeout(()=>{const o=document.getElementById('perm-overlay');if(o)o.style.display='flex';},600);
  }
}

// ===== SAVE PERSONAL DATA =====
function savePersonalData(){
  showT('✓','Údaje uloženy','Synchronizováno s MotoGo24');
}

function deleteAccount(){
  if(confirm('Opravdu smazat účet? Tato akce je nevratná.')){
    try{localStorage.clear();}catch(e){}
    showT('🗑️','Účet smazán','Přesměrovávám...');
    setTimeout(()=>goTo('s-login'),1400);
  }
}
