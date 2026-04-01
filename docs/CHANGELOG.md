# Farm Dashboard — Changelog

All notable changes to this project are recorded here, from the first public release through **2.0.0**. For GitHub release blurbs, see [RELEASE_NOTES.md](../RELEASE_NOTES.md). For **network exposure and trust assumptions**, see [SECURITY.md](./SECURITY.md).

---

## Versioning

| Artifact | Where it lives | Format |
|----------|----------------|--------|
| **Desktop app** | `FS25_FarmDashboard_App/FS25_FarmDashboard_App/package.json` | Semver (e.g. `2.0.0`) |
| **FS25 mod** | `FS25_FarmDashboard_Mod/FS25_FarmDashboard_Mod/modDesc.xml` and `FarmDashboard.VERSION` in Lua | Giants style (e.g. `2.0.0.0`) |
| **Source headers** | First line of many `.js` / `.lua` files | `v2.0.0` (aligned with the release above) |

---

## Release overview

| Version | Focus |
|---------|--------|
| **1.0.0** | First public release: mod + Electron app, local/FTP, XML + Lua merge, full dashboard sections. |
| **1.1.2** | Mod shop image export pipeline, vehicle thumbnails from extracted PNGs, installer resources. |
| **2.0.0** | Field accuracy and merge rules, single-player authority, multi-farm UI, data pipeline robustness, packaging, docs, repo hygiene, security/network documentation. |

---

## 1.0.0 — First public release

**App:** `1.0.0` · **Mod:** `1.0.0.0`

Initial shipping version documented in [RELEASE_NOTES.md](../RELEASE_NOTES.md).

### Product

- **FS25 mod** — Background collector writing `data.json` under the user profile (`modSettings/FS25_FarmDashboard/…`), configurable update interval (default 10s).
- **Desktop app (Electron)** — HTTP + WebSocket on port **8766**, reads local files or **FTP**, merges **live Lua JSON** with **savegame XML** (`xmlCollector.js` + `dataMerger.js`).
- **Dashboard (web)** — Livestock, vehicles, fields (including Precision Farming–style overlays when the mod exports them), economy, pastures, productions, weather, notifications, theming.

### Install expectations

Mod must be enabled and the save loaded at least once before the desktop app can show data; see [README.md](../README.md).

---

## 1.1.2 — Mod shop images & vehicle thumbnails

**App:** `1.1.2` · **Mod:** unchanged at `1.0.0.0` on this line (mod version bumps with **2.0.0**).

### PowerShell: `tools/Export-ModStoreImages.ps1`

- Recursively scans the FS25 **mods** folder (unpacked dirs and `.zip` archives).
- Prefers **store** textures (`store_*.png` / `.dds`, `textures\store`, etc.); icon-only assets opt-in via flags.
- Maps mod XML to English display names; outputs **`ModKey__<sanitized title>.png`** (or basename fallback) under `web/assests/img/items_mod_extract/`.
- **DDS → PNG** via ImageMagick `magick` or DirectXTex **texconv** (optional bundled exe).
- Emits **`FD_JSON`** progress lines for Electron; supports **skip if file exists**, **`-Force`**, summary JSON for the app.

### Electron (`main.js`)

- IPC **`export-mod-store-images`** with line-buffered stdout, BOM-safe summary JSON, long timeout, completion dialogs.
- **`GET /api/item-image-filenames`** — lists curated `items/` and mod-extract PNGs for the renderer.

### Web

- **`modExportProgress.js`** — modal/overlay progress on setup and dashboard.
- **`vehicles.js` / `app.js`** — loads mod-extract filenames from the API; **strict-then-fuzzy** filename matching vs curated Giants-style `items/` assets; manual **`vehicleModelMap`** fallbacks.

### Build

- `electron-builder` **`extraResources`** ships the PowerShell script (and optional `texconv`).

### Known limitations (1.1.2)

- Vehicle ↔ thumbnail matching can still be wrong in edge cases (title vs in-game name, fuzzy collisions). Export tooling is solid; matching heuristics remain the main follow-up.

---

## 2.0.0 — Full change set since 1.0.0 (shipping line)

**App:** `2.0.0` · **Mod:** `2.0.0.0` (`modDesc.xml`, `FarmDashboard.VERSION`)

This release **includes everything below**, including behaviour refined during development after **1.0.0** and **1.1.2** (field pipeline, merge rules, authority, UI). It supersedes ad-hoc session notes when they conflict with the shipped tree.

