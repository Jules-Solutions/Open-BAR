# Research Report 09: AI Training Strategy for BAR

> **Session:** Session_2
> **Date:** 2026-02-16
> **Status:** DRAFT — Needs Jules's review before presenting to Discord group
> **Origin:** Jules's initial idea + community feedback from RobotRobert03 and MrDeadKingz

---

## Table of Contents

1. [The Vision](#1-the-vision)
2. [The Pushback (And Why It's Partially Right)](#2-the-pushback-and-why-its-partially-right)
3. [The Hybrid Architecture](#3-the-hybrid-architecture)
4. [Data Pipeline](#4-data-pipeline)
5. [Training Methodology](#5-training-methodology)
6. [What We Need to Build](#6-what-we-need-to-build)
7. [Timeline and Phases](#7-timeline-and-phases)
8. [Open Questions](#8-open-questions)

---

## 1. The Vision

**Jules's original idea:**
> "Train it on replay data and let it fight headless mode against AI and 'dynamic averaged replays'. With some reinforcement learning I am curious how it would go. Cause hardcoding will in the end always be exploitable."

This is the right instinct. Hard-coded AI is fundamentally limited:
- **Exploitable** — Players find patterns and cheese them
- **Brittle** — Balance changes break assumptions
- **Static** — Can't adapt to new strategies or meta shifts
- **Labor-intensive** — Felenious has 1600+ hours of manual tuning

The question isn't *whether* ML/RL can help, but *where in the stack* it adds value and *what approach* is practical given BAR's constraints.

---

## 2. The Community Debate (And What's Actually Right)

### RobotRobert03's concerns:
1. "Not enough replay data" for training
2. "Bad games" pollute the dataset — hard to filter quality
3. "Balance updates" invalidate historical data every season
4. "1v1 training doesn't transfer to 8v8"
5. "So many variables... the scope would be challenging and massive"

### ACowAdonis's key insight (Feb 15):
> Replays are timestamped command logs, NOT game state. The simulation creates the meaning.

This is critical. A replay says "build solar at (1200, 800) at frame 2700." It does NOT say: was the player floating energy? Was there an incoming raid? Was this the right call? The gap between commands and outcomes is the simulation.

### Noodles's proposals (Feb 14-15):
1. **LLM-on-commands**: Treat game commands as a language, train a next-command predictor. Condition on vision input (video or structured state).
2. **Compartmentalized ML**: Use ML for specific decisions (what to build, where to deploy, push/hold/raid) rather than end-to-end control.
3. Has access to an **HPC cluster** for training.

### What's valid from each:
- **RobotRobert03**: Replay data IS limited and balance-dependent. Correct.
- **ACowAdonis**: Command logs without simulation context ARE insufficient for learning tactical decisions. Correct. He also has 800GB of replays + a replay parser exists (pandaro confirmed).
- **Noodles**: LLM approach CAN work for command prediction with the right conditioning. Compartmentalized ML is the right decomposition. HPC access is a game-changer.
- **Felenious**: "Show me something working" is the right bar. Practical results over theoretical debate.
- **TheBlindjin**: Headless speed is the critical bottleneck question. Untested.

### The synthesis:
- **For build orders and eco timing**: Replay command logs ARE sufficient (these are player decisions, not simulation outcomes)
- **For tactical and strategic decisions**: Self-play with full state access is required (ACowAdonis is right)
- **For architecture**: Compartmentalized ML on top of rule system (Noodles is right, and it's what we proposed)
- **For training data generation**: Self-play solves the data scarcity problem (not dependent on replays)
- **For credibility**: Deliver the block placement system first (Felenious is right)

**The biggest insight: you don't need ML to play the game. You need it to tune parameters faster than humans can.**

### Available resources revealed in the conversation:
| Resource | Who Has It | Size/Details |
|----------|-----------|--------------|
| Historical replays | ACowAdonis | 800GB (2019-2026) |
| Historical replays | Felenious | 730GB (2019-2026) |
| Replay parser | pandaro confirmed it exists | Unknown location |
| HPC cluster | Noodles | For training |
| Game data pipeline | Jules (us) | Building now — widgets, sim, export |
| Barb3 internals | Felenious | 1600 hours of domain knowledge |

---

## 3. The Hybrid Architecture

The key idea: **ML doesn't replace the rule system. It accelerates the tuning of the rule system.**

```
┌─────────────────────────────────────────────────────────────┐
│                    THE STACK                                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Layer 4: SELF-PLAY OPTIMIZER (RL)               [Phase 5+] │
│  ├── Runs headless matches between AI variants               │
│  ├── Tunes Layer 2 & 3 parameters automatically              │
│  ├── Compresses 1600 hours of manual tuning into days        │
│  └── Generates training data as a byproduct                  │
│                                                              │
│  Layer 3: DATA-INFORMED CALIBRATION              [Phase 3-4] │
│  ├── Replay-derived timing benchmarks (per map, per role)    │
│  ├── Build order effectiveness scoring                       │
│  ├── Unit composition win rates by game phase                │
│  └── Updates the rule system's constants/thresholds          │
│                                                              │
│  Layer 2: PARAMETERIZED RULE SYSTEM              [Phase 2]   │
│  ├── Block placement templates (our quest)                   │
│  ├── Factory production ratios (Felenious's config JSONs)    │
│  ├── Economy thresholds (when to tech, when to expand)       │
│  ├── Defense timing and placement rules                      │
│  └── All parameters exposed as tunable configs               │
│                                                              │
│  Layer 1: HARD-CODED FOUNDATION                  [Phase 1]   │
│  ├── CircuitAI C++ engine (builder, economy, military mgrs)  │
│  ├── Game API interaction (Spring callbacks)                  │
│  ├── Basic pathfinding, threat evaluation                     │
│  └── Core game loop and state management                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**The insight:** Felenious's 1600 hours mostly went into Layers 1-2. The block placement quest adds to Layer 2. Layers 3-4 are what Jules brings to the table — the data science and ML expertise to accelerate what Felenious does manually.

---

## 4. Data Pipeline

### 4.1 Data Sources

| Source | Data Type | Volume | Freshness | Effort |
|--------|-----------|--------|-----------|--------|
| BAR replay archive | Full game replays (.sdfz) | 1000s of games | Mixed (patch versions) | Medium (scraper needed) |
| In-game export (our widgets) | Economy snapshots, unit census, build timing | Per-game | Always current | Low (already building) |
| Headless self-play | Full game state at tick resolution | Unlimited | Always current | High (headless setup) |
| BAR API / stats pages | Match results, player ratings | Large | Current | Low (if API exists) |
| Unit database | Unit stats, costs, abilities | Complete | Per-patch | Already have (bar_units.db) |

### 4.2 Game State Recorder

**What we need to capture per game (every N seconds):**

```python
GameStateSnapshot = {
    "tick": int,                    # Game frame number
    "time_seconds": float,          # Real game time

    # Economy
    "metal_income": float,
    "metal_usage": float,
    "metal_storage": float,
    "energy_income": float,
    "energy_usage": float,
    "energy_storage": float,

    # Units
    "unit_counts": {                # Per unit type
        "armwin": 12,
        "armsolar": 4,
        "armlab": 1,
        ...
    },
    "total_metal_value": float,     # Army + buildings
    "total_buildpower": float,

    # Territory
    "mex_count": int,
    "mex_positions": [(x, z), ...],
    "base_center": (x, z),
    "base_radius": float,
    "territory_area": float,

    # Military
    "army_value": float,
    "army_composition": {...},
    "kills": int,
    "losses": int,

    # Build orders
    "recent_builds": [              # Last N buildings placed
        {"type": "armwin", "position": (x, z), "time": float},
        ...
    ],
    "factory_queue": [...],
}
```

**Where this runs:**
- **Lua widget** for live games (our TotallyLegal overlay already tracks most of this)
- **Python parser** for replay analysis
- **Headless mode hook** for self-play training

### 4.3 Replay Processing Pipeline

```
Replay Archive (.sdfz files)
       │
       ▼
┌──────────────────┐
│  Filter by:       │
│  - Engine version │ (current patch only)
│  - Game mode      │ (team games for team AI, 1v1 for 1v1 AI)
│  - Player OS      │ (high rated = better data)
│  - Completion     │ (no early quits)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Parse replay:    │
│  - Extract events │ (build, move, attack commands)
│  - Sample state   │ (every 30 seconds)
│  - Tag phases     │ (early/mid/late game)
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────┐
│  Feature extraction:          │
│  - Build order sequences      │
│  - Factory timing benchmarks  │
│  - Eco trajectory curves      │
│  - Unit composition over time │
│  - Building placement patterns│
│  - Win/loss outcome label     │
└──────────────────────────────┘
```

---

## 5. Training Methodology

### 5.1 Phase 1: Imitation Learning (Learn From Experts)

**Goal:** Extract "what good players do" as calibration targets.

**Not** training a neural network to play. Instead:
- **Build order benchmarks:** "On Supreme Isthmus, front players average first T2 at 4:30 with 8 wind, 2 solar, 1 lab"
- **Timing distributions:** "First factory typically at 0:45-1:15, second at 2:00-3:00"
- **Eco curves:** "Winning players hit 20 metal income by 3:00, 40 by 6:00"
- **Unit mix patterns:** "At 10 minutes, winning armies are typically 60% raiders, 30% brawlers, 10% AA"

These become **target parameters** for the rule system. Instead of Felenious manually tuning "build factory at tick X", we say "build factory when your eco curve matches the benchmark."

### 5.2 Phase 2: Parameter Optimization (Bayesian/Evolutionary)

**Goal:** Auto-tune the hundreds of config values in Barb3's JSON files.

Barb3 has tunable parameters everywhere:
- `factory.json` — unit production ratios
- `economy.json` — build thresholds
- `build_chain.json` — adjacency triggers
- `behaviour.json` — aggression levels, expansion timing
- Our new `block_templates.json` — block sizes, spacing, placement priority

**Method:**
1. Define a fitness function: win rate against baseline AI + eco efficiency + space utilization
2. Use Bayesian optimization or evolutionary strategies to search the parameter space
3. Each evaluation = run N headless games with candidate parameters
4. Converge on optimal parameter sets per map type

**Why this works for BAR:**
- Parameter space is finite and structured (JSON configs)
- Each game is 10-20 minutes — feasible to run 100s per day in headless
- Fitness is clear: win/loss + secondary metrics
- No neural network needed — just smart search over configs

### 5.3 Phase 3: Self-Play RL (The Ambitious Part)

**Goal:** Train sub-policies that make dynamic decisions based on game state.

**NOT** end-to-end "learn to play from raw pixels." Instead, modular RL for specific decisions:

| Sub-Policy | Input | Output | Why RL Helps |
|------------|-------|--------|--------------|
| Factory timing | Eco state, map position, role | "Build factory now" / "Wait" | Dynamic vs static threshold |
| Tech transition | Eco curve, army state, threat level | "Go T2 now" / "Build more T1" | Depends on opponent behavior |
| Aggression level | Army strength, enemy position, map control | "Attack" / "Defend" / "Expand" | Requires reading the game state |
| Build priority | Available space, eco state, block status | "More wind" / "Solar" / "Defense" | Context-dependent optimization |

**Method:** Proximal Policy Optimization (PPO) or similar, training against self-play variants.

**Key constraint:** The RL policies **advise** the rule system, they don't replace it. The rule system always has a valid default. The RL component just nudges timings and priorities.

---

## 6. What We Need to Build

### Already Have / Building
- [x] Unit database (bar_units.db, unitlist.csv)
- [x] Economy tracking widgets (TotallyLegal overlay)
- [x] Build order simulation (sim/bar_sim)
- [x] CLI tools (sim/cli.py)
- [ ] Block placement system (current quest)

### Need to Build (Data Layer)
- [ ] Replay scraper for beyondallreason.info/replays
- [ ] Replay parser (sdfz → game state snapshots)
- [ ] Game state recorder widget (extend TotallyLegal)
- [ ] Feature extraction pipeline
- [ ] Training data storage (SQLite or Parquet)

### Need to Build (Training Layer)
- [ ] Headless mode launcher script (batch game runner)
- [ ] Fitness function evaluator
- [ ] Parameter optimization framework (Optuna or similar)
- [ ] Results dashboard (extend web UI)

### Need to Build (RL Layer — Stretch)
- [ ] Game state → observation space converter
- [ ] Action space definition per sub-policy
- [ ] PPO training loop
- [ ] Policy → JSON config exporter
- [ ] Self-play match scheduler

---

## 7. Timeline and Phases

| Phase | Focus | Depends On | Output |
|-------|-------|------------|--------|
| **Now** | Block placement quest | Felenious answers | Working block templates in Barb3 |
| **Phase 1** | Data pipeline | Block placement done | Replay scraper, game state recorder, feature extraction |
| **Phase 2** | Benchmarking | Data pipeline | Build order / timing / eco benchmarks per map |
| **Phase 3** | Parameter optimization | Headless mode working | Auto-tuned JSON configs that outperform manual tuning |
| **Phase 4** | Self-play framework | Parameter optimization | Headless batch runner, fitness evaluation |
| **Phase 5** | RL sub-policies | Self-play framework | Dynamic decision-making that adapts to opponents |

**Critical path:** The block placement quest is Phase 0 — it proves we can modify Barb3 effectively and establishes the dev workflow. Everything else builds on top of that.

---

## 8. Noodles's LLM-on-Commands Approach (New Avenue)

Noodles proposed training a language model on game commands — essentially treating BAR gameplay as a sequence prediction problem. This deserves its own analysis.

### How It Would Work

```
Replay command stream:
  [frame 0]    BUILD armcom (1200, 800)
  [frame 45]   MOVE armcom (1300, 850)
  [frame 90]   BUILD armwin (1232, 816)
  [frame 135]  BUILD armwin (1248, 816)
  ...

Tokenize → Train transformer → Predict next command
```

Condition on:
- Map layout (static input)
- Current game state (structured: resources, unit counts, territory)
- Or: video frames from replay playback (vision component)

### Strengths
- Learns player patterns implicitly (build order culture, timing conventions)
- Generative — can produce novel strategies by combining patterns
- Noodles has HPC access and expertise to train this
- Replay data IS available (1.5TB+ between ACowAdonis and Felenious)

### ACowAdonis's Valid Critique
Commands alone don't capture game state. The model doesn't know:
- Why a player built that building (enemy rushing? eco booming? defensive?)
- What happened between commands (units died, eco stalled, territory lost)
- Whether the command was GOOD (the player might be losing)

### Our Fix: Structured State Conditioning
Instead of raw video, use structured game state extracted from simulation:

```python
StateVector = {
    "resources": [metal_income, energy_income, metal_storage, ...],
    "units": [type_counts_array],  # 100+ unit types
    "territory": [mex_count, base_radius, frontline_distance],
    "threats": [enemy_army_value, incoming_raid_detected, ...],
    "build_state": [factories_count, pending_builds, ...],
    "game_phase": [early/mid/late encoding],
}
```

This is WAY more information-dense than video and directly maps to decision-relevant features.

### How This Connects to Our Work
1. We're already building the game state extraction (TotallyLegal widgets)
2. Our simulator can generate state vectors from replays
3. The block placement system gives us a concrete first test case
4. If Noodles trains the model, we provide the data pipeline and game integration

### Collaboration Model
| Person | Contribution |
|--------|-------------|
| **Jules (us)** | Data pipeline, game state extraction, Barb3 integration, block placement |
| **Noodles** | LLM training, model architecture, HPC compute |
| **ACowAdonis** | Replay data (800GB), replay parsing expertise, theoretical grounding |
| **Felenious** | Domain knowledge, validation, "does this look right?" testing |
| **TheBlindjin** | Headless mode testing, infrastructure |

---

## 9. Open Questions

| Question | Impact | Who Can Answer | Status |
|----------|--------|----------------|--------|
| How fast can headless BAR run? (up to 999x — actual throughput is CPU-bound) | Critical for self-play training feasibility | Testing needed / TheBlindjin interested | **Top priority to benchmark** |
| Where is the replay parser pandaro mentioned? | Affects data pipeline timeline | pandaro / BAR community | Ask in Discord |
| What's the replay format (.sdfz) structure exactly? | Affects parsing approach | ACowAdonis (has parsed them) | Ask ACowAdonis |
| Can we hook into the game loop from Python for state extraction? | Affects training loop architecture | Spring engine docs | Research needed |
| Does BAR have a headless mode launcher? How to configure? | Critical for self-play | BAR devs / Spring docs | Research needed |
| Are there existing Spring RTS ML/RL projects to learn from? | Could save months of work | Research needed | Search GitHub/papers |
| Does the BAR API expose match statistics? | Affects benchmarking | BAR website / API docs | Check website |
| Can Noodles's HPC cluster run headless BAR? (Linux support?) | Affects training scale | Noodles + testing | Ask Noodles |
| What tokenization scheme works for BAR commands? | Affects LLM approach | Noodles + us | Design together |

---

## Key Pitch Points (For Discord)

When presenting to the group, emphasize:

1. **"This isn't replacing what Felenious built."** It's accelerating the tuning process. The rule system stays. ML tunes the knobs.
2. **"We don't need millions of replays."** Self-play generates its own data. Replays are for initialization and benchmarking, not primary training.
3. **"It's modular, not monolithic."** We're not training one big model. We're tuning specific parameters and training specific sub-decisions.
4. **"Balance patches aren't a problem."** Because we retrain from the current rule system + current game data. Not from historical replays.
5. **"The block placement quest is step zero."** It proves the workflow and gives us a concrete deliverable before we touch any ML.

---

*This strategy positions Jules at the intersection of Felenious's domain expertise (1600 hours of game knowledge) and modern AI tooling (data pipelines, optimization, RL). The goal isn't to compete with Felenious — it's to give him superpowers.*
