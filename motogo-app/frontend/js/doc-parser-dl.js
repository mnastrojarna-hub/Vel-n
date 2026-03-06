// ===== DOC-PARSER-DL.JS – DL & Passport parsers (v5.0.0) =====
// Zone-based parsing for řidičský průkaz and cestovní pas.
// Loaded after doc-parser-core.js

(function(){
  'use strict';
  var C = DocParser._c;

  // DL front zones
  var Z = {
    headerEnd:0.15, surnameStart:0.08, surnameEnd:0.35,
    nameStart:0.15, nameEnd:0.45, dobStart:0.25, dobEnd:0.55
  };

  function parseDlFront(text){
    var data={}, ls=C.lines(text), total=ls.length;

    for(var i=0;i<ls.length;i++){
      var l=ls[i], pos=C.zonePos(i,total);
      // Field "1." surname
      if((/^1[.\s]/.test(l)||C.isSurnameLabel(l))&&!data.lastName&&
         pos>=Z.surnameStart&&pos<=Z.surnameEnd){
        var sv=l.replace(/^1[.\s]+/,'').replace(/.*[\/|:]/,'').trim();
        if(C.isValidName(sv)) data.lastName=C.clean(sv);
        else if(i+1<ls.length&&C.isValidName(ls[i+1])) data.lastName=C.clean(ls[i+1]);
      }
      // Field "2." first name
      if((/^2[.\s]/.test(l)||C.isNameLabel(l))&&!data.firstName&&
         pos>=Z.nameStart&&pos<=Z.nameEnd){
        var nv=l.replace(/^2[.\s]+/,'').replace(/.*[\/|:]/,'').trim();
        if(C.isValidName(nv)) data.firstName=C.clean(nv);
        else if(i+1<ls.length&&C.isValidName(ls[i+1])) data.firstName=C.clean(ls[i+1]);
      }
      // Field "3." DOB
      if((/^3[.\s]/.test(l)||C.isDobLabel(l))&&!data.dob&&
         pos>=Z.dobStart&&pos<=Z.dobEnd){
        var dv=C.extractDate(l);
        if(dv&&dv.y>1920&&dv.y<2015) data.dob=dv.str;
        else if(i+1<ls.length){var d2=C.extractDate(ls[i+1]);if(d2&&d2.y>1920&&d2.y<2015) data.dob=d2.str;}
      }
      // License number
      var lm=l.match(/\b([A-Z]{1,2}\s*\d{5,7})\b/i);
      if(!lm) lm=l.match(/\b([EF][A-Z0-9]\s*\d{5,7})\b/i);
      if(lm&&!data.licenseNumber) data.licenseNumber=lm[1];
      // Dates
      var dms=l.match(/(\d{1,2})\s*[.\/-]\s*(\d{1,2})\s*[.\/-]\s*(\d{4})/g);
      if(dms) dms.forEach(function(dm){
        var p=dm.match(/(\d{1,2})\s*[.\/-]\s*(\d{1,2})\s*[.\/-]\s*(\d{4})/);
        if(p){
          var yr=parseInt(p[3]);
          if(yr>2025&&!data.licenseExpiry) data.licenseExpiry=p[1]+'. '+p[2]+'. '+p[3];
          else if(yr>2005&&yr<=2026&&!data.licenseIssued) data.licenseIssued=p[1]+'. '+p[2]+'. '+p[3];
        }
      });
      // Category
      if(/\b(A2|A1|A|B|C|D)\b/.test(l)){
        var cm=l.match(/\b(A2|A1|A|B)\b/);
        if(cm&&!data.licenseCategory) data.licenseCategory=cm[1];
      }
    }

    // Positional fallback for names (skip header)
    if(!data.lastName||!data.firstName){
      for(var fi=0;fi<ls.length;fi++){
        var fpos=C.zonePos(fi,total);
        if(fpos<Z.headerEnd) continue;
        if(fpos>Z.nameEnd+0.10) break;
        var fl=ls[fi];
        if(C.isValidName(fl)&&!C.isSurnameLabel(fl)&&!C.isNameLabel(fl)&&!C.isDobLabel(fl)&&!/^[123][.\s]/.test(fl)){
          var cv=C.clean(fl);
          if(cv.length>=2&&cv.length<=30){
            if(!data.lastName) data.lastName=cv;
            else if(!data.firstName) data.firstName=cv;
          }
        }
      }
    }
    if(data.firstName) data.firstName=C.fixCzechName(data.firstName);
    if(data.lastName) data.lastName=C.fixCzechName(data.lastName);
    return data;
  }

  function parseDlBack(text){
    var data={}, ls=C.lines(text);
    for(var i=0;i<ls.length;i++){
      var l=ls[i];
      if(/\bA[12]?\b/.test(l)){
        var cm=l.match(/\b(A2|A1|A|B)\b/);
        if(cm&&!data.licenseCategory) data.licenseCategory=cm[1];
      }
      var lm=l.match(/\b([A-Z]{1,2}\s*\d{5,7})\b/i);
      if(!lm) lm=l.match(/\b([EF][A-Z0-9]\s*\d{5,7})\b/i);
      if(lm&&!data.licenseNumber) data.licenseNumber=lm[1];
    }
    return data;
  }

  function parsePassport(text){
    var data={}, ls=C.lines(text), total=ls.length;
    var mrz=C.parseMRZ(ls);
    if(mrz.firstName) data.firstName=mrz.firstName;
    if(mrz.lastName) data.lastName=mrz.lastName;
    if(mrz.dob) data.dob=mrz.dob;
    if(mrz.idNumber) data.idNumber=mrz.idNumber;

    for(var i=0;i<ls.length;i++){
      var l=ls[i], pos=C.zonePos(i,total);
      if(pos<0.15&&(C.isSurnameLabel(l)||C.isNameLabel(l))) continue;
      if(C.isSurnameLabel(l)&&!data.lastName){
        var sv=C.valueNearLabel(ls,i,C.isValidName);
        if(sv) data.lastName=sv;
      }
      if(C.isNameLabel(l)&&!data.firstName){
        var nv=C.valueNearLabel(ls,i,C.isValidName);
        if(nv) data.firstName=nv;
      }
      if(C.isDobLabel(l)&&!data.dob){
        var d1=C.extractDate(l);if(d1&&d1.y>1920&&d1.y<2015) data.dob=d1.str;
        if(!data.dob&&i+1<ls.length){var d2=C.extractDate(ls[i+1]);if(d2&&d2.y>1920&&d2.y<2015) data.dob=d2.str;}
      }
      var pn=l.match(/\b(\d{7,9})\b/);
      if(pn&&!data.idNumber&&pos>0.15) data.idNumber=pn[1];
    }
    return data;
  }

  DocParser.parseDlFront = parseDlFront;
  DocParser.parseDlBack = parseDlBack;
  DocParser.parsePassport = parsePassport;
})();
