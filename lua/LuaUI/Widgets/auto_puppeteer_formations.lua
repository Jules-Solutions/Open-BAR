-- Unit Puppeteer: Formations - Formation shapes and role-based unit distribution
-- Intercepts group move commands and distributes units into tactical formations.
-- Supports circle, half-circle, square, star, and nested formations.
-- Uses Hungarian algorithm (from cmd_customformations2 by Errrrrrr/Niobium)
-- for optimal unit-to-position assignment when unit count <= 40.
-- Coexists with cmd_customformations2: that widget handles line-drawing via mouse
-- gestures, this widget handles geometric shape formations via CommandNotify.
-- PvE/Unranked ONLY. Disabled in "No Automation" mode.
-- Requires: auto_puppeteer_core.lua (WG.TotallyLegal.Puppeteer)
--
-- References:
--   cmd_customformations2.lua (zxbc/BAR_widgets) — Hungarian + NoX algorithms
--   Spring.TestMoveOrder(defID, x, y, z) -> bool

function widget:GetInfo()
    return {
        name      = "Puppeteer Formations",
        desc      = "Formation shapes and role-based unit positioning. PvE only.",
        author    = "TotallyLegalWidget",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 106,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- Localized API references
--------------------------------------------------------------------------------

local spGetMyTeamID         = Spring.GetMyTeamID
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetGroundHeight     = Spring.GetGroundHeight
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetGameFrame        = Spring.GetGameFrame
local spGetCommandQueue     = Spring.GetCommandQueue
local spEcho                = Spring.Echo
local spTestMoveOrder       = Spring.TestMoveOrder

local CMD_MOVE = CMD.MOVE

local mathSqrt  = math.sqrt
local mathCos   = math.cos
local mathSin   = math.sin
local mathPi    = math.pi
local mathMax   = math.max
local mathMin   = math.min
local mathAtan2 = math.atan2
local mathFloor = math.floor
local mathAbs   = math.abs
local mathHuge  = math.huge
local osclock   = os.clock

--------------------------------------------------------------------------------
-- Core library reference
--------------------------------------------------------------------------------

local TL = nil
local PUP = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CFG = {
    minRadius           = 60,       -- minimum formation radius
    radiusScaleFactor   = 40,       -- radius = sqrt(N) * this
    groupCleanupAge     = 600,      -- remove groups older than 600 frames (20s)
    maxHungarianUnits   = 40,       -- use Hungarian algo up to this count
    maxAlgoTime         = 0.01,     -- 10ms time budget for matching algorithm
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local nextGroupID = 1
local mapSizeX = 0
local mapSizeZ = 0
local hasTestMove = false

--------------------------------------------------------------------------------
-- Formation math helpers
--------------------------------------------------------------------------------

local function CalculateRadius(unitCount)
    return mathMax(CFG.minRadius, mathSqrt(unitCount) * CFG.radiusScaleFactor)
end

local function GetAveragePosition(unitIDs)
    if #unitIDs == 0 then return nil, nil, nil end

    local sumX, sumY, sumZ = 0, 0, 0
    local count = 0

    for _, uid in ipairs(unitIDs) do
        local x, y, z = spGetUnitPosition(uid)
        if x then
            sumX = sumX + x
            sumY = sumY + y
            sumZ = sumZ + z
            count = count + 1
        end
    end

    if count == 0 then return nil, nil, nil end
    return sumX / count, sumY / count, sumZ / count
end

-- Get unit's final destination (end of command queue), not current position.
-- Pattern from cmd_customformations2 — used for shift-queued formations.
local function GetUnitFinalPosition(uID)
    local ux, uy, uz = spGetUnitPosition(uID)
    local cmds = spGetCommandQueue(uID, 5000)

    if cmds then
        for i = #cmds, 1, -1 do
            local cmd = cmds[i]
            local params = cmd.params
            if params and #params >= 3 then
                return params[1], params[2], params[3]
            end
        end
    end

    return ux, uy, uz
end

local function ClampToMap(x, z)
    x = mathMax(32, mathMin(x, mapSizeX - 32))
    z = mathMax(32, mathMin(z, mapSizeZ - 32))
    return x, z
end

local function ValidatePosition(x, z, unitDefID)
    x, z = ClampToMap(x, z)
    local y = spGetGroundHeight(x, z)
    if not y then return nil, nil, nil end

    if hasTestMove and unitDefID then
        local valid = spTestMoveOrder(unitDefID, x, y, z)
        if not valid then
            -- Try small offsets to find a valid position nearby
            for offset = 20, 60, 20 do
                for _, dz in ipairs({ offset, -offset, 0, 0 }) do
                    for _, dx in ipairs({ 0, 0, offset, -offset }) do
                        if dx ~= 0 or dz ~= 0 then
                            local tx, tz = ClampToMap(x + dx, z + dz)
                            local ty = spGetGroundHeight(tx, tz)
                            if ty and spTestMoveOrder(unitDefID, tx, ty, tz) then
                                return tx, ty, tz
                            end
                        end
                    end
                end
            end
            return nil, nil, nil
        end
    end

    return x, y, z
end

--------------------------------------------------------------------------------
-- Formation shape generators
--------------------------------------------------------------------------------

local function GenerateCircle(centerX, centerZ, radius, count, facing)
    local positions = {}
    for i = 1, count do
        local angle = 2 * mathPi * (i - 1) / count
        local x = centerX + radius * mathCos(angle)
        local z = centerZ + radius * mathSin(angle)
        -- Fix 5: Use facing-relative depth instead of hardcoded 0.5
        local depth = 0.5 - 0.5 * mathCos(angle - facing)  -- 0 = front, 1 = back
        positions[i] = { x = x, z = z, depth = depth }
    end
    return positions
end

local function GenerateHalfCircle(centerX, centerZ, radius, count, facing)
    local positions = {}
    for i = 1, count do
        local angle = mathPi * (i - 1) / mathMax(count - 1, 1) - mathPi / 2 + facing
        local x = centerX + radius * mathCos(angle)
        local z = centerZ + radius * mathSin(angle)

        local arcPos = (i - 1) / mathMax(count - 1, 1)
        local depth = mathAbs(arcPos - 0.5) * 2

        positions[i] = { x = x, z = z, depth = depth }
    end
    return positions
end

local function GenerateSquare(centerX, centerZ, radius, count, facing)
    local positions = {}
    local perimeter = 8 * radius
    local spacing = perimeter / count

    local cos_f = mathCos(facing)
    local sin_f = mathSin(facing)

    for i = 1, count do
        local dist = (i - 1) * spacing
        local x_local, z_local, depth

        if dist < 2 * radius then
            x_local = dist - radius
            z_local = -radius
            depth = 0.25
        elseif dist < 4 * radius then
            x_local = radius
            z_local = (dist - 2 * radius) - radius
            depth = 0.75
        elseif dist < 6 * radius then
            x_local = radius - (dist - 4 * radius)
            z_local = radius
            depth = 1.0
        else
            x_local = -radius
            z_local = radius - (dist - 6 * radius)
            depth = 0.75
        end

        local x = centerX + (x_local * cos_f - z_local * sin_f)
        local z = centerZ + (x_local * sin_f + z_local * cos_f)

        positions[i] = { x = x, z = z, depth = depth }
    end

    return positions
end

local function GenerateStar(centerX, centerZ, radius, count, facing)
    local positions = {}
    local innerRadius = radius * 0.5

    for i = 1, count do
        local angle = 2 * mathPi * (i - 1) / count
        local r = (i % 2 == 1) and radius or innerRadius
        local x = centerX + r * mathCos(angle)
        local z = centerZ + r * mathSin(angle)
        -- Fix 5: Use facing-relative depth instead of hardcoded values
        local depth = 0.5 - 0.5 * mathCos(angle - facing)  -- 0 = front, 1 = back

        positions[i] = { x = x, z = z, depth = depth }
    end

    return positions
end

local function GenerateNestedFormation(centerX, centerZ, baseRadius, count, facing, shape, nesting)
    if nesting <= 1 then
        if shape == 2 then return GenerateCircle(centerX, centerZ, baseRadius, count, facing) end
        if shape == 3 then return GenerateHalfCircle(centerX, centerZ, baseRadius, count, facing) end
        if shape == 4 then return GenerateSquare(centerX, centerZ, baseRadius, count, facing) end
        if shape == 5 then return GenerateStar(centerX, centerZ, baseRadius, count, facing) end
        return nil
    end

    local positions = {}
    local layerPerimeters = {}
    local totalPerimeter = 0

    for layer = 1, nesting do
        local layerRadius = baseRadius * layer / nesting
        local perimeter = 2 * mathPi * layerRadius
        layerPerimeters[layer] = perimeter
        totalPerimeter = totalPerimeter + perimeter
    end

    local layerCounts = {}
    local assigned = 0
    for layer = 1, nesting do
        local ratio = layerPerimeters[layer] / totalPerimeter
        local layerCount = mathFloor(count * ratio + 0.5)
        layerCounts[layer] = layerCount
        assigned = assigned + layerCount
    end

    local diff = count - assigned
    if diff ~= 0 then
        layerCounts[nesting] = layerCounts[nesting] + diff
    end

    for layer = 1, nesting do
        local layerRadius = baseRadius * layer / nesting
        local layerCount = layerCounts[layer]

        if layerCount > 0 then
            local layerPos
            if shape == 2 then layerPos = GenerateCircle(centerX, centerZ, layerRadius, layerCount, facing)
            elseif shape == 3 then layerPos = GenerateHalfCircle(centerX, centerZ, layerRadius, layerCount, facing)
            elseif shape == 4 then layerPos = GenerateSquare(centerX, centerZ, layerRadius, layerCount, facing)
            elseif shape == 5 then layerPos = GenerateStar(centerX, centerZ, layerRadius, layerCount, facing)
            end

            if layerPos then
                for _, pos in ipairs(layerPos) do
                    pos.depth = (pos.depth or 0.5) * (layer / nesting)
                    positions[#positions + 1] = pos
                end
            end
        end
    end

    return positions
end

--------------------------------------------------------------------------------
-- Hungarian Algorithm (adapted from cmd_customformations2 by Errrrrrr/Niobium)
-- Optimal unit-to-position assignment minimizing total travel distance.
-- O(n^3) — used for <= 40 units.
--------------------------------------------------------------------------------

local function FindHungarian(costMatrix, n)
    local colcover = {}
    local rowcover = {}
    local starscol = {}
    local primescol = {}

    for i = 1, n do
        rowcover[i] = false
        colcover[i] = false
        starscol[i] = false
        primescol[i] = false
    end

    -- Row reduction
    for i = 1, n do
        local row = costMatrix[i]
        if not row then break end
        local minVal = row[1]
        for j = 2, n do
            if row[j] < minVal then minVal = row[j] end
        end
        for j = 1, n do
            row[j] = row[j] - minVal
        end
    end

    -- Column reduction
    for j = 1, n do
        local minVal = costMatrix[1][j]
        if not minVal then break end
        for i = 2, n do
            if costMatrix[i][j] < minVal then minVal = costMatrix[i][j] end
        end
        for i = 1, n do
            costMatrix[i][j] = costMatrix[i][j] - minVal
        end
    end

    -- Initial starring
    for i = 1, n do
        local row = costMatrix[i]
        if not row then break end
        for j = 1, n do
            if (row[j] == 0) and not colcover[j] then
                colcover[j] = true
                starscol[i] = j
                break
            end
        end
    end

    -- Priming function
    local function doPrime(r, c, rmax)
        primescol[r] = c
        local starCol = starscol[r]
        if starCol then
            rowcover[r] = true
            colcover[starCol] = false
            for i = 1, rmax do
                if not rowcover[i] and (costMatrix[i][starCol] == 0) then
                    local rr, cc = doPrime(i, starCol, rmax)
                    if rr then return rr, cc end
                end
            end
            return nil
        else
            return r, c
        end
    end

    -- Step: prime zeroes
    local function stepPrimeZeroes()
        while true do
            for i = 1, n do
                if not rowcover[i] then
                    local row = costMatrix[i]
                    for j = 1, n do
                        if (row[j] == 0) and not colcover[j] then
                            local ri, rj = doPrime(i, j, i - 1)
                            if ri then return ri, rj end
                            break
                        end
                    end
                end
            end

            local minVal = mathHuge
            for i = 1, n do
                if not rowcover[i] then
                    local row = costMatrix[i]
                    for j = 1, n do
                        if (row[j] < minVal) and not colcover[j] then
                            minVal = row[j]
                        end
                    end
                end
            end

            for i = 1, n do
                local row = costMatrix[i]
                if rowcover[i] then
                    for j = 1, n do
                        if colcover[j] then row[j] = row[j] + minVal end
                    end
                else
                    for j = 1, n do
                        if not colcover[j] then row[j] = row[j] - minVal end
                    end
                end
            end
        end
    end

    -- Step: augment starring
    local function stepFiveStar(row, col)
        primescol[row] = false
        starscol[row] = col
        local ignoreRow = row

        repeat
            local noFind = true
            for i = 1, n do
                if (starscol[i] == col) and (i ~= ignoreRow) then
                    noFind = false
                    local pcol = primescol[i]
                    primescol[i] = false
                    starscol[i] = pcol
                    ignoreRow = i
                    col = pcol
                    break
                end
            end
        until noFind

        for i = 1, n do
            rowcover[i] = false
            colcover[i] = false
            primescol[i] = false
        end
        for i = 1, n do
            local scol = starscol[i]
            if scol then colcover[scol] = true end
        end
    end

    -- Main loop
    while true do
        local done = true
        for i = 1, n do
            if not colcover[i] then done = false; break end
        end

        if done then
            local pairings = {}
            for i = 1, n do
                pairings[i] = { i, starscol[i] }
            end
            return pairings
        end

        local r, c = stepPrimeZeroes()
        stepFiveStar(r, c)
    end
end

--------------------------------------------------------------------------------
-- NoX crossing-prevention heuristic (for > 40 units)
-- Adapted from cmd_customformations2 by Errrrrrr/Niobium.
-- Detects and swaps assignments where unit paths cross.
--------------------------------------------------------------------------------

local function AssignNoX(unitPositions, nodePositions, unitCount)
    local startTime = osclock()

    -- Build unit set sorted by slope
    local unitSet = {}
    local fdist = -1
    local fm = nil

    for u = 1, unitCount do
        local up = unitPositions[u]
        unitSet[u] = { up[1], up[2], up[3], nodePositions[u] } -- ux, uid, uz, node

        for i = u - 1, 1, -1 do
            local prev = unitSet[i]
            local dx, dz = prev[1] - up[1], prev[3] - up[3]
            local dist = dx * dx + dz * dz
            if dist > fdist then
                fdist = dist
                -- Fix 2: Guard against division by zero
                local dx_safe = prev[1] - up[1]
                if mathAbs(dx_safe) < 0.001 then dx_safe = 0.001 end
                fm = (prev[3] - up[3]) / dx_safe
            end
        end
    end

    -- Also check node-node distances for slope
    for i = 1, unitCount - 1 do
        local np = nodePositions[i]
        local nx, nz = np[1], np[3]
        for j = i + 1, unitCount do
            local mp = nodePositions[j]
            local dx, dz = mp[1] - nx, mp[3] - nz
            local dist = dx * dx + dz * dz
            if dist > fdist then
                fdist = dist
                -- Fix 2: Guard against division by zero
                local dx_safe = mp[1] - nx
                if mathAbs(dx_safe) < 0.001 then dx_safe = 0.001 end
                fm = (mp[3] - nz) / dx_safe
            end
        end
    end

    if fm then
        -- Fix 2: Guard against division by zero in sort function
        local fm_safe = fm
        if mathAbs(fm_safe) < 0.001 then fm_safe = 0.001 end
        local function sortFunc(a, b)
            return (a[3] + a[1] / fm_safe) < (b[3] + b[1] / fm_safe)
        end
        table.sort(unitSet, sortFunc)
        table.sort(nodePositions, sortFunc)

        for u = 1, unitCount do
            unitSet[u][4] = nodePositions[u]
        end
    end

    -- Crossing resolution passes
    local binSize = math.ceil(unitCount / 100)
    while (binSize >= 1) and (osclock() - startTime < CFG.maxAlgoTime) do
        local Ms, Cs = {}, {}
        local stFin, stFinCnt = {}, 0
        local stChk, stChkCnt = {}, unitCount

        for u = 1, unitCount do stChk[u] = u end

        while (stChkCnt > 0) and (osclock() - startTime < CFG.maxAlgoTime) do
            local u = stChk[stChkCnt]
            local ud = unitSet[u]
            local ux, uz = ud[1], ud[3]
            local mn = ud[4]
            local nx, nz = mn[1], mn[3]

            -- Fix 2: Guard against division by zero in slope calculation
            local dx_u = nx - ux
            if mathAbs(dx_u) < 0.001 then dx_u = 0.001 end
            local Mu = (nz - uz) / dx_u
            local Cu = uz - Mu * ux

            local clashes = false

            for i = 1, stFinCnt, binSize do
                local f = stFin[i]
                local fd = unitSet[f]
                if fd then
                    local tn = fd[4]
                    -- Fix 2: Guard against division by zero in intersection calculation
                    local denom = Mu - Ms[f]
                    if mathAbs(denom) < 0.001 then denom = 0.001 end
                    local ix = (Cs[f] - Cu) / denom
                    local iz = Mu * ix + Cu

                    if ((ux - ix) * (ix - nx) >= 0) and
                       ((uz - iz) * (iz - nz) >= 0) and
                       ((fd[1] - ix) * (ix - tn[1]) >= 0) and
                       ((fd[3] - iz) * (iz - tn[3]) >= 0) then
                        ud[4] = tn
                        fd[4] = mn
                        stFin[i] = stFin[stFinCnt]
                        stFinCnt = stFinCnt - 1
                        stChkCnt = stChkCnt + 1
                        stChk[stChkCnt] = f
                        clashes = true
                        break
                    end
                end
            end

            if not clashes then
                stFinCnt = stFinCnt + 1
                stFin[stFinCnt] = u
                stChkCnt = stChkCnt - 1
                Ms[u] = Mu
                Cs[u] = Cu
            end
        end

        binSize = mathFloor(binSize / 2)
    end

    -- Build result
    local result = {}
    for i = 1, unitCount do
        local unit = unitSet[i]
        result[i] = { unitID = unit[2], node = unit[4] }
    end
    return result
end

--------------------------------------------------------------------------------
-- Unit-to-position assignment (dispatches to Hungarian or NoX)
--------------------------------------------------------------------------------

local function AssignUnitsToPositions(positions, units, shifted)
    local unitCount = #units
    if unitCount == 0 then return {} end

    -- Build position array in node format {x, y, z}
    local nodes = {}
    for i, pos in ipairs(positions) do
        local x, z = ClampToMap(pos.x, pos.z)
        local y = spGetGroundHeight(x, z) or 0
        nodes[i] = { x, y, z }
    end

    if unitCount <= CFG.maxHungarianUnits then
        -- Fix 3: Filter out units with nil positions BEFORE building matrix
        local validUnits = {}
        for i = 1, unitCount do
            local uid = units[i]
            local ux, uz
            if shifted then
                ux, _, uz = GetUnitFinalPosition(uid)
            else
                ux, _, uz = spGetUnitPosition(uid)
            end
            if ux then
                validUnits[#validUnits + 1] = { uid = uid, x = ux, z = uz, idx = i }
            end
        end

        local validCount = #validUnits
        if validCount == 0 then return {} end

        -- Hungarian: build distance matrix (only for valid units)
        local distances = {}
        for i = 1, validCount do
            local ux = validUnits[i].x
            local uz = validUnits[i].z
            distances[i] = {}
            for j = 1, validCount do
                local dx, dz = nodes[j][1] - ux, nodes[j][3] - uz
                distances[i][j] = mathFloor(mathSqrt(dx * dx + dz * dz) + 0.5)
            end
        end

        -- Fix 1: Add role-distance bias to cost matrix when roleSort is enabled
        if PUP and PUP.toggles.roleSort then
            for i = 1, validCount do
                local uid = validUnits[i].uid
                local udata = PUP.units[uid]
                local role = udata and udata.role or "standard"
                for j = 1, validCount do
                    local depth = positions[j].depth or 0.5
                    -- Penalty: assault units assigned to deep positions, artillery to shallow
                    if role == "assault" and depth > 0.6 then
                        distances[i][j] = distances[i][j] * 1.5
                    elseif role == "artillery" and depth < 0.4 then
                        distances[i][j] = distances[i][j] * 1.5
                    elseif role == "scout" and depth > 0.3 and depth < 0.7 then
                        distances[i][j] = distances[i][j] * 1.2
                    end
                end
            end
        end

        local pairings = FindHungarian(distances, validCount)

        local result = {}
        for _, pair in ipairs(pairings) do
            result[validUnits[pair[1]].uid] = pair[2]  -- unitID -> position index
        end
        return result
    else
        -- NoX: build unit position array
        local unitPositions = {}
        for i = 1, unitCount do
            local ux, uy, uz
            if shifted then
                ux, uy, uz = GetUnitFinalPosition(units[i])
            else
                ux, uy, uz = spGetUnitPosition(units[i])
            end
            if ux then
                unitPositions[i] = { ux, units[i], uz }
            end
        end

        local noxResult = AssignNoX(unitPositions, nodes, unitCount)

        local result = {}
        for _, entry in ipairs(noxResult) do
            -- Find position index for this node
            for j, node in ipairs(nodes) do
                if node[1] == entry.node[1] and node[3] == entry.node[3] then
                    result[entry.unitID] = j
                    break
                end
            end
        end
        return result
    end
end

--------------------------------------------------------------------------------
-- Role-based position pre-sorting
-- Reorders positions array so front slots go to assault, back to artillery
--------------------------------------------------------------------------------

local function ApplyRoleSort(positions, units)
    if not PUP then return positions end

    -- Sort positions by depth
    local indexed = {}
    for i, pos in ipairs(positions) do
        indexed[i] = { idx = i, pos = pos, depth = pos.depth or 0.5 }
    end
    table.sort(indexed, function(a, b) return a.depth < b.depth end)

    -- Classify units by role
    local roleGroups = { assault = {}, standard = {}, artillery = {}, scout = {} }
    for _, uid in ipairs(units) do
        local udata = PUP.units[uid]
        local role = udata and udata.role or "standard"
        roleGroups[role][#roleGroups[role] + 1] = uid
    end

    -- Build ordered unit list: assault first, then standard, then scouts, then arty
    local orderedUnits = {}
    for _, uid in ipairs(roleGroups.assault) do orderedUnits[#orderedUnits + 1] = uid end
    for _, uid in ipairs(roleGroups.standard) do orderedUnits[#orderedUnits + 1] = uid end
    for _, uid in ipairs(roleGroups.scout) do orderedUnits[#orderedUnits + 1] = uid end
    for _, uid in ipairs(roleGroups.artillery) do orderedUnits[#orderedUnits + 1] = uid end

    -- Reorder positions: shallowest depth for assault, deepest for artillery
    local reorderedPositions = {}
    for i, entry in ipairs(indexed) do
        reorderedPositions[i] = entry.pos
    end

    return reorderedPositions, orderedUnits
end

--------------------------------------------------------------------------------
-- Formation command processing
--------------------------------------------------------------------------------

local function ProcessFormationCommand(cmdParams, cmdOpts)
    if not PUP or not PUP.toggles.formations then return false end

    local shape = PUP.toggles.formationShape or 1
    if shape == 1 then return false end -- Line = default, don't intercept

    local selectedUnits = spGetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return false end

    -- Filter to managed units
    local managedUnits = {}
    for _, uid in ipairs(selectedUnits) do
        if PUP.units[uid] then
            managedUnits[#managedUnits + 1] = uid
        end
    end

    if #managedUnits <= 2 then return false end -- Too few for formation

    local centerX = cmdParams[1]
    local centerZ = cmdParams[3]
    if not centerX or not centerZ then return false end

    -- Calculate facing
    local avgX, avgY, avgZ = GetAveragePosition(managedUnits)
    if not avgX then return false end
    local facing = mathAtan2(centerZ - avgZ, centerX - avgX)

    -- Calculate radius
    local radius = CalculateRadius(#managedUnits)

    -- Generate positions
    local nesting = PUP.toggles.formationNesting or 1
    local positions = GenerateNestedFormation(
        centerX, centerZ, radius, #managedUnits, facing, shape, nesting
    )
    if not positions or #positions == 0 then return false end

    -- Apply role sorting if enabled
    local unitsForAssignment = managedUnits
    if PUP.toggles.roleSort then
        positions, unitsForAssignment = ApplyRoleSort(positions, managedUnits)
    end

    -- Check if shift was held (for queued commands)
    local shifted = cmdOpts and cmdOpts.shift

    -- Assign units to positions using Hungarian / NoX
    local assignments = AssignUnitsToPositions(positions, unitsForAssignment, shifted)

    -- Issue move commands
    local frame = spGetGameFrame()
    local groupID = nextGroupID
    nextGroupID = nextGroupID + 1

    local groupUnits = {}
    local groupPositions = {}

    for uid, posIdx in pairs(assignments) do
        local pos = positions[posIdx]
        if pos then
            local defID = PUP.units[uid] and PUP.units[uid].defID
            local x, y, z = ValidatePosition(pos.x, pos.z, defID)
            if x then
                -- Fix 4: Respect shift-queue modifier
                local moveOpts = shifted and { "shift" } or {}
                spGiveOrderToUnit(uid, CMD_MOVE, { x, y, z }, moveOpts)

                -- Store formation position (numeric indices for compatibility with dodge)
                if PUP.units[uid] then
                    PUP.units[uid].formationPos = { x, 0, z }
                end

                groupUnits[#groupUnits + 1] = uid
                groupPositions[#groupPositions + 1] = { x = x, z = z }
            end
        end
    end

    -- Store group data
    if #groupUnits > 0 then
        PUP.groups[groupID] = {
            shape = shape,
            centerX = centerX,
            centerZ = centerZ,
            radius = radius,
            facingAngle = facing,
            unitIDs = groupUnits,
            positions = groupPositions,
            frame = frame,
        }
    end

    return true
end

--------------------------------------------------------------------------------
-- Group cleanup
--------------------------------------------------------------------------------

local function CleanupOldGroups(frame)
    if not PUP or not PUP.groups then return end

    for groupID, group in pairs(PUP.groups) do
        if frame - group.frame > CFG.groupCleanupAge then
            -- Clear formation positions for units in this group
            for _, uid in ipairs(group.unitIDs) do
                if PUP.units[uid] then
                    PUP.units[uid].formationPos = nil
                end
            end
            PUP.groups[groupID] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    if not WG.TotallyLegal then
        spEcho("[Puppeteer Formations] ERROR: Core library not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    TL = WG.TotallyLegal

    if not TL.IsAutomationAllowed() then
        spEcho("[Puppeteer Formations] Automation not allowed. Disabling.")
        widgetHandler:RemoveWidget(self)
        return
    end

    if not WG.TotallyLegal.Puppeteer then
        spEcho("[Puppeteer Formations] ERROR: Puppeteer Core not loaded.")
        widgetHandler:RemoveWidget(self)
        return
    end

    PUP = WG.TotallyLegal.Puppeteer

    mapSizeX = Game.mapSizeX or 8192
    mapSizeZ = Game.mapSizeZ or 8192

    hasTestMove = (spTestMoveOrder ~= nil)

    local algoInfo = "Hungarian (<=" .. CFG.maxHungarianUnits .. ") + NoX (>" .. CFG.maxHungarianUnits .. ")"
    spEcho("[Puppeteer Formations] Enabled. Assignment: " .. algoInfo ..
           ". TestMoveOrder: " .. (hasTestMove and "yes" or "no"))
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if not TL or not PUP then return false end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return false end
    if cmdID ~= CMD_MOVE then return false end

    local ok, result = pcall(ProcessFormationCommand, cmdParams, cmdOpts)
    if not ok then
        spEcho("[Puppeteer Formations] Error: " .. tostring(result))
        return false
    end

    return result
end

function widget:GameFrame(frame)
    if not TL or not PUP then return end
    if (WG.TotallyLegal.automationLevel or 0) < 1 then return end

    if frame % 60 == 0 then
        local ok, err = pcall(CleanupOldGroups, frame)
        if not ok then
            spEcho("[Puppeteer Formations] CleanupGroups error: " .. tostring(err))
        end
    end
end
