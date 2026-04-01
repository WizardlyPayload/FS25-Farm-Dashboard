-- FS25 FarmDashboard | FarmDashboardDataCollector.lua | v2.0.0
-- Collectors run one per time slice across collectionCycleMs (default 60s) so the game
-- is not hit with every module in one frame; data.json is rewritten after each slice.

FarmDashboardDataCollector = {}
FarmDashboardDataCollector.data = {}
FarmDashboardDataCollector.moduleCache = {}
FarmDashboardDataCollector.slotAccumulator = 0

function FarmDashboardDataCollector:init()
    self.collectors = {
        animals    = AnimalDataCollector,
        vehicles   = VehicleDataCollector,
        weather    = WeatherDataCollector,
        fields     = FieldDataCollector,
        finance    = FinanceDataCollector,
        economy    = EconomyDataCollector,
        production = ProductionDataCollector
    }

    for name, collector in pairs(self.collectors) do
        if collector.init then
            collector:init()
        end
    end

    self:loadConfig()
    self:resetStaggerState()
end

function FarmDashboardDataCollector:resetStaggerState()
    self.moduleCache = {}
    self.staggerFirstRunDone = false
    self.nextSliceIdx = 1
    self.slotAccumulator = 0
end

function FarmDashboardDataCollector:loadConfig()
    self.config = {
        interval            = 10000,
        collectionCycleMs   = 60000,
        enableAnimals       = true,
        enableVehicles      = true,
        enableWeather       = true,
        enableFields        = true,
        enableFinance       = true,
        enableEconomy       = true,
        enableProduction    = true,
    }

    local configPath = getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/config.xml"

    if fileExists(configPath) then
        local xmlFile = loadXMLFile("FarmDashboardConfig", configPath)
        if xmlFile ~= 0 then
            self.config.interval = getXMLInt(xmlFile, "farmDashboard.settings#updateInterval") or self.config.interval
            local cycleMs = getXMLInt(xmlFile, "farmDashboard.settings#collectionCycleMs")
            if cycleMs and cycleMs > 0 then
                self.config.collectionCycleMs = cycleMs
            else
                -- Legacy configs: stretch one old tick across ~7 modules → full cycle length
                self.config.collectionCycleMs = math.max(60000, (self.config.interval or 10000) * 7)
            end
            self.config.enableAnimals    = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#animals"),    true)
            self.config.enableVehicles   = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#vehicles"),   true)
            self.config.enableWeather    = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#weather"),    true)
            self.config.enableFields     = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#fields"),     true)
            self.config.enableFinance    = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#finance"),    true)
            self.config.enableEconomy    = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#economy"),    true)
            self.config.enableProduction = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#production"), true)
            delete(xmlFile)
        end
    else
        createFolder(getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/")
        local xmlFile = createXMLFile("FarmDashboardConfig", configPath, "farmDashboard")
        setXMLInt(xmlFile, "farmDashboard.settings#updateInterval", self.config.interval)
        setXMLInt(xmlFile, "farmDashboard.settings#collectionCycleMs", self.config.collectionCycleMs)
        setXMLBool(xmlFile, "farmDashboard.modules#animals",    true)
        setXMLBool(xmlFile, "farmDashboard.modules#vehicles",   true)
        setXMLBool(xmlFile, "farmDashboard.modules#weather",    true)
        setXMLBool(xmlFile, "farmDashboard.modules#fields",     true)
        setXMLBool(xmlFile, "farmDashboard.modules#finance",    true)
        setXMLBool(xmlFile, "farmDashboard.modules#economy",    true)
        setXMLBool(xmlFile, "farmDashboard.modules#production", true)
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end

    self.config.collectionCycleMs = math.max(5000, math.min(1800000, self.config.collectionCycleMs or 60000))
    FarmDashboard.UPDATE_INTERVAL = self.config.collectionCycleMs
end

--- Stable order must match slice spacing (one module per slot over collectionCycleMs).
function FarmDashboardDataCollector:getEnabledCollectorOrder()
    local order = {}
    local seq = {
        { "animals",    "enableAnimals" },
        { "vehicles",   "enableVehicles" },
        { "fields",     "enableFields" },
        { "finance",    "enableFinance" },
        { "weather",    "enableWeather" },
        { "economy",    "enableEconomy" },
        { "production", "enableProduction" }
    }
    for _, row in ipairs(seq) do
        local name, flag = row[1], row[2]
        if self.config[flag] then
            table.insert(order, name)
        end
    end
    return order
end

function FarmDashboardDataCollector:assembleDataFromModuleCache()
    if not _G.g_currentMission then return nil end

    local mc = self.moduleCache
    local data = {
        timestamp  = _G.g_time or 0,
        status     = "active",
        gameTime   = self:getGameTime(),
        farmInfo   = self:getFarmInfo(),
        animals    = mc.animals or {},
        vehicles   = mc.vehicles or {},
        fields     = mc.fields or {},
        production = mc.production or {},
        finance    = mc.finance or {},
        weather    = mc.weather or {},
        economy    = mc.economy or {}
    }

    if data.finance and data.finance.money then
        data.money = data.finance.money
    end

    self.data = data
    return data
end

function FarmDashboardDataCollector:runOneStaggeredSlice(order)
    local n = #order
    if n < 1 then return end

    local idx = self.nextSliceIdx or 1
    if idx > n then idx = 1 end
    local name = order[idx]
    self.nextSliceIdx = (idx % n) + 1

    local result = self:safeCollect(name)
    if name == "production" then
        local prod = result or {}
        prod.husbandryTotals = self:collectHusbandryTotals()
        self.moduleCache.production = prod
    else
        self.moduleCache[name] = result or {}
    end

    local assembled = self:assembleDataFromModuleCache()
    if assembled then
        self:writeDataToFile(assembled)
    end
end

function FarmDashboardDataCollector:update(dt)
    if not dt or type(dt) ~= "number" or dt <= 0 then return end
    if not _G.g_currentMission then return end

    local order = self:getEnabledCollectorOrder()
    local n = #order
    if n < 1 then return end

    local cycleMs = self.config.collectionCycleMs
    local slotMs = cycleMs / n

    if not self.staggerFirstRunDone then
        self.staggerFirstRunDone = true
        self.nextSliceIdx = 1
        self.slotAccumulator = 0
        self:runOneStaggeredSlice(order)
        return
    end

    self.slotAccumulator = (self.slotAccumulator or 0) + dt
    while self.slotAccumulator >= slotMs do
        self.slotAccumulator = self.slotAccumulator - slotMs
        self:runOneStaggeredSlice(order)
    end
end

-- FIX: Aggregate milk/manure/slurry totals across all husbandry buildings.
-- This provides the farm-wide storage numbers that pastures.js needs.
function FarmDashboardDataCollector:collectHusbandryTotals()
    local totals = {}

    if not _G.g_currentMission or not _G.g_currentMission.husbandrySystem then
        return totals
    end

    local success, err = pcall(function()
        for _, placeable in pairs(_G.g_currentMission.husbandrySystem.placeables or {}) do
            if placeable and placeable:getOwnerFarmId() == 1 then
                -- Check fillLevels via multiple spec paths
                local function addFill(specObj)
                    if not specObj then return end
                    local fillLevel = specObj.fillLevel
                    local fillType  = specObj.fillType

                    if fillLevel and type(fillLevel) == "number" and fillLevel > 0 then
                        local typeName = "UNKNOWN"
                        if fillType and _G.g_fillTypeManager then
                            local ftData = _G.g_fillTypeManager:getFillTypeByIndex(fillType)
                            if ftData and ftData.name then
                                typeName = ftData.name
                            end
                        end
                        totals[typeName] = (totals[typeName] or 0) + fillLevel
                    end
                end

                -- Specs that hold liquid/solid outputs
                addFill(placeable.spec_husbandryMilk)
                addFill(placeable.spec_husbandryLiquidManure)
                addFill(placeable.spec_husbandryManure)

                -- Generic fill unit fallback
                if placeable.spec_fillUnit and placeable.spec_fillUnit.fillUnits then
                    for _, unit in pairs(placeable.spec_fillUnit.fillUnits) do
                        if unit.fillType and unit.fillLevel and type(unit.fillLevel) == "number" and unit.fillLevel > 0 then
                            local ftData = _G.g_fillTypeManager and _G.g_fillTypeManager:getFillTypeByIndex(unit.fillType)
                            local typeName = (ftData and ftData.name) or "UNKNOWN"
                            if typeName ~= "UNKNOWN" then
                                totals[typeName] = (totals[typeName] or 0) + unit.fillLevel
                            end
                        end
                    end
                end
            end
        end
    end)

    if not success then
        Logging.warning("[FarmDash] collectHusbandryTotals failed: " .. tostring(err))
    end

    return totals
end

function FarmDashboardDataCollector:safeCollect(collectorName)
    local collector = self.collectors[collectorName]
    if not collector or not collector.collect then return {} end

    local success, result = pcall(function() return collector:collect() end)
    if success then
        return result or {}
    else
        Logging.warning("[FarmDash] Failed to collect " .. tostring(collectorName))
        return {}
    end
end

function FarmDashboardDataCollector:getGameTime()
    if not _G.g_currentMission or not _G.g_currentMission.environment then return {} end
    local env = _G.g_currentMission.environment
    return {
        day          = env.currentDay         or 1,
        dayInPeriod  = env.currentDayInPeriod or 1,
        period       = env.currentPeriod      or 1,
        year         = env.currentYear        or 1,
        hour         = env.currentHour        or 0,
        minute       = env.currentMinute      or 0,
        dayTime      = env.dayTime            or 0,
        timeScale    = (_G.g_currentMission.missionInfo and _G.g_currentMission.missionInfo.timeScale) or 1
    }
end

function FarmDashboardDataCollector:getFarmInfo()
    local farms = {}
    if _G.g_farmManager then
        for _, farm in pairs(_G.g_farmManager.farms) do
            local farmData = {
                id      = farm.farmId,
                farmId  = farm.farmId,
                name    = farm.name   or ("Farm " .. tostring(farm.farmId)),
                color   = farm.color  or 0,
                loan    = farm.loan   or 0,
                money   = farm.money  or 0,
                players = {}
            }
            if farm.players then
                for _, player in pairs(farm.players) do
                    table.insert(farmData.players, {
                        name   = player.nickname or "Unknown",
                        id     = player.userId
                    })
                end
            end
            table.insert(farms, farmData)
        end
    end
    return farms
end

function FarmDashboardDataCollector:getSavegameDirName()
    local savegameDir = "default_save"
    if _G.g_currentMission and _G.g_currentMission.missionInfo then
        local info = _G.g_currentMission.missionInfo
        if info.savegameDirectoryName and info.savegameDirectoryName ~= "" then
            savegameDir = info.savegameDirectoryName
        elseif info.savegameIndex and info.savegameIndex > 0 then
            savegameDir = "savegame" .. tostring(info.savegameIndex)
        end
    end
    return savegameDir
end

--- modSettings/FS25_FarmDashboard/<saveSlot>/ (same folder as data.json)
function FarmDashboardDataCollector:getDataOutputDir()
    local dataPath = getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/" .. self:getSavegameDirName() .. "/"
    createFolder(dataPath)
    return dataPath
end

function FarmDashboardDataCollector:writeDataToFile(data)
    local savegameDir    = self:getSavegameDirName()
    local currentMapName = "Unknown Map"

    if _G.g_currentMission and _G.g_currentMission.missionInfo then
        local info = _G.g_currentMission.missionInfo
        if info.mapTitle and info.mapTitle ~= "" then
            currentMapName = info.mapTitle
        end
    end

    data.serverInfo = { mapName = currentMapName, saveSlot = savegameDir }

    local dataPath = self:getDataOutputDir()

    -- Pretty-print (indented) so data.json is human-readable and tools can open it
    local jsonData = self:toJSON(data, 0)
    if not jsonData or jsonData == "" then return end

    local filePath = dataPath .. "data.json"
    local file = io.open(filePath, "w")
    if file then
        file:write(jsonData)
        file:close()
    end
end

--- @param depth number|nil nil = compact (legacy); 0+ = pretty-print with 2-space indent
function FarmDashboardDataCollector:toJSON(data, depth)
    local compact = (depth == nil)
    local level   = compact and 0 or depth
    local ind     = (not compact) and string.rep("  ", level) or ""
    local ind1    = (not compact) and string.rep("  ", level + 1) or ""
    local nl      = compact and "" or "\n"
    local sp      = compact and "" or " "

    if type(data) == "table" then
        local isArray = true
        local count   = 0
        for k, v in pairs(data) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then
                isArray = false
                break
            end
        end

        if count == 0 then
            if compact then return "{}" end
            return "{" .. nl .. ind .. "}"
        end

        if isArray and count > 0 then
            local result = "[" .. nl
            for i, v in ipairs(data) do
                if i > 1 then result = result .. "," .. nl end
                if not compact then result = result .. ind1 end
                result = result .. self:toJSON(v, compact and nil or (level + 1))
            end
            if not compact then result = result .. nl .. ind end
            return result .. "]"
        else
            local keys = {}
            for k in pairs(data) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)

            local result = "{" .. nl
            local first  = true
            for _, k in ipairs(keys) do
                local v = data[k]
                if not first then result = result .. "," .. nl end
                if not compact then result = result .. ind1 end
                first = false
                local key = tostring(k)
                    :gsub('[\x00-\x1f]', '')
                    :gsub('\\', '\\\\')
                    :gsub('"', '\\"')
                result = result .. '"' .. key .. '":' .. sp .. self:toJSON(v, compact and nil or (level + 1))
            end
            if not compact then result = result .. nl .. ind end
            return result .. "}"
        end
    elseif type(data) == "string" then
        local escaped = data
            :gsub('\\', '\\\\')
            :gsub('"',  '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
            :gsub('[\x00-\x08\x0b\x0c\x0e-\x1f]', '')
        return '"' .. escaped .. '"'
    elseif type(data) == "number" then
        if data ~= data or data == math.huge or data == -math.huge then return "null" end
        return tostring(data)
    elseif type(data) == "boolean" then
        return tostring(data)
    else
        return "null"
    end
end

function FarmDashboardDataCollector:getCurrentData() return self.data end

function FarmDashboardDataCollector:shutdown()
    for name, collector in pairs(self.collectors) do
        if collector.shutdown then collector:shutdown() end
    end
    self:resetStaggerState()
end
