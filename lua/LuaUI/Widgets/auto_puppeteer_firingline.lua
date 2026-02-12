-- Puppeteer Firing Line - Shoot-cycle rotation formation
-- Units form a rotating firing line: front units fire, cycle back to reload, next units advance.
-- Creates continuous staggered fire with automatic reload choreography.
-- Validates positions with TestMoveOrder when available.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: auto_puppeteer_core.lua (WG.TotallyLegal.Puppeteer)
--
-- References:
--   Spring.TestMoveOrder(defID, x, y, z) -> bool

function widget:GetInfo()
    return {
        name      = "Puppeteer Firing Line",
        desc      = "Rotating firing line formation. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 107,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetGameFrame        = Spring.GetGameFrame
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetUnitsInCylinder  = Spring.GetUnitsInCylinder
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local spIsUnitAllied        = Spring.IsUnitAllied
local spTestMoveOrder       = Spring.TestMoveOrder

local CMD_MOVE   = CMD.MOVE
local CMD_FIGHT  = CMD.FIGHT
local CMD_ATTACK = CMD.ATTACK

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min
local mathAbs  = math.abs
local mathCos  = math.cos
local mathSin  = math.sin
local mathAtan2 = math.atan2

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local PUP = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency    = 5,        -- process firing lines every N frames
    unitSpacing        = 50,       -- elmos between firing slots
    optimalRangeFactor = 0.9,      -- fire at 90% of max weapon range
    reloadPerpOffset   = 1.0,      -- perpendicular offset for reload positions (in spacing units)
    reloadBackOffset   = 0.5,      -- backward offset for reload positions (in spacing units)
    healSeekRadius     = 300,      -- scan for constructors within this radius
    healApproachDist   = 100,      -- move within this distance of constructor
    healMaxDeviation   = 200,      -- max distance from reload position while seeking heal
    positionTolerance  = 30,       -- unit reached position if within this distance
    maxFiringLines     = 3,        -- performance cap: max concurrent firing lines
    maxUnitsPerLine    = 20,       -- performance cap: max units per line
    minUnitsForLine    = 3,        -- need at least 3 same-type units to form a line
    noEnemyTimeout     = 150,      -- cleanup line if no enemy for this many frames
    activationRadius   = 1.5,      -- auto-form line if enemies within (weaponRange * this factor)
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local firingLines = {}      -- lineID -> line state
local unitToLine = {}       -- unitID -> lineID (reverse lookup)
local nextLineID = 1

-- Feature detection (set at init)
local hasTestMove = false
local mapSizeX = 0
local mapSizeZ = 0

-- Weapon reload time cache
local weaponReloadCache = {}  -- defID -> { reload, reloadFrames }

local function GetWeaponReload(defID)
    if weaponReloadCache[defID] then return weaponReloadCache[defID] end

    local def = UnitDefs[defID]
    if not def or not def.weapons then
        weaponReloadCache[defID] = { reload = 2.0, reloadFrames = 60 }
        return weaponReloadCache[defID]
    end

    local maxReload = 2.0  -- default
    for _, w in ipairs(def.weapons) do
        local wDefID = w.weaponDef
        if wDefID and WeaponDefs[wDefID] then
            local r = WeaponDefs[wDefID].reload or 2.0
            if r > maxReload then maxReload = r end
        end
    end

    local frames = mathMax(1, maxReload * 30)  -- convert seconds to frames
    weaponReloadCache[defID] = { reload = maxReload, reloadFrames = frames }
    return weaponReloadCache[defID]
end

--------------------------------------------------------------------------------
-- Enemy finding
--------------------------------------------------------------------------------

local function FindNearestEnemy(ux, uz, searchRadius)
    local enemies
    if spGetUnitsInCylinder then
        enemies = spGetUnitsInCylinder(ux, uz, searchRadius, Spring.ENEMY_UNITS)
    elseif spGetUnitsInRectangle then
        enemies = spGetUnitsInRectangle(
            ux - searchRadius, uz - searchRadius,
            ux + searchRadius, uz + searchRadius
        )
    end

    if not enemies or #enemies == 0 then return nil, nil, nil, math.huge end

    local bestUID, bestX, bestZ, bestDist = nil, nil, nil, math.huge

    for _, eid in ipairs(enemies) do
        if not spIsUnitAllied(eid) then
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

--------------------------------------------------------------------------------
-- Firing line state machine
--------------------------------------------------------------------------------

-- State transitions:
-- waiting -> advancing -> firing -> cycling -> reloading -> waiting

local function TransitionUnit(line, uid, newState, frame)
    -- Find slot for this unit
    for slotIdx, slot in ipairs(line.slots) do
        if slot.uid == uid then
            slot.state = newState
            slot.stateFrame = frame
            return
        end
    end

    -- Check queue
    for qIdx, qUID in ipairs(line.queue) do
        if qUID == uid then
            -- Promote from queue to advancing
            if newState == "advancing" then
                table.remove(line.queue, qIdx)
                table.insert(line.slots, { uid = uid, state = "advancing", stateFrame = frame, slotIdx = #line.slots + 1 })
            end
            return
        end
    end

    -- Check reloading
    for rIdx, rUID in ipairs(line.reloading) do
        if rUID == uid then
            if newState == "waiting" then
                table.remove(line.reloading, rIdx)
                table.insert(line.queue, uid)
            end
            return
        end
    end
end

local function GetUnitState(line, uid)
    for _, slot in ipairs(line.slots) do
        if slot.uid == uid then return slot.state, slot.stateFrame end
    end
    for _, qUID in ipairs(line.queue) do
        if qUID == uid then return "waiting", 0 end
    end
    for _, rUID in ipairs(line.reloading) do
        if rUID == uid then return "reloading", 0 end
    end
    return nil, nil
end

local function FindConstructor(ux, uz, radius)
    local nearby
    if spGetUnitsInCylinder then
        nearby = spGetUnitsInCylinder(ux, uz, radius, spGetMyTeamID())
    elseif spGetUnitsInRectangle then
        nearby = spGetUnitsInRectangle(
            ux - radius, uz - radius,
            ux + radius, uz + radius
        )
    end

    if not nearby then return nil, nil, nil end

    for _, uid in ipairs(nearby) do
        local defID = spGetUnitDefID(uid)
        if defID then
            local cls = TL.GetUnitClass(defID)
            if cls and cls.isBuilder and not cls.isFactory then
                local cx, cy, cz = spGetUnitPosition(uid)
                if cx then return uid, cx, cz end
            end
        end
    end

    return nil, nil, nil
end

local function ClampToMap(x, z)
    return mathMax(32, mathMin(x, mapSizeX - 32)),
           mathMax(32, mathMin(z, mapSizeZ - 32))
end

local function ValidatePosition(x, z, unitDefID)
    x, z = ClampToMap(x, z)
    local y = spGetGroundHeight(x, z)
    if not y then return x, z end

    if hasTestMove and unitDefID then
        local valid = spTestMoveOrder(unitDefID, x, y, z)
        if not valid then
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
        end
    end

    return x, z
end

local function CalculateFiringPosition(line, slotIdx)
    local width = line.width
    local spacing = CFG.unitSpacing

    -- Center of firing line
    local centerX = line.frontX
    local centerZ = line.frontZ

    -- Perpendicular to enemy direction
    local perpX = -line.enemyDir.z
    local perpZ = line.enemyDir.x

    -- Offset for this slot (centered around middle)
    local offset = (slotIdx - (width + 1) / 2) * spacing
    local targetX = centerX + perpX * offset
    local targetZ = centerZ + perpZ * offset

    targetX, targetZ = ClampToMap(targetX, targetZ)

    return targetX, targetZ
end

local function CalculateReloadPosition(line, slotIdx)
    local firingX, firingZ = CalculateFiringPosition(line, slotIdx)
    local spacing = CFG.unitSpacing

    -- Perpendicular direction (left or right, alternating by slot)
    local perpX = -line.enemyDir.z
    local perpZ = line.enemyDir.x
    local perpSide = (slotIdx % 2 == 0) and 1 or -1

    -- Backward direction (away from enemy)
    local backX = -line.enemyDir.x
    local backZ = -line.enemyDir.z

    -- Scale loop depth with number of cycling units
    -- More units cycling = slightly deeper loop to avoid congestion
    local cycling = #line.reloading + #line.queue
    local depthScale = 1.0 + mathMax(0, cycling - line.width) * 0.15

    local reloadX = firingX + perpX * perpSide * spacing * CFG.reloadPerpOffset + backX * spacing * CFG.reloadBackOffset * depthScale
    local reloadZ = firingZ + perpZ * perpSide * spacing * CFG.reloadPerpOffset + backZ * spacing * CFG.reloadBackOffset * depthScale

    reloadX, reloadZ = ClampToMap(reloadX, reloadZ)

    return reloadX, reloadZ
end

local function ProcessUnitStateMachine(line, slotIdx, frame)
    local slot = line.slots[slotIdx]
    if not slot then return end

    local uid = slot.uid
    local state = slot.state
    local stateFrame = slot.stateFrame

    local ux, uy, uz = spGetUnitPosition(uid)
    if not ux then return end

    local unitDefID = PUP.units[uid] and PUP.units[uid].defID

    if state == "advancing" then
        local targetX, targetZ = CalculateFiringPosition(line, slotIdx)
        -- Validate firing position
        targetX, targetZ = ValidatePosition(targetX, targetZ, unitDefID)

        local dx = targetX - ux
        local dz = targetZ - uz
        local dist = mathSqrt(dx * dx + dz * dz)

        if dist <= CFG.positionTolerance then
            -- Reached firing position
            TransitionUnit(line, uid, "firing", frame)
            if PUP.units[uid] then PUP.units[uid].state = "firing" end
        else
            -- Move to firing position
            local targetY = spGetGroundHeight(targetX, targetZ) or 0
            spGiveOrderToUnit(uid, CMD_MOVE, {targetX, targetY, targetZ}, {})
        end

    elseif state == "firing" then
        local elapsedFrames = frame - stateFrame
        if elapsedFrames >= line.reloadTime then
            -- Weapon has fired, now in reload
            TransitionUnit(line, uid, "cycling", frame)
            if PUP.units[uid] then PUP.units[uid].state = "idle" end

            -- Advance next unit from queue
            if #line.queue > 0 then
                local nextUID = line.queue[1]
                TransitionUnit(line, nextUID, "advancing", frame)
            end
        end
        -- Stay in position while firing

    elseif state == "cycling" then
        local reloadX, reloadZ = CalculateReloadPosition(line, slotIdx)
        -- Validate reload position
        reloadX, reloadZ = ValidatePosition(reloadX, reloadZ, unitDefID)

        local dx = reloadX - ux
        local dz = reloadZ - uz
        local dist = mathSqrt(dx * dx + dz * dz)

        if dist <= CFG.positionTolerance then
            -- Reached reload position
            TransitionUnit(line, uid, "reloading", frame)
            table.remove(line.slots, slotIdx)
            table.insert(line.reloading, uid)
        else
            -- Move to reload position
            local targetY = spGetGroundHeight(reloadX, reloadZ) or 0
            spGiveOrderToUnit(uid, CMD_MOVE, {reloadX, targetY, reloadZ}, {})
        end

    elseif state == "reloading" then
        -- Seek nearby constructor for healing
        local constructorUID, cx, cz = FindConstructor(ux, uz, CFG.healSeekRadius)
        if constructorUID then
            local dx = cx - ux
            local dz = cz - uz
            local distToConstructor = mathSqrt(dx * dx + dz * dz)

            -- Also check distance from reload position
            local reloadX, reloadZ = CalculateReloadPosition(line, slotIdx)
            local drx = reloadX - ux
            local drz = reloadZ - uz
            local distFromReload = mathSqrt(drx * drx + drz * drz)

            if distToConstructor > CFG.healApproachDist and distFromReload < CFG.healMaxDeviation then
                -- Move toward constructor
                local approachX = ux + dx * 0.5
                local approachZ = uz + dz * 0.5
                local approachY = spGetGroundHeight(approachX, approachZ) or 0
                spGiveOrderToUnit(uid, CMD_MOVE, {approachX, approachY, approachZ}, {})
            end
        end

        -- Check if reload complete
        local elapsedFrames = frame - stateFrame
        if elapsedFrames >= line.reloadTime then
            -- Reload complete, back to queue
            for rIdx, rUID in ipairs(line.reloading) do
                if rUID == uid then
                    table.remove(line.reloading, rIdx)
                    table.insert(line.queue, uid)
                    break
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Firing line formation
--------------------------------------------------------------------------------

local function CalculateLineGeometry(groupUnits, groupDefID)
    -- Find center of mass
    local cx, cz = 0, 0
    local count = 0
    for _, uid in ipairs(groupUnits) do
        local ux, uy, uz = spGetUnitPosition(uid)
        if ux then
            cx = cx + ux
            cz = cz + uz
            count = count + 1
        end
    end
    if count == 0 then return nil end
    cx = cx / count
    cz = cz / count

    -- Find nearest enemy
    local range = PUP.GetWeaponRange(groupDefID)
    local enemyUID, ex, ez, enemyDist = FindNearestEnemy(cx, cz, range * CFG.activationRadius)
    if not enemyUID then return nil end

    -- Direction to enemy
    local dx = ex - cx
    local dz = ez - cz
    local len = mathMax(mathSqrt(dx * dx + dz * dz), 1)
    local enemyDir = { x = dx / len, z = dz / len }

    -- Front position (at optimal weapon range)
    local frontDist = range * CFG.optimalRangeFactor
    local frontX = cx + enemyDir.x * (enemyDist - frontDist)
    local frontZ = cz + enemyDir.z * (enemyDist - frontDist)

    return {
        enemyUID = enemyUID,
        enemyDir = enemyDir,
        enemyDist = enemyDist,
        frontX = frontX,
        frontZ = frontZ,
    }
end

local function CreateFiringLine(groupUnits, groupDefID, frame)
    if #firingLines >= CFG.maxFiringLines then return nil end
    if #groupUnits < CFG.minUnitsForLine then return nil end
    if #groupUnits > CFG.maxUnitsPerLine then
        -- Truncate to max
        local truncated = {}
        for i = 1, CFG.maxUnitsPerLine do
            truncated[i] = groupUnits[i]
        end
        groupUnits = truncated
    end

    local geometry = CalculateLineGeometry(groupUnits, groupDefID)
    if not geometry then return nil end

    local width = mathMin(PUP.toggles.firingLineWidth or 1, 5)
    local reloadData = GetWeaponReload(groupDefID)

    local lineID = nextLineID
    nextLineID = nextLineID + 1

    local line = {
        lineID       = lineID,
        defID        = groupDefID,
        enemyUID     = geometry.enemyUID,
        enemyDir     = geometry.enemyDir,
        enemyDist    = geometry.enemyDist,
        frontX       = geometry.frontX,
        frontZ       = geometry.frontZ,
        reloadTime   = reloadData.reloadFrames,
        width        = width,
        slots        = {},
        queue        = {},
        reloading    = {},
        frame        = frame,
        lastEnemyFrame = frame,
    }

    -- Assign first width units to advancing slots
    for i = 1, mathMin(width, #groupUnits) do
        local uid = groupUnits[i]
        table.insert(line.slots, { uid = uid, state = "advancing", stateFrame = frame, slotIdx = i })
        unitToLine[uid] = lineID
        if PUP.units[uid] then PUP.units[uid].state = "idle" end
    end

    -- Rest go to queue
    for i = width + 1, #groupUnits do
        local uid = groupUnits[i]
        table.insert(line.queue, uid)
        unitToLine[uid] = lineID
    end

    firingLines[lineID] = line
    return lineID
end

local function UpdateFiringLineGeometry(line, frame)
    -- Re-scan for nearest enemy
    local cx, cz = line.frontX, line.frontZ
    local range = PUP.GetWeaponRange(line.defID)
    local enemyUID, ex, ez, enemyDist = FindNearestEnemy(cx, cz, range * CFG.activationRadius)

    if enemyUID then
        -- Update enemy info
        line.enemyUID = enemyUID
        line.enemyDist = enemyDist
        line.lastEnemyFrame = frame

        -- Update enemy direction
        local dx = ex - cx
        local dz = ez - cz
        local len = mathMax(mathSqrt(dx * dx + dz * dz), 1)
        line.enemyDir = { x = dx / len, z = dz / len }

        -- Update front position
        local frontDist = range * CFG.optimalRangeFactor
        local newFrontX = cx + line.enemyDir.x * (enemyDist - frontDist)
        local newFrontZ = cz + line.enemyDir.z * (enemyDist - frontDist)
        line.frontX = newFrontX
        line.frontZ = newFrontZ
    end
end

local function CleanupFiringLine(lineID)
    local line = firingLines[lineID]
    if not line then return end

    -- Clear unit associations
    for _, slot in ipairs(line.slots) do
        unitToLine[slot.uid] = nil
        if PUP.units[slot.uid] then PUP.units[slot.uid].state = "idle" end
    end
    for _, uid in ipairs(line.queue) do
        unitToLine[uid] = nil
    end
    for _, uid in ipairs(line.reloading) do
        unitToLine[uid] = nil
    end

    firingLines[lineID] = nil
end

local function ProcessFiringLine(lineID, frame)
    local line = firingLines[lineID]
    if not line then return end

    -- Check for stale line (no enemy for timeout)
    if (frame - line.lastEnemyFrame) > CFG.noEnemyTimeout then
        CleanupFiringLine(lineID)
        return
    end

    -- Check if line has too few units
    local totalUnits = #line.slots + #line.queue + #line.reloading
    if totalUnits < 2 then
        CleanupFiringLine(lineID)
        return
    end

    -- Update geometry
    UpdateFiringLineGeometry(line, frame)

    -- Process each slot's state machine
    for i = #line.slots, 1, -1 do  -- reverse order to handle removals
        ProcessUnitStateMachine(line, i, frame)
    end

    -- Process reloading units (in case they need to transition back to queue)
    -- Already handled in ProcessUnitStateMachine

    -- Verify all units still exist
    for i = #line.slots, 1, -1 do
        local uid = line.slots[i].uid
        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            table.remove(line.slots, i)
            unitToLine[uid] = nil
        end
    end
    for i = #line.queue, 1, -1 do
        local uid = line.queue[i]
        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            table.remove(line.queue, i)
            unitToLine[uid] = nil
        end
    end
    for i = #line.reloading, 1, -1 do
        local uid = line.reloading[i]
        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            table.remove(line.reloading, i)
            unitToLine[uid] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Auto-formation detection
--------------------------------------------------------------------------------

local function DetectAndFormLines(frame)
    if not PUP.toggles.firingLine then return end

    -- Group units by defID
    local groups = {}  -- defID -> { uid1, uid2, ... }

    for uid, data in pairs(PUP.units) do
        if not unitToLine[uid] then  -- not already in a line
            local defID = data.defID
            if data.hasWeapon and data.range > 0 then
                if not groups[defID] then groups[defID] = {} end
                table.insert(groups[defID], uid)
            end
        end
    end

    -- Try to form lines for groups with enough units
    for defID, groupUnits in pairs(groups) do
        if #groupUnits >= CFG.minUnitsForLine and #firingLines < CFG.maxFiringLines then
            -- Check if group is near enemies
            local geometry = CalculateLineGeometry(groupUnits, defID)
            if geometry then
                CreateFiringLine(groupUnits, defID, frame)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Command notification (explicit formation)
--------------------------------------------------------------------------------

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    if not PUP or not PUP.toggles.firingLine then return false end
    if cmdID ~= CMD_FIGHT and cmdID ~= CMD_ATTACK then return false end

    local selected = Spring.GetSelectedUnits()
    if not selected or #selected < CFG.minUnitsForLine then return false end

    -- Group selected by defID
    local groups = {}
    for _, uid in ipairs(selected) do
        if PUP.units[uid] and not unitToLine[uid] then
            local defID = PUP.units[uid].defID
            if not groups[defID] then groups[defID] = {} end
            table.insert(groups[defID], uid)
        end
    end

    -- Form lines for eligible groups
    local frame = spGetGameFrame()
    for defID, groupUnits in pairs(groups) do
        if #groupUnits >= CFG.minUnitsForLine then
            CreateFiringLine(groupUnits, defID, frame)
        end
    end

    return false  -- don't block command
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[Puppeteer Firing Line] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[Puppeteer Firing Line] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    if not WG.TotallyLegal.Puppeteer then
        Spring.Echo("[Puppeteer Firing Line] ERROR: Puppeteer Core not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    PUP = WG.TotallyLegal.Puppeteer
    PUP.firingLines = firingLines  -- expose state to other widgets

    mapSizeX = Game.mapSizeX or 8192
    mapSizeZ = Game.mapSizeZ or 8192

    -- Feature detection
    hasTestMove = (spTestMoveOrder ~= nil)

    Spring.Echo("[Puppeteer Firing Line] Enabled. Max " .. CFG.maxFiringLines ..
                " concurrent lines. TestMoveOrder: " .. (hasTestMove and "yes" or "no"))
end

function widget:Shutdown()
    if PUP then
        -- Cleanup all firing lines
        for lineID in pairs(firingLines) do
            CleanupFiringLine(lineID)
        end
        PUP.firingLines = nil
    end
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if not PUP or not PUP.active then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        -- Auto-detect and form new lines
        DetectAndFormLines(frame)

        -- Process existing firing lines
        for lineID in pairs(firingLines) do
            ProcessFiringLine(lineID, frame)
        end
    end)
    if not ok then
        Spring.Echo("[Puppeteer Firing Line] GameFrame error: " .. tostring(err))
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if unitToLine[unitID] then
        unitToLine[unitID] = nil
        -- Line cleanup will happen in next ProcessFiringLine call
    end
end
