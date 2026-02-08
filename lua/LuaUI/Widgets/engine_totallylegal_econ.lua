-- TotallyLegal Economy Manager - Automatic economic balancing
-- Monitors resource flow, detects stalls/floats, assigns idle constructors to build tasks.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (provides key resolution, mex spots, build placement)

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
local spEcho                = Spring.Echo

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min

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
    -- Bug #10: only apply reserves when there's an active goal; stale reserves never clear otherwise
    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    if goals and goals.overrides and goals.activeGoal then
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

local function CanAfford(defID)
    local def = UnitDefs[defID]
    if not def then return false end
    local res = TL.GetTeamResources()
    local metalNeeded = (def.metalCost or 0) * 0.15
    local energyNeeded = (def.energyCost or 0) * 0.15
    return res.metalCurrent >= metalNeeded and res.energyCurrent >= energyNeeded
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
        if task and task.defID and UnitDefs[task.defID] and CanAfford(task.defID) then
            for _, conUID in ipairs(projectCons) do
                local cx, cy, cz = spGetUnitPosition(conUID)
                if cx then
                    local bx, bz
                    if task.position then
                        bx, bz = task.position[1], task.position[2]
                    else
                        bx, bz = TL.FindBuildPosition(conUID, task.defID, cx, cz)
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

    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local role = strat and strat.role or "balanced"
    local emergency = strat and strat.emergencyMode or "none"
    local state = econState.state

    if emergency == "mobilization" then return end

    -- Build candidate list in priority order
    local candidates = {}

    if emergency == "defend_base" then
        local defID = TL.ResolveKey("llt")
        if defID then candidates[#candidates + 1] = { key = "llt", defID = defID } end
    end

    if role == "eco" then
        local defID = TL.ResolveKey("mex")
        if defID then candidates[#candidates + 1] = { key = "mex", defID = defID } end
    end

    for _, bp in ipairs(BUILD_PRIORITY) do
        if bp.condition == "always" or bp.condition == state then
            local defID = TL.ResolveKey(bp.key)
            if defID then
                candidates[#candidates + 1] = { key = bp.key, defID = defID }
            end
        end
    end

    if role == "support" then
        local defID = TL.ResolveKey("radar")
        if defID then candidates[#candidates + 1] = { key = "radar", defID = defID } end
    end

    -- Get build area from map zones if defined
    local mapZones = WG.TotallyLegal and WG.TotallyLegal.MapZones
    local buildArea = mapZones and mapZones.buildingArea
    local buildOptions = { buildArea = buildArea or nil }
    local mexBuildOptions = { buildArea = buildArea or nil, useTieredPriority = true }

    -- For each idle constructor, try candidates in priority order
    for _, conUID in ipairs(normalCons) do
        local cx, cy, cz = spGetUnitPosition(conUID)
        if cx then
            for _, cand in ipairs(candidates) do
                if CanAfford(cand.defID) then
                    local opts = (cand.key == "mex") and mexBuildOptions or buildOptions
                    local bx, bz = TL.FindBuildPosition(conUID, cand.defID, cx, cz, opts)
                    if bx then
                        local by = spGetGroundHeight(bx, bz) or 0
                        spGiveOrderToUnit(conUID, -cand.defID, {bx, by, bz}, {})
                        -- Claim mex spots to prevent constructor collision
                        if cand.key == "mex" and TL.ClaimMexSpot then
                            TL.ClaimMexSpot(bx, bz, conUID)
                        end
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

    -- Expose economy state
    WG.TotallyLegal.Economy = econState
    econState._ready = true

    spEcho("[TotallyLegal Econ] Ready (uses core library for keys + mex spots)")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        AnalyzeEconomy()
        AssignIdleConstructors()
    end)
    if not ok then
        spEcho("[TotallyLegal Econ] GameFrame error: " .. tostring(err))
    end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitTeam ~= spGetMyTeamID() then return end
    if not TL then return end
    local def = UnitDefs[unitDefID]
    if def and def.extractsMetal and def.extractsMetal > 0 then
        local ux, _, uz = spGetUnitPosition(unitID)
        if ux and TL.ReleaseMexClaim then
            TL.ReleaseMexClaim(ux, uz)
        end
    end
end

function widget:Shutdown()
    if WG.TotallyLegal and WG.TotallyLegal.Economy then
        WG.TotallyLegal.Economy._ready = false
    end
end