### A. Mod — runtime & authority

- **`FarmDashboard:isAuthority()`** — Data collection runs in **single-player** and on **MP host / dedicated**, not only when `g_server` is set. Fixes **no `data.json` updates in SP** when `g_server` was nil.
- **Debug / introspection bridge** — Any experimental `FieldStateDebugBridge` / `field_introspection` paths from development were **removed**; shipping mod writes normal **`data.json`** only.

### B. Mod — field data (`FieldDataCollector.lua` and related)

- **Owned vs NPC fields** — Player-owned fields use the same **`FieldState:update`-style sampling** as unowned/NPC fields where applicable, instead of relying only on APIs that could **lag or disagree** with the map for owned land.
- **Ground type** — Adjustments that cleared **growth** no longer run when a **crop is planted** (avoids wiping growth stage used for rolling / status).
- **Rolling / compaction** — **`rollerLevel`** from the engine is exported as a **rolled fraction** consistent with HUD-style semantics (engine raw value can be “remaining work”, not “progress”).
- **Growth / rolling windows** — Handles **grass vs arable** growth-stage differences where the rolling window applies.
- **Field suggestions (Lua)** — Ordering and harvest/mulch/stubble logic aligned with live probes; dead **withered + grass** branch removed where it could never run.

### C. App — merge layer (`dataMerger.js`, `xmlCollector.js`)

- **`needsWork`** — When both Lua and XML exist, **Lua wins** (`luaField.needsWork ?? xmlField.needsWork`). XML-only heuristics (`limeLevel`, `sprayLevel`, `plowLevel`, etc.) no longer force **false “needs work”** on healthy growing crops.
- **Field suggestions** — If Lua provides suggestions, **Lua list is used** (sorted by priority); XML harvest lines are **filtered** when the live probe shows **mulched stubble**, **no crop**, etc., to avoid stale “Harvest …” rows.
- **Full field list for multi-farm** — Merge prefers **`allFields`** from XML when present so the API exposes **every field** with **`ownerFarmId`**; the UI filters by selected farm.

### D. Dashboard — web client (`web/assests/js/…`)

- **Lua tables as JSON objects** — `fields` (and similar) often arrive as **`{ "1": {…} }`**, not arrays. **`coerceJsonArray` / `normalizeFieldsPayload`** (and related paths in **`realtime-connector.js`**, **`apiStorage.js`**, **`fields.js`**) convert these so lists render and filters work.
- **`buildSuggestion` / empty suggestions** — Empty Lua `suggestions` serializes as **`{}`**; code no longer assumes **array**-only or throws when spreading.
- **Initial file read** — Local **`data.json`** watch can miss **`add`** for an existing file; **immediate read** after watch start avoids “empty dashboard until touch” in some cases.
- **Multi-farm** — **`dashboard.allFields`** holds the full list; **`filterFieldsForFarmView`** (and farm switch) show the correct farm without always including farm **1**.
- **Status badge** — “Needs work” aligns with **`needsWork || needsRolling`** and the Needs Work filter.
- **Merged top-level fields** — **`money`** and other merger outputs update when **`!== undefined`** (including zero balance).
- **Livestock tag image** — **`tag.svg`** replaces missing **`tag.png`** reference.

### E. Network & browser use (unchanged behaviour, now documented)

- Server listens on **`0.0.0.0:8766`**; **CORS** enabled — you can open **`http://<PC-LAN-IP>:8766`** from another device on the same network. See **[SECURITY.md](./SECURITY.md)** for trust boundaries (no login on LAN).

### F. Packaging, repo, and versions

- **`preload.js`** included in **`electron-builder` `files`** so it ships if preload is wired later.
- **Removed** unused **`VehicleDataCollectorSimple.lua`** (never listed in `modDesc.xml`); tooling lists updated accordingly.
- **Source headers** normalized to **`v2.0.0`** across tracked app and mod sources for this release.
- **Generated mod shop PNGs** — Contents of **`web/assests/img/items_mod_extract/`** are **gitignored** (keep locally after export; **`.gitkeep`** preserves the folder). Not required for a clean clone.

### G. Mod — staggered collection & `config.xml` (different from the app’s FTP poll)

After **1.0.0**, the mod moved to **staggered collection** so the game is not asked to run **every** collector in the same frame on every tick:

