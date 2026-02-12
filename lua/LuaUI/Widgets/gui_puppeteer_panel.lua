-- Puppeteer Control Panel - Toggle controls, formation picker, config sliders
-- Floating, draggable, collapsible panel for configuring all Puppeteer features.
-- Ranked-safe (read-only display + toggle state changes). No GiveOrder calls.
-- Requires: auto_puppeteer_core.lua (WG.TotallyLegal.Puppeteer)

function widget:GetInfo()
    return {
        name      = "Puppeteer Panel",
        desc      = "Control panel for Unit Puppeteer. Toggle features, pick formations, adjust settings.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 100,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetViewGeometry = Spring.GetViewGeometry
local spGetGameFrame    = Spring.GetGameFrame
local spEcho            = Spring.Echo

local glColor     = gl.Color
local glRect      = gl.Rect
local glText      = gl.Text
local glLineWidth = gl.LineWidth
local glBeginEnd  = gl.BeginEnd
local glVertex    = gl.Vertex
local GL_LINES    = GL.LINES
local GL_LINE_LOOP = GL.LINE_LOOP

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL  = nil
local PUP = nil   -- WG.TotallyLegal.Puppeteer

--------------------------------------------------------------------------------
-- Layout configuration
--------------------------------------------------------------------------------

local PANEL = {
    width         = 260,
    titleHeight   = 22,
    padding       = 8,
    rowHeight     = 22,
    toggleBtnW    = 32,
    toggleBtnH    = 16,
    shapeBtnSize  = 24,
    numBtnW       = 20,
    numBtnH       = 16,
    sectionGap    = 6,
    fontSize      = 11,
    titleFontSize = 12,
    statusFontSize = 10,
}

local COL = {
    panelBg       = { 0.05, 0.05, 0.08, 0.92 },
    panelBorder   = { 0.20, 0.25, 0.40, 0.80 },
    titleBg       = { 0.08, 0.12, 0.22, 0.95 },
    titleText     = { 0.70, 0.85, 1.00, 1.00 },
    labelText     = { 0.80, 0.82, 0.88, 1.00 },
    valueText     = { 0.95, 0.95, 1.00, 1.00 },
    statusText    = { 0.55, 0.58, 0.65, 1.00 },
    -- Toggle buttons
    toggleOn      = { 0.20, 0.55, 0.30, 0.90 },
    toggleOnText  = { 0.90, 1.00, 0.90, 1.00 },
    toggleOff     = { 0.15, 0.15, 0.20, 0.80 },
    toggleOffText = { 0.50, 0.50, 0.55, 0.80 },
    toggleHover   = { 0.25, 0.25, 0.35, 0.90 },
    -- Shape buttons
    shapeActive   = { 0.25, 0.45, 0.70, 0.90 },
    shapeInactive = { 0.12, 0.12, 0.18, 0.80 },
    shapeHover    = { 0.20, 0.30, 0.50, 0.90 },
    shapeText     = { 0.90, 0.95, 1.00, 1.00 },
    shapeDimText  = { 0.50, 0.55, 0.65, 0.80 },
    -- +/- buttons
    numBtnBg      = { 0.12, 0.12, 0.18, 0.80 },
    numBtnHover   = { 0.20, 0.25, 0.35, 0.90 },
    numBtnText    = { 0.80, 0.85, 0.95, 1.00 },
    -- Separator
    separator     = { 0.25, 0.28, 0.38, 0.50 },
    -- Minimize/close
    ctrlBtnBg     = { 0.15, 0.15, 0.22, 0.80 },
    ctrlBtnHover  = { 0.30, 0.20, 0.20, 0.90 },
    ctrlBtnText   = { 0.70, 0.70, 0.80, 1.00 },
    -- Master toggle
    masterOn      = { 0.15, 0.50, 0.65, 0.90 },
    masterOff     = { 0.40, 0.15, 0.15, 0.90 },
}

-- Toggle definitions: { key, label }
local BOOL_TOGGLES = {
    { key = "smartMove",  label = "Smart Move" },
    { key = "dodge",      label = "Dodge" },
    { key = "formations", label = "Formations" },
    { key = "roleSort",   label = "Role Sort" },
    { key = "firingLine", label = "Firing Line" },
    { key = "scatter",    label = "Scatter" },
    { key = "march",      label = "March" },
    { key = "rangeWalk",  label = "Range Walk" },
    { key = "rangeKeep",  label = "Range Keep" },
}

-- Shape icons
local SHAPE_ICONS = { "\xe2\x80\x94", "O", "C", "[ ]", "*" }  -- line, circle, half_circle, square, star
local SHAPE_LABELS = { "Line", "Circle", "Half-C", "Square", "Star" }

-- Numeric controls: { key, label, min, max, step }
local NUM_CONTROLS = {
    { key = "formationNesting", label = "Nesting",   min = 1, max = 5, step = 1 },
    { key = "firingLineWidth",  label = "Line Width", min = 1, max = 5, step = 1 },
    { key = "scatterDistance",  label = "Scatter",    min = 40, max = 300, step = 20 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local vsx, vsy = 0, 0
local panelX, panelY = 200, 400    -- bottom-left corner of panel
local panelH = 0                    -- calculated
local panelVisible = true
local panelCollapsed = false
local positionRestored = false      -- flag to prevent overwriting restored position
local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0
local hoveredElement = nil          -- string key or nil

-- Clickable regions: key -> { x1, y1, x2, y2 }
local hitRects = {}

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end
local function FillRect(x1, y1, x2, y2) glRect(x1, y1, x2, y2) end

local function DrawOutlineRect(x1, y1, x2, y2)
    glBeginEnd(GL_LINE_LOOP, function()
        glVertex(x1, y1, 0)
        glVertex(x2, y1, 0)
        glVertex(x2, y2, 0)
        glVertex(x1, y2, 0)
    end)
end

local function DrawSeparator(x1, x2, y)
    SetColor(COL.separator)
    glLineWidth(1)
    glBeginEnd(GL_LINES, function()
        glVertex(x1, y, 0)
        glVertex(x2, y, 0)
    end)
end

local function RegisterHit(key, x1, y1, x2, y2)
    hitRects[key] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

--------------------------------------------------------------------------------
-- Layout and rendering
--------------------------------------------------------------------------------

local function CalculateAndDraw()
    if not PUP then return end

    hitRects = {}
    local P = PANEL
    local x = panelX
    local w = P.width
    local pad = P.padding
    local rh = P.rowHeight

    -- Calculate total height first (for positioning from bottom-left)
    local contentH = 0
    -- Title bar
    contentH = contentH + P.titleHeight
    -- Master toggle row
    contentH = contentH + rh + pad
    -- Separator
    contentH = contentH + P.sectionGap
    -- Toggle rows (4 rows of 2 toggles each)
    local toggleRows = math.ceil(#BOOL_TOGGLES / 2)
    contentH = contentH + toggleRows * rh
    -- Separator
    contentH = contentH + P.sectionGap
    -- Shape selector row
    contentH = contentH + P.shapeBtnSize + 4
    -- Separator
    contentH = contentH + P.sectionGap
    -- Numeric controls
    contentH = contentH + #NUM_CONTROLS * rh
    -- Separator
    contentH = contentH + P.sectionGap
    -- Status line
    contentH = contentH + rh
    -- Bottom padding
    contentH = contentH + pad

    panelH = contentH

    local y = panelY + panelH   -- start drawing from top

    -- Panel background
    SetColor(COL.panelBorder)
    FillRect(x - 1, panelY - 1, x + w + 1, panelY + panelH + 1)
    SetColor(COL.panelBg)
    FillRect(x, panelY, x + w, panelY + panelH)

    -------------------------------------------------------
    -- Title bar
    -------------------------------------------------------
    y = y - P.titleHeight
    SetColor(COL.titleBg)
    FillRect(x, y, x + w, y + P.titleHeight)
    RegisterHit("title", x, y, x + w, y + P.titleHeight)

    -- Title text
    SetColor(COL.titleText)
    glText("Puppeteer", x + pad, y + 4, P.titleFontSize, "o")

    -- Minimize button
    local minBtnX = x + w - 40
    local minBtnW = 18
    local minBtnY = y + 3
    local minBtnH = P.titleHeight - 6
    SetColor(hoveredElement == "minimize" and COL.ctrlBtnHover or COL.ctrlBtnBg)
    FillRect(minBtnX, minBtnY, minBtnX + minBtnW, minBtnY + minBtnH)
    SetColor(COL.ctrlBtnText)
    glText("_", minBtnX + minBtnW / 2, minBtnY + 1, 10, "ocB")
    RegisterHit("minimize", minBtnX, minBtnY, minBtnX + minBtnW, minBtnY + minBtnH)

    -- Close button
    local clsBtnX = x + w - 20
    SetColor(hoveredElement == "close" and COL.ctrlBtnHover or COL.ctrlBtnBg)
    FillRect(clsBtnX, minBtnY, clsBtnX + minBtnW, minBtnY + minBtnH)
    SetColor(COL.ctrlBtnText)
    glText("X", clsBtnX + minBtnW / 2, minBtnY + 1, 10, "ocB")
    RegisterHit("close", clsBtnX, minBtnY, clsBtnX + minBtnW, minBtnY + minBtnH)

    if panelCollapsed then return end

    -------------------------------------------------------
    -- Master toggle
    -------------------------------------------------------
    y = y - rh - pad / 2
    local masterOn = PUP.active
    local masterBtnX = x + pad
    local masterBtnW = w - pad * 2
    local masterBtnH = P.toggleBtnH + 2
    SetColor(hoveredElement == "master" and COL.toggleHover or (masterOn and COL.masterOn or COL.masterOff))
    FillRect(masterBtnX, y, masterBtnX + masterBtnW, y + masterBtnH)
    SetColor(COL.valueText)
    local masterLabel = masterOn and "PUPPETEER ACTIVE" or "PUPPETEER OFF"
    glText(masterLabel, masterBtnX + masterBtnW / 2, y + 2, P.fontSize, "ocB")
    RegisterHit("master", masterBtnX, y, masterBtnX + masterBtnW, y + masterBtnH)

    -------------------------------------------------------
    -- Separator
    -------------------------------------------------------
    y = y - P.sectionGap
    DrawSeparator(x + pad, x + w - pad, y + P.sectionGap / 2)

    -------------------------------------------------------
    -- Boolean toggles (2 columns)
    -------------------------------------------------------
    local colW = (w - pad * 3) / 2
    for i, toggle in ipairs(BOOL_TOGGLES) do
        local col = ((i - 1) % 2)
        if col == 0 then
            y = y - rh
        end

        local bx = x + pad + col * (colW + pad)
        local btnX = bx
        local btnW = P.toggleBtnW
        local btnH = P.toggleBtnH
        local btnY = y + (rh - btnH) / 2

        local isOn = PUP.toggles[toggle.key]
        local hitKey = "toggle_" .. toggle.key
        local isHovered = (hoveredElement == hitKey)

        -- Toggle button
        if isHovered then
            SetColor(COL.toggleHover)
        elseif isOn then
            SetColor(COL.toggleOn)
        else
            SetColor(COL.toggleOff)
        end
        FillRect(btnX, btnY, btnX + btnW, btnY + btnH)

        -- ON/OFF text
        SetColor(isOn and COL.toggleOnText or COL.toggleOffText)
        glText(isOn and "ON" or "OFF", btnX + btnW / 2, btnY + 1, 9, "ocB")

        -- Label
        SetColor(COL.labelText)
        glText(toggle.label, btnX + btnW + 4, btnY + 1, P.fontSize, "o")

        RegisterHit(hitKey, btnX, btnY, btnX + colW, btnY + btnH)
    end

    -------------------------------------------------------
    -- Separator
    -------------------------------------------------------
    y = y - P.sectionGap
    DrawSeparator(x + pad, x + w - pad, y + P.sectionGap / 2)

    -------------------------------------------------------
    -- Formation shape selector
    -------------------------------------------------------
    y = y - P.shapeBtnSize - 4
    SetColor(COL.labelText)
    glText("Shape:", x + pad, y + P.shapeBtnSize / 2 - 2, P.fontSize, "o")

    local shapeStartX = x + pad + 46
    local currentShape = PUP.toggles.formationShape or 1
    local shapeCount = PUP.SHAPE_COUNT or 5

    for i = 1, shapeCount do
        local sx = shapeStartX + (i - 1) * (P.shapeBtnSize + 3)
        local sy = y
        local sw = P.shapeBtnSize
        local sh = P.shapeBtnSize

        local isActive = (i == currentShape)
        local hitKey = "shape_" .. i
        local isHovered = (hoveredElement == hitKey)

        if isHovered then
            SetColor(COL.shapeHover)
        elseif isActive then
            SetColor(COL.shapeActive)
        else
            SetColor(COL.shapeInactive)
        end
        FillRect(sx, sy, sx + sw, sy + sh)

        -- Shape icon
        SetColor(isActive and COL.shapeText or COL.shapeDimText)
        local icon = SHAPE_LABELS[i] and string.sub(SHAPE_LABELS[i], 1, 2) or "?"
        if i == 1 then icon = "--" end
        if i == 2 then icon = "O" end
        if i == 3 then icon = "C" end
        if i == 4 then icon = "[]" end
        if i == 5 then icon = "*" end
        glText(icon, sx + sw / 2, sy + sh / 2 - 5, 10, "ocB")

        RegisterHit(hitKey, sx, sy, sx + sw, sy + sh)
    end

    -------------------------------------------------------
    -- Separator
    -------------------------------------------------------
    y = y - P.sectionGap
    DrawSeparator(x + pad, x + w - pad, y + P.sectionGap / 2)

    -------------------------------------------------------
    -- Numeric controls: value with +/- buttons
    -------------------------------------------------------
    for _, ctrl in ipairs(NUM_CONTROLS) do
        y = y - rh

        -- Label
        SetColor(COL.labelText)
        glText(ctrl.label .. ":", x + pad, y + rh / 2 - 5, P.fontSize, "o")

        -- Current value
        local val = PUP.toggles[ctrl.key] or ctrl.min
        SetColor(COL.valueText)
        local valStr = tostring(val)
        local valX = x + pad + 80
        glText(valStr, valX, y + rh / 2 - 5, P.fontSize, "o")

        -- Minus button
        local minusX = x + w - pad - P.numBtnW * 2 - 4
        local minusY = y + (rh - P.numBtnH) / 2
        local minusKey = "minus_" .. ctrl.key
        SetColor(hoveredElement == minusKey and COL.numBtnHover or COL.numBtnBg)
        FillRect(minusX, minusY, minusX + P.numBtnW, minusY + P.numBtnH)
        SetColor(COL.numBtnText)
        glText("-", minusX + P.numBtnW / 2, minusY + 1, 11, "ocB")
        RegisterHit(minusKey, minusX, minusY, minusX + P.numBtnW, minusY + P.numBtnH)

        -- Plus button
        local plusX = x + w - pad - P.numBtnW
        local plusKey = "plus_" .. ctrl.key
        SetColor(hoveredElement == plusKey and COL.numBtnHover or COL.numBtnBg)
        FillRect(plusX, minusY, plusX + P.numBtnW, minusY + P.numBtnH)
        SetColor(COL.numBtnText)
        glText("+", plusX + P.numBtnW / 2, minusY + 1, 11, "ocB")
        RegisterHit(plusKey, plusX, minusY, plusX + P.numBtnW, minusY + P.numBtnH)
    end

    -------------------------------------------------------
    -- Separator
    -------------------------------------------------------
    y = y - P.sectionGap
    DrawSeparator(x + pad, x + w - pad, y + P.sectionGap / 2)

    -------------------------------------------------------
    -- Status line
    -------------------------------------------------------
    y = y - rh
    local unitCount = PUP.unitCount or 0
    local maxUnits = 80
    local groupCount = 0
    if PUP.groups then
        for _ in pairs(PUP.groups) do groupCount = groupCount + 1 end
    end
    local lineCount = 0
    if PUP.firingLines then
        for _ in pairs(PUP.firingLines) do lineCount = lineCount + 1 end
    end

    SetColor(COL.statusText)
    local statusText = "Units: " .. unitCount .. "/" .. maxUnits
    if groupCount > 0 then
        statusText = statusText .. "  Fmns: " .. groupCount
    end
    if lineCount > 0 then
        statusText = statusText .. "  Lines: " .. lineCount
    end
    glText(statusText, x + pad, y + rh / 2 - 5, P.statusFontSize, "o")

    -- Shape name on the right
    local shapeName = PUP.GetShapeName and PUP.GetShapeName(currentShape) or "?"
    SetColor(COL.statusText)
    glText(shapeName, x + w - pad, y + rh / 2 - 5, P.statusFontSize, "oR")
end

local function DrawCollapsedPanel()
    if not PUP then return end

    hitRects = {}
    local P = PANEL
    local x = panelX
    local w = P.width
    local y = panelY

    panelH = P.titleHeight

    -- Border + background
    SetColor(COL.panelBorder)
    FillRect(x - 1, y - 1, x + w + 1, y + P.titleHeight + 1)
    SetColor(COL.titleBg)
    FillRect(x, y, x + w, y + P.titleHeight)
    RegisterHit("title", x, y, x + w, y + P.titleHeight)

    -- Title text
    SetColor(COL.titleText)
    local masterOn = PUP.active
    local statusStr = masterOn and " [ACTIVE]" or " [OFF]"
    glText("Puppeteer" .. statusStr, x + P.padding, y + 4, P.titleFontSize, "o")

    -- Expand button
    local expBtnX = x + w - 20
    local expBtnY = y + 3
    local expBtnW = 18
    local expBtnH = P.titleHeight - 6
    SetColor(hoveredElement == "minimize" and COL.ctrlBtnHover or COL.ctrlBtnBg)
    FillRect(expBtnX, expBtnY, expBtnX + expBtnW, expBtnY + expBtnH)
    SetColor(COL.ctrlBtnText)
    glText("+", expBtnX + expBtnW / 2, expBtnY + 1, 10, "ocB")
    RegisterHit("minimize", expBtnX, expBtnY, expBtnX + expBtnW, expBtnY + expBtnH)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function widget:DrawScreen()
    if not TL then return end
    -- Lazy grab: Puppeteer Core loads after this widget
    PUP = TL.Puppeteer
    if not PUP then return end
    if not panelVisible then return end

    if panelCollapsed then
        DrawCollapsedPanel()
    else
        CalculateAndDraw()
    end
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

local function PointInRect(mx, my, r)
    return mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2
end

function widget:IsAbove(mx, my)
    if not TL or not TL.Puppeteer or not panelVisible then return false end
    return mx >= panelX and mx <= panelX + PANEL.width and my >= panelY and my <= panelY + panelH
end

function widget:MouseMove(mx, my, dx, dy, button)
    if not TL or not TL.Puppeteer or not panelVisible then return false end

    -- Dragging
    if isDragging then
        panelX = mx - dragOffsetX
        panelY = my - dragOffsetY
        -- Clamp to screen
        panelX = mathMax(0, mathMin(panelX, vsx - PANEL.width))
        panelY = mathMax(0, mathMin(panelY, vsy - panelH))
        return true
    end

    -- Hover detection
    hoveredElement = nil
    for key, r in pairs(hitRects) do
        if PointInRect(mx, my, r) then
            hoveredElement = key
            return false
        end
    end

    return false
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end
    if not TL or not TL.Puppeteer or not panelVisible then return false end
    PUP = TL.Puppeteer

    -- Check if click is on the panel
    if not self:IsAbove(mx, my) then return false end

    -- Title bar: start drag
    local titleRect = hitRects["title"]
    if titleRect and PointInRect(mx, my, titleRect) then
        -- Check if it's on a control button first
        local minRect = hitRects["minimize"]
        local clsRect = hitRects["close"]

        if minRect and PointInRect(mx, my, minRect) then
            panelCollapsed = not panelCollapsed
            return true
        end

        if clsRect and PointInRect(mx, my, clsRect) then
            panelVisible = false
            return true
        end

        -- Start drag
        isDragging = true
        dragOffsetX = mx - panelX
        dragOffsetY = my - panelY
        return true
    end

    if panelCollapsed then return true end

    -- Master toggle
    if hitRects["master"] and PointInRect(mx, my, hitRects["master"]) then
        PUP.active = not PUP.active
        Spring.SetConfigInt("Puppeteer_active", PUP.active and 1 or 0)
        spEcho("[Puppeteer] " .. (PUP.active and "Enabled" or "Disabled"))
        return true
    end

    -- Boolean toggles
    for _, toggle in ipairs(BOOL_TOGGLES) do
        local hitKey = "toggle_" .. toggle.key
        local r = hitRects[hitKey]
        if r and PointInRect(mx, my, r) then
            if PUP.ToggleBool then
                PUP.ToggleBool(toggle.key)
            end
            return true
        end
    end

    -- Shape selector
    local shapeCount = PUP.SHAPE_COUNT or 5
    for i = 1, shapeCount do
        local hitKey = "shape_" .. i
        local r = hitRects[hitKey]
        if r and PointInRect(mx, my, r) then
            if PUP.SetToggle then
                PUP.SetToggle("formationShape", i)
            end
            return true
        end
    end

    -- Numeric +/- controls
    for _, ctrl in ipairs(NUM_CONTROLS) do
        local minusKey = "minus_" .. ctrl.key
        local plusKey = "plus_" .. ctrl.key

        local r = hitRects[minusKey]
        if r and PointInRect(mx, my, r) then
            local val = PUP.toggles[ctrl.key] or ctrl.min
            val = mathMax(ctrl.min, val - ctrl.step)
            if PUP.SetToggle then
                PUP.SetToggle(ctrl.key, val)
            end
            return true
        end

        r = hitRects[plusKey]
        if r and PointInRect(mx, my, r) then
            local val = PUP.toggles[ctrl.key] or ctrl.min
            val = mathMin(ctrl.max, val + ctrl.step)
            if PUP.SetToggle then
                PUP.SetToggle(ctrl.key, val)
            end
            return true
        end
    end

    return true  -- consume click on panel area
end

function widget:MouseRelease(mx, my, button)
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
        spEcho("[Puppeteer Panel] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    -- PUP is grabbed lazily in DrawScreen/mouse handlers
    -- because Puppeteer Core (layer 103) loads AFTER this widget (layer 100)
    PUP = TL.Puppeteer  -- may be nil at this point, that's OK

    -- Default position: left of sidebar if it exists, otherwise right side of screen
    -- Only set default if position wasn't restored from config
    if not positionRestored then
        local sidebarInfo = TL.SidebarInfo
        if sidebarInfo and sidebarInfo.dockRight then
            panelX = sidebarInfo.x - PANEL.width - 8
        else
            panelX = vsx - PANEL.width - 50
        end
        panelY = vsy / 2 - 100
    end

    -- Expose panel visibility toggle for sidebar integration
    WG.TotallyLegal.PuppeteerPanel = {
        Show = function() panelVisible = true end,
        Hide = function() panelVisible = false end,
        Toggle = function() panelVisible = not panelVisible end,
        IsVisible = function() return panelVisible end,
    }

    spEcho("[Puppeteer Panel] Initialized (waiting for Puppeteer Core).")
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    -- Clamp panel position
    panelX = mathMax(0, mathMin(panelX, vsx - PANEL.width))
    panelY = mathMax(0, mathMin(panelY, vsy - panelH))
end

function widget:Shutdown()
    if WG.TotallyLegal then
        WG.TotallyLegal.PuppeteerPanel = nil
    end
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return {
        panelX = panelX,
        panelY = panelY,
        collapsed = panelCollapsed,
        visible = panelVisible,
    }
end

function widget:SetConfigData(data)
    if data and data.panelX then
        panelX = data.panelX
        panelY = data.panelY or panelY
        panelVisible = data.visible ~= false
        panelCollapsed = data.collapsed or false
        positionRestored = true
    end
end
