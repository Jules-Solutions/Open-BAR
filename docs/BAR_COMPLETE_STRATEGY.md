# Beyond All Reason - Complete Strategy Framework
## 1v1 Armada Edition - Comprehensive Guide

---

# PART 1: CORE PHILOSOPHY

## The Core Loop (Always Active)

These rules override EVERYTHING. Check them every few seconds.

| Rule | How to Check | Fix |
|------|--------------|-----|
| **Never stall metal** | Metal bar depleting? | Build mex, reclaim, slow production |
| **Never stall energy** | Energy bar depleting? | Build energy NOW, pause factory |
| **Never float resources** | Bars staying full? | Add BP, build more units |
| **Always have vision** | Fog of war? Radar gaps? | Radar + scout with Ticks |
| **Always queue production** | Factory idle? | Queue units |
| **Protect commander** | Is com safe? | Don't throw the game |

---

# PART 2: ECONOMY SYSTEMS

## Metal Production

### Metal Extractors
| Type | Cost | Output | Notes |
|------|------|--------|-------|
| T1 Mex | 50M / 500E | ~2 M/s | Map dependent (1.8-2.5) |
| T2 Moho | 550M / 6600E | ~8 M/s | 4x base value. Priority upgrade. |

**Expansion Priority:**
1. Starting 3 mexes (safe)
2. Safe side expansion
3. Contested middle mexes (with army)
4. Forward mexes (when winning)

### Energy Converters
Convert excess energy into metal.

| Type | Conversion | Efficiency |
|------|------------|------------|
| T1 | 70 E/s → 1 M/s | Baseline |
| T2 | 600 E/s → 10.3 M/s | 20% better |

**When to Build Converters:**
- ✓ Energy income exceeds consumption by 100+ E/s
- ✓ All practical mex expansion done
- ✓ Yellow slider at 70-80% and still floating E
- ✗ DON'T build if you can still safely expand
- ✗ DON'T build if energy is tight

**Yellow Slider (Resource Bar):**
- Controls when converters activate
- Higher = converters off more (save energy)
- Lower = converters on more (make metal)
- Start at 70-80%, adjust based on needs

**CRITICAL: Converters chain explode! Space them apart!**

---

## Energy Production

### Wind vs Solar Decision

| Avg Wind | Choice | Reasoning |
|----------|--------|-----------|
| < 7 | Solar | More metal-efficient |
| ≥ 7 | Wind | More metal-efficient |
| ≥ 12 | Wind + Storage | High variance, buffer helps |

Check wind: Press `I` for map info.

### Energy Buildings

| Building | Cost | Output | When to Build |
|----------|------|--------|---------------|
| Wind | 40M / 175E | 0-25 E/s | Wind ≥ 7 |
| Solar | 150M / 0E | 20 E/s | Wind < 7, or E-stalling |
| Tidal | 175M / 1750E | 18-25 E/s | Water maps |
| Geo T1 | 350M / 3500E | 300 E/s | If geo vents available |
| Adv Solar | 280M / 2800E | 75 E/s | T2, slow scaling |
| Fusion | 3500M / 16000E | 1000 E/s | T2, main energy |

**WARNING: Fusion explodes on death! Don't cluster!**

---

## Build Power

**The Ratio (from official guide):**
```
200 Build Power per 5 M/s income and 100 E/s income
```

| Unit | Build Power | Notes |
|------|-------------|-------|
| Commander | 200 BP | Starting unit |
| Nano Turret | 200 BP | Stationary, assists |
| T1 Con Bot | 100 BP | Mobile |
| T1 Con Vehicle | 100 BP | Faster than bot |
| T2 Con Bot | 200 BP | T2 buildings |
| T2 Con Vehicle | 200 BP | Faster |

**Nano Turret Threshold:**
```
Build when: Metal ≥ 8/s AND Energy ≥ 100/s
```

**Key Insight:** Nano turrets are better than second factories. One factory + nanos is more efficient than two factories.

---

## Storage

| Storage | Cost | Capacity | When |
|---------|------|----------|------|
| Metal Storage | 200M | +3000 M | Before T2 (bank resources) |
| Energy Storage | 175M / 1750E | +6000 E | With wind (variance buffer) |

Don't overbuild storage. It doesn't produce, only stores.

---

# PART 3: STATE SYSTEM

## State Definitions

```
OPENING      → 0-2 mex, factory building
FOUNDATION   → Factory up, no constructor yet
EXPANSION    → 1+ con, metal < 8/s
SCALING      → 8-20 M/s, building toward T2
T2_READY     → 20+ M/s, 500+ E/s, 1000+ stored
T2_TRANSITION→ T2 lab building/built
LATE_GAME    → 3+ Moho, 1+ Fusion
```

