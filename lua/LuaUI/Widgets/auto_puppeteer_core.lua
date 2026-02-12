-- Unit Puppeteer: Core - Shared state, toggle system, unit management
-- Foundation widget for the Puppeteer family. Loads first, owns the state table.
-- Other auto_puppeteer_* widgets read/write through WG.TotallyLegal.Puppeteer.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: 01_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "Puppeteer Core",
        desc      = "Unit Puppeteer shared state and toggle system. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 103,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetGameFrame        = Spring.GetGameFrame
local spGetConfigInt        = Spring.GetConfigInt
local spSetConfigInt        = Spring.SetConfigInt
local spEcho                = Spring.Echo

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    unitRefreshFrequency = 30,   -- refresh unit registry every N frames (~1s)
    maxManagedUnits      = 80,   -- performance cap across all puppeteer widgets
}

--------------------------------------------------------------------------------
-- Toggle defaults
--------------------------------------------------------------------------------

local DEFAULT_TOGGLES = {
    smartMove        = true,
    dodge            = true,
    formations       = true,
    formationShape   = 1,        -- 1=line, 2=circle, 3=half_circle, 4=square, 5=star
    formationNesting = 1,        -- 1-5 concentric layers
    roleSort         = true,
    firingLine       = false,
    firingLineWidth  = 1,        -- 1-5 units wide
    scatter          = false,
    scatterDistance   = 120,      -- elmos
    march            = false,
    rangeWalk        = false,
}

-- Shape name lookup
local SHAPE_NAMES = { "line", "circle", "half_circle", "square", "star" }
local SHAPE_COUNT = #SHAPE_NAMES

--------------------------------------------------------------------------------
-- Weapon range cache
--------------------------------------------------------------------------------

local weaponRangeCache = {}  -- defID -> maxRange

