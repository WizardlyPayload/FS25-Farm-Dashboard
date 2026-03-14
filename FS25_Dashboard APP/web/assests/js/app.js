import * as apiStorage from './modules/apiStorage.js';
import * as parsers from './modules/parsers.js';
import * as navigation from './modules/navigation.js';
import * as notifications from './modules/notifications.js';
import * as changes from './modules/changes.js';
import * as livestock from './modules/livestock.js';
import * as pastures from './modules/pastures.js';
import * as vehicles from './modules/vehicles.js';
import * as economy from './modules/economy.js';
import * as fields from './modules/fields.js';
import * as environment from './modules/environment.js';
import * as theming from './modules/theming.js';

class LivestockDashboard {
  constructor() {
    this.animals = [];
    this.fields = [];
    this.placeables = [];
    this.pastures = [];
    this.playerFarms = [];
    this.notificationHistory = [];
    this.maxNotifications = 10;
    
    // MULTIPLAYER FIX: Set a default active Farm ID
    this.selectedFarmId = 1; 
    
    this.init();
  }

  init() {
    this.setupEventListeners();
    this.setupTabs();
    this.setupURLRouting();
    this.loadNotificationHistory();
    this.checkAPIAvailability();
    this.initTheming();
    
    // Launch the Farm Selector builder
    this.buildFarmSelector();
  }

  // MULTIPLAYER FIX: Dynamically build a dropdown to switch farms
  async buildFarmSelector() {
    try {
        const apiBaseURL = this.getAPIBaseURL ? this.getAPIBaseURL() : "http://127.0.0.1:8766";
        const response = await fetch(`${apiBaseURL}/api/data?t=${new Date().getTime()}`);
        if (!response.ok) return;
        
        const data = await response.json();
        
        // Ensure we have farm data and it's an array
        if (data.farmInfo && Array.isArray(data.farmInfo)) {
            // Filter out the "Unowned" farm (ID 0) and nameless NPC farms
            const activeFarms = data.farmInfo.filter(farm => farm.id > 0 && farm.name && farm.name.trim() !== "");
            this.playerFarms = activeFarms;
            
            this.renderFarmDropdown(activeFarms);
        }
    } catch (error) {
        console.error("[FarmSelector] Error fetching farm data:", error);
    }
  }

  renderFarmDropdown(farms) {
    // Look for the dashboard header to inject the dropdown
    const header = document.querySelector(".dashboard-header") || document.querySelector("header") || document.body;
    
    // Prevent creating multiple dropdowns
    if (document.getElementById("farm-selector-container")) return;

    let optionsHTML = farms.map(farm => 
        `<option value="${farm.id}" ${farm.id === this.selectedFarmId ? 'selected' : ''}>${farm.name} (Farm ${farm.id})</option>`
    ).join('');

    const selectorHTML = `
        <div id="farm-selector-container" style="position: absolute; top: 15px; right: 200px; z-index: 1000;">
            <div class="input-group input-group-sm shadow-sm">
                <span class="input-group-text bg-dark text-white border-secondary"><i class="bi bi-house-door"></i></span>
                <select id="active-farm-select" class="form-select bg-secondary text-white border-secondary">
                    ${optionsHTML}
                </select>
            </div>
        </div>
    `;

    header.insertAdjacentHTML('beforeend', selectorHTML);

    // Add event listener to trigger a refresh when a new farm is selected
    document.getElementById("active-farm-select").addEventListener("change", (e) => {
        this.selectedFarmId = parseInt(e.target.value);
        console.log(`[FarmSelector] Switched active farm to ID: ${this.selectedFarmId}`);
        
        // Force a refresh of the currently active section
        if (this.currentSection === "fields" && this.loadFields) {
            this.loadFields(true);
        } else if (this.currentSection === "vehicles" && this.loadVehicles) {
            this.loadVehicles(); // Assuming you add the same activeFarmId filter to vehicles later!
        }
    });
  }
}

Object.assign(
  LivestockDashboard.prototype,
  apiStorage, parsers, navigation, notifications, 
  changes, livestock, pastures, vehicles, economy, fields, environment, theming
);

let dashboard;
document.addEventListener("DOMContentLoaded", () => {
  dashboard = new LivestockDashboard();
  window.dashboard = dashboard;
});