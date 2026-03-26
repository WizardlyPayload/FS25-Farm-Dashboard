# FS25 Farm Dashboard

Real-time farm management dashboard for **Farming Simulator 25**: an **Electron** desktop app plus an in-game **mod** that exports live data (fields, vehicles, animals, economy, productions, and more) to a browser UI on your PC. Works with local saves or dedicated servers (including FTP).

**GitHub:** [github.com/WizardlyPayload/FS25-Farm-Dashboard](https://github.com/WizardlyPayload/FS25-Farm-Dashboard)

Clone in **GitHub Desktop** and open the **`FS25-Farm-Dashboard`** folder on your machine.

**Release:** **1.0.0** (see [RELEASE_NOTES.md](RELEASE_NOTES.md) · [Releases](https://github.com/WizardlyPayload/FS25-Farm-Dashboard/releases)).

---

## Repository layout

| Folder | Contents |
|--------|----------|
| **`FS25_Dashboard APP`** | Electron app (Node), web UI, API on port **8766** by default |
| **`FS25_Dashboard MOD`** | FS25 mod (Lua) — copy into the game `mods` directory |

---

## Install order (for end users)

1. **Install the mod** — copy **`FS25_Dashboard MOD`** into FS25 mods so the game sees the mod (folder name must match how you package it, e.g. `FS25_FarmDashboard`).
2. **Run FS25**, enable the mod on your save (or server), and **load the save at least once** so the mod creates its output (`data.json` under `modSettings/FS25_FarmDashboard/…`).
3. **Install the desktop app** — run the **Windows `.exe`** from [**Releases**](https://github.com/WizardlyPayload/FS25-Farm-Dashboard/releases) when published, or build locally (`npm run dist`).
4. Open the app and complete **Setup** (local paths or **FTP** for hosted servers).

Installing the app before the mod has run at least once can make first-time setup harder because folders or `data.json` may not exist yet.

---

## Mod install (Windows, typical)

Copy the mod folder into:

`Documents\My Games\FarmingSimulator2025\mods\`

Enable it in the game mod list for your save or dedicated server.

---

## Desktop app install

- Use the **NSIS installer** from [**Releases**](https://github.com/WizardlyPayload/FS25-Farm-Dashboard/releases), or build with `npm run dist` in `FS25_Dashboard APP`.
- After install, launch **FS25 Farm Dashboard** and use **http://localhost:8766** in your browser (unless you change the port).

---

## Build from source (developers)

Prerequisites: **Node.js LTS**, **npm**, Windows (for the current NSIS target).

```powershell
cd "FS25_Dashboard APP"
npm install
npm run dist
```

Installer output: **`FS25_Dashboard APP`** → **`release/`**.

Run without packaging:

```powershell
cd "FS25_Dashboard APP"
npm start
```

---

## GitHub Desktop workflow

1. **Clone** this repository in GitHub Desktop (or **File → Add local repository** if this folder is already a clone).
2. Commit changes with a clear message → **Push origin**.
3. **Releases:** create a tag (e.g. `v1.0.0`), upload the **installer `.exe`** and a **zip of the mod folder** for players who don’t build from source.

Do **not** commit `node_modules/` — use `.gitignore` (included).

---

## Two local folders (MAIN backup + this clone)

If you keep a second copy outside git (e.g. **MAIN CODEBASE**) as a safety net, run `tools/Sync-FarmDashboard-Trees.ps1` to mirror sources between that tree and this repo: `-Direction ToGit` after editing MAIN (before `git commit`), or `-Direction FromGit` after `git pull` to refresh MAIN. Use `-DryRun` first to preview. Override paths with `-MainRoot`, `-GitRoot`, or `FARM_DASHBOARD_MAIN_ROOT` / `FARM_DASHBOARD_GIT_ROOT`.

---

## Troubleshooting

| Issue | Try |
|--------|-----|
| Dashboard waits for data | Confirm FS25 ran with the mod enabled; check Setup paths or FTP. |
| Nothing via FTP | Check host, credentials, and paths (`profile`, savegame slot). |
| Port 8766 in use | Close the other app using the port or restart after closing old instances. |

---

## Credits

Based on **JoshWalki**’s Farm Dashboard concept; this fork runs the stack in an Electron app. See `FS25_Dashboard MOD/modDesc.xml` for author credits.

---

## License

Add a `LICENSE` file if you want explicit terms; until then, rights remain with the authors unless stated otherwise.
