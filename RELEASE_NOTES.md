# FS25 Farm Dashboard — Release notes

Use this file for **short copy-paste text** on GitHub Releases. The **full history** is in [docs/CHANGELOG.md](docs/CHANGELOG.md). **Security and LAN access** are summarized in [docs/SECURITY.md](docs/SECURITY.md). **Authors:** [AUTHORS.md](AUTHORS.md) — **JoshWalki** (Josh) & **WizardlyPayload**.

---

## Current shipping line: **2.0.0** (app) / **2.0.0.0** (mod)

### GitHub release title (example)

`FS25 Farm Dashboard 2.0.0`

### Description (copy-paste)

**FS25 Farm Dashboard 2.0.0** ships two parts:

1. **FS25 mod** (version **2.0.0.0**) — install into FS25 `mods`, enable on your save or server, and **run the game at least once** before relying on the desktop app.
2. **Windows desktop app** (version **2.0.0**) — NSIS installer; serves the dashboard at **http://localhost:8766** and on your **LAN** (e.g. `http://192.168.x.x:8766`) so you can use a phone or second PC on the same Wi‑Fi (**no login** — see [docs/SECURITY.md](docs/SECURITY.md)).

**Highlights in 2.0.0:** Reliable field and merge behaviour (Lua vs XML, `needsWork`, rolling, multi-farm field lists); single-player and host **authority** fixes so `data.json` always updates; robust JSON/array handling in the web UI; mod shop export (from 1.1.2) with repo hygiene for extracted PNGs; **documentation** for network use, **mod collection timing**, and **FTP polling** (see table below).

**Install order:** mod → enable & load save → then install/run the desktop app. See the [README](README.md) for full steps, FTP setup, and troubleshooting.

### Where this release is documented (2.0.0)

| Topic | Document | What to read |
|--------|-----------|----------------|
| **Mod: staggered collectors** — one module per time slice, `collectionCycleMs`, `config.xml` | [CHANGELOG §2.0.0 → **G**](docs/CHANGELOG.md) | How often `data.json` refreshes *inside the game* vs a single 10s “do everything” tick |
| **App: FTP polling** — interval, initial delay, **sync vs staggered** multi-server | [CHANGELOG §2.0.0 → **H**](docs/CHANGELOG.md) | How often the app pulls remote `data.json` and how multiple FTP servers are scheduled |
| **Farm switcher** — FTP and multi-farm local saves | [CHANGELOG §2.0.0 → **I**](docs/CHANGELOG.md) | When the navbar farm dropdown appears |
| **LAN / browser / no login** | [SECURITY.md](docs/SECURITY.md) | Trust model and firewall |
| **Product + setup screenshot ideas** | [docs/DESCRIPTION_AND_SCREENSHOTS.md](docs/DESCRIPTION_AND_SCREENSHOTS.md) | Long description, screenshot checklist |
| **Everything since 1.0.0** | [CHANGELOG.md](docs/CHANGELOG.md) | Full version history |
| **Authors** | [AUTHORS.md](AUTHORS.md) | **JoshWalki** (Josh) & **WizardlyPayload** |

### Attach to this release (recommended)

- `FS25 Farm Dashboard Setup x.x.x.exe` (from `FS25_FarmDashboard_App/FS25_FarmDashboard_App/release/` after `npm run dist`, or `FS25_Dashboard APP/release/` in the GitHub clone layout)
- `FS25_FarmDashboard_Mod.zip` — zip the **`FS25_FarmDashboard_Mod`** folder (or **`FS25_Dashboard MOD`** from the clone) so users extract it into `Documents\My Games\FarmingSimulator2025\mods\`

### Reporting issues

Include: FS25 version, single-player vs dedicated, mod **2.0.0.0**, app **2.0.0**, local vs FTP, and what you expected vs what happened.

---

## Earlier releases (summary)

| Version | Notes |
|---------|--------|
| **1.1.2** | Mod shop image export, `items_mod_extract` thumbnails, vehicle image matching improvements. |
| **1.0.0** | First public release — see [docs/CHANGELOG.md](docs/CHANGELOG.md). |

Full detail for every line: [docs/CHANGELOG.md](docs/CHANGELOG.md).
