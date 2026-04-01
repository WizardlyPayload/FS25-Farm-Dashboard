// FS25 FarmDashboard | main.js | v2.0.0
// Authors: JoshWalki, WizardlyPayload
// Electron main: Express + WS on 8766, chokidar/FTP → mergeData → renderer.

const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs   = require('fs');
const os   = require('os');
const { spawn } = require('child_process');

const express   = require('express');
const http      = require('http');
const WebSocket = require('ws');
const cors      = require('cors');
const chokidar  = require('chokidar');
const ftp       = require('basic-ftp');
const Store     = require('electron-store');

const { collectXmlData, SAVEGAME_XML_FILES } = require('./xmlCollector');
const { mergeData }      = require('./dataMerger');

const store = new Store();

/** PowerShell 5.1 `Set-Content -Encoding utf8` writes UTF-8 BOM; JSON.parse rejects it. */
function stripUtf8Bom(s) {
    if (typeof s !== 'string' || s.length === 0) return s;
    return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s;
}
let mainWindow;
let serverStates = {};   // id → { luaData, xmlData, mergedData, watcher, intervals[] }
/** Timeouts/intervals for coordinated multi-FTP polling (cleared in stopAllWatchers). */
let ftpPollingTimers = [];

/** PowerShell script: repo tools/ or packaged resources/tools/ */
function getModExportScriptPath() {
    if (app.isPackaged) {
        const p = path.join(process.resourcesPath, 'tools', 'Export-ModStoreImages.ps1');
        if (fs.existsSync(p)) return p;
    }
    return path.join(__dirname, '..', '..', 'tools', 'Export-ModStoreImages.ps1');
}

/** Optional bundled DirectXTex texconv (place at resources/texconv/texconv.exe). */
function getBundledTexconvPath() {
    const candidates = [
        path.join(__dirname, 'resources', 'texconv', 'texconv.exe'),
        path.join(process.resourcesPath || '', 'texconv', 'texconv.exe')
    ];
    for (const p of candidates) {
        if (p && fs.existsSync(p)) return p;
    }
    return null;
}

function sendModExportProgress(sender, payload) {
    if (!sender || sender.isDestroyed()) return;
    try {
        sender.send('export-mod-store-images-progress', payload);
    } catch (e) {
        /* ignore */
    }
}

function createPowerShellLineSplitter(onLine) {
    let buf = '';
    return {
        push(chunk) {
            buf += chunk.toString('utf8');
            const parts = buf.split(/\r?\n/);
            buf = parts.pop() || '';
            for (const line of parts) onLine(line);
        },
        flush() {
            if (buf) {
                onLine(buf);
                buf = '';
            }
        }
    };
}

