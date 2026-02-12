-- Unit Puppeteer: Raid - Automated mex raiding patrol
-- Five units on infinite loop. Economy death by a thousand cuts.
-- Scans for enemy metal extractors, builds optimal patrol route,
-- assigns fast units to cycle through targets destroying undefended mexes.
-- Integrates with the full Puppeteer micro stack (dodge, range-keep, jitter)
-- so raiders are nearly impossible to kill.
--
-- Usage: Select fast units, toggle Raid ON in the Puppeteer panel.
-- Raiders will automatically patrol and destroy enemy mexes.
-- Toggle OFF to release units. Player commands on a raider release it.
--
-- PvE/Unranked ONLY. Requires: auto_puppeteer_core.lua
-- Requires: 01_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "Puppeteer Raid",
        desc      = "Automated mex raiding patrol. Select fast units, toggle ON. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 109,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spGetGameFrame        = Spring.GetGameFrame
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local spIsUnitAllied        = Spring.IsUnitAllied
local spGetMyTeamID         = Spring.GetMyTeamID
local spEcho                = Spring.Echo

local CMD_MOVE    = CMD.MOVE
local CMD_ATTACK  = CMD.ATTACK
local CMD_FIGHT   = CMD.FIGHT
local CMD_STOP    = CMD.STOP
local CMD_PATROL  = CMD.PATROL

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor

--------------------------------------------------------------------------------
-- Core references
--------------------------------------------------------------------------------

local TL  = nil
local PUP = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    scanFrequency    = 90,      -- scan for enemy mexes every ~3 seconds
    routeFrequency   = 150,     -- rebuild route every ~5 seconds
    processFrequency = 5,       -- process raider actions every N frames
    defendedRadius   = 500,     -- turrets within this range = "defended"
    arrivalRadius    = 200,     -- close enough to start attacking
    skipDefended     = true,    -- skip mexes with nearby static defenses
    maxTargets       = 40,      -- cap on tracked mex positions
    staleTimeout     = 900,     -- remove unseen mexes after ~30 seconds
    attackTimeout    = 300,     -- skip target if attacking for > 10 seconds
    progressTimeout  = 60,      -- skip target if no progress in ~2 seconds
    minRaidSpeed     = 40,      -- minimum unit speed to be a raider
    reissueInterval  = 60,      -- re-issue move command every ~2 seconds
}

local mapSizeX = 0
local mapSizeZ = 0

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local knownMexes = {}       -- mexUnitID -> { x, z, defID, lastSeen, defended }
local raidSquad = {}        -- unitID -> { targetIdx, state, lastOrderFrame, attackStart, lastDist }
local raidRoute = {}        -- ordered list: { mexID, x, z }
local raidSquadCount = 0
local prevRaidToggle = false
local lastScanFrame = 0
local lastRouteFrame = 0

-- UnitDef classification caches
local mexDefIDs = {}        -- defID -> true (is a metal extractor)
local turretDefIDs = {}     -- defID -> true (is a static defense with ground weapons)

--------------------------------------------------------------------------------
-- Build unit classification tables at init
--------------------------------------------------------------------------------

local function BuildUnitClassTables()
    for defID, def in pairs(UnitDefs) do
        -- Metal extractors
        if def.extractsMetal and def.extractsMetal > 0 then
            mexDefIDs[defID] = true
        end

        -- Static defenses: non-mobile buildings with ground-capable weapons
        if def.isBuilding or (not def.canMove and def.isImmobile) then
            if def.weapons then
                for _, w in ipairs(def.weapons) do
                    local wDefID = w.weaponDef
                    if wDefID and WeaponDefs[wDefID] then
                        local wd = WeaponDefs[wDefID]
                        if wd.canAttackGround ~= false and (wd.range or 0) > 50 then
                            turretDefIDs[defID] = true
                            break
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Dist2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return mathSqrt(dx * dx + dz * dz)
end

--------------------------------------------------------------------------------
-- Scan for enemy metal extractors
--------------------------------------------------------------------------------

