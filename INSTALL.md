# FS25 Farm Dashboard — Installation (simple steps)

Read these steps **in order**. Do **not** install the Windows dashboard app until the mod has been used in **every** save where you want the dashboard.

### Why the mod has to come before the dashboard

The **Windows app is not inside the game**. It cannot read your farm directly from FS25. It only reads a file called **`data.json`** that the **mod** creates and updates while you play (or while a dedicated server runs).

Until you have **loaded a save with the mod enabled** at least once:

- The game has not created the mod’s output folders under your profile.
- **`data.json` does not exist yet** (or is not being updated) for that save.
- The dashboard would have **nothing to show**, even if the app is installed.

So: **mod first** (so FS25 can create the data), **dashboard app second** (so something can open that data in the browser). The order avoids a blank or “waiting for data” setup when you first open the app.

On a **dedicated / hosted server**, the same idea applies: the mod must be **active on the server** and the save must have run so **`data.json`** exists in the server profile (where your FTP or host points)—not only on your own PC.

---

## 1. Install the mod in Farming Simulator 25

1. Copy the **`FS25_FarmDashboard`** mod folder into your FS25 mods folder.  
   **Typical Windows path:**  
   `Documents\My Games\FarmingSimulator2025\mods\`
2. Start **Farming Simulator 25**.

---

## 2. Enable the mod on **each** save you care about (required)

**You must do this for every savegame (single-player or server) where you want the dashboard to work.**

1. For each save: open **Mods** and make sure **Farm Dashboard** is **enabled** for that save.
2. **Load that save** (play until you are in the game world, not only the menu).
3. Repeat for **every other save** that should use the dashboard (different slots, multiplayer farms, dedicated server saves, etc.).

The mod creates its folders and starts writing **`data.json`** only **after** the save has been loaded with the mod active. If you skip this for a save, that save will have no data for the app later.

---

## 3. Install the Windows dashboard app (only after step 2)

1. Run the **FS25 Farm Dashboard** installer (`.exe` from [Releases](https://github.com/WizardlyPayload/FS25-Farm-Dashboard/releases) or your own build).
2. Start **Farm Dashboard** from the Start menu or desktop shortcut.
3. The first time it opens, complete **Setup** (local folder to your FS25 profile, or **FTP** if you use a hosted/dedicated server).
4. Open your browser to **http://localhost:8766** (or the address the app shows).

### Tablet or phone on the same network (Wi‑Fi / LAN)

The dashboard works in any normal web browser. The PC that runs **Farm Dashboard** hosts the site for your whole home network.

1. **Keep the app running** on the PC (the embedded server must be up).
2. **Put the tablet (or phone) on the same network** as that PC — same Wi‑Fi, or Wi‑Fi and Ethernet on the same router.
3. On the **PC**, find its **LAN IPv4 address** (the address other devices use to reach it):
   - **Windows:** Open **Command Prompt** or **PowerShell** and run `ipconfig`. Under your active adapter (**Wi‑Fi** or **Ethernet**), note **IPv4 Address** (often looks like `192.168.x.x` or `10.x.x.x`).
4. On the **tablet**, open a browser and go to:

   **`http://<that-IPv4-address>:8766`**

   Example: `http://192.168.1.50:8766`

5. If the page does not load, on the PC check **Windows Firewall** and allow **Node.js** / **Farm Dashboard** on **private** networks when prompted, or see [docs/SECURITY.md](docs/SECURITY.md) for firewall notes.

There is **no separate login** on the tablet; anyone who can open that URL on your network sees the same farm data. Do not use this on untrusted public Wi‑Fi without firewall rules — details in [docs/SECURITY.md](docs/SECURITY.md).

---

## 4. If something says “waiting for data”

- Confirm you completed **step 2** for that save (mod enabled, save **loaded** at least once).
- Check **Setup** paths or FTP settings so they point at the right profile and save folder.
- Make sure **FS25** has been run with the mod on for that save before expecting data.

---

## Short version

| Order | What to do |
|-------|------------|
| **First** | Mod in `mods` folder → enable on save → **load save** (repeat for **all** saves you want). |
| **Then** | Install and run the **dashboard app** → Setup → open **http://localhost:8766** on the PC, or **`http://<PC-LAN-IP>:8766`** on a tablet on the same network (see above). |

**Authors:** [AUTHORS.md](AUTHORS.md)
