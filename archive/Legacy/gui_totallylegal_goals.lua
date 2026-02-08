-- TotallyLegal Goal Queue UI Panel - Goal management interface
-- Displays goal queue with progress, resource allocation sliders, add/remove/reorder goals.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua, engine_totallylegal_goals.lua

function widget:GetInfo()
    return {
        name      = "TotallyLegal Goal Panel",
        desc      = "Goal queue management UI: resource allocation sliders, goal list, add/remove. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 54,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetViewGeometry = Spring.GetViewGeometry
local spGetGameFrame    = Spring.GetGameFrame
local spEcho            = Spring.Echo

local glColor    = gl.Color
local glRect     = gl.Rect
local glText     = gl.Text
local glLineWidth = gl.LineWidth

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local GoalsAPI = nil

--------------------------------------------------------------------------------
-- UI Configuration
--------------------------------------------------------------------------------

local CFG = {
    windowWidth    = 320,
    titleHeight    = 26,
    sectionHeight  = 20,
    rowHeight      = 22,
    sliderHeight   = 14,
    sliderLabelH   = 16,
    padding        = 10,
    innerPad       = 6,
    fontSize       = 9,
    titleFontSize  = 11,
    labelFontSize  = 9,
    buttonWidth    = 100,
    buttonHeight   = 18,
    progressBarH   = 10,
    goalRowHeight  = 28,
    maxVisibleGoals = 8,
}

local COL = {
    background  = { 0.05, 0.05, 0.08, 0.88 },
    titleBar    = { 0.12, 0.15, 0.25, 0.95 },
    titleText   = { 0.90, 0.90, 0.95, 1.0 },
    labelText   = { 0.65, 0.65, 0.70, 1.0 },
    valueText   = { 0.85, 0.90, 0.95, 1.0 },
    sectionBg   = { 0.08, 0.10, 0.15, 0.80 },
    sectionText = { 0.70, 0.75, 0.85, 1.0 },
    buttonBg    = { 0.15, 0.20, 0.30, 0.85 },
    buttonHover = { 0.20, 0.30, 0.45, 0.90 },
    buttonText  = { 0.85, 0.90, 0.95, 1.0 },
    sliderBg    = { 0.15, 0.15, 0.20, 0.80 },
    sliderFill  = { 0.30, 0.55, 0.80, 0.90 },
    sliderKnob  = { 0.70, 0.80, 0.90, 1.0 },
    separator   = { 0.30, 0.30, 0.40, 0.30 },
    progressBg  = { 0.12, 0.12, 0.15, 0.80 },
    progressFill = { 0.25, 0.65, 0.35, 0.90 },
    progressStall = { 0.80, 0.50, 0.20, 0.90 },
    activeGoal  = { 0.30, 0.75, 0.30, 1.0 },
    pendingGoal = { 0.50, 0.50, 0.55, 1.0 },
    completedGoal = { 0.35, 0.35, 0.40, 0.60 },
    removeBtn   = { 0.70, 0.25, 0.25, 0.90 },
    arrowBtn    = { 0.40, 0.45, 0.55, 0.80 },
    checkboxOn  = { 0.30, 0.75, 0.30, 1.0 },
    checkboxOff = { 0.40, 0.40, 0.45, 0.80 },
    popupBg     = { 0.10, 0.12, 0.18, 0.95 },
}

--------------------------------------------------------------------------------
-- Window state
--------------------------------------------------------------------------------

local windowX = 20
local windowY = 100
local windowW = CFG.windowWidth
local windowH = 400
local vsx, vsy = 0, 0

local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0
local collapsed = false

-- Slider dragging state
local sliderDragging = nil  -- "econVsUnits" | "savings" | "teamShare" | "projectFunding" | nil

-- UI mode
local uiMode = "normal"  -- "normal" | "adding" | "preset_select"

-- Add-goal form state
local addForm = {
    goalType  = "unit_production",
    role      = "assault",
    count     = 5,
    destination = "front",
    buildKey  = "fusion",
    metric    = "metalIncome",
    threshold = 20,
    techLevel = 2,
    factoryType = "bot",
    bpTarget  = 300,
}

-- Goal type display names
local GOAL_TYPE_LABELS = {
    unit_production  = "Unit Production",
    structure_build  = "Structure Build",
    structure_place  = "Place Structure",
    economy_target   = "Economy Target",
    tech_transition  = "Tech Transition",
    buildpower_target = "Build Power",
}

local GOAL_TYPE_ORDER = {
    "unit_production", "structure_build", "structure_place",
    "economy_target", "tech_transition", "buildpower_target",
}

--------------------------------------------------------------------------------
-- Helper: cycle through options
--------------------------------------------------------------------------------

local function CycleOption(current, options)
    for i, opt in ipairs(options) do
        if opt == current then
            return options[(i % #options) + 1]
        end
    end
    return options[1]
end

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end

--------------------------------------------------------------------------------
-- Rendering: Sliders
--------------------------------------------------------------------------------

local function DrawSlider(x, y, w, h, value, minVal, maxVal, label, valueStr)
    -- Label
    SetColor(COL.labelText)
    glText(label, x, y + h + 1, CFG.labelFontSize, "o")

    -- Value text
    SetColor(COL.valueText)
    glText(valueStr or tostring(mathFloor(value)), x + w, y + h + 1, CFG.labelFontSize, "or")

    -- Track
    SetColor(COL.sliderBg)
    glRect(x, y, x + w, y + h)

    -- Fill
    local frac = (value - minVal) / mathMax(maxVal - minVal, 1)
    SetColor(COL.sliderFill)
    glRect(x, y, x + w * frac, y + h)

    -- Knob
    local knobX = x + w * frac
    SetColor(COL.sliderKnob)
    glRect(knobX - 2, y - 1, knobX + 2, y + h + 1)
end

--------------------------------------------------------------------------------
-- Rendering: Buttons
--------------------------------------------------------------------------------

local function DrawButton(x, y, w, h, label, color)
    SetColor(color or COL.buttonBg)
    glRect(x, y, x + w, y + h)
    SetColor(COL.buttonText)
    glText(label, x + w / 2, y + 3, CFG.fontSize, "ocB")
end

local function DrawSmallButton(x, y, w, h, label, color)
    SetColor(color or COL.arrowBtn)
    glRect(x, y, x + w, y + h)
    SetColor(COL.buttonText)
    glText(label, x + w / 2, y + 2, CFG.fontSize - 1, "oc")
end

--------------------------------------------------------------------------------
-- Rendering: Progress bar
--------------------------------------------------------------------------------

local function DrawProgressBar(x, y, w, h, current, total, stalled)
    SetColor(COL.progressBg)
    glRect(x, y, x + w, y + h)

    if total > 0 then
        local frac = mathMin(1, current / total)
        SetColor(stalled and COL.progressStall or COL.progressFill)
        glRect(x, y, x + w * frac, y + h)
    end
end

--------------------------------------------------------------------------------
-- Rendering: Goal row
--------------------------------------------------------------------------------

local function DrawGoalRow(x, y, w, goal, index)
    local h = CFG.goalRowHeight

    -- Status indicator
    local statusColor
    if goal.status == "active" then statusColor = COL.activeGoal
    elseif goal.status == "completed" then statusColor = COL.completedGoal
    else statusColor = COL.pendingGoal end

    -- Status dot
    SetColor(statusColor)
    glRect(x + 2, y + h/2 - 3, x + 8, y + h/2 + 3)

    -- Goal name
    local typeName = GOAL_TYPE_LABELS[goal.goalType] or goal.goalType
    local goalName = ""
    if goal.goalType == "unit_production" then
        goalName = (goal.target.count or "?") .. "x " .. (goal.target.role or "?")
        if goal.target.destination then
            goalName = goalName .. " -> " .. goal.target.destination
        end
    elseif goal.goalType == "structure_build" then
        goalName = (goal.target.count or "?") .. "x " .. (goal.target.buildKey or "?")
    elseif goal.goalType == "structure_place" then
        goalName = (goal.target.buildKey or "?")
        if goal.target.position then
            goalName = goalName .. " @(" .. mathFloor(goal.target.position[1]) .. "," .. mathFloor(goal.target.position[2]) .. ")"
        else
            goalName = goalName .. " (no pos)"
        end
    elseif goal.goalType == "economy_target" then
        goalName = (goal.target.metric or "?") .. " >= " .. (goal.target.threshold or "?")
    elseif goal.goalType == "tech_transition" then
        goalName = "T" .. (goal.target.techLevel or "?")
        if goal.target.factoryType then goalName = goalName .. " " .. goal.target.factoryType end
    elseif goal.goalType == "buildpower_target" then
        goalName = "BP >= " .. (goal.target.bpTarget or "?")
    end

    SetColor(statusColor)
    glText(index .. ".", x + 12, y + h - 8, CFG.fontSize, "o")
    SetColor(COL.valueText)
    glText(goalName, x + 26, y + h - 8, CFG.fontSize, "o")

    -- Progress bar
    local progX = x + 26
    local progW = w - 80
    if goal.progress and goal.progress.total > 0 then
        local pct = mathMin(100, mathFloor((goal.progress.current / goal.progress.total) * 100))
        DrawProgressBar(progX, y + 2, progW, CFG.progressBarH, goal.progress.current, goal.progress.total, goal._stalled)
        SetColor(COL.labelText)
        glText(pct .. "%", progX + progW + 4, y + 2, CFG.fontSize - 1, "o")
    end

    -- Up/down arrows
    local arrowW = 14
    local arrowH = 12
    local arrowX = x + w - 50
    DrawSmallButton(arrowX, y + h/2, arrowW, arrowH, "^", COL.arrowBtn)
    DrawSmallButton(arrowX + arrowW + 2, y + h/2, arrowW, arrowH, "v", COL.arrowBtn)

    -- Remove button
    DrawSmallButton(x + w - 18, y + h/2, 14, arrowH, "x", COL.removeBtn)
end

--------------------------------------------------------------------------------
-- Rendering: Add goal form
--------------------------------------------------------------------------------

local function DrawAddForm(x, y, w)
    local h = 0
    local rowH = CFG.rowHeight

    SetColor(COL.popupBg)
    local formHeight = 5 * rowH + CFG.padding * 2
    glRect(x, y - formHeight, x + w, y)
    h = formHeight

    local ry = y - CFG.padding

    -- Goal type
    ry = ry - rowH
    SetColor(COL.labelText)
    glText("Type:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
    DrawButton(x + 70, ry + 1, 140, 16, GOAL_TYPE_LABELS[addForm.goalType] or addForm.goalType)

    -- Context-sensitive fields
    ry = ry - rowH
    if addForm.goalType == "unit_production" then
        SetColor(COL.labelText)
        glText("Role:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 90, 16, addForm.role)

        ry = ry - rowH
        SetColor(COL.labelText)
        glText("Count:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawSmallButton(x + 70, ry + 2, 16, 14, "-")
        SetColor(COL.valueText)
        glText(tostring(addForm.count), x + 95, ry + 5, CFG.labelFontSize, "oc")
        DrawSmallButton(x + 106, ry + 2, 16, 14, "+")

        ry = ry - rowH
        SetColor(COL.labelText)
        glText("Dest:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 90, 16, addForm.destination)

    elseif addForm.goalType == "structure_build" then
        SetColor(COL.labelText)
        glText("Build:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 90, 16, addForm.buildKey)

        ry = ry - rowH
        SetColor(COL.labelText)
        glText("Count:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawSmallButton(x + 70, ry + 2, 16, 14, "-")
        SetColor(COL.valueText)
        glText(tostring(addForm.count), x + 95, ry + 5, CFG.labelFontSize, "oc")
        DrawSmallButton(x + 106, ry + 2, 16, 14, "+")

    elseif addForm.goalType == "economy_target" then
        SetColor(COL.labelText)
        glText("Metric:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 110, 16, addForm.metric)

        ry = ry - rowH
        SetColor(COL.labelText)
        glText("Target:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawSmallButton(x + 70, ry + 2, 16, 14, "-")
        SetColor(COL.valueText)
        glText(tostring(addForm.threshold), x + 98, ry + 5, CFG.labelFontSize, "oc")
        DrawSmallButton(x + 114, ry + 2, 16, 14, "+")

    elseif addForm.goalType == "tech_transition" then
        SetColor(COL.labelText)
        glText("Tech:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 50, 16, "T" .. addForm.techLevel)

        ry = ry - rowH
        SetColor(COL.labelText)
        glText("Factory:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawButton(x + 70, ry + 1, 90, 16, addForm.factoryType)

    elseif addForm.goalType == "buildpower_target" then
        SetColor(COL.labelText)
        glText("BP Target:", x + CFG.innerPad, ry + 5, CFG.labelFontSize, "o")
        DrawSmallButton(x + 80, ry + 2, 16, 14, "-")
        SetColor(COL.valueText)
        glText(tostring(addForm.bpTarget), x + 108, ry + 5, CFG.labelFontSize, "oc")
        DrawSmallButton(x + 124, ry + 2, 16, 14, "+")
    end

    -- Confirm / Cancel buttons
    ry = y - formHeight + CFG.padding
    DrawButton(x + CFG.innerPad, ry, 70, 16, "Confirm", COL.activeGoal)
    DrawButton(x + 80 + CFG.innerPad, ry, 60, 16, "Cancel", COL.removeBtn)

    return h
end

--------------------------------------------------------------------------------
-- Rendering: Preset list
--------------------------------------------------------------------------------

local function DrawPresetList(x, y, w)
    local presets = GoalsAPI and GoalsAPI.GetPresets() or {}
    local rowH = CFG.rowHeight
    local h = #presets * rowH + CFG.padding * 2

    SetColor(COL.popupBg)
    glRect(x, y - h, x + w, y)

    local ry = y - CFG.padding
    for i, preset in ipairs(presets) do
        ry = ry - rowH
        DrawButton(x + CFG.innerPad, ry + 2, w - CFG.innerPad * 2, 16, preset.name)
    end

    -- Cancel
    ry = ry - rowH
    DrawButton(x + CFG.innerPad, ry + 2, 60, 16, "Cancel", COL.removeBtn)

    return h + rowH
end

--------------------------------------------------------------------------------
-- Main DrawScreen
--------------------------------------------------------------------------------

function widget:DrawScreen()
    if not TL then return end

    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    if not goals then return end

    -- Calculate window height
    local sliderSection = 4 * (CFG.sliderHeight + CFG.sliderLabelH) + CFG.rowHeight + CFG.padding
    local goalCount = mathMin(#goals.queue, CFG.maxVisibleGoals)
    local goalSection = goalCount * CFG.goalRowHeight + CFG.rowHeight + CFG.padding
    local buttonSection = CFG.buttonHeight + CFG.padding

    windowH = CFG.titleHeight + (collapsed and 0 or (
        sliderSection + CFG.sectionHeight + goalSection + buttonSection + CFG.padding
    ))

    -- Background
    SetColor(COL.background)
    glRect(windowX, windowY, windowX + windowW, windowY + windowH)

    -- Title bar
    SetColor(COL.titleBar)
    glRect(windowX, windowY + windowH - CFG.titleHeight, windowX + windowW, windowY + windowH)
    SetColor(COL.titleText)
    glText("Goal & Project Queue", windowX + CFG.padding, windowY + windowH - CFG.titleHeight + 7, CFG.titleFontSize, "oB")

    -- Collapse toggle
    SetColor(COL.labelText)
    glText(collapsed and "[+]" or "[-]", windowX + windowW - CFG.padding - 20,
           windowY + windowH - CFG.titleHeight + 7, CFG.titleFontSize, "o")

    if collapsed then return end

    local x = windowX + CFG.padding
    local contentW = windowW - CFG.padding * 2
    local y = windowY + windowH - CFG.titleHeight - CFG.padding

    -- ---- Resource Allocation Section ----
    y = y - CFG.sectionHeight
    SetColor(COL.sectionBg)
    glRect(windowX + 2, y, windowX + windowW - 2, y + CFG.sectionHeight)
    SetColor(COL.sectionText)
    glText("Resource Allocation", x, y + 4, CFG.fontSize, "oB")

    local alloc = goals.allocation

    -- Econ <-> Army slider
    y = y - CFG.sliderLabelH - CFG.sliderHeight
    DrawSlider(x, y, contentW, CFG.sliderHeight, alloc.econVsUnits, 0, 100, "Econ <-> Army", tostring(mathFloor(alloc.econVsUnits)))

    -- Savings slider
    y = y - CFG.sliderLabelH - CFG.sliderHeight
    DrawSlider(x, y, contentW, CFG.sliderHeight, alloc.savingsRate, 0, 100, "Savings", alloc.savingsRate .. "%")

    -- Team Share slider
    y = y - CFG.sliderLabelH - CFG.sliderHeight
    DrawSlider(x, y, contentW, CFG.sliderHeight, alloc.teamShareRate, 0, 100, "Team Share", alloc.teamShareRate .. "%")

    -- Project Funding slider
    y = y - CFG.sliderLabelH - CFG.sliderHeight
    DrawSlider(x, y, contentW, CFG.sliderHeight, alloc.projectFunding, 0, 100, "Project Fund", alloc.projectFunding .. "%")

    -- Auto Mode checkbox
    y = y - CFG.rowHeight
    SetColor(alloc.autoMode and COL.checkboxOn or COL.checkboxOff)
    glRect(x, y + 4, x + 12, y + 16)
    if alloc.autoMode then
        SetColor(COL.buttonText)
        glText("x", x + 6, y + 5, CFG.fontSize, "oc")
    end
    SetColor(COL.labelText)
    glText("Auto Mode", x + 18, y + 5, CFG.labelFontSize, "o")

    y = y - CFG.innerPad

    -- ---- Goal Queue Section ----
    y = y - CFG.sectionHeight
    SetColor(COL.sectionBg)
    glRect(windowX + 2, y, windowX + windowW - 2, y + CFG.sectionHeight)
    SetColor(COL.sectionText)
    glText("Goal Queue (" .. #goals.queue .. ")", x, y + 4, CFG.fontSize, "oB")

    -- Goal list
    for i = 1, mathMin(#goals.queue, CFG.maxVisibleGoals) do
        y = y - CFG.goalRowHeight
        DrawGoalRow(x, y, contentW, goals.queue[i], i)
    end

    if #goals.queue == 0 then
        y = y - CFG.goalRowHeight
        SetColor(COL.labelText)
        glText("No goals defined. Click [+ Add] or [Presets] to start.", x, y + 10, CFG.fontSize, "o")
    end

    y = y - CFG.padding

    -- Action buttons
    y = y - CFG.buttonHeight
    local btnW = (contentW - CFG.innerPad * 2) / 3
    DrawButton(x, y, btnW, CFG.buttonHeight, "+ Add", COL.buttonBg)
    DrawButton(x + btnW + CFG.innerPad, y, btnW, CFG.buttonHeight, "Presets", COL.buttonBg)
    DrawButton(x + (btnW + CFG.innerPad) * 2, y, btnW, CFG.buttonHeight, "Place", COL.buttonBg)

    -- Draw add form or preset list if active
    if uiMode == "adding" then
        DrawAddForm(windowX, windowY, windowW)
    elseif uiMode == "preset_select" then
        DrawPresetList(windowX, windowY, windowW)
    end
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:IsAbove(x, y)
    if not TL then return false end
    if collapsed then
        return x >= windowX and x <= windowX + windowW
           and y >= windowY + windowH - CFG.titleHeight and y <= windowY + windowH
    end
    -- Main window area
    if x >= windowX and x <= windowX + windowW
       and y >= windowY and y <= windowY + windowH then
        return true
    end
    -- Form/preset popup extends BELOW the main window
    if uiMode == "adding" then
        local formHeight = 5 * CFG.rowHeight + CFG.padding * 2
        if x >= windowX and x <= windowX + windowW
           and y >= windowY - formHeight and y < windowY then
            return true
        end
    elseif uiMode == "preset_select" then
        local presets = GoalsAPI and GoalsAPI.GetPresets() or {}
        local popupH = (#presets + 1) * CFG.rowHeight + CFG.padding * 2
        if x >= windowX and x <= windowX + windowW
           and y >= windowY - popupH and y < windowY then
            return true
        end
    end
    return false
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end
    if not self:IsAbove(mx, my) then
        -- Click outside = close popups
        if uiMode ~= "normal" then
            uiMode = "normal"
            return true
        end
        return false
    end

    local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
    if not goals then return false end

    local titleBot = windowY + windowH - CFG.titleHeight

    -- Title bar
    if my >= titleBot then
        if mx >= windowX + windowW - CFG.padding - 30 then
            collapsed = not collapsed
            return true
        end
        isDragging = true
        dragOffsetX = mx - windowX
        dragOffsetY = my - windowY
        return true
    end

    if collapsed then return true end

    local x = windowX + CFG.padding
    local contentW = windowW - CFG.padding * 2
    local alloc = goals.allocation

    -- Handle preset list clicks (popup drawn BELOW the main window)
    if uiMode == "preset_select" then
        local presets = GoalsAPI and GoalsAPI.GetPresets() or {}
        local rowH = CFG.rowHeight
        local popupH = #presets * rowH + CFG.padding * 2

        -- Preset rows: laid out top-to-bottom starting from windowY - padding
        local py = windowY - CFG.padding
        for i, preset in ipairs(presets) do
            py = py - rowH
            if my >= py and my < py + rowH then
                if GoalsAPI then GoalsAPI.AddGoalFromPreset(i) end
                uiMode = "normal"
                return true
            end
        end

        -- Cancel button at bottom of popup
        py = py - rowH
        if my >= py and my < py + rowH then
            uiMode = "normal"
            return true
        end

        uiMode = "normal"
        return true
    end

    -- Handle add form clicks (form is drawn BELOW the main window)
    if uiMode == "adding" then
        local rowH = CFG.rowHeight
        local formHeight = 5 * rowH + CFG.padding * 2

        -- Form extends from windowY downward: windowY - formHeight to windowY
        -- Rows are laid out top-to-bottom starting from windowY - padding
        local ry = windowY - CFG.padding

        -- Type row
        ry = ry - rowH
        if my >= ry and my < ry + rowH and mx >= windowX + 70 then
            addForm.goalType = CycleOption(addForm.goalType, GOAL_TYPE_ORDER)
            return true
        end

        -- Context fields (row 2)
        ry = ry - rowH
        if my >= ry and my < ry + rowH then
            if addForm.goalType == "unit_production" then
                if mx >= windowX + 70 then
                    local roles = GoalsAPI and GoalsAPI.GetRoleOptions() or {"assault"}
                    addForm.role = CycleOption(addForm.role, roles)
                end
            elseif addForm.goalType == "structure_build" then
                if mx >= windowX + 70 then
                    local keys = {"mex", "wind", "solar", "fusion", "llt", "hlt", "nano", "converter"}
                    addForm.buildKey = CycleOption(addForm.buildKey, keys)
                end
            elseif addForm.goalType == "economy_target" then
                if mx >= windowX + 70 then
                    local metrics = GoalsAPI and GoalsAPI.GetMetricOptions() or {"metalIncome"}
                    addForm.metric = CycleOption(addForm.metric, metrics)
                end
            elseif addForm.goalType == "tech_transition" then
                if mx >= windowX + 70 then
                    addForm.techLevel = (addForm.techLevel % 3) + 1
                    if addForm.techLevel < 2 then addForm.techLevel = 2 end
                end
            elseif addForm.goalType == "buildpower_target" then
                if mx < windowX + 100 then
                    addForm.bpTarget = mathMax(50, addForm.bpTarget - 50)
                elseif mx > windowX + 120 then
                    addForm.bpTarget = mathMin(3000, addForm.bpTarget + 50)
                end
            end
            return true
        end

        -- Context fields (row 3)
        ry = ry - rowH
        if my >= ry and my < ry + rowH then
            if addForm.goalType == "unit_production" then
                -- Count +/-
                if mx < windowX + 90 then
                    addForm.count = mathMax(1, addForm.count - 1)
                elseif mx > windowX + 100 then
                    addForm.count = mathMin(100, addForm.count + 1)
                end
            elseif addForm.goalType == "structure_build" then
                if mx < windowX + 90 then
                    addForm.count = mathMax(1, addForm.count - 1)
                elseif mx > windowX + 100 then
                    addForm.count = mathMin(20, addForm.count + 1)
                end
            elseif addForm.goalType == "economy_target" then
                if mx < windowX + 90 then
                    addForm.threshold = mathMax(5, addForm.threshold - 5)
                elseif mx > windowX + 110 then
                    addForm.threshold = mathMin(200, addForm.threshold + 5)
                end
            elseif addForm.goalType == "tech_transition" then
                local ftypes = GoalsAPI and GoalsAPI.GetFactoryTypeOptions() or {"bot"}
                addForm.factoryType = CycleOption(addForm.factoryType, ftypes)
            end
            return true
        end

        -- Destination row (row 4 for unit_production)
        ry = ry - rowH
        if my >= ry and my < ry + rowH then
            if addForm.goalType == "unit_production" then
                local dests = GoalsAPI and GoalsAPI.GetDestOptions() or {"front"}
                addForm.destination = CycleOption(addForm.destination, dests)
            end
            return true
        end

        -- Confirm / Cancel (bottom of form)
        local confirmY = windowY - formHeight + CFG.padding
        if my >= confirmY and my < confirmY + 20 then
            if mx < windowX + 80 then
                -- Confirm
                if GoalsAPI then
                    local target = {}
                    if addForm.goalType == "unit_production" then
                        target = { role = addForm.role, count = addForm.count, destination = addForm.destination }
                    elseif addForm.goalType == "structure_build" then
                        target = { buildKey = addForm.buildKey, count = addForm.count }
                    elseif addForm.goalType == "structure_place" then
                        -- Switch to placement mode
                        GoalsAPI.StartPlacement(addForm.buildKey)
                        uiMode = "normal"
                        return true
                    elseif addForm.goalType == "economy_target" then
                        target = { metric = addForm.metric, threshold = addForm.threshold }
                    elseif addForm.goalType == "tech_transition" then
                        target = { techLevel = addForm.techLevel, factoryType = addForm.factoryType }
                    elseif addForm.goalType == "buildpower_target" then
                        target = { bpTarget = addForm.bpTarget }
                    end
                    GoalsAPI.AddGoal(addForm.goalType, target)
                end
                uiMode = "normal"
            else
                -- Cancel
                uiMode = "normal"
            end
            return true
        end

        return true
    end

    -- ---- Normal mode clicks ----

    -- Map Y coordinates to sections
    local y = windowY + windowH - CFG.titleHeight - CFG.padding

    -- Skip resource allocation section header
    y = y - CFG.sectionHeight

    -- Slider areas (4 sliders)
    local sliderNames = { "econVsUnits", "savingsRate", "teamShareRate", "projectFunding" }
    for _, sname in ipairs(sliderNames) do
        y = y - CFG.sliderLabelH - CFG.sliderHeight
        if my >= y and my <= y + CFG.sliderHeight + CFG.sliderLabelH then
            local frac = mathMax(0, mathMin(1, (mx - x) / contentW))
            alloc[sname] = mathFloor(frac * 100)
            sliderDragging = sname
            return true
        end
    end

    -- Auto mode checkbox
    y = y - CFG.rowHeight
    if my >= y and my <= y + CFG.rowHeight and mx >= x and mx <= x + 100 then
        alloc.autoMode = not alloc.autoMode
        return true
    end

    y = y - CFG.innerPad

    -- Goal section header
    y = y - CFG.sectionHeight

    -- Goal rows
    for i = 1, mathMin(#goals.queue, CFG.maxVisibleGoals) do
        y = y - CFG.goalRowHeight
        if my >= y and my <= y + CFG.goalRowHeight then
            local goal = goals.queue[i]
            -- Check which button was clicked
            local btnArea = x + contentW

            -- Remove button (rightmost)
            if mx >= btnArea - 18 and mx <= btnArea - 4 then
                if GoalsAPI then GoalsAPI.RemoveGoal(goal.id) end
                return true
            end

            -- Down arrow
            if mx >= btnArea - 48 and mx <= btnArea - 32 then
                if GoalsAPI then GoalsAPI.MoveGoalDown(goal.id) end
                return true
            end

            -- Up arrow
            if mx >= btnArea - 64 and mx <= btnArea - 50 then
                if GoalsAPI then GoalsAPI.MoveGoalUp(goal.id) end
                return true
            end

            return true
        end
    end

    -- Skip empty goals area
    if #goals.queue == 0 then
        y = y - CFG.goalRowHeight
    end

    y = y - CFG.padding

    -- Action buttons
    y = y - CFG.buttonHeight
    if my >= y and my <= y + CFG.buttonHeight then
        local btnW = (contentW - CFG.innerPad * 2) / 3
        if mx >= x and mx <= x + btnW then
            -- [+ Add]
            uiMode = "adding"
            return true
        elseif mx >= x + btnW + CFG.innerPad and mx <= x + 2 * btnW + CFG.innerPad then
            -- [Presets]
            uiMode = "preset_select"
            return true
        elseif mx >= x + 2 * (btnW + CFG.innerPad) then
            -- [Place]
            if GoalsAPI then
                GoalsAPI.StartPlacement("lrpc")
            end
            return true
        end
    end

    return true
end

function widget:MouseMove(mx, my, dx, dy, button)
    if isDragging then
        windowX = mx - dragOffsetX
        windowY = my - dragOffsetY
        windowX = mathMax(0, mathMin(windowX, vsx - windowW))
        windowY = mathMax(0, mathMin(windowY, vsy - windowH))
        return true
    end

    if sliderDragging then
        local goals = WG.TotallyLegal and WG.TotallyLegal.Goals
        if goals then
            local x = windowX + CFG.padding
            local contentW = windowW - CFG.padding * 2
            local frac = mathMax(0, mathMin(1, (mx - x) / contentW))
            goals.allocation[sliderDragging] = mathFloor(frac * 100)
        end
        return true
    end

    return false
end

function widget:MouseRelease(mx, my, button)
    isDragging = false
    sliderDragging = nil
    return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()

    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Goal Panel] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Goal Panel] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    GoalsAPI = WG.TotallyLegal.GoalsAPI
    if not GoalsAPI then
        spEcho("[TotallyLegal Goal Panel] WARNING: Goals engine not loaded yet. UI will activate when available.")
    end

    windowX = 20
    windowY = 100

    spEcho("[TotallyLegal Goal Panel] UI ready.")
end

function widget:Update(dt)
    -- Re-acquire GoalsAPI if it wasn't available at init
    if not GoalsAPI and WG.TotallyLegal then
        GoalsAPI = WG.TotallyLegal.GoalsAPI
    end
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    windowX = mathMax(0, mathMin(windowX, vsx - windowW))
    windowY = mathMax(0, mathMin(windowY, vsy - windowH))
end

function widget:Shutdown()
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return {
        windowX   = windowX,
        windowY   = windowY,
        collapsed = collapsed,
    }
end

function widget:SetConfigData(data)
    if data.windowX then windowX = data.windowX end
    if data.windowY then windowY = data.windowY end
    if data.collapsed ~= nil then collapsed = data.collapsed end
end