local function ScanForEnemyMexes(frame)
    local getUnits = Spring.GetVisibleUnits or Spring.GetAllUnits
    local units = getUnits()
    if not units then return end

    for _, uid in ipairs(units) do
        if not spIsUnitAllied(uid) then
            local defID = spGetUnitDefID(uid)
            if defID and mexDefIDs[defID] then
                local mx, my, mz = spGetUnitPosition(uid)
                if mx then
                    knownMexes[uid] = {
                        x        = mx,
                        z        = mz,
                        defID    = defID,
                        lastSeen = frame,
                        defended = false,
                    }
                end
            end
        end
    end

    -- Prune stale entries (mexes not seen for too long — likely destroyed)
    for mexID, data in pairs(knownMexes) do
        if (frame - data.lastSeen) > CFG.staleTimeout then
            knownMexes[mexID] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Check if a position is defended by static defenses
--------------------------------------------------------------------------------

local function IsPositionDefended(x, z)
    local pad = CFG.defendedRadius
    local units = spGetUnitsInRectangle(
        mathMax(0, x - pad), mathMax(0, z - pad),
        mathMin(mapSizeX, x + pad), mathMin(mapSizeZ, z + pad)
    )
    if not units then return false end

    for _, uid in ipairs(units) do
        if not spIsUnitAllied(uid) then
            local defID = spGetUnitDefID(uid)
            if defID and turretDefIDs[defID] then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Build patrol route (nearest-neighbor TSP approximation)
--------------------------------------------------------------------------------

