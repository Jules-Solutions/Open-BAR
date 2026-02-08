-- TotallyLegal Build Order Executor - Automatic opening build execution
-- Executes opening build orders from strategy config or imported JSON.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (provides key resolution, mex spots, build placement)

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
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spEcho                = Spring.Echo

local CMD_STOP = CMD.STOP

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 15,        -- check every 15 frames (0.5s)
    resourceBuffer   = 0.15,      -- need 15% of cost available to start
    buildTimeout     = 1800,      -- 60s timeout (factories need more time)
    retryDelay       = 90,        -- frames to wait before retrying a failed item
    maxRetries       = 3,         -- max retries per item before skipping
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local commanderID = nil
local commanderDefID = nil
local buildQueue = {}           -- array of { key, type }
local currentQueueIndex = 1
local phase = "waiting"         -- "waiting", "building", "handoff", "done"

-- Build tracking: don't advance queue until current build is DONE
local currentBuildDefID = nil   -- defID of what we're currently building
local currentBuildFrame = 0     -- frame when we issued the order
local currentBuildPos = nil     -- { x, z } for mex claim release
local retryCount = 0            -- retries for current item
local retryWaitUntil = 0        -- frame to wait until before retrying

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
-- Build order file import (Bug #16)
--------------------------------------------------------------------------------

local function LoadBuildOrderFromFile(path)
    if not path or path == "" then return nil end
    local content = VFS.LoadFile(path)
    if not content then
        spEcho("[TotallyLegal Build] Cannot load build order file: " .. tostring(path))
        return nil
    end

    -- Minimal JSON array-of-objects parser for: [{"key":"mex","type":"structure"}, ...]
    local queue = {}
    for key, itemType in content:gmatch('{%s*"key"%s*:%s*"([^"]+)"%s*,%s*"type"%s*:%s*"([^"]+)"%s*}') do
        queue[#queue + 1] = { key = key, type = itemType }
    end
    -- Also try reversed field order: {"type":"structure","key":"mex"}
    if #queue == 0 then
        for itemType, key in content:gmatch('{%s*"type"%s*:%s*"([^"]+)"%s*,%s*"key"%s*:%s*"([^"]+)"%s*}') do
            queue[#queue + 1] = { key = key, type = itemType }
        end
    end

    if #queue == 0 then
        spEcho("[TotallyLegal Build] Build order file parsed but empty or invalid format: " .. path)
        return nil
    end

    -- Validate all keys resolve
    for i, item in ipairs(queue) do
        if not TL.ResolveKey(item.key) then
            spEcho("[TotallyLegal Build] WARNING: Unknown key '" .. item.key .. "' at position " .. i .. " in build order file")
        end
    end

    spEcho("[TotallyLegal Build] Loaded build order from file: " .. path .. " (" .. #queue .. " items)")
    return queue
end

--------------------------------------------------------------------------------
-- Build queue generation
--------------------------------------------------------------------------------

local function GenerateDefaultQueue()
    local strat = WG.TotallyLegal and WG.TotallyLegal.Strategy

    -- Bug #16: try loading build order from file if configured
    if strat and strat.buildOrderFile then
        local fileQueue = LoadBuildOrderFromFile(strat.buildOrderFile)
        if fileQueue then
            buildQueue = fileQueue
            currentQueueIndex = 1
            phase = "building"
            return
        end
        -- File load failed, fall through to auto-generation
    end

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
            return  -- still working
        end

        -- Commander is no longer building. Check if it has queued commands.
        local cmds = spGetUnitCommands(commanderID, 1)
        if cmds and #cmds > 0 then
            -- Has commands in queue (walking to build site, etc.)
            -- Check for timeout
            if frame - currentBuildFrame > CFG.buildTimeout then
                spEcho("[TotallyLegal Build] Build timeout for item " .. currentQueueIndex .. ", cancelling")
                spGiveOrderToUnit(commanderID, CMD_STOP, {}, {})
                if currentBuildPos and TL.ReleaseMexClaim then
                    TL.ReleaseMexClaim(currentBuildPos.x, currentBuildPos.z)
                    currentBuildPos = nil
                end
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

        -- Commander idle with no commands = build completed (or order was rejected)
        local elapsed = frame - currentBuildFrame
        local item = buildQueue[currentQueueIndex]
        if elapsed < 30 then
            -- Completed in < 0.33s = order was silently rejected by the engine
            spEcho("[TotallyLegal Build] REJECTED (instant): " .. item.key ..
                   " (" .. currentQueueIndex .. "/" .. #buildQueue .. ") after " .. elapsed .. " frames")
            if currentBuildPos and TL.ReleaseMexClaim then
                TL.ReleaseMexClaim(currentBuildPos.x, currentBuildPos.z)
                currentBuildPos = nil
            end
            currentBuildDefID = nil
            retryCount = retryCount + 1
            if retryCount > CFG.maxRetries then
                spEcho("[TotallyLegal Build] Max retries for rejected: " .. item.key .. ", skipping")
                currentQueueIndex = currentQueueIndex + 1
                retryCount = 0
            else
                retryWaitUntil = frame + CFG.retryDelay
            end
            return
        end

        spEcho("[TotallyLegal Build] Completed: " .. item.key ..
               " (" .. currentQueueIndex .. "/" .. #buildQueue .. ") in " ..
               string.format("%.1fs", elapsed / 30))
        -- Release mex claim on completion
        if currentBuildPos and TL.ReleaseMexClaim then
            TL.ReleaseMexClaim(currentBuildPos.x, currentBuildPos.z)
            currentBuildPos = nil
        end
        currentBuildDefID = nil
        retryCount = 0
        currentQueueIndex = currentQueueIndex + 1

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

    -- Resolve key via core library (single source of truth)
    local defID = TL.ResolveKey(item.key)
    if not defID then
        spEcho("[TotallyLegal Build] Unknown unit key: " .. item.key .. ", skipping")
        currentQueueIndex = currentQueueIndex + 1
        retryCount = 0
        return
    end

    -- Resource check
    if not CanAfford(defID) then
        return  -- wait for resources
    end

    local cx, cy, cz = spGetUnitPosition(commanderID)
    if not cx then return end

    -- Find build position via core library (handles mex spots + spiral placement)
    local opts = nil
    if item.key == "mex" then
        opts = { useTieredPriority = true }
    end
    local bx, bz = TL.FindBuildPosition(commanderID, defID, cx, cz, opts)
    if not bx then
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

    -- Claim mex spot to prevent constructor collision
    if item.key == "mex" and TL.ClaimMexSpot then
        TL.ClaimMexSpot(bx, bz, commanderID)
        currentBuildPos = { x = bx, z = bz }
    else
        currentBuildPos = nil
    end

    -- Track this build
    currentBuildDefID = defID
    currentBuildFrame = frame
    spEcho("[TotallyLegal Build] Building: " .. item.key ..
           " (" .. currentQueueIndex .. "/" .. #buildQueue ..
           ") at (" .. math.floor(bx) .. ", " .. math.floor(bz) .. ")")
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

    -- Expose build phase to other widgets
    WG.TotallyLegal.BuildPhase = phase

    spEcho("[TotallyLegal Build] Ready (uses core library for keys + mex spots)")
end

function widget:GameStart()
    -- Core library handles faction detection, key table, and mex spots at its GameStart.
    -- We just find our commander and generate the queue.
    FindCommander()
    if commanderID then
        spEcho("[TotallyLegal Build] Commander found: " .. commanderID)
    else
        spEcho("[TotallyLegal Build] WARNING: Commander not found at GameStart")
    end

    GenerateDefaultQueue()
    WG.TotallyLegal.BuildPhase = phase
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if phase == "done" then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
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
            if WG.TotallyLegal then
                WG.TotallyLegal.BuildPhase = "done"
            end
        end
    end)
    if not ok then
        spEcho("[TotallyLegal Build] GameFrame error: " .. tostring(err))
    end
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.BuildPhase = nil
    end
end