/** Shared by ipcMain.handle and POST /api/export-mod-store-images (fallback when IPC is unavailable). */
async function runExportModStoreImages(progressSender) {
    if (process.platform !== 'win32') {
        const msg = 'Mod image export runs only on Windows (PowerShell + FS mods folder layout).';
        if (mainWindow) {
            await dialog.showMessageBox(mainWindow, { type: 'info', title: 'Mod shop images', message: msg, buttons: ['OK'] });
        }
        return { ok: false, error: msg };
    }

    const scriptPath = getModExportScriptPath();
    if (!fs.existsSync(scriptPath)) {
        const err = `Export script not found:\n${scriptPath}`;
        if (mainWindow) {
            await dialog.showMessageBox(mainWindow, { type: 'error', title: 'Mod shop images', message: err, buttons: ['OK'] });
        }
        return { ok: false, error: err };
    }

    const modsRoot = path.join(os.homedir(), 'Documents', 'My Games', 'FarmingSimulator2025', 'mods');
    const outputDir = path.join(__dirname, 'web', 'assests', 'img', 'items_mod_extract');
    const summaryJson = path.join(app.getPath('temp'), 'farmdash-mod-export-summary.json');
    try {
        if (fs.existsSync(summaryJson)) fs.unlinkSync(summaryJson);
    } catch (e) { /* ignore */ }

    const texconv = getBundledTexconvPath();
    const args = [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath,
        '-ModsRoot', modsRoot,
        '-OutputDir', outputDir,
        '-SummaryJsonPath', summaryJson
    ];
    if (texconv) args.push('-TexconvPath', texconv);

    console.log('[export-mod-store-images] Starting PowerShell:', scriptPath);
    console.log('[export-mod-store-images] ModsRoot:', modsRoot);

    let stderr = '';
    let exitCode = -1;
    /** Avoid hung invoke() if PowerShell never exits (huge mod trees). */
    const MOD_EXPORT_POWERSHELL_MAX_MS = 90 * 60 * 1000;
    const emitStdoutLine = (line) => {
        const t = line.replace(/\r$/, '');
        process.stdout.write(t + '\n');
        const trimmed = t.trim();
        if (!trimmed) return;
        if (trimmed.startsWith('FD_JSON ')) {
            try {
                const obj = JSON.parse(trimmed.slice(8));
                sendModExportProgress(progressSender, obj);
            } catch (parseErr) {
                sendModExportProgress(progressSender, { type: 'log', line: trimmed });
            }
        } else {
            sendModExportProgress(progressSender, { type: 'log', line: trimmed });
        }
    };
    try {
        exitCode = await new Promise((resolve, reject) => {
            const stdoutSplitter = createPowerShellLineSplitter(emitStdoutLine);
            const child = spawn('powershell.exe', args, {
                windowsHide: true,
                cwd: path.dirname(scriptPath)
            });
            child.stdout.on('data', (d) => {
                stdoutSplitter.push(d);
            });
            child.stderr.on('data', (d) => {
                const s = d.toString('utf8');
                stderr += s;
                process.stderr.write(d);
                for (const line of s.split(/\r?\n/)) {
                    const x = line.trim();
                    if (x) sendModExportProgress(progressSender, { type: 'log', line: `[stderr] ${x}` });
                }
            });
            let settled = false;
            const timeoutId = setTimeout(() => {
                if (settled) return;
                settled = true;
                try { child.kill(); } catch (killErr) { /* ignore */ }
                reject(new Error('PowerShell export timed out (90 min). Try a smaller mods folder or run the script manually.'));
            }, MOD_EXPORT_POWERSHELL_MAX_MS);
            child.on('error', (err) => {
                clearTimeout(timeoutId);
                if (settled) return;
                settled = true;
                reject(err);
            });
            child.on('close', (code) => {
                stdoutSplitter.flush();
                clearTimeout(timeoutId);
                if (settled) return;
                settled = true;
                sendModExportProgress(progressSender, { type: 'done', exitCode: code });
                resolve(code);
            });
        });
    } catch (e) {
        const err = e && e.message ? e.message : String(e);
        const timedOut = /timed out/i.test(err);
        if (mainWindow) {
            await dialog.showMessageBox(mainWindow, {
                type: 'error',
                title: 'Mod shop images',
                message: timedOut ? 'Mod image export timed out or was stopped.' : 'Could not start PowerShell.',
                detail: err,
                buttons: ['OK']
            });
        }
        return { ok: false, error: err };
    }

    console.log('[export-mod-store-images] PowerShell exit code:', exitCode);

    let summary = null;
    try {
        if (fs.existsSync(summaryJson)) {
            const raw = stripUtf8Bom(fs.readFileSync(summaryJson, 'utf8'));
            summary = JSON.parse(raw);
        }
    } catch (e) {
        console.warn('[export-mod-store-images] summary parse:', e.message);
    }

    if (!summary) {
        const detail = [
            stderr || '(no stderr)',
            '',
            `PowerShell exit code: ${exitCode}`,
            `Script: ${scriptPath}`
        ].join('\n');
        if (mainWindow) {
            await dialog.showMessageBox(mainWindow, {
                type: 'error',
                title: 'Mod shop images',
                message: 'Export did not produce a summary file.',
                detail,
                buttons: ['OK']
            });
        }
        return { ok: false, error: 'No summary JSON', exitCode, stderr };
    }

    if (summary.ok === false) {
        if (mainWindow) {
            await dialog.showMessageBox(mainWindow, {
                type: 'error',
                title: 'Mod shop images',
                message: summary.error || 'Export failed',
                detail: `Mods folder:\n${summary.modsRoot || modsRoot}`,
                buttons: ['OK']
            });
        }
        return summary;
    }

    const n = summary.textureMatches || 0;
    const png = summary.pngCopied || 0;
    const dds = summary.ddsConverted || 0;
    const skippedExisting = summary.outputsSkippedExisting || 0;
    const skipped = summary.ddsSkippedNoConverter || 0;
    const failed = summary.ddsConvertFailed || 0;

    const detailLines = [
        `New exports this run: ${n}`,
        skippedExisting > 0 ? `Already exported (skipped; run PowerShell with -Force to overwrite): ${skippedExisting}` : null,
        `PNG copied (source was already PNG): ${png}`,
        `DDS converted to PNG: ${dds}`,
        skipped > 0 ? `DDS skipped (install ImageMagick or add texconv.exe to resources/texconv): ${skipped}` : null,
        failed > 0 ? `DDS conversion failed: ${failed}` : null,
        `Top-level mod folders: ${summary.topLevelModFolders ?? '—'}`,
        `Zip archives scanned: ${summary.zipArchivesScanned ?? '—'}`,
        summary.ddsConverter ? `DDS converter used: ${summary.ddsConverter}` : 'DDS converter: none (PNG-only or no DDS matches)',
        '',
        `Output:`,
        summary.outputDir || outputDir
    ].filter((line) => line !== null);

    let msg;
    let boxType = 'info';
    if (n === 0 && skippedExisting === 0) {
        boxType = 'warning';
        msg = 'No matching shop/icon textures were found under your FS25 mods folder.';
    } else if (n === 0 && skippedExisting > 0) {
        msg = `Nothing new to export. ${skippedExisting} texture(s) were already in the output folder (skipped).`;
    } else {
        msg = `Exported ${n} texture(s): ${png} PNG copied, ${dds} DDS converted to PNG.${
            skippedExisting ? ` (${skippedExisting} already up to date.)` : ''
        }`;
    }

    if (mainWindow) {
        await dialog.showMessageBox(mainWindow, {
            type: boxType,
            title: 'Mod shop images',
            message: msg,
            detail: detailLines.join('\n'),
            buttons: ['OK']
        });
    }

    return { ...summary, ok: true };
}

