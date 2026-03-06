// ===== LANG-SELECT.JS – First-launch language selection for MotoGo24 =====
// Shows language picker on first app launch, persists choice in localStorage.
// Dependencies: js/i18n.js (setLanguage, _currentLang)

var LANG_STORAGE_KEY = 'mg_lang';

function selectInitLang(lang) {
  try { localStorage.setItem(LANG_STORAGE_KEY, lang); } catch (e) {}
  _currentLang = lang;
  var overlay = document.getElementById('lang-overlay');
  if (overlay) overlay.style.display = 'none';
  // Apply language to entire app
  if (typeof setLanguage === 'function') setLanguage(lang);
  // Apply i18n-dom translations if available
  if (typeof applyI18nDom === 'function') applyI18nDom();
}

function initLangSelect() {
  try {
    var saved = localStorage.getItem(LANG_STORAGE_KEY);
    if (saved) {
      // Language already chosen – apply it silently
      _currentLang = saved;
      if (typeof setLanguage === 'function') setLanguage(saved);
      return;
    }
  } catch (e) {}
  // First launch – show language overlay
  var overlay = document.getElementById('lang-overlay');
  if (overlay) overlay.style.display = 'flex';
}
