-- TotallyLegal Core Library - Shared utilities for all TotallyLegal widgets
-- Provides: mode detection, unit classification, unit tracking, team resources, math, rendering helpers.
-- All exposed via WG.TotallyLegal table. Must load before other TotallyLegal widgets (layer = -1).

function widget:GetInfo()
    return {
        name      = "TotallyLegal Core",
        desc      = "Shared library for TotallyLegal widget suite. Provides unit classification, mode detection, math, and rendering helpers.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = -1,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID          = Spring.GetMyTeamID
local spGetMyAllyTeamID      = Spring.GetMyAllyTeamID
local spGetTeamUnits         = Spring.GetTeamUnits
local spGetTeamResources     = Spring.GetTeamResources
local spGetUnitDefID         = Spring.GetUnitDefID
local spGetUnitPosition      = Spring.GetUnitPosition
local spGetGameFrame         = Spring.GetGameFrame
local spGetGameRulesParam    = Spring.GetGameRulesParam
local spGetSpectatingState   = Spring.GetSpectatingState
local spGetGroundHeight      = Spring.GetGroundHeight
local spTestBuildOrder       = Spring.TestBuildOrder
local spEcho                 = Spring.Echo

local glColor      = gl.Color
local glRect       = gl.Rect
local glText       = gl.Text
local glLineWidth  = gl.LineWidth
local glBeginEnd   = gl.BeginEnd
local glVertex     = gl.Vertex
local GL_LINES     = GL.LINES

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local mathSqrt  = math.sqrt
local mathCos   = math.cos
local mathSin   = math.sin
local strFormat = string.format
local osClock   = os.clock

--------------------------------------------------------------------------------
-- Internal state
--------------------------------------------------------------------------------

local unitClassification = {}   -- defID -> class table
local myUnits = {}              -- unitID -> defID
local cachedResources = {
    metalIncome = 0, metalExpend = 0, metalCurrent = 0, metalStorage = 1,
    energyIncome = 0, energyExpend = 0, energyCurrent = 0, energyStorage = 1,
}
local lastResourceUpdate = 0
local RESOURCE_UPDATE_INTERVAL = 0.5

local automationAllowed = nil   -- cached, set on Initialize/GameStart
local automationLevel = 0         -- 0=overlay, 1=execute, 2=advise, 3=autonomous
local detectedFaction = "unknown"  -- "armada" | "cortex" | "unknown"

--------------------------------------------------------------------------------
-- Mode detection
--------------------------------------------------------------------------------

local function CheckAutomationAllowed()
    -- GDT (Game Developer Tools) rules param controls widget policy
    -- "noautomation" = ranked/PvP, no GiveOrder calls allowed
    -- nil or other = automation allowed
    local gdt = spGetGameRulesParam and spGetGameRulesParam("widget_allow_automaton")
    if gdt == 0 then
        automationAllowed = false
        return false
    end
    -- Also check the older/alternative param
    local noAuto = spGetGameRulesParam and spGetGameRulesParam("noautomation")
    if noAuto == 1 then
        automationAllowed = false
        return false
    end
    automationAllowed = true
    return true
end

local function IsAutomationAllowed()
    if automationAllowed == nil then
        CheckAutomationAllowed()
    end
    return automationAllowed
end

local function IsPvE()
    return IsAutomationAllowed()
end

local function GetAutomationLevel()
    return automationLevel
end

local function SetAutomationLevel(level)
    level = math.max(0, math.min(3, tonumber(level) or 0))
    automationLevel = level
    if WG.TotallyLegal then
        WG.TotallyLegal.automationLevel = level
    end
    spEcho("[TotallyLegal Core] Automation level set to " .. level)
end

--------------------------------------------------------------------------------
-- Faction detection
--------------------------------------------------------------------------------

local function DetectFaction()
    local myTeamID = spGetMyTeamID()
    local units = spGetTeamUnits(myTeamID)
    if not units then return end
    for _, uid in ipairs(units) do
        local defID = spGetUnitDefID(uid)
        if defID and UnitDefs[defID] then
            local cp = UnitDefs[defID].customParams or {}
            if cp.iscommander then
                local name = (UnitDefs[defID].name or ""):lower()
                if name:find("^arm") then
                    detectedFaction = "armada"
                elseif name:find("^cor") then
                    detectedFaction = "cortex"
                end
                return
            end
        end
    end
end

local function GetFaction()
    return detectedFaction
end

--------------------------------------------------------------------------------
-- Building infrastructure: key resolution, mex spots, placement
-- Single source of truth — all engine widgets use these instead of local copies.
--------------------------------------------------------------------------------

local keyToDefID = {}            -- short_key -> defID
local keysBuiltForFaction = "none"
local mexSpots = nil             -- cached array of {x, z}
local mexSpotsMethod = "none"    -- which method found the spots

local BUILD_CFG = {
    buildSpacing    = 80,
    maxSpiralSteps  = 30,
    mexSearchRadius = 1500,
}

-- Build the short_key -> defID mapping for the given faction.
-- Called once at GameStart when faction is known. Filters wrong-faction units.
local function BuildKeyTable(faction)
    if faction == keysBuiltForFaction and faction ~= "unknown" then return end

    keyToDefID = {}
    keysBuiltForFaction = faction

    local skipPrefix = nil
    if faction == "armada" then skipPrefix = "^cor"
    elseif faction == "cortex" then skipPrefix = "^arm"
    end

    for defID, def in pairs(UnitDefs) do
        local name = (def.name or ""):lower()
        local cp = def.customParams or {}

        if skipPrefix and name:find(skipPrefix) then
            -- skip wrong faction
        else
            -- Direct name lookup
            keyToDefID[name] = defID

            -- Metal extractors
            if def.extractsMetal and def.extractsMetal > 0 then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["moho"] = keyToDefID["moho"] or defID
                    keyToDefID["adv_mex"] = keyToDefID["adv_mex"] or defID
                else
                    keyToDefID["mex"] = keyToDefID["mex"] or defID
                end
            end

            -- Wind generators
            if def.windGenerator and def.windGenerator > 0 then
                keyToDefID["wind"] = keyToDefID["wind"] or defID
            end

            -- Solar: detect by name (BAR solars have energyMake=0; set via Lua runtime)
            if name:find("solar") and def.isBuilding then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_solar"] = keyToDefID["adv_solar"] or defID
                else
                    keyToDefID["solar"] = keyToDefID["solar"] or defID
                end
            end

            -- Fusion: high energy output buildings
            if def.energyMake and def.energyMake >= 200 and def.isBuilding then
                keyToDefID["fusion"] = keyToDefID["fusion"] or defID
            end

            -- Bot factories (armlab/corlab, armalab/coralab)
            if def.isFactory and name:find("lab") then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_bot_lab"] = keyToDefID["adv_bot_lab"] or defID
                else
                    keyToDefID["bot_lab"] = keyToDefID["bot_lab"] or defID
                end
            end

            -- Vehicle plants (armvp/corvp, armavp/coravp)
            if def.isFactory and name:find("vp") then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_vehicle_plant"] = keyToDefID["adv_vehicle_plant"] or defID
                else
                    keyToDefID["vehicle_plant"] = keyToDefID["vehicle_plant"] or defID
                end
            end

            -- Energy converters
            if cp.energyconv_capacity then
                local tl = tonumber(cp.techlevel) or 1
                if tl >= 2 then
                    keyToDefID["adv_converter"] = keyToDefID["adv_converter"] or defID
                else
                    keyToDefID["converter"] = keyToDefID["converter"] or defID
                end
            end

            -- Geothermal
            if cp.geothermal then
                keyToDefID["geo"] = keyToDefID["geo"] or defID
            end

            -- Nano turret (building with buildSpeed but not factory)
            if def.isBuilding and (def.buildSpeed or 0) > 0 and not def.isFactory then
                keyToDefID["nano"] = keyToDefID["nano"] or defID
            end

            -- Radar
            if def.isBuilding and def.radarRadius and def.radarRadius > 0 then
                keyToDefID["radar"] = keyToDefID["radar"] or defID
            end

            -- LLT (cheap T1 defense turret)
            if def.isBuilding and def.weapons and #def.weapons > 0 and not def.isFactory then
                local cost = def.metalCost or 0
                if cost < 200 and (tonumber(cp.techlevel) or 1) < 2 then
                    keyToDefID["llt"] = keyToDefID["llt"] or defID
                end
            end
        end
    end

    spEcho("[TotallyLegal Core] Keys built for " .. faction ..
           " | mex=" .. tostring(keyToDefID["mex"] ~= nil) ..
           " wind=" .. tostring(keyToDefID["wind"] ~= nil) ..
           " solar=" .. tostring(keyToDefID["solar"] ~= nil) ..
           " bot_lab=" .. tostring(keyToDefID["bot_lab"] ~= nil) ..
           " vp=" .. tostring(keyToDefID["vehicle_plant"] ~= nil) ..
           " fusion=" .. tostring(keyToDefID["fusion"] ~= nil))
end

local function ResolveKey(key)
    if not key then return nil end
    return keyToDefID[key:lower()] or keyToDefID[key]
end

local function GetKeyTable()
    return keyToDefID
end

-- Mex spot discovery: tries multiple methods in order of reliability.
-- Returns array of {x, z} positions representing actual metal spots.
local function LoadMexSpots()
    if mexSpots then return mexSpots end

    -- Method 1: WG.metalSpots (populated by BAR's built-in mex overlay widget)
    if WG.metalSpots then
        local raw = WG.metalSpots
        if type(raw) == "table" then
            local spots = {}
            for _, spot in ipairs(raw) do
                local sx = spot.x or spot[1]
                local sz = spot.z or spot[3] or spot[2]
                if sx and sz then
                    spots[#spots + 1] = { x = sx, z = sz }
                end
            end
            if #spots > 0 then
                mexSpots = spots
                mexSpotsMethod = "WG.metalSpots"
                spEcho("[TotallyLegal Core] Mex spots from WG.metalSpots: " .. #mexSpots)
                return mexSpots
            end
        end
    end

    -- Method 2: Spring.GetMetalMapSpots (may return nil in widget context)
    if Spring.GetMetalMapSpots then
        local ok, raw = pcall(Spring.GetMetalMapSpots)
        if ok and raw and type(raw) == "table" and #raw > 0 then
            mexSpots = {}
            for _, spot in ipairs(raw) do
                local sx = spot.x or spot[1]
                local sz = spot.z or spot[3] or spot[2]
                if sx and sz then
                    mexSpots[#mexSpots + 1] = { x = sx, z = sz }
                end
            end
            if #mexSpots > 0 then
                mexSpotsMethod = "Spring.GetMetalMapSpots"
                spEcho("[TotallyLegal Core] Mex spots from Spring API: " .. #mexSpots)
                return mexSpots
            end
        end
    end

    -- Method 3: Metal map scan using Spring.GetMetalAmount
    -- The metal map has 16-elmo resolution. We scan it and find positions
    -- with actual metal, then snap them to valid build positions.
    if Spring.GetMetalAmount then
        local mapX = Game.mapSizeX or 8192
        local mapZ = Game.mapSizeZ or 8192
        local metalRes = 16
        local mexDefID = ResolveKey("mex")

        -- Collect all positions with metal > 0
        local metalPositions = {}
        local metalMapW = mathFloor(mapX / metalRes)
        local metalMapH = mathFloor(mapZ / metalRes)

        for mx = 0, metalMapW - 1 do
            for mz = 0, metalMapH - 1 do
                local ok2, metal = pcall(Spring.GetMetalAmount, mx, mz)
                if ok2 and metal and metal > 0 then
                    metalPositions[#metalPositions + 1] = {
                        x = mx * metalRes + metalRes / 2,
                        z = mz * metalRes + metalRes / 2,
                    }
                end
            end
        end

        if #metalPositions > 0 then
            -- Cluster nearby metal squares into discrete spots.
            -- Each metal spot covers a small radius of metal squares.
            local used = {}
            local clusterRadius = 80  -- squares within 80 elmos = same spot
            local spots = {}

            for i, pos in ipairs(metalPositions) do
                if not used[i] then
                    local sumX, sumZ, count = 0, 0, 0
                    for j = i, #metalPositions do
                        if not used[j] then
                            local dx = metalPositions[j].x - pos.x
                            local dz = metalPositions[j].z - pos.z
                            if (dx * dx + dz * dz) < clusterRadius * clusterRadius then
                                sumX = sumX + metalPositions[j].x
                                sumZ = sumZ + metalPositions[j].z
                                count = count + 1
                                used[j] = true
                            end
                        end
                    end

                    if count > 0 then
                        -- Snap cluster center to metal-map grid
                        local cx = mathFloor(sumX / count / metalRes) * metalRes
                        local cz = mathFloor(sumZ / count / metalRes) * metalRes

                        -- Verify buildable if we have mex defID
                        if mexDefID then
                            local cy = spGetGroundHeight(cx, cz) or 0
                            local result = spTestBuildOrder(mexDefID, cx, cy, cz, 0)
                            if result and result > 0 then
                                spots[#spots + 1] = { x = cx, z = cz }
                            end
                        else
                            spots[#spots + 1] = { x = cx, z = cz }
                        end
                    end
                end
            end

            if #spots > 0 then
                mexSpots = spots
                mexSpotsMethod = "metal_map_scan"
                spEcho("[TotallyLegal Core] Mex spots from metal map: " .. #mexSpots)
                return mexSpots
            end
        end
    end

    -- Method 4: Grid scan with TestBuildOrder + sanity check
    -- Only accepts if count is in realistic range (20-200 for typical maps).
    local mexDefID = ResolveKey("mex")
    if mexDefID then
        local mapX = Game.mapSizeX or 8192
        local mapZ = Game.mapSizeZ or 8192
        local step = 64
        local candidates = {}

        for gx = step, mapX - step, step do
            for gz = step, mapZ - step, step do
                local gy = spGetGroundHeight(gx, gz) or 0
                local result = spTestBuildOrder(mexDefID, gx, gy, gz, 0)
                if result and result >= 2 then
                    candidates[#candidates + 1] = { x = gx, z = gz }
                end
            end
        end

        if #candidates > 0 and #candidates <= 200 then
            mexSpots = candidates
            mexSpotsMethod = "grid_scan"
            spEcho("[TotallyLegal Core] Mex spots from grid scan: " .. #mexSpots)
        else
            mexSpots = {}
            mexSpotsMethod = "none"
            spEcho("[TotallyLegal Core] Grid scan got " .. #candidates ..
                   " positions (expected 20-200). Mex auto-placement disabled." ..
                   " Available APIs: GetMetalMapSpots=" .. tostring(Spring.GetMetalMapSpots ~= nil) ..
                   " GetMetalAmount=" .. tostring(Spring.GetMetalAmount ~= nil) ..
                   " WG.metalSpots=" .. tostring(WG.metalSpots ~= nil))
        end
    else
        mexSpots = {}
        mexSpotsMethod = "none"
        spEcho("[TotallyLegal Core] No mex defID resolved. Mex auto-placement disabled.")
    end

    return mexSpots
end

local function GetMexSpots()
    return LoadMexSpots()
end

local function InvalidateMexSpots()
    mexSpots = nil
    mexSpotsMethod = "none"
end

-- Find the nearest unoccupied mex spot to (x, z).
local function FindNearestMexSpot(x, z)
    local spots = LoadMexSpots()
    if not spots or #spots == 0 then return nil, nil end

    local mexDefID = ResolveKey("mex")
    if not mexDefID then return nil, nil end

    local bestX, bestZ = nil, nil
    local bestDist = math.huge

    for _, spot in ipairs(spots) do
        local dx = spot.x - x
        local dz = spot.z - z
        local dist = mathSqrt(dx * dx + dz * dz)
        if dist < bestDist and dist < BUILD_CFG.mexSearchRadius then
            local gy = spGetGroundHeight(spot.x, spot.z) or 0
            local result = spTestBuildOrder(mexDefID, spot.x, gy, spot.z, 0)
            if result and result > 0 then
                bestDist = dist
                bestX = spot.x
                bestZ = spot.z
            end
        end
    end

    return bestX, bestZ
end

-- Find a build position for any structure.
-- Mex: snaps to nearest metal spot. Others: spiral outward from base position.
-- Optional 'options' table: { buildArea = {center={x,z}, radius=N, defined=bool} }
local function FindBuildPosition(builderID, defID, baseX, baseZ, options)
    local def = UnitDefs[defID]
    if not def then return nil, nil end

    -- Metal extractors: find nearest real mex spot
    if def.extractsMetal and def.extractsMetal > 0 then
        return FindNearestMexSpot(baseX, baseZ)
    end

    -- Constrain to building area if provided
    local buildArea = options and options.buildArea
    if buildArea and buildArea.defined then
        baseX = buildArea.center.x
        baseZ = buildArea.center.z
    end

    -- Spiral outward from base position
    local mapSizeX = Game.mapSizeX or 8192
    local mapSizeZ = Game.mapSizeZ or 8192

    for step = 0, BUILD_CFG.maxSpiralSteps do
        local angle = step * 2.4  -- golden angle for good coverage
        local radius = BUILD_CFG.buildSpacing * (1 + step * 0.3)
        local tx = baseX + mathCos(angle) * radius
        local tz = baseZ + mathSin(angle) * radius

        tx = mathMax(64, mathMin(tx, mapSizeX - 64))
        tz = mathMax(64, mathMin(tz, mapSizeZ - 64))

        -- Respect build area constraint
        if buildArea and buildArea.defined then
            local dx = tx - buildArea.center.x
            local dz = tz - buildArea.center.z
            if (dx * dx + dz * dz) > (buildArea.radius * buildArea.radius) then
                goto continue
            end
        end

        do
            local result = spTestBuildOrder(defID, tx, spGetGroundHeight(tx, tz) or 0, tz, 0)
            if result and result > 0 then
                return tx, tz
            end
        end

        ::continue::
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Unit classification engine
--------------------------------------------------------------------------------

local function BuildUnitClassificationTable()
    unitClassification = {}

    for defID, def in pairs(UnitDefs) do
        local cls = {
            resource    = nil,       -- resource category string or nil
            census      = nil,       -- census category string or nil
            buildSpeed  = def.buildSpeed or 0,
            metalCost   = def.metalCost or 0,
            energyCost  = def.energyCost or 0,
            isFactory   = def.isFactory or false,
            isBuilder   = (def.buildSpeed or 0) > 0,
            isBuilding  = def.isBuilding or false,
            techLevel   = 1,
            maxSpeed    = def.speed or 0,
            weaponRange = 0,
            weaponCount = 0,
            canFly      = def.canFly or false,
            canMove     = def.canMove or false,
        }

        local cp = def.customParams or {}
        cls.techLevel = tonumber(cp.techlevel) or 1

        -- Weapon data
        if def.weapons and #def.weapons > 0 then
            cls.weaponCount = #def.weapons
            local maxRange = 0
            for _, w in ipairs(def.weapons) do
                local wDefID = w.weaponDef
                if wDefID and WeaponDefs[wDefID] then
                    local r = WeaponDefs[wDefID].range or 0
                    if r > maxRange then maxRange = r end
                end
            end
            cls.weaponRange = maxRange
        end

        -- Resource classification
        if def.extractsMetal and def.extractsMetal > 0 then
            cls.resource = (cls.techLevel >= 2) and "adv_mex" or "mex"
        elseif def.windGenerator and def.windGenerator > 0 then
            cls.resource = "wind"
        elseif cp.energyconv_capacity then
            cls.resource = (cls.techLevel >= 2) and "adv_converter" or "converter"
        elseif def.tidalGenerator and def.tidalGenerator > 0 then
            cls.resource = "tidal"
        elseif cp.geothermal then
            cls.resource = "geo"
        elseif def.isBuilding and (def.name or ""):lower():find("solar") then
            -- Solar: detect by name (BAR solars have energyMake=0; set via Lua runtime)
            cls.resource = cls.techLevel >= 2 and "adv_solar" or "solar"
        elseif def.energyMake and def.energyMake >= 200 and def.isBuilding then
            cls.resource = "fusion"
        end

        -- Census classification
        if def.isFactory then
            cls.census = "factory"
        elseif def.isBuilding then
            local hasWeapons = def.weapons and #def.weapons > 0
            if hasWeapons then
                cls.census = "defense"
            elseif cls.resource then
                cls.census = "economy"
            elseif def.radarRadius and def.radarRadius > 0 then
                cls.census = "utility"
            elseif def.jammerRadius and def.jammerRadius > 0 then
                cls.census = "utility"
            else
                cls.census = "utility"
            end
        elseif def.canFly then
            cls.census = "aircraft"
        elseif def.canMove then
            if cls.buildSpeed > 0 then
                cls.census = "builder"
            else
                local hasWeapons = def.weapons and #def.weapons > 0
                if not hasWeapons then
                    cls.census = "utility"
                elseif def.moveDef and def.moveDef.name then
                    local mn = def.moveDef.name:lower()
                    if mn:find("boat") or mn:find("ship") or mn:find("hover") then
                        cls.census = "ship"
                    elseif mn:find("tank") or mn:find("veh") then
                        cls.census = "vehicle_combat"
                    else
                        cls.census = "bot_combat"
                    end
                else
                    local speed = def.speed or 0
                    if speed > 0 then
                        cls.census = "bot_combat"
                    else
                        cls.census = "utility"
                    end
                end
            end
        end

        -- Commander override
        if cp.iscommander then
            cls.census = "builder"
        end

        unitClassification[defID] = cls
    end
end

local function GetUnitClass(defID)
    return unitClassification[defID]
end

local function RebuildClassification()
    BuildUnitClassificationTable()
end

--------------------------------------------------------------------------------
-- Unit tracking
--------------------------------------------------------------------------------

local function RebuildUnitCache()
    myUnits = {}
    local myTeamID = spGetMyTeamID()
    local units = spGetTeamUnits(myTeamID)
    if units then
        for i = 1, #units do
            local uid = units[i]
            local defID = spGetUnitDefID(uid)
            if defID then
                myUnits[uid] = defID
            end
        end
    end
end

local function GetMyUnits()
    return myUnits
end

--------------------------------------------------------------------------------
-- Team resources (cached)
--------------------------------------------------------------------------------

local function UpdateTeamResources()
    local now = osClock()
    if now - lastResourceUpdate < RESOURCE_UPDATE_INTERVAL then
        return cachedResources
    end
    lastResourceUpdate = now

    local myTeamID = spGetMyTeamID()
    local mCur, mStor, mPull, mInc, mExp = spGetTeamResources(myTeamID, "metal")
    local eCur, eStor, ePull, eInc, eExp = spGetTeamResources(myTeamID, "energy")

    cachedResources.metalIncome  = mInc or 0
    cachedResources.metalExpend  = mExp or 0
    cachedResources.metalCurrent = mCur or 0
    cachedResources.metalStorage = mathMax(mStor or 1, 1)
    cachedResources.energyIncome  = eInc or 0
    cachedResources.energyExpend  = eExp or 0
    cachedResources.energyCurrent = eCur or 0
    cachedResources.energyStorage = mathMax(eStor or 1, 1)

    return cachedResources
end

local function GetTeamResources()
    return UpdateTeamResources()
end

--------------------------------------------------------------------------------
-- Math helpers
--------------------------------------------------------------------------------

local function Dist2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return mathSqrt(dx * dx + dz * dz)
end

local function Dist3D(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return mathSqrt(dx * dx + dy * dy + dz * dz)
end

local function NearestUnit(x, z, unitTable)
    local bestUID = nil
    local bestDist = math.huge
    for uid, defID in pairs(unitTable) do
        local ux, uy, uz = spGetUnitPosition(uid)
        if ux then
            local d = Dist2D(x, z, ux, uz)
            if d < bestDist then
                bestDist = d
                bestUID = uid
            end
        end
    end
    return bestUID, bestDist
end

local function PointInCircle(px, pz, cx, cz, r)
    local dx = px - cx
    local dz = pz - cz
    return (dx * dx + dz * dz) <= (r * r)
end

local function DistToLineSegment(px, pz, x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    local lenSq = dx * dx + dz * dz
    if lenSq == 0 then return Dist2D(px, pz, x1, z1) end
    local t = mathMax(0, mathMin(1, ((px - x1) * dx + (pz - z1) * dz) / lenSq))
    local projX = x1 + t * dx
    local projZ = z1 + t * dz
    return Dist2D(px, pz, projX, projZ)
end

--------------------------------------------------------------------------------
-- Rendering helpers
--------------------------------------------------------------------------------

local function FormatRate(n)
    if n == nil then return "0" end
    if n >= 1000 then
        return strFormat("%.1fk", n / 1000)
    elseif n >= 100 then
        return strFormat("%.0f", n)
    elseif n >= 10 then
        return strFormat("%.1f", n)
    else
        return strFormat("%.1f", n)
    end
end

local function FormatInt(n)
    if n == nil then return "0" end
    if n >= 100000 then
        return strFormat("%.0fk", n / 1000)
    elseif n >= 10000 then
        return strFormat("%.1fk", n / 1000)
    else
        return strFormat("%.0f", n)
    end
end

local function FormatBP(n)
    if n == nil then return "0" end
    return strFormat("%.0f", n)
end

local function SetColor(c)
    glColor(c[1], c[2], c[3], c[4])
end

local function DrawFilledRect(x1, y1, x2, y2)
    glRect(x1, y1, x2, y2)
end

local function DrawHLine(x1, x2, y, c)
    SetColor(c)
    glLineWidth(1)
    glBeginEnd(GL_LINES, function()
        glVertex(x1, y, 0)
        glVertex(x2, y, 0)
    end)
end

--------------------------------------------------------------------------------
-- Widget lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    BuildUnitClassificationTable()
    CheckAutomationAllowed()

    if spGetGameFrame() > 0 then
        RebuildUnitCache()
        UpdateTeamResources()
    end

    -- Expose everything via WG table
    WG.TotallyLegal = {
        -- Meta
        automationLevel     = automationLevel,
        GetAutomationLevel  = GetAutomationLevel,
        SetAutomationLevel  = SetAutomationLevel,

        -- Widget visibility (sidebar manages this, other widgets check it)
        WidgetVisibility    = {},

        -- Mode detection
        IsAutomationAllowed = IsAutomationAllowed,
        IsPvE               = IsPvE,

        -- Unit classification
        GetUnitClass         = GetUnitClass,
        RebuildClassification = RebuildClassification,

        -- Team data
        GetMyUnits       = GetMyUnits,
        GetTeamResources = GetTeamResources,

        -- Faction
        DetectFaction = DetectFaction,
        GetFaction    = GetFaction,

        -- Building infrastructure (shared — engines use these, not local copies)
        BuildKeyTable      = BuildKeyTable,
        ResolveKey         = ResolveKey,
        GetKeyTable        = GetKeyTable,
        LoadMexSpots       = LoadMexSpots,
        GetMexSpots        = GetMexSpots,
        InvalidateMexSpots = InvalidateMexSpots,
        FindBuildPosition  = FindBuildPosition,
        FindNearestMexSpot = FindNearestMexSpot,

        -- Math helpers
        Dist2D             = Dist2D,
        Dist3D             = Dist3D,
        NearestUnit        = NearestUnit,
        PointInCircle      = PointInCircle,
        DistToLineSegment  = DistToLineSegment,

        -- Rendering helpers
        FormatRate     = FormatRate,
        FormatInt      = FormatInt,
        FormatBP       = FormatBP,
        SetColor       = SetColor,
        DrawFilledRect = DrawFilledRect,
        DrawHLine      = DrawHLine,
    }

    spEcho("[TotallyLegal Core] Initialized. Automation allowed: " .. tostring(IsAutomationAllowed()))
end

function widget:GameStart()
    RebuildUnitCache()
    CheckAutomationAllowed()
    DetectFaction()
    BuildKeyTable(detectedFaction)
    LoadMexSpots()
    spEcho("[TotallyLegal Core] GameStart complete | faction=" .. detectedFaction ..
           " | mexSpots=" .. (mexSpots and #mexSpots or 0) .. " (" .. mexSpotsMethod .. ")")
end

function widget:Update(dt)
    UpdateTeamResources()
end

-- Unit tracking callins
function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitTeam == spGetMyTeamID() then
        myUnits[unitID] = unitDefID
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    myUnits[unitID] = nil
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if newTeam == spGetMyTeamID() then
        myUnits[unitID] = unitDefID
    elseif oldTeam == spGetMyTeamID() then
        myUnits[unitID] = nil
    end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
    if newTeam == spGetMyTeamID() then
        myUnits[unitID] = unitDefID
    elseif oldTeam == spGetMyTeamID() then
        myUnits[unitID] = nil
    end
end

function widget:Shutdown()
    WG.TotallyLegal = nil
end
