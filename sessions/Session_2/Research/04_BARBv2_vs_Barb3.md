# Research Report 04: BARb v2 vs Barb3 -- Structural Comparison

> **Session:** Session_2
> **Date:** 2026-02-13
> **Focus:** Architecture, config system, and building logic differences between BARb v2 (legacy) and Barb3 (modern)
> **Sources:** Local files only -- `Prod/Skirmish/BARb/stable/`, `Prod/Skirmish/Barb3/stable/`, `Prod/Beyond-All-Reason/luarules/configs/BARb/`

---

## 1. Version History and Context

### BARb v2 -- The Legacy AI

BARb (Beyond All Reason Bot) was created by **Felenious** with over 1,600 hours of development time. It is the official AI shipped with the BAR game itself, embedded directly in the main game repository at `Beyond-All-Reason/luarules/configs/BARb/`. The Skirmish AI variant (`Skirmish/BARb/stable/`) is the standalone deployment of the same logic.

BARb v2 operates on a **per-difficulty-level architecture**: separate script directories for `easy`, `medium`, `hard`, and `hard_aggressive`. Each difficulty level contains its own copy of the four manager files (builder, economy, factory, military) plus an init file and a commander handler. Configuration is similarly duplicated -- per-difficulty JSON files for behaviour, build_chain, block_map, commander, economy, factory, and response.

The AI is written in **AngelScript** and compiled into `SkirmishAI.dll`, loaded by the CircuitAI C++ engine at runtime.

### Barb3 -- The Modern Refactor

Barb3 is the next-generation version, developed as a **separate Skirmish AI** in `Skirmish/Barb3/stable/`. It represents a ground-up refactor of BARb v2 with several key design goals:

- **Modularity:** Shared code in a single `src/` directory eliminates duplication across difficulty levels
- **Per-profile configuration:** Instead of difficulty-named folders, profiles are named descriptively (e.g., `experimental_balanced`, `experimental_Suicidal`)
- **Role system:** An AI role framework (FRONT, AIR, TECH, SEA, FRONT_TECH, HOVER_SEA) drives per-role behavior, factory selection, economy management, and building priorities
- **Map awareness:** Per-map configuration files with start spots, factory weights, unit limits, and strategic objectives
- **Per-faction configs:** Separate configuration files for Armada, Cortex, and Legion factions (not merged into a single file)
- **Strategy system:** Weighted probabilistic strategy selection at game start (T2 rush, T3 rush, nuke rush)

Barb3 still compiles to `SkirmishAI.dll` and runs on the same CircuitAI C++ engine.

### Why v3 Exists

The v2 codebase became difficult to maintain because:
1. Every difficulty level duplicated the entire script tree -- changes needed propagation to 4+ copies
2. No concept of "roles" -- every AI instance played identically regardless of map position
3. No per-map tuning -- the AI had no awareness of map topology, start positions, or water coverage
4. No faction-specific configs -- Armada and Cortex shared config files, with Legion bolted on via conditionals
5. Limited extensibility -- adding a new feature meant editing 4+ files in lockstep

---

## 2. Folder Structure Comparison

### BARb v2 Structure

```
BARb/stable/
|-- AIInfo.lua
|-- AIOptions.lua
|-- SkirmishAI.dll
|-- config/
|   |-- behaviour.json          (default/fallback)
|   |-- block_map.json
|   |-- build_chain.json
|   |-- commander.json
|   |-- economy.json
|   |-- factory.json
|   |-- response.json
|   |-- easy/
|   |   |-- behaviour.json
|   |   |-- build_chain.json
|   |   |-- commander.json
|   |   |-- economy.json
|   |   |-- factory.json
|   |   |-- response.json
|   |   +-- easy_ai_readme.txt
|   |-- medium/
|   |   |-- behaviour.json
|   |   |-- build_chain.json
|   |   |-- commander.json
|   |   |-- economy.json
|   |   +-- factory.json
|   |-- hard/
|   |   |-- behaviour.json
|   |   |-- behaviour_leg.json
|   |   |-- block_map.json
|   |   |-- block_map_leg.json
|   |   |-- build_chain.json
|   |   |-- build_chain_leg.json
|   |   |-- commander.json
|   |   |-- commander_leg.json
|   |   |-- economy.json
|   |   |-- economy_leg.json
|   |   |-- factory.json
|   |   |-- factory_leg.json
|   |   +-- response.json
|   +-- hard_aggressive/
|       |-- (same structure as hard/)
|       +-- ...
+-- script/
    |-- common.as               (side registration, armor, categories)
    |-- define.as               (constants)
    |-- task.as                 (task definitions)
    |-- unit.as                 (unit definitions)
    |-- easy/
    |   |-- init.as
    |   |-- main.as
    |   |-- manager/
    |   |   |-- builder.as
    |   |   |-- economy.as
    |   |   |-- factory.as
    |   |   +-- military.as
    |   +-- misc/
    |       +-- commander.as
    |-- medium/                 (same structure as easy/)
    |-- hard/                   (same structure as easy/)
    +-- hard_aggressive/        (same structure as easy/)
```

