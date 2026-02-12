-- Puppeteer Speed Gadget: Server-side speed limiting for march groups
-- Receives speed requests from the Puppeteer March widget via SendLuaRulesMsg.
-- Calls Spring.SetGroundMoveTypeData (synced-only API) to cap unit speed.
-- PvE/Unranked ONLY.
--
-- Protocol (widget -> gadget via Spring.SendLuaRulesMsg):
--   "pup_speed|unitID|maxSpeed"   -- set max speed for unit
--   "pup_speed_reset|unitID"      -- restore original max speed

function gadget:GetInfo()
    return {
        name      = "Puppeteer Speed",
        desc      = "Server-side speed limiting for Puppeteer march groups.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Synced only
--------------------------------------------------------------------------------

if not gadgetHandler:IsSyncedCode() then
    return
end

--------------------------------------------------------------------------------
-- Localized API
--------------------------------------------------------------------------------

local spGetUnitDefID          = Spring.GetUnitDefID
local spGetUnitTeam           = Spring.GetUnitTeam
local spSetGroundMoveTypeData = Spring.MoveCtrl and Spring.MoveCtrl.SetGroundMoveTypeData
                                or Spring.SetGroundMoveTypeData
local spEcho                  = Spring.Echo
local spValidUnitID           = Spring.ValidUnitID

local tonumber = tonumber
local strFind  = string.find
local strSub   = string.sub

--------------------------------------------------------------------------------
-- State: track which units have capped speed so we can restore them
--------------------------------------------------------------------------------

local cappedUnits = {}  -- unitID -> originalMaxSpeed

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetOriginalMaxSpeed(unitID)
    local defID = spGetUnitDefID(unitID)
    if not defID then return nil end
    local def = UnitDefs[defID]
    if not def then return nil end
    return def.speed or 0
end

-- Simple split on '|'
local function ParseMsg(msg)
    local parts = {}
    local start = 1
    while true do
        local pos = strFind(msg, "|", start, true)
        if not pos then
            parts[#parts + 1] = strSub(msg, start)
            break
        end
        parts[#parts + 1] = strSub(msg, start, pos - 1)
        start = pos + 1
    end
    return parts
end

local function SetUnitSpeed(unitID, speed)
    if not spValidUnitID(unitID) then return end

    -- Store original if not already capped
    if not cappedUnits[unitID] then
        local origSpeed = GetOriginalMaxSpeed(unitID)
        if not origSpeed or origSpeed <= 0 then return end
        cappedUnits[unitID] = origSpeed
    end

    -- Clamp: never set higher than original
    local clamped = math.min(speed, cappedUnits[unitID])
    if clamped <= 0 then return end

    local ok, err = pcall(spSetGroundMoveTypeData, unitID, "maxWantedSpeed", clamped)
    if not ok then
        spEcho("[Puppeteer Speed] SetGroundMoveTypeData error: " .. tostring(err))
    end
end

local function ResetUnitSpeed(unitID)
    if not cappedUnits[unitID] then return end
    if not spValidUnitID(unitID) then
        cappedUnits[unitID] = nil
        return
    end

    local origSpeed = cappedUnits[unitID]
    local ok, err = pcall(spSetGroundMoveTypeData, unitID, "maxWantedSpeed", origSpeed)
    if not ok then
        spEcho("[Puppeteer Speed] Reset error: " .. tostring(err))
    end
    cappedUnits[unitID] = nil
end

--------------------------------------------------------------------------------
-- Message handler
--------------------------------------------------------------------------------

function gadget:RecvLuaMsg(msg, playerID)
    if not msg then return end

    -- Quick prefix check
    if strSub(msg, 1, 9) ~= "pup_speed" then return end

    local parts = ParseMsg(msg)
    local cmd = parts[1]

    if cmd == "pup_speed" then
        -- pup_speed|unitID|maxSpeed
        local unitID = tonumber(parts[2])
        local speed  = tonumber(parts[3])
        if unitID and speed then
            SetUnitSpeed(unitID, speed)
        end

    elseif cmd == "pup_speed_reset" then
        -- pup_speed_reset|unitID
        local unitID = tonumber(parts[2])
        if unitID then
            ResetUnitSpeed(unitID)
        end
    end
end

--------------------------------------------------------------------------------
-- Cleanup on unit death/transfer
--------------------------------------------------------------------------------

function gadget:UnitDestroyed(unitID)
    cappedUnits[unitID] = nil
end

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    -- Reset speed if unit changes hands
    ResetUnitSpeed(unitID)
end

--------------------------------------------------------------------------------
-- Safety: reset all on gadget shutdown
--------------------------------------------------------------------------------

function gadget:Shutdown()
    for unitID, _ in pairs(cappedUnits) do
        ResetUnitSpeed(unitID)
    end
    cappedUnits = {}
end
