// ===== DOC-PARSER-ID.JS – Czech ID card parsers (v4.1.0) =====
// Zone-based parsing for občanský průkaz front & back.
// Loaded after doc-parser-core.js

(function(){
  'use strict';
  var C = DocParser._c;

  // Czech ID front zones (% of total lines)
  var Z = {
    headerEnd:0.20, surnameStart:0.12, surnameEnd:0.40,
    nameStart:0.20, nameEnd:0.50, dobStart:0.30, dobEnd:0.65, mrzStart:0.70
  };

  function parseIdFront(text){
    var data={}, ls=C.lines(text), total=ls.length;

    // 1. MRZ (bottom 30%)
    var mrzLines=ls.filter(function(l,i){ return C.zonePos(i,total)>=Z.mrzStart; });
    if(mrzLines.length>=2){
      var mrz=C.parseMRZ(mrzLines);
      if(mrz.firstName) data.firstName=mrz.firstName;
      if(mrz.lastName) data.lastName=mrz.lastName;
      if(mrz.dob) data.dob=mrz.dob;
      if(mrz.idNumber) data.idNumber=mrz.idNumber;
    }
    if(!data.firstName||!data.lastName){
      var mrzFull=C.parseMRZ(ls);
      if(mrzFull.firstName&&!data.firstName) data.firstName=mrzFull.firstName;
      if(mrzFull.lastName&&!data.lastName) data.lastName=mrzFull.lastName;
      if(mrzFull.dob&&!data.dob) data.dob=mrzFull.dob;
      if(mrzFull.idNumber&&!data.idNumber) data.idNumber=mrzFull.idNumber;
    }

    // 2. Labeled fields in valid zones
    for(var i=0;i<ls.length;i++){
      var l=ls[i], pos=C.zonePos(i,total);
      if(C.isSurnameLabel(l)&&!data.lastName&&pos>=Z.surnameStart&&pos<=Z.surnameEnd){
        var sv=C.valueNearLabel(ls,i,C.isValidName);
        if(sv) data.lastName=sv;
      }
      if(C.isNameLabel(l)&&!data.firstName&&pos>=Z.nameStart&&pos<=Z.nameEnd){
        var nv=C.valueNearLabel(ls,i,C.isValidName);
        if(nv) data.firstName=nv;
      }
      if(C.isDobLabel(l)&&!data.dob&&pos>=Z.dobStart&&pos<=Z.dobEnd){
        var d1=C.extractDate(l);
        if(d1&&d1.y>1920&&d1.y<2015) data.dob=d1.str;
        if(!data.dob&&i+1<ls.length){
          var d2=C.extractDate(ls[i+1]);
          if(d2&&d2.y>1920&&d2.y<2015) data.dob=d2.str;
        }
      }
      if(!data.idNumber){
        var dn=l.match(/\b(\d{6,9})\b/);
        if(dn&&pos>Z.headerEnd) data.idNumber=dn[1];
      }
    }

    // 3. Positional fallback – skip header zone
    if(!data.lastName||!data.firstName){
      for(var fi=0;fi<ls.length;fi++){
        var fpos=C.zonePos(fi,total);
        if(fpos<Z.headerEnd) continue;
        if(fpos>Z.nameEnd+0.10) break;
        var fl=ls[fi];
        if(C.isValidName(fl)&&!C.isSurnameLabel(fl)&&!C.isNameLabel(fl)&&!C.isDobLabel(fl)){
          var cv=C.clean(fl);
          if(cv.length>=2&&cv.length<=30){
            if(!data.lastName) data.lastName=cv;
            else if(!data.firstName) data.firstName=cv;
          }
        }
      }
    }

    // 4. Date fallback in DOB zone
    if(!data.dob){
      for(var di=0;di<ls.length;di++){
        var dpos=C.zonePos(di,total);
        if(dpos<Z.dobStart||dpos>Z.dobEnd) continue;
        var sd=C.extractDate(ls[di]);
        if(sd&&sd.y>1940&&sd.y<2010){ data.dob=sd.str; break; }
      }
    }
    if(data.firstName) data.firstName=C.fixCzechName(data.firstName);
    if(data.lastName) data.lastName=C.fixCzechName(data.lastName);
    return data;
  }

  function parseIdBack(text){
    var data={}, ls=C.lines(text);
    var addressFound=false;
    for(var i=0;i<ls.length;i++){
      var l=ls[i];
      // Try labeled approach
      if(/bydli[šs]t[ěe]/i.test(l)||/adresa/i.test(l)||/residence/i.test(l)||
         /BYDL/i.test(l)||/trval/i.test(l)||/pobyt/i.test(l)){
        var a=(ls[i+1]||'').trim();
        if(a&&a.length>3&&!C.isRejected(a)){data.street=a; addressFound=true;}
        var c=(ls[i+2]||'').trim(); if(c) data.cityLine=c;
      }
      // PSČ pattern: 3 digits + space + 2 digits (or 5 digits)
      var zm=l.match(/(\d{3})\s*(\d{2})/);
      if(zm&&!data.zip){
        data.zip=zm[1]+' '+zm[2];
        // City is often after PSČ on same line
        var afterZip=l.substring(l.indexOf(zm[0])+zm[0].length).trim();
        if(afterZip&&afterZip.length>1&&!data.city) data.city=afterZip;
        // Or city is the text BEFORE PSČ
        var beforeZip=l.substring(0,l.indexOf(zm[0])).trim();
        if(!data.city&&beforeZip&&beforeZip.length>2&&!/bydli|adres|residence/i.test(beforeZip)){
          data.city=beforeZip;
        }
      }
      // Street pattern: text + č.p./čp + number
      if(!data.street&&/\d+/.test(l)){
        var stMatch=l.match(/^([A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽa-záčďéěíňóřšťúůýž\s]+)\s+(?:č[\.\s]*p[\.\s]*|čp[\.\s]*)?\s*(\d+)/i);
        if(stMatch&&stMatch[1].trim().length>2&&!C.isRejected(stMatch[1])){
          data.street=stMatch[1].trim()+' '+stMatch[2];
        }
      }
    }
    // Fallback: extract city from cityLine
    if(!data.city&&data.cityLine){
      var z2=data.cityLine.match(/(\d{3})\s*(\d{2})\s*(.*)/);
      if(z2){data.zip=z2[1]+' '+z2[2];data.city=z2[3].trim();}
      else data.city=data.cityLine;
    }
    // Fallback: derive PSČ from known Czech city names
    if(data.city&&!data.zip){
      var cityZips={'Pelhřimov':'393 01','Praha':'110 00','Brno':'602 00',
        'Ostrava':'702 00','Plzeň':'301 00','Liberec':'460 01','Olomouc':'779 00',
        'České Budějovice':'370 01','Hradec Králové':'500 02','Jihlava':'586 01',
        'Humpolec':'396 01','Kamenice nad Lipou':'394 70','Pacov':'395 01'};
      var cl=data.city.toLowerCase();
      for(var ck in cityZips){
        if(cl.indexOf(ck.toLowerCase())!==-1){data.zip=cityZips[ck];break;}
      }
    }
    // Fallback: if street contains address with town
    if(data.street&&!data.city){
      var okrMatch=data.street.match(/okr[.\s]+([A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽa-záčďéěíňóřšťúůýž\s]+)/i);
      if(okrMatch) data.city=okrMatch[1].trim();
    }
    return data;
  }

  DocParser.parseIdFront = parseIdFront;
  DocParser.parseIdBack = parseIdBack;
})();
