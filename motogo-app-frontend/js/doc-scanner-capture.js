// ===== DOC-SCANNER-CAPTURE.JS – Image quality & multi-frame capture (v4.1.0) =====
// Extends DocScanner with image analysis, multi-capture, and debug photo saving.
// Loaded after doc-scanner-camera.js

(function(){
  'use strict';

  // Image preprocessing – grayscale + gamma + contrast stretch (NO binarization)
  function _enhanceForOCR(ctx, w, h){
    var img=ctx.getImageData(0,0,w,h), d=img.data;
    var sumB=0, count=w*h;
    // Convert to grayscale and measure brightness
    for(var i=0;i<d.length;i+=4){
      var g=Math.round(d[i]*0.299+d[i+1]*0.587+d[i+2]*0.114);
      d[i]=d[i+1]=d[i+2]=g;
      sumB+=g;
    }
    var mean=sumB/count;
    // Gamma correction for dark/bright images
    var gamma=1.0;
    if(mean<80) gamma=0.4;
    else if(mean<110) gamma=0.55;
    else if(mean<130) gamma=0.7;
    else if(mean>200) gamma=1.8;
    else if(mean>180) gamma=1.4;
    if(gamma!==1.0){
      var lut=new Uint8Array(256);
      for(var j=0;j<256;j++) lut[j]=Math.min(255,Math.round(255*Math.pow(j/255,gamma)));
      for(var k=0;k<d.length;k+=4){d[k]=lut[d[k]];d[k+1]=lut[d[k+1]];d[k+2]=lut[d[k+2]];}
      // Recalc mean
      sumB=0; for(var r=0;r<d.length;r+=4) sumB+=d[r]; mean=sumB/count;
    }
    // Strong contrast stretch: map [mean-80, mean+80] → [0, 255]
    var lo=Math.max(0,mean-80), hi=Math.min(255,mean+80);
    var range=hi-lo; if(range<50) range=50;
    for(var p=0;p<d.length;p+=4){
      var v=Math.max(0,Math.min(255,Math.round((d[p]-lo)*255/range)));
      d[p]=d[p+1]=d[p+2]=v;
    }
    ctx.putImageData(img,0,0);
  }

  // Enhance for human viewing / gallery save (NO binarization)
  function _enhanceForDisplay(ctx, w, h){
    var img=ctx.getImageData(0,0,w,h), d=img.data;
    var sumB=0, count=w*h;
    for(var i=0;i<d.length;i+=4){
      sumB += d[i]*0.299+d[i+1]*0.587+d[i+2]*0.114;
    }
    var mean=sumB/count;
    // Gamma correction for dark images
    var gamma=1.0;
    if(mean<90) gamma=0.45;
    else if(mean<120) gamma=0.6;
    if(gamma<1.0){
      var lut=new Uint8Array(256);
      for(var j=0;j<256;j++) lut[j]=Math.min(255,Math.round(255*Math.pow(j/255,gamma)));
      for(var k=0;k<d.length;k+=4){ d[k]=lut[d[k]]; d[k+1]=lut[d[k+1]]; d[k+2]=lut[d[k+2]]; }
      // Recalc mean after gamma
      sumB=0;
      for(var m=0;m<d.length;m+=4) sumB+=d[m]*0.299+d[m+1]*0.587+d[m+2]*0.114;
      mean=sumB/count;
    }
    // Contrast boost: (val - mean) * 1.3 + mean + 20
    for(var p=0;p<d.length;p+=4){
      d[p]  =Math.max(0,Math.min(255,Math.round((d[p]-mean)*1.3+mean+20)));
      d[p+1]=Math.max(0,Math.min(255,Math.round((d[p+1]-mean)*1.3+mean+20)));
      d[p+2]=Math.max(0,Math.min(255,Math.round((d[p+2]-mean)*1.3+mean+20)));
    }
    ctx.putImageData(img,0,0);
  }

  function checkImageQuality(canvas){
    var ctx=canvas.getContext('2d'), w=canvas.width, h=canvas.height;
    var img=ctx.getImageData(0,0,w,h), d=img.data;
    var sumB=0,sumSq=0,edgeSum=0,count=w*h;
    var gray=new Uint8Array(count);
    for(var i=0;i<d.length;i+=4){
      var g=d[i]*0.299+d[i+1]*0.587+d[i+2]*0.114;
      gray[i/4]=g; sumB+=g; sumSq+=g*g;
    }
    var meanB=sumB/count, variance=sumSq/count-meanB*meanB;
    for(var y=1;y<h-1;y+=2) for(var x=1;x<w-1;x+=2){
      var lap=-4*gray[y*w+x]+gray[(y-1)*w+x]+gray[(y+1)*w+x]+gray[y*w+x-1]+gray[y*w+x+1];
      edgeSum+=Math.abs(lap);
    }
    var edge=edgeSum/(count/4);
    var cxA=Math.round(w*0.2),cxB=Math.round(w*0.8);
    var cyA=Math.round(h*0.2),cyB=Math.round(h*0.8);
    var cSum=0,cCnt=0,bSum=0,bCnt=0;
    for(var fy=0;fy<h;fy+=4) for(var fx=0;fx<w;fx+=4){
      var v=gray[fy*w+fx];
      if(fx>=cxA&&fx<=cxB&&fy>=cyA&&fy<=cyB){cSum+=v;cCnt++;}
      else{bSum+=v;bCnt++;}
    }
    var centerMean=cCnt?cSum/cCnt:0, borderMean=bCnt?bSum/bCnt:0;
    var docInFrame=Math.abs(centerMean-borderMean)>15 && edge>=2.5;
    return {
      brightness:meanB, contrast:Math.sqrt(variance), sharpness:edge,
      centerBright:centerMean, borderBright:borderMean, docInFrame:docInFrame,
      isTooDark:meanB<80, isTooBright:meanB>220, isBlurry:edge<2.0,
      isLowContrast:Math.sqrt(variance)<25,
      isGood:meanB>=55&&meanB<=235&&edge>=2.0&&Math.sqrt(variance)>=20&&docInFrame
    };
  }

  function _qualityScore(q){
    var s=0;
    s -= Math.abs(q.brightness-130)*0.3;
    s += q.sharpness*10;
    s += q.contrast*0.5;
    if(q.docInFrame) s+=30;
    if(q.isTooDark||q.isTooBright) s-=40;
    if(q.isBlurry) s-=25;
    return s;
  }

  // 50 frames, 150ms interval, min 15 valid, top 10 OCR'd
  function multiCapture(progressCb, doneCb){
    var SHOTS=50, INTERVAL=150, MIN_VALID=15;
    var frames=[], idx=0, extraRounds=0;
    function take(){
      if(idx>=SHOTS){
        if(frames.length<MIN_VALID && extraRounds<20){
          extraRounds++;
          idx++;
          if(progressCb) progressCb(idx, SHOTS+extraRounds, frames.length);
          var ce=DocScanner.captureFrame();
          if(ce){
            var qe=checkImageQuality(ce);
            if(qe.docInFrame && !qe.isBlurry){
              var c2e=document.createElement('canvas');
              c2e.width=ce.width;c2e.height=ce.height;
              c2e.getContext('2d').drawImage(ce,0,0);
              frames.push({canvas:c2e, quality:qe});
            }
          }
          setTimeout(take, INTERVAL);
          return;
        }
        _saveToGallery(frames);
        _pickBestMulti(frames, doneCb);
        return;
      }
      var c=DocScanner.captureFrame();
      if(c){
        var q=checkImageQuality(c);
        if(q.docInFrame && !q.isBlurry){
          var c2=document.createElement('canvas');
          c2.width=c.width;c2.height=c.height;
          c2.getContext('2d').drawImage(c,0,0);
          frames.push({canvas:c2, quality:q});
        }
      }
      idx++;
      if(progressCb) progressCb(idx, SHOTS, frames.length);
      setTimeout(take, INTERVAL);
    }
    take();
  }

  // Save debug photos to device GALLERY (Pictures/MotoGo24/)
  function _saveToGallery(frames){
    try{
      var sorted=frames.slice().sort(function(a,b){return _qualityScore(b.quality)-_qualityScore(a.quality);});
      var top5=sorted.slice(0,Math.min(5,sorted.length));
      var docType=DocScanner.getDocType();
      // Save to public Pictures directory so they appear in gallery
      if(window.cordova && window.resolveLocalFileSystemURL){
        var picDir=cordova.file.externalRootDirectory;
        if(!picDir) picDir=cordova.file.externalDataDirectory;
        if(picDir){
          window.resolveLocalFileSystemURL(picDir, function(root){
            root.getDirectory('Pictures', {create:true}, function(picsDir){
              picsDir.getDirectory('MotoGo24', {create:true}, function(mgDir){
                top5.forEach(function(f,fi){
                  // Enhance copy for gallery (keep original raw)
                  var ec=document.createElement('canvas');
                  ec.width=f.canvas.width; ec.height=f.canvas.height;
                  var ectx=ec.getContext('2d');
                  ectx.drawImage(f.canvas,0,0);
                  _enhanceForDisplay(ectx, ec.width, ec.height);
                  var b64=ec.toDataURL('image/jpeg',0.92).split(',')[1];
                  var byteChars=atob(b64);
                  var byteArr=new Uint8Array(byteChars.length);
                  for(var j=0;j<byteChars.length;j++) byteArr[j]=byteChars.charCodeAt(j);
                  var blob=new Blob([byteArr],{type:'image/jpeg'});
                  var fname='scan_'+docType+'_'+fi+'_'+Date.now()+'.jpg';
                  mgDir.getFile(fname,{create:true},function(fileEntry){
                    fileEntry.createWriter(function(writer){
                      writer.write(blob);
                      console.log('[DocScanner] Gallery photo: '+fileEntry.nativeURL);
                      // Trigger media scanner so photo appears in gallery
                      if(window.plugins && window.plugins.mediascanner){
                        window.plugins.mediascanner.scan(fileEntry.nativeURL);
                      }
                    });
                  });
                });
              });
            });
          });
        }
      }
    }catch(e){ console.warn('[DocScanner] Gallery save failed:',e); }
  }

  // Send only the BEST frame to Mindee API (saves API calls)
  function _pickBestMulti(frames, cb){
    if(!frames.length){ cb(new Error('No valid frames'),''); return; }
    frames.sort(function(a,b){return _qualityScore(b.quality)-_qualityScore(a.quality);});
    // Send only the BEST frame to Mindee API (saves API calls)
    var best = frames[0];
    DocScanner.runOCR(best.canvas, function(err, text){
      cb(err, text);
    });
  }

  // Attach to DocScanner
  DocScanner.checkImageQuality = checkImageQuality;
  DocScanner.multiCapture = multiCapture;
  DocScanner._enhanceForOCR = _enhanceForOCR;
  DocScanner._enhanceForDisplay = _enhanceForDisplay;
  DocScanner._qualityScore = _qualityScore;
})();
