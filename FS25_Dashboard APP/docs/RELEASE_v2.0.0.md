# FS25 Farm Dashboard — Release v2.0.0

Release date: 2026 (see repository tags for exact build).

## Highlights

### Installation & language

- **Windows NSIS installer** shows **language selection as the first page** (before licence/directory steps). The choice is written to `%APPDATA%\fs25-farm-dashboard\install-locale.txt` and consumed on first launch so the **Server Manager** and **Dashboard** default to the same language.
- **Server Manager (`setup.html`)** displays the **language selector at the top** of the window, with copy explaining alignment with the installer and in-app Theme settings.
- **Dashboard** uses a shared translation layer (`web/assests/js/i18n/i18n.js`, `web/locales/translations.json`) with **English fallback** for missing strings per locale.

### ImageMagick

- After file installation, the NSIS `customInstall` step runs `resources/install-imagemagick.ps1` to provide **ImageMagick (`magick`)** for DDS→PNG conversion in the mod image pipeline (order: bundled installer → existing install → winget → Chocolatey → official download).

### Documentation

- Root **`README.md`**: install steps, dev commands, layout, i18n maintenance (`build-translations.mjs`).
- This file: **v2.0.0** release notes for packaging and GitHub/Git release descriptions.

## Technical notes for maintainers

- Regenerate `web/locales/translations.json`:  
  `node web/locales/build-translations.mjs`
- NSIS warnings: `build.nsis.warningsAsErrors` may be `false` when using custom pages (electron-builder / NSIS quirks).
- `electron-store` holds `locale` (2-letter code) alongside `config` for servers.

## Upgrade from older builds

- No automatic migration of language beyond new `install-locale.txt` / `locale` store keys; existing users keep prior behaviour until they change language in Theme settings or reinstall.
