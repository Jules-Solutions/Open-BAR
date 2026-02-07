-- TotallyLegal Priority Highlights - World-space visual priority indicators
-- Draws glowing circles around high-priority targets: idle factories, idle builders, attacked structures, enemy commanders.
-- Ranked-safe (read-only). No GiveOrder calls.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Priority",
        desc      = "Priority highlights: glowing circles on idle factories, idle builders, attacked structures. Ranked-safe.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 53,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetUnitIsBuilding = Spring.GetUnitIsBuilding
local spGetUnitCommands   = Spring.GetUnitCommands
local spGetGameFrame      = Spring.GetGameFrame
local spIsUnitAllied      = Spring.IsUnitAllied

local glColor             = gl.Color
local glLineWidth         = gl.LineWidth
local glDrawGroundCircle  = gl.DrawGroundCircle

local mathSin   = math.sin
local mathMax   = math.max
local osClock   = os.clock

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    updateInterval   = 1.0,
    circleSegments   = 32,
    lineWidth        = 2.5,
    -- Radii
    factoryRadius    = 80,
    builderRadius    = 50,
    attackedRadius   = 90,
    commanderRadius  = 120,
    -- Thresholds
    healthThreshold  = 0.7,  -- show "under attack" below 70% health
    idleBPThreshold  = 50,   -- only highlight builders with >= 50 BP
    -- Toggle flags
    showIdleFactories  = true,
    showIdleBuilders   = true,
    showAttacked       = true,
    showEnemyCommanders = true,
}

local COL = {
    idleFactory  = { 1.0, 0.3, 0.3 },   -- red
    idleBuilder  = { 0.9, 0.9, 0.2 },    -- yellow
    attacked     = { 1.0, 0.2, 0.2 },    -- bright red
    commander    = { 0.7, 0.3, 0.9 },    -- purple
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local highlights = {}   -- { x, z, radius, color, pulseSpeed }
local lastUpdateTime = 0
local recentlyAttacked = {}  -- unitID -> frame (tracks units taking damage)

--------------------------------------------------------------------------------
-- Damage tracking
--------------------------------------------------------------------------------

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer)
    if unitTeam == spGetMyTeamID() then
        recentlyAttacked[unitID] = spGetGameFrame()
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    recentlyAttacked[unitID] = nil
end

--------------------------------------------------------------------------------
-- Priority calculation
--------------------------------------------------------------------------------

local function UpdateHighlights()
    highlights = {}
    if not TL then return end

    local myUnits = TL.GetMyUnits()
    local frame = spGetGameFrame()

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if not cls then goto continue end

        local x, y, z = spGetUnitPosition(uid)
        if not x then goto continue end

        -- Idle factories
        if CFG.showIdleFactories and cls.isFactory then
            local building = spGetUnitIsBuilding(uid)
            local cmdCount = spGetUnitCommands(uid, 0)
            if not building and (cmdCount or 0) == 0 then
                highlights[#highlights + 1] = {
                    x = x, z = z,
                    radius = CFG.factoryRadius,
                    color = COL.idleFactory,
                    pulseSpeed = 2.0,
                }
            end
        end

        -- Idle high-BP builders (not factories)
        if CFG.showIdleBuilders and cls.isBuilder and not cls.isFactory and cls.buildSpeed >= CFG.idleBPThreshold then
            local building = spGetUnitIsBuilding(uid)
            local cmdCount = spGetUnitCommands(uid, 0)
            if not building and (cmdCount or 0) == 0 then
                highlights[#highlights + 1] = {
                    x = x, z = z,
                    radius = CFG.builderRadius,
                    color = COL.idleBuilder,
                    pulseSpeed = 3.0,
                }
            end
        end

        -- Recently attacked structures
        if CFG.showAttacked and cls.isBuilding then
            local attackFrame = recentlyAttacked[uid]
            if attackFrame and (frame - attackFrame) < 150 then  -- 5 seconds
                local health, maxHealth = spGetUnitHealth(uid)
                if health and maxHealth and maxHealth > 0 then
                    if (health / maxHealth) < CFG.healthThreshold then
                        highlights[#highlights + 1] = {
                            x = x, z = z,
                            radius = CFG.attackedRadius,
                            color = COL.attacked,
                            pulseSpeed = 5.0,  -- fast pulse for urgency
                        }
                    end
                end
            end
        end

        ::continue::
    end

    -- Cleanup old damage records (older than 10 seconds)
    for uid, attackFrame in pairs(recentlyAttacked) do
        if (frame - attackFrame) > 300 then
            recentlyAttacked[uid] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

function widget:DrawWorld()
    if not TL then return end
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Priority == false then return end
    if #highlights == 0 then return end

    local now = osClock()

    for _, h in ipairs(highlights) do
        local alpha = 0.3 + 0.4 * (0.5 + 0.5 * mathSin(now * h.pulseSpeed * math.pi))
        glColor(h.color[1], h.color[2], h.color[3], alpha)
        glLineWidth(CFG.lineWidth)
        glDrawGroundCircle(h.x, 0, h.z, h.radius, CFG.circleSegments)

        -- Inner ring (smaller, brighter)
        glColor(h.color[1], h.color[2], h.color[3], alpha * 0.5)
        glDrawGroundCircle(h.x, 0, h.z, h.radius * 0.6, CFG.circleSegments)
    end

    glColor(1, 1, 1, 1)  -- reset
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Priority] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end
    TL = WG.TotallyLegal
end

function widget:Update(dt)
    if not TL then return end
    local now = osClock()
    if now - lastUpdateTime < CFG.updateInterval then return end
    lastUpdateTime = now
    UpdateHighlights()
end
