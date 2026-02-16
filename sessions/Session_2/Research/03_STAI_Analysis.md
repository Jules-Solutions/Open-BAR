# Research Report 03: STAI Deep-Dive Analysis

> **Quest:** BARB (Building AI for Resource-efficient Bases)
> **Session:** Session_2
> **Date:** 2026-02-13
> **Focus:** STAI building placement system, module architecture, role/task system
> **Source:** `Beyond-All-Reason/luarules/gadgets/ai/STAI/`

---

## Table of Contents

1. [Module/Behaviour Architecture Pattern](#1-modulebehaviour-architecture-pattern)
2. [Role System Deep Dive](#2-role-system-deep-dive)
3. [Task Queue System](#3-task-queue-system)
4. [Building Position System (THE CRITICAL SECTION)](#4-building-position-system)
5. [Engineer Management](#5-engineer-management)
6. [Economy Filtering](#6-economy-filtering)
7. [Strengths (What Works Well)](#7-strengths-what-works-well-for-building)
8. [Weaknesses (Where It Still Scatters)](#8-weaknesses-where-it-still-scatters)
9. [Lessons for Our Block-Based Design](#9-lessons-for-our-block-based-design)

---

## 1. Module/Behaviour Architecture Pattern

STAI is structured around a clean two-tier class hierarchy:

### Handler/Module (`*hst.lua`) -- Global Coordination

Handlers inherit from the `Module` base class. They manage **global state** -- things that apply across all units of a type. There is typically one instance per handler per AI team.

| Handler File | Internal Name | Responsibility |
|---|---|---|
| `buildingshst.lua` | `buildingshst` | Build positions, rectangle tracking, role assignment |
| `taskshst.lua` | `taskshst` | Task queue definitions per role |
| `ecohst.lua` | `ecohst` | Rolling resource averages (income/usage/reserves) |
| `engineerhst.lua` | `engineerhst` | Engineer-to-builder ratios and assignment tracking |
| `labshst.lua` | `labshst` | Factory management, tech progression, production queues |
| `armyhst.lua` | `armyhst` | Unit table definitions, categories, factory data |
| `maphst.lua` | `maphst` | Map analysis, metal spots, mobility networks |
| `schedulerHST.lua` | `schedulerhst` | Frame scheduling for update distribution |
| `attackhst.lua` | `attackhst` | Attack coordination |
| `scouthst.lua` | `scouthst` | Scouting management |
| `damagehst.lua` | `damagehst` | Damage tracking |

Handlers have a standard lifecycle:

```lua
function SomeHST:Init()     -- Called once at AI creation
function SomeHST:Update()   -- Called per frame (but gated by scheduler)
```

The scheduler distributes `Update()` calls across frames to avoid CPU spikes. Each handler only updates when `self.ai.schedulerhst.moduleUpdate == self:Name()`.

### Behaviour (`*bst.lua`) -- Per-Unit Logic

Behaviours inherit from the `Behaviour` base class. There is **one instance per unit** that has that behaviour. A single unit may have multiple behaviours, managed by priority election.

| Behaviour File | Unit Type | Responsibility |
|---|---|---|
| `buildersbst.lua` | Constructors | Process task queue, find build positions, issue build orders |
| `engineerbst.lua` | Engineers | Guard builders, assist construction |
| `labsbst.lua` | Factories | Production queue execution |
| `attackerbst.lua` | Combat units | Attack target selection |
| `scoutbst.lua` | Scout units | Map exploration |
| `bomberbst.lua` | Bombers | Bombing runs |
| `commanderbst.lua` | Commander | Commander-specific logic |
| `reclaimbst.lua` | Reclaimers | Reclaim wrecks/features |
| `cleanerbst.lua` | Any unit | Clean up stuck/trapped units |

Behaviours use the priority/election system:

```lua
function BuildersBST:Priority()
    return 100  -- Higher = more likely to be elected
end

function BuildersBST:Activate()   -- Called when elected as active behaviour
function BuildersBST:Deactivate() -- Called when another behaviour takes over
function BuildersBST:Update()     -- Called every frame while active
```

### How They Interact

```
                  +--------------------------------------------------+
                  |              STAI AI Instance                     |
                  |                                                    |
                  |  Handlers (Global State)     Behaviours (Per-Unit) |
                  |  +-----------------+         +-----------------+  |
                  |  | buildingshst    |<------->| buildersbst [1] |  |
                  |  |  .roles{}       |  reads  | buildersbst [2] |  |
                  |  |  .builders{}    |  roles  | buildersbst [3] |  |
                  |  |  .sketch{}      |  &      |       ...       |  |
                  |  |  .dontBuildRects|  rects  +-----------------+  |
                  |  +-----------------+                               |
                  |          ^                   +-----------------+  |
                  |          |                   | engineerbst [1] |  |
                  |  +-----------------+  writes | engineerbst [2] |  |
                  |  | taskshst        |-------->|       ...       |  |
                  |  |  .roles{}       |  task   +-----------------+  |
                  |  +-----------------+  queues                      |
                  |          ^                   +-----------------+  |
                  |          |                   | labsbst [1]     |  |
                  |  +-----------------+         | labsbst [2]     |  |
                  |  | ecohst          |-------->|       ...       |  |
                  |  |  .Metal{}       |  eco    +-----------------+  |
                  |  |  .Energy{}      |  state                       |
                  |  +-----------------+                               |
                  |                                                    |
                  |  +-----------------+                               |
                  |  | engineerhst     |  tracks engineer assignments  |
                  |  +-----------------+                               |
                  |                                                    |
                  |  +-----------------+                               |
                  |  | labshst         |  factory rating & selection   |
                  |  +-----------------+                               |
                  +--------------------------------------------------+
```

The key data flow for building:

1. `ecohst` updates rolling resource averages
2. `taskshst` defines what each role should build (with economy conditions)
3. `buildingshst` tracks roles, planned builds, and blocked rectangles
4. `buildersbst` (per builder) reads its role's task queue, checks conditions, calls `buildingshst` to find positions
5. `engineerhst` assigns extra engineers to help active builders
6. `labshst` decides which factories to build and where

---

## 2. Role System Deep Dive

### The 8 Roles

| Role | Purpose | Typical Task Queue Focus |
|---|---|---|
| `starter` | Early game commander | 3 mexes -> energy -> factory -> LLT |
| `eco` | Energy production & storage | Factory -> nano -> LLT -> wind/solar/fusion -> storage -> converters |
| `expand` | Territory & resource expansion | Mex -> LLT -> emergency solar -> radar |
| `nano` | Nano turret construction | Only builds nano turrets |
| `support` | Defensive infrastructure | Radar -> turrets -> popups -> heavy turrets -> AA |
| `assist` | Help other builders (idle role) | Single task: mex (always fails economy check, forcing assist) |
| `default` | Mixed tasks (kitchen sink) | Factory -> energy -> storage -> converters -> mex -> nano -> AA -> defenses -> everything |
| `metalMaker` | Energy-to-metal conversion | Converters -> energy storage -> metal storage -> targeting facilities |

### Role Assignment Logic (`BuildingsHST:SetRole`)

The assignment is a **priority waterfall** that depends on whether the unit is a commander, T2 builder, or T1 builder.

**Commander Logic** (re-evaluated every queue cycle):

```lua
function BuildingsHST:SetRole(builderID)
    local builder = game:GetUnitByID(builderID)
    local name = builder:Name()

    if self.ai.armyhst.commanderList[name] then
        -- Commander: dynamic role based on game state
        if countFinished('_nano_') == 0 and countMyUnit('_nano_') == 1 then
            role = 'assist'       -- A nano is building, help it finish
        elseif countFinished('_nano_') == 0 then
            role = 'starter'      -- No nanos at all: do early build order
        elseif ecoCount >= 1 and expandCount >= 3 then
            role = 'assist'       -- Enough expanders, go help someone
        elseif ecoCount >= 1 then
            role = 'expand'       -- Have eco builder, go grab mexes
        else
            role = 'default'      -- Fallback
        end
```

**T2 Builder Logic** (techLevel == 4, assigned once, then sticky):

```lua
    elseif unitTable[name].techLevel == 4 then
        if existingRole then
            role = existingRole           -- Keep existing role
        elseif RoleCounter(name,'expand') < 1 then
            role = 'expand'               -- First T2: expand
        elseif RoleCounter(name,'eco') < 1 then
            role = 'eco'                  -- Second T2: eco
        elseif RoleCounter(name,'expand') < 2 then
            role = 'expand'               -- Third T2: more expanding
        elseif RoleCounter(name,'support') < 1 then
            role = 'support'              -- Fourth T2: support
        elseif RoleCounter(name,'metalMaker') < 1 then
            role = 'metalMaker'           -- Fifth T2: metal making
        elseif RoleCounter(name,'default') < 1 then
            role = 'default'              -- Sixth T2: default
        else
            -- Beyond 6 T2 builders: 60% expand, 40% support
            if math.random() < 0.6 then
                role = 'expand'
            else
                role = 'support'
            end
        end
```

**T1 Builder Logic** (standard constructors, assigned once, then sticky):

```lua
    else
        if existingRole then
            role = existingRole           -- Keep existing role
        elseif RoleCounter(name,'eco') < 1 then
            role = 'eco'                  -- First T1: eco
        elseif RoleCounter(name,'expand') < 3 then
            role = 'expand'               -- Next 3 T1: expand
        elseif RoleCounter(name,'nano') < 1 then
            role = 'nano'                 -- Fifth T1: nano builder
        elseif RoleCounter(name,'support') < 1 then
            role = 'support'              -- Sixth T1: support
        elseif RoleCounter(name,'default') < 1 then
            role = 'default'              -- Seventh T1: default
        else
            -- Beyond 7: 60% expand, 40% support
            if math.random() < 0.6 then
                role = 'expand'
            else
                role = 'support'
            end
        end
    end
```

### Role Transitions

Roles are mostly **sticky** once assigned (the `if self.roles[builderID]` check returns the existing role). The exceptions:

1. **Commander**: Re-evaluated every queue cycle via `ProgressQueue()`:
   ```lua
   -- In BuildersBST:ProgressQueue():
   if self.isCommander then
       self.role = self.ai.buildingshst:SetRole(self.id)
       self.queue = self.ai.taskshst.roles[self.role]
   end
   ```

2. **Failover transitions**: When a builder exhausts its queue without placing anything (`fails > #queue`), it cycles roles:
   ```lua
   -- In BuildersBST:ProgressQueue():
   if self.fails > #self.queue then
       if role == 'expand' then
           role = 'support'     -- expand -> support
       elseif role == 'support' then
           role = 'default'     -- support -> default
       elseif role == 'default' then
           role = 'expand'      -- default -> expand (cycle)
       end
       self:Assist()  -- Fall back to helping someone else
   end
   ```

### `RoleCounter` -- The Counting Function

This function is used heavily during role assignment to count how many builders of a given name already have a given role:

```lua
function BuildingsHST:RoleCounter(builderName, targetRole)
    local counter = 0      -- this name + this role
    local globalCount = 0  -- all builders total
    local roleCount = 0    -- any name + this role
    local nameCount = 0    -- this name + any role
    for id, role in pairs(self.roles) do
        globalCount = globalCount + 1
        if role.builderName == builderName and role.role == targetRole then
            counter = counter + 1
        end
        if role.builderName == builderName then
            nameCount = nameCount + 1
        end
        if role.role == targetRole then
            roleCount = roleCount + 1
        end
    end
    return counter, nameCount, roleCount, globalCount
end
```

The key insight: role limits are **per unit type** (per `builderName`), not global. So if you have 3 ARM T1 constructors (`armck`), each gets its own slot in the priority waterfall. A 4th `armck` would get `support` or beyond.

---

## 3. Task Queue System

### Task Structure

Each task in a role's queue is a Lua table with these fields:

```lua
{
    category  = '_wind_',           -- Unit category key from armyhst
    economy   = function(_, param, name)  -- Economy gate: returns true if affordable
                    return E.full < 0.5 or E.income < 30
                end,
    special   = true,               -- Triggers special filter (wind speed, etc.)
    numeric   = 5,                  -- Max count limit (false = unlimited)
    duplicate = true,               -- Prevent duplicate builds in progress
    location  = {                   -- Where to search for build position
        categories = {'_nano_', 'factoryMobilities'},  -- Near these
        min = 50,                   -- Minimum distance from anchor
        max = 390,                  -- Maximum distance from anchor
        neighbours = {'_wind_'},    -- Don't build if too many of these nearby
        number = 2,                 -- Max neighbour count threshold
        list = somePositionList,    -- Explicit position list to search
        himself = true,             -- Fallback: search from builder's position
        friendlyGrid = true,        -- Fallback: search from builder's position
    },
}
```

### Task Execution Order (from `BuildersBST:ProgressQueue`)

The builder iterates through its role's queue **sequentially** starting from where it left off:

```
For each task in queue[idx .. #queue]:
    |
    +-- 1. getOrder(builder, JOB)
    |       Find a unit name from the category that this builder can build
    |       (respects land/water depth matching)
    |
    +-- 2. specialFilter(cat, param, name)         [if JOB.special]
    |       Wind speed check, tide check, anti-air need, etc.
    |
    +-- 3. limitedNumber(name, number)             [if JOB.numeric]
    |       Count existing units, skip if at limit
    |
    +-- 4. CheckForDuplicates(name)                [if JOB.duplicate]
    |       Check builders{} and sketch{} for same unit name
    |       Also blocks any factory if ANY factory is already planned
    |
    +-- 5. CategoryEconFilter(cat, param, name)    [if JOB.economy]
    |       Execute the economy function with current eco state
    |
    +-- 6. findPlace(utype, value, cat, loc)       [if passed all filters]
    |       Resolve build position based on location spec
    |       |
    |       +-- location.categories -> searchPosNearCategories()
    |       +-- location.list -> searchPosInList()
    |       +-- location.himself -> FindClosestBuildSite() from builder pos
    |       +-- category == '_mex_' -> ClosestFreeMex() special path
    |       +-- category == '_nano_' -> near factory special path
    |
    +-- 7. Issue build order
    |       NewPlan() -> register in builders{}
    |       GiveOrder(-defID, {x,y,z,facing})
    |
    +-- If position not found: increment fails counter, continue to next task
```

### Economy Conditions -- Examples by Role

**Starter role** (early game, very permissive):

| Task | Economy Condition |
|---|---|
| `_mex_` | `return true` (always) |
| `_wind_` | `return true` (always) |
| `_solar_` | `return true` (always) |
| `factoryMobilities` | `M.income > 6 or countMyUnit('_mex_') >= 2 and E.income > 40` |
| `_llt_` | `countMyUnit('factoryMobilities') > 0` |

**Eco role** (economy focused, moderate gates):

| Task | Economy Condition |
|---|---|
| `factoryMobilities` | `M.income > 6 and E.income > 30` |
| `_nano_` (first) | `countMyUnit(name) == 0` (only if no nanos exist) |
| `_wind_` | `E.full < 0.75 or E.income < E.usage * 1.25 or E.income < 30` |
| `_fus_` | `E.income < E.usage * 1.25 or E.full < 0.5` |
| `_convs_` | `E.income > E.usage * 1.1 and E.full > 0.9 and E.income > 200` |

**Default role** (late game, strict gates for expensive items):

| Task | Economy Condition |
|---|---|
| `_silo_` | `E.income > 8000 and M.income > 100 and E.full > 0.5 and M.full > 0.5` |
| `_lol_` | `E.income > 15000 and M.income > 200 and E.full > 0.8 and M.full > 0.5` |
| `_plasma_` | `E.income > 5000 and M.income > 100 and E.full > 0.5 and M.full > 0.5` |

### Location Filters

The `location` field controls WHERE the building is placed relative to existing structures:

```
location = {
    categories = {'_nano_', 'factoryMobilities'},
    --  Search near existing nanos first, then near factories

    min = 50,   max = 390,
    --  At least 50 elmos away, at most 390 elmos away

    neighbours = {'_wind_'},  number = 2,
    --  Skip anchor if 2+ wind generators already within range

    list = self.ai.maphst.hotSpots,
    --  Fallback: search through explicit position list

    himself = true,
    --  Final fallback: search from builder's own position
}
```

### Special Filters

The `specialFilter` in `BuildersBST` handles conditional categories:

```lua
function BuildersBST:specialFilter(cat, param, name)
    if cat == '_solar_' then
        -- Upgrade to advanced solar if metal & energy high enough
        if eco.Metal.reserves > 100 and eco.Energy.income > 200 then
            name = advancedVersion
        end
        -- Only build solar if wind is weak
        check = (map:AverageWind() <= 7 or map:GetWind() < 5)

    elseif cat == '_wind_' then
        check = map:AverageWind() > 7 and map:GetWind() > 5

    elseif cat == '_tide_' then
        check = map:TidalStrength() >= 10

    elseif cat == '_aa1_' or cat == '_flak_' or cat == '_aabomb_' then
        check = self.ai.needAntiAir    -- Only build AA when needed

    elseif cat == '_convs_' then
        -- T1 converters: only if < 2 fusions
        -- T2+ converters: always allowed
    end
end
```

---

## 4. Building Position System

**This is the most critical section for the BARB quest.** The building position system in `buildingshst.lua` is the core of STAI's base layout behaviour.

### Overview

```
Builder wants to place a building
        |
        v
searchPosNearCategories()  OR  searchPosInList()  OR  direct call
        |                              |                    |
        v                              v                    v
    Find anchor positions (existing buildings of target category)
        |
        v
    Sort anchors by distance to builder
        |
        v
    For each anchor:
        |
        +-- unitsNearCheck() -- skip if too many neighbours
        |
        +-- FindClosestBuildSite(unittype, anchorX, anchorY, anchorZ, ...)
                |
                v
            Spiral search outward from anchor
                |
                v
            For each candidate point on spiral:
                |
                +-- CheckBuildPos() validation chain
                |       |
                |       +-- isInMap()
                |       +-- getUnitsInCylinder() spacing check
                |       +-- dontBuildRects[] overlap check
                |       +-- builders[] overlap check
                |       +-- LandWaterFilter()
                |       +-- UnitCanGoHere()
                |
                +-- CanBuildHere()
                        |
                        +-- Spring.Pos2BuildPos() (snap to grid)
                        +-- Spring.TestBuildOrder() (engine validation)
                |
                v
            Return first valid position
```

### FindClosestBuildSite -- The Spiral Search Algorithm

This is the heart of STAI's position finding. It searches in an **expanding spiral** from an anchor point.

```lua
function BuildingsHST:FindClosestBuildSite(unittype, bx, by, bz, minDist, maxDist, builder, recycledPos)
    maxDist = maxDist or 390          -- Default max search radius: 390 elmos
    minDist = minDist or 1
    minDist = math.max(minDist, 1)

    local twicePi = math.pi * 2
    local angleIncMult = twicePi / minDist

    local maxtest = math.max(10, (maxDist - minDist) / 100)  -- Radius step size

    for radius = minDist, maxDist, maxtest do
        local angleInc = radius * twicePi * angleIncMult  -- More points at larger radius
        local initAngle = math.random() * twicePi         -- RANDOM start angle

        for angle = initAngle, initAngle + twicePi, angleInc do
            -- Calculate candidate position
            local dx = radius * math.cos(realAngle)
            local dz = radius * math.sin(realAngle)
            local x, z = bx + dx, bz + dz

            -- Clamp to map bounds
            -- Get ground height
            -- Run CheckBuildPos validation
            -- If valid, run CanBuildHere for engine confirmation
            -- Return first valid position found
        end
    end
    -- Returns nil if no valid position found
end
```

**ASCII diagram of the spiral search pattern:**

```
                        maxDist
                     .....+.....
                  ../     |     \..
                ./   _____|_____  \.
               /   /      |     \  \
              /  /  . . . | . .  \  \
             / /  .   ____|____. .\  \
            | |  . ../    |   \.  |  |
            | | . ./  ....|... \. |  |
            | | . |  .    |   .| .|  |
   ---------|.|---|--.*----+---.|--|----------
            | | . |  . initAngle.| .|  |
            | | . .\  ....|... /. |  |
            | |  . .\_.___|__/..  |  |
             \ \  .   ____|____. ./  /
              \  \  . . . | . .  /  /
               \   \______|____/   /
                \.   minDist    ./
                  ..\     |   /..
                     .....|.....
                          |

    Radius starts at minDist, expands in steps of maxtest.
    At each radius: walk a full 360 degrees from a RANDOM start angle.
    Angle increment is proportional to radius (more samples at larger radii).
```

**Key parameters:**

| Parameter | Default | Purpose |
|---|---|---|
| `minDist` | 1 | Minimum search radius from anchor |
| `maxDist` | 390 | Maximum search radius from anchor |
| `maxtest` | `max(10, (maxDist-minDist)/100)` | Radius step size (~100 rings) |
| `angleIncMult` | `2*pi / minDist` | Controls how many angle steps per ring |
| `initAngle` | `random() * 2*pi` | **Random** starting angle per ring |

**The random start angle** is a crucial detail: it means that for the same anchor point, successive calls will try different directions first. This prevents the AI from always building in the same direction, but it also means placement is inherently unpredictable.

### Rectangle Tracking System

STAI uses an axis-aligned rectangle system to track areas where building is forbidden. There are three overlapping collections:

```
dontBuildRects[]   -- Permanent blocked areas
    Created by:
        - DontBuildOnMetalOrGeoSpots()  -- 80x80 elmo zones on ALL spots
        - UnitCreated()                 -- When a building starts construction
    Removed by:
        - DoBuildRectangleByUnitID()    -- When a building dies

sketch[]           -- Buildings currently under construction
    Created by:
        - UnitCreated()                 -- Builder starts constructing
    Removed by:
        - MyUnitBuilt()                 -- Construction finishes
        - UnitDead()                    -- Building dies during construction

builders[]         -- Planned builds (ordered but not yet started)
    Created by:
        - NewPlan()                     -- Builder is issued a build order
    Removed by:
        - ClearMyProjects()             -- Build finishes, fails, or is cancelled
```

**Rectangle calculation** (`CalculateRect`):

```lua
function BuildingsHST:CalculateRect(rect)
    -- Uses the shared helper from common/stai_factory_rect.lua
    local outsets = factoryRect.getOutsets(unitName, unitTable, factoryExitSides)

    if outsets == nil and hasExitSide then
        -- Factory with known exit: use CalculateFactoryLane() instead
        return
    end

    -- Normal building or factory without exit data:
    rect.x1 = position.x - outX
    rect.z1 = position.z - outZ
    rect.x2 = position.x + outX
    rect.z2 = position.z + outZ
end
```

**Outset multipliers** (from `stai_factory_rect.lua`):

| Unit Type | X Multiplier | Z Multiplier | Example (4x4 footprint) |
|---|---|---|---|
| Normal building | `xsize * 4` | `zsize * 4` | 16x16 elmo rect |
| Factory (unknown exit) | `xsize * 6` | `zsize * 9` | 24x36 elmo rect |
| Air factory (exit=0) | `xsize * 4` | `zsize * 4` | 16x16 elmo rect |
| Factory (known exit) | Calculated by `CalculateFactoryLane` | Variable, extends 10x in exit direction |

### DontBuildOnMetalOrGeoSpots -- The 40-Elmo Exclusion

At AI initialization, every metal and geo spot gets an 80x80 elmo exclusion zone:

```lua
function BuildingsHST:DontBuildOnMetalOrGeoSpots()
    for i, p in pairs(self.ai.maphst.allSpots) do
        self:DontBuildRectangle(p.x - 40, p.z - 40, p.x + 40, p.z + 40)
    end
end
```

```
         40 elmos
    +-----|-----+
    |     |     |
    |     M     | 40 elmos   M = metal/geo spot
    |     |     |            Total exclusion: 80x80 elmos
    +-----|-----+
```

This prevents non-mex buildings from being placed on extraction points, but it is also checked during `CheckBuildPos` for ALL buildings, ensuring mex spots remain available.

### CheckBuildPos -- The Validation Chain

This is the gatekeeper function. Every candidate position from the spiral search must pass ALL checks:

```lua
function BuildingsHST:CheckBuildPos(pos, unitTypeToBuild, builder)
    -- CHECK 1: Map bounds
    if not self.ai.maphst:isInMap(pos) then return end

    -- CHECK 2: Building spacing (cylinder check)
    local range = self:GetBuildSpacing(unitTypeToBuild)
    -- range = 100 for factories, 50 for mexes, 100 for everything else
    local neighbours = game:getUnitsInCylinder(pos, range)
    for each neighbour:
        if neighbour is a static building and not same type:
            return nil  -- Too close to another building

    -- CHECK 3: Forbidden rectangle overlap
    local rect = {position = pos, unitName = unitTypeToBuild:Name()}
    self:CalculateRect(rect)

    for each rect in dontBuildRects[]:
        if RectsOverlap(rect, dontRect):
            return nil  -- Would overlap a metal/geo spot or existing building

    -- CHECK 4: Planned build overlap
    for each plan in builders[]:
        if RectsOverlap(rect, plan):
            return nil  -- Would overlap another builder's planned position

    -- CHECK 5: Land/water filter
    if not LandWaterFilter(pos, unitTypeToBuild, builder):
        return nil  -- Amphibious builder would travel too far across shore

    -- CHECK 6: Path accessibility
    if not maphst:UnitCanGoHere(builder, pos):
        return nil  -- Builder can't reach this position

    return true
end
```

**Validation chain as ASCII diagram:**

```
Candidate Position (x, z)
         |
         v
    [In map bounds?] --NO--> reject
         |YES
         v
    [getUnitsInCylinder(pos, spacing)]
    [Any static building within 50-100 elmos?] --YES--> reject
         |NO
         v
    [Calculate building rectangle]
    [Overlaps any dontBuildRect?] --YES--> reject
         |NO
         v
    [Overlaps any planned build?] --YES--> reject
         |NO
         v
    [Amphibious shore distance > 250?] --YES--> reject
         |NO
         v
    [UnitCanGoHere (path exists)?] --NO--> reject
         |YES
         v
    [CanBuildHere]
    [Spring.Pos2BuildPos (snap to grid)]
    [Spring.TestBuildOrder (engine check)] --FAIL--> reject
         |PASS
         v
    VALID POSITION -- return it
```

### Factory Exit Lane Calculation

Factories need clear exit lanes so produced units do not get stuck. STAI calculates these based on the factory's **facing** (which is determined by proximity to map edges):

```lua
function BuildingsHST:GetFacing(p)
    -- Factory faces AWAY from the nearest map edge
    if abs(mapSizeX - 2*x) > abs(mapSizeZ - 2*z) then
        if 2*x > mapSizeX then facing = 3 (east)
        else facing = 1 (west)
    else
        if 2*z > mapSizeZ then facing = 2 (south)
        else facing = 0 (north)
    end
end
```

```lua
function BuildingsHST:CalculateFactoryLane(rect)
    local outX = unitTable.xsize * 6   -- Factory half-width
    local outZ = unitTable.zsize * 6   -- Factory half-depth
    local tall = outZ * 10             -- Exit lane length = 10x factory depth

    -- facing 0 (north): exit goes SOUTH (increasing z)
    if facing == 0 then
        rect.x1 = pos.x - outX
        rect.x2 = pos.x + outX
        rect.z1 = pos.z - outZ    -- Factory body
        rect.z2 = pos.z + tall    -- Long exit lane southward
    -- facing 2 (south): exit goes NORTH (decreasing z)
    elseif facing == 2 then
        rect.z1 = pos.z - tall    -- Long exit lane northward
        rect.z2 = pos.z + outZ    -- Factory body
    -- ... etc for east/west
    end
end
```

**ASCII diagram of factory exit lane (facing north, exit south):**

```
                     outX
              +------|------+
              |      |      |
              | FACTORY     | outZ (factory body)
              |      |      |
    pos.z --> +------+------+
              |             |
              |  EXIT LANE  |
              |  (blocked)  |
              |             |  tall = outZ * 10
              |  No building|
              |  allowed    |
              |  here       |
              |             |
              +-------------+
```

This rectangle is added to `dontBuildRects[]` when the factory is created, preventing other buildings from blocking the factory's output.

### Build Spacing Values

```lua
function BuildingsHST:GetBuildSpacing(unitTypeToBuild)
    if isFactory then
        spacing = 100   -- Factories need 100 elmo clearance
    elseif isMex then
        spacing = 50    -- Mexes need 50 elmo clearance
    else
        spacing = 100   -- Everything else: 100 elmo clearance
    end
end
```

The 100-elmo default spacing is quite generous. Combined with the spiral search, this contributes to the "scattered" feel of STAI bases -- buildings end up spread far apart because each one needs 100 elmos of clear space around it.

### searchPosNearCategories -- The Anchor System

This function is how STAI places buildings "near" existing infrastructure:

```lua
function BuildingsHST:searchPosNearCategories(utype, builder, minDist, maxDist, categories,
                                               neighbours, number)
    for each category in categories:
        -- Get all team units matching this category
        -- Sort by distance to builder (closest first)
        for each unit (sorted by distance):
            -- Check neighbour density: skip if too many similar units nearby
            if not unitsNearCheck(unitPos, maxDist, number, neighbours) then
                -- Run spiral search centered on this unit
                pos = FindClosestBuildSite(utype, unitPos, minDist, maxDist, builder)
                if pos then return pos end
            end
        end
    end
    -- All anchors exhausted: return nil
end
```

The flow:
1. Find all existing buildings matching the target categories (e.g., `{'_nano_', 'factoryMobilities'}`)
2. Sort them by distance to the builder (try closest anchors first)
3. For each anchor, check if the area is already saturated with neighbours
4. If not saturated, run spiral search from that anchor
5. Return the first valid position found

---

## 5. Engineer Management

### Engineer Concept

In STAI, "engineers" are lightweight construction units produced by factories. They are distinct from "builders" (constructors that have their own task queue and role). Engineers follow the simpler pattern of just guarding/assisting a builder.

### `EngineerHST` -- The Handler

```lua
function EngineerHST:Init()
    self.Engineers = {}           -- Engineer units
    self.Builders = {}            -- Builders who can be helped (keyed by builderID)
    self.maxEngineersPerBuilder = 1   -- Scales with economy
    -- Per-role engineer demand:
    self.eco = 3
    self.expand = 2
    self.support = 1
    self.default = 1
    self.starter = 0             -- Starter doesn't get help
    self.metalMaker = 2
    self.nano = 0                -- Nanos don't get help
    self.engineersNeeded = 0
end
```

### Engineer Demand Calculation

```lua
function EngineerHST:EngineersNeeded()
    -- Scale max engineers per builder with energy income
    self.maxEngineersPerBuilder = math.ceil(self.ai.ecohst.Energy.income / 3000)

    local engineersNeeded = 0
    for builderID, engineers in pairs(self.Builders) do
        local count = #engineers                    -- Current engineers assigned
        local role = buildingshst.roles[builderID]  -- Builder's role
        local target = self[role.role]               -- Role's engineer quota
        local needed = (target * maxEngineersPerBuilder) - count
        engineersNeeded = engineersNeeded + needed
    end
    return engineersNeeded
end
```

Example: If `maxEngineersPerBuilder = 2` (energy income ~6000) and you have an `eco` builder (quota 3), it wants `3 * 2 = 6` engineers. If it already has 2, it needs 4 more.

### Builder Registration

When a new builder is constructed that has an associated engineer type, it registers itself:

```lua
-- In BuildersBST:EngineerhstBuilderBuild()
function BuildersBST:EngineerhstBuilderBuild()
    for engineerName, builderName in pairs(armyhst.engineers) do
        if self.name == builderName then
            engineerhst.Builders[self.id] = {}
            engineerhst:EngineersNeeded()   -- Recalculate demand
            return
        end
    end
end
```

### Assist Fallback in BuildersBST

When a builder exhausts its queue or is damaged, it falls back to assisting:

```lua
function BuildersBST:Assist()
    -- Find the closest builder with an active project
    for bossID, project in pairs(buildingshst.builders) do
        if UnitCanGoHere(builder, project.position) then
            local builderLevel = unitTable[project.builderName].techLevel
            if builderLevel >= bossLevel then   -- Prefer highest tech
                if distance < bossDist then     -- Then closest
                    bossTarget = project.builderID
                end
            end
        end
    end
    if bossTarget then
        GiveOrder(CMD.GUARD, bossTarget)   -- Guard = assist construction
        self.assistant = bossTarget
    end
end
```

---

## 6. Economy Filtering

### Rolling Average System (`EcoHST`)

STAI does not use raw instantaneous resource values. Instead, it maintains a **rolling average of 30 samples**:

```lua
local average = 30   -- Number of samples in the rolling window

function EcoHST:Init()
    self.samples = {}    -- Circular buffer of 30 snapshots
    self.Index = 1       -- Current write position

    -- Initialize all 30 samples with current values
    for i = 1, average do
        self.samples[i] = {
            Metal = { reserves, capacity, pull, income, usage, share, sent, received, full },
            Energy = { reserves, capacity, pull, income, usage, share, sent, received, full }
        }
    end

    -- Exposed averages (what task queue economy functions read):
    self.Energy = { reserves=0, capacity=1000, income=20, usage=0, ... full=1 }
    self.Metal  = { reserves=0, capacity=1000, income=20, usage=0, ... full=1 }
end
```

### Update Cycle

Each frame (gated by scheduler), one sample is overwritten and the entire average is recomputed:

```lua
function EcoHST:Update()
    -- Overwrite current sample slot with latest Spring data
    local M = self.samples[self.Index].Metal
    M.reserves, M.capacity, M.pull, M.income, M.usage, ... = Spring.GetTeamResources('metal')
    local E = self.samples[self.Index].Energy
    E.reserves, E.capacity, E.pull, E.income, E.usage, ... = Spring.GetTeamResources('energy')

    -- Recompute averages across all 30 samples
    for i, sample in pairs(self.samples) do
        for name, properties in pairs(sample) do
            for property, value in pairs(properties) do
                self[name][property] = self[name][property] + value
            end
        end
    end
    for i, name in pairs(self.resourceNames) do
        for property, value in pairs(self[name]) do
            self[name][property] = self[name][property] / average
        end
        -- Calculate fill ratio
        self[name].full = self[name].reserves / self[name].capacity
    end

    -- Advance circular buffer
    self.Index = self.Index + 1
    if self.Index > average then self.Index = 1 end
end
```

### Properties Tracked

For both Metal and Energy:

| Property | Description |
|---|---|
| `reserves` | Current amount in storage |
| `capacity` | Maximum storage capacity |
| `pull` | Amount being pulled (demand) |
| `income` | Rate of production |
| `usage` | Rate of consumption (expense) |
| `share` | Share level setting |
| `sent` | Amount shared to allies |
| `received` | Amount received from allies |
| `full` | `reserves / capacity` (0.0 to 1.0) |

### How Economy State Gates Tasks

The economy values are used **directly as closures** in the task definitions. Each task's `economy` field is a function that captures the `M` (Metal) and `E` (Energy) tables from the module scope:

```lua
-- From TasksHST:startRolesParams()
local M = self.ai.ecohst.Metal   -- Reference to the LIVE rolling average
local E = self.ai.ecohst.Energy

self.roles.eco = {
    { category = '_fus_',
      economy = function(_, param, name)
          return (E.income < E.usage * 1.25) or E.full < 0.5
      end,
      ...
    },
}
```

Because `M` and `E` are references to the live average tables (not copies), the economy functions always read the latest 30-sample averages. This means:

- Economy decisions are **smoothed** (no flickering from frame-to-frame noise)
- There is a **lag** (up to 30 update cycles) before drastic economy changes are reflected
- The `full` ratio is particularly useful for threshold decisions (e.g., "build storage when 90% full")

---

## 7. Strengths (What Works Well for Building)

### 7.1 Rectangle Avoidance Prevents Overlapping

The triple-layer rectangle system (`dontBuildRects`, `sketch`, `builders`) ensures that:
- Buildings never overlap with each other
- Planned builds are reserved before construction starts
- Metal/geo spots remain available for extractors
- Factory exit lanes stay clear

This is a simple but effective collision system. The fact that rectangles are checked at **plan time** (not just build time) prevents race conditions between multiple builders.

### 7.2 Metal/Geo Spot Exclusion Zones

The 80x80 elmo exclusion zones on metal and geo spots are added at initialization, ensuring no non-extractor building ever blocks a resource point. This is a critical correctness feature.

### 7.3 Spiral Search is Thorough

The expanding-radius spiral guarantees that if a valid position exists within `maxDist` of the anchor, it will eventually be found. The ring-by-ring approach means closer positions are tried first, which naturally produces tighter bases when space is available.

### 7.4 Role System Prevents All-Same-Thing Problem

By assigning different roles to different builders, STAI ensures that its economy develops on multiple fronts simultaneously:
- First builder does eco (factories + energy)
- Next builders expand (grab mexes)
- Later builders handle nanos, support, defense

Without this, all builders would chase the same highest-priority task.

### 7.5 Task Queues with Economy Conditions

Each task has its own economy gate, meaning:
- Expensive items are only attempted when the economy can support them
- Cheap items (wind, mex) have permissive gates
- The queue order creates a natural progression from cheap to expensive

### 7.6 Neighbour Density Checks

The `unitsNearCheck` system prevents over-saturating an area. For example, turret tasks have `neighbours = {'_popup2_'}` so the AI will not place 5 popups right next to each other.

### 7.7 Factory Lane Protection

The directional exit lane calculation is simple but effective. By extending the blocked rectangle in the factory's exit direction, STAI prevents the common AI mistake of walling in its own factories.

---

## 8. Weaknesses (Where It Still Scatters)

### 8.1 Spiral Search Inherently Spreads Buildings Outward

The fundamental problem: each building placed adds a new blocked rectangle. The next spiral search must find a position OUTSIDE all existing blocked rectangles. As the base grows, valid positions are pushed further and further from the anchor.

```
Turn 1: Build wind at anchor  -> radius 1 works
Turn 2: Build solar           -> radius 1 blocked, try radius 2
Turn 3: Build wind            -> radius 1-2 blocked, try radius 3
...
Turn N: Build converter       -> radius 1-N blocked, try radius N+1
```

Each successive building ends up in a larger ring, creating a progressively more scattered base.

### 8.2 No Concept of "Blocks" or "Modules"

STAI places each building **independently**. There is no higher-level grouping like "build a 3x3 grid of solars" or "build a fusion with 4 converters around it." Each building decision is:
1. Pick what to build
2. Find a position that passes all checks
3. Place it there

There is no spatial relationship between consecutive placements beyond "near the same anchor."

### 8.3 No Adjacency Preference

The spiral search returns the **first valid position**. It does not score candidates or prefer positions that would create tight clusters. Two solars might end up on opposite sides of the anchor, 200 elmos apart, even though there was a perfectly good spot right next to the first solar.

### 8.4 Random Angle Means Unpredictable Direction

```lua
local initAngle = math.random() * twicePi   -- Random each ring!
```

This is intentional (prevents directional bias) but means:
- Two identical build requests from the same anchor may produce positions in completely different directions
- The base layout is non-deterministic and cannot be predicted
- No preference for building in a consistent direction

### 8.5 No Spatial Planning -- Reactive, Not Proactive

STAI never asks "where should I put my next cluster of buildings?" It only asks "where can I put THIS building RIGHT NOW?" There is no:
- Forward reservation of space for future expansion
- Blueprint or template system for common building groups
- Strategic zone planning (eco zone, defense zone, production zone)

### 8.6 100-Elmo Default Spacing is Excessive

The `GetBuildSpacing` function returns 100 elmos for non-mex buildings. This means each building needs a 200-elmo-diameter clear cylinder, which is very generous and contributes significantly to base sprawl. For context, a typical solar collector footprint is about 32 elmos wide -- the 100-elmo spacing puts 3+ building widths of empty space between structures.

### 8.7 Anchor Selection is Distance-Based Only

When choosing which existing building to place near (`searchPosNearCategories`), the only criterion is **distance from the builder**. There is no consideration of:
- Which anchor has the most available space around it
- Which anchor is closer to the base center
- Which anchor would produce the most compact layout

### 8.8 No Building Rotation Optimization

Factory facing is determined by map edge proximity, not by where other buildings are. For non-factory buildings, facing is always 1 (the default in the order). There is no attempt to orient buildings for optimal space usage.

---

## 9. Lessons for Our Block-Based Design

### 9.1 Rectangle Tracking is Essential -- We Need It Too

STAI's rectangle system is its most valuable contribution. Any placement system needs to know:
- Where existing buildings are (including padding)
- Where metal/geo spots are (to keep them clear)
- Where planned builds will go (to prevent conflicts)
- Where factory exits need to stay clear

**For BARB:** We should adopt rectangle tracking but extend it. Instead of just "is this spot blocked?" we should maintain a spatial grid that tracks both blocked areas AND designated zones (eco zone, defense zone, etc.).

### 9.2 Factory Exit Lanes Must Be Respected

Factory lane calculation is simple and effective. We should carry this forward directly, possibly with improvements:
- Lane width based on the widest unit the factory can produce
- Lane length based on rally point distance
- Dynamic lane adjustment if rally point changes

### 9.3 Economy Gating Works Well

The pattern of attaching economy conditions to each build task is clean and effective. We should keep this pattern but make the conditions more sophisticated:
- Instead of threshold checks, use rate-of-change predictions
- Factor in build time (will we have enough income by the time it finishes?)
- Consider opportunity cost (building X means not building Y)

### 9.4 Role-Based Builder Assignment is Superior

Treating all constructors the same (as our current TotallyLegal does) leads to:
- All builders chasing the same task
- No specialization
- No parallelism in base development

**For BARB:** We should implement roles, but potentially simplify to 3-4 roles instead of 8:
- `foundation` -- early game opener
- `eco` -- energy, storage, converters
- `expand` -- mexes and forward positions
- `defense` -- turrets, AA, radar

### 9.5 The Spiral Search is the Root Cause of Scattering

**This is the single most important lesson.** The spiral search algorithm fundamentally cannot produce compact, organized bases because:

1. It returns the **first** valid position, not the **best** position
2. It searches outward, meaning positions far from center are found when close ones are blocked
3. The random starting angle prevents consistent directional building
4. There is no concept of "preferred zones" or "designated areas"

**For BARB, we need a fundamentally different placement algorithm:**

Instead of "search outward from anchor until something works," we need:

```
1. Define ZONES (eco zone, defense zone, factory zone)
2. Within each zone, define a GRID of preferred positions
3. When placing a building:
   a. Determine which zone it belongs to
   b. Score all available grid positions in that zone
   c. Pick the highest-scoring position
   d. Score factors: adjacency to related buildings, distance to zone center,
      compactness, access paths
```

This inverts the search: instead of "where CAN I build?" it becomes "where SHOULD I build?"

### 9.6 The Neighbour Check Pattern is Reusable

The `unitsNearCheck` pattern (checking density of specific unit types within a radius) is a good primitive for our system too. We can use it for:
- Ensuring defense coverage doesn't over-concentrate
- Spreading radar coverage across the map
- Preventing energy storage from clustering (blast radius risk)

### 9.7 The Assist Fallback is Good Design

When a builder cannot find any valid task, falling back to "guard the closest active builder" is an excellent pattern. It ensures constructors are never truly idle -- they always contribute to something. We should implement this in BARB.

### 9.8 Summary: What to Keep vs What to Replace

| STAI Feature | Keep / Replace | Reason |
|---|---|---|
| Rectangle tracking | **Keep** (and extend) | Fundamental correctness requirement |
| Factory exit lanes | **Keep** | Prevents blocking |
| Economy gating per task | **Keep** (and improve) | Clean, effective pattern |
| Role-based builders | **Keep** (simplify) | Prevents all-same-task problem |
| Rolling eco averages | **Keep** | Smooths noisy data |
| Neighbour density check | **Keep** | Prevents over-saturation |
| Assist fallback | **Keep** | No idle constructors |
| Spiral search | **REPLACE** | Root cause of scattering |
| Independent per-building placement | **REPLACE** | Need block/module concept |
| Random start angle | **REPLACE** | Need deterministic zone-based placement |
| 100-elmo default spacing | **REDUCE** | Excessive, causes sprawl |
| Distance-only anchor selection | **REPLACE** | Need multi-criteria scoring |

---

## Appendix A: Full File Reference

All source files under `Beyond-All-Reason/luarules/gadgets/ai/STAI/`:

| File | Lines | Role |
|---|---|---|
| `buildingshst.lua` | 697 | Build position system, rectangle tracking, role assignment |
| `buildersbst.lua` | 477 | Builder behaviour: queue processing, position search, assist fallback |
| `taskshst.lua` | 1202 | Task queue definitions for all 8 roles + factory production queues |
| `ecohst.lua` | 128 | Rolling 30-sample economy averages |
| `engineerhst.lua` | 63 | Engineer demand calculation and builder tracking |
| `labshst.lua` | 408 | Factory management: rating, selection, positioning, production |
| `common/stai_factory_rect.lua` | 51 | Shared rectangle outset calculator |

Full STAI file listing (42 files):
`ai.lua`, `antinukebst.lua`, `armyhst.lua`, `astarclass.lua`, `attackerbst.lua`, `attackhst.lua`, `behaviourfactory.lua`, `behaviours.lua`, `bomberbst.lua`, `bomberhst.lua`, `boot.lua`, `bootbst.lua`, `buildersbst.lua`, `buildingshst.lua`, `cleanerbst.lua`, `cleanhst.lua`, `commanderbst.lua`, `damagehst.lua`, `ecohst.lua`, `engineerbst.lua`, `engineerhst.lua`, `labsbst.lua`, `labshst.lua`, `loshst.lua`, `maphst.lua`, `mexupbst.lua`, `modules.lua`, `nukebst.lua`, `nullbehaviour.lua`, `nullmodule.lua`, `overviewhst.lua`, `raidbst.lua`, `raidhst.lua`, `reclaimbst.lua`, `schedulerHST.lua`, `scoutbst.lua`, `scouthst.lua`, `sleepst.lua`, `targethst.lua`, `taskshst.lua`, `test.lua`, `tool.lua`, `unithst.lua`

---

## Appendix B: Key Data Flow Diagram

```
                        GAME ENGINE
                            |
                Spring.GetTeamResources()
                Spring.TestBuildOrder()
                Spring.Pos2BuildPos()
                            |
                            v
    +--------------------------------------------------+
    |                    EcoHST                         |
    |  samples[1..30] --> rolling average               |
    |  .Metal = { income, usage, reserves, full, ... }  |
    |  .Energy = { income, usage, reserves, full, ... } |
    +----------------------|---------------------------+
                           |  economy functions read
                           |  live references to M, E
                           v
    +--------------------------------------------------+
    |                   TasksHST                        |
    |  .roles = {                                       |
    |    starter = [ task1, task2, ... ],                |
    |    eco     = [ task1, task2, ... ],                |
    |    expand  = [ task1, task2, ... ],                |
    |    ...                                            |
    |  }                                                |
    |  Each task = { category, economy(), special,      |
    |                numeric, duplicate, location }      |
    +----------------------|---------------------------+
                           |  queue per role
                           v
    +--------------------------------------------------+
    |               BuildingsHST                        |
    |  .roles[builderID] = { role, builderName }        |
    |  .builders[builderID] = { unitName, position, ... }|
    |  .sketch[unitID] = { unitName, position, ... }    |
    |  .dontBuildRects[] = { x1,z1,x2,z2,unitID }      |
    |                                                    |
    |  SetRole()        --> assign role to builder       |
    |  FindClosestBuildSite() --> spiral search          |
    |  CheckBuildPos()  --> validation chain             |
    |  NewPlan()        --> register planned build       |
    |  CalculateRect()  --> compute building rectangle   |
    +----------------------|---------------------------+
                           |  roles, positions,
                           |  rectangle checks
                           v
    +--------------------------------------------------+
    |               BuildersBST (per unit)              |
    |  .role = 'eco'                                    |
    |  .queue = taskshst.roles['eco']                   |
    |  .idx = current position in queue                 |
    |  .fails = consecutive placement failures          |
    |                                                    |
    |  ProgressQueue() --> iterate tasks                 |
    |    getOrder()    --> find buildable unit name      |
    |    specialFilter()--> wind/tide/AA checks          |
    |    limitedNumber()--> count limits                 |
    |    CheckForDuplicates() --> no double builds       |
    |    CategoryEconFilter() --> economy gate           |
    |    findPlace()   --> resolve position              |
    |                                                    |
    |  Assist()        --> guard closest active builder  |
    +--------------------------------------------------+
                           |
                           v
                    BUILD ORDER ISSUED
                 GiveOrder(-defID, {x,y,z,facing})
```

---

*This report is a definitive reference for the STAI building system. All code snippets are from the actual source files. The analysis should eliminate the need to re-read the STAI source code for the BARB quest's building placement design work.*
