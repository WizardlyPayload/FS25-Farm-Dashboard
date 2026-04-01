# FS25 Farm Dashboard — Full description & screenshot guide

This document describes the **in-game mod** and **desktop application**, lists every major **UI surface** in the project, and tells you **exactly which screenshots to take** and where to save them so you can drop them into GitHub or a release page.

**Version history:** [CHANGELOG.md](./CHANGELOG.md) · **Short release blurbs:** [RELEASE_NOTES.md](../RELEASE_NOTES.md) · **Security / LAN:** [SECURITY.md](./SECURITY.md) · **Authors:** [AUTHORS.md](../AUTHORS.md) (JoshWalki & WizardlyPayload)

> **Note:** Screenshots must be captured on **your PC** while FS25 and the dashboard app are running with real data. Place image files under `docs/screenshots/` (create the folder) using the filenames below. Then uncomment or add the Markdown image lines in your README.

---

## Part A — The FS25 mod (`FS25_FarmDashboard`)

### What it is

A **server-side / save-side Lua mod** for Farming Simulator 25. It does **not** add a big in-game HUD; it runs in the background while you play (or on a dedicated server), collects data from the game engine, and writes **`data.json`** (and optional **`config.xml`**) under your user profile.

### What it collects (modules)

| Area | Role |
|------|------|
| **Animals** | Husbandries, clusters, Realistic Livestock–style individuals where available |
| **Vehicles** | Fleet state, positions, fill levels, damage, ownership |
| **Fields** | Growth, soil, weeds, Precision Farming overlays where applicable |
| **Finance** | Money and related summary |
| **Weather** | Current conditions and forecast-oriented data |
| **Economy** | Sell points, market-style price discovery |
| **Production** | Production points / factories, chains, fill levels |

Data is refreshed on a **configurable interval** (default **10 seconds**, see `config.xml`).

### Where files go (typical Windows)

- **Output:** `Documents\My Games\FarmingSimulator2025\modSettings\FS25_FarmDashboard\<savegame folder>\data.json`
- **Config:** `Documents\My Games\FarmingSimulator2025\modSettings\FS25_FarmDashboard\config.xml`

### Multiplayer

Supported on **dedicated server**; the mod must be active on the server so it can write the same style of export for tools that read the profile (or FTP on hosted setups).

### “Screenshots” for the mod (there is no custom mod UI)

The mod has **no dedicated dashboard panel inside FS25**. For documentation, use one or more of:

| # | Suggested filename | What to capture |
|---|---------------------|-----------------|
| M1 | `docs/screenshots/mod-01-mods-list.png` | FS25 **Mod** screen showing **Farm Dashboard** enabled for your save |
| M2 | `docs/screenshots/mod-02-gameplay.png` | Normal gameplay (optional) to show the mod running in the background |
| M3 | `docs/screenshots/mod-03-data-json.png` | File Explorer with **`data.json`** path visible (blur personal paths if you prefer) |

**Markdown (paste into README after you add the files):**

```md
### FS25 mod
![Mod enabled in FS25](docs/screenshots/mod-01-mods-list.png)
```

---

## Part B — The desktop app (Electron)

### What it is

A **Windows desktop program** that:

- Hosts a **local HTTP API** (default port **8766**) and **WebSocket** updates
- Reads **`data.json`** from disk **or** via **FTP** (hosted / GPortal-style servers)
- Merges **live Lua JSON** with **savegame XML** (fields, farmlands, economy, vehicles, etc.) when XML is available
- Opens an embedded or external **browser UI** at **`http://localhost:8766`**

First-time **Server Manager** screen: **`setup.html`** (local paths, FTP, multi-server).

### Timing: mod vs app (2.0.0)

Two different “schedules” are involved (see [CHANGELOG.md §2.0.0 — **G** and **H**](./CHANGELOG.md)):

| Layer | What it controls |
|--------|------------------|
| **In-game mod** | **Staggered collection**: one data module (animals, vehicles, fields, …) per slice over **`collectionCycleMs`** (default ~60s; tunable in **`config.xml`**). Writes **`data.json`** after each slice. |
| **Desktop app (FTP)** | **FTP polling**: how often the app downloads remote **`data.json`**, plus **sync** (all FTP servers at once) vs **staggered** (spread across the interval). Set on **Setup** under **FTP polling**. |

