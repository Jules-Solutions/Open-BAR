-- TotallyLegal Auto Dodge - Projectile dodging for mobile units
-- Units automatically dodge incoming projectiles by moving perpendicular to the trajectory.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Auto Dodge",
        desc      = "Auto-dodge incoming projectiles. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 102,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID               = Spring.GetMyTeamID
local spGetUnitPosition           = Spring.GetUnitPosition
local spGetUnitDefID              = Spring.GetUnitDefID
local spGetUnitHealth             = Spring.GetUnitHealth
local spGetGameFrame              = Spring.GetGameFrame
local spGetGroundHeight           = Spring.GetGroundHeight
local spGiveOrderToUnit           = Spring.GiveOrderToUnit
local spGetProjectilesInRectangle = Spring.GetProjectilesInRectangle
local spGetProjectilePosition     = Spring.GetProjectilePosition
local spGetProjectileVelocity     = Spring.GetProjectileVelocity
local spGetProjectileDefID        = Spring.GetProjectileDefID

local CMD_MOVE = CMD.MOVE

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min
local mathAbs  = math.abs

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency = 3,        -- every N game frames (~0.1s)
    dodgeRadius     = 60,       -- how far to dodge (elmos)
    hitRadius       = 40,       -- consider projectile dangerous if impact within this radius
    maxProjectileSpeed = 800,   -- ignore projectiles faster than this (undodgeable)
    minUnitSpeed    = 30,       -- don't dodge with units slower than this
    cooldownFrames  = 15,       -- frames between dodge commands per unit
    maxManagedUnits = 30,       -- performance cap
    searchPadding   = 400,      -- search area around each unit for projectiles
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local managedUnits = {}      -- unitID -> { defID, speed, radius }
local dodgeCooldowns = {}    -- unitID -> frame

-- Cache: defIDs that are hitscan/beam weapons (undodgeable)
local hitscanWeapons = {}    -- weaponDefID -> true

local function BuildHitscanTable()
    hitscanWeapons = {}
    for wDefID, wDef in pairs(WeaponDefs) do
        if wDef.type == "BeamLaser" or wDef.type == "LightningCannon" then
            hitscanWeapons[wDefID] = true
        end
        -- Also skip very fast projectiles
        local speed = wDef.projectilespeed or wDef.weaponVelocity or 0
        if speed > CFG.maxProjectileSpeed / 30 then  -- convert to elmos/frame
            hitscanWeapons[wDefID] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Unit management
--------------------------------------------------------------------------------

local function RefreshManagedUnits()
    managedUnits = {}
    local myUnits = TL.GetMyUnits()
    local count = 0

    for uid, defID in pairs(myUnits) do
        if count >= CFG.maxManagedUnits then break end

        local cls = TL.GetUnitClass(defID)
        if cls and cls.canMove and not cls.isFactory and not cls.isBuilding then
            local speed = cls.maxSpeed or 0
            if speed >= CFG.minUnitSpeed then
                local def = UnitDefs[defID]
                local radius = def and (def.xsize or 2) * 8 or 16  -- approximate collision radius
                managedUnits[uid] = { defID = defID, speed = speed, radius = radius }
                count = count + 1
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Dodge logic
--------------------------------------------------------------------------------

local function PredictImpact(px, py, pz, vx, vy, vz, ux, uy, uz)
    -- Find closest point on projectile trajectory to unit
    -- Parametric: P(t) = (px + vx*t, py + vy*t, pz + vz*t)
    -- Minimize distance to (ux, uy, uz)

    local dx = ux - px
    local dy = uy - py
    local dz = uz - pz

    local vLen2 = vx * vx + vy * vy + vz * vz
    if vLen2 < 0.001 then return math.huge, 0, 0, 0 end

    local t = (dx * vx + dy * vy + dz * vz) / vLen2

    if t < 0 then return math.huge, 0, 0, 0 end  -- projectile moving away

    local closestX = px + vx * t
    local closestY = py + vy * t
    local closestZ = pz + vz * t

    local cx = closestX - ux
    local cy = closestY - uy
    local cz = closestZ - uz

    local closestDist = mathSqrt(cx * cx + cy * cy + cz * cz)

    return closestDist, closestX, closestY, closestZ
end

local function GetDodgeDirection(ux, uz, px, pz, vx, vz)
    -- Perpendicular to projectile velocity in XZ plane
    -- Two options: left or right of trajectory
    local perpX = -vz
    local perpZ = vx

    local len = mathSqrt(perpX * perpX + perpZ * perpZ)
    if len < 0.001 then return 0, 0 end

    perpX = perpX / len
    perpZ = perpZ / len

    -- Choose the direction that moves unit away from the projectile's path
    -- Simple heuristic: use the perpendicular that's on the same side as the unit
    local toUnitX = ux - px
    local toUnitZ = uz - pz

    local dot = toUnitX * perpX + toUnitZ * perpZ
    if dot < 0 then
        perpX = -perpX
        perpZ = -perpZ
    end

    return perpX, perpZ
end

local function ProcessUnit(uid, data, frame)
    -- Check cooldown
    if dodgeCooldowns[uid] and (frame - dodgeCooldowns[uid]) < CFG.cooldownFrames then
        return
    end

    local ux, uy, uz = spGetUnitPosition(uid)
    if not ux then return end

    -- Search for projectiles near this unit
    local pad = CFG.searchPadding
    local projectiles = spGetProjectilesInRectangle(
        ux - pad, uz - pad,
        ux + pad, uz + pad
    )

    if not projectiles or #projectiles == 0 then return end

    local bestThreatDist = math.huge
    local bestDodgeX, bestDodgeZ = 0, 0
    local foundThreat = false

    for _, pID in ipairs(projectiles) do
        -- Skip hitscan weapons
        local pDefID = spGetProjectileDefID(pID)
        if pDefID and not hitscanWeapons[pDefID] then
            local px, py, pz = spGetProjectilePosition(pID)
            local vx, vy, vz = spGetProjectileVelocity(pID)

            if px and vx then
                local closestDist = PredictImpact(px, py, pz, vx, vy, vz, ux, uy, uz)

                if closestDist < (data.radius + CFG.hitRadius) and closestDist < bestThreatDist then
                    bestThreatDist = closestDist
                    local dx, dz = GetDodgeDirection(ux, uz, px, pz, vx, vz)
                    bestDodgeX = dx
                    bestDodgeZ = dz
                    foundThreat = true
                end
            end
        end
    end

    if foundThreat and (bestDodgeX ~= 0 or bestDodgeZ ~= 0) then
        local targetX = ux + bestDodgeX * CFG.dodgeRadius
        local targetZ = uz + bestDodgeZ * CFG.dodgeRadius

        -- Clamp to map bounds
        local mapSizeX = Game.mapSizeX or 8192
        local mapSizeZ = Game.mapSizeZ or 8192
        targetX = mathMax(32, mathMin(targetX, mapSizeX - 32))
        targetZ = mathMax(32, mathMin(targetZ, mapSizeZ - 32))

        local targetY = spGetGroundHeight(targetX, targetZ) or 0

        spGiveOrderToUnit(uid, CMD_MOVE, {targetX, targetY, targetZ}, {})
        dodgeCooldowns[uid] = frame
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Dodge] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[TotallyLegal Dodge] Automation not allowed in this game mode. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildHitscanTable()
    Spring.Echo("[TotallyLegal Dodge] Enabled (PvE mode).")
end

function widget:GameFrame(frame)
    if not TL then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    RefreshManagedUnits()

    for uid, data in pairs(managedUnits) do
        local health = spGetUnitHealth(uid)
        if health and health > 0 then
            ProcessUnit(uid, data, frame)
        end
    end

    -- Cleanup stale cooldowns
    for uid, cd in pairs(dodgeCooldowns) do
        if frame - cd > 300 then
            dodgeCooldowns[uid] = nil
        end
    end
end
