-- Unit Puppeteer: Smart Move - Range-aware pathing
-- Intercepts CMD_MOVE to prevent units walking into enemy weapon ranges.
-- Uses Spring.GetUnitEstimatedPath to check the engine's actual planned path,
-- Spring.TestMoveOrder to validate reroute waypoints, and circle-avoidance
-- geometry for calculating safe detours.
-- FIGHT command overrides (aggressive push).
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

-- Path API (may not exist in all engine versions, checked at init)
local spGetUnitEstimatedPath   = Spring.GetUnitEstimatedPath     -- unitID -> waypoints, indices
local spTestMoveOrder          = Spring.TestMoveOrder             -- defID, x, y, z -> bool
local spGetUnitMoveTypeData    = Spring.GetUnitMoveTypeData       -- unitID -> table

-- Path module (may not exist in widget context)
local PathRequestPath          = nil  -- set at init if available

local CMD_MOVE    = CMD.MOVE
local CMD_FIGHT   = CMD.FIGHT
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
}

local mapSizeX = 0
local mapSizeZ = 0

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local activeReroutes = {}    -- unitID -> { destX, destZ, frame, stoppedAtEdge }
local enemyRangeCache = {}   -- enemyDefID -> maxWeaponRange
local hasPathAPI = false     -- set at init: can we use Path.RequestPath?
local hasTestMove = false    -- set at init: can we use TestMoveOrder?
local hasEstimatedPath = false -- set at init: can we use GetUnitEstimatedPath?

--------------------------------------------------------------------------------
-- Enemy weapon range lookup
--------------------------------------------------------------------------------

local function GetEnemyWeaponRange(unitID)
    local defID = spGetUnitDefID(unitID)
    if not defID then return 0 end

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

    for _, danger in ipairs(pathDangers) do
        local cx, cz = danger.x, danger.z
        local radius = danger.range + 10

        -- Check if this segment actually crosses this danger
        local intersects = SegmentCircleIntersect(curX, curZ, destX, destZ, cx, cz, radius)
        if intersects then
            local entryAngle = mathAtan2(curZ - cz, curX - cx)
            local exitAngle = mathAtan2(destZ - cz, destX - cx)

            local arcWP = CalcArcWaypoints(cx, cz, radius, entryAngle, exitAngle, CFG.arcSegments)

            -- Validate arc waypoints
            for _, wp in ipairs(arcWP) do
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

    return rerouted
end

--------------------------------------------------------------------------------
-- Reactive check: idle units sitting in danger
--------------------------------------------------------------------------------

local function CheckUnitsInDanger(frame)
    if not PUP or not PUP.toggles.smartMove then return end

    for uid, data in pairs(PUP.units) do
        if not activeReroutes[uid] and data.state == "idle" then
            local ux, uy, uz = spGetUnitPosition(uid)
            if ux then
                local cmds = spGetUnitCommands(uid, 1)
                if not cmds or #cmds == 0 then
                    local pad = 800
                    local dangers = GetDangerousEnemiesInArea(
                        ux - pad, uz - pad, ux + pad, uz + pad
                    )

                    for _, d in ipairs(dangers) do
                        if PointInCircle(ux, uz, d.x, d.z, d.range) then
                            local edgeX, edgeZ = CircleEdgePoint(d.x, d.z, d.range, ux, uz)

                            -- Validate escape point
                            local vx, vy, vz
                            if hasTestMove and data.defID then
                                vx, vy, vz = ValidateWaypoint(edgeX, edgeZ, data.defID)
                            else
                                edgeX, edgeZ = ClampToMap(edgeX, edgeZ)
                                vx = edgeX
                                vy = spGetGroundHeight(edgeX, edgeZ) or 0
                                vz = edgeZ
                            end

                            if vx then
                                spGiveOrderToUnit(uid, CMD_MOVE, { vx, vy, vz }, {})
                            end
                            break
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

        -- Cleanup stale reroutes
        for uid, rr in pairs(activeReroutes) do
            if frame - rr.frame > 300 or not PUP.units[uid] then
                activeReroutes[uid] = nil
            end
        end
    end)
    if not ok then
        Spring.Echo("[Puppeteer SmartMove] GameFrame error: " .. tostring(err))
    end
end
