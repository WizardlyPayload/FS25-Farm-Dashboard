// FS25 FarmDashboard | main.js | v1.0.0
// Electron main: Express + WS on 8766, chokidar/FTP → mergeData → renderer.

const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs   = require('fs');
const os   = require('os');

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
let mainWindow;
let serverStates = {};   // id → { luaData, xmlData, mergedData, watcher, intervals[] }

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
    const srv    = config?.servers?.find(s => s.id === serverId);
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

function startFtpPolling(srv) {
    const state = serverStates[srv.id];
    pollFtp(srv);
    const t = setInterval(() => pollFtp(srv), 15000);
    state.intervals.push(t);
    triggerXmlPoll(srv.id);
    const xmlInterval = setInterval(() => triggerXmlPoll(srv.id), 60000);
    state.intervals.push(xmlInterval);
}

// ── Boot / teardown ───────────────────────────────────────────────────────────

function stopAllWatchers() {
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

    servers.forEach(srv => {
        serverStates[srv.id] = {
            luaData: null, xmlData: null, mergedData: null,
            watcher: null, intervals: [], lastSaveSlot: null
        };
        if (srv.mode === 'local') startLocalWatching(srv);
        else if (srv.mode === 'ftp') startFtpPolling(srv);
    });

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
    store.set('config', newConfig);
    bootServer(newConfig);
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