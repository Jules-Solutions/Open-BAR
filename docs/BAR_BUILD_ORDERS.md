# BAR Commander Build Orders
## Pre-Game Queue & Opening Sequences

---

# CONCEPT: PRE-GAME QUEUING

Before the game starts (during the 120-second countdown), you can queue orders for your commander. These execute automatically when the game begins.

**Why This Matters:**
- Commander never idles in crucial opening
- Consistent, optimized start every game
- Frees your attention for scouting/planning
- Eliminates early-game mistakes

**How to Queue:**
- Hold `SHIFT` while giving orders to queue them
- Orders execute in sequence
- Works for: build commands, move commands, patrol, etc.

---

# BUILD TIME REFERENCE

| Building | Build Time | @ 200 BP (Com) | Metal | Energy |
|----------|------------|----------------|-------|--------|
| Mex | 1200 | **6.0s** | 50 | 500 |
| Wind | 1050 | **5.25s** | 40 | 175 |
| Solar | 2100 | **10.5s** | 150 | 0 |
| Bot Lab | 7000 | **35s** | 650 | 1300 |
| Radar | 1500 | **7.5s** | 50 | 500 |
| LLT | 2800 | **14s** | 85 | 850 |
| Nano | 6000 | **30s** | 200 | 4000 |

**Note:** Walk time between buildings adds ~2-5 seconds each.

---

# OPENING DECISION TREE

```
START
  │
  ├─► Check wind speed (press 'I' for map info)
  │     │
  │     ├─► Wind ≥ 7? ──► WIND BUILD ORDER
  │     │
  │     └─► Wind < 7? ──► SOLAR BUILD ORDER
  │
  └─► Check map type
        │
        ├─► Standard land map ──► BOT LAB
        ├─► Very flat/open ──► Consider VEHICLE PLANT
        └─► Water/island ──► Consider SHIPYARD or AIR
```

---

# BUILD ORDER A: WIND MAP (Avg Wind ≥ 7)

**Total queue time: ~85 seconds**
**Metal spots: Assumes 3 starting mexes within reasonable distance**

## The Queue (SHIFT+Click all of these pre-game)

| #   | Order                    | Time      | Running Total | Notes              |
| --- | ------------------------ | --------- | ------------- | ------------------ |
| 1   | **Mex #1** (closest)     | 6s        | 0:06          |                    |
| 2   | **Mex #2** (2nd closest) | 6s + walk | 0:14          |                    |
| 3   | **Wind #1**              | 5s        | 0:19          | Near mex cluster   |
| 4   | **Wind #2**              | 5s        | 0:24          |                    |
| 5   | **Wind #3**              | 5s        | 0:29          |                    |
| 6   | **Bot Lab**              | 35s       | 1:04          | Central, protected |
| 7   | **Mex #3**               | 6s + walk | 1:12          | If safe/close      |
| 8   | **Wind #4**              | 5s        | 1:17          |                    |
| 9   | **Wind #5**              | 5s        | 1:22          |                    |
| 10  | **Radar**                | 7.5s      | 1:30          | On high ground     |

### After Queue Completes (~1:30)

**This is where pre-planning ends and reactive play begins.**

Your situation at 1:30:
- 3 Mexes running (~6 M/s)
- 5 Winds running (~35-60 E/s depending on wind)
- Bot Lab almost done or just finishing
- Radar providing vision

**Next priorities (manual):**
1. Queue factory: `Tick → Tick → Grunt → Grunt → Con`
2. Commander continues energy (more wind)
3. Watch for enemy movements on radar
4. Send Ticks to scout when ready

---

# BUILD ORDER B: LOW WIND MAP (Avg Wind < 7)

**Total queue time: ~95 seconds**
**Solar is more expensive but consistent**

## The Queue

| #   | Order        | Time      | Running Total | Notes                  |
| --- | ------------ | --------- | ------------- | ---------------------- |
| 1   | **Mex #1**   | 6s        | 0:06          |                        |
| 2   | **Mex #2**   | 6s + walk | 0:14          |                        |
| 3   | **Solar #1** | 10.5s     | 0:25          | No E cost - good first |
| 4   | **Solar #2** | 10.5s     | 0:36          |                        |
| 5   | **Bot Lab**  | 35s       | 1:11          |                        |
| 6   | **Mex #3**   | 6s + walk | 1:19          |                        |
| 7   | **Solar #3** | 10.5s     | 1:30          |                        |
| 8   | **Radar**    | 7.5s      | 1:38          |                        |
|     |              |           |               |                        |

