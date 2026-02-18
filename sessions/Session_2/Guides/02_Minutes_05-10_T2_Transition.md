# Barb3 TECH Walkthrough — Minutes 5:00–10:00

> T2 lab construction, first T2 constructor, fusion reactor, and the recycling gambit.

---

## Phase 5: T2 Lab Decision (around 4:00–6:00)

### The Gate

The primary T1 constructor's waterfall (`Tech_T1Constructor_AiMakeTask`, `tech.as:1023`) checks T2 lab eligibility first:

```
ShouldBuildT2BotLabFromIncomeWithFirstGate():
  First lab gate:
    metalIncome >= 18.0  (MinimumMetalIncomeForT2Lab)
    energyIncome >= 600.0 (MinimumEnergyIncomeForT2Lab)
  Additional labs (later):
    floor(mi / 100) or floor(ei / 1000), whichever is lower
    Max: MaxT2BotLabs (starts at 1)
```

At ~5 minutes with wind blocks + mexes, you'll typically have ~20 metal income and ~800 energy. Both thresholds met.

### Placement

The first T2 lab is always anchored at `Global::Map::StartPos` — the commander's spawn point (`tech.as:1055`). Additional labs (if economy permits later) anchor at the commander's current position.

```angelscript
if (t2LabCount == 0) {
    anchorPos = Global::Map::StartPos;  // First lab: at spawn
} else {
    anchorPos = com.GetPos(ai.frame);   // Later labs: follow commander
}
```

The enqueue uses `shake = SQUARE_SIZE * 20` (160 elmos) — moderate randomization around the anchor.

> **Source:** `tech.as:1038-1070`

---

## Phase 6: The Recycling Gambit (5:00–6:30)

### What Is Recycling?

While the T2 lab is being built, metal reserves may drop. The `Recycle()` function (`tech.as:1345`) checks if the AI should **reclaim its own T1 bot lab** to feed metal into T2 lab construction.

### Recycle Conditions

```
IF T2 lab is queued (being built)
AND metal.current < 600
AND T1 constructor count >= 3
AND metalIncome <= 45
AND no Advanced Fusion built yet
THEN → reclaim primary T1 bot lab
```

This is a deliberate sacrifice. The T1 lab has served its purpose (produced constructors via opener). TECH treats it as scaffolding — reclaim it, use the metal to finish the T2 lab faster.

### What Gets Reclaimed

- `Factory::primaryT1BotLab` is reclaimed via `TaskB::Reclaim(Priority::NORMAL, lab, 180 * SECOND)`
- The `primaryT1BotLab` pointer is immediately set to `null` to avoid dangling references
- This frees up ~400 metal (the lab's cost) toward T2 lab construction

### Safety Gates

The recycle has several safety valves:
- Won't fire if an Advanced Fusion exists (late game, metal isn't scarce)
- Won't fire if metal income > 45 (economy is healthy enough)
- Won't fire if fewer than 3 T1 constructors exist (need workforce)

> **Source:** `tech.as:1345-1412`

---

## Phase 7: T2 Lab Completes (around 6:00–7:00)

### Immediate Reactions

When the T2 bot lab finishes, several things trigger simultaneously:

#### 1. Factory Assist Forced ON

`Tech_EconomyUpdate()` (`tech.as:227`) runs every economy tick. When it detects:

```angelscript
if (hasT2Lab && t2ConstructionBotCount < 1) {
    aiFactoryMgr.isAssistRequired = true;
}
```

This forces **all nearby constructors to assist the T2 lab** — rushing the first T2 constructor out as fast as possible. The flag stays on until a T2 constructor is produced.

> **Source:** `tech.as:241-244`

#### 2. T1 Metal Storage Unlocked

`Tech_FactoryAiUnitAdded()` (`tech.as:654`) detects the first T2 lab and raises the T1 metal storage cap from 0 to 1. This prevents metal overflow during the expensive T2 phase (constructors cost more, build tasks use more metal).

```angelscript
if (!hasRaisedT1MetalStorageCap && UnitHelpers::IsT2BotLab(uname) && t2LabCount <= 1) {
    UnitHelpers::BatchApplyUnitCaps(t1Metal, 1);
    hasRaisedT1MetalStorageCap = true;
}
```

> **Source:** `tech.as:664-683`

#### 3. First T2 Constructor Queued

`Tech_FactoryAiMakeTask()` (`tech.as:384`) checks if T2 constructor count < `MinimumT2ConstructorBots` (default: 1). It's 0, so:

```angelscript
// T2 bot lab: recruit a T2 constructor at HIGH priority
array<string> t2BotCtors = UnitHelpers::GetT2BotConstructors(side);
return aiFactoryMgr.Enqueue(
    TaskS::Recruit(RecruitType::BUILDPOWER, Priority::HIGH, t2Ctor, pos, 64.f)
);
```

For Armada this produces `armack` (Advanced Construction Bot).

> **Source:** `tech.as:446-460`

---

## Phase 8: First T2 Constructor (around 7:00)

### Registration

