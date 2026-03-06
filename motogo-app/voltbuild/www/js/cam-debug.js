// ===== CAM-DEBUG.JS – Console-only logging stub (v2.0) =====
// On-screen panel removed. All log calls go to console only.
// Keeps public API so existing CamDebug.log() calls don't break.

var CamDebug = (function(){
  'use strict';
  function log(tag, msg, data){
    var ts = new Date().toTimeString().substring(0,8);
    var line = ts + ' [' + tag + '] ' + msg;
    if(data !== undefined){
      try{
        if(data instanceof Error) line += ' | ' + data.name + ': ' + data.message;
        else if(typeof data === 'object') line += ' | ' + JSON.stringify(data);
        else line += ' | ' + String(data);
      }catch(e){}
    }
    console.log('[CamDebug] ' + line);
  }
  return {
    log: log,
    clear: function(){},
    hide: function(){},
    show: function(){},
    dump: function(){ return ''; },
    logEnv: function(){}
  };
})();
