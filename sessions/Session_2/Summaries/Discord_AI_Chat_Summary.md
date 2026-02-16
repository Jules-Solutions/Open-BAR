# Discord AI Chat Summary

> **Source:** `Discord_Chats/AI Discord Chat History.md`
> **Messages:** 58 | **Period:** Dec 24-30, 2025
> **Extraction Date:** Feb 13, 2026

---

## Key Participants

| Name                    | Role / Tags                     | Key Contributions in This Chat                                                                                                                                                                       |
| ----------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[SMRT]Felnious**      | 1600 Hours AIdev                | Primary AI developer. Controls what AI builds, where it walks, attacks. Working on Legion Navy/Seaplanes hotfix. Confirmed total control over AI behavior via JSON/AS config. Promised Starfall fix. |
| **lamer**               | Contributor (CircuitAI dev)     | Core engine-level insights: task state machines, `Unit::Capture` / `Unit::ExecuteCustomCommand` API proposals, CircuitAI AngelScript code references, DefendTask concept.                            |
| **sam (73 61 6d)**      | Player / Tester                 | Reported AI difficulty regression: 1v2'd Hard AI too easily on Great Divide and Center Command.                                                                                                      |
| **Seth Gamre**          | Lead Surveyor (Team Leader)     | Proposed "Space Race" game mode concept involving capture objectives. Noted Barbs have no capture or objective awareness.                                                                            |
| **[SMRT]RobotRobert03** | Community / Tester              | Noted assist drones use capture but commanders do not. Confirmed Starfall disabled for AI. Community commentary.                                                                                     |
| **Isfet Solaris**       | Player / Tester                 | Reported AI lava pathfinding bug: AI walks into lava treating it like water.                                                                                                                         |
| **Arxam**               | AI researcher / Newcomer        | Investigated CircuitAI/AngelScript hooks. Working on efficiency equations (metal-over-time for units/actions). Building custom AI code; asked about AI performance showcase repos.                   |
| **sicbastard**          | Community                       | Asked how tasks work; offered to help Arxam; asked about ghost building memory (LOS issue).                                                                                                          |
| **Bones**               | Player / Tester                 | Asked about Starfall status for AI. Commentary on Legion polish and Starfall model.                                                                                                                  |
| **ZephyrSkies**         | Community                       | Confirmed Armada/Cortex will get same polish treatment as Legion. Posted meme gif.                                                                                                                   |
| **Damgam**              | Audio Design Lead (Team Leader) | Reacted with meme gif. Minimal technical contribution in this window.                                                                                                                                |

---

## Timeline of Discussions

### Dec 24, 2025 -- AI Difficulty, Capture Mechanics, Lava Pathing, Build Orders

**AI difficulty regression (sam, msg 2-3)**
- sam reported beating Hard AI in a 1v2 with little effort on Great Divide and Center Command.
- Medium AI described as "trashy at building" but still applies map pressure; Hard AI "normally relatively hard to hold a line in 1v2" but not anymore.

**Space Race game mode concept (Seth Gamre, msg 4)**
- Proposed a race-to-capture-a-spaceship mode. Barbs currently have zero capture or objective awareness.

**Capture mechanics (RobotRobert03 + lamer, msg 5, 9-11)**
- Commanders don't use capture; assist drones do.
- lamer proposed solutions: spawn a special drone unit every N minutes, disable AI control on spawn, give it a capture command. OR adjust decoy commander probability weights via JSON config to enable capture behavior.
- lamer proposed adding `Unit::Capture` or a more general `Unit::ExecuteCustomCommand` to the AngelScript interface.
- lamer also noted a `DefendTask` with a specific unit target would be useful.

**Lava pathfinding bug (Isfet Solaris, msg 6-8)**
- AI walks directly into lava, treating it as water. No known fix at the time.

**Build orders and map customization (Felnious, msg 12)**
- AI uses a generic build order across ALL maps; build orders are NOT currently customizable per map.
- Felnious planned to look at smaller maps for specific build orders but noted small maps are too fast for AI to ramp up.

