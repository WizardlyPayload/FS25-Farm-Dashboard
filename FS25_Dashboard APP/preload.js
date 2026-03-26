// FS25 FarmDashboard | preload.js | v1.0.1
// Not referenced by main.js BrowserWindow (setup uses nodeIntegration). Kept for optional future isolation.

/**
 * preload.js
 * Runs in a privileged context before the renderer.
 * Exposes ONLY the specific Electron IPC calls the UI needs.
 * This lets contextIsolation stay ON, which fixes the input focus bug.
 */
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Setup screen
  getCurrentConfig:  ()       => ipcRenderer.invoke('get-current-config'),
  saveSettings:      (config) => ipcRenderer.send('save-settings', config),
  scanLocalSaves:    ()       => ipcRenderer.invoke('scan-local-saves'),
  openSetup:         ()       => ipcRenderer.send('open-setup'),
  resetSettings:     ()       => ipcRenderer.send('reset-settings'),
});
