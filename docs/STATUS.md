# TotallyLegal: Project Status & Context

Last updated: 2026-02-07

## Repository Structure

```
BAR/
├── lua/LuaUI/Widgets/          # 18 Lua widgets
│   ├── lib_totallylegal_core.lua           # PERCEPTION: shared state, single source of truth
│   ├── gui_totallylegal_overlay.lua        # PRESENTATION: resource/unit info
│   ├── gui_totallylegal_goals.lua          # PRESENTATION: goal queue display
│   ├── gui_totallylegal_timeline.lua       # PRESENTATION: econ timeline graph
│   ├── gui_totallylegal_threat.lua         # PRESENTATION: threat estimation
│   ├── gui_totallylegal_priority.lua       # PRESENTATION: priority highlighting
│   ├── gui_totallylegal_sidebar.lua        # PRESENTATION: KSP-style widget toggle bar
│   ├── auto_totallylegal_dodge.lua         # EXECUTION/MICRO: projectile dodging
│   ├── auto_totallylegal_skirmish.lua      # EXECUTION/MICRO: optimal range kiting
│   ├── auto_totallylegal_rezbot.lua        # EXECUTION/MICRO: resurrect/reclaim
│   ├── engine_totallylegal_config.lua      # DECISION: strategy config panel + level toggle
│   ├── engine_totallylegal_build.lua       # EXECUTION/MACRO: opening build orders
│   ├── engine_totallylegal_econ.lua        # EXECUTION/MACRO: economy balancing
│   ├── engine_totallylegal_prod.lua        # EXECUTION/MACRO: factory production
│   ├── engine_totallylegal_zone.lua        # EXECUTION/MACRO: frontline management
│   ├── engine_totallylegal_goals.lua       # EXECUTION/MACRO: goal queue orchestration
│   ├── engine_totallylegal_strategy.lua    # EXECUTION/MACRO: attack patterns
│   └── engine_totallylegal_mapzones.lua    # PERCEPTION: map drawing (lines, areas)
├── lua/LuaUI/install.bat                   # Windows symlink installer
├── sim/                                     # Python simulation engine
│   ├── bar_sim/                            # Core package
│   │   ├── engine.py, models.py, econ.py, production.py
│   │   ├── strategy.py, goals.py, optimizer.py
│   │   ├── map_data.py, map_parser.py
│   │   ├── io.py, format.py, compare.py, db.py
│   │   ├── states.py, units.py, headless.py
│   │   ├── repl.py, web.py
│   │   ├── econ_ctrl.py
│   │   ├── lua/ (map_scanner.lua, sim_executor.lua)
│   │   ├── static/ (web dashboard)
│   │   └── maps/.gitkeep
│   ├── data/
│   │   ├── bar_units.db, unitlist.csv
│   │   ├── build_orders/ (aggressive.yaml, solar_opening.yaml, wind_opening.yaml)
│   │   └── headless/ (input/.gitkeep, output/.gitkeep)
│   ├── cli.py
│   └── pyproject.toml
├── docs/
│   ├── ARCHITECTURE.md          # System design (five systems, four levels, state contract)
│   ├── PLAN.md                  # This roadmap
│   ├── STATUS.md                # This file
│   ├── BUGS.md                  # Bug catalog
│   ├── BAR_STRATEGY.md          # Strategy framework
│   ├── BAR_COMPLETE_STRATEGY.md # Comprehensive strategy guide
│   ├── BAR_BUILD_ORDERS.md      # Build order reference
│   ├── Brainstorm_1.md          # Original brainstorm
│   ├── Brainstorm_1_Structured.md
│   └── Research_Widget_Ecosystem.md
├── archive/                     # Legacy files
├── README.md
├── LICENSE (GPL v2)
├── CONTRIBUTING.md
└── .gitignore
```

## Automation Level System

The core architectural concept. A single integer gates all system behavior:

| Level | Name | Player Does | System Does |
|-------|------|-------------|-------------|
| 0 | Overlay | Play normally | Display info only (PvP safe) |
| 1 | Execute | Set strategy via config panel | Execute it (all engines active) |
| 2 | Advise | Approve/override recommendations | Sim predicts + recommends |
| 3 | Autonomous | Watch | AI decides + executes |

**Implementation:** `WG.TotallyLegal.automationLevel` (default 0). Toggled via config panel row 0. All 9 execution widgets check `(WG.TotallyLegal.automationLevel or 0) < 1` at top of GameFrame. GUI widgets and mapzones always run.

## Widget Layer Order