ipcMain.handle('export-mod-store-images', (event) => runExportModStoreImages(event.sender));

// ── Express / WebSocket ───────────────────────────────────────────────────────
const expressApp = express();
const server     = http.createServer(expressApp);
const wss        = new WebSocket.Server({ server });
const PORT       = 8766;
const clients    = new Set();

expressApp.use(cors());
expressApp.use(express.json());
expressApp.use(express.static(path.join(__dirname, 'web')));
expressApp.get('/', (req, res) => res.sendFile(path.join(__dirname, 'web', 'index.html')));
expressApp.get('/setup.html', (req, res) => res.sendFile(path.join(__dirname, 'setup.html')));

expressApp.get('/api/servers', (req, res) => {
    const config = store.get('config');
    if (!config?.servers) return res.json([]);
    res.json(config.servers.map(s => ({ id: s.id, name: s.name, mode: s.mode || 'local' })));
});

function getDataForServer(req) {
    const serverId = req.query.serverId;
    const state = serverId
        ? serverStates[serverId]
        : serverStates[Object.keys(serverStates)[0]];
    return state?.mergedData || null;
}

expressApp.get('/api/data',       (req, res) => {
    const d = getDataForServer(req);
    res.json(d ? { ...d, timestamp: new Date().toISOString() } : { error: 'Waiting for data...' });
});
expressApp.get('/api/animals',    (req, res) => res.json(getDataForServer(req)?.animals    || []));
expressApp.get('/api/vehicles',   (req, res) => res.json(getDataForServer(req)?.vehicles   || []));
expressApp.get('/api/fields',     (req, res) => res.json(getDataForServer(req)?.fields     || []));
expressApp.get('/api/production', (req, res) => res.json(getDataForServer(req)?.production || {}));
expressApp.get('/api/finance',    (req, res) => res.json(getDataForServer(req)?.finance    || {}));
expressApp.get('/api/weather',    (req, res) => res.json(getDataForServer(req)?.weather    || {}));
expressApp.get('/api/economy',    (req, res) => res.json(getDataForServer(req)?.economy    || {}));
expressApp.get('/api/farmlands',  (req, res) => res.json(getDataForServer(req)?.xmlFarmlands || []));
expressApp.get('/api/status',     (req, res) => res.json({ status: 'online' }));

