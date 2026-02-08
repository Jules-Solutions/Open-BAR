-- TotallyLegal Zone Manager - Frontline and unit positioning management
-- Controls base/front/rally zones, assigns combat units, manages posture behavior.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Zones",
        desc      = "Zone & frontline manager: base/front/rally zones with posture behavior. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 204,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetTeamStartPosition = Spring.GetTeamStartPosition
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitCommands   = Spring.GetUnitCommands
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetGameFrame      = Spring.GetGameFrame
local spGiveOrderToUnit   = Spring.GiveOrderToUnit
local spEcho              = Spring.Echo

local CMD_MOVE    = CMD.MOVE
local CMD_PATROL  = CMD.PATROL
local CMD_FIGHT   = CMD.FIGHT

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
    updateFrequency    = 60,      -- every 60 frames (2s)
    baseRadius         = 800,     -- base zone radius (elmos)
    rallyRadius        = 200,     -- rally point gathering radius
    rallyThreshold     = 5,       -- send group when N units at rally
    frontAdvanceStep   = 100,     -- how far to advance front per step
    retreatThreshold   = 0.3,     -- retreat if < 30% of group survives engagement
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local zones = {
    base = { x = 0, z = 0, radius = CFG.baseRadius, set = false },
    rally = { x = 0, z = 0, radius = CFG.rallyRadius, set = false },
    front = { x = 0, z = 0, radius = 400, set = false },
}

local unitAssignments = {}  -- unitID -> "rally" | "front" | "base"
local rallyGroup = {}       -- array of unitIDs waiting at rally
local frontGroup = {}       -- array of unitIDs at front
local enemyDirection = { x = 0, z = 1 }  -- estimated direction toward enemy

-- Exposed via WG
local zoneState = {
    base = zones.base,
    front = zones.front,
    rally = zones.rally,
    assignments = unitAssignments,
}

--------------------------------------------------------------------------------
-- Zone setup
--------------------------------------------------------------------------------

local function SetupZones()
    -- Base = team start position
    local myTeamID = spGetMyTeamID()
    if spGetTeamStartPosition then
        local sx, sy, sz = spGetTeamStartPosition(myTeamID)
        if sx then
            zones.base.x = sx
            zones.base.z = sz
            zones.base.set = true
        end
    end

    if not zones.base.set then
        -- Fallback: use first unit position
        local myUnits = TL.GetMyUnits()
        for uid, _ in pairs(myUnits) do
            local x, y, z = spGetUnitPosition(uid)
            if x then
                zones.base.x = x
                zones.base.z = z
                zones.base.set = true
                break
            end
        end
    end

    if not zones.base.set then return end

    -- Estimate enemy direction: toward map center from our base
    local mapCX = (Game.mapSizeX or 8192) / 2
    local mapCZ = (Game.mapSizeZ or 8192) / 2
    local dx = mapCX - zones.base.x
    local dz = mapCZ - zones.base.z
    local len = mathSqrt(dx * dx + dz * dz)
    if len > 0 then
        enemyDirection.x = dx / len
        enemyDirection.z = dz / len
    end

    -- Rally = between base and center
    zones.rally.x = zones.base.x + enemyDirection.x * CFG.baseRadius * 0.8
    zones.rally.z = zones.base.z + enemyDirection.z * CFG.baseRadius * 0.8
    zones.rally.set = true

    -- Front = further out
    zones.front.x = zones.base.x + enemyDirection.x * CFG.baseRadius * 1.5
    zones.front.z = zones.base.z + enemyDirection.z * CFG.baseRadius * 1.5
    zones.front.set = true

    -- Lane offset: shift rally+front perpendicular to enemy direction
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local lane = strat and strat.laneAssignment or "center"
    if lane ~= "center" then
        local perpX = -enemyDirection.z
        local perpZ = enemyDirection.x
        local mapWidth = mathMax(Game.mapSizeX or 8192, 1)
        local offset = mapWidth * 0.15
        if lane == "left" then offset = -offset end
        zones.rally.x = zones.rally.x + perpX * offset
        zones.rally.z = zones.rally.z + perpZ * offset
        zones.front.x = zones.front.x + perpX * offset
        zones.front.z = zones.front.z + perpZ * offset
    end

    -- Secondary line override: use midpoint as front position
    local mapZones = WG.TotallyLegal and WG.TotallyLegal.MapZones
    if mapZones and mapZones.secondaryLine and mapZones.secondaryLine.defined then
        local sl = mapZones.secondaryLine
        zones.front.x = (sl.p1.x + sl.p2.x) / 2
        zones.front.z = (sl.p1.z + sl.p2.z) / 2
    end
