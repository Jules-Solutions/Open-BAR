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
        elseif def.energyMake and def.energyMake > 0 then
            if def.isBuilding then
                if def.energyMake >= 200 then
                    cls.resource = "fusion"
                elseif cls.techLevel >= 2 then
                    cls.resource = "adv_solar"
                else
                    cls.resource = "solar"
                end
            end
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