### Dec 26, 2025 -- Legion Navy Hotfix, Task Architecture

**Legion Hotfix #1 Navy/Seaplanes PR (Felnious, msg 13)**
- PR #6501 merged. Fixes include: T2 Lab placement issue, Economy Block_Map updated for Legion new buildings, Legion Sea Labs better opening, created new variants.

**Task system architecture (sicbastard + lamer, msg 14-15)**
- sicbastard asked how tasks work.
- lamer answered: tasks work "like states in a state machine."

### Dec 27, 2025 -- CircuitAI Exploration, Total AI Control, Efficiency Equations

**CircuitAI/AngelScript investigation (Arxam, msg 16, 19)**
- Arxam explored extracting hooks/calls from `.as` files and creating new files with different calls from `.as` and `.json`.
- Looked into CircuitAI and AngelCode, decided assembly-level work was too low-level.

**Felnious demonstrates total AI control (Felnious, msg 17-28)**
- Posted 5 screenshots demonstrating AI control capabilities.
- Stated explicitly: "I have total control over what the AI can and can't do" -- where to walk, where to build, where to attack, what/when/how many.
- Joked about drawing profanity with walls using AI ("but COC" -- code of conduct).

**Efficiency equations (Arxam, msg 30-33)**
- Arxam working on translating any unit/action into metal-over-time as an efficiency metric.
- Has rough start with eco and converter math plus unit pricing.
- Needed build power and build time conversion; eventually solved it independently.

### Dec 28, 2025 -- Arxam's Progress, AI Showcase

**Arxam's custom AI code (Arxam, msg 37-38)**
- Code written, starting bug hunting.
- Asked about repos or showcase options to present AI performance, using existing AI as contrast/baseline.

### Dec 29, 2025 -- Ghost Buildings, Starfall Status

**Ghost building memory / LOS issue (sicbastard, msg 41)**
- Asked how to get previously discovered buildings. Bot only sees structures in current LOS, ignores "ghost" buildings on the map.
- No answer provided in this chat window.

**Starfall disabled for AI (Bones + RobotRobert03, msg 42-43)**
- Confirmed: AI still has Starfall disabled.

### Dec 30, 2025 -- Starfall Fix, Legion Polish, Community Banter

**Starfall fix incoming (Felnious, msg 44)**
- Felnious promised a fix "soon" for AI Starfall capability.
- Community reaction: universal dread about AI getting Starfall ("we are all dreading the day it gets added").

**Legion polish and faction parity (msg 51-56)**
- New Starfall model praised, wind-up mechanic highlighted.
- Legion's polish improvements noted; hope expressed that Armada and Cortex will receive the same treatment.
- ZephyrSkies confirmed they will.

---

## Technical Insights

### AI Architecture

- **Task system = state machine.** Each task operates like a state in a state machine (lamer, msg 15). This is the core mental model for understanding AI behavior flow.
- **Control granularity is total.** Felnious confirmed the AI dev has full control over: movement (where to walk), construction (where to build), combat (where to attack), production (what, when, how many) (msg 21-25).
- **AngelScript (`.as`) + JSON config** is the interface layer. The `.as` files contain hooks and calls; `.json` files contain configuration parameters like probability weights and build orders.
- **CircuitAI** is the underlying AI framework. It uses AngelScript for scripting. The barbarian branch is the relevant fork: `rlcevg/CircuitAI` on the `barbarian` branch.
- **Unit control API:** lamer proposed `Unit::ExecuteCustomCommand` as a general-purpose command interface, beyond just `Unit::Capture` (msg 10). This would allow execution of any game-specific or engine built-in command.
- **Ghost building awareness** is a known gap: bots only see structures currently in LOS, losing track of previously scouted enemy buildings (sicbastard, msg 41). No solution was offered in this chat.

### Building Logic

