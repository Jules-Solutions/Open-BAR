# TotallyLegal Checkpoint: 2026-02-08

## Current Reality Check

### What "Mathematically Optimal" Actually Requires

1. Build the right structure at the right time at the right place
2. Produce the right units in the right quantities
3. Send units to the right locations
4. All decisions based on calculation, not hardcoded heuristics

### What We Actually Have

| System | File | Exists? | Tested In-Game? | Makes Optimal Decisions? |
|--------|------|---------|-----------------|--------------------------|
| Core library | `lib_totallylegal_core.lua` | ✅ | ❓ | N/A (data layer) |
| Build executor | `engine_totallylegal_build.lua` | ✅ | ❌ | ❌ hardcoded queue |
| Economy manager | `engine_totallylegal_econ.lua` | ✅ | ❌ | ❌ threshold heuristics |
| Production manager | `engine_totallylegal_prod.lua` | ✅ | ❌ | ❌ ratio-based |
| Zone manager | `engine_totallylegal_zone.lua` | ✅ | ❌ | ❌ distance-based |
| Goals system | `engine_totallylegal_goals.lua` | ✅ | ❌ | ❌ |
| Strategy executor | `engine_totallylegal_strategy.lua` | ✅ | ❌ | ❌ |
| Python sim | `sim/bar_sim/` | ✅ | Standalone only | Has optimizer but **NOT CONNECTED** |

### Core Problem

Widgets make decisions with inline heuristics like:
```lua
if energyIncome < metalIncome * 10 then buildWind()
```

Should be:
```lua
bestAction = sim.optimize(currentState)
execute(bestAction)
```

The Python sim that could make optimal decisions isn't wired to the game.

---

## Open Questions

### 1. Verified Basic Execution
- Do the widgets even RUN without crashing?
- Never tested in-game after all these changes

### 2. Constructor Management
Who assigns idle constructors? The economy widget? Do they:
- Expand to new mexes?
- Build energy when stalling?
- Assist factories?
- Not collide with each other?

### 3. Continuous Decision Loop
The build executor handles the OPENING (first ~2 minutes). Then what?

Who decides:
- Build more winds or fusion?
- Expand or defend?
- Tech up or mass T1?

### 4. Simulation-Driven Decisions
How do we bridge Python sim → Lua execution?

---

## Action Items

### 1. Answer the Questions Above
- Read through each execution widget
- Map what decisions each one makes
- Identify gaps and overlaps

### 2. Research BARB (BAR's Native AI)
- How does it work?
- What architecture does it use?
- What can we learn/borrow?
- Where is the source code?

### 3. Test Current System In-Game
- Load a game with automation level 1
- Enable logging
- Watch what happens
- Collect and analyze logs
- Document what works and what doesn't

### 4. Analyze Strategy Implementation
Explain the full flow:
- How is strategy configured?
- How does config → execution work?
- What triggers each decision?
- Where are the heuristics vs calculated decisions?

### 5. Analyze Economy Widget
Explain the full flow:
- What decisions does it make?
- When does it make them?
- How does it prioritize?
- How does it interact with other systems?

### 6. Decide How to Move Forward
Based on findings:
- Fix bugs first vs architecture changes?
- Wire simulation now vs later?
- What's the minimal viable automaton?

---

## Session Work Done Today

### Priority Widget (`gui_totallylegal_priority.lua`)
- Fixed `IsBuilderEffectivelyIdle()` - no longer triggers while building

### Build Executor (`engine_totallylegal_build.lua`)
- Added shift-queue with `MaintainBuildQueue()`, `queueAhead=5`
- Integrated Blueprint API for modular building
- Dynamic module generation (target area, aspect ratio, blast radius awareness)
- Category system: only eco buildings + nano turrets can be grouped

### What We Built (Module System)
```lua
MODULE_CFG = {
    targetAreaSquares = 48,      -- tunable parameter
    aspectRatio = 1.33,          -- tunable parameter
    blastRadiusBuffer = 1.2,     -- safety margin
    interGroupSpacing = 32,      -- elmos between groups
}
```

This IS useful for the simulation because:
- Parameters can be optimized by the sim
- Placement is deterministic (sim can predict where buildings go)
- State tracking via `placedGroups[]`

But it's premature if the basic execution doesn't work.

---

## File References

### Execution Widgets (Need Analysis)
- `engine_totallylegal_build.lua` - ~1100 lines
- `engine_totallylegal_econ.lua` - TBD
- `engine_totallylegal_prod.lua` - TBD
- `engine_totallylegal_zone.lua` - TBD
- `engine_totallylegal_goals.lua` - TBD
- `engine_totallylegal_strategy.lua` - TBD

### Python Sim (Reference)
- `sim/bar_sim/engine.py`
- `sim/bar_sim/econ.py`
- `sim/bar_sim/optimizer.py`

### BARB AI (To Research)
- Location: likely in BAR game data or GitHub repo
- Need to find and study

---

## Next Session Checklist

- [ ] Find BARB source code
- [ ] Read `engine_totallylegal_econ.lua` fully, document decision flow
- [ ] Read `engine_totallylegal_strategy.lua` fully, document flow
- [ ] Test in-game, collect logs
- [ ] Create decision matrix: what decides what
- [ ] Identify the "handoff" gap between opening and mid-game

---

## BARB/STAI Research Findings

**Location:** `Beyond-All-Reason/luarules/gadgets/ai/STAI/` (GitHub)

STAI uses a **Module/Behaviour architecture**:
- `*hst.lua` = Handler/Module (high-level coordination, global state)
- `*bst.lua` = Behaviour (per-unit behaviors)

### Key Components

| File | Type | Purpose |
|------|------|---------|
| `ecohst.lua` | Handler | Rolling 30-sample resource average, tracks income/usage/reserves/capacity |
| `buildingshst.lua` | Handler | Build position finding, rectangle tracking, role assignment |
| `engineerhst.lua` | Handler | Manages engineer-to-builder assignments |
| `labshst.lua` | Handler | Factory management and production |
| `taskshst.lua` | Handler | Defines task queues per role |
| `buildersbst.lua` | Behaviour | Builder AI - processes task queue for each constructor |
| `engineerbst.lua` | Behaviour | Engineer AI - guards builders |

### STAI's Role System

Each builder unit is assigned a **role** that determines what it builds:

| Role | Purpose |
|------|---------|
| `starter` | First nano turret builder |
| `eco` | Energy production |
| `expand` | Mex expansion |
| `nano` | Nano turret builder |
| `support` | Radar, defenses |
| `assist` | Help other builders |
| `default` | Mixed tasks |
| `metalMaker` | Converters |

Role assignment is **dynamic**:
```lua
-- Commander role logic (simplified from SetRole)
if no nanos exist then role = 'starter'
elseif eco_count < 1 and expand_count >= 3 then role = 'assist'
elseif eco_count >= 1 then role = 'expand'
else role = 'default'
```

### STAI's Task Queue System

Each role has a queue of tasks with filters:

```lua
-- Example task structure (inferred from buildersbst.lua)
{
    category = '_wind_',          -- unit category to build
    economy = { ... },            -- economy conditions required
    special = true,               -- use special filter (wind speed check)
    numeric = 5,                  -- max count limit
    duplicate = true,             -- prevent duplicates
    location = {                  -- where to build
        categories = {'_fac_'},   -- near these categories
        min = 50, max = 390,      -- distance range
    }
}
```

### STAI's Build Position System

**Rectangle tracking** prevents collisions:
- `dontBuildRects[]` - areas where building is blocked (mex spots, geo, factory exit lanes)
- `sketch[]` - buildings under construction
- `builders[]` - planned builds (builder has orders but not started yet)

**Factory exit lanes** are calculated to keep the front clear:
```lua
-- Factory gets a "lane" rectangle extending from its exit
if facing == 0 then  -- north
    rect.z2 = position.z + tall  -- extend north
```

### STAI vs TotallyLegal Comparison

| Feature | STAI | TotallyLegal |
|---------|------|--------------|
| Role system | ✅ Dynamic per-builder | ❌ None |
| Task queues | ✅ Configurable per-role | ❌ Single priority list |
| Economy filtering | ✅ Per-task conditions | ⚠️ Global state check |
| Position finding | ✅ Rectangle avoidance | ⚠️ Basic spiral search |
| Engineer management | ✅ Tracks assignments | ❌ No assignment |
| Fallback behavior | ✅ Assist other builders | ❌ Just retry |
| Duplicate prevention | ✅ Factory-aware | ❌ None |

### What We Should Learn from STAI

1. **Role-based builder assignment** - Don't treat all constructors the same
2. **Task queue per role** - Each role has different priorities
3. **Build rectangle tracking** - Avoid placing in bad spots
4. **Factory exit lane awareness** - Don't block factory output
5. **Engineer assist system** - Extra constructors help, don't idle
6. **Fallback to assist** - When stuck, help someone else

---

## Economy Widget Analysis

**File:** `engine_totallylegal_econ.lua` (337 lines)

### Decision Flow

