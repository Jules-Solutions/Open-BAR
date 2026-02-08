# TotallyLegal: Project Plan & Roadmap

## Vision

TotallyLegal is a **system of systems** for Beyond All Reason. Not a collection of features - five systems (Perception, Simulation, Decision, Execution, Presentation) that compose differently across four automation levels. The simulation engine is the strategic brain - the "Doctor Strange" of BAR - capable of running thousands of scenarios to find the optimal move.

The end goal: an AI player that can play BAR autonomously. But first, everything needs to work reliably for a human player.

## Current State (as of 2026-02-07)

### What Works
- **Overlays** (gui_* widgets) - info display, PvP safe
- **Auto-dodge** - decent projectile dodging
- **Project structure** - reorganized from flat "script jungle" to proper repo layout
- **automationLevel gate** - Level 0 (overlay) issues zero orders, Level 1+ enables execution

### What's Buggy/Broken
- **Economy manager** - constructor collision, stale goal reserves
- **Production manager** - goal count goes negative, aircraft roles not differentiated
- **Build order executor** - phase tracking race condition, no build order import
- **Zone manager** - dead units in groups, secondary line only reads at GameStart
- **Goals system** - stall detection false positive, overrides linger, duplicate BuildKeyTable
- **Strategy executor** - no abort conditions on attack patterns, broken retreat
- **Config panel** - slider math allows >100% allocation (breaks logic)
- **Skirmish** - overrides player movement commands
- **Rezbot** - spam-reassigns every frame (no per-bot cooldown)

### What's Proof of Concept
- **Python simulation** - works standalone but needs real map data for accurate predictions

---

## Phase Plan

### Phase 1: Organize & Define -- COMPLETED
- [x] Directory restructure (TotallyLegalWidget/ -> lua/sim/docs/archive)
- [x] README.md, LICENSE (GPL v2), CONTRIBUTING.md
- [x] docs/ARCHITECTURE.md (five systems, four levels, state contract)
- [x] install.bat (Windows symlink into BAR data dir)
- [x] automationLevel field in WG.TotallyLegal (getter/setter, WG sync)
- [x] Level toggle in config panel (row 0, cycles 0-3, persisted)
- [x] Level >= 1 gate in all 9 execution widgets
- [x] gui_* and engine_mapzones ungated (always run at all levels)

### Phase 2: Stabilize Perception (core library as single source of truth) -- COMPLETED
Fix lib_totallylegal_core.lua so every other system has reliable data.