**Setup** also includes **Scan FS25 mods for dashboard images** (mod shop PNG export) and **scan local saves** for paths. Full detail: [RELEASE_NOTES.md — “Where this release is documented”](../RELEASE_NOTES.md).

### “Screenshots” for the desktop app

| # | Suggested filename | What to capture | How to open |
|---|---------------------|-----------------|-------------|
| D1 | `docs/screenshots/app-01-setup.png` | **Server Manager / Setup** — servers, FTP, paths | First launch or gear icon → setup |
| D2 | `docs/screenshots/app-02-landing.png` | **Home** — six section cards (Livestock, Vehicles, Fields, Economy, Pastures, Productions) | Click **Home** in navbar |
| D3 | `docs/screenshots/app-03-navbar.png` | **Top bar** — game time, data source, weather, connection (optional crop) | Any screen with navbar visible |
| D4 | `docs/screenshots/app-04-offline.png` | **Connection error** card (“Oops — something went wrong”) | Optional: stop FS25 / break API to show |

---

## Part C — Web dashboard pages (inside the app)

Open **`http://localhost:8766`** after the app is running and data is flowing.

| Section | URL hash | Suggested filename | What to show |
|---------|----------|-------------------|--------------|
| **Livestock** | `#livestock` | `docs/screenshots/ui-01-livestock.png` | Summary cards + animals **DataTable** (expand filters if you want a second shot) |
| **Vehicles** | `#vehicles` | `docs/screenshots/ui-02-vehicles.png` | Fleet cards / list for **active farm** |
| **Fields** | `#fields` | `docs/screenshots/ui-03-fields.png` | Summary stats + field cards; optional second: **Needs Work** filter |
| **Economy** | `#economy` | `docs/screenshots/ui-04-economy.png` | Prices / finance view |
| **Pastures** | `#pastures` | `docs/screenshots/ui-05-pastures.png` | Pasture / husbandry overview |
| **Productions** | `#productions` | `docs/screenshots/ui-06-productions.png` | Production chains for **selected farm** |

**Optional extras**

| Suggested filename | Content |
|---------------------|---------|
| `docs/screenshots/ui-07-theme.png` | Theme / palette modal (palette button in navbar) |
| `docs/screenshots/ui-08-notifications.png` | Notification history modal |
| `docs/screenshots/ui-09-export.png` | Livestock export modal (CSV / Excel / PDF) |
| `docs/screenshots/ui-10-farm-dropdown.png` | Farm selector in header (**FTP / multi-farm**) |

**Markdown block for README (after files exist):**

```md
## Screenshots

### Home
![Home](docs/screenshots/app-02-landing.png)

### Livestock
![Livestock](docs/screenshots/ui-01-livestock.png)

### Vehicles
![Vehicles](docs/screenshots/ui-02-vehicles.png)

### Fields
![Fields](docs/screenshots/ui-03-fields.png)

### Economy
![Economy](docs/screenshots/ui-04-economy.png)

### Pastures
![Pastures](docs/screenshots/ui-05-pastures.png)

### Productions
![Productions](docs/screenshots/ui-06-productions.png)
```

---

## Quick capture checklist

Use **Win + Shift + S** (Snipping Tool) or fullscreen capture.

- [ ] `mod-01-mods-list.png`
- [ ] `app-01-setup.png`
- [ ] `app-02-landing.png`
- [ ] `ui-01-livestock.png`
- [ ] `ui-02-vehicles.png`
- [ ] `ui-03-fields.png`
- [ ] `ui-04-economy.png`
- [ ] `ui-05-pastures.png`
- [ ] `ui-06-productions.png`

Commit the `docs/screenshots/*.png` files to git, or attach them to **GitHub Releases** as extra assets (README images usually live in the repo).

---

## One-paragraph “store” description (copy-paste)

**FS25 Farm Dashboard** pairs a lightweight **Farming Simulator 25 mod** with a **Windows desktop app**. The mod exports live farm data from your save or server to `data.json`; the app serves a rich **browser dashboard** on your PC—livestock, vehicles, fields (with Precision Farming context), economy, pastures, and production chains—with optional **FTP** support for dedicated hosts. Install the mod, load your save once, then install the desktop app and open **http://localhost:8766** to manage your operation from a second screen.

---

*Document revision: 2.0 — aligned with app **2.0.0** / mod **2.0.0.0** (see [CHANGELOG.md](./CHANGELOG.md)). Authors: **JoshWalki** & **WizardlyPayload** ([AUTHORS.md](../AUTHORS.md)).*
