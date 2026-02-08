-- TotallyLegal Strategy Executor - Attack strategies and emergency modes
-- Executes named attack strategies (Creeping, Piercing, Fake Retreat, Anti-AA Raid)
-- and emergency modes (Defend Base, Mobilization) by commanding units directly.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua, engine_totallylegal_zone.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Strategy",
        desc      = "Attack strategy executor and emergency mode handler. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 207,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitCommands   = Spring.GetUnitCommands
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetGameFrame      = Spring.GetGameFrame
local spGetGroundHeight   = Spring.GetGroundHeight
local spGiveOrderToUnit   = Spring.GiveOrderToUnit
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spEcho              = Spring.Echo

local CMD_MOVE    = CMD.MOVE
local CMD_FIGHT   = CMD.FIGHT
local CMD_PATROL  = CMD.PATROL
local CMD_STOP    = CMD.STOP
local CMD_FIRE_STATE = CMD.FIRE_STATE

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency = 60,         -- every 60 frames (2s)
    creepingAdvance = 50,         -- elmos per advance step
    creepingInterval = 300,       -- frames between advances (10s)
    piercingAbortLoss = 0.5,     -- abort if >50% losses
    baitFraction = 0.3,           -- 30% of units as bait in fake retreat
    raidSpeedThreshold = 80,      -- minimum speed for raid units
    holdFireState = 0,            -- fire state: hold fire
    returnFireState = 1,          -- fire state: return fire
    fireAtWillState = 2,          -- fire state: fire at will
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local strategyExec = {
    activeStrategy = "none",
    activeEmergency = "none",
    initialized = false,

    -- Creeping Forward
    creeping = {
        lastAdvanceFrame = 0,
        initialCount = 0,
    },

    -- Piercing Assault
    piercing = {
        targetPoint = nil,      -- { x, z }
        initialCount = 0,
    },

    -- Fake Retreat
    fakeRetreat = {
        baitGroup = {},         -- array of unitIDs
        ambushGroup = {},       -- array of unitIDs
        phase = "idle",         -- "idle" | "bait_engage" | "retreating" | "ambush"
        killZone = nil,         -- { x, z }
        phaseStartFrame = 0,
    },

    -- Anti-AA Raid
    antiAARaid = {
        raidGroup = {},
        phase = "idle",         -- "idle" | "raiding" | "returning"
    },
}

--------------------------------------------------------------------------------
-- Helper: get alive front units from zone manager
--------------------------------------------------------------------------------

