# Research Report 07: Building Placement Logic -- Cross-AI Comparison

> **Session:** Session_2
> **Date:** 2026-02-13
> **Scope:** Deep analysis of building placement algorithms across STAI, CircuitAI/Barb3, TotallyLegal, and the Blueprint system
> **Purpose:** Identify root causes of building scattering and determine where improvements must happen
> **Synthesizes findings from:** Reports 01-06

---

## Table of Contents

1. [The Problem Statement](#1-the-problem-statement)
2. [STAI Placement (Lua Gadget)](#2-stai-placement-lua-gadget)
3. [CircuitAI / Barb3 Placement (C++ + AngelScript)](#3-circuitai--barb3-placement-c--angelscript)
4. [TotallyLegal Placement (Lua Widget)](#4-totallylegal-placement-lua-widget)
5. [Blueprint System (Lua Gadget)](#5-blueprint-system-lua-gadget)
6. [Root Cause Analysis: Why Scattering Happens](#6-root-cause-analysis-why-scattering-happens)
7. [Where the Improvement Must Happen](#7-where-the-improvement-must-happen)
8. [Comparison Table](#8-comparison-table)
9. [Actionable Takeaways for Quest](#9-actionable-takeaways-for-quest)

---

## 1. The Problem Statement

**Felenious's exact words:**

> "Add building in blocks instead of spread areas -- that's an issue we have where they waste space."

### Current Behavior

AI systems place buildings scattered across "safe" territory. Each building is placed independently via a search outward from some anchor point. The result is a sprawling, disorganized base where:

- **Space is wasted:** Large gaps between buildings that serve no purpose
- **Walking time increases:** Constructors travel farther between jobs
- **Defense coverage fragments:** Turrets and shields cannot cover compact zones
- **Nano turret efficiency drops:** Caretakers have limited range (~400 elmos); scattered buildings fall outside their coverage
- **Reclaim/repair paths lengthen:** Damaged buildings are harder to reach when spread across the map

### Desired Behavior

Buildings placed in organized clusters/blocks. Compact bases. Efficient use of space. Specific building types grouped together -- wind turbines in grids, solars in rows, converters near energy sources, defenses forming perimeters.

```
CURRENT (scattered):                    DESIRED (blocks):

    W   W       S       W              +--------+  +--------+
  W       M       S                    |W W W W |  |S S S S |
      F         W     M               |W W W W |  |S S S S |
  W     W   S       W                 +--------+  +--------+
        S       W                     +------------------+
    W       M       W                 |    F [factory]    |
                                      |  N N N   N N N   |
W = wind, S = solar, M = converter    +------------------+
F = factory, N = nano
```

The difference is stark: the current approach treats every building as an independent decision. The desired approach treats groups of similar buildings as a single planned unit.

---

## 2. STAI Placement (Lua Gadget)

**File:** `Prod/Beyond-All-Reason/luarules/gadgets/ai/STAI/buildingshst.lua`

### Algorithm: Spiral Search from Anchor Point

STAI's `FindClosestBuildSite` is the core placement function. It performs a spiral outward search from a given anchor position (typically near an existing building or the builder's location).

```lua
-- buildingshst.lua, lines 132-198 (abridged for clarity)
function BuildingsHST:FindClosestBuildSite(unittype, bx,by,bz, minDist, maxDist, builder, recycledPos)
    maxDist = maxDist or 390
    minDist = minDist or 1
    minDist = math.max(minDist, 1)

    local twicePi = math.pi * 2
    local angleIncMult = twicePi / minDist
    local maxtest = math.max(10, (maxDist - minDist) / 100)

    local checkpos = recycledPos or {}

    for radius = minDist, maxDist, maxtest do
        local angleInc = radius * twicePi * angleIncMult
        local initAngle = math.random() * twicePi  -- RANDOM starting angle
        for angle = initAngle, initAngle + twicePi, angleInc do
            local realAngle = angle
            if realAngle > twicePi then realAngle = realAngle - twicePi end

            local dx = radius * math.cos(realAngle)
            local dz = radius * math.sin(realAngle)

            local x, z = bx + dx, bz + dz
            -- clamp to map bounds
            local y = map:GetGroundHeight(x, z)
            checkpos.x, checkpos.y, checkpos.z = x, y, z

            local check = self:CheckBuildPos(checkpos, unittype, builder)
            if check then
                local buildable, px, py, pz = self:CanBuildHere(unittype, x, y, z)
                if buildable then
                    checkpos.x, checkpos.y, checkpos.z = px, py, pz
                    return checkpos
                end
            end
        end
    end
end
```

Key observations:

1. **`math.random() * twicePi`** -- Random starting angle means consecutive placements of the same building type will scatter in different directions
2. **First valid position wins** -- No scoring, no preference for adjacency to similar buildings
3. **Spiral expands outward** -- Naturally pushes buildings away from center

### Collision Avoidance: Three-Layer Check

STAI validates every candidate position through `CheckBuildPos` (lines 210-266):

```lua
function BuildingsHST:CheckBuildPos(pos, unitTypeToBuild, builder)
    -- Layer 1: Spacing check (100 elmos for factories, 50 for mexes)
    local range = self:GetBuildSpacing(unitTypeToBuild)
    local neighbours = game:getUnitsInCylinder(pos, range)
    -- reject if static building already within range

    -- Layer 2: dontBuildRects[] -- metal/geo spots (80x80 exclusion zones)
    for i, dont in pairs(self.dontBuildRects) do
        if self.ai.tool:RectsOverlap(rect, dont) then return nil end
    end

    -- Layer 3: builders[] -- planned but not yet started constructions
    for i, plan in pairs(self.builders) do
        if self.ai.tool:RectsOverlap(rect, plan) then return nil end
    end

    -- Layer 4: Land/water filter for amphibious constructors
    -- Layer 5: Pathability check (UnitCanGoHere)
end
```

And the final engine-level validation via `CanBuildHere` (lines 200-207):

```lua
function BuildingsHST:CanBuildHere(unittype, x, y, z)
    local newX, newY, newZ = Spring.Pos2BuildPos(unittype:ID(), x, y, z)
    local buildable = Spring.TestBuildOrder(unittype:ID(), newX, newY, newZ, 1)
    return buildable ~= 0, newX, newY, newZ
end
```

### Context-Aware Placement

STAI does have higher-level placement strategies that choose WHICH anchor to spiral from:

- **`searchPosNearCategories`** (line 268): Finds positions near existing buildings of specified categories, sorted by distance from builder
- **`searchPosInList`** (line 308): Searches a list of preferred positions
- **`BuildNearNano`** (line 331): Tries to place near nano turrets

These functions provide the anchor point to `FindClosestBuildSite`, but once the anchor is set, the spiral search takes over with no clustering awareness.

### Strengths

- Thorough five-layer validation prevents overlaps
- Metal/geo spot exclusion zones (`DontBuildOnMetalOrGeoSpots` creates 80x80 exclusion rects)
- Factory lane reservation via `CalculateFactoryLane` (long rect in front of factory)
- Rectangle-based tracking of all planned and in-progress construction (`sketch[]`, `builders[]`)

### Why It Scatters

1. **Random starting angle** on every call -- no memory of previous placement direction
2. **First-valid-position wins** -- no scoring for adjacency to similar buildings
3. **Each building is an independent decision** -- no concept of "I need 6 wind turbines in a block"
4. **Spiral inherently pushes outward** from seed point
5. **No template system** -- cannot say "place a 2x3 grid of wind turbines"

---

## 3. CircuitAI / Barb3 Placement (C++ + AngelScript)

**Files:**
- `Prod/Skirmish/Barb3/stable/script/src/manager/builder.as` (AngelScript manager)
- `Prod/Skirmish/Barb3/stable/config/experimental_balanced/block_map.json` (block definitions)
- `Prod/Skirmish/Barb3/stable/config/experimental_balanced/ArmadaBuildChain.json` (adjacency chains)

### Architecture: Two-Layer System

CircuitAI's building placement is split between compiled C++ and scriptable AngelScript/JSON:

```
+--------------------------------------------------+
|           AngelScript (builder.as)                |
|  Decides WHAT to build and WHEN                   |
|  Can override position via Enqueue(SBuildTask)    |
+--------------------------------------------------+
              |
              v
+--------------------------------------------------+
|           C++ Engine (CBuilderManager)            |
|  DefaultMakeTask() -- position search algorithm   |
|  Reads block_map.json for collision constraints   |
|  Calls Spring.TestBuildOrder for validation        |
+--------------------------------------------------+
              |
              v
+--------------------------------------------------+
|           JSON Config Files                       |
|  block_map.json -- blocker shapes & ignore rules  |
|  build_chain.json -- post-build adjacency chains  |
+--------------------------------------------------+
```

### block_map.json: Exclusion Zone Definitions

The block_map defines how each building category reserves space. It is purely a NEGATIVE constraint system -- it defines what CANNOT overlap, not where things SHOULD go.

```jsonc
// block_map.json (abridged)
{
  "building": {
    "class_land": {
      "wind": {
        "type": ["rectangle", "engy_low"],
        // No explicit yard -- uses explosion radius as default spacer
        "ignore": ["engy_low"]   // Winds CAN overlap with other winds
      },
      "solar": {
        "type": ["rectangle", "engy_mid"],
        "ignore": ["engy_mid", "def_low", "mex", "def_low"],
        "yard": [6, 6]           // 6 * 16 = 96 elmo spacer on each side
      },
      "fac_land_t1": {
        "type": ["rectangle", "factory"],
        "offset": [0, 5],
        "size": [8, 8],
        "yard": [0, 30]          // 30 * 16 = 480 elmo yard in front/back
      },
      "fusion": {
        "type": ["rectangle", "engy_high"],
        "yard": [5, 5],
        "ignore": ["mex", "engy_high"]
      }
    },
    "instance": {
      "wind": ["armwin", "corwin", "armtide", "cortide", "legwin", "legtide"],
      "solar": ["armsolar", "corsolar", "legsolar"],
      "fac_land_t1": ["armlab", "armvp", "armhp", "corlab", "corvp", "corhp", ...],
      ...
    }
  }
}
```

**Key properties per building class:**
- **`type`**: `[blocker_shape, structure_type]` -- shape is `rectangle` or `circle`; type is a category like `factory`, `engy_low`, `mex`, etc.
- **`size`**: Footprint in grid squares (1 square = 16 elmos)
- **`yard`**: Additional exclusion padding beyond the size
- **`offset`**: Shift of the yardmap for asymmetric buildings
- **`ignore`**: List of structure_types this class is allowed to overlap with

The `ignore` rules are crucial. Wind turbines (`engy_low`) ignore other `engy_low`, meaning they CAN be placed close together. But there is no mechanism to say they SHOULD be placed close together.

### build_chain.json: Reactive Adjacency

The build_chain system triggers additional builds AFTER a building completes. It is a hub-and-spoke model:

```jsonc
// ArmadaBuildChain.json (abridged)
"build_chain": {
  "energy": {
    "armsolar": {
      "hub": [
        [  // chain1: when a solar completes, maybe build a converter nearby
          {"unit": "armmakr", "category": "convert",
           "offset": [80, 80], "condition": {"energy": true}}
        ]
      ]
    },
    "armafus": {
      "hub": [
        [  // chain1: when an advanced fusion completes, build support
          {"unit": "armnanotc", "category": "nano",
           "offset": {"front": 5}, "priority": "normal"},
          {"unit": "armnanotc", "category": "nano",
           "offset": {"front": 10}, "priority": "normal"},
          {"unit": "armmmkr", "category": "convert",
           "offset": [120, 120]},
          {"unit": "armmmkr", "category": "convert",
           "offset": [120, -120]},
          {"unit": "armflak", "category": "defence",
           "offset": {"front": 150}, "priority": "normal"}
        ]
      ]
    }
  }
}
```

**Offset formats:**
- `[x, z]` -- explicit elmo offsets in South facing
- `{"front": N, "left": N, ...}` -- directional offsets relative to building facing

This is the closest existing system to block-based placement. But it is reactive (triggers AFTER construction completes) and limited to one-to-many relationships (one hub building spawns multiple children).

### AngelScript: Explicit Enqueue with Position

The AngelScript layer can override C++'s default position search by enqueueing tasks with explicit positions:

```cpp
// builder.as -- The SBuildTask structure (from task.as)
SBuildTask Common(Task::BuildType type, Task::Priority priority,
    CCircuitDef@ buildDef, const AIFloat3& in position,
    float shake = SQUARE_SIZE * 32,   // position randomization radius
    bool isActive = true,
    int timeout = ASSIGN_TIMEOUT)

// Usage pattern in builder.as:
IUnitTask@ _EnqueueGenericByName(Task::BuildType btype, const string &in defName,
    const AIFloat3 &in anchor, float shake, int timeoutFrames,
    Task::Priority prio = Task::Priority::NOW)
{
    CCircuitDef@ def = ai.GetCircuitDef(defName);
    if (def is null) return null;
    if (!def.IsAvailable(ai.frame)) return null;
    return aiBuilderMgr.Enqueue(
        TaskB::Common(btype, prio, def, anchor,
                      /*shake*/ shake, /*active*/ true, /*timeout*/ timeoutFrames)
    );
}
```

The critical parameter is **`shake`** -- a randomization radius applied to the anchor position. The default is `SQUARE_SIZE * 32 = 256 elmos`. This means even explicitly positioned builds get scattered by up to 256 elmos from their intended location unless shake is reduced.

For block-based placement, we would need to set `shake` to a very small value (or zero) and provide precise positions.

### Why CircuitAI Scatters

1. **`DefaultMakeTask()` in C++** performs its own position search -- we don't have the source, but it spreads from a seed point using block_map constraints
2. **block_map is negative-only** -- defines exclusion zones, not clustering preferences
3. **build_chain is reactive** -- only triggers after building completion, doesn't plan ahead
4. **Default shake of 256 elmos** randomizes positions even when explicitly set
5. **No group concept** -- no way to say "build 4 solars in a square"

---

## 4. TotallyLegal Placement (Lua Widget)

**File:** `lua/LuaUI/Widgets/01_totallylegal_core.lua`

### Algorithm: Golden-Angle Spiral Search

TotallyLegal's `FindBuildPosition` uses a similar spiral approach to STAI but with a golden-angle pattern for more uniform coverage:

```lua
-- 01_totallylegal_core.lua, lines 862-911
local function FindBuildPosition(builderID, defID, baseX, baseZ, options)
    local def = UnitDefs[defID]
    if not def then return nil, nil end

    -- Metal extractors: snap to nearest real mex spot
    if def.extractsMetal and def.extractsMetal > 0 then
        return FindNearestMexSpot(baseX, baseZ, buildArea, options)
    end

    -- Constrain to building area if provided
    local buildArea = options and options.buildArea
    if buildArea and buildArea.defined then
        baseX = buildArea.center.x
        baseZ = buildArea.center.z
    end

    -- Spiral outward from base position
    for step = 0, BUILD_CFG.maxSpiralSteps do
        local angle = step * 2.4          -- golden angle (~137.5 degrees)
        local radius = BUILD_CFG.buildSpacing * (1 + step * 0.3)
        local tx = baseX + mathCos(angle) * radius
        local tz = baseZ + mathSin(angle) * radius

        -- clamp to map bounds
        tx = mathMax(64, mathMin(tx, mapSizeX - 64))
        tz = mathMax(64, mathMin(tz, mapSizeZ - 64))

        -- Respect build area constraint
        if not skipPos then
            local result = spTestBuildOrder(defID, tx, ..., tz, 0)
            if result and result > 0 then
                return tx, tz
            end
        end
    end
    return nil, nil
end
```

### Key Differences from STAI

- **Golden angle (2.4 radians)** instead of random starting angle -- more uniform coverage but still spreads in all directions
- **`BUILD_CFG.buildSpacing`** controls minimum distance between candidate positions
- **Build area constraint** -- can restrict search to a circular region (used for defensive placement)
- **Simpler validation** -- only `TestBuildOrder`, no rectangle tracking or plan overlap check

### Current Limitations

- **Level 0** (current implementation) = overlay/advisory only, no actual placement
- **Level 1+** would use the economy widget's `BUILD_PRIORITY` list for build ordering
- Same spiral-outward pattern means same scattering behavior

### Why It Would Scatter

1. **Same spiral search pattern** as STAI
2. **First valid position wins** -- no adjacency scoring
3. **No concept of building groups** -- individual placement decisions
4. **No rectangle tracking** -- doesn't even know what else is planned nearby

---

## 5. Blueprint System (Lua Gadget)

**File:** `Prod/Beyond-All-Reason/luarules/gadgets/ruins/Blueprints/BYAR/Blueprints/*.lua`

### The Proof of Concept

The Blueprint system is used for spawning scavenger ruins -- pre-defined building arrangements placed as a group. It proves the Spring engine fully supports precise multi-building placement.

### Data Format

Each blueprint is a Lua function returning a table with exact offsets:

```lua
-- damgam_ecoStuff.lua -- T1 wind cluster (7 wind turbines in a tight hex pattern)
local function t1Eco1()
    return {
        type = types.Land,
        tiers = { tiers.T0, tiers.T1 },
        radius = 48,
        buildings = {
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = 0, zOffset = 0, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = 48, zOffset = -32, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = 48, zOffset = 16, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = -48, zOffset = -16, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = 0, zOffset = 48, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = -48, zOffset = 32, direction = 1 },
            { unitDefID = UnitDefNames.corwin_scav.id,
              xOffset = 0, zOffset = -48, direction = 1 },
        },
    }
end
```

**Blueprint entry structure:**
```
{ unitDefID, xOffset, zOffset, direction }
```

Where:
- `unitDefID` = Spring unit definition ID
- `xOffset`, `zOffset` = elmo offset from blueprint center
- `direction` = facing (0=south, 1=east, 2=north, 3=west)

### Existing Blueprint Categories

From `damgam_ecoStuff.lua` alone:

| Blueprint | Buildings | Radius | Description |
|-----------|-----------|--------|-------------|
| `t1Eco1` | 7 wind turbines | 48 | Tight hex cluster (Cortex) |
| `t1Eco2` | 7 wind turbines | 48 | Tight hex cluster (Armada) |
| `t1Eco3` | 2 adv solar + nano + 8 walls | 88 | Defended nano hub (Cortex) |
| `t1Eco4` | 2 adv solar + nano + 8 walls | 88 | Defended nano hub (Armada) |
| `t1Eco5` | 4 nanos + 4 adv solar + 2 stor + 12 walls | 128 | Full eco block (Cortex) |
| `t1Eco9` | 4 solar + 10 walls | 80 | Solar grid with walls (Armada) |
| `t2Energy1` | 2 fusion + 14 walls | 128 | Fusion pair (Armada) |
| `t2ResourcesBase1` | 1 adv fusion + 6 mmkr + 4 flak + 20 walls | 208 | Full T3 resource base |

From `damgam_bases.lua`:

| Blueprint | Buildings | Radius | Description |
|-----------|-----------|--------|-------------|
| `redBase1` | Factory + 16 turrets + 10 walls | 196 | Complete defended base (Cortex) |
| `blueBase1` | Factory + 16 turrets + 10 walls | 196 | Complete defended base (Armada) |
| `blueBase2` | 4 nanos + 20 turrets + 35 walls | 192 | Full nano-turret fortress (Armada) |
| `redBase2` | 4 nanos + 20 turrets + 35 walls | 192 | Full nano-turret fortress (Cortex) |

### Key Insight: This Is Exactly What We Want

The Blueprint system demonstrates:
- **Compact, organized layouts** -- buildings tightly packed with intentional spacing
- **Functional grouping** -- energy buildings together, defenses on perimeter, nanos near factories
- **Exact reproducibility** -- same template always produces same layout
- **Engine compatibility** -- Spring engine handles these precise placements without issues

**But it's not used by AI.** It's only used for ruins spawning by the scavenger system.

---

## 6. Root Cause Analysis: Why Scattering Happens

### The Decision-Making Flow

Every AI system follows the same fundamental pattern:

```
DECISION: "I need to build a wind turbine"
    |
    v
ANCHOR: Pick a starting point (near builder, near factory, near similar building)
    |
    v
SEARCH: Spiral outward from anchor, testing each candidate
    |
    v
VALIDATE: Check collision, pathability, build order
    |
    v
ACCEPT: First valid position wins
    |
    v
RESULT: Single building placed, no awareness of future placements
```

The problem is NOT in any single step. It is in the ABSENCE of a step between DECISION and ANCHOR:

```
DECISION: "I need to build a wind turbine"
    |
    v
[MISSING] GROUP PLAN: "I need 6 wind turbines in a 2x3 grid at position X"
    |
    v
ANCHOR: ...
```

### Root Causes (Ranked by Impact)

**1. No group planning (CRITICAL)**

Every building is placed as an individual decision. When the AI needs 6 wind turbines for energy, it makes 6 separate placement calls. Each call has no knowledge of the other 5.

```
Call 1: Place wind  -> spiral from factory, find spot at (1200, 800)
Call 2: Place wind  -> spiral from factory, find spot at (900, 1100)  -- different angle
Call 3: Place wind  -> spiral from factory, find spot at (1400, 600)  -- different angle
Call 4: Place wind  -> spiral from factory, find spot at (800, 900)   -- different angle
Call 5: Place wind  -> spiral from factory, find spot at (1100, 1300) -- different angle
Call 6: Place wind  -> spiral from factory, find spot at (1300, 700)  -- different angle
```

Result: 6 wind turbines scattered across a ~600 elmo area instead of packed in a ~100 elmo block.

**2. Spiral search inherently spreads outward (HIGH)**

The spiral pattern tests positions at increasing radii. Even if the anchor is well-chosen, the spiral has no preference for:
- Positions adjacent to buildings of the same type
- Positions that form rectangular grids
- Positions that maximize density within a region

**3. Random/deterministic angle without direction memory (HIGH)**

STAI uses `math.random() * twicePi` for the starting angle on every call. TotallyLegal uses a fixed golden angle. Neither remembers "the last wind turbine went northeast, so this one should go northeast too."

**4. Reactive adjacency, not proactive (MEDIUM)**

CircuitAI's build_chain only fires AFTER a building completes. It cannot plan ahead. When building a fusion reactor, it doesn't know yet that it will also need 6 metal makers and 2 flak towers nearby -- those decisions happen sequentially, each potentially placing further from the original hub.

**5. Negative-only constraints (MEDIUM)**

block_map defines what CANNOT overlap. There is no "positive constraint" system -- no way to say:
- "Wind turbines SHOULD be within 50 elmos of each other"
- "Converters SHOULD be within 100 elmos of energy buildings"
- "Defenses SHOULD form a perimeter around eco buildings"

**6. No spatial template system (LOW impact but HIGH solution value)**

None of the AI systems have a concept of "a wind block is a 2x3 grid of wind turbines with 48-elmo spacing." The Blueprint system has exactly this, but it's isolated in the ruins spawner.

### Visual Comparison

```
WHAT SPIRAL SEARCH PRODUCES:         WHAT TEMPLATES WOULD PRODUCE:

   Random angle = 47 deg              Template: 2x3 wind grid
         W                            +-----+-----+-----+
        / (r=100)                     | W   | W   | W   |  48 elmo spacing
  anchor                              +-----+-----+-----+
        \ (r=120)                     | W   | W   | W   |
         W                            +-----+-----+-----+
                                      Placed as single unit
   Random angle = 193 deg             at computed anchor point
        W
       / (r=110)
  anchor
       \ (r=130)
        W

   6 calls = 6 random directions     1 call = 1 organized block
```

---

## 7. Where the Improvement Must Happen

### Three Possible Intervention Points

```
+--------------------------------------------------+
|  OPTION A: Modify C++ (CBuilderManager)          |
|  Change: Core position search algorithm           |
|  Scope:  Recompile SkirmishAI.dll                 |
+--------------------------------------------------+
              |
              v
+--------------------------------------------------+
|  OPTION B: Override in AngelScript (builder.as)   |
|  Change: Calculate positions, call Enqueue()      |
|  Scope:  Script files only, hot-reloadable        |
+--------------------------------------------------+
              |
              v
+--------------------------------------------------+
|  OPTION C: Extend block_map + build_chain JSON    |
|  Change: Add template/clustering config           |
|  Scope:  JSON config only                         |
+--------------------------------------------------+
```

### Option A: Modify C++ (CircuitAI)

**What:** Modify `CBuilderManager::DefaultMakeTask()` and the underlying position search to support clustering preferences.

**Pro:**
- Most powerful -- can change the core search algorithm
- Would benefit all building types automatically
- Could implement grid-snapping, density scoring, etc.

**Con:**
- Requires recompiling `SkirmishAI.dll` (complex C++ build system)
- C++ source is not in our repo (CircuitAI engine code)
- Harder to test and iterate
- Changes affect all build types -- risk of breaking what works

**Verdict:** Too invasive for the current quest. Worth considering for a future deep integration.

### Option B: Override in AngelScript

**What:** Use `aiBuilderMgr.Enqueue(SBuildTask)` with precisely calculated positions. Bypass `DefaultMakeTask()` for building types that should be clustered.

The mechanism already exists and is proven in builder.as:

```cpp
// builder.as -- Existing pattern for explicit placement
IUnitTask@ _EnqueueGenericByName(
    Task::BuildType btype,
    const string &in defName,
    const AIFloat3 &in anchor,
    float shake,                    // <-- KEY: set to 0 for precise placement
    int timeoutFrames,
    Task::Priority prio = Task::Priority::NOW)
{
    CCircuitDef@ def = ai.GetCircuitDef(defName);
    return aiBuilderMgr.Enqueue(
        TaskB::Common(btype, prio, def, anchor,
                      /*shake*/ shake, /*active*/ true, /*timeout*/ timeoutFrames)
    );
}
```

**Pro:**
- Hot-reloadable (no recompilation)
- Can be JSON-configurable via template definitions
- Can coexist with existing C++ placement for non-templated buildings
- Easier to test and iterate
- `Enqueue` with `shake=0` gives pixel-perfect placement

**Con:**
- Must duplicate/replace some C++ decision logic
- Need to implement our own collision checking for template validation
- May need to handle edge cases where C++ would have found a valid spot but our template doesn't fit

### Option C: Extend block_map.json + build_chain.json

**What:** Add a "block template" concept to existing JSON config. Extend build_chain to plan groups proactively rather than reactively.

**Pro:**
- Most compatible with existing infrastructure
- Purely data-driven changes
- build_chain already supports offset-based placement

**Con:**
- Still constrained by C++ search algorithm for initial placement
- build_chain is reactive (post-build trigger), not proactive (pre-plan)
- Cannot create truly new behavior without code changes
- Template validation would still happen in C++ with no clustering awareness

### Recommended Approach: Option B (Primary) + Option C (Supporting)

```
+------------------------------------------------------------------+
|                    RECOMMENDED ARCHITECTURE                        |
+------------------------------------------------------------------+
|                                                                    |
|  1. TEMPLATE DEFINITIONS (JSON)                                    |
|     - Block templates for each building category                   |
|     - Stored in config/ alongside block_map.json                   |
|     - Format inspired by Blueprint system                          |
|                                                                    |
|  2. TEMPLATE PLANNER (AngelScript)                                 |
|     - Reads template definitions                                   |
|     - Finds valid anchor for entire template                       |
|     - Validates all positions in template fit                      |
|     - Enqueues all buildings with shake=0                          |
|                                                                    |
|  3. FALLBACK TO DEFAULT (C++)                                      |
|     - If template doesn't fit, fall back to DefaultMakeTask()      |
|     - block_map.json continues to prevent bad overlaps             |
|     - build_chain.json continues to handle adjacency               |
|                                                                    |
+------------------------------------------------------------------+

Flow:
  AI decides to build wind turbine
    |
    v
  Template planner checks: "wind_block_2x3" template
    |
    v
  Find anchor position for entire 2x3 block
    |
    v
  Validate all 6 positions via TestBuildOrder
    |                               |
    v (all valid)                   v (some blocked)
  Enqueue all 6 with shake=0      Fall back to single placement
    |                               via DefaultMakeTask()
    v
  Builders construct organized block
```

### Why This Works

1. **Template definitions** (JSON) give us the "positive constraint" system we lack
2. **AngelScript planner** calculates positions BEFORE any building starts
3. **`Enqueue` with `shake=0`** gives pixel-perfect placement via the existing API
4. **Fallback to C++** means we don't break anything -- worst case, we get the old scattered behavior
5. **build_chain can be extended** to trigger template placements, not just single buildings

### Template Definition Format (Proposed)

Inspired by the Blueprint system but adapted for AI use:

```jsonc
// block_templates.json (new file)
{
  "templates": {
    "wind_block_2x3": {
      "trigger": "armwin",          // when AI wants to build this unit
      "count_threshold": 1,          // trigger when building 1+ at a time
      "buildings": [
        { "unit": "armwin", "dx": 0,   "dz": 0   },
        { "unit": "armwin", "dx": 48,  "dz": 0   },
        { "unit": "armwin", "dx": 96,  "dz": 0   },
        { "unit": "armwin", "dx": 0,   "dz": 48  },
        { "unit": "armwin", "dx": 48,  "dz": 48  },
        { "unit": "armwin", "dx": 96,  "dz": 48  }
      ],
      "anchor_near": ["factory", "nano"],  // prefer placing near these
      "min_spacing_from_template": 64       // gap between template instances
    },
    "solar_block_2x2": {
      "trigger": "armsolar",
      "count_threshold": 1,
      "buildings": [
        { "unit": "armsolar", "dx": 0,   "dz": 0   },
        { "unit": "armsolar", "dx": 96,  "dz": 0   },
        { "unit": "armsolar", "dx": 0,   "dz": 96  },
        { "unit": "armsolar", "dx": 96,  "dz": 96  }
      ],
      "anchor_near": ["factory", "nano"]
    },
    "fusion_complex": {
      "trigger": "armfus",
      "count_threshold": 1,
      "buildings": [
        { "unit": "armfus",    "dx": 0,    "dz": 0    },
        { "unit": "armmmkr",   "dx": 120,  "dz": 0    },
        { "unit": "armmmkr",   "dx": -120, "dz": 0    },
        { "unit": "armmmkr",   "dx": 0,    "dz": 120  },
        { "unit": "armnanotc", "dx": 0,    "dz": -80  }
      ],
      "anchor_near": ["factory"]
    }
  }
}
```

---

## 8. Comparison Table

| Feature | STAI | CircuitAI/Barb3 | TotallyLegal | Blueprint System |
|---|---|---|---|---|
| **Language** | Lua (Gadget) | C++ + AngelScript | Lua (Widget) | Lua (Gadget) |
| **Search Algorithm** | Spiral, random start angle | C++ internal search | Spiral, golden angle | Direct offset (no search) |
| **Collision Detection** | Rectangle arrays (`dontBuildRects[]`, `sketch[]`, `builders[]`) | block_map.json class rules | `TestBuildOrder` only | N/A (ruins spawn) |
| **Clustering Support** | None | `ignore` rules allow proximity | None | Full templates with exact offsets |
| **Adjacency System** | None (some "near category" heuristics) | build_chain.json (reactive) | None | Explicit offsets per building |
| **Group Planning** | No -- each building independent | No -- each building independent | No -- each building independent | Yes -- entire group at once |
| **Position Override** | N/A (gadget, uses Spring API directly) | `aiBuilderMgr.Enqueue(SBuildTask)` with anchor + shake | N/A (widget, advisory only) | Direct `(xOffset, zOffset)` from center |
| **AI-Usable** | Yes (runs as gadget AI) | Yes (Skirmish AI) | Yes (widget, L0 = overlay) | No (ruins spawner only) |
| **Hot-Reloadable** | Limited (gadget reload) | Yes (AngelScript + JSON) | Yes (widget reload) | N/A |
| **Validation Chain** | bounds -> spacing -> rects -> land/water -> path -> TestBuildOrder | block_map constraints -> C++ search -> TestBuildOrder | TestBuildOrder | None (assumes valid spawn) |
| **Factory Lanes** | `CalculateFactoryLane` (long exclusion rect) | block_map yard `[0, 30]` on factory classes | None | Explicit offset in template |

### Search Algorithm Detail Comparison

```
STAI Spiral:                  TotallyLegal Golden:           Blueprint Direct:

  . . 5 . .                     . 7 . 3 .                   [W] [W] [W]
  . 4 . 1 .                     . . 5 . 1                   [W] [W] [W]
  3 . X . 6                     6 . X . .                    (exact positions)
  . 8 . 2 .                     . 4 . 8 .
  . . 7 . .                     2 . . . .

  Random start, wrapping         Fixed 137.5-deg step        No search needed
  First valid wins               First valid wins             All pre-computed
```

---

## 9. Actionable Takeaways for Quest

### Core Insights

1. **We need POSITIVE placement (templates), not just NEGATIVE constraints (block_map).**
   The fundamental gap across all AI systems is the absence of a "where things SHOULD go" system. block_map says "don't overlap." We need something that says "place these together."

2. **AngelScript's `Enqueue(SBuildTask)` with explicit positions is our main tool.**
   The API already exists. `TaskB::Common(btype, prio, def, position, shake=0)` gives us precise placement. We just need to calculate the right positions.

3. **block_map and build_chain should be extended, not replaced.**
   These systems handle collision avoidance and post-build adjacency. They work. We add a template layer on top that handles clustering. When templates can't fit, the existing systems serve as fallback.

4. **Blueprint format gives us a proven data structure for templates.**
   `{ unitDefID, xOffset, zOffset, direction }` is battle-tested. Our template format should mirror this, translated to JSON for AngelScript consumption.

5. **STAI's rectangle tracking shows what validation we need.**
   Before placing a template, we need to check:
   - All positions pass `TestBuildOrder`
   - No overlap with existing buildings (cylinder check)
   - No overlap with exclusion zones (metal spots, geo spots, factory lanes)
   - Builder can path to all positions
   STAI's `CheckBuildPos` is a good reference for this validation chain.

### Implementation Priority

| Priority | Task | Justification |
|----------|------|---------------|
| P0 | Define template JSON format | Foundation for everything else |
| P0 | Template validation in AngelScript | Must verify entire template fits before committing |
| P1 | Wind/solar block templates | Most common scattered buildings, highest visual impact |
| P1 | Enqueue integration (shake=0) | Connect templates to existing build system |
| P2 | Factory complex templates | Factory + nanos + defenses as a unit |
| P2 | Fusion/energy complex templates | Fusion + converters + flak as a unit |
| P3 | Template rotation (0/90/180/270) | Adapt templates to map orientation |
| P3 | Partial template placement | Place as many buildings as fit, queue rest |

### The One-Sentence Summary

**Every AI system places buildings one at a time via spiral search with no clustering awareness; the fix is a template layer in AngelScript that plans groups and enqueues them with precise positions, falling back to the existing spiral search when templates don't fit.**

---

*End of Research Report 07*
