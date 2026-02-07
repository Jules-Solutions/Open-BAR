-- TotallyLegal Goal & Project Queue - Ordered objectives with resource allocation
-- Manages goal queue, evaluates completion, generates overrides for econ/prod/zone engines.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua,
--           engine_totallylegal_econ.lua, engine_totallylegal_prod.lua, engine_totallylegal_zone.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Goals",
        desc      = "Goal & project queue: ordered objectives with resource allocation. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 205,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetMyAllyTeamID   = Spring.GetMyAllyTeamID
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetUnitCommands   = Spring.GetUnitCommands
local spGetGameFrame      = Spring.GetGameFrame
local spGiveOrderToUnit   = Spring.GiveOrderToUnit
local spShareResources    = Spring.ShareResources
local spEcho              = Spring.Echo

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local mathSqrt  = math.sqrt

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency    = 45,     -- every 45 frames (1.5s)
    stallCheckFrames   = 600,    -- 20s with no progress = stalled
    reassignCooldown   = 300,    -- 10s before re-assigning a constructor
}

--------------------------------------------------------------------------------
-- Goal types
--------------------------------------------------------------------------------

local GOAL_TYPES = {
    "unit_production",    -- produce N units of a role/type
    "structure_build",    -- build N structures of a type (auto-placed)
    "structure_place",    -- build a structure at a specific map position
    "economy_target",     -- reach a resource income threshold
    "tech_transition",    -- get a T2/T3 factory running
    "buildpower_target",  -- reach a total build power threshold
}

local GOAL_TYPE_SET = {}
for _, gt in ipairs(GOAL_TYPES) do GOAL_TYPE_SET[gt] = true end

--------------------------------------------------------------------------------
-- Role options (matching prod.lua role classification)
--------------------------------------------------------------------------------

local ROLE_OPTIONS = {
    "raider", "assault", "skirmisher", "aa", "scout",
    "light_tank", "heavy_tank", "artillery", "constructor",
}

local DESTINATION_OPTIONS = { "front", "rally", "base" }

local METRIC_OPTIONS = { "metalIncome", "energyIncome" }

local FACTORY_TYPE_OPTIONS = { "bot", "vehicle", "air" }

--------------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------------

