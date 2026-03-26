-- FS25 FarmDashboard | ProductionDataCollector.lua | v1.2.0
-- 1) ProductionChainManager:getProductionPointsForFarmId / getFactoriesForFarmId
-- 2) Placeable scan (REQUIRED on many builds): PlaceableProductionPoint.lua has
--    addProductionPoint() commented out — points may never register on the manager.
--    Game UI iterates placeableSystem.placeables + spec_productionPoint (see onBuy).

ProductionDataCollector = {}

function ProductionDataCollector:init()
    self.lastCollectTime = 0
    self.collectInterval = 1000
end

function ProductionDataCollector:collect()
    if not _G.g_currentMission then
        return { chains = {} }
    end

    local currentTime = _G.g_time or 0
    if type(currentTime) == "number" and type(self.lastCollectTime) == "number" and type(self.collectInterval) == "number"
        and currentTime - self.lastCollectTime < self.collectInterval then
        return self.lastProductionData or { chains = {} }
    end
    self.lastCollectTime = currentTime

    local result = { chains = {} }
    local seenPP = {}
    local seenFactoryPlaceable = {}

    local AH = rawget(_G, "AccessHandler")
    local everyone = (AH and AH.EVERYONE) or 0

    local pcm = _G.g_currentMission.productionChainManager

    local function notePP(pp)
        if pp then seenPP[pp] = true end
    end

    local function noteFactory(placeable)
        if placeable then seenFactoryPlaceable[placeable] = true end
    end

    if pcm then
        local function addFarmProductions(farmId)
            if not farmId or farmId == everyone then return end

            local points = pcm.getProductionPointsForFarmId and pcm:getProductionPointsForFarmId(farmId) or {}
            for _, pp in ipairs(points) do
                notePP(pp)
                local pData = self:collectProductionPointData(pp, farmId)
                if pData then
                    pData.source = "chainManager"
                    table.insert(result.chains, pData)
                end
            end

            local factories = pcm.getFactoriesForFarmId and pcm:getFactoriesForFarmId(farmId) or {}
            for _, placeable in ipairs(factories) do
                noteFactory(placeable)
                local pData = self:collectFactoryPlaceable(placeable, farmId)
                if pData then
                    pData.source = "chainManager"
                    table.insert(result.chains, pData)
                end
            end
        end

        if _G.g_farmManager and _G.g_farmManager.farms then
            for _, farm in pairs(_G.g_farmManager.farms) do
                if farm and farm.farmId then
                    addFarmProductions(farm.farmId)
                end
            end
        else
            if pcm.productionPoints then
                for _, pp in ipairs(pcm.productionPoints) do
                    local ok, fid = pcall(function() return pp:getOwnerFarmId() end)
                    if ok and fid and fid ~= everyone then
                        notePP(pp)
                        local pData = self:collectProductionPointData(pp, fid)
                        if pData then
                            pData.source = "chainManager"
                            table.insert(result.chains, pData)
                        end
                    end
                end
            end
            if pcm.factories then
                for _, placeable in ipairs(pcm.factories) do
                    local ok, fid = pcall(function() return placeable:getOwnerFarmId() end)
                    if ok and fid and fid ~= everyone then
                        noteFactory(placeable)
                        local pData = self:collectFactoryPlaceable(placeable, fid)
                        if pData then
                            pData.source = "chainManager"
                            table.insert(result.chains, pData)
                        end
                    end
                end
            end
        end
    end

    -- Always merge placeables: production points often exist only here (manager add commented in base game).
    self:mergePlaceableProductions(result, seenPP, seenFactoryPlaceable, everyone)

    self.lastProductionData = result
    return result
end

