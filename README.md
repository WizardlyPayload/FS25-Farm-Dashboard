# FS25 Farm Dashboard

A desktop companion app plus a **Farming Simulator 25** mod that exports live farm data (fields, vehicles, animals, economy, production, and more) to a local dashboard in your browser. Use it on your own PC or point it at a dedicated server over FTP.

**Public repo:** [github.com/WizardlyPayload/FS25-Farm-Dashboard](https://github.com/WizardlyPayload/FS25-Farm-Dashboard) · [**Releases**](https://github.com/WizardlyPayload/FS25-Farm-Dashboard/releases)

**Current release:** **2.0.0** (app) / **2.0.0.0** (mod) — see [RELEASE_NOTES.md](RELEASE_NOTES.md) for GitHub blurbs and [docs/CHANGELOG.md](docs/CHANGELOG.md) for the full version history.

**Documentation:** [docs/README.md](docs/README.md) (index) · **Simple install:** [INSTALL.md](INSTALL.md) · **Product description + screenshot checklist:** [docs/DESCRIPTION_AND_SCREENSHOTS.md](docs/DESCRIPTION_AND_SCREENSHOTS.md) · **Security & LAN access:** [docs/SECURITY.md](docs/SECURITY.md) · **Release blurbs + doc map:** [RELEASE_NOTES.md](RELEASE_NOTES.md) · **Authors:** [AUTHORS.md](AUTHORS.md)

**2.0.0 timing & behaviour:** In [docs/CHANGELOG.md](docs/CHANGELOG.md), open section **2.0.0** and find subsections **G** (mod stagger & `config.xml`), **H** (FTP polling & setup), **I** (farm switcher). [RELEASE_NOTES.md](RELEASE_NOTES.md) has a table with the same links for GitHub Releases.

---

## What you get

| Piece | Role |
|--------|------|
| **FS25 mod** (`FS25_FarmDashboard`) | Runs inside the game (or dedicated server). Writes `data.json` and uses your savegame for full context. |
| **Farm Dashboard app** (Windows `.exe` installer) | Runs on your PC. Reads that data (local disk or FTP), merges it with savegame XML when needed, and serves the dashboard on **port 8766** (localhost and your LAN — see below). |

---

## Install order (important)

**For the shortest step-by-step guide, read [INSTALL.md](INSTALL.md) first.** It states clearly that the **mod must be run (save loaded) for every save you want the dashboard on** before you install the Windows app.

Do this in order the first time:

1. **Install the FS25 mod** (see below).
2. **Start FS25**, enable the mod on your save (or server), and **load the save at least once** so the mod can create its config/output folders and start writing data.
3. **Install the Farm Dashboard desktop app** (the `.exe` from this repository’s **Releases** page, or from your own build).
4. Open the app and complete **Setup** (local paths and/or FTP for hosted servers).

The app expects the mod to be in place and the game to have run with it enabled; installing the desktop app first can make first-time setup confusing if folders or `data.json` do not exist yet.

---

## 1. Installing the mod

1. Copy the **`FS25_FarmDashboard_Mod`** folder into your FS25 mods directory so the game sees a mod named **`FS25_FarmDashboard`** (folder name must match what you ship).

   **Typical Windows path:**

   `Documents\My Games\FarmingSimulator2025\mods\`

2. In FS25, **activate the mod** for your save (or add it to your dedicated server’s mod list).
3. **Load the save** (or start the server). You only need to do this once before relying on the dashboard; after that, play as normal.

The mod writes under your profile, e.g.:

`Documents\My Games\FarmingSimulator2025\modSettings\FS25_FarmDashboard\<savegame folder>\data.json`

---

## 2. Installing the desktop app (Windows installer)

1. Download the latest **`FS25 Farm Dashboard` Setup `.exe`** from the **Releases** page of this repository (or run the installer you built yourself).
2. Run the installer and follow the prompts (desktop shortcut is optional depending on installer settings).
3. Launch **Farm Dashboard** from the Start menu or desktop.

The app listens on **port 8766** by default. If something else uses that port, close the other program or adjust your setup.

---

## 3. First-time setup in the app

When you open the app for the first time, it opens the **Setup** screen:

- **Local play:** Point to your FS25 profile / mod output folder if the defaults are wrong.
- **Dedicated / GPortal:** Use **FTP** mode with host, user, password, and paths as provided by your host (often under `profile/`).

Save the settings. The main dashboard will load and start polling for data.

---

## 4. Using the dashboard

- On the PC running the app, open **http://localhost:8766** (or the URL shown by the app).
- **From another device on the same network** (phone, tablet, second PC), open **`http://<this-computer’s-LAN-IP>:8766`** — the server listens on all interfaces. There is **no login**; anyone who can reach that port on your network can see the same dashboard data. Use a firewall on untrusted networks; see [docs/SECURITY.md](docs/SECURITY.md).
- Use the navigation (livestock, fields, vehicles, economy, productions, pastures, etc.).
- For **multi-farm** or FTP servers, use the **farm selector** in the header when available.

---

## Building the installer from source (developers)

Prerequisites: **Node.js LTS**, **npm**, Windows recommended for the current NSIS target.

```bash
cd FS25_FarmDashboard_App/FS25_FarmDashboard_App
npm install
npm run dist
```

In the **GitHub clone** (`FS25_Dashboard APP` folder names), use:

```bash
cd "FS25_Dashboard APP"
npm install
npm run dist
```

The installer is written to **`release/`** (see `package.json` → `build.directories.output`).

To run without packaging:

```bash
npm start
```

---

## Repository layout

| Path | Contents |
|------|----------|
| `FS25_FarmDashboard_Mod/` | FS25 mod (Lua) — ship this to the game `mods` folder |
| `FS25_FarmDashboard_App/` | Electron app (Node), web UI, merger, FTP polling |

### Syncing this tree into the GitHub Desktop clone

The public repo uses folder names **`FS25_Dashboard APP`** and **`FS25_Dashboard MOD`**. To copy this codebase into `Documents\FS25-Farm-Dashboard` **without** `node_modules` or **`release/`** (build the `.exe` locally after you pull):

1. Open **PowerShell** in this repo root (MAIN CODEBASE).
2. Run:

```powershell
.\tools\Sync-To-GitClone.ps1
```

Optional: `.\tools\Sync-To-GitClone.ps1 -GitRoot "C:\path\to\FS25-Farm-Dashboard"`

Then open **`FS25-Farm-Dashboard`** in **GitHub Desktop**, review changes, commit, and push.

---

## GitHub: pushing with GitHub Desktop

1. **Clone** your existing repository in GitHub Desktop (or add this folder as a local repo if you created it first).
2. **Recommended:** Commit the **`.gitignore`** in the repo root so `node_modules/`, `release/`, and build artifacts are not uploaded.
3. Stage changes → write a clear **summary** (e.g. `Release v2.0.0 — README and changelog`) → **Commit to main**.
4. **Push origin** to sync with GitHub.

### Publishing a release (for the `.exe` and mod zip)

1. On GitHub: **Releases** → **Draft a new release**.
2. **Tag:** e.g. `v2.0.0` (create new tag on `main`).
3. **Title:** e.g. `FS25 Farm Dashboard 2.0.0`.
4. **Description:** Paste from [RELEASE_NOTES.md](RELEASE_NOTES.md) or summarize; full history in [docs/CHANGELOG.md](docs/CHANGELOG.md).
5. **Attach binaries:**
   - The **NSIS installer** `.exe` from `FS25_FarmDashboard_App/FS25_FarmDashboard_App/release/`.
   - A **zip of the mod folder** `FS25_FarmDashboard_Mod` (users extract into `mods`).

Check **“Set as latest release”** if appropriate, then **Publish release**.

---

## Troubleshooting

| Issue | What to try |
|--------|-------------|
| Dashboard says “waiting for data” | Ensure FS25 ran with the mod enabled; check Setup paths or FTP. |
| Nothing on FTP | Confirm FTP credentials, `profile` path, and savegame slot match the server. |
| Port 8766 in use | Close the other program or restart the PC after closing old instances of the app. |

---

## Two local folders (MAIN backup + GitHub clone)

If you keep a second copy outside git (e.g. **MAIN CODEBASE**) as a safety net, run `tools/Sync-FarmDashboard-Trees.ps1` to mirror sources between that tree and this repo: `-Direction ToGit` after editing MAIN (before `git commit`), or `-Direction FromGit` after `git pull` to refresh MAIN. Use `-DryRun` first to preview. Override paths with `-MainRoot`, `-GitRoot`, or `FARM_DASHBOARD_MAIN_ROOT` / `FARM_DASHBOARD_GIT_ROOT`.

---

## Reporting bugs

Include: FS25 version, single-player vs dedicated, **mod** version **2.0.0.0**, **app** version **2.0.0**, local vs FTP, and steps to reproduce.

---

## Credits

**JoshWalki** (Josh) / **Wizardlypayload** — original Farm Dashboard and FS25 mod. **WizardlyPayload** — co-author (Electron app, maintenance, docs). See **[AUTHORS.md](AUTHORS.md)** and `FS25_FarmDashboard_Mod/.../modDesc.xml`.

---

## License

Add a `LICENSE` file to the repository if you want to specify terms (e.g. MIT, GPL, or “all rights reserved”). Until then, assume **all rights reserved** unless you state otherwise.