/** Curated PNGs under items/ + exported mod shop PNGs under items_mod_extract/ (for vehicle image matching). */
expressApp.get('/api/item-image-filenames', (req, res) => {
    const itemsDir = path.join(__dirname, 'web', 'assests', 'img', 'items');
    const modDir = path.join(__dirname, 'web', 'assests', 'img', 'items_mod_extract');
    const listPng = (dir) => {
        try {
            return fs.readdirSync(dir).filter((f) => /\.png$/i.test(f));
        } catch (e) {
            return [];
        }
    };
    res.json({ items: listPng(itemsDir), modExtract: listPng(modDir) });
});

/** Fallback when renderer cannot reach ipcMain (e.g. old build) — same logic as IPC handler. */
expressApp.post('/api/export-mod-store-images', async (req, res) => {
    try {
        const result = await runExportModStoreImages();
        res.json(result);
    } catch (e) {
        console.error('[export-mod-store-images] HTTP:', e);
        res.status(500).json({ ok: false, error: e && e.message ? e.message : String(e) });
    }
});

wss.on('connection', ws => {
    clients.add(ws);
    ws.on('close', () => clients.delete(ws));
});

function broadcast(serverId, data) {
    const msg = JSON.stringify({ type: 'data', serverId, data, timestamp: new Date().toISOString() });
    clients.forEach(c => { if (c.readyState === WebSocket.OPEN) c.send(msg); });
}

// ── Data processing ───────────────────────────────────────────────────────────

function rebuildMerged(serverId) {
    const state = serverStates[serverId];
    if (!state) return;
    state.mergedData = mergeData(state.luaData, state.xmlData);
    broadcast(serverId, state.mergedData);
}

function processLuaData(serverId, raw) {
    try {
        const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const state = serverStates[serverId];
        if (!state) return;

        state.luaData = data;

        // If we don't have XML yet (or saveSlot changed), trigger XML poll now
        const saveSlot = data.serverInfo?.saveSlot;
        if (saveSlot && saveSlot !== state.lastSaveSlot) {
            state.lastSaveSlot = saveSlot;
            triggerXmlPoll(serverId);
        }

        rebuildMerged(serverId);

        console.log(`[${new Date().toISOString()}] [${serverId}] Lua data updated`);
    } catch (e) {
        console.error(`[processLuaData] ${serverId}:`, e.message);
    }
}