## Priorities Per State

### OPENING
| Priority | Action |
|----------|--------|
| 1 | Mex #1 (closest) |
| 2 | Mex #2 |
| 3 | 2-3 Energy (wind if ≥7, else solar) |
| 4 | Bot Lab |

### FOUNDATION
| Priority | Action |
|----------|--------|
| 1 | Mex #3 |
| 2 | Energy scale (~60 E/s) |
| 3 | Factory: Tick → Tick → Combat → Constructor |
| 4 | Radar |

### EXPANSION
| Priority | Action |
|----------|--------|
| 1 | Con: Grab contested mexes |
| 2 | Con: 1-2 LLT at key points |
| 3 | Commander: Energy scale |
| 4 | Factory: Combat units |
| 5 | Check: Ready for nano? (8 M/s, 100 E/s) |

### SCALING
| Priority | Action |
|----------|--------|
| 1 | Build Nano on factory |
| 2 | Continue mex expansion (10+ target) |
| 3 | Get 2nd Constructor |
| 4 | Energy scale → 500 E/s |
| 5 | Bank metal → 1000-2000 |

### T2_READY
| Priority | Action |
|----------|--------|
| 1 | Start Advanced Bot Lab |
| 2 | Maintain T1 production |
| 3 | Queue T2 Con first |
| 4 | Protect key mexes |

### T2_TRANSITION
| Priority | Action |
|----------|--------|
| 1 | T2 Con → Moho back mexes |
| 2 | T2 Con → Fusion Reactor |
| 3 | T1 Factory: Keep producing |
| 4 | Consider T2 units |

### LATE_GAME
| Priority | Action |
|----------|--------|
| 1 | All mex → Moho |
| 2 | Multiple Fusions |
| 3 | Nano farm (3-5) |
| 4 | T2 Converters |
| 5 | T3/Experimentals |

---

# PART 4: UNIT COMPOSITION

## Army Composition by Phase

### Early Game (OPENING - EXPANSION)
| Unit | Role | Use |
|------|------|-----|
| Tick | Scout | Map vision, find enemy |
| Pawn | Raider | Harass, kill cons |
| Grunt | Combat | Core fighting unit |
| Rocketer | Siege | Push defenses |

**Typical Mix:** 2 Ticks, then Grunts with a few Rocketers

### Mid Game (SCALING - T2_READY)
| Unit | Role | Use |
|------|------|-----|
| Grunt/Pawn | Core | Numbers |
| Rocketer | Siege | Defense bust |
| Warrior | Anti-swarm | AoE |
| Jethro | AA | If enemy air |

**Typical Mix:** Grunts + Rocketers, add Warriors vs swarm

### Late Game (T2+)
| Unit | Role | Use |
|------|------|-----|
| Zeus | Assault | Push power |
| Fido | Skirmish | Range |
| Invader | Artillery | AoE |
| Eraser | EMP | Disable |

**Typical Mix:** Zeus front, Fido/Invader support, Erasers vs heavy

## Counter Matrix

| If Enemy Has | Build |
|--------------|-------|
| Swarms (Pawns, Grunts) | Warriors, AoE |
| Assault (Zeus, Bulldogs) | Skirmishers, Artillery |
| Skirmishers (Rocketers, Fido) | Fast raiders, Air |
| Artillery | Raiders, Air, Fast assault |
| Defenses | Rocketers, Artillery, Bombers |
| Air | AA turrets + Mobile AA |

---

# PART 5: DEFENSE SYSTEM

## Defense vs Army Decision

**Build Defense When:**
- Protecting key positions
- Buying time to eco/tech
- Good choke points exist
- You're ahead (secure lead)
- Need AA coverage

**Build Army Instead When:**
- Need to contest map
- Enemy is turtling
- Open terrain
- You're behind (need to take risks)

## Defense Placement Guide

### LLT (Light Laser Tower)
- **Cost:** 85M / 850E
- **Range:** 350
- **When:** Early game, protecting expansions
- **Where:** Behind contested mexes, choke points
- **Warning:** Outranged by Rocketer (450)!

### HLT (Sentinel)
- **Cost:** 350M / 3500E
- **Range:** 500
- **When:** Mid game, vs assault units
- **Where:** Behind LLTs as second line

### Plasma Battery (Ambusher)
- **Cost:** 500M / 5000E
- **Range:** 700
- **When:** Mid game, vs grouped enemies
- **Where:** High ground, covering wide approaches