local function GetFrontUnits()
    local zones = WG.TotallyLegal and WG.TotallyLegal.Zones
    if not zones or not zones.assignments then return {} end

    local units = {}
    for uid, assignment in pairs(zones.assignments) do
        if assignment == "front" then
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                units[#units + 1] = uid
            end
        end
    end
    return units
end

local function GetRallyUnits()
    local zones = WG.TotallyLegal and WG.TotallyLegal.Zones
    if not zones or not zones.assignments then return {} end

    local units = {}
    for uid, assignment in pairs(zones.assignments) do
        if assignment == "rally" then
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                units[#units + 1] = uid
            end
        end
    end
    return units
end

local function GetAllCombatUnits()
    local front = GetFrontUnits()
    local rally = GetRallyUnits()
    for _, uid in ipairs(rally) do
        front[#front + 1] = uid
    end
    return front
end

local function GetZoneData()
    local zones = WG.TotallyLegal and WG.TotallyLegal.Zones
    if not zones then return nil end
    return zones
end

local function GetEnemyDirection()
    local zones = GetZoneData()
    if not zones or not zones.base or not zones.base.set then return { x = 0, z = 1 } end
    local mapCX = (Game.mapSizeX or 8192) / 2
    local mapCZ = (Game.mapSizeZ or 8192) / 2
    local dx = mapCX - zones.base.x
    local dz = mapCZ - zones.base.z
    local len = mathSqrt(dx * dx + dz * dz)
    if len > 0 then return { x = dx / len, z = dz / len } end
    return { x = 0, z = 1 }
end

local function OrderUnitsToFight(units, tx, tz)
    local ty = spGetGroundHeight(tx, tz) or 0
    for _, uid in ipairs(units) do
        spGiveOrderToUnit(uid, CMD_FIGHT, { tx, ty, tz }, {})
    end
end

local function OrderUnitsToMove(units, tx, tz)
    local ty = spGetGroundHeight(tx, tz) or 0
    for _, uid in ipairs(units) do
        spGiveOrderToUnit(uid, CMD_MOVE, { tx, ty, tz }, {})
    end
end

--------------------------------------------------------------------------------
-- Strategy: Creeping Forward
--------------------------------------------------------------------------------

local function ExecuteCreeping(frame)
    local zones = GetZoneData()
    if not zones or not zones.front or not zones.front.set then return end

    local creep = strategyExec.creeping
    local frontUnits = GetFrontUnits()

    -- Track initial count for abort threshold
    if creep.initialCount == 0 and #frontUnits > 0 then
        creep.initialCount = #frontUnits
    end

    -- Bug #20: Abort on heavy losses (60% casualties)
    if creep.initialCount > 0 and #frontUnits < creep.initialCount * 0.4 then
        spEcho("[TotallyLegal Strategy] Creeping forward aborted: heavy losses.")
        local rallyX = zones.rally and zones.rally.x or zones.base.x
        local rallyZ = zones.rally and zones.rally.z or zones.base.z
        OrderUnitsToMove(frontUnits, rallyX, rallyZ)
        -- Bug #21: mark retreating so zone manager doesn't re-send to front
        if zones.assignments then
            for _, uid in ipairs(frontUnits) do
                zones.assignments[uid] = "retreating"
            end
        end
        local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
        if strat then strat.attackStrategy = "none" end
        return
    end

    -- Advance front position periodically
    if frame - creep.lastAdvanceFrame >= CFG.creepingInterval then
        creep.lastAdvanceFrame = frame

        local dir = GetEnemyDirection()
        zones.front.x = zones.front.x + dir.x * CFG.creepingAdvance
        zones.front.z = zones.front.z + dir.z * CFG.creepingAdvance

        -- Clamp to map bounds
        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        zones.front.x = mathMax(64, mathMin(zones.front.x, mapSizeX - 64))
        zones.front.z = mathMax(64, mathMin(zones.front.z, mapSizeZ - 64))

        -- Re-issue fight orders to all front units
        OrderUnitsToFight(frontUnits, zones.front.x, zones.front.z)

        spEcho("[TotallyLegal Strategy] Creeping forward: front advanced to " ..
               mathFloor(zones.front.x) .. ", " .. mathFloor(zones.front.z))
    end
end

--------------------------------------------------------------------------------
-- Strategy: Piercing Assault
--------------------------------------------------------------------------------

local function ExecutePiercing(frame)
    local zones = GetZoneData()
    if not zones or not zones.front or not zones.front.set then return end

    local pierce = strategyExec.piercing

    -- Calculate target point if not set: midpoint between front and map center
    if not pierce.targetPoint then
        local dir = GetEnemyDirection()
        local mapCX = (Game.mapSizeX or 8192) / 2
        local mapCZ = (Game.mapSizeZ or 8192) / 2
        pierce.targetPoint = {
            x = (zones.front.x + mapCX) / 2,
            z = (zones.front.z + mapCZ) / 2,
        }
    end

    local frontUnits = GetFrontUnits()

    -- Track initial count
    if pierce.initialCount == 0 then
        pierce.initialCount = #frontUnits
    end

    -- Check for abort condition: >50% losses
    if pierce.initialCount > 0 and #frontUnits < pierce.initialCount * CFG.piercingAbortLoss then
        spEcho("[TotallyLegal Strategy] Piercing assault aborted: heavy losses.")
        -- Retreat to rally
        local rallyX = zones.rally and zones.rally.x or zones.base.x
        local rallyZ = zones.rally and zones.rally.z or zones.base.z
        OrderUnitsToMove(frontUnits, rallyX, rallyZ)
        -- Bug #21: mark retreating so zone manager doesn't re-send to front
        if zones.assignments then
            for _, uid in ipairs(frontUnits) do
                zones.assignments[uid] = "retreating"
            end
        end
        -- Reset and deactivate
        local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
        if strat then strat.attackStrategy = "none" end
        return
    end

    -- Concentrate all front units on the target point
    OrderUnitsToFight(frontUnits, pierce.targetPoint.x, pierce.targetPoint.z)
end

--------------------------------------------------------------------------------
-- Strategy: Fake Retreat
--------------------------------------------------------------------------------

local function ExecuteFakeRetreat(frame)
    local zones = GetZoneData()
    if not zones or not zones.front or not zones.front.set then return end

    local fr = strategyExec.fakeRetreat

    if fr.phase == "idle" then
        -- Initialize: split units into bait and ambush groups
        local frontUnits = GetFrontUnits()
        if #frontUnits < 4 then return end  -- need at least 4 units

        -- Set kill zone between rally and front
        if zones.rally and zones.rally.set then
            fr.killZone = {
                x = (zones.rally.x + zones.front.x) / 2,
                z = (zones.rally.z + zones.front.z) / 2,
            }
        else
            fr.killZone = { x = zones.front.x, z = zones.front.z }
        end

        -- Split: 30% bait, 70% ambush
        local baitCount = mathMax(1, mathFloor(#frontUnits * CFG.baitFraction))
        fr.baitGroup = {}
        fr.ambushGroup = {}
        for i, uid in ipairs(frontUnits) do
            if i <= baitCount then
                fr.baitGroup[#fr.baitGroup + 1] = uid
            else
                fr.ambushGroup[#fr.ambushGroup + 1] = uid
            end
        end

        -- Move ambush group to kill zone and hold fire
        OrderUnitsToMove(fr.ambushGroup, fr.killZone.x, fr.killZone.z)
        for _, uid in ipairs(fr.ambushGroup) do
            spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.holdFireState }, {})
        end

        -- Bait group: engage forward
        local dir = GetEnemyDirection()
        local engageX = zones.front.x + dir.x * 300
        local engageZ = zones.front.z + dir.z * 300
        OrderUnitsToFight(fr.baitGroup, engageX, engageZ)

        fr.phase = "bait_engage"
        fr.phaseStartFrame = frame
        spEcho("[TotallyLegal Strategy] Fake retreat: bait engaging, ambush positioning.")

    elseif fr.phase == "bait_engage" then
        -- Bug #20: abort if all bait units die
        local baitAlive = 0
        for _, uid in ipairs(fr.baitGroup) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then baitAlive = baitAlive + 1 end
        end
        if baitAlive == 0 then
            spEcho("[TotallyLegal Strategy] Fake retreat aborted: all bait units lost.")
            for _, uid in ipairs(fr.ambushGroup) do
                local health = spGetUnitHealth(uid)
                if health and health > 0 then
                    spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.fireAtWillState }, {})
                end
            end
            if fr.killZone then
                local dir = GetEnemyDirection()
                OrderUnitsToFight(fr.ambushGroup, fr.killZone.x + dir.x * 200, fr.killZone.z + dir.z * 200)
            end
            fr.phase = "idle"
            fr.baitGroup = {}
            fr.ambushGroup = {}
            local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
            if strat then strat.attackStrategy = "none" end
            return
        end
        -- Wait for bait to make contact (5 seconds), then retreat
        if frame - fr.phaseStartFrame >= 150 then
            -- Retreat bait toward kill zone
            if fr.killZone then
                OrderUnitsToMove(fr.baitGroup, fr.killZone.x, fr.killZone.z)
            end
            fr.phase = "retreating"
            fr.phaseStartFrame = frame
            spEcho("[TotallyLegal Strategy] Fake retreat: bait retreating to kill zone.")
        end

    elseif fr.phase == "retreating" then
        -- Bug #20: abort if all bait units die during retreat
        local baitAlive = 0
        for _, uid in ipairs(fr.baitGroup) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then baitAlive = baitAlive + 1 end
        end
        if baitAlive == 0 then
            spEcho("[TotallyLegal Strategy] Fake retreat aborted during retreat: all bait lost, springing early.")
            for _, uid in ipairs(fr.ambushGroup) do
                local health = spGetUnitHealth(uid)
                if health and health > 0 then
                    spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.fireAtWillState }, {})
                end
            end
            if fr.killZone then
                local dir = GetEnemyDirection()
                OrderUnitsToFight(fr.ambushGroup, fr.killZone.x + dir.x * 200, fr.killZone.z + dir.z * 200)
            end
            fr.phase = "ambush"
            fr.phaseStartFrame = frame
            return
        end
        -- Wait for bait to reach kill zone area (5 seconds), then spring ambush
        if frame - fr.phaseStartFrame >= 150 then
            -- Ambush group: fire at will and fight
            for _, uid in ipairs(fr.ambushGroup) do
                spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.fireAtWillState }, {})
            end
            if fr.killZone then
                -- Fight outward from kill zone toward enemy
                local dir = GetEnemyDirection()
                local fightX = fr.killZone.x + dir.x * 200
                local fightZ = fr.killZone.z + dir.z * 200
                OrderUnitsToFight(fr.ambushGroup, fightX, fightZ)
            end

            fr.phase = "ambush"
            fr.phaseStartFrame = frame
            spEcho("[TotallyLegal Strategy] Fake retreat: AMBUSH SPRUNG!")
        end

    elseif fr.phase == "ambush" then
        -- After ambush plays out (15 seconds), reset
        if frame - fr.phaseStartFrame >= 450 then
            -- Restore fire state for all units
            local allUnits = {}
            for _, uid in ipairs(fr.baitGroup) do allUnits[#allUnits + 1] = uid end
            for _, uid in ipairs(fr.ambushGroup) do allUnits[#allUnits + 1] = uid end
            for _, uid in ipairs(allUnits) do
                local health = spGetUnitHealth(uid)
                if health and health > 0 then
                    spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.fireAtWillState }, {})
                end
            end

            fr.phase = "idle"
            fr.baitGroup = {}
            fr.ambushGroup = {}
            spEcho("[TotallyLegal Strategy] Fake retreat: cycle complete, resetting.")

            -- Deactivate strategy
            local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
            if strat then strat.attackStrategy = "none" end
        end
    end
