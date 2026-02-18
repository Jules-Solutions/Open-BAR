# Barb3 TECH Walkthrough — Minutes 10:00–20:00

> Economy scaling unlocks, air plants, gantry approach, nuclear decisions, and first real military.

---

## Overview

Minutes 10-20 is the **inflection point**. TECH transitions from pure economy to mixed economy + military. Several threshold cascades fire as income grows, unlocking capabilities that were capped to 0 at game start.

---

## Phase 10: Economy Threshold Cascades (10:00–15:00)

### Advanced Storage Unlock

When `metalIncome >= 100`:

```angelscript
if (!hasUnlockedAdvancedStorage && metalIncome >= 100.0f) {
    UnitHelpers::BatchApplyUnitCaps(advE, 1);  // Advanced energy storage
    UnitHelpers::BatchApplyUnitCaps(advM, 1);  // Advanced metal storage
    hasUnlockedAdvancedStorage = true;
}
```

This unlocks 1 advanced energy storage and 1 advanced metal storage. These double the AI's resource buffer, smoothing out income spikes.

> **Source:** `tech.as:258-271`

### Bot Lab Expansion Threshold

When `metalIncome >= MetalIncomeThresholdForBotLabExpansion` (200, or 100 with T2_RUSH):

Several things happen simultaneously:

1. **T1 bot lab cap raised to 3** — `BatchApplyUnitCaps(GetAllT1BotLabs(), 3)`
2. **All land factories get `mainRole=static`** — factories can now be built at the front line, not just near base
3. **T1 bot scouts uncapped** — `armflea`/`corak`/`leggob` cap raised to 100
4. **Fast T2 bots uncapped** — `armfast`/`corpyro`/`legstr` cap raised to 100
5. **MaxT1Builders raised to 25** — allows many more T1 constructors
6. **MaxT2BotLabs raised to 3** — allows up to 3 T2 bot labs

This is a **paradigm shift** — the AI goes from conservative base-builder to aggressive expander.

> **Source:** `tech.as:301-340`

### Dynamic Gantry Caps

Every economy tick:

```angelscript
int allowedGantry = EconomyHelpers::AllowedGantryCountFromIncome(
    metalIncome,               // current mi
    energyIncome,              // current ei
    MetalIncomePerGantry,      // 250.0
    EnergyIncomePerGantry      // 6000.0
);
```

Formula: `min(floor(mi / 250), floor(ei / 6000))`. At 250mi + 6000ei, first gantry becomes available.

If `allowedGantry > 1`, gantry caps are raised for all factions and factories get repositioned (no longer just support/base).

> **Source:** `tech.as:274-296`

### Dynamic Air Plant Caps

```angelscript
int allowedT2Air = EconomyHelpers::AllowedT2AircraftPlantCountFromIncome(
    metalIncome, energyIncome,
    RequiredMetalIncomeForT2AircraftPlant,   // 200.0
    RequiredEnergyIncomeForT2AircraftPlant   // 2000.0
);
if (allowedT2Air > 0) { allowedT1Air = 1; }  // T1 air unlocked as stepping stone
```

T2 air becomes available at 200mi + 2000ei. T1 air unlocked as a prerequisite (1 plant max).

> **Source:** `tech.as:342-375`

---

## Phase 11: T1 Constructor Enters New Phase (10:00–15:00)

The primary T1 constructor's waterfall now reaches items that were previously blocked:

### T1 Aircraft Plant

```
ShouldBuildT1AircraftPlant():
  metalIncome >= 60.0 (RequiredMetalIncomeForAirPlant)
  energyIncome >= 2000.0 (RequiredEnergyIncomeForAirPlant)
  metalCurrent >= 1000.0 (RequiredMetalCurrentForAirPlant)
  t1AirPlants < MaxT1AircraftPlants (1)
```

Around minute 12-15, when energy income hits 2000 from fusion + winds, the T1 constructor builds an aircraft plant. This enables:
- T1 construction aircraft (scouts/builders that fly)
- Air scouting for map vision
- Stepping stone to T2 air

> **Source:** `tech.as:1075-1098`

### T1 Bot Lab Expansion

```
if (metalIncome >= MetalIncomeThresholdForBotLabExpansion) {
    if (t1LabCount < 5) {
        // Build another T1 bot lab
    }
}
```

If the T1 lab was recycled earlier, the constructor may rebuild one (or more). Additional T1 labs produce more constructors and scouts, accelerating the economy further.

> **Source:** `tech.as:1160-1168`

### Guard T2 Constructor

If no specific building is needed but a primary T2 constructor exists:

```angelscript
if (Builder::primaryT2BotConstructor !is null) {
    return GuardHelpers::AssignWorkerGuard(u, Builder::primaryT2BotConstructor, Priority::HIGH, true, 120 * SECOND);
}
```

The T1 constructor assists the T2 constructor — doubling its build speed on whatever it's working on.

> **Source:** `tech.as:1170-1172`

---

## Phase 12: T2 Constructor — Building Toward T3 (10:00–20:00)

The primary T2 constructor's waterfall (`Tech_T2Constructor_AiMakeTask`) now enters its real progression:

### Gantry (First One: around 15-20 minutes)

```
ShouldBuildGantry():
  metalIncome >= 250.0 per gantry (MetalIncomePerGantry)
  energyIncome >= 6000.0 per gantry (EnergyIncomePerGantry)
```

The gantry (experimental superfactory) is TECH's crown jewel. At ~250mi + ~6000ei (achievable around minute 15-20 with fusion + mex upgrades), the T2 constructor starts building one.

For the first gantry, placement uses `Builder::EnqueueLandGantry()` with default positioning logic (C++ picks a safe spot near base).

> **Source:** `tech.as:1210-1221`

### Advanced Energy Converter

Continues building converters when:
```
metalIncome >= 18.0 AND energyIncome >= 1200.0 AND energy < 90% storage
```

Converters help when energy overflows but metal is scarce — converts excess energy to metal.

> **Source:** `tech.as:1223-1234`

### Nuclear Silo (If NUKE_RUSH)

With NUKE_RUSH active (25% of games):
```
Rush mode: metalIncome >= 50.0 AND energyIncome >= 2000.0
           Build up to NukeRush (1) silos
```

If NUKE_RUSH was rolled AND economy hit 50mi, the nuke silo may have started around minute 8-10. By minute 15-20, it could be complete and stockpiling missiles. This is the aggressive TECH play.

Without NUKE_RUSH, the regular threshold is 600mi + 10000ei — very late game.

> **Source:** `tech.as:1237-1253`

### Anti-Nuke

```
metalIncome >= 80.0 AND energyIncome >= 3000.0
Minimum count: 1
Additional: floor(metalIncome / 80) allowed
```

Around minute 12-15, when income supports it, TECH builds its first anti-nuke. This is defensive — protecting against enemy nuclear threats.

> **Source:** `tech.as:1256-1273`

### Advanced Fusion Reactor

```
ShouldBuildAdvancedFusionReactor():
  metalIncome >= 70.0 (MinimumMetalIncomeForAFUS)
  energyIncome >= 2000.0 (MinimumEnergyIncomeForAFUS)
  energy < 90% storage
  If NUKE_RUSH: only build if nuke silo count > 0 (nuke takes priority)
  If nuke silo is queued AND AFUS < 2: suppress AFUS (don't compete for resources)
```

The AFUS provides massive energy (5000+). But there's a deliberate tension with nuke silos — if a nuke is being built, the AI suppresses AFUS construction to avoid resource competition. Once the nuke is done, AFUS resumes.

> **Source:** `tech.as:1287-1314`

### Regular Fusion Reactor

```
metalIncome >= 20.0 AND energyIncome >= 700.0 AND energyIncome < 2000.0
energy < 90% storage
```

Continues building fusion reactors as long as energy income is below 2000. Once above 2000, AFUS takes over.

> **Source:** `tech.as:1316-1327`

---

## Phase 13: Factory Production Evolves (10:00–20:00)

### T2 Bot Lab Production

With income above the bot lab gate, the factory maintains a steady cycle:

1. **Maintain T2 constructor minimum** — always replace if destroyed
2. **Fast-assist bots** — scale with income: `cap = 5 * floor(mi / 45)`
3. **Blocks of 10 fast T2 bots** — continuous military production
4. **Default** — C++ picks other useful units from JSON factory configs

### T1 Aircraft Plant Production

Once built, `Tech_FactoryAiMakeTask` handles the T1 air plant:

```angelscript
// T1 air ctor below target → enqueue construction aircraft
if (Factory::primaryT1AirPlant !is null && u.id == Factory::primaryT1AirPlant.id
    && t1AirCtorCount < 100) {
    // Enqueue T1 air constructor (armca/corca/legca)
}
```

The T1 air plant primarily produces **construction aircraft** — flying builders that can reach remote mex spots and assist construction anywhere on the map.

> **Source:** `tech.as:498-531`

### Gantry Production (If Built)

