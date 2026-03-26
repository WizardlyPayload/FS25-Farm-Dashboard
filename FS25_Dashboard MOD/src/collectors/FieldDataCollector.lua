-- FS25 FarmDashboard | FieldDataCollector.lua | v1.0.12

FieldDataCollector = {}

function FieldDataCollector:init()
    print("[FarmDashboard] Field data collector initialized (Hybrid: NPC State + Physical HUD Probe)")
end

function FieldDataCollector:collect()
    local fieldData = {}
    
    if not _G.g_currentMission then return fieldData end
    if not _G.g_fieldManager or not _G.g_fieldManager.fields then return fieldData end

    -- ====================================================================
    -- PRECISION FARMING DETECTION
    -- ====================================================================
    local isPF = false
    local pfInstance = nil
    if _G.FS25_precisionFarming and _G.FS25_precisionFarming.g_precisionFarming then 
        isPF = true 
        pfInstance = _G.FS25_precisionFarming.g_precisionFarming
    elseif _G.g_precisionFarming then 
        isPF = true 
        pfInstance = _G.g_precisionFarming
    end
    
    local currentFarmId = 1
    if _G.g_currentMission.getFarmId then
        currentFarmId = _G.g_currentMission:getFarmId()
    elseif _G.g_currentMission.player and _G.g_currentMission.player.farmId then
        currentFarmId = _G.g_currentMission.player.farmId
    end
    
    local function callMethod(instance, methodName, ...)
        if not instance then return nil end
        if type(instance[methodName]) == "function" then
            local ok, res = pcall(instance[methodName], instance, ...)
            if ok and res ~= nil then return res end
        end
        return nil
    end

    --- Weed: engine may return 0–1 (fraction) or 0–4 (discrete stages). Do not treat 4 as 400%.
    local function weedPercentForDisplay(w)
        w = w or 0
        if w < 0 then w = 0 end
        if w <= 1 then
            return math.floor(w * 100)
        end
        if w <= 4 then
            return math.min(100, math.floor((w / 4) * 100))
        end
        return math.min(100, math.floor(w))
    end

    -- Create the NPC FieldState object (Used ONLY for unowned fields)
    local probeState = nil
    if _G.FieldState and _G.FieldState.new then
        local ok, fs = pcall(function() return _G.FieldState.new() end)
        if ok then probeState = fs end
    end
    
    for fieldId, field in pairs(_G.g_fieldManager.fields) do
        
        local ownerFarmId = field.farmland and field.farmland.farmId or 0
        local isOwned = (ownerFarmId > 0 and ownerFarmId == currentFarmId)
        local displayId = fieldId
        
        if field.farmland and field.farmland.id and field.farmland.id > 0 then
            displayId = field.farmland.id
        end
        
        local fData = {
            id                    = fieldId,
            name                  = string.format("Field %d", displayId),
            hectares              = field.areaHa or 0,
            fieldAreaInSqm        = (field.areaHa or 0) * 10000,
            isOwned               = isOwned,
            ownerFarmId           = ownerFarmId,
            farmlandId            = displayId,
            posX                  = field.posX or 0,
            posZ                  = field.posZ or 0,
            fruitType             = "unknown",
            fruitTypeIndex        = 0,
            growthState           = 0,
            maxGrowthState        = 0,
            growthStatePercentage = 0,
            harvestReady          = false,
            isWithered            = false,
            isHarvested           = false,
            stateName             = "Empty",
            growthLabel           = "empty",
            fertilizationLevel    = 0,
            plowLevel             = 0,
            limeLevel             = 0,
            weedLevel             = 0,
            mulchLevel            = 0,
            rollerLevel           = 0,
            stubbleLevel          = 0,
            sprayLevel            = 0,
            stoneLevel            = 0,
            groundType            = 0,
            isPrecisionFarming    = isPF,
            nitrogenLevel         = 0,
            targetNitrogen        = 0,
            phValue               = 0,
            targetPh              = 0,
            isScanned             = false,
            nitrogenText          = "",
            limeText              = "",
            needsWork             = false,
            needsPlowing          = false,
            needsLime             = false,
            needsFertilizer       = false,
            needsWeeding          = false,
            suggestions           = {}
        }

        -- Get True Center Coordinates
        local cx = fData.posX
        local cz = fData.posZ
        if field.getCenterOfFieldWorldPosition then
            local ok, x, z = pcall(function() return field:getCenterOfFieldWorldPosition() end)
            if ok and x and z then cx, cz = x, z end
        end

        -- ====================================================================
        -- 1. THE HYBRID PROBE 
        -- ====================================================================
        if not isOwned then
            -- [UNOWNED FIELDS]: Use the NPC Contract Planner (Saves CPU, highly accurate for AI)
            if probeState and type(probeState.update) == "function" then
                local foundCrop = false
                local offsets = { {0,0}, {5,5}, {-5,-5}, {5,-5}, {-5,5} }
                for _, off in ipairs(offsets) do
                    pcall(function() probeState:update(cx + off[1], cz + off[2]) end)
                    if probeState.fruitTypeIndex and probeState.fruitTypeIndex > 0 then
                        fData.fruitTypeIndex     = probeState.fruitTypeIndex
                        fData.growthState        = probeState.growthState or 0
                        fData.fertilizationLevel = probeState.sprayLevel or 0
                        fData.plowLevel          = probeState.plowLevel or 0
                        fData.limeLevel          = probeState.limeLevel or 0
                        fData.weedLevel          = probeState.weedState or 0
                        fData.mulchLevel         = probeState.stubbleShredLevel or 0
                        fData.groundType         = probeState.groundType or 0
                        foundCrop = true
                        break
                    end
                end
                if not foundCrop then
                    pcall(function() probeState:update(cx, cz) end)
                    fData.fertilizationLevel = probeState.sprayLevel or 0
                    fData.plowLevel          = probeState.plowLevel or 0
                    fData.limeLevel          = probeState.limeLevel or 0
                    fData.weedLevel          = probeState.weedState or 0
                    fData.mulchLevel         = probeState.stubbleShredLevel or 0
                    fData.groundType         = probeState.groundType or 0
                end
            end
        else
            -- [OWNED FIELDS]: Use the same FieldState world sampling as unowned/NPC fields.
            -- HUD (fieldInfoSystem.getFieldInfoAtWorldPosition) + getFruitTypeIndexAtWorldPos(2-arg)
            -- were giving stale data for player farmland; FieldState:update matches FieldManager / map.
            local offsets = { {0,0}, {5,5}, {-5,-5}, {5,-5}, {-5,5}, {10,0}, {-10,0}, {0,10}, {0,-10} }
            local foundCrop = false

            if probeState and type(probeState.update) == "function" then
                for _, off in ipairs(offsets) do
                    pcall(function() probeState:update(cx + off[1], cz + off[2]) end)
                    if probeState.fruitTypeIndex and probeState.fruitTypeIndex > 0 then
                        fData.fruitTypeIndex     = probeState.fruitTypeIndex
                        fData.growthState        = probeState.growthState or 0
                        fData.fertilizationLevel = probeState.sprayLevel or 0
                        fData.plowLevel          = probeState.plowLevel or 0
                        fData.limeLevel          = probeState.limeLevel or 0
                        fData.weedLevel          = probeState.weedState or 0
                        fData.mulchLevel         = probeState.stubbleShredLevel or 0
                        fData.groundType         = probeState.groundType or 0
                        foundCrop = true
                        break
                    end
                end
                if not foundCrop then
                    pcall(function() probeState:update(cx, cz) end)
                    fData.fertilizationLevel = probeState.sprayLevel or 0
                    fData.plowLevel          = probeState.plowLevel or 0
                    fData.limeLevel          = probeState.limeLevel or 0
                    fData.weedLevel          = probeState.weedState or 0
                    fData.mulchLevel         = probeState.stubbleShredLevel or 0
                    fData.groundType         = probeState.groundType or 0
                end
            end

            -- Per-field FieldState (engine-owned) as a second opinion when probeState missed crop
            if field.fieldState and type(field.fieldState.update) == "function" then
                pcall(function() field.fieldState:update(cx, cz) end)
                local fs = field.fieldState
                if (not foundCrop or (fData.fruitTypeIndex or 0) == 0) and fs.fruitTypeIndex and fs.fruitTypeIndex > 0 then
                    fData.fruitTypeIndex     = fs.fruitTypeIndex
                    fData.growthState        = fs.growthState or 0
                    fData.fertilizationLevel = fs.sprayLevel or 0
                    fData.plowLevel          = fs.plowLevel or 0
                    fData.limeLevel          = fs.limeLevel or 0
                    fData.weedLevel          = fs.weedState or 0
                    fData.mulchLevel         = fs.stubbleShredLevel or 0
                    fData.groundType         = fs.groundType or 0
                    foundCrop = true
                elseif not foundCrop then
                    fData.fertilizationLevel = fs.sprayLevel or fData.fertilizationLevel
                    fData.plowLevel          = fs.plowLevel or fData.plowLevel
                    fData.limeLevel          = fs.limeLevel or fData.limeLevel
                    fData.weedLevel          = fs.weedState or fData.weedLevel
                    fData.mulchLevel         = fs.stubbleShredLevel or fData.mulchLevel
                    fData.groundType         = fs.groundType or fData.groundType
                end
            end
        end

        -- 1b. No crop on probe: center read often misses mulched stubble — max stubble across offsets on this farmland
        local mulchBefore1b = fData.mulchLevel or 0
        if (fData.fruitTypeIndex or 0) == 0 then
            local soilOffsets = {
                {0, 0}, {5, 5}, {-5, -5}, {5, -5}, {-5, 5},
                {10, 0}, {-10, 0}, {0, 10}, {0, -10},
                {20, 0}, {-20, 0}, {0, 20}, {0, -20},
                {15, 15}, {-15, -15}
            }
            local myFarmlandId = field.farmland and field.farmland.id or nil
            local function sampleOnThisFarmland(sx, sz)
                if not myFarmlandId or not _G.g_farmlandManager or not _G.g_farmlandManager.getFarmlandAtWorldPosition then
                    return true
                end
                local ok, fm = pcall(function()
                    return _G.g_farmlandManager:getFarmlandAtWorldPosition(sx, sz)
                end)
                if not ok or not fm then return false end
                return fm.id == myFarmlandId
            end
            local maxMulch = mulchBefore1b
            if probeState and type(probeState.update) == "function" then
                for _, off in ipairs(soilOffsets) do
                    local sx, sz = cx + off[1], cz + off[2]
                    if sampleOnThisFarmland(sx, sz) then
                        pcall(function() probeState:update(sx, sz) end)
                        local m = probeState.stubbleShredLevel or 0
                        if m > maxMulch then maxMulch = m end
                    end
                end
            end
            if field.fieldState and type(field.fieldState.update) == "function" then
                for _, off in ipairs(soilOffsets) do
                    local sx, sz = cx + off[1], cz + off[2]
                    if sampleOnThisFarmland(sx, sz) then
                        pcall(function() field.fieldState:update(sx, sz) end)
                        local fs = field.fieldState
                        local m = fs and fs.stubbleShredLevel or 0
                        if m > maxMulch then maxMulch = m end
                    end
                end
            end
            fData.mulchLevel = maxMulch
        end

        -- Engine GroundType Cache Override for Visual Dirt
        local gType = fData.groundType
        if gType == 3 or gType == 4 then
            if fData.growthState == 0 then fData.growthState = 1 end
            fData.harvestReady = false
        elseif gType == 1 or gType == 2 then
            fData.growthState  = 0
            fData.harvestReady = false
        end

        -- ====================================================================
        -- 2. CROP CLASSIFICATION & HARVEST MATH
        -- ====================================================================
        if fData.fruitTypeIndex > 0 and _G.g_fruitTypeManager then
            local ftDesc = _G.g_fruitTypeManager:getFruitTypeByIndex(fData.fruitTypeIndex)
            if ftDesc then
                fData.fruitType      = ftDesc.name or "unknown"
                fData.maxGrowthState = ftDesc.numGrowthStates or 0
                -- Grass: FS25 field UI uses 4 growth stages; engine numGrowthStates can be 8
                local ftUpper = string.upper(tostring(fData.fruitType or ""))
                if ftUpper == "GRASS" and fData.maxGrowthState > 4 then
                    fData.maxGrowthState = 4
                end
                local gs             = fData.growthState
                local gsName         = ftDesc.growthStateToName and ftDesc.growthStateToName[gs]
                
                local minHarvest = ftDesc.minHarvestingGrowthState or fData.maxGrowthState
                local maxHarvest = ftDesc.maxHarvestingGrowthState or fData.maxGrowthState
                local maxStateToShow = minHarvest
                if ftDesc.yieldScales and ftDesc.yieldScales[minHarvest] ~= nil and ftDesc.yieldScales[minHarvest] ~= 1 then
                    maxStateToShow = maxHarvest
                end

                -- Grass is perennial: do not use arable "withered" / over-max rules (regrowth confuses them).
                local isWitheredState = (gsName == "withered" or (ftDesc.maxHarvestingGrowthState and gs > ftDesc.maxHarvestingGrowthState))
                if ftUpper ~= "GRASS" and isWitheredState then
                    fData.isWithered   = true
                    fData.growthLabel  = "withered"
                    fData.stateName    = "Withered"
                    fData.harvestReady = false
                elseif gsName == "harvested" then
                    fData.isHarvested  = true
                    fData.growthLabel  = "harvested"
                    fData.stateName    = "Harvested"
                elseif gsName == "harvestReady" or (ftDesc.minHarvestingGrowthState and gs >= ftDesc.minHarvestingGrowthState and gs <= maxHarvest) then
                    fData.harvestReady = true
                    fData.growthLabel  = "harvest_ready"
                    fData.stateName    = "Ready"
                elseif gs > 0 then
                    fData.growthLabel  = "growing"
                    fData.stateName    = "Growing"
                else
                    fData.growthLabel  = "empty"
                    fData.stateName    = "Empty"
                end
                
                if maxStateToShow > 0 then
                    fData.growthStatePercentage = math.min(100, math.floor((fData.growthState / maxStateToShow) * 100))
                    if fData.harvestReady then fData.growthStatePercentage = 100 end
                end
            end
        end

        -- ====================================================================
        -- 3. PRECISION FARMING RADIUS SCANNER
        -- ====================================================================
        local nLevel, nTarget, phLevel, phTarget = 0, 0, 0, 0
        local isScanned = false

        if isPF and pfInstance then
            local baseRadius = math.sqrt(fData.fieldAreaInSqm / math.pi)
            local sampleOffsets = {
                {0, 0}, {0.25, 0}, {-0.25, 0}, {0, 0.25}, {0, -0.25},
                {0.5, 0.5}, {-0.5, -0.5}, {0.5, -0.5}, {-0.5, 0.5},
                {0.6, 0}, {-0.6, 0}, {0, 0.6}, {0, -0.6}
            }
            local sumN, sumNTarget, validN = 0, 0, 0
            local sumPh, sumPhTarget, validPh = 0, 0, 0

            -- Ignore sample points that fall on a neighbour field (offsets can cross the boundary).
            local myFarmlandId = field.farmland and field.farmland.id or nil
            local function sampleOnThisFarmland(sx, sz)
                if not myFarmlandId or not _G.g_farmlandManager or not _G.g_farmlandManager.getFarmlandAtWorldPosition then
                    return true
                end
                local ok, fm = pcall(function()
                    return _G.g_farmlandManager:getFarmlandAtWorldPosition(sx, sz)
                end)
                if not ok or not fm then return false end
                return fm.id == myFarmlandId
            end

            for _, offset in ipairs(sampleOffsets) do
                local sX = cx + (offset[1] * baseRadius)
                local sZ = cz + (offset[2] * baseRadius)
                if not sampleOnThisFarmland(sX, sZ) then
                    -- skip points outside this field's farmland (prevents Field 4 inheriting Field 3 PF)
                else
                local soilType = callMethod(pfInstance.soilMap, "getTypeIndexAtWorldPos", sX, sZ)
                
                if soilType and type(soilType) == "number" and soilType > 0 then
                    isScanned = true
                    local ptN = callMethod(pfInstance.nitrogenMap, "getLevelAtWorldPos", sX, sZ)
                    if ptN and type(ptN) == "number" then
                        if ptN <= 45 and ptN % 1 == 0 then ptN = math.max(0, (ptN - 1) * 5) end
                        if ptN > 0 then sumN = sumN + ptN; validN = validN + 1 end
                    end
                    local ptNTgt = callMethod(pfInstance.nitrogenMap, "getTargetLevelAtWorldPos", sX, sZ)
                    if ptNTgt == nil or ptNTgt == 0 then
                        ptNTgt = callMethod(pfInstance.nitrogenMap, "getTargetLevelAtWorldPos", sX, sZ, fData.fruitTypeIndex)
                    end
                    if ptNTgt and type(ptNTgt) == "number" then
                        if ptNTgt <= 45 and ptNTgt % 1 == 0 then ptNTgt = math.max(0, (ptNTgt - 1) * 5) end
                        sumNTarget = sumNTarget + ptNTgt
                    end
                    local ptPh = callMethod(pfInstance.pHMap, "getLevelAtWorldPos", sX, sZ)
                    if ptPh and type(ptPh) == "number" then
                        if ptPh >= 1 and ptPh <= 31 and ptPh % 1 == 0 then ptPh = (ptPh * 0.125) + 4.375 end
                        if ptPh > 0 then sumPh = sumPh + ptPh; validPh = validPh + 1 end
                    end
                    local ptPhTgt = callMethod(pfInstance.pHMap, "getOptimalPHValueForSoilTypeIndex", soilType)
                    if ptPhTgt and type(ptPhTgt) == "number" then
                        if ptPhTgt >= 1 and ptPhTgt <= 31 and ptPhTgt % 1 == 0 then ptPhTgt = (ptPhTgt * 0.125) + 4.375 end
                        sumPhTarget = sumPhTarget + ptPhTgt
                    end
                end
                end
            end

            if validN  > 0 then nLevel  = sumN  / validN;  nTarget  = sumNTarget  / validN  end
            if validPh > 0 then phLevel = sumPh / validPh; phTarget = sumPhTarget / validPh end
        end

        fData.isScanned      = isScanned
        fData.nitrogenLevel  = nLevel
        fData.targetNitrogen = nTarget
        fData.phValue        = phLevel
        fData.targetPh       = phTarget

        -- ====================================================================
        -- 4. STATUS FLAGS AND SUGGESTIONS
        -- ====================================================================
        fData.needsPlowing = fData.plowLevel < 1
        fData.needsWeeding = fData.weedLevel > 0.3

        if isPF then
            if not isScanned then
                fData.fertilizationLevel = 0
                fData.limeLevel          = 0
                fData.needsLime          = true
                fData.needsFertilizer    = true
                fData.nitrogenText       = "Needs Scan"
                fData.limeText           = "Needs Scan"
            else
                fData.nitrogenText       = string.format("%.0f / %.0f kg/ha", nLevel, nTarget)
                fData.limeText           = string.format("%.1f pH", phLevel)
                fData.fertilizationLevel = nTarget > 0 and math.min(2, (nLevel / nTarget) * 2) or 0
                -- Lime suggested when below map target window or absolute soil pH below 6.5
                fData.limeLevel          = ((phTarget > 0 and phLevel >= (phTarget - 0.2)) or phLevel >= 6.5) and 1 or 0
                fData.needsLime          = (phTarget > 0 and phLevel < (phTarget - 0.2)) or (phLevel < 6.5)
                fData.needsFertilizer    = nTarget > 0 and (nLevel < nTarget - 10)
            end
        else
            fData.needsFertilizer = fData.fertilizationLevel < 2
            fData.needsLime       = fData.limeLevel < 1
            fData.nitrogenText    = string.format("%d/2", fData.fertilizationLevel)
            fData.limeText        = fData.needsLime and "Needed" or "Done"
        end

        fData.needsWork = fData.needsFertilizer or fData.needsLime or fData.needsWeeding or fData.needsPlowing

        local fruitUp = string.upper(tostring(fData.fruitType or ""))
        local isGrass = (fruitUp == "GRASS")

        if fData.isWithered then
            if isGrass then
                table.insert(fData.suggestions, {priority = 1, type = "harvest", action = "Harvest grass", reason = "Grass is ready to cut"})
            else
                table.insert(fData.suggestions, {priority = 1, type = "harvest", action = "Harvest withered crop", reason = "Crop has withered"})
            end
        elseif fData.harvestReady and (fData.mulchLevel or 0) < 1 and not fData.isHarvested and fData.growthLabel ~= "harvested" then
            -- Do not suggest harvest when stubble is mulched or crop already taken (stale harvestReady is common)
            local harvestAction = isGrass and "Harvest grass" or "Harvest crop"
            local harvestReason = isGrass and "Grass is ready to cut" or "Crop is ready for harvest"
            table.insert(fData.suggestions, {priority = 1, type = "harvest", action = harvestAction, reason = harvestReason})
        elseif fData.growthState == 0 and fData.hectares > 0 then
            if fData.needsPlowing then
                table.insert(fData.suggestions, {priority = 2, type = "preparation", action = "Plow field",          reason = "Field needs plowing before planting"})
            elseif isPF and not isScanned then
                table.insert(fData.suggestions, {priority = 2, type = "preparation", action = "Soil Map",            reason = "Field needs scanning"})
            else
                -- No plow required: min-till / no-till options instead of implying a plow pass
                table.insert(fData.suggestions, {priority = 2, type = "planting",    action = "Cultivate or direct drilling", reason = "Field is ready for seeding (no plow required)"})
            end
        elseif fData.growthState > 0 and not fData.harvestReady then
            if fData.needsWeeding then
                table.insert(fData.suggestions, {priority = 3, type = "maintenance", action = "Remove weeds",        reason = string.format("Weed level: %.0f%%", weedPercentForDisplay(fData.weedLevel))})
            end
            if isPF then
                if not isScanned then
                    table.insert(fData.suggestions, {priority = 4, type = "info",        action = "Soil Map",        reason = "Field needs scanning"})
                else
                    if fData.needsLime then
                        local tgt = phTarget > 0 and string.format("%.1f", phTarget) or "6.5"
                        table.insert(fData.suggestions, {priority = 3, type = "maintenance", action = "Apply lime",  reason = string.format("Avg pH %.1f / target %s (lime if below 6.5)", phLevel, tgt)})
                    end
                    if fData.needsFertilizer and nTarget > 0 then
                        table.insert(fData.suggestions, {priority = 3, type = "maintenance", action = "Apply nitrogen", reason = string.format("Avg: %.0f / Target: %.0f kg/ha", nLevel, nTarget)})
                    end
                end
            else
                if fData.needsFertilizer then
                    table.insert(fData.suggestions, {priority = 3, type = "maintenance", action = "Apply fertilizer", reason = string.format("Fertilization level: %d/2", fData.fertilizationLevel)})
                end
                if fData.needsLime then
                    table.insert(fData.suggestions, {priority = 3, type = "maintenance", action = "Apply lime",       reason = "Soil pH needs correction"})
                end
            end
        end

        table.sort(fData.suggestions, function(a, b) return a.priority < b.priority end)

        -- Stubble mulch (same source as fields.xml stubbleShredLevel); expose for API/UI parity
        local stubble = fData.mulchLevel or 0
        fData.stubbleShredLevel = stubble
        fData.isMulched = (stubble >= 1)

        if (fData.fruitTypeIndex or 0) == 0 then
            if stubble >= 1 then
                fData.fruitType = "mulched_stubble"
                fData.stateName = "Mulched"
                fData.growthLabel = "mulched_fallow"
            else
                fData.fruitType = "empty"
            end
        end

        table.insert(fieldData, fData)
    end

    table.sort(fieldData, function(a, b) return a.id < b.id end)
    return fieldData
end