# BAR Strategy Guide - Armada Vehicles (Self-Sufficient)

> **Disclaimer:** All values are conservative estimates to ensure surplus during proper play. Better to overestimate expenses than run into shortages.

---

## Table of Contents
1. [Economic Profiles by Faction](#economic-profiles-by-faction)
2. [Core Formulas](#core-formulas)
3. [Build Order - Phase by Phase](#build-order---phase-by-phase)
4. [Economy Group Templates](#economy-group-templates)
5. [Building Cost Reference](#building-cost-reference)
6. [Production Maintenance Costs](#production-maintenance-costs)

---

## Economic Profiles by Faction

| Factory      | Economic Profile                     |
| ------------ | ------------------------------------ |
| **Bots**     | Cheap, energy-light, metal-efficient |
| **Vehicles** | Heavier metal, moderate energy       |
| **Air**      | Extreme energy, low metal            |

---

## Core Formulas

### Build Time Calculation
```
BuildTime = unit.buildtime / TotalBuildPower
```

### Cost Per Second
```
Metal/s = metalCost × TotalBuildPower / buildtime
Energy/s = energyCost × TotalBuildPower / buildtime
```

---

## Build Order - Phase by Phase

### Phase 1: Pregame - Commander Queue

**Goal:** Establish basic economy and first production facility

**Commander Build Queue:**
1. 2× Mex
2. 3× Wind
3. 1× Lab
4. 3× Wind
5. 1× Mex (if close and defendable)
6. 2× Solar
7. → Secure all defendable Mexes
8. 10× Wind
9. 1× Energy Converter
10. 2-3× Sentry towers near lab
11. 1× Energy Storage
12. 1× Metal Storage

**Strategic Choice After Storage:**
- **Option A - Front Defense:** Build sentry towers one big square away from front
  - Every second square: Sentry tower
  - Behind defense line: Radar + AA
  - Fill gaps: Sentry every square, AA every second square

- **Option B - Economy Expansion:** Build energy infrastructure
  - Groups of: 6 Wind + 2 Solar + 1 Converter

**Expected Result:**
- **Metal:** 6-15 M/s (3-5 Mexes)
- **Energy:** 180 E/s (14 Wind + 2 Solar)
- **Time:** Pregame phase complete

---

### Phase 2: Game Start - Lab Production & Parallel Expansion

**Goal:** Establish unit production and reach first stable economy point

**Lab Queue (as soon as lab completes):**
1. 1× Constructor
2. 5× Scouts
3. 10× Light combat units
4. 1× Constructor
5. 10× Light combat units
6. 1× Constructor
7. 10× Light combat units
8. 1× Resurrector
9. 20× Light combat units
10. 150× Medium combat units

**Parallel Tasks:**
- **Economy:** Build ~10 Economy Groups until reaching 20 M/s & 300 E/s
  - With 5 Mexes, need exactly 10 groups
  - This enables full lab production (first stable point)

- **Front Establishment:** (costs 4-6 M/s + 30-60 E/s)
  - Defense line one big square from front
  - Every second square: Sentry
  - One square behind: 2× Radar + 2× AA
  - Fill gaps: Sentries every square, AA every second square
  - Troop position: Half square in front of defense
  - Rally point: One square behind defenses
  - Optional (if eco allows): Dragon's teeth + Mines

- **T1 Defense Expansion:**
  - Overwatch towers: Every second square between sentries
  - Gauntlets: In gaps between AA

- **Lab Support:** Build 1-2 Nanos depending on economy

**Economy Group - Early Game:**
```
6× Wind     (16s each)
2× Solar    (26s each)
1× Converter (26s)

Output:  1 M/s + 30 E/s
Time @BP400: 43.5s
Demand: 20-25 M/s + 400 E/s
```

**Expected Result:**
- **Metal:** 20 M/s
- **Energy:** 300 E/s
- **Build Power:** 600 BP
- **Time:** ~9 minutes from game start

---

### Phase 3: Early-Mid Scaling - T2 Transition

**Prerequisites:**
- ✅ +20 M/s income
- ✅ +1000 E/s income
- ✅ Front under control

**Goal:** Upgrade all Mexes and prepare T2 production

**Economy Group - T2 Transition:**
```
3× Advanced Solar
2× Converters

Output: 2 M/s + 120 E/s
Time @BP400: 73s
Demand: 20 M/s + 400 E/s
```

**Build Order:**
1. Cycle 3 Constructors in lab (instant replacement if one dies)
2. Cycle 20 of each relevant combat unit
   - +5 AA units if enemy is air-heavy and raids planned
3. Balance economy with converters
4. Find T2 construction site
5. Build 1× Nano at construction site
6. Build 2× Economy Groups in nano range
7. Build Advanced Lab/Plant in nano range
   - Queue: 1× Constructor only (no other units yet)
   - Send constructor to upgrade Mexes
   - Mex upgrade demand: 8.5 M/s + 100 E/s
8. Build 1× Economy Group
9. Build 2× Nanos
10. Build 2× Economy Groups
11. Build 1× Nano
12. (Optional) Fortify Advanced Plant
13. (If possible) Coordinate first serious raid with teammates

**Expected Result:**
- **Economy Groups:** 5 groups = 10 M/s + 600 E/s
- **Advanced Mexes:** 35 M/s (all mexes upgraded)
- **Total:** 55 M/s + 1000 E/s
- **Status:** Ready for T2 unit production

---

### Phase 4: Midgame - T2 Production Scaling

**Prerequisites:**
- ✅ Expected results from Phase 3

**Goal:** Full T2 production capability

**Scaling Targets:**
- Supercharge main lab: 3 Nanos → 25 M/s + 300 E/s
- Scale advanced lab: 9 Nanos → 75 M/s + 900 E/s
- Transition to T2 economy infrastructure

**Economy Group - Midgame:**
```
1× Fusion Reactor
1× Advanced Converter
2× Nanos

⚠️ MUST be built with minimum 5 nanos!

Output: 10 M/s + 200 E/s
```

**Build Order:**
1. Build 1× Nano
2. Build 7× Economy Groups
3. As soon as eco allows:
   - Start T2 unit production
   - Fortify front with second Advanced Constructor
   - Place Nanos at front for repairs
4. Execute second raid with remaining T1 + some T2 units
   - If early compared to enemy, could be game-winning

**Expected Result:**
- **Metal:** 150 M/s
- **Energy:** 2000 E/s
- **Army:** Full T2 composition

---

### Phase 5: Late Game - Advanced Warfare

**Status:** TBD (Game dynamics highly variable at this stage)

**General Direction:**
- Scale offense and defense into T2
- Long-range artillery
- Nukes and Anti-nukes
- T3 technology transition

**Note:** Late game strategy heavily depends on:
- Map control
- Enemy composition
- Team coordination
- Resource distribution

---

## Economy Group Templates

### Early Game Group
| Component | Quantity | Build Time | Output |
|-----------|----------|------------|--------|
| Wind | 6 | 16s each | — |
| Solar | 2 | 26s each | — |
| Converter | 1 | 26s | — |
| **Total** | — | **43.5s @BP400** | **1 M/s + 30 E/s** |

**Production Demand:** 20-25 M/s + 400 E/s

---

### T2 Transition Group
| Component | Quantity | Build Time | Output |
|-----------|----------|------------|--------|
| Advanced Solar | 3 | 80s each | — |
| Converter | 2 | 26s each | — |
| **Total** | — | **73s @BP400** | **2 M/s + 120 E/s** |

**Production Demand:** 20 M/s + 400 E/s

---

### Midgame Group (T2 Economy)
| Component | Quantity | Build Time | Output |
|-----------|----------|------------|--------|
| Fusion Reactor | 1 | — | — |
| Advanced Converter | 1 | — | — |
| Nano | 2 | — | — |
| **Total** | — | **Build with 5+ nanos** | **10 M/s + 200 E/s** |

---

## Building Cost Reference

### Defense Structures

#### Gauntlet (Permanent Defense)
```
Cost: 1250 M + 12500 E (214s build time)
@BP100: 5.8 M/s + 58.41 E/s
```

#### Sentry (Temporary Defense)
```
Cost: 85 M + 680 E (24s build time)
@BP100: 3.54 M/s + 28.3 E/s
```

#### Beamer (Fixed Defense)
```
Cost: 190 M + 1500 E (48s build time)
@BP100: 3.95 M/s + 21.25 E/s
```

---

### Economy Structures

#### Advanced Solar
```
Cost: 350 M + 5000 E (80s build time)
Output: 80 E/s

@BP100: 4.375 M/s + 62.5 E/s
@BP400: 17.5 M/s + 250 E/s
```

#### Advanced Mex
```
Cost: 620 M + 7700 E (149s build time)
@BP100: 4.2 M/s + 51.7 E/s
```

#### Wind
```
Build time: 16s
Output: ~10 E/s (average)
```

#### Solar
```
Build time: 26s
Output: Fixed energy
```

---

### Production Facilities

#### Advanced Vehicle Plant
```
Cost: 2600 M + 14000 E (180s build time)
@BP100: 5.2 M/s + 28 E/s

Target: 1 minute build time
Required: 300 BP → 15.6 M/s + 74 E/s

⚠️ Reclaim Strategy:
- Reclaim old bot lab: 375 M
- Reclaim 10 windmills: 300 M
- Total reclaim boost: ~675 M
- Collect map metal: ~100 M
- Consider pausing main lab for 1 min (if not on front duty)
```

---

## Production Maintenance Costs

### Factory Production (Continuous)

#### Bot Lab (Ticks/Pawns & Rovers/Blitz)
```
Metal:  10-20 M/s
Energy: 150-300 E/s
```

#### Vehicle Plant
```
Metal:  20-40 M/s
Energy: 300-600 E/s
```

#### Air Plant
```
Metal:  10-25 M/s
Energy: 600-1200 E/s
⚠️ Extreme energy demand!
```

---

### Support Structures

#### Energy Converter (T1)
```
Consumes: 70 E/s
Produces: 1 M/s
```

#### Energy Converter (T2)
```
Consumes: 600 E/s
Produces: 10 M/s
```

#### One Nano (Assistant)
```
Costs: 5 M/s + 150 E/s
```

---

## Strategic Notes

### Multiplayer Considerations
For team games, additional strategies needed for:
- Front role specialization
- Tech progression coordination
- Naval strategies (map dependent)

**Remember:** This guide is a framework, not rigid instructions. Adapt to:
- Enemy composition
- Map features
- Team dynamics
- Game pace

---

### Resource Thresholds

**Energy Demand ≥ 1000 E/s:**
- Switch from Wind/Solar to Advanced Solar production
- Better efficiency at scale

---

## External Resources

**Unit Comparison Tool:**
[motioncorrect.github.io/unit-comparison-tool](https://motioncorrect.github.io/unit-comparison-tool)

---

*Strategy guide for competitive BAR play - Armada Vehicles faction, self-sufficient role.*
