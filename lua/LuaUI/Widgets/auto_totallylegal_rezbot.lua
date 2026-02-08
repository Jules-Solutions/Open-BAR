-- TotallyLegal Auto Rezbot - Automated resurrection and reclaim management
-- Idle resurrection bots autonomously find and prioritize resurrect/reclaim targets.
-- PvE/Unranked ONLY. Uses GiveOrderToUnit. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Auto Rezbot",
        desc      = "Auto-manage resurrection bots: prioritize resurrect > reclaim. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 101,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetUnitHealth       = Spring.GetUnitHealth
local spGetAllFeatures      = Spring.GetAllFeatures
local spGetFeaturePosition  = Spring.GetFeaturePosition
local spGetFeatureDefID     = Spring.GetFeatureDefID
local spGetGameFrame        = Spring.GetGameFrame
local spGiveOrderToUnit     = Spring.GiveOrderToUnit

local CMD_RESURRECT = CMD.RESURRECT
local CMD_RECLAIM   = CMD.RECLAIM

local mathSqrt = math.sqrt
local mathMax  = math.max

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateFrequency  = 30,       -- every N game frames (1 second)
    maxSearchRadius  = 3000,     -- max distance from base center to search
    reclaimTrees     = false,    -- auto-reclaim trees (can be toggled)
    priorityResurrect = 10.0,    -- weight multiplier for resurrectables
    priorityReclaim   = 1.0,     -- weight multiplier for reclaimables
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local assignments = {}   -- rezbotUID -> featureID (currently assigned target)
local assignedFeatures = {} -- featureID -> rezbotUID (reverse lookup)
local botCooldowns = {}  -- rezbotUID -> frame when last assigned (Bug #25)
local baseCenterX = 0
local baseCenterZ = 0
local baseCenterSet = false

--------------------------------------------------------------------------------
-- Rezbot identification
--------------------------------------------------------------------------------

local rezbotDefIDs = {}  -- set of defIDs that can resurrect

local function BuildRezbotTable()
    rezbotDefIDs = {}
    for defID, def in pairs(UnitDefs) do
        if def.canResurrect then
            rezbotDefIDs[defID] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Feature scoring
--------------------------------------------------------------------------------

local function ScoreFeature(fID, fDefID, fx, fz, isResurrectable)
    local fDef = FeatureDefs[fDefID]
    if not fDef then return 0 end

    local metal = fDef.metal or 0
    local energy = fDef.energy or 0

    -- Skip features with no value
    if metal <= 0 and energy <= 0 then
        -- Could be a tree
        if not CFG.reclaimTrees then return 0 end
        return 0.1  -- minimal priority for trees
    end

    local score = metal + energy * 0.1

    if isResurrectable then
        score = score * CFG.priorityResurrect
    else
        score = score * CFG.priorityReclaim
    end

    -- Distance penalty from base center
    if baseCenterSet then
        local dx = fx - baseCenterX
        local dz = fz - baseCenterZ
        local dist = mathSqrt(dx * dx + dz * dz)
        if dist > CFG.maxSearchRadius then
            return 0  -- too far
        end
        score = score / mathMax(1, dist / 500)
    end

    return score
end

--------------------------------------------------------------------------------
-- Assignment logic
--------------------------------------------------------------------------------

local function FindIdleRezbots()
    local idle = {}
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        if rezbotDefIDs[defID] then
            local cmdCount = spGetUnitCommands(uid, 0)
            if cmdCount == 0 then
                idle[#idle + 1] = uid
            end
        end
    end

    return idle
end

local function UpdateBaseCenter()
    if baseCenterSet then return end
    local myUnits = TL.GetMyUnits()

    -- Use first builder/commander position as base center
    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.isBuilder then
            local x, y, z = spGetUnitPosition(uid)
            if x then
                baseCenterX = x
                baseCenterZ = z
                baseCenterSet = true
                return
            end
        end
    end
end

local function AssignRezbots(frame)
    local idleBots = FindIdleRezbots()
    if #idleBots == 0 then return end

    -- Cleanup stale assignments (dead bots)
    for uid, fID in pairs(assignments) do
        local health = spGetUnitHealth(uid)
        if not health or health <= 0 then
            if assignedFeatures[fID] == uid then
                assignedFeatures[fID] = nil
            end
            assignments[uid] = nil
            botCooldowns[uid] = nil
        end
    end

    -- Bug #25: clean stale feature assignments (feature no longer exists)
    for fID, botUID in pairs(assignedFeatures) do
        local fDefID = spGetFeatureDefID(fID)
        if not fDefID then
            assignedFeatures[fID] = nil
            if assignments[botUID] == fID then
                assignments[botUID] = nil
            end
        end
    end

    -- Get all features
    local features = spGetAllFeatures()
    if not features or #features == 0 then return end

    -- Score and sort features
    local scoredFeatures = {}
    for _, fID in ipairs(features) do
        if not assignedFeatures[fID] then  -- skip already assigned
            local fDefID = spGetFeatureDefID(fID)
            if fDefID then
                local fx, fy, fz = spGetFeaturePosition(fID)
                if fx then
                    local fDef = FeatureDefs[fDefID]
                    local isResurrectable = fDef and fDef.resurrectable or false

                    local score = ScoreFeature(fID, fDefID, fx, fz, isResurrectable)
                    if score > 0 then
                        scoredFeatures[#scoredFeatures + 1] = {
                            fID = fID,
                            fDefID = fDefID,
                            x = fx, z = fz,
                            score = score,
                            resurrect = isResurrectable,
                        }
                    end
                end
            end
        end
    end

    if #scoredFeatures == 0 then return end

    -- Sort by score descending
    table.sort(scoredFeatures, function(a, b) return a.score > b.score end)

    -- Assign each idle bot to nearest high-priority feature
    for _, botUID in ipairs(idleBots) do
        -- Bug #25: per-bot cooldown to prevent spam-reassignment
        if botCooldowns[botUID] and (frame - botCooldowns[botUID]) < CFG.updateFrequency * 3 then
            goto nextBot
        end

        local bx, by, bz = spGetUnitPosition(botUID)
        if not bx then goto nextBot end

        local bestFeature = nil
        local bestScore = 0

        for _, sf in ipairs(scoredFeatures) do
            if not assignedFeatures[sf.fID] then
                -- Factor in distance to this specific bot
                local dx = sf.x - bx
                local dz = sf.z - bz
                local dist = mathSqrt(dx * dx + dz * dz)
                local adjustedScore = sf.score / mathMax(1, dist / 300)

                if adjustedScore > bestScore then
                    bestScore = adjustedScore
                    bestFeature = sf
                end
            end
        end

        if bestFeature then
            local cmdID = bestFeature.resurrect and CMD_RESURRECT or CMD_RECLAIM
            -- Feature IDs need Game.maxUnits offset for commands
            local maxUnits = Game.maxUnits or 32000
            spGiveOrderToUnit(botUID, cmdID, {bestFeature.fID + maxUnits}, {})

            assignments[botUID] = bestFeature.fID
            assignedFeatures[bestFeature.fID] = botUID
            botCooldowns[botUID] = frame
        end

        ::nextBot::
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Rezbot] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        Spring.Echo("[TotallyLegal Rezbot] Automation not allowed in this game mode. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    BuildRezbotTable()
    Spring.Echo("[TotallyLegal Rezbot] Enabled (PvE mode).")
end

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end
    if frame % CFG.updateFrequency ~= 0 then return end

    local ok, err = pcall(function()
        UpdateBaseCenter()
        AssignRezbots(frame)
    end)
    if not ok then
        Spring.Echo("[TotallyLegal Rezbot] GameFrame error: " .. tostring(err))
    end
end
