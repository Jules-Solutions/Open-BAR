-- TotallyLegal Threat Estimator - Enemy Capability Prediction for Beyond All Reason
-- Tracks scouted enemy units and estimates capabilities based on time + observations.
-- Ranked-safe (read-only). No GiveOrder calls.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Threat",
        desc      = "Threat estimator: predicts enemy capabilities from scouting + elapsed time. Ranked-safe.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 52,
        enabled   = false,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetMyAllyTeamID   = Spring.GetMyAllyTeamID
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitTeam       = Spring.GetUnitTeam
local spGetViewGeometry   = Spring.GetViewGeometry
local spGetGameFrame      = Spring.GetGameFrame
local spIsUnitAllied      = Spring.IsUnitAllied

local glColor    = gl.Color
local glRect     = gl.Rect
local glText     = gl.Text

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local osClock   = os.clock

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    windowWidth   = 280,
    titleHeight   = 24,
    rowHeight     = 16,
    sectionHeight = 20,
    padding       = 8,
    fontSize      = 10,
    titleFontSize = 12,
    updateInterval = 2.0,
}

local COL = {
    background = { 0.05, 0.05, 0.08, 0.85 },
    titleBar   = { 0.10, 0.10, 0.16, 0.95 },
    titleText  = { 0.90, 0.90, 0.95, 1.0 },
    headerText = { 0.70, 0.80, 0.90, 1.0 },
    labelText  = { 0.65, 0.65, 0.70, 1.0 },
    countText  = { 0.50, 0.55, 0.60, 1.0 },
    riskLow    = { 0.30, 0.75, 0.30, 1.0 },
    riskMed    = { 0.90, 0.80, 0.20, 1.0 },
    riskHigh   = { 0.90, 0.50, 0.20, 1.0 },
    riskCrit   = { 1.00, 0.30, 0.30, 1.0 },
    separator  = { 0.30, 0.30, 0.40, 0.30 },
}

-- Time estimates (in seconds from seeing trigger)
local THREAT_DEFS = {
    { trigger = "t2_factory",  name = "T2 Units",         delay = 0,    confidence = "confirmed" },
    { trigger = "t2_factory",  name = "Nuke Silo",        delay = 90,   confidence = "possible" },
    { trigger = "t2_factory",  name = "Nuke Ready",       delay = 270,  confidence = "estimated" },
    { trigger = "t2_factory",  name = "T3 Possible",      delay = 180,  confidence = "possible" },
    { trigger = "t2_factory",  name = "Superweapons",     delay = 360,  confidence = "possible" },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local windowX = 100
local windowY = 200
local windowW = CFG.windowWidth
local windowH = 200
local isDragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local vsx, vsy = 0, 0

local knownEnemyUnits = {}  -- defID -> { count, firstSeen (frame), lastSeen (frame), name }
local enemyFactories = {}   -- defID -> count
local estimatedBP = 0
local firstT2SeenFrame = nil
local highestTechSeen = 1
local threats = {}          -- { name, eta (seconds from now), riskLevel, confidence }
local lastUpdateTime = 0
local totalEnemySeen = 0

--------------------------------------------------------------------------------
-- Enemy tracking
--------------------------------------------------------------------------------

local function ProcessEnemyUnit(unitID, unitDefID)
    if not unitDefID then return end
    local def = UnitDefs[unitDefID]
    if not def then return end

    local frame = spGetGameFrame()
    local cp = def.customParams or {}
    local tl = tonumber(cp.techlevel) or 1

    if not knownEnemyUnits[unitDefID] then
        knownEnemyUnits[unitDefID] = {
            count = 0,
            firstSeen = frame,
            lastSeen = frame,
            name = def.humanName or def.name or "Unknown",
            techLevel = tl,
            isFactory = def.isFactory or false,
            buildSpeed = def.buildSpeed or 0,
            metalCost = def.metalCost or 0,
        }
    end

    local entry = knownEnemyUnits[unitDefID]
    entry.count = entry.count + 1
    entry.lastSeen = frame
    totalEnemySeen = totalEnemySeen + 1

    if tl > highestTechSeen then
        highestTechSeen = tl
    end

    if tl >= 2 and not firstT2SeenFrame then
        firstT2SeenFrame = frame
    end

    if def.isFactory then
        enemyFactories[unitDefID] = (enemyFactories[unitDefID] or 0) + 1
        estimatedBP = estimatedBP + (def.buildSpeed or 0)
    end
end

--------------------------------------------------------------------------------
-- Threat assessment
--------------------------------------------------------------------------------

local function UpdateThreats()
    threats = {}
    local frame = spGetGameFrame()
    local gameSeconds = frame / 30

    -- Time-based general threats (no scouting needed)
    if gameSeconds > 120 then
        threats[#threats + 1] = { name = "T1 Units", eta = 0, riskLevel = "confirmed", confidence = "certain" }
    end

    if gameSeconds > 300 and highestTechSeen < 2 then
        threats[#threats + 1] = { name = "T2 Possible (unscouted)", eta = 0, riskLevel = "medium", confidence = "estimated" }
    end

    -- Scouting-based threats
    if firstT2SeenFrame then
        local secSinceT2 = (frame - firstT2SeenFrame) / 30

        for _, td in ipairs(THREAT_DEFS) do
            if td.trigger == "t2_factory" then
                local timeLeft = td.delay - secSinceT2
                local riskLevel
                if timeLeft <= 0 then
                    riskLevel = "critical"
                elseif timeLeft < 30 then
                    riskLevel = "high"
                elseif timeLeft < 90 then
                    riskLevel = "medium"
                else
                    riskLevel = "low"
                end

                threats[#threats + 1] = {
                    name = td.name,
                    eta = mathMax(0, timeLeft),
                    riskLevel = riskLevel,
                    confidence = td.confidence,
                }
            end
        end
    end

    -- Sort: critical first, then by ETA
    table.sort(threats, function(a, b)
        local order = { critical = 0, high = 1, medium = 2, low = 3, confirmed = 0 }
        local oa = order[a.riskLevel] or 4
        local ob = order[b.riskLevel] or 4
        if oa ~= ob then return oa < ob end
        return a.eta < b.eta
    end)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end

local function GetRiskColor(level)
    if level == "critical" or level == "confirmed" then return COL.riskCrit
    elseif level == "high" then return COL.riskHigh
    elseif level == "medium" then return COL.riskMed
    else return COL.riskLow end
end

local function FormatETA(seconds)
    if seconds <= 0 then return "NOW" end
    local m = mathFloor(seconds / 60)
    local s = mathFloor(seconds % 60)
    if m > 0 then
        return string.format("%dm%02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

function widget:DrawScreen()
    if not TL then return end
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Threat == false then return end

    -- Calculate dynamic height
    local rows = 0
    rows = rows + 1  -- "Known Enemy Units" header
    local shownUnits = 0
    for _, entry in pairs(knownEnemyUnits) do
        if entry.count > 0 then shownUnits = shownUnits + 1 end
    end
    rows = rows + mathMin(shownUnits, 8)  -- cap at 8 unit types
    rows = rows + 1  -- separator
    rows = rows + 1  -- "Threat Assessment" header
    rows = rows + #threats

    windowH = CFG.titleHeight + CFG.padding * 2 + rows * CFG.rowHeight + CFG.sectionHeight

    -- Background
    SetColor(COL.background)
    glRect(windowX, windowY, windowX + windowW, windowY + windowH)

    -- Title bar
    SetColor(COL.titleBar)
    glRect(windowX, windowY + windowH - CFG.titleHeight, windowX + windowW, windowY + windowH)
    SetColor(COL.titleText)
    glText("Threat Estimator", windowX + CFG.padding, windowY + windowH - CFG.titleHeight + 6, CFG.titleFontSize, "oB")

    -- Tech level indicator
    local techStr = "Tech: T" .. highestTechSeen
    SetColor(highestTechSeen >= 2 and COL.riskHigh or COL.riskLow)
    glText(techStr, windowX + windowW - CFG.padding, windowY + windowH - CFG.titleHeight + 6, CFG.fontSize, "or")

    local x = windowX + CFG.padding
    local rEdge = windowX + windowW - CFG.padding
    local y = windowY + windowH - CFG.titleHeight - CFG.padding

    -- Known Enemy Units section
    SetColor(COL.headerText)
    y = y - CFG.sectionHeight
    glText("Known Enemy Units (" .. totalEnemySeen .. " spotted)", x, y + 4, CFG.fontSize + 1, "oB")

    -- Sort units by metal cost (most expensive first)
    local sortedUnits = {}
    for defID, entry in pairs(knownEnemyUnits) do
        if entry.count > 0 then
            sortedUnits[#sortedUnits + 1] = { defID = defID, entry = entry }
        end
    end
    table.sort(sortedUnits, function(a, b) return a.entry.metalCost > b.entry.metalCost end)

    local shown = 0
    for _, item in ipairs(sortedUnits) do
        if shown >= 8 then break end
        y = y - CFG.rowHeight
        shown = shown + 1

        local entry = item.entry
        local techColor = entry.techLevel >= 2 and COL.riskHigh or COL.labelText
        SetColor(techColor)
        glText(entry.name, x + 4, y + 2, CFG.fontSize, "o")

        SetColor(COL.countText)
        glText("x" .. entry.count, rEdge - 50, y + 2, CFG.fontSize, "o")

        SetColor(COL.labelText)
        local cost = TL.FormatInt(entry.metalCost * entry.count)
        glText(cost .. "M", rEdge, y + 2, CFG.fontSize, "or")
    end

    -- Separator
    y = y - 4
    SetColor(COL.separator)
    glRect(windowX + 5, y, windowX + windowW - 5, y + 1)
    y = y - 4

    -- Threat Assessment section
    SetColor(COL.headerText)
    y = y - CFG.sectionHeight
    glText("Threat Assessment", x, y + 4, CFG.fontSize + 1, "oB")

    if #threats == 0 then
        y = y - CFG.rowHeight
        SetColor(COL.labelText)
        glText("No threats detected yet", x + 4, y + 2, CFG.fontSize, "o")
    else
        for _, threat in ipairs(threats) do
            y = y - CFG.rowHeight

            SetColor(GetRiskColor(threat.riskLevel))
            local indicator = threat.riskLevel == "critical" and "!!" or
                             threat.riskLevel == "high" and "!" or
                             threat.riskLevel == "medium" and "~" or " "
            glText(indicator, x, y + 2, CFG.fontSize, "o")
            glText(threat.name, x + 14, y + 2, CFG.fontSize, "o")

            -- ETA
            local etaStr = FormatETA(threat.eta)
            SetColor(GetRiskColor(threat.riskLevel))
            glText(etaStr, rEdge, y + 2, CFG.fontSize, "or")
        end
    end
end

--------------------------------------------------------------------------------
-- Unit scouting callins
--------------------------------------------------------------------------------

function widget:UnitEnteredLos(unitID, unitTeam)
    if spIsUnitAllied(unitID) then return end
    local defID = spGetUnitDefID(unitID)
    if defID then
        ProcessEnemyUnit(unitID, defID)
    end
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:IsAbove(x, y)
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Threat == false then return false end
    return x >= windowX and x <= windowX + windowW
       and y >= windowY and y <= windowY + windowH
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    if not self:IsAbove(x, y) then return false end

    -- No interactive elements in this widget — drag from any surface
    isDragging = true
    dragOffsetX = x - windowX
    dragOffsetY = y - windowY
    return true
end

function widget:MouseMove(x, y, dx, dy, button)
    if isDragging then
        windowX = x - dragOffsetX
        windowY = y - dragOffsetY
        windowX = mathMax(0, mathMin(windowX, vsx - windowW))
        windowY = mathMax(0, mathMin(windowY, vsy - windowH))
        return true
    end
    return false
end

function widget:MouseRelease(x, y, button)
    if isDragging then isDragging = false return true end
    return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()

    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Threat] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal
    -- Position beside sidebar, below overlay
    windowX = vsx - windowW - 60
    windowY = vsy - 100 - 400 - 220  -- below overlay
end

function widget:Update(dt)
    if not TL then return end
    local now = osClock()
    if now - lastUpdateTime < CFG.updateInterval then return end
    lastUpdateTime = now
    UpdateThreats()
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    windowX = mathMax(0, mathMin(windowX, vsx - windowW))
    windowY = mathMax(0, mathMin(windowY, vsy - windowH))
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return { windowX = windowX, windowY = windowY }
end

function widget:SetConfigData(data)
    if data.windowX then windowX = data.windowX end
    if data.windowY then windowY = data.windowY end
end
