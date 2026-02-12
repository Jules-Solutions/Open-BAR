-- Unit Puppeteer: Smart Move - Range-aware pathing + proactive range-keeping
-- Three layers of range awareness:
--   1. MOVE interception: reroutes commands around enemy weapon ranges
--   2. Reactive danger check: pushes idle/moving units out of danger zones
--   3. Proactive range-keep: units auto-retreat before enemies get in range
-- Supports radar contacts (assumes default range for unidentified units).
-- Kite logic: outranging units maintain firing distance, outranged units flee.
-- FIGHT/ATTACK commands override range-keeping (explicit engagement).
-- PvE/Unranked ONLY. Requires: auto_puppeteer_core.lua
-- Requires: 01_totallylegal_core.lua (WG.TotallyLegal)
--
-- References:
--   Path API: https://springrts.com/wiki/Lua_PathFinder
--   TestMoveOrder: Spring.TestMoveOrder(defID, x,y,z) -> bool
--   GetUnitEstimatedPath: Spring.GetUnitEstimatedPath(unitID) -> waypoints, indices

function widget:GetInfo()
    return {
        name      = "Puppeteer Smart Move",
        desc      = "Range-aware pathing: units avoid enemy weapon ranges. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 104,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetUnitPosition        = Spring.GetUnitPosition
local spGetUnitDefID           = Spring.GetUnitDefID
local spGetUnitCommands        = Spring.GetUnitCommands
local spGetUnitHealth          = Spring.GetUnitHealth
local spGetSelectedUnits       = Spring.GetSelectedUnits
local spGetGameFrame           = Spring.GetGameFrame
local spGetGroundHeight        = Spring.GetGroundHeight
local spGiveOrderToUnit        = Spring.GiveOrderToUnit
local spGetUnitsInRectangle    = Spring.GetUnitsInRectangle
local spIsUnitAllied           = Spring.IsUnitAllied
local spGetMyTeamID            = Spring.GetMyTeamID
local spGetUnitVelocity        = Spring.GetUnitVelocity

-- Path API (may not exist in all engine versions, checked at init)
local spGetUnitEstimatedPath   = Spring.GetUnitEstimatedPath     -- unitID -> waypoints, indices
local spTestMoveOrder          = Spring.TestMoveOrder             -- defID, x, y, z -> bool
local spGetUnitMoveTypeData    = Spring.GetUnitMoveTypeData       -- unitID -> table

-- Path module (may not exist in widget context)
local PathRequestPath          = nil  -- set at init if available

local CMD_MOVE    = CMD.MOVE
local CMD_FIGHT   = CMD.FIGHT
local CMD_ATTACK  = CMD.ATTACK
local CMD_STOP    = CMD.STOP

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min
local mathAbs   = math.abs
local mathAtan2 = math.atan2
local mathCos   = math.cos
local mathSin   = math.sin
local mathPi    = math.pi

--------------------------------------------------------------------------------
-- Core references
--------------------------------------------------------------------------------

local TL  = nil
local PUP = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency    = 5,      -- check active moves every N frames
    safetyMargin       = 30,     -- stop this many elmos before weapon range edge
    enemyScanRadius    = 1500,   -- scan this far for enemies along path
    maxEnemiesChecked  = 20,     -- performance cap on enemy checks per unit
    arcSegments        = 8,      -- number of waypoints for arcing around danger
    maxDetourRatio     = 3.0,    -- if arc is > 3x direct distance, go through instead
    waypointCheckStep  = 100,    -- check estimated path every N elmos for danger
    -- Range-keeping
    rangeKeepFrequency = 8,      -- proactive retreat check every N frames
    radarDefaultRange  = 450,    -- assumed weapon range for unidentified radar contacts (covers T2)
    comfortBuffer      = 60,     -- start retreating this far before enemy range edge
    rangeKeepScanPad   = 1200,   -- scan radius for range-keeping enemies
    retreatCooldown    = 20,     -- frames between retreat orders per unit
    -- Predictive retreat
    predictiveFrames   = 45,     -- lookahead window (~1.5s at 30fps)
    -- Combat jitter (velocity noise to break enemy aim prediction)
    jitterAmplitude    = 35,     -- base lateral displacement (elmos)
    jitterFrequency    = 10,     -- frames between jitter moves per unit
    jitterCombatRadius = 1200,   -- only jitter when enemies within this range
    -- Threat escalation
    threatEscalationCap = 3.0,   -- max multiplier on comfort buffer
}

local mapSizeX = 0
local mapSizeZ = 0

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local activeReroutes = {}    -- unitID -> { destX, destZ, frame, stoppedAtEdge }
local retreatCooldowns = {}  -- unitID -> frame (last retreat order)
local enemyRangeCache = {}   -- enemyDefID -> maxWeaponRange
local hasPathAPI = false     -- set at init: can we use Path.RequestPath?
local hasTestMove = false    -- set at init: can we use TestMoveOrder?
local hasEstimatedPath = false -- set at init: can we use GetUnitEstimatedPath?
local jitterCooldowns = {}   -- unitID -> frame
local jitterDirections = {}  -- unitID -> 1 or -1 (alternating lateral direction)

--------------------------------------------------------------------------------
-- Enemy weapon range lookup
--------------------------------------------------------------------------------

local function GetEnemyWeaponRange(unitID)
    local defID = spGetUnitDefID(unitID)
    if not defID then
        -- Radar contact: unit visible on radar but type unknown
        -- Assume a default danger range rather than ignoring it
        return CFG.radarDefaultRange
    end

    if enemyRangeCache[defID] then return enemyRangeCache[defID] end

    local def = UnitDefs[defID]
    if not def or not def.weapons then
        enemyRangeCache[defID] = 0
        return 0
    end

    local maxRange = 0
    for _, w in ipairs(def.weapons) do
        local wDefID = w.weaponDef
        if wDefID and WeaponDefs[wDefID] then
            local wd = WeaponDefs[wDefID]
            -- Skip weapons that can only target air (AA weapons)
            if wd.canAttackGround ~= false then
                local r = wd.range or 0
                if r > maxRange then maxRange = r end
            end
        end
    end

    enemyRangeCache[defID] = maxRange
    return maxRange
end

--------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------

local function SegmentCircleIntersect(ax, az, bx, bz, cx, cz, r)
    local dx = bx - ax
    local dz = bz - az
    local fx = ax - cx
    local fz = az - cz

    local a = dx * dx + dz * dz
    if a < 0.001 then return false, 0, 0 end

    local b = 2 * (fx * dx + fz * dz)
    local c = fx * fx + fz * fz - r * r

    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then return false, 0, 0 end

    local sqrtD = mathSqrt(discriminant)
    local t1 = (-b - sqrtD) / (2 * a)
    local t2 = (-b + sqrtD) / (2 * a)

    if t1 > 1 or t2 < 0 then return false, 0, 0 end

    t1 = mathMax(0, t1)
    t2 = mathMin(1, t2)

    local segLen = mathSqrt(a)
    return true, t1 * segLen, t2 * segLen
end

local function CircleEdgePoint(cx, cz, radius, targetX, targetZ)
    local dx = targetX - cx
    local dz = targetZ - cz
    local len = mathSqrt(dx * dx + dz * dz)
    if len < 0.001 then return cx + radius, cz end
    return cx + (dx / len) * radius, cz + (dz / len) * radius
end

