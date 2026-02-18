# Barb3 TECH Walkthrough — Minutes 30:00+

> Endgame steady state, nuclear policy, donation system, and complete systems overview.

---

## Overview

After minute 30, TECH enters a **steady-state loop**. The decision waterfalls still run, but most thresholds have been passed. The game is about **scaling production**, **nuclear warfare**, and **experimental army composition**. There are no new unlocks — just more of everything.

---

## Phase 21: Nuclear Policy (30:00+)

### Nuke Silo Production

Two pathways exist depending on the NUKE_RUSH roll:

**With NUKE_RUSH (25% of games):**
```
Rush threshold: metalIncome >= 50.0 AND energyIncome >= 2000.0
Max rush silos: NukeRush (1)
```
The first silo was likely built around minute 8-15. After the rush silo, additional silos require normal thresholds.

**Normal threshold:**
```
metalIncome >= 600.0 AND energyIncome >= 10000.0
No upper limit on silo count (NukeLimit = 20)
```

At extreme income (600mi + 10000ei), TECH builds nukes freely. Each silo auto-produces nuclear missiles.

> **Source:** `tech.as:1237-1253`, `global.as:277-281`

### Anti-Nuke Scaling

```
Minimum count: 1 (MinimumAntiNukeCount)
Allowed: floor(metalIncome / 80.0) (MetalIncomePerAntiNuke)
Threshold: metalIncome >= 80.0 AND energyIncome >= 3000.0
```

Anti-nuke count scales with income. At 400mi, the AI maintains up to 5 anti-nukes. These are placed near the T2 bot lab anchor position.

> **Source:** `tech.as:1256-1273`, `global.as:283-290`

---

## Phase 22: Steady-State Production Loop

### The Gantry Cycle

Each gantry repeats this cycle:

```
1. Check metal income > 200 → queue 5 signature experimentals (HIGH priority)
2. Fall through to C++ DefaultMakeTask → picks heavy/super units from Factory JSON
3. Wait for production to complete → repeat
```

With multiple gantries, experimental production accelerates linearly. Three gantries producing simultaneously can field an army of heavy units every few minutes.

### The T2 Bot Lab Cycle

If T2 bot labs survived recycling (or were rebuilt after economy scaled):

```
1. Maintain T2 constructor minimum → recruit if needed
2. Fast-assist bots → scale with income (cap = 5 * floor(mi/45))
3. Blocks of 10 fast T2 bots → continuous military
4. Default → C++ picks remaining units from Factory JSON
```

### The Air Plant Cycle

```
1. Maintain air constructor count → recruit if below target
2. Default → C++ picks combat aircraft from Factory JSON
```

---

## Phase 23: The Donation System (Team Cooperative Play)

### How It Works

TECH donates its 3rd T2 constructor to allied team leader:

```angelscript
namespace Donate {
    int T2CtorEverBuilt = 0;
    bool DonatedThird = false;

    void Tech_BuilderAiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage) {
        if (Donate::IsT2Constructor(d)) {
            Donate::T2CtorEverBuilt += 1;
            if (!Donate::DonatedThird && Donate::T2CtorEverBuilt == 3) {
                Donate::DonatedThird = true;
                Donate::TryDonate(unit);
            }
        }
    }
}
```

### What Counts as T2 Constructor?

```angelscript
bool IsT2Constructor(const CCircuitDef@ d) {
    int tier = UnitHelpers::GetConstructorTier(d);
    if (tier == 2) return true;
    // Also count T2 air constructors: armaca/coraca/legaca
    if (UnitHelpers::IsAirConstructor(d)) { ... }
}
```

Both ground T2 constructors and T2 air constructors count. The 3rd one of either type triggers the donation.

### Why Donate?

This is a cooperative AI design: TECH rushes to T2 faster than other roles. By donating a T2 constructor, it helps allies start their own T2 transition earlier. The donation only happens once per game.

> **Source:** `tech.as:27-56`, `tech.as:763-778`

---

## Phase 24: Role Switch System

### How Role Switching Works

Every `Tech_MakeSwitchInterval()` frames (400-500 seconds), the engine asks if the AI should switch factories:

```angelscript
bool Tech_AiIsSwitchTime(int lastSwitchFrame) {
    int interval = (20 * SECOND);  // 20 seconds
    return (lastSwitchFrame + interval) <= ai.frame;
}

bool Tech_AiIsSwitchAllowed(facDef, armyCost, factoryCount, metalCurrent, &out assistRequired) {
    bool switchAllowed = metalIncome > 100.0f;
    int totalGantryCount = landGantryCount + waterGantryCount;
    assistRequired = (totalGantryCount < 1) ? false : (!switchAllowed);
    return switchAllowed;
}
```

