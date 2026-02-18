# Barb3 Building Decision & Placement — File Reference

> Every code file involved in deciding WHAT to build, WHERE to place it, and HOW to manage the task lifecycle.
>
> Read these files to understand the full building pipeline.

---

## The Building Decision Pipeline

```
Engine tick
  │
  ├─ Economy::AiUpdateEconomy()          ← gates all decisions
  │    └─ Tech_EconomyUpdate()           ← dynamic caps, scaling
  │
  ├─ Builder::AiMakeTask(unit)           ← "what should this constructor build?"
  │    └─ Tech_BuilderAiMakeTask()       ← the big waterfall
  │         ├─ BlockPlanner::*           ← our wind grid system
  │         ├─ Tech_T1Constructor_*      ← T2 lab, air, solar, nano
  │         └─ Tech_T2Constructor_*      ← gantry, fusion, nuke, AFUS
  │
  ├─ Factory::AiMakeTask(unit)           ← "what should this factory produce?"
  │    └─ Tech_FactoryAiMakeTask()       ← constructor/combat production
  │
  ├─ Factory::AiGetFactoryToBuild(pos)   ← "what factory type to build?"
  │    └─ Tech_SelectFactoryHandler()    ← role-based factory selection
  │
  └─ Military::AiMakeDefence(cluster)    ← "should we build turrets here?"
       └─ Tech_AiMakeDefence()           ← defense gating
```

---

## AngelScript Source Files

### Decision Logic (WHAT to build)

| File | Path | Key Functions | What It Decides |
|------|------|--------------|----------------|
| **tech.as** | `script/src/roles/tech.as` | `Tech_BuilderAiMakeTask`, `Tech_T1Constructor_AiMakeTask`, `Tech_T2Constructor_AiMakeTask`, `Tech_FactoryAiMakeTask`, `Tech_EconomyUpdate`, `Tech_ApplyStartLimits`, `Recycle` | **THE main file.** All TECH builder waterfalls, factory production, economy scaling, unit caps, recycling. ~1500 lines. |
| **builder.as** | `script/src/manager/builder.as` | `AiMakeTask`, `AiTaskRemoved`, `MakeDefaultTaskWithLog`, `EnqueueT2LabIfNeeded`, `EnqueueT1Solar`, `EnqueueT1Nano`, `EnqueueFUS`, `EnqueueAFUS`, `EnqueueNukeSilo`, `EnqueueAntiNuke`, `EnqueueLandGantry`, `EnqueueT1AirFactory`, `EnqueueT1BotLab`, `EnqueueAdvEnergyConverter`, `EnqueueT1EnergyConverter` | Constructor hierarchy (primary/secondary/freelance), task lifecycle, all `Enqueue*` helper functions that create build tasks. ~2100 lines. |
| **factory.as** | `script/src/manager/factory.as` | `AiMakeTask`, `AiGetFactoryToBuild`, `AiUnitAdded`, `AiUnitRemoved`, `GetPreferredFactory`, `GetPreferredFactoryPos`, `GetT2BotLabPos`, `EnqueueGantrySignatureBatch` | Factory tracking (all `primary*` references), nano per-factory tracking, factory production delegation. ~800 lines. |
| **economy.as** | `script/src/manager/economy.as` | `AiUpdateEconomy`, `GetMinMetalIncomeLast10s`, `GetMinEnergyIncomeLast10s`, `_UpdateSlidingMinima` | Resource tracking, sliding-window 10s minimums, stalling detection, energy/metal state flags. Gates all building decisions. |
| **military.as** | `script/src/manager/military.as` | `AiMakeTask`, `AiMakeDefence`, `AiIsAirValid` | Defense trigger logic, military task delegation. Thin wrapper that delegates to role handlers. |
| **economy_helpers.as** | `script/src/helpers/economy_helpers.as` | `ShouldBuildT2BotLab*`, `ShouldBuildFusionReactor`, `ShouldBuildAdvancedFusionReactor`, `ShouldBuildGantry`, `ShouldBuildNuclearSilo`, `ShouldBuildAntiNuke`, `ShouldBuildT1Solar`, `ShouldBuildT1Nano`, `ShouldBuildT1AircraftPlant`, `ShouldBuildT1EnergyConverter`, `ShouldBuildT2EnergyConverter`, `AllowedGantryCountFromIncome`, `CalculateT1BuilderCap`, `CalculateT2BuilderCap` | **All economy gate functions.** Every "should I build X?" check lives here. Pure functions — take income values, return bool. |
| **block_planner.as** | `script/src/helpers/block_planner.as` | `ShouldInterceptForWind`, `EnqueueNextWindFromBlock`, `ChooseBlockOrigin`, `OnTaskRemoved`, `TryCreateNewBlock` | **Our addition.** Wind grid placement with 4x4 blocks, slot state machine, task lifecycle tracking. |

### Placement Logic (WHERE to build)

| File | Path | Key Content | What It Controls |
|------|------|------------|-----------------|
| **block_map.json** | `config/experimental_balanced/block_map.json` | `building.class_land` section | **Placement exclusion zones.** Defines blocker shapes, spacing, yard sizes for every building class (factory, solar, wind, geo, mex, nano, defense). Controls minimum distances between buildings. |
| **build_chain.json** | `config/experimental_balanced/ArmadaBuildChain.json` (+ Cortex, Legion) | `build_chain.*` sections | **Post-build auto-construction.** When building X completes, automatically queue building Y at offset position. Defense rings around factories, converters near energy, etc. |
| **block_planner.as** | `script/src/helpers/block_planner.as` | `ChooseBlockOrigin`, `GetSlotPos` | **Grid-based wind placement.** Calculates exact positions in 4x4 grid offset from StartPos. |

### Types & Structures

| File | Path | Key Content | What It Defines |
|------|------|------------|----------------|
| **task.as** | `script/src/task.as` | `SBuildTask`, `TaskB::Common`, `TaskB::Factory`, `TaskB::Spot`, `Task::BuildType` enum | Build task structure — type, priority, position, shake, timeout. Factory functions to create tasks. |
| **opener.as** | `script/src/types/opener.as` | `Opener::GetOpener`, `Opener::SO`, `Opener::GetOpenInfo` | Factory opener build queues — probabilistic initial production sequences per factory type. |
| **strategy.as** | `script/src/types/strategy.as` | `Strategy` enum, `StrategyUtil` | Strategy bitmask (T2_RUSH, T3_RUSH, NUKE_RUSH) that modifies building thresholds. |
| **role_config.as** | `script/src/types/role_config.as` | `RoleConfig` class, all delegate types | Delegate-based role hook registration — connects tech.as functions to engine callbacks. |
| **profile_controller.as** | `script/src/types/profile_controller.as` | `ProfileController` | Routes engine callbacks to the active role's handlers. |
| **map_config.as** | `script/src/types/map_config.as` | `MapConfig`, `StartSpot` | Map configuration types — start positions, roles, unit limits, factory weights. |

### Helper Functions

| File | Path | Key Content |
|------|------|------------|
| **unit_helpers.as** | `script/src/helpers/unit_helpers.as` | `GetAllT1BotLabs`, `GetAllT2BotLabs`, `GetAllFusionReactors`, `IsT1BotLab`, `IsT2BotLab`, `IsGantryLab`, `GetT1WindNameForSide`, `BatchApplyUnitCaps`, `GetConstructorTier` — unit lookup and classification |
| **unit_def_helpers.as** | `script/src/helpers/unit_def_helpers.as` | `SumUnitDefCounts`, `SetIgnoreFor`, `SetMainRoleFor` — unit definition manipulation |
| **factory_helpers.as** | `script/src/helpers/factory_helpers.as` | `SelectStartFactoryForRole`, `GetFallbackStartFactoryForRole` — factory type selection |
| **guard_helpers.as** | `script/src/helpers/guard_helpers.as` | `AssignWorkerGuard` — assign constructors to assist others |
| **generic_helpers.as** | `script/src/helpers/generic_helpers.as` | `LogUtil` — logging at configurable levels |
| **limits_helpers.as** | `script/src/helpers/limits_helpers.as` | Unit limit merging (map + role limits) |

### Configuration & Initialization

| File | Path | Key Content |
|------|------|------------|
| **global.as** | `script/src/global.as` | `RoleSettings::Tech::*` — ALL thresholds (T2 lab gates, fusion gates, gantry gates, nuke gates, caps, military quotas). **The single source of truth for tunable numbers.** |
| **main.as** | `script/experimental_balanced/main.as` | Strategy dice rolls, profile application, factory tier tagging |
| **init.as** | `script/experimental_balanced/init.as` | JSON config loading (11 files), armor/category init |
| **setup.as** | `script/src/setup.as` | Map resolution, role matching, deferred setup |
| **maps.as** | `script/src/maps.as` | Map registration (18 maps) |

### JSON Config Files (per-faction)

| File | What It Controls |
|------|-----------------|
| `ArmadaBuildChain.json` / `CortexBuildChain.json` / `LegionBuildChain.json` | Post-build auto-construction chains (defense rings, converters, etc.) |
| `ArmadaEconomy.json` / `CortexEconomy.json` / `LegionEconomy.json` | Energy producer selection, mex selection, build limits, income factors |
| `ArmadaFactory.json` / `CortexFactory.json` / `LegionFactory.json` | Factory unit production tiers, probability weights, income gates |
| `ArmadaBehaviour.json` / `CortexBehaviour.json` / `LegionBehaviour.json` | Unit behavior, defense radius, retreat thresholds, role overrides |
| `block_map.json` | Building spacing/exclusion zones (shared across factions) |
| `commander.json` / `commander_leg.json` | Commander behavior |
| `response.json` | Threat response rules |

---

## Reading Order (recommended)

If you want to understand the full building pipeline, read in this order:

1. **`global.as`** (lines 82-292) — All the threshold numbers
2. **`tech.as`** (full file) — The decision waterfalls
3. **`economy_helpers.as`** — The gate functions tech.as calls
4. **`builder.as`** — The Enqueue* functions and constructor hierarchy
5. **`factory.as`** — Factory tracking and production
6. **`block_map.json`** — How C++ decides WHERE to place
7. **`ArmadaBuildChain.json`** — What auto-builds after each structure
8. **`ArmadaFactory.json`** — Factory production probability tables
9. **`block_planner.as`** — Our wind grid system

---

*Created: 2026-02-17*
