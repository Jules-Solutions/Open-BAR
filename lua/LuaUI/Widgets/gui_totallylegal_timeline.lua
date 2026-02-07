-- TotallyLegal Timeline - Economy Graph Widget for Beyond All Reason
-- Tracks M/E income, expenditure, and storage over time. Draws a scrolling line graph.
-- Ranked-safe (read-only). No GiveOrder calls.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Timeline",
        desc      = "Economy timeline graph: M/E income, expenditure, storage over time. Ranked-safe.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 51,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetViewGeometry = Spring.GetViewGeometry
local spGetGameFrame    = Spring.GetGameFrame
local spGetGameSeconds  = Spring.GetGameSeconds

local glColor      = gl.Color
local glRect       = gl.Rect
local glText       = gl.Text
local glLineWidth  = gl.LineWidth
local glBeginEnd   = gl.BeginEnd
local glVertex     = gl.Vertex
local GL_LINE_STRIP = GL.LINE_STRIP
local GL_LINES      = GL.LINES

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
    graphWidth   = 300,
    graphHeight  = 150,
    padding      = 10,
    titleHeight  = 24,
    legendHeight = 20,
    fontSize     = 10,
    titleFontSize = 12,
    maxHistory   = 150,  -- 150 samples * 2s = 5 minutes
    sampleInterval = 2.0,
}