**Key observation:** The script directory is duplicated 4 times. Each difficulty has its own `init.as`, `main.as`, and 4 manager files plus a commander handler. Total: ~24 difficulty-specific script files.

### Barb3 Structure

```
Barb3/stable/
|-- AIInfo.lua
|-- AIOptions.lua
|-- SkirmishAI.dll
|-- config/
|   |-- experimental_balanced/
|   |   |-- ArmadaBehaviour.json
|   |   |-- ArmadaBuildChain.json
|   |   |-- ArmadaEconomy.json
|   |   |-- ArmadaFactory.json
|   |   |-- CortexBehaviour.json
|   |   |-- CortexBuildChain.json
|   |   |-- CortexEconomy.json
|   |   |-- CortexFactory.json
|   |   |-- LegionBehaviour.json
|   |   |-- LegionBuildChain.json
|   |   |-- LegionEconomy.json
|   |   |-- LegionFactory.json
|   |   |-- block_map.json
|   |   |-- commander.json
|   |   |-- commander_leg.json
|   |   |-- extrascavunits.json
|   |   |-- extraunits.json
|   |   +-- response.json
|   |-- experimental_EightyBonus/    (same structure)
|   |-- experimental_FiftyBonus/     (same structure)
|   |-- experimental_HundredBonus/   (same structure)
|   |-- experimental_Suicidal/       (same structure)
|   +-- experimental_ThirtyBonus/    (same structure)
+-- script/
    |-- experimental_balanced/
    |   |-- init.as             (thin profile entry point)
    |   +-- main.as             (thin profile entry point)
    |-- experimental_EightyBonus/
    |   |-- init.as
    |   +-- main.as
    |-- (... one pair per profile ...)
    +-- src/                    (*** SHARED CODE ***)
        |-- common.as
        |-- define.as
        |-- global.as           (*** NEW: global state namespace ***)
        |-- setup.as            (*** NEW: map/role/profile setup ***)
        |-- maps.as             (*** NEW: map registration ***)
        |-- task.as
        |-- unit.as
        |-- helpers/
        |   |-- builder_helpers.as
        |   |-- collection_helpers.as
        |   |-- defense_helpers.as
        |   |-- economy_helpers.as
        |   |-- factory_helpers.as
        |   |-- generic_helpers.as
        |   |-- guard_helpers.as
        |   |-- limits_helpers.as
        |   |-- map_helpers.as
        |   |-- objective_executor.as
        |   |-- objective_helpers.as
        |   |-- role_helpers.as
        |   |-- role_limit_helpers.as
        |   |-- task_helpers.as
        |   |-- terrain_helpers.as
        |   |-- unit_helpers.as
        |   +-- unitdef_helpers.as
        |-- manager/
        |   |-- builder.as      (1000+ lines, shared)
        |   |-- economy.as
        |   |-- factory.as
        |   +-- military.as
        |   +-- objective_manager.as
        |-- maps/
        |   |-- default_map_config.as
        |   |-- factory_mapping.as
        |   |-- supreme_isthmus.as
        |   |-- all_that_glitters.as
        |   |-- (... 17+ map files ...)
        |   +-- mediterraneum.as
        |-- misc/
        |   +-- commander.as
        |-- roles/
        |   |-- front.as
        |   |-- front_tech.as
        |   |-- air.as
        |   |-- tech.as
        |   |-- sea.as
        |   +-- hover_sea.as
        +-- types/
            |-- ai_role.as
            |-- building_type.as
            |-- map_config.as
            |-- opener.as
            |-- profile.as
            |-- profile_controller.as
            |-- role_config.as
            |-- start_spot.as
            |-- strategic_objectives.as
            |-- strategy.as
            +-- terrain.as
```

**Key observation:** The `src/` directory contains ALL shared logic. Profile directories (`experimental_balanced/`, etc.) contain only thin `init.as` + `main.as` wrappers that `#include` from `src/`. Total shared source files: ~45+, versus ~4 duplicated per profile.

---

## 3. Script Architecture

### v2: Flat Manager Duplication

In v2, each difficulty level is self-contained. The `main.as` for hard difficulty includes the four managers directly:

```angelscript
// BARb/stable/script/hard/main.as
#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"

namespace Main {
    void AiMain() {
        // Mark T2/T3 factories with attributes
        for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
            CCircuitDef@ cdef = ai.GetCircuitDef(defId);
            if (cdef.costM >= 200.f && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 1.f)
                cdef.AddAttribute(Unit::Attr::BASE.type);
        }
        // ... factory T2/T3 attribute tagging ...
    }
    void AiUpdate() {}  // empty
}
```

The `init.as` loads a flat list of profile configs:

```angelscript
// BARb/stable/script/hard/init.as
@data.profile = @(array<string> = {
    "behaviour", "block_map", "build_chain", "commander",
    "economy", "factory", "response"
});
// Optional Legion add-on
if (experimentallegionfaction == "1") {
    data.profile.insertAt(data.profile.length(), {
        "behaviour_leg", "block_map_leg", "build_chain_leg",
        "commander_leg", "economy_leg", "factory_leg"
    });
}
```

Each manager file (e.g., `builder.as`) directly implements the AI callbacks: `AiMakeTask`, `AiTaskAdded`, `AiTaskRemoved`, `AiUnitAdded`, `AiUnitRemoved`. No abstraction layers exist.

### v3: Shared Source with Role Delegation

In v3, the profile entry points are minimal wrappers:

```angelscript
// Barb3/stable/script/experimental_balanced/main.as
#include "../src/setup.as"
#include "../src/helpers/generic_helpers.as"
#include "../src/global.as"
#include "../src/maps.as"
#include "../src/types/strategy.as"

namespace Main {
    // Weighted strategy configuration
    namespace StrategyWeights {
        float Tech_T2_RUSH = 0.85f;
        float Tech_T3_RUSH = 0.35f;
        float Tech_NUKE_RUSH = 0.25f;
    }

    void AiMain() {
        Maps::registerMaps();
        ApplyTechStrategyWeights();
        // Factory T2/T3 tagging...
        ApplyProfileSettings();
    }

    void AiUpdate() {
        if (Global::profileController !is null)
            Global::profileController.MainUpdate();
    }
}
```

The `init.as` loads **per-faction** config files:

```angelscript
// Barb3/stable/script/experimental_balanced/init.as
@data.profile = @(array<string> = {
    "ArmadaBehaviour", "CortexBehaviour",
    "ArmadaBuildChain", "CortexBuildChain",
    "block_map", "commander",
    "ArmadaEconomy", "CortexEconomy",
    "ArmadaFactory", "CortexFactory",
    "response"
});
// Conditional: Legion, Scav Units, Extra Units
```

The `setup.as` file is the **orchestration hub** -- it includes all role handlers, all helper modules, all managers, and drives the entire initialization sequence:

```angelscript
// Barb3/stable/script/src/setup.as (includes, abbreviated)
#include "helpers/generic_helpers.as"
#include "roles/front.as"
#include "roles/front_tech.as"
#include "roles/air.as"
#include "roles/tech.as"
#include "roles/sea.as"
#include "roles/hover_sea.as"
#include "types/role_config.as"
#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
```

### v3 Systems Not Present in v2

| System | Files | Purpose |
|--------|-------|---------|
| Role system | `roles/*.as`, `types/ai_role.as`, `types/role_config.as` | Per-role behavior handlers, factory selection, economy tuning |
| Map configs | `maps/*.as`, `types/map_config.as`, `types/start_spot.as` | Per-map start spots, unit limits, factory weights |
| Opener system | `types/opener.as` | Probabilistic build queues per factory type |
| Strategic objectives | `types/strategic_objectives.as`, `types/building_type.as` | Per-map build objectives with eco/role gates |
| Profile controller | `types/profile_controller.as` | Runtime role dispatch, per-tick role updates |
| Strategy system | `types/strategy.as` | Bitmask strategies (T2_RUSH, T3_RUSH, NUKE_RUSH) |
| Global state | `global.as` | Centralized state: map info, economy tracking, role settings |
| 17 helper modules | `helpers/*.as` | Builder, defense, economy, factory, guard, limits, map, objective, role, task, terrain, unit helpers |

---

## 4. Config System

### v2: Per-Difficulty, Faction-Agnostic

BARb v2 uses a **flat per-difficulty** config layout:

```
config/
|-- hard/
|   |-- behaviour.json          (Armada + Cortex merged)
|   |-- behaviour_leg.json      (Legion overlay)
|   |-- block_map.json
|   |-- block_map_leg.json
|   |-- build_chain.json
|   |-- build_chain_leg.json
|   |-- commander.json
|   |-- economy.json            (Armada + Cortex merged)
|   |-- economy_leg.json
|   |-- factory.json
|   +-- response.json
```

Both factions share the same economy file. The v2 economy config embeds both `armada` and `cortex` entries:

```json
// BARb v2 - config/hard/economy.json
"energy": {
    "land": {
        "armwin": [200, 300],
        "armsolar": [80, 120],
        "armfus": [30, 40],
        "armafus": [200, 300],
        "corwin": [200, 300],
        "corsolar": [80, 120],
        "corfus": [30, 40],
        "corafus": [200, 300]
    }
}
```

### v3: Per-Profile, Per-Faction

Barb3 splits config by **profile name** and **faction**:

```
config/
|-- experimental_balanced/
|   |-- ArmadaBehaviour.json
|   |-- ArmadaBuildChain.json
|   |-- ArmadaEconomy.json
|   |-- ArmadaFactory.json
|   |-- CortexBehaviour.json
|   |-- CortexBuildChain.json
|   |-- CortexEconomy.json
|   |-- CortexFactory.json
|   |-- LegionBehaviour.json    (full first-class support)
|   |-- LegionBuildChain.json
|   |-- LegionEconomy.json
|   |-- LegionFactory.json
|   |-- block_map.json          (shared across factions)
|   |-- commander.json
|   |-- response.json
|   |-- extrascavunits.json     (new: scav unit support)
|   +-- extraunits.json         (new: experimental units)
```

The Armada economy file in v3 contains only Armada entries:

```json
// Barb3 - config/experimental_balanced/ArmadaEconomy.json
"energy": {
    "land": {
        "armwin": [200, 300],
        "armsolar": [80, 120],
        "armadvsol": [80, 120],
        "armfus": [30, 40],
        "armafus": [50, 100, 70, 4000, 6.44],
        "armgeo": [4, 8, 16, 300]
    }
}
```

**Config files and what they control:**

| Config File | Purpose |
|-------------|---------|
| `block_map.json` | Spatial blocking rules: how buildings claim space around themselves (shape, type, yard size, ignore lists). Controls factory spacing, energy cluster density, defense placement exclusion zones |
| `*BuildChain.json` | Build chain triggers: what to build when a structure finishes (e.g., build a pylon near a completed solar, place defenses near a mex). The "hub" system allows chained multi-step construction sequences |
| `*Economy.json` | Energy generation limits, income factors over time, cluster ranges, mex/geo definitions, build-speed modifiers |
| `*Factory.json` | Factory production weights, unit role assignments, unit priorities per factory type |
| `*Behaviour.json` | Unit behavior tuning: retreat thresholds, engagement rules, role assignments for specific unit definitions |
| `commander.json` | Commander build sequences and behavior |
| `response.json` | Threat response configuration |

---

## 5. Role System (v3 Only)

### The AiRole Enum

Barb3 introduces a formal **role** concept that determines the AI's strategic personality for an entire game session:

```angelscript
// Barb3/stable/script/src/types/ai_role.as
enum AiRole {
    FRONT = 0,       // Aggressive ground forces
    AIR = 1,         // Air superiority
    TECH = 2,        // Technology rush / economy focus
    SEA = 3,         // Naval dominance
    FRONT_TECH = 4,  // Hybrid front-tech / economic substitute
    HOVER_SEA = 5,   // Hybrid sea role, preferring hovercraft
}
```

### Deferred Initialization Pattern

The role is **not** determined at AI startup. Instead, it is resolved lazily when the first factory is requested:

1. **`AiGetFactoryToBuild`** is called by the C++ engine when the AI needs its first factory
2. This triggers **`Setup::setupMap(pos)`** with the actual start position
3. `setupMap` reads the map name, finds the matching `MapConfig`, finds the nearest `StartSpot`, and derives the `AiRole`
4. The role determines which `RoleConfig` is selected and cached in `Global::profileController.RoleCfg`
5. All subsequent builder, factory, economy, and military decisions route through the role's delegate handlers

```angelscript
// Barb3/stable/script/src/setup.as (abbreviated flow)
void setupMap(const AIFloat3& in startPos) {
    Global::Map::MapName = ai.GetMapName();
    Global::Map::Config = Maps::mapManager.getMapConfig(Global::Map::MapName);

    string side = ai.GetSideName();
    string defaultFactoryName = Factory::GetDefaultFactory(startPos, true, false).GetName();
    AiRole defaultRole = RoleHelpers::DefaultRoleForFactory(defaultFactoryName);

    // Nearest start spot determines the map-assigned role
    @Global::Map::NearestMapStartPosition = MapHelpers::NearestSpot(startPos, spots);
    AiRole derivedRole = Global::Map::NearestMapStartPosition.aiRole;

    // Match role to a registered RoleConfig
    RoleConfig@ matchedCfg = RoleConfigs::Match(derivedRole, side, startPos, defaultFactoryName);
    @Global::profileController.RoleCfg = matchedCfg;

    // Apply role-specific startup unit limits
    RoleConfigs::ApplyStartLimits();

    // Merge map + role unit limits
    dictionary@ merged = LimitsHelpers::ComputeAndStoreMergedUnitLimits(Global::Map::Config, derivedRole);
    UnitHelpers::ApplyUnitLimits(merged);
}
```

### Per-Role Behavior via RoleConfig

Each role registers a `RoleConfig` object containing delegate function pointers that override default behavior:

```angelscript
// Barb3/stable/script/src/types/role_config.as
class RoleConfig {
    AiRole role;
    dictionary UnitMaxOverrides;
    MainUpdateDelegate@ MainUpdateHandler;
    EconomyUpdateDelegate@ EconomyUpdateHandler;
    InitDelegate@ InitHandler;

    // Factory switching policy
    AiIsSwitchTimeDelegate@ AiIsSwitchTimeHandler;
    AiIsSwitchAllowedDelegate@ AiIsSwitchAllowedHandler;

    // Builder delegates
    AiMakeTaskDelegate@ BuilderAiMakeTaskHandler;
    AiTaskAddedDelegate@ BuilderAiTaskAddedHandler;
    AiUnitAddedDelegate@ BuilderAiUnitAdded;

    // Factory delegates
    AiMakeTaskDelegate@ FactoryAiMakeTaskHandler;
    SelectFactoryDelegate@ SelectFactoryHandler;

    // Military delegates
    AiMakeTaskDelegate@ MilitaryAiMakeTaskHandler;
    AiMakeDefence@ AiMakeDefenceHandler;

    // Role matching predicate
    RoleMatchDelegate@ RoleMatchHandler;
}
```

**Why this matters for building:** Different roles have fundamentally different building priorities. The TECH role prioritizes T2 labs, energy infrastructure, and mex upgrades. The FRONT role prioritizes factories, defenses, and nano caretakers. The HOVER_SEA role may prioritize seaplane platforms and tidal generators. The role's `BuilderAiMakeTaskHandler` can intercept and redirect every builder task request.

---

## 6. Builder/Building Logic Differences

This is the central section for understanding the building placement gap.

### v2 Builder: Minimal Scripting, Maximum Delegation

The BARb v2 builder is remarkably thin -- only 162 lines including comments:

```angelscript
// BARb/stable/script/hard/manager/builder.as
namespace Builder {
    CCircuitUnit@ energizer1 = null;
    CCircuitUnit@ energizer2 = null;

    IUnitTask@ AiMakeTask(CCircuitUnit@ unit) {
        // Delegates entirely to the C++ engine
        return aiBuilderMgr.DefaultMakeTask(unit);
    }

    void AiTaskAdded(IUnitTask@ task) {
        // Empty -- all commented out debug logging
    }

    void AiTaskRemoved(IUnitTask@ task, bool done) {
        // Empty -- all commented out
    }

    void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage) {
        // Simple logic: first two cheap constructors get BASE attribute
        if (cdef.costM < 200.f) {
            if (energizer1 is null) {
                @energizer1 = unit;
                unit.AddAttribute(Unit::Attr::BASE.type);
            }
        } else {
            if (energizer2 is null) {
                @energizer2 = unit;
                unit.AddAttribute(Unit::Attr::BASE.type);
            }
        }
    }
}
```

**Key insight:** v2 building decisions are almost entirely made by the C++ `aiBuilderMgr.DefaultMakeTask()` engine. The AngelScript layer merely tags the first two constructors as "BASE" units (so they build near the base). Everything else -- what to build, where to place it, when to build it -- is handled by the C++ placement algorithm reading from `block_map.json` and `build_chain.json`.

### v3 Builder: Massive Script-Side Management

The Barb3 builder is **1000+ lines** of AngelScript with extensive constructor management:

```angelscript
// Barb3/stable/script/src/manager/builder.as (structure overview)
namespace Builder {
    // COMMANDER + GUARDS
    CCircuitUnit@ commander = null;
    dictionary commanderGuards;

    // TACTICAL CONSTRUCTORS (one per unit category)
    bool TacticalEnabled = false;
    CCircuitUnit@ tacticalBotConstructor = null;
    CCircuitUnit@ tacticalVehConstructor = null;
    CCircuitUnit@ tacticalAirConstructor = null;
    CCircuitUnit@ tacticalSeaConstructor = null;
    CCircuitUnit@ tacticalHoverConstructor = null;

    // PRIMARY/SECONDARY CONSTRUCTORS (per category, per tier)
    CCircuitUnit@ primaryT1BotConstructor = null;
    CCircuitUnit@ secondaryT1BotConstructor = null;
    CCircuitUnit@ primaryT2BotConstructor = null;
    CCircuitUnit@ secondaryT2BotConstructor = null;
    // ... same for Veh, Air, Sea, Hover ...

    // GUARD MAPS (per constructor, per tier)
    dictionary primaryT1BotConstructorGuards;
    dictionary secondaryT1BotConstructorGuards;
    // ... 18+ guard dictionaries ...

    // WORKER POOL
    dictionary unassignedWorkers;

    // TASK TRACKING
    dictionary builderCurrentTasks;
    dictionary trackEligibleBuilders;
    dictionary taskTrackByUnit;

    // BUILD QUEUE COUNTERS
    int T2LabQueuedCount = 0;
    int FusionQueuedCount = 0;
    int AdvancedFusionQueuedCount = 0;
    int LandGantryQueuedCount = 0;
    int NukeSiloQueuedCount = 0;
    // ... many more ...

    // COOLDOWN SYSTEM
    const int T2_FACTORY_COOLDOWN_FRAMES = 120 * SECOND;
    const int GANTRY_COOLDOWN_FRAMES = 120 * SECOND;
    const int NANO_COOLDOWN_FRAMES = 2 * SECOND;
    // ... per-structure-type cooldowns ...
}
```

#### Constructor Hierarchy

Barb3 organizes constructors into a **leadership hierarchy**:

1. **Commander** -- the starting unit, receives its own guard pool
2. **Primary constructors** -- first constructor of each category/tier, acts as the "lead builder"
3. **Secondary constructors** -- second constructor, acts as backup/parallel builder
4. **Tactical constructors** -- optional per-category constructor for front-line building
5. **Freelance constructors** -- T2 constructors that operate independently
6. **Unassigned workers** -- builders not currently assigned to any leader

Guards (assisting builders) are distributed across leaders using dictionaries keyed by unit ID. The promotion system automatically fills vacancies:

```angelscript
void PromotePrimaryT1BotIfNeeded() {
    if (primaryT1BotConstructor is null) {
        CCircuitUnit@ p1 = PromoteFromGuards(
            @primaryT1BotConstructorGuards, null, "primaryT1BotConstructor");
        if (p1 !is null) { @primaryT1BotConstructor = p1; }
    }
}
```

#### Task Tracking System

Barb3 implements a per-builder task tracking system that v2 lacks entirely:

```angelscript
class BuilderTaskTrack {
    IUnitTask@ task;
    CCircuitUnit@ unit;
    bool isTaskAdded;
    int createdFrame;
    int graceUntilFrame;
    int timeoutFrame;
    string defName;
    int buildTypeVal;

    bool IsLikelyStarted() const {
        if (!isTaskAdded || task is null || unit is null) return false;
        const float startRange = SQUARE_SIZE * 48.0f;
        return MapHelpers::IsUnitInRangeOfTask(unit, task, startRange);
    }
}
```

This tracks what each builder is working on, whether it has actually started construction, and applies grace periods and timeouts to prevent stuck builders. The v2 builder has none of this -- it fires and forgets.

#### How Building Tasks Are Created

**v2:** The `AiMakeTask` function calls `aiBuilderMgr.DefaultMakeTask(unit)` and returns. The C++ engine decides what to build based on config files (economy needs, block_map constraints, build_chain triggers). The script has zero influence over what gets built or where.

**v3:** The `MakeDefaultTaskWithLog` function wraps the same C++ call but adds:
- Logging of every task creation with unit position, definition name, and build type
- Task metadata extraction (build definition name, build type value)
- Per-builder task caching for deduplication
- Role-specific task interception via `BuilderAiMakeTaskHandler` delegate

The role handler (e.g., `RoleFront`, `RoleTech`) can intercept the builder task pipeline to:
- Gate factory construction behind economy thresholds
- Enforce cooldowns between structure types
- Manage build queues for fusion reactors, T2 labs, gantries, nuke silos
- Track and coordinate multiple builders working on the same structure type

### How block_map.json Is Used

Both v2 and v3 use `block_map.json` to define spatial blocking rules. The JSON is read by the **C++ engine**, not by AngelScript. It tells the C++ placement algorithm:

- How much space each building class claims (yard size)
- What shape the blocker uses (rectangle vs circle)
- Which structure types can overlap (ignore lists)
- How factories, energy buildings, defenses, and mexes relate spatially

**v2 block_map** uses generic class names:

```json
"fac_veh": { "type": ["rectangle", "factory"], "offset": [0, 1], "yard": [8, 10] },
"fac_bot": { "type": ["rectangle", "factory"], "offset": [0, 1], "yard": [6, 8] }
```

**v3 block_map** introduces tier-aware classes with different spacing:

```json
"fac_land_t1": { "type": ["rectangle", "factory"], "offset": [0, 5], "size": [8, 8], "yard": [0, 30] },
"fac_land_t2": { "type": ["rectangle", "factory"], "yard": [12, 20], "offset": [4, 6] }
```

Notable v3 additions:
- `fac_land_t1` and `fac_land_t2` as separate classes (v2 had `fac_veh` and `fac_bot`)
- `advsolar` as its own class (v2 grouped it with `fusion`)
- `def_mid` and `def_hvy` tiers (v2 only had `def_low`)
- `def_air` as a separate class
- Much larger factory yards (v3: `yard: [0, 30]` for T1 vs v2: `yard: [8, 10]` for vehicles)

### The Build Chain Hub System

Both versions use `build_chain.json` to define what happens when a structure finishes. The "hub" system allows chaining multiple structures off a completed building:

```json
// Example hub pattern (from v2 hard build_chain.json)
"hub": [
    [{"unit": "armsolar", "category": "energy", "offset": [64, 0]},
     {"unit": "armsolar", "category": "energy", "offset": [-64, 0]}],
    // chain2...
]
```

When a building completes, the engine reads the hub entries and places the chained buildings at the specified offsets. This is the **primary mechanism** for creating building clusters in both v2 and v3.

In v3, the build chain configs are per-faction (`ArmadaBuildChain.json`, `CortexBuildChain.json`) and can be tuned independently for each faction's specific building footprints.

---

## 7. Map Configuration System (v3 Only)

Barb3 introduces a comprehensive per-map configuration system with 17+ individually configured maps.

### Map Registration

```angelscript
// Barb3/stable/script/src/maps.as
namespace Maps {
    MapConfigManager@ mapManager = MapConfigManager(DEFAULT_MAP_CONFIG);

    void registerMaps() {
        SupremeIsthmus::registerObjectives();
        mapManager.RegisterMapConfig(SupremeIsthmus::config);
        mapManager.RegisterMapConfig(AllThatGlitters::config);
        mapManager.RegisterMapConfig(EightHorses::config);
        // ... 15 more maps ...
    }
}
```

### Per-Map Start Spots with Role Assignments

Each map defines start positions with pre-assigned AI roles:

