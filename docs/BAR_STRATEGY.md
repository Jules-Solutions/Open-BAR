# Beyond All Reason - Base Strategy Framework
## 1v1 Armada Edition

---

## Philosophy

This strategy is **state-based, not time-based**. The game doesn't care what minute it is - it cares what your economy looks like. Good players think:

> "I have 8 metal income and 100 energy, I can support a nano now"

Not:

> "It's minute 4, time to build nano"

---

## The Core Loop (Always Active)

These rules override everything. Check them constantly.

| Rule | Check | Fix |
|------|-------|-----|
| **Never stall metal** | Metal bar depleting? | Build mex, reclaim, slow production |
| **Never stall energy** | Energy bar depleting? | Build energy NOW, pause factory |
| **Never float resources** | Bars full? | Add build power, build more units |
| **Always have vision** | Radar gaps? Fog of war? | Radar coverage, scout with Ticks |
| **Always queue production** | Factory idle? | Queue units (unless energy stalling) |
| **Protect commander** | In danger? | Don't throw - it's your win condition |

---

## States & Transitions

```
┌─────────────┐
│   OPENING   │  0-2 mex, no factory
└──────┬──────┘
       │ Factory placed
       ▼
┌─────────────┐
│ FOUNDATION  │  Factory up, no constructor yet
└──────┬──────┘
       │ First constructor completed
       ▼
┌─────────────┐
│  EXPANSION  │  1 con, <8 M/s
└──────┬──────┘
       │ Metal ≥8/s AND Energy ≥100/s
       ▼
┌─────────────┐
│   SCALING   │  8-20 M/s, building toward T2
└──────┬──────┘
       │ Metal ≥20/s AND Energy ≥500/s AND Stored ≥1000M
       ▼
┌─────────────┐
│  T2 READY   │  Economy can support T2
└──────┬──────┘
       │ T2 Lab construction started
       ▼
┌─────────────┐
│ T2 TRANSIT  │  Building T2 infrastructure
└──────┬──────┘
       │ 3+ Moho AND 1+ Fusion
       ▼
┌─────────────┐
│  LATE GAME  │  T2 economy online
└─────────────┘
```

---

## State Details

### STATE: OPENING
**Condition:** 0-2 mex, no factory complete

| Priority | Action | Target |
|----------|--------|--------|
| 1 | Build Mex #1 (closest to commander) | Metal income |
| 2 | Build Mex #2 | Metal income |
| 3 | Build 2-3 Energy | Stay positive |
| 4 | Place Bot Lab | Production |

**Energy Decision:**
- Press `I` to check map wind
- **Wind ≥ 7** → Wind Turbines (40M each)
- **Wind < 7** → Solar Collectors (150M each)

---

### STATE: FOUNDATION
**Condition:** Factory up, no constructor out yet

| Priority | Action | Target |
|----------|--------|--------|
| 1 | Complete Mex #3 | Full starting cluster |
| 2 | Scale energy | Stay positive (~60 E/s) |
| 3 | Factory: Tick → Tick → Combat → **Constructor** | Production |
| 4 | Build Radar | Vision |

**Checkpoint:** When constructor pops out, you enter EXPANSION.

---

### STATE: EXPANSION
**Condition:** 1 constructor, metal income <8/s

| Priority | Action | Target |
|----------|--------|--------|
| 1 | Constructor: Grab contested mexes | Map control |
| 2 | Constructor: 1-2 LLT at key points | Defense |
| 3 | Commander: Energy scale | Prep for nano |
| 4 | Factory: Combat units | Army |
| 5 | Evaluate nano threshold | See below |

**Nano Threshold Check:**
```
IF Metal/s ≥ 8 AND Energy/s ≥ 100
THEN → Build nano turret to assist factory
ELSE → Keep expanding economy first
```

---

### STATE: SCALING
**Condition:** Metal ≥8/s, can support nano

| Priority | Action | Target |
|----------|--------|--------|
| 1 | Build Nano assisting factory | +200 BP |
| 2 | Continue mex expansion | 10+ mexes |
| 3 | Get 2nd Constructor | Faster expansion |
| 4 | Energy scale → 500 E/s | T2 prep |
| 5 | Bank metal → 1000-2000 | T2 prep |

---

### STATE: T2 READY
**Condition:** Metal ≥20/s, Energy ≥500/s, Stored ≥1000M

| Priority | Action | Target |
|----------|--------|--------|
| 1 | Start Advanced Bot Lab | T2 access |
| 2 | Maintain T1 production | Don't stop army |
| 3 | Protect key mexes | Economy |
| 4 | Queue T2 Con first in T2 lab | Moho access |

**Total T2 Investment:** ~4000 metal
- Adv Bot Lab: 2200M
- T2 Constructor: 400M
- First 3 Mohos: 1650M

---

### STATE: T2 TRANSITION
**Condition:** T2 Lab building or built

