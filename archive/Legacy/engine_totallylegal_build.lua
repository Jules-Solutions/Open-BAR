-- TotallyLegal Build Order Executor - Automatic opening build execution
-- Executes opening build orders from strategy config or imported JSON.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_config.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Build",
        desc      = "Build order executor: automatic opening builds from config or JSON. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 201,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetTeamUnits        = Spring.GetTeamUnits
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitIsBuilding   = Spring.GetUnitIsBuilding
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetGameFrame        = Spring.GetGameFrame
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetGroundHeight     = Spring.GetGroundHeight
local spTestBuildOrder      = Spring.TestBuildOrder
local spEcho                = Spring.Echo

local CMD_STOP    = CMD.STOP

local mathSqrt  = math.sqrt
local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local mathCos   = math.cos
local mathSin   = math.sin
local mathPi    = math.pi

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 15,        -- check every 15 frames (0.5s)
    mexSearchRadius  = 1500,      -- search radius for mex spots
    buildSpacing     = 80,        -- spacing for energy buildings
    maxSpiralSteps   = 30,        -- max spiral search attempts for placement
    retryDelay       = 90,        -- frames to wait before retrying a failed item
    maxRetries       = 3,         -- max retries per item before skipping
    resourceBuffer   = 0.15,      -- need 15% of cost available to start
    buildTimeout     = 1800,      -- 60s timeout (was 20s; factories need more time)
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local commanderID = nil
local commanderDefID = nil
local buildQueue = {}           -- array of { key, type }
local currentQueueIndex = 1
local phase = "waiting"         -- "waiting", "building", "handoff", "done"
local mexSpots = nil            -- cached mex spot positions

-- Build tracking: don't advance queue until current build is DONE
local currentBuildDefID = nil   -- defID of what we're currently building
local currentBuildFrame = 0     -- frame when we issued the order
local retryCount = 0            -- retries for current item
local retryWaitUntil = 0        -- frame to wait until before retrying

-- Mapping from short keys to UnitDef names
local keyToDefID = {}           -- short_key -> defID

--------------------------------------------------------------------------------
-- Unit key resolution
--------------------------------------------------------------------------------

local function BuildKeyTable(faction)
    keyToDefID = {}

    -- Filter out wrong-faction units to avoid resolving e.g. cormex for Armada player
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
            keyToDefID[name] = defID

            if def.extractsMetal and def.extractsMetal > 0 then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["moho"] = keyToDefID["moho"] or defID
                    keyToDefID["adv_mex"] = keyToDefID["adv_mex"] or defID
                else
                    keyToDefID["mex"] = keyToDefID["mex"] or defID
                end
            end
            if def.windGenerator and def.windGenerator > 0 then
                keyToDefID["wind"] = keyToDefID["wind"] or defID
            end
            -- Bot factories: armlab, corlab, armalab, coralab (name contains "lab")
            if def.isFactory and name:find("lab") then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_bot_lab"] = keyToDefID["adv_bot_lab"] or defID
                else
                    keyToDefID["bot_lab"] = keyToDefID["bot_lab"] or defID
                end
            end
            -- Vehicle plants: armvp, corvp, armavp, coravp (name contains "vp")
            if def.isFactory and name:find("vp") then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_vehicle_plant"] = keyToDefID["adv_vehicle_plant"] or defID
                else
                    keyToDefID["vehicle_plant"] = keyToDefID["vehicle_plant"] or defID
                end
            end
            if cp.energyconv_capacity then
                keyToDefID["converter"] = keyToDefID["converter"] or defID
            end
            if cp.geothermal then
                keyToDefID["geo"] = keyToDefID["geo"] or defID
            end
            if def.energyMake and def.energyMake > 0 and def.isBuilding and not (def.windGenerator and def.windGenerator > 0) then
                if def.energyMake >= 200 then
                    keyToDefID["fusion"] = keyToDefID["fusion"] or defID
                else
                    keyToDefID["solar"] = keyToDefID["solar"] or defID
                end
            end
            -- Nano turret
            if def.isBuilding and (def.buildSpeed or 0) > 0 and not def.isFactory then
                keyToDefID["nano"] = keyToDefID["nano"] or defID
            end
            -- Radar
            if def.isBuilding and def.radarRadius and def.radarRadius > 0 then
                keyToDefID["radar"] = keyToDefID["radar"] or defID
            end
            -- LLT (cheap defense)
            if def.isBuilding and def.weapons and #def.weapons > 0 and not def.isFactory then
                local cost = def.metalCost or 0
                if cost < 200 and (tonumber(cp.techlevel) or 1) < 2 then
                    keyToDefID["llt"] = keyToDefID["llt"] or defID
                end
            end
        end
    end