### Pulsar
- **Cost:** 1500M / 18000E
- **Range:** 900
- **When:** T2, vs heavy units
- **Where:** Core defensive positions
- **Warning:** Uses 150 E per shot!

### AA Turret (Chainsaw)
- **Cost:** 85M / 850E
- **Range:** 800
- **When:** IMMEDIATELY when enemy air plant spotted
- **Where:** Cover factory, cover eco, overlapping fields
- **How Many:** 2-3 minimum for base coverage

### Walls
- **Dragon's Teeth:** 3M, blocks pathing, use liberally
- **Fortification:** 15M, blocks shots, use sparingly
- **Purpose:** Funnel enemies, slow raiders, create chokes

---

# PART 6: AIR SYSTEM

## When to Build Air Plant

**Go Air When:**
- Enemy has no AA (punish it)
- Hard-to-reach expansions (island maps)
- Strong eco lead (can afford two production lines)
- Need to contest air superiority

**Don't Go Air When:**
- Eco can't support two production lines
- Enemy has strong AA
- Small map (ground reaches everywhere)
- You're behind

## Air Unit Roles

| Unit | Role | Use |
|------|------|-----|
| Blink | Scout | Map vision (expendable) |
| Freedom Fighter | Fighter | Air superiority, intercept bombers |
| Phoenix | Bomber | Snipe mexes, cons, lone units |
| Stiletto (T2) | Gunship | Ground attack support |
| Lightning (T2) | Heavy Bomber | Destroy buildings, heavy targets |

## AA Response Protocol

**When you scout enemy air plant:**
1. Build 2-3 AA turrets covering base (URGENT)
2. Add mobile AA (Jethro/Samson) to army
3. ~90 seconds until first bomber arrives

**When bombers incoming:**
1. Pull constructors to safety
2. Spread important buildings
3. Don't cluster units

**AA Ratio:**
- 2-3 turrets per base cluster
- 1-2 mobile AA per 10 army units

---

# PART 7: COMBAT SYSTEM

## Engagement Decision

**Take Fight When:**
- Superior army value
- Terrain advantage
- Enemy split/out of position
- Have repair support nearby

**Avoid Fight When:**
- Enemy has superior value
- Fighting into defenses
- Your army is split

## Micro Techniques

### Kiting
- Attack while moving backward
- Use when you have range advantage
- Example: Rocketers vs Grunts

### Focus Fire
- Concentrate fire on single targets
- Right-click specific units
- Priority: High-value targets first

### Concave
- Arc formation so all units fire
- Spread units in crescent facing enemy
- More DPS from same army

### Terrain Use
- **High ground:** Extra range for arty/plasma
- **Cliffs:** Bots climb, vehicles can't
- **Water:** Amphibious flanking
- **Chokes:** Force clumping for AoE

### Retreat & Repair
- Pull units below 50% HP
- Send to constructor behind lines
- Repaired unit = free value

## Wreck Economy

- Wrecks give 33-67% of unit metal
- Commander wreck = 1250 metal (CONTEST THIS)
- After fights: Send con to reclaim immediately
- Rez bot: Resurrect expensive units (costs energy)
- Reclaim: Fast metal for cheap units

---

# PART 8: COMMANDER

## Role by Phase

| Phase | Role | Position |
|-------|------|----------|
| Early | Primary builder | In base |
| Mid | Front-line threat / builder | Behind front, close enough to D-gun |
| Late | Defense / opportunistic | Safe in base, or with army |

## D-Gun Usage

- **Damage:** Kills anything (except commanders)
- **Cost:** 500 energy
- **Reload:** 1 second
- **Range:** ~350

**Best Targets:**
- T2 assault units (Zeus, Bulldogs)
- Expensive units (>300 metal)
- Clumped groups (AoE splash)

**Don't D-Gun:**
- Cheap units (waste of energy)
- When energy stalling
- Into superior numbers

## Commander Safety

**Threats:**
- Bomber snipes
- EMP + focus fire
- Swarm overwhelming

**Safety Measures:**
- Always know where enemy army is
- Don't overextend alone
- Have retreat path
- Mobile AA if air threat

**Rule:** If you're not sure it's safe, it's not safe.

**Death Explosion:** ~5000 damage in large AoE. Can use offensively (com bomb) but very risky.

---

# PART 9: LATE GAME

## Late Game Goals

### Economy
- All mexes → Moho
- 2-4 Fusion Reactors
- Converter farm for excess energy

### Production
- Nano farm (3-5 nanos on factory)
- Multiple factories (OK now)
- Spam T2 assault