```
GameFrame (every 30 frames)
    ↓
AnalyzeEconomy()
    ├── Get resource snapshot from TL.GetTeamResources()
    ├── Calculate metalFill, energyFill ratios
    ├── Set state: "metal_stall" | "energy_stall" | "metal_float" | "energy_float" | "balanced"
    └── Check goal reserves (suppress float while banking)
    ↓
AssignIdleConstructors()
    ├── FindIdleConstructors() - scan all my builders with no commands
    ├── Split by goal.projectConstructors fraction (for goal builds)
    ├── Project cons → assigned to goal's econBuildTask
    └── Normal cons → iterate BUILD_PRIORITY list
        ├── Check condition matches state
        ├── Check CanAfford (15% of cost)
        ├── TL.FindBuildPosition() - spiral search
        └── GiveOrderToUnit(-defID, {x,y,z})
```

### BUILD_PRIORITY (hardcoded)

```lua
{ key = "mex",       condition = "metal_stall",    priority = 100 },
{ key = "wind",      condition = "energy_stall",   priority = 90 },
{ key = "solar",     condition = "energy_stall",   priority = 85 },
{ key = "mex",       condition = "always",         priority = 70 },
{ key = "wind",      condition = "always",         priority = 50 },
{ key = "converter", condition = "energy_float",   priority = 40 },
```

### What's Missing vs STAI

1. **No role system** - All constructors treated equally
2. **No task queues** - Single global priority list
3. **No special filters** - Doesn't check wind speed for wind, etc.
4. **No duplicate prevention** - Could build 10 radars
5. **No engineer assist** - Extra cons just idle if nothing to build
6. **No factory awareness** - Doesn't know about factory exit lanes

---

## Strategy Widget Analysis

**File:** `engine_totallylegal_strategy.lua` (711 lines)

### Attack Strategies

| Strategy | Description | Abort Condition |
|----------|-------------|-----------------|
| `creeping` | Slowly advance front line | 60% losses |
| `piercing` | All units concentrate on one point | 50% losses |
| `fake_retreat` | Bait + ambush | All bait units dead |
| `anti_aa_raid` | Fast units hit AA | ? |

### Emergency Modes

| Mode | Effect |
|------|--------|
| `defend_base` | Build LLT |
| `mobilization` | Stop building, make units |

### Decision Flow

```
GameFrame (every 60 frames)
    ↓
Check Strategy.attackStrategy
    ├── "creeping" → ExecuteCreeping()
    ├── "piercing" → ExecutePiercing()
    ├── "fake_retreat" → ExecuteFakeRetreat()
    └── "anti_aa_raid" → ExecuteAntiAARaid()
    ↓
Check Strategy.emergencyMode
    ├── "defend_base" → (handled by econ widget)
    └── "mobilization" → (suppresses econ building)
```

### How Strategies Get Units

```lua
GetFrontUnits()  -- from ZoneManager.assignments where assignment == "front"
GetRallyUnits()  -- where assignment == "rally"
```

### What's Missing

1. **No automatic strategy selection** - Human must pick
2. **No scouting integration** - Doesn't know what enemy has
3. **No timing windows** - Doesn't know when to attack
4. **No retreat coordination** - Just moves to rally point

---

## Gap Analysis: Opening → Mid-game Handoff

### The Problem

`engine_totallylegal_build.lua` handles the **opening** (first ~5 items):
```lua
buildQueue = {
    { key = "mex", type = "structure" },
    { key = "mex", type = "structure" },
    { key = "wind", type = "dynamic_module" },
    { key = "bot_lab", type = "structure" },
    { key = "mex", type = "structure" },
}
```

When it finishes, `phase = "done"` and `BuildPhase = "done"`.

Then `engine_totallylegal_econ.lua` takes over with its simple priority system.

**But there's no coordination:**
- Build widget doesn't tell econ widget where it built things
- Econ widget doesn't know if factory was placed
- No continuity in strategy

### The Gap

| Time | System | Working? |
|------|--------|----------|
| 0:00-2:00 | Build executor | ✅ Executes fixed queue |
| 2:00+ | Economy manager | ⚠️ Simple threshold heuristics |
| 2:00+ | Production manager | ❓ Untested |
| 2:00+ | Zone manager | ❓ Untested |
| 2:00+ | Strategy executor | ⚠️ Only if manually triggered |

---

## Recommended Path Forward

### Option 1: Fix the Basics (Conservative)
1. Test current widgets in-game
2. Fix crashes/bugs found
3. Improve economy widget with role system
4. Wire production → economy → zones
5. Then connect simulation

### Option 2: STAI-Style Rewrite (Ambitious)
1. Implement role-based builder assignment
2. Implement task queue system per role
3. Implement rectangle tracking for positions
4. Implement engineer assist system
5. Then connect simulation

### Option 3: Simulation-First (Your Vision)
1. Build simbridge to export game state
2. Python sim makes ALL decisions
3. Lua widgets just execute
4. Train RL on sim decisions

**Recommendation:** Start with Option 1 (test what we have), then decide if Option 2 or 3 makes more sense based on what works/breaks.
