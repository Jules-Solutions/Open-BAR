# TotallyLegal System Architecture

## Overview

TotallyLegal is not a collection of features. It is a set of **five systems** that compose differently at each **automation level**. The simulation engine is central to every level - it just wires differently.

```
                     ┌──────────────────────┐
                     │   PRESENTATION       │
                     │   (overlays, panels)  │
                     └──────────┬───────────┘
                                │ displays
                                │
 ┌──────────────┐    ┌──────────┴───────────┐    ┌──────────────┐
 │  PERCEPTION  │───>│      DECISION        │───>│  EXECUTION   │
 │  (game state,│    │  (strategy choice)   │    │  (build, prod│
 │   scouting)  │    └──────────┬───────────┘    │   move, fight│
 └──────────────┘               │                └──────────────┘
                                │ queries
                                │
                     ┌──────────┴───────────┐
                     │    SIMULATION         │
                     │  (predictions, opti-  │
                     │   mization, threat)   │
                     └──────────────────────┘
```

---

## The Five Systems

### Perception
**Reads game state.** Units, resources, map terrain, enemy intel from scouting.

| Component | Type | File |
|-----------|------|------|
| Core Library | Lua widget | `lib_totallylegal_core.lua` |
| Map Zones | Lua widget | `engine_totallylegal_mapzones.lua` |
| Map Data | Python | `sim/bar_sim/map_data.py`, `map_parser.py` |

The core library is the **single source of truth** for unit classification, key resolution (short name -> defID), mex spots, team resources, and build position finding. No other widget duplicates these.

### Simulation
**Models the game forward.** Build order validation, economic predictions, enemy estimation, strategy optimization. Runs in Python.

| Component | File |
|-----------|------|
| Engine | `sim/bar_sim/engine.py` |
| Economy model | `sim/bar_sim/econ.py` |
| Production model | `sim/bar_sim/production.py` |
| Strategy model | `sim/bar_sim/strategy.py` |
| Goals model | `sim/bar_sim/goals.py` |
| Optimizer | `sim/bar_sim/optimizer.py` |
| Live bridge | `sim/bar_sim/live.py` (future) |

### Decision
**Chooses what to do.** The decision source changes based on automation level: human via config panel (Level 1), sim recommendations approved by human (Level 2), or AI agent (Level 3).

| Component | Type | File |
|-----------|------|------|
| Config Panel | Lua widget | `engine_totallylegal_config.lua` |
| Sim Bridge | Lua widget | `engine_totallylegal_simbridge.lua` (future) |
| ML Agent | Python | `sim/bar_sim/ml/` (future) |

### Execution
**Carries out decisions.** Build orders, economy balancing, factory production, zone management, combat micro. These widgets issue `GiveOrderToUnit` calls - the actual game actions.

| Component | Scope | File |
|-----------|-------|------|
| Build Orders | Macro | `engine_totallylegal_build.lua` |
| Economy | Macro | `engine_totallylegal_econ.lua` |
| Production | Macro | `engine_totallylegal_prod.lua` |
| Zones | Macro | `engine_totallylegal_zone.lua` |
| Goals | Macro | `engine_totallylegal_goals.lua` |
| Strategy | Macro | `engine_totallylegal_strategy.lua` |
| Auto Dodge | Micro | `auto_totallylegal_dodge.lua` |
| Auto Skirmish | Micro | `auto_totallylegal_skirmish.lua` |
| Auto Rezbot | Micro | `auto_totallylegal_rezbot.lua` |

### Presentation
**Shows information to the human.** Overlays, panels, recommendations. Never issues orders.

| Component | File |
|-----------|------|
| Resource Overlay | `gui_totallylegal_overlay.lua` |
| Goal Panel | `gui_totallylegal_goals.lua` |
| Economy Timeline | `gui_totallylegal_timeline.lua` |
| Threat Display | `gui_totallylegal_threat.lua` |
| Priority Highlight | `gui_totallylegal_priority.lua` |

---

## The Four Automation Levels

A single integer (`automationLevel`) gates all system behavior. Each system checks the current level and adjusts what it does.

```
Level 0: OVERLAY          Level 1: EXECUTE          Level 2: ADVISE           Level 3: AUTONOMOUS
─────────────────         ──────────────────        ──────────────────        ──────────────────
Perception: ON            Perception: ON            Perception: ON            Perception: ON
Simulation: OFF           Simulation: VALIDATE      Simulation: PREDICT       Simulation: OPTIMIZE
Decision:   OFF           Decision:   HUMAN         Decision:   SIM→HUMAN    Decision:   AI
Execution:  OFF           Execution:  ON            Execution:  ON            Execution:  ON
Presentation: INFO        Presentation: +STATUS     Presentation: +RECS       Presentation: +WHY
```