```angelscript
// Barb3/stable/script/src/maps/supreme_isthmus.as
StartSpot@[] spots = {
    StartSpot(AIFloat3(  711, 0,  7218), AiRole::HOVER_SEA, false),  // P1
    StartSpot(AIFloat3(  837, 0, 10407), AiRole::TECH, false),       // P2
    StartSpot(AIFloat3( 2155, 0, 11747), AiRole::AIR, false),        // P3
    StartSpot(AIFloat3( 2513, 0,  7983), AiRole::FRONT, false),      // P4
    // ... more spots ...
};
```

### Per-Map Factory Weights

Maps can override which factories the AI prefers for each role:

```angelscript
dictionary getFactoryWeights() {
    dictionary root;
    // FRONT role: prefer vehicle plants on this map
    dictionary frontArm; frontArm.set("armlab",2); frontArm.set("armvp",5);
    dictionary frontCor; frontCor.set("corlab",2); frontCor.set("corvp",5);
    // ...
    root.set("FRONT", @frontRole);
    root.set("AIR", @airRole);
    root.set("SEA", @seaRole);
    // ...
    return root;
}
```

### Per-Map Unit Limits

Maps can restrict specific units (e.g., prohibit certain amphibious units on maps where they cause pathing issues):

```angelscript
dictionary getMapUnitLimits() {
    dictionary limits;
    limits.set("armpincer", 0);  // No pincer on this map
    limits.set("corgarp", 0);    // No garpike on this map
    return limits;
}
```

### Strategic Objectives

Maps can define **strategic build objectives** -- specific locations where the AI should build specific structures:

```angelscript
Objectives::StrategicObjective@ o1 = Objectives::StrategicObjective();
o1.id = "island_air_two_mexes";
o1.AddStep(Objectives::BuildingType::T1_LIGHT_AA, 3);
o1.pos = AIFloat3(340.f, 0.f, 12700.f);
o1.radius = SQUARE_SIZE * 8.0f;
o1.roles = { AiRole::AIR };
o1.classes = { Objectives::ConstructorClass::AIR };
o1.tiers = { 1, 2 };
o1.priority = 10;
o1.builderGroup = Objectives::BuilderGroup::TACTICAL;
config.AddObjective(o1);
```

**None of this exists in v2.** BARb v2 has zero map-specific behavior -- every map is treated identically.

---

## 8. Opener System (v3 Only)

Barb3 defines **probabilistic build queues** for the opening factory. The opener determines what units are produced first from each factory type:

```angelscript
// Barb3/stable/script/src/types/opener.as
SOpener@ opener = SOpener({
    {Factory::armlab, array<SQueue> = {
        SQueue(0.9f, {  // 90% chance: builder -> scout -> raider -> builder -> 4x raider
            SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER),
            SO(RT::BUILDER), SO(RT::RAIDER, 4)
        }),
        SQueue(0.1f, {  // 10% chance: raider -> builder -> riot -> builder -> 4x raider
            SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RIOT),
            SO(RT::BUILDER), SO(RT::RAIDER, 4), SO(RT::BUILDER)
        })
    }},
    {Factory::armalab, array<SQueue> = {
        SQueue(1.0f, {  // 100% chance: T2 builder -> 3x skirm -> T2 builder -> ...
            SO(RT::BUILDER2), SO(RT::SKIRM, 3), SO(RT::BUILDER2),
            SO(RT::SKIRM, 2), SO(RT::AA), SO(RT::BUILDER2)
        })
    }},
    // ... per-factory-type queues for all factions ...
}, {  // Default fallback queue
    SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER, 3),
    SO(RT::BUILDER), SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RAIDER)
});
```

The unit type codes used:

| Code | Meaning |
|------|---------|
| `RT::BUILDER` | T1 Constructor |
| `RT::BUILDER2` | T2 Constructor |
| `RT::SCOUT` | Scout unit |
| `RT::RAIDER` | Fast attack unit |
| `RT::RIOT` | Anti-swarm / riot unit |
| `RT::ASSAULT` | Heavy assault unit |
| `RT::SKIRM` | Skirmisher / ranged unit |
| `RT::ARTY` | Artillery unit |
| `RT::AA` | Anti-air unit |
| `RT::BOMBER` | Bomber aircraft |

Selection uses `AiDice(weights)` -- a weighted random function that picks from the available queues based on their probabilities.

**v2 has the opener system in its factory manager** but without the probabilistic weighting -- it uses a simpler static sequence loaded from the `factory.json` config. The v3 approach allows the same factory to produce different opening sequences across games, adding variety.

---

## 9. What Changed for Building Logic

### The Quest Context

Felenious's quest is about improving Barb3's **building placement** -- specifically, making the AI build in organized clusters rather than scattering structures across the map. This section explains the architectural gap.

### What v2 Does

v2 building placement is entirely C++ driven:
1. The C++ engine's `aiBuilderMgr.DefaultMakeTask()` decides what to build based on economy state and `economy.json` config
2. The C++ placement algorithm reads `block_map.json` to determine spacing constraints
3. On completion, `build_chain.json` hub entries trigger chained constructions at hard-coded offsets
4. The script layer (`builder.as`) merely tags two constructors as BASE and delegates everything else

### What v3 Adds on Top