- **Generic build order across all maps.** The AI currently uses one build order for every map. There is NO per-map customization. Felnious acknowledged this is a problem, especially for smaller maps where game pace is too fast for the AI's generic ramp-up (msg 12).
- **T2 Lab placement issue** was fixed in PR #6501 (Legion-specific).
- **Economy Block_Map** was updated to include Legion's new buildings (PR #6501).
- **Build placement is fully controllable** -- Felnious can dictate exactly where to build (msg 23), but this control has not been exposed as per-map configuration yet.

### Unit Production & Balance

- **AI difficulty regression reported.** Hard AI in 1v2 felt much easier than expected on Great Divide and Center Command (sam, msg 2-3). Medium AI still applies map pressure despite poor building, but Hard AI failed to maintain line pressure.
- **Starfall is disabled for AI.** Confirmed by RobotRobert03 (msg 43). Felnious working on enabling it (msg 44).
- **Efficiency equations.** Arxam is independently developing a metal-over-time efficiency metric for all units/actions, incorporating eco, converter math, unit pricing, build power, and build time (msg 30-33).

### Game Mode Concepts

- **Space Race** (Seth Gamre, msg 4): A race to capture a massive war spaceship in the center of the map. Requires AI to understand capture and objectives -- neither of which Barbs currently support.
- **Capture mechanics workarounds** (lamer, msg 9): Spawn special drone units with capture commands, or configure decoy commanders with adjusted probability weights via JSON. Disable normal AI control on these units and give direct orders.

### Legion Faction Updates

- **PR #6501: Legion Hotfix #1 Navy/Seaplanes** (Dec 25, 2025)
  - Fixed T2 Lab placement issue
  - Fixed Economy Block_Map to include Legion new buildings
  - Fixed Legion Sea Labs to have a better opening
  - Created new variants
  - Fixes applied to Hard and Hard_Aggressive difficulty levels
- **Starfall:** New model praised, wind-up mechanic highlighted. AI integration pending. Community dreads it.
- **Polish improvements:** Legion is getting significant polish; Armada and Cortex expected to follow.

### CircuitAI & AngelScript

- **Key code reference:** `https://github.com/rlcevg/CircuitAI/blob/barbarian/data/script/dev/main.as#L54` -- this line shows how to disable control for a unit on spawn.
- **AngelScript interface proposals** (lamer):
  - `Unit::Capture` -- dedicated capture command
  - `Unit::ExecuteCustomCommand` -- general-purpose command execution (preferred for future-proofing)
  - `DefendTask` with specific unit target -- for objective-guarding behavior
- **Arxam's approach:** Extract hooks/calls from `.as` files, create new files with modified calls from `.as` and `.json`. Acknowledged this doesn't allow deep AI alteration but is a starting point.
- **Assembly concern:** Arxam looked into CircuitAI internals and found it too low-level ("I don't want to touch assembly"), suggesting the C++ layer beneath AngelScript is not approachable for most contributors.

---

## Actionable Items for BARB Quest

These items are directly relevant to improving building logic in the BAR AI:

### Technical Details About AI Control

1. **Build orders are NOT map-specific.** The AI uses one generic build order for all maps. This is the single biggest building logic limitation mentioned. Felnious acknowledged the problem but hasn't addressed it yet (msg 12).
2. **Full placement control exists.** Felnious confirmed "where to build" is fully controllable (msg 23). The infrastructure to place buildings intelligently is there; the configuration layer is what's missing.
3. **JSON config drives behavior.** Probability weights, build orders, and unit behavior are configured via JSON files alongside AngelScript hooks. This is the primary customization surface.

### References to Build Customization