| Level | Name | Player Does | System Does |
|-------|------|-------------|-------------|
| 0 | Overlay | Play normally | Display info (PvP safe, zero GiveOrder calls) |
| 1 | Execute | Set the strategy | Execute it faithfully |
| 2 | Advise | Approve/override recommendations | Predict, recommend, then execute approved strategy |
| 3 | Autonomous | Watch and learn | Decide optimal strategy and execute it |

### How each system uses the level

- **Perception** always runs (all levels need game state)
- **Simulation** is off at Level 0, validates build orders at Level 1, runs active predictions at Level 2+, drives optimization at Level 3
- **Decision** source: none (L0), human config panel (L1), sim recommends + human approves (L2), AI decides (L3)
- **Execution** widgets check `automationLevel >= 1` before issuing any `GiveOrderToUnit` call. At Level 0 they do nothing.
- **Presentation** always shows info. Adds engine status at L1, recommendations at L2, AI reasoning at L3.

---

## Shared State Contract

All inter-system communication goes through `WG.TotallyLegal`. Each system owns specific sections and only writes to its own.

```lua
WG.TotallyLegal = {
    -- META (owned by core)
    automationLevel = 0,           -- 0-3, gates all behavior
    IsAutomationAllowed = fn,      -- game rules check (PvP vs PvE)
    IsPvE = fn,

    -- PERCEPTION (owned by core + mapzones)
    GetFaction = fn,               -- "armada" | "cortex" | "unknown"
    GetMyUnits = fn,               -- unitID -> defID
    GetUnitClass = fn,             -- defID -> classification table
    GetTeamResources = fn,         -- metal/energy income/spend/storage
    ResolveKey = fn,               -- "mex" -> defID
    GetKeyTable = fn,              -- full key -> defID map
    GetMexSpots = fn,              -- array of {x, z}
    FindBuildPosition = fn,        -- find valid build location
    FindNearestMexSpot = fn,       -- nearest unoccupied mex spot
    MapZones = {},                 -- base/rally/front zone data

    -- DECISION (owned by config or simbridge)
    Strategy = {},                 -- the current strategy config table

    -- EXECUTION STATE (each engine owns its section)
    BuildPhase = "waiting",        -- build order executor state
    Economy = {},                  -- economy analysis state
    Production = {},               -- production manager state
    Zones = {},                    -- zone manager state
    Goals = {},                    -- goal queue state

    -- SIMULATION (owned by simbridge, future)
    Predictions = {},              -- forward predictions
    Recommendations = {},          -- suggested strategy changes

    -- HELPERS (owned by core)
    Dist2D = fn, Dist3D = fn,
    NearestUnit = fn,
    PointInCircle = fn,
    DistToLineSegment = fn,
    FormatRate = fn, FormatInt = fn, FormatBP = fn,
    SetColor = fn, DrawFilledRect = fn, DrawHLine = fn,
}
```

### Rules

1. Each system **only writes** to its own section
2. Each system reads from other sections with **nil-safe access**
3. Core library owns Perception (single source of truth for unit data, keys, resources)
4. **Load order doesn't matter** if every read is nil-safe
5. Disabling any widget must not crash any other widget

---

## Widget Load Order

Widgets are loaded by Spring in `layer` order (lower = earlier):

| Layer | Widget | System |
|-------|--------|--------|
| -1 | lib_core | Perception |
| 100 | gui_overlay | Presentation |
| 101 | gui_goals, gui_timeline, gui_threat, gui_priority | Presentation |
| 102 | auto_dodge | Execution (micro) |
| 103 | auto_skirmish | Execution (micro) |
| 104 | auto_rezbot | Execution (micro) |
| 200 | engine_config | Decision |
| 201 | engine_mapzones | Perception |
| 202 | engine_econ | Execution (macro) |
| 203 | engine_prod | Execution (macro) |
| 204 | engine_build | Execution (macro) |
| 205 | engine_zone | Execution (macro) |
| 206 | engine_goals | Execution (macro) |
| 207 | engine_strategy | Execution (macro) |

Core loads first (layer -1). Everything else nil-checks `WG.TotallyLegal` on init.

---

## Fair Play

- **Level 0** makes zero `GiveOrderToUnit` calls. Read-only info display. Safe for ranked PvP.
- **Level 1+** uses `GiveOrderToUnit`. Automatically disabled when BAR's `noautomation` game rule is active.
- The `automationLevel` field provides a clear, auditable boundary between observation and action.
