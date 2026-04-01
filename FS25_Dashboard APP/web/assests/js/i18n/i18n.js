// FS25 FarmDashboard | i18n | translation layer (EU / EEA locales, English fallback per string)

const STORAGE_KEY = 'farmdash_locale';

/** BCP 47 codes we ship; native names for the language selector. */
export const LOCALE_NAMES = {
  en: 'English',
  bg: 'Български',
  hr: 'Hrvatski',
  cs: 'Čeština',
  da: 'Dansk',
  nl: 'Nederlands',
  et: 'Eesti',
  fi: 'Suomi',
  fr: 'Français',
  de: 'Deutsch',
  el: 'Ελληνικά',
  hu: 'Magyar',
  ga: 'Gaeilge',
  it: 'Italiano',
  lv: 'Latviešu',
  lt: 'Lietuvių',
  mt: 'Malti',
  pl: 'Polski',
  pt: 'Português',
  ro: 'Română',
  sk: 'Slovenčina',
  sl: 'Slovenščina',
  es: 'Español',
  sv: 'Svenska',
  is: 'Íslenska',
  nb: 'Norsk bokmål',
  uk: 'Українська'
};

const FALLBACK = 'en';

let catalog = null;
let currentLocale = FALLBACK;
let flatEn = {};

function normalizeLocale(code) {
  if (!code || typeof code !== 'string') return FALLBACK;
  const lower = code.trim().toLowerCase().replace('_', '-');
  const primary = lower.split('-')[0];
  if (LOCALE_NAMES[primary]) return primary;
  return FALLBACK;
}

async function pickInitialLocale() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && LOCALE_NAMES[saved]) return saved;
  } catch (_) {}
  try {
    if (typeof require === 'function') {
      const { ipcRenderer } = require('electron');
      if (ipcRenderer && ipcRenderer.invoke) {
        const s = await ipcRenderer.invoke('get-stored-locale');
        if (s && LOCALE_NAMES[s]) return s;
      }
    }
  } catch (_) {}
  const nav = typeof navigator !== 'undefined' ? navigator.language || navigator.userLanguage : FALLBACK;
  return normalizeLocale(nav || FALLBACK);
}

async function loadCatalog() {
  const res = await fetch('/locales/translations.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`i18n: ${res.status}`);
  catalog = await res.json();
  flatEn = {};
  if (catalog.strings && typeof catalog.strings === 'object') {
    for (const [key, row] of Object.entries(catalog.strings)) {
      if (row && typeof row === 'object' && row[FALLBACK] != null) flatEn[key] = row[FALLBACK];
    }
  }
}

export function getLocale() {
  return currentLocale;
}

export function t(key) {
  if (!catalog || !catalog.strings) return key;
  const row = catalog.strings[key];
  if (!row || typeof row !== 'object') return flatEn[key] ?? key;
  const v = row[currentLocale] ?? row[FALLBACK];
  if (v != null && v !== '') return v;
  return flatEn[key] ?? key;
}

export function applyDom(root = document) {
  root.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    if (!key) return;
    const val = t(key);
    if (el.hasAttribute('data-i18n-html')) el.innerHTML = val;
    else el.textContent = val;
  });
  root.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    const key = el.getAttribute('data-i18n-placeholder');
    if (key) el.setAttribute('placeholder', t(key));
  });
  root.querySelectorAll('[data-i18n-title]').forEach((el) => {
    const key = el.getAttribute('data-i18n-title');
    if (key) el.setAttribute('title', t(key));
  });
  root.querySelectorAll('[data-i18n-aria]').forEach((el) => {
    const key = el.getAttribute('data-i18n-aria');
    if (key) el.setAttribute('aria-label', t(key));
  });
}

function bindLanguageSelect() {
  const sel = document.getElementById('farmdash-language-select');
  if (!sel || sel.dataset.farmdashI18nBound === '1') return;
  sel.dataset.farmdashI18nBound = '1';
  sel.innerHTML = '';
  const codes = Object.keys(LOCALE_NAMES).sort((a, b) => LOCALE_NAMES[a].localeCompare(LOCALE_NAMES[b], 'en'));
  for (const code of codes) {
    const opt = document.createElement('option');
    opt.value = code;
    opt.textContent = LOCALE_NAMES[code];
    if (code === currentLocale) opt.selected = true;
    sel.appendChild(opt);
  }
  sel.addEventListener('change', () => {
    const next = normalizeLocale(sel.value);
    setLocale(next, true);
  });
}

export function setLocale(code, reloadUi = false) {
  currentLocale = normalizeLocale(code);
  try {
    localStorage.setItem(STORAGE_KEY, currentLocale);
  } catch (_) {}
  try {
    if (typeof require === 'function') {
      const { ipcRenderer } = require('electron');
      if (ipcRenderer && ipcRenderer.send) ipcRenderer.send('set-stored-locale', currentLocale);
    }
  } catch (_) {}
  if (typeof document !== 'undefined') {
    document.documentElement.lang = currentLocale;
    const sel = document.getElementById('farmdash-language-select');
    if (sel) sel.value = currentLocale;
    applyDom(document);
  }
  window.dispatchEvent(new CustomEvent('farmdash-locale-changed', { detail: { locale: currentLocale } }));
  if (reloadUi) {
    try {
      window.location.reload();
    } catch (_) {}
  }
}

export async function initI18n() {
  await loadCatalog();
  currentLocale = await pickInitialLocale();
  if (typeof document !== 'undefined') {
    document.documentElement.lang = currentLocale;
    bindLanguageSelect();
    applyDom(document);
    const sel = document.getElementById('farmdash-language-select');
    if (sel) sel.value = currentLocale;
    document.title = t('page.title');
  }
  return { t, getLocale, setLocale, applyDom };
}
