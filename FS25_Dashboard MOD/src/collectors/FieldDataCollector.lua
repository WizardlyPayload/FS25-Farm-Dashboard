-- FS25 FarmDashboard | FieldDataCollector.lua | v2.0.0

FieldDataCollector = {}

function FieldDataCollector:init()
    print("[FarmDashboard] Field data collector initialized (Hybrid: NPC State + Physical HUD Probe)")
end

function FieldDataCollector:collect()
    local fieldData = {}
    
    if not _G.g_currentMission then return fieldData end
    if not _G.g_fieldManager or not _G.g_fieldManager.fields then return fieldData end

    --- Shown on lime / fertiliser / nitrogen / weed-spray suggestions (limit crop trampling).
    local TYRE_NOTE_ON_CROP = " Use narrow tyres when working on the crop (lime, fertiliser, spray)."
    --- When combining several nutrient sources, organic liquids/solids before mineral (player guidance).
    local FERT_ORGANIC_FIRST = " Prefer manure or slurry before solid or liquid mineral fertilizer when using multiple products."

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

    --- Roller / soil compaction: FS `FieldState.rollerLevel` (FieldState.lua). After `update`, higher values mean *more rolling
    --- still required* / less compacted; lower = already rolled — opposite of a 0–1 “rolled progress”. We export `rollerLevel`
    --- as rolled fraction (1 = done, 0 = not rolled) so JSON/UI match the HUD.
    local function readRollerFromState(st)
        if not st then return 0 end
        local ok, v = pcall(function()
            local r = st.rollerLevel or st.rollLevel or st.rollingLevel
            if r ~= nil and type(r) == "number" then return r end
            return 0
        end)
        if ok and type(v) == "number" then return v end
        return 0
    end

    --- Engine raw: low = already rolled, high = still needs rolling (0–1). Output: rolled fraction 0–1 for JSON/UI.
    local function rollerLevelAsRolledFraction(raw)
        raw = raw or 0
        if raw < 0 then raw = 0 end
        if raw > 1 and raw <= 255 then raw = raw / 255 end
        if raw > 1 then raw = 1 end
        return 1 - raw
    end

    --- Weed: integer 0–4 = FS stages; else 0–1 fraction; else 0–100 = percent. Normalize to 0–1.
    local function weedNorm01(w)
        w = w or 0
        if w < 0 then w = 0 end
        if w <= 4 and w == math.floor(w) then
            return math.min(1, w / 4)
        end
        if w <= 1 then return w end
        if w <= 100 then return math.min(1, w / 100) end
        return math.min(1, w / 255)
    end

    local function weedPercentForDisplay(w)
        return math.min(100, math.floor(weedNorm01(w) * 100 + 0.5))
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
            --- Raw `numGrowthStates` from fruit desc (grass can be 8); used for rolling window vs UI-capped `maxGrowthState`.
            engineNumGrowthStates = 0,
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
            phLimeBarMin          = 0,
            phLimeBarMax          = 0,
            needsWork             = false,
            needsPlowing          = false,
            needsLime             = false,
            needsFertilizer       = false,
            needsWeeding          = false,
            needsRolling          = false,
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

        -- 1c. Roller: read raw `rollerLevel`, export inverted rolled fraction for API/UI parity with HUD.
        do
            local raw = 0
            if field.fieldState and type(field.fieldState.update) == "function" then
                pcall(function() field.fieldState:update(cx, cz) end)
                raw = readRollerFromState(field.fieldState)
            elseif probeState and type(probeState.update) == "function" then
                pcall(function() probeState:update(cx, cz) end)
                raw = readRollerFromState(probeState)
            end
            fData.rollerLevel = rollerLevelAsRolledFraction(raw)
        end

        -- Engine GroundType cache: only adjust "visual dirt" when there is NO crop.
        -- If we clobber growthState with groundType while fruit is planted, rolling / stage-1 tasks
        -- disagree with the in-game field map (e.g. field still shows "needs rolling").
        local gType = fData.groundType
        if (fData.fruitTypeIndex or 0) == 0 then
            if gType == 3 or gType == 4 then
                if fData.growthState == 0 then fData.growthState = 1 end
                fData.harvestReady = false
            elseif gType == 1 or gType == 2 then
                fData.growthState  = 0
                fData.harvestReady = false
            end
        end

        -- ====================================================================
        -- 2. CROP CLASSIFICATION & HARVEST MATH
        -- ====================================================================
        if fData.fruitTypeIndex > 0 and _G.g_fruitTypeManager then
            local ftDesc = _G.g_fruitTypeManager:getFruitTypeByIndex(fData.fruitTypeIndex)
            if ftDesc then
                fData.fruitType      = ftDesc.name or "unknown"
                fData.engineNumGrowthStates = ftDesc.numGrowthStates or 0
                fData.maxGrowthState = fData.engineNumGrowthStates
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

                -- Grass: engine often marks harvest-ready at 3/4; only treat as ready at final growth stage (4/4).
                if ftUpper == "GRASS" and (fData.maxGrowthState or 0) > 0 and (fData.growthState or 0) > 0
                    and (fData.growthState or 0) < fData.maxGrowthState then
                    fData.harvestReady = false
                    fData.growthLabel  = "growing"
                    fData.stateName    = "Growing"
                    if maxStateToShow > 0 then
                        fData.growthStatePercentage = math.min(99, math.floor((fData.growthState / maxStateToShow) * 100))
                    end
                end
            end
        end

        -- ====================================================================
        -- 3. PRECISION FARMING RADIUS SCANNER
        -- ====================================================================
        local nLevel, nTarget, phLevel, phTarget = 0, 0, 0, 0
        local isScanned = false
        local sumPhBarMin, validPhBarMin = 0, 0

        --- Decode PF pH map raw 1..31 scale to pH if needed (same as ptPh).
        local function decodePhRaw(v)
            if not v or type(v) ~= "number" then return nil end
            if v >= 1 and v <= 31 and v % 1 == 0 then return (v * 0.125) + 4.375 end
            return v
        end

        --- Lower end of the "healthy" pH range for this soil type (for UI bar + lime band).
        --- Tries PF pHMap methods; falls back to optimal − margin (per soil sample).
        local function getPhBarMinForSoilType(pHMap, soilTypeIdx, optimalPh)
            local tryNames = {
                "getMinimumPHValueForSoilTypeIndex",
                "getMinPHValueForSoilTypeIndex",
                "getMinimumRecommendedPHForSoilTypeIndex",
                "getMinRecommendedPHForSoilTypeIndex",
            }
            for _, nm in ipairs(tryNames) do
                local v = callMethod(pHMap, nm, soilTypeIdx)
                v = decodePhRaw(v)
                if v and v > 0 and v < (optimalPh or 99) then return v end
            end
            if optimalPh and optimalPh > 0 then
                return math.max(4.3, optimalPh - 1.2)
            end
            return 5.5
        end

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
                    local optForBar = ptPhTgt
                    if optForBar and optForBar > 0 then
                        local barMinPt = getPhBarMinForSoilType(pfInstance.pHMap, soilType, optForBar)
                        if barMinPt and barMinPt > 0 then
                            sumPhBarMin = sumPhBarMin + barMinPt
                            validPhBarMin = validPhBarMin + 1
                        end
                    end
                end
                end
            end

            if validN  > 0 then nLevel  = sumN  / validN;  nTarget  = sumNTarget  / validN  end
            if validPh > 0 then phLevel = sumPh / validPh; phTarget = sumPhTarget / validPh end
        end

        local phBarMinAvg = 0
        if validPhBarMin > 0 then phBarMinAvg = sumPhBarMin / validPhBarMin end
        if phBarMinAvg <= 0 and phTarget > 0 then phBarMinAvg = math.max(4.3, phTarget - 1.2) end
        if phBarMinAvg <= 0 then phBarMinAvg = 5.5 end

        fData.isScanned      = isScanned
        fData.nitrogenLevel  = nLevel
        fData.targetNitrogen = nTarget
        fData.phValue        = phLevel
        fData.targetPh       = phTarget
        fData.phLimeBarMin   = phBarMinAvg
        fData.phLimeBarMax   = phTarget

        -- ====================================================================
        -- 4. STATUS FLAGS AND SUGGESTIONS
        -- ====================================================================
        fData.needsPlowing = fData.plowLevel < 1
        -- ~15%+ weeds (handles 0–1, 0–4 stages, or 0–100 percent-style reads)
        fData.needsWeeding = weedNorm01(fData.weedLevel) > 0.15

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
                -- Lime: use PF optimal pH for sampled soil types (targetPh); band matches in-game recommendation (~0.2 below target).
                local limeBand = 0.2
                if phTarget > 0 then
                    fData.limeLevel   = (phLevel >= (phTarget - limeBand)) and 1 or 0
                    fData.needsLime   = phLevel < (phTarget - limeBand)
                else
                    fData.limeLevel   = phLevel >= 6.5 and 1 or 0
                    fData.needsLime   = phLevel < 6.5
                end
                fData.needsFertilizer    = nTarget > 0 and (nLevel < nTarget - 10)
            end
        else
            fData.needsFertilizer = fData.fertilizationLevel < 2
            fData.needsLime       = fData.limeLevel < 1
            fData.nitrogenText    = string.format("%d/2", fData.fertilizationLevel)
            fData.limeText        = fData.needsLime and "Needed" or "Done"
        end

        local fruitUp = string.upper(tostring(fData.fruitType or ""))
        local isGrass = (fruitUp == "GRASS")

        -- Lime on growing crops: not practical after emergence past stage 3 (arable only).
        if not isGrass and (fData.fruitTypeIndex or 0) > 0 and (fData.growthState or 0) > 3 then
            fData.needsLime = false
        end

        -- Roll: first growth stage only; `rollerLevel` here is rolled fraction (1 = done), so need roll while < 1.
        fData.needsRolling = false
        if (fData.fruitTypeIndex or 0) > 0 and not fData.harvestReady and not fData.isWithered
            and (fData.rollerLevel or 0) < 1 then
            local engMax = fData.engineNumGrowthStates or 0
            if engMax <= 0 then engMax = fData.maxGrowthState or 0 end
            local gs = fData.growthState or 0
            local ftUp = string.upper(tostring(fData.fruitType or ""))
            local inFirstStage = false
            if ftUp == "GRASS" and engMax > 4 then
                inFirstStage = (math.ceil((gs * 4) / engMax) == 1)
            else
                inFirstStage = (gs == 1)
            end
            fData.needsRolling = inFirstStage
        end

        fData.needsWork = fData.needsFertilizer or fData.needsLime or fData.needsWeeding or fData.needsPlowing or fData.needsRolling

        --- No crop planted yet (even if groundType forced growthState>0 for cultivated soil).
        local noCrop = (fData.fruitTypeIndex or 0) == 0

        if fData.isWithered then
            if isGrass then
                table.insert(fData.suggestions, {priority = 1, type = "harvest", action = "Harvest grass", reason = "Grass is ready to cut"})
            else
                table.insert(fData.suggestions, {priority = 1, type = "harvest", action = "Harvest withered crop", reason = "Crop has withered"})
            end
        elseif not noCrop and fData.harvestReady and (fData.mulchLevel or 0) < 1 and not fData.isHarvested and fData.growthLabel ~= "harvested" then
            -- Do not suggest harvest when stubble is mulched or crop already taken (stale harvestReady is common)
            local harvestAction = isGrass and "Harvest grass" or "Harvest crop"
            local harvestReason = isGrass and "Grass is ready to cut" or "Crop is ready for harvest"
            table.insert(fData.suggestions, {priority = 1, type = "harvest", action = harvestAction, reason = harvestReason})
        elseif noCrop and fData.hectares > 0 then
            -- Order: Soil map (10) → plow (11) → cultivate if mulched (12) → lime (13) → sow (14). noCrop, not growthState==0 — cultivated empty often reports growthState 1.
            if isPF and not isScanned then
                table.insert(fData.suggestions, {priority = 10, type = "preparation", action = "Soil Map", reason = "Scan field before lime and planting decisions"})
            else
                if fData.needsPlowing then
                    table.insert(fData.suggestions, {priority = 11, type = "preparation", action = "Plow field", reason = "Plow before lime and seeding when the field requires it (e.g. after harvest or heavy residue)"})
                end
                if (fData.mulchLevel or 0) >= 1 then
                    table.insert(fData.suggestions, {priority = 12, type = "preparation", action = "Cultivate field", reason = "Mulched stubble — cultivate before lime and drilling (needed even with direct drill or planter)"})
                end
                if isPF and isScanned and fData.needsLime then
                    local tgt = phTarget > 0 and string.format("%.1f", phTarget) or "6.5"
                    local band = phTarget > 0 and string.format("%.1f", phTarget - 0.2) or "6.3"
                    table.insert(fData.suggestions, {priority = 13, type = "maintenance", action = "Apply lime", reason = string.format("Avg pH %.1f / soil target %s (lime before seeding; below ~%s)%s", phLevel, tgt, band, TYRE_NOTE_ON_CROP)})
                elseif not isPF and fData.needsLime then
                    table.insert(fData.suggestions, {priority = 13, type = "maintenance", action = "Apply lime", reason = "Soil pH needs correction before seeding" .. TYRE_NOTE_ON_CROP})
                end
                if fData.needsPlowing then
                    -- Sow only after plowing is done in-game
                elseif (fData.plowLevel or 0) >= 1 then
                    local mulched = (fData.mulchLevel or 0) >= 1
                    local reason = mulched
                        and "Soil is prepared (cultivated / mulch worked); sow or plant your next crop"
                        or "Soil is prepared; sow or plant your next crop"
                    table.insert(fData.suggestions, {priority = 14, type = "planting", action = "Sow or plant crop", reason = reason})
                else
                    table.insert(fData.suggestions, {priority = 14, type = "planting", action = "Cultivate or direct drilling", reason = "Prepare seedbed, then sow or plant"})
                end
            end
        elseif not noCrop and fData.growthState > 0 and not fData.harvestReady then
            -- Order: PF scan (11) → lime (12, arable stage ≤3) → roll stage 1 (13) → fertiliser (15) → weeds (18). N deferred if early + near target.
            local gsGrow = fData.growthState or 0
            local limeOkGrow = fData.needsLime and (isGrass or gsGrow <= 3)
            local deferEarlyN = isPF and isScanned and nTarget > 0 and gsGrow <= 2 and nLevel >= (nTarget - 20)

            if isPF and not isScanned then
                table.insert(fData.suggestions, {priority = 11, type = "info", action = "Soil Map", reason = "Scan field for nitrogen and pH targets"})
            end
            if isPF and isScanned and limeOkGrow then
                local tgt = phTarget > 0 and string.format("%.1f", phTarget) or "6.5"
                local band = phTarget > 0 and string.format("%.1f", phTarget - 0.2) or "6.3"
                table.insert(fData.suggestions, {priority = 12, type = "maintenance", action = "Apply lime", reason = string.format("Avg pH %.1f / soil target %s (below ~%s)%s", phLevel, tgt, band, TYRE_NOTE_ON_CROP)})
            elseif not isPF and limeOkGrow then
                table.insert(fData.suggestions, {priority = 12, type = "maintenance", action = "Apply lime", reason = "Soil pH needs correction" .. TYRE_NOTE_ON_CROP})
            end
            if fData.needsRolling then
                table.insert(fData.suggestions, {priority = 13, type = "maintenance", action = "Roll field", reason = "Needs rolling — grass or crop at first growth stage after planting"})
            end
            if isPF and isScanned and fData.needsFertilizer and nTarget > 0 and not deferEarlyN then
                table.insert(fData.suggestions, {priority = 15, type = "maintenance", action = "Apply nitrogen", reason = string.format("Avg: %.0f / Target: %.0f kg/ha.%s%s", nLevel, nTarget, FERT_ORGANIC_FIRST, TYRE_NOTE_ON_CROP)})
            elseif not isPF and fData.needsFertilizer then
                local reason = string.format("Fertilization level: %d/2.%s", fData.fertilizationLevel, FERT_ORGANIC_FIRST)
                if (fData.fertilizationLevel or 0) >= 1 then
                    reason = reason .. " Second application with spreader or sprayer to reach full level."
                end
                table.insert(fData.suggestions, {priority = 15, type = "maintenance", action = "Apply fertilizer", reason = reason .. TYRE_NOTE_ON_CROP})
            end
            if fData.needsWeeding then
                local wp = weedPercentForDisplay(fData.weedLevel)
                local weedReason
                if not isGrass and gsGrow <= 2 then
                    weedReason = string.format("Weed level: %.0f%% — weeder or hoe suit early growth (around stage 2 or below).", wp)
                else
                    weedReason = string.format("Weed level: %.0f%%", wp) .. TYRE_NOTE_ON_CROP .. " Herbicide sprayer recommended once past early growth."
                end
                table.insert(fData.suggestions, {priority = 18, type = "maintenance", action = "Remove weeds", reason = weedReason})
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