# Strategic AI Design — BARB Enhancement Vision

> All design ideas, principles, and architectural decisions surfaced during Session 2 brainstorming.
> This document captures the "what should BARB become" vision that goes beyond the block placement MVP.

---

## Core Principle: BAR Is an Opportunity Cost Game

Every second, the AI must decide how to allocate limited resources (metal, energy, time, buildpower) across three competing priorities:

| Priority | Purpose | Examples |
|----------|---------|----------|
| **Economy** | Increase future income | Mexes, energy, storage, constructors |
| **Defense** | Protect what we have | Turrets, shields, anti-nuke, walls |
| **Offense** | Threaten the enemy | Combat units, factories, army composition |

The optimal split is dynamic — it shifts based on game state, threat level, and strategic goals.

### The Real Limited Resource Is Time

Metal and energy are renewable. Time is not. Every second a constructor is idle or building the wrong thing, the enemy gains. The AI must:
- Always have all constructors busy with the highest-ROI task
- Never build buildpower it can't utilize (income-limited)
- Minimize wasted resources (metal/energy overflow = lost time)

---

## Decision Framework: Scoring Over Waterfalls

### Current System (Waterfall)
```
for each building (top to bottom priority):
    if income >= gate:
        build it → RETURN
```
Static priority, hard-coded gates. No comparison between alternatives.

### Target System (Scoring)
```
for each candidate building:
    score = ROI(building, gameState, goals) * urgency * feasibility
candidates.sort(by: score, descending)
return candidates[0]
```

### ROI Calculation

