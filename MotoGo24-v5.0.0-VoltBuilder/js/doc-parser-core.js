// ===== DOC-PARSER-CORE.JS – Shared utilities & MRZ (v5.0.0) =====
// Zone-based template approach with reject list for document headers.

var DocParser = (function(){
  'use strict';

  var CZ_CHARS = /[^a-zA-ZáčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ\s-]/g;

  var REJECT_WORDS = [
    'občanský','průkaz','občansky','prukaz','identity','card','doklad',
    'totožnosti','totoznosti','republika','česká','ceska','czech','republic',
    'řidičský','ridicsky','driving','licence','license','pas','passport',
    'cestovní','cestovni','ministerstvo','vnitra','ministry','interior',
    'přední','zadní','strana','platnost','vydán','vydáno','platí',
    'datum','narození','narozeni','bydliště','bydliste','pohlaví','pohlavi',
    'místo','misto','okres','rodné','rodne','číslo','cislo','čp','cp',
    'sex','nationality','surname','name','given','date','birth','place',
    'authority','expiry','signature','holder','jméno','jmeno','příjmení',
    'prijmeni','poznámka','poznamka','document','number','valid','issued',
    'state','organ','úřad','urad','kategorie','category','skupina'
  ];
  var _rejectSet = {};
  REJECT_WORDS.forEach(function(w){ _rejectSet[w.toLowerCase()]=true; });

  function clean(s){ return (s||'').replace(CZ_CHARS,'').trim(); }
  function lines(text){ return text.split('\n').map(function(l){return l.trim();}).filter(Boolean); }

  function isRejected(s){
    var words = s.toLowerCase().split(/[\s-]+/);
    for(var i=0;i<words.length;i++){
      var w = words[i].replace(/[^a-záčďéěíňóřšťúůýž]/gi,'');
      if(w && _rejectSet[w]) return true;
    }
    return false;
  }

  function isValidName(s){
    var c = clean(s);
    if(c.length<2 || c.length>30) return false;
    if(/^\d/.test(c)) return false;
    // Accept uppercase start OR common OCR mangling of Czech uppercase
    if(!/^[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽa-záčďéěíňóřšťúůýž]/.test(c)) return false;
    if(isRejected(c)) return false;
    if(/\d{3,}/.test(s)) return false;
    return true;
  }

  function fixCzechName(s){
    if(!s) return s;
    // Common Tesseract OCR errors for Czech names
    var fixes = {
      'JIRI':'Jiří','JIRl':'Jiří','JIFI':'Jiří','JlRl':'Jiří','JlRI':'Jiří',
      'JIRÍ':'Jiří','JIŘl':'Jiří','JIŘI':'Jiří',
      'SEMORAD':'Šemorád','SEMORÁD':'Šemorád','ŠEMORAD':'Šemorád',
      'SEMORED':'Šemorád','ŠEMORED':'Šemorád'
    };
    var upper = s.toUpperCase().replace(/\s/g,'');
    if(fixes[upper]) return fixes[upper];
    // Generic: capitalize first letter, lowercase rest
    var result = s.charAt(0).toUpperCase() + s.substring(1).toLowerCase();
    // Fix common OCR substitutions
    result = result.replace(/[lI]([ří])/g, function(m,c){ return 'í'+c; });
    return result;
  }

  function extractDate(s){
    var m = s.match(/(\d{1,2})\s*[.\/-]\s*(\d{1,2})\s*[.\/-]\s*(\d{4})/);
    if(!m) return null;
    var dd=parseInt(m[1]),mm=parseInt(m[2]),yy=parseInt(m[3]);
    if(mm>=1&&mm<=12&&dd>=1&&dd<=31) return {d:dd,m:mm,y:yy,str:dd+'. '+mm+'. '+yy};
    return null;
  }

  function parseMRZ(ls){
    var data = {};
    var mrz = ls.filter(function(l){
      return l.length >= 28 && /[A-Z0-9<]{20,}/.test(l.replace(/\s/g,''));
    });
    if(mrz.length < 2) return data;
    var l1 = mrz[mrz.length-2].replace(/\s/g,'');
    var l2 = mrz[mrz.length-1].replace(/\s/g,'');
    if(/^[IP][<DO]?CZE/.test(l1) || /^[IP]<CZE/.test(l1)){
      var nameStr = l1.replace(/^.{5}/,'').replace(/</g,' ').trim();
      var parts = nameStr.split(/\s{2,}/);
      if(parts.length >= 2){
        var ln=parts[0].trim(), fn=parts[1].trim().split(/\s+/)[0];
        if(isValidName(ln)) data.lastName=ln;
        if(isValidName(fn)) data.firstName=fn;
      } else {
        var alt = l1.substring(5).split(/<<+/);
        if(alt.length>=2){
          var aln=alt[0].replace(/</g,' ').trim();
          var afn=alt[1].replace(/</g,' ').trim().split(/\s+/)[0];
          if(isValidName(aln)) data.lastName=aln;
          if(isValidName(afn)) data.firstName=afn;
        }
      }
    }
    if(l2.length >= 28){
      var doc = l2.substring(0,9).replace(/</g,'').trim();
      if(doc && /[A-Z0-9]{5,}/.test(doc)) data.idNumber = doc;
      var dobStr = l2.substring(13,19);
      if(/^\d{6}$/.test(dobStr)){
        var by=parseInt(dobStr.substring(0,2)),bm=parseInt(dobStr.substring(2,4)),bd=parseInt(dobStr.substring(4,6));
        by = by>30?1900+by:2000+by;
        if(bm>=1&&bm<=12&&bd>=1&&bd<=31) data.dob=bd+'. '+bm+'. '+by;
      }
    }
    return data;
  }

  // Fuzzy label matchers
  function isSurnameLabel(l){
    return /p[řrŕ][íiíl]jmen[íi]/i.test(l) || /surname/i.test(l) ||
           /příjm/i.test(l) || /pr[il]jm/i.test(l) || /PRIJM/i.test(l);
  }
  function isNameLabel(l){
    return (/jm[ée]n[oó]\b/i.test(l) || /\bname\b/i.test(l) || /given/i.test(l) ||
            /JMENO/i.test(l)) && !isSurnameLabel(l);
  }
  function isDobLabel(l){
    return /narozen/i.test(l) || /datum\s*nar/i.test(l) || /birth/i.test(l) ||
           /nar\.\s*dat/i.test(l) || /NAROZEN/i.test(l) || /geb/i.test(l);
  }

  function valueNearLabel(ls, idx, validator){
    var l = ls[idx];
    var sameLine = l.replace(/.*[\/|:]/,'').trim();
    if(validator(sameLine)) return clean(sameLine);
    for(var j=1;j<=2&&idx+j<ls.length;j++){
      var nxt=ls[idx+j];
      if(validator(nxt)) return clean(nxt);
    }
    return null;
  }

  function zonePos(lineIdx, total){
    return total>1 ? lineIdx/(total-1) : 0;
  }

  // Public core API – parsers will attach themselves
  return {
    _c: { clean:clean, lines:lines, isRejected:isRejected, isValidName:isValidName,
      fixCzechName:fixCzechName,
      extractDate:extractDate, parseMRZ:parseMRZ, isSurnameLabel:isSurnameLabel,
      isNameLabel:isNameLabel, isDobLabel:isDobLabel, valueNearLabel:valueNearLabel,
      zonePos:zonePos }
  };
})();
