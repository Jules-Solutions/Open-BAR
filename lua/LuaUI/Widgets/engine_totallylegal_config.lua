-- TotallyLegal Strategy Config - Pre-game and in-game strategy configuration
-- Provides UI for setting strategy parameters. Exposes WG.TotallyLegal.Strategy for all engine modules.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: lib_totallylegal_core.lua (WG.TotallyLegal)

function widget:GetInfo()
    return {
        name      = "TotallyLegal Config",
        desc      = "Strategy configuration panel for TotallyLegal automation engine. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 200,
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
local glBeginEnd = gl.BeginEnd
local glVertex   = gl.Vertex
local GL_LINES   = GL.LINES

local mathMax   = math.max
local mathMin   = math.min
local mathFloor = math.floor
local osClock   = os.clock

-- Spring key codes
local KEYSYMS = Spring.GetKeySymConstants and Spring.GetKeySymConstants() or {}
local KEY_F1 = KEYSYMS.F1 or 0x0122
local KEY_F2 = KEYSYMS.F2 or 0x0123

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil

--------------------------------------------------------------------------------
-- Strategy state (exposed via WG.TotallyLegal.Strategy)
--------------------------------------------------------------------------------

local strategy = {
    -- Opening
    openingMexCount = 3,          -- 1-4
    energyStrategy  = "auto",     -- "auto", "wind_only", "solar_only", "mixed"

    -- Composition
    unitComposition = "mixed",    -- "bots", "vehicles", "mixed"
    posture         = "balanced", -- "defensive", "balanced", "aggressive"

    -- Timing
    t2Timing = "standard",       -- "early", "standard", "late"

    -- Economy balance
    econArmyBalance = 50,        -- 0-100, 0=all econ, 100=all army

    -- Build order source
    buildOrderFile  = nil,        -- path to JSON build order, or nil for auto-generate

    -- Faction (auto-detected, read-only)
    faction = "unknown",          -- "armada", "cortex", "unknown"

    -- Player role (team game strategic function)
    role = "balanced",            -- "balanced", "eco", "aggro", "support"

    -- Lane assignment (map sector responsibility)
    laneAssignment = "center",    -- "left", "center", "right"

    -- T2 transition mode
    t2Mode = "solo",              -- "solo", "receive"
    t2ReceiveMinute = 5,          -- minute to expect T2 con from ally

    -- Attack strategy (overrides posture-based behavior when active)
    attackStrategy = "none",      -- "none", "creeping", "piercing", "fake_retreat", "anti_aa_raid"

    -- Emergency mode (temporary unsustainable override)
    emergencyMode = "none",       -- "none", "defend_base", "mobilization"
    emergencyExpiry = 0,          -- game frame when emergency auto-expires
}

--------------------------------------------------------------------------------
-- UI Configuration
--------------------------------------------------------------------------------

local CFG = {
    windowWidth    = 280,
    titleHeight    = 26,
    rowHeight      = 24,
    sliderHeight   = 20,
    padding        = 10,
    fontSize       = 10,
    titleFontSize  = 12,
    labelFontSize  = 10,
    buttonWidth    = 120,
    buttonHeight   = 22,
    emergencyDuration = 1800,    -- 60 seconds at 30fps
}

local COL = {
    background  = { 0.05, 0.05, 0.08, 0.88 },
    titleBar    = { 0.12, 0.15, 0.25, 0.95 },
    titleText   = { 0.90, 0.90, 0.95, 1.0 },
    labelText   = { 0.65, 0.65, 0.70, 1.0 },
    valueText   = { 0.85, 0.90, 0.95, 1.0 },
    buttonBg    = { 0.15, 0.20, 0.30, 0.85 },
    buttonHover = { 0.20, 0.30, 0.45, 0.90 },
    buttonText  = { 0.85, 0.90, 0.95, 1.0 },
    sliderBg    = { 0.15, 0.15, 0.20, 0.80 },
    sliderFill  = { 0.30, 0.55, 0.80, 0.90 },
    sliderKnob  = { 0.70, 0.80, 0.90, 1.0 },
    separator   = { 0.30, 0.30, 0.40, 0.30 },
    active      = { 0.30, 0.75, 0.30, 1.0 },
    factionText = { 0.90, 0.85, 0.30, 1.0 },
    emergencyRed    = { 0.80, 0.20, 0.15, 0.90 },
    emergencyOrange = { 0.80, 0.55, 0.15, 0.90 },
    emergencyActive = { 1.00, 0.30, 0.20, 1.0 },
    emergencyText   = { 1.00, 1.00, 1.00, 1.0 },
}

-- Option definitions for cycling buttons
local ENERGY_OPTIONS  = { "auto", "wind_only", "solar_only", "mixed" }
local COMP_OPTIONS    = { "bots", "vehicles", "mixed" }
local POSTURE_OPTIONS = { "defensive", "balanced", "aggressive" }
local T2_OPTIONS      = { "early", "standard", "late" }
local ROLE_OPTIONS    = { "balanced", "eco", "aggro", "support" }
local LANE_OPTIONS    = { "left", "center", "right" }
local T2MODE_OPTIONS  = { "solo", "receive" }
local ATTACK_OPTIONS  = { "none", "creeping", "piercing", "fake_retreat", "anti_aa_raid" }
local LEVEL_OPTIONS   = { 0, 1, 2, 3 }
local LEVEL_LABELS    = { [0] = "Overlay", [1] = "Execute", [2] = "Advise", [3] = "Autonomous" }

local ENERGY_LABELS  = { auto = "Auto", wind_only = "Wind Only", solar_only = "Solar Only", mixed = "Mixed" }
local COMP_LABELS    = { bots = "Bots", vehicles = "Vehicles", mixed = "Mixed" }
local POSTURE_LABELS = { defensive = "Defensive", balanced = "Balanced", aggressive = "Aggressive" }
local T2_LABELS      = { early = "Early", standard = "Standard", late = "Late" }
local ROLE_LABELS    = { balanced = "Balanced", eco = "Eco", aggro = "Aggro", support = "Support" }
local LANE_LABELS    = { left = "Left", center = "Center", right = "Right" }
local T2MODE_LABELS  = { solo = "Solo T2", receive = "Receive T2 Con" }
local ATTACK_LABELS  = { none = "None", creeping = "Creeping Fwd", piercing = "Piercing",
                          fake_retreat = "Fake Retreat", anti_aa_raid = "Anti-AA Raid" }

--------------------------------------------------------------------------------
-- Window state
--------------------------------------------------------------------------------

local windowX = 20
local windowY = 200
local windowW = CFG.windowWidth
local windowH = 300
local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0
local vsx, vsy = 0, 0
local collapsed = false

-- Click interaction state
local sliderDragging = nil   -- "econArmy" or nil
local hoverButton = nil

-- Emergency button Y positions (computed during draw)
local emergencyButtonY = 0
local emergencyButtonsVisible = false

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

--------------------------------------------------------------------------------
-- Emergency mode helpers
--------------------------------------------------------------------------------

-- Bug #8: Warn on contradictory strategy combinations
local stratWarning = nil     -- { text, expireTime }

local function ValidateStrategy()
    local warnings = {}
    if strategy.unitComposition == "bots" and strategy.attackStrategy == "anti_aa_raid" then
        warnings[#warnings + 1] = "Bots are slow for Anti-AA Raid"
    end
    if strategy.posture == "aggressive" and strategy.emergencyMode == "defend_base" then
        warnings[#warnings + 1] = "Aggressive posture conflicts with Defend Base"
    end
    if strategy.role == "eco" and strategy.posture == "aggressive" then
        warnings[#warnings + 1] = "Eco role conflicts with Aggressive posture"
    end
    if #warnings > 0 then
        local msg = "[TotallyLegal Config] WARNING: " .. table.concat(warnings, "; ")
        spEcho(msg)
        stratWarning = { text = warnings[1], expireTime = osClock() + 3 }
    end
end

--------------------------------------------------------------------------------
-- Strategy API for programmatic control (Phase 3 feature: sim bridge)
--------------------------------------------------------------------------------

local STRATEGY_OPTIONS = {
    energyStrategy  = ENERGY_OPTIONS,
    unitComposition = COMP_OPTIONS,
    posture         = POSTURE_OPTIONS,
    t2Timing        = T2_OPTIONS,
    role            = ROLE_OPTIONS,
    laneAssignment  = LANE_OPTIONS,
    t2Mode          = T2MODE_OPTIONS,
    attackStrategy  = ATTACK_OPTIONS,
}

local STRATEGY_NUMERIC = {
    openingMexCount = { min = 1, max = 4 },
    econArmyBalance = { min = 0, max = 100 },
    t2ReceiveMinute = { min = 1, max = 15 },
}

local STRATEGY_READONLY = { faction = true, _ready = true, emergencyExpiry = true }

local function SetStrategy(key, value)
    if not key then return false, "key is nil" end
    if STRATEGY_READONLY[key] then return false, "key '" .. key .. "' is read-only" end
    if strategy[key] == nil and not STRATEGY_NUMERIC[key] then return false, "unknown key '" .. key .. "'" end

    -- Validate option-based keys
    if STRATEGY_OPTIONS[key] then
        local valid = false
        for _, opt in ipairs(STRATEGY_OPTIONS[key]) do
            if opt == value then valid = true; break end
        end
        if not valid then return false, "invalid value '" .. tostring(value) .. "' for key '" .. key .. "'" end
    end

    -- Validate numeric keys
    if STRATEGY_NUMERIC[key] then
        if type(value) ~= "number" then return false, "key '" .. key .. "' requires a number" end
        local bounds = STRATEGY_NUMERIC[key]
        value = mathMax(bounds.min, mathMin(bounds.max, mathFloor(value)))
    end

    strategy[key] = value
    ValidateStrategy()
    spEcho("[TotallyLegal Config] SetStrategy: " .. key .. " = " .. tostring(value))
    return true
end

local function GetStrategySnapshot()
    local snap = {}
    for k, v in pairs(strategy) do
        if k ~= "_ready" then
            snap[k] = v
        end
    end
    return snap
end

local function ActivateEmergency(mode)
    if strategy.emergencyMode == mode then
        -- Toggle off
        strategy.emergencyMode = "none"
        strategy.emergencyExpiry = 0
        spEcho("[TotallyLegal Config] Emergency mode deactivated.")
    else
        strategy.emergencyMode = mode
        strategy.emergencyExpiry = spGetGameFrame() + CFG.emergencyDuration
        spEcho("[TotallyLegal Config] EMERGENCY: " .. mode .. " activated!")
    end
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function SetColor(c) glColor(c[1], c[2], c[3], c[4]) end

local function DrawButton(x, y, w, h, label, isActive)
    SetColor(isActive and COL.active or COL.buttonBg)
    glRect(x, y, x + w, y + h)
    SetColor(COL.buttonText)
    glText(label, x + w / 2, y + 3, CFG.fontSize, "ocB")
end

local function DrawSlider(x, y, w, h, value, minVal, maxVal, label)
    SetColor(COL.labelText)
    glText(label, x, y + h + 2, CFG.labelFontSize, "o")
    SetColor(COL.valueText)
    glText(tostring(mathFloor(value)), x + w, y + h + 2, CFG.labelFontSize, "or")
    SetColor(COL.sliderBg)
    glRect(x, y, x + w, y + h)
    local frac = (value - minVal) / mathMax(maxVal - minVal, 1)
    SetColor(COL.sliderFill)
    glRect(x, y, x + w * frac, y + h)
    local knobX = x + w * frac
    SetColor(COL.sliderKnob)
    glRect(knobX - 3, y - 2, knobX + 3, y + h + 2)
end

local function DrawRow(x, y, label, value)
    SetColor(COL.labelText)
    glText(label, x, y + 4, CFG.labelFontSize, "o")
    SetColor(COL.valueText)
    glText(value, x + windowW - CFG.padding * 2, y + 4, CFG.labelFontSize, "or")
    return y - CFG.rowHeight
end

local function DrawColoredRow(x, y, label, value, valueColor)
    SetColor(COL.labelText)
    glText(label, x, y + 4, CFG.labelFontSize, "o")
    SetColor(valueColor)
    glText(value, x + windowW - CFG.padding * 2, y + 4, CFG.labelFontSize, "or")
    return y - CFG.rowHeight
end

function widget:DrawScreen()
    if not TL then return end
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Config == false then return end

    -- Row count: level(1) + faction(1) + role(1) + mex(1) + energy(1) + units(1) + lane(1) + posture(1) + t2timing(1) + t2mode(1)
    -- + slider(2) + separator(0.5) + attack(1) + separator(0.5) + emergency buttons(1.5) + status(1) = ~16 rows
    local rows = collapsed and 0 or 16
    windowH = CFG.titleHeight + (collapsed and 0 or (rows * CFG.rowHeight + CFG.padding * 2))

    -- Background
    SetColor(COL.background)
    glRect(windowX, windowY, windowX + windowW, windowY + windowH)

    -- Title bar
    SetColor(COL.titleBar)
    glRect(windowX, windowY + windowH - CFG.titleHeight, windowX + windowW, windowY + windowH)
    SetColor(COL.titleText)
    glText("Strategy Config", windowX + CFG.padding, windowY + windowH - CFG.titleHeight + 7, CFG.titleFontSize, "oB")

    -- Collapse toggle
    SetColor(COL.labelText)
    glText(collapsed and "[+]" or "[-]", windowX + windowW - CFG.padding - 20, windowY + windowH - CFG.titleHeight + 7, CFG.titleFontSize, "o")

    if collapsed then
        emergencyButtonsVisible = false
        return
    end

    -- Content
    local x = windowX + CFG.padding
    local rEdge = windowX + windowW - CFG.padding
    local y = windowY + windowH - CFG.titleHeight - CFG.padding

    -- Automation Level
    local curLevel = TL.GetAutomationLevel and TL.GetAutomationLevel() or 0
    local levelLabel = LEVEL_LABELS[curLevel] or tostring(curLevel)
    local levelColor = curLevel == 0 and COL.labelText or COL.active
    y = DrawColoredRow(x, y, "Level:", levelLabel, levelColor)

    -- Faction (read-only, yellow)
    local factionDisplay = strategy.faction == "unknown" and "Detecting..." or
                           (strategy.faction:sub(1,1):upper() .. strategy.faction:sub(2)) .. " (auto)"
    y = DrawColoredRow(x, y, "Faction:", factionDisplay, COL.factionText)

    -- Player Role
    local roleColor = strategy.role == "aggro" and COL.emergencyOrange
                   or strategy.role == "eco" and COL.active
                   or strategy.role == "support" and COL.sliderFill
                   or COL.valueText
    y = DrawColoredRow(x, y, "Role:", ROLE_LABELS[strategy.role] or strategy.role, roleColor)

    -- Opening Mex Count
    y = DrawRow(x, y, "Opening Mex:", tostring(strategy.openingMexCount))

    -- Energy Strategy
    y = DrawRow(x, y, "Energy:", ENERGY_LABELS[strategy.energyStrategy] or strategy.energyStrategy)

    -- Unit Composition
    y = DrawRow(x, y, "Units:", COMP_LABELS[strategy.unitComposition] or strategy.unitComposition)

    -- Lane Assignment
    y = DrawRow(x, y, "Lane:", LANE_LABELS[strategy.laneAssignment] or strategy.laneAssignment)

    -- Posture
    local postureColor = strategy.posture == "aggressive" and COL.active or COL.valueText
    y = DrawColoredRow(x, y, "Posture:", POSTURE_LABELS[strategy.posture] or strategy.posture, postureColor)

    -- T2 Timing
    y = DrawRow(x, y, "T2 Timing:", T2_LABELS[strategy.t2Timing] or strategy.t2Timing)

    -- T2 Mode
    local t2Display = T2MODE_LABELS[strategy.t2Mode] or strategy.t2Mode
    if strategy.t2Mode == "receive" then
        t2Display = t2Display .. " @" .. tostring(strategy.t2ReceiveMinute) .. "m"
    end
    y = DrawRow(x, y, "T2 Mode:", t2Display)

    -- Econ/Army Balance Slider
    y = y - 4
    DrawSlider(x, y - CFG.sliderHeight, windowW - CFG.padding * 2, CFG.sliderHeight,
               strategy.econArmyBalance, 0, 100, "Econ <-> Army")
    y = y - CFG.sliderHeight - CFG.rowHeight

    -- Separator
    SetColor(COL.separator)
    glRect(windowX + 5, y + CFG.rowHeight - 2, windowX + windowW - 5, y + CFG.rowHeight - 1)

    -- Attack Strategy
    local attackColor = strategy.attackStrategy ~= "none" and COL.emergencyOrange or COL.valueText
    y = DrawColoredRow(x, y, "Attack:", ATTACK_LABELS[strategy.attackStrategy] or strategy.attackStrategy, attackColor)

    -- Separator
    SetColor(COL.separator)
    glRect(windowX + 5, y + CFG.rowHeight - 2, windowX + windowW - 5, y + CFG.rowHeight - 1)

    -- Emergency buttons
    local btnW = (windowW - CFG.padding * 3) / 2
    local btnH = CFG.buttonHeight
    local btnY = y - 2
    emergencyButtonY = btnY
    emergencyButtonsVisible = true

    -- Defend Base button
    local isDefend = strategy.emergencyMode == "defend_base"
    local defendColor = isDefend and COL.emergencyActive or COL.emergencyRed
    -- Pulse effect when active
    if isDefend then
        local pulse = 0.7 + 0.3 * math.abs(math.sin(osClock() * 4))
        defendColor = { pulse, 0.15, 0.10, 0.95 }
    end
    SetColor(defendColor)
    glRect(x, btnY - btnH, x + btnW, btnY)
    SetColor(COL.emergencyText)
    glText("DEFEND BASE", x + btnW / 2, btnY - btnH + 5, CFG.fontSize, "ocB")

    -- Mobilize button
    local isMobilize = strategy.emergencyMode == "mobilization"
    local mobilizeColor = isMobilize and COL.emergencyActive or COL.emergencyOrange
    if isMobilize then
        local pulse = 0.7 + 0.3 * math.abs(math.sin(osClock() * 4))
        mobilizeColor = { pulse, 0.45 * pulse, 0.10, 0.95 }
    end
    SetColor(mobilizeColor)
    local btnX2 = x + btnW + CFG.padding
    glRect(btnX2, btnY - btnH, btnX2 + btnW, btnY)
    SetColor(COL.emergencyText)
    glText("MOBILIZE", btnX2 + btnW / 2, btnY - btnH + 5, CFG.fontSize, "ocB")

    y = btnY - btnH - 6

    -- Status line
    SetColor(COL.labelText)
    local statusText
    if strategy.emergencyMode ~= "none" then
        local remaining = strategy.emergencyExpiry - spGetGameFrame()
        local secs = mathMax(0, mathFloor(remaining / 30))
        local modeLabel = strategy.emergencyMode == "defend_base" and "Defend Base" or "Mobilization"
        statusText = "EMERGENCY: " .. modeLabel .. " (" .. secs .. "s)"
        SetColor(COL.emergencyActive)
    elseif stratWarning and osClock() < stratWarning.expireTime then
        statusText = "WARN: " .. stratWarning.text
        SetColor(COL.emergencyOrange)
    else
        statusText = "Click values to cycle | Ctrl+F1/F2 emergency"
    end
    glText(statusText, x, y + 4, CFG.fontSize - 1, "o")
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:IsAbove(x, y)
    if WG.TotallyLegal and WG.TotallyLegal.WidgetVisibility and WG.TotallyLegal.WidgetVisibility.Config == false then return false end
    return x >= windowX and x <= windowX + windowW
       and y >= windowY and y <= windowY + windowH
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    if not self:IsAbove(x, y) then return false end

    local titleBot = windowY + windowH - CFG.titleHeight

    -- Collapse toggle
    if y >= titleBot then
        if x >= windowX + windowW - CFG.padding - 30 then
            collapsed = not collapsed
            return true
        end
        isDragging = true
        dragOffsetX = x - windowX
        dragOffsetY = y - windowY
        return true
    end

    if collapsed then return true end

    -- Check emergency buttons first (they're at the bottom)
    if emergencyButtonsVisible then
        local bx = windowX + CFG.padding
        local btnW = (windowW - CFG.padding * 3) / 2
        local btnH = CFG.buttonHeight
        local btnY = emergencyButtonY

        -- Defend Base button
        if x >= bx and x <= bx + btnW and y >= btnY - btnH and y <= btnY then
            ActivateEmergency("defend_base")
            return true
        end

        -- Mobilize button
        local btnX2 = bx + btnW + CFG.padding
        if x >= btnX2 and x <= btnX2 + btnW and y >= btnY - btnH and y <= btnY then
            ActivateEmergency("mobilization")
            return true
        end
    end

    -- Determine which row was clicked (simple Y-based mapping)
    local contentTop = windowY + windowH - CFG.titleHeight - CFG.padding
    local rowClicked = mathFloor((contentTop - y) / CFG.rowHeight)

    -- Only cycle values when clicking the right half (value area).
    -- Clicking the left half (label area) starts a drag for easier repositioning.
    local midX = windowX + windowW * 0.45
    if x < midX and rowClicked ~= 10 and rowClicked ~= 11 then
        -- Label area → drag
        isDragging = true
        dragOffsetX = x - windowX
        dragOffsetY = y - windowY
        return true
    end

    -- Row mapping:
    -- 0: Automation Level
    -- 1: Faction (read-only, no action)
    -- 2: Role
    -- 3: Opening Mex Count
    -- 4: Energy Strategy
    -- 5: Unit Composition
    -- 6: Lane Assignment
    -- 7: Posture
    -- 8: T2 Timing
    -- 9: T2 Mode (left-click cycles mode, right side adjusts minute)
    -- 10+: Slider area (econArmyBalance)
    -- then: attack strategy, emergency buttons

    if rowClicked == 0 then
        -- Automation Level: cycle 0->1->2->3->0
        if TL.SetAutomationLevel then
            local cur = TL.GetAutomationLevel and TL.GetAutomationLevel() or 0
            TL.SetAutomationLevel((cur + 1) % 4)
        end
    elseif rowClicked == 1 then
        -- Faction: read-only, start drag
        isDragging = true
        dragOffsetX = x - windowX
        dragOffsetY = y - windowY
    elseif rowClicked == 2 then
        strategy.role = CycleOption(strategy.role, ROLE_OPTIONS)
    elseif rowClicked == 3 then
        strategy.openingMexCount = (strategy.openingMexCount % 4) + 1
    elseif rowClicked == 4 then
        strategy.energyStrategy = CycleOption(strategy.energyStrategy, ENERGY_OPTIONS)
    elseif rowClicked == 5 then
        strategy.unitComposition = CycleOption(strategy.unitComposition, COMP_OPTIONS)
    elseif rowClicked == 6 then
        strategy.laneAssignment = CycleOption(strategy.laneAssignment, LANE_OPTIONS)
    elseif rowClicked == 7 then
        strategy.posture = CycleOption(strategy.posture, POSTURE_OPTIONS)
    elseif rowClicked == 8 then
        strategy.t2Timing = CycleOption(strategy.t2Timing, T2_OPTIONS)
    elseif rowClicked == 9 then
        -- T2 Mode: cycle mode, or adjust minute if receive mode
        -- Only the far-right 60px adjusts the minute; everything else cycles mode
        local minuteZone = windowX + windowW - CFG.padding - 60
        if strategy.t2Mode == "receive" and x > minuteZone then
            strategy.t2ReceiveMinute = (strategy.t2ReceiveMinute % 15) + 1
        else
            strategy.t2Mode = CycleOption(strategy.t2Mode, T2MODE_OPTIONS)
        end
    elseif rowClicked == 10 or rowClicked == 11 then
        -- Slider area
        local sliderX = windowX + CFG.padding
        local sliderW = windowW - CFG.padding * 2
        local frac = mathMax(0, mathMin(1, (x - sliderX) / sliderW))
        strategy.econArmyBalance = mathFloor(frac * 100)
        sliderDragging = "econArmy"
    elseif rowClicked == 12 then
        -- Attack Strategy (after separator)
        strategy.attackStrategy = CycleOption(strategy.attackStrategy, ATTACK_OPTIONS)
    end

    ValidateStrategy()  -- Bug #8: check for contradictory combos after each change
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
    if sliderDragging == "econArmy" then
        local sliderX = windowX + CFG.padding
        local sliderW = windowW - CFG.padding * 2
        local frac = mathMax(0, mathMin(1, (x - sliderX) / sliderW))
        strategy.econArmyBalance = mathFloor(frac * 100)
        return true
    end
    return false
end

function widget:MouseRelease(x, y, button)
    isDragging = false
    sliderDragging = nil
    return false
end

--------------------------------------------------------------------------------
-- Keyboard shortcuts
--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)
    if isRepeat then return false end
    if not mods.ctrl then return false end

    if key == KEY_F1 then
        ActivateEmergency("defend_base")
        return true
    elseif key == KEY_F2 then
        ActivateEmergency("mobilization")
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Game frame processing
--------------------------------------------------------------------------------

function widget:GameFrame(frame)
    if not TL then return end
    if not (WG.TotallyLegal and WG.TotallyLegal._ready) then return end

    local ok, err = pcall(function()
        -- Auto-expire emergency modes
        if strategy.emergencyMode ~= "none" and strategy.emergencyExpiry > 0 then
            if frame >= strategy.emergencyExpiry then
                spEcho("[TotallyLegal Config] Emergency mode expired.")
                strategy.emergencyMode = "none"
                strategy.emergencyExpiry = 0
            end
        end

        -- Auto-detect faction if not yet known (poll every 2s)
        if strategy.faction == "unknown" and frame % 60 == 0 and frame > 30 then
            local faction = TL.GetFaction()
            if faction ~= "unknown" then
                strategy.faction = faction
                spEcho("[TotallyLegal Config] Faction detected: " .. faction)
            end
        end
    end)
    if not ok then
        spEcho("[TotallyLegal Config] GameFrame error: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()

    if not WG.TotallyLegal then
        spEcho("[TotallyLegal Config] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[TotallyLegal Config] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Expose strategy to other engine widgets
    WG.TotallyLegal.Strategy = strategy
    WG.TotallyLegal.SetStrategy = SetStrategy
    WG.TotallyLegal.GetStrategySnapshot = GetStrategySnapshot
    strategy._ready = true

    windowX = 20
    windowY = vsy / 2

    spEcho("[TotallyLegal Config] Strategy config loaded.")
end

function widget:ViewResize(newX, newY)
    vsx, vsy = newX, newY
    windowX = mathMax(0, mathMin(windowX, vsx - windowW))
    windowY = mathMax(0, mathMin(windowY, vsy - windowH))
end

function widget:Shutdown()
    if WG.TotallyLegal then
        if WG.TotallyLegal.Strategy then
            WG.TotallyLegal.Strategy._ready = false
        end
        WG.TotallyLegal.SetStrategy = nil
        WG.TotallyLegal.GetStrategySnapshot = nil
    end
end

--------------------------------------------------------------------------------
-- Config persistence
--------------------------------------------------------------------------------

function widget:GetConfigData()
    return {
        windowX = windowX,
        windowY = windowY,
        collapsed = collapsed,
        automationLevel = TL.GetAutomationLevel and TL.GetAutomationLevel() or 0,
        openingMexCount = strategy.openingMexCount,
        energyStrategy = strategy.energyStrategy,
        unitComposition = strategy.unitComposition,
        posture = strategy.posture,
        t2Timing = strategy.t2Timing,
        econArmyBalance = strategy.econArmyBalance,
        role = strategy.role,
        laneAssignment = strategy.laneAssignment,
        t2Mode = strategy.t2Mode,
        t2ReceiveMinute = strategy.t2ReceiveMinute,
        attackStrategy = strategy.attackStrategy,
    }
end

function widget:SetConfigData(data)
    if data.windowX then windowX = data.windowX end
    if data.windowY then windowY = data.windowY end
    if data.collapsed ~= nil then collapsed = data.collapsed end
    if data.automationLevel and TL and TL.SetAutomationLevel then
        TL.SetAutomationLevel(data.automationLevel)
    end
    if data.openingMexCount then strategy.openingMexCount = data.openingMexCount end
    if data.energyStrategy then strategy.energyStrategy = data.energyStrategy end
    if data.unitComposition then strategy.unitComposition = data.unitComposition end
    if data.posture then strategy.posture = data.posture end
    if data.t2Timing then strategy.t2Timing = data.t2Timing end
    if data.econArmyBalance then strategy.econArmyBalance = data.econArmyBalance end
    if data.role then strategy.role = data.role end
    if data.laneAssignment then strategy.laneAssignment = data.laneAssignment end
    if data.t2Mode then strategy.t2Mode = data.t2Mode end
    if data.t2ReceiveMinute then strategy.t2ReceiveMinute = data.t2ReceiveMinute end
    if data.attackStrategy then strategy.attackStrategy = data.attackStrategy end
end
