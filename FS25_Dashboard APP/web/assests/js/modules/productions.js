// FS25 FarmDashboard | productions.js | v2.0.0
// Production chains: fill levels + active slots for the active farm.

function escapeHtml(s) {
  if (s == null || s === "") return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Normalize Lua/JSON chains to an array */
export function normalizeProductionChains(production) {
  if (!production) return [];
  const c = production.chains;
  if (Array.isArray(c)) return c;
  if (c && typeof c === "object") return Object.values(c);
  return [];
}

export function getOwnedChainsForFarm(production, farmId) {
  const all = normalizeProductionChains(production);
  if (all.length === 0) return [];

  let fid = Number(farmId);
  if (!Number.isFinite(fid) || fid <= 0) fid = 1;

  // Strict: only chains whose ownerFarmId matches the selected farm (no fallback to “all map” chains).
  return all.filter((ch) => Number(ch.ownerFarmId) === fid);
}

export function getOwnedProductionChainCount() {
  return getOwnedChainsForFarm(this.production, this.activeFarmId ?? 1).length;
}

/** Format storage level: FS often uses liters; some buffers use 0–1 fill ratio */
function formatFillAmount(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  if (n >= 0 && n <= 1.0001) return `${(n * 100).toFixed(0)}%`;
  if (Math.abs(n) >= 1000)
    return `${n.toLocaleString(undefined, { maximumFractionDigits: 0 })} L`;
  return `${n.toLocaleString(undefined, { maximumFractionDigits: 1 })} L`;
}

function fillRowsFromMap(map) {
  if (!map || typeof map !== "object") return "";
  const keys = Object.keys(map).sort((a, b) => a.localeCompare(b));
  if (keys.length === 0)
    return '<tr><td colspan="2" class="text-muted small">No data</td></tr>';
  return keys
    .map(
      (k) =>
        `<tr><td>${escapeHtml(k)}</td><td class="text-end font-monospace">${formatFillAmount(map[k])}</td></tr>`
    )
    .join("");
}

function recipeRows(inputs, outputs) {
  const ins = Array.isArray(inputs) ? inputs : [];
  const outs = Array.isArray(outputs) ? outputs : [];
  const lines = [];
  ins.forEach((row) => {
    lines.push(
      `<tr><td><span class="badge bg-secondary">In</span></td><td>${escapeHtml(row.fillType || "?")}</td><td class="text-end small text-muted">${row.recipeAmount != null ? row.recipeAmount : "—"} / cycle</td></tr>`
    );
  });
  outs.forEach((row) => {
    lines.push(
      `<tr><td><span class="badge bg-farm-accent text-dark">Out</span></td><td>${escapeHtml(row.fillType || "?")}</td><td class="text-end small text-muted">${row.recipeAmount != null ? row.recipeAmount : "—"} / cycle</td></tr>`
    );
  });
  if (lines.length === 0)
    return '<tr><td colspan="3" class="text-muted small">No recipe rows</td></tr>';
  return lines.join("");
}

function buildChainCard(chain) {
  const name = escapeHtml(chain.name || "Production");
  const cid = escapeHtml(String(chain.id ?? ""));
  const farmId = Number(chain.ownerFarmId);
  const chainActive = chain.isActive === true;
  const inMap = chain.inputFillLevels || {};
  const outMap = chain.outputFillLevels || {};
  const prods = Array.isArray(chain.productions) ? chain.productions : [];

  const prodBlocks = prods
    .map((p, idx) => {
      const active = p.isActive === true;
      const st = escapeHtml(String(p.status || "—"));
      const pname = escapeHtml(p.name || `Slot ${idx + 1}`);
      const cph =
        p.cyclesPerHour != null && Number(p.cyclesPerHour) > 0
          ? `<span class="small text-muted ms-2">${Number(p.cyclesPerHour).toFixed(2)} / h</span>`
          : "";
      return `
        <div class="border border-secondary rounded p-2 mb-2 bg-dark">
          <div class="d-flex justify-content-between align-items-center flex-wrap gap-1">
            <strong class="text-farm-accent">${pname}</strong>
            <span>
              ${active ? '<span class="badge bg-success">Active</span>' : '<span class="badge bg-secondary">Inactive</span>'}
              <span class="badge bg-outline-light border border-secondary text-light">${st}</span>
              ${cph}
            </span>
          </div>
          <table class="table table-sm table-dark mb-0 mt-2 small">
            <thead><tr><th style="width:8rem"></th><th>Fill type</th><th class="text-end">Recipe</th></tr></thead>
            <tbody>${recipeRows(p.inputs, p.outputs)}</tbody>
          </table>
        </div>`;
    })
    .join("");

  return `
    <div class="card bg-secondary border-farm-accent mb-4 shadow-sm">
      <div class="card-header d-flex justify-content-between align-items-center flex-wrap gap-2">
        <div>
          <h5 class="mb-0 text-farm-accent"><i class="bi bi-building-gear me-2"></i>${name}</h5>
          <small class="text-muted">ID ${cid} · Farm ${farmId}</small>
        </div>
        <div>
          ${chainActive ? '<span class="badge bg-success">Chain running</span>' : '<span class="badge bg-secondary">Chain stopped</span>'}
        </div>
      </div>
      <div class="card-body">
        <div class="row g-3">
          <div class="col-md-6">
            <h6 class="text-muted mb-2"><i class="bi bi-box-arrow-in-down me-1"></i>Input storage</h6>
            <table class="table table-sm table-dark mb-0">
              <thead><tr><th>Fill type</th><th class="text-end">Level</th></tr></thead>
              <tbody>${fillRowsFromMap(inMap)}</tbody>
            </table>
          </div>
          <div class="col-md-6">
            <h6 class="text-muted mb-2"><i class="bi bi-box-arrow-up me-1"></i>Output storage</h6>
            <table class="table table-sm table-dark mb-0">
              <thead><tr><th>Fill type</th><th class="text-end">Level</th></tr></thead>
              <tbody>${fillRowsFromMap(outMap)}</tbody>
            </table>
          </div>
        </div>
        <h6 class="text-muted mt-4 mb-2"><i class="bi bi-diagram-3 me-1"></i>Production slots</h6>
        ${prodBlocks || '<p class="text-muted small mb-0">No per-slot data from the game.</p>'}
      </div>
    </div>`;
}

export function buildProductionsPageHTML(dashboard) {
  const farmId = dashboard.activeFarmId ?? 1;
  const chains = getOwnedChainsForFarm(dashboard.production, farmId);

  if (chains.length === 0) {
    return `
      <div class="row mb-4">
        <div class="col-12 text-center">
          <h2 class="text-farm-accent"><i class="bi bi-building-gear me-2"></i>Productions</h2>
          <p class="lead text-muted">No production chains reported for your farm yet, or the mod has not written fresh data.</p>
          <p class="text-muted small">Ensure the Farm Dashboard mod is active and production points exist on the map.</p>
        </div>
      </div>`;
  }

  const cards = chains.map((c) => buildChainCard(c)).join("");
  return `
    <div class="row mb-3">
      <div class="col-12 text-center">
        <h2 class="text-farm-accent"><i class="bi bi-building-gear me-2"></i>Productions</h2>
        <p class="text-muted mb-0">${chains.length} chain${chains.length === 1 ? "" : "s"} · Farm ${farmId}</p>
      </div>
    </div>
    <div class="row">
      <div class="col-12">${cards}</div>
    </div>`;
}

export function showProductionsSection() {
  this.currentSection = "productions";
  const el = document.getElementById("section-content");
  if (el) {
    el.innerHTML = buildProductionsPageHTML(this);
    el.classList.remove("d-none");
  }
  document.getElementById("landing-page")?.classList.add("d-none");
  document.getElementById("dashboard-content")?.classList.add("d-none");
  this.updateNavbar();
}

/** Call after realtime production JSON updates */
export function refreshProductionsIfVisible() {
  if (this.currentSection !== "productions") return;
  const el = document.getElementById("section-content");
  if (el) el.innerHTML = buildProductionsPageHTML(this);
}