local function GetWeaponRange(defID)
    if weaponRangeCache[defID] then return weaponRangeCache[defID] end

    local def = UnitDefs[defID]
    if not def or not def.weapons then
        weaponRangeCache[defID] = 0
        return 0
    end

    local maxRange = 0
    for _, w in ipairs(def.weapons) do
        local wDefID = w.weaponDef
        if wDefID and WeaponDefs[wDefID] then
            local wd = WeaponDefs[wDefID]
            -- Skip AA-only weapons (can't hit ground units)
            if wd.canAttackGround ~= false then
                local r = wd.range or 0
                if r > maxRange then maxRange = r end
            end
        end
    end

    weaponRangeCache[defID] = maxRange
    return maxRange
end

--------------------------------------------------------------------------------
-- Unit classification for role sorting
--------------------------------------------------------------------------------

local unitRoleCache = {}  -- defID -> "assault"|"standard"|"artillery"|"scout"

local function ClassifyUnit(defID)
    if unitRoleCache[defID] then return unitRoleCache[defID] end

    local def = UnitDefs[defID]
    if not def then
        unitRoleCache[defID] = "standard"
        return "standard"
    end

    local range = GetWeaponRange(defID)
    local hp = def.health or 0
    local speed = def.speed or 0

    local role
    if range > 600 then
        role = "artillery"
    elseif speed > 80 and hp < 500 then
        role = "scout"
    elseif range < 350 and hp > 1000 then
        role = "assault"
    else
        role = "standard"
    end

    unitRoleCache[defID] = role
    return role
end

--------------------------------------------------------------------------------
-- Toggle persistence
--------------------------------------------------------------------------------

local function LoadToggles()
    local toggles = {}
    for key, default in pairs(DEFAULT_TOGGLES) do
        local configKey = "Puppeteer_" .. key
        if type(default) == "boolean" then
            local val = spGetConfigInt(configKey, default and 1 or 0)
            toggles[key] = (val == 1)
        elseif type(default) == "number" then
            toggles[key] = spGetConfigInt(configKey, default)
        end
    end
    return toggles
end

local function SaveToggles(toggles)
    for key, val in pairs(toggles) do
        local configKey = "Puppeteer_" .. key
        if type(val) == "boolean" then
            spSetConfigInt(configKey, val and 1 or 0)
        elseif type(val) == "number" then
            spSetConfigInt(configKey, val)
        end
    end
end

--------------------------------------------------------------------------------
-- Unit registry
--------------------------------------------------------------------------------

local function RefreshUnitRegistry(puppeteer)
    local units = {}
    local count = 0

    local myUnits = TL.GetMyUnits()
    if not myUnits then return end

    for uid, defID in pairs(myUnits) do
        if count >= CFG.maxManagedUnits then break end

        local cls = TL.GetUnitClass(defID)
        if cls and cls.canMove and not cls.isFactory and not cls.isBuilding and not cls.isBuilder then
            local speed = cls.maxSpeed or 0
            if speed > 0 then
                local def = UnitDefs[defID]
                local radius = def and (def.xsize or 2) * 8 or 16
                local range = GetWeaponRange(defID)
                local role = ClassifyUnit(defID)

                -- Preserve existing formation position if unit was already managed
                local existing = puppeteer.units[uid]
                local formationPos = existing and existing.formationPos or nil
                local state = existing and existing.state or "idle"

                units[uid] = {
                    defID        = defID,
                    role         = role,
                    range        = range,
                    speed        = speed,
                    radius       = radius,
                    hasWeapon    = (cls.weaponCount or 0) > 0,
                    formationPos = formationPos,
                    state        = state,
                }
                count = count + 1
            end
        end
    end

    puppeteer.units = units
    puppeteer.unitCount = count
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local function GetShapeName(idx)
    return SHAPE_NAMES[idx] or "line"
end

local function CycleShape(toggles)
    local current = toggles.formationShape or 1
    current = current + 1
    if current > SHAPE_COUNT then current = 1 end
    toggles.formationShape = current
    return GetShapeName(current)
end

local function SetToggle(puppeteer, key, value)
    if puppeteer.toggles[key] ~= nil then
        puppeteer.toggles[key] = value
        SaveToggles(puppeteer.toggles)
        spEcho("[Puppeteer] " .. key .. " = " .. tostring(value))
    end
end

local function ToggleBool(puppeteer, key)
    if type(puppeteer.toggles[key]) == "boolean" then
        puppeteer.toggles[key] = not puppeteer.toggles[key]
        SaveToggles(puppeteer.toggles)
        spEcho("[Puppeteer] " .. key .. " = " .. tostring(puppeteer.toggles[key]))
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[Puppeteer Core] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[Puppeteer Core] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Initialize shared state
    local toggles = LoadToggles()
    local activeState = spGetConfigInt("Puppeteer_active", 1)

    WG.TotallyLegal.Puppeteer = {
        active    = (activeState == 1),
        toggles   = toggles,
        units     = {},          -- unitID -> unit data
        unitCount = 0,
        groups    = {},          -- groupID -> formation data
        firingLines = {},        -- lineID -> firing line state

        -- Public API
        GetShapeName  = GetShapeName,
        CycleShape    = function() return CycleShape(toggles) end,
        SetToggle     = function(key, val) SetToggle(WG.TotallyLegal.Puppeteer, key, val) end,
        ToggleBool    = function(key) ToggleBool(WG.TotallyLegal.Puppeteer, key) end,
        GetWeaponRange = GetWeaponRange,
        ClassifyUnit   = ClassifyUnit,
        SHAPE_NAMES    = SHAPE_NAMES,
        SHAPE_COUNT    = SHAPE_COUNT,
    }

    -- Signal old dodge/skirmish to yield
    WG.TotallyLegal.PuppeteerActive = true

    spEcho("[Puppeteer Core] Enabled. Managing up to " .. CFG.maxManagedUnits .. " units.")
end

function widget:Shutdown()
    if WG.TotallyLegal then
        -- Save toggles before shutdown
        local pup = WG.TotallyLegal.Puppeteer
        if pup and pup.toggles then
            SaveToggles(pup.toggles)
        end

        WG.TotallyLegal.Puppeteer = nil
        WG.TotallyLegal.PuppeteerActive = nil
    end
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    local puppeteer = WG.TotallyLegal.Puppeteer
    if not puppeteer then return end

    if frame % CFG.unitRefreshFrequency == 0 then
        local ok, err = pcall(RefreshUnitRegistry, puppeteer)
        if not ok then
            spEcho("[Puppeteer Core] RefreshUnits error: " .. tostring(err))
        end
    end
end

-- Track unit creation
function widget:UnitCreated(unitID, unitDefID, unitTeam)
    if not TL then return end
    local puppeteer = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
    if not puppeteer then return end
    if unitTeam ~= spGetMyTeamID() then return end

    local cls = TL.GetUnitClass(unitDefID)
    if cls and cls.canMove and not cls.isFactory and not cls.isBuilding and not cls.isBuilder then
        local speed = cls.maxSpeed or 0
        if speed > 0 and puppeteer.unitCount < CFG.maxManagedUnits then
            local def = UnitDefs[unitDefID]
            local radius = def and (def.xsize or 2) * 8 or 16
            puppeteer.units[unitID] = {
                defID        = unitDefID,
                role         = ClassifyUnit(unitDefID),
                range        = GetWeaponRange(unitDefID),
                speed        = speed,
                radius       = radius,
                hasWeapon    = (cls.weaponCount or 0) > 0,
                formationPos = nil,
                state        = "idle",
            }
            puppeteer.unitCount = (puppeteer.unitCount or 0) + 1
        end
    end
end

-- Track unit destruction
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    local puppeteer = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
    if not puppeteer then return end

    if puppeteer.units[unitID] then
        puppeteer.units[unitID] = nil
        puppeteer.unitCount = mathMax(0, (puppeteer.unitCount or 1) - 1)
    end
end

-- Track unit transfers (gifted/captured)
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if newTeam == spGetMyTeamID() then
        self:UnitCreated(unitID, unitDefID, newTeam)
    else
        self:UnitDestroyed(unitID, unitDefID, oldTeam)
    end
end