v3 adds significant script-side management, but the **core placement algorithm remains in C++**:
1. The role system gates what gets built (TECH role prevents factory spam, FRONT role avoids nuke silos)
2. The constructor hierarchy ensures specific builders handle specific tasks (primary handles base expansion, tactical handles frontline)
3. Per-map strategic objectives tell specific constructors to build at specific coordinates
4. Build queue counters and cooldowns prevent over-investment in a single structure type
5. The block_map has more refined classes (T1 vs T2 factories, defense tiers)

### The Gap

The problem is that despite all of v3's scripting sophistication, the **actual placement decision** (where exactly to put a building) still comes from the C++ engine's `DefaultMakeTask()`. The config system (`block_map.json` + `build_chain.json`) defines:

- **Constraints:** "factories need X yards of clearance, don't overlap with energy buildings"
- **Chains:** "after building a solar, try to place another solar at offset [64, 0]"

But it does **not** define:

- **Block layouts:** "build a 3x3 grid of solars at this specific location"
- **Zone planning:** "designate this area for energy, that area for defenses, this corridor for factories"
- **Spatial intent:** "keep all T1 energy within 500 elmos of the factory"

The C++ placement algorithm uses the block_map constraints to avoid collisions but still **searches outward from the builder's position** for valid placement spots. This search pattern naturally creates scatter -- builders fan out from base and place structures wherever they find space.

### What Barb3 Needs

To achieve true block-based placement, the system would need one or more of:

1. **Script-side placement control:** Override `DefaultMakeTask()` placement with explicit coordinates derived from a layout plan
2. **Zone-aware block_map extensions:** New config fields that cluster buildings into designated zones (energy block, defense block, factory row)
3. **Layout templates:** Pre-designed building arrangements loaded from config and placed as a unit
4. **Hub chain redesign:** Convert hub offsets from relative to zone-relative, so chain builds fill a designated area rather than radiating from the trigger building

The strategic objectives system in v3 is a step toward this -- it already places specific structures at specific map coordinates. The gap is extending this concept from "build 3x AA at island" to "build your entire base according to a spatial plan."

---

## 10. Summary Table

| Feature | BARb v2 | Barb3 |
|---------|---------|-------|
| **Architecture** | Flat per-difficulty duplication (4x copies of all scripts) | Shared `src/` with thin profile wrappers |
| **Config layout** | Per-difficulty folders (`easy/`, `hard/`, etc.) with merged faction configs | Per-profile folders (`experimental_balanced/`, etc.) with per-faction configs |
| **Faction support** | Armada + Cortex merged; Legion bolted on via `_leg` suffix files | Armada, Cortex, Legion as first-class separate configs |
| **Role system** | None -- all AI instances behave identically | 6 roles (FRONT, AIR, TECH, SEA, FRONT_TECH, HOVER_SEA) with delegate-based behavior |
| **Map awareness** | None -- all maps treated identically | 17+ individual map configs with start spots, factory weights, unit limits |
| **Strategic objectives** | None | Per-map objectives with eco gates, role filters, builder group assignment |
| **Opener system** | Static factory sequence from config | Probabilistic weighted queues per factory type with `AiDice` selection |
| **Builder script complexity** | ~160 lines, 2 constructor slots, delegates all decisions to C++ | 1000+ lines, 20+ constructor slots, task tracking, guard management, cooldown system |
| **Building placement** | Entirely C++ driven via `DefaultMakeTask()` | Still C++ driven at the core, but with script-side gating, queuing, and strategic objective overrides |
| **block_map.json** | Generic classes (fac_veh, fac_bot, fusion, def_low) | Tier-aware classes (fac_land_t1, fac_land_t2, def_mid, def_hvy, advsolar) with larger yard values |
| **build_chain.json** | Single merged file for both factions | Per-faction files (ArmadaBuildChain, CortexBuildChain, LegionBuildChain) |
| **Strategy system** | None | Bitmask strategies (T2_RUSH, T3_RUSH, NUKE_RUSH) with weighted probability selection |
| **Global state** | None -- each manager is self-contained | `global.as` with namespaces for Map, Economy, AISettings, RoleSettings, Statistics |
| **Profile controller** | None | `ProfileController` class with role-based `MainUpdate()` dispatch |
| **Helper modules** | 0 | 17 specialized helper files (builder, defense, economy, factory, guard, limits, map, objective, role, task, terrain, unit) |
| **Constructor hierarchy** | 2 "energizer" slots (cheap + expensive) | Commander, primary, secondary, tactical, freelance per category (Bot, Veh, Air, Sea, Hover) x T1/T2 |
| **Task tracking** | None | `BuilderTaskTrack` with grace periods, timeouts, likely-started heuristics |
| **Build cooldowns** | None | Per-structure-type cooldowns (T2 factory: 120s, gantry: 120s, nano: 2s, etc.) |
| **Profiles shipped** | 4 (easy, medium, hard, hard_aggressive) | 6 (balanced, ThirtyBonus, FiftyBonus, EightyBonus, HundredBonus, Suicidal) |

---

*End of Report 04. This comparison forms the foundation for understanding what building placement improvements are possible within Barb3's architecture and where the C++ engine boundary limits script-side control.*