end

--------------------------------------------------------------------------------
-- Strategy: Anti-AA Raid
--------------------------------------------------------------------------------

local function IsAAUnit(defID)
    if not defID then return false end
    local def = UnitDefs[defID]
    if not def or not def.weapons then return false end
    for _, w in ipairs(def.weapons) do
        local wDefID = w.weaponDef
        if wDefID and WeaponDefs[wDefID] then
            if WeaponDefs[wDefID].canAttackGround == false then
                return true  -- AA weapon
            end
        end
    end
    return false
end

local function IsShieldUnit(defID)
    if not defID then return false end
    local def = UnitDefs[defID]
    if not def then return false end
    local cp = def.customParams or {}
    return cp.shield_power ~= nil or (def.shieldWeaponDef ~= nil)
end

local function IsJammerUnit(defID)
    if not defID then return false end
    local def = UnitDefs[defID]
    if not def then return false end
    return (def.jammerRadius or 0) > 0
end

local function ExecuteAntiAARaid(frame)
    local zones = GetZoneData()
    if not zones or not zones.front or not zones.front.set then return end

    local raid = strategyExec.antiAARaid

    if raid.phase == "idle" then
        -- Collect fast units from front and rally
        local allUnits = GetAllCombatUnits()
        raid.raidGroup = {}

        for _, uid in ipairs(allUnits) do
            local defID = spGetUnitDefID(uid)
            if defID then
                local cls = TL.GetUnitClass(defID)
                if cls and cls.maxSpeed >= CFG.raidSpeedThreshold and not cls.isBuilder then
                    raid.raidGroup[#raid.raidGroup + 1] = uid
                end
            end
        end

        if #raid.raidGroup < 2 then
            spEcho("[TotallyLegal Strategy] Anti-AA raid: not enough fast units.")
            local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
            if strat then strat.attackStrategy = "none" end
            return
        end

        -- Target: fight toward enemy base area (where AA likely is)
        local dir = GetEnemyDirection()
        local targetX = zones.front.x + dir.x * 800
        local targetZ = zones.front.z + dir.z * 800
        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        targetX = mathMax(64, mathMin(targetX, mapSizeX - 64))
        targetZ = mathMax(64, mathMin(targetZ, mapSizeZ - 64))

        OrderUnitsToFight(raid.raidGroup, targetX, targetZ)
        raid.phase = "raiding"
        spEcho("[TotallyLegal Strategy] Anti-AA raid: " .. #raid.raidGroup .. " fast units dispatched.")

    elseif raid.phase == "raiding" then
        -- Check if raid group is depleted (< 30% remaining)
        local alive = 0
        for _, uid in ipairs(raid.raidGroup) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then alive = alive + 1 end
        end

        if alive == 0 or alive < #raid.raidGroup * 0.3 then
            -- Retreat survivors to rally
            local rallyX = zones.rally and zones.rally.x or zones.base.x
            local rallyZ = zones.rally and zones.rally.z or zones.base.z
            for _, uid in ipairs(raid.raidGroup) do
                local health = spGetUnitHealth(uid)
                if health and health > 0 then
                    local ty = spGetGroundHeight(rallyX, rallyZ) or 0
                    spGiveOrderToUnit(uid, CMD_MOVE, { rallyX, ty, rallyZ }, {})
                end
            end
            raid.phase = "returning"
            spEcho("[TotallyLegal Strategy] Anti-AA raid: retreating, heavy losses.")
        end

    elseif raid.phase == "returning" then
        -- Once all idle or dead, reset
        local allIdle = true
        for _, uid in ipairs(raid.raidGroup) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                local cmdCount = spGetUnitCommands(uid, 0)
                if (cmdCount or 0) > 0 then
                    allIdle = false
                    break
                end
            end
        end

        if allIdle then
            raid.raidGroup = {}
            raid.phase = "idle"
            spEcho("[TotallyLegal Strategy] Anti-AA raid: complete.")
            local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
            if strat then strat.attackStrategy = "none" end
        end
    end
end

--------------------------------------------------------------------------------
-- Emergency: Defend Base
--------------------------------------------------------------------------------

local function ExecuteDefendBase(frame)
    local zones = GetZoneData()
    if not zones or not zones.base or not zones.base.set then return end

    -- Every update cycle, recall all units to base
    local allUnits = GetAllCombatUnits()
    OrderUnitsToFight(allUnits, zones.base.x, zones.base.z)
end

--------------------------------------------------------------------------------
-- Emergency: Mobilization
-- (Production handled by prod.lua reading Strategy.emergencyMode)
-- Zone.lua reads emergencyMode to drop rally threshold to 1
-- This executor just ensures existing front units keep fighting
--------------------------------------------------------------------------------

local function ExecuteMobilization(frame)
    local zones = GetZoneData()
    if not zones or not zones.front or not zones.front.set then return end

    -- Re-issue fight orders to idle front units
    local frontUnits = GetFrontUnits()
    for _, uid in ipairs(frontUnits) do
        local cmdCount = spGetUnitCommands(uid, 0)
        if (cmdCount or 0) == 0 then
            local fy = spGetGroundHeight(zones.front.x, zones.front.z) or 0
            spGiveOrderToUnit(uid, CMD_FIGHT, { zones.front.x, fy, zones.front.z }, {})
        end
    end
end

--------------------------------------------------------------------------------
-- Main update
--------------------------------------------------------------------------------

local function UpdateStrategy(frame)
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    if not strat then return end

    -- Emergency modes take priority
    local emergency = strat.emergencyMode or "none"
    strategyExec.activeEmergency = emergency

    if emergency == "defend_base" then
        ExecuteDefendBase(frame)
        return
    elseif emergency == "mobilization" then
        ExecuteMobilization(frame)
        -- Don't return — attack strategy can still run during mobilization
    end

    -- Attack strategies
    local attack = strat.attackStrategy or "none"

    -- Detect strategy change
    if attack ~= strategyExec.activeStrategy then
        -- Reset state for new strategy
        strategyExec.creeping.lastAdvanceFrame = 0
        strategyExec.creeping.initialCount = 0
        strategyExec.piercing.targetPoint = nil
        strategyExec.piercing.initialCount = 0
        strategyExec.fakeRetreat.phase = "idle"
        strategyExec.fakeRetreat.baitGroup = {}
        strategyExec.fakeRetreat.ambushGroup = {}
        strategyExec.antiAARaid.phase = "idle"
        strategyExec.antiAARaid.raidGroup = {}
        strategyExec.activeStrategy = attack

        if attack ~= "none" then
            spEcho("[TotallyLegal Strategy] Activated: " .. attack)
        end
    end

    if attack == "creeping" then
        ExecuteCreeping(frame)
    elseif attack == "piercing" then
        ExecutePiercing(frame)
    elseif attack == "fake_retreat" then
        ExecuteFakeRetreat(frame)
    elseif attack == "anti_aa_raid" then
        ExecuteAntiAARaid(frame)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Strategy] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Strategy] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    WG.TotallyLegal.StrategyExec = strategyExec
    strategyExec._ready = true

    spEcho("[TotallyLegal Strategy] Strategy executor ready.")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end
    if frame < 60 then return end

    local ok, err = pcall(function()
        UpdateStrategy(frame)
    end)
    if not ok then
        spEcho("[TotallyLegal Strategy] GameFrame error: " .. tostring(err))
    end
end

function widget:Shutdown()
    -- Restore fire state for any units we may have set to hold fire
    local fr = strategyExec.fakeRetreat
    if fr.ambushGroup then
        for _, uid in ipairs(fr.ambushGroup) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                spGiveOrderToUnit(uid, CMD_FIRE_STATE, { CFG.fireAtWillState }, {})
            end
        end
    end

    if WG.TotallyLegal and WG.TotallyLegal.StrategyExec then
        WG.TotallyLegal.StrategyExec._ready = false
    end
end