**Switch allowed above 100mi.** The C++ engine then decides whether to add a new factory type based on army composition, threat assessment, and available factory options.

**Assist required** only kicks in after at least one gantry exists AND income is below 100. This means:
- Pre-gantry: constructors build infrastructure, not assist factories
- Post-gantry: low-income constructors assist factory production

> **Source:** `tech.as:617-652`

---

## Complete Systems Overview

### The Four Manager Hooks

Every game tick, the engine calls these manager functions, which delegate to role-specific handlers:

```
Economy::AiUpdateEconomy()  → Tech_EconomyUpdate()
  - Resource tracking (sliding-window minimums)
  - Dynamic cap scaling
  - Factory assist logic
  - Advanced storage unlock
  - Gantry/air plant cap updates

Factory::AiMakeTask(unit)   → Tech_FactoryAiMakeTask()
  - Constructor production waterfall
  - Fast-assist bot production
  - Combat unit blocks (T2 bots)
  - Gantry experimental batches

Builder::AiMakeTask(unit)   → Tech_BuilderAiMakeTask()
  - MEX/GEO passthrough
  - Wind block interception (our addition)
  - Commander logic
  - T1 constructor waterfall (T2 lab, air, solar, nano, expansion)
  - T2 constructor waterfall (gantry, converter, nuke, AFUS, fusion)

Military::AiMakeTask(unit)  → Tech_MilitaryAiMakeTask()
  - Below 50mi: null (no orders)
  - Above 50mi: C++ default military
```

### The Economy Tick

`Tech_EconomyUpdate()` runs every economy update (30 FPS simulation, called on slow update cycle):

```
1. Check factory assist bootstrap (T2 lab + no T2 constructors)
2. Tech_IncomeBuilderLimits(metalIncome) — scale all builder/rez/assist caps
3. Advanced storage unlock check (100mi)
4. Dynamic gantry cap update
5. T1 bot lab expansion check
6. Dynamic air plant cap update
```

### The Builder Hierarchy

Constructors have a strict hierarchy managed by `builder.as`:

| Role | Who | Priority |
|------|-----|----------|
| Commander | Starting unit | Low priority, mostly default tasks |
| Primary T1 | First T1 constructor | T2 lab, air plant, solar, nano |
| Secondary T1 | Second T1 constructor | Assists primary, recycles |
| Primary T2 | First T2 constructor | Gantry, AFUS, nuke, fusion |
| Secondary T2 | Second T2 constructor | Assists primary T2 |
| Freelance T2 | Third+ T2 constructor | Default tasks, mex upgrades |
| Air constructors | T1/T2 air builders | Nano caretakers, remote building |

### The Task Lifecycle

```
Builder requests task → Tech_BuilderAiMakeTask returns IUnitTask
  ↓
Task queued → Builder::AiTaskAdded → Tech_BuilderAiTaskAdded
  ↓
Unit builds → (engine manages construction)
  ↓
Build complete/failed → Builder::AiTaskRemoved → Tech_BuilderAiTaskRemoved
                                                  BlockPlanner::OnTaskRemoved
  ↓
Builder idle → Engine requests new task → cycle repeats
```

---

## Complete Threshold Reference

### T1 Constructor Waterfall (Tech_T1Constructor_AiMakeTask)

| Priority | Building | Metal Gate | Energy Gate | Other Condition |
|----------|----------|-----------|-------------|----------------|
| 1 | T2 Bot Lab | 18 mi | 600 ei | First gate; then income-scaled |
| 2 | T1 Aircraft Plant | 60 mi | 2000 ei | metalCurrent >= 1000 |
| 3 | T1 Energy Converter | < 18 mi | >= 250 ei | energyCurrent >= 90% storage |
| 4 | T1 Solar | — | < 160 ei | Always if under threshold |
| 5 | T1 Nano Caretaker | 10 mi/nano | 200 ei/nano | Factory must exist |
| 6 | T1 Advanced Solar | — | < 600 ei | T2 progress gate |
| 7 | T1 Bot Lab Expansion | 200 mi | — | t1LabCount < 5 |
| 8 | Guard T2 Constructor | — | — | If primary T2 exists |

### T2 Constructor Waterfall (Tech_T2Constructor_AiMakeTask)

