-- TotallyLegal Sidebar - KSP-style widget toggle bar
-- Docked to screen edge, toggles visibility of individual TotallyLegal widgets.
-- Ranked-safe (read-only). No GiveOrder calls.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Sidebar",
        desc      = "KSP-style toggle bar for TotallyLegal widgets. Click icons to show/hide overlays and panels.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 99,
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

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local osClock   = os.clock

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Widget registry
--------------------------------------------------------------------------------

-- Categories: "info" = always available, "micro" = Level 1+
local WIDGET_REGISTRY = {
    { key = "Overlay",   icon = "OV", name = "Resource Overlay",    category = "info" },
    { key = "Timeline",  icon = "TL", name = "Economy Timeline",    category = "info" },
    -- separator
    { key = "Puppeteer", icon = "UP", name = "Unit Puppeteer (master toggle)", category = "micro" },
    { key = "SmartMove", icon = "SM", name = "Smart Move (range-aware pathing)", category = "micro" },
    { key = "PupDodge",  icon = "PD", name = "Auto-Dodge (projectile evasion)", category = "micro" },
    { key = "Formation", icon = "FM", name = "Formations (line/circle/wedge)", category = "micro" },
    { key = "FiringLn",  icon = "FL", name = "Firing Line (attack positioning)", category = "micro" },
    { key = "March",     icon = "MR", name = "March & Scatter (speed match + spacing)", category = "micro" },
}

-- Which categories have separator lines before them
local CATEGORY_SEPARATORS = { micro = true }

-- Puppeteer toggle mapping: sidebar key -> Puppeteer toggle key
local PUPPETEER_TOGGLES = {
    SmartMove  = "smartMove",
    PupDodge   = "dodge",
    Formation  = "formations",
    FiringLn   = "firingLine",
    March      = "march",
}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    buttonSize   = 32,
    buttonGap    = 2,
    edgePadding  = 4,
    cornerRadius = 0,
    fontSize     = 10,
    tooltipFontSize = 13,
    tooltipPadding  = 8,
    separatorHeight = 6,
    levelIndicatorHeight = 28,  -- bigger automation button
    levelFontSize = 14,
    dragHandleHeight = 10,
    dockRight    = true,      -- true = right edge, false = left edge
    collapseSize = 32,        -- collapsed bar width = just the logo button
}

local COL = {
    barBg         = { 0.05, 0.05, 0.08, 0.88 },
    buttonBg      = { 0.12, 0.12, 0.18, 0.90 },
    buttonHover   = { 0.18, 0.18, 0.28, 0.95 },
    buttonActive  = { 0.15, 0.25, 0.40, 0.95 },
    iconDimmed    = { 0.40, 0.40, 0.45, 0.70 },
    iconLit       = { 0.85, 0.95, 1.00, 1.00 },
    iconDisabled  = { 0.25, 0.25, 0.28, 0.50 },
    separator     = { 0.30, 0.30, 0.40, 0.40 },
    tooltipBg     = { 0.06, 0.06, 0.10, 0.97 },
    tooltipBorder = { 0.35, 0.45, 0.65, 0.80 },
    tooltipText   = { 0.95, 0.95, 1.00, 1.00 },
    logoBg        = { 0.10, 0.15, 0.25, 0.95 },
    logoText      = { 0.50, 0.80, 1.00, 1.00 },
    dragHandle    = { 0.30, 0.30, 0.40, 0.60 },
    dragHandleHover = { 0.45, 0.50, 0.65, 0.90 },
    -- Level indicator colors
    levelGrey     = { 0.40, 0.40, 0.40, 0.90 },
    levelGreen    = { 0.30, 0.80, 0.30, 0.90 },
    levelBlue     = { 0.30, 0.50, 1.00, 0.90 },
    levelGold     = { 1.00, 0.85, 0.20, 0.90 },
}

local LEVEL_COLORS = {
    [0] = COL.levelGrey,
    [1] = COL.levelGreen,
    [2] = COL.levelBlue,
    [3] = COL.levelGold,
}

local LEVEL_NAMES = {
    [0] = "PvP",
    [1] = "PvE",
    [2] = "Train",
    [3] = "EvE",
}

local LEVEL_DESCRIPTIONS = {
    [0] = "Manual play, no automation",
    [1] = "AI executes commands",
    [2] = "AI advises (suggestions)",
    [3] = "Fully autonomous AI",
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local vsx, vsy = 0, 0
local sidebarCollapsed = false
local hoveredButton = nil      -- index into WIDGET_REGISTRY, or "logo", or "level", or "drag"
local buttonRects = {}         -- [i] = { x1, y1, x2, y2 }
local logoRect = {}            -- { x1, y1, x2, y2 }
local levelRect = {}           -- { x1, y1, x2, y2 }
local dragHandleRect = {}      -- { x1, y1, x2, y2 }
local barX, barY, barW, barH = 0, 0, 0, 0

-- Drag state for vertical repositioning
local isDraggingY = false
local dragOffsetY = 0
local userBarY = nil  -- nil = auto-center, number = user-set position

--------------------------------------------------------------------------------
-- Visibility state management
--------------------------------------------------------------------------------

local function EnsureVisibilityTable()
    if not WG.TotallyLegal then return end
    if not WG.TotallyLegal.WidgetVisibility then
        WG.TotallyLegal.WidgetVisibility = {}
    end
    local vis = WG.TotallyLegal.WidgetVisibility
    for _, entry in ipairs(WIDGET_REGISTRY) do
        if vis[entry.key] == nil then
            vis[entry.key] = true
        end
    end
end

local function IsWidgetVisible(key)
    -- For Puppeteer sub-toggles, read from Puppeteer state
    local pupToggle = PUPPETEER_TOGGLES[key]
    if pupToggle then
        local pup = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
        if pup and pup.toggles then
            return pup.toggles[pupToggle] or false
        end
        return false
    end

    -- For master Puppeteer toggle: show panel visibility state
    if key == "Puppeteer" then
        local panel = WG.TotallyLegal and WG.TotallyLegal.PuppeteerPanel
        if panel and panel.IsVisible then
            return panel.IsVisible()
        end
        local pup = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
        return pup and pup.active or false
    end

    if not WG.TotallyLegal or not WG.TotallyLegal.WidgetVisibility then return true end
    local v = WG.TotallyLegal.WidgetVisibility[key]
    if v == nil then return true end
    return v
end

local function ToggleWidgetVisibility(key)
    -- For Puppeteer sub-toggles, use Puppeteer's toggle API
    local pupToggle = PUPPETEER_TOGGLES[key]
    if pupToggle then
        local pup = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
        if pup and pup.ToggleBool then
            pup.ToggleBool(pupToggle)
        end
        return
    end

    -- For master Puppeteer toggle: open/close the panel
    if key == "Puppeteer" then
        local panel = WG.TotallyLegal and WG.TotallyLegal.PuppeteerPanel
        if panel and panel.Toggle then
            panel.Toggle()
        else
            -- Fallback: toggle active state directly
            local pup = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
            if pup then
                pup.active = not pup.active
                Spring.Echo("[Puppeteer] " .. (pup.active and "Enabled" or "Disabled"))
            end
        end
        return
    end

    EnsureVisibilityTable()
    if not WG.TotallyLegal or not WG.TotallyLegal.WidgetVisibility then return end
    local cur = WG.TotallyLegal.WidgetVisibility[key]
    if cur == nil then cur = true end
    WG.TotallyLegal.WidgetVisibility[key] = not cur
end

local function IsWidgetAvailable(entry)
    -- Info widgets are always available
    if entry.category == "info" then return true end
    -- Micro/macro require automation level >= 1
    local level = TL and TL.GetAutomationLevel and TL.GetAutomationLevel() or 0
    if level < 1 then return false end

    -- Puppeteer sub-toggles require Puppeteer Core loaded
    if PUPPETEER_TOGGLES[entry.key] or entry.key == "Puppeteer" then
        local pup = WG.TotallyLegal and WG.TotallyLegal.Puppeteer
        return pup ~= nil
    end

    return true
end

--------------------------------------------------------------------------------
-- Layout calculation
--------------------------------------------------------------------------------

local function CalculateLayout()
    local btnSize = CFG.buttonSize
    local gap = CFG.buttonGap
    local pad = CFG.edgePadding

    -- Total height: drag handle + logo + buttons + separators + level indicator
    local totalH = CFG.dragHandleHeight + pad + btnSize + gap  -- drag handle + logo button

    local lastCat = nil
    for _, entry in ipairs(WIDGET_REGISTRY) do
        if CATEGORY_SEPARATORS[entry.category] and lastCat ~= entry.category then
            totalH = totalH + CFG.separatorHeight
        end
        totalH = totalH + btnSize + gap
        lastCat = entry.category
    end

    totalH = totalH + CFG.separatorHeight + CFG.levelIndicatorHeight + pad

    barW = btnSize + pad * 2
    barH = totalH

    if CFG.dockRight then
        barX = vsx - barW
    else
        barX = 0
    end
    
    -- Use user-set Y position or center
    if userBarY then
        barY = mathMax(0, mathMin(userBarY, vsy - barH))
    else
        barY = (vsy - barH) / 2
    end

    -- Calculate button positions (top to bottom)
    local y = barY + barH

    -- Drag handle at top
    y = y - CFG.dragHandleHeight
    dragHandleRect = { x1 = barX, y1 = y, x2 = barX + barW, y2 = y + CFG.dragHandleHeight }
    y = y - pad

    -- Logo button
    local x = barX + pad
    y = y - btnSize
    logoRect = { x1 = x, y1 = y, x2 = x + btnSize, y2 = y + btnSize }
    y = y - gap

    -- Widget buttons
    buttonRects = {}
    lastCat = nil
    for i, entry in ipairs(WIDGET_REGISTRY) do
        if CATEGORY_SEPARATORS[entry.category] and lastCat ~= entry.category then
            y = y - CFG.separatorHeight
        end
        y = y - btnSize
        buttonRects[i] = { x1 = x, y1 = y, x2 = x + btnSize, y2 = y + btnSize }
        y = y - gap
        lastCat = entry.category
    end

    -- Level indicator
    y = y - CFG.separatorHeight
    y = y - CFG.levelIndicatorHeight
    levelRect = { x1 = x, y1 = y, x2 = x + btnSize, y2 = y + CFG.levelIndicatorHeight }
    
    -- Expose sidebar position for other widgets to dock beside
    if WG.TotallyLegal then
        WG.TotallyLegal.SidebarInfo = {
            x = barX,
            y = barY,
            w = barW,
            h = barH,
            dockRight = CFG.dockRight,
        }
    end
end

--------------------------------------------------------------------------------
-- Rendering helpers
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end
local function FillRect(x1, y1, x2, y2) glRect(x1, y1, x2, y2) end

local function DrawSeparator(y)
    local cx = barX + barW / 2
    local hw = (CFG.buttonSize - 8) / 2
    SetColor(COL.separator)
    glLineWidth(1)
    glBeginEnd(GL_LINES, function()
        glVertex(cx - hw, y, 0)
        glVertex(cx + hw, y, 0)
    end)
end

local function DrawDragHandle(hovered)
    -- Three horizontal lines (grip pattern)
    SetColor(hovered and COL.dragHandleHover or COL.dragHandle)
    local cx = (dragHandleRect.x1 + dragHandleRect.x2) / 2
    local cy = (dragHandleRect.y1 + dragHandleRect.y2) / 2
    local hw = 6
    glLineWidth(1)
    for i = -1, 1 do
        local ly = cy + i * 2.5
        glBeginEnd(GL_LINES, function()
            glVertex(cx - hw, ly, 0)
            glVertex(cx + hw, ly, 0)
        end)
    end
end

--------------------------------------------------------------------------------
-- Main rendering
--------------------------------------------------------------------------------

local function DrawBar()
    -- Bar background
    SetColor(COL.barBg)
    FillRect(barX, barY, barX + barW, barY + barH)

    -- Drag handle at top
    DrawDragHandle(hoveredButton == "drag")

    -- Logo button
    local lr = logoRect
    local logoHovered = (hoveredButton == "logo")
    SetColor(logoHovered and COL.buttonHover or COL.logoBg)
    FillRect(lr.x1, lr.y1, lr.x2, lr.y2)
    SetColor(COL.logoText)
    local cx = (lr.x1 + lr.x2) / 2
    local cy = (lr.y1 + lr.y2) / 2 - 4
    glText("TL", cx, cy, CFG.fontSize + 1, "ocB")

    -- Widget buttons
    local lastCat = nil
    for i, entry in ipairs(WIDGET_REGISTRY) do
        local r = buttonRects[i]
        if not r then break end

        -- Draw separator line between categories
        if CATEGORY_SEPARATORS[entry.category] and lastCat ~= entry.category then
            DrawSeparator(r.y2 + CFG.buttonGap + CFG.separatorHeight / 2)
        end
        lastCat = entry.category

        local visible = IsWidgetVisible(entry.key)
        local available = IsWidgetAvailable(entry)
        local hovered = (hoveredButton == i)

        -- Button background
        if not available then
            SetColor(COL.buttonBg)
        elseif hovered then
            SetColor(COL.buttonHover)
        elseif visible then
            SetColor(COL.buttonActive)
        else
            SetColor(COL.buttonBg)
        end
        FillRect(r.x1, r.y1, r.x2, r.y2)

        -- Icon text
        if not available then
            SetColor(COL.iconDisabled)
        elseif visible then
            SetColor(COL.iconLit)
        else
            SetColor(COL.iconDimmed)
        end
        local bcx = (r.x1 + r.x2) / 2
        local bcy = (r.y1 + r.y2) / 2 - 4
        glText(entry.icon, bcx, bcy, CFG.fontSize, "ocB")
    end

    -- Level indicator (automation mode button)
    local level = TL and TL.GetAutomationLevel and TL.GetAutomationLevel() or 0
    local levelCol = LEVEL_COLORS[level] or COL.levelGrey
    local isHovered = (hoveredButton == "level")
    
    -- Background
    if isHovered then
        SetColor(COL.buttonHover)
    else
        SetColor(COL.buttonBg)
    end
    FillRect(levelRect.x1, levelRect.y1, levelRect.x2, levelRect.y2)
    
    -- Colored accent bar at bottom
    SetColor(levelCol)
    FillRect(levelRect.x1, levelRect.y1, levelRect.x2, levelRect.y1 + 4)
    
    -- Text label
    local levelText = LEVEL_NAMES[level] or "?"
    SetColor(COL.iconLit)
    local lcx = (levelRect.x1 + levelRect.x2) / 2
    local lcy = (levelRect.y1 + levelRect.y2) / 2 - 2
    glText(levelText, lcx, lcy, CFG.levelFontSize, "ocB")
end

local function DrawTooltip()
    if not hoveredButton then return end

    local text = nil
    if hoveredButton == "logo" then
        text = sidebarCollapsed and "Expand Sidebar" or "Collapse Sidebar"
    elseif hoveredButton == "drag" then
        text = "Drag to reposition"
    elseif hoveredButton == "level" then
        local level = TL and TL.GetAutomationLevel and TL.GetAutomationLevel() or 0
        local desc = LEVEL_DESCRIPTIONS and LEVEL_DESCRIPTIONS[level] or ""
        text = (LEVEL_NAMES[level] or "?") .. ": " .. desc .. " (click to cycle)"
    elseif type(hoveredButton) == "number" then
        local entry = WIDGET_REGISTRY[hoveredButton]
        if entry then
            local visible = IsWidgetVisible(entry.key)
            local available = IsWidgetAvailable(entry)
            if not available then
                text = entry.name .. " (requires Level 1+)"
            elseif visible then
                text = entry.name .. " (click to hide)"
            else
                text = entry.name .. " (click to show)"
            end
        end
    end

    if not text then return end

    -- Tooltip position: to the left of the bar (or right if docked left)
    local tipW = #text * (CFG.tooltipFontSize * 0.6) + CFG.tooltipPadding * 2
    local tipH = CFG.tooltipFontSize + CFG.tooltipPadding * 2
    local tipX, tipY

    -- Get the rect of the hovered element
    local refRect
    if hoveredButton == "logo" then
        refRect = logoRect
    elseif hoveredButton == "level" then
        refRect = levelRect
    elseif hoveredButton == "drag" then
        refRect = dragHandleRect
    else
        refRect = buttonRects[hoveredButton]
    end
    if not refRect then return end

    tipY = (refRect.y1 + refRect.y2) / 2 - tipH / 2

    if CFG.dockRight then
        tipX = barX - tipW - 4
    else
        tipX = barX + barW + 4
    end

    -- Clamp to screen
    tipX = mathMax(0, mathMin(tipX, vsx - tipW))
    tipY = mathMax(0, mathMin(tipY, vsy - tipH))

    -- Tooltip border (slightly larger rect behind)
    SetColor(COL.tooltipBorder)
    FillRect(tipX - 1, tipY - 1, tipX + tipW + 1, tipY + tipH + 1)

    -- Tooltip background
    SetColor(COL.tooltipBg)
    FillRect(tipX, tipY, tipX + tipW, tipY + tipH)

    SetColor(COL.tooltipText)
    glText(text, tipX + CFG.tooltipPadding, tipY + CFG.tooltipPadding - 1, CFG.tooltipFontSize, "o")
end

function widget:DrawScreen()
    if not TL then return end
    if sidebarCollapsed then
        -- Just draw the logo button
        local lr = logoRect
        local logoHovered = (hoveredButton == "logo")
        SetColor(logoHovered and COL.buttonHover or COL.logoBg)
        FillRect(lr.x1, lr.y1, lr.x2, lr.y2)
        SetColor(COL.logoText)
        local cx = (lr.x1 + lr.x2) / 2
        local cy = (lr.y1 + lr.y2) / 2 - 4
        glText("TL", cx, cy, CFG.fontSize + 1, "ocB")
        DrawTooltip()
        return
    end

    DrawBar()
    DrawTooltip()
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

local function PointInRect(x, y, r)
    return x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2
end

function widget:IsAbove(x, y)
    if not TL then return false end

    if sidebarCollapsed then
        return PointInRect(x, y, logoRect)
    end

    return x >= barX and x <= barX + barW and y >= barY and y <= barY + barH
end

function widget:MouseMove(x, y, dx, dy, button)
    if not TL then return false end

    -- Handle Y-drag
    if isDraggingY then
        userBarY = y - dragOffsetY
        userBarY = mathMax(0, mathMin(userBarY, vsy - barH))
        CalculateLayout()
        return true
    end

    hoveredButton = nil

    if sidebarCollapsed then
        if PointInRect(x, y, logoRect) then
            hoveredButton = "logo"
        end
        return false
    end

    -- Check drag handle
    if PointInRect(x, y, dragHandleRect) then
        hoveredButton = "drag"
        return false
    end

    -- Check logo
    if PointInRect(x, y, logoRect) then
        hoveredButton = "logo"
        return false
    end

    -- Check level indicator
    if PointInRect(x, y, levelRect) then
        hoveredButton = "level"
        return false
    end

    -- Check widget buttons
    for i, r in ipairs(buttonRects) do
        if PointInRect(x, y, r) then
            hoveredButton = i
            return false
        end
    end

    return false
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    if not TL then return false end

    -- Drag handle: start Y-drag
    if not sidebarCollapsed and PointInRect(x, y, dragHandleRect) then
        isDraggingY = true
        dragOffsetY = y - barY
        return true
    end

    -- Logo: toggle collapse
    if PointInRect(x, y, logoRect) then
        sidebarCollapsed = not sidebarCollapsed
        if not sidebarCollapsed then
            CalculateLayout()
        end
        return true
    end

    if sidebarCollapsed then return false end

    -- Level indicator: cycle automation level
    if PointInRect(x, y, levelRect) then
        if TL.SetAutomationLevel and TL.GetAutomationLevel then
            local cur = TL.GetAutomationLevel()
            TL.SetAutomationLevel((cur + 1) % 4)
        end
        return true
    end

    -- Widget buttons: toggle visibility
    for i, r in ipairs(buttonRects) do
        if PointInRect(x, y, r) then
            local entry = WIDGET_REGISTRY[i]
            if entry and IsWidgetAvailable(entry) then
                ToggleWidgetVisibility(entry.key)
            end
            return true
        end
    end

    return false
end

function widget:MouseRelease(x, y, button)
    if isDraggingY then
        isDraggingY = false
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
        spEcho("[TotallyLegal Sidebar] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal
    EnsureVisibilityTable()
    CalculateLayout()

    spEcho("[TotallyLegal Sidebar] Initialized. " .. #WIDGET_REGISTRY .. " widgets registered.")
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    CalculateLayout()
end

function widget:Shutdown()
    -- Don't nil the visibility table - other widgets may still be shutting down
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    local visData = {}
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility then
        for _, entry in ipairs(WIDGET_REGISTRY) do
            visData[entry.key] = WG.TotallyLegal.WidgetVisibility[entry.key]
        end
    end
    return {
        collapsed = sidebarCollapsed,
        dockRight = CFG.dockRight,
        userBarY = userBarY,
        visibility = visData,
    }
end

function widget:SetConfigData(data)
    if data.collapsed ~= nil then sidebarCollapsed = data.collapsed end
    if data.dockRight ~= nil then CFG.dockRight = data.dockRight end
    if data.userBarY ~= nil then userBarY = data.userBarY end
    if data.visibility then
        EnsureVisibilityTable()
        if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility then
            for k, v in pairs(data.visibility) do
                WG.TotallyLegal.WidgetVisibility[k] = v
            end
        end
    end
end