local function BuildPatrolRoute()
    -- Collect undefended targets
    local targets = {}
    for mexID, data in pairs(knownMexes) do
        local defended = false
        if CFG.skipDefended then
            defended = IsPositionDefended(data.x, data.z)
            data.defended = defended
        end

        if not defended then
            if #targets < CFG.maxTargets then
                targets[#targets + 1] = { mexID = mexID, x = data.x, z = data.z }
            end
        end
    end

    if #targets == 0 then
        raidRoute = {}
        return
    end

    if #targets == 1 then
        raidRoute = targets
        return
    end

    -- Compute centroid of all targets
    local cx, cz = 0, 0
    for _, t in ipairs(targets) do
        cx = cx + t.x
        cz = cz + t.z
    end
    cx = cx / #targets
    cz = cz / #targets

    -- Find nearest to centroid as starting point
    local bestStart = 1
    local bestDist = math.huge
    for i, t in ipairs(targets) do
        local d = Dist2D(cx, cz, t.x, t.z)
        if d < bestDist then
            bestDist = d
            bestStart = i
        end
    end

    -- Nearest-neighbor greedy route
    local visited = {}
    local route = {}
    local current = bestStart

    for _ = 1, #targets do
        visited[current] = true
        route[#route + 1] = targets[current]

        -- Find nearest unvisited
        local nearest = nil
        local nearestDist = math.huge
        for i, t in ipairs(targets) do
            if not visited[i] then
                local d = Dist2D(targets[current].x, targets[current].z, t.x, t.z)
                if d < nearestDist then
                    nearestDist = d
                    nearest = i
                end
            end
        end

        if nearest then
            current = nearest
        end
    end

    raidRoute = route
end

--------------------------------------------------------------------------------
-- Assign raiders evenly across the route
--------------------------------------------------------------------------------

local function AssignRaidersToRoute()
    if #raidRoute == 0 then return end

    local raiders = {}
    for uid, _ in pairs(raidSquad) do
        raiders[#raiders + 1] = uid
    end

    if #raiders == 0 then return end

    -- Distribute evenly: raider i starts at target (i * M/N)
    local spacing = mathMax(1, mathFloor(#raidRoute / #raiders))
    for i, uid in ipairs(raiders) do
        local targetIdx = ((i - 1) * spacing) % #raidRoute + 1
        raidSquad[uid].targetIdx = targetIdx
        raidSquad[uid].state = "moving"
        raidSquad[uid].lastOrderFrame = 0
        raidSquad[uid].attackStart = 0
        raidSquad[uid].lastDist = nil
    end
end

--------------------------------------------------------------------------------
-- Advance a raider to the next target in the route
--------------------------------------------------------------------------------

local function AdvanceToNextTarget(uid)
    local data = raidSquad[uid]
    if not data then return end

    -- Cycle through route to find next undefended target
    local nextIdx = data.targetIdx + 1
    if nextIdx > #raidRoute then nextIdx = 1 end

    local checked = 0
    while checked < #raidRoute do
        local target = raidRoute[nextIdx]
        if target then
            local mexData = knownMexes[target.mexID]
            if mexData and not mexData.defended then
                break  -- found a valid target
            end
        end
        nextIdx = nextIdx + 1
        if nextIdx > #raidRoute then nextIdx = 1 end
        checked = checked + 1
    end

    data.targetIdx = nextIdx
    data.state = "moving"
    data.attackStart = 0
    data.lastDist = nil
    data.lastOrderFrame = 0
end

--------------------------------------------------------------------------------
-- Process raider actions
--------------------------------------------------------------------------------

local function ProcessRaiders(frame)
    if #raidRoute == 0 then return end

    for uid, data in pairs(raidSquad) do
        -- Check raider is still alive
        local ux, uy, uz = spGetUnitPosition(uid)
        if not ux then
            raidSquad[uid] = nil
            raidSquadCount = raidSquadCount - 1
            goto continue_raider
        end

        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            raidSquad[uid] = nil
            raidSquadCount = raidSquadCount - 1
            goto continue_raider
        end

        -- Get current target
        local target = raidRoute[data.targetIdx]
        if not target then
            -- Route was rebuilt, reset
            data.targetIdx = mathMin(data.targetIdx, #raidRoute)
            if data.targetIdx < 1 then data.targetIdx = 1 end
            target = raidRoute[data.targetIdx]
            if not target then goto continue_raider end
        end

        -----------------------------------------------------------------------
        -- MOVING: traveling to next target
        -----------------------------------------------------------------------
        if data.state == "moving" then
            local dist = Dist2D(ux, uz, target.x, target.z)

            if dist < CFG.arrivalRadius then
                -- Arrived! Check if mex still exists
                local mx, my, mz = spGetUnitPosition(target.mexID)
                if mx then
                    -- Attack the mex
                    spGiveOrderToUnit(uid, CMD_ATTACK, { target.mexID }, {})
                    data.state = "attacking"
                    data.attackStart = frame
                    data.lastOrderFrame = frame
                else
                    -- Mex is gone, remove and advance
                    knownMexes[target.mexID] = nil
                    AdvanceToNextTarget(uid)
                end
            else
                -- Still traveling
                local timeSinceOrder = frame - data.lastOrderFrame

                if timeSinceOrder > CFG.reissueInterval then
                    -- Check if making progress
                    if data.lastDist and dist >= (data.lastDist - 10) then
                        -- No progress for reissueInterval frames
                        -- Something is blocking (range-keep, terrain, defenders)
                        -- Mark as defended and skip
                        local mexData = knownMexes[target.mexID]
                        if mexData then mexData.defended = true end
                        AdvanceToNextTarget(uid)
                    else
                        -- Still progressing, re-issue move command
                        -- (handles SmartMove reroutes and range-keep retreats)
                        local ty = spGetGroundHeight(target.x, target.z) or 0
                        spGiveOrderToUnit(uid, CMD_MOVE, { target.x, ty, target.z }, {})
                        data.lastOrderFrame = frame
                        data.lastDist = dist
                    end
                end
            end

        -----------------------------------------------------------------------
        -- ATTACKING: engaging the mex
        -----------------------------------------------------------------------
        elseif data.state == "attacking" then
            -- Check if mex is destroyed
            local mx, my, mz = spGetUnitPosition(target.mexID)
            if not mx then
                -- Mex destroyed! Advance to next target
                knownMexes[target.mexID] = nil
                AdvanceToNextTarget(uid)
            elseif (frame - data.attackStart) > CFG.attackTimeout then
                -- Taking too long — probably defended, skip
                local mexData = knownMexes[target.mexID]
                if mexData then mexData.defended = true end
                AdvanceToNextTarget(uid)
            else
                -- Keep attacking. Re-issue if command got cleared
                -- (dodge might have issued a MOVE that cleared the ATTACK)
                local cmds = spGetUnitCommands(uid, 1)
                if not cmds or #cmds == 0 then
                    spGiveOrderToUnit(uid, CMD_ATTACK, { target.mexID }, {})
                    data.lastOrderFrame = frame
                end
            end
        end

        ::continue_raider::
    end
end

--------------------------------------------------------------------------------
-- Command interception: player commands release raiders
--------------------------------------------------------------------------------

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if not PUP then return false end
    if not PUP.toggles.raid then return false end
    if raidSquadCount == 0 then return false end

    -- Player manually commanding a raider releases it from the squad
    if cmdID == CMD_MOVE or cmdID == CMD_STOP or cmdID == CMD_PATROL
    or cmdID == CMD_FIGHT or cmdID == CMD_ATTACK then
        local selected = spGetSelectedUnits()
        if selected then
            for _, uid in ipairs(selected) do
                if raidSquad[uid] then
                    raidSquad[uid] = nil
                    raidSquadCount = raidSquadCount - 1
                    if PUP.units[uid] then
                        PUP.units[uid].state = "idle"
                    end
                end
            end
        end
    end

    return false  -- don't consume the command
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[Puppeteer Raid] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[Puppeteer Raid] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    PUP = TL.Puppeteer
    if not PUP then
        spEcho("[Puppeteer Raid] Puppeteer Core not loaded. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    mapSizeX = Game.mapSizeX or 8192
    mapSizeZ = Game.mapSizeZ or 8192

    BuildUnitClassTables()
    spEcho("[Puppeteer Raid] Enabled. Select fast units and toggle Raid ON.")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    PUP = WG.TotallyLegal.Puppeteer
    if not PUP then return end

    local raidOn = PUP.toggles.raid

    ---------------------------------------------------------------------------
    -- Toggle ON: capture selected units as raid squad
    ---------------------------------------------------------------------------
    if raidOn and not prevRaidToggle then
        local selected = spGetSelectedUnits()
        if selected and #selected > 0 then
            raidSquad = {}
            raidSquadCount = 0
            for _, uid in ipairs(selected) do
                local unitData = PUP.units[uid]
                if unitData and unitData.speed >= CFG.minRaidSpeed then
                    raidSquad[uid] = {
                        targetIdx      = 1,
                        state          = "moving",
                        lastOrderFrame = 0,
                        attackStart    = 0,
                        lastDist       = nil,
                    }
                    raidSquadCount = raidSquadCount + 1
                    unitData.state = "raiding"
                end
            end

            if raidSquadCount > 0 then
                spEcho("[Puppeteer Raid] Squad: " .. raidSquadCount .. " raiders assigned.")
                lastScanFrame = 0    -- force immediate scan
                lastRouteFrame = 0   -- force immediate route build
            else
                spEcho("[Puppeteer Raid] No fast units selected (need speed >= " .. CFG.minRaidSpeed .. ").")
            end
        else
            spEcho("[Puppeteer Raid] No units selected. Select fast units first.")
        end
    end

    ---------------------------------------------------------------------------
    -- Toggle OFF: release all raiders
    ---------------------------------------------------------------------------
    if not raidOn and prevRaidToggle then
        for uid, _ in pairs(raidSquad) do
            if PUP.units[uid] then
                PUP.units[uid].state = "idle"
            end
            spGiveOrderToUnit(uid, CMD_STOP, {}, {})
        end
        raidSquad = {}
        raidSquadCount = 0
        raidRoute = {}
        knownMexes = {}
        spEcho("[Puppeteer Raid] Squad released.")
    end

    prevRaidToggle = raidOn

    if not raidOn or raidSquadCount == 0 then return end

    ---------------------------------------------------------------------------
    -- Main raid loop
    ---------------------------------------------------------------------------
    local ok, err = pcall(function()
        -- Periodic scan for enemy mexes
        if (frame - lastScanFrame) >= CFG.scanFrequency then
            ScanForEnemyMexes(frame)
            lastScanFrame = frame
        end

        -- Periodic route rebuild
        if (frame - lastRouteFrame) >= CFG.routeFrequency then
            BuildPatrolRoute()
            if #raidRoute > 0 then
                AssignRaidersToRoute()
            end
            lastRouteFrame = frame
        end

        -- Process raider actions
        if frame % CFG.processFrequency == 0 then
            ProcessRaiders(frame)
        end
    end)
    if not ok then
        spEcho("[Puppeteer Raid] GameFrame error: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Unit lifecycle
--------------------------------------------------------------------------------

function widget:UnitDestroyed(unitID)
    -- Raider died
    if raidSquad[unitID] then
        raidSquad[unitID] = nil
        raidSquadCount = mathMax(0, raidSquadCount - 1)
    end

    -- Known mex destroyed
    if knownMexes[unitID] then
        knownMexes[unitID] = nil
    end
end

function widget:Shutdown()
    -- Release all raiders
    if PUP then
        for uid, _ in pairs(raidSquad) do
            if PUP.units[uid] then
                PUP.units[uid].state = "idle"
            end
        end
    end
    raidSquad = {}
    raidRoute = {}
    knownMexes = {}
end
