-- FS25 FarmDashboard | FarmDashboard.lua | v1.0.0

FarmDashboard = {}
FarmDashboard.MOD_NAME = "FS25_FarmDashboard"
FarmDashboard.MOD_DIR = _G.g_currentModDirectory
FarmDashboard.VERSION = "1.0.0.0"
FarmDashboard.UPDATE_INTERVAL = 10000
FarmDashboard.PORT = 8766
FarmDashboard.readyAt = nil

local hasLoaded = false

function FarmDashboard:loadMap()
    if hasLoaded then return end
    hasLoaded = true

    -- Source all collector scripts (paths relative to mod root)
    source(FarmDashboard.MOD_DIR .. "src/FarmDashboardDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/AnimalDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/VehicleDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/FieldDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/ProductionDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/FinanceDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/WeatherDataCollector.lua")
    source(FarmDashboard.MOD_DIR .. "src/collectors/EconomyDataCollector.lua")

    FarmDashboardDataCollector:init()

    if _G.g_server ~= nil then
        _G.g_currentMission:addUpdateable(FarmDashboard)
        FarmDashboard.isRegistered = true
        local currentTime = _G.g_time or 0
        FarmDashboard.readyAt = (type(currentTime) == "number") and (currentTime + 2000) or 2000
    end

    FarmDashboard:startDashboard()
end

function FarmDashboard:onStartMission()
    if _G.g_server ~= nil and not self.isRegistered then
        if _G.g_currentMission then
            _G.g_currentMission:addUpdateable(FarmDashboard)
            self.isRegistered = true
            local currentTime = _G.g_time or 0
            FarmDashboard.readyAt = (type(currentTime) == "number") and (currentTime + 2000) or 2000
        end
    end
end

function FarmDashboard:deleteMap()
    if _G.g_currentMission and self.isRegistered then
        _G.g_currentMission:removeUpdateable(FarmDashboard)
        self.isRegistered = false
    end
    if FarmDashboardDataCollector then
        FarmDashboardDataCollector:shutdown()
    end
end

function FarmDashboard:update(dt)
    if not _G.g_currentMission then return end
    if _G.g_server == nil then return end
    if not FarmDashboard.readyAt or not _G.g_time then return end
    if type(_G.g_time) ~= "number" or type(FarmDashboard.readyAt) ~= "number" then return end
    if _G.g_time < FarmDashboard.readyAt then return end

    local success, err = pcall(function()
        if FarmDashboardDataCollector and dt and type(dt) == "number" then
            FarmDashboardDataCollector:update(dt)
        end
    end)

    if not success and err then
        Logging.error("[FarmDash] Update error: %s", tostring(err))
    end
end

function FarmDashboard:startDashboard()
end

addModEventListener(FarmDashboard)
