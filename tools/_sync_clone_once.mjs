import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const dstRoot = 'c:/Users/Graham/Documents/FS25-Farm-Dashboard';

const dirPairs = [
  ['FS25_FarmDashboard_App/FS25_FarmDashboard_App/web', path.join(dstRoot, 'FS25_Dashboard APP/web')],
  ['FS25_FarmDashboard_App/FS25_FarmDashboard_App/build', path.join(dstRoot, 'FS25_Dashboard APP/build')],
  ['FS25_FarmDashboard_App/FS25_FarmDashboard_App/resources', path.join(dstRoot, 'FS25_Dashboard APP/resources')],
  ['FS25_FarmDashboard_App/FS25_FarmDashboard_App/tools', path.join(dstRoot, 'FS25_Dashboard APP/tools')],
  ['FS25_FarmDashboard_Mod/FS25_FarmDashboard_Mod', path.join(dstRoot, 'FS25_Dashboard MOD')],
  ['tools', path.join(dstRoot, 'tools')],
  ['docs', path.join(dstRoot, 'docs')],
];

const appFiles = [
  'dataMerger.js',
  'xmlCollector.js',
  'preload.js',
  'package.json',
  'package-lock.json',
  'setup.html',
];
const rootFiles = ['README.md', 'RELEASE_NOTES.md', '.gitignore'];

for (const [rel, dest] of dirPairs) {
  const src = path.join(root, rel);
  if (!fs.existsSync(src)) {
    console.error('MISSING', src);
    process.exitCode = 1;
    continue;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.cpSync(src, dest, { recursive: true });
  console.log('OK dir', rel, '->', dest);
}

const appInner = path.join(root, 'FS25_FarmDashboard_App/FS25_FarmDashboard_App');
for (const name of appFiles) {
  const src = path.join(appInner, name);
  const dest = path.join(dstRoot, 'FS25_Dashboard APP', name);
  if (!fs.existsSync(src)) {
    console.error('MISSING', src);
    process.exitCode = 1;
    continue;
  }
  fs.copyFileSync(src, dest);
  console.log('OK file', name);
}

for (const name of rootFiles) {
  const src = path.join(root, name);
  const dest = path.join(dstRoot, name);
  if (!fs.existsSync(src)) {
    console.error('MISSING', src);
    process.exitCode = 1;
    continue;
  }
  fs.copyFileSync(src, dest);
  console.log('OK root', name);
}

// main.js already synced via editor; ensure copy matches MAIN
const mainSrc = path.join(appInner, 'main.js');
const mainDst = path.join(dstRoot, 'FS25_Dashboard APP/main.js');
if (fs.existsSync(mainSrc)) {
  fs.copyFileSync(mainSrc, mainDst);
  console.log('OK main.js');
}

const obsolete = path.join(dstRoot, 'FS25_Dashboard MOD/src/collectors/VehicleDataCollectorSimple.lua');
if (fs.existsSync(obsolete)) {
  fs.unlinkSync(obsolete);
  console.log('REMOVED', obsolete);
}

console.log('done');
