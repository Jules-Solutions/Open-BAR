# Key File Index -- BARB Quest

> Quick-reference index of every critical source file for the Build Module Quest.
> All paths relative to `C:\Jules.Life\Projects\TheLab\Experiments\BAR\`.

---

## 1. STAI (BAR's Built-in Lua AI)

Base path: `Prod/Beyond-All-Reason/luarules/gadgets/ai/STAI/`

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `buildingshst.lua` | Building position system: rectangle tracking, spiral search, factory exit lanes | Best reference for understanding placement algorithms; direct analog to what block_map.json replaces |
| `buildersbst.lua` | Builder behavior: processes task queue per constructor, role-based actions | Shows how builders pick and execute build tasks -- the consumption side of placement |
| `engineerhst.lua` | Engineer management: guard assignments, assist coordination | Nano/engineer assignment patterns; relevant to caretaker placement near factories |
| `ecohst.lua` | Economy handler: rolling 30-sample resource averages, income/usage/reserves | Reference for eco thresholds that gate building decisions |
| `labshst.lua` | Factory management and production queuing | Factory-centric build logic; how STAI decides what to produce |
| `taskshst.lua` | Task queue definitions per role (eco, expand, nano, support, etc.) | Defines the task taxonomy that drives builder behavior |
| `attackhst.lua` | Attack coordination | Context for military structure placement priorities |
| `scouthst.lua` | Scout management | Peripheral -- scout-related economy timing |

---

## 2. Barb3 (Modern Refactored AI -- AngelScript)

Base path: `Prod/Skirmish/Barb3/stable/`

### 2a. Core Scripts (`script/src/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `setup.as` | Entry point: deferred init, role determination from start spots, factory selection hook | Initialization flow; where block placement system must be loaded |
| `common.as` | Shared includes, utility functions | Import chain; any new helpers must be included here |
| `define.as` | Constants and definitions | Global constants that placement logic may reference |
| `global.as` | Global state management | Shared state that managers read/write |
| `task.as` | Task system base | Task lifecycle; building tasks originate here |
| `unit.as` | Unit handling base | Unit tracking fundamentals |
| `maps.as` | Map config registry; includes all per-map configs | Determines which map_config is active, affecting placement |

### 2b. Managers (`script/src/manager/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `builder.as` | Builder/constructor management: task assignment, building queues | **PRIMARY INTEGRATION POINT** -- block placement must hook into this manager |
| `economy.as` | Resource tracking: income, pull, sliding window thresholds, stall detection | Gates when buildings are affordable; placement depends on eco state |
| `factory.as` | Factory production: opener sequences, nano caretaker limits, T2 expansion | Factory placement and expansion logic; interacts with block system |
| `military.as` | Combat unit grouping, attack thresholds | Military pressure signals that influence defense placement |
| `objective_manager.as` | Strategic objective tracking and assignment | High-level goals that drive what gets built where |

### 2c. Roles (`script/src/roles/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `front.as` | Frontline combat role | Role-specific build priorities and unit mix |
| `air.as` | Air-focused role | Air factory placement and priority |
| `tech.as` | Economy/tech role | Heavy eco build patterns; most building-intensive role |
| `sea.as` | Naval role | Sea factory and naval structure placement |
| `front_tech.as` | Hybrid front/economy role | Mixed placement needs |
| `hover_sea.as` | Hovercraft variant | Amphibious placement considerations |

### 2d. Types (`script/src/types/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `building_type.as` | BuildingType taxonomy: 30+ types (T1_MEX, T1_ENERGY, T1_LIGHT_TURRET, etc.) | **CRITICAL** -- defines the building categories that block_map.json references |
| `ai_role.as` | AiRole enum: FRONT, AIR, TECH, SEA, FRONT_TECH, HOVER_SEA | Roles determine which buildings are prioritized |
| `opener.as` | Build order sequences with probabilistic weighting per factory | Early-game placement ordering; first buildings placed by block system |
| `profile.as` | Difficulty profile configuration | Tuning knobs that affect building aggressiveness |
| `profile_controller.as` | Profile state management | Runtime profile state |
| `role_config.as` | Per-role unit caps and behavior parameters | Caps that limit how many of each building type |
| `map_config.as` | Map configuration container | Per-map overrides for placement behavior |
| `start_spot.as` | StartSpot class: position, role, land-locked flag | Starting position data; anchor point for initial block placement |
| `strategic_objectives.as` | Objective definitions with priorities | Strategic goals that drive expansion placement |
| `strategy.as` | Strategy configuration | High-level strategy affecting build composition |
| `terrain.as` | Terrain type handling | Terrain classification affecting where buildings can go |