/** Pull savegame XML from FTP (e.g. GPortal: profile/savegameN/…) into userData/ftpXmlCache. */
async function downloadFtpSavegameXml(srv, saveSlot) {
    const slot = saveSlot || srv.localSubFolder || 'savegame1';
    const localDir = path.join(app.getPath('userData'), 'ftpXmlCache', srv.id, slot);
    fs.mkdirSync(localDir, { recursive: true });

    const remoteDir = srv.ftpSavegameRemoteDir
        ? String(srv.ftpSavegameRemoteDir).replace(/\\/g, '/').replace(/\/$/, '')
        : `${String(srv.ftpBasePath || 'profile').replace(/\\/g, '/').replace(/\/$/, '')}/${slot}`;

    const client = new ftp.Client();
    client.ftp.verbose = false;
    try {
        await client.access({
            host: srv.ftpHost, port: parseInt(srv.ftpPort) || 21,
            user: srv.ftpUser, password: srv.ftpPass, secure: false
        });

        let ok = 0;
        for (const name of SAVEGAME_XML_FILES) {
            const remotePath = `${remoteDir}/${name}`;
            const tmpPath = path.join(localDir, `${name}.tmp`);
            const finalPath = path.join(localDir, name);
            if (await safeDownload(client, remotePath, tmpPath, finalPath)) ok++;
        }
        if (ok > 0) {
            console.log(`[FTP] [${srv.id}] Cached ${ok}/${SAVEGAME_XML_FILES.length} savegame XML -> ${localDir}`);
        } else {
            console.warn(`[FTP] [${srv.id}] No XML files found under ${remoteDir}/`);
        }
        return ok > 0;
    } catch (e) {
        console.warn(`[FTP] [${srv.id}] XML download failed: ${e.message}`);
        return false;
    } finally {
        client.close();
    }
}

async function triggerXmlPoll(serverId) {
    const config = store.get('config');
    const srv    = config?.servers?.find(s => String(s.id) === String(serverId));
    if (!srv) return;

    const state    = serverStates[serverId];
    const saveSlot = state?.lastSaveSlot;
    const effectiveSlot = saveSlot || srv.localSubFolder || 'savegame1';

    try {
        if (srv.mode === 'ftp') {
            await downloadFtpSavegameXml(srv, saveSlot);
        }
        const xmlData = await collectXmlData(srv, saveSlot);
        if (xmlData) {
            serverStates[serverId].xmlData = xmlData;
            rebuildMerged(serverId);
            console.log(`[XML] [${serverId}] XML data updated (slot=${effectiveSlot})`);
        }
    } catch (e) {
        console.warn(`[XML] [${serverId}] XML poll failed:`, e.message);
    }
}

// ── Local file watcher ────────────────────────────────────────────────────────