local COL = {
    background    = { 0.05, 0.05, 0.08, 0.85 },
    titleBar      = { 0.10, 0.10, 0.16, 0.95 },
    titleText     = { 0.90, 0.90, 0.95, 1.0 },
    gridLine      = { 0.20, 0.20, 0.25, 0.40 },
    metalIncome   = { 0.40, 0.80, 0.85, 1.0 },
    metalExpend   = { 0.40, 0.80, 0.85, 0.40 },
    energyIncome  = { 1.00, 0.95, 0.35, 1.0 },
    energyExpend  = { 1.00, 0.95, 0.35, 0.40 },
    metalFill     = { 0.40, 0.80, 0.85, 0.10 },
    energyFill    = { 1.00, 0.95, 0.35, 0.10 },
    axisText      = { 0.50, 0.50, 0.55, 0.80 },
    labelText     = { 0.65, 0.65, 0.70, 1.0 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local windowX = 100
local windowY = 100
local windowW = CFG.graphWidth + CFG.padding * 2 + 30  -- extra space for right Y-axis labels
local windowH = CFG.titleHeight + CFG.graphHeight + CFG.legendHeight + CFG.padding * 2
local isDragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local vsx, vsy = 0, 0

-- Ring buffer
local history = {}     -- { metalIncome, metalExpend, energyIncome, energyExpend, gameTime }
local historyHead = 0
local historyCount = 0
local lastSampleTime = 0

--------------------------------------------------------------------------------
-- Ring buffer operations
--------------------------------------------------------------------------------

local function AddSample(mInc, mExp, eInc, eExp, gameTime)
    historyHead = (historyHead % CFG.maxHistory) + 1
    history[historyHead] = {
        mInc = mInc, mExp = mExp,
        eInc = eInc, eExp = eExp,
        t = gameTime,
    }
    if historyCount < CFG.maxHistory then
        historyCount = historyCount + 1
    end
end

local function GetSample(i)
    -- i=1 is oldest, i=historyCount is newest
    local idx = (historyHead - historyCount + i - 1) % CFG.maxHistory + 1
    return history[idx]
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end

local function DrawGraph()
    if historyCount < 2 then return end

    local gx = windowX + CFG.padding
    local gy = windowY + CFG.padding + CFG.legendHeight
    local gw = CFG.graphWidth
    local gh = CFG.graphHeight

    -- Dual Y-axis: separate scales for metal and energy
    local metalMax = 1
    local energyMax = 10
    for i = 1, historyCount do
        local s = GetSample(i)
        if s then
            metalMax = mathMax(metalMax, s.mInc, s.mExp)
            energyMax = mathMax(energyMax, s.eInc, s.eExp)
        end
    end
    metalMax = metalMax * 1.2   -- 20% headroom
    energyMax = energyMax * 1.2

    -- Grid lines (horizontal)
    SetColor(COL.gridLine)
    glLineWidth(1)
    for frac = 0.25, 1.0, 0.25 do
        local ly = gy + gh * frac
        glBeginEnd(GL_LINES, function()
            glVertex(gx, ly, 0)
            glVertex(gx + gw, ly, 0)
        end)
    end

    -- Left Y-axis labels (Metal - cyan)
    SetColor(COL.metalIncome)
    glText("0", gx - 3, gy, CFG.fontSize, "or")
    glText(string.format("%.0f", metalMax / 2), gx - 3, gy + gh * 0.5, CFG.fontSize, "or")
    glText(string.format("%.0f", metalMax), gx - 3, gy + gh, CFG.fontSize, "or")

    -- Right Y-axis labels (Energy - yellow)
    SetColor(COL.energyIncome)
    glText("0", gx + gw + 3, gy, CFG.fontSize, "o")
    glText(string.format("%.0f", energyMax / 2), gx + gw + 3, gy + gh * 0.5, CFG.fontSize, "o")
    glText(string.format("%.0f", energyMax), gx + gw + 3, gy + gh, CFG.fontSize, "o")

    -- Time labels on X-axis
    if historyCount > 0 then
        local newest = GetSample(historyCount)
        local oldest = GetSample(1)
        if newest and oldest then
            SetColor(COL.axisText)
            local function FmtTime(s)
                local m = mathFloor(s / 60)
                local sec = mathFloor(s % 60)
                return string.format("%d:%02d", m, sec)
            end
            glText(FmtTime(oldest.t), gx, gy - 3, CFG.fontSize - 1, "o")
            glText(FmtTime(newest.t), gx + gw, gy - 3, CFG.fontSize - 1, "or")
        end
    end

    -- Draw lines helper (with per-line maxVal for dual axis)
    local function DrawLine(color, field, maxVal)
        SetColor(color)
        glLineWidth(1.5)
        glBeginEnd(GL_LINE_STRIP, function()
            for i = 1, historyCount do
                local s = GetSample(i)
                if s then
                    local x = gx + (i - 1) / (historyCount - 1) * gw
                    local y = gy + (s[field] / maxVal) * gh
                    glVertex(x, y, 0)
                end
            end
        end)
    end

    -- Draw metal lines (scaled to metalMax)
    DrawLine(COL.metalIncome, "mInc", metalMax)
    DrawLine(COL.metalExpend, "mExp", metalMax)

    -- Draw energy lines (scaled to energyMax)
    DrawLine(COL.energyIncome, "eInc", energyMax)
    DrawLine(COL.energyExpend, "eExp", energyMax)
end

local function DrawLegend()
    local lx = windowX + CFG.padding
    local ly = windowY + CFG.padding + 2

    -- Metal
    SetColor(COL.metalIncome)
    glRect(lx, ly, lx + 10, ly + 10)
    SetColor(COL.labelText)
    glText("Metal", lx + 14, ly, CFG.fontSize, "o")

    -- Energy
    local ex = lx + 70
    SetColor(COL.energyIncome)
    glRect(ex, ly, ex + 10, ly + 10)
    SetColor(COL.labelText)
    glText("Energy", ex + 14, ly, CFG.fontSize, "o")

    -- Solid = income, dashed = expenditure
    SetColor(COL.axisText)
    glText("solid=income  dim=spend", lx + 150, ly, CFG.fontSize - 1, "o")
end

function widget:DrawScreen()
    if not TL then return end
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Timeline == false then return end
    if historyCount < 1 then return end

    -- Background
    SetColor(COL.background)
    glRect(windowX, windowY, windowX + windowW, windowY + windowH)

    -- Title bar
    SetColor(COL.titleBar)
    glRect(windowX, windowY + windowH - CFG.titleHeight, windowX + windowW, windowY + windowH)

    SetColor(COL.titleText)
    glText("Economy Timeline", windowX + CFG.padding, windowY + windowH - CFG.titleHeight + 6, CFG.titleFontSize, "oB")

    DrawGraph()
    DrawLegend()
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:IsAbove(x, y)
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Timeline == false then return false end
    return x >= windowX and x <= windowX + windowW
       and y >= windowY and y <= windowY + windowH
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    if not self:IsAbove(x, y) then return false end

    -- Drag from any surface (no interactive elements in this widget)
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
    if isDragging then
        isDragging = false
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()

    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Timeline] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    windowX = vsx - windowW - 20
    windowY = 50
end

function widget:Update(dt)
    if not TL then return end

    local now = osClock()
    if now - lastSampleTime < CFG.sampleInterval then return end
    lastSampleTime = now

    local gameTime = spGetGameSeconds and spGetGameSeconds() or (spGetGameFrame() / 30)
    if gameTime <= 0 then return end

    local res = TL.GetTeamResources()
    AddSample(res.metalIncome, res.metalExpend, res.energyIncome, res.energyExpend, gameTime)
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