### 2e. Maps (`script/src/maps/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `factory_mapping.as` | Maps (AiRole, Side, LandLocked) to factory unit; deterministic selection | Factory selection drives which block layouts apply |
| `default_map_config.as` | Default fallback map config | Baseline placement parameters when no map-specific config exists |
| `supreme_isthmus.as` | Map-specific config | Per-map overrides (choke points, expansion zones) |
| `all_that_glitters.as` | Map-specific config | Per-map overrides |
| `swirly_rock.as` | Map-specific config | Per-map overrides |
| *(16 more map configs)* | `acidic_quarry`, `ancient_bastion_remake`, `eight_horses`, `flats_and_forests`, `forge`, `glacial_gap`, `koom_valley`, `mediterraneum`, `raptor_crater`, `red_river_estuary`, `serene_caldera`, `shore_to_shore`, `sinkhole_network`, `tempest`, `tundra_continents` | Each may override placement parameters |

### 2f. Helpers (`script/src/helpers/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `builder_helpers.as` | Building placement utilities | **KEY** -- existing placement helper functions; block system must extend or replace these |
| `defense_helpers.as` | Defense structure placement | Turret/defense placement logic to integrate with blocks |
| `economy_helpers.as` | Economy decision support | Eco checks that gate building decisions |
| `factory_helpers.as` | Factory management utilities | Factory-adjacent placement helpers |
| `map_helpers.as` | Map analysis utilities | Terrain queries used during placement |
| `terrain_helpers.as` | Terrain classification | Buildability checks per terrain type |
| `objective_executor.as` | Objective execution logic | Translates objectives into build actions |
| `objective_helpers.as` | Objective support utilities | Objective-related queries |
| `role_helpers.as` | Role management | Role queries affecting build priorities |
| `role_limit_helpers.as` | Role limit management | Cap enforcement |
| `task_helpers.as` | Task system utilities | Task creation/management for build orders |
| `unit_helpers.as` | Unit data utilities | Unit queries during placement |
| `unitdef_helpers.as` | UnitDef data utilities | Static unit definition lookups (footprints, costs) |
| `collection_helpers.as` | Collection utilities | Generic data structure helpers |
| `generic_helpers.as` | Generic utilities | Shared utility functions |
| `guard_helpers.as` | Guard behavior helpers | Engineer guarding logic |
| `limits_helpers.as` | Limit enforcement helpers | Building count limits |

### 2g. Configuration (`config/experimental_balanced/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `block_map.json` | Spatial blocking system for building placement: blocker shapes, structure types, yard/offset, ignore rules | **THE KEY FILE** -- defines the block placement system our build module must implement |
| `ArmadaBuildChain.json` | Build chain config: what gets built adjacent to what (hub system, offsets, conditions) | **CRITICAL** -- our blocks must integrate with this adjacency/chain system |
| `ArmadaBehaviour.json` | AI behavior tuning per unit type | Behavior params that affect building usage |
| `ArmadaEconomy.json` | Economy thresholds and priorities | Eco gates for building decisions |
| `ArmadaFactory.json` | Factory production weights and limits | Factory output affecting what needs placement |
| `CortexBuildChain.json` | Cortex build chain config | Same as Armada, for Cortex faction |
| `CortexBehaviour.json` | Cortex behavior tuning | Same as Armada, for Cortex |
| `CortexEconomy.json` | Cortex economy config | Same as Armada, for Cortex |
| `CortexFactory.json` | Cortex factory config | Same as Armada, for Cortex |
| `LegionBuildChain.json` | Legion build chain config | Same as Armada, for Legion faction |
| `LegionBehaviour.json` | Legion behavior tuning | Same as Armada, for Legion |
| `LegionEconomy.json` | Legion economy config | Same as Armada, for Legion |
| `LegionFactory.json` | Legion factory config | Same as Armada, for Legion |
| `commander.json` | Commander configuration (Armada/Cortex) | Commander starting build capabilities |
| `commander_leg.json` | Commander configuration (Legion) | Legion commander variant |
| `block_map.json` | *(listed above)* | |
| `extraunits.json` | Extra unit definitions | Additional unit data |
| `extrascavunits.json` | Scavenger extra units | Scavenger mode unit data |
| `response.json` | Response configuration | Reactive behavior tuning |

### 2h. API Reference

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `angelscript-references.md` | Complete CircuitAI API reference: SBuildTask, CBuilderManager, CEconomyManager, etc. | **ESSENTIAL** -- the API surface we code against; defines what placement functions exist |

---

## 3. BARb v2 (Legacy AI)

Base path: `Prod/Skirmish/BARb/stable/`

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `script/common.as` | Shared includes (legacy) | Reference for older placement patterns |
| `script/define.as` | Constants (legacy) | Legacy constants |
| `script/task.as` | Task system (legacy) | Older task model |
| `script/unit.as` | Unit handling (legacy) | Older unit tracking |
| `script/{difficulty}/manager/builder.as` | Builder manager per difficulty (easy/medium/hard/hard_aggressive) | Legacy builder placement; shows how difficulty scaling was done |
| `script/{difficulty}/manager/economy.as` | Economy manager per difficulty | Legacy eco gating |
| `script/{difficulty}/manager/factory.as` | Factory manager per difficulty | Legacy factory logic |
| `script/{difficulty}/manager/military.as` | Military manager per difficulty | Legacy military logic |

---

## 4. Blueprint System (BAR Game Engine)

Base path: `Prod/Beyond-All-Reason/luarules/gadgets/ruins/Blueprints/BYAR/`

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `blueprint_controller.lua` | Blueprint loading, tier system, type system | Shows how BAR itself handles pre-designed building layouts |
| `blueprint_tiers.lua` | Tier definitions | Tier progression relevant to block tier mapping |
| `Blueprints/*.lua` (21 files) | Blueprint definitions: `Damgam_*`, `KrashKourse_*`, `Nikuksis_*`, `IronFist_*`, `hermano_*`, `link_sea` | Concrete layout examples; patterns we can learn from for block design |

---

## 5. TotallyLegal (Our Widget Suite)

Base path: `lua/LuaUI/Widgets/`

### 5a. Active Widgets

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `01_totallylegal_core.lua` | Core library: perception, shared state, FindBuildPosition | **Foundation** -- shared state contract; any build module must integrate here |
| `auto_puppeteer_core.lua` | Puppeteer micro core | Micro system architecture reference |
| `auto_puppeteer_dodge.lua` | Dodge micro module | Combat micro |
| `auto_puppeteer_firingline.lua` | Firing line micro module | Combat positioning |
| `auto_puppeteer_formations.lua` | Formation micro module | Group movement |
| `auto_puppeteer_march.lua` | March/patrol micro module | Movement automation |
| `auto_puppeteer_raid.lua` | Raid micro module | Automated raiding |
| `auto_puppeteer_smartmove.lua` | Smart movement micro module | Pathfinding micro |
| `gui_totallylegal_overlay.lua` | Debug overlay visualization | Visual debugging for placement |
| `gui_totallylegal_timeline.lua` | Timeline visualization | Game phase tracking |
| `gui_totallylegal_sidebar.lua` | Sidebar UI | Status display |
| `gui_puppeteer_panel.lua` | Puppeteer control panel | Micro suite UI |

