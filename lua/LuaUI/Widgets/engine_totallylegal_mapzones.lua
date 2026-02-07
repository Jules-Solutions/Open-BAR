-- TotallyLegal Map Zones - Defense lines and building area management
-- Allows drawing defense lines (primary/secondary) and building area on the map.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Map Zones",
        desc      = "Map-drawn defense lines and building area. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 206,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetViewGeometry   = Spring.GetViewGeometry
local spGetGameFrame      = Spring.GetGameFrame
local spGetGroundHeight   = Spring.GetGroundHeight
local spTraceScreenRay    = Spring.TraceScreenRay
local spEcho              = Spring.Echo

local glColor      = gl.Color
local glRect       = gl.Rect
local glText       = gl.Text
local glLineWidth  = gl.LineWidth
local glBeginEnd   = gl.BeginEnd
local glVertex     = gl.Vertex
local glPushMatrix = gl.PushMatrix
local glPopMatrix  = gl.PopMatrix
local glScale      = gl.Scale
local GL_LINES     = GL.LINES
local GL_LINE_LOOP = GL.LINE_LOOP
local GL_LINE_STRIP = GL.LINE_STRIP

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local mathSqrt  = math.sqrt
local mathCos   = math.cos
local mathSin   = math.sin
local mathPi    = math.pi

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    panelWidth     = 200,
    panelHeight    = 120,
    panelPadding   = 8,
    titleHeight    = 22,
    buttonHeight   = 20,
    buttonSpacing  = 4,
    fontSize       = 9,
    titleFontSize  = 11,
    circleSegments = 32,
}

local COL = {
    panelBg     = { 0.05, 0.05, 0.08, 0.85 },
    panelTitle  = { 0.12, 0.15, 0.25, 0.95 },
    titleText   = { 0.90, 0.90, 0.95, 1.0 },
    labelText   = { 0.65, 0.65, 0.70, 1.0 },
    buttonBg    = { 0.15, 0.20, 0.30, 0.85 },
    buttonActive = { 0.30, 0.55, 0.80, 0.90 },
    buttonText  = { 0.85, 0.90, 0.95, 1.0 },
    clearBtn    = { 0.60, 0.20, 0.20, 0.85 },
    -- Map rendering colors
    buildingArea    = { 0.20, 0.70, 0.20, 0.35 },
    buildingAreaLine = { 0.30, 0.80, 0.30, 0.60 },
    primaryLine     = { 0.90, 0.15, 0.15, 0.80 },
    secondaryLine   = { 0.90, 0.80, 0.15, 0.70 },
    previewLine     = { 0.80, 0.80, 0.80, 0.50 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local mapZones = {
    buildingArea  = { defined = false, center = { x = 0, z = 0 }, radius = 600 },
    primaryLine   = { defined = false, p1 = { x = 0, z = 0 }, p2 = { x = 0, z = 0 } },
    secondaryLine = { defined = false, p1 = { x = 0, z = 0 }, p2 = { x = 0, z = 0 } },
    drawMode      = "none",  -- "none" | "building_area" | "primary_line" | "secondary_line"
}

-- Drawing state
local drawClick = 0       -- 0 = waiting for first click, 1 = waiting for second click
local firstClickPos = nil -- { x, z } from first click

-- Panel position
local vsx, vsy = 0, 0
local panelX, panelY = 0, 0
local panelCollapsed = false
local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0

-- Mouse preview position (for drawing feedback)
local previewX, previewZ = nil, nil

--------------------------------------------------------------------------------
-- API functions
--------------------------------------------------------------------------------

local function StartDrawBuildingArea()
    mapZones.drawMode = "building_area"
    drawClick = 0
    firstClickPos = nil
    spEcho("[TotallyLegal MapZones] Click map to set building area center.")
end

local function StartDrawPrimaryLine()
    mapZones.drawMode = "primary_line"
    drawClick = 0
    firstClickPos = nil
    spEcho("[TotallyLegal MapZones] Click map to set primary defense line start.")
end

local function StartDrawSecondaryLine()
    mapZones.drawMode = "secondary_line"
    drawClick = 0
    firstClickPos = nil
    spEcho("[TotallyLegal MapZones] Click map to set secondary defense line start.")
end

local function ClearBuildingArea()
    mapZones.buildingArea.defined = false
    spEcho("[TotallyLegal MapZones] Building area cleared.")
end

local function ClearPrimaryLine()
    mapZones.primaryLine.defined = false
    spEcho("[TotallyLegal MapZones] Primary defense line cleared.")
end

local function ClearSecondaryLine()
    mapZones.secondaryLine.defined = false
    spEcho("[TotallyLegal MapZones] Secondary defense line cleared.")
end

local function ClearAll()
    ClearBuildingArea()
    ClearPrimaryLine()
    ClearSecondaryLine()
end

local function IsInsideBuildingArea(x, z)
    if not mapZones.buildingArea.defined then return true end  -- no constraint
    local ba = mapZones.buildingArea
    local dx = x - ba.center.x
    local dz = z - ba.center.z
    return (dx * dx + dz * dz) <= (ba.radius * ba.radius)
end

local function CancelDraw()
    mapZones.drawMode = "none"
    drawClick = 0
    firstClickPos = nil
    previewX, previewZ = nil, nil
end

--------------------------------------------------------------------------------
-- World position from screen coordinates
--------------------------------------------------------------------------------

local function GetWorldPos(sx, sy)
    local kind, coords = spTraceScreenRay(sx, sy, true)
    if kind == "ground" and coords then
        return coords[1], coords[3]
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Minimap rendering
--------------------------------------------------------------------------------

function widget:DrawInMiniMap(sx, sz)
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.MapZones == false then return end
    local mapSizeX = Game.mapSizeX or 8192
    local mapSizeZ = Game.mapSizeZ or 8192
    local scaleX = sx / mapSizeX
    local scaleZ = sz / mapSizeZ

    glPushMatrix()
    glScale(1, 1, 1)

    -- Building area (green circle)
    if mapZones.buildingArea.defined then
        local ba = mapZones.buildingArea
        glColor(COL.buildingAreaLine[1], COL.buildingAreaLine[2], COL.buildingAreaLine[3], COL.buildingAreaLine[4])
        glLineWidth(1.5)
        glBeginEnd(GL_LINE_LOOP, function()
            for i = 0, CFG.circleSegments - 1 do
                local angle = (i / CFG.circleSegments) * 2 * mathPi
                local px = (ba.center.x + mathCos(angle) * ba.radius) * scaleX
                local pz = (ba.center.z + mathSin(angle) * ba.radius) * scaleZ
                glVertex(px, pz, 0)
            end
        end)
    end

    -- Primary defense line (solid red)
    if mapZones.primaryLine.defined then
        local pl = mapZones.primaryLine
        glColor(COL.primaryLine[1], COL.primaryLine[2], COL.primaryLine[3], COL.primaryLine[4])
        glLineWidth(2.5)
        glBeginEnd(GL_LINES, function()
            glVertex(pl.p1.x * scaleX, pl.p1.z * scaleZ, 0)
            glVertex(pl.p2.x * scaleX, pl.p2.z * scaleZ, 0)
        end)
    end

    -- Secondary defense line (dashed yellow - approximated with segments)
    if mapZones.secondaryLine.defined then
        local sl = mapZones.secondaryLine
        glColor(COL.secondaryLine[1], COL.secondaryLine[2], COL.secondaryLine[3], COL.secondaryLine[4])
        glLineWidth(2.0)
        local dashCount = 8
        local dx = sl.p2.x - sl.p1.x
        local dz = sl.p2.z - sl.p1.z
        for d = 0, dashCount - 1, 2 do
            local t0 = d / dashCount
            local t1 = (d + 1) / dashCount
            glBeginEnd(GL_LINES, function()
                glVertex((sl.p1.x + dx * t0) * scaleX, (sl.p1.z + dz * t0) * scaleZ, 0)
                glVertex((sl.p1.x + dx * t1) * scaleX, (sl.p1.z + dz * t1) * scaleZ, 0)
            end)
        end
    end

    -- Preview: show first click point and line to cursor during drawing
    if mapZones.drawMode ~= "none" and firstClickPos and previewX then
        glColor(COL.previewLine[1], COL.previewLine[2], COL.previewLine[3], COL.previewLine[4])
        glLineWidth(1.0)
        if mapZones.drawMode == "building_area" then
            -- Preview circle
            local cx, cz = firstClickPos.x, firstClickPos.z
            local r = mathSqrt((previewX - cx)^2 + (previewZ - cz)^2)
            glBeginEnd(GL_LINE_LOOP, function()
                for i = 0, CFG.circleSegments - 1 do
                    local angle = (i / CFG.circleSegments) * 2 * mathPi
                    local px = (cx + mathCos(angle) * r) * scaleX
                    local pz = (cz + mathSin(angle) * r) * scaleZ
                    glVertex(px, pz, 0)
                end
            end)
        else
            -- Preview line
            glBeginEnd(GL_LINES, function()
                glVertex(firstClickPos.x * scaleX, firstClickPos.z * scaleZ, 0)
                glVertex(previewX * scaleX, previewZ * scaleZ, 0)
            end)
        end
    end

    glColor(1, 1, 1, 1)
    glPopMatrix()
end

--------------------------------------------------------------------------------
-- World rendering (3D terrain indicators)
--------------------------------------------------------------------------------

function widget:DrawWorldPreUnit()
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.MapZones == false then return end
    -- Building area ground circle
    if mapZones.buildingArea.defined then
        local ba = mapZones.buildingArea
        glColor(COL.buildingArea[1], COL.buildingArea[2], COL.buildingArea[3], COL.buildingArea[4])
        glLineWidth(2.0)
        glBeginEnd(GL_LINE_LOOP, function()
            for i = 0, CFG.circleSegments - 1 do
                local angle = (i / CFG.circleSegments) * 2 * mathPi
                local px = ba.center.x + mathCos(angle) * ba.radius
                local pz = ba.center.z + mathSin(angle) * ba.radius
                local py = spGetGroundHeight(px, pz) or 0
                glVertex(px, py + 5, pz)
            end
        end)
    end

    -- Primary defense line (thick red line on ground)
    if mapZones.primaryLine.defined then
        local pl = mapZones.primaryLine
        glColor(COL.primaryLine[1], COL.primaryLine[2], COL.primaryLine[3], COL.primaryLine[4])
        glLineWidth(4.0)
        local segments = 16
        glBeginEnd(GL_LINE_STRIP, function()
            for i = 0, segments do
                local t = i / segments
                local px = pl.p1.x + (pl.p2.x - pl.p1.x) * t
                local pz = pl.p1.z + (pl.p2.z - pl.p1.z) * t
                local py = spGetGroundHeight(px, pz) or 0
                glVertex(px, py + 8, pz)
            end
        end)
    end

    -- Secondary defense line (dashed yellow on ground)
    if mapZones.secondaryLine.defined then
        local sl = mapZones.secondaryLine
        glColor(COL.secondaryLine[1], COL.secondaryLine[2], COL.secondaryLine[3], COL.secondaryLine[4])
        glLineWidth(3.0)
        local dashCount = 10
        local dx = sl.p2.x - sl.p1.x
        local dz = sl.p2.z - sl.p1.z
        for d = 0, dashCount - 1, 2 do
            local t0 = d / dashCount
            local t1 = (d + 1) / dashCount
            glBeginEnd(GL_LINES, function()
                local px0 = sl.p1.x + dx * t0
                local pz0 = sl.p1.z + dz * t0
                local py0 = spGetGroundHeight(px0, pz0) or 0
                local px1 = sl.p1.x + dx * t1
                local pz1 = sl.p1.z + dz * t1
                local py1 = spGetGroundHeight(px1, pz1) or 0
                glVertex(px0, py0 + 8, pz0)
                glVertex(px1, py1 + 8, pz1)
            end)
        end
    end

    glColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Control panel rendering
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end

local function DrawPanelButton(x, y, w, h, label, isActive)
    SetColor(isActive and COL.buttonActive or COL.buttonBg)
    glRect(x, y, x + w, y + h)
    SetColor(COL.buttonText)
    glText(label, x + w / 2, y + 3, CFG.fontSize, "ocB")
end

function widget:DrawScreen()
    if not TL then return end
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.MapZones == false then return end

    local pH = panelCollapsed and CFG.titleHeight or CFG.panelHeight

    -- Panel background
    SetColor(COL.panelBg)
    glRect(panelX, panelY, panelX + CFG.panelWidth, panelY + pH)

    -- Title bar
    SetColor(COL.panelTitle)
    glRect(panelX, panelY + pH - CFG.titleHeight, panelX + CFG.panelWidth, panelY + pH)
    SetColor(COL.titleText)
    glText("Map Zones", panelX + CFG.panelPadding, panelY + pH - CFG.titleHeight + 6, CFG.titleFontSize, "oB")

    -- Collapse toggle
    SetColor(COL.labelText)
    glText(panelCollapsed and "[+]" or "[-]", panelX + CFG.panelWidth - CFG.panelPadding - 18,
           panelY + pH - CFG.titleHeight + 6, CFG.titleFontSize, "o")

    if panelCollapsed then return end

    -- Draw mode indicator
    if mapZones.drawMode ~= "none" then
        SetColor(COL.buttonActive)
        local modeStr = "Drawing: " .. mapZones.drawMode:gsub("_", " ")
        if drawClick == 0 then modeStr = modeStr .. " (click start)"
        else modeStr = modeStr .. " (click end)" end
        glText(modeStr, panelX + CFG.panelPadding, panelY + pH - CFG.titleHeight - 16, CFG.fontSize, "o")
    end

    -- Buttons
    local bx = panelX + CFG.panelPadding
    local bw = CFG.panelWidth - CFG.panelPadding * 2
    local by = panelY + CFG.panelPadding

    -- Status line
    local statusParts = {}
    if mapZones.buildingArea.defined then statusParts[#statusParts + 1] = "Area" end
    if mapZones.primaryLine.defined then statusParts[#statusParts + 1] = "PriLine" end
    if mapZones.secondaryLine.defined then statusParts[#statusParts + 1] = "SecLine" end
    SetColor(COL.labelText)
    local statusStr = #statusParts > 0 and ("Defined: " .. table.concat(statusParts, ", ")) or "No zones defined"
    glText(statusStr, bx, by, CFG.fontSize - 1, "o")
    by = by + 14

    -- Clear button
    DrawPanelButton(bx, by, bw, CFG.buttonHeight, "Clear All", false)
    by = by + CFG.buttonHeight + CFG.buttonSpacing

    -- Draw buttons row
    local btn3W = (bw - CFG.buttonSpacing * 2) / 3
    DrawPanelButton(bx, by, btn3W, CFG.buttonHeight, "Area",
                    mapZones.drawMode == "building_area")
    DrawPanelButton(bx + btn3W + CFG.buttonSpacing, by, btn3W, CFG.buttonHeight, "Primary",
                    mapZones.drawMode == "primary_line")
    DrawPanelButton(bx + (btn3W + CFG.buttonSpacing) * 2, by, btn3W, CFG.buttonHeight, "Secondary",
                    mapZones.drawMode == "secondary_line")
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

local function IsAbovePanel(x, y)
    local pH = panelCollapsed and CFG.titleHeight or CFG.panelHeight
    return x >= panelX and x <= panelX + CFG.panelWidth
       and y >= panelY and y <= panelY + pH
end

function widget:IsAbove(x, y)
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.MapZones == false then return false end
    return IsAbovePanel(x, y)
end

function widget:MousePress(x, y, button)
    -- Right-click cancels draw mode
    if button == 3 and mapZones.drawMode ~= "none" then
        CancelDraw()
        spEcho("[TotallyLegal MapZones] Drawing cancelled.")
        return true
    end

    if button ~= 1 then return false end

    -- Panel interaction
    if IsAbovePanel(x, y) then
        local pH = panelCollapsed and CFG.titleHeight or CFG.panelHeight
        local titleBot = panelY + pH - CFG.titleHeight

        -- Title bar
        if y >= titleBot then
            if x >= panelX + CFG.panelWidth - CFG.panelPadding - 28 then
                panelCollapsed = not panelCollapsed
                return true
            end
            isDragging = true
            dragOffsetX = x - panelX
            dragOffsetY = y - panelY
            return true
        end

        if panelCollapsed then return true end

        -- Button clicks
        local bx = panelX + CFG.panelPadding
        local bw = CFG.panelWidth - CFG.panelPadding * 2
        local by = panelY + CFG.panelPadding + 14  -- after status text

        -- Clear button
        if y >= by and y <= by + CFG.buttonHeight then
            ClearAll()
            return true
        end
        by = by + CFG.buttonHeight + CFG.buttonSpacing

        -- Draw buttons row
        local btn3W = (bw - CFG.buttonSpacing * 2) / 3
        if y >= by and y <= by + CFG.buttonHeight then
            if x >= bx and x <= bx + btn3W then
                if mapZones.drawMode == "building_area" then CancelDraw()
                else StartDrawBuildingArea() end
                return true
            elseif x >= bx + btn3W + CFG.buttonSpacing and x <= bx + btn3W * 2 + CFG.buttonSpacing then
                if mapZones.drawMode == "primary_line" then CancelDraw()
                else StartDrawPrimaryLine() end
                return true
            elseif x >= bx + (btn3W + CFG.buttonSpacing) * 2 then
                if mapZones.drawMode == "secondary_line" then CancelDraw()
                else StartDrawSecondaryLine() end
                return true
            end
        end

        return true
    end

    -- Map click during draw mode
    if mapZones.drawMode ~= "none" then
        local wx, wz = GetWorldPos(x, y)
        if not wx then return false end

        if drawClick == 0 then
            -- First click
            firstClickPos = { x = wx, z = wz }
            drawClick = 1

            if mapZones.drawMode == "building_area" then
                spEcho("[TotallyLegal MapZones] Center set. Click to define radius.")
            else
                spEcho("[TotallyLegal MapZones] Start set. Click to define end point.")
            end
            return true
        else
            -- Second click
            if mapZones.drawMode == "building_area" then
                mapZones.buildingArea.center.x = firstClickPos.x
                mapZones.buildingArea.center.z = firstClickPos.z
                mapZones.buildingArea.radius = mathSqrt(
                    (wx - firstClickPos.x)^2 + (wz - firstClickPos.z)^2)
                mapZones.buildingArea.defined = true
                spEcho("[TotallyLegal MapZones] Building area defined (radius: " ..
                       mathFloor(mapZones.buildingArea.radius) .. " elmos).")
            elseif mapZones.drawMode == "primary_line" then
                mapZones.primaryLine.p1.x = firstClickPos.x
                mapZones.primaryLine.p1.z = firstClickPos.z
                mapZones.primaryLine.p2.x = wx
                mapZones.primaryLine.p2.z = wz
                mapZones.primaryLine.defined = true
                spEcho("[TotallyLegal MapZones] Primary defense line defined.")
            elseif mapZones.drawMode == "secondary_line" then
                mapZones.secondaryLine.p1.x = firstClickPos.x
                mapZones.secondaryLine.p1.z = firstClickPos.z
                mapZones.secondaryLine.p2.x = wx
                mapZones.secondaryLine.p2.z = wz
                mapZones.secondaryLine.defined = true
                spEcho("[TotallyLegal MapZones] Secondary defense line defined.")
            end

            CancelDraw()
            return true
        end
    end

    return false
end

function widget:MouseMove(x, y, dx, dy, button)
    if isDragging then
        panelX = x - dragOffsetX
        panelY = y - dragOffsetY
        panelX = mathMax(0, mathMin(panelX, vsx - CFG.panelWidth))
        panelY = mathMax(0, mathMin(panelY, vsy - CFG.panelHeight))
        return true
    end

    -- Update preview position during draw mode
    if mapZones.drawMode ~= "none" and firstClickPos then
        local wx, wz = GetWorldPos(x, y)
        if wx then
            previewX, previewZ = wx, wz
        end
    end

    return false
end

function widget:MouseRelease(x, y, button)
    isDragging = false
    return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()

    if not WG.TotallyLegal then
        spEcho("[TotallyLegal MapZones] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal MapZones] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Position panel above BAR's bottom UI (build menu is ~200px tall)
    panelX = 20
    panelY = 280

    -- Expose state and API
    WG.TotallyLegal.MapZones = mapZones
    mapZones._ready = true
    WG.TotallyLegal.MapZonesAPI = {
        StartDrawBuildingArea  = StartDrawBuildingArea,
        StartDrawPrimaryLine   = StartDrawPrimaryLine,
        StartDrawSecondaryLine = StartDrawSecondaryLine,
        ClearBuildingArea      = ClearBuildingArea,
        ClearPrimaryLine       = ClearPrimaryLine,
        ClearSecondaryLine     = ClearSecondaryLine,
        ClearAll               = ClearAll,
        IsInsideBuildingArea   = IsInsideBuildingArea,
    }

    spEcho("[TotallyLegal MapZones] Map zone manager ready.")
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    panelX = mathMax(0, mathMin(panelX, vsx - CFG.panelWidth))
    panelY = mathMax(0, mathMin(panelY, vsy - CFG.panelHeight))
end

function widget:Shutdown()
    if WG.TotallyLegal then
        if WG.TotallyLegal.MapZones then
            WG.TotallyLegal.MapZones._ready = false
        end
        if WG.TotallyLegal.MapZonesAPI then
            WG.TotallyLegal.MapZonesAPI._ready = false
        end
    end
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return {
        panelX = panelX,
        panelY = panelY,
        panelCollapsed = panelCollapsed,
        buildingArea = mapZones.buildingArea.defined and {
            cx = mapZones.buildingArea.center.x,
            cz = mapZones.buildingArea.center.z,
            r  = mapZones.buildingArea.radius,
        } or nil,
        primaryLine = mapZones.primaryLine.defined and {
            p1x = mapZones.primaryLine.p1.x, p1z = mapZones.primaryLine.p1.z,
            p2x = mapZones.primaryLine.p2.x, p2z = mapZones.primaryLine.p2.z,
        } or nil,
        secondaryLine = mapZones.secondaryLine.defined and {
            p1x = mapZones.secondaryLine.p1.x, p1z = mapZones.secondaryLine.p1.z,
            p2x = mapZones.secondaryLine.p2.x, p2z = mapZones.secondaryLine.p2.z,
        } or nil,
    }
end

function widget:SetConfigData(data)
    if data.panelX then panelX = data.panelX end
    if data.panelY then panelY = data.panelY end
    if data.panelCollapsed ~= nil then panelCollapsed = data.panelCollapsed end
    if data.buildingArea then
        mapZones.buildingArea.center.x = data.buildingArea.cx
        mapZones.buildingArea.center.z = data.buildingArea.cz
        mapZones.buildingArea.radius = data.buildingArea.r
        mapZones.buildingArea.defined = true
    end
    if data.primaryLine then
        mapZones.primaryLine.p1.x = data.primaryLine.p1x
        mapZones.primaryLine.p1.z = data.primaryLine.p1z
        mapZones.primaryLine.p2.x = data.primaryLine.p2x
        mapZones.primaryLine.p2.z = data.primaryLine.p2z
        mapZones.primaryLine.defined = true
    end
    if data.secondaryLine then
        mapZones.secondaryLine.p1.x = data.secondaryLine.p1x
        mapZones.secondaryLine.p1.z = data.secondaryLine.p1z
        mapZones.secondaryLine.p2.x = data.secondaryLine.p2x
        mapZones.secondaryLine.p2.z = data.secondaryLine.p2z
        mapZones.secondaryLine.defined = true
    end
end
