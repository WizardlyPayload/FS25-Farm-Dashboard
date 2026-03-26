-- FS25 FarmDashboard | FinanceDataCollector.lua | v1.0.0

FinanceDataCollector = {}

function FinanceDataCollector:init()
end

function FinanceDataCollector:collect()
    local financeData = {
        farmId    = 1,
        money     = 0,
        loan      = 0,
        loanMax   = 500000,
        totalAssets = 0,
        netWorth  = 0,
        vehicles  = { count = 0, totalValue = 0 },
        animals   = { count = 0, totalValue = 0 },
        buildings = { count = 0, totalValue = 0 },
        land      = { count = 0, totalValue = 0, hectares = 0 }
    }

    if not _G.g_currentMission then
        return financeData
    end

    -- FIX: FS25 stores money per farm via g_farmManager, not on the mission object.
    -- g_currentMission:getMoney() does not exist in FS25.
    pcall(function()
        if _G.g_farmManager and _G.g_farmManager.farms then
            for _, farm in pairs(_G.g_farmManager.farms) do
                -- Farm 1 is always the local/first player farm
                if farm.farmId == 1 then
                    financeData.money   = farm.money  or 0
                    financeData.loan    = farm.loan   or 0
                    financeData.loanMax = farm.loanMax or 500000
                    break
                end
            end
        end
    end)

    -- Vehicle total value for farm 1
    pcall(function()
        local vehicleValue = 0
        local vehicleCount = 0
        if _G.g_currentMission.vehicles then
            for _, vehicle in pairs(_G.g_currentMission.vehicles) do
                local ok, fId = pcall(function() return vehicle:getOwnerFarmId() end)
                if ok and fId == 1 then
                    vehicleCount = vehicleCount + 1
                    local ok2, price = pcall(function() return vehicle:getSellPrice() end)
                    vehicleValue = vehicleValue + (ok2 and price or (vehicle.price or 0))
                end
            end
        end
        financeData.vehicles.count      = vehicleCount
        financeData.vehicles.totalValue = vehicleValue
    end)

    financeData.totalAssets = financeData.money + financeData.vehicles.totalValue
    financeData.netWorth    = financeData.totalAssets - financeData.loan

    return financeData
end

function FinanceDataCollector:shutdown()
end