### 5b. Shelved Widgets (`_shelf/`)

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `_shelf/engine_totallylegal_build.lua` | **Shelved build executor** -- has module system prototype | **DIRECT ANCESTOR** -- contains early build module patterns; study before reimplementing |
| `_shelf/engine_totallylegal_econ.lua` | Shelved economy engine | Eco tracking prototype |
| `_shelf/engine_totallylegal_prod.lua` | Shelved production engine | Production management prototype |
| `_shelf/engine_totallylegal_zone.lua` | Shelved zone engine | Zone management prototype |
| `_shelf/engine_totallylegal_mapzones.lua` | Shelved map zones engine | Map zone analysis prototype |
| `_shelf/engine_totallylegal_goals.lua` | Shelved goals engine | Goal system prototype |
| `_shelf/engine_totallylegal_strategy.lua` | Shelved strategy engine | Strategy system prototype |
| `_shelf/02_totallylegal_config.lua` | Shelved config module | Configuration prototype |
| `_shelf/gui_totallylegal_threat.lua` | Shelved threat visualization | Threat map prototype |
| `_shelf/gui_totallylegal_priority.lua` | Shelved priority visualization | Priority display prototype |
| `_shelf/gui_totallylegal_goals.lua` | Shelved goals visualization | Goals display prototype |
| `_shelf/auto_totallylegal_rezbot.lua` | Shelved rezbot automation | Reclaim bot prototype |
| `_shelf/auto_totallylegal_dodge.lua` | Shelved dodge automation (pre-puppeteer) | Early dodge prototype |
| `_shelf/auto_totallylegal_skirmish.lua` | Shelved skirmish automation | Early skirmish prototype |

---

## 6. Documentation and Analysis

Base path: `docs/`

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `CHECKPOINT_2026-02-08.md` | STAI analysis, economy/strategy widget gaps, recommendations | Current state assessment; identifies what the build module must solve |
| `ARCHITECTURE.md` | Five-system architecture, shared state contract | System design; where build module fits in the architecture |
| `STATUS.md` | Widget inventory, known issues | Current widget status and gaps |
| `BAR_COMPLETE_STRATEGY.md` | Complete BAR strategy guide | Strategic context for placement decisions |
| `BAR_STRATEGY.md` | BAR strategy reference | Strategy reference |
| `BAR_BUILD_ORDERS.md` | Build order documentation | Build order patterns that placement must support |
| `PLAN.md` | Development plan | Roadmap context |
| `BUGS.md` | Known bugs | Issues to avoid or fix |
| `FEATURE_SIDEBAR.md` | Sidebar feature spec | UI integration points |
| `Research_Widget_Ecosystem.md` | Widget ecosystem research | BAR widget API landscape |
| `Brainstorm_1.md` | Initial brainstorm | Early ideas |
| `Brainstorm_1_Structured.md` | Structured brainstorm | Organized early ideas |

---

## 7. Discord Logs

Base path: `Discord_Chats/`

| Path | Description | Relevance to Quest |
|------|-------------|--------------------|
| `AI Discord Chat History.md` | 58 messages about AI development (Dec 2025) | Community insights on AI building behavior and known issues |
| `Discord Barb 2.0 Testing Forum chat history.md` | 27 messages about Barb 2.0 testing (Feb 2026) | Recent Barb testing feedback; placement-related bug reports |

---

## Priority Reading Order for the Build Module Quest

1. **`block_map.json`** -- Understand the spatial blocking system we must implement
2. **`ArmadaBuildChain.json`** -- Understand the adjacency/chain system blocks integrate with
3. **`angelscript-references.md`** -- Know the API surface (SBuildTask, CBuilderManager)
4. **`builder.as` (manager)** -- The primary integration point for placement
5. **`builder_helpers.as`** -- Existing placement utilities to extend
6. **`building_type.as`** -- The building taxonomy blocks reference
7. **`buildingshst.lua` (STAI)** -- Best reference for placement algorithm patterns
8. **`_shelf/engine_totallylegal_build.lua`** -- Our own earlier attempt; learn from it
9. **`01_totallylegal_core.lua`** -- Shared state contract any build widget must use
10. **`ARCHITECTURE.md`** -- Where the build module fits in the five-system design