local GOAL_PRESETS = {
    { name = "Rush 5 Tanks",       goalType = "unit_production",  target = { role = "assault",    count = 5,  destination = "front" }},
    { name = "5 Raiders to Front", goalType = "unit_production",  target = { role = "raider",     count = 5,  destination = "front" }},
    { name = "Scale to 20 M/s",    goalType = "economy_target",   target = { metric = "metalIncome", threshold = 20 }},
    { name = "Scale to 40 E/s",    goalType = "economy_target",   target = { metric = "energyIncome", threshold = 40 }},
    { name = "Transition to T2",   goalType = "tech_transition",  target = { techLevel = 2 }},
    { name = "Build Fusion",       goalType = "structure_build",  target = { buildKey = "fusion",  count = 1 }},
    { name = "Build Nuke Silo",    goalType = "structure_place",  target = { buildKey = "nuke_silo" }},
    { name = "Light Base Defense",  goalType = "structure_build",  target = { buildKey = "llt",     count = 3 }},
    { name = "Get 450 Total BP",   goalType = "buildpower_target", target = { bpTarget = 450 }},
    { name = "Produce 10 Heavies", goalType = "unit_production",  target = { role = "heavy_tank", count = 10, destination = "front" }},
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local nextGoalID = 1

local goalState = {
    queue = {},           -- ordered array of Goal tables
    activeGoal = nil,     -- reference to the currently active goal (or nil)

    allocation = {
        econVsUnits    = 50,
        savingsRate    = 0,
        teamShareRate  = 0,
        projectFunding = 30,
        autoMode       = false,
    },

    overrides = {
        econBuildTask       = nil,   -- { key, defID, position }
        projectConstructors = 0,     -- fraction 0.0-1.0
        reserveMetal        = 0,
        reserveEnergy       = 0,
        prodOverride        = nil,   -- { unitDefID, count, roleKey }
        unitDestination     = nil,   -- { unitUIDs, target, behavior }
    },

    -- Map placement mode
    placementMode = {
        active   = false,
        buildKey = nil,
    },
}

-- Constructor assignment cooldowns: conUID -> last assignment frame
local conCooldowns = {}

--------------------------------------------------------------------------------
-- Unit key resolution (same pattern as build.lua / econ.lua)
--------------------------------------------------------------------------------

local keyToDefID = {}

local function BuildKeyTable()
    keyToDefID = {}
    for defID, def in pairs(UnitDefs) do
        local name = (def.name or ""):lower()
        local cp = def.customParams or {}

        keyToDefID[name] = defID

        if def.extractsMetal and def.extractsMetal > 0 then
            local tl = tonumber(cp.techlevel) or 1
            if tl >= 2 then
                keyToDefID["moho"] = keyToDefID["moho"] or defID
                keyToDefID["adv_mex"] = keyToDefID["adv_mex"] or defID
            else
                keyToDefID["mex"] = keyToDefID["mex"] or defID
            end
        end
        if def.windGenerator and def.windGenerator > 0 then
            keyToDefID["wind"] = keyToDefID["wind"] or defID
        end
        if def.isFactory and name:find("bot") then
            local tl = tonumber(cp.techlevel) or 1
            if tl >= 2 then
                keyToDefID["adv_bot_lab"] = keyToDefID["adv_bot_lab"] or defID
            else
                keyToDefID["bot_lab"] = keyToDefID["bot_lab"] or defID
            end
        end
        if def.isFactory and name:find("veh") then
            local tl = tonumber(cp.techlevel) or 1
            if tl >= 2 then
                keyToDefID["adv_vehicle_plant"] = keyToDefID["adv_vehicle_plant"] or defID
            else
                keyToDefID["vehicle_plant"] = keyToDefID["vehicle_plant"] or defID
            end
        end
        if def.isFactory and name:find("air") then
            local tl = tonumber(cp.techlevel) or 1
            if tl >= 2 then
                keyToDefID["adv_air_plant"] = keyToDefID["adv_air_plant"] or defID
            else
                keyToDefID["air_plant"] = keyToDefID["air_plant"] or defID
            end
        end
        if cp.energyconv_capacity then
            local tl = tonumber(cp.techlevel) or 1
            if tl >= 2 then
                keyToDefID["adv_converter"] = keyToDefID["adv_converter"] or defID
            else
                keyToDefID["converter"] = keyToDefID["converter"] or defID
            end
        end
        if cp.geothermal then
            keyToDefID["geo"] = keyToDefID["geo"] or defID
        end
        if def.energyMake and def.energyMake > 0 and def.isBuilding
           and not (def.windGenerator and def.windGenerator > 0) then
            if def.energyMake >= 200 then
                keyToDefID["fusion"] = keyToDefID["fusion"] or defID
            else
                keyToDefID["solar"] = keyToDefID["solar"] or defID
            end
        end
        -- Defense structures
        if def.isBuilding and def.weapons and #def.weapons > 0 then
            local cost = def.metalCost or 0
            if cost < 200 then
                keyToDefID["llt"] = keyToDefID["llt"] or defID
            elseif cost < 600 then
                keyToDefID["hlt"] = keyToDefID["hlt"] or defID
            end
        end
        -- Nuke silo
        if cp.stockpile_type and cp.stockpile_type == "nuclear" then
            keyToDefID["nuke_silo"] = keyToDefID["nuke_silo"] or defID
        end
        -- Nano turret (static builder)
        if def.isBuilding and def.buildSpeed and def.buildSpeed > 0 and not def.isFactory then
            keyToDefID["nano"] = keyToDefID["nano"] or defID
        end
    end
end

local function ResolveKey(key)
    if not key then return nil end
    return keyToDefID[key:lower()] or keyToDefID[key]
end

--------------------------------------------------------------------------------
-- Role resolution (uses prod.lua's Production state)
--------------------------------------------------------------------------------

local function FindBestUnitForRole(role)
    -- Use prod.lua's role mappings via Production state
    -- Fall back to searching UnitDefs if Production isn't available
    local bestDefID = nil
    local bestCost = 0

    for defID, def in pairs(UnitDefs) do
        if not def.isBuilding and def.canMove and not def.isFactory then
            local cp = def.customParams or {}
            local hasWeapons = def.weapons and #def.weapons > 0
            local speed = def.speed or 0
            local cost = def.metalCost or 0

            local unitRole = nil
            if def.buildSpeed and def.buildSpeed > 0 then
                unitRole = "constructor"
            elseif not hasWeapons then
                unitRole = "utility"
            elseif def.canFly then
                unitRole = "aircraft"
            else
                -- Ground combat classification (mirrors prod.lua)
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

                if isAA then unitRole = "aa"
                elseif speed > 90 and cost < 200 then unitRole = "raider"
                elseif speed > 60 and cost < 150 then unitRole = "scout"
                elseif cost > 500 then unitRole = "heavy_tank"
                elseif cost > 200 then unitRole = "assault"
                elseif speed < 40 then unitRole = "artillery"
                else
                    local mn = def.moveDef and def.moveDef.name and def.moveDef.name:lower() or ""
                    if mn:find("tank") or mn:find("veh") then
                        unitRole = "light_tank"
                    else
                        unitRole = "skirmisher"
                    end
                end
            end

            if unitRole == role and cost > bestCost then
                bestCost = cost
                bestDefID = defID
            end
        end
    end

    return bestDefID
end

--------------------------------------------------------------------------------
-- Goal creation
--------------------------------------------------------------------------------

local function CreateGoal(goalType, target)
    if not GOAL_TYPE_SET[goalType] then
        spEcho("[TotallyLegal Goals] Unknown goal type: " .. tostring(goalType))
        return nil
    end

    local goal = {
        id       = nextGoalID,
        goalType = goalType,
        status   = "pending",
        priority = #goalState.queue + 1,
        target   = target or {},
        funding  = { fraction = 0.3 },
        progress = {
            current    = 0,
            total      = target and (target.count or target.threshold or target.bpTarget or 1) or 1,
            startFrame = 0,
            lastProgressFrame = 0,
        },
    }

    -- Resolve defID for structure goals
    if goalType == "structure_build" or goalType == "structure_place" then
        if target.buildKey then
            goal.target.defID = ResolveKey(target.buildKey)
        end
    end

    -- Resolve defID for unit production goals
    if goalType == "unit_production" and target.role then
        goal.target.unitDefID = FindBestUnitForRole(target.role)
    end

    nextGoalID = nextGoalID + 1
    return goal
end

--------------------------------------------------------------------------------
-- Queue management (exposed via WG for GUI widget)
--------------------------------------------------------------------------------

local function AddGoal(goalType, target)
    local goal = CreateGoal(goalType, target)
    if not goal then return nil end

    goalState.queue[#goalState.queue + 1] = goal

    -- If no active goal, activate this one
    if not goalState.activeGoal then
        goal.status = "active"
        goal.progress.startFrame = spGetGameFrame()
        goal.progress.lastProgressFrame = spGetGameFrame()
        goalState.activeGoal = goal
    end

    spEcho("[TotallyLegal Goals] Added goal: " .. goalType ..
           " (ID=" .. goal.id .. ", queue pos=" .. #goalState.queue .. ")")
    return goal.id
end

local function RemoveGoal(goalID)
    for i, goal in ipairs(goalState.queue) do
        if goal.id == goalID then
            table.remove(goalState.queue, i)
            -- If we removed the active goal, advance
            if goalState.activeGoal and goalState.activeGoal.id == goalID then
                goalState.activeGoal = nil
                -- Find next pending
                for _, g in ipairs(goalState.queue) do
                    if g.status == "pending" then
                        g.status = "active"
                        g.progress.startFrame = spGetGameFrame()
                        g.progress.lastProgressFrame = spGetGameFrame()
                        goalState.activeGoal = g
                        break
                    end
                end
            end
            -- Renumber priorities
            for j, g in ipairs(goalState.queue) do
                g.priority = j
            end
            spEcho("[TotallyLegal Goals] Removed goal ID=" .. goalID)
            return true
        end
    end
    return false
end

local function MoveGoalUp(goalID)
    for i, goal in ipairs(goalState.queue) do
        if goal.id == goalID and i > 1 then
            goalState.queue[i], goalState.queue[i-1] = goalState.queue[i-1], goalState.queue[i]
            goalState.queue[i].priority = i
            goalState.queue[i-1].priority = i - 1
            return true
        end
    end
    return false
end

local function MoveGoalDown(goalID)
    for i, goal in ipairs(goalState.queue) do
        if goal.id == goalID and i < #goalState.queue then
            goalState.queue[i], goalState.queue[i+1] = goalState.queue[i+1], goalState.queue[i]
            goalState.queue[i].priority = i
            goalState.queue[i+1].priority = i + 1
            return true
        end
    end
    return false
end

local function AddGoalFromPreset(presetIndex)
    local preset = GOAL_PRESETS[presetIndex]
    if not preset then return nil end
    -- Deep copy target table
    local target = {}
    for k, v in pairs(preset.target) do target[k] = v end
    return AddGoal(preset.goalType, target)
end

--------------------------------------------------------------------------------
-- Completion checkers
--------------------------------------------------------------------------------

local function CountUnitsMatchingRole(role)
    local myUnits = TL.GetMyUnits()
    local count = 0
    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and not cls.isBuilding and not cls.isFactory then
            -- Check if this unit's role matches
            -- Use the same classification as prod.lua
            local def = UnitDefs[defID]
            if def then
                local hasWeapons = def.weapons and #def.weapons > 0
                local speed = def.speed or 0
                local cost = def.metalCost or 0
                local unitRole = nil

                if def.buildSpeed and def.buildSpeed > 0 then
                    unitRole = "constructor"
                elseif not hasWeapons then
                    unitRole = "utility"
                elseif def.canFly then
                    unitRole = "aircraft"
                else
                    local isAA = false
                    if def.weapons then
                        for _, w in ipairs(def.weapons) do
                            local wDefID = w.weaponDef
                            if wDefID and WeaponDefs[wDefID] and WeaponDefs[wDefID].canAttackGround == false then
                                isAA = true
                            end
                        end
                    end
                    if isAA then unitRole = "aa"
                    elseif speed > 90 and cost < 200 then unitRole = "raider"
                    elseif speed > 60 and cost < 150 then unitRole = "scout"
                    elseif cost > 500 then unitRole = "heavy_tank"
                    elseif cost > 200 then unitRole = "assault"
                    elseif speed < 40 then unitRole = "artillery"
                    else
                        local mn = def.moveDef and def.moveDef.name and def.moveDef.name:lower() or ""
                        if mn:find("tank") or mn:find("veh") then
                            unitRole = "light_tank"
                        else
                            unitRole = "skirmisher"
                        end
                    end
                end

                if unitRole == role then count = count + 1 end
            end
        end
    end
    return count
end

local function CountStructures(buildKey)
    local targetDefID = ResolveKey(buildKey)
    if not targetDefID then return 0 end
    local myUnits = TL.GetMyUnits()
    local count = 0
    for uid, defID in pairs(myUnits) do
        if defID == targetDefID then count = count + 1 end
    end
    return count
end

local function CheckUnitProduction(goal)
    local count = CountUnitsMatchingRole(goal.target.role)

    -- If destination is specified, only count units at that zone
    if goal.target.destination and WG.TotallyLegal.Zones then
        local zones = WG.TotallyLegal.Zones
        local assignments = zones.assignments or {}
        local destCount = 0
        local myUnits = TL.GetMyUnits()
        for uid, defID in pairs(myUnits) do
            if assignments[uid] == goal.target.destination then
                -- Check role match (simplified: count all assigned to dest that match type)
                -- For simplicity, count total of role regardless of zone
                -- Zone manager handles routing
            end
        end
        -- Use total count - zone routing is handled by overrides
    end

    goal.progress.current = count
    goal.progress.total = goal.target.count
    return count >= goal.target.count
end

local function CheckStructureBuild(goal)
    local count = CountStructures(goal.target.buildKey)
    goal.progress.current = count
    goal.progress.total = goal.target.count
    return count >= goal.target.count
end

local function CheckStructurePlace(goal)
    if not goal.target.defID or not goal.target.position then return false end

    local myUnits = TL.GetMyUnits()
    for uid, defID in pairs(myUnits) do
        if defID == goal.target.defID then
            local x, _, z = spGetUnitPosition(uid)
            if x then
                local dist = TL.Dist2D(x, z, goal.target.position[1], goal.target.position[2])
                if dist < 150 then
                    goal.progress.current = 1
                    goal.progress.total = 1
                    return true
                end
            end
        end
    end
    goal.progress.current = 0
    goal.progress.total = 1
    return false
end

local function CheckEconomyTarget(goal)
    local res = TL.GetTeamResources()
    local value = 0
    if goal.target.metric == "metalIncome" then
        value = res.metalIncome
    elseif goal.target.metric == "energyIncome" then
        value = res.energyIncome
    end
    goal.progress.current = value
    goal.progress.total = goal.target.threshold
    return value >= goal.target.threshold
end

local function CheckTechTransition(goal)
    local myUnits = TL.GetMyUnits()
    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.isFactory and cls.techLevel >= goal.target.techLevel then
            if not goal.target.factoryType then
                goal.progress.current = 1
                goal.progress.total = 1
                return true
            end
            local name = UnitDefs[defID] and (UnitDefs[defID].name or ""):lower() or ""
            if goal.target.factoryType == "bot" and name:find("bot") then
                goal.progress.current = 1; goal.progress.total = 1; return true
            end
            if goal.target.factoryType == "vehicle" and name:find("veh") then
                goal.progress.current = 1; goal.progress.total = 1; return true
            end
            if goal.target.factoryType == "air" and name:find("air") then
                goal.progress.current = 1; goal.progress.total = 1; return true
            end
        end
    end
    goal.progress.current = 0
    goal.progress.total = 1
    return false
end

local function CheckBuildpowerTarget(goal)
    local myUnits = TL.GetMyUnits()
    local totalBP = 0
    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.buildSpeed then
            totalBP = totalBP + cls.buildSpeed
        end
    end
    goal.progress.current = totalBP
    goal.progress.total = goal.target.bpTarget
    return totalBP >= goal.target.bpTarget
end

local COMPLETION_CHECKERS = {
    unit_production  = CheckUnitProduction,
    structure_build  = CheckStructureBuild,
    structure_place  = CheckStructurePlace,
    economy_target   = CheckEconomyTarget,
    tech_transition  = CheckTechTransition,
    buildpower_target = CheckBuildpowerTarget,
}

local function EvaluateGoalCompletion(goal)
    local checker = COMPLETION_CHECKERS[goal.goalType]
    if not checker then return false end
    return checker(goal)
end

--------------------------------------------------------------------------------
-- Queue advancement
--------------------------------------------------------------------------------

local function AdvanceQueue()
    if goalState.activeGoal then
        goalState.activeGoal.status = "completed"
        spEcho("[TotallyLegal Goals] Completed: " .. goalState.activeGoal.goalType ..
               " (ID=" .. goalState.activeGoal.id .. ")")
    end
    goalState.activeGoal = nil

    -- Find next pending goal
    for _, goal in ipairs(goalState.queue) do
        if goal.status == "pending" then
            goal.status = "active"
            goal.progress.startFrame = spGetGameFrame()
            goal.progress.lastProgressFrame = spGetGameFrame()
            goalState.activeGoal = goal
            spEcho("[TotallyLegal Goals] Activated: " .. goal.goalType ..
                   " (ID=" .. goal.id .. ")")
            return
        end
    end

    spEcho("[TotallyLegal Goals] All goals completed.")
end

--------------------------------------------------------------------------------
-- Override generation
--------------------------------------------------------------------------------

local function ClearOverrides()
    goalState.overrides.econBuildTask = nil
    goalState.overrides.projectConstructors = 0
    goalState.overrides.reserveMetal = 0
    goalState.overrides.reserveEnergy = 0
    goalState.overrides.prodOverride = nil
    goalState.overrides.unitDestination = nil
end

local function GenerateOverrides(goal)
    ClearOverrides()
    if not goal then return end

    local alloc = goalState.allocation
    local projectFrac = alloc.projectFunding / 100

    if goal.goalType == "unit_production" then
        -- Override production: queue the desired unit at factories
        local unitDefID = goal.target.unitDefID
        if unitDefID then
            local remaining = mathMax(0, goal.target.count - goal.progress.current)
            goalState.overrides.prodOverride = {
                unitDefID = unitDefID,
                count     = remaining,
                roleKey   = goal.target.role,
            }
        end
        goalState.overrides.projectConstructors = 0 -- no con override for unit goals

    elseif goal.goalType == "structure_build" then
        -- Override econ: assign constructors to build this structure
        local defID = goal.target.defID or ResolveKey(goal.target.buildKey)
        if defID then
            goalState.overrides.econBuildTask = {
                key    = goal.target.buildKey,
                defID  = defID,
                position = nil, -- auto-place
            }
            goalState.overrides.projectConstructors = projectFrac
        end

    elseif goal.goalType == "structure_place" then
        -- Override econ: assign constructors to build at specific position
        local defID = goal.target.defID or ResolveKey(goal.target.buildKey)
        if defID and goal.target.position then
            goalState.overrides.econBuildTask = {
                key      = goal.target.buildKey,
                defID    = defID,
                position = goal.target.position,
            }
            goalState.overrides.projectConstructors = projectFrac
        end
        -- Reserve resources for expensive structures
        local cost = defID and UnitDefs[defID] and UnitDefs[defID].metalCost or 0
        if cost > 1000 then
            goalState.overrides.reserveMetal = cost * 0.5
        end

    elseif goal.goalType == "economy_target" then
        -- Override econ: build appropriate economy structures
        local key = "mex"
        if goal.target.metric == "energyIncome" then
            key = "wind"
        end
        local defID = ResolveKey(key)
        if defID then
            goalState.overrides.econBuildTask = {
                key    = key,
                defID  = defID,
                position = nil,
            }
            goalState.overrides.projectConstructors = projectFrac
        end

    elseif goal.goalType == "tech_transition" then
        -- Override econ: build T2/T3 factory
        local key = "adv_bot_lab"
        if goal.target.factoryType == "vehicle" then
            key = "adv_vehicle_plant"
        elseif goal.target.factoryType == "air" then
            key = "adv_air_plant"
        end
        local defID = ResolveKey(key)
        if defID then
            goalState.overrides.econBuildTask = {
                key    = key,
                defID  = defID,
                position = nil,
            }
            goalState.overrides.projectConstructors = projectFrac
        end
        -- Reserve resources for expensive T2 factories
        local cost = defID and UnitDefs[defID] and UnitDefs[defID].metalCost or 0
        if cost > 500 then
            goalState.overrides.reserveMetal = cost * 0.3
        end

    elseif goal.goalType == "buildpower_target" then
        -- Override econ: build nanos or constructors
        local defID = ResolveKey("nano")
        if defID then
            goalState.overrides.econBuildTask = {
                key    = "nano",
                defID  = defID,
                position = nil,
            }
            goalState.overrides.projectConstructors = projectFrac
        end
    end

    -- Apply savings reserve
    if alloc.savingsRate > 0 then
        local res = TL.GetTeamResources()
        goalState.overrides.reserveMetal = mathMax(
            goalState.overrides.reserveMetal,
            res.metalStorage * (alloc.savingsRate / 100)
        )
        goalState.overrides.reserveEnergy = mathMax(
            goalState.overrides.reserveEnergy,
            res.energyStorage * (alloc.savingsRate / 100)
        )
    end
end

--------------------------------------------------------------------------------
-- Auto-mode resource allocation
--------------------------------------------------------------------------------

local function ComputeAutoAllocation()
    local alloc = goalState.allocation
    local econ = WG.TotallyLegal.Economy
    if not econ then return end

    local state = econ.state

    if state == "metal_stall" or state == "energy_stall" then
        -- Stalling: shift toward economy
        alloc.econVsUnits = mathMax(alloc.econVsUnits - 5, 20)
        alloc.projectFunding = mathMax(alloc.projectFunding - 5, 10)
    elseif state == "metal_float" or state == "energy_float" then
        -- Floating: shift toward army/projects
        alloc.econVsUnits = mathMin(alloc.econVsUnits + 5, 80)
        alloc.projectFunding = mathMin(alloc.projectFunding + 5, 50)
    else
        -- Balanced: trend toward 50/30
        if alloc.econVsUnits < 50 then alloc.econVsUnits = alloc.econVsUnits + 1
        elseif alloc.econVsUnits > 50 then alloc.econVsUnits = alloc.econVsUnits - 1 end
        if alloc.projectFunding < 30 then alloc.projectFunding = alloc.projectFunding + 1
        elseif alloc.projectFunding > 30 then alloc.projectFunding = alloc.projectFunding - 1 end
    end

    -- If active goal is expensive, boost project funding
    if goalState.activeGoal then
        local gt = goalState.activeGoal.goalType
        if gt == "tech_transition" or gt == "structure_place" then
            alloc.projectFunding = mathMin(alloc.projectFunding + 3, 60)
        end
    end
end

--------------------------------------------------------------------------------
-- Team resource sharing
--------------------------------------------------------------------------------

local function ApplyTeamShare()
    local alloc = goalState.allocation
    if alloc.teamShareRate <= 0 then return end

    local res = TL.GetTeamResources()
    local metalSurplus = res.metalCurrent - (res.metalStorage * (alloc.savingsRate / 100))
    local energySurplus = res.energyCurrent - (res.energyStorage * (alloc.savingsRate / 100))

    if metalSurplus > 0 then
        local shareAmount = metalSurplus * (alloc.teamShareRate / 100)
        if shareAmount > 1 and spShareResources then
            -- Share with ally team
            local myAllyTeam = spGetMyAllyTeamID()
            if myAllyTeam then
                spShareResources(myAllyTeam, "metal", shareAmount)
            end
        end
    end

    if energySurplus > 0 then
        local shareAmount = energySurplus * (alloc.teamShareRate / 100)
        if shareAmount > 1 and spShareResources then
            local myAllyTeam = spGetMyAllyTeamID()
            if myAllyTeam then
                spShareResources(myAllyTeam, "energy", shareAmount)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Stall detection
--------------------------------------------------------------------------------

local function CheckStalled(goal)
    local frame = spGetGameFrame()
    local prevProgress = goal.progress.current

    -- Track if progress changed
    if goal._lastCheckedProgress and goal._lastCheckedProgress ~= prevProgress then
        goal.progress.lastProgressFrame = frame
    end
    goal._lastCheckedProgress = prevProgress

    -- Stalled if no progress for stallCheckFrames
    if (frame - goal.progress.lastProgressFrame) > CFG.stallCheckFrames then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Map click placement (MousePress handler)
--------------------------------------------------------------------------------

function widget:MousePress(x, y, button)
    if not goalState.placementMode.active then return false end

    if button == 3 then
        -- Right click = cancel
        goalState.placementMode.active = false
        goalState.placementMode.buildKey = nil
        spEcho("[TotallyLegal Goals] Placement cancelled.")
        return true
    end

    if button == 1 then
        -- Left click = place
        local _, coords = Spring.TraceScreenRay(x, y, true)
        if coords then
            local wx, wy, wz = coords[1], coords[2], coords[3]
            local buildKey = goalState.placementMode.buildKey

            -- Create the placed structure goal
            AddGoal("structure_place", {
                buildKey = buildKey,
                position = { wx, wz },
                facing   = 0,
            })

            goalState.placementMode.active = false
            goalState.placementMode.buildKey = nil
            spEcho("[TotallyLegal Goals] Placed " .. buildKey .. " at (" ..
                   mathFloor(wx) .. ", " .. mathFloor(wz) .. ")")
            return true
        end
    end

    return false
end

local function StartPlacement(buildKey)
    if not buildKey then return end
    goalState.placementMode.active = true
    goalState.placementMode.buildKey = buildKey
    spEcho("[TotallyLegal Goals] Click on map to place " .. buildKey .. " (right-click to cancel)")
end

--------------------------------------------------------------------------------
-- Main GameFrame loop
--------------------------------------------------------------------------------

function widget:GameFrame(frame)
    if not TL then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end
    if frame < 90 then return end  -- skip first 3 seconds

    -- 1. Evaluate current active goal completion
    local active = goalState.activeGoal
    if active then
        if EvaluateGoalCompletion(active) then
            AdvanceQueue()
            active = goalState.activeGoal
        elseif CheckStalled(active) then
            active._stalled = true
        else
            active._stalled = false
        end
    else
        -- No active goal, try to find one
        for _, goal in ipairs(goalState.queue) do
            if goal.status == "pending" then
                goal.status = "active"
                goal.progress.startFrame = frame
                goal.progress.lastProgressFrame = frame
                goalState.activeGoal = goal
                active = goal
                break
            end
        end
    end

    -- 2. Generate overrides for the active goal
    GenerateOverrides(active)

    -- 3. Auto-mode resource allocation
    if goalState.allocation.autoMode then
        ComputeAutoAllocation()
    end

    -- 4. Team sharing
    if goalState.allocation.teamShareRate > 0 then
        ApplyTeamShare()
    end

    -- 5. Clean up completed goals from queue display
    -- (keep them for history but don't process)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Goals] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Goals] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildKeyTable()

    -- Expose goal state to other widgets and the GUI
    WG.TotallyLegal.Goals = goalState

    -- Expose API functions for the GUI widget
    WG.TotallyLegal.GoalsAPI = {
        AddGoal         = AddGoal,
        RemoveGoal      = RemoveGoal,
        MoveGoalUp      = MoveGoalUp,
        MoveGoalDown    = MoveGoalDown,
        AddGoalFromPreset = AddGoalFromPreset,
        StartPlacement  = StartPlacement,
        GetPresets      = function() return GOAL_PRESETS end,
        GetGoalTypes    = function() return GOAL_TYPES end,
        GetRoleOptions  = function() return ROLE_OPTIONS end,
        GetDestOptions  = function() return DESTINATION_OPTIONS end,
        GetMetricOptions = function() return METRIC_OPTIONS end,
        GetFactoryTypeOptions = function() return FACTORY_TYPE_OPTIONS end,
    }

    spEcho("[TotallyLegal Goals] Goal queue manager ready.")
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.Goals = nil
        WG.TotallyLegal.GoalsAPI = nil
    end
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    -- Serialize goals and allocation
    local savedGoals = {}
    for _, goal in ipairs(goalState.queue) do
        if goal.status ~= "completed" then
            savedGoals[#savedGoals + 1] = {
                goalType = goal.goalType,
                target   = goal.target,
                status   = goal.status,
            }
        end
    end

    return {
        allocation = goalState.allocation,
        goals      = savedGoals,
    }
end

function widget:SetConfigData(data)
    if data.allocation then
        for k, v in pairs(data.allocation) do
            if goalState.allocation[k] ~= nil then
                goalState.allocation[k] = v
            end
        end
    end

    if data.goals then
        for _, saved in ipairs(data.goals) do
            AddGoal(saved.goalType, saved.target)
        end
    end
end