end

--------------------------------------------------------------------------------
-- Unit assignment
--------------------------------------------------------------------------------

local function IsCombatUnit(defID)
    local cls = TL.GetUnitClass(defID)
    if not cls then return false end
    if cls.isFactory or cls.isBuilder or cls.isBuilding then return false end
    if cls.weaponCount == 0 then return false end
    if not cls.canMove then return false end
    return true
end

local function AssignNewUnits()
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        if not unitAssignments[uid] and IsCombatUnit(defID) then
            -- New combat unit -> send to rally
            unitAssignments[uid] = "rally"
            rallyGroup[#rallyGroup + 1] = uid

            if zones.rally.set then
                local ry = Spring.GetGroundHeight(zones.rally.x, zones.rally.z) or 0
                spGiveOrderToUnit(uid, CMD_MOVE, {zones.rally.x, ry, zones.rally.z}, {})
            end
        end
    end

    -- Cleanup dead units
    for uid, assignment in pairs(unitAssignments) do
        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            unitAssignments[uid] = nil
        end
    end

    -- Goal override: route designated units to goal destinations
    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    if goals and goals.overrides and goals.overrides.unitDestination then
        local dest = goals.overrides.unitDestination
        if dest.target and dest.unitUIDs then
            for _, uid in ipairs(dest.unitUIDs) do
                if unitAssignments[uid] then
                    local gy = Spring.GetGroundHeight(dest.target[1], dest.target[2]) or 0
                    local cmd = CMD_MOVE
                    if dest.behavior == "fight" then cmd = CMD_FIGHT
                    elseif dest.behavior == "patrol" then cmd = CMD_PATROL end
                    spGiveOrderToUnit(uid, cmd, {dest.target[1], gy, dest.target[2]}, {})
                end
            end
        end
    end
end

local function CheckRallyGroup()
    if not zones.front.set then return end

    -- Count alive units at rally
    local alive = {}
    for _, uid in ipairs(rallyGroup) do
        if unitAssignments[uid] == "rally" then
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                alive[#alive + 1] = uid
            end
        end
    end

    rallyGroup = alive

    -- Mobilization: send units immediately (threshold=1)
    local stratCfg = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local threshold = CFG.rallyThreshold
    if stratCfg and stratCfg.emergencyMode == "mobilization" then
        threshold = 1
    end

    if #rallyGroup >= threshold then
        -- Send group to front
        for _, uid in ipairs(rallyGroup) do
            unitAssignments[uid] = "front"
            frontGroup[#frontGroup + 1] = uid

            local fy = Spring.GetGroundHeight(zones.front.x, zones.front.z) or 0
            spGiveOrderToUnit(uid, CMD_FIGHT, {zones.front.x, fy, zones.front.z}, {})
        end

        spEcho("[TotallyLegal Zones] Sent " .. #rallyGroup .. " units to front line.")
        rallyGroup = {}
    end
end

local function ManageFrontLine()
    if not zones.front.set then return end

    -- Defer to strategy executor when active
    local stratExec = WG.TotallyLegal and WG.TotallyLegal.StrategyExec
    if stratExec and stratExec.activeStrategy ~= "none" then return end
    if stratExec and stratExec.activeEmergency ~= "none" then return end

    -- Clean dead from front group
    local alive = {}
    for _, uid in ipairs(frontGroup) do
        if unitAssignments[uid] == "front" then
            local health = spGetUnitHealth(uid)
            if health and health > 0 then
                alive[#alive + 1] = uid
            end
        end
    end
    frontGroup = alive

    -- Ensure front never retreats behind primary defense line
    local mapZones = WG.TotallyLegal and WG.TotallyLegal.MapZones
    if mapZones and mapZones.primaryLine and mapZones.primaryLine.defined then
        local pl = mapZones.primaryLine
        local midX = (pl.p1.x + pl.p2.x) / 2
        local midZ = (pl.p1.z + pl.p2.z) / 2
        local frontDist = TL.Dist2D(zones.base.x, zones.base.z, zones.front.x, zones.front.z)
        local lineDist = TL.Dist2D(zones.base.x, zones.base.z, midX, midZ)
        if frontDist < lineDist then
            zones.front.x = midX
            zones.front.z = midZ
        end
    end

    -- Get posture from strategy config
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local posture = strat and strat.posture or "balanced"

    -- Re-issue patrol commands to idle front units
    for _, uid in ipairs(frontGroup) do
        local cmdCount = spGetUnitCommands(uid, 0)
        if (cmdCount or 0) == 0 then
            local fy = Spring.GetGroundHeight(zones.front.x, zones.front.z) or 0
            if posture == "aggressive" then
                -- Fight toward enemy
                local targetX = zones.front.x + enemyDirection.x * CFG.frontAdvanceStep
                local targetZ = zones.front.z + enemyDirection.z * CFG.frontAdvanceStep
                local ty = Spring.GetGroundHeight(targetX, targetZ) or 0
                spGiveOrderToUnit(uid, CMD_FIGHT, {targetX, ty, targetZ}, {})
            elseif posture == "defensive" then
                -- Patrol around front zone
                spGiveOrderToUnit(uid, CMD_PATROL, {zones.front.x, fy, zones.front.z}, {})
            else
                -- Balanced: fight to front position
                spGiveOrderToUnit(uid, CMD_FIGHT, {zones.front.x, fy, zones.front.z}, {})
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Rendering (minimal zone indicators on minimap)
--------------------------------------------------------------------------------

function widget:DrawInMiniMap(sx, sz)
    if not zones.base.set then return end

    local mapSizeX = Game.mapSizeX or 8192
    local mapSizeZ = Game.mapSizeZ or 8192

    -- Scale factors
    local scaleX = sx / mapSizeX
    local scaleZ = sz / mapSizeZ

    gl.PushMatrix()
    gl.Scale(1, 1, 1)

    -- Base zone (blue circle)
    gl.Color(0.3, 0.3, 0.8, 0.3)
    gl.LineWidth(1)
    local segments = 20
    gl.BeginEnd(GL.LINE_LOOP, function()
        for i = 0, segments - 1 do
            local angle = (i / segments) * 2 * math.pi
            local px = (zones.base.x + math.cos(angle) * zones.base.radius) * scaleX
            local pz = (zones.base.z + math.sin(angle) * zones.base.radius) * scaleZ
            gl.Vertex(px, pz, 0)
        end
    end)

    -- Rally point (yellow dot)
    if zones.rally.set then
        gl.Color(0.9, 0.9, 0.2, 0.8)
        local rx = zones.rally.x * scaleX
        local rz = zones.rally.z * scaleZ
        gl.Rect(rx - 3, rz - 3, rx + 3, rz + 3)
    end

    -- Front zone (red circle)
    if zones.front.set then
        gl.Color(0.8, 0.3, 0.3, 0.3)
        gl.BeginEnd(GL.LINE_LOOP, function()
            for i = 0, segments - 1 do
                local angle = (i / segments) * 2 * math.pi
                local px = (zones.front.x + math.cos(angle) * zones.front.radius) * scaleX
                local pz = (zones.front.z + math.sin(angle) * zones.front.radius) * scaleZ
                gl.Vertex(px, pz, 0)
            end
        end)
    end

    -- Lane indicator
    local stratDraw = WG.TotallyLegal and WG.TotallyLegal.Strategy
    local laneDraw = stratDraw and stratDraw.laneAssignment or "center"
    if laneDraw ~= "center" then
        gl.Color(1, 1, 1, 0.7)
        local laneLabel = laneDraw:upper():sub(1, 1)
        local lx = zones.base.x * scaleX
        local lz = zones.base.z * scaleZ - 12
        gl.Text(laneLabel, lx, lz, 10, "oc")
    end

    gl.Color(1, 1, 1, 1)
    gl.PopMatrix()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Zones] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Zones] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    WG.TotallyLegal.Zones = zoneState

    spEcho("[TotallyLegal Zones] Zone manager ready.")
end

function widget:GameStart()
    SetupZones()
end

function widget:GameFrame(frame)
    if not TL then return end
    if frame % CFG.updateFrequency ~= 0 then return end
    if not zones.base.set then
        SetupZones()
        if not zones.base.set then return end
    end

    AssignNewUnits()
    CheckRallyGroup()
    ManageFrontLine()
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.Zones = nil
    end
end
