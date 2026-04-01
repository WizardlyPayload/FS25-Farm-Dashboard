// FS25 FarmDashboard | setup.html i18n (first-run wizard). Loads strings from web/locales/translations.json via main process.
(function () {
  const { ipcRenderer } = require('electron');

  const LOCALE_NAMES = {
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

  let catalog = null;
  let lang = 'en';

  function t(key) {
    const row = catalog && catalog.strings && catalog.strings[key];
    if (!row || typeof row !== 'object') return key;
    const v = row[lang] || row.en;
    return v != null && v !== '' ? v : key;
  }

  function apply() {
    document.querySelectorAll('[data-setup-i18n]').forEach((el) => {
      const key = el.getAttribute('data-setup-i18n');
      if (!key) return;
      const v = t(key);
      if (el.tagName === 'TITLE') {
        document.title = v;
        return;
      }
      if (el.hasAttribute('data-setup-html')) el.innerHTML = v;
      else el.textContent = v;
    });
    document.querySelectorAll('[data-setup-placeholder]').forEach((el) => {
      const key = el.getAttribute('data-setup-placeholder');
      if (key) el.setAttribute('placeholder', t(key));
    });
  }

  async function init() {
    try {
      catalog = await ipcRenderer.invoke('get-translations-json');
    } catch (e) {
      console.warn('[setup-i18n]', e);
      return;
    }
    const q = new URLSearchParams(window.location.search).get('lang');
    let stored = 'en';
    try {
      stored = (await ipcRenderer.invoke('get-stored-locale')) || 'en';
    } catch (_) {}
    lang = q && LOCALE_NAMES[q] ? q : stored;
    if (!LOCALE_NAMES[lang]) lang = 'en';

    const sel = document.getElementById('setup-lang-select');
    if (sel) {
      sel.innerHTML = '';
      Object.keys(LOCALE_NAMES)
        .sort((a, b) => LOCALE_NAMES[a].localeCompare(LOCALE_NAMES[b], 'en'))
        .forEach((code) => {
          const opt = document.createElement('option');
          opt.value = code;
          opt.textContent = LOCALE_NAMES[code];
          if (code === lang) opt.selected = true;
          sel.appendChild(opt);
        });
      sel.addEventListener('change', () => {
        const next = sel.value;
        try {
          ipcRenderer.send('set-stored-locale', next);
        } catch (_) {}
        try {
          const url = new URL(window.location.href);
          url.searchParams.set('lang', next);
          window.location.href = url.toString();
        } catch (_) {
          window.location = 'setup.html?lang=' + encodeURIComponent(next);
        }
      });
    }
    apply();
    document.documentElement.lang = lang;
    window.setupT = function (key) {
      return t(key);
    };
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