--- Enumerate g_currentMission.placeableSystem.placeables (official pattern: PlaceableProductionPoint:onBuy).
function ProductionDataCollector:mergePlaceableProductions(result, seenPP, seenFactoryPlaceable, everyone)
    local ps = _G.g_currentMission.placeableSystem
    if not ps or not ps.placeables then
        return
    end

    for _, placeable in ipairs(ps.placeables) do
        if placeable and placeable.spec_productionPoint and placeable.spec_productionPoint.productionPoint then
            local pp = placeable.spec_productionPoint.productionPoint
            if not seenPP[pp] then
                local ok, fid = pcall(function() return placeable:getOwnerFarmId() end)
                if ok and fid and fid ~= everyone then
                    seenPP[pp] = true
                    local pData = self:collectProductionPointData(pp, fid)
                    if pData then
                        pData.source = "placeable"
                        if placeable.storeName then
                            pData.placeableStoreName = placeable.storeName
                        end
                        table.insert(result.chains, pData)
                    end
                end
            end
        elseif placeable and placeable.spec_factory and not seenFactoryPlaceable[placeable] then
            local ok, fid = pcall(function() return placeable:getOwnerFarmId() end)
            if ok and fid and fid ~= everyone then
                seenFactoryPlaceable[placeable] = true
                local pData = self:collectFactoryPlaceable(placeable, fid)
                if pData then
                    pData.source = "placeable"
                    table.insert(result.chains, pData)
                end
            end
        end
    end
end

function ProductionDataCollector:boolVal(val, obj, method)
    if type(val) == "boolean" then return val end
    if obj and type(obj[method]) == "function" then
        local ok, r = pcall(function() return obj[method](obj) end)
        if ok and type(r) == "boolean" then return r end
    end
    return false
end

--- Split storage fill levels into input / output using ProductionPoint type maps when available.
function ProductionDataCollector:fillLevelsFromStorage(pp, data)
    if not pp or not pp.storage or not pp.storage.getFillLevels then return end
    local levels = pp.storage:getFillLevels()
    if not levels then return end

    for fillTypeIndex, level in pairs(levels) do
        if type(fillTypeIndex) == "number" and type(level) == "number" then
            local ftName = _G.g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex) or "unknown"
            local isIn = pp.inputFillTypeIds and pp.inputFillTypeIds[fillTypeIndex]
            local isOut = pp.outputFillTypeIds and pp.outputFillTypeIds[fillTypeIndex]
            if isIn then
                data.inputFillLevels[ftName] = level
            elseif isOut then
                data.outputFillLevels[ftName] = level
            else
                data.inputFillLevels[ftName] = level
            end
        end
    end
end

function ProductionDataCollector:productionSlotIsActive(pp, production)
    if production.isEnabled ~= nil then
        return production.isEnabled == true
    end
    if pp.activeProductions then
        for _, ap in ipairs(pp.activeProductions) do
            if ap.id == production.id then
                return true
            end
        end
    end
    return false
end

function ProductionDataCollector:productionSlotStatus(pp, production)
    local ok, st = pcall(function()
        if pp.productionsIdToObj and production.id and pp.productionsIdToObj[production.id] then
            local po = pp.productionsIdToObj[production.id]
            if po and po.status ~= nil then return tostring(po.status) end
        end
        return nil
    end)
    if ok and st then return st end
    if production.status ~= nil then
        return tostring(production.status)
    end
    return "unknown"
end