When the T2 constructor pops out, `Builder::AiUnitAdded()` registers it as `Builder::primaryT2BotConstructor`. This is the AI's most important unit for the next 10 minutes.

### The Donation Counter

`Tech_BuilderAiUnitAdded()` (`tech.as:763`) tracks every T2 constructor ever built:

```angelscript
if (Donate::IsT2Constructor(d)) {
    Donate::T2CtorEverBuilt += 1;
    if (!Donate::DonatedThird && Donate::T2CtorEverBuilt == 3) {
        Donate::TryDonate(unit);  // Give 3rd T2 ctor to team leader
    }
}
```

The 3rd T2 constructor ever built gets **donated to the allied team leader** — a cooperative behavior where TECH shares its tech advantage.

> **Source:** `tech.as:763-778`

---

## Phase 9: T2 Constructor Decision Tree (7:00–10:00)

### The T2 Waterfall

Once the primary T2 constructor is idle, `Tech_T2Constructor_AiMakeTask()` (`tech.as:1196`) takes over. This is the **endgame pipeline** even though it's only minute 7:

#### 1. Gantry Check (SKIPPED at this stage)

```
ShouldBuildGantry():
  metalIncome >= MetalIncomePerGantry (250.0)
  energyIncome >= EnergyIncomePerGantry (6000.0)
```

At minute 7 with ~25 metal / ~1000 energy: way too early. Skipped.

> **Source:** `tech.as:1210-1221`

#### 2. Advanced Energy Converter (SOMETIMES triggers)

```
ShouldBuildT2EnergyConverter():
  metalIncome >= 18.0 (MinimumMetalIncomeForAdvConverter)
  energyIncome >= 1200.0 (MinimumEnergyIncomeForAdvConverter)
  energy current < 90% storage (energy is not overflowing)
```

If the T2 lab construction drained energy reserves, this may trigger. Builds an advanced converter (Moho Maker) to stabilize energy-to-metal conversion.

> **Source:** `tech.as:1223-1234`

#### 3. Nuke Silo Check (USUALLY SKIPPED)

```
ShouldBuildNuclearSilo():
  Rush mode (NUKE_RUSH active):
    metalIncome >= 50.0 AND energyIncome >= 2000.0
    Build up to NukeRush (1) silos
  Normal mode:
    metalIncome >= 600.0 AND energyIncome >= 10000.0
```

If you rolled NUKE_RUSH (25% chance) AND economy hit 50mi by minute 8-9, this triggers early. Very aggressive — the T2 constructor starts a nuke silo instead of fusion. Otherwise skipped.

> **Source:** `tech.as:1237-1253`

#### 4. Anti-Nuke Check (SKIPPED)

```
metalIncome >= 80.0 AND energyIncome >= 3000.0
Minimum count: 1
```

Not enough income yet. Skipped.

> **Source:** `tech.as:1256-1273`

#### 5. Freelance Mex Assist (SOMETIMES triggers)

If there's a freelance T2 constructor doing mex upgrades nearby and energy income is sufficient (>500), the primary T2 constructor may guard it to help with mex upgrades.

> **Source:** `tech.as:1275-1285`

#### 6. Advanced Fusion Reactor (SKIPPED)

```
metalIncome >= 70.0 AND energyIncome >= 2000.0
```

Not enough income yet. Skipped.

> **Source:** `tech.as:1287-1314`

#### 7. Fusion Reactor (OFTEN triggers around minute 8-9)

```
ShouldBuildFusionReactor():
  metalIncome >= 20.0 (MinimumMetalIncomeForFUS)
  energyIncome >= 700.0 (MinimumEnergyIncomeForFUS)
  energyIncome < 2000.0 (MaxEnergyIncomeForFUS — stops building fusion once energy is high)
  energy current < 90% storage (not overflowing)
```

This is typically the **first major T2 construction**. The fusion reactor provides a big energy income boost (~200-1000 energy depending on map wind speed), which unlocks further T2 buildings.

> **Source:** `tech.as:1316-1327`

#### 8. Default Fallback

If nothing triggers, the T2 constructor falls through to `DefaultMakeTask` — C++ handles mex upgrades, general construction, and reclaiming.

> **Source:** `tech.as:1342`

---

## Meanwhile: Factory Production (7:00–10:00)

### T2 Factory Waterfall

`Tech_FactoryAiMakeTask()` runs every time the T2 lab needs a new production order:

#### 1. Maintain T2 Constructor Minimum

If T2 constructors < `MinimumT2ConstructorBots` (1), produce another. This ensures the primary always has a replacement if destroyed.

#### 2. Fast-Assist Bots

```angelscript
int assistCap = 5 * int(metalIncome / 45.0f);
if (fastAssist.length() > 0 && haveAssist < assistCap && metalCurrent > 2000.0f) {
    // Enqueue fast-assist bot (Fink/Grim/etc.)
}
```

Small fast bots that assist constructors, speeding up builds. Only triggers when metal reserves are high (>2000).

> **Source:** `tech.as:462-496`

