/**
 * Fetch text sources from WizardlyPayload/FS25-Farm-Dashboard (main) and write into this workspace.
 * Same files as on GitHub — open any path in the browser, e.g.:
 *   https://raw.githubusercontent.com/WizardlyPayload/FS25-Farm-Dashboard/main/FS25_Dashboard%20APP/web/assests/js/app.js
 * Syncs main.js + setup.html + app + mod Lua. Skips binaries, release/, node_modules.
 *
 * Run from repo root: node tools/sync-upstream-wizardlypayload.mjs
 * Or double-click: tools/sync-from-github.bat
 *
 * If raw.githubusercontent.com mangles regex-heavy files, fetch the GitHub Contents API JSON for
 * that path and decode: node tools/decode-github-api-file.mjs <api.json> <outfile>
 */
import https from "https";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = path.join(__dirname, "..");

function resolveAppDir(ws) {
  const main = path.join(ws, "FS25_FarmDashboard_App", "FS25_FarmDashboard_App");
  const git = path.join(ws, "FS25_Dashboard APP");
  if (fs.existsSync(main)) return main;
  if (fs.existsSync(git)) return git;
  throw new Error("App folder not found (expected MAIN or FS25_Dashboard APP layout).");
}
function resolveModDir(ws) {
  const main = path.join(ws, "FS25_FarmDashboard_Mod", "FS25_FarmDashboard_Mod");
  const git = path.join(ws, "FS25_Dashboard MOD");
  if (fs.existsSync(main)) return main;
  if (fs.existsSync(git)) return git;
  throw new Error("Mod folder not found (expected MAIN or FS25_Dashboard MOD layout).");
}
const APP = resolveAppDir(WORKSPACE);
const MOD = resolveModDir(WORKSPACE);

const BASE =
  "https://raw.githubusercontent.com/WizardlyPayload/FS25-Farm-Dashboard/main/";

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          return fetchText(res.headers.location).then(resolve).catch(reject);
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} ${url}`));
          return;
        }
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () =>
          resolve(Buffer.concat(chunks).toString("utf8"))
        );
      })
      .on("error", reject);
  });
}

/** [ remotePathFromRepoRoot, localAbsolutePath ] */
const FILES = [
  // App root (upstream folder: FS25_Dashboard APP/)
  ["FS25_Dashboard APP/dataMerger.js", path.join(APP, "dataMerger.js")],
  ["FS25_Dashboard APP/main.js", path.join(APP, "main.js")],
  ["FS25_Dashboard APP/setup.html", path.join(APP, "setup.html")],
  ["FS25_Dashboard APP/preload.js", path.join(APP, "preload.js")],
  ["FS25_Dashboard APP/package.json", path.join(APP, "package.json")],
  ["FS25_Dashboard APP/package-lock.json", path.join(APP, "package-lock.json")],
  ["FS25_Dashboard APP/xmlCollector.js", path.join(APP, "xmlCollector.js")],
  // Web
  ["FS25_Dashboard APP/web/index.html", path.join(APP, "web", "index.html")],
  [
    "FS25_Dashboard APP/web/assests/css/styles.css",
    path.join(APP, "web", "assests", "css", "styles.css"),
  ],
  ["FS25_Dashboard APP/web/assests/js/app.js", path.join(APP, "web", "assests", "js", "app.js")],
  [
    "FS25_Dashboard APP/web/assests/js/realtime-connector.js",
    path.join(APP, "web", "assests", "js", "realtime-connector.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/apiStorage.js",
    path.join(APP, "web", "assests", "js", "modules", "apiStorage.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/changes.js",
    path.join(APP, "web", "assests", "js", "modules", "changes.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/economy.js",
    path.join(APP, "web", "assests", "js", "modules", "economy.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/environment.js",
    path.join(APP, "web", "assests", "js", "modules", "environment.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/fields.js",
    path.join(APP, "web", "assests", "js", "modules", "fields.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/livestock.js",
    path.join(APP, "web", "assests", "js", "modules", "livestock.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/navigation.js",
    path.join(APP, "web", "assests", "js", "modules", "navigation.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/notifications.js",
    path.join(APP, "web", "assests", "js", "modules", "notifications.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/parsers.js",
    path.join(APP, "web", "assests", "js", "modules", "parsers.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/pastures.js",
    path.join(APP, "web", "assests", "js", "modules", "pastures.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/productions.js",
    path.join(APP, "web", "assests", "js", "modules", "productions.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/theming.js",
    path.join(APP, "web", "assests", "js", "modules", "theming.js"),
  ],
  [
    "FS25_Dashboard APP/web/assests/js/modules/vehicles.js",
    path.join(APP, "web", "assests", "js", "modules", "vehicles.js"),
  ],
  // Tools inside app folder
  [
    "FS25_Dashboard APP/tools/export-fields-to-csv.bat",
    path.join(APP, "tools", "export-fields-to-csv.bat"),
  ],
  [
    "FS25_Dashboard APP/tools/export-fields-to-csv.mjs",
    path.join(APP, "tools", "export-fields-to-csv.mjs"),
  ],
  // Mod (FS25_Dashboard MOD/ → FS25_FarmDashboard_Mod/FS25_FarmDashboard_Mod/)
  ["FS25_Dashboard MOD/modDesc.xml", path.join(MOD, "modDesc.xml")],
  [
    "FS25_Dashboard MOD/src/FarmDashboard.lua",
    path.join(MOD, "src", "FarmDashboard.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/FarmDashboardDataCollector.lua",
    path.join(MOD, "src", "FarmDashboardDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/AnimalDataCollector.lua",
    path.join(MOD, "src", "collectors", "AnimalDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/EconomyDataCollector.lua",
    path.join(MOD, "src", "collectors", "EconomyDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/FieldDataCollector.lua",
    path.join(MOD, "src", "collectors", "FieldDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/FieldDataCollectordatadump.lua",
    path.join(MOD, "src", "collectors", "FieldDataCollectordatadump.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/FinanceDataCollector.lua",
    path.join(MOD, "src", "collectors", "FinanceDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/ProductionDataCollector.lua",
    path.join(MOD, "src", "collectors", "ProductionDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/VehicleDataCollector.lua",
    path.join(MOD, "src", "collectors", "VehicleDataCollector.lua"),
  ],
  [
    "FS25_Dashboard MOD/src/collectors/WeatherDataCollector.lua",
    path.join(MOD, "src", "collectors", "WeatherDataCollector.lua"),
  ],
];

async function main() {
  let ok = 0;
  let fail = 0;
  for (const [remote, dest] of FILES) {
    const url = BASE + encodeURI(remote);
    try {
      const text = await fetchText(url);
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, text, "utf8");
      console.log("OK", remote);
      ok++;
    } catch (e) {
      console.error("FAIL", remote, e.message);
      fail++;
    }
  }
  console.log(`\nDone: ${ok} written, ${fail} failed.`);
  if (fail) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
