-- TotallyLegal Auto Skirmish - Automatic kiting at optimal weapon range
-- Units automatically maintain optimal engagement distance: kite when too close, close when too far.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Auto Skirmish",
        desc      = "Auto-kiting: units maintain optimal weapon range. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 100,
        enabled   = false,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spGetGameFrame        = Spring.GetGameFrame
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetGroundHeight     = Spring.GetGroundHeight

local CMD_MOVE    = CMD.MOVE
local CMD_STOP    = CMD.STOP
local CMD_FIGHT   = CMD.FIGHT
local CMD_ATTACK  = CMD.ATTACK

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency = 5,       -- every N game frames
    kiteThreshold   = 0.80,    -- kite if enemy < 80% of max range
    holdMin         = 0.80,    -- hold position between 80-100% range
    holdMax         = 1.00,
    approachTarget  = 0.90,    -- close to 90% of max range
    kiteDistance    = 80,       -- additional distance to kite beyond current position
    maxManagedUnits = 40,      -- performance cap
    globalMode      = false,   -- false = selected units only, true = all combat units
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local managedUnits = {}     -- unitID -> { defID, range, speed }
local unitCooldowns = {}    -- unitID -> frame (last order issued)
local COOLDOWN_FRAMES = 10  -- don't re-order within 10 frames

-- Precomputed weapon ranges per defID
local weaponRanges = {}     -- defID -> maxRange

local function GetWeaponRange(defID)
    if weaponRanges[defID] then return weaponRanges[defID] end

    local def = UnitDefs[defID]
    if not def or not def.weapons then
        weaponRanges[defID] = 0
        return 0
    end

    local maxRange = 0
    for _, w in ipairs(def.weapons) do
        local wDefID = w.weaponDef
        if wDefID and WeaponDefs[wDefID] then
            local r = WeaponDefs[wDefID].range or 0
            if r > maxRange then maxRange = r end
        end
    end

    weaponRanges[defID] = maxRange
    return maxRange
end

--------------------------------------------------------------------------------
-- Unit management
--------------------------------------------------------------------------------

local function RefreshManagedUnits()
    managedUnits = {}

    if CFG.globalMode then
        local myUnits = TL.GetMyUnits()
        local count = 0
        for uid, defID in pairs(myUnits) do
            if count >= CFG.maxManagedUnits then break end
            local cls = TL.GetUnitClass(defID)
            if cls and cls.weaponCount > 0 and cls.canMove and not cls.isFactory and not cls.isBuilder then
                local range = GetWeaponRange(defID)
                if range > 0 then
                    managedUnits[uid] = { defID = defID, range = range, speed = cls.maxSpeed }
                    count = count + 1
                end
            end
        end
    else
        local selected = spGetSelectedUnits()
        if not selected then return end
        local count = 0
        for _, uid in ipairs(selected) do
            if count >= CFG.maxManagedUnits then break end
            local defID = spGetUnitDefID(uid)
            if defID then
                local cls = TL.GetUnitClass(defID)
                if cls and cls.weaponCount > 0 and cls.canMove and not cls.isFactory then
                    local range = GetWeaponRange(defID)
                    if range > 0 then
                        managedUnits[uid] = { defID = defID, range = range, speed = cls.maxSpeed }
                        count = count + 1
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Skirmish logic
--------------------------------------------------------------------------------

local function FindNearestEnemy(ux, uz, searchRadius)
    -- Use GetUnitsInCylinder if available, else GetUnitsInRectangle
    local enemies
    if Spring.GetUnitsInCylinder then
        enemies = Spring.GetUnitsInCylinder(ux, uz, searchRadius, Spring.ENEMY_UNITS)
    elseif Spring.GetUnitsInRectangle then
        enemies = Spring.GetUnitsInRectangle(
            ux - searchRadius, uz - searchRadius,
            ux + searchRadius, uz + searchRadius,
            false  -- not allied
        )
    end

    if not enemies or #enemies == 0 then return nil, nil, nil, math.huge end

    local bestUID, bestX, bestZ, bestDist = nil, nil, nil, math.huge

    for _, eid in ipairs(enemies) do
        if not Spring.IsUnitAllied(eid) then
            local ex, ey, ez = spGetUnitPosition(eid)
            if ex then
                local dx = ex - ux
                local dz = ez - uz
                local dist = mathSqrt(dx * dx + dz * dz)
                if dist < bestDist then
                    bestUID = eid
                    bestX = ex
                    bestZ = ez
                    bestDist = dist
                end
            end
        end
    end

    return bestUID, bestX, bestZ, bestDist