end

local function ResolveKey(key)
    return keyToDefID[key:lower()] or keyToDefID[key]
end

--------------------------------------------------------------------------------
-- Mex spot management
--------------------------------------------------------------------------------

local function LoadMexSpots()
    if mexSpots then return end

    -- Method 1: Spring API
    if Spring.GetMetalMapSpots then
        local raw = Spring.GetMetalMapSpots()
        if raw and #raw > 0 then
            -- Normalize format: ensure {x=, z=} fields
            mexSpots = {}
            for i, spot in ipairs(raw) do
                local sx = spot.x or spot[1]
                local sz = spot.z or spot[3] or spot[2]
                if sx and sz then
                    mexSpots[#mexSpots + 1] = { x = sx, z = sz }
                end
            end
            if #mexSpots > 0 then
                spEcho("[TotallyLegal Build] Mex spots from API: " .. #mexSpots)
                return
            end
        end
    end

    -- Method 2: Grid scan with TestBuildOrder
    -- This finds every position on the map where a mex can be built.
    -- Works regardless of whether GetMetalMapSpots is available.
    mexSpots = {}
    local mexDefID = ResolveKey("mex")
    if not mexDefID then
        spEcho("[TotallyLegal Build] Cannot scan for mex: no mex defID resolved")
        return
    end

    local mapX = Game.mapSizeX or 8192
    local mapZ = Game.mapSizeZ or 8192
    local step = 64  -- metal map resolution is 16, but mex footprint is larger

    for gx = step, mapX - step, step do
        for gz = step, mapZ - step, step do
            local gy = spGetGroundHeight(gx, gz) or 0
            local result = spTestBuildOrder(mexDefID, gx, gy, gz, 0)
            if result and result >= 2 then
                mexSpots[#mexSpots + 1] = { x = gx, z = gz }
            end
        end
    end

    spEcho("[TotallyLegal Build] Mex spots from grid scan: " .. #mexSpots)
end

local function FindNearestMexSpot(x, z)
    LoadMexSpots()
    local mexDefID = ResolveKey("mex")
    if not mexDefID then
        spEcho("[TotallyLegal Build] ERROR: No mex defID resolved!")
        return nil, nil, nil
    end

    local bestX, bestZ = nil, nil
    local bestDist = math.huge

    for i, spot in ipairs(mexSpots) do
        local dx = spot.x - x
        local dz = spot.z - z
        local dist = mathSqrt(dx * dx + dz * dz)
        if dist < bestDist and dist < CFG.mexSearchRadius then
            -- Verify still buildable (not already occupied)
            local gy = spGetGroundHeight(spot.x, spot.z) or 0
            local result = spTestBuildOrder(mexDefID, spot.x, gy, spot.z, 0)
            if result and result > 0 then
                bestDist = dist
                bestX = spot.x
                bestZ = spot.z
            end
        end
    end

    if bestX then
        return bestX, bestZ
    end

    spEcho("[TotallyLegal Build] No buildable mex within " .. CFG.mexSearchRadius ..
           " elmos (cached spots: " .. #mexSpots .. ")")
    return nil, nil
end

--------------------------------------------------------------------------------
-- Building placement
--------------------------------------------------------------------------------

local function FindBuildPosition(builderID, defID, baseX, baseZ)
    local def = UnitDefs[defID]
    if not def then return nil, nil end

    -- For mex: find nearest buildable mex spot
    if def.extractsMetal and def.extractsMetal > 0 then
        local mx, mz, idx = FindNearestMexSpot(baseX, baseZ)
        if mx then
            return mx, mz
        end
        return nil, nil
    end

    -- For other structures: spiral outward from base
    for step = 0, CFG.maxSpiralSteps do
        local angle = step * 2.4  -- golden angle for good spread
        local radius = CFG.buildSpacing * (1 + step * 0.3)
        local tx = baseX + mathCos(angle) * radius
        local tz = baseZ + mathSin(angle) * radius

        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        tx = mathMax(64, mathMin(tx, mapSizeX - 64))
        tz = mathMax(64, mathMin(tz, mapSizeZ - 64))

        local result = spTestBuildOrder(defID, tx, spGetGroundHeight(tx, tz) or 0, tz, 0)
        if result and result > 0 then
            return tx, tz
        end
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Resource checking
--------------------------------------------------------------------------------

local function CanAfford(defID)
    local def = UnitDefs[defID]
    if not def then return false end
    local res = TL.GetTeamResources()
    local metalNeeded = (def.metalCost or 0) * CFG.resourceBuffer
    local energyNeeded = (def.energyCost or 0) * CFG.resourceBuffer
    return res.metalCurrent >= metalNeeded and res.energyCurrent >= energyNeeded
end

local function IsBuilderIdle(uid)
    local building = spGetUnitIsBuilding(uid)
    if building then return false end
    local cmds = spGetUnitCommands(uid, 1)
    return not cmds or #cmds == 0
end

--------------------------------------------------------------------------------
-- Build queue generation
--------------------------------------------------------------------------------

local function GenerateDefaultQueue()
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy
    if not strat then
        -- No strategy config yet; use hardcoded sensible default
        buildQueue = {
            { key = "mex", type = "structure" },
            { key = "mex", type = "structure" },
            { key = "wind", type = "structure" },
            { key = "wind", type = "structure" },
            { key = "bot_lab", type = "structure" },
            { key = "wind", type = "structure" },
            { key = "wind", type = "structure" },
            { key = "mex", type = "structure" },
        }
        currentQueueIndex = 1
        phase = "building"
        spEcho("[TotallyLegal Build] Using default opening (no strategy config)")
        return
    end

    buildQueue = {}

    -- Mex
    local mexCount = strat.openingMexCount or 2
    for i = 1, mexCount do
        buildQueue[#buildQueue + 1] = { key = "mex", type = "structure" }
    end

    -- Energy based on strategy
    if strat.energyStrategy == "wind_only" or strat.energyStrategy == "auto" then
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
    elseif strat.energyStrategy == "solar_only" then
        buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
        buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
    else
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
        buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
    end

    -- Factory
    if strat.unitComposition == "bots" or strat.unitComposition == "mixed" then
        buildQueue[#buildQueue + 1] = { key = "bot_lab", type = "structure" }
    else
        buildQueue[#buildQueue + 1] = { key = "vehicle_plant", type = "structure" }
    end

    -- More energy after factory
    buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
    buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }

    -- Extra mex
    buildQueue[#buildQueue + 1] = { key = "mex", type = "structure" }

    currentQueueIndex = 1
    phase = "building"
    spEcho("[TotallyLegal Build] Generated opening queue (" .. #buildQueue .. " items)")
end

--------------------------------------------------------------------------------
-- Build execution - waits for each build to COMPLETE before advancing
--------------------------------------------------------------------------------

local function FindCommander()
    local myTeamID = spGetMyTeamID()
    local units = spGetTeamUnits(myTeamID)
    if not units then return end

    for _, uid in ipairs(units) do
        local defID = spGetUnitDefID(uid)
        if defID then
            local cp = UnitDefs[defID] and UnitDefs[defID].customParams or {}
            if cp.iscommander then
                commanderID = uid
                commanderDefID = defID
                return
            end
        end
    end
end

local function ExecuteNextBuild()
    local frame = spGetGameFrame()

    -- Check if queue is done
    if currentQueueIndex > #buildQueue then
        phase = "handoff"
        return
    end

    if not commanderID then
        FindCommander()
        if not commanderID then return end
    end

    -- If we're currently building something, wait for it to complete
    if currentBuildDefID then
        -- Check: is commander still actively building?
        local building = spGetUnitIsBuilding(commanderID)
        if building then
            -- Still working, keep waiting
            return
        end

        -- Commander is no longer building. Check if it has queued commands.
        local cmds = spGetUnitCommands(commanderID, 1)
        if cmds and #cmds > 0 then
            -- Has commands in queue (walking to build site, etc.)
            -- But check for timeout - if stuck too long, something went wrong
            if frame - currentBuildFrame > CFG.buildTimeout then
                spEcho("[TotallyLegal Build] Build timeout for item " .. currentQueueIndex .. ", cancelling")
                spGiveOrderToUnit(commanderID, CMD_STOP, {}, {})
                currentBuildDefID = nil
                retryCount = retryCount + 1
                if retryCount > CFG.maxRetries then
                    spEcho("[TotallyLegal Build] Max retries for: " .. buildQueue[currentQueueIndex].key .. ", skipping")
                    currentQueueIndex = currentQueueIndex + 1
                    retryCount = 0
                end
                retryWaitUntil = frame + 30
            end
            return
        end

        -- Commander idle with no commands = build completed (or order was cancelled)
        spEcho("[TotallyLegal Build] Completed: " .. buildQueue[currentQueueIndex].key .. " (" .. currentQueueIndex .. "/" .. #buildQueue .. ")")
        currentBuildDefID = nil
        retryCount = 0
        currentQueueIndex = currentQueueIndex + 1

        -- Check if queue is now done
        if currentQueueIndex > #buildQueue then
            phase = "handoff"
            return
        end
    end

    -- Wait for retry delay
    if frame < retryWaitUntil then return end

    -- Commander must be idle to start new build
    if not IsBuilderIdle(commanderID) then return end

    local item = buildQueue[currentQueueIndex]
    if not item then
        phase = "handoff"
        return
    end

    local defID = ResolveKey(item.key)
    if not defID then
        spEcho("[TotallyLegal Build] Unknown unit key: " .. item.key .. ", skipping")
        currentQueueIndex = currentQueueIndex + 1
        retryCount = 0
        return
    end

    -- Resource check: can we afford to start this build?
    if not CanAfford(defID) then
        -- Wait for resources, don't skip
        return
    end

    local cx, cy, cz = spGetUnitPosition(commanderID)
    if not cx then return end

    local bx, bz = FindBuildPosition(commanderID, defID, cx, cz)
    if not bx then
        -- Can't place - retry later or skip if too many retries
        retryCount = retryCount + 1
        if retryCount > CFG.maxRetries then
            spEcho("[TotallyLegal Build] Cannot place: " .. item.key .. " after " .. CFG.maxRetries .. " retries, skipping")
            currentQueueIndex = currentQueueIndex + 1
            retryCount = 0
        else
            retryWaitUntil = frame + CFG.retryDelay
        end
        return
    end

    local by = spGetGroundHeight(bx, bz) or 0
    spGiveOrderToUnit(commanderID, -defID, {bx, by, bz}, {})

    -- Track this build - don't advance until it completes
    currentBuildDefID = defID
    currentBuildFrame = frame
    spEcho("[TotallyLegal Build] Building: " .. item.key .. " (" .. currentQueueIndex .. "/" .. #buildQueue .. ")")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Build] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Build] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildKeyTable("unknown")  -- faction unknown at Initialize; rebuilt at GameStart

    -- Expose build phase to other widgets
    WG.TotallyLegal.BuildPhase = phase

    spEcho("[TotallyLegal Build] Pre-faction keys (will rebuild at GameStart)")
end

function widget:GameStart()
    FindCommander()
    if commanderID then
        spEcho("[TotallyLegal Build] Commander found: " .. commanderID)
    else
        spEcho("[TotallyLegal Build] WARNING: Commander not found at GameStart")
    end

    -- Detect faction from commander and rebuild key table with faction filter
    local faction = "unknown"
    if commanderDefID and UnitDefs[commanderDefID] then
        local name = (UnitDefs[commanderDefID].name or ""):lower()
        if name:find("^arm") then faction = "armada"
        elseif name:find("^cor") then faction = "cortex" end
    end
    spEcho("[TotallyLegal Build] Faction: " .. faction)

    BuildKeyTable(faction)
    spEcho("[TotallyLegal Build] Keys: mex=" .. tostring(keyToDefID["mex"] ~= nil) ..
           " wind=" .. tostring(keyToDefID["wind"] ~= nil) ..
           " solar=" .. tostring(keyToDefID["solar"] ~= nil) ..
           " bot_lab=" .. tostring(keyToDefID["bot_lab"] ~= nil) ..
           " vehicle_plant=" .. tostring(keyToDefID["vehicle_plant"] ~= nil))

    -- Rebuild mex spots with correct faction defID
    mexSpots = nil
    LoadMexSpots()
    spEcho("[TotallyLegal Build] Mex spots: " .. (mexSpots and #mexSpots or 0) ..
           " (API available: " .. tostring(Spring.GetMetalMapSpots ~= nil) .. ")")

    GenerateDefaultQueue()
    WG.TotallyLegal.BuildPhase = phase
end

function widget:GameFrame(frame)
    if not TL then return end
    if phase == "done" then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    if phase == "waiting" then
        if frame > 30 then
            FindCommander()
            if commanderID and #buildQueue == 0 then
                GenerateDefaultQueue()
            end
        end
    elseif phase == "building" then
        ExecuteNextBuild()
    elseif phase == "handoff" then
        spEcho("[TotallyLegal Build] Opening complete. Handing off to economy manager.")
        phase = "done"
        -- Signal to other widgets
        if WG.TotallyLegal then
            WG.TotallyLegal.BuildPhase = "done"
        end
    end
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.BuildPhase = nil
    end
end
