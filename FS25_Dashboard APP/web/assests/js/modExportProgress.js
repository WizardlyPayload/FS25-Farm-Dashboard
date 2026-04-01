// FS25 FarmDashboard | modExportProgress.js | v2.0.0 | live mod shop image export UI (Electron IPC)
(function () {
  const MAX_LOG_LINES = 450;

  function tr(key, fallback) {
    return typeof window.t === "function" ? window.t(key) : fallback;
  }

  function showModal() {
    const el = document.getElementById("modExportProgressModal");
    if (!el) return;
    const useBs =
      el.classList.contains("modal") &&
      typeof bootstrap !== "undefined" &&
      bootstrap.Modal;
    if (useBs) {
      bootstrap.Modal.getOrCreateInstance(el, {
        backdrop: "static",
        keyboard: false,
      }).show();
    } else {
      el.style.display = "flex";
    }
  }

  function hideModal() {
    const el = document.getElementById("modExportProgressModal");
    if (!el) return;
    const useBs =
      el.classList.contains("modal") &&
      typeof bootstrap !== "undefined" &&
      bootstrap.Modal;
    if (useBs) {
      const m = bootstrap.Modal.getInstance(el);
      if (m) m.hide();
    } else {
      el.style.display = "none";
    }
  }

  function resetUi() {
    const bar = document.getElementById("modExportProgressBar");
    const label = document.getElementById("modExportProgressLabel");
    const log = document.getElementById("modExportLog");
    if (bar) {
      bar.style.width = "0%";
      bar.classList.remove("progress-bar-striped", "progress-bar-animated", "fd-indeterminate");
      bar.setAttribute("aria-valuenow", "0");
    }
    if (label) label.textContent = "Starting PowerShell…";
    if (log) log.textContent = "";
  }

  function appendLogLine(logEl, line) {
    if (!logEl) return;
    if (logEl.textContent) logEl.textContent += "\n";
    logEl.textContent += line;
    const lines = logEl.textContent.split("\n");
    if (lines.length > MAX_LOG_LINES) {
      logEl.textContent = lines.slice(-MAX_LOG_LINES).join("\n");
    }
    logEl.scrollTop = logEl.scrollHeight;
  }

  function onProgress(data) {
    if (!data || typeof data !== "object") return;
    const bar = document.getElementById("modExportProgressBar");
    const label = document.getElementById("modExportProgressLabel");
    const log = document.getElementById("modExportLog");

    if (data.type === "init" && label) {
      const t = data.totalSteps || 0;
      const f = data.folderCount ?? 0;
      const z = data.zipCount ?? 0;
      label.textContent =
        "Found " +
        f +
        " mod folder(s) and " +
        z +
        " zip archive(s) — " +
        t +
        " step(s) to process.";
      if (bar) {
        if (t <= 0) {
          bar.style.width = "100%";
          bar.classList.add("progress-bar-striped", "progress-bar-animated", "fd-indeterminate");
        } else {
          bar.style.width = "0%";
          bar.classList.remove("progress-bar-striped", "progress-bar-animated", "fd-indeterminate");
        }
      }
    }
    if (data.type === "step" && label && bar) {
      const cur = data.current || 0;
      const tot = Math.max(1, data.total || 1);
      const pct = Math.min(100, Math.round((100 * cur) / tot));
      bar.style.width = pct + "%";
      bar.setAttribute("aria-valuenow", String(pct));
      bar.classList.remove("progress-bar-striped", "progress-bar-animated", "fd-indeterminate");
      const phase = data.phase === "zip" ? "Zip" : "Folder";
      const name = String(data.label || "").slice(0, 140);
      label.textContent = phase + " " + cur + " / " + tot + (name ? ": " + name : "");
    }
    if (data.type === "log") {
      appendLogLine(log, data.line || "");
    }
    if (data.type === "done" && label) {
      label.textContent = tr("modExport.finishing", "Finishing…");
    }
  }

  /**
   * @param {import('electron').IpcRenderer} ipcRenderer
   * @returns {() => void} cleanup — call when export invoke settles (then/catch/finally)
   */
  window.attachModExportProgress = function (ipcRenderer) {
    resetUi();
    showModal();
    const handler = (_e, payload) => {
      onProgress(payload);
    };
    ipcRenderer.on("export-mod-store-images-progress", handler);
    return function cleanup() {
      ipcRenderer.removeListener("export-mod-store-images-progress", handler);
      hideModal();
    };
  };
})();