**budgetCost** (BAR's standard unit value formula):
```
budgetCost = metalCost + energyCost/60 + buildTime/300
```
- 1 metal = 1 budget unit
- 60 energy = 1 budget unit
- 300 buildtime frames = 1 budget unit (at 100 BP)

**Economy ROI** (for income-generating buildings):
```
breakeven_time = budgetCost / (income_per_second * time_value_factor)
ROI = 1 / breakeven_time  // higher = better investment
```

**Military ROI** (for combat units):
```
value = effective_dps * survivability_factor / budgetCost
counter_bonus = 1.5 if counters current enemy composition
ROI = value * counter_bonus * urgency
```

**Defense ROI**:
```
ROI = threat_level * coverage_value / budgetCost
```

### Priority Split Function

```
econ_weight = f(current_income, target_income, army_safety_margin)
defense_weight = f(threat_level, current_defense_coverage, incoming_threats)
offense_weight = f(army_strength_ratio, kill_opportunity, pressure_need)

// Normalize to 1.0
total = econ_weight + defense_weight + offense_weight
econ_pct = econ_weight / total
defense_pct = defense_weight / total
offense_pct = offense_weight / total
```

### Reactive Overrides

| Condition | Response |
|-----------|----------|
| Army just got wiped | offense_weight *= 3.0 |
| Nuke incoming, no anti-nuke | defense_weight = 100.0 (absolute priority) |
| Enemy passive for 3+ min | econ_weight *= 2.0 |
| Just killed 5k+ metal of enemy | offense_weight *= 2.0 (rush window) |
| Energy stalling | econ_weight *= 2.0 (energy focus) |

---

## Cell-Based Building System

### Terminology

| Term | Definition |
|------|-----------|
| **Cell** | A rectangular buildable area that gets filled with templates |
| **Template** | A predefined arrangement of buildings (e.g., 4x4 wind farm, factory cluster) |
| **Base Cell** | Around starting factory — economy + production |
| **Expansion Cell** | Adjacent to base cell — unlocked when base cell is full |
| **Front Cell** | Toward enemy — defensive templates |
| **Outpost Cell** | Remote positions — mex clusters, geo vents |

### Cell Lifecycle

```
1. PLANNED    — Cell position chosen, templates assigned
2. ACTIVE     — Currently being filled with buildings
3. FULL       — All template slots occupied
4. UPGRADING  — T1 buildings being reclaimed for T2 replacements
5. ABANDONED  — Too far from front / no longer strategic
```

### Cell Sizing

Cell size chosen so one "tier" of buildings fits comfortably:
- T1 cell: ~256x256 elmos (8x8 building grid at 32-elmo spacing)
- T2 cell: ~384x384 elmos (larger buildings need more space)
- Front cell: Variable width, depth = 2-3 building rows

### Progressive Filling Rules

1. Fill current cell before opening next cell
2. Higher-priority templates placed first within a cell
3. Reclaim-and-rebuild is an explicit strategy (T1 wind → T2 fusion)
4. Base center calculation only considers buildings in economy cells (NOT front cells)

### Cell Expansion Direction

Determined by map analysis:
- Away from enemy (safe expansion)
- Toward resource clusters (mex fields)
- Along terrain features (ridgelines, water edges)

---

## Resource Management

### Income Tracking (Improved)

Current AI: Single `income` value from engine (includes reclaim)

**Target:** Separate income streams:
| Stream | Stability | Use For |
|--------|-----------|---------|
| Mex income | Stable (constant while alive) | Long-term planning |
| Energy production | Stable (solar) or Variable (wind) | Long-term planning |
| Wind income | Variable (map-dependent) | Discounted by variance |
| Reclaim income | Temporary (bursty) | Short-term opportunism only |

### Wind Awareness

Maps have `windMin` and `windMax` values. The AI should:
- Query map wind data at game start (need engine bridge)
- Calculate expected wind income = `windCount * (windMin + windMax) / 2`
- Calculate wind variance for risk assessment
- Prefer solar on low-wind maps, wind on high-wind maps

### Build Budgeting

Before starting a build:
```
buildDuration = buildTime / assignedBuildpower
metalDrain = metalCost / buildDuration  // M/s during construction
energyDrain = energyCost / buildDuration  // E/s during construction

canAfford = (metalIncome - currentMetalDrain) >= metalDrain
          AND (energyIncome - currentEnergyDrain) >= energyDrain
```

If can't afford at current income, calculate time to accumulate:
```
storageNeeded = buildCost - (incomeRate * buildDuration)
if storageNeeded > currentStorage: need more storage first
```

### Buildpower Utilization

Track: `totalBuildpower` vs `usableBuildpower`:
```
usableBuildpower = metalIncome / metalDrainPerBP
efficiency = activeBuildpower / totalBuildpower
```
Don't build more constructors if efficiency < 0.7 (70% utilization)

---

## Enemy Awareness (Currently Missing)

### What We Need

| Capability | Current State | Target |
|-----------|--------------|--------|
| Enemy unit sightings | None in script layer | Track via LOS events |
| Enemy composition | Not tracked | Maintain running estimate |
| Enemy army value | Not tracked | Sum budgetCost of seen units |
| Enemy income estimate | Not available | Estimate from visible mexes/buildings |
| Kill tracking | Not tracked | Track value destroyed per engagement |
| Counter-unit mapping | Not implemented | Lookup table: enemy unit → best counter |

### Threat Estimation

```
estimated_enemy_army = sum(budgetCost of seen enemy units)
estimated_enemy_income = visible_enemy_mexes * mex_income_rate * uncertainty_factor
time_to_rebuild = estimated_enemy_army / estimated_enemy_income

// Rush window detection:
if (metal_just_killed > estimated_enemy_income * 180):  // > 3 min of their eco
    RUSH OPPORTUNITY — shift to 90% offense
```

### Counter-Unit System

Maintain a lookup table:
```
enemy_unit → [counter_unit_1, counter_unit_2, ...]
```

When enemy composition changes, re-score factory production to favor counters.

---

## Map Analysis (Runtime, Not Hardcoded)

### Goal: Play Any Map at Full Potential

Replace the 18 hardcoded map configs with runtime analysis that works on ALL maps.

### Analysis Pipeline (runs during pregame ~60s)

1. **Heightmap scan** — elevation data, slope analysis
2. **Water mask** — identify sea zones, islands, coastal areas
3. **Mex locations** — cluster mexes into fields, identify contested/safe fields
4. **Geo vents** — locate and prioritize
5. **Chokepoints** — narrow passages between high ground or water
6. **High ground** — elevated positions with range/vision advantage
7. **Cover** — areas behind terrain features (defilade)
8. **Start position analysis** — classify as island/coastal/inland/corner
9. **Enemy direction** — determine likely enemy approach vectors
10. **Cell placement** — auto-generate base cells, front cells, expansion cells

### Available Map Data (Spring Engine)

- Heightmap (elevation per grid cell)
- Metal map (mex positions)
- Water depth map
- Type map (terrain passability)
- Map dimensions
- Start positions (provided by engine at game start)
- Wind min/max (map metadata)

### What This Replaces

| Currently | Target |
|-----------|--------|
| 18 hardcoded map configs | Runtime analysis for ANY map |
| ~233 manual start spots | Engine-provided positions + auto-classification |
| Per-map unit bans | Dynamic based on terrain (ban vehicles on water maps, etc.) |
| Per-map factory weights | Based on terrain analysis (sea start → shipyard) |
| 1 map with strategic objectives | Auto-detected chokepoints and objectives |

---

## Pregame Window (~60 seconds)

Players choose positions and queue commander build orders. The AI should use this time for:

1. **Map analysis pipeline** (heightmap, mex clustering, chokepoints)
2. **Start position classification** (island, coastal, inland)
3. **Role determination** (based on position analysis, not lookup table)
4. **Opening build order calculation** (optimal for this specific position)
5. **Cell layout planning** (base cell, expansion direction, front cells)
6. **Commander build queue** (queue the opening during pregame like human players do)

### Implementation

Requires a pregame hook — either:
- C++ framework callback (if CircuitAI supports it)
- Lua widget that sends map data via `AiLuaMessage` during pregame
- Timer-based: start analysis in `AiMain()`, budget computation across frames

---

## Modular Code Architecture

### Principle: Our Code in Separate Files, Minimal Hooks

```
helpers/block_planner.as       ← Wind grid placement (EXISTS)
helpers/template_engine.as     ← Template definitions + placement logic (NEW)
helpers/cell_manager.as        ← Cell lifecycle, expansion, filling (NEW)
helpers/economy_planner.as     ← Resource forecasting, build budgeting (NEW)
helpers/threat_tracker.as      ← Enemy tracking, counter-unit logic (NEW)
helpers/map_analyzer.as        ← Runtime map analysis (NEW)
helpers/scoring.as             ← ROI calculations, priority scoring (NEW)
config/block_templates.json    ← Template library (NEW)
```

### Integration Points (Minimal Changes to Existing Files)

| Existing File | Change | Lines |
|--------------|--------|-------|
| `builder.as` | `#include` new helpers, task callbacks | ~5 lines |
| `tech.as` | Scoring interception before waterfall | ~20 lines |
| `economy.as` | Income stream separation hooks | ~10 lines |
| `main.as` | Map analyzer init call | ~3 lines |
| `military.as` | Threat tracker hooks | ~5 lines |

Total changes to existing code: ~45 lines. All logic in our own files.

---

## Key BAR Mechanics Reference

### Resource Conversion Rates
- **Energy to Metal:** 60:1 (T2 energy converter rate)
- **Budget cost formula:** `metalCost + energyCost/60 + buildTime/300`
- **Build speed:** `buildTime / totalAssistingBuildpower` = seconds to complete

### Build Mechanics
- T2 air plant requires T1 air constructor (NOT T2)
- Nanos can assist any nearby construction
- Multiple constructors can assist one build (additive buildpower)
- Commander has ~300 buildpower (represents the /300 in budget formula)

### Pregame
- ~60 seconds for position selection + commander build queue
- Players can pre-queue buildings during this time
- AI should use this window for map analysis and planning

### Key Stats Not in CCircuitDef (Need CSV/JSON Lookup)
- buildtime, buildpower, dps, weaponrange, radarrange, sightrange
- metalmake, energymake (production values)
- All detection ranges

---

## Open Design Questions

1. **How to get map data into AngelScript?** — Heightmap/water map not directly exposed. May need Lua bridge or C++ extension.
2. **How to get enemy unit events?** — C++ framework may have callbacks not exposed to script. Need to investigate or add them.
3. **How much computation budget per frame?** — Map analysis and scoring must not cause lag. Budget across multiple frames.
4. **Config format for templates?** — JSON (consistent with existing) vs inline AngelScript arrays.
5. **How to handle different difficulty levels?** — Scoring weights per profile? Intentional sub-optimal play?
6. **Integration with Felenious's manual build order system?** — Guard clauses so both systems coexist.

---

*Created: 2026-02-18 — Session 2 Strategic AI Design*
*Source: Jules + Claude brainstorming session*