### After Queue Completes (~1:40)

Your situation:
- 3 Mexes (~6 M/s)
- 3 Solars (60 E/s constant)
- Bot Lab finishing
- Radar up

**Next priorities (manual):**
1. Queue factory: `Tick → Tick → Grunt → Grunt → Con`
2. Commander builds more solar (need ~100 E/s for nano later)
3. Scout with Ticks

---

# BUILD ORDER C: AGGRESSIVE OPENING (Rush Detection Expected)

**Sacrifices some eco for early combat capability**

## The Queue

| # | Order | Time | Running Total | Notes |
|---|-------|------|---------------|-------|
| 1 | **Mex #1** | 6s | 0:06 | |
| 2 | **Mex #2** | 6s + walk | 0:14 | |
| 3 | **Wind/Solar x2** | 10-21s | 0:25-35 | Minimum energy |
| 4 | **Bot Lab** | 35s | 1:00-1:10 | |
| 5 | **Radar** | 7.5s | 1:08-1:18 | EARLY - need vision |
| 6 | **LLT** | 14s | 1:22-1:32 | Defensive position |

### After Queue Completes

- Factory queue: `Tick → Grunt → Grunt → Grunt → Con`
- Commander: More energy, then prepare to D-gun
- Watch radar closely for incoming

---

# BUILD ORDER D: GEOTHERMAL MAP

**If you have a geo vent near spawn - HUGE advantage**

## The Queue

| # | Order | Time | Running Total | Notes |
|---|-------|------|---------------|-------|
| 1 | **Mex #1** | 6s | 0:06 | |
| 2 | **Mex #2** | 6s + walk | 0:14 | |
| 3 | **Wind/Solar x1** | 5-10s | 0:19-24 | Just enough to start |
| 4 | **Geothermal** | 37.5s | 0:57-1:02 | 300 E/s! |
| 5 | **Bot Lab** | 35s | 1:32-1:37 | |
| 6 | **Mex #3** | 6s | 1:38-1:43 | |
| 7 | **Radar** | 7.5s | 1:46-1:51 | |

### After Queue Completes

- You have 300 E/s from geo - energy solved for a while
- Focus on mex expansion and production
- Can afford nano earlier than normal

---

# THE TRANSITION: QUEUE → REACTIVE

## Why the Queue Ends at ~1:30-2:00

After radar goes up, the game requires **decisions based on information**:

| What You Learn | How You React |
|----------------|---------------|
| Enemy expanding safely | Match expansion, eco hard |
| Enemy rushing | Defensive LLT, combat units, com forward |
| Enemy going air | AA turrets IMMEDIATELY |
| Enemy turtling | Out-eco, don't over-commit to army |

**You can't pre-queue reactions.**

## Commander Role After Queue (2:00+)

| Time | Commander Should Be Doing |
|------|--------------------------|
| 2:00-4:00 | Scaling energy, walking toward contested mexes |
| 4:00-6:00 | Building nano turret on factory (if 8 M/s, 100 E/s) |
| 6:00+ | Either: more eco, forward defense, or joining army |

---

# FACTORY QUEUE TEMPLATE

Once factory is up, immediately queue:

## Standard Queue
```
1. Tick (scout)
2. Tick (scout) 
3. Grunt or Pawn (combat)
4. Grunt or Pawn (combat)
5. Constructor (expansion)
6. [Then continue combat units]
```

## Aggressive Queue (enemy rushing)
```
1. Tick (scout)
2. Grunt (combat)
3. Grunt (combat)
4. Grunt (combat)
5. Grunt (combat)
6. Constructor (after you stabilize)
```

## Greedy Queue (enemy passive)
```
1. Tick (scout)
2. Tick (scout)
3. Constructor (fast expansion)
4. Constructor (if very safe)
5. [Then combat when needed]
```

---

# AFTER THE OPENING: DECISION FRAMEWORK

## At ~3:00-4:00 Check Your State

```
Metal income?
├── < 6 M/s → PROBLEM: Expand immediately
├── 6-8 M/s → Normal, continue
└── > 8 M/s → Good, consider nano

Energy income?
├── Stalling → STOP EVERYTHING, build energy
├── 60-100 E/s → Normal for early game
└── > 100 E/s → Good, can support nano

Factory producing?
├── Idle → Queue more units!
├── Producing → Good
└── Stalled → Fix eco first
```

## At ~5:00-6:00 Check Nano Timing

```
Can I build Nano?
├── Metal ≥ 8/s? 
│   ├── Yes → Continue
│   └── No → More mexes first
├── Energy ≥ 100/s?
│   ├── Yes → Continue  
│   └── No → More energy first
└── Both yes? → BUILD NANO ON FACTORY
```

## At ~8:00-10:00 Check T2 Path

```
Should I start T2?
├── Metal ≥ 20/s? 
│   ├── Yes → Continue
│   └── No → More expansion
├── Energy ≥ 500/s?
│   ├── Yes → Continue
│   └── No → More energy (lots more)
├── Metal stored ≥ 1000?
│   ├── Yes → Continue
│   └── No → Build storage, bank up
└── All yes? → START ADV BOT LAB
```

---

# COMMON OPENING MISTAKES

| Mistake | Why It's Bad | Fix |
|---------|--------------|-----|
| Building factory before 2 energy | You'll E-stall | Always 2-3 energy first |
| Not queuing during countdown | Wasted time at start | Use full 120s to queue |
| Walking com too far early | Lost build time | Keep early builds close |
| Forgetting radar | No information | Always include radar |
| Factory with no queue | Idle production | Queue 5+ units immediately |
| Building nano before eco ready | Hard stall | Wait for 8M/100E |

---

# QUICK REFERENCE: COPY-PASTE BUILD ORDERS

## Wind Map (≥7 avg)
```
SHIFT-QUEUE:
Mex → Mex → Wind → Wind → Wind → Bot Lab → Mex → Wind → Wind → Radar

FACTORY QUEUE:
Tick → Tick → Grunt → Grunt → Con → [combat]
```

## Solar Map (<7 avg)
```
SHIFT-QUEUE:
Mex → Mex → Solar → Solar → Bot Lab → Mex → Solar → Radar

FACTORY QUEUE:
Tick → Tick → Grunt → Grunt → Con → [combat]
```

## Aggressive
```
SHIFT-QUEUE:
Mex → Mex → Wind/Solar x2 → Bot Lab → Radar → LLT

FACTORY QUEUE:
Tick → Grunt → Grunt → Grunt → Grunt → Con
```

---

# TIMING BENCHMARKS

**Use these to check if you're on track:**

| Time | You Should Have |
|------|-----------------|
| 0:30 | 2 mex, 2-3 energy building |
| 1:00 | 2-3 mex, factory building |
| 1:30 | 3 mex, factory almost done, radar building |
| 2:00 | Factory producing, 5-6 energy |
| 3:00 | First scouts out, con expanding |
| 4:00 | 4-6 mex, ~80 E/s |
| 5:00 | 6-8 mex, ~100 E/s, considering nano |
| 6:00 | Nano building or just finished |

If you're significantly behind these benchmarks, you're probably:
- Walking commander too far
- Not queuing efficiently
- Resource stalling somewhere

---

# ADVANCED: MAP-SPECIFIC OPENERS

Different maps have different optimal openings. Here are principles:

## Small Maps (Supreme Battlefield, etc.)
- Faster aggression likely
- Consider early LLT
- Radar very important (short distances)
- Less time to eco before contact

## Large Maps (Red Comet, etc.)
- More time to eco
- Expansion is key
- Can afford greedier opening
- Air becomes more viable

## Choke Maps
- Defenses very valuable
- Control the choke early
- Can turtle more safely

## Open Maps
- Army quality matters more
- Defenses less effective
- Mobile warfare
- Consider vehicles

---

*Next step: Play 5 games using the appropriate build order. Focus on executing the queue perfectly and hitting the timing benchmarks.*