function ProductionDataCollector:collectProductionPointData(pp, farmId)
    if not pp then return nil end

    local name = "Production"
    if pp.getName then
        local ok, n = pcall(function() return pp:getName() end)
        if ok and n and tostring(n) ~= "" then name = tostring(n) end
    end

    local pid = pp.id or 0
    if type(pid) ~= "number" and type(pid) ~= "string" then
        pid = tostring(pid or "pp")
    end

    local data = {
        id = pid,
        name = name,
        ownerFarmId = farmId,
        isActive = (pp.activeProductions and #pp.activeProductions > 0) or false,
        productions = {},
        inputFillLevels = {},
        outputFillLevels = {},
        position = self:getPositionFromObject(pp),
        source = "productionPoint",
    }

    self:fillLevelsFromStorage(pp, data)

    if pp.productions then
        for _, production in pairs(pp.productions) do
            local cph, cpm = 0, 0
            if type(production.cyclesPerHour) == "function" then
                local ok, v = pcall(function() return production:cyclesPerHour() end)
                if ok and type(v) == "number" then cph = v end
            elseif type(production.cyclesPerHour) == "number" then
                cph = production.cyclesPerHour
            end
            if type(production.cyclesPerMonth) == "function" then
                local ok, v = pcall(function() return production:cyclesPerMonth() end)
                if ok and type(v) == "number" then cpm = v end
            elseif type(production.cyclesPerMonth) == "number" then
                cpm = production.cyclesPerMonth
            end
            local prodData = {
                id = production.id or "unknown",
                name = production.name or "Unknown",
                isActive = self:productionSlotIsActive(pp, production),
                status = self:productionSlotStatus(pp, production),
                cyclesPerHour = cph,
                cyclesPerMonth = cpm,
                inputs = {},
                outputs = {},
            }
            if production.inputs then
                for _, input in pairs(production.inputs) do
                    table.insert(prodData.inputs, {
                        fillType = _G.g_fillTypeManager:getFillTypeNameByIndex(input.type) or "unknown",
                        recipeAmount = input.amount or 0,
                    })
                end
            end
            if production.outputs then
                for _, output in pairs(production.outputs) do
                    table.insert(prodData.outputs, {
                        fillType = _G.g_fillTypeManager:getFillTypeNameByIndex(output.type) or "unknown",
                        recipeAmount = output.amount or 0,
                    })
                end
            end
            table.insert(data.productions, prodData)
        end
    end

    return data
end

function ProductionDataCollector:collectFactoryPlaceable(placeable, farmId)
    if not placeable or not placeable.spec_factory then return nil end
    local spec = placeable.spec_factory

    local name = "Factory"
    if placeable.getName then
        local ok, n = pcall(function() return placeable:getName() end)
        if ok and n and tostring(n) ~= "" then name = tostring(n) end
    end

    local fid = placeable.id or placeable.rootNode or 0
    local data = {
        id = "factory_" .. tostring(fid),
        name = name,
        ownerFarmId = farmId,
        isActive = (spec.progress ~= nil and spec.progress > 0) or (spec.hasInputMaterials == true),
        productions = {},
        inputFillLevels = {},
        outputFillLevels = {},
        position = self:getPositionFromObject(placeable),
        source = "factory",
    }

    if spec.storage and spec.storage.getFillLevels then
        local levels = spec.storage:getFillLevels()
        if levels then
            for fillTypeIndex, level in pairs(levels) do
                if type(fillTypeIndex) == "number" and type(level) == "number" then
                    local ftName = _G.g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex) or "unknown"
                    if placeable.inputFillTypeIdsArray then
                        local isIn = false
                        for _, idx in ipairs(placeable.inputFillTypeIdsArray) do
                            if idx == fillTypeIndex then isIn = true break end
                        end
                        if isIn then
                            data.inputFillLevels[ftName] = level
                        else
                            data.outputFillLevels[ftName] = level
                        end
                    else
                        data.inputFillLevels[ftName] = level
                    end
                end
            end
        end
    end

    if placeable.productions then
        for _, production in pairs(placeable.productions) do
            local prodData = {
                id = production.primaryProductFillType and tostring(production.primaryProductFillType) or "factory",
                name = production.name or "Production",
                isActive = spec.isSoundPlaying == true or (spec.progress or 0) > 0,
                status = tostring(spec.progress or 0),
                cyclesPerHour = 0,
                cyclesPerMonth = production.cyclesPerMonth or 0,
                inputs = {},
                outputs = {},
            }
            if production.inputs then
                for _, input in pairs(production.inputs) do
                    local ft = _G.g_fillTypeManager:getFillTypeByIndex(input.type)
                    table.insert(prodData.inputs, {
                        fillType = (ft and ft.name) or "unknown",
                        recipeAmount = input.amount or 0,
                    })
                end
            end
            if production.outputs then
                for _, output in pairs(production.outputs) do
                    local ft = _G.g_fillTypeManager:getFillTypeByIndex(output.type)
                    table.insert(prodData.outputs, {
                        fillType = (ft and ft.name) or "unknown",
                        recipeAmount = output.amount or 0,
                    })
                end
            end
            table.insert(data.productions, prodData)
        end
    end

    return data
end

function ProductionDataCollector:getPositionFromObject(obj)
    if obj and obj.rootNode then
        local success, x, y, z = pcall(getWorldTranslation, obj.rootNode)
        if success and x and y and z then
            return { x = x, y = y, z = z }
        end
    end
    return { x = 0, y = 0, z = 0 }
end