local function CalcArcWaypoints(cx, cz, radius, startAngle, endAngle, segments)
    local waypoints = {}
    local diff = endAngle - startAngle
    while diff > mathPi do diff = diff - 2 * mathPi end
    while diff < -mathPi do diff = diff + 2 * mathPi end

    for i = 0, segments do
        local t = i / segments
        local angle = startAngle + diff * t
        local wx = cx + mathCos(angle) * radius
        local wz = cz + mathSin(angle) * radius
        waypoints[#waypoints + 1] = { x = wx, z = wz }
    end

    return waypoints
end

local function PointInCircle(px, pz, cx, cz, r)
    local dx = px - cx
    local dz = pz - cz
    return (dx * dx + dz * dz) <= (r * r)
end

local function Dist2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return mathSqrt(dx * dx + dz * dz)
end

local function ClampToMap(x, z)
    return mathMax(32, mathMin(x, mapSizeX - 32)),
           mathMax(32, mathMin(z, mapSizeZ - 32))
end

--------------------------------------------------------------------------------
-- Validate a waypoint is reachable via TestMoveOrder
--------------------------------------------------------------------------------

local function ValidateWaypoint(x, z, unitDefID)
    x, z = ClampToMap(x, z)
    local y = spGetGroundHeight(x, z) or 0

    if hasTestMove and unitDefID then
        local valid = spTestMoveOrder(unitDefID, x, y, z)
        if not valid then
            return nil, nil, nil
        end
    end

    return x, y, z
end

--------------------------------------------------------------------------------
-- Scan for dangerous enemies in an area
--------------------------------------------------------------------------------

local function GetDangerousEnemiesInArea(minX, minZ, maxX, maxZ)
    local dangers = {}

    minX = mathMax(0, minX)
    maxX = mathMin(mapSizeX, maxX)
    minZ = mathMax(0, minZ)
    maxZ = mathMin(mapSizeZ, maxZ)

    local enemies = spGetUnitsInRectangle(minX, minZ, maxX, maxZ)
    if not enemies then return dangers end

    local count = 0
    for _, eid in ipairs(enemies) do
        if count >= CFG.maxEnemiesChecked then break end

        if not spIsUnitAllied(eid) then
            local ex, ey, ez = spGetUnitPosition(eid)
            local range = GetEnemyWeaponRange(eid)

            if ex and range > 50 then
                local totalRange = range + CFG.safetyMargin
                dangers[#dangers + 1] = {
                    unitID = eid,
                    x = ex, z = ez,
                    range = totalRange,
                }
                count = count + 1
            end
        end
    end

    return dangers
end

--------------------------------------------------------------------------------
-- Check if a point is in any danger zone
--------------------------------------------------------------------------------

local function IsPointInDanger(px, pz, dangers)
    for _, d in ipairs(dangers) do
        if PointInCircle(px, pz, d.x, d.z, d.range) then
            return true, d
        end
    end
    return false, nil
end

--------------------------------------------------------------------------------
-- Check if a point is in any danger zone (excluding one specific danger)
--------------------------------------------------------------------------------

local function IsPointInAnyDanger(px, pz, dangers, excludeIdx)
    for i, d in ipairs(dangers) do
        if i ~= excludeIdx then
            if PointInCircle(px, pz, d.x, d.z, d.range) then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Check the engine's estimated path for a unit against danger zones
-- Returns the first dangerous waypoint index, or nil if safe
--------------------------------------------------------------------------------

local function CheckEstimatedPathForDanger(unitID, dangers)
    if not hasEstimatedPath then return nil end

    local waypoints, indices = spGetUnitEstimatedPath(unitID)
    if not waypoints or #waypoints == 0 then return nil end

    -- Check each waypoint against danger zones
    for i, wp in ipairs(waypoints) do
        local wx, wy, wz = wp[1] or wp.x, wp[2] or wp.y, wp[3] or wp.z
        if wx and wz then
            local inDanger, danger = IsPointInDanger(wx, wz, dangers)
            if inDanger then
                return i, wx, wz, danger
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Scan for dangers along a straight-line path
--------------------------------------------------------------------------------

local function FindDangersAlongPath(startX, startZ, destX, destZ)
    -- Bounding box of path + scan radius
    local minX = mathMin(startX, destX) - CFG.enemyScanRadius
    local maxX = mathMax(startX, destX) + CFG.enemyScanRadius
    local minZ = mathMin(startZ, destZ) - CFG.enemyScanRadius
    local maxZ = mathMax(startZ, destZ) + CFG.enemyScanRadius

    local allDangers = GetDangerousEnemiesInArea(minX, minZ, maxX, maxZ)

    -- Filter to only those whose range actually intersects our path
    local pathDangers = {}
    for _, d in ipairs(allDangers) do
        local intersects = SegmentCircleIntersect(
            startX, startZ, destX, destZ, d.x, d.z, d.range
        )
        if intersects then
            pathDangers[#pathDangers + 1] = d
        end
    end

    return pathDangers, allDangers
end

--------------------------------------------------------------------------------
-- Smart path calculation
--------------------------------------------------------------------------------

local function CalcSmartPath(unitID, unitX, unitZ, destX, destZ, unitDefID)
    local pathDangers, allDangers = FindDangersAlongPath(unitX, unitZ, destX, destZ)

    -- Also check the engine's estimated path if available
    if hasEstimatedPath and #pathDangers == 0 then
        local dangerIdx, wx, wz, danger = CheckEstimatedPathForDanger(unitID, allDangers)
        if dangerIdx and danger then
            pathDangers[#pathDangers + 1] = danger
        end
    end

    if #pathDangers == 0 then return nil end  -- no danger, use normal pathing

    -- Check if destination itself is inside enemy range
    for _, d in ipairs(pathDangers) do
        if PointInCircle(destX, destZ, d.x, d.z, d.range) then
            -- Stop at range edge
            local edgeX, edgeZ = CircleEdgePoint(d.x, d.z, d.range, unitX, unitZ)

            -- Validate the edge point is reachable
            if hasTestMove and unitDefID then
                local vx, vy, vz = ValidateWaypoint(edgeX, edgeZ, unitDefID)
                if vx then
                    return { { x = vx, z = vz } }, true
                end
                -- If edge point is unreachable, try a few offsets
                for offset = 20, 60, 20 do
                    local dx = edgeX - d.x
                    local dz = edgeZ - d.z
                    local len = mathSqrt(dx * dx + dz * dz)
                    if len > 0.001 then
                        local tryX = edgeX + (dx / len) * offset
                        local tryZ = edgeZ + (dz / len) * offset
                        vx, vy, vz = ValidateWaypoint(tryX, tryZ, unitDefID)
                        if vx then
                            return { { x = vx, z = vz } }, true
                        end
                    end
                end
            else
                edgeX, edgeZ = ClampToMap(edgeX, edgeZ)
                return { { x = edgeX, z = edgeZ } }, true
            end
        end
    end

    -- Destination is safe but path crosses danger zone(s)
    -- Sort dangers by proximity (closest first)
    table.sort(pathDangers, function(a, b)
        local da = Dist2D(unitX, unitZ, a.x, a.z)
        local db = Dist2D(unitX, unitZ, b.x, b.z)
        return da < db
    end)

    -- Build waypoint chain that arcs around each danger zone
    local waypoints = {}
    local curX, curZ = unitX, unitZ

    for dangerIdx, danger in ipairs(pathDangers) do
        local cx, cz = danger.x, danger.z
        local radius = danger.range + 10

        -- Check if this segment actually crosses this danger
        local intersects = SegmentCircleIntersect(curX, curZ, destX, destZ, cx, cz, radius)
        if intersects then
            local entryAngle = mathAtan2(curZ - cz, curX - cx)
            local exitAngle = mathAtan2(destZ - cz, destX - cx)

            local arcWP = CalcArcWaypoints(cx, cz, radius, entryAngle, exitAngle, CFG.arcSegments)

            -- Validate arc doesn't cross through danger
            local arcCrossesDanger = false
            for _, wp in ipairs(arcWP) do
                if PointInCircle(wp.x, wp.z, cx, cz, danger.range) then
                    arcCrossesDanger = true
                    break
                end
            end

            -- If shorter arc goes through danger, use the longer arc
            if arcCrossesDanger then
                -- Reverse: swap angles to go the long way around
                arcWP = CalcArcWaypoints(cx, cz, radius, exitAngle, entryAngle, CFG.arcSegments)
                -- Reverse the waypoint order so direction is correct
                local reversed = {}
                for i = #arcWP, 1, -1 do
                    reversed[#reversed + 1] = arcWP[i]
                end
                arcWP = reversed
            end

            -- Validate arc waypoints (both terrain reachability AND against all other dangers)
            for _, wp in ipairs(arcWP) do
                -- Check if this waypoint lands inside any OTHER danger zone
                if IsPointInAnyDanger(wp.x, wp.z, pathDangers, dangerIdx) then
                    -- Skip this waypoint - it lands in another danger zone
                    goto continue_waypoint
                end

                local vx, vy, vz
                if hasTestMove and unitDefID then
                    vx, vy, vz = ValidateWaypoint(wp.x, wp.z, unitDefID)
                else
                    wp.x, wp.z = ClampToMap(wp.x, wp.z)
                    vx, vz = wp.x, wp.z
                end

                if vx then
                    waypoints[#waypoints + 1] = { x = vx, z = vz }
                    curX, curZ = vx, vz
                end

                ::continue_waypoint::
            end
        end
    end

    -- Append final destination
    waypoints[#waypoints + 1] = { x = destX, z = destZ }

    if #waypoints <= 1 then return nil end

    -- Check if the detour is worth it
    local directDist = Dist2D(unitX, unitZ, destX, destZ)
    local arcDist = 0
    local prevX, prevZ = unitX, unitZ
    for _, wp in ipairs(waypoints) do
        arcDist = arcDist + Dist2D(prevX, prevZ, wp.x, wp.z)
        prevX, prevZ = wp.x, wp.z
    end

    if arcDist > directDist * CFG.maxDetourRatio then
        return nil  -- too far to reroute, go direct
    end

    -- Check if waypoints are actually safe (not landing inside ANY danger zone)
    local unsafeCount = 0
    for _, wp in ipairs(waypoints) do
        for _, d in ipairs(allDangers) do
            if PointInCircle(wp.x, wp.z, d.x, d.z, d.range) then
                unsafeCount = unsafeCount + 1
                break
            end
        end
    end
    if unsafeCount > #waypoints * 0.5 then
        return nil  -- can't find safe path, go direct
    end

    return waypoints, false
end

--------------------------------------------------------------------------------
-- Command interception
--------------------------------------------------------------------------------

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if not PUP then return false end
    if not PUP.active then return false end
    if not PUP.toggles.smartMove then return false end

    -- Only intercept MOVE commands (FIGHT overrides Smart Move)
    if cmdID ~= CMD_MOVE then return false end
    if not cmdParams or #cmdParams < 3 then return false end

    local destX, destY, destZ = cmdParams[1], cmdParams[2], cmdParams[3]

    local selectedUnits = spGetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return false end

    local rerouted = false

    for _, uid in ipairs(selectedUnits) do
        local unitData = PUP.units[uid]
        if unitData then
            local ux, uy, uz = spGetUnitPosition(uid)
            if ux then
                local waypoints, stoppedAtEdge = CalcSmartPath(
                    uid, ux, uz, destX, destZ, unitData.defID
                )

                if waypoints and #waypoints > 0 then
                    -- Issue first waypoint
                    local wp = waypoints[1]
                    local wpx, wpz = ClampToMap(wp.x, wp.z)
                    local wpy = spGetGroundHeight(wpx, wpz) or 0

                    spGiveOrderToUnit(uid, CMD_MOVE, { wpx, wpy, wpz }, {})

                    -- Queue remaining waypoints
                    for i = 2, #waypoints do
                        local w = waypoints[i]
                        local wx, wz = ClampToMap(w.x, w.z)
                        local wy = spGetGroundHeight(wx, wz) or 0
                        spGiveOrderToUnit(uid, CMD_MOVE, { wx, wy, wz }, { "shift" })
                    end

                    -- Track reroute
                    activeReroutes[uid] = {
                        destX = destX,
                        destZ = destZ,
                        frame = spGetGameFrame(),
                        stoppedAtEdge = stoppedAtEdge,
                    }

                    rerouted = true
                end
            end
        end
    end

    -- Issue original move to non-managed units so they aren't left standing
    if rerouted then
        for _, uid in ipairs(selectedUnits) do
            if not PUP.units[uid] then
                local y = spGetGroundHeight(destX, destZ) or 0
                spGiveOrderToUnit(uid, CMD_MOVE, { destX, y, destZ }, {})
            end
        end
    end

    return rerouted
end

--------------------------------------------------------------------------------
-- Reactive check: idle units sitting in danger
--------------------------------------------------------------------------------

local function CheckUnitsInDanger(frame)
    if not PUP or not PUP.toggles.smartMove then return end

    for uid, data in pairs(PUP.units) do
        if not activeReroutes[uid] then
            local ux, uy, uz = spGetUnitPosition(uid)
            if ux then
                local cmds = spGetUnitCommands(uid, 1)
                local isIdle = (not cmds or #cmds == 0)
                local isMoving = (cmds and #cmds > 0 and cmds[1].id == CMD_MOVE)

                if isIdle then
                    -- Idle units sitting inside enemy range: push to edge
                    local pad = 800
                    local dangers = GetDangerousEnemiesInArea(
                        ux - pad, uz - pad, ux + pad, uz + pad
                    )

                    -- Find all zones the unit is inside
                    local insideDangers = {}
                    for _, d in ipairs(dangers) do
                        if PointInCircle(ux, uz, d.x, d.z, d.range) then
                            insideDangers[#insideDangers + 1] = d
                        end
                    end

                    if #insideDangers > 0 then
                        -- Compute combined escape vector (average direction away from all danger centers)
                        local escX, escZ = 0, 0
                        for _, d in ipairs(insideDangers) do
                            local dx = ux - d.x
                            local dz = uz - d.z
                            local len = mathSqrt(dx * dx + dz * dz)
                            if len > 0.001 then
                                -- Weight by how deep inside the zone we are (deeper = stronger push)
                                local depth = 1.0 - (len / d.range)
                                escX = escX + (dx / len) * mathMax(0.1, depth)
                                escZ = escZ + (dz / len) * mathMax(0.1, depth)
                            else
                                -- Exactly at center, pick arbitrary direction
                                escX = escX + 1
                            end
                        end

                        local escLen = mathSqrt(escX * escX + escZ * escZ)
                        if escLen > 0.001 then
                            escX = escX / escLen
                            escZ = escZ / escLen

                            -- Walk along escape direction until outside ALL zones
                            local maxDist = 0
                            for _, d in ipairs(insideDangers) do
                                maxDist = mathMax(maxDist, d.range)
                            end

                            -- Try escape at increasing distances
                            local escaped = false
                            for tryDist = 100, maxDist + 200, 50 do
                                local tryX = ux + escX * tryDist
                                local tryZ = uz + escZ * tryDist
                                tryX, tryZ = ClampToMap(tryX, tryZ)

                                local safe = true
                                for _, d in ipairs(insideDangers) do
                                    if PointInCircle(tryX, tryZ, d.x, d.z, d.range) then
                                        safe = false
                                        break
                                    end
                                end

                                if safe then
                                    local vx, vy, vz
                                    if hasTestMove and data.defID then
                                        vx, vy, vz = ValidateWaypoint(tryX, tryZ, data.defID)
                                    else
                                        vx = tryX
                                        vy = spGetGroundHeight(tryX, tryZ) or 0
                                        vz = tryZ
                                    end

                                    if vx then
                                        spGiveOrderToUnit(uid, CMD_MOVE, { vx, vy, vz }, {})
                                        escaped = true
                                        break
                                    end
                                end
                            end
                            -- If can't escape, do nothing (don't ping-pong)
                        end
                    end

                elseif isMoving then
                    -- Moving units: check if path now crosses newly revealed danger
                    local destX = cmds[1].params[1]
                    local destZ = cmds[1].params[3]
                    if destX and destZ then
                        local waypoints, stoppedAtEdge = CalcSmartPath(
                            uid, ux, uz, destX, destZ, data.defID
                        )

                        if waypoints and #waypoints > 0 then
                            -- Reroute around newly discovered danger
                            local wp = waypoints[1]
                            local wpx, wpz = ClampToMap(wp.x, wp.z)
                            local wpy = spGetGroundHeight(wpx, wpz) or 0
                            spGiveOrderToUnit(uid, CMD_MOVE, { wpx, wpy, wpz }, {})

                            for i = 2, #waypoints do
                                local w = waypoints[i]
                                local wx, wz = ClampToMap(w.x, w.z)
                                local wy = spGetGroundHeight(wx, wz) or 0
                                spGiveOrderToUnit(uid, CMD_MOVE, { wx, wy, wz }, { "shift" })
                            end

                            activeReroutes[uid] = {
                                destX = destX,
                                destZ = destZ,
                                frame = frame,
                                stoppedAtEdge = stoppedAtEdge,
                            }
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Proactive range-keeping: stay out of enemy weapon range at all times
--------------------------------------------------------------------------------

local function IsUnitEngaged(uid)
    local cmds = spGetUnitCommands(uid, 1)
    if not cmds or #cmds == 0 then return false end
    local cmdID = cmds[1].id
    -- FIGHT, ATTACK, or attack-move mean the player explicitly chose to engage
    return (cmdID == CMD_FIGHT or cmdID == CMD_ATTACK)
end

local function ProactiveRangeKeep(frame)
    if not PUP or not PUP.toggles.rangeKeep then return end

    for uid, data in pairs(PUP.units) do
        -- Skip units already being rerouted
        if activeReroutes[uid] then goto continue_unit end

        -- Skip units on retreat cooldown
        if retreatCooldowns[uid] and (frame - retreatCooldowns[uid]) < CFG.retreatCooldown then
            goto continue_unit
        end

        -- Skip units explicitly engaged (FIGHT/ATTACK commands)
        if IsUnitEngaged(uid) then goto continue_unit end

        -- Skip firing line units (they have their own positioning)
        if data.state == "firing" or data.state == "advancing" or data.state == "cycling" or data.state == "reloading" then
            goto continue_unit
        end

        local ux, uy, uz = spGetUnitPosition(uid)
        if not ux then goto continue_unit end

        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then goto continue_unit end

        -- Scan for nearby enemies
        local pad = CFG.rangeKeepScanPad
        local enemies = spGetUnitsInRectangle(
            mathMax(0, ux - pad), mathMax(0, uz - pad),
            mathMin(mapSizeX, ux + pad), mathMin(mapSizeZ, uz + pad)
        )
        if not enemies then goto continue_unit end

        -- Find threats: enemies whose weapon range (+ buffer) covers our position
        -- OR enemies closing fast enough to reach range within prediction window
        local retreatX, retreatZ = 0, 0
        local threatCount = 0
        local ourRange = data.range or 0

        for _, eid in ipairs(enemies) do
            if not spIsUnitAllied(eid) then
                local ex, ey, ez = spGetUnitPosition(eid)
                if ex then
                    local enemyRange = GetEnemyWeaponRange(eid)
                    if enemyRange > 50 then
                        local dx = ux - ex
                        local dz = uz - ez
                        local dist = mathSqrt(dx * dx + dz * dz)
                        if dist < 0.001 then
                            dx, dz, dist = 1, 0, 1
                        end
                        local nx, nz = dx / dist, dz / dist

                        -- Effective comfort buffer scales with threat count
                        local effectiveBuffer = CFG.comfortBuffer * mathMin(
                            CFG.threatEscalationCap,
                            1.0 + threatCount * 0.3
                        )
                        local dangerRadius = enemyRange + CFG.safetyMargin + effectiveBuffer

                        local isThreat = false
                        local moveDist = 0

                        if dist < dangerRadius then
                            -- Already inside danger zone - immediate threat
                            isThreat = true

                            -- Kite distance: where should we stand?
                            local targetDist
                            if ourRange > enemyRange + 30 then
                                -- We outrange them: stand at our max range (can shoot, they can't)
                                targetDist = ourRange * 0.95
                            else
                                -- They outrange or match us: stand just outside their range
                                targetDist = dangerRadius
                            end

                            moveDist = targetDist - dist

                        elseif spGetUnitVelocity then
                            -- Predictive retreat: check if enemy is closing fast
                            local evx, evy, evz = spGetUnitVelocity(eid)
                            if evx and evz then
                                -- Closing speed: how fast enemy approaches us
                                -- nx points from enemy to us, so dot(enemyVel, nx) > 0 = approaching
                                local closingSpeed = evx * nx + evz * nz

                                if closingSpeed > 0.5 then
                                    -- Enemy is approaching us
                                    local distToRange = dist - dangerRadius
                                    if distToRange > 0 then
                                        local framesToRange = distToRange / closingSpeed
                                        if framesToRange < CFG.predictiveFrames then
                                            -- They'll be in range within our prediction window
                                            -- Start retreating NOW
                                            isThreat = true
                                            -- Move enough to maintain current safe distance
                                            moveDist = effectiveBuffer + closingSpeed * 5
                                        end
                                    end
                                end
                            end
                        end

                        if isThreat and moveDist > 10 then
                            -- Weight by urgency (deeper inside or faster approach = stronger push)
                            local urgency = mathMax(0.1, 1.0 - dist / (dangerRadius + 200))
                            retreatX = retreatX + nx * moveDist * urgency
                            retreatZ = retreatZ + nz * moveDist * urgency
                            threatCount = threatCount + 1
                        end
                    end
                end
            end
        end

        if threatCount > 0 then
            -- Average retreat vector
            retreatX = retreatX / threatCount
            retreatZ = retreatZ / threatCount

            local targetX = ux + retreatX
            local targetZ = uz + retreatZ
            targetX, targetZ = ClampToMap(targetX, targetZ)

            -- Validate retreat position
            local targetY
            if hasTestMove and data.defID then
                local vx, vy, vz = ValidateWaypoint(targetX, targetZ, data.defID)
                if vx then
                    targetX, targetY, targetZ = vx, vy, vz
                else
                    goto continue_unit
                end
            else
                targetY = spGetGroundHeight(targetX, targetZ) or 0
            end

            -- Only retreat if displacement is meaningful (avoid micro-stuttering)
            local finalMoveDist = Dist2D(ux, uz, targetX, targetZ)
            if finalMoveDist > 15 then
                spGiveOrderToUnit(uid, CMD_MOVE, { targetX, targetY, targetZ }, {})
                retreatCooldowns[uid] = frame
            end
        end

        ::continue_unit::
    end
end

--------------------------------------------------------------------------------
-- Combat jitter: micro-movement to disrupt enemy weapon aim prediction
-- Spring weapons lead targets based on current velocity. Constant small
-- velocity changes make the prediction consistently wrong.
-- Only applies to idle units in combat zones.
--------------------------------------------------------------------------------

local function ApplyCombatJitter(frame)
    if not PUP or not PUP.toggles.jitter then return end

    for uid, data in pairs(PUP.units) do
        -- Only jitter idle units (no commands)
        local cmds = spGetUnitCommands(uid, 1)
        if cmds and #cmds > 0 then goto continue_jitter end

        -- Skip firing line units
        if data.state == "firing" or data.state == "advancing"
        or data.state == "cycling" or data.state == "reloading" then
            goto continue_jitter
        end

        -- Skip units that just retreated (don't undo retreat with jitter)
        if retreatCooldowns[uid] and (frame - retreatCooldowns[uid]) < CFG.retreatCooldown * 2 then
            goto continue_jitter
        end

        -- On jitter cooldown?
        if jitterCooldowns[uid] and (frame - jitterCooldowns[uid]) < CFG.jitterFrequency then
            goto continue_jitter
        end

        -- Speed check
        if data.speed < 20 then goto continue_jitter end

        local ux, uy, uz = spGetUnitPosition(uid)
        if not ux then goto continue_jitter end

        -- Only jitter if enemies are nearby (combat zone)
        local combatPad = CFG.jitterCombatRadius
        local enemies = spGetUnitsInRectangle(
            mathMax(0, ux - combatPad), mathMax(0, uz - combatPad),
            mathMin(mapSizeX, ux + combatPad), mathMin(mapSizeZ, uz + combatPad)
        )
        if not enemies then goto continue_jitter end

        -- Find nearest enemy for lateral direction calculation
        local nearX, nearZ = 0, 0
        local nearDist = math.huge
        local hasEnemy = false
        for _, eid in ipairs(enemies) do
            if not spIsUnitAllied(eid) then
                local ex, _, ez = spGetUnitPosition(eid)
                if ex then
                    local d = Dist2D(ux, uz, ex, ez)
                    if d < nearDist then
                        nearDist = d
                        nearX = ex
                        nearZ = ez
                        hasEnemy = true
                    end
                end
            end
        end
        if not hasEnemy then goto continue_jitter end

        -- Compute lateral direction (perpendicular to enemy direction)
        local dx = ux - nearX
        local dz = uz - nearZ
        local len = mathSqrt(dx * dx + dz * dz)
        if len < 1 then dx, dz, len = 1, 0, 1 end
        local nx, nz = dx / len, dz / len

        -- Perpendicular: (-nz, nx) or (nz, -nx)
        -- Alternate direction each jitter cycle per unit
        local dir = jitterDirections[uid] or 1
        jitterDirections[uid] = -dir  -- flip for next time
        local perpX = -nz * dir
        local perpZ = nx * dir

        -- Add slight bias away from enemy (10% retreat + 90% lateral)
        local jitterX = perpX * 0.9 + nx * 0.1
        local jitterZ = perpZ * 0.9 + nz * 0.1
        local jLen = mathSqrt(jitterX * jitterX + jitterZ * jitterZ)
        if jLen > 0.001 then
            jitterX = jitterX / jLen
            jitterZ = jitterZ / jLen
        end

        -- Randomize amplitude (60-140% of base)
        local amplitude = CFG.jitterAmplitude * (0.6 + math.random() * 0.8)

        local jx = ux + jitterX * amplitude
        local jz = uz + jitterZ * amplitude
        jx, jz = ClampToMap(jx, jz)

        local jy = spGetGroundHeight(jx, jz) or 0

        -- Validate position is reachable
        if hasTestMove and data.defID then
            local vx, vy, vz = ValidateWaypoint(jx, jz, data.defID)
            if not vx then goto continue_jitter end
            jx, jy, jz = vx, vy, vz
        end

        spGiveOrderToUnit(uid, CMD_MOVE, { jx, jy, jz }, {})
        jitterCooldowns[uid] = frame

        ::continue_jitter::
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[Puppeteer SmartMove] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[Puppeteer SmartMove] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    PUP = TL.Puppeteer
    if not PUP then
        Spring.Echo("[Puppeteer SmartMove] Puppeteer Core not loaded. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    mapSizeX = Game.mapSizeX or 8192
    mapSizeZ = Game.mapSizeZ or 8192

    -- Detect available API features
    hasTestMove = (spTestMoveOrder ~= nil)
    hasEstimatedPath = (spGetUnitEstimatedPath ~= nil)

    -- Check if Path module is available (may be gadget-only)
    if Path and Path.RequestPath then
        PathRequestPath = Path.RequestPath
        hasPathAPI = true
        Spring.Echo("[Puppeteer SmartMove] Path API available.")
    end

    local features = {}
    if hasTestMove then features[#features + 1] = "TestMoveOrder" end
    if hasEstimatedPath then features[#features + 1] = "EstimatedPath" end
    if hasPathAPI then features[#features + 1] = "PathAPI" end

    Spring.Echo("[Puppeteer SmartMove] Enabled. Features: " ..
        (#features > 0 and table.concat(features, ", ") or "basic"))
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    PUP = WG.TotallyLegal.Puppeteer
    if not PUP then return end

    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        CheckUnitsInDanger(frame)

        -- Proactive range-keeping (slightly less frequent)
        if frame % CFG.rangeKeepFrequency == 0 then
            ProactiveRangeKeep(frame)
        end

        -- Combat jitter (micro-movement for idle units in combat zones)
        if frame % CFG.jitterFrequency == 0 then
            ApplyCombatJitter(frame)
        end

        -- Cleanup stale reroutes
        for uid, rr in pairs(activeReroutes) do
            local unitData = PUP.units[uid]
            -- Scale timeout: slow units get more time. Base 300 frames, scale by speed ratio
            local timeout = 300
            if unitData and unitData.speed and unitData.speed > 0 then
                -- Slower units get longer timeouts (base speed ~60 elmos/s)
                timeout = mathMax(300, mathMin(1800, math.floor(600 / unitData.speed * 60)))
            end
            if frame - rr.frame > timeout or not PUP.units[uid] then
                activeReroutes[uid] = nil
            end
        end

        -- Cleanup stale retreat cooldowns
        if frame % 300 == 0 then
            for uid, cd in pairs(retreatCooldowns) do
                if frame - cd > 600 then
                    retreatCooldowns[uid] = nil
                end
            end
        end

        -- Cleanup stale jitter state
        if frame % 600 == 0 then
            for uid, _ in pairs(jitterCooldowns) do
                if not PUP.units[uid] then
                    jitterCooldowns[uid] = nil
                    jitterDirections[uid] = nil
                end
            end
        end
    end)
    if not ok then
        Spring.Echo("[Puppeteer SmartMove] GameFrame error: " .. tostring(err))
    end
end

function widget:Shutdown()
    activeReroutes = {}
    retreatCooldowns = {}
    jitterCooldowns = {}
    jitterDirections = {}
    PUP = nil
    TL = nil
end
