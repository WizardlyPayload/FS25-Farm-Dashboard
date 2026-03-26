/**
 * Reads FarmDashboard data.json and writes one CSV row per field (Excel-friendly).
 * Usage: node export-fields-to-csv.mjs [path-to-data.json] [output.csv]
 * If omitted, reads: Documents/My Games/FarmingSimulator2025/modSettings/FS25_FarmDashboard/savegame1/data.json
 */

import fs from 'fs';
import path from 'path';
import os from 'os';

const defaultJson = path.join(
    os.homedir(),
    'Documents',
    'My Games',
    'FarmingSimulator2025',
    'modSettings',
    'FS25_FarmDashboard',
    'savegame1',
    'data.json'
);

const inPath = process.argv[2] || defaultJson;
const outPath = process.argv[3] || path.join(process.cwd(), 'fields-from-savegame.csv');

if (!fs.existsSync(inPath)) {
    console.error('File not found:', inPath);
    console.error('Usage: node export-fields-to-csv.mjs [data.json] [out.csv]');
    process.exit(1);
}

const raw = fs.readFileSync(inPath, 'utf8');
const data = JSON.parse(raw);
const fields = Array.isArray(data.fields) ? data.fields : [];

function cell(v) {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
    if (s.includes('"') || s.includes(',') || s.includes('\n') || s.includes('\r')) {
        return `"${s.replace(/"/g, '""')}"`;
    }
    return s;
}

const keySet = new Set();
for (const f of fields) {
    if (f && typeof f === 'object') Object.keys(f).forEach(k => keySet.add(k));
}
const keys = [...keySet].sort((a, b) => {
    const pri = ['id', 'farmlandId', 'name', 'ownerFarmId'];
    const ia = pri.indexOf(a);
    const ib = pri.indexOf(b);
    if (ia >= 0 && ib >= 0) return ia - ib;
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    return a.localeCompare(b);
});

const lines = [keys.map(k => cell(k)).join(',')];
for (const f of fields) {
    lines.push(keys.map(k => cell(f[k])).join(','));
}

fs.writeFileSync(outPath, lines.join('\r\n'), 'utf8');
console.log(`Wrote ${fields.length} fields, ${keys.length} columns -> ${outPath}`);
