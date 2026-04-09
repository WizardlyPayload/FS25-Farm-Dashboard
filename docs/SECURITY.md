# FS25 Farm Dashboard — Security & network notes

**Authors:** **JoshWalki** (Josh) / Wizardlypayload and **WizardlyPayload** — see [AUTHORS.md](../AUTHORS.md).

This document describes how the **desktop app** exposes data, what is **not** protected, and how that fits a **home / LAN** setup. It is written for **2.0.0**; review again after major upgrades.

---

## Network: browser access on your LAN (important)

The app binds the HTTP server to **`0.0.0.0` on port `8766`**, not only `127.0.0.1`. That means a **tablet or phone browser on the same Wi‑Fi** can load the dashboard by using the **PC’s LAN IPv4 address**, not `localhost` (on the tablet, `localhost` would mean the tablet itself).

| Access | Typical URL |
|--------|-------------|
| Same PC | `http://localhost:8766` |
| Phone / tablet / another PC **on the same network** | `http://<this-PCs-LAN-IPv4>:8766` (e.g. `http://192.168.1.50:8766`) — find the IPv4 with **`ipconfig`** on Windows under the active adapter |

User-facing steps (same network, firewall, examples) are also in the root **[INSTALL.md](../INSTALL.md)**.

**CORS** is enabled for the API routes so a normal browser can load the dashboard from that origin.

**Implications**

- Anyone who can reach **port 8766** on that machine (same Wi‑Fi, Ethernet, or routed LAN) can **read the same farm data** the app serves (merged JSON: animals, fields, money, vehicles, etc.). There is **no login** and **no per-client access control** in the app.
- This is **by design** for convenience (tablet on the sofa, second monitor, teammate on LAN). It is **not** suitable to expose directly to the **public internet** without extra layers (VPN, reverse proxy with auth, firewall rules).

**Recommendations**

- Use **Windows Firewall** (or your OS firewall) to block **inbound** TCP **8766** from untrusted networks if the PC joins public Wi‑Fi.
- For **remote** access from outside the home, prefer a **VPN** into your network rather than port-forwarding 8766 to the world.
- **FTP passwords** for dedicated servers are stored in **electron-store** (local user profile). Treat the PC account as trusted; use a **strong Windows password** and disk encryption if the machine is portable.

---

## Electron & web stack (threat model)

The dashboard window loads **local** HTML/JS served by Express. Typical settings include **`nodeIntegration: true`**, relaxed **`webSecurity`**, and **no context isolation** — this matches a **single-user, trusted local tool**, not a website that loads third-party ads or untrusted URLs.

**Do not** point the Electron window at arbitrary remote sites with this configuration. **Do not** load untrusted content in the same window.

---

## Dependencies & builds

- **`npm audit`** may report issues in **electron**, **electron-builder**, or transitive **dev** dependencies. Many affect **build-time** tooling (packaging archives), not the runtime server on a normal user install.
- After **`npm audit fix`**, remaining items often need **major** upgrades (`npm audit fix --force`) and full regression testing — plan those **after** a release, not the night before, unless a fix is critical.

---

## Mod (game) side

The FS25 mod only writes **`data.json`** under the user profile. It does not open a network port. Game and mod updates are outside this repo’s control; keep FS25 and mods updated per GIANTS’ guidance.

---

## Reporting security concerns

For **public** security issues (e.g. unintended remote code execution via the app), contact the maintainers via the GitHub repository’s channels (**JoshWalki** & **WizardlyPayload** — [AUTHORS.md](../AUTHORS.md)). Include app version **2.0.0** and platform **Windows**.
