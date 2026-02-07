--------------------------------------------------------------------------------
-- sim_executor.lua — Headless Build Order Executor Widget
--------------------------------------------------------------------------------
-- Reads a build order from JSON, executes it in a real BAR game (headless or
-- normal), logs economy snapshots, and writes results to JSON on completion.
--
-- Communication:
--   Input:  <write_dir>/input/build_order.json
--   Output: <write_dir>/output/sim_result.json
--
-- The write_dir is auto-detected: VFS.GetWriteDir() .. "headless/"
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "Sim Executor",
        desc      = "Executes build orders and logs economy for headless simulation",
        author    = "BAR Build Order Simulator",
        date      = "2026",
        license   = "MIT",
        layer     = 0,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SNAPSHOT_INTERVAL = 30   -- frames between economy snapshots (30 frames ≈ 1 second)
local LOG_PREFIX = "[SimExecutor] "

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local writeDir           -- filesystem path for I/O
local buildOrder         -- parsed JSON table
local targetFrame        -- frame at which to stop and write results
local myTeamID
local myAllyTeamID

-- Builder tracking
local commanderID        -- unitID of our commander
local commanderQueue     -- list of {game_id=..., type=...}
local commanderQueueIdx = 1

-- Factories: { unitID = { queue = {...}, idx = 1 } }
local factories = {}
local factoryCount = 0

-- Constructors (mobile builders): { unitID = { queue = {...}, idx = 1 } }
local constructors = {}
local conCount = 0

-- Mex spots
local mexSpots = {}          -- sorted by distance from start pos: { {x, z, claimed} }
local nextMexSpotIdx = 1     -- next unclaimed mex spot

-- Economy snapshots
local snapshots = {}

-- Completion log: { {frame, game_id, builder_type} }
local completionLog = {}

-- Stall tracking
local stallEvents = {}
local currentStall = nil
local totalMetalStallFrames = 0
local totalEnergyStallFrames = 0

-- Milestones
local milestones = {}

-- Peaks
local peakMetalIncome = 0
local peakEnergyIncome = 0

-- Unit counts for tracking
local unitCounts = {}

-- Building placement
local baseX, baseZ       -- start position
local placementAngle = 0 -- current angle for spiral placement
local placementRadius = 120
local placementStep = 60

-- Flag: are we done?
local finished = false

--------------------------------------------------------------------------------
-- JSON helpers (minimal parser/writer)
--------------------------------------------------------------------------------

-- Use Spring's built-in JSON if available, otherwise a minimal implementation
local json