end

local function ProcessUnit(uid, data, frame)
    -- Check cooldown
    if unitCooldowns[uid] and (frame - unitCooldowns[uid]) < COOLDOWN_FRAMES then
        return
    end

    local ux, uy, uz = spGetUnitPosition(uid)
    if not ux then return end

    -- Bug #24: only kite units that are idle or actively engaging, not player-commanded
    local cmds = spGetUnitCommands(uid, 1)
    if cmds and #cmds > 0 then
        local cmdID = cmds[1].id
        if cmdID ~= CMD_FIGHT and cmdID ~= CMD_ATTACK then
            return  -- player gave a specific command, don't override
        end
    end

    local range = data.range
    local searchRadius = range * 1.5

    local enemyUID, ex, ez, dist = FindNearestEnemy(ux, uz, searchRadius)
    if not enemyUID then return end

    local ratio = dist / range

    if ratio < CFG.kiteThreshold then
        -- Too close: kite away
        local dx = ux - ex
        local dz = uz - ez
        local len = mathMax(mathSqrt(dx * dx + dz * dz), 1)
        local nx = dx / len
        local nz = dz / len

        local targetX = ux + nx * CFG.kiteDistance
        local targetZ = uz + nz * CFG.kiteDistance

        -- Clamp to map bounds
        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        targetX = mathMax(32, mathMin(targetX, mapSizeX - 32))
        targetZ = mathMax(32, mathMin(targetZ, mapSizeZ - 32))

        local targetY = spGetGroundHeight(targetX, targetZ) or 0

        spGiveOrderToUnit(uid, CMD_MOVE, {targetX, targetY, targetZ}, {})
        unitCooldowns[uid] = frame

    elseif ratio > CFG.holdMax then
        -- Too far: close in to optimal range
        local dx = ex - ux
        local dz = ez - uz
        local len = mathMax(mathSqrt(dx * dx + dz * dz), 1)
        local nx = dx / len
        local nz = dz / len

        local approachDist = dist - range * CFG.approachTarget
        local targetX = ux + nx * approachDist
        local targetZ = uz + nz * approachDist
        local targetY = spGetGroundHeight(targetX, targetZ) or 0

        spGiveOrderToUnit(uid, CMD_MOVE, {targetX, targetY, targetZ}, {})
        unitCooldowns[uid] = frame
    end
    -- Between kiteThreshold and holdMax: do nothing, let weapon fire
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Skirmish] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[TotallyLegal Skirmish] Automation not allowed in this game mode. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Yield to Puppeteer if active (Smart Move replaces skirmish behavior)
    if WG.TotallyLegal.PuppeteerActive then
        Spring.Echo("[TotallyLegal Skirmish] Puppeteer active, yielding to Puppeteer Smart Move.")
        widgetHandler:RemoveWidget(self)
        return
    end

    Spring.Echo("[TotallyLegal Skirmish] Enabled (PvE mode). Managing " ..
                (CFG.globalMode and "all combat units" or "selected units") .. ".")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        RefreshManagedUnits()

        for uid, data in pairs(managedUnits) do
            -- Verify unit still exists
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                ProcessUnit(uid, data, frame)
            end
        end

        -- Cleanup stale cooldowns
        for uid, cd in pairs(unitCooldowns) do
            if frame - cd > 300 then  -- 10 seconds
                unitCooldowns[uid] = nil
            end
        end
    end)
    if not ok then
        Spring.Echo("[TotallyLegal Skirmish] GameFrame error: " .. tostring(err))
    end
end
