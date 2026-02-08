-- TotallyLegal Overlay - PvP Information Widget for Beyond All Reason
-- A ranked-safe (read-only) overlay with resource breakdown, unit census, and build power dashboard.
-- No GiveOrder calls. No automation. Pure information.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Overlay",
        desc      = "PvP info overlay: resource breakdown, unit census, build power dashboard. Ranked-safe (read-only).",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 50,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references (widget-specific only)
--------------------------------------------------------------------------------

local spGetMyTeamID          = Spring.GetMyTeamID
local spGetUnitResources     = Spring.GetUnitResources
local spGetUnitIsBuilding    = Spring.GetUnitIsBuilding
local spGetUnitCommands      = Spring.GetUnitCommands
local spGetViewGeometry      = Spring.GetViewGeometry
local spGetGameFrame         = Spring.GetGameFrame

local glColor      = gl.Color
local glRect       = gl.Rect
local glText       = gl.Text
local glLineWidth  = gl.LineWidth
local glBeginEnd   = gl.BeginEnd
local glVertex     = gl.Vertex
local glDeleteList = gl.DeleteList
local GL_LINES     = GL.LINES

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local strFormat = string.format
local osClock   = os.clock

--------------------------------------------------------------------------------
-- Core library reference (set in Initialize)
--------------------------------------------------------------------------------

local TL = nil  -- WG.TotallyLegal

--------------------------------------------------------------------------------
-- Constants & configuration
--------------------------------------------------------------------------------

local FAST_UPDATE_INTERVAL = 0.5
local SLOW_UPDATE_INTERVAL = 2.0

local CFG = {
    windowWidth         = 330,
    titleBarHeight      = 26,
    sectionHeaderHeight = 22,
    dataRowHeight       = 17,
    totalRowHeight      = 20,
    sectionPadding      = 5,
    leftPadding         = 10,
    rightPadding        = 10,
    barHeight           = 14,
    barPadding          = 4,
    collapseButtonSize  = 14,
    titleFontSize       = 13,
    headerFontSize      = 11.5,
    dataFontSize        = 11,
    totalFontSize       = 11.5,
    panelGap            = 2,
}

local COL = {
    background    = { 0.05, 0.05, 0.08, 0.85 },
    titleBar      = { 0.10, 0.10, 0.16, 0.95 },
    titleText     = { 0.90, 0.90, 0.95, 1.0 },
    headerBg      = { 0.08, 0.08, 0.13, 0.90 },
    headerText    = { 0.70, 0.80, 0.90, 1.0 },
    labelText     = { 0.65, 0.65, 0.70, 1.0 },
    countText     = { 0.50, 0.55, 0.60, 1.0 },
    metalPos      = { 0.55, 0.80, 0.90, 1.0 },
    metalNeg      = { 0.90, 0.45, 0.45, 1.0 },
    energyPos     = { 1.00, 0.95, 0.35, 1.0 },
    energyNeg     = { 0.90, 0.45, 0.45, 1.0 },
    barBg         = { 0.15, 0.15, 0.20, 0.80 },
    barActive     = { 0.30, 0.75, 0.30, 0.90 },
    barIdle       = { 0.60, 0.60, 0.20, 0.70 },
    stallMetal    = { 1.00, 0.30, 0.30, 1.0 },
    stallEnergy   = { 1.00, 0.60, 0.00, 1.0 },
    warningBg     = { 0.40, 0.10, 0.10, 0.50 },
    totalBg       = { 0.10, 0.10, 0.15, 0.60 },
    totalText     = { 0.95, 0.95, 1.00, 1.0 },
    separator     = { 0.30, 0.30, 0.40, 0.30 },
    collapseIcon  = { 0.60, 0.60, 0.70, 0.80 },
    rowAlt        = { 0.07, 0.07, 0.11, 0.85 },
}

--------------------------------------------------------------------------------
-- Resource & census category definitions
--------------------------------------------------------------------------------

local RESOURCE_CAT_ORDER = {
    "mex", "adv_mex", "wind", "solar", "adv_solar",
    "geo", "tidal", "fusion", "converter", "adv_converter",
}
local RESOURCE_CAT_LABELS = {
    mex           = "Metal Extractors",
    adv_mex       = "Adv. Metal Ext.",
    wind          = "Wind Turbines",
    solar         = "Solar Collectors",
    adv_solar     = "Adv. Solar",
    geo           = "Geothermal",
    tidal         = "Tidal Generators",
    fusion        = "Fusion Reactors",
    converter     = "Converters",
    adv_converter = "Adv. Converters",
}

local CENSUS_CAT_ORDER = {
    "economy", "factory", "builder",
    "bot_combat", "vehicle_combat", "aircraft", "ship",
    "defense", "utility",
}
local CENSUS_CAT_LABELS = {
    economy        = "Economy",
    factory        = "Factories",
    builder        = "Builders",
    bot_combat     = "Combat Bots",
    vehicle_combat = "Combat Vehicles",
    aircraft       = "Aircraft",
    ship           = "Ships",
    defense        = "Defenses",
    utility        = "Utility",
}

--------------------------------------------------------------------------------
-- State variables
--------------------------------------------------------------------------------

-- Window
local windowX = 100
local windowY = 300
local windowW = CFG.windowWidth
local windowH = 400
local isDragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local vsx, vsy = 0, 0

-- Panels
local panelExpanded = { true, true, true }
local panelNames = { "Resource Production", "Unit Census", "Build Power" }

-- Data
local resourceData = {}
local teamResources = { metalIncome = 0, energyIncome = 0, metalCurrent = 0, energyCurrent = 0, metalStorage = 1, energyStorage = 1 }

local censusData = {}
local censusTotals = {}
local totalArmyValue = 0
local totalUnitCount = 0

local buildPowerData = {
    totalBP = 0, activeBP = 0, idleBP = 0,
    idleBuilders = {},
    stallingMetal = false, stallingEnergy = false,
}

-- Timing
local lastFastUpdate = 0
local lastSlowUpdate = 0

-- Display lists
local dlistBg = nil
local dlistContent = nil

-- Computed layout positions
local panelPositions = {}

--------------------------------------------------------------------------------
-- Data collection (uses WG.TotallyLegal for classification and unit tracking)
--------------------------------------------------------------------------------

local function CollectResourceData()
    for _, cat in ipairs(RESOURCE_CAT_ORDER) do
        resourceData[cat] = { count = 0, metal = 0, energy = 0 }
    end
    resourceData["other"] = { count = 0, metal = 0, energy = 0 }

    local res = TL.GetTeamResources()
    teamResources.metalIncome  = res.metalIncome
    teamResources.energyIncome = res.energyIncome
    teamResources.metalCurrent = res.metalCurrent
    teamResources.energyCurrent = res.energyCurrent
    teamResources.metalStorage = res.metalStorage
    teamResources.energyStorage = res.energyStorage

    local accountedMetal = 0
    local accountedEnergy = 0
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.resource then
            local cat = cls.resource
            local entry = resourceData[cat]
            if entry then
                entry.count = entry.count + 1
                local mMake, mUse, eMake, eUse = spGetUnitResources(uid)
                if mMake then
                    entry.metal = entry.metal + mMake
                    accountedMetal = accountedMetal + mMake
                end
                if eMake then
                    entry.energy = entry.energy + eMake
                    accountedEnergy = accountedEnergy + eMake
                end
            end
        end
    end

    resourceData["other"].metal  = mathMax(0, (res.metalIncome) - accountedMetal)
    resourceData["other"].energy = mathMax(0, (res.energyIncome) - accountedEnergy)
end

local function CollectUnitCensus()
    for _, cat in ipairs(CENSUS_CAT_ORDER) do
        censusData[cat] = {}
        censusTotals[cat] = { count = 0, metalValue = 0 }
    end

    totalArmyValue = 0
    totalUnitCount = 0
    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.census then
            local cat = cls.census
            if censusTotals[cat] then
                censusData[cat][defID] = (censusData[cat][defID] or 0) + 1
                censusTotals[cat].count = censusTotals[cat].count + 1
                censusTotals[cat].metalValue = censusTotals[cat].metalValue + (cls.metalCost or 0)
            end
        end
        totalUnitCount = totalUnitCount + 1
        totalArmyValue = totalArmyValue + ((cls and cls.metalCost) or 0)
    end
end

local function CollectBuildPowerData()
    buildPowerData.totalBP = 0
    buildPowerData.activeBP = 0
    buildPowerData.idleBP = 0
    buildPowerData.idleBuilders = {}

    local res = TL.GetTeamResources()
    buildPowerData.stallingMetal  = (res.metalCurrent / res.metalStorage) < 0.03
    buildPowerData.stallingEnergy = (res.energyCurrent / res.energyStorage) < 0.03

    local myUnits = TL.GetMyUnits()

    for uid, defID in pairs(myUnits) do
        local cls = TL.GetUnitClass(defID)
        if cls and cls.buildSpeed > 0 then
            buildPowerData.totalBP = buildPowerData.totalBP + cls.buildSpeed

            local buildTarget = spGetUnitIsBuilding(uid)
            if buildTarget then
                buildPowerData.activeBP = buildPowerData.activeBP + cls.buildSpeed
            else
                buildPowerData.idleBP = buildPowerData.idleBP + cls.buildSpeed
                if not cls.isFactory then
                    local cmdCount = spGetUnitCommands(uid, 0)
                    if cmdCount == 0 then
                        buildPowerData.idleBuilders[#buildPowerData.idleBuilders + 1] = {
                            defID = defID, unitID = uid, bp = cls.buildSpeed
                        }
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Layout calculation
--------------------------------------------------------------------------------

local function GetPanelContentHeight(panelIndex)
    if panelIndex == 1 then
        local rows = 0
        for _, cat in ipairs(RESOURCE_CAT_ORDER) do
            if resourceData[cat] and resourceData[cat].count > 0 then
                rows = rows + 1
            end
        end
        if resourceData["other"] and (resourceData["other"].metal > 0.05 or resourceData["other"].energy > 0.05) then
            rows = rows + 1
        end
        rows = rows + 1
        return rows * CFG.dataRowHeight + CFG.totalRowHeight + CFG.sectionPadding * 2

    elseif panelIndex == 2 then
        local rows = 0
        for _, cat in ipairs(CENSUS_CAT_ORDER) do
            if censusTotals[cat] and censusTotals[cat].count > 0 then
                rows = rows + 1
            end
        end
        rows = rows + 1
        return rows * CFG.dataRowHeight + CFG.totalRowHeight + CFG.sectionPadding * 2

    elseif panelIndex == 3 then
        local rows = 4
        if buildPowerData.stallingMetal then rows = rows + 1 end
        if buildPowerData.stallingEnergy then rows = rows + 1 end
        if #buildPowerData.idleBuilders > 0 then
            rows = rows + 1
            local grouped = {}
            for _, b in ipairs(buildPowerData.idleBuilders) do
                grouped[b.defID] = (grouped[b.defID] or 0) + 1
            end
            for _ in pairs(grouped) do
                rows = rows + 1
            end
        end
        return rows * CFG.dataRowHeight + CFG.sectionPadding * 2
    end
    return 0
end

local function CalculateWindowHeight()
    local h = CFG.titleBarHeight
    for i = 1, 3 do
        h = h + CFG.sectionHeaderHeight
        if panelExpanded[i] then
            h = h + GetPanelContentHeight(i)
        end
        h = h + CFG.panelGap
    end
    return h
end

local function CalculatePanelPositions()
    panelPositions = {}
    local y = windowY + windowH - CFG.titleBarHeight
    for i = 1, 3 do
        local headerTop = y
        local headerBot = y - CFG.sectionHeaderHeight
        local contentBot = headerBot
        if panelExpanded[i] then
            contentBot = headerBot - GetPanelContentHeight(i)
        end
        panelPositions[i] = {
            headerTop = headerTop,
            headerBot = headerBot,
            contentTop = headerBot,
            contentBot = contentBot,
        }
        y = contentBot - CFG.panelGap
    end
end

--------------------------------------------------------------------------------
-- Rendering helpers (local wrappers using core lib)
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end
local function DrawFilledRect(x1, y1, x2, y2) glRect(x1, y1, x2, y2) end

local function DrawHLine(x1, x2, y, c)
    SetColor(c)
    glLineWidth(1)
    glBeginEnd(GL_LINES, function()
        glVertex(x1, y, 0)
        glVertex(x2, y, 0)
    end)
end

local function DrawDataRowBg(x1, y1, x2, y2, isAlt)
    if isAlt then
        SetColor(COL.rowAlt)
    else
        SetColor(COL.background)
    end
    DrawFilledRect(x1, y1, x2, y2)
end

local FormatRate = nil
local FormatInt = nil
local FormatBP = nil

--------------------------------------------------------------------------------
-- Panel rendering: Resources
--------------------------------------------------------------------------------

local function DrawResourcePanel()
    local pp = panelPositions[1]
    if not pp or not panelExpanded[1] then return end

    local x = windowX + CFG.leftPadding
    local rEdge = windowX + windowW - CFG.rightPadding
    local y = pp.contentTop - CFG.sectionPadding
    local colCount = windowX + 170
    local colMetal = windowX + 210
    local colEnergy = windowX + 270

    local rowIdx = 0

    for _, cat in ipairs(RESOURCE_CAT_ORDER) do
        local d = resourceData[cat]
        if d and d.count > 0 then
            local ry = y - CFG.dataRowHeight
            DrawDataRowBg(windowX, ry, windowX + windowW, y, rowIdx % 2 == 1)

            SetColor(COL.labelText)
            glText(RESOURCE_CAT_LABELS[cat] or cat, x, ry + 3, CFG.dataFontSize, "o")

            SetColor(COL.countText)
            glText("(" .. d.count .. ")", colCount, ry + 3, CFG.dataFontSize, "o")

            if d.metal > 0.01 then
                SetColor(COL.metalPos)
                glText(FormatRate(d.metal) .. " M", colMetal, ry + 3, CFG.dataFontSize, "or")
            end

            if d.energy > 0.01 then
                SetColor(COL.energyPos)
                glText(FormatRate(d.energy) .. " E", colEnergy, ry + 3, CFG.dataFontSize, "or")
            end

            y = ry
            rowIdx = rowIdx + 1
        end
    end

    -- Other / Reclaim row
    local otherD = resourceData["other"]
    if otherD and (otherD.metal > 0.05 or otherD.energy > 0.05) then
        local ry = y - CFG.dataRowHeight
        DrawDataRowBg(windowX, ry, windowX + windowW, y, rowIdx % 2 == 1)

        SetColor(COL.labelText)
        glText("Other / Reclaim", x, ry + 3, CFG.dataFontSize, "o")

        if otherD.metal > 0.05 then
            SetColor(COL.metalPos)
            glText(FormatRate(otherD.metal) .. " M", colMetal, ry + 3, CFG.dataFontSize, "or")
        end
        if otherD.energy > 0.05 then
            SetColor(COL.energyPos)
            glText(FormatRate(otherD.energy) .. " E", colEnergy, ry + 3, CFG.dataFontSize, "or")
        end

        y = ry
        rowIdx = rowIdx + 1
    end

    DrawHLine(windowX + 5, windowX + windowW - 5, y, COL.separator)

    -- Total row
    local ry = y - CFG.totalRowHeight
    SetColor(COL.totalBg)
    DrawFilledRect(windowX, ry, windowX + windowW, y)

    SetColor(COL.totalText)
    glText("TOTAL", x, ry + 4, CFG.totalFontSize, "oB")

    SetColor(COL.metalPos)
    glText(FormatRate(teamResources.metalIncome) .. " M/s", colMetal, ry + 4, CFG.totalFontSize, "or")

    SetColor(COL.energyPos)
    glText(FormatRate(teamResources.energyIncome) .. " E/s", colEnergy, ry + 4, CFG.totalFontSize, "or")
end

--------------------------------------------------------------------------------
-- Panel rendering: Unit Census
--------------------------------------------------------------------------------

local function DrawCensusPanel()
    local pp = panelPositions[2]
    if not pp or not panelExpanded[2] then return end

    local x = windowX + CFG.leftPadding
    local rEdge = windowX + windowW - CFG.rightPadding
    local y = pp.contentTop - CFG.sectionPadding
    local colCount = windowX + 200
    local colValue = windowX + windowW - CFG.rightPadding

    local rowIdx = 0

    for _, cat in ipairs(CENSUS_CAT_ORDER) do
        local t = censusTotals[cat]
        if t and t.count > 0 then
            local ry = y - CFG.dataRowHeight
            DrawDataRowBg(windowX, ry, windowX + windowW, y, rowIdx % 2 == 1)

            SetColor(COL.labelText)
            glText(CENSUS_CAT_LABELS[cat] or cat, x, ry + 3, CFG.dataFontSize, "o")

            SetColor(COL.countText)
            glText("(" .. t.count .. ")", colCount, ry + 3, CFG.dataFontSize, "o")

            SetColor(COL.metalPos)
            glText(FormatInt(t.metalValue) .. " M", colValue, ry + 3, CFG.dataFontSize, "or")

            y = ry
            rowIdx = rowIdx + 1
        end
    end

    DrawHLine(windowX + 5, windowX + windowW - 5, y, COL.separator)

    -- Total row
    local ry = y - CFG.totalRowHeight
    SetColor(COL.totalBg)
    DrawFilledRect(windowX, ry, windowX + windowW, y)

    SetColor(COL.totalText)
    glText("TOTAL (" .. totalUnitCount .. " units)", x, ry + 4, CFG.totalFontSize, "oB")

    SetColor(COL.metalPos)
    glText(FormatInt(totalArmyValue) .. " M", colValue, ry + 4, CFG.totalFontSize, "or")
end

--------------------------------------------------------------------------------
-- Panel rendering: Build Power
--------------------------------------------------------------------------------

local function DrawBuildPowerPanel()
    local pp = panelPositions[3]
    if not pp or not panelExpanded[3] then return end

    local x = windowX + CFG.leftPadding
    local rEdge = windowX + windowW - CFG.rightPadding
    local y = pp.contentTop - CFG.sectionPadding

    local totalBP  = buildPowerData.totalBP
    local activeBP = buildPowerData.activeBP
    local idleBP   = buildPowerData.idleBP

    -- Total BP text
    local ry = y - CFG.dataRowHeight
    SetColor(COL.labelText)
    glText("Total Build Power:", x, ry + 3, CFG.dataFontSize, "o")
    SetColor(COL.totalText)
    glText(FormatBP(totalBP), rEdge, ry + 3, CFG.dataFontSize, "or")
    y = ry

    -- Progress bar
    ry = y - CFG.barHeight - CFG.barPadding * 2
    local barX1 = x
    local barX2 = rEdge
    local barY1 = ry + CFG.barPadding
    local barY2 = y - CFG.barPadding
    local barW = barX2 - barX1

    SetColor(COL.barBg)
    DrawFilledRect(barX1, barY1, barX2, barY2)

    if totalBP > 0 then
        local activeFrac = activeBP / totalBP
        local idleFrac = idleBP / totalBP

        SetColor(COL.barActive)
        DrawFilledRect(barX1, barY1, barX1 + barW * activeFrac, barY2)

        SetColor(COL.barIdle)
        DrawFilledRect(barX1 + barW * activeFrac, barY1, barX1 + barW * (activeFrac + idleFrac), barY2)

        local pct = mathFloor(activeBP / totalBP * 100 + 0.5)
        SetColor(COL.titleText)
        local barMidX = (barX1 + barX2) / 2
        local barMidY = (barY1 + barY2) / 2 - 4
        glText(pct .. "% active", barMidX, barMidY, CFG.dataFontSize - 1, "ocB")
    end
    y = ry

    -- Active / Idle text rows
    ry = y - CFG.dataRowHeight
    SetColor(COL.barActive)
    glText("Active:", x, ry + 3, CFG.dataFontSize, "o")
    SetColor(COL.totalText)
    glText(FormatBP(activeBP) .. " BP", rEdge, ry + 3, CFG.dataFontSize, "or")
    y = ry

    ry = y - CFG.dataRowHeight
    SetColor(COL.barIdle)
    glText("Idle:", x, ry + 3, CFG.dataFontSize, "o")
    SetColor(COL.totalText)
    glText(FormatBP(idleBP) .. " BP", rEdge, ry + 3, CFG.dataFontSize, "or")
    y = ry

    -- Stalling warnings
    local now = osClock()
    local flash = (mathFloor(now * 2) % 2 == 0)

    if buildPowerData.stallingMetal then
        ry = y - CFG.dataRowHeight
        if flash then
            SetColor(COL.warningBg)
            DrawFilledRect(windowX, ry, windowX + windowW, y)
            SetColor(COL.stallMetal)
            glText("!! STALLING METAL", x, ry + 3, CFG.dataFontSize, "oB")
        end
        y = ry
    end

    if buildPowerData.stallingEnergy then
        ry = y - CFG.dataRowHeight
        if flash then
            SetColor(COL.warningBg)
            DrawFilledRect(windowX, ry, windowX + windowW, y)
            SetColor(COL.stallEnergy)
            glText("!! STALLING ENERGY", x, ry + 3, CFG.dataFontSize, "oB")
        end
        y = ry
    end

    -- Idle builders list
    if #buildPowerData.idleBuilders > 0 then
        DrawHLine(windowX + 5, windowX + windowW - 5, y, COL.separator)
        ry = y - CFG.dataRowHeight
        SetColor(COL.headerText)
        glText("Idle Builders:", x, ry + 3, CFG.dataFontSize, "oB")
        y = ry

        local grouped = {}
        local groupOrder = {}
        for _, b in ipairs(buildPowerData.idleBuilders) do
            if not grouped[b.defID] then
                grouped[b.defID] = { count = 0, bp = b.bp }
                groupOrder[#groupOrder + 1] = b.defID
            end
            grouped[b.defID].count = grouped[b.defID].count + 1
        end

        for _, defID in ipairs(groupOrder) do
            local g = grouped[defID]
            local def = UnitDefs[defID]
            local name = def and def.humanName or "Unknown"

            ry = y - CFG.dataRowHeight
            SetColor(COL.labelText)
            local txt = "  " .. name
            if g.count > 1 then
                txt = txt .. " x" .. g.count
            end
            glText(txt, x, ry + 3, CFG.dataFontSize - 0.5, "o")

            SetColor(COL.countText)
            glText(FormatBP(g.bp * g.count) .. " BP", rEdge, ry + 3, CFG.dataFontSize - 0.5, "or")

            y = ry
        end
    end
end

--------------------------------------------------------------------------------
-- Main rendering
--------------------------------------------------------------------------------

local function DrawWindowBackground()
    SetColor(COL.titleBar)
    DrawFilledRect(windowX, windowY + windowH - CFG.titleBarHeight, windowX + windowW, windowY + windowH)

    SetColor(COL.titleText)
    glText("TotallyLegal Overlay", windowX + CFG.leftPadding, windowY + windowH - CFG.titleBarHeight + 7, CFG.titleFontSize, "oB")

    for i = 1, 3 do
        local pp = panelPositions[i]
        if not pp then break end

        SetColor(COL.headerBg)
        DrawFilledRect(windowX, pp.headerBot, windowX + windowW, pp.headerTop)

        SetColor(COL.headerText)
        glText(panelNames[i], windowX + CFG.leftPadding, pp.headerBot + 5, CFG.headerFontSize, "oB")

        local btnX = windowX + windowW - CFG.rightPadding - CFG.collapseButtonSize
        local btnY = pp.headerBot + 4
        SetColor(COL.collapseIcon)
        local icon = panelExpanded[i] and "[-]" or "[+]"
        glText(icon, btnX, btnY, CFG.headerFontSize, "o")

        if panelExpanded[i] then
            SetColor(COL.background)
            DrawFilledRect(windowX, pp.contentBot, windowX + windowW, pp.contentTop)
        end
    end
end

local function DrawWindowContent()
    DrawResourcePanel()
    DrawCensusPanel()
    DrawBuildPowerPanel()
end

function widget:DrawScreen()
    if not TL then return end

    windowH = CalculateWindowHeight()
    CalculatePanelPositions()

    DrawWindowBackground()
    DrawWindowContent()
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:IsAbove(x, y)
    return x >= windowX and x <= windowX + windowW
       and y >= windowY and y <= windowY + windowH
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    if not self:IsAbove(x, y) then return false end

    -- Check collapse buttons first (only interactive elements)
    for i = 1, 3 do
        local pp = panelPositions[i]
        if pp then
            local btnX = windowX + windowW - CFG.rightPadding - CFG.collapseButtonSize - 5
            local btnX2 = windowX + windowW - CFG.rightPadding + 5
            local btnY = pp.headerBot
            local btnY2 = pp.headerTop
            if x >= btnX and x <= btnX2 and y >= btnY and y <= btnY2 then
                panelExpanded[i] = not panelExpanded[i]
                return true
            end
        end
    end

    -- Any other click on the widget starts a drag
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

    -- Wait for core library
    if not WG.TotallyLegal then
        Spring.Echo("[TotallyLegal Overlay] ERROR: Core library not loaded. Enable lib_totallylegal_core first.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal
    FormatRate = TL.FormatRate
    FormatInt = TL.FormatInt
    FormatBP = TL.FormatBP

    windowX = vsx - windowW - 20
    windowY = vsy / 2

    if spGetGameFrame() > 0 then
        CollectResourceData()
        CollectUnitCensus()
        CollectBuildPowerData()
    end
end

function widget:Update(dt)
    if not TL then return end

    local now = osClock()

    if now - lastFastUpdate >= FAST_UPDATE_INTERVAL then
        lastFastUpdate = now
        CollectResourceData()
        CollectBuildPowerData()
    end

    if now - lastSlowUpdate >= SLOW_UPDATE_INTERVAL then
        lastSlowUpdate = now
        CollectUnitCensus()
    end
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    windowX = mathMax(0, mathMin(windowX, vsx - windowW))
    windowY = mathMax(0, mathMin(windowY, vsy - windowH))
end

function widget:Shutdown()
    if dlistBg then glDeleteList(dlistBg) end
    if dlistContent then glDeleteList(dlistContent) end
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return {
        windowX = windowX,
        windowY = windowY,
        panelExpanded1 = panelExpanded[1],
        panelExpanded2 = panelExpanded[2],
        panelExpanded3 = panelExpanded[3],
    }
end

function widget:SetConfigData(data)
    if data.windowX then windowX = data.windowX end
    if data.windowY then windowY = data.windowY end
    if data.panelExpanded1 ~= nil then panelExpanded[1] = data.panelExpanded1 end
    if data.panelExpanded2 ~= nil then panelExpanded[2] = data.panelExpanded2 end
    if data.panelExpanded3 ~= nil then panelExpanded[3] = data.panelExpanded3 end
end
