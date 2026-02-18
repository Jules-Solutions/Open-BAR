# Barb3 TECH Walkthrough — Minutes 20:00–30:00

> Advanced fusion, multiple gantries, T3 experimentals, full military machine, and T2 lab recycling.

---

## Overview

Minutes 20-30 is TECH's **power spike**. The economy compounds rapidly — each AFUS and mex upgrade multiplies income further, which unlocks more gantries, which produce experimentals that win fights, which secures more territory for more mexes. The positive feedback loop is TECH's win condition.

---

## Phase 15: Advanced Fusion Reactor Chain (20:00–25:00)

### AFUS Construction

By minute 20, income typically supports AFUS:

```
metalIncome >= 70.0 AND energyIncome >= 2000.0 AND energy < 90% storage
```

Each AFUS provides ~5000+ energy income. The T2 constructor builds these near the T2 bot lab (`Factory::GetT2BotLabPos()`), with shake = 256 elmos.

### AFUS vs Nuke Competition

There's a deliberate resource competition guard:

```angelscript
const bool nukeCooldownActive = Builder::IsNukeSiloBuildQueued();
if (nukeCooldownActive && afusBuilt < 2) {
    // Suppress AFUS: nuke takes priority until 2 AFUS exist
}
```

If a nuke silo is being built AND fewer than 2 AFUS exist, AFUS construction is suppressed. This prevents the AI from starving its nuke project. Once 2 AFUS are built (providing ~10000 energy), the suppression lifts.

> **Source:** `tech.as:1287-1314`

### Fusion Reactor Cutoff

Regular fusion reactors stop when:

```
energyIncome >= 2000.0 (MaxEnergyIncomeForFUS)
```

Once AFUS provides enough energy, the AI stops building small fusion and only builds AFUS.

> **Source:** `tech.as:1316-1327`

---

## Phase 16: Multi-Gantry Production (20:00–30:00)

### Gantry Scaling

The allowed gantry count scales dynamically:

```
allowedGantry = min(floor(metalIncome / 250), floor(energyIncome / 6000))
```

| Metal Income | Energy Income | Gantries Allowed |
|-------------|--------------|-----------------|
| 250 | 6000 | 1 |
| 500 | 12000 | 2 |
| 750 | 18000 | 3 |
| 1000 | 24000 | 4 |

When `allowedGantry > 1`:
- Land and water gantry caps are raised for all factions
- More gantries can be placed across the map

### Gantry Production Queue

Each gantry runs through `Tech_FactoryAiMakeTask`:

```angelscript
if (UnitHelpers::IsGantryLab(facDef.GetName())) {
    if (metalIncome > 200.0f) {
        // Queue batch of 5 signature experimentals at HIGH priority
        Factory::EnqueueGantrySignatureBatch(u, side, 5, Priority::HIGH);
    }
    return aiFactoryMgr.DefaultMakeTask(u);  // C++ picks remaining units
}
```

When metal income > 200 (almost always by this phase), each gantry queues 5 signature experimentals. Otherwise, C++ default picks appropriate T3/super units from the Factory JSON configs.

### What "Signature Experimentals" Are

These are the faction-specific game-enders:
- **Armada:** Krogoth (armshltx-produced super unit)
- **Cortex:** Juggernaut (corgant-produced super unit)
- **Legion:** Legion equivalents (leggant-produced)

The specific units chosen come from the `EnqueueGantrySignatureBatch` logic which looks up the faction's heavy units.

> **Source:** `tech.as:416-425`

---

## Phase 17: T2 Lab Recycling — Round 2 (20:00–30:00)

### Why Recycle the T2 Lab?

When AFUS or nuke silo is queued and metal reserves are low, the Recycle function considers reclaiming the T2 bot lab:

```angelscript
if ((Builder::IsAdvancedFusionBuildQueued() || Builder::IsNukeSiloBuildQueued())
    && aiEconomyMgr.metal.current < 600.0f) {
    if (Factory::primaryT2BotLab !is null) {
        float labCostM = labDef.costM;
        float freeStorage = metal.storage - metal.current;
        if (freeStorage >= labCostM) {
            // Reclaim T2 lab → metal goes to AFUS/Nuke
        }
    }
}
```

### Safety: Free Storage Check

Unlike the T1 lab reclaim (which was unconditional), T2 lab reclaim has a **free storage check**: the AI only reclaims if there's enough free metal storage capacity to hold the reclaimed metal. This prevents wasting resources if storage is nearly full.

### The Reasoning

By this point, the gantry has replaced the T2 lab as the primary factory. The T2 lab's metal cost (~2000+) can be redirected into an AFUS or nuke silo. The AI is cannibalizing its own infrastructure to accelerate the endgame.

> **Source:** `tech.as:1383-1409`

---

## Phase 18: Air Force Development (20:00–30:00)

### T2 Aircraft Plant

When caps allow (dynamic scaling from `Tech_EconomyUpdate`):

```
RequiredMetalIncomeForT2AircraftPlant = 200.0
RequiredEnergyIncomeForT2AircraftPlant = 2000.0
```

The T1 constructor builds a T2 aircraft plant. This enables:
- T2 construction aircraft (advanced flying builders)
- T2 bombers and fighters

### Air Plant Production

`Tech_FactoryAiMakeTask` handles air plants with constructor maintenance:

```angelscript
// T2 air plant: maintain T2 air constructors below target
if (Factory::primaryT2AirPlant !is null && u.id == Factory::primaryT2AirPlant.id
    && t2AirCtorCount < 100) {
    // Enqueue T2 air constructor (armaca/coraca/legaca)
}
```

The air plant prioritizes construction aircraft production. Combat aircraft come from the C++ default factory logic and the JSON factory configs.

> **Source:** `tech.as:498-531`

---

## Phase 19: Full Military Operation (20:00–30:00)

### Attack Gate Cleared

With metalIncome well above 50, `Tech_MilitaryAiMakeTask` passes through to C++ military:

```angelscript
if (metalIncome < 50.0f) return null;
return aiMilitaryMgr.DefaultMakeTask(u);  // Full military AI active
```

### Military Quotas (TECH Role)

| Quota | Value | Meaning |
|-------|-------|---------|
| `scout` | 0 | No dedicated scout units |
| `attack` | 1.0 (power) | Very low threshold — attacks with small groups |
| `raid.min` | 30.0 (power) | Minimum raid group power |
| `raid.avg` | 30.0 (power) | Average raid group power |

These are deliberately low for TECH. The role doesn't need a massive army — its experimentals do the heavy lifting.

### Defense Policy

```angelscript
void Tech_AiMakeDefence(int cluster, const AIFloat3& in pos) {
    if (metalIncome < 300.0f) {
        aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
    }
}
```

Defense building via C++ only triggers below 300mi. Above 300mi, TECH relies on its army for defense rather than static turrets. This is intentional — at high income, metal is better spent on units than on buildings.

Note: Land defense turrets remain at cap 0 throughout. Only AA and LRPC can be placed by `DefaultMakeDefence`.

> **Source:** `tech.as:728-755`

### Factory Switch Logic

`Tech_AiIsSwitchAllowed` (`tech.as:624`) controls when the AI can switch to a new factory type:

```angelscript
bool switchAllowed = metalIncome > 100.0f;
// Disable factory assist until at least one gantry exists
assistRequired = (totalGantryCount < 1) ? false : (!switchAllowed);
```

Above 100mi, factory switching is allowed. Until a gantry exists, factory assist is disabled (constructors don't automatically assist factories — they build infrastructure instead).

> **Source:** `tech.as:624-647`

---

## Phase 20: Income-Scaled Dynamic Caps (Steady State)

By minute 25-30, `Tech_IncomeBuilderLimits()` has scaled everything up:

### Builder Caps at Various Income Levels

| Metal Income | T1 Builder Cap | T2 Builder Cap | Rez Bot Cap | Fast-Assist Cap |
|-------------|---------------|---------------|-------------|----------------|
| 50 | 5 | 3 | 2 | 5 |
| 100 | 5 | 3 | 5 | 10 |
| 150 | 5-10 | 3-5 | 7 | 15 |
| 200 | 10-15 | 5 | 10 | 20 |
| 300+ | 15-25 | 5 | 15 | 30+ |

### Air Plant Caps

| Metal Income | Energy Income | T1 Air Plants | T2 Air Plants |
|-------------|--------------|--------------|--------------|
| < 200 | < 2000 | 0 | 0 |
| >= 200 | >= 2000 | 1 | 1 |
| Higher | Higher | 1 (max) | 1 (max) |

> **Source:** `tech.as:951-996`, `tech.as:342-375`

---

## Economy State at Minute 30

| Resource | Typical Value | Source |
|----------|--------------|--------|
| Metal income | ~150–400 | Many mex upgrades + converters |
| Energy income | ~5000–15000 | AFUS + fusion + winds |
| Constructors | 3-5 T1 + 3-5 T2 + air constructors | Large workforce |
| Factories | Gantry(s) + T2 bot lab(s) + air plant(s) | Full spectrum |
| Military | 30-60 T2 bots + experimentals | Serious army |
| Key buildings | Multiple AFUS, anti-nuke, possibly nuke silo | Full infrastructure |

---

## What Defines This Phase

1. **AFUS chain** — each one adds ~5000 energy, enabling more gantries
2. **Gantry production** — experimentals start rolling off the line
3. **Resource cannibalization** — T2 labs recycled for AFUS/nuke metal
4. **Air development** — T2 air plant for construction aircraft and bombers
5. **Military activation** — fast T2 bots + experimentals form a real army
6. **Dynamic scaling** — every cap grows with income, creating positive feedback

---

## Summary: Minutes 20-30

```
Minute 20:  AFUS construction begins, energy income jumps
Minute 21:  First gantry starts producing experimentals
Minute 22:  Anti-nuke complete, defense established
Minute 23:  T2 lab may be recycled for AFUS/nuke metal
Minute 24:  Second AFUS lifts nuke suppression
Minute 25:  Factory switching enabled (>100mi), multi-factory production
Minute 26:  T2 air plant built, flying constructors deployed
Minute 27:  Second gantry possible (500mi + 12000ei)
Minute 28:  Full military with experimentals
Minute 29:  Income compounds: more mexes → more builders → more mexes
Minute 30:  Full late-game operation
```

---

*Previous: [03 — Minutes 10-20: Scaling & Military](03_Minutes_10-20_Scaling_and_Military.md)*
*Next: [05 — Minutes 30+: Endgame & Systems Overview](05_Minutes_30_Plus_Endgame.md)*