function startLocalWatching(srv) {
    const state = serverStates[srv.id];

    let basePath = srv.localPath;
    if (!basePath) {
        basePath = path.join(
            os.homedir(),
            'Documents', 'My Games', 'FarmingSimulator2025',
            'modSettings', 'FS25_FarmDashboard'
        );
    }

    const folderName = srv.localSubFolder ||
                       srv.name.replace(/[<>:"/\\|?*]/g, '').trim();
    const luaJsonPath = path.join(basePath, folderName, 'data.json');

    if (!fs.existsSync(luaJsonPath)) {
        console.log(`[Local] Waiting for: ${luaJsonPath}`);
        const t = setTimeout(() => startLocalWatching(srv), 5000);
        state.intervals.push(t);
        return;
    }

    console.log(`[Local] Watching: ${luaJsonPath}`);

    const watcher = chokidar.watch(luaJsonPath, { usePolling: true, interval: 1000 });
    state.watcher = watcher;

    const readFile = () => {
        if (fs.existsSync(luaJsonPath)) processLuaData(srv.id, fs.readFileSync(luaJsonPath, 'utf8'));
    };

    watcher.on('add',    readFile);
    watcher.on('change', readFile);

    // XML poll immediately then every 60s (XML changes on save, not every 10s)
    triggerXmlPoll(srv.id);
    const xmlInterval = setInterval(() => triggerXmlPoll(srv.id), 60000);
    state.intervals.push(xmlInterval);
}

// ── FTP polling ───────────────────────────────────────────────────────────────

async function safeDownload(client, remotePath, localTmp, localFinal) {
    try {
        await client.downloadTo(localTmp, remotePath);
        if (fs.existsSync(localTmp) && fs.statSync(localTmp).size > 0) {
            if (fs.existsSync(localFinal)) fs.unlinkSync(localFinal);
            fs.renameSync(localTmp, localFinal);
            return true;
        }
    } catch (e) {}
    return false;
}

async function pollFtp(srv) {
    const client = new ftp.Client();
    client.ftp.verbose = false;
    const userDataPath = app.getPath('userData');
    try {
        await client.access({
            host: srv.ftpHost, port: parseInt(srv.ftpPort) || 21,
            user: srv.ftpUser, password: srv.ftpPass, secure: false
        });

        const basePath   = srv.ftpBasePath || 'profile';
        const folderName = srv.localSubFolder || 'savegame1';
        const remotePath = `${basePath}/modSettings/FS25_FarmDashboard/${folderName}/data.json`;

        const tmpPath   = path.join(userDataPath, `data_${srv.id}.json.tmp`);
        const finalPath = path.join(userDataPath, `data_${srv.id}.json`);

        if (await safeDownload(client, remotePath, tmpPath, finalPath)) {
            processLuaData(srv.id, fs.readFileSync(finalPath, 'utf8'));
        }
    } catch (err) {
        console.warn(`[FTP] ${srv.name}: ${err.message}`);
    } finally {
        client.close();
    }
}

function getFtpPollingOptions(config) {
    const fp = config.ftpPolling || {};
    const minutes = Math.min(25, Math.max(1, parseInt(fp.intervalMinutes, 10) || 5));
    const delaySec = Math.min(600, Math.max(0, parseInt(fp.initialDelaySeconds, 10) || 0));
    const scheduleMode = fp.scheduleMode === 'staggered' ? 'staggered' : 'sync';
    return {
        intervalMinutes: minutes,
        initialDelaySeconds: delaySec,
        scheduleMode,
        intervalMs: minutes * 60 * 1000
    };
}

function clearFtpPollingTimers() {
    for (const t of ftpPollingTimers) {
        clearTimeout(t);
        clearInterval(t);
    }
    ftpPollingTimers = [];
}

/**
 * FTP data.json + XML refresh schedule (global for all FTP servers).
 * sync: every interval, poll all servers in parallel.
 * staggered: one server per sub-interval, evenly spaced so each server repeats every full interval.
 */
function startFtpPollingCoordinator(config, ftpServers) {
    if (!ftpServers.length) return;

    clearFtpPollingTimers();

    const opts = getFtpPollingOptions(config);
    const { intervalMs, initialDelaySeconds, scheduleMode } = opts;
    const initialDelayMs = initialDelaySeconds * 1000;
    const N = ftpServers.length;

    console.log(
        `[FTP] Schedule: ${scheduleMode} | every ${opts.intervalMinutes} min | ` +
        `delay ${initialDelaySeconds}s | ${N} server(s)`
    );

    const runLuaThenXml = (srv) =>
        pollFtp(srv)
            .then(() => triggerXmlPoll(srv.id))
            .catch((e) => console.warn(`[FTP] ${srv.name}:`, e.message));

    const pushTimer = (id) => { ftpPollingTimers.push(id); };

    if (scheduleMode === 'sync') {
        const tick = () => {
            Promise.all(ftpServers.map((srv) => runLuaThenXml(srv))).catch((e) =>
                console.warn('[FTP] sync batch:', e.message)
            );
        };
        const startId = setTimeout(() => {
            tick();
            pushTimer(setInterval(tick, intervalMs));
        }, initialDelayMs);
        pushTimer(startId);
        return;
    }

    // staggered: equal slots across one full interval
    const slotMs = Math.max(1, Math.floor(intervalMs / N));
    let idx = 0;
    const staggerTick = () => {
        runLuaThenXml(ftpServers[idx % N]);
        idx++;
    };
    const startId = setTimeout(() => {
        staggerTick();
        pushTimer(setInterval(staggerTick, slotMs));
    }, initialDelayMs);
    pushTimer(startId);
}

// ── Boot / teardown ───────────────────────────────────────────────────────────

function stopAllWatchers() {
    clearFtpPollingTimers();
    for (const state of Object.values(serverStates)) {
        if (state.watcher) state.watcher.close();
        for (const t of (state.intervals || [])) { clearTimeout(t); clearInterval(t); }
    }
    serverStates = {};
}

function bootServer(config) {
    stopAllWatchers();

    const servers = config.servers || (config.mode ? [{
        id: 'srv_legacy', name: 'My Server', ...config
    }] : []);

    const ftpServers = servers.filter(s => s.mode === 'ftp');

    servers.forEach(srv => {
        serverStates[srv.id] = {
            luaData: null, xmlData: null, mergedData: null,
            watcher: null, intervals: [], lastSaveSlot: null
        };
        if (srv.mode === 'local') startLocalWatching(srv);
    });

    startFtpPollingCoordinator(config, ftpServers);

    if (!server.listening) {
        server.listen(PORT, '0.0.0.0', () => {
            console.log(`Server listening on http://0.0.0.0:${PORT}`);
            if (mainWindow) mainWindow.loadURL(`http://localhost:${PORT}`);
        });
    } else {
        if (mainWindow) mainWindow.loadURL(`http://localhost:${PORT}`);
    }
}

// ── Electron window ───────────────────────────────────────────────────────────

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1400, height: 900,
        title: 'FS25 Farm Dashboard',
        autoHideMenuBar: true,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: false
        }
    });

    const config = store.get('config');
    if (config?.isConfigured) bootServer(config);
    else mainWindow.loadFile(path.join(__dirname, 'setup.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { stopAllWatchers(); if (process.platform !== 'darwin') app.quit(); });

// ── IPC ───────────────────────────────────────────────────────────────────────

ipcMain.on('save-settings', (event, newConfig) => {
    const prev = store.get('config') || {};
    const merged = {
        ...prev,
        ...newConfig,
        servers: newConfig.servers
    };
    if (newConfig.ftpPolling) {
        merged.ftpPolling = { ...(prev.ftpPolling || {}), ...newConfig.ftpPolling };
    }
    store.set('config', merged);
    bootServer(merged);
});

ipcMain.handle('get-current-config', () => store.get('config'));

ipcMain.on('reset-settings', () => {
    store.delete('config');
    app.relaunch();
    app.exit();
});

ipcMain.on('open-setup', () => {
    if (mainWindow) mainWindow.loadFile(path.join(__dirname, 'setup.html'));
});

ipcMain.handle('scan-local-saves', async () => {
    const userHome = os.homedir();
    const basePath = path.join(
        userHome, 'Documents', 'My Games', 'FarmingSimulator2025',
        'modSettings', 'FS25_FarmDashboard'
    );
    if (!fs.existsSync(basePath)) return [];

    const foundSaves = [];
    const folders = fs.readdirSync(basePath, { withFileTypes: true });

    for (const dirent of folders) {
        if (!dirent.isDirectory()) continue;
        const jsonPath = path.join(basePath, dirent.name, 'data.json');
        if (!fs.existsSync(jsonPath)) continue;
        try {
            const parsed  = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
            const mapName = parsed.serverInfo?.mapName || 'Unknown Map';
            foundSaves.push({
                id: 'srv_' + Date.now() + Math.floor(Math.random() * 1000),
                name: `${mapName} (${dirent.name})`,
                mode: 'local',
                localPath: basePath,
                localSubFolder: dirent.name
            });
        } catch (e) {
            console.warn(`[scan-local-saves] Error parsing ${dirent.name}:`, e.message);
        }
    }
    return foundSaves;
});