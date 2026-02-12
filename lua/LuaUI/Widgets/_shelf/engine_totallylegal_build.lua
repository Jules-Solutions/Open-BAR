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
        enabled   = false,
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
local spGiveOrderArrayToUnitArray = Spring.GiveOrderArrayToUnitArray

local CMD_STOP = CMD.STOP

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local BlueprintAPI = nil  -- will be WG["api_blueprint"] if available

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 15,        -- check every 15 frames (0.5s)
    resourceBuffer   = 0.15,      -- need 15% of cost available to start
    buildTimeout     = 1800,      -- 60s timeout (factories need more time)
    retryDelay       = 90,        -- frames to wait before retrying a failed item
    maxRetries       = 3,         -- max retries per item before skipping
    queueAhead       = 5,         -- keep this many items queued ahead on commander
}

--------------------------------------------------------------------------------
-- Dynamic Module System Configuration
-- Modules are generated at runtime based on building footprint and these settings
--------------------------------------------------------------------------------

local MODULE_CFG = {
    -- Target area for a module in build squares (8 elmos each)
    -- e.g., 48 squares = roughly 6x8 or 8x6 grid
    targetAreaSquares = 48,

    -- Aspect ratio preference: width / height
    -- 1.0 = square, 1.5 = prefer wider, 0.67 = prefer taller
    aspectRatio = 1.33,  -- slight preference for wider (4:3)

    -- Module size limits (number of buildings)
    minModuleSize = 2,
    maxModuleSize = 20,

    -- Blast radius handling
    blastRadiusBuffer = 1.2,       -- multiply blast radius by this for safety margin
    interGroupSpacing = 32,        -- minimum spacing between groups in elmos (2 squares)
    defaultBlastRadius = 48,       -- fallback if can't determine from unitdef
}

--------------------------------------------------------------------------------
-- Building Category System - determines what CAN be grouped
-- Only eco buildings (energy, converters, storage) and nano turrets
--------------------------------------------------------------------------------

-- Explicit list of units that CAN be grouped into modules
local GROUPABLE_UNITS = {
    -- Energy production
    armwin = true, corwin = true,           -- T1 wind
    armsolar = true, corsolar = true,       -- T1 solar
    armadvsol = true, coradvsol = true,     -- T2 advanced solar
    armtide = true, cortide = true,         -- tidal
    armgeo = true, corgeo = true,           -- geothermal (usually single but can group)
    -- Metal converters
    armmakr = true, cormakr = true,         -- T1 metal maker
    armmmkr = true, cormmkr = true,         -- T2 metal maker
    armfmkr = true, corfmkr = true,         -- floating metal maker
    -- Storage (can group for protection)
    armmstor = true, cormstor = true,       -- metal storage
    armestor = true, corestor = true,       -- energy storage
    -- Nano turrets (construction towers)
    armnanotc = true, cornanotc = true,     -- T1 nano turret
    armnanotcplat = true, cornanotcplat = true,  -- platform nano
    -- T2 energy (usually single but allow grouping)
    armfus = true, corfus = true,           -- fusion reactor
    armafus = true, corafus = true,         -- advanced fusion
    armckfus = true, corckfus = true,       -- cloakable fusion
}

-- Units that should NEVER be grouped (always single placement)
-- This is checked first, overrides GROUPABLE_UNITS if somehow in both
local NEVER_GROUP_UNITS = {
    -- Metal extractors (need specific spots)
    armmex = true, cormex = true,
    armmoho = true, cormoho = true,
    armuwmex = true, coruwmex = true,
    -- Defenses (strategic placement)
    armllt = true, corllt = true,
    armhlt = true, corhlt = true,
    armpb = true, corpb = true,
    armguard = true, corguard = true,
    armrl = true, corrl = true,
    armcir = true, cormadsam = true,
    armflak = true, corflak = true,
    armamd = true, corfmd = true,
    -- Radar/Sonar/Jammers (strategic placement)
    armrad = true, corrad = true,
    armarad = true, corarad = true,
    armjamt = true, corjamt = true,
    armsonar = true, corsonar = true,
    -- Factories (single)
    armlab = true, corlab = true,
    armvp = true, corvp = true,
    armap = true, corap = true,
    armsy = true, corsy = true,
    armhp = true, corhp = true,
    armalab = true, coralab = true,
    armavp = true, coravp = true,
    armaap = true, coraap = true,
    armasy = true, corasy = true,
    armshltx = true, corgant = true,
    -- Superweapons
    armsilo = true, corsilo = true,
    armbrtha = true, corbuzz = true,
    armvulc = true, corraj = true,
}

-- Check if a unit type can be grouped into modules
local function CanBeGrouped(unitDefID)
    local def = UnitDefs[unitDefID]
    if not def then return false end

    local name = def.name

    -- Never group these
    if NEVER_GROUP_UNITS[name] then
        return false
    end

    -- Explicit groupable list
    if GROUPABLE_UNITS[name] then
        return true
    end

    -- Check for commander (never group)
    local cp = def.customParams or {}
    if cp.iscommander then
        return false
    end

    -- Check if it's a factory (never group)
    if def.isFactory then
        return false
    end

    -- Check for weapon (probably defense, don't group)
    if def.weapons and #def.weapons > 0 then
        return false
    end

    -- Check for extractor (never group)
    if def.extractsMetal and def.extractsMetal > 0 then
        return false
    end

    -- Check for radar/sonar range (sensor building, don't group)
    if (def.radarRadius and def.radarRadius > 0) or
       (def.sonarRadius and def.sonarRadius > 0) or
       (def.jammerRadius and def.jammerRadius > 0) then
        return false
    end

    -- If we get here, check if it looks like eco (produces energy or converts metal)
    -- This catches modded eco buildings not in our explicit list
    if (def.energyMake and def.energyMake > 0) or
       (def.makesMetal and def.makesMetal > 0) then
        return true
    end

    -- Default: don't group unknown buildings
    return false
end

--------------------------------------------------------------------------------
-- Placed Groups Tracking (for blast radius awareness)
--------------------------------------------------------------------------------

local placedGroups = {}  -- { { centerX, centerZ, radius, unitDefID }, ... }

local function RegisterPlacedGroup(centerX, centerZ, radius, unitDefID)
    placedGroups[#placedGroups + 1] = {
        centerX = centerX,
        centerZ = centerZ,
        radius = radius,
        unitDefID = unitDefID,
    }
end

local function IsWithinBlastZone(x, z, bufferMult)
    bufferMult = bufferMult or MODULE_CFG.blastRadiusBuffer
    for _, group in ipairs(placedGroups) do
        local dist = math.sqrt((x - group.centerX)^2 + (z - group.centerZ)^2)
        if dist < (group.radius * bufferMult + MODULE_CFG.interGroupSpacing) then
            return true, group
        end
    end
    return false
end

local function ClearPlacedGroups()
    placedGroups = {}
end

--------------------------------------------------------------------------------
-- Blast Radius Detection
--------------------------------------------------------------------------------

-- Known blast radii for common buildings (deathExplosion damage falloff)
-- These are approximate values in elmos
local KNOWN_BLAST_RADII = {
    -- Energy
    armwin = 32, corwin = 32,
    armsolar = 40, corsolar = 40,
    armadvsol = 64, coradvsol = 64,
    armfus = 160, corfus = 160,         -- fusion = big boom
    armafus = 200, corafus = 200,       -- afus = bigger boom
    -- Metal
    armmakr = 32, cormakr = 32,
    armmmkr = 96, cormmkr = 96,         -- T2 makers
    armmstor = 48, cormstor = 48,
    -- Factories (big explosions)
    armlab = 80, corlab = 80,
    armvp = 80, corvp = 80,
    armap = 80, corap = 80,
    armsy = 80, corsy = 80,
    -- Defense
    armllt = 40, corllt = 40,
    armhlt = 64, corhlt = 64,
}

local function GetBlastRadius(unitDefID)
    local def = UnitDefs[unitDefID]
    if not def then return MODULE_CFG.defaultBlastRadius end

    -- Check known values first
    if KNOWN_BLAST_RADII[def.name] then
        return KNOWN_BLAST_RADII[def.name]
    end

    -- Try to estimate from unit properties
    -- Larger/more expensive buildings tend to have bigger death explosions
    local footprint = math.max(def.xsize or 2, def.zsize or 2) * 8
    local costFactor = math.sqrt((def.metalCost or 50) + (def.energyCost or 0) / 100) / 8

    -- Base on footprint, scale by cost
    local estimated = footprint * (0.8 + costFactor * 0.4)

    -- Clamp to reasonable range
    return math.max(24, math.min(200, estimated))
end

--------------------------------------------------------------------------------
-- Dynamic Module Dimension Calculation
--------------------------------------------------------------------------------

-- Calculate optimal module grid (numX × numZ) for a given building type
local function CalculateModuleDimensions(unitDefID)
    local def = UnitDefs[unitDefID]
    if not def then return 1, 1 end

    -- Use the category system to check if this building can be grouped
    if not CanBeGrouped(unitDefID) then
        return 1, 1  -- Single placement only
    end

    -- Building footprint in build squares (8 elmos each)
    local bldgX = def.xsize or 2  -- footprint units (each = 2 squares = 16 elmos)
    local bldgZ = def.zsize or 2

    -- Building area in footprint units squared
    local bldgArea = bldgX * bldgZ

    -- Target count based on area
    -- targetAreaSquares is in 8-elmo squares, building size is in 16-elmo footprint units
    -- So convert: 48 squares / (bldgX * 2 * bldgZ * 2) buildings
    local targetCount = MODULE_CFG.targetAreaSquares / (bldgArea * 4)

    if targetCount < MODULE_CFG.minModuleSize then
        targetCount = MODULE_CFG.minModuleSize
    elseif targetCount > MODULE_CFG.maxModuleSize then
        targetCount = MODULE_CFG.maxModuleSize
    end

    -- Calculate grid dimensions based on aspect ratio preference
    -- numX / numZ = aspectRatio, numX * numZ = targetCount
    -- numZ = sqrt(targetCount / aspectRatio)
    local numZ = math.sqrt(targetCount / MODULE_CFG.aspectRatio)
    local numX = targetCount / numZ

    -- Round to nearest integers, ensuring at least 1
    numX = math.max(1, math.floor(numX + 0.5))
    numZ = math.max(1, math.floor(numZ + 0.5))

    -- Re-check total count after rounding
    local total = numX * numZ
    if total < MODULE_CFG.minModuleSize then
        -- Bump up the smaller dimension
        if numX <= numZ then
            numX = math.ceil(MODULE_CFG.minModuleSize / numZ)
        else
            numZ = math.ceil(MODULE_CFG.minModuleSize / numX)
        end
    elseif total > MODULE_CFG.maxModuleSize then
        -- Scale down
        local scale = math.sqrt(MODULE_CFG.maxModuleSize / total)
        numX = math.max(1, math.floor(numX * scale))
        numZ = math.max(1, math.floor(numZ * scale))
    end

    return numX, numZ
end

-- Generate a module blueprint dynamically for any building type
local function GenerateModuleBlueprint(unitDefID, numX, numZ)
    local def = UnitDefs[unitDefID]
    if not def then return nil end

    local unitName = def.name

    -- Building footprint in elmos
    local footprintX = (def.xsize or 2) * 16  -- 16 elmos per footprint unit
    local footprintZ = (def.zsize or 2) * 16

    -- Calculate positions centered around origin
    local units = {}
    local halfX = (numX - 1) * footprintX / 2
    local halfZ = (numZ - 1) * footprintZ / 2

    for zIdx = 0, numZ - 1 do
        for xIdx = 0, numX - 1 do
            local px = xIdx * footprintX - halfX
            local pz = zIdx * footprintZ - halfZ

            units[#units + 1] = {
                unitName = unitName,
                facing = 0,
                position = { px, 0, pz },
            }
        end
    end

    return {
        name = "_TL_dynamic_" .. unitName .. "_" .. numX .. "x" .. numZ,
        ordered = true,
        spacing = 0,
        facing = 0,
        units = units,
    }
end

-- Calculate the blast zone radius for a placed module
local function CalculateModuleBlastRadius(unitDefID, numX, numZ)
    local def = UnitDefs[unitDefID]
    if not def then return MODULE_CFG.defaultBlastRadius end

    local footprintX = (def.xsize or 2) * 16
    local footprintZ = (def.zsize or 2) * 16

    -- Module extent from center
    local extentX = numX * footprintX / 2
    local extentZ = numZ * footprintZ / 2
    local moduleRadius = math.sqrt(extentX^2 + extentZ^2)

    -- Add individual building blast radius
    local bldgBlast = GetBlastRadius(unitDefID)

    return moduleRadius + bldgBlast
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local commanderID = nil
local commanderDefID = nil
local buildQueue = {}           -- array of { key, type, count (optional) }
local issuedUpTo = 0            -- highest index we've issued orders for
local phase = "waiting"         -- "waiting", "building", "handoff", "done"

-- Tracking for mex claims
local claimedMexSpots = {}      -- array of { x, z } to release on shutdown
local lastIssueFrame = 0        -- frame when we last issued orders
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
-- Modular Building Functions (uses Blueprint API for placement)
--------------------------------------------------------------------------------

-- ARM -> COR unit name mapping for faction conversion
local ARM_TO_COR = {
    armwin = "corwin",
    armmakr = "cormakr",
    armsolar = "corsolar",
    armadvsol = "coradvsol",
    armmstor = "cormstor",
    armestor = "corestor",
    armmex = "cormex",
    armfus = "corfus",
    armafus = "corafus",
    armmmkr = "cormmkr",
}

-- Get the faction-appropriate unit name
local function GetFactionUnit(unitName)
    local faction = TL and TL.GetFaction and TL.GetFaction() or "arm"
    if faction == "arm" then
        return unitName
    end
    return ARM_TO_COR[unitName] or unitName
end

-- Find valid position for a module blueprint near specified location
-- Now includes blast zone awareness to keep distance between groups
local function FindModulePosition(builderID, blueprint, moduleRadius, nearX, nearZ)
    if not BlueprintAPI then return nil, nil end

    -- Get builder's existing queue positions to avoid conflicts
    local queuedPositions = {}
    local cmds = Spring.GetUnitCommands(builderID, 50) or {}
    for _, cmd in ipairs(cmds) do
        if cmd.id and cmd.id < 0 and cmd.params and cmd.params[1] then
            -- Build order: params are {x, y, z, facing}
            local qx, qz = cmd.params[1], cmd.params[3]
            if qx and qz then
                queuedPositions[#queuedPositions + 1] = { x = qx, z = qz, defID = -cmd.id }
            end
        end
    end

    -- Use spiral search to find valid position
    local searchRadius = 1200
    local stepSize = BlueprintAPI.BUILD_SQUARE_SIZE or 16
    local maxAttempts = 200

    -- Check if a position conflicts with existing queued builds
    local function conflictsWithQueue(x, z, defID)
        local def = UnitDefs[defID]
        if not def then return false end
        local radius = math.max((def.xsize or 2) * 4, (def.zsize or 2) * 4) + 8  -- footprint + buffer
        
        for _, q in ipairs(queuedPositions) do
            local dx = x - q.x
            local dz = z - q.z
            local dist = math.sqrt(dx*dx + dz*dz)
            -- Use combined footprints as minimum distance
            local qDef = UnitDefs[q.defID]
            local qRadius = qDef and math.max((qDef.xsize or 2) * 4, (qDef.zsize or 2) * 4) + 8 or 32
            if dist < (radius + qRadius) then
                return true
            end
        end
        return false
    end

    -- Basic buildability check for all units in blueprint
    local function canPlaceModule(centerX, centerZ)
        -- First, check blast zone conflicts with existing groups
        local inBlast, conflictGroup = IsWithinBlastZone(centerX, centerZ)
        if inBlast then
            return false  -- too close to existing group
        end

        -- Test each building position
        for _, unit in ipairs(blueprint.units) do
            if unit.unitDefID then
                local x = centerX + unit.position[1]
                local z = centerZ + unit.position[3]
                local y = spGetGroundHeight(x, z) or 0
                
                -- Check if blocked by terrain
                local result = Spring.TestBuildOrder(unit.unitDefID, x, y, z, unit.facing)
                if result == 0 then
                    return false  -- blocked by terrain/structure
                end
                
                -- Check if conflicts with our own queue
                if conflictsWithQueue(x, z, unit.unitDefID) then
                    return false  -- would overlap queued building
                end
            end
        end
        return true
    end

    -- Golden angle spiral search (same pattern as core library)
    local goldenAngle = math.pi * (3 - math.sqrt(5))
    for i = 0, maxAttempts do
        local r = stepSize * math.sqrt(i) * 2
        local theta = i * goldenAngle

        local testX = nearX + r * math.cos(theta)
        local testZ = nearZ + r * math.sin(theta)

        -- Snap to build grid
        testX = math.floor(testX / stepSize + 0.5) * stepSize
        testZ = math.floor(testZ / stepSize + 0.5) * stepSize

        if canPlaceModule(testX, testZ) then
            return testX, testZ
        end

        if r > searchRadius then break end
    end

    return nil, nil  -- couldn't find valid position
end

-- Issue dynamic module build orders to a builder
-- unitDefID = which building type to place
-- count = optional override for number of buildings (nil = auto-calculate)
-- nearX, nearZ = approximate location
-- useShiftOverride = optional boolean to force shift behavior (nil = auto-detect)
-- Returns number of individual build orders issued
local function IssueDynamicModuleBuild(builderID, unitDefID, nearX, nearZ, count, useShiftOverride)
    if not BlueprintAPI then
        spEcho("[TotallyLegal Build] Blueprint API not available, cannot build module")
        return 0
    end

    local def = UnitDefs[unitDefID]
    if not def then
        spEcho("[TotallyLegal Build] Unknown unitDefID: " .. tostring(unitDefID))
        return 0
    end

    -- Calculate module dimensions
    local numX, numZ
    if count then
        -- User specified count - try to make roughly square
        local aspect = MODULE_CFG.aspectRatio
        numZ = math.max(1, math.floor(math.sqrt(count / aspect) + 0.5))
        numX = math.max(1, math.ceil(count / numZ))
    else
        numX, numZ = CalculateModuleDimensions(unitDefID)
    end

    -- For single-unit "modules" (factories, etc), just use regular build
    if numX == 1 and numZ == 1 then
        return 0  -- caller should use regular build order
    end

    -- Generate the module blueprint dynamically
    local serialized = GenerateModuleBlueprint(unitDefID, numX, numZ)
    if not serialized then
        spEcho("[TotallyLegal Build] Failed to generate module blueprint")
        return 0
    end

    -- Convert to blueprint object (this resolves unitNames to unitDefIDs)
    local blueprint = BlueprintAPI.createBlueprintFromSerialized(serialized)
    if not blueprint then
        spEcho("[TotallyLegal Build] Failed to create blueprint from serialized data")
        return 0
    end

    -- Calculate blast radius for this module
    local moduleBlastRadius = CalculateModuleBlastRadius(unitDefID, numX, numZ)

    -- Find valid position (includes blast zone awareness)
    local modX, modZ = FindModulePosition(builderID, blueprint, moduleBlastRadius, nearX, nearZ)
    if not modX then
        spEcho("[TotallyLegal Build] Cannot find valid position for module of " .. def.name)
        return 0
    end

    -- Build the orders array
    local orders = {}
    local cmdOpts = { shift = true }
    local firstOpts = {}

    -- Determine if we need shift for first item:
    -- If caller overrides, use that; otherwise check existing queue
    local shouldShift = useShiftOverride
    if shouldShift == nil then
        -- Auto-detect: shift if there are existing commands in queue
        local existingCmds = spGetUnitCommands(builderID, 0) or 0
        shouldShift = existingCmds > 0
    end
    if shouldShift then
        firstOpts = { shift = true }
    end

    for i, unit in ipairs(blueprint.units) do
        if unit.unitDefID then
            local x = modX + unit.position[1]
            local z = modZ + unit.position[3]
            local y = spGetGroundHeight(x, z) or 0

            local sx, sy, sz = Spring.Pos2BuildPos(unit.unitDefID, x, y, z, unit.facing)

            orders[#orders + 1] = {
                -unit.unitDefID,
                { sx, sy, sz, unit.facing },
                i == 1 and firstOpts or cmdOpts,
            }
        end
    end

    if #orders == 0 then
        spEcho("[TotallyLegal Build] No valid orders built for module")
        return 0
    end

    -- Issue all orders at once
    spGiveOrderArrayToUnitArray({ builderID }, orders, false)

    -- Debug: verify orders were actually added
    local postCmds = spGetUnitCommands(builderID, 0) or 0
    spEcho("[TotallyLegal Build] Module issued with shift=" .. tostring(shouldShift) .. ", queue now has " .. postCmds .. " commands")

    -- Register this group for blast zone tracking
    RegisterPlacedGroup(modX, modZ, moduleBlastRadius, unitDefID)

    spEcho("[TotallyLegal Build] Issued dynamic module of " .. def.name ..
           " (" .. numX .. "x" .. numZ .. " = " .. #orders ..
           " buildings) at (" .. math.floor(modX) .. ", " .. math.floor(modZ) ..
           "), blast radius: " .. math.floor(moduleBlastRadius))

    return #orders
end

-- Legacy wrapper for template-based builds (now generates dynamically)
-- useShiftOverride = optional boolean to force shift behavior
local function IssueModuleBuild(builderID, templateKey, nearX, nearZ, useShiftOverride)
    -- Parse the template key to extract unit type
    -- Format: "wind_row_2x5" -> "armwin", "converter_block_2x2" -> "armmakr"
    local unitName = nil
    local count = nil

    if templateKey:find("^wind") then
        unitName = GetFactionUnit("armwin")
        local dims = templateKey:match("(%d+)x(%d+)")
        if dims then
            local w, h = templateKey:match("(%d+)x(%d+)")
            count = tonumber(w) * tonumber(h)
        end
    elseif templateKey:find("^converter") or templateKey:find("^makr") then
        unitName = GetFactionUnit("armmakr")
        local w, h = templateKey:match("(%d+)x(%d+)")
        if w and h then count = tonumber(w) * tonumber(h) end
    elseif templateKey:find("^solar") then
        unitName = GetFactionUnit("armsolar")
        local w, h = templateKey:match("(%d+)x(%d+)")
        if w and h then count = tonumber(w) * tonumber(h) end
    else
        spEcho("[TotallyLegal Build] Unknown template pattern: " .. templateKey)
        return 0
    end

    local unitDefID = UnitDefNames[unitName] and UnitDefNames[unitName].id
    if not unitDefID then
        spEcho("[TotallyLegal Build] Unknown unit: " .. tostring(unitName))
        return 0
    end

    return IssueDynamicModuleBuild(builderID, unitDefID, nearX, nearZ, count, useShiftOverride)
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
        -- If Blueprint API is available, use dynamic modules
        if BlueprintAPI then
            buildQueue = {
                { key = "mex", type = "structure" },
                { key = "mex", type = "structure" },
                { key = "wind", type = "dynamic_module" },  -- auto-calculated wind module!
                { key = "bot_lab", type = "structure" },
                { key = "mex", type = "structure" },
            }
        else
            -- Fallback: individual winds
            buildQueue = {
                { key = "mex", type = "structure" },
                { key = "mex", type = "structure" },
                { key = "bot_lab", type = "structure" },  -- Factory before energy
                { key = "wind", type = "structure" },
                { key = "wind", type = "structure" },
                { key = "wind", type = "structure" },
                { key = "wind", type = "structure" },
                { key = "mex", type = "structure" },
            }
        end
        issuedUpTo = 0
        phase = "building"
        spEcho("[TotallyLegal Build] Using default opening (no strategy config)")
        return
    end

    buildQueue = {}

    -- Mex first (quick income)
    local mexCount = strat.openingMexCount or 2
    for i = 1, mexCount do
        buildQueue[#buildQueue + 1] = { key = "mex", type = "structure" }
    end

    -- Factory BEFORE energy modules (so modules know where factory will be)
    if strat.unitComposition == "bots" or strat.unitComposition == "mixed" then
        buildQueue[#buildQueue + 1] = { key = "bot_lab", type = "structure" }
    else
        buildQueue[#buildQueue + 1] = { key = "vehicle_plant", type = "structure" }
    end

    -- Energy based on strategy - use dynamic modules if available
    local useModules = BlueprintAPI and (strat.useModularBuilding ~= false)

    if strat.energyStrategy == "wind_only" or strat.energyStrategy == "auto" then
        if useModules then
            -- Dynamic module with optional count override
            local count = strat.modulePreference == "2x5" and 10 or nil  -- nil = auto
            buildQueue[#buildQueue + 1] = { key = "wind", type = "dynamic_module", count = count }
        else
            -- Individual winds
            buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
            buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
        end
    elseif strat.energyStrategy == "solar_only" then
        if useModules then
            buildQueue[#buildQueue + 1] = { key = "solar", type = "dynamic_module" }
        else
            buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
            buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
        end
    else
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
        buildQueue[#buildQueue + 1] = { key = "solar", type = "structure" }
    end

    -- More energy after initial batch - another dynamic module
    if useModules and (strat.energyStrategy == "wind_only" or strat.energyStrategy == "auto") then
        buildQueue[#buildQueue + 1] = { key = "wind", type = "dynamic_module" }
    else
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
        buildQueue[#buildQueue + 1] = { key = "wind", type = "structure" }
    end

    -- Extra mex
    buildQueue[#buildQueue + 1] = { key = "mex", type = "structure" }

    issuedUpTo = 0
    phase = "building"
    spEcho("[TotallyLegal Build] Generated opening queue (" .. #buildQueue .. " items)")
end

--------------------------------------------------------------------------------
-- Build execution - shift-queues multiple builds at once
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

-- Issue orders for items [fromIndex, toIndex] with shift-queue
-- Supports both single structures and modules
local function IssueBuildOrders(fromIndex, toIndex)
    if not commanderID then return 0 end

    local cx, cy, cz = spGetUnitPosition(commanderID)
    if not cx then return 0 end

    local issued = 0
    local useShift = (fromIndex > 1) or (spGetUnitCommands(commanderID, 0) or 0) > 0

    for i = fromIndex, toIndex do
        local item = buildQueue[i]
        if not item then break end

        -- Check if this is a module (type == "module" or "dynamic_module")
        if item.type == "module" then
            -- Legacy module building via template key parsing
            local count = IssueModuleBuild(commanderID, item.key, cx, cz, useShift)
            if count > 0 then
                issued = issued + 1  -- count as 1 queue item
                useShift = true
                spEcho("[TotallyLegal Build] Queued module: " .. item.key ..
                       " (" .. i .. "/" .. #buildQueue .. ", " .. count .. " buildings)")
            else
                spEcho("[TotallyLegal Build] Cannot place module: " .. item.key .. " (item " .. i .. ")")
            end
        elseif item.type == "dynamic_module" then
            -- New dynamic module: key is unit name/defID, count is optional
            local defID = TL.ResolveKey(item.key)
            if not defID then
                local def = UnitDefNames[item.key]
                if def then defID = def.id end
            end
            if defID then
                local count = IssueDynamicModuleBuild(commanderID, defID, cx, cz, item.count, useShift)
                if count > 0 then
                    issued = issued + 1
                    useShift = true
                    spEcho("[TotallyLegal Build] Queued dynamic module: " .. item.key ..
                           " (" .. i .. "/" .. #buildQueue .. ", " .. count .. " buildings)")
                else
                    spEcho("[TotallyLegal Build] Cannot place dynamic module: " .. item.key)
                end
            else
                spEcho("[TotallyLegal Build] Unknown unit for dynamic module: " .. item.key)
            end
        else
            -- Single structure (original logic)
            local defID = TL.ResolveKey(item.key)
            if not defID then
                spEcho("[TotallyLegal Build] Unknown key: " .. item.key .. ", skipping")
            else
                -- Find build position
                local opts = nil
                if item.key == "mex" then
                    opts = { useTieredPriority = true }
                end
                local bx, bz = TL.FindBuildPosition(commanderID, defID, cx, cz, opts)
                if bx then
                    local by = spGetGroundHeight(bx, bz) or 0
                    local cmdOpts = useShift and {"shift"} or {}
                    spGiveOrderToUnit(commanderID, -defID, {bx, by, bz}, cmdOpts)

                    -- Debug: verify order was added
                    local postCmds = spGetUnitCommands(commanderID, 0) or 0
                    
                    -- Claim mex spot
                    if item.key == "mex" and TL.ClaimMexSpot then
                        TL.ClaimMexSpot(bx, bz, commanderID)
                        claimedMexSpots[#claimedMexSpots + 1] = { x = bx, z = bz }
                    end

                    issued = issued + 1
                    useShift = true  -- all subsequent orders use shift

                    spEcho("[TotallyLegal Build] Queued: " .. item.key ..
                           " (" .. i .. "/" .. #buildQueue .. ") at (" ..
                           math.floor(bx) .. ", " .. math.floor(bz) .. "), shift=" .. 
                           tostring(cmdOpts[1] == "shift") .. ", queue=" .. postCmds)
                else
                    spEcho("[TotallyLegal Build] Cannot place: " .. item.key .. " (item " .. i .. ")")
                end
            end
        end
    end

    return issued
end

local function MaintainBuildQueue()
    local frame = spGetGameFrame()

    -- All items issued and commander idle = done
    if issuedUpTo >= #buildQueue then
        local cmdCount = spGetUnitCommands(commanderID, 0) or 0
        local building = spGetUnitIsBuilding(commanderID)
        if cmdCount == 0 and not building then
            phase = "handoff"
        end
        return
    end

    if not commanderID then
        FindCommander()
        if not commanderID then return end
    end

    -- Wait for retry delay
    if frame < retryWaitUntil then return end

    -- Check how many items are currently in commander's queue
    local cmdCount = spGetUnitCommands(commanderID, 0) or 0

    -- Calculate how many more we need to issue to maintain queueAhead
    local needed = CFG.queueAhead - cmdCount
    if needed <= 0 then return end

    -- Cap at remaining items
    local fromIndex = issuedUpTo + 1
    local toIndex = math.min(issuedUpTo + needed, #buildQueue)

    if fromIndex > toIndex then return end

    local issued = IssueBuildOrders(fromIndex, toIndex)
    if issued > 0 then
        issuedUpTo = issuedUpTo + issued
        lastIssueFrame = frame
        spEcho("[TotallyLegal Build] Issued " .. issued .. " orders, total issued: " .. issuedUpTo .. "/" .. #buildQueue)
    else
        -- Failed to issue any - might be placement issue, wait and retry
        retryWaitUntil = frame + CFG.retryDelay
    end
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

    -- Get Blueprint API if available (for modular building)
    BlueprintAPI = WG["api_blueprint"]
    if BlueprintAPI then
        spEcho("[TotallyLegal Build] Blueprint API available - module building enabled")
    else
        spEcho("[TotallyLegal Build] Blueprint API not found - module building disabled")
    end

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Build] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Expose build phase to other widgets
    WG.TotallyLegal.BuildPhase = phase

    -- Expose dynamic module building capability for other widgets
    WG.TotallyLegal.BuildModule = function(builderID, templateKey, nearX, nearZ)
        if not BlueprintAPI then return 0 end
        return IssueModuleBuild(builderID, templateKey, nearX, nearZ)
    end

    -- New: Build a dynamic module for any unit type
    WG.TotallyLegal.BuildDynamicModule = function(builderID, unitDefIDOrName, nearX, nearZ, countOverride)
        if not BlueprintAPI then return 0 end
        local unitDefID = unitDefIDOrName
        if type(unitDefIDOrName) == "string" then
            local def = UnitDefNames[unitDefIDOrName]
            if not def then return 0 end
            unitDefID = def.id
        end
        return IssueDynamicModuleBuild(builderID, unitDefID, nearX, nearZ, countOverride)
    end

    -- New: Get calculated module dimensions for a unit type
    WG.TotallyLegal.GetModuleDimensions = function(unitDefIDOrName)
        local unitDefID = unitDefIDOrName
        if type(unitDefIDOrName) == "string" then
            local def = UnitDefNames[unitDefIDOrName]
            if not def then return 1, 1 end
            unitDefID = def.id
        end
        return CalculateModuleDimensions(unitDefID)
    end

    -- New: Get/set module configuration
    WG.TotallyLegal.GetModuleConfig = function()
        return {
            targetAreaSquares = MODULE_CFG.targetAreaSquares,
            aspectRatio = MODULE_CFG.aspectRatio,
            minModuleSize = MODULE_CFG.minModuleSize,
            maxModuleSize = MODULE_CFG.maxModuleSize,
            blastRadiusBuffer = MODULE_CFG.blastRadiusBuffer,
            interGroupSpacing = MODULE_CFG.interGroupSpacing,
        }
    end

    WG.TotallyLegal.SetModuleConfig = function(key, value)
        if MODULE_CFG[key] ~= nil then
            MODULE_CFG[key] = value
            spEcho("[TotallyLegal Build] Module config updated: " .. key .. " = " .. tostring(value))
            return true
        end
        return false
    end

    -- New: Blast zone management
    WG.TotallyLegal.GetPlacedGroups = function() return placedGroups end
    WG.TotallyLegal.ClearPlacedGroups = ClearPlacedGroups
    WG.TotallyLegal.GetBlastRadius = GetBlastRadius

    -- New: Category checking - determine if a unit type can be grouped
    WG.TotallyLegal.CanBeGrouped = function(unitDefIDOrName)
        local unitDefID = unitDefIDOrName
        if type(unitDefIDOrName) == "string" then
            local def = UnitDefNames[unitDefIDOrName]
            if not def then return false end
            unitDefID = def.id
        end
        return CanBeGrouped(unitDefID)
    end

    -- Get the groupable units list (for UI/debugging)
    WG.TotallyLegal.GetGroupableUnits = function() return GROUPABLE_UNITS end
    WG.TotallyLegal.GetNeverGroupUnits = function() return NEVER_GROUP_UNITS end

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
            MaintainBuildQueue()
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
    -- Release any claimed mex spots
    if TL and TL.ReleaseMexClaim then
        for _, spot in ipairs(claimedMexSpots) do
            TL.ReleaseMexClaim(spot.x, spot.z)
        end
    end
    claimedMexSpots = {}

    -- Clear placed groups
    ClearPlacedGroups()

    if WG.TotallyLegal then
        WG.TotallyLegal.BuildPhase = nil
        WG.TotallyLegal.BuildModule = nil
        WG.TotallyLegal.BuildDynamicModule = nil
        WG.TotallyLegal.GetModuleDimensions = nil
        WG.TotallyLegal.GetModuleConfig = nil
        WG.TotallyLegal.SetModuleConfig = nil
        WG.TotallyLegal.GetPlacedGroups = nil
        WG.TotallyLegal.ClearPlacedGroups = nil
        WG.TotallyLegal.GetBlastRadius = nil
        WG.TotallyLegal.CanBeGrouped = nil
        WG.TotallyLegal.GetGroupableUnits = nil
        WG.TotallyLegal.GetNeverGroupUnits = nil
    end

    BlueprintAPI = nil
end