### Game Enders
- **Nukes:** Expensive, map-changing. Scout for anti-nuke first.
- **Big Bertha:** Long-range artillery pressure
- **Experimentals:** T3 units that solo armies

## Nukes

**Your Nuke:**
- Cost: 2500M + huge energy stockpile
- Use: Destroy eco clusters, mass armies
- Warning: Anti-nuke stops it. Scout first!

**Anti-Nuke:**
- Cost: 1800M / 54000E
- Range: ~4000
- MUST HAVE if enemy might nuke
- Keep missiles stockpiled!

---

# PART 10: MODIFIERS

## Energy Modifiers
| Condition | Adjustment |
|-----------|------------|
| No Wind (< 7) | Solar only |
| High Wind (≥ 12) | Wind + Storage |
| Geo Vents | Prioritize Geo (300 E/s) |
| Water + Tidal | Tidal for stable energy |

## Enemy Behavior Modifiers
| Condition | Adjustment |
|-----------|------------|
| Rush Detected | Pause expansion, com to front, LLT, combat only |
| Enemy Turtling | Eco harder, outscale them |
| Air Threat | 2-3 AA turrets, mobile AA in army |
| Losing Map Control | Prioritize army, reclaim, defensive |

## Terrain Modifiers
| Condition | Adjustment |
|-----------|------------|
| Hilly/Rough | Bot Lab (bots climb) |
| Flat/Open | Consider Vehicle Plant |

## Economy Modifiers
| Condition | Adjustment |
|-----------|------------|
| Energy Stalling | STOP. Build energy. Pause factory. |
| Metal Floating | Add BP or build more units |
| Rich Reclaim | Send con to reclaim for early boost |

---

# PART 11: RECOVERY

## When You're Behind

### Lost Army
1. Don't panic
2. Reclaim the wrecks!
3. Build emergency defenses
4. Rebuild army

### Lost Eco
1. Rebuild metal first
2. Every mex is priority
3. Scale back production until eco recovers

### Behind Overall
**Options:**
- Turtle and out-tech
- All-in timing attack
- Harass eco, avoid main army
- Go air if they have no AA

**Remember:** Game isn't over until commander dies.

---

# PART 12: COMMON MISTAKES

| Mistake | Why It's Bad | Fix |
|---------|--------------|-----|
| Nano before eco supports it | You stall harder | Wait for 8 M/s, 100 E/s |
| Multiple T1 factories | Wasteful | Use nanos instead |
| Going T2 while stalling | You'll stall worse | Stabilize eco first |
| Floating metal | Wasted resources | Add BP or units |
| Ignoring radar | Can't react to threats | Always have coverage |
| Idle factory | Lost production | Always queue |
| Clustering converters | Chain explosion | Space them out |
| No AA vs air | Die to bombers | Build AA on scout |
| Commander overextend | Lose game | Stay safe |
| Fighting into defenses | Trade poorly | Artillery or flank |

---

# QUICK REFERENCE CARD

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         BAR 1V1 QUICK REFERENCE                          ║
╠═══════════════════════════════════════════════════════════════════════════╣
║  OPENING: Mex → Mex → 2-3 Energy (wind≥7?) → Bot Lab                     ║
║  FACTORY: Tick → Tick → Combat → Constructor                              ║
║                                                                           ║
║  THRESHOLDS:                                                              ║
║    Nano:     Metal ≥ 8/s AND Energy ≥ 100/s                              ║
║    T2 Ready: Metal ≥ 20/s AND Energy ≥ 500/s AND Stored ≥ 1000           ║
║                                                                           ║
║  RATIOS:                                                                  ║
║    200 BP per 5 M/s and 100 E/s                                          ║
║    70 E/s → 1 M/s (T1 converter)                                         ║
║    600 E/s → 10.3 M/s (T2 converter)                                     ║
║                                                                           ║
║  COUNTERS:                                                                ║
║    vs Swarm → AoE (Warriors, Plasma)                                     ║
║    vs Assault → Skirmishers, Artillery                                   ║
║    vs Defenses → Rocketers, Bombers, EMP                                 ║
║    vs Air → AA turrets + Mobile AA (URGENT)                              ║
║                                                                           ║
║  CORE LOOP: Never stall. Never float. Always vision. Always produce.     ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

# FILES INCLUDED

| File | Purpose |
|------|---------|
| `BAR_COMPLETE_STRATEGY.md` | This document |
| `bar_econ.py` | Economy calculator |
| `bar_states.py` | State system |
| `bar_units.py` | Complete unit database |
| `bar_systems.py` | All game subsystems |

---

*Version 2.0 - Comprehensive Edition*
*For Beyond All Reason (Armada, 1v1)*