#### 3. T2 Combat Units (THE FIRST MILITARY)

The strategy bitmask determines the income gate:

```angelscript
const float botLabGate = isEarlyBotLabExpansionEnabled  // T2_RUSH active?
    ? MetalIncomeThresholdForEarlyBotLabExpansion  // 100.0
    : MetalIncomeThresholdForBotLabExpansion;       // 200.0
```

Once metal income exceeds the gate, the T2 lab starts producing **blocks of 10 fast T2 bots**:
- Armada: `armfast` (Sprinter)
- Cortex: `corpyro` (Fiend)
- Legion: `legstr` (Hoplite)

On land-locked maps, it switches to amphibious units (Platypus/Duck/Telchine).

With T2_RUSH (85% likely), the gate is 100 metal income — combat production can start as early as minute 8-9.

> **Source:** `tech.as:565-595`

---

## Economy Scaling: Tech_EconomyUpdate

Every economy tick, `Tech_EconomyUpdate()` (`tech.as:227`) recalculates dynamic caps. By minute 10, these thresholds may start activating:

| Check | Threshold | What Unlocks |
|-------|-----------|-------------|
| Advanced storage | metalIncome >= 100 | Advanced energy/metal storage caps raised to 1 |
| Bot lab expansion | metalIncome >= 200 (or 100 with T2_RUSH) | T1 bot labs raised to 3, factories become `mainRole=static` |
| Dynamic gantry caps | metalIncome/250, energyIncome/6000 | Gantry count scales with income |
| T2 air plant caps | Formula-based | T2 air plants scale with income |
| Builder caps | `Tech_IncomeBuilderLimits()` | T1/T2 builder, rez bot, fast-assist caps all scale |

### Builder Cap Formulas

```
T1 builder cap = EconomyHelpers::CalculateT1BuilderCap(metalIncome, min=5, max=MaxT1Builders)
T2 builder cap = EconomyHelpers::CalculateT2BuilderCap(metalIncome, min=3, max=MaxT2Builders)
Rez bot cap = max(1, floor(metalIncome / 20))    [if >= 5, otherwise 1]
Fast-assist cap = 5 * floor(metalIncome / 45)
```

> **Source:** `tech.as:227-376`, `tech.as:951-996`

---

## What TECH Is NOT Doing at Minute 10

| Category | Status | Why |
|----------|--------|-----|
| Ground defense turrets | Cap = 0 | `GetAllLandDefences()` capped to 0 at start |
| T1 combat units | Ignored | `SetIgnoreFor(t1Units, true)` |
| Attacking | Disabled | `Tech_MilitaryAiMakeTask` returns null if metalIncome < 50 |
| Vehicle/hover plants | Cap = 0 | Explicitly capped at start |
| Defense turrets | Only via C++ | `Tech_AiMakeDefence` delegates to `DefaultMakeDefence` only if metalIncome < 300 AND threat detected |

---

## Strategy Bitmask Effects at This Stage

| Strategy | If Active | Visible Effect by Minute 10 |
|----------|----------|---------------------------|
| T2_RUSH (85%) | Yes | Bot lab expansion gate lowered to 100mi → earlier T2 combat production |
| T3_RUSH (35%) | Not yet visible | Will affect gantry timing later |
| NUKE_RUSH (25%) | Sometimes | If 50+ metal income, T2 ctor builds nuke silo instead of fusion |

---

## Economy State at Minute 10

| Resource | Typical Value | Source |
|----------|--------------|--------|
| Metal income | ~25–35 | 6-10 mexes + converters |
| Energy income | ~1000–1500 | Wind blocks + solars + fusion |
| Metal stored | ~300–800 | Fluctuating |
| Constructors | 2 T1 + 1-2 T2 | Primary T2 is the star |
| Factories | 0-1 T1 lab (may be recycled) + 1 T2 lab | T2 lab is primary |
| Military | 5-10 fast T2 bots (if T2_RUSH) | First real combat units |
| Key buildings | 1 fusion reactor, possibly 1 advanced converter | Energy infrastructure |

---

## Summary: The T2 Transition

```
Minute 5:  T2 lab starts building at spawn
Minute 5.5: T1 lab recycled for metal (if reserves low)
Minute 6.5: T2 lab completes, factory assist ON
Minute 7:   First T2 constructor produced
Minute 7.5: T2 ctor checks gantry (too early), starts converter or fusion
Minute 8:   Second T2 constructor if minimum requires it
Minute 8.5: T2 factory starts producing fast T2 bots
Minute 9:   Fusion reactor completes, energy income jumps
Minute 10:  Economy scaling kicks in
```

TECH at minute 10 is a **pure economy machine** — no defenses, minimal military, maximum infrastructure investment. It's betting that teammates (FRONT/AIR) protect it while it races to T3.

---

*Previous: [01 — Minutes 0-5: Spawn & Opening](01_Minutes_00-05_Spawn_and_Opening.md)*
*Next: [03 — Minutes 10-20: Scaling & First Military](03_Minutes_10-20_Scaling_and_Military.md)*
