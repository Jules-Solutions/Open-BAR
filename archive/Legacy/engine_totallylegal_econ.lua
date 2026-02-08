-- TotallyLegal Economy Manager - Automatic economic balancing
-- Monitors resource flow, detects stalls/floats, assigns idle constructors to build tasks.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Economy",
        desc      = "Economy manager: auto-balance M/E, assign idle constructors. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 202,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitIsBuilding   = Spring.GetUnitIsBuilding
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetGameFrame        = Spring.GetGameFrame
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spTestBuildOrder      = Spring.TestBuildOrder
local spEcho                = Spring.Echo

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local mathCos   = math.cos
local mathSin   = math.sin

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 30,     -- every 30 frames (1s)
    stallThreshold   = 0.05,   -- < 5% storage = stalling
    floatThreshold   = 0.80,   -- > 80% storage = floating
    buildSpacing     = 80,
    maxSpiralSteps   = 20,
}

-- Priority queue: what to build when
local BUILD_PRIORITY = {
    { key = "mex",       condition = "metal_stall",    priority = 100 },
    { key = "wind",      condition = "energy_stall",   priority = 90 },
    { key = "solar",     condition = "energy_stall",   priority = 85 },
    { key = "mex",       condition = "always",         priority = 70 },
    { key = "wind",      condition = "always",         priority = 50 },
    { key = "converter", condition = "energy_float",   priority = 40 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local econState = {
    state = "balanced",       -- "balanced", "metal_stall", "energy_stall", "metal_float", "energy_float"
    metalRate = 0,
    energyRate = 0,
    recommendation = "none",
}

local constructorAssignments = {}  -- constructorUID -> "assigned" (tracking busy cons)
local keyToDefID = {}
local cachedMexSpots = nil  -- cached mex positions for the map

--------------------------------------------------------------------------------
-- Unit key resolution (simplified)
--------------------------------------------------------------------------------

local function BuildKeyTable(faction)
    keyToDefID = {}

    -- Filter out wrong-faction units
    local skipPrefix = nil
    if faction == "armada" then skipPrefix = "^cor"
    elseif faction == "cortex" then skipPrefix = "^arm"
    end

    for defID, def in pairs(UnitDefs) do
        local name = (def.name or ""):lower()
        local cp = def.customParams or {}

        -- Skip units belonging to the other faction
        if skipPrefix and name:find(skipPrefix) then
            -- skip
        else
            if def.extractsMetal and def.extractsMetal > 0 and (tonumber(cp.techlevel) or 1) < 2 then
                keyToDefID["mex"] = keyToDefID["mex"] or defID
            end
            if def.windGenerator and def.windGenerator > 0 then
                keyToDefID["wind"] = keyToDefID["wind"] or defID
            end
            if def.energyMake and def.energyMake > 0 and def.isBuilding and def.energyMake < 200 and not (def.windGenerator and def.windGenerator > 0) then
                keyToDefID["solar"] = keyToDefID["solar"] or defID
            end
            if cp.energyconv_capacity and (tonumber(cp.techlevel) or 1) < 2 then
                keyToDefID["converter"] = keyToDefID["converter"] or defID
            end
            -- Defense turrets (cheap T1 buildings with weapons)
            if def.isBuilding and def.weapons and #def.weapons > 0 and not def.isFactory then
                local cost = def.metalCost or 0
                if cost < 200 and (tonumber(cp.techlevel) or 1) < 2 then
                    keyToDefID["llt"] = keyToDefID["llt"] or defID
                end
            end
            -- Radar
            if def.isBuilding and def.radarRadius and def.radarRadius > 0 then
                keyToDefID["radar"] = keyToDefID["radar"] or defID
            end
        end
    end
end

local function ResolveKey(key)
    return keyToDefID[key:lower()]
end

--------------------------------------------------------------------------------
-- Economy analysis
--------------------------------------------------------------------------------

local function AnalyzeEconomy()
    local res = TL.GetTeamResources()

    econState.metalRate = res.metalIncome - res.metalExpend
    econState.energyRate = res.energyIncome - res.energyExpend

    local metalFill = res.metalCurrent / res.metalStorage
    local energyFill = res.energyCurrent / res.energyStorage

    if metalFill < CFG.stallThreshold then
        econState.state = "metal_stall"
        econState.recommendation = "build_mex"
    elseif energyFill < CFG.stallThreshold then
        econState.state = "energy_stall"
        econState.recommendation = "build_energy"
    elseif metalFill > CFG.floatThreshold then
        econState.state = "metal_float"
        econState.recommendation = "spend_metal"
    elseif energyFill > CFG.floatThreshold then
        econState.state = "energy_float"
        econState.recommendation = "build_converter"
    else
        econState.state = "balanced"
        econState.recommendation = "expand"
    end

    -- Goal override: respect reserve thresholds (suppress float while banking)
    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    if goals and goals.overrides then
        local reserveM = goals.overrides.reserveMetal or 0
        local reserveE = goals.overrides.reserveEnergy or 0
        if reserveM > 0 and res.metalCurrent < reserveM and econState.state == "metal_float" then
            econState.state = "balanced"
            econState.recommendation = "bank_metal"
        end
        if reserveE > 0 and res.energyCurrent < reserveE and econState.state == "energy_float" then
            econState.state = "balanced"
            econState.recommendation = "bank_energy"
        end
    end
end

--------------------------------------------------------------------------------
-- Constructor management
--------------------------------------------------------------------------------

local function FindIdleConstructors()
    local idle = {}
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.isBuilder and not cls.isFactory then
            local building = spGetUnitIsBuilding(uid)
            local cmdCount = spGetUnitCommands(uid, 0)
            if not building and (cmdCount or 0) == 0 then
                idle[#idle + 1] = uid
            end
        end
    end

    return idle
end

local function LoadMexSpots()
    if cachedMexSpots then return end

    -- Try Spring API first
    if Spring.GetMetalMapSpots then
        local raw = Spring.GetMetalMapSpots()
        if raw and #raw > 0 then
            cachedMexSpots = {}
            for _, spot in ipairs(raw) do
                local sx = spot.x or spot[1]
                local sz = spot.z or spot[3] or spot[2]
                if sx and sz then
                    cachedMexSpots[#cachedMexSpots + 1] = { x = sx, z = sz }
                end
            end
            if #cachedMexSpots > 0 then
                spEcho("[TotallyLegal Econ] Mex spots from API: " .. #cachedMexSpots)
                return
            end
        end
    end

    -- Fallback: grid scan with TestBuildOrder
    cachedMexSpots = {}
    local mexDefID = ResolveKey("mex")
    if not mexDefID then return end

    local mapX = Game.mapSizeX or 8192
    local mapZ = Game.mapSizeZ or 8192
    local step = 64

    for gx = step, mapX - step, step do
        for gz = step, mapZ - step, step do
            local gy = spGetGroundHeight(gx, gz) or 0
            local result = spTestBuildOrder(mexDefID, gx, gy, gz, 0)
            if result and result >= 2 then
                cachedMexSpots[#cachedMexSpots + 1] = { x = gx, z = gz }
            end
        end
    end

    spEcho("[TotallyLegal Econ] Mex spots from grid scan: " .. #cachedMexSpots)
end

local function FindBuildPosition(builderID, defID, baseX, baseZ)
    local def = UnitDefs[defID]
    if not def then return nil, nil end

    -- Mex: find nearest buildable cached spot
    if def.extractsMetal and def.extractsMetal > 0 then
        LoadMexSpots()
        local bestDist = math.huge
        local bestX, bestZ = nil, nil
        for _, spot in ipairs(cachedMexSpots) do
            local dx = spot.x - baseX
            local dz = spot.z - baseZ
            local dist = mathSqrt(dx * dx + dz * dz)
            if dist < bestDist then
                local gy = spGetGroundHeight(spot.x, spot.z) or 0
                local result = spTestBuildOrder(defID, spot.x, gy, spot.z, 0)
                if result and result > 0 then
                    bestDist = dist
                    bestX = spot.x
                    bestZ = spot.z
                end
            end
        end
        if bestX then return bestX, bestZ end
        return nil, nil
    end

    -- Other: spiral placement
    -- Constrain to building area if defined
    local mapZones = WG.TotallyLegal and WG.TotallyLegal.MapZones
    local buildArea = mapZones and mapZones.buildingArea
    if buildArea and buildArea.defined then
        baseX = buildArea.center.x
        baseZ = buildArea.center.z
    end

    for step = 0, CFG.maxSpiralSteps do
        local angle = step * 2.4
        local radius = CFG.buildSpacing * (1 + step * 0.3)
        local tx = baseX + mathCos(angle) * radius
        local tz = baseZ + mathSin(angle) * radius

        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        tx = mathMax(64, mathMin(tx, mapSizeX - 64))
        tz = mathMax(64, mathMin(tz, mapSizeZ - 64))

        -- Skip positions outside building area
        local inArea = true
        if buildArea and buildArea.defined then
            local dx = tx - buildArea.center.x
            local dz = tz - buildArea.center.z
            if (dx * dx + dz * dz) > (buildArea.radius * buildArea.radius) then
                inArea = false
            end
        end

        if inArea then
            local result = spTestBuildOrder(defID, tx, spGetGroundHeight(tx, tz) or 0, tz, 0)
            if result and result > 0 then
                return tx, tz
            end
        end
    end

    return nil, nil
end

local function CanAfford(defID)
    local def = UnitDefs[defID]
    if not def then return false end
    local res = TL.GetTeamResources()
    -- Need at least 15% of cost to start (same buffer as build engine)
    local metalNeeded = (def.metalCost or 0) * 0.15
    local energyNeeded = (def.energyCost or 0) * 0.15
    return res.metalCurrent >= metalNeeded and res.energyCurrent >= energyNeeded
end

local function GetBuildTask()
    local state = econState.state
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local role = strat and strat.role or "balanced"
    local emergency = strat and strat.emergencyMode or "none"

    -- Emergency: mobilization → skip econ building (factories handle everything)
    if emergency == "mobilization" then
        return nil, nil
    end

    -- Emergency: defend_base → prioritize defense structures
    if emergency == "defend_base" then
        local defID = ResolveKey("llt")
        if defID then return "llt", defID end
    end

    -- Role: eco → always prioritize mex first
    if role == "eco" then
        local defID = ResolveKey("mex")
        if defID then return "mex", defID end
    end

    -- Standard priority iteration
    for _, bp in ipairs(BUILD_PRIORITY) do
        if bp.condition == "always" or bp.condition == state then
            local defID = ResolveKey(bp.key)
            if defID then
                return bp.key, defID
            end
        end
    end

    -- Role: support → fallback to radar/jammer
    if role == "support" then
        local defID = ResolveKey("radar")
        if defID then return "radar", defID end
    end

    return nil, nil
end

local function SplitByBPFraction(idle, fraction)
    if fraction <= 0 or #idle == 0 then return {}, idle end
    if fraction >= 1 then return idle, {} end

    local totalBP = 0
    for _, uid in ipairs(idle) do
        local defID = TL.GetMyUnits()[uid]
        local cls = defID and TL.GetUnitClass(defID)
        totalBP = totalBP + (cls and cls.buildSpeed or 0)
    end

    local targetBP = totalBP * fraction
    local assignedBP = 0
    local projectCons = {}
    local normalCons = {}

    for _, uid in ipairs(idle) do
        local defID = TL.GetMyUnits()[uid]
        local cls = defID and TL.GetUnitClass(defID)
        local bp = cls and cls.buildSpeed or 0
        if assignedBP < targetBP then
            projectCons[#projectCons + 1] = uid
            assignedBP = assignedBP + bp
        else
            normalCons[#normalCons + 1] = uid
        end
    end

    return projectCons, normalCons
end

local function AssignIdleConstructors()
    local idle = FindIdleConstructors()
    if #idle == 0 then return end

    -- Check for goal overrides: split constructors between project and normal
    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    local projectFrac = (goals and goals.overrides and goals.overrides.projectConstructors) or 0
    local projectCons, normalCons = SplitByBPFraction(idle, projectFrac)

    -- Assign project constructors to goal's build task
    if #projectCons > 0 and goals and goals.overrides and goals.overrides.econBuildTask then
        local task = goals.overrides.econBuildTask
        if task.defID and CanAfford(task.defID) then
            for _, conUID in ipairs(projectCons) do
                local cx, cy, cz = spGetUnitPosition(conUID)
                if cx then
                    local bx, bz
                    if task.position then
                        bx, bz = task.position[1], task.position[2]
                    else
                        bx, bz = FindBuildPosition(conUID, task.defID, cx, cz)
                    end
                    if bx then
                        local by = spGetGroundHeight(bx, bz) or 0
                        spGiveOrderToUnit(conUID, -task.defID, {bx, by, bz}, {})
                    end
                end
            end
        end
    end

    -- Assign normal constructors via standard priority system
    if #normalCons == 0 then return end

    -- Build candidate list in priority order (role + econ state)
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local role = strat and strat.role or "balanced"
    local emergency = strat and strat.emergencyMode or "none"
    local state = econState.state

    if emergency == "mobilization" then return end

    local candidates = {}

    if emergency == "defend_base" then
        local defID = ResolveKey("llt")
        if defID then candidates[#candidates + 1] = { key = "llt", defID = defID } end
    end

    if role == "eco" then
        local defID = ResolveKey("mex")
        if defID then candidates[#candidates + 1] = { key = "mex", defID = defID } end
    end

    for _, bp in ipairs(BUILD_PRIORITY) do
        if bp.condition == "always" or bp.condition == state then
            local defID = ResolveKey(bp.key)
            if defID then
                candidates[#candidates + 1] = { key = bp.key, defID = defID }
            end
        end
    end

    if role == "support" then
        local defID = ResolveKey("radar")
        if defID then candidates[#candidates + 1] = { key = "radar", defID = defID } end
    end

    -- For each idle constructor, try candidates in priority order
    -- If the top-priority build can't be placed, fall through to the next one
    for _, conUID in ipairs(normalCons) do
        local cx, cy, cz = spGetUnitPosition(conUID)
        if cx then
            for _, cand in ipairs(candidates) do
                if CanAfford(cand.defID) then
                    local bx, bz = FindBuildPosition(conUID, cand.defID, cx, cz)
                    if bx then
                        local by = spGetGroundHeight(bx, bz) or 0
                        spGiveOrderToUnit(conUID, -cand.defID, {bx, by, bz}, {})
                        break  -- assigned, move to next constructor
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
        spEcho("[TotallyLegal Econ] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Econ] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildKeyTable("unknown")  -- faction unknown at Initialize; rebuilt at GameStart

    -- Expose economy state
    WG.TotallyLegal.Economy = econState

    spEcho("[TotallyLegal Econ] Economy manager ready (keys rebuilt at GameStart).")
end

function widget:GameStart()
    -- Detect faction and rebuild key table with correct faction filter
    local faction = TL.GetFaction()
    if faction == "unknown" then
        -- Core lib might not have detected yet; check our own units
        local myUnits = TL.GetMyUnits()
        for uid, defID in pairs(myUnits) do
            if defID and UnitDefs[defID] then
                local name = (UnitDefs[defID].name or ""):lower()
                if name:find("^arm") then faction = "armada"; break
                elseif name:find("^cor") then faction = "cortex"; break end
            end
        end
    end

    BuildKeyTable(faction)
    cachedMexSpots = nil  -- rebuild with correct faction mex defID

    spEcho("[TotallyLegal Econ] Faction: " .. faction ..
           " | mex=" .. tostring(keyToDefID["mex"] ~= nil) ..
           " wind=" .. tostring(keyToDefID["wind"] ~= nil) ..
           " solar=" .. tostring(keyToDefID["solar"] ~= nil))
end

function widget:GameFrame(frame)
    if not TL then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    AnalyzeEconomy()
    AssignIdleConstructors()
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.Economy = nil
    end
end