| Priority | Action | Target |
|----------|--------|--------|
| 1 | T2 Con → Upgrade back mexes to Moho | 4x metal |
| 2 | T2 Con → Build Fusion Reactor | 1000 E/s |
| 3 | T1 Factory keeps producing | Army |
| 4 | Consider T2 units | Power spike |

---

### STATE: LATE GAME
**Condition:** 3+ Moho, 1+ Fusion

| Priority | Action | Target |
|----------|--------|--------|
| 1 | All mex → Moho | Max metal |
| 2 | Multiple Fusions | Energy abundance |
| 3 | Nano farm | Fast production |
| 4 | T2 Converters | Metal boost |
| 5 | T3/Experimentals | End game |

---

## Modifiers (Conditional Rules)

These adjust priorities based on conditions:

### Energy Modifiers

| Condition | Adjustment |
|-----------|------------|
| **No Wind (avg < 7)** | Solar only. Skip wind entirely. |
| **High Wind (≥12)** | Wind only. Add Energy Storage for variance. |
| **Geo Vents Available** | Prioritize Geothermal (300 E/s stable). |
| **Water + Tidal > 18** | Tidal generators for stable energy. |

### Enemy Behavior Modifiers

| Condition | Adjustment |
|-----------|------------|
| **Rush Detected** | Pause expansion. Commander to front. LLT. Combat units only. |
| **Enemy Turtling** | Eco harder. Delay army. Outscale them. |
| **Air Threat** | 1-2 AA turrets. AA units in army. Spread buildings. |
| **Losing Map Control** | Prioritize army over eco. Reclaim wrecks. Defensive. |

### Terrain Modifiers

| Condition | Adjustment |
|-----------|------------|
| **Hilly/Rough Terrain** | Prefer Bot Lab. Bots traverse hills. |
| **Open/Flat Map** | Consider Vehicle Plant. Tanks have better stats. |

### Economy Modifiers

| Condition | Adjustment |
|-----------|------------|
| **Energy Stalling** | STOP. Build energy. Pause factory. |
| **Metal Floating** | Add build power or build more units. |
| **Rich Reclaim** | Send constructor to reclaim. Big metal boost. |

---

## Key Numbers Reference

### Economy Ratios (Official Guide)
```
200 Build Power per 5 M/s and 100 E/s
```

| Unit | Build Power |
|------|-------------|
| Commander | 200 BP |
| Nano Turret | 200 BP |
| T1 Con Bot | 100 BP |
| T2 Con Bot | 200 BP |

### Unit Costs (Armada)

| Unit | Metal | Energy | Build Time @200BP |
|------|-------|--------|-------------------|
| Metal Extractor | 50 | 500 | 6s |
| Solar Collector | 150 | 0 | 10.5s |
| Wind Turbine | 40 | 175 | 5.2s |
| Bot Lab | 650 | 1300 | 35s |
| Nano Turret | 200 | 4000 | 30s |
| Construction Bot | 100 | 1000 | 15s |
| Tick (Scout) | 25 | 300 | 5.5s |
| Pawn | 35 | 700 | 7.5s |
| LLT | 85 | 850 | 14s |
| Adv Bot Lab | 2200 | 12000 | 125s |
| Moho Mex | 550 | 6600 | 70s |
| Fusion | 3500 | 16000 | 150s |

### Wind vs Solar Breakeven

| Avg Wind | Better Choice | Why |
|----------|--------------|-----|
| < 5.3 | Solar | More metal-efficient |
| ≥ 5.3 | Wind | More metal-efficient |
| ≥ 7 | Wind | Official guide threshold |

*Use 7 as your decision point - it's conservative and accounts for variance.*

---

## Common Mistakes

❌ **Building nano before eco can support it**
→ Nano at 5 M/s just makes you stall harder

❌ **Multiple T1 factories**
→ Wasteful. Use nanos to boost one factory instead.

❌ **Going T2 while stalling**
→ T2 costs ~4000 metal. You need stable eco first.

❌ **Floating metal**
→ You have a build power bottleneck. Add nanos/cons.

❌ **Ignoring radar/scouting**
→ You can't react to what you can't see.

❌ **Idle factory**
→ Always be producing (unless energy stalling).

---

## Quick Start Checklist

```
□ Check wind (press I) → Wind ≥7? Wind : Solar
□ Mex → Mex → 2-3 Energy → Bot Lab
□ Queue: Tick → Tick → Combat → Constructor
□ Commander: Mex #3 → Energy → Radar
□ Constructor: Contested mexes → LLT
□ At 8 M/s + 100 E/s → Build nano
□ At 10+ mex → Get 2nd constructor
□ At 20 M/s + 500 E/s + 1000 stored → Start T2
□ T2 Con: Moho back mex → Fusion → More Moho
```

---

## Files Included

- `bar_econ.py` - Economy calculator with unit data
- `bar_states.py` - State system definitions and quick reference
- `BAR_STRATEGY.md` - This document

Run the Python files to:
- Analyze your current game state
- Calculate wind vs solar breakeven
- Check T2 readiness
- Get priority recommendations

---

*Version 1.0 - January 2025*
*For Beyond All Reason (Armada, 1v1)*