local function initJSON()
    -- Spring 105+ has Spring.Utilities.json
    if Spring.Utilities and Spring.Utilities.json then
        json = Spring.Utilities.json
        return
    end

    -- Try to load from VFS
    local success, mod = pcall(function()
        return VFS.Include("LuaUI/Utilities/json.lua") or
               VFS.Include("lualibs/json.lua")
    end)
    if success and mod then
        json = mod
        return
    end

    -- Minimal fallback: we only need decode and encode for simple structures
    json = {}

    -- Minimal JSON decoder
    function json.decode(str)
        -- Use Spring's loadstring with JSON-to-Lua transformation
        -- Replace JSON null/true/false, convert arrays
        local s = str
        s = s:gsub("null", "nil")
        -- This is a simplified approach; for production use a real JSON lib
        -- We'll use a pattern-based approach
        local func, err = loadstring("return " .. s:gsub("%[", "{"):gsub("%]", "}"):gsub(":", "="):gsub('"(%w+)"%s*=', '["%1"]='))
        if func then
            return func()
        end
        Spring.Echo(LOG_PREFIX .. "JSON decode error: " .. tostring(err))
        return nil
    end

    -- Minimal JSON encoder
    function json.encode(tbl)
        local function serialize(val, indent)
            indent = indent or ""
            local t = type(val)
            if t == "nil" then
                return "null"
            elseif t == "boolean" then
                return val and "true" or "false"
            elseif t == "number" then
                if val ~= val then return "null" end  -- NaN
                if val == math.huge or val == -math.huge then return "null" end
                return string.format("%.6g", val)
            elseif t == "string" then
                return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
            elseif t == "table" then
                -- Check if array
                local isArray = (#val > 0)
                if isArray then
                    local parts = {}
                    local nextIndent = indent .. "  "
                    for i, v in ipairs(val) do
                        parts[i] = nextIndent .. serialize(v, nextIndent)
                    end
                    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
                else
                    local parts = {}
                    local nextIndent = indent .. "  "
                    for k, v in pairs(val) do
                        parts[#parts + 1] = nextIndent .. '"' .. tostring(k) .. '": ' .. serialize(v, nextIndent)
                    end
                    if #parts == 0 then return "{}" end
                    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
                end
            end
            return "null"
        end
        return serialize(tbl, "")
    end
end

--------------------------------------------------------------------------------
-- File I/O helpers
--------------------------------------------------------------------------------

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then
        Spring.Echo(LOG_PREFIX .. "ERROR: Cannot write to " .. path)
        return false
    end
    f:write(content)
    f:close()
    return true
end

--------------------------------------------------------------------------------
-- Mex spot discovery
--------------------------------------------------------------------------------

local function discoverMexSpots()
    -- Try Spring API first
    local spots
    if Spring.GetMetalMapSpots then
        spots = Spring.GetMetalMapSpots()
    end

    if not spots or #spots == 0 then
        -- Fallback: scan the metal map manually
        Spring.Echo(LOG_PREFIX .. "No metal spots from API, scanning metal map...")
        spots = {}
        local mapX = Game.mapSizeX
        local mapZ = Game.mapSizeZ
        local step = 32  -- check every 32 elmos

        for x = 0, mapX, step do
            for z = 0, mapZ, step do
                local metal = Spring.GetMetalAmount(x, z)  -- deprecated but works
                if metal and metal > 0 then
                    spots[#spots + 1] = { x = x, y = Spring.GetGroundHeight(x, z), z = z, metal = metal }
                end
            end
        end
    end

    if not spots or #spots == 0 then
        Spring.Echo(LOG_PREFIX .. "WARNING: No metal spots found on map!")
        return
    end

    -- Sort by distance from our start position
    table.sort(spots, function(a, b)
        local da = (a.x - baseX)^2 + (a.z - baseZ)^2
        local db = (b.x - baseX)^2 + (b.z - baseZ)^2
        return da < db
    end)

    for i, spot in ipairs(spots) do
        mexSpots[i] = { x = spot.x, z = spot.z, claimed = false }
    end

    Spring.Echo(LOG_PREFIX .. "Found " .. #mexSpots .. " metal spots, sorted by distance from start")
end

--------------------------------------------------------------------------------
-- Build position finding
--------------------------------------------------------------------------------

local function getNextMexPosition()
    while nextMexSpotIdx <= #mexSpots do
        local spot = mexSpots[nextMexSpotIdx]
        if not spot.claimed then
            spot.claimed = true
            nextMexSpotIdx = nextMexSpotIdx + 1
            return spot.x, spot.z
        end
        nextMexSpotIdx = nextMexSpotIdx + 1
    end
    return nil, nil
end

local function getSpiralPosition()
    -- Spiral outward from base for energy/misc buildings
    local x = baseX + math.cos(placementAngle) * placementRadius
    local z = baseZ + math.sin(placementAngle) * placementRadius

    placementAngle = placementAngle + 1.2  -- ~69 degrees
    if placementAngle > math.pi * 2 then
        placementAngle = placementAngle - math.pi * 2
        placementRadius = placementRadius + placementStep
    end

    return x, z
end

local function getFactoryPosition()
    -- Place factory near base, offset from center
    local x = baseX + 200
    local z = baseZ + 100
    return x, z
end

local function getNanoPosition(factoryID)
    -- Place nano near the factory it assists
    if factoryID and Spring.ValidUnitID(factoryID) then
        local fx, fy, fz = Spring.GetUnitPosition(factoryID)
        if fx then
            return fx - 80, fz  -- offset to the side
        end
    end
    return baseX + 120, baseZ + 100
end

local function getBuildPosition(unitDefName, builderID)
    local unitDefID = UnitDefNames[unitDefName]
    if not unitDefID then
        Spring.Echo(LOG_PREFIX .. "WARNING: Unknown unitDef: " .. unitDefName)
        return nil, nil
    end

    local uDef = UnitDefs[unitDefID.id or unitDefID]

    -- Check if this is a mex (extracts metal)
    local isMex = false
    if uDef and uDef.extractsMetal and uDef.extractsMetal > 0 then
        isMex = true
    elseif unitDefName:find("mex") or unitDefName:find("moho") then
        isMex = true
    end

    if isMex then
        return getNextMexPosition()
    end

    -- Check if factory
    local isFactory = false
    if uDef and uDef.isFactory then
        isFactory = true
    elseif unitDefName:find("lab") or unitDefName:find("vp") or unitDefName:find("ap") then
        isFactory = true
    end

    if isFactory then
        return getFactoryPosition()
    end

    -- Check if nano
    if unitDefName:find("nanotc") then
        -- Find first factory to assist
        for fid, _ in pairs(factories) do
            return getNanoPosition(fid)
        end
        return getNanoPosition(nil)
    end

    -- Default: spiral placement for energy, defense, etc.
    return getSpiralPosition()
end

--------------------------------------------------------------------------------
-- Build command issuance
--------------------------------------------------------------------------------

local function issueBuildCommand(builderID, unitDefName)
    local unitDefID = UnitDefNames[unitDefName]
    if not unitDefID then
        Spring.Echo(LOG_PREFIX .. "WARNING: Cannot find unitDef for: " .. unitDefName)
        return false
    end

    local defID = unitDefID.id or unitDefID

    local x, z = getBuildPosition(unitDefName, builderID)
    if not x or not z then
        Spring.Echo(LOG_PREFIX .. "WARNING: No build position for " .. unitDefName)
        return false
    end

    local y = Spring.GetGroundHeight(x, z) or 0

    -- Find valid build position near target
    local bx, by, bz = Spring.ClosestBuildPos(myTeamID, defID, x, y, z, 400, 0)
    if bx then
        x, z = bx, bz
    end

    -- Issue build command
    Spring.GiveOrderToUnit(builderID, -defID, { x, y, z }, 0)
    return true
end

local function issueProduceCommand(factoryID, unitDefName)
    local unitDefID = UnitDefNames[unitDefName]
    if not unitDefID then
        Spring.Echo(LOG_PREFIX .. "WARNING: Cannot find unitDef for production: " .. unitDefName)
        return false
    end

    local defID = unitDefID.id or unitDefID

    -- Factory build command: use negative unitDefID with no position
    Spring.GiveOrderToUnit(factoryID, -defID, {}, 0)
    return true
end

--------------------------------------------------------------------------------
-- Builder management
--------------------------------------------------------------------------------

local function processCommanderQueue()
    if not commanderID or not Spring.ValidUnitID(commanderID) then return end
    if not commanderQueue then return end
    if commanderQueueIdx > #commanderQueue then return end

    -- Check if commander is idle (no commands)
    local cmds = Spring.GetUnitCommands(commanderID, 1)
    if cmds and #cmds > 0 then return end  -- busy

    local item = commanderQueue[commanderQueueIdx]
    if not item then return end

    local gameID = item.game_id
    local success = issueBuildCommand(commanderID, gameID)
    if success then
        Spring.Echo(LOG_PREFIX .. "Commander building: " .. gameID .. " (#" .. commanderQueueIdx .. ")")
        commanderQueueIdx = commanderQueueIdx + 1
    else
        Spring.Echo(LOG_PREFIX .. "Commander: failed to build " .. gameID .. ", skipping")
        commanderQueueIdx = commanderQueueIdx + 1
    end
end

local function processFactoryQueues()
    for unitID, data in pairs(factories) do
        if not Spring.ValidUnitID(unitID) then
            factories[unitID] = nil
        elseif data.idx <= #data.queue then
            -- Check if factory has an empty build queue
            local cmds = Spring.GetUnitCommands(unitID, 1)
            if not cmds or #cmds == 0 then
                local item = data.queue[data.idx]
                if item then
                    local success = issueProduceCommand(unitID, item.game_id)
                    if success then
                        Spring.Echo(LOG_PREFIX .. "Factory producing: " .. item.game_id .. " (#" .. data.idx .. ")")
                        data.idx = data.idx + 1
                    else
                        data.idx = data.idx + 1  -- skip on failure
                    end
                end
            end
        end
    end
end

local function processConstructorQueues()
    for unitID, data in pairs(constructors) do
        if not Spring.ValidUnitID(unitID) then
            constructors[unitID] = nil
        elseif data.idx <= #data.queue then
            local cmds = Spring.GetUnitCommands(unitID, 1)
            if not cmds or #cmds == 0 then
                local item = data.queue[data.idx]
                if item then
                    local success = issueBuildCommand(unitID, item.game_id)
                    if success then
                        Spring.Echo(LOG_PREFIX .. "Constructor building: " .. item.game_id .. " (#" .. data.idx .. ")")
                        data.idx = data.idx + 1
                    else
                        data.idx = data.idx + 1
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Economy tracking
--------------------------------------------------------------------------------

local function recordSnapshot(frame)
    local mCur, mStor, mPull, mInc, mExp, mShare, mSent, mRec = Spring.GetTeamResources(myTeamID, "metal")
    local eCur, eStor, ePull, eInc, eExp, eShare, eSent, eRec = Spring.GetTeamResources(myTeamID, "energy")

    if not mCur then return end

    local totalBP = 0
    -- Commander BP
    if commanderID and Spring.ValidUnitID(commanderID) then
        local def = UnitDefs[Spring.GetUnitDefID(commanderID)]
        if def then totalBP = totalBP + (def.buildSpeed or 0) end
    end
    for fid, _ in pairs(factories) do
        if Spring.ValidUnitID(fid) then
            local def = UnitDefs[Spring.GetUnitDefID(fid)]
            if def then totalBP = totalBP + (def.buildSpeed or 0) end
        end
    end
    for cid, _ in pairs(constructors) do
        if Spring.ValidUnitID(cid) then
            local def = UnitDefs[Spring.GetUnitDefID(cid)]
            if def then totalBP = totalBP + (def.buildSpeed or 0) end
        end
    end

    -- Calculate army value
    local armyValue = 0
    for defName, count in pairs(unitCounts) do
        local defID = UnitDefNames[defName]
        if defID then
            local def = UnitDefs[defID.id or defID]
            if def and not def.isBuilder and not def.isFactory then
                armyValue = armyValue + (def.metalCost or 0) * count
            end
        end
    end

    -- Stall factor approximation
    local stallFactor = 1.0
    if mPull and mPull > 0 and mInc then
        local mFactor = math.min(1.0, (mInc + mCur) / mPull)
        stallFactor = math.min(stallFactor, mFactor)
    end
    if ePull and ePull > 0 and eInc then
        local eFactor = math.min(1.0, (eInc + eCur) / ePull)
        stallFactor = math.min(stallFactor, eFactor)
    end

    local tick = math.floor(frame / 30)

    local snap = {
        frame = frame,
        tick = tick,
        metal_income = mInc or 0,
        energy_income = eInc or 0,
        metal_stored = mCur or 0,
        energy_stored = eCur or 0,
        metal_expenditure = mExp or 0,
        energy_expenditure = eExp or 0,
        build_power = totalBP,
        army_value_metal = armyValue,
        stall_factor = stallFactor,
        unit_counts = {},
    }

    -- Copy unit counts
    for k, v in pairs(unitCounts) do
        snap.unit_counts[k] = v
    end

    snapshots[#snapshots + 1] = snap

    -- Track peaks
    if (mInc or 0) > peakMetalIncome then peakMetalIncome = mInc end
    if (eInc or 0) > peakEnergyIncome then peakEnergyIncome = eInc end

    -- Track stall events
    local isStalling = stallFactor < 0.95
    if isStalling then
        local mFactor = 1.0
        local eFactor = 1.0
        if mPull and mPull > 0 then mFactor = math.min(1.0, (mInc + mCur) / mPull) end
        if ePull and ePull > 0 then eFactor = math.min(1.0, (eInc + eCur) / ePull) end
        local resource = (mFactor < eFactor) and "metal" or "energy"

        if resource == "metal" then
            totalMetalStallFrames = totalMetalStallFrames + SNAPSHOT_INTERVAL
        else
            totalEnergyStallFrames = totalEnergyStallFrames + SNAPSHOT_INTERVAL
        end

        if not currentStall then
            currentStall = {
                start_tick = tick,
                end_tick = tick,
                resource = resource,
                severity = 1.0 - stallFactor,
            }
        else
            currentStall.end_tick = tick
            currentStall.severity = math.max(currentStall.severity, 1.0 - stallFactor)
        end
    else
        if currentStall then
            stallEvents[#stallEvents + 1] = currentStall
            currentStall = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Unit tracking callbacks
--------------------------------------------------------------------------------

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitTeam ~= myTeamID then return end

    local def = UnitDefs[unitDefID]
    if not def then return end

    local defName = def.name
    local frame = Spring.GetGameFrame()
    local tick = math.floor(frame / 30)

    -- Track unit count
    unitCounts[defName] = (unitCounts[defName] or 0) + 1

    -- Log completion
    local builderType = "unknown"
    if def.isFactory then
        builderType = "factory_produced"
    elseif def.isBuilding then
        builderType = "built"
    else
        builderType = "produced"
    end
    completionLog[#completionLog + 1] = { frame = frame, game_id = defName, builder_type = builderType }

    -- Is it a factory? Register it for queue processing
    if def.isFactory then
        factoryCount = factoryCount + 1
        local queueKey = "factory_" .. (factoryCount - 1)
        local queue = {}
        if buildOrder.factory_queues and buildOrder.factory_queues[queueKey] then
            queue = buildOrder.factory_queues[queueKey]
        elseif buildOrder.factory_queues and buildOrder.factory_queues["factory_0"] then
            queue = buildOrder.factory_queues["factory_0"]
        end
        factories[unitID] = { queue = queue, idx = 1 }
        Spring.Echo(LOG_PREFIX .. "Factory online: " .. defName .. " (queue: " .. queueKey .. ", " .. #queue .. " items)")

        -- Milestone
        if factoryCount == 1 then
            milestones[#milestones + 1] = {
                tick = tick,
                event = "first_factory",
                description = def.humanName .. " online",
            }
        end
    end

    -- Is it a constructor (mobile builder)?
    if def.isBuilder and not def.isFactory and not def.isBuilding and defName ~= "armcom" and defName ~= "corcom" then
        conCount = conCount + 1
        local queueKey = "con_" .. conCount
        local queue = {}
        if buildOrder.constructor_queues and buildOrder.constructor_queues[queueKey] then
            queue = buildOrder.constructor_queues[queueKey]
        elseif buildOrder.constructor_queues and buildOrder.constructor_queues["con_1"] then
            queue = buildOrder.constructor_queues["con_1"]
        end
        constructors[unitID] = { queue = queue, idx = 1 }
        Spring.Echo(LOG_PREFIX .. "Constructor online: " .. defName .. " (queue: " .. queueKey .. ", " .. #queue .. " items)")

        -- Milestone
        if conCount == 1 then
            milestones[#milestones + 1] = {
                tick = tick,
                event = "first_constructor",
                description = def.humanName .. " produced",
            }
        end
    end

    -- Nano turret
    if defName:find("nanotc") then
        milestones[#milestones + 1] = {
            tick = tick,
            event = "first_nano",
            description = "Nano turret online",
        }
        -- Nano auto-assists nearest factory via engine behavior
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if unitTeam ~= myTeamID then return end
    local def = UnitDefs[unitDefID]
    if not def then return end
    local defName = def.name
    unitCounts[defName] = math.max(0, (unitCounts[defName] or 1) - 1)

    -- Clean up tracked builders
    if unitID == commanderID then
        commanderID = nil
        Spring.Echo(LOG_PREFIX .. "WARNING: Commander destroyed!")
    end
    factories[unitID] = nil
    constructors[unitID] = nil
end

--------------------------------------------------------------------------------
-- Result writing
--------------------------------------------------------------------------------

local function writeResults()
    local frame = Spring.GetGameFrame()

    -- Close any open stall event
    if currentStall then
        stallEvents[#stallEvents + 1] = currentStall
        currentStall = nil
    end

    -- Calculate total army value
    local totalArmyValue = 0
    for defName, count in pairs(unitCounts) do
        local defID = UnitDefNames[defName]
        if defID then
            local def = UnitDefs[defID.id or defID]
            if def and not def.isBuilder and not def.isFactory and not def.isBuilding then
                totalArmyValue = totalArmyValue + (def.metalCost or 0) * count
            end
        end
    end

    local result = {
        build_order_name = buildOrder.name or "headless_sim",
        total_frames = frame,
        snapshots = snapshots,
        milestones = milestones,
        stall_events = stallEvents,
        completion_log = completionLog,
        mex_spots_used = nextMexSpotIdx - 1,
        peak_metal_income = peakMetalIncome,
        peak_energy_income = peakEnergyIncome,
        total_metal_stall_seconds = math.floor(totalMetalStallFrames / 30),
        total_energy_stall_seconds = math.floor(totalEnergyStallFrames / 30),
        total_army_metal_value = totalArmyValue,
    }

    local outPath = writeDir .. "output/sim_result.json"
    local jsonStr = json.encode(result)
    local ok = writeFile(outPath, jsonStr)
    if ok then
        Spring.Echo(LOG_PREFIX .. "Results written to " .. outPath)
    else
        Spring.Echo(LOG_PREFIX .. "ERROR: Failed to write results to " .. outPath)
    end
end

--------------------------------------------------------------------------------
-- Widget lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    initJSON()

    -- Determine write directory
    writeDir = "headless/"

    -- Try VFS write dir
    if VFS and VFS.GetWriteDir then
        writeDir = VFS.GetWriteDir() .. "headless/"
    end

    -- Read build order
    local inputPath = writeDir .. "input/build_order.json"
    local content = readFile(inputPath)
    if not content then
        Spring.Echo(LOG_PREFIX .. "ERROR: Cannot read " .. inputPath)
        Spring.Echo(LOG_PREFIX .. "Widget will disable itself.")
        widgetHandler:RemoveWidget(self)
        return
    end

    buildOrder = json.decode(content)
    if not buildOrder then
        Spring.Echo(LOG_PREFIX .. "ERROR: Failed to parse build_order.json")
        widgetHandler:RemoveWidget(self)
        return
    end

    Spring.Echo(LOG_PREFIX .. "Build order loaded: " .. (buildOrder.name or "unnamed"))
    Spring.Echo(LOG_PREFIX .. "  Faction: " .. (buildOrder.faction or "unknown"))
    Spring.Echo(LOG_PREFIX .. "  Duration: " .. (buildOrder.duration_frames or "?") .. " frames")
    Spring.Echo(LOG_PREFIX .. "  Commander queue: " .. (buildOrder.commander_queue and #buildOrder.commander_queue or 0) .. " items")

    targetFrame = buildOrder.duration_frames or 18000

    -- Get our team
    myTeamID = Spring.GetMyTeamID()
    myAllyTeamID = Spring.GetMyAllyTeamID()

    -- Commander queue from build order
    commanderQueue = buildOrder.commander_queue or {}
    commanderQueueIdx = 1

    Spring.Echo(LOG_PREFIX .. "Initialized. Target frame: " .. targetFrame)
end

function widget:GameStart()
    -- Find our commander
    local units = Spring.GetTeamUnits(myTeamID)
    if units then
        for _, uid in ipairs(units) do
            local defID = Spring.GetUnitDefID(uid)
            if defID then
                local def = UnitDefs[defID]
                if def and (def.name == "armcom" or def.name == "corcom") then
                    commanderID = uid
                    baseX, _, baseZ = Spring.GetUnitPosition(uid)
                    Spring.Echo(LOG_PREFIX .. "Commander found: " .. def.name .. " at " .. math.floor(baseX) .. ", " .. math.floor(baseZ))
                    break
                end
            end
        end
    end

    if not commanderID then
        -- Fallback: use start position
        baseX, _, baseZ = Spring.GetTeamStartPosition(myTeamID)
        if not baseX then
            baseX = Game.mapSizeX / 2
            baseZ = Game.mapSizeZ / 2
        end
        Spring.Echo(LOG_PREFIX .. "WARNING: Commander not found, using start position")
    end

    -- Discover metal spots
    discoverMexSpots()

    -- Take initial snapshot
    recordSnapshot(0)

    Spring.Echo(LOG_PREFIX .. "Game started. Executing build order...")
end

function widget:GameFrame(frame)
    if finished then return end

    -- Check if we've reached target frame
    if frame >= targetFrame then
        Spring.Echo(LOG_PREFIX .. "Target frame reached (" .. frame .. "). Writing results...")
        recordSnapshot(frame)
        writeResults()
        finished = true
        -- Quit the game
        Spring.SendCommands("quitforce")
        return
    end

    -- Process builder queues every few frames (not every frame for performance)
    if frame % 5 == 0 then
        processCommanderQueue()
        processFactoryQueues()
        processConstructorQueues()
    end

    -- Record economy snapshot at interval
    if frame % SNAPSHOT_INTERVAL == 0 then
        recordSnapshot(frame)
    end
end

function widget:Shutdown()
    if not finished then
        Spring.Echo(LOG_PREFIX .. "Widget shutting down before completion")
        -- Write partial results
        writeResults()
    end
end
