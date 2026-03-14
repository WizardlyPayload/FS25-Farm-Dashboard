FieldDataCollector = {}
FieldDataCollector.hasDumped = false

function FieldDataCollector:init()
    print("[FarmDashboard] Field data collector initialized (MEGADUMPER Active)")
end

function FieldDataCollector:collect()
    -- Wait until the mission is fully loaded
    if not _G.g_currentMission then return {} end
    
    -- DUMP SCRIPT: Will only run ONCE to avoid spamming the log
    if not self.hasDumped and _G.g_fieldManager and _G.g_fieldManager.fields then
        self.hasDumped = true
        
        print("==================================================")
        print("[FarmDash-MEGADUMP] INITIATING DEEP ENGINE SCAN")
        print("==================================================")
        
        -- ==========================================
        -- PART 1: API DISCOVERY
        -- ==========================================
        print("\n--- 1. FSDensityMapUtil Functions ---")
        if _G.FSDensityMapUtil then
            for k, v in pairs(_G.FSDensityMapUtil) do
                if type(v) == "function" then
                    print("  FSDensityMapUtil." .. tostring(k) .. "()")
                end
            end
        else
            print("  FSDensityMapUtil not found in global scope.")
        end

        -- ==========================================
        -- PART 2: NATIVE CACHE DUMP (Field 5 - Sunflowers)
        -- ==========================================
        print("\n--- 2. Field 5 Native Properties ---")
        local field5 = _G.g_fieldManager.fields[5]
        if field5 then
            for k, v in pairs(field5) do
                local vType = type(v)
                if vType == "string" or vType == "number" or vType == "boolean" then
                    print(string.format("  [%s] %s = %s", vType, tostring(k), tostring(v)))
                elseif vType == "table" and k == "fieldState" then
                    print("  [table] fieldState (THE CACHE):")
                    for sk, sv in pairs(v) do
                        local st = type(sv)
                        if st == "string" or st == "number" or st == "boolean" then
                            print(string.format("     -> [%s] %s = %s", st, tostring(sk), tostring(sv)))
                        end
                    end
                end
            end
        else
            print("  Field 5 not found!")
        end

        -- ==========================================
        -- PART 3: PHYSICAL DIRT PROBES
        -- ==========================================
        print("\n--- 3. Density Map Probes ---")
        -- Testing Grass(3), Empty(4), Sunflowers(5), Soybeans(6)
        local testFields = {3, 4, 5, 6} 
        
        for _, fieldId in ipairs(testFields) do
            local field = _G.g_fieldManager.fields[fieldId]
            if field then
                local px = field.posX or 0
                local pz = field.posZ or 0
                print(string.format("\n>> Probing Field %d (X:%.2f, Z:%.2f) <<", fieldId, px, pz))
                
                if _G.FSDensityMapUtil then
                    
                    -- TEST A: getFruitTypeIndexAtWorldPos (2D vs 3D)
                    if type(_G.FSDensityMapUtil.getFruitTypeIndexAtWorldPos) == "function" then
                        local ok2D, res2D = pcall(_G.FSDensityMapUtil.getFruitTypeIndexAtWorldPos, px, pz)
                        print(string.format("  getFruitTypeIndex (2D: x,z)   : ok=%s, res=%s", tostring(ok2D), tostring(res2D)))
                        
                        local ok3D, res3D = pcall(_G.FSDensityMapUtil.getFruitTypeIndexAtWorldPos, px, 0, pz)
                        print(string.format("  getFruitTypeIndex (3D: x,0,z) : ok=%s, res=%s", tostring(ok3D), tostring(res3D)))
                    end
                    
                    -- TEST B: getFieldDataAtWorldPosition (2D vs 3D)
                    if type(_G.FSDensityMapUtil.getFieldDataAtWorldPosition) == "function" then
                        -- Test 2D Signature
                        local ok2, v1, v2, v3, v4, v5, v6 = pcall(_G.FSDensityMapUtil.getFieldDataAtWorldPosition, px, pz)
                        print(string.format("  getFieldData      (2D: x,z)   : ok=%s | Returns: %s, %s, %s, %s, %s, %s", 
                            tostring(ok2), tostring(v1), tostring(v2), tostring(v3), tostring(v4), tostring(v5), tostring(v6)))
                            
                        -- Test 3D Signature
                        local ok3, w1, w2, w3, w4, w5, w6 = pcall(_G.FSDensityMapUtil.getFieldDataAtWorldPosition, px, 0, pz)
                        print(string.format("  getFieldData      (3D: x,0,z) : ok=%s | Returns: %s, %s, %s, %s, %s, %s", 
                            tostring(ok3), tostring(w1), tostring(w2), tostring(w3), tostring(w4), tostring(w5), tostring(w6)))
                    end
                end
            end
        end

        print("==================================================")
        print("[FarmDash-MEGADUMP] SCAN COMPLETE")
        print("==================================================")
    end
    
    -- Return an empty table so the dashboard doesn't crash while we debug
    return {}
end