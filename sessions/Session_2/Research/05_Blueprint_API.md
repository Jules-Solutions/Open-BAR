# Research Report 05: BAR Blueprint System & Block-Based Building AI

> **Session:** Session_2
> **Date:** 2026-02-13
> **Scope:** Analysis of BAR's ruins Blueprint system for applicability to AI block-based building
> **Source Files Analyzed:**
> - `luarules/gadgets/ruins/Blueprints/BYAR/blueprint_controller.lua`
> - `luarules/gadgets/ruins/Blueprints/BYAR/blueprint_tiers.lua`
> - `luarules/gadgets/ai_ruins.lua` (main ruins spawner gadget)
> - `luarules/gadgets/ai_ruin_blueprint_tester.lua` (dev testing gadget)
> - 5 blueprint definition files (factory_centers, bases, T2_Eco, LLT_defences, small_outposts)
> - `luarules/configs/BARb/stable/config/hard/build_chain.json` (for comparison)

---

## 1. What Blueprints Are in BAR

Blueprints in Beyond All Reason are **pre-defined base layouts** -- collections of buildings arranged in specific spatial patterns. They are currently used for a single purpose: the **ruins system** (also called "Scavenger ruins").

### Gameplay Context

When ruins are enabled in a BAR game, the map spawns with pre-built clusters of damaged structures belonging to the Gaia team. These represent the remnants of a "previous civilization" -- abandoned bases, defensive outposts, economy clusters, and factory complexes scattered across the terrain. Players can reclaim these ruins for resources, fight through their static defences, or use them as terrain features in their strategy.

The ruins system is:
- **Enabled via game mod options** (`Spring.GetModOptions().ruins == "enabled"`)
- **Spawned at game start** by the `ai_ruins.lua` gadget
- **Configurable density** -- from "veryrare" (0.25x) through "verydense" (4x)
- **Randomized** -- blueprint selection, rotation, and mirroring are all randomized

Crucially, **blueprints are NOT currently used by any AI for building placement**. The BARb AI uses an entirely different system (`build_chain.json`) for deciding what and where to build. The blueprint system lives in Lua gadget-space, while the AI operates in AngelScript.

### What the Blueprint Library Contains

There are **21 blueprint definition files**, each containing multiple blueprint functions:

| File | Blueprint Count | Description |
|------|----------------|-------------|
| `Damgam_factory_centers.lua` | 1 | Factory clusters with nanos and defences |
| `damgam_factory_centers_2.lua` | ? | Additional factory layouts |
| `damgam_bases.lua` | 4 | Full base layouts (red/blue factions) |
| `damgam_T2_Eco.lua` | 12 | T2 economy clusters (fusion reactors + metal makers) |
| `damgam_LLT_defences.lua` | 14 | T1 defensive outposts (LLT corners, crosses) |
| `damgam_small_outposts.lua` | 17 | Mixed outposts (firebases, wind farms, gantries, etc.) |
| `damgam_HLT_defences.lua` | ? | T2 defensive positions |
| `damgam_epic_defences.lua` | ? | T3 major defensive installations |
| `damgam_ecoStuff.lua` | ? | Economy buildings |
| `damgam_rectors.lua` | ? | Constructor-focused layouts |
| `damgam_Jammers.lua` | ? | Radar jamming outposts |
| `damgam_tacnukes.lua` | ? | Tactical nuke installations |
| `damgam_shielded_LRPCs.lua` | ? | Shielded long-range plasma cannons |
| `IronFist_Defences.lua` | ? | Community-contributed defences |
| `KrashKourse_land.lua` | ? | Community land blueprints |
| `KrashKourse_sea.lua` | ? | Community sea blueprints |
| `Nikuksis_land.lua` | ? | Community land blueprints |
| `hermano_T2_Eco.lua` | ? | T2 eco variants |
| `Damgam_Basic_Sea.lua` | ? | Sea-based blueprints |
| `link_sea.lua` | ? | Sea blueprints |
| `damgam_tiny_defences_T1.lua` | ? | Small T1 defence clusters |

