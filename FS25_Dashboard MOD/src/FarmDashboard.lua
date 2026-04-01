-- FS25 FarmDashboard | FarmDashboard.lua | v2.0.0
-- Authors: JoshWalki, WizardlyPayload

FarmDashboard = {}
FarmDashboard.MOD_NAME = "FS25_FarmDashboard"
FarmDashboard.MOD_DIR = _G.g_currentModDirectory
FarmDashboard.VERSION = "2.0.0.0"
FarmDashboard.UPDATE_INTERVAL = 10000
FarmDashboard.PORT = 8766
FarmDashboard.readyAt = nil

local hasLoaded = false

--- Collectors and data.json must run in single-player (often no g_server) and on MP host/dedicated — not on MP clients.
function FarmDashboard:isAuthority()
    if not _G.g_currentMission then return false end
    if _G.g_server ~= nil then
        if type(_G.g_server.getIsServer) == "function" then
            local ok, isSrv = pcall(function() return _G.g_server:getIsServer() end)
            if ok then return isSrv end
        end
        return true
    end
    if _G.g_connectionManager ~= nil and type(_G.g_connectionManager.getIsClient) == "function" then
        local ok, isCl = pcall(function() return _G.g_connectionManager:getIsClient() end)
        if ok and isCl then return false end
    end
    return true
end

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

    if self:isAuthority() then
        _G.g_currentMission:addUpdateable(FarmDashboard)
        FarmDashboard.isRegistered = true
        local currentTime = _G.g_time or 0
        FarmDashboard.readyAt = (type(currentTime) == "number") and (currentTime + 2000) or 2000
    end

    FarmDashboard:startDashboard()
end

function FarmDashboard:onStartMission()
    if self:isAuthority() and not self.isRegistered then
        if _G.g_currentMission then
            _G.g_currentMission:addUpdateable(FarmDashboard)
            self.isRegistered = true
            local currentTime = _G.g_time or 0
            FarmDashboard.readyAt = (type(currentTime) == "number") and (currentTime + 2000) or 2000
        end
    end
    if FarmDashboardDataCollector and FarmDashboardDataCollector.resetStaggerState then
        FarmDashboardDataCollector:resetStaggerState()
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
    if not self:isAuthority() then return end
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
