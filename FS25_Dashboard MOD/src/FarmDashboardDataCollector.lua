FarmDashboardDataCollector = {}
FarmDashboardDataCollector.updateTimer = 0
FarmDashboardDataCollector.data = {}

function FarmDashboardDataCollector:init()
    self.collectors = {
        animals = AnimalDataCollector,
        vehicles = VehicleDataCollector,
        weather = WeatherDataCollector,
        fields = FieldDataCollector,
        finance = FinanceDataCollector,
        economy = EconomyDataCollector
    }

    for name, collector in pairs(self.collectors) do
        if collector.init then
            collector:init()
        end
    end

    self:loadConfig()
end

function FarmDashboardDataCollector:loadConfig()
    self.config = {
        interval = 10000,
        enableAnimals = true,
        enableVehicles = true,
        enableWeather = true,
        enableFields = true,
        enableFinance = true,
        enableEconomy = true
    }

    local configPath = getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/config.xml"
    
    if fileExists(configPath) then
        local xmlFile = loadXMLFile("FarmDashboardConfig", configPath)
        if xmlFile ~= 0 then
            self.config.interval = getXMLInt(xmlFile, "farmDashboard.settings#updateInterval") or self.config.interval
            self.config.enableAnimals = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#animals"), true)
            self.config.enableVehicles = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#vehicles"), true)
            self.config.enableWeather = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#weather"), true)
            self.config.enableFields = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#fields"), true)
            self.config.enableFinance = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#finance"), true)
            self.config.enableEconomy = Utils.getNoNil(getXMLBool(xmlFile, "farmDashboard.modules#economy"), true)
            delete(xmlFile)
        end
    else
        createFolder(getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/")
        local xmlFile = createXMLFile("FarmDashboardConfig", configPath, "farmDashboard")
        
        setXMLInt(xmlFile, "farmDashboard.settings#updateInterval", self.config.interval)
        setXMLBool(xmlFile, "farmDashboard.modules#animals", true)
        setXMLBool(xmlFile, "farmDashboard.modules#vehicles", true)
        setXMLBool(xmlFile, "farmDashboard.modules#weather", true)
        setXMLBool(xmlFile, "farmDashboard.modules#fields", true)
        setXMLBool(xmlFile, "farmDashboard.modules#finance", true)
        setXMLBool(xmlFile, "farmDashboard.modules#economy", true)
        
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
    
    FarmDashboard.UPDATE_INTERVAL = self.config.interval
end

function FarmDashboardDataCollector:update(dt)
    if not dt or type(dt) ~= "number" or dt <= 0 then return end
    if not _G.g_currentMission then return end

    self.updateTimer = (self.updateTimer or 0) + dt
    
    if self.updateTimer >= FarmDashboard.UPDATE_INTERVAL then
        self.updateTimer = 0
        
        local collected = self:collectAllData()
        if collected then
            self:writeDataToFile(collected)
        end
    end
end

function FarmDashboardDataCollector:collectAllData()
    if not _G.g_currentMission then return nil end

    local data = {
        timestamp = _G.g_time or 0,
        status = "active",
        money = _G.g_currentMission:getMoney() or 0,
        gameTime = self:getGameTime(),
        farmInfo = self:getFarmInfo(),
        animals = {},
        vehicles = {},
        fields = {},
        production = {},
        finance = {},
        weather = {},
        economy = {}
    }

    if self.config.enableAnimals then data.animals = self:safeCollect("animals") end
    if self.config.enableVehicles then data.vehicles = self:safeCollect("vehicles") end
    if self.config.enableFields then data.fields = self:safeCollect("fields") end
    if self.config.enableFinance then data.finance = self:safeCollect("finance") end
    if self.config.enableWeather then data.weather = self:safeCollect("weather") end
    if self.config.enableEconomy then data.economy = self:safeCollect("economy") end

    self.data = data
    return data
end

function FarmDashboardDataCollector:safeCollect(collectorName)
    local collector = self.collectors[collectorName]
    if not collector or not collector.collect then return {} end

    local success, result = pcall(function() return collector:collect() end)
    if success then
        return result or {}
    else
        print("[FarmDash] Failed to collect " .. tostring(collectorName) .. " data")
        return {}
    end
end

function FarmDashboardDataCollector:getGameTime()
    if not _G.g_currentMission or not _G.g_currentMission.environment then return {} end
    local env = _G.g_currentMission.environment
    return {
        day = env.currentDay or 1, dayInPeriod = env.currentDayInPeriod or 1,
        period = env.currentPeriod or 1, year = env.currentYear or 1,
        hour = env.currentHour or 0, minute = env.currentMinute or 0,
        dayTime = env.dayTime or 0, timeScale = _G.g_currentMission.missionInfo.timeScale or 1
    }
end

function FarmDashboardDataCollector:getFarmInfo()
    local farms = {}
    if _G.g_farmManager then
        for _, farm in pairs(_G.g_farmManager.farms) do
            local farmData = {
                id = farm.farmId, name = farm.name, color = farm.color,
                loan = farm.loan or 0, money = farm.money or 0, players = {}
            }
            if farm.players then
                for _, player in pairs(farm.players) do
                    table.insert(farmData.players, { name = player.nickname or "Unknown", id = player.userId })
                end
            end
            table.insert(farms, farmData)
        end
    end
    return farms
end

function FarmDashboardDataCollector:writeDataToFile(data)
    local savegameDir = "default_save"
    local currentMapName = "Unknown Map"

    if _G.g_currentMission and _G.g_currentMission.missionInfo then
        local info = _G.g_currentMission.missionInfo
        if info.savegameDirectoryName and info.savegameDirectoryName ~= "" then
            savegameDir = info.savegameDirectoryName
        elseif info.savegameIndex and info.savegameIndex > 0 then
            savegameDir = "savegame" .. tostring(info.savegameIndex)
        end
        if info.mapTitle and info.mapTitle ~= "" then
            currentMapName = info.mapTitle
        end
    end

    data.serverInfo = { mapName = currentMapName, saveSlot = savegameDir }

    local dataPath = getUserProfileAppPath() .. "modSettings/FS25_FarmDashboard/" .. savegameDir .. "/"
    createFolder(dataPath)

    local jsonData = self:toJSON(data)
    if not jsonData or jsonData == "" then return end

    local filePath = dataPath .. "data.json"
    local file, err = io.open(filePath, "w")
    if file then
        file:write(jsonData)
        file:close()
        
        local farmDataPath = dataPath .. "farmdata.json"
        local farmFile = io.open(farmDataPath, "w")
        if farmFile then
            farmFile:write(jsonData)
            farmFile:close()
        end
    end
end

function FarmDashboardDataCollector:toJSON(data)
    if type(data) == "table" then
        local isArray = true
        local count = 0
        for k, v in pairs(data) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then
                isArray = false
                break
            end
        end

        if isArray and count > 0 then
            local result = "["
            for i, v in ipairs(data) do
                if i > 1 then result = result .. "," end
                result = result .. self:toJSON(v)
            end
            return result .. "]"
        else
            local result = "{"
            local first = true
            for k, v in pairs(data) do
                if not first then result = result .. "," end
                local key = tostring(k):gsub('[\x00-\x1f]', ''):gsub('\\', '\\\\'):gsub('"', '\\"')
                result = result .. '"' .. key .. '":' .. self:toJSON(v)
                first = false
            end
            return result .. "}"
        end
    elseif type(data) == "string" then
        local escaped = data:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'):gsub('[\x00-\x08\x0b\x0c\x0e-\x1f]', '')
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
end