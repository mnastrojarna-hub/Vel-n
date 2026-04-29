// ===== MotoGo24 Web — Rezervace: bank-style in-page camera (frame + auto burst) =====
var MG = window.MG || {};
window.MG = MG;

// Public API:
//   MG._rezOpenCamera(docType, onCapture)
//     onCapture(base64Array)  — array of best frames (3–6) ready for OCR
// Falls back to native file input with capture=environment when getUserMedia is unavailable.

(function(){
  var BURST_COUNT = 5;        // 5 frames per side
  var BURST_INTERVAL_MS = 350; // ~1.75s total — enough time to vary focus/exposure
  var FRAME_RATIO = 1.586;    // ID-1 (CR80) — same as banks; OP / ŘP both fit

  function hasMediaDevices(){
    return !!(navigator && navigator.mediaDevices && navigator.mediaDevices.getUserMedia &&
              window.HTMLCanvasElement && document.createElement('canvas').getContext);
  }

  function fileToBase64(file){
    return new Promise(function(resolve,reject){
      var fr=new FileReader();
      fr.onload=function(){
        var img=new Image();
        img.onload=function(){
          var canvas=document.createElement('canvas');
          var maxW=1600,w=img.width,h=img.height;
          if(w>maxW){h=Math.round(h*maxW/w);w=maxW;}
          canvas.width=w;canvas.height=h;
          canvas.getContext('2d').drawImage(img,0,0,w,h);
          resolve(canvas.toDataURL('image/jpeg',0.85).split(',')[1]);
        };
        img.onerror=reject;
        img.src=fr.result;
      };
      fr.onerror=reject;
      fr.readAsDataURL(file);
    });
  }

  // Native fallback — single shot via <input capture=environment>
  function nativeCapture(onCapture){
    var input=document.createElement('input');
    input.type='file'; input.accept='image/*';
    input.setAttribute('capture','environment');
    input.style.display='none';
    document.body.appendChild(input);
    input.onchange=function(){
      var file=input.files&&input.files[0];
      document.body.removeChild(input);
      if(!file){ onCapture([]); return; }
      fileToBase64(file).then(function(b64){ onCapture([b64]); }).catch(function(){ onCapture([]); });
    };
    input.click();
  }

  // Native gallery upload (any image / PDF)
  MG._rezPickFromGallery = function(onPick){
    var input=document.createElement('input');
    input.type='file'; input.accept='image/*,.pdf';
    input.style.display='none';
    document.body.appendChild(input);
    input.onchange=function(){
      var file=input.files&&input.files[0];
      document.body.removeChild(input);
      if(!file){ onPick(null,null); return; }
      if(file.type && file.type.indexOf('image')!==-1){
        fileToBase64(file).then(function(b64){ onPick(b64,file); }).catch(function(){ onPick(null,file); });
      } else {
        onPick(null, file); // PDF → caller handles raw upload
      }
    };
    input.click();
  };

  // Score a frame on focus (Laplacian-ish variance) inside the frame rectangle
  // Higher = sharper. Used to pick the best from the burst.
  function scoreSharpness(canvas, rect){
    try{
      var ctx=canvas.getContext('2d');
      var sx=Math.max(0,Math.floor(rect.x)), sy=Math.max(0,Math.floor(rect.y));
      var sw=Math.min(canvas.width-sx, Math.floor(rect.w));
      var sh=Math.min(canvas.height-sy, Math.floor(rect.h));
      if(sw<10||sh<10) return 0;
      var img=ctx.getImageData(sx,sy,sw,sh).data;
      // Sample every 4th px to keep it cheap
      var step=4, sum=0, sumSq=0, n=0;
      for(var y=1;y<sh-1;y+=step){
        for(var x=1;x<sw-1;x+=step){
          var i=(y*sw+x)*4;
          var g=(img[i]*0.299 + img[i+1]*0.587 + img[i+2]*0.114);
          var iL=((y)*sw+(x-1))*4, iR=((y)*sw+(x+1))*4;
          var iU=((y-1)*sw+x)*4, iD=((y+1)*sw+x)*4;
          var gL=(img[iL]*0.299+img[iL+1]*0.587+img[iL+2]*0.114);
          var gR=(img[iR]*0.299+img[iR+1]*0.587+img[iR+2]*0.114);
          var gU=(img[iU]*0.299+img[iU+1]*0.587+img[iU+2]*0.114);
          var gD=(img[iD]*0.299+img[iD+1]*0.587+img[iD+2]*0.114);
          var lap=Math.abs(4*g - gL - gR - gU - gD);
          sum+=lap; sumSq+=lap*lap; n++;
        }
      }
      if(n===0) return 0;
      var mean=sum/n;
      return (sumSq/n) - mean*mean; // variance of Laplacian
    }catch(e){ return 0; }
  }

  function buildOverlay(docType){
    var label = docType==='id' ? 'Doklad totožnosti' : 'Řidičský průkaz';
    var wrap=document.createElement('div');
    wrap.id='rez-cam-overlay';
    wrap.innerHTML =
      '<div class="rez-cam-bg"></div>'+
      '<video class="rez-cam-video" autoplay playsinline muted></video>'+
      '<div class="rez-cam-mask">'+
        '<div class="rez-cam-frame">'+
          '<div class="rez-cam-corner tl"></div><div class="rez-cam-corner tr"></div>'+
          '<div class="rez-cam-corner bl"></div><div class="rez-cam-corner br"></div>'+
        '</div>'+
      '</div>'+
      '<div class="rez-cam-top">'+
        '<button type="button" class="rez-cam-close" aria-label="Zavřít">&times;</button>'+
        '<div class="rez-cam-title">'+label+'</div>'+
      '</div>'+
      '<div class="rez-cam-hint">Vložte doklad celý do rámečku. Držte telefon rovně, dobré osvětlení.</div>'+
      '<div class="rez-cam-bottom">'+
        '<button type="button" class="rez-cam-shoot">'+
          '<span class="rez-cam-shoot-inner"></span>'+
          '<span class="rez-cam-shoot-label">Spustit sken</span>'+
        '</button>'+
        '<div class="rez-cam-progress" style="display:none"><div class="rez-cam-progress-track"><div class="rez-cam-progress-bar"></div></div><div class="rez-cam-progress-text">Snímám…</div></div>'+
      '</div>';
    document.body.appendChild(wrap);
    return wrap;
  }

  function frameRectInVideo(video){
    // The frame is centered, ~88% width on phones, capped by aspect ratio.
    var vw=video.videoWidth||1280, vh=video.videoHeight||720;
    // Choose orientation matching the video — landscape vs portrait
    var landscape = vw >= vh;
    var fw, fh;
    if(landscape){
      fw = Math.round(vw*0.78);
      fh = Math.round(fw / FRAME_RATIO);
      if(fh > vh*0.78){ fh = Math.round(vh*0.78); fw = Math.round(fh * FRAME_RATIO); }
    } else {
      // portrait — frame is rotated (still ID-1, but width<height in this orientation)
      fh = Math.round(vh*0.55);
      fw = Math.round(fh / FRAME_RATIO * 1); // wider than tall when held landscape — but on portrait we still want horizontal card
      // simpler: keep horizontal card on portrait phone
      fw = Math.round(vw*0.86);
      fh = Math.round(fw / FRAME_RATIO);
    }
    return { x: Math.round((vw-fw)/2), y: Math.round((vh-fh)/2), w: fw, h: fh };
  }

  function captureFrame(video, rect){
    var canvas=document.createElement('canvas');
    // Crop to the frame rectangle, max 1600 wide for OCR speed
    var maxW=1600;
    var w=rect.w, h=rect.h;
    if(w>maxW){ h=Math.round(h*maxW/w); w=maxW; }
    canvas.width=w; canvas.height=h;
    var ctx=canvas.getContext('2d');
    ctx.drawImage(video, rect.x, rect.y, rect.w, rect.h, 0, 0, w, h);
    return canvas;
  }

  MG._rezOpenCamera = function(docType, onCapture){
    if(!hasMediaDevices()){
      nativeCapture(onCapture);
      return;
    }

    var overlay=buildOverlay(docType);
    var video=overlay.querySelector('.rez-cam-video');
    var shootBtn=overlay.querySelector('.rez-cam-shoot');
    var closeBtn=overlay.querySelector('.rez-cam-close');
    var progress=overlay.querySelector('.rez-cam-progress');
    var progressBar=overlay.querySelector('.rez-cam-progress-bar');
    var progressText=overlay.querySelector('.rez-cam-progress-text');
    var stream=null;
    var closed=false;

    function cleanup(){
      if(closed) return;
      closed=true;
      try{ if(stream){ stream.getTracks().forEach(function(t){ t.stop(); }); } }catch(e){}
      try{ if(overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay); }catch(e){}
    }

    closeBtn.addEventListener('click', function(){ cleanup(); onCapture([]); });

    var constraints = {
      audio: false,
      video: {
        facingMode: { ideal: 'environment' },
        width:  { ideal: 1920 },
        height: { ideal: 1080 }
      }
    };

    navigator.mediaDevices.getUserMedia(constraints).then(function(s){
      stream=s;
      video.srcObject=s;
      // Try to lock focus to continuous on supported browsers
      try{
        var track=s.getVideoTracks()[0];
        if(track && track.getCapabilities){
          var caps=track.getCapabilities();
          var advanced=[];
          if(caps.focusMode && caps.focusMode.indexOf('continuous')!==-1) advanced.push({focusMode:'continuous'});
          if(caps.exposureMode && caps.exposureMode.indexOf('continuous')!==-1) advanced.push({exposureMode:'continuous'});
          if(advanced.length) track.applyConstraints({advanced:advanced}).catch(function(){});
        }
      }catch(e){}
    }).catch(function(err){
      // Permission denied or HW failure → fall back to native
      cleanup();
      nativeCapture(onCapture);
    });

    shootBtn.addEventListener('click', function(){
      if(closed) return;
      shootBtn.disabled=true; shootBtn.style.opacity='.5';
      progress.style.display='flex';
      var rect=frameRectInVideo(video);
      var frames=[];
      var done=0;

      function shotOnce(){
        if(closed) return;
        var canvas=captureFrame(video, rect);
        var sharp=scoreSharpness(canvas, {x:0,y:0,w:canvas.width,h:canvas.height});
        var b64=canvas.toDataURL('image/jpeg',0.85).split(',')[1];
        frames.push({ b64:b64, sharp:sharp });
        done++;
        var pct=Math.round(done*100/BURST_COUNT);
        progressBar.style.width=pct+'%';
        progressText.textContent='Snímek '+done+'/'+BURST_COUNT;
        if(done<BURST_COUNT){
          setTimeout(shotOnce, BURST_INTERVAL_MS);
        } else {
          // Sort by sharpness descending — best first
          frames.sort(function(a,b){ return b.sharp - a.sharp; });
          var ordered=frames.map(function(f){ return f.b64; });
          cleanup();
          onCapture(ordered);
        }
      }

      // Small initial delay so user can settle the document
      setTimeout(shotOnce, 250);
    });
  };

  // Sequentially run OCR over a list of base64 frames; return first result with fields,
  // or last error response for status display.
  MG._rezOcrBurst = async function(frames, docType, userId){
    var lastResp=null;
    for(var i=0;i<frames.length;i++){
      try{
        var res=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/scan-document',{
          method:'POST',
          headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
          body:JSON.stringify({image_base64:frames[i],document_type:docType==='id'?'id':'dl',user_id:userId||null})
        });
        var resp=await res.json();
        lastResp=resp;
        var f=(resp&&resp.data)||(resp&&resp.fields)||null;
        if(f && Object.keys(f).length>0){
          // Need at least one meaningful field to consider it a success
          var keyOk = (docType==='id') ? (f.idNumber || f.firstName || f.lastName || f.dateOfBirth)
                                       : (f.licenseNumber || f.licenseCategory || f.licenseExpiry);
          if(keyOk){
            return { ok:true, fields:f, frameIndex:i, frame:frames[i] };
          }
        }
      }catch(e){ lastResp={ error:String(e) }; }
    }
    return { ok:false, response:lastResp, frame: frames[0]||null };
  };
})();
