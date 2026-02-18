# BARB Quest — TODO

## Phase 0: Research & Documentation [DONE]
- [x] Create quest folder structure (sessions/Session_2/)
- [x] Create README.md (quest overview)
- [x] Create OPEN_QUESTIONS.md
- [x] Create Context/Key_File_Index.md
- [x] Summarize Discord AI chat history
- [x] Summarize Discord Barb 2.0 testing history
- [x] Research Report 01: BAR Architecture
- [x] Research Report 02: AngelScript Reference
- [x] Research Report 03: STAI Analysis
- [x] Research Report 04: BARBv2 vs Barb3 Comparison
- [x] Research Report 05: Blueprint API
- [x] Research Report 06: Block Map System Deep Dive
- [x] Research Report 07: Building Placement Logic (cross-AI synthesis)
- [x] Research Report 08: Modular Build Design Proposal
- [x] Update OPEN_QUESTIONS.md with research findings

## Phase 1: Development Environment Setup [DONE]
- [x] Verify BAR game installed (`%LOCALAPPDATA%\Programs\Beyond-All-Reason\`)
- [x] Engine version: `recoil_2025.06.12`
- [x] Deploy Barb3 as separate AI via directory junction (BARb untouched)
- [x] Enable devmode.txt + uncheck "Simplified AI List" in Settings > Developer
- [x] Replace DLL with engine-compatible version (BARb's DLL)
- [x] Locate AI log output → `data\infolog.txt` (search for `[BlockPlanner]`)
- [x] Document the dev loop: modify .as → new match → observe → iterate
- [x] Write SETUP.md documenting the full dev environment
- [x] Load Barb3 AI in a skirmish game (experimental_balanced profile)
- [x] Create a test skirmish scenario (spectate Barb3 vs BARb)

## Phase 2: Prototype Block Placement (MVP) [DONE]
- [x] WindBlock template data structure in AngelScript
- [x] Block seed point selection (offset from StartPos, grid-snapped)
- [x] Slot position calculation (4x4 grid, 32 elmo spacing)
- [x] Hook into Barb3: intercept in builder waterfall for wind turbines
- [x] aiBuilderMgr.Enqueue() with shake=0 for exact positions
- [x] Task lifecycle: OnTaskRemoved callback in builder.as
- [x] Economy gating: metal > 5, energy stalling check
- [x] Test: wind turbines form clusters (confirmed 2026-02-17)

## Phase 3: Config-Driven Block Planner [DONE ✓]
Replaced hardcoded template_engine.as with config-driven block_planner.as.
Verified across 5+ test games. AI wins consistently against medium BARb.

### Files Created
- **`helpers/block_planner.as`** (~730 lines) — The main system
  - BuildingConfig registry: one entry per category, not per unit/faction
  - Scoring orchestration: ROI * urgency * feasibility * reliability
  - Block manager: tracks active blocks per category, cooldown, cleanup
  - Pending build tracking: prevents over-queueing (max 3 in-flight)
  - Wind estimation: `EstimateWindPerTurbine()` infers current wind from economy
  - Wind efficiency check: when stalling + wind < 6 E/s → exclude wind, solar only
  - Actual wind speed feeds into scorer (not hardcoded 15 fallback)
  - Portfolio diversification: dynamic target ratio from base scores
- **`helpers/cell_manager.as`** (~300 lines) — Position management
  - Rectangle-aware placement: tracks full block footprints (OccupiedRect)
  - Collision check with BLOCK_GAP (50 elmo) clearance on all sides
  - Mixed block types safe (different sizes don't overlap)
  - Cell size: 400x400 elmos, expansion away from map center
- **`helpers/scoring.as`** (~130 lines) — Pure math scoring
  - budgetCost = metalCost + energyCost/60 + buildTime/300
  - ROI * urgency * feasibility * reliability
  - Wind reliability penalty (when map data available)

### Files Modified
- `manager/builder.as` — Include + OnTaskRemoved hook (2 lines)
- `roles/front.as` — Block planner intercept in waterfall (~15 lines)
- `roles/front_tech.as` — Same intercept (~15 lines)
- `roles/tech.as` — Same intercept (~15 lines)
- `helpers/unit_helpers.as` — Added GetWindNameForSide() (+8 lines)

### Files Deleted
- `helpers/template_engine.as` — 642-line hardcoded system, fully replaced

### Registry (3 categories)
```
category    spacing  metal  energy  buildTime  eMake  variable  cols  rows
wind          32      40     175     1600        0     true       2     5
solar        112     155       0     2600       20     false      3     2
advsolar      96     350    5000     7950       80     false      2     2
```

### Gating Logic (ShouldIntercept)
1. Gate 1: mi < 5 → skip (too early)
2. Gate 2: pending >= 3 → skip (enough in-flight)
3. Gate 3: account for pending builds in effective EI
4. Gate 4: effectiveEI >= mi * 20 → skip (energy healthy)
5. If stalling + windPerTurbine < 6 → exclude wind, scorer picks solar vs advsolar

### Test Results
- Test 3: Block planner working, 27 enqueues, 4 blocks (3 wind + 1 solar)
- Test 4: Pacing fixed, pending cap working, waterfall coexists
- Test 5: Wind efficiency check fired (5.97 < 6 → built solar), advsolar built late game
- Tests 6-7: AI wins consistently against medium BARb, builds energy converters

---

## Phase 4: Buildpower & Economy Intelligence [CURRENT]

### 4a: Buildpower Management (Highest Impact)
Understanding the current constructor system:
- Leader/Guard hierarchy: primary + secondary leaders, up to 10 guards each
- Guards assist whatever leader builds (factory OR energy) — no task awareness
- No buildpower utilization tracking (keeps building cons it can't feed)
- Block planner tasks picked up by ONE builder — no collaboration mechanism

Improvements needed:
- [ ] Buildpower utilization check: `usableBP = metalIncome / metalDrainPerBP`
  - Don't build more constructors if utilization < 70%
  - Surgical: add check to constructor enqueue path in waterfall
- [ ] BP-aware scoring: score = ROI adjusted for available BP to build it
  - advsolar at 80 BP → 99 seconds. At 400 BP → 20 seconds. Time cost matters.
- [ ] Constructor collaboration on blocks: assign nearby idle cons to assist block builds
- [ ] Nano turret placement: aware of cell/block geometry

### 4b: Energy Registry Expansion
- [ ] Add converter to block planner registry (close the energy→metal loop)
- [ ] Add fusion config (late game, high cost)
- [ ] Add tidal config (water maps)
- [ ] Dynamic grid sizing based on available cell area

### 4c: Scoring Improvements
- [ ] Factor build time at actual BP into feasibility
- [ ] Priority split function: economy % / defense % / offense %
- [ ] Reactive overrides: army wiped → offense x3, nuke incoming → defense absolute

### 4d: Cell System Evolution
- [ ] Front cells (toward enemy — defensive templates)
- [ ] Outpost cells (remote mex clusters)
- [ ] Factory zone cells (factory + nanos + exit lane protection)
- [ ] Reclaim-and-rebuild (T1 wind → T2 fusion upgrade strategy)

## Phase 5: Map Vision & Threat Awareness
- [ ] **Map Analyzer** (`helpers/map_analyzer.as`)
  - [ ] Coordinate-to-state mapping: buildable, threat level, terrain type
  - [ ] Heightmap scan: elevation, slopes, chokepoints, high ground
  - [ ] Mex clustering: group spots into fields, classify contested vs safe
  - [ ] Start position classification: island, coastal, inland, corner
  - [ ] Enemy direction estimation from start positions
  - [ ] Auto-generate cell layout from terrain analysis
  - [ ] Use pregame window (~60s) for analysis
- [ ] **Threat Tracker** (`helpers/threat_tracker.as`)
  - [ ] Track enemy units via LOS events (composition, army value)
  - [ ] Estimate enemy income from visible buildings
  - [ ] Counter-unit mapping: enemy comp → production adjustment
  - [ ] Rush window detection: kill value > 3 min of enemy eco → rush

## Phase 6: Multi-Faction Testing & Polish
- [ ] Test on 5+ different maps (varied terrain, wind levels)
- [ ] Test all difficulty profiles (HundredBonus, balanced, etc.)
- [ ] Test all factions (Armada, Cortex, Legion)
- [ ] Performance profiling (no frame drops from placement calculations)
- [ ] Collect feedback from BAR community testers

## Phase 7: PR & Delivery
- [ ] Clean up code for PR submission
- [ ] Write documentation for the block system
- [ ] Before/after screenshots for PR description
- [ ] Ensure backward compatibility with existing config
- [ ] Submit PR to Felenious's Skirmish repo
- [ ] Address code review feedback

## Stretch Goals
- [ ] Dynamic block resizing based on available space
- [ ] Learning from player blueprints (parse popular layouts)
- [ ] Commander landing zone optimization
- [ ] Multi-AI coordination (share building zones between allied AIs)
- [ ] Connect to TotallyLegal simulation engine for optimal block parameters

## Active Questions
- How to access buildpower utilization data in AngelScript? (Need for Phase 4a)
- Can we redirect guard assignments to block builds? (Need for Phase 4a)
- Wind data via GameRules still returns -1 — using estimation workaround
- What maps should we prioritize for testing? (Need for Phase 6)

---
*Last updated: 2026-02-18*
*Quest given by: Felenious ([SMRT]Felnious), BAR AI Lead Developer*
