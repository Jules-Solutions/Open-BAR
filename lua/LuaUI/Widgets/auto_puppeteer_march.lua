-- Unit Puppeteer: March - Speed-matched marching, scatter spacing, convergent range walking
-- Part of the Puppeteer family. Reads state from WG.TotallyLegal.Puppeteer.
-- Validates scatter/range-walk positions with TestMoveOrder when available.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: auto_puppeteer_core.lua (WG.TotallyLegal.Puppeteer)
--
-- References:
--   Spring.TestMoveOrder(defID, x, y, z) -> bool

function widget:GetInfo()
    return {
        name      = "Puppeteer March",
        desc      = "Speed-matched march, scatter spacing, convergent range walking. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 108,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetGameFrame        = Spring.GetGameFrame
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spGetUnitCommands     = Spring.GetUnitCommands
local spEcho                = Spring.Echo
local spTestMoveOrder       = Spring.TestMoveOrder

local CMD_MOVE                = CMD.MOVE
local CMD_STOP                = CMD.STOP
local CMD_SET_WANTED_MAX_SPEED = 70  -- CMD code for speed limiting

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min
local mathAbs  = math.abs

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local PUP = nil  -- WG.TotallyLegal.Puppeteer

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    scatterFrequency    = 10,    -- process scatter every N frames
    scatterMaxIterations = 3,    -- max repulsion iterations per cycle
    scatterNudgeDistance = 8,    -- elmos per iteration
    scatterMaxUnits     = 60,    -- performance cap for scatter
    marchCleanupFrames  = 600,   -- cleanup stale march groups after 20s
    marchUpdateFrequency = 5,    -- update march waypoints every N frames
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local marchGroups = {}       -- groupID -> { unitIDs, destX, destZ, minSpeed, frame }
local nextGroupID = 1
local scatterLastProcessed = {}  -- unitID -> frame

-- Feature detection (set at init)
local hasTestMove = false

-- Test if CMD_SET_WANTED_MAX_SPEED is supported
local supportsMaxSpeedCmd = nil

local function TestMaxSpeedSupport()
    if supportsMaxSpeedCmd ~= nil then return supportsMaxSpeedCmd end
    supportsMaxSpeedCmd = false  -- CMD 70 removed from Recoil engine
    return false
end

--------------------------------------------------------------------------------
-- Utility: Distance and vector math
--------------------------------------------------------------------------------

local function Distance2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return mathSqrt(dx * dx + dz * dz)
end

local function Normalize2D(x, z)
    local len = mathSqrt(x * x + z * z)
    if len < 0.001 then return 0, 0 end
    return x / len, z / len
end

local function ClampToMap(x, z)
    local msx = Game.mapSizeX or 8192
    local msz = Game.mapSizeZ or 8192
    x = mathMax(32, mathMin(x, msx - 32))
    z = mathMax(32, mathMin(z, msz - 32))
    return x, z
end

local function ValidatePosition(x, z, unitDefID)
    x, z = ClampToMap(x, z)
    if not hasTestMove or not unitDefID then return x, z end

    local y = spGetGroundHeight(x, z)
    if not y then return x, z end

    local valid = spTestMoveOrder(unitDefID, x, y, z)
    if valid then return x, z end

    -- Try small offsets
    for offset = 20, 60, 20 do
        for _, dz in ipairs({ offset, -offset, 0, 0 }) do
            for _, dx in ipairs({ 0, 0, offset, -offset }) do
                if dx ~= 0 or dz ~= 0 then
                    local tx, tz = ClampToMap(x + dx, z + dz)
                    local ty = spGetGroundHeight(tx, tz)
                    if ty and spTestMoveOrder(unitDefID, tx, ty, tz) then
                        return tx, tz
                    end
                end
            end
        end
    end

    return x, z  -- fallback to original
end

local function GetAveragePosition(unitIDs)
    local sumX, sumZ, count = 0, 0, 0
    for _, uid in ipairs(unitIDs) do
        local ux, _, uz = spGetUnitPosition(uid)
        if ux then
            sumX = sumX + ux
            sumZ = sumZ + uz
            count = count + 1
        end
    end
    if count == 0 then return 0, 0 end
    return sumX / count, sumZ / count
end

--------------------------------------------------------------------------------
-- Feature 1: Speed-Matched March
--------------------------------------------------------------------------------

local function FindMinSpeed(unitIDs)
    if not PUP or not PUP.units then return nil end

    local minSpeed = math.huge
    for _, uid in ipairs(unitIDs) do
        local udata = PUP.units[uid]
        if udata and udata.speed then
            minSpeed = mathMin(minSpeed, udata.speed)
        end
    end

    if minSpeed == math.huge then return nil end
    return minSpeed
end

local function StartMarchGroup(unitIDs, destX, destZ, frame)
    if not unitIDs or #unitIDs == 0 then return end

    local minSpeed = FindMinSpeed(unitIDs)
    if not minSpeed then return end

    local groupID = nextGroupID
    nextGroupID = nextGroupID + 1

    marchGroups[groupID] = {
        unitIDs = unitIDs,
        destX = destX,
        destZ = destZ,
        minSpeed = minSpeed,
        frame = frame,
    }

    -- Apply speed limit to all units in group
    if TestMaxSpeedSupport() then
        for _, uid in ipairs(unitIDs) do
            local udata = PUP.units[uid]
            if udata and udata.speed > minSpeed then
                -- Set max speed to match slowest unit
                spGiveOrderToUnit(uid, CMD_SET_WANTED_MAX_SPEED, {minSpeed}, {})
            end
        end
    end

    return groupID
end

local function UpdateMarchGroups(frame)
    for groupID, group in pairs(marchGroups) do
        local allArrived = true
        local activeCount = 0

        for _, uid in ipairs(group.unitIDs) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                local ux, _, uz = spGetUnitPosition(uid)
                if ux then
                    local dist = Distance2D(ux, uz, group.destX, group.destZ)
                    if dist > 50 then  -- tolerance: 50 elmos
                        allArrived = false
                        activeCount = activeCount + 1
                    end
                end
            end
        end

        -- Cleanup if all arrived or group is stale
        if allArrived or activeCount == 0 or (frame - group.frame) > CFG.marchCleanupFrames then
            -- Release speed limits
            if TestMaxSpeedSupport() then
                for _, uid in ipairs(group.unitIDs) do
                    local health = spGetUnitHealth(uid)
                    if health and health > 0 then
                        local udata = PUP.units[uid]
                        if udata then
                            -- Reset to original max speed
                            spGiveOrderToUnit(uid, CMD_SET_WANTED_MAX_SPEED, {udata.speed}, {})
                        end
                    end
                end
            end

            marchGroups[groupID] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Feature 2: Scatter / Anti-Splash Spacing
--------------------------------------------------------------------------------

local function ProcessScatter(frame)
    if not PUP or not PUP.units then return end
    if not PUP.toggles.scatter then return end

    local scatterDist = PUP.toggles.scatterDistance or 120
    local units = {}
    local count = 0

    -- Collect units to scatter (idle/moving only, not dodging, not too recently processed)
    for uid, udata in pairs(PUP.units) do
        if count >= CFG.scatterMaxUnits then break end

        if udata.state ~= "dodging" then
            local lastProcessed = scatterLastProcessed[uid] or 0
            if (frame - lastProcessed) >= CFG.scatterFrequency then
                -- Only scatter idle units or units with just a move command
                local cmds = spGetUnitCommands(uid, 1)
                local isIdle = (not cmds or #cmds == 0)
                local isMoving = (cmds and #cmds > 0 and cmds[1].id == CMD_MOVE)
                if isIdle or isMoving then
                    local health = spGetUnitHealth(uid)
                    if health and health > 0 then
                        local ux, uy, uz = spGetUnitPosition(uid)
                        if ux then
                            units[#units + 1] = { uid = uid, x = ux, y = uy, z = uz, data = udata }
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    if #units == 0 then return end

    -- Repulsion solver
    for iteration = 1, CFG.scatterMaxIterations do
        local moved = false

        for i = 1, #units do
            local u1 = units[i]
            local forceX, forceZ = 0, 0

            -- Check against other units
            for j = 1, #units do
                if i ~= j then
                    local u2 = units[j]
                    local dx = u1.x - u2.x
                    local dz = u1.z - u2.z
                    local dist = mathSqrt(dx * dx + dz * dz)

                    if dist < scatterDist and dist > 0.01 then
                        -- Repulsion force
                        local strength = (scatterDist - dist) / scatterDist
                        local nx, nz = Normalize2D(dx, dz)
                        forceX = forceX + nx * strength
                        forceZ = forceZ + nz * strength
                    end
                end
            end

            -- Apply nudge if force exists
            if forceX ~= 0 or forceZ ~= 0 then
                local fx, fz = Normalize2D(forceX, forceZ)
                u1.x = u1.x + fx * CFG.scatterNudgeDistance
                u1.z = u1.z + fz * CFG.scatterNudgeDistance
                moved = true
            end
        end

        if not moved then break end  -- converged
    end

    -- Apply movements
    for _, u in ipairs(units) do
        -- Validate scatter position is reachable
        local defID = u.data and u.data.defID
        local newX, newZ = ValidatePosition(u.x, u.z, defID)
        local newY = spGetGroundHeight(newX, newZ) or 0

        -- Only move if nudged significantly
        local oldX, _, oldZ = spGetUnitPosition(u.uid)
        if oldX then
            local moveDist = Distance2D(oldX, oldZ, newX, newZ)
            if moveDist > 5 then  -- threshold: 5 elmos
                spGiveOrderToUnit(u.uid, CMD_MOVE, {newX, newY, newZ}, {})
                scatterLastProcessed[u.uid] = frame
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Feature 3: Convergent Range Walking
--------------------------------------------------------------------------------

local function ApplyRangeWalk(unitIDs, destX, destZ)
    if not PUP or not PUP.units then return end
    if not PUP.toggles.rangeWalk then return end
    if #unitIDs == 0 then return end

    -- Find shortest range in group
    local minRange = math.huge
    for _, uid in ipairs(unitIDs) do
        local udata = PUP.units[uid]
        if udata and udata.range then
            minRange = mathMin(minRange, udata.range)
        end
    end

    if minRange == math.huge then return end

    -- Calculate direction vector from average position to destination
    local avgX, avgZ = GetAveragePosition(unitIDs)
    local dirX, dirZ = Normalize2D(destX - avgX, destZ - avgZ)

    if dirX == 0 and dirZ == 0 then return end

    -- Apply range-based offset to each unit
    for _, uid in ipairs(unitIDs) do
        local udata = PUP.units[uid]
        if udata and udata.range then
            local offset = udata.range - minRange

            -- Offset backward (opposite to movement direction)
            local offsetX = destX - dirX * offset
            local offsetZ = destZ - dirZ * offset

            -- Validate position is reachable
            local finalX, finalZ = ValidatePosition(offsetX, offsetZ, udata.defID)
            local finalY = spGetGroundHeight(finalX, finalZ) or 0

            spGiveOrderToUnit(uid, CMD_MOVE, {finalX, finalY, finalZ}, {})
        end
    end
end

--------------------------------------------------------------------------------
-- Command interception
--------------------------------------------------------------------------------

function widget:CommandNotify(cmdID, params, options)
    if not TL or not PUP then return false end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return false end
    if cmdID ~= CMD_MOVE then return false end
    if not params or #params < 3 then return false end

    local destX, destY, destZ = params[1], params[2], params[3]
    local frame = spGetGameFrame()

    local selectedUnits = spGetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return false end

    -- Filter to managed units only
    local managedSelected = {}
    for _, uid in ipairs(selectedUnits) do
        if PUP.units[uid] then
            managedSelected[#managedSelected + 1] = uid
        end
    end

    if #managedSelected == 0 then return false end

    -- Apply features based on toggles
    local rangeWalkApplied = false
    local marchApplied = false

    -- Feature 3: Range Walk (apply first, modifies destinations)
    if PUP.toggles.rangeWalk and #managedSelected > 1 then
        ApplyRangeWalk(managedSelected, destX, destZ)
        rangeWalkApplied = true
    end

    -- Feature 1: March (speed matching)
    if PUP.toggles.march and #managedSelected > 1 then
        StartMarchGroup(managedSelected, destX, destZ, frame)
        marchApplied = true
    end

    -- If range walk was applied, suppress original command (we issued custom moves)
    if rangeWalkApplied then
        return true  -- suppress
    end

    return false  -- allow original command
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[Puppeteer March] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[Puppeteer March] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    if not WG.TotallyLegal.Puppeteer then
        spEcho("[Puppeteer March] ERROR: Puppeteer Core not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    PUP = WG.TotallyLegal.Puppeteer

    -- Feature detection
    hasTestMove = (spTestMoveOrder ~= nil)

    TestMaxSpeedSupport()
    spEcho("[Puppeteer March] NOTE: Speed matching unavailable (requires gadget). Scatter and range walk active.")
    spEcho("[Puppeteer March] Enabled. TestMoveOrder: " .. (hasTestMove and "yes" or "no"))
end

function widget:Shutdown()
    -- Release all speed limits
    if supportsMaxSpeedCmd and PUP and PUP.units then
        for uid, udata in pairs(PUP.units) do
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                spGiveOrderToUnit(uid, CMD_SET_WANTED_MAX_SPEED, {udata.speed}, {})
            end
        end
    end

    marchGroups = {}
    scatterLastProcessed = {}
end

function widget:GameFrame(frame)
    if not TL or not PUP then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    local ok, err = pcall(function()
        -- Feature 1: Update march groups
        if PUP.toggles.march and frame % CFG.marchUpdateFrequency == 0 then
            UpdateMarchGroups(frame)
        end

        -- Feature 2: Scatter spacing
        if PUP.toggles.scatter and frame % CFG.scatterFrequency == 0 then
            ProcessScatter(frame)
        end

        -- Cleanup stale scatter timestamps
        if frame % 300 == 0 then
            for uid, lastFrame in pairs(scatterLastProcessed) do
                if frame - lastFrame > 600 then
                    scatterLastProcessed[uid] = nil
                end
            end
        end
    end)

    if not ok then
        spEcho("[Puppeteer March] GameFrame error: " .. tostring(err))
    end
end
