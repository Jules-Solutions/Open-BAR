# BAR Project — Open-BAR / TotallyLegal

> AI agent context for the Beyond All Reason widget suite, simulation engine, and AI automation system.

## What This Project Is

**TotallyLegal** is an AI automation and strategy system for [Beyond All Reason](https://www.beyondallreason.info/) (open-source RTS game, Spring Engine). It consists of:

1. **Lua Widget Suite** — In-game widgets for perception, micro automation, and presentation
2. **Python Simulation Engine** — Build order simulation, optimization, and strategy modeling
3. **Puppeteer Micro Suite** — Formation-aware dodging, kiting, smart movement, and raiding

The system operates at **four automation levels** (0=Overlay/PvP-safe, 1=Execute, 2=Advise, 3=Autonomous) and is built around **five systems** (Perception, Simulation, Decision, Execution, Presentation).

## Repository Structure

```
BAR/
├── lua/LuaUI/Widgets/        # Active Lua widgets (12 files)
│   ├── 01_totallylegal_core.lua          # Core library (perception, shared state)
│   ├── auto_puppeteer_core.lua           # Puppeteer shared core
│   ├── auto_puppeteer_dodge.lua          # Formation-aware projectile dodging
│   ├── auto_puppeteer_firingline.lua     # Optimal range kiting
│   ├── auto_puppeteer_formations.lua     # Unit formation management
│   ├── auto_puppeteer_march.lua          # Group movement coordination
│   ├── auto_puppeteer_raid.lua           # Automated mex raiding patrol
│   ├── auto_puppeteer_smartmove.lua      # Reactive rerouting around enemies
│   ├── gui_puppeteer_panel.lua           # Puppeteer control panel
│   ├── gui_totallylegal_overlay.lua      # Resource breakdown, unit census
│   ├── gui_totallylegal_sidebar.lua      # KSP-style widget toggle bar
│   └── gui_totallylegal_timeline.lua     # Economy timeline graph
│   └── _shelf/                           # Shelved macro widgets (Phase 6+)
├── sim/                                  # Python 3.11+ simulation engine
│   ├── bar_sim/                          # Core package (20+ modules)
│   ├── data/                             # Unit DB, build orders, map cache
│   ├── tests/                            # pytest suite (36+ tests)
│   └── cli.py                            # CLI entry point
├── Prod/                                 # Reference code (BAR source, Skirmish AI)
├── docs/                                 # Architecture, strategy, status, roadmap
├── sessions/                             # Work sessions
├── Discord_Chats/                        # Communication logs with BAR devs
└── archive/                              # Legacy files
```

## Architecture — The Five Systems

```
                     ┌──────────────────────┐
                     │   PRESENTATION       │
                     │   (overlays, panels)  │
                     └──────────┬───────────┘
                                │ displays
 ┌──────────────┐    ┌──────────┴───────────┐    ┌──────────────┐
 │  PERCEPTION  │───>│      DECISION        │───>│  EXECUTION   │
 │  (game state)│    │  (strategy choice)   │    │  (build, move│
 └──────────────┘    └──────────┬───────────┘    │   fight)     │
                                │ queries        └──────────────┘
                     ┌──────────┴───────────┐
                     │    SIMULATION         │
                     │  (predictions, opti-  │
                     │   mization, threat)   │
                     └──────────────────────┘
```

All inter-system communication flows through the `WG.TotallyLegal` shared state table. Each system owns its section, reads are nil-safe. See `docs/ARCHITECTURE.md` for the full state contract.

## Tech Stack

| Layer | Language | Key Details |
|-------|----------|-------------|
| In-game widgets | **Lua** (Spring RTS widget API) | `WG.*` global state, `widget:GameFrame()` loop, `Spring.GiveOrderToUnit()` |
| Simulation engine | **Python 3.11+** | pyyaml, fastapi, uvicorn, pytest |
| Web dashboard | **FastAPI + HTML/CSS/JS** | `sim/bar_sim/web.py` |
| Game engine | **C++ / AngelScript** | Reference only in `Prod/` — not our code |
| Build orders | **YAML** | `sim/data/build_orders/` |

## Development Conventions

### Widget Naming

| Prefix | System | Orders? | Example |
|--------|--------|---------|---------|
| `01_totallylegal_*` | Perception (core) | No | `01_totallylegal_core.lua` |
| `gui_*` | Presentation | No | `gui_totallylegal_overlay.lua` |
| `auto_puppeteer_*` | Execution/Micro | Yes | `auto_puppeteer_dodge.lua` |
| `engine_*` | Execution/Macro or Decision | Yes | (currently shelved) |

### Widget Load Order

Core loads at layer -1. Puppeteer core at layer 0. All other widgets at higher layers. Load order doesn't matter if every read is nil-safe.

### Shared State Rules

1. Each system **only writes** to its own `WG.TotallyLegal` section
2. Each system reads from other sections with **nil-safe access**
3. Core library is the **single source of truth** for unit data, keys, resources
4. Disabling any widget must not crash any other widget

### Fair Play

- **Level 0** = zero `GiveOrderToUnit` calls. Read-only. PvP safe.
- **Level 1+** = uses automation. Auto-disabled when `noautomation` game rule is active.

### Git

- Branch: `main`
- Commit messages: imperative mood, describe the change
- License: GPL v2.0

### Python

- Package at `sim/`, install with `pip install -e .` from `sim/` dir
- Tests: `pytest` from `sim/` dir
- CLI: `python cli.py <command>`

## Current State (Feb 2026)

### Completed (Phases 1-5)

- Perception stabilized — core library as single source of truth
- Execution stabilized — Level 1 macro engines all fixed (now shelved pending macro redesign)
- Micro automation — Puppeteer suite: dodge, firing line, formations, march, smart move, raid
- Simulation engine — build order optimization, map data integration, parity with Lua logic
- Presentation — overlays, sidebar, timeline

### Active Work — The BARB Quest

Jules was tasked by a BAR dev to **improve the building logic for BARB** (new BAR AI). Current goals:

1. Research BAR's architecture and STAI (existing AI)
2. Analyze BARB 2 & 3 differences
3. Build modular build order system using Blueprint API
4. Connect game data with web dashboard
5. Improve simulation/calculator
6. Export/scrape game data for future AI training

### Upcoming (Phases 6-7)

- **Phase 6:** Sim bridge — connect Python sim to Lua execution (Level 2: Advise)
- **Phase 7:** AI agent — autonomous strategy via RL (Level 3: Autonomous)

## Key Files to Read First

1. `CLAUDE.md` — This file
2. `docs/ARCHITECTURE.md` — Five systems, four levels, shared state contract
3. `docs/STATUS.md` — Widget inventory, known issues
4. `docs/PLAN.md` — Roadmap (Phases 1-7)
5. `docs/CHECKPOINT_2026-02-08.md` — Deep analysis, STAI research findings
6. `lua/LuaUI/Widgets/01_totallylegal_core.lua` — Core library (foundation)
7. `sessions/Session_2/Brainstorm.md` — Current quest and goals

## Key Reference Resources

| Resource | Location |
|----------|----------|
| BAR game source | `Prod/Beyond-All-Reason/` |
| Skirmish AI reference | `Prod/Skirmish/` |
| Discord chat logs | `Discord_Chats/` |
| BAR strategy guides | `docs/BAR_STRATEGY.md`, `docs/BAR_COMPLETE_STRATEGY.md` |
| Build order reference | `docs/BAR_BUILD_ORDERS.md` |
| Unit database | `sim/data/bar_units.db`, `sim/data/unitlist.csv` |

## Constraints

### Do
- Respect the five-system architecture
- Keep widget reads nil-safe
- Test Lua changes in skirmish before committing
- Run `pytest` in `sim/` after Python changes
- Keep Level 0 at zero `GiveOrderToUnit` calls
- Read `docs/ARCHITECTURE.md` before modifying widget interactions
- Document architectural decisions in `docs/`

### Don't
- Duplicate logic that belongs in core library
- Issue orders from `gui_*` widgets
- Break the shared state contract
- Add dependencies between widgets that bypass `WG.TotallyLegal`
- Modify files in `Prod/` (reference only, not our code)
- Mix presentation and execution concerns in the same widget