- [x] Fix faction detection (add fallback scan + retry + manual override)
- [x] Remove duplicate BuildKeyTable() from engine_goals (core is the ONLY source)
- [x] Remove duplicate role classification from engine_goals (use prod's roleMappings)
- [x] Make ALL cross-system reads nil-safe (no crashes from load order)
- [x] Add _ready flags to each system's state section
- [x] Add pcall wrappers in all GameFrame functions (graceful degradation)
- [x] Fix FindBuildPosition() to respect build area for mex placement
- [x] Fix shutdown ordering (systems nil their own state, core never nils root table)

**Acceptance:** ONE BuildKeyTable, faction detected within 5s, disabling any widget doesn't crash others, clean shutdown.

### Phase 3: Stabilize Execution (make Level 1 actually work) -- COMPLETED
Fix engines so human-set strategy actually executes correctly. Fix in dependency order.

**3a: Config & Strategy (Decision system)**
- [x] Fix slider math: DEFERRED (only one slider, correctly clamped 0-100; future feature redesign)
- [x] Add strategy validation (ValidateStrategy warns on contradictory combos)
- [x] Add SetStrategy(key, value) API for programmatic control (future sim bridge)
- [x] Add GetStrategySnapshot() for serialization

**3b: Economy Manager**
- [x] Fix constructor collision (ClaimMexSpot/ReleaseMexClaim in core library)
- [x] Fix stale goal reserves (only apply when goals.activeGoal exists)

**3c: Production Manager**
- [x] Fix goal count going negative (mathMax(0, goalOverride.count - 1))
- [x] Add aircraft role differentiation (fighter/bomber/gunship/air_constructor)

**3d: Zone Manager**
- [x] Fix dead unit cleanup (CleanDeadUnits() atomic cleanup first in GameFrame)
- [x] Add dynamic secondary line updates (polled every GameFrame, hash-based change detection)

**3e: Build Order Executor**
- [x] Fix phase tracking race condition (threshold 10 -> 30 frames)
- [x] Add build order file import (LoadBuildOrderFromFile via VFS.LoadFile + pattern-based JSON parse)

**3f: Goals System**
- [x] Fix stall detection false positive (reset _lastCheckedProgress on new goals)
- [x] Fix override lifecycle (ClearOverrides at top of AdvanceQueue)
- [x] Wire goals to econ/prod/zone with proper orchestration (nil-guard warnings + UnitDefs validation)

**3g: Strategy Execution**
- [x] Add abort conditions to all attack patterns (creeping: 60% loss abort; fake_retreat: bait-death abort)
- [x] Fix retreat behavior ("retreating" assignment state, zone manager respects it, flips to "rally" when idle)

**Acceptance:** Set strategy -> system builds correctly. Goals complete. Constructors don't pile up. Dead units don't get orders. No slider combo breaks econ.

### Phase 4: Polish Execution Micro (can run in parallel with Phase 3) -- COMPLETED
- [x] Dodge: Scale radius by unit size, add minimum projectile travel time check
- [x] Skirmish: Don't override player movement commands, only kite engaged units
- [x] Rezbot: Add per-bot cooldown (3s), clean stale feature assignments

### Phase 5: Simulation as Engine (make sim useful at Level 1-2) -- COMPLETED
- [x] Map data integration (terrain, walking times, mex spots per map)
  - WalkTimeEstimator: speed-based walk time per builder type and distance
  - Cached map data pipeline with normalized name matching and alias table
  - Pre-cached maps: delta_siege_dry, comet_catcher_remake, supreme_isthmus
- [x] Build order optimization (run N sims, rank by fitness)
  - GA optimizer already worked; added --top N flag for ranked comparison
  - Auto-save optimized builds to data/build_orders/
- [x] Maintain parity between Python logic and Lua execution logic
  - parity.py: central registry of Lua-mirrored constants (STALL/FLOAT thresholds, RESOURCE_BUFFER, ECON_PRIORITIES)
  - Resource buffer check (15% affordability) added to engine.py
  - econ_ctrl.py imports from parity.py instead of local constants
- [x] Python test suite (pytest) to validate sim behavior
  - 36 tests across 7 files: engine, econ_ctrl, walk_time, map_data, parity, IO, CLI
  - pytest added to pyproject.toml optional deps
- [x] CLI improvements for practical use
  - Improved optimize output header (shows map, wind, mex, GA params)
  - --top N flag for ranked candidate comparison
  - Auto-save to data/build_orders/optimized_{map}_{goal}.yaml
  - cache-popular map action for batch scanning

**Acceptance:** `bar-sim optimize --map DeltaSiege` produces ranked build orders. Sim accounts for map-specific walking times.

### Phase 6: Connect the Systems (Level 2: Advise)
- [ ] engine_totallylegal_simbridge.lua - exports game state to JSON, reads predictions
- [ ] sim/bar_sim/live.py - watches for state updates, runs predictions, writes results
- [ ] Enemy estimation from scouting data (threat model)
- [ ] Presentation layer shows recommendations with reasoning
- [ ] automationLevel = 2 behavior: sim suggests, overlay shows, human approves

### Phase 7: The AI (Level 3: Autonomous)
- [ ] Define observation space (game state features)
- [ ] Define action space (strategy config changes)
- [ ] Define reward signal (income growth, army value, game outcome)
- [ ] Gymnasium-compatible environment wrapper around sim engine
- [ ] Data collection from replays
- [ ] Training loop (imitation learning first, then RL)
- [ ] automationLevel = 3 behavior: AI decides, widgets execute, overlay explains

---

## Feature Ideas (Backlog)

### ~~Widget Sidebar Toggle (KSP-style)~~ -- IMPLEMENTED
Implemented as `gui_totallylegal_sidebar.lua` (layer 99). Vertical bar on right screen edge with 2-char icon buttons for all 10 widgets. Click to toggle visibility via `WG.TotallyLegal.WidgetVisibility`. Level indicator at bottom (click to cycle). Collapse to TL logo. Design doc: `docs/FEATURE_SIDEBAR.md`.
