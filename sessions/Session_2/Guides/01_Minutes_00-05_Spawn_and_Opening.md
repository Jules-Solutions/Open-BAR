# Barb3 TECH Walkthrough — Minutes 0:00–5:00

> Spawn, role selection, first factory, opener queue, and early economy decisions.

---

## Phase 1: Engine Init (Frame 0)

### What Happens

The engine loads `SkirmishAI.dll` (CircuitAI C++ runtime), which compiles all AngelScript from `init.as`. This triggers:

1. **`Init::AiInit()`** (`init.as:6`) — Returns `SInitInfo` containing:
   - Armor definitions (damage type mappings)
   - Category masks (unit classification)
   - Profile config list: 11 JSON files loaded by C++ (BehaviourJSON, BuildChainJSON, Economy, Factory, block_map, commander, response)
   - If Legion is enabled via mod options, 5 more JSON files are added

2. **`Main::AiMain()`** (`main.as:50`) — Runs once after init:
   - `Maps::registerMaps()` — Registers all map-specific configurations (start positions, roles, unit limits)
   - `ApplyTechStrategyWeights()` — Rolls 3 independent strategy dice:

| Strategy  | Probability | Effect                                                         |
| --------- | ----------- | -------------------------------------------------------------- |
| T2_RUSH   | 85%         | Lowers bot lab expansion threshold from 200 → 100 metal income |
| T3_RUSH   | 35%         | Affects gantry build timing (checked later)                    |
| NUKE_RUSH | 25%         | Enables early nuke silo at 50 metal income instead of 600      |

   - Tags T2 factories with `Factory::Attr::T2` and gantries with `Factory::Attr::T3`
   - Calls `ApplyProfileSettings()` (currently empty for experimental_balanced)

**Important:** Map resolution and role selection are **deferred** — they don't happen until the first factory request.

> **Source:** `init.as:6`, `main.as:50`, `main.as:30`

---

## Phase 2: Commander Spawns & Role Selection (0–5 seconds)

### The Deferred Setup

When the engine asks "what factory should this AI build?", it calls `Factory::AiGetFactoryToBuild()` (`setup.as:29`). On the **first call** (`isStart=true`), this triggers the deferred setup chain:

1. **`Setup::setupMap(pos)`** (`setup.as:47-49`) — Now that we know the commander's position:
   - Resolves map name from engine
   - Finds the nearest registered `StartSpot` for this position
   - Determines `LandLocked` status (is spawn surrounded by water?)
   - Loads map-specific unit limits if configured
   - Merges map limits with role limits into `Global::Map::MergedUnitLimits`

2. **Role matching** — The ProfileController iterates registered roles (FRONT, AIR, TECH, SEA, FRONT_TECH, HOVER_SEA) and calls each role's `RoleMatch()` function. For maps with configured start spots, the preferred role comes from the map config.

3. **`Tech_RoleMatch()`** (`tech.as:1420`) — Simply checks: `preferredMapRole == AiRole::TECH`. If the map says this start position should be TECH, it returns true.

4. **`Tech_Init()`** (`tech.as:63`) — Role initialization:
   - Sets `allyRange = 1000.0f` (how far to look for allies)
   - Sets military quotas: `scout=0`, `attack=1.0` (power threshold), `raid.min=30`, `raid.avg=30`
   - Calls `Tech_ApplyStartLimits()` — the big one

### Start Limits: What TECH Locks Down

`Tech_ApplyStartLimits()` (`tech.as:94`) applies aggressive caps:

| Category | Cap | Meaning |
|----------|-----|---------|
| T1 combat units | 0 | No raiders, no tanks, no artillery |
| T2 combat units | 0 | Nothing until economy scaling unlocks them |
| Rez bots | 0 | No resurrection bots at start |
| Fast-assist bots | 0 | No Finks/Grims at start |
| T1 bot labs | 1 | Only one bot lab |
| T2 bot labs | 1 | Only one T2 lab allowed |
| T1 vehicle plants | 0 | No vehicles |
| T2 vehicle plants | 0 | No vehicles |
| Hover plants | 0 | No hover |
| T1 aircraft plants | 0 | No air at start |
| T2 aircraft plants | 0 | No air at start |
| T1/T2 shipyards | 0 | No navy at start |
| T1 solar | 4 | Max 4 solar collectors |
| Fusion reactors | 0 | No fusion at start |
| Advanced fusion | 0 | No AFUS at start |
| Land defenses | 0 | No turrets, no walls |
| T1 air combat | 0 | No fighters/bombers |
| T2 air combat | 0 | No fighters/bombers |
| T1 metal storage | 0 | No storage (unlocked when first T2 lab built) |
| Advanced storage | 0 | No advanced storage (unlocked at 100 metal income) |

Additionally:
- All T1 combat units are **ignored** (`SetIgnoreFor = true`) — the AI won't even consider building them
- All T1/T2 land labs and air plants are tagged as `mainRole = "support"` — they stay near base

> **Source:** `tech.as:94-196`

### Factory Selection

`Tech_SelectFactoryHandler()` (`tech.as:600`) picks the starting factory:
- Uses `FactoryHelpers::SelectStartFactoryForRole(TECH, side)` which checks map-specific factory weights
- For most maps, TECH starts with a **T1 bot lab** (armlab/corlab/leglab)

> **Source:** `tech.as:600-615`

---

## Phase 3: First Factory & Opener Queue (0:05–1:30)

### Factory Registered

When the T1 bot lab finishes construction, `Factory::AiUnitAdded()` (`factory.as:150`) tracks it as `primaryT1BotLab`.

### The Opener System

The C++ engine has a built-in opener system defined in the Factory JSON configs. Each factory has probabilistic build queues:

```
ArmadaFactory.json → armlab opener (90% chance):
  constructor → scout → raider → constructor → raider × 4
```

The opener is a **one-time sequence**. Once it completes, the factory switches to `Tech_FactoryAiMakeTask()` for all future production decisions.

### What the Opener Produces

For TECH role, the opener typically produces:
1. **T1 constructor bot** (armck) — becomes `primaryT1BotConstructor`
2. **Scout** (armflea/Tick) — provides early vision
3. **Raider** (armham/Hammer) — early defense/harassment
4. **Second constructor** (armck) — becomes `secondaryT1BotConstructor`
5. **More raiders** (4x) — early map control

Note: TECH has all T1 combat unit caps at 0 and `SetIgnoreFor=true`, BUT the opener bypasses these caps because it's driven by the C++ factory system, not AngelScript caps. The opener units still get built.

> **Source:** `types/opener.as`, `config/experimental_balanced/ArmadaFactory.json`

---

## Phase 4: Early Economy — The Builder Decision Tree (1:30–5:00)

### How Builder Decisions Work

Every time a constructor finishes a task or becomes idle, the engine calls `Builder::AiMakeTask()` → `Tech_BuilderAiMakeTask()` (`tech.as:782`).

### The Full Waterfall (Tech_BuilderAiMakeTask)

```
1. Get defaultTask from C++ (DefaultMakeTask)
2. If defaultTask is MEX/MEXUP/GEO/GEOUP → return it immediately (always prioritize extractors)
3. WIND BLOCK INTERCEPTION (our addition):
   - If metalIncome > 5 AND (energyIncome < 200 OR stalling) → place wind in grid
4. Get economy snapshot (10-second rolling minimums)
5. Is this the Commander? → Tech_Commander_AiMakeTask (recycle check, then default)
6. Is this a T1 constructor?
   a. Primary T1 → Tech_T1Constructor_AiMakeTask (the big decision tree)
   b. Secondary T1 → recycle check, then assist primary if income < 80
   c. Other T1 → recycle check, then air constructor nano logic, then default
7. Is this a T2 constructor?
   a. Primary T2 → Tech_T2Constructor_AiMakeTask (endgame pipeline)
   b. Secondary T2 → assist primary if income < 160
   c. Freelance T2 → default tasks
8. Return defaultTask (fallback)
```

> **Source:** `tech.as:782-916`

### What the Primary T1 Constructor Does (Minutes 1:30–5:00)

`Tech_T1Constructor_AiMakeTask()` (`tech.as:1023`) runs this waterfall:

1. **T2 bot lab check** — Can we afford a T2 lab?
   - First lab gate: `metalIncome >= 18.0` AND `energyIncome >= 600.0`
   - At minute 3-4 with a few mexes + winds, typically NOT yet met
   - **Skipped at this stage**

2. **T1 aircraft plant** — Can we build air?
   - Needs `metalIncome >= 60` AND `energyIncome >= 2000` AND `metalCurrent >= 1000`
   - Way too early. **Skipped**

3. **T1 energy converter** — Should we convert energy to metal?
   - While `metalIncome < 18` AND `energyIncome >= 250` AND `energyCurrent >= 90% storage`
   - If energy is overflowing but metal is scarce, build a converter. **Sometimes triggers around minute 3-4**

4. **T1 solar** — Need more energy?
   - While `energyIncome < 160` (SolarEnergyIncomeMinimum)
   - **Triggers early** — constructor builds solars until 160 energy income

5. **T1 nano caretaker** — Speed up factory production?
   - If there's a preferred factory AND income supports it (energyPerNano=200, metalPerNano=10)
   - Placed near the factory. **Often triggers around minute 3-4**

6. **T1 advanced solar** — Bigger energy?
   - While `energyIncome < 600` (AdvancedSolarEnergyIncomeMinimum) and not gated by T2 progress
   - **May trigger late in this window**

7. **T1 bot lab expansion** — Need more labs?
   - `metalIncome >= 200` — way too early. **Skipped**

8. **Guard T2 constructor** — If primary T2 exists, assist it
   - No T2 constructor yet. **Skipped**

### Meanwhile: The Default C++ Task

When nothing in the waterfall triggers, `defaultTask` from C++ handles:
- **Metal extractors** — C++ knows optimal mex spots and sends constructors to claim them
- **Reclaiming** — picking up nearby wrecks for resources
- **Patrolling** — moving to useful positions

### Wind Block Interception (Our Addition)

At step 3 of the main waterfall, our `BlockPlanner::ShouldInterceptForWind()` checks:
- `metalIncome > 5.0` (not too early)
- `energyIncome < 200.0` OR energy is stalling
- Wind def is available for current faction
- Block capacity exists (< MAX_ACTIVE_BLOCKS)

If triggered, it places wind turbines in a 4x4 grid (32-elmo spacing, shake=0) instead of letting C++ scatter them randomly. This is the behavior you saw in the test — tighter wind clusters near the base.

> **Source:** `tech.as:797-809`, `helpers/block_planner.as`

---

## Economy State at Minute 5

| Resource | Typical Value | Source |
|----------|--------------|--------|
| Metal income | ~15–20 | 4-6 mexes |
| Energy income | ~400–800 | Winds (block clusters) + solars (up to 4) |
| Metal stored | ~200–500 | Fluctuating |
| Constructors | 2 T1 (primary + secondary) | From opener |
| Factories | 1 T1 bot lab | Starting factory |
| Combat units | 1 scout + 4-5 raiders | From opener only |

### What's About to Happen

The economy is approaching T2 lab thresholds (18 metal, 600 energy). The next phase is the T2 transition — the defining moment of the TECH role.

---

*Next: [02 — Minutes 5-10: T2 Transition](02_Minutes_05-10_T2_Transition.md)*