```angelscript
if (UnitHelpers::IsGantryLab(facDef.GetName())) {
    if (metalIncome > 200.0f) {
        // Queue 5 signature experimentals at HIGH priority
        IUnitTask@ tSig = Factory::EnqueueGantrySignatureBatch(u, side, 5, Priority::HIGH);
    }
    return aiFactoryMgr.DefaultMakeTask(u);  // C++ picks heavy/super units
}
```

Once a gantry exists, it produces experimental units. If metal income > 200, it queues batches of 5 signature experimentals. Otherwise, C++ default picks appropriate heavy units.

> **Source:** `tech.as:416-425`

---

## Phase 14: Military Awakens (10:00–20:00)

### Attack Gate

`Tech_MilitaryAiMakeTask()` (`tech.as:728`):

```angelscript
if (metalIncome < 50.0f) {
    return null;  // No military orders below 50 mi
}
return aiMilitaryMgr.DefaultMakeTask(u);
```

Once metal income exceeds 50, combat units start receiving **actual attack orders** from the C++ military manager. Before this, they just sit around.

### Defense Trigger

`Tech_AiMakeDefence()` (`tech.as:743`):

```angelscript
if (metalIncome < 300.0f) {
    aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
}
```

Defense structures are built via C++ `DefaultMakeDefence` when:
- The engine detects an enemy threat cluster
- AND metal income < 300

Note: TECH has `GetAllLandDefences()` capped to 0 at start. But C++ `DefaultMakeDefence` can still place AA and LRPC (long-range plasma cannon) — those aren't in the "land defenses" category. Ground turrets remain at cap 0.

> **Source:** `tech.as:728-755`

### What Military Looks Like at Minute 20

- 10-30 fast T2 bots (Sprinters/Fiends/Hoplites) from factory blocks
- Some T1 units surviving from opener
- Possibly first experimental unit from gantry
- C++ military manager directing attacks when power threshold met

---

## The Secondary T2 Constructor

If a second T2 constructor was produced:

```angelscript
// Secondary T2: assist primary while income is below threshold
if (EconomyHelpers::ShouldSecondaryT2AssistPrimary(
    metalIncome, SecondaryT2AssistMetalIncomeMax /*160.0*/, hasPrimary
)) {
    return GuardHelpers::AssignWorkerGuard(u, Builder::primaryT2BotConstructor, ...);
}
```

Below 160 metal income, the secondary T2 constructor **guards the primary** — doubling build speed on critical structures (gantry, fusion, nuke). Above 160mi, it gets its own default tasks.

> **Source:** `tech.as:1330-1339`

---

## The Donation System

When the 3rd T2 constructor is ever produced:

```angelscript
if (!Donate::DonatedThird && Donate::T2CtorEverBuilt == 3) {
    Donate::DonatedThird = true;
    Donate::TryDonate(unit);  // Transfer to allied team leader
}
```

TECH donates its 3rd T2 constructor to the team's lead player. This is a cooperative behavior — TECH shares its advanced tech with allies who may have better military positioning.

> **Source:** `tech.as:763-778`

---

## Economy State at Minute 20

| Resource | Typical Value | Source |
|----------|--------------|--------|
| Metal income | ~60–150 | 10-15 mexes + some T2 mex upgrades + converters |
| Energy income | ~2000–5000 | Fusion + winds + solars + maybe AFUS |
| Constructors | 2-3 T1 + 2-3 T2 + air constructors | Expanding workforce |
| Factories | 1-2 T2 bot labs + 1 air plant + possibly gantry | Full production |
| Military | 15-40 fast T2 bots + experimental start | Growing army |
| Key buildings | 1-2 fusion, possibly AFUS, possibly nuke silo, anti-nuke | Major infrastructure |

---

## Summary: Minutes 10-20

```
Minute 10:   Economy scaling kicks in, caps start rising
Minute 11:   Advanced storage unlocked (if 100mi)
Minute 12:   Bot lab expansion (if 100/200mi), factories go to front
Minute 13:   T1 aircraft plant built (if 60mi + 2000ei)
Minute 14:   Anti-nuke started (if 80mi + 3000ei)
Minute 15:   AFUS or fusion continues, energy income climbing
Minute 16:   Military attack gate hit (50mi), combat units get orders
Minute 17:   Gantry approaches (need 250mi + 6000ei)
Minute 18:   First experimental unit possible
Minute 19:   T2 air plant may be unlocked (200mi + 2000ei)
Minute 20:   Full mixed economy + military operation
```

---

*Previous: [02 — Minutes 5-10: T2 Transition](02_Minutes_05-10_T2_Transition.md)*
*Next: [04 — Minutes 20-30: Late Game](04_Minutes_20-30_Late_Game.md)*
