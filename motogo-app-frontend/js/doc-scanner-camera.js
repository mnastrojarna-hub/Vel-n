// ===== DOC-SCANNER-CAMERA.JS – Camera management (v4.1.0) =====
// Handles camera permissions, stream lifecycle, exposure adjustment.
// Part of DocScanner module – loaded before doc-scanner-capture.js

var DocScanner = (function(){
  'use strict';
  var _stream = null;
  var _video = null;
  var _overlay = null;
  var _docType = 'id_front';
  var _idType = 'op';
  var _results = {};
  var _worker = null;
  var _workerReady = false;

  var DOC_SEQUENCE = ['id_front','id_back','dl_front','dl_back'];
  var DOC_LABELS = {
    id_front:'Občanský průkaz – přední strana',
    id_back:'Občanský průkaz – zadní strana',
    passport_front:'Cestovní pas – datová strana',
    dl_front:'Řidičský průkaz – přední strana',
    dl_back:'Řidičský průkaz – zadní strana'
  };
  var DOC_ICONS = {
    id_front:'🪪', id_back:'🪪', passport_front:'📕',
    dl_front:'🏍️', dl_back:'🏍️'
  };

  function getSequence(){
    if(_idType==='passport') return ['passport_front','dl_front','dl_back'];
    return ['id_front','id_back','dl_front','dl_back'];
  }

  // Worker init stub – Mindee API handles OCR server-side
  function initWorker(cb){ if(cb) cb(); }

  function _killStream(s){
    if(s){ try{ s.getTracks().forEach(function(t){ t.stop(); }); }catch(e){} }
  }

  function _adjustExposure(stream){
    try{
      var track = stream.getVideoTracks()[0];
      if(!track || typeof track.getCapabilities !== 'function') return;
      var caps = track.getCapabilities();
      var adv = {};
      if(caps.exposureMode) adv.exposureMode = 'continuous';
      if(caps.exposureCompensation){
        var min=caps.exposureCompensation.min, max=caps.exposureCompensation.max;
        adv.exposureCompensation = min + (max-min)*0.55;
      }
      if(caps.focusMode) adv.focusMode = 'continuous';
      if(caps.brightness){
        var bMin=caps.brightness.min, bMax=caps.brightness.max;
        adv.brightness = bMin + (bMax-bMin)*0.6;
      }
      if(caps.torch) adv.torch = false;
      if(caps.whiteBalanceMode) adv.whiteBalanceMode = 'continuous';
      if(Object.keys(adv).length) track.applyConstraints({advanced:[adv]}).catch(function(){});
    }catch(e){}
  }

  function _attachStream(stream){
    _stream = stream;
    _video.srcObject = stream;
    _video.setAttribute('playsinline','true');
    _adjustExposure(stream);
    return _video.play();
  }

  function _tryGetMedia(constraints, label, timeoutMs){
    var tid, timedOut = false;
    return new Promise(function(resolve, reject){
      tid = setTimeout(function(){
        timedOut = true;
        reject(new Error('Timeout: '+label+' ('+timeoutMs+'ms)'));
      }, timeoutMs);
      navigator.mediaDevices.getUserMedia(constraints)
        .then(function(s){ if(timedOut){_killStream(s);return;} clearTimeout(tid); resolve(s); })
        .catch(function(e){ clearTimeout(tid); if(!timedOut) reject(e); });
    });
  }

  function _requestCamPerm(){
    var cp = window.cordova && window.cordova.plugins && window.cordova.plugins.permissions;
    if(cp && cp.CAMERA){
      return new Promise(function(resolve){
        cp.checkPermission(cp.CAMERA, function(s){
          if(s.hasPermission){ resolve('granted'); return; }
          cp.requestPermission(cp.CAMERA, function(r){
            resolve(r.hasPermission ? 'granted' : 'denied');
          }, function(){ resolve('error'); });
        }, function(){ resolve('error'); });
      });
    }
    if(navigator.permissions && navigator.permissions.query){
      return navigator.permissions.query({name:'camera'})
        .then(function(s){ return s.state; })
        .catch(function(){ return 'unknown'; });
    }
    return Promise.resolve('unknown');
  }

  function startCamera(videoEl, overlayEl){
    _video = videoEl;
    _overlay = overlayEl;
    if(!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia){
      return Promise.reject(new Error('Camera API not available'));
    }
    var c1 = {video:{facingMode:'environment',width:{ideal:3840},height:{ideal:2160},frameRate:{ideal:30,min:15},focusMode:{ideal:'continuous'},exposureMode:{ideal:'continuous'}},audio:false};
    var c2 = {video:true, audio:false};
    var c3 = {video:{facingMode:'user'}, audio:false};
    return _requestCamPerm().then(function(perm){
      if(perm==='denied') throw new Error('Camera permission denied by user/system');
      return _tryGetMedia(c1,'env-HD',12000)
        .then(function(s){ return _attachStream(s); })
        .catch(function(){ _killStream(_stream); _stream=null;
          return _tryGetMedia(c2,'basic',10000).then(function(s){ return _attachStream(s); });
        })
        .catch(function(){ _killStream(_stream); _stream=null;
          return _tryGetMedia(c3,'front-cam',8000).then(function(s){ return _attachStream(s); });
        })
        .catch(function(e){ _killStream(_stream); _stream=null; throw e; });
    });
  }

  function stopCamera(){
    if(_stream){ _stream.getTracks().forEach(function(t){t.stop();}); _stream=null; }
    if(_video) _video.srcObject=null;
  }

  function captureFrame(){
    if(!_video) return null;
    var vw=_video.videoWidth, vh=_video.videoHeight;
    if(!vw||!vh) return null;
    // Crop to document area – landscape card ratio ~1.586
    var cropW=Math.round(vw*0.92), cropH=Math.round(cropW/1.586);
    if(cropH>vh*0.90){cropH=Math.round(vh*0.90);cropW=Math.round(cropH*1.586);}
    var cropX=Math.round((vw-cropW)/2), cropY=Math.round((vh-cropH)/2);
    var c=document.createElement('canvas');
    c.width=cropW; c.height=cropH;
    c.getContext('2d').drawImage(_video, cropX,cropY,cropW,cropH, 0,0,cropW,cropH);
    return c;
  }

  // Expose internals needed by capture/ocr modules
  return {
    _internals: {
      getStream:function(){return _stream;}, getVideo:function(){return _video;},
      getWorker:function(){return _worker;}, isWorkerReady:function(){return _workerReady;},
      getDocType:function(){return _docType;}, setDocType:function(t){_docType=t;},
      getResults:function(){return _results;}, setResult:function(k,v){_results[k]=v;},
      getIdType:function(){return _idType;}, setIdType:function(t){_idType=t;}
    },
    DOC_SEQUENCE:DOC_SEQUENCE, DOC_LABELS:DOC_LABELS, DOC_ICONS:DOC_ICONS,
    getSequence:getSequence, setIdType:function(t){_idType=t;},
    initWorker:initWorker,
    startCamera:startCamera, stopCamera:stopCamera, captureFrame:captureFrame,
    setDocType:function(t){_docType=t;}, getDocType:function(){return _docType;},
    setResult:function(k,v){_results[k]=v;}, getResults:function(){return _results;},
    isWorkerReady:function(){return _workerReady;},
    reset:function(){_results={};_docType='id_front';_idType='op';}
  };
})();