| Layer | Widget | System | Gated |
|-------|--------|--------|-------|
| -1 | lib_core | Perception | No (always) |
| 100 | auto_skirmish | Execution/Micro | Yes (level >= 1) |
| 101 | auto_rezbot | Execution/Micro | Yes |
| 102 | auto_dodge | Execution/Micro | Yes |
| 50-53 | gui_overlay, gui_goals, gui_timeline, gui_threat, gui_priority | Presentation | No (always) |
| 99 | gui_sidebar | Presentation | No (always - widget toggle bar) |
| 200 | engine_config | Decision | No (always - it's where you set the level) |
| 201 | engine_build | Execution/Macro | Yes |
| 202 | engine_econ | Execution/Macro | Yes |
| 203 | engine_prod | Execution/Macro | Yes |
| 204 | engine_zone | Execution/Macro | Yes |
| 205 | engine_goals | Execution/Macro | Yes |
| 206 | engine_mapzones | Perception | No (no orders, just drawing) |
| 207 | engine_strategy | Execution/Macro | Yes |

## Shared State Contract

All inter-system communication via `WG.TotallyLegal`:

```lua
WG.TotallyLegal = {
    -- META (core)
    automationLevel, GetAutomationLevel(), SetAutomationLevel(n)
    IsAutomationAllowed(), IsPvE()
    WidgetVisibility = { Overlay, Goals, Timeline, Threat, Priority, Config, MapZones, ... }

    -- PERCEPTION (core)
    GetFaction(), GetMyUnits(), GetUnitClass(defID), GetTeamResources()
    ResolveKey(key), GetKeyTable(), GetMexSpots(), FindBuildPosition()
    FindNearestMexSpot(), Dist2D(), Dist3D(), NearestUnit()

    -- PERCEPTION (mapzones)
    MapZones = { buildingArea, primaryLine, secondaryLine, drawMode }
    MapZonesAPI = { StartDraw*, Clear*, IsInsideBuildingArea }

    -- DECISION (config)
    Strategy = { openingMexCount, energyStrategy, unitComposition, posture,
                 t2Timing, econArmyBalance, faction, role, laneAssignment,
                 t2Mode, t2ReceiveMinute, attackStrategy, emergencyMode, emergencyExpiry }

    -- EXECUTION STATE (each engine owns its section)
    BuildPhase = "waiting"|"building"|"handoff"|"done"
    Economy = { state, metalRate, energyRate, recommendation }
    Production = { factories, currentMix, desiredMix }
    Zones = { base, front, rally, assignments }
    Goals = { queue, activeGoal, allocation, overrides, placementMode }
    GoalsAPI = { AddGoal, RemoveGoal, MoveGoalUp/Down, AddGoalFromPreset, StartPlacement }
    StrategyExec = { activeStrategy, activeEmergency, creeping, piercing, fakeRetreat, antiAARaid }

    -- RENDERING HELPERS (core)
    FormatRate(), FormatInt(), FormatBP(), SetColor(), DrawFilledRect(), DrawHLine()
}
```

## Known Duplications (Phase 2 will fix)

1. **BuildKeyTable()** exists in BOTH `lib_core.lua` AND `engine_goals.lua` - goals should use core's
2. **Role classification** is duplicated in `engine_goals.lua` (CountUnitsMatchingRole, FindBestUnitForRole) - should use prod's roleMappings via WG
3. **ResolveKey()** exists in both core and goals - goals should use `TL.ResolveKey()`

## Python Simulation Engine

Standalone package at `sim/`. Install with `pip install -e .` from `sim/` dir.

**Key files:**
- `engine.py` - Main simulation loop
- `models.py` - Data models (GameState, Unit, etc.)
- `econ.py` - Economy simulation
- `production.py` - Factory production simulation
- `strategy.py` - Strategy model
- `goals.py` - Goal queue simulation
- `optimizer.py` - Build order optimization
- `map_data.py` / `map_parser.py` - Map data (needs real data for accuracy)
- `cli.py` - Command-line interface
- `web.py` + `static/` - Web dashboard (basic)

**Current limitation:** No real map data. Walking times and environment states are approximated. For accurate simulations we need actual map terrain data, mex spot positions per map, pathfinding distances.

**The vision:** The sim is the "Doctor Strange" - run 1000 games simultaneously, find the optimal play. Used at every automation level:
- Level 1: Validate build orders offline
- Level 2: Run predictions, compare options, recommend strategy changes
- Level 3: Full optimization -> AI decides optimal strategy

## Git Context

- Branch: `exp/keyboard-macros` (in the TheLab monorepo)
- Main branch: `main`
- All BAR files are currently untracked (new experiment)
- Monorepo path: `Jules.Life/Projects/TheLab/Experiments/BAR/`
