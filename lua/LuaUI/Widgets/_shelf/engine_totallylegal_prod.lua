-- TotallyLegal Production Manager - Automatic factory output management
-- Manages factory production queues based on strategy composition preferences.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua, engine_totallylegal_econ.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Production",
        desc      = "Production manager: auto-queue factory units based on strategy. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 203,
        enabled   = false,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitCommands   = Spring.GetUnitCommands
local spGetGameFrame      = Spring.GetGameFrame
local spGiveOrderToUnit   = Spring.GiveOrderToUnit
local spEcho              = Spring.Echo

local mathFloor = math.floor
local mathMax   = math.max

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 60,     -- every 60 frames (2s)
    minQueueSize     = 3,      -- keep at least 3 items in each factory queue
    maxQueueSize     = 6,      -- don't queue more than 6
}

-- Composition templates: unit category -> weight
-- Categories are matched by moveDef and weapon status
local COMPOSITIONS = {
    bots = {
        { role = "raider",     weight = 0.40 },
        { role = "assault",    weight = 0.30 },
        { role = "skirmisher", weight = 0.20 },
        { role = "aa",         weight = 0.10 },
    },
    vehicles = {
        { role = "scout",      weight = 0.10 },
        { role = "light_tank", weight = 0.30 },
        { role = "heavy_tank", weight = 0.30 },
        { role = "artillery",  weight = 0.20 },
        { role = "aa",         weight = 0.10 },
    },
    mixed = {
        { role = "raider",     weight = 0.25 },
        { role = "assault",    weight = 0.25 },
        { role = "light_tank", weight = 0.20 },
        { role = "skirmisher", weight = 0.15 },
        { role = "aa",         weight = 0.10 },
        { role = "constructor", weight = 0.05 },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local factoryData = {}  -- factoryUID -> { defID, buildList }
local roleMappings = {} -- defID -> role string (built at init)

-- Production tracking exposed via WG
local productionState = {
    factories = {},      -- factoryUID -> defID
    currentMix = {},     -- role -> count
    desiredMix = {},     -- role -> fraction
}

--------------------------------------------------------------------------------
-- Role classification
--------------------------------------------------------------------------------

local function BuildRoleMappings()
    roleMappings = {}

    for defID, def in pairs(UnitDefs) do
        if not def.isBuilding and def.canMove and not def.isFactory then
            local cp = def.customParams or {}
            local hasWeapons = def.weapons and #def.weapons > 0
            local speed = def.speed or 0
            local cost = def.metalCost or 0

            if def.buildSpeed and def.buildSpeed > 0 then
                roleMappings[defID] = "constructor"
            elseif not hasWeapons then
                roleMappings[defID] = "utility"
            elseif def.canFly then
                -- Bug #12: differentiate aircraft roles
                local airIsAA = false
                local airHasGroundAttack = false
                local airMaxRange = 0
                if def.weapons then
                    for _, w in ipairs(def.weapons) do
                        local wDefID = w.weaponDef
                        if wDefID and WeaponDefs[wDefID] then
                            if WeaponDefs[wDefID].canAttackGround == false then
                                airIsAA = true
                            else
                                airHasGroundAttack = true
                                airMaxRange = mathMax(airMaxRange, WeaponDefs[wDefID].range or 0)
                            end
                        end
                    end
                end
                if airIsAA and not airHasGroundAttack then
                    roleMappings[defID] = "fighter"
                elseif def.buildSpeed and def.buildSpeed > 0 then
                    roleMappings[defID] = "air_constructor"
                elseif airMaxRange > 600 then
                    roleMappings[defID] = "bomber"
                elseif speed > 120 then
                    roleMappings[defID] = "gunship"
                else
                    roleMappings[defID] = "bomber"
                end
            else
                -- Ground combat units: classify by speed and cost
                local isAA = false
                if def.weapons then
                    for _, w in ipairs(def.weapons) do
                        local wDefID = w.weaponDef
                        if wDefID and WeaponDefs[wDefID] then
                            if WeaponDefs[wDefID].canAttackGround == false then
                                isAA = true
                            end
                        end
                    end
                end

                if isAA then
                    roleMappings[defID] = "aa"
                elseif speed > 90 and cost < 200 then
                    roleMappings[defID] = "raider"
                elseif speed > 60 and cost < 150 then
                    roleMappings[defID] = "scout"
                elseif cost > 500 then
                    roleMappings[defID] = "heavy_tank"
                elseif cost > 200 then
                    roleMappings[defID] = "assault"
                elseif speed < 40 then
                    roleMappings[defID] = "artillery"
                else
                    -- Medium speed, medium cost
                    local mn = def.moveDef and def.moveDef.name and def.moveDef.name:lower() or ""
                    if mn:find("tank") or mn:find("veh") then
                        roleMappings[defID] = "light_tank"
                    else
                        roleMappings[defID] = "skirmisher"
                    end
                end
            end
        end
    end

    if productionState then
        productionState.roleMappings = roleMappings
    end
end

--------------------------------------------------------------------------------
-- Factory management
--------------------------------------------------------------------------------

local function GetFactoryBuildList(factoryDefID)
    local def = UnitDefs[factoryDefID]
    if not def or not def.buildOptions then return {} end
    return def.buildOptions
end

local function FindBestUnit(buildList, targetRole)
    local bestDefID = nil
    local bestScore = -1

    for _, defID in ipairs(buildList) do
        local role = roleMappings[defID]
        if role == targetRole then
            local cost = (UnitDefs[defID] and UnitDefs[defID].metalCost) or 0
            if cost > bestScore then
                bestScore = cost
                bestDefID = defID
            end
        end
    end

    return bestDefID
end

local function GetCurrentMix()
    local mix = {}
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        local role = roleMappings[defID]
        if role then
            mix[role] = (mix[role] or 0) + 1
        end
    end

    productionState.currentMix = mix
    return mix
end

local function QueueProduction()
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    -- Work even without strategy config - use sensible defaults
    local emergencyMode = strat and strat.emergencyMode or "none"
    local compKey = strat and strat.unitComposition or "mixed"
    local role = strat and strat.role or "balanced"

    -- Emergency: mobilization → flood cheapest combat unit at all factories
    if emergencyMode == "mobilization" then
        local myUnits = TL.GetMyUnits()
        for uid, defID in pairs(myUnits) do
            local cls = TL.GetUnitClass(defID)
            if cls and cls.isFactory then
                productionState.factories[uid] = defID
                local cmdCount = spGetUnitCommands(uid, 0)
                if (cmdCount or 0) < CFG.maxQueueSize then
                    local buildList = GetFactoryBuildList(defID)
                    local cheapestDefID = nil
                    local cheapestCost = math.huge
                    for _, bDefID in ipairs(buildList) do
                        local role = roleMappings[bDefID]
                        if role and role ~= "constructor" and role ~= "utility" then
                            local cost = (UnitDefs[bDefID] and UnitDefs[bDefID].metalCost) or math.huge
                            if cost < cheapestCost then
                                cheapestCost = cost
                                cheapestDefID = bDefID
                            end
                        end
                    end
                    if cheapestDefID then
                        spGiveOrderToUnit(uid, -cheapestDefID, {}, {"shift"})
                    end
                end
            end
        end
        return
    end

    local composition = COMPOSITIONS[compKey] or COMPOSITIONS.mixed

    -- Role-based composition adjustments
    if role ~= "balanced" then
        local adjusted = {}
        for _, entry in ipairs(composition) do
            local w = entry.weight
            if role == "aggro" then
                if entry.role == "raider" or entry.role == "assault" then
                    w = w + 0.10
                elseif entry.role == "constructor" then
                    w = 0
                end
            elseif role == "eco" then
                if entry.role == "constructor" then
                    w = 0.15
                end
            elseif role == "support" then
                if entry.role == "constructor" or entry.role == "utility" then
                    w = w + 0.05
                end
            end
            adjusted[#adjusted + 1] = { role = entry.role, weight = w }
        end
        composition = adjusted
    end

    -- Update desired mix for display
    productionState.desiredMix = {}
    for _, entry in ipairs(composition) do
        productionState.desiredMix[entry.role] = entry.weight
    end

    local currentMix = GetCurrentMix()

    -- Calculate total combat units
    local totalCombat = 0
    for role, count in pairs(currentMix) do
        if role ~= "constructor" and role ~= "utility" then
            totalCombat = totalCombat + count
        end
    end

    -- Check for goal overrides
    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    local goalOverride = goals and goals.overrides and goals.overrides.prodOverride

    local myUnits = TL.GetMyUnits()
    productionState.factories = {}

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.isFactory then
            productionState.factories[uid] = defID

            -- Check queue length
            local cmdCount = spGetUnitCommands(uid, 0)
            if (cmdCount or 0) < CFG.minQueueSize then
                local buildList = GetFactoryBuildList(defID)
                if #buildList > 0 then
                    -- Goal override: try to queue the goal's requested unit first
                    local overrideHandled = false
                    if goalOverride and goalOverride.unitDefID and UnitDefs[goalOverride.unitDefID] and goalOverride.count > 0 then
                        for _, bDefID in ipairs(buildList) do
                            if bDefID == goalOverride.unitDefID then
                                spGiveOrderToUnit(uid, -goalOverride.unitDefID, {}, {"shift"})
                                goalOverride.count = mathMax(0, goalOverride.count - 1)
                                overrideHandled = true
                                break
                            end
                        end
                    end

                    if not overrideHandled then
                        -- Normal: find most under-represented role
                        local bestRole = nil
                        local bestDeficit = -math.huge

                        for _, entry in ipairs(composition) do
                            local desired = entry.weight * mathMax(totalCombat, 10)
                            local actual = currentMix[entry.role] or 0
                            local deficit = desired - actual

                            if deficit > bestDeficit then
                                -- Check if this factory can build this role
                                local unitDefID = FindBestUnit(buildList, entry.role)
                                if unitDefID then
                                    bestDeficit = deficit
                                    bestRole = entry.role
                                end
                            end
                        end

                        if bestRole then
                            local unitDefID = FindBestUnit(buildList, bestRole)
                            if unitDefID then
                                -- Queue the unit (shift-add to append)
                                spGiveOrderToUnit(uid, -unitDefID, {}, {"shift"})
                            end
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Prod] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Prod] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildRoleMappings()

    WG.TotallyLegal.Production = productionState
    productionState.roleMappings = roleMappings
    productionState._ready = true

    spEcho("[TotallyLegal Prod] Production manager ready.")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end
    if frame < 60 then return end  -- skip first 2 seconds

    local ok, err = pcall(function()
        QueueProduction()
    end)
    if not ok then
        spEcho("[TotallyLegal Prod] GameFrame error: " .. tostring(err))
    end
end

function widget:Shutdown()
    if WG.TotallyLegal and WG.TotallyLegal.Production then
        WG.TotallyLegal.Production._ready = false
    end
end
