# Research Report 01: BAR Engine Architecture Deep-Dive

> **Quest:** BARB Building AI Modification
> **Session:** Session_2
> **Date:** 2026-02-13
> **Purpose:** Understand how Beyond All Reason works at the engine level so we can modify its AI building logic.

---

## Table of Contents

1. [Spring/Recoil Engine Overview](#1-springrecoil-engine-overview)
2. [BAR Game Structure](#2-bar-game-structure)
3. [AI Interface Layer](#3-ai-interface-layer)
4. [Lua Widget System (LuaUI -- Unsynced)](#4-lua-widget-system-luaui----unsynced)
5. [Lua Gadget System (LuaRules -- Synced)](#5-lua-gadget-system-luarules----synced)
6. [Key Building APIs](#6-key-building-apis)
7. [How CircuitAI / BARb Integrates](#7-how-circuitai--barb-integrates)

---

## 1. Spring/Recoil Engine Overview

### What is Spring / Recoil?

**Spring** is a free, open-source RTS game engine originally created as a 3D remake of Total Annihilation. It has powered dozens of RTS games since the mid-2000s. The engine handles physics simulation, pathfinding, networking, rendering, and provides extensive Lua scripting APIs.

**Recoil** is a hard fork of Spring maintained by the Beyond All Reason team. It branched from the Spring 105.x tree and includes significant performance improvements, networking upgrades (tested with 80-160 player games), and BAR-specific optimizations. Despite the fork, the Lua API and overall architecture remain compatible with Spring 105 documentation.

```
Timeline:
  Spring Engine (original)
      |
      +-- v104.0 ... v105.x (stable branch)
      |
      +-- Recoil Engine (BAR fork of 105.x)
              |
              +-- Beyond All Reason game
```

**Source:** [Recoil Engine GitHub](https://github.com/beyond-all-reason/RecoilEngine)

### The Game Loop: Simulation vs Rendering

This is the most important architectural concept for our work. Spring separates the simulation from rendering completely:

```
+------------------------------------------------------------------+
|                        GAME LOOP                                  |
|                                                                   |
|  +--------------------------+   +-----------------------------+   |
|  |   SIMULATION (Synced)    |   |   RENDERING (Unsynced)      |   |
|  |                          |   |                             |   |
|  |  Fixed 30 fps (frames    |   |  As fast as possible        |   |
|  |  per sim-second at 1x    |   |  (60fps, 144fps, etc.)      |   |
|  |  game speed)             |   |                             |   |
|  |                          |   |  Purely visual -- no game   |   |
|  |  Deterministic on ALL    |   |  state changes              |   |
|  |  clients                 |   |                             |   |
|  |                          |   |  Client-local only          |   |
|  |  Physics, unit AI,       |   |                             |   |
|  |  damage, building,       |   |  Drawing, UI, camera,       |   |
|  |  resources, commands     |   |  sound, effects             |   |
|  +--------------------------+   +-----------------------------+   |
+------------------------------------------------------------------+
```

The simulation tick rate is **30 game frames per second** at 1x game speed. This is confirmed in the BARb AngelScript code:

```angelscript
// From: Prod/Skirmish/BARb/stable/script/define.as
const int SECOND = 30;  // sim frames per second at speed 1.0
const int MINUTE = 60 * SECOND;
const int SQUARE_SIZE = 8;
```

At 2x speed, 60 sim frames run per real second. At 100x, up to 3000 per second (if the CPU can keep up). The rendering pipeline runs independently -- slowing the game does not make it look like a slideshow.

### Synced vs Unsynced Code (CRITICAL)

This is **the** most important distinction for our AI work:

```
+----------------------------------------------+
|             SYNCED (Deterministic)            |
|                                               |
|  Runs identically on ALL clients              |
|  Can modify game state                        |
|  Uses streflop for identical float math       |
|  Only transfers commands over network          |
|                                               |
|  Lives in: LuaRules (gadgets), LuaGaia        |
|  Also: Skirmish AIs (C++ DLLs)               |
|                                               |
|  Examples:                                    |
|    - Unit creation/destruction                |
|    - Damage calculation                       |
|    - Resource transactions                    |
|    - Build order validation                   |
|    - AI decision-making (STAI, SimpleAI)      |
+----------------------------------------------+

+----------------------------------------------+
|            UNSYNCED (Client-Local)            |
|                                               |
|  Runs only on one client                      |
|  CANNOT modify game state directly            |
|  Can issue commands (like a player would)     |
|  Respects fog of war                          |
|                                               |
|  Lives in: LuaUI (widgets)                    |
|                                               |
|  Examples:                                    |
|    - UI overlays and HUD                      |
|    - Camera control                           |
|    - Unit selection helpers                   |
|    - Player-assistance automation             |
|    - Our TotallyLegal/Puppeteer widgets       |
+----------------------------------------------+
```

**Why this matters for us:** AI code that runs as a **gadget** (synced) sees ALL units, can modify game state directly, and is authoritative. AI code that runs as a **widget** (unsynced) only sees what the player sees (fog of war applies), and can only issue commands as if it were the player clicking.

### Networking Model

Spring uses **deterministic lockstep** networking:

1. All clients run the same simulation independently
2. Only player commands are transmitted over the network (not unit positions)
3. The server maintains a clock; clients sync to it
4. Determinism is achieved using `streflop` -- a library that forces identical floating-point behavior across all machines
5. If an AI blocks during its processing, the entire game simulation pauses

This means any synced code (gadget or skirmish AI) MUST produce identical results on all machines, or the game desyncs.

---

## 2. BAR Game Structure

### Directory Layout

The BAR game content lives in `Prod/Beyond-All-Reason/` and is structured as follows:

```
Beyond-All-Reason/
|
+-- luarules/
|   +-- gadgets/           <-- Synced game logic (gadgets)
|   |   +-- ai/            <-- AI implementations
|   |   |   +-- STAI/      <-- Lua-based medium AI
|   |   |   +-- Shard/     <-- Shard AI runtime
|   |   +-- ai_simpleai.lua
|   |   +-- AILoader.lua   <-- Boots shard-based AIs
|   |   +-- api_build_blocking.lua
|   |   +-- cmd_*.lua       <-- Command handlers
|   +-- configs/
|       +-- BARb/           <-- BARb AI config files (block_map.json)
|
+-- luaui/                  <-- Unsynced client code
|   +-- Widgets/            <-- Player widgets (F11 menu)
|   +-- main.lua, system.lua, etc.
|
+-- units/                  <-- Unit definitions
|   +-- ArmBuildings/
|   |   +-- LandFactories/  (armlab.lua, etc.)
|   |   +-- LandEconomy/    (armsolar.lua, armmex.lua, etc.)
|   |   +-- LandDefenceOffence/
|   +-- CorBuildings/
|   +-- ArmBots/, CorBots/, etc.
|   +-- armcom.lua, corcom.lua  (commanders)
|
+-- gamedata/               <-- Core game data
|   +-- unitdefs.lua        <-- Unit definition parser
|   +-- movedefs.lua        <-- Movement type definitions
|   +-- modrules.lua        <-- Game rules
|   +-- armordefs.lua       <-- Armor type definitions
|
+-- common/                 <-- Shared helpers
|   +-- stai_factory_rect.lua  <-- Build rectangle helper
|
+-- luaai.lua               <-- Registry of Lua-based AIs
+-- modinfo.lua             <-- Game metadata (shortName: BYAR)
```

### Unit Definitions

Units are defined as Lua tables in individual files under `units/`. Here is the structure of a factory definition:

```lua
-- From: Prod/Beyond-All-Reason/units/ArmBuildings/LandFactories/armlab.lua
return {
    armlab = {
        builder = true,
        buildtime = 5000,
        energycost = 950,
        metalcost = 500,
        footprintx = 6,       -- Width in build grid units (1 unit = 8 elmos)
        footprintz = 6,       -- Depth in build grid units
        maxslope = 15,        -- Max terrain slope for placement
        maxwaterdepth = 0,    -- Cannot be built in water
        health = 2900,
        workertime = 150,     -- Build speed
        -- yardmap defines walkable (o) vs exit (e) tiles:
        yardmap = "ooooooooooooooooooeeeeeeeeeeeeeeeeee",
        buildoptions = {
            [1] = "armck",     -- Construction Kbot
            [2] = "armpw",     -- Peewee
            [3] = "armrectr",  -- Resurrector
            -- ... more build options
        },
    },
}
```

Key fields for building placement:
- **footprintx / footprintz**: Size in grid squares (each = 16 elmos, i.e., 2 * SQUARE_SIZE)
- **yardmap**: String defining which tiles are open (o) and which are exit lanes (e)
- **maxslope**: Maximum terrain slope where the building can be placed
- **maxwaterdepth**: 0 means land-only

The game loads all `*.lua` files from `units/` via the `gamedata/unitdefs.lua` parser, which assembles them into the global `UnitDefs` table accessible at runtime.

### Map Format

Maps in Spring/Recoil are self-contained archives containing:
- **Heightmap**: Terrain elevation data (8-elmo resolution per heightmap pixel)
- **Metalmap**: Pixel-based metal density overlay
- **Typemap**: Terrain type per tile (affects movement speed)
- **Textures**: Diffuse, normals, specular for the terrain
- **Features**: Trees, rocks, and other map objects
- **Start positions**: Per-team spawn points

The `SQUARE_SIZE` constant of 8 elmos is fundamental -- it defines the resolution of the heightmap grid. Buildings snap to a grid that is 2 * SQUARE_SIZE = 16 elmos.

---

## 3. AI Interface Layer

### How Skirmish AIs Work

Spring provides a native C/C++ interface for "Skirmish AIs" -- standalone AI players that plug into the engine as shared libraries (DLLs on Windows, .so on Linux).

```
+------------------------------------------------------------------+
|                     ENGINE (Recoil)                               |
|                                                                   |
|   +-----------------------+     +----------------------------+    |
|   | AI Interface (C API)  |<--->| SkirmishAI.dll             |    |
|   |                       |     | (C++ CircuitAI framework)  |    |
|   | Callbacks:            |     |                            |    |
|   |  - UnitCreated()      |     |  Loads .as (AngelScript)   |    |
|   |  - UnitFinished()     |     |  files at startup          |    |
|   |  - UnitIdle()         |     |                            |    |
|   |  - UnitDestroyed()    |     |  Managers:                 |    |
|   |  - EnemyEnterLOS()    |     |   CBuilderManager          |    |
|   |  - Update()           |     |   CEconomyManager          |    |
|   |                       |     |   CFactoryManager          |    |
|   | Commands:             |     |   CMilitaryManager         |    |
|   |  - GiveOrder()        |     |   CTerrainManager          |    |
|   |  - GetUnitDef()       |     +----------------------------+    |
|   |  - GetEnemyUnits()    |                                       |
|   +-----------------------+                                       |
+------------------------------------------------------------------+
```

**The DLL Model:**

1. Each AI difficulty level is a separate configuration that loads the same `SkirmishAI.dll`
2. The DLL contains the CircuitAI C++ framework
3. At startup, the DLL reads `AIInfo.lua` to identify itself and `AIOptions.lua` for settings
4. The engine calls into the DLL using a C callback interface (defined in `SSkirmishAICallback.h`)
5. If the AI blocks during a callback, the entire game pauses -- AIs are synchronous

**Key Callbacks (C++ Interface):**

| Callback | Triggered When |
|----------|---------------|
| `UnitCreated(unitID, builderID)` | Construction of a unit begins |
| `UnitFinished(unitID)` | Construction completes |
| `UnitIdle(unitID)` | Unit's command queue becomes empty |
| `UnitDestroyed(unitID, attackerID)` | Unit dies |
| `EnemyEnterLOS(unitID)` | Enemy unit enters line of sight |
| `EnemyLeaveLOS(unitID)` | Enemy unit leaves line of sight |
| `Update(frame)` | Every simulation frame (30/sec) |

The AI can issue commands back to the engine through the callback interface, such as giving move/attack/build orders to its units.

**Reference:** [CircuitAI GitHub](https://github.com/rlcevg/CircuitAI), [Spring AI Development Wiki](https://springrts.com/wiki/AI:Development)

### Lua AIs (Alternative Path)

BAR also supports Lua-based AIs that run as gadgets. These are registered in `luaai.lua`:

```lua
-- From: Prod/Beyond-All-Reason/luaai.lua
return {
  { name = 'SimpleAI',          desc = 'EasyAI' },
  { name = 'SimpleDefenderAI',  desc = 'EasyAI' },
  { name = 'SimpleConstructorAI', desc = 'EasyAI' },
  { name = 'ScavengersAI',      desc = 'Infinite Games' },
  { name = 'STAI',              desc = 'Medium AI by @pandaro' },
  { name = 'Shard',             desc = 'Shard - Basic Shard AI' },
  { name = 'RaptorsAI',         desc = 'Raptor Defence' },
}
```

The `AILoader.lua` gadget detects which teams are assigned to Lua AIs and boots the appropriate AI code. STAI runs through the Shard runtime framework, which provides a class-based behavior tree system.

---

## 4. Lua Widget System (LuaUI -- Unsynced)

### How Widgets Work

Widgets are Lua scripts that run locally on a single client. They are the mechanism used by player-assistance tools like our TotallyLegal suite.

```
Player's Machine Only
+------------------------------------------------------------------+
|  LuaUI (Widget Handler)                                          |
|                                                                   |
|  +-- Widget A (gui_buildmenu.lua)                                |
|  +-- Widget B (gui_healthbars_gl4.lua)                           |
|  +-- Widget C (01_totallylegal_core.lua)    <-- Our code         |
|  +-- Widget D (auto_puppeteer_dodge.lua)    <-- Our code         |
|  +-- ...                                                         |
|                                                                   |
|  Loaded from: luaui/Widgets/                                     |
|  Player can toggle via F11 menu                                  |
|  Can be overridden by local copies in user's Spring data dir     |
+------------------------------------------------------------------+
```

Widgets are stored in `luaui/Widgets/` (game-bundled) or the user's local Spring data directory. Players can enable/disable them with F11. The game can ship default widgets, but players can replace them with their own versions.

### Widget Lifecycle (Callins)

These are the callback functions the engine calls on each widget:

```
LIFECYCLE:
  widget:GetInfo()        -- Returns name, desc, author, layer, enabled
  widget:Initialize()     -- Called when widget loads (game start or reload)
  widget:Shutdown()       -- Called when widget unloads

PER-FRAME:
  widget:GameFrame(n)     -- Called every simulation frame (30/sec at 1x)
  widget:Update(dt)       -- Called every draw frame (as fast as rendering)

RENDERING:
  widget:DrawWorld()      -- Draw in 3D world space (after terrain)
  widget:DrawWorldPreUnit()  -- Draw before units are rendered
  widget:DrawScreen(vsx, vsy) -- Draw in 2D screen space (HUD)
  widget:DrawInMiniMap(sx, sz) -- Draw on the minimap

UNIT EVENTS:
  widget:UnitCreated(unitID, unitDefID, unitTeam)
  widget:UnitFinished(unitID, unitDefID, unitTeam)
  widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  widget:UnitIdle(unitID, unitDefID, unitTeam)
  widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts)

INPUT:
  widget:MousePress(x, y, button)
  widget:MouseRelease(x, y, button)
  widget:KeyPress(key, mods, isRepeat)
  widget:CommandNotify(cmdID, cmdParams, cmdOpts)

GAME STATE:
  widget:GameStart()
  widget:GameOver(winningAllyTeams)
  widget:GamePaused(playerID, paused)
```

The `layer` field in `GetInfo()` controls load order -- lower layers load first. Our TotallyLegal Core uses `layer = -1` to ensure it loads before other TotallyLegal widgets that depend on it.

### WG Table (Cross-Widget Communication)

The `WG` (Widget Global) table is the standard mechanism for widgets to share data:

```lua
-- In 01_totallylegal_core.lua (our code):
-- Expose shared data to other widgets
WG.TotallyLegal = {
    GetMyUnits     = function() return myUnits end,
    GetResources   = function() return cachedResources end,
    IsAutomationAllowed = function() return automationAllowed end,
    -- ... more shared functions
}

-- In auto_puppeteer_dodge.lua (another widget):
-- Read shared data from core
local TL = WG.TotallyLegal
if TL and TL.IsAutomationAllowed() then
    local units = TL.GetMyUnits()
    -- ... use the data
end
```

The `WG` table persists across all widgets in the same LuaUI environment. Any widget can read from or write to it. This is how our multi-widget suite communicates without tight coupling.

### Spring API Available to Widgets

Key API calls widgets can use:

```lua
-- UNIT QUERIES (respects fog of war)
Spring.GetMyTeamID()                    -- Your team ID
Spring.GetTeamUnits(teamID)             -- All your units
Spring.GetUnitDefID(unitID)             -- Unit's definition
Spring.GetUnitPosition(unitID)          -- Unit's x,y,z position
Spring.GetUnitHealth(unitID)            -- Current/max health
Spring.GetUnitCommands(unitID, count)   -- Command queue

-- MAP / TERRAIN
Spring.GetGroundHeight(x, z)            -- Terrain height at position
Spring.GetMapDrawMode()                 -- Current map display mode
Spring.TestBuildOrder(defID, x,y,z, facing) -- Can a building go here?

-- GIVING ORDERS (acts like a player click)
Spring.GiveOrderToUnit(unitID, cmdID, params, opts)
Spring.GiveOrderToUnitArray(unitIDs, cmdID, params, opts)

-- SELECTION
Spring.SelectUnitArray(unitIDs)         -- Programmatically select units

-- RESOURCES
Spring.GetTeamResources(teamID, "metal")   -- Metal info
Spring.GetTeamResources(teamID, "energy")  -- Energy info
```

### Widget Limitations

Widgets **CANNOT**:
- See enemy units hidden by fog of war
- Directly modify game state (health, resources, create/destroy units)
- See units of other players that are not visible
- Access synced-only APIs (Spring.CreateUnit, Spring.SetUnitHealth, etc.)
- Bypass the command validation system

Widgets **CAN**:
- Issue any command a player could issue (move, attack, build, etc.)
- Read all visible game state
- Draw 2D/3D overlays
- Communicate with other widgets via WG table
- Control own units only

This means a widget-based AI acts exactly like a very fast player clicking -- it has the same information and capabilities as a human.

---

## 5. Lua Gadget System (LuaRules -- Synced)

### How Gadgets Work

Gadgets run in the **synced** environment -- they execute identically on all clients and have full authority over game state.

```
ALL Clients (Deterministic)
+------------------------------------------------------------------+
|  LuaRules (Gadget Handler)                                       |
|                                                                   |
|  +-- Gadget: api_build_blocking.lua    (build restrictions)      |
|  +-- Gadget: ai_simpleai.lua           (SimpleAI bot)            |
|  +-- Gadget: AILoader.lua              (STAI/Shard boot)         |
|  +-- Gadget: cmd_area_mex.lua          (area mex command)        |
|  +-- Gadget: api_resource_spot_finder   (metal/geo spots)        |
|  +-- ...hundreds more...                                         |
|                                                                   |
|  Players CANNOT toggle gadgets (unlike widgets)                  |
|  Gadgets are bundled with the game                               |
+------------------------------------------------------------------+
```

Unlike widgets, **players cannot enable/disable gadgets** -- they are part of the game and run for everyone.

### Gadget Lifecycle

A gadget can contain BOTH synced and unsynced code, separated by:

```lua
if gadgetHandler:IsSyncedCode() then
    -- SYNCED: Runs on all clients, can modify game state
    function gadget:Initialize()
        -- Setup synced state
    end

    function gadget:GameFrame(frame)
        -- Per-frame synced logic
    end

    function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
        -- React to unit creation (authoritative)
    end
else
    -- UNSYNCED: Runs locally, handles visuals/UI
    function gadget:DrawWorld()
        -- Render debug visuals, effects, etc.
    end
end
```

### How STAI Works as a Gadget

STAI is a Lua AI that runs as a synced gadget through the Shard runtime:

```
AILoader.lua (gadget)
    |
    +-- Detects teams assigned to "STAI" via Spring.GetTeamLuaAI()
    |
    +-- Loads Shard runtime (luarules/gadgets/ai/shard_runtime/)
    |
    +-- Boots STAI (luarules/gadgets/ai/STAI/boot.lua)
        |
        +-- Loads ai.lua -> creates STAI class
        +-- Loads behaviour modules:
            +-- buildersbst.lua   (construction behaviour)
            +-- buildingshst.lua  (building placement/management)
            +-- maphst.lua        (terrain analysis)
            +-- ecohst.lua        (economy management)
            +-- labsbst.lua       (factory management)
            +-- etc.
```

Because STAI runs as a synced gadget, it can:
- See ALL units on the map (no fog of war)
- Directly call `Spring.GiveOrderToUnit()` authoritatively
- Call `Spring.TestBuildOrder()` and `Spring.Pos2BuildPos()` for placement
- Access `Spring.GetGroundHeight()` at any map location

Here is an example of STAI's build placement code:

```lua
-- From: Prod/Beyond-All-Reason/luarules/gadgets/ai/STAI/buildingshst.lua

function BuildingsHST:CanBuildHere(unittype, x, y, z)
    local newX, newY, newZ = Spring.Pos2BuildPos(unittype:ID(), x, y, z)
    local buildable = Spring.TestBuildOrder(unittype:ID(), newX, newY, newZ, 1)
    if buildable == 0 then buildable = false end
    return buildable, newX, newY, newZ
end

function BuildingsHST:FindClosestBuildSite(unittype, bx, by, bz, minDist, maxDist, builder)
    -- Spiral search outward from position
    for radius = minDist, maxDist, maxtest do
        for angle = initAngle, initAngle + twicePi, angleInc do
            local x, z = bx + dx, bz + dz
            local y = map:GetGroundHeight(x, z)
            local check = self:CheckBuildPos(checkpos, unittype, builder)
            if check then
                local buildable, px, py, pz = self:CanBuildHere(unittype, x, y, z)
                if buildable then
                    return {x = px, y = py, z = pz}
                end
            end
        end
    end
end
```

### Key Difference: Gadgets vs Widgets for AI

| Aspect | Gadget (Synced) | Widget (Unsynced) |
|--------|----------------|-------------------|
| Sees all units | Yes | Only visible (fog of war) |
| Modifies game state | Yes (authoritative) | No (only commands) |
| Runs on | All clients | One client |
| Player toggleable | No | Yes (F11) |
| Can desync game | Yes, if buggy | No |
| Build order validation | Direct API access | Same API, acts like player |
| Examples | STAI, SimpleAI, Scavengers | TotallyLegal, Puppeteer |

---

## 6. Key Building APIs

These are the critical engine functions for building placement. They are available to both gadgets and widgets (though behavior differs slightly in authority).

### Spring.TestBuildOrder

Tests whether a building can be placed at a given position.

```lua
local result = Spring.TestBuildOrder(unitDefID, x, y, z, facing)

-- Returns:
--   0 = blocked (terrain, existing structure, etc.)
--   1 = blocked by mobile unit (unit in the way but can move)
--   2 = free to build
-- Also returns featureID if a reclaimable feature is blocking
```

**Facing values:**
- 0 = "south" (default, exits toward +Z)
- 1 = "east"
- 2 = "north"
- 3 = "west"

### Spring.Pos2BuildPos

Snaps a world position to the valid build grid:

```lua
local snappedX, snappedY, snappedZ = Spring.Pos2BuildPos(unitDefID, x, y, z)
```

Buildings snap to a grid of 2 * SQUARE_SIZE = 16 elmos. This function takes a raw position and returns the nearest valid build grid position for the given unit definition. The snap accounts for the unit's footprint size (even-sized footprints snap differently than odd-sized).

### Spring.GetGroundHeight

Returns terrain elevation at a map position:

```lua
local height = Spring.GetGroundHeight(x, z)
-- Returns the ground height at position (x, z)
-- Negative values = underwater
-- Used to determine if a position is on land or water
```

### Spring.GiveOrderToUnit

Issues a command to a unit, including build orders:

```lua
-- Move order
Spring.GiveOrderToUnit(unitID, CMD.MOVE, {x, y, z}, {})

-- Build order (note: negative unitDefID for build commands)
Spring.GiveOrderToUnit(builderID, -unitDefID, {x, y, z, facing}, {})

-- Queued build order (shift-queue)
Spring.GiveOrderToUnit(builderID, -unitDefID, {x, y, z, facing}, {"shift"})

-- Using CMD.INSERT for queue insertion
Spring.GiveOrderToUnit(unitID, CMD.INSERT, {
    position,     -- queue position (0 = front)
    cmdID,        -- the command to insert
    cmdOpt,       -- command options
    x, y, z       -- command parameters
}, {"alt"})
```

### Synced-Only: Spring.CreateUnit

Only available in gadgets (synced context):

```lua
-- Directly spawn a unit (no builder needed)
Spring.CreateUnit(unitDefName, x, y, z, facing, teamID)

-- Can also specify "being built" state
Spring.CreateUnit(unitDefName, x, y, z, facing, teamID, true)  -- nanoframe
```

### Combined Build Placement Pattern

The standard pattern for finding and executing a build position:

```lua
-- 1. Choose a candidate position
local candidateX, candidateZ = somePosition.x, somePosition.z

-- 2. Get ground height
local candidateY = Spring.GetGroundHeight(candidateX, candidateZ)

-- 3. Snap to build grid
local buildX, buildY, buildZ = Spring.Pos2BuildPos(defID, candidateX, candidateY, candidateZ)

-- 4. Test if buildable
local result = Spring.TestBuildOrder(defID, buildX, buildY, buildZ, facing)
if result ~= 0 then  -- 0 = blocked
    -- 5. Issue the build order
    Spring.GiveOrderToUnit(builderID, -defID, {buildX, buildY, buildZ, facing}, {})
end
```

---

## 7. How CircuitAI / BARb Integrates

### Architecture Overview

BARb (BARbarIAn) is the primary AI for Beyond All Reason. It uses the **CircuitAI** C++ framework by rlcevg as its runtime, with game-specific logic written in **AngelScript** (.as files).

```
+------------------------------------------------------------------+
|  Engine (Recoil)                                                  |
|      |                                                            |
|      v                                                            |
|  C AI Interface                                                   |
|      |                                                            |
|      v                                                            |
|  SkirmishAI.dll (CircuitAI C++ Framework)                        |
|      |                                                            |
|      +-- CBuilderManager   (building placement, task assignment) |
|      +-- CEconomyManager   (resource tracking, income/expense)   |
|      +-- CFactoryManager   (production queues)                   |
|      +-- CMilitaryManager  (combat unit control)                 |
|      +-- CTerrainManager   (map analysis, block_map.json)        |
|      |                                                            |
|      +-- AngelScript VM                                          |
|          |                                                        |
|          +-- script/common.as     (factions, armor, categories)  |
|          +-- script/define.as     (constants: SECOND=30, etc.)   |
|          +-- script/unit.as       (role/attribute definitions)   |
|          +-- script/task.as       (task types and builders)      |
|          +-- script/<difficulty>/                                 |
|              +-- init.as          (AI initialization)            |
|              +-- main.as          (main loop, update hooks)      |
|              +-- manager/                                        |
|                  +-- builder.as   (build task creation)          |
|                  +-- economy.as   (eco thresholds)               |
|                  +-- factory.as   (factory production)           |
|                  +-- military.as  (combat behavior)              |
+------------------------------------------------------------------+
```

### The DLL + AngelScript Model

The relationship between the DLL and scripts:

```
File: Prod/Skirmish/BARb/stable/
    |
    +-- SkirmishAI.dll          <-- Compiled C++ (CircuitAI framework)
    +-- AIInfo.lua              <-- Identity: name="BARb", interface="C"
    +-- AIOptions.lua           <-- Configurable difficulty options
    +-- config/
    |   +-- block_map.json      <-- Building placement constraints
    |   +-- hard/
    |       +-- block_map.json  <-- Difficulty-specific overrides
    +-- script/
        +-- common.as           <-- Shared definitions (factions)
        +-- define.as           <-- Constants
        +-- unit.as             <-- Unit role taxonomy
        +-- task.as             <-- Task type system
        +-- hard/
            +-- init.as         <-- Boot sequence
            +-- main.as         <-- Main update loop
            +-- manager/
                +-- builder.as  <-- Build task logic
                +-- economy.as  <-- Economy decisions
                +-- factory.as  <-- Factory production
                +-- military.as <-- Combat logic
```

The C++ DLL loads all `.as` files at startup. The `init.as` file tells the framework which JSON profile configs to load:

```angelscript
// From: Prod/Skirmish/BARb/stable/script/hard/init.as
SInitInfo AiInit()
{
    AiLog("hard AngelScript Rules!");
    SInitInfo data;
    data.armor = InitArmordef();
    data.category = InitCategories();

    // These strings reference JSON config files in the config/ directory
    @data.profile = @(array<string> = {
        "behaviour", "block_map", "build_chain",
        "commander", "economy", "factory", "response"
    });
    return data;
}
```

### Building Placement: The block_map.json System

The C++ `CTerrainManager` uses `block_map.json` to define placement constraints for each building class. This is where building spacing, exclusion zones, and factory yards are configured:

```json
// From: Prod/Skirmish/BARb/stable/config/block_map.json (excerpt)
{
"building": {
    "class_land": {
        "fac_land": {
            "type": ["rectangle", "factory"],
            "offset": [0, 7],
            "yard": [8, 20],
            "ignore": ["def_low"]
        },
        "fac_air": {
            // ... air factory constraints
        }
    }
},
"terrain": {
    "analyze": "armcom",
    "area_min_tiles": 32,
    "lake_tiles": 100
}
}
```

**Key concepts in block_map.json:**
- **type**: `[shape, structure_type]` -- Rectangle or circle blocker, factory/mex/geo/pylon/etc.
- **offset**: Position offset from unit center (in units of 16 elmos)
- **yard**: Extra space around the building (blocker_size = size + yard)
- **ignore**: Which other structure types can overlap this blocker
- Units of measurement: 1 size unit = SQUARE_SIZE * 2 = 16 elmos

The C++ framework does the heavy lifting of spatial search using these constraints. When the `CBuilderManager` needs to place a building, it:

1. Reads the block_map constraints for the building class
2. Uses `CTerrainManager` to find valid terrain
3. Checks against existing blocker rectangles
4. Returns a validated position

### AngelScript's Level of Control

The `.as` scripts interact with the C++ managers through exposed API objects:

```angelscript
// Key global objects available in AngelScript:
ai              // CCircuitAI - the main AI instance
aiBuilderMgr    // CBuilderManager - handles construction
aiEconomyMgr    // CEconomyManager - resource tracking
aiFactoryMgr    // CFactoryManager - production queues
aiMilitaryMgr   // CMilitaryManager - combat
aiTerrainMgr    // CTerrainManager - map analysis
aiSetupMgr      // CSetupManager - configuration
```

**Creating a build task with explicit position:**

```angelscript
// From: Prod/Skirmish/BARb/stable/script/task.as
SBuildTask Common(
    Task::BuildType type,
    Task::Priority priority,
    CCircuitDef@ buildDef,
    const AIFloat3& in position,
    float shake = SQUARE_SIZE * 32,  // Randomize position by offset
    bool isActive = true,
    int timeout = ASSIGN_TIMEOUT
)
{
    SBuildTask ti;
    ti.type = type;
    ti.priority = priority;
    @ti.buildDef = buildDef;
    ti.position = position;
    ti.shake = shake;        // <-- How much to jitter the position
    ti.isActive = isActive;
    ti.timeout = timeout;
    ti.cost = SResource(0.f, 0.f);
    // ...
    return ti;
}
```

**Default vs Custom task creation:**

```angelscript
// From: Prod/Skirmish/BARb/stable/script/hard/manager/builder.as

// The default path: C++ decides everything
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
    return aiBuilderMgr.DefaultMakeTask(unit);
}

// But you CAN override with explicit positions:
// aiBuilderMgr.Enqueue(SBuildTask) -- queue a task with specific position
// The 'shake' parameter controls how much the C++ side can adjust the position
```

### The Key Question: How Much Control Does AngelScript Have?

Based on the code analysis:

**AngelScript CAN:**
- Override the default task creation (`AiMakeTask` returns a custom task)
- Create `SBuildTask` with explicit positions and shake values
- Set task priority (LOW, NORMAL, HIGH, NOW)
- Control which units get assigned to building tasks
- Set unit attributes (e.g., `BASE` attribute for build-near-base behavior)
- Query unit definitions, positions, resource state

**The C++ layer handles:**
- Actual position search within the `block_map.json` constraint system
- Terrain analysis (slope, water, area connectivity)
- Blocker rectangle collision checking
- The final `TestBuildOrder` validation
- Path planning for builders

**The `shake` parameter is the key lever.** When AngelScript creates a build task with `shake = 0`, it requests an exact position. With larger `shake` values (default: `SQUARE_SIZE * 32` = 256 elmos), the C++ side randomizes within that radius while respecting constraints.

### Build Type Taxonomy

The task system defines a complete taxonomy of building types:

```angelscript
// From: Prod/Skirmish/BARb/stable/script/task.as
enum BuildType {
    FACTORY = 0,
    NANO,       // Nano turrets (assist builders)
    STORE,      // Resource storage
    PYLON,      // Energy pylon
    ENERGY,     // Power plants
    GEO,        // Geothermal
    GEOUP,      // Geothermal upgrade
    DEFENCE,    // Turrets / defenses
    BUNKER,     // Bunker structures
    BIG_GUN,    // Super weapons (Big Bertha, etc.)
    RADAR,      // Radar towers
    SONAR,      // Sonar stations
    CONVERT,    // Metal converters
    MEX,        // Metal extractors
    MEXUP,      // Mex upgrade (T1 -> T2)
    REPAIR,     // Repair task
    RECLAIM,    // Reclaim task
    RESURRECT,  // Resurrect wreckage
    RECRUIT,    // Request units
    TERRAFORM,  // Terraform terrain
}
```

Each build type maps to a class in `block_map.json`, which defines its spatial constraints.

---

## Summary: Architecture Layers for Our Quest

```
+=====================================================+
| Layer 4: AngelScript (.as)                          |
|   - Game-specific AI behavior                       |
|   - Task creation, economy thresholds               |
|   - CAN specify positions + shake                   |
|   - Our primary modification target for BARb        |
+=====================================================+
         |  calls into
         v
+=====================================================+
| Layer 3: CircuitAI C++ (SkirmishAI.dll)             |
|   - Building placement search algorithm             |
|   - block_map.json constraint system                |
|   - Terrain analysis, blocker management            |
|   - We modify config (JSON), not C++ code           |
+=====================================================+
         |  uses
         v
+=====================================================+
| Layer 2: Spring/Recoil Engine APIs                  |
|   - TestBuildOrder, Pos2BuildPos                    |
|   - GetGroundHeight, GiveOrderToUnit                |
|   - Deterministic simulation at 30fps               |
+=====================================================+
         |  runs on
         v
+=====================================================+
| Layer 1: Recoil Engine Core                         |
|   - Pathfinding, physics, networking                |
|   - Heightmap, metalmap, unitdefs                   |
|   - Lockstep deterministic simulation               |
+=====================================================+

ALTERNATIVE PATH (our widgets):
+=====================================================+
| Layer W: Lua Widgets (LuaUI)                        |
|   - TotallyLegal, Puppeteer suites                  |
|   - Runs unsynced, client-local                     |
|   - Issues commands like a player                   |
|   - Limited: fog of war, no direct state changes    |
|   - Communicates via WG table                       |
+=====================================================+

ALTERNATIVE PATH (STAI):
+=====================================================+
| Layer G: Lua Gadgets (LuaRules)                     |
|   - STAI, SimpleAI                                  |
|   - Runs synced, sees everything                    |
|   - BuildingsHST does spiral search placement       |
|   - Full Spring API access                          |
+=====================================================+
```

### What This Means for Our Building AI Quest

1. **BARb (AngelScript + C++ DLL):** We can modify the `.as` scripts to change high-level build decisions (what to build, priority, approximate position). The C++ layer handles fine-grained placement using `block_map.json`. We can also edit JSON configs.

2. **STAI (Lua gadget):** We can directly modify the Lua code for placement algorithms. The `BuildingsHST` module shows us the spiral-search pattern and how `TestBuildOrder`/`Pos2BuildPos` are used in practice.

3. **Widget approach (our code):** We can build widgets that assist with building placement visualization and automate build orders as a player would. Limited by fog of war but safe from desyncs.

4. **The `block_map.json` system** is the key to understanding BARb's building spacing. Each building class has defined blockers (rectangles/circles), offsets, and ignore lists that determine where buildings can be placed relative to each other.

---

## Sources

- [Spring RTS Wiki - Lua Beginners FAQ](https://springrts.com/wiki/Lua_Beginners_FAQ)
- [Spring RTS Wiki - Lua Environments (Synced vs Unsynced)](https://springrts.com/wiki/Lua:Environments)
- [Spring RTS Wiki - Lua Callins](https://springrts.com/wiki/Lua:Callins)
- [Spring RTS Wiki - Lua SyncedCtrl](https://springrts.com/wiki/Lua_SyncedCtrl)
- [Spring RTS Wiki - Lua UnsyncedCtrl](https://springrts.com/wiki/Lua_UnsyncedCtrl)
- [Spring RTS Wiki - Lua SyncedRead](https://springrts.com/wiki/Lua_SyncedRead)
- [Spring RTS Wiki - AI Development](https://springrts.com/wiki/AI:Development)
- [Spring RTS Wiki - Lua CMDs](https://springrts.com/wiki/Lua_CMDs)
- [Spring RTS Wiki - Lua Widgets](https://springrts.com/wiki/Lua_Widgets)
- [CircuitAI GitHub (rlcevg)](https://github.com/rlcevg/CircuitAI)
- [CircuitAI - barbarian branch](https://github.com/rlcevg/CircuitAI/tree/barbarian)
- [Recoil Engine GitHub](https://github.com/beyond-all-reason/RecoilEngine)
- [Recoil Engine Documentation](https://beyond-all-reason.github.io/RecoilEngine/)
- [Beyond All Reason GitHub](https://github.com/beyond-all-reason/Beyond-All-Reason)
- [BAR AI Policy](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/AI_POLICY.md)
- [Beyond All Reason Official Site](https://www.beyondallreason.info)
- [Spring RTS Forum - Deterministic Physics](https://springrts.com/phpbb/viewtopic.php?t=33030)
- [Spring RTS Forum - Networking Model](https://springrts.com/phpbb/viewtopic.php?t=37637)
- [Spring RTS Forum - Game Speed](https://springrts.com/phpbb/viewtopic.php?t=30623)
- [Spring RTS Forum - Pos2BuildPos](https://springrts.com/phpbb/viewtopic.php?t=26709)
- [Spring RTS Forum - GiveOrderToUnit](https://springrts.com/phpbb/viewtopic.php?t=12020)
- [Wikibooks - Lua in SpringRTS/Gadgets](https://en.wikibooks.org/wiki/Lua_in_SpringRTS/Gadgets)
- [Beyond All Reason Wikipedia](https://en.wikipedia.org/wiki/Beyond_All_Reason)