4. **Economy Block_Map** is a key data structure -- it was updated in PR #6501 to include Legion's new buildings. Understanding this map is important for building logic.
5. **T2 Lab placement** had a specific bug that was fixed (PR #6501). Lab placement is a known pain point.
6. **Legion Sea Labs** got a "better opening" in the same PR, indicating build order sequencing is tunable per building type.

### Map-Specific Configuration Mentions

7. **Felnious explicitly stated** he'll look at smaller maps for specific build orders (msg 12). This work hasn't happened yet as of this chat.
8. **Great Divide and Center Command** were specifically named as maps where AI performance regressed (sam, msg 2).

### Performance Issues Related to Building/Production

9. **Small maps are too fast for AI** -- the generic build order doesn't ramp up quickly enough (Felnious, msg 12).
10. **Medium AI is "trashy at building"** but still applies pressure across the map (sam, msg 3). This suggests building quality vs. aggression tradeoff.
11. **Hard AI difficulty regression** -- less challenging than expected in 1v2 scenarios (sam, msg 2-3). Could be related to building/eco efficiency.

### Ghost Building / Memory Gap

12. **AI loses track of scouted buildings** once they leave LOS (sicbastard, msg 41). This affects strategic building decisions (knowing what the enemy has built).

---

## Key Links & References

| Type | Reference | Context |
|------|-----------|---------|
| **GitHub PR** | [PR #6501 - Legion Hotfix #1 Navy/Seaplanes](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6501) | Felnious's Legion Navy/Seaplanes fix (Dec 25, 2025) |
| **Source Code** | [CircuitAI barbarian branch - main.as L54](https://github.com/rlcevg/CircuitAI/blob/barbarian/data/script/dev/main.as#L54) | How to disable AI control for a unit on spawn |
| **Repository** | [rlcevg/CircuitAI](https://github.com/rlcevg/CircuitAI) (barbarian branch) | The AI framework powering BAR Barbarian AI |
| **Game Repo** | [beyond-all-reason/Beyond-All-Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) | Main BAR game repository |

---

## Raw Insights (Verbatim Quotes)

> **Felnious (msg 12):** "I'll be looking at smaller maps later on for specific build orders but usually small maps are to fast for ais to get going as they use a generic build order across all maps and aren't currently customizable per map"

> **Felnious (msg 21-25):** "i have total control over what the AI can and cant do / where to walk / where to build / where to attack / what, when, how many?"

> **lamer (msg 15):** "I'd say like a states in a state machine" (on how tasks work)

> **lamer (msg 9):** "Let that mode have a special drone-unit spawned automatically by commander every Nth minute. Disable control for such unit on spawn [...] Give it a command to capture. Or decoy commanders can capture, adjust its probability weight with special json config."

> **lamer (msg 10):** "Should i add `Unit::Capture` command to AS interface or `Unit::ExecuteCustomCommand` that would allow execution of any (game-specific or engine built-in) command?"

> **sam (msg 2):** "yeah but even on great divide and center command which i both play a lot like i 1v2'd the AI without any real effort"

> **sam (msg 3):** "like the med AI i am used to being trashy at building but it would at least still apply pressure across the map but the hard AI is normally relitivly hard to hold a line in a 1v2"

> **Seth Gamre (msg 4):** "I have a game mode in mind, calling it 'space race' It's a race to capture a massive war spaceship in the middle of the map. Barb's right now have no conception of using capture let alone objectives."

> **Isfet Solaris (msg 6):** "is there a way to make the AI more intelligent about lava? Some friends and I were playing and filled a slot with AI, but it kept walking directly into the lava and treating it like water."

> **Arxam (msg 16):** "take the Barb AI files, and extract the hooks and calls from the .as files [...] create new files from the .as and .json by making different calls"

> **Arxam (msg 30):** "did anyone already make an efficiency equation? AKA, any unit/action translated into metal over time"

> **sicbastard (msg 41):** "How can i get the buildings previously discovered? Right now my bot is only aware of structures it can have in LOS and ignores buildings that are 'ghosts' on the map."

> **RobotRobert03 (msg 50):** "Tbh we are all dreading the day it gets added" (on AI getting Starfall)

> **Message 1 (attribution unclear):** "We have an ai that has the ability to be able to build what we tell them to but can't release it yet"

---

*Summary prepared for BARB Quest Session 2. Primary value: confirmation that build orders are map-agnostic (biggest gap), full placement control exists but is unconfigured per-map, and JSON + AngelScript is the customization surface.*
