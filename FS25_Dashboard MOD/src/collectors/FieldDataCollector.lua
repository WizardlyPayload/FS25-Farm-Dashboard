FieldDataCollector = {}
FieldDataCollector.hasProbed = false

function FieldDataCollector:init()
    print("[FarmDashboard] Field data collector initialized (FOOT PROBE ACTIVE)")
end

function FieldDataCollector:collect()
    -- Wait until the mission is loaded
    if not _G.g_currentMission then return {} end
    
    -- Only run this ONCE when the player is actually walking around
    if not self.hasProbed and _G.g_currentMission.player and _G.g_currentMission.player.isControlled then
        
        -- Get the exact coordinates of the player's feet
        local px, py, pz = getWorldTranslation(_G.g_currentMission.player.rootNode)
        
        print("==================================================")
        print("[FarmDash] FOOT PROBE INITIATED")
        print(string.format("[FarmDash] Player standing at X:%.2f, Y:%.2f, Z:%.2f", px, py, pz))
        
        if _G.FSDensityMapUtil and _G.FSDensityMapUtil.getFieldDataAtWorldPosition then
            -- 1. Probe the 3D data (This is what the HUD does)
            local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9 = pcall(_G.FSDensityMapUtil.getFieldDataAtWorldPosition, px, py, pz)
            
            print("[FarmDash] getFieldDataAtWorldPosition returned:")
            print("  ok = " .. tostring(ok))
            print("  Slot 1 = " .. tostring(r1))
            print("  Slot 2 = " .. tostring(r2))
            print("  Slot 3 = " .. tostring(r3))
            print("  Slot 4 = " .. tostring(r4))
            print("  Slot 5 = " .. tostring(r5))
            print("  Slot 6 = " .. tostring(r6))
            print("  Slot 7 = " .. tostring(r7))
            print("  Slot 8 = " .. tostring(r8))
            print("  Slot 9 = " .. tostring(r9))
            
            -- 2. Probe the strict 2D crop data
            local ok2, fIdx = pcall(_G.FSDensityMapUtil.getFruitTypeIndexAtWorldPos, px, pz)
            print("[FarmDash] getFruitTypeIndexAtWorldPos returned: " .. tostring(fIdx))
        else
            print("[FarmDash] FSDensityMapUtil not available!")
        end
        print("==================================================")
        
        self.hasProbed = true
    end
    
    -- Return an empty table so the dashboard doesn't crash the UI while we test
    return {}
end