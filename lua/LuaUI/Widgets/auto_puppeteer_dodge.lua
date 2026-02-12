-- Puppeteer Dodge - Formation-aware projectile dodging for mobile units
-- Evolved from auto_totallylegal_dodge.lua with formation awareness:
-- - Units dodge toward formation positions when possible
-- - Units return to formation after dodge cooldown
-- - Suppresses dodge while unit is firing
-- - Validates dodge positions with TestMoveOrder when available
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal), auto_puppeteer_core.lua
--
-- References:
--   Spring.TestMoveOrder(defID, x, y, z) -> bool

function widget:GetInfo()
    return {
        name      = "Puppeteer Dodge",
        desc      = "Formation-aware auto-dodge. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 105,
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
local spTestMoveOrder             = Spring.TestMoveOrder

local CMD_MOVE = CMD.MOVE

local mathSqrt = math.sqrt
local mathMax  = math.max
local mathMin  = math.min
local mathAbs  = math.abs

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local PUP = nil

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
    returnCooldown  = 30,       -- frames after dodge before returning to formation
    maxManagedUnits = 40,       -- performance cap
    searchPadding   = 400,      -- search area around each unit for projectiles
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local dodgeCooldowns = {}    -- unitID -> frame
local dodgedUnits = {}       -- unitID -> { frame, formationPos }

-- Feature detection (set at init)
local hasTestMove = false
local mapSizeX = 0
local mapSizeZ = 0

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
-- Dodge logic (from auto_totallylegal_dodge.lua)
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

    return closestDist, closestX, closestY, closestZ, t
end

local function GetDodgeDirection(ux, uz, px, pz, vx, vz, formationPos)
    -- Perpendicular to projectile velocity in XZ plane
    -- Two options: left or right of trajectory
    local perpX = -vz
    local perpZ = vx

    local len = mathSqrt(perpX * perpX + perpZ * perpZ)
    if len < 0.001 then return 0, 0 end

    perpX = perpX / len
    perpZ = perpZ / len

    -- If unit has a formation position, choose the perpendicular direction
    -- that's closer to the formation position
    if formationPos and formationPos[1] and formationPos[3] then
        local toFormX = formationPos[1] - ux
        local toFormZ = formationPos[3] - uz

        local dotForm = toFormX * perpX + toFormZ * perpZ

        -- If perpendicular is away from formation, flip it
        if dotForm < 0 then
            perpX = -perpX
            perpZ = -perpZ
        end
    else
        -- Original heuristic: choose the direction that moves unit away from the projectile's path
        local toUnitX = ux - px
        local toUnitZ = uz - pz

        local dot = toUnitX * perpX + toUnitZ * perpZ
        if dot < 0 then
            perpX = -perpX
            perpZ = -perpZ
        end
    end

    return perpX, perpZ
end

local function ProcessUnit(uid, data, frame)
    -- Check if unit is firing - suppress dodge to allow firing
    if data.state == "firing" then
        return
    end

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
                local closestDist, _, _, _, impactTime = PredictImpact(px, py, pz, vx, vy, vz, ux, uy, uz)

                -- Skip projectiles arriving in < 3 frames (undodgeable)
                if closestDist < (data.radius + CFG.hitRadius) and impactTime >= 3 and closestDist < bestThreatDist then
                    bestThreatDist = closestDist
                    local dx, dz = GetDodgeDirection(ux, uz, px, pz, vx, vz, data.formationPos)
                    bestDodgeX = dx
                    bestDodgeZ = dz
                    foundThreat = true
                end
            end
        end
    end

    if foundThreat and (bestDodgeX ~= 0 or bestDodgeZ ~= 0) then
        -- Scale dodge distance by unit size
        local dodgeDist = mathMax(CFG.dodgeRadius, data.radius * 1.5)
        local targetX = ux + bestDodgeX * dodgeDist
        local targetZ = uz + bestDodgeZ * dodgeDist

        -- Clamp to map bounds
        targetX = mathMax(32, mathMin(targetX, mapSizeX - 32))
        targetZ = mathMax(32, mathMin(targetZ, mapSizeZ - 32))

        local targetY = spGetGroundHeight(targetX, targetZ) or 0

        -- Validate dodge position is reachable
        if hasTestMove and data.defID then
            local valid = spTestMoveOrder(data.defID, targetX, targetY, targetZ)
            if not valid then
                -- Try flipping dodge direction
                targetX = ux - bestDodgeX * dodgeDist
                targetZ = uz - bestDodgeZ * dodgeDist
                targetX = mathMax(32, mathMin(targetX, mapSizeX - 32))
                targetZ = mathMax(32, mathMin(targetZ, mapSizeZ - 32))
                targetY = spGetGroundHeight(targetX, targetZ) or 0
                valid = spTestMoveOrder(data.defID, targetX, targetY, targetZ)
                if not valid then return end  -- nowhere to dodge
            end
        end

        spGiveOrderToUnit(uid, CMD_MOVE, {targetX, targetY, targetZ}, {})
        dodgeCooldowns[uid] = frame

        -- Track dodge event for formation return
        if data.formationPos then
            dodgedUnits[uid] = {
                frame = frame,
                formationPos = { data.formationPos[1], data.formationPos[2], data.formationPos[3] }
            }
        end
    end
end

local function ProcessDodgedUnits(frame)
    -- Return units to formation after dodge cooldown expires
    for uid, dodgeData in pairs(dodgedUnits) do
        local elapsed = frame - dodgeData.frame

        if elapsed >= CFG.returnCooldown then
            -- Check if unit still exists and has formation position
            local unitData = PUP.units[uid]
            if unitData and unitData.formationPos then
                local ux, uy, uz = spGetUnitPosition(uid)

                if ux then
                    -- Check if unit is under new threat
                    local pad = CFG.searchPadding
                    local projectiles = spGetProjectilesInRectangle(
                        ux - pad, uz - pad,
                        ux + pad, uz + pad
                    )

                    local underThreat = false
                    if projectiles and #projectiles > 0 then
                        -- Quick threat check
                        for _, pID in ipairs(projectiles) do
                            local pDefID = spGetProjectileDefID(pID)
                            if pDefID and not hitscanWeapons[pDefID] then
                                local px, py, pz = spGetProjectilePosition(pID)
                                local vx, vy, vz = spGetProjectileVelocity(pID)

                                if px and vx then
                                    local closestDist = PredictImpact(px, py, pz, vx, vy, vz, ux, uy, uz)
                                    if closestDist < (unitData.radius + CFG.hitRadius) then
                                        underThreat = true
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- If not under threat, return to formation
                    if not underThreat then
                        local formPos = unitData.formationPos
                        spGiveOrderToUnit(uid, CMD_MOVE, {formPos[1], formPos[2], formPos[3]}, {})
                        dodgedUnits[uid] = nil
                    else
                        -- Still under threat, extend cooldown
                        dodgedUnits[uid].frame = frame
                    end
                end
            else
                -- Unit lost or no longer has formation position
                dodgedUnits[uid] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[Puppeteer Dodge] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[Puppeteer Dodge] Automation not allowed in this game mode. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Check if Puppeteer is active (this replaces old dodge widget)
    if not WG.TotallyLegal.PuppeteerActive then
        Spring.Echo("[Puppeteer Dodge] Puppeteer not active. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    mapSizeX = Game.mapSizeX or 8192
    mapSizeZ = Game.mapSizeZ or 8192

    -- Feature detection
    hasTestMove = (spTestMoveOrder ~= nil)

    BuildHitscanTable()
    Spring.Echo("[Puppeteer Dodge] Enabled (formation-aware). TestMoveOrder: " ..
                (hasTestMove and "yes" or "no"))
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    -- Nil-safe Puppeteer reference
    PUP = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
    if not PUP then return end

    -- Check if dodge is enabled
    if not PUP.toggles.dodge then return end

    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        local count = 0

        -- Process active units from Puppeteer registry
        for uid, data in pairs(PUP.units) do
            if count >= CFG.maxManagedUnits then break end

            -- Only dodge units with weapons and sufficient speed
            if data.hasWeapon and data.speed >= CFG.minUnitSpeed then
                local health = spGetUnitHealth(uid)
                if health and health > 0 then
                    ProcessUnit(uid, data, frame)
                    count = count + 1
                end
            end
        end

        -- Process units that dodged and should return to formation
        ProcessDodgedUnits(frame)

        -- Cleanup stale cooldowns
        for uid, cd in pairs(dodgeCooldowns) do
            if frame - cd > 300 then
                dodgeCooldowns[uid] = nil
            end
        end

        -- Cleanup stale dodge tracking
        for uid, dodgeData in pairs(dodgedUnits) do
            if frame - dodgeData.frame > 600 then  -- 20 seconds max
                dodgedUnits[uid] = nil
            end
        end
    end)
    if not ok then
        Spring.Echo("[Puppeteer Dodge] GameFrame error: " .. tostring(err))
    end
end

function widget:Shutdown()
    -- Clean up state
    dodgeCooldowns = {}
    dodgedUnits = {}
end