In the 5 files analyzed in detail, there are **48+ distinct blueprint functions**, many with internal randomization that yields additional variant layouts.

---

## 2. Blueprint Controller

The blueprint controller (`blueprint_controller.lua`) is the orchestration layer that loads, indexes, and serves blueprints to the ruins spawner.

### Loading Pipeline

```lua
-- Step 1: Load tier/type configuration
local blueprintConfig = VFS.Include(
    'luarules/gadgets/ruins/Blueprints/' .. Game.gameShortName .. '/blueprint_tiers.lua'
)
local tiers = blueprintConfig.Tiers
local types = blueprintConfig.BlueprintTypes

-- Step 2: Define the storage structure (type -> tier -> list of blueprint functions)
local constructorBlueprints = {
    [types.Land] = {
        [tiers.T0] = { },
        [tiers.T1] = { },
        [tiers.T2] = { },
        [tiers.T3] = { },
        [tiers.T4] = { },
    },
    [types.Sea] = {
        [tiers.T0] = { },
        [tiers.T1] = { },
        [tiers.T2] = { },
        [tiers.T3] = { },
        [tiers.T4] = { },
    },
}
```

The controller uses `VFS.DirList` to discover all `.lua` files in the Blueprints directory, then iterates through each file's exported functions:

```lua
local function populateBlueprints(blueprintType)
    local blueprintsDirectory = VFS.DirList(
        blueprintsConfig[1].directory, '*.lua'
    )

    for _, blueprintFile in ipairs(blueprintsDirectory) do
        local success, fileContents = pcall(VFS.Include, blueprintFile)
        if success then
            for _, blueprintFunction in ipairs(fileContents) do
                local blueprintSuccess, blueprint = pcall(blueprintFunction)
                if blueprintSuccess then
                    -- Index by type AND each tier it belongs to
                    for _, tier in ipairs(blueprint.tiers) do
                        table.insert(
                            blueprintTable[blueprint.type][tier],
                            blueprintFunction
                        )
                    end
                end
            end
        end
    end
    insertDummyBlueprints(blueprintType)
end
```

Key observations:
- **Blueprint functions are stored, not their results** -- each call to a blueprint function generates a fresh layout (important for randomized variants)
- A single blueprint function can be indexed into **multiple tiers** (e.g., T2 and T3 simultaneously)
- Dummy blueprints fill empty tier/type slots to prevent nil errors
- The entire population happens at load time (line 93: `populateBlueprints(1)`)

### Selection API

The controller exposes two simple functions:

```lua
return {
    GetRandomLandBlueprint = getRandomConstructorLandBlueprint,
    GetRandomSeaBlueprint = getRandomConstructorSeaBlueprint,
}
```

Both take a `tier` parameter and return a fresh blueprint object:

```lua
local getRandomBluePrint = function(blueprintType, tier, type)
    local blueprintList = blueprintTable[type][tier]
    local blueprintFunction = blueprintList[math.random(1, #blueprintList)]
    local blueprint = blueprintFunction()  -- CALL the function to generate fresh layout
    return blueprint
end
```

### Type System

Only two types exist:
- `Land = 1` -- terrestrial blueprints
- `Sea = 2` -- naval/amphibious blueprints

### Blueprint Types (Internal Classification)

The controller defines an additional classification that is NOT currently used in the selection API but exists in the data model:

```lua
local blueprintTypes = {
    Constructor = 1,
    Spawner     = 2,
    Ruin        = 3,
}
```

Currently only `Constructor` (type 1) blueprints are loaded. The `Spawner` and `Ruin` types appear to be reserved for future expansion.

---

## 3. Blueprint File Format

Every blueprint definition file follows a consistent pattern.

### File Structure

```lua
-- 1. Load shared configuration
local blueprintConfig = VFS.Include(
    'luarules/gadgets/ruins/Blueprints/' .. Game.gameShortName .. '/blueprint_tiers.lua'
)
local tiers = blueprintConfig.Tiers
local types = blueprintConfig.BlueprintTypes
local UDN = UnitDefNames

-- 2. Optional helper functions
local function getRandomNanoTowerID()
    return math.random(0, 1) == 0 and UDN.armnanotc_scav.id or UDN.cornanotc_scav.id
end

-- 3. Blueprint functions (one per layout)
local function myBlueprint()
    return {
        type = types.Land,              -- Land or Sea
        tiers = { tiers.T2, tiers.T3 }, -- Which tiers this applies to
        radius = 192,                   -- Bounding radius in elmos
        buildings = {                   -- Array of building placements
            { unitDefID = UDN.armfus_scav.id, xOffset = 0, zOffset = 0, direction = 1 },
            { unitDefID = UDN.armnanotc_scav.id, xOffset = 80, zOffset = 40, direction = 2 },
            -- ... more buildings ...
        },
    }
end

-- 4. Export all blueprint functions as an array
return {
    myBlueprint,
}
```

### Building Entry Format

Each building in a blueprint is a table with exactly 4 fields:

```lua
{
    unitDefID = <integer>,   -- Spring engine unit definition ID
    xOffset   = <integer>,   -- X displacement from anchor point (elmos)
    zOffset   = <integer>,   -- Z displacement from anchor point (elmos)
    direction = <integer>,   -- Facing: 0=south, 1=east, 2=north, 3=west
}
```

The `unitDefID` is resolved at load time via `UnitDefNames` (e.g., `UDN.armfus_scav.id`). All units in blueprints use the `_scav` variant (Scavenger faction units), which is important -- the blueprint tester gadget strips the `_scav` suffix when spawning for testing:

```lua
local nonscavname = string.gsub(UnitDefs[unitDefID].name, "_scav", "")
```

### Offset Coordinate System

Offsets are measured in **elmos** (BAR's base distance unit, equivalent to 1 heightmap pixel = 8 elmos). The coordinate system:
- **xOffset**: East-West axis. Positive = East, Negative = West.
- **zOffset**: North-South axis. Positive = South, Negative = North.
- Both are relative to a **center anchor point** (typically where the primary building sits at `0, 0`).

Common offset values and what they represent:
- `24-48`: Adjacent small buildings (dragon's teeth, walls, small turrets)
- `72-96`: One building-width spacing (typical for nanos around a factory)
- `128-196`: Full building cluster radius (factories, fusion reactors)
- `200+`: Outer perimeter defences

### Randomization Techniques

Blueprints employ several randomization strategies:

**1. Variant selection within a function:**
```lua
local function t1UnitSpammer()
    local r = math_random(0, 2)  -- 3 completely different layouts
    if r == 0 then
        buildings = { ... }      -- Cortex bot lab variant
    elseif r == 1 then
        buildings = { ... }      -- Cortex vehicle plant variant
    elseif r == 2 then
        buildings = { ... }      -- Cortex air plant variant
    end
    return { ... buildings = buildings }
end
```

**2. Random unit selection from a pool:**
```lua
local randomturrets = {
    UDN.armllt_scav.id, UDN.armllt_scav.id,  -- weighted toward LLTs
    UDN.armhlt_scav.id,
    BPWallOrPopup('scav', 1, "land"),           -- random wall/popup
    UDN.armrl_scav.id,
    UDN.armnanotc_scav.id,
}
-- Each defence slot picks randomly from this weighted pool
{ unitDefID = randomturrets[math.random(1,#randomturrets)], xOffset = ... }
```

**3. Random factory selection:**
```lua
local r = math.random(0,1)
if r == 0 then
    factoryID = UDN.corlab_scav.id   -- Bot Lab
else
    factoryID = UDN.corvp_scav.id    -- Vehicle Plant
end
```

**4. Random position (minefields):**
```lua
{ unitDefID = UDN.armmine1_scav.id,
  xOffset = math.random(-192,192),
  zOffset = math.random(-192,192),
  direction = 0 }
```

### The `BPWallOrPopup` Helper

Defined in `blueprint_tiers.lua`, this is a shared randomization function for wall/defence pieces:

```lua
function BPWallOrPopup(faction, tier, surface)
    local wallRandom = math.random()
    if wallRandom <= 0.1 then  -- 10% chance of armed wall
        return UDN[wallUnitDefs[faction][tier][surface].armed[
            math.random(1, #wallUnitDefs[faction][tier][surface].armed)
        ]].id
    else  -- 90% chance of unarmed wall
        return UDN[wallUnitDefs[faction][tier][surface].unarmed[
            math.random(1, #wallUnitDefs[faction][tier][surface].unarmed)
        ]].id
    end
end
```

It supports:
- **4 factions**: arm, cor, leg, scav
- **2 tiers**: Tier 1 (dragon's teeth, popup turrets) and Tier 2 (fortification walls)
- **2 surfaces**: land and sea
- **Armed vs unarmed**: 10% chance of getting an armed wall piece

---

## 4. Example Blueprint Analysis

### Example 1: T2Eco4 -- Minimal Walled Fusion

From `damgam_T2_Eco.lua`, the simplest T2 economy blueprint:

```lua
local function T2Eco4()
    return {
        type = types.Land,
        tiers = {tiers.T2, tiers.T3, tiers.T4 },
        radius = 96,
        buildings = {
            -- Ring of 12 walls surrounding a single fusion reactor
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 72, zOffset = -32, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -72, zOffset = 32, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -40, zOffset = 80, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 24, zOffset = 80, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -8, zOffset = 96, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 72, zOffset = 32, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 88, zOffset = 0, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -88, zOffset = 0, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 40, zOffset = -80, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -24, zOffset = -80, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 8, zOffset = -96, direction = 1},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -72, zOffset = -32, direction = 1},
            -- Central fusion reactor
            { unitDefID = UnitDefNames.armfus_scav.id, xOffset = 0, zOffset = 0, direction = 1},
        },
    }
end
```

**Spatial Analysis:**
- Radius: 96 elmos (compact)
- 1 fusion reactor at center (0,0)
- 12 wall segments forming a hexagonal ring at ~72-96 elmo distance
- All walls face east (direction = 1)
- Total footprint roughly 192x192 elmos (12x12 heightmap cells)

This is essentially a "protected fusion" template -- exactly the kind of building block an AI might use.

### Example 2: redBase1 -- Full T1 Base with Factory

From `damgam_bases.lua`:

```lua
local function redBase1()
    local randomturrets = {
        UDN.corllt_scav.id, UDN.corllt_scav.id,    -- 2/7 chance LLT
        UDN.corhllt_scav.id,                          -- 1/7 chance HLLT
        UDN.corhlt_scav.id,                            -- 1/7 chance HLT
        BPWallOrPopup('scav', 1, "land"),              -- 1/7 chance wall/popup
        UDN.corrl_scav.id,                             -- 1/7 chance rocket launcher
        UDN.cornanotc_scav.id,                         -- 1/7 chance nano tower
    }
    local factoryID  -- randomly picked: Bot Lab or Vehicle Plant

    return {
        type = types.Land,
        tiers = { tiers.T2, tiers.T3 },
        radius = 196,
        buildings = {
            -- 16 random turrets/nanos along two flanks
            { unitDefID = randomturrets[math.random(1,#randomturrets)],
              xOffset = -196, zOffset = -64, direction = 0 },
            -- ... 15 more random defence placements ...

            -- Central factory
            { unitDefID = factoryID, xOffset = 0, zOffset = 0, direction = 0 },

            -- 10 wall segments forming inner perimeter
            { unitDefID = BPWallOrPopup('scav', 1, "land"),
              xOffset = -136, zOffset = -32, direction = 0 },
            -- ... 9 more wall placements ...
        }
    }
end
```

**Spatial Analysis:**
- Radius: 196 elmos (medium-large)
- Layout follows a clear **layered defense** pattern:
  - Center (0,0): Factory
  - Inner ring (~136 elmos): Wall segments
  - Outer ring (~196 elmos): Turrets and nanos
- Turret positions are fixed, but turret TYPES are randomized from a weighted pool
- The factory itself is randomly chosen between bot lab and vehicle plant
- Total of ~27 buildings per instance

### Example 3: lltCornerArm1 -- Minimal T0 Defence Post

From `damgam_LLT_defences.lua`:

```lua
local function lltCornerArm1()
    return {
        type = types.Land,
        tiers = { tiers.T0, tiers.T1},
        radius = 59,
        buildings = {
            -- 7 wall segments forming an L-shape
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 6, zOffset = -37, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 38, zOffset = 59, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 38, zOffset = 27, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -58, zOffset = -37, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = -26, zOffset = -37, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 38, zOffset = -5, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 1, "land"), xOffset = 38, zOffset = -37, direction = 2},
            -- 2 fortification walls at corner
            { unitDefID = BPWallOrPopup('scav', 2), xOffset = -26, zOffset = -5, direction = 2},
            { unitDefID = BPWallOrPopup('scav', 2), xOffset = 6, zOffset = 27, direction = 2},
            -- 3 LLTs covering the corner
            { unitDefID = UnitDefNames.armllt_scav.id, xOffset = -58, zOffset = -5, direction = 2},
            { unitDefID = UnitDefNames.armllt_scav.id, xOffset = 6, zOffset = 59, direction = 2},
            { unitDefID = UnitDefNames.armllt_scav.id, xOffset = 6, zOffset = -5, direction = 2},
        },
    }
end
```

**Spatial Analysis:**
- Radius: 59 elmos (very compact, roughly 7x7 heightmap cells)
- 3 Light Laser Turrets in an L-shape providing overlapping fields of fire
- 7 regular walls + 2 tier-2 fortification walls forming a corner structure
- All buildings face north (direction = 2)
- This is the smallest meaningful "building block" in the blueprint library

---

## 5. Blueprint Tiers

The tier system is defined in `blueprint_tiers.lua`:

```lua
local tiers = {
    T0 = 0,
    T1 = 1,
    T2 = 2,
    T3 = 3,
    T4 = 4,
}
```

### Tier Definitions and Progression Mapping

| Tier | Label | Game Phase | Typical Buildings | Blueprint Types |
|------|-------|------------|-------------------|-----------------|
| T0 | Early Start | First 3 min | Wind farms, minefields, single turrets | Tiny outposts, wind farms |
| T1 | Early Game | 3-10 min | LLTs, bot labs, solar, metal extractors | Defence corners/crosses, basic bases |
| T2 | Mid Game | 10-20 min | Fusion reactors, T2 factories, HLTs | Economy clusters, full bases, firebases |
| T3 | Late Game | 20-35 min | Advanced fusions, T3 gantries, long-range guns | Epic defences, gantries, heavy firebases |
| T4 | Endgame | 35+ min | Superweapons, experimental factories | Largest/most fortified layouts |

### Multi-Tier Assignments

Blueprints commonly span multiple tiers. From the analyzed files:

- `windFarm1`: T0, T1 (available from early game)
- `minefield1`: T0, T1, T2, T3 (relevant throughout the game)
- `redBase1`: T2, T3 (mid-to-late game)
- `T2Eco0` through `T2Eco7`: T2, T3, T4 (mid-game onwards)
- `T2Eco8` through `T2Eco11`: T3, T4 only (late game -- these contain advanced fusions/T3 units)
- `t3Gantry1/2`: T3, T4 (late game experimental factories)

### Tier Selection in the Ruins Spawner

The `ai_ruins.lua` gadget selects tiers based on map-relative density. The ruins spawner picks a random tier based on the desired "power level" for each spawn location, then calls `blueprintController.GetRandomLandBlueprint(tier)` to get a matching layout.

### Mapping to AI Build Phases

If we were to map these tiers to AI progression phases:

| AI Phase | Blueprint Tier | What AI Would Build |
|----------|---------------|-------------------|
| Opening (Commander build) | T0 | Wind farms, 1-2 turrets, walls |
| Early Expansion | T1 | Defence clusters at expansion mexes |
| Factory Complex | T1-T2 | Factory + nanos + walls around factory |
| Mid-Game Economy | T2 | Fusion clusters with metal makers |
| Fortification | T2-T3 | Heavy defence positions, firebase templates |
| Late Game | T3-T4 | Superweapon emplacements, T3 factory complexes |

---

## 6. Relevance to Block-Based Building

This is the central question: **can the blueprint system be leveraged for AI building placement?**

### Direct Invocation: No

The blueprint system cannot be directly called by BARb or any AI:

1. **Language barrier**: Blueprints live in Lua gadget space. BARb AI runs in AngelScript.
2. **No cross-runtime API**: There is no mechanism for AngelScript to call Lua functions.
3. **Ruins-specific**: The blueprint controller's only consumers are `ai_ruins.lua` (the ruins spawner) and `ai_ruin_blueprint_tester.lua` (a dev tool).
4. **Scav units**: All blueprints reference `_scav` unit variants, not the standard faction units an AI would build.

### Data Format: Exactly What We Need

Despite the invocation barrier, the **data format** is a near-perfect match for what a block-based building AI would require:

```
Blueprint Entry = { unitDefID, xOffset, zOffset, direction }
```

This is functionally equivalent to saying: "from this anchor point, place building X at offset (dx, dz) facing direction D." That is precisely the instruction an AI builder needs.

### How the Ruins Spawner Actually Places Buildings

The `ai_ruin_blueprint_tester.lua` gadget reveals the actual placement call:

```lua
Spring.CreateUnit(
    nonscavDefID,
    basePosX + xOffset,
    Spring.GetGroundHeight(basePosX + xOffset, basePosZ + zOffset),
    basePosZ + zOffset,
    direction,
    0  -- teamID (Gaia)
)
```

This is the exact same `Spring.CreateUnit` call that any unit placement system uses. The blueprint system proves that **BAR's engine natively supports precise offset-based multi-building placement**.

### Rotation and Mirroring

The `ai_ruins.lua` gadget implements full rotation and mirroring of blueprints:

```lua
local function randomlyRotateBlueprint()
    local randomRotation = math.random(0,3)
    if randomRotation == 0 then  -- normal
        return false, 1, 1, 0       -- swapXZ, flipX, flipZ, rotation
    elseif randomRotation == 1 then  -- 90 degrees anti-clockwise
        return true, 1, -1, 1
    elseif randomRotation == 2 then  -- 180 degrees
        return false, -1, -1, 2
    elseif randomRotation == 3 then  -- 270 degrees
        return true, -1, 1, 3
    end
end
```

This rotation logic is critical: it means a single blueprint definition can be placed in any of 4 orientations (and optionally mirrored), giving 8 total placement variations from one template. Any AI block system would need equivalent rotation logic.

### Collision/Position Validation

The ruins spawner uses a separate library (`damgam_lib/position_checks.lua`) to validate placements -- checking distance from metal spots, geo vents, map edges, water, and other ruins. An AI block system would need similar terrain validation.

---

## 7. Adaptation Strategy for BARB Quest

### Core Concept: Blueprint-Inspired Block Templates

We can create an AI building system that borrows the blueprint data format but implements placement in AngelScript. Here is the strategy:

### Step 1: Define Block Templates in JSON

Convert the Lua blueprint format to JSON (which AngelScript can parse via BARb's existing config system):

**Lua Blueprint (current):**
```lua
{ unitDefID = UDN.armfus_scav.id, xOffset = 0, zOffset = 0, direction = 1 }
```

**JSON Block Template (proposed):**
```json
{
    "name": "protected_fusion",
    "tier": 2,
    "surface": "land",
    "radius": 96,
    "anchor": "armfus",
    "buildings": [
        { "unit": "armfus",    "x": 0,   "z": 0,   "facing": 1, "role": "core" },
        { "unit": "armnanotc", "x": 80,  "z": 0,   "facing": 1, "role": "support" },
        { "unit": "armnanotc", "x": -80, "z": 0,   "facing": 3, "role": "support" },
        { "unit": "armdrag",   "x": 72,  "z": -32, "facing": 1, "role": "wall" },
        { "unit": "armdrag",   "x": -72, "z": 32,  "facing": 1, "role": "wall" }
    ]
}
```

Key differences from Lua blueprints:
- **Unit names** instead of unitDefIDs (resolved at runtime, faction-agnostic)
- **Anchor field** identifies the "trigger" building (matches build_chain.json's event model)
- **Role field** allows the AI to skip optional parts (e.g., skip walls if tight on resources)
- **Faction-agnostic**: use a mapping table to translate armada->cortex->legion equivalents

### Step 2: Integrate with build_chain.json

The existing `build_chain.json` already has a "hub" system for placing buildings relative to a trigger building:

```json
"armfus": {
    "hub": [
        [
            {"unit": "armferret", "category": "defence", "offset": [-80, 80],
             "condition": {"air": true}},
            {"unit": "armnanotc", "category": "defence", "offset": {"front": 100}}
        ]
    ]
}
```

Block templates could be an **extension** of the hub system -- a "hub" that places a whole cluster instead of individual buildings. The existing offset and condition system would define WHERE the block goes; the block template defines WHAT goes in it.

### Step 3: Implement in AngelScript

The placement logic in AngelScript would:

1. Parse JSON block templates at init
2. When a trigger event fires (e.g., "fusion completed"), look up applicable block templates
3. Evaluate conditions (income threshold, threat level, available space)
4. Pick a template and resolve the anchor position
5. For each building in the template:
   - Apply rotation (based on factory facing or map position)
   - Validate terrain (buildable, not underwater, not on mex/geo)
   - Queue the build order with the nearest constructor

### Step 4: Extract Patterns from Existing Blueprints

The 48+ existing blueprint functions contain **expert-level base layout knowledge**. We should mine them for patterns:

| Pattern | Source Blueprints | AI Application |
|---------|------------------|----------------|
| Walled Fusion | T2Eco4, T2Eco5 | Protect eco buildings |
| Factory + Nano Ring | Damgam_factory_centers | Optimal factory setup |
| LLT Corner | lltCornerArm1/Cor1 | Defensive expansion |
| LLT Cross | lltCrossArm1/Cor1 | Chokepoint defence |
| Wind Farm Grid | windFarm1 | T1 energy |
| Fusion + Metal Maker Cluster | T2Eco6, T2Eco7 | T2 economy block |

---

## 8. Comparison: Blueprints vs build_chain.json

Both systems define building groups with spatial relationships. Here is a detailed comparison:

| Aspect | Blueprints (Lua) | build_chain.json |
|--------|-----------------|------------------|
| **Language** | Lua functions | JSON |
| **Runtime** | Gadget space (server-side) | AngelScript (AI-side) |
| **Purpose** | Ruins spawning | AI build decisions |
| **Positioning** | Absolute offsets from center `(xOffset, zOffset)` | Relative offsets from trigger building `[x, z]` or directional `{"front": 80}` |
| **Facing** | Explicit per-building `direction: 0-3` | Implicit (inherited from parent or factory) |
| **Scale** | Full base layouts (10-60 buildings) | Small chains (1-5 buildings per hub) |
| **Randomization** | Internal to function (variant selection, random pools) | None (deterministic per config) |
| **Conditions** | None (always spawn) | Rich conditions: `air`, `energy`, `wind`, `sensor`, `chance` |
| **Tier System** | T0-T4 with multi-tier assignment | Implicit via income thresholds |
| **Faction** | Scav only (hardcoded unit names) | Faction-aware (armada/cortex columns) |
| **Terrain Validation** | Separate position_checks library | Built into AngelScript placement |
| **Rotation** | Applied externally by ruins spawner | Direction-aware offsets (`front/back/left/right`) |

### The Best of Both Worlds

A combined approach would use:

**From Blueprints:**
- Pre-defined spatial arrangements (the "art" of base layout)
- Multi-building clusters as atomic units
- Tier-based progression
- Rotation/mirroring support
- Radius-based collision avoidance

**From build_chain.json:**
- Event-driven triggers (building completion events)
- Conditional placement (income, threat, chance)
- Faction-agnostic unit specification
- Category-based reasoning (energy, defence, factory, etc.)
- Integration with the existing AI decision loop

### Proposed Hybrid Format

```json
"block_templates": {
    "protected_fusion_arm": {
        "trigger": "armfus",
        "tier": [2, 3],
        "radius": 96,
        "condition": {"energy": true, "chance": 0.7},
        "buildings": [
            {"unit": "armnanotc", "offset": [80, 0], "category": "nano"},
            {"unit": "armnanotc", "offset": [-80, 0], "category": "nano"},
            {"unit": "armdrag", "offset": [72, -32], "category": "wall"},
            {"unit": "armdrag", "offset": [-72, 32], "category": "wall"},
            {"unit": "armdrag", "offset": [88, 0], "category": "wall"},
            {"unit": "armdrag", "offset": [-88, 0], "category": "wall"}
        ]
    },
    "factory_cluster_arm": {
        "trigger": "armlab",
        "tier": [1, 2],
        "radius": 128,
        "condition": {"chance": 1.0},
        "buildings": [
            {"unit": "armnanotc", "offset": [72, -72], "category": "nano"},
            {"unit": "armnanotc", "offset": [72, 72], "category": "nano"},
            {"unit": "armnanotc", "offset": [-72, -72], "category": "nano"},
            {"unit": "armnanotc", "offset": [-72, 72], "category": "nano"},
            {"unit": "armllt", "offset": [128, 0], "category": "defence"},
            {"unit": "armllt", "offset": [-128, 0], "category": "defence"}
        ]
    }
}
```

This keeps the build_chain.json's event model and condition system while adding the blueprint's cluster-of-buildings concept.

---

## Key Takeaways

1. **The blueprint system proves the concept.** BAR already has production code for defining and placing groups of buildings from offset-based templates. The spatial data format works.

2. **We cannot reuse the code directly.** The Lua/AngelScript boundary and the scav-unit specificity make direct invocation impossible. We must reimplement in AngelScript.

3. **We CAN reuse the design knowledge.** The 48+ blueprint layouts encode expert-level understanding of BAR base design. These should be studied and translated into AI-appropriate templates.

4. **The build_chain.json system is the right integration point.** Rather than building a parallel system, block templates should extend the existing hub mechanism in build_chain.json.

5. **Rotation logic is non-trivial but solved.** The `randomlyRotateBlueprint` function in ai_ruins.lua provides the exact math needed for 4-way rotation of offset-based layouts.

6. **Start small.** The smallest useful blueprints (lltCornerArm1 at 12 buildings, T2Eco4 at 13 buildings) show that even 10-15 building templates create meaningful tactical structures. We do not need 60-building mega-bases to start.

7. **The radius field is critical.** Every blueprint specifies its bounding radius. This is essential for collision avoidance between templates and for terrain validation. Our block templates must include this.

---

## Sources

- [Blueprint Editor Feature Request -- GitHub Issue #4016](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/4016)
- [Blueprints config corruption -- GitHub Issue #4792](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/4792)
- [Auto faction substitution -- GitHub Issue #4816](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/4816)
- [Beyond All Reason Official Site](https://www.beyondallreason.info)