| Priority | Building | Metal Gate | Energy Gate | Other Condition |
|----------|----------|-----------|-------------|----------------|
| 1 | Land Gantry | 250 mi/gantry | 6000 ei/gantry | Income-scaled cap |
| 2 | Adv Energy Converter | 18 mi | 1200 ei | energy < 90% storage |
| 3 | Nuclear Silo | 50 mi (rush) / 600 mi (normal) | 2000 ei (rush) / 10000 ei (normal) | NUKE_RUSH flag |
| 4 | Anti-Nuke | 80 mi | 3000 ei | Minimum 1, scales with income |
| 5 | Freelance Mex Assist | — | 500 ei | Freelance T2 exists, nearby |
| 6 | Advanced Fusion | 70 mi | 2000 ei | Nuke suppression check |
| 7 | Fusion Reactor | 20 mi | 700 ei | energyIncome < 2000 |

### Start Caps vs Endgame Caps

| Category | Start Cap | Endgame Cap | Unlock Trigger |
|----------|----------|-------------|---------------|
| T1 combat | 0 (ignored) | 0 (ignored) | Never unlocked |
| T2 combat | 0 | 0 (from cap) but produced via factory | Factory blocks bypass caps |
| T1 bot labs | 1 | 3 | metalIncome >= expansion threshold |
| T2 bot labs | 1 | 3 | metalIncome >= expansion threshold |
| T1 air plants | 0 | 1 | Dynamic air plant scaling |
| T2 air plants | 0 | 1 | Dynamic air plant scaling |
| Gantries | 0 | 4+ | Income-scaled: mi/250, ei/6000 |
| T1 solar | 4 | 4 | Never raised |
| Fusion | 0 | 0 (built via builder logic, not cap) | Builder waterfall |
| AFUS | 0 | 0 (built via builder logic, not cap) | Builder waterfall |
| T1 metal storage | 0 | 1 | First T2 lab built |
| Advanced storage | 0 | 1 | metalIncome >= 100 |
| Land defenses | 0 | 0 | Never unlocked |
| Nuke silos | 20 (NukeLimit) | 20 | Builder waterfall thresholds |

---

## Known Limitations & Opportunities

### What TECH Does Well
- Fast T2 transition (18mi threshold is aggressive)
- Economy compounding (each investment enables the next)
- Cooperative play (T2 constructor donation)
- Nuclear deterrence (anti-nuke) and offense (nuke rush)
- Experimental production via gantry

### What TECH Struggles With
- **No ground defense turrets** — relies entirely on mobile army and allies
- **No T1 combat** — vulnerable to early rushes before T2 bots arrive
- **Single factory type** — only bot labs, no vehicle or hover diversification
- **Fixed building placement** — C++ spiral search scatters buildings (our block planner addresses winds, but other buildings still scatter)
- **No dynamic threat response** — doesn't adjust build order based on what enemy is doing
- **Hard-coded thresholds** — all numbers in `global.as` are static; no learning or adaptation

### Where Our Block Planner Fits

Our block planner improves the "fixed building placement" limitation for wind turbines. Future expansion (Phase 3+) will add:
- Solar blocks
- Factory clusters
- Fusion blocks
- Defense lines

This turns scattered building placement into organized, space-efficient modules.

---

## How It All Fits Together

```
Game Start
    │
    ├── Strategy Dice (T2_RUSH 85%, T3_RUSH 35%, NUKE_RUSH 25%)
    ├── Role Assignment (map config → TECH)
    ├── Start Limits (everything locked down)
    │
    ▼ Minutes 0-5: Opening
    ├── T1 Bot Lab → Opener queue (constructors + scouts)
    ├── Constructors claim mexes, build solars/winds
    ├── Wind Block Planner creates 4x4 grids
    │
    ▼ Minutes 5-10: T2 Transition
    ├── T2 Lab at spawn (recycle T1 lab for metal)
    ├── First T2 constructor → fusion reactor
    ├── T2 factory starts producing fast T2 bots
    │
    ▼ Minutes 10-20: Scaling
    ├── Economy thresholds cascade (storage, expansion, air)
    ├── Gantry construction begins
    ├── Air plant for construction aircraft
    ├── Anti-nuke, possibly nuke silo
    │
    ▼ Minutes 20-30: Late Game
    ├── AFUS chain (massive energy)
    ├── Multiple gantries → experimentals
    ├── Full military operation
    ├── T2 lab recycled for AFUS/nuke metal
    │
    ▼ Minutes 30+: Endgame
    ├── Steady-state production loop
    ├── Nuclear warfare (if thresholds met)
    ├── Income compounds until game ends
    └── Experimentals + nukes = win condition
```

---

*Previous: [04 — Minutes 20-30: Late Game](04_Minutes_20-30_Late_Game.md)*
*Back to: [Index](00_Barb3_Walkthrough_Index.md)*
