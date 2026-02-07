# TotallyLegalWidget -- Brainstorm 1 (Structured)

> BAR (Beyond All Reason) widget suite: from visual overlays to full strategic automation.
> The game is open source and encourages community widgets. This repo will be **public** and shared on the BAR Discord.

---

## Project Principles

1. **Public & Shared** -- Repo is public; shared on the BAR Discord per the "mystery advantage" policy (widgets must be publicly available).
2. **Two Operating Modes** (from day 1):
   | Mode | Default For | Allowed |
   |------|-------------|---------|
   | **All** | Unranked / PvE / Custom | Full automation |
   | **No Automation** | PvP / Ranked | Visual + input convenience only |
3. **No Hardcoded Paths** -- Keep everything configurable for long-term maintainability.
4. **Research First** -- Survey existing BAR widgets, frameworks, and community repos before building anything.

---

## Open Research Questions

- Is there a Python-Lua bridge library (or a BAR-specific one)?
- What widgets already exist in the BAR community? Which ones overlap with our goals?
- Are there existing widget frameworks or boilerplate repos?
- Is a Python interface useful, or is raw Lua sufficient for everything?
- How does the engine expose map data (terrain, buildability, pathability)? Is a custom spatial index needed or is this already solved?

---

## Feature Roadmap

### Tier 1 -- Standalone Widgets (Small Scope)

| Widget                 | Description                                                     |
| ---------------------- | --------------------------------------------------------------- |
| **Auto Skirmishing**   | Units automatically kite and engage at optimal range            |
| **Automated Rezbots**  | Resurrection bots autonomously prioritize and reclaim/resurrect |
| **Projectile Dodging** | Units dodge incoming projectiles when possible                  |

### Tier 2 -- Python-Lua Interface Library

A reusable module/library that bridges Python scripting to BAR's Lua widget API.

**Core capabilities:**
- Game lifecycle hooks: `ServerLoaded`, `LocationChosen`, `GameStarted`, etc.
- Read game state (units, resources, map, economy)
- Issue build orders and unit commands (automation mode only)
- Scriptable strategy logic (e.g., `if energy_surplus > 70: build_converter()`)

**Map Intelligence subsystem:**
- On game start, build a spatial index (vector DB or grid) of the map
- Per-coordinate attributes: buildable, pathable by ground/vehicle/air, elevation, terrain type
- Used by all higher-tier automation features

### Tier 3 -- Strategic Automation Engine ("Goal Achievement System")

The core vision: change the game from micromanagement to **issuing general orders**.

#### 3a. Pre-Game Strategy Configuration

Before the match starts, define:

| Parameter              | Options / Range                                        |
| ---------------------- | ------------------------------------------------------ |
| Faction                | Armada / Cortex                                        |
| Start location         | Map pick                                               |
| Opening mex count      | 1--4                                                   |
| Unit composition       | Infantry / Vehicle / Mixed / ...                       |
| Role                   | Eco / Aggro / Support / ...                            |
| Primary defense line   | Map-drawn line (never falls)                           |
| Secondary defense line | Map-drawn line (the active front)                      |
| Building area          | Map-drawn zone                                         |
| Lane assignment        | Left / Center / Right / ...                            |
| Wind/energy strategy   | Auto / Opening only / Wind only / Solar only / % split |
| Posture                | Defensive / Offensive                                  |
| T2 transition plan     | Solo T2 / Receive T2 con from teammate at minute X     |

#### 3b. Goal & Project Queue

Define an ordered list of goals/projects. Each is achieved as efficiently as possible given the strategy and map.

**Example goals:**
- Get 5 medium tanks to the frontline
- Get T1 lab running at X build power
- Build light T1 defenses for base; medium for front
- Scale economy until con 2 bot arrives
- Transition to T2 economy
- Get T2 lab running at X build power
- Reach T3 with X build power
- Build a nuke
- Build long-range plasma cannon at location Y
- Produce X Titans

**Resource allocation controls:**
| Slider | Purpose |
|--------|---------|
| Econ vs. Units | % of resources to economy scaling vs. unit production |
| Savings / Team share | % of resources reserved for storage or gifted to allies |
| Project funding | % of resources dedicated to special projects (nukes, cannons, titans) |
| Auto mode | Let the system decide allocation dynamically |

**Project orders:** Place a structure (e.g., long-range plasma cannon) on the map. The system allocates or frees resources and builds it. For unit-based projects (e.g., "50 Titans"), the system calculates the most efficient production path.

#### 3c. Build Order Execution

- On game start, automatically places optimal opening build orders
- Queues correct units
- Manages build orders to minimize resource waste (no stalling, no overflow)
- Generates an economic prediction timeline for the chosen strategy

#### 3d. Frontline & Troop Management

No micromanagement. Define lines and posture; units act autonomously.

**Defense:**
- Primary line: last stand, units defend to the death
- Secondary line: active front, can be pushed or pulled
- Units auto-engage, kite, and dodge within their zone
- Dynamic reaction to enemy unit ranges

**Attack strategies:**

| Strategy | Description |
|----------|-------------|
| **Creeping Forward** | Slowly advance the front line toward the enemy base core |
| **Piercing Assault** | Concentrate fire on one point; push deep into enemy territory; engage only mobile units and static defenses |
| **Fake Retreat** | Small force engages outside jammer range, retreats on contact, lures enemy into a kill zone of hidden long-range units that hold fire until triggered |
| **Anti-Anti-Defense Raid** | Fast assault targeting AA, anti-nukes, plasma shields, jammers -- clearing the path for an air strike |
| *(more TBD)* | |

**Emergency modes:**

| Mode | Behavior |
|------|----------|
| **Defend Base (Life & Death)** | Temporarily maximize unit production (unsustainably); all units guard base from the attack direction; engage everything within base radius |
| **Mobilization** | Temporarily maximize T1/T2 production (unsustainably) to flood the front with reinforcements |

### Tier 4 -- PvP Overlay (Visual, Ranked-Safe)

Information overlay for competitive play (no automation, read-only).

| Feature | Detail |
|---------|--------|
| **Resource production breakdown** | Per unit type: e.g., windmills = 200 E/s, solar = 15 E/s |
| **Unit census** | Count of each unit type currently alive |
| **Build power dashboard** | Total BP, active BP, idle BP, stalling BP |
| **Priority highlights** | Large glowing circles around high-priority targets/assets |
| **Timeline graph** | Expected vs. predicted vs. actual economy over time with checkpoints |
| **Threat estimator** | Estimates enemy capabilities based on scouting + elapsed time. E.g., after first T2 unit spotted, start timers for: nuke silo construction + nuke production (adjusted by estimated BP). Shows risk bands: "T2 units possible" -> "T2 units likely" -> "T3/superweapons possible" |

### Tier 5 -- Build Order Simulator ("Simulation of the Simulation")

Offline tool for designing and optimizing build orders with hard math.

- Define map parameters and available build area
- Simulate resource income, build times, unit output
- Compare build order variants with exact numbers
- Solve: "Is this 5% optimization actually better?" without waiting 5 minutes in-game
- Iterate rapidly on openings and macro plans

### Tier 6 -- AI Agent (PvE / Demo Only)

If Tiers 1--5 are built, we have all the primitives to let an AI play the game.

- Adaptive, strategic AI player
- Combines: symbolic reasoning + semantic understanding + reinforcement learning
- Has memory across games
- Target: OS rating over 9000
- **Strictly PvE and agent software demos** -- not for ranked play

---

## Development Approach

### Phase 1: Research & Foundation
1. Survey existing BAR widgets, community repos, and frameworks
2. Determine if a Python-Lua bridge is viable or if pure Lua is the way
3. Start from an existing widget as a base

### Phase 2: Visual First (Ranked-Safe)
1. Draw overlays and UI panels (Tier 4 features)
2. Read game state (units, selection, resources)
3. Add UI controls and settings
4. No `GiveOrder`-type API calls

### Phase 3: Input Convenience
1. Selection helpers, smart UI shortcuts
2. Still non-automating
3. Check if goals are achievable via keybinds/uikey tweaks or existing widget config before writing new code

### Phase 4: Automation (PvE/Unranked Only)
1. Build Tier 1 standalone widgets (skirmishing, rezbots, dodging)
2. Build Tier 2 Python-Lua interface
3. Build Tier 3 strategic automation engine
4. Build Tier 5 offline simulator

### Phase 5: AI Agent (Experimental)
1. Integrate all tiers into an autonomous player
2. Reinforcement learning loop
3. PvE testing and demos

### Guiding Principle

> Work with the game, not dominate it on day 1.

- Start visual, then convenience, then automation, then AI.
- If deeper behavior changes are needed, move to game-side (gadget/mod) work and use the BAR dev workflow.
- Keep everything shareable and policy-compliant.
