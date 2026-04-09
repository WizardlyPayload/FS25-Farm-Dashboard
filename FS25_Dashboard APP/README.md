# FS25 Farm Dashboard

**Version 2.0.0** — Real-time farm management dashboard for *Farming Simulator 25*, with local save folders and dedicated (FTP) servers.

**Authors:** JoshWalki, WizardlyPayload  

---

## What it does

- Connects to the FS25 Farm Dashboard mod data (local `modSettings` paths or FTP to a dedicated server).
- Serves a web UI (Electron + Express on port **8766**, bound to **`0.0.0.0`**) with live stock, vehicles, fields, economy, pastures, productions, weather, and notifications. A **tablet or phone on the same LAN** can use **`http://<PC-IPv4>:8766`** in a browser; see repo root **[INSTALL.md](../INSTALL.md)** and **[docs/SECURITY.md](../docs/SECURITY.md)**.
- Optional **mod shop image import**: scans your FS25 mods folder, exports PNGs and converts `icon_*.dds` for dashboard thumbnails (uses **ImageMagick** / **texconv** when available).

---

## Installation (Windows)

### 1. Run the installer

1. Run **`FS25 Farm Dashboard Setup 2.0.0.exe`** (or the current release build).
2. **The first screen is language selection** — choose the language used for the rest of the installer, the **first-run Server Manager** setup, and the default **Dashboard** language (you can change language again inside the app under **Theme & Color Settings**).
3. The installer installs the app and **automatically runs an ImageMagick helper** so DDS→PNG conversion works without manual downloads when possible (bundled/offline installer, **winget**, **Chocolatey**, or a **download** fallback — see `build/install-imagemagick.ps1`).

### 2. First launch — Server Manager

If the app is not configured yet, the **Server Manager** window opens:

1. **Language** is shown at the **very top** (same list as the installer). If you already picked a language in the installer, it is applied here; you can change it and the page reloads in the new language.
2. Add servers (**Auto-Detect Local Saves** and/or **Add Server Manually** for FTP).
3. Click **Launch Dashboard** to start the embedded server and open the dashboard.

Settings are stored with the app (Electron Store). The dashboard remembers your language in **localStorage** (`farmdash_locale`) and in the main process store (`locale`).

---

## Languages (EU / EEA coverage)

- **Installer (NSIS):** first page = language dropdown; writes `%APPDATA%\fs25-farm-dashboard\install-locale.txt` for the first app launch.
- **Server Manager (`setup.html`):** language bar is the first UI block; strings are loaded from `web/locales/translations.json` (`setup.*` keys).
- **Dashboard (`web/`):** `web/assests/js/i18n/i18n.js` + `data-i18n` attributes; language selector in **Theme & Color Settings**.

Strings are merged **per key** with **English** as fallback when a locale is incomplete. To add or edit text, use `web/locales/build-translations.mjs` and run:

```bash
node web/locales/build-translations.mjs
```

---

## Development

**Requirements:** Node.js, npm.

```bash
npm install
npm start
```

**Production Windows build:**

```bash
npm run dist
```

Output: `release/FS25 Farm Dashboard Setup 2.0.0.exe` (and unpacked app under `release/win-unpacked/`).

**NSIS include:** `build/installer.nsh` (language welcome page + ImageMagick `customInstall`). `package.json` → `build.nsis.include`.

---

## Project layout (app)

| Path | Purpose |
|------|--------|
| `main.js` | Electron main: Express/WS, FTP polling, IPC, locale file consumption |
| `setup.html` | First-run Server Manager (language-first) |
| `web/index.html` | Dashboard UI |
| `web/locales/translations.json` | Generated UI strings (do not edit by hand — regenerate from `build-translations.mjs`) |
| `web/assests/js/i18n/i18n.js` | Dashboard i18n |
| `web/assests/js/setup-i18n.js` | Setup wizard i18n |
| `build/installer.nsh` | NSIS: language page + ImageMagick install |
| `build/install-imagemagick.ps1` | ImageMagick install helper |

---

## Release notes — v2.0.0

See **`docs/RELEASE_v2.0.0.md`** for the full changelog. Summary:

- **Language first:** NSIS installer welcome page + Server Manager language bar; shared `locale` store and `translations.json` pipeline.
- **Dashboard i18n:** EU/EEA-oriented locales with English fallback per string.
- **ImageMagick:** Installed automatically during setup when possible (bundled / winget / Chocolatey / official download).
- **Server Manager:** FTP polling options, HTTP feed fields, mod image scan integration.

---

## Licence / credits

Bundled third-party components (Electron, Chromium, ImageMagick when installed, etc.) are subject to their respective licences. Game content and mod data remain property of Giants Software and respective mod authors.
