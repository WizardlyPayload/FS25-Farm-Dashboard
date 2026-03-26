# FS25 Farm Dashboard — Release 1.0.0

First public release for wider testing.

## Release description (paste into GitHub Releases)

**FS25 Farm Dashboard 1.0.0** includes:

1. **FS25 mod** (version in `FS25_Dashboard MOD/modDesc.xml`) — install into FS25 `mods`, enable on the save or server, and **run the game at least once** before relying on the desktop app.
2. **Windows desktop app** (version in `FS25_Dashboard APP/package.json`) — NSIS installer; serves the dashboard at **http://localhost:8766**.

**Install order:** mod → enable & load save → then install/run the desktop app. See [README.md](README.md).

**Repository:** https://github.com/WizardlyPayload/FS25-Farm-Dashboard

## Suggested release assets

- `FS25 Farm Dashboard Setup x.x.x.exe` from `FS25_Dashboard APP/release/` after `npm run dist`
- Zip of **`FS25_Dashboard MOD`** for users to extract into `Documents\My Games\FarmingSimulator2025\mods\`

## Reporting issues

Include: FS25 version, single-player vs dedicated, mod and app versions, local vs FTP, and steps to reproduce.