- **`FarmDashboardDataCollector`** runs **one enabled module per time slice** (animals → vehicles → fields → … in a fixed order) across a **`collectionCycleMs`** window (default **60s**, clamped **5s–30min**). Each slice still **assembles cached data** and **rewrites `data.json`**, so the file updates often but work is spread out.
- **`config.xml`** (under `modSettings/FS25_FarmDashboard/`) supports **`updateInterval`**, **`collectionCycleMs`**, and **per-module toggles** (animals, vehicles, fields, finance, weather, economy, production). Older configs without `collectionCycleMs` get a derived cycle length (legacy: at least **7×** the old update interval or **60s** minimum).
- **`FarmDashboard.UPDATE_INTERVAL`** follows **`collectionCycleMs`** (the Lua mission update cadence), not the old single 10s “do everything” model.

This is **independent** of the **desktop app’s FTP polling** settings below.

### H. App — setup screen, FTP polling, and mod image export

- **FTP polling** (`setup.html` + `main.js`): For dedicated / hosted servers, users can set **delay before first poll (seconds)**, **poll every (minutes)** (1–25), and **schedule mode** — **sync** (poll **all** FTP servers on the same tick) or **staggered** (one FTP server per sub-interval so work is spread across the interval). Stored under **`config.ftpPolling`** and executed by **`startFtpPollingCoordinator`**.
- **Scan FS25 mods for dashboard images** — Button on setup runs the **mod shop export** pipeline (PowerShell **`Export-ModStoreImages.ps1`** via IPC), filling **`items_mod_extract/`** for vehicle thumbnails (see **1.1.2**).
- **Scan local saves** — **`scan-local-saves`** helps discover **`modSettings/FS25_FarmDashboard`** save folders for configuration.

*Note:* Earlier development sessions experimented with extra dashboard-only timers and debug APIs; the **shipping 2.0.0** tree standardises on **file watch + FTP coordinator + mod export** as above.

### I. Farm switcher (multi-farm & GPortal)

- **`isFarmDropdownEnabled()`** — The navbar farm dropdown appears when the active server is **FTP** **or** when there is **more than one player farm** in the save (local multi-farm), so you are not limited to the original **FTP-only** switcher in some **1.0.0** builds.
- Development history included several **reverts and re-applies** (farm id types, `ownerFarmId` from Lua vs XML, `activeFarmId === 0` edge cases). **2.0.0** keeps **Lua-first `ownerFarmId`** in merge where applicable, **`allFields`**, **`filterFieldsForFarmView`**, and numeric-safe comparisons as in the current **`apiStorage.js`** / **`fields.js`** / **`realtime-connector.js`**.

### J. Known limitations (2.0.0)

- **FTP mode** — Savegame **XML** merge needs local or downloaded files; **Lua-only** merge is expected when XML is unavailable on hosted paths.
- **Husbandry totals (Lua)** — Some aggregations still assume **farm 1** in places; multi-farm husbandry totals may be incomplete for other farm IDs until a future release.
- **`npm audit`** — Some advisories remain in **electron** / **electron-builder** transitive trees; address with tested major upgrades post-release unless a critical runtime CVE applies to your threat model.

### Maintainer note

After pulling, run **`npm install`** under `FS25_FarmDashboard_App/FS25_FarmDashboard_App` before **`npm run dist`** so `package-lock.json` matches `package.json`.

---

## Documentation map

| File | Role |
|------|------|
| [README.md](../README.md) | Install, build, LAN browser access, troubleshooting, GitHub workflow |
| [INSTALL.md](../INSTALL.md) | Basic install order: mod in every target save **before** the desktop app |
| [RELEASE_NOTES.md](../RELEASE_NOTES.md) | Short copy-paste text for GitHub Releases |
| [docs/DESCRIPTION_AND_SCREENSHOTS.md](./DESCRIPTION_AND_SCREENSHOTS.md) | Long-form product description + screenshot checklist |
| [docs/SECURITY.md](./SECURITY.md) | Network exposure, LAN browser use, trust model |
| [../AUTHORS.md](../AUTHORS.md) | JoshWalki & WizardlyPayload |
| This file | Full version history |

---

## Reporting issues

Include: FS25 version, single-player vs dedicated, **mod** version (see `modDesc.xml`), **app** version (see `package.json`), local vs FTP, and steps to reproduce.

---

## Credits

**JoshWalki** (Josh) / **Wizardlypayload** and **WizardlyPayload** — see **[AUTHORS.md](../AUTHORS.md)** and `modDesc.xml`.
