--------------------------------------------------------------------------------
-- map_scanner.lua — One-time map data scanner widget
--------------------------------------------------------------------------------
-- Scans a map on GameStart and writes all map data to JSON, then quits.
-- Used by HeadlessEngine.scan_map() for one-time map data extraction.
--
-- Output: <write_dir>/headless/output/map_data.json
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "Map Scanner",
        desc      = "Scans map data and writes to JSON for the BAR simulator",
        author    = "BAR Build Order Simulator",
        date      = "2026",
        license   = "MIT",
        layer     = 0,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- JSON encoder (minimal, self-contained)
--------------------------------------------------------------------------------

local function jsonEncode(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end
        if val == math.huge or val == -math.huge then return "null" end
        return string.format("%.6g", val)
    elseif t == "string" then
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif t == "table" then
        local isArray = (#val > 0)
        if isArray then
            local parts = {}
            local ni = indent .. "  "
            for i, v in ipairs(val) do
                parts[i] = ni .. jsonEncode(v, ni)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        else
            local parts = {}
            local ni = indent .. "  "
            for k, v in pairs(val) do
                parts[#parts + 1] = ni .. '"' .. tostring(k) .. '": ' .. jsonEncode(v, ni)
            end
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    end
    return "null"
end

--------------------------------------------------------------------------------
-- File I/O
--------------------------------------------------------------------------------

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then
        Spring.Echo("[MapScanner] ERROR: Cannot write to " .. path)
        return false
    end
    f:write(content)
    f:close()
    return true
end

--------------------------------------------------------------------------------
-- Scanner
--------------------------------------------------------------------------------

local writeDir = ""

function widget:Initialize()
    if VFS and VFS.GetWriteDir then
        writeDir = VFS.GetWriteDir()
    end
    Spring.Echo("[MapScanner] Initialized. Write dir: " .. writeDir)
end

function widget:GameStart()
    Spring.Echo("[MapScanner] Scanning map: " .. (Game.mapName or "unknown"))

    local data = {
        map_name = Game.mapName or "unknown",
        map_width = Game.mapSizeX or 0,
        map_height = Game.mapSizeZ or 0,
        wind_min = Game.windMin or 0,
        wind_max = Game.windMax or 25,
        tidal = Game.tidal or 0,
        gravity = Game.gravity or 100,
        start_positions = {},
        mex_spots = {},
        geo_vents = {},
        features = {},
        total_reclaim_metal = 0,
        total_reclaim_energy = 0,
    }

    -- Start positions: iterate over all teams
    local teamList = Spring.GetTeamList()
    if teamList then
        for _, teamID in ipairs(teamList) do
            local x, y, z = Spring.GetTeamStartPosition(teamID)
            if x and x > 0 then
                data.start_positions[#data.start_positions + 1] = {
                    team_id = teamID,
                    x = x,
                    z = z,
                }
            end
        end
    end
    Spring.Echo("[MapScanner] Start positions: " .. #data.start_positions)

    -- Metal spots
    local spots = nil
    if Spring.GetMetalMapSpots then
        spots = Spring.GetMetalMapSpots()
    end

    if spots and #spots > 0 then
        for _, s in ipairs(spots) do
            data.mex_spots[#data.mex_spots + 1] = {
                x = s.x,
                z = s.z,
                metal = s.metal or 0,
            }
        end
        Spring.Echo("[MapScanner] Metal spots (API): " .. #data.mex_spots)
    else
        -- Fallback: scan metal map manually
        Spring.Echo("[MapScanner] No metal spots from API, scanning metal map...")
        local mapX = Game.mapSizeX or 0
        local mapZ = Game.mapSizeZ or 0
        local step = 16
        local rawSpots = {}

        for x = 0, mapX, step do
            for z = 0, mapZ, step do
                local _, metal = Spring.GetGroundInfo(x, z)
                if metal and metal > 0 then
                    rawSpots[#rawSpots + 1] = { x = x, z = z, metal = metal }
                end
            end
        end

        -- Cluster nearby raw spots into mex positions
        -- Simple: find local maxima (spots with highest metal in 64-elmo radius)
        local used = {}
        for i, s in ipairs(rawSpots) do
            if not used[i] then
                local cx, cz, cm = s.x, s.z, s.metal
                local count = 1
                for j, s2 in ipairs(rawSpots) do
                    if not used[j] and j ~= i then
                        local dx = s2.x - s.x
                        local dz = s2.z - s.z
                        if dx * dx + dz * dz < 64 * 64 then
                            cx = cx + s2.x
                            cz = cz + s2.z
                            cm = math.max(cm, s2.metal)
                            count = count + 1
                            used[j] = true
                        end
                    end
                end
                used[i] = true
                data.mex_spots[#data.mex_spots + 1] = {
                    x = cx / count,
                    z = cz / count,
                    metal = cm,
                }
            end
        end
        Spring.Echo("[MapScanner] Metal spots (scan): " .. #data.mex_spots)
    end

    -- Features: geo vents, reclaim (rocks, trees, wrecks)
    local features = Spring.GetAllFeatures()
    if features then
        for _, fid in ipairs(features) do
            local defID = Spring.GetFeatureDefID(fid)
            local def = FeatureDefs[defID]
            if def then
                local x, y, z = Spring.GetFeaturePosition(fid)

                -- Check for geo vent
                if def.geoThermal then
                    data.geo_vents[#data.geo_vents + 1] = { x = x, z = z }
                end

                -- Track reclaim totals
                local fMetal = def.metal or 0
                local fEnergy = def.energy or 0
                if def.reclaimable and (fMetal > 0 or fEnergy > 0) then
                    data.total_reclaim_metal = data.total_reclaim_metal + fMetal
                    data.total_reclaim_energy = data.total_reclaim_energy + fEnergy
                end
            end
        end
    end
    Spring.Echo("[MapScanner] Geo vents: " .. #data.geo_vents)
    Spring.Echo("[MapScanner] Total reclaim: " .. math.floor(data.total_reclaim_metal) .. " metal, " .. math.floor(data.total_reclaim_energy) .. " energy")

    -- Write output
    local outDir = writeDir .. "headless/output/"
    local outPath = outDir .. "map_data.json"
    local jsonStr = jsonEncode(data, "")
    local ok = writeFile(outPath, jsonStr)

    if ok then
        Spring.Echo("[MapScanner] Data written to " .. outPath)
    else
        Spring.Echo("[MapScanner] ERROR: Failed to write " .. outPath)
    end

    -- Quit immediately
    Spring.Echo("[MapScanner] Scan complete. Quitting...")
    Spring.SendCommands("quitforce")
end
