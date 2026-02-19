# Recursive Goal Planner — Design Concept

> Future architecture to replace the hardcoded waterfall with goal-driven build planning.
> Captured during Phase 4 implementation (2026-02-18). Implement after Phase 4 testing.

---

## Core Idea

A series of goals in priority order. The AI works toward the current goal. If a prerequisite isn't affordable, it recursively becomes the sub-goal until something IS affordable and buildable.

### Goal Chain Example

```
Goal 1: Get T1 lab/plant up
Goal 2: Get it running sustainably (enough E/M to feed production)
Goal 3: Get it running with +200 additional BP (nanos or cons)
Goal 4: Get it running with +400 BP
Goal 5: Build T2 lab/plant
Goal 6: Get antinuke
...
```

### How It Works

1. Current goal = "Build T2 lab"
2. T2 lab costs X metal, Y energy at Z BP for W seconds
3. Calculate: do I have enough mi/ei to sustain this build?
4. If NO → what do I need? e.g., need 600 ei but only have 300
5. Subgoal: "Reach 600 ei"
6. Score options: wind vs solar vs advsolar given map + current BP
7. Can I afford the best option? If NO → recurse again
8. Eventually reach something affordable → build it → pop back up

```
Goal: T2 Lab (need 18 mi, 600 ei)
├── Subgoal: Reach 600 ei (currently at 300)
│   ├── Best option: advsolar (80 E/s each, need ~4)
│   ├── Can afford? advsolar costs 350m + 5000e → NO (only 20 mi)
│   ├── Subgoal: Reach affordable energy
│   │   ├── Best option: wind (map avg 15 E/s, 40m each) → YES, affordable
│   │   └── BUILD WIND → pop back up
│   └── Re-evaluate: now at 315 ei, still need more → build more wind/solar
├── Subgoal: Reach 18 mi (currently at 12)
│   └── Claim nearest mex spots → BUILD MEX
└── Prerequisites met → BUILD T2 LAB
```

### Storage as Buffer

Storage acts as a loan against future income:

- `usableStorage = min(metalStored * 0.6, goalCost * 0.5)`
- Never spend more than 60% of storage on one goal
- Storage can fund up to 50% of any single goal cost
- Remaining cost must come from income within reasonable timeframe

Example: Goal costs 350 metal. Income = 20/s. Storage = 200.
- usableStorage = min(200 * 0.6, 350 * 0.5) = min(120, 175) = 120
- Remaining = 350 - 120 = 230 metal from income = 11.5 seconds
- Without storage: 350 / 20 = 17.5 seconds
- Storage saves 6 seconds — significant in early game

### BP Awareness

Each goal knows the planned BP for execution:
- "Build T2 lab at 300 BP" → takes 40 seconds, costs X metal/s drain
- "Build T2 lab at 600 BP" → takes 20 seconds, costs 2X metal/s drain
- Planner picks the BP target based on available cons and economy

This feeds into whether more cons are needed:
- Goal says "I need 400 BP to build this efficiently"
- Currently have 300 BP (commander + 1 con)
- Subgoal: "Get 100 more BP" → build one more con
- But ONLY if the time saved justifies the con's cost

---

## Alignment with Felenious's Strategy System

The existing strategy system uses **probabilistic dice** at game start:

| Strategy  | Probability | Effect |
|-----------|-------------|--------|
| T2_RUSH   | 85%         | Lower T2 lab threshold |
| T3_RUSH   | 35%         | Earlier gantry timing |
| NUKE_RUSH | 25%         | Early nuke silo |

The goal planner sits **on top of** this:
- Strategy dice determine WHAT goals matter and their priority/timing
- Goal planner determines HOW to achieve them efficiently
- T2_RUSH → moves "Build T2 lab" higher in goal chain, lowers prerequisites
- NUKE_RUSH → inserts "Build nuke silo" into chain earlier

They're complementary, not conflicting.

---

## Relationship to Current Systems

### What It Replaces
- The hardcoded waterfall in `tech.as` (Tech_T1Constructor_AiMakeTask)
- The fixed economy thresholds (ShouldBuildT1Solar, ShouldBuildT2BotLab, etc.)
- The income-based gating logic in economy_helpers.as

### What It Keeps
- Block planner (execution: HOW to place buildings in grids)
- Cell manager (WHERE blocks go)
- Scoring (WHICH building type has best ROI — used within goal evaluation)
- BP-aware scoring (Phase 4a — feeds into goal cost estimation)
- Block collaboration (Phase 4b — applies regardless of architecture)
- Constructor utilization (Phase 4c — con production gating)

### What It Adds
- Goal chain data structure (ordered priority list)
- Goal evaluator (can I achieve this? what do I need?)
- Recursive decomposition (goal → subgoals → affordable action)
- Storage-aware cost calculation
- BP-target planning (how much BP should this goal have?)

---

## Implementation Phases (Future)

### Phase A: Goal Data Structure
- Define Goal class: target, cost, prerequisites, BP requirement
- Define GoalChain: ordered list with current goal pointer
- Static chain for TECH role (hardcoded order, replace waterfall)

### Phase B: Goal Evaluator
- CanAchieve(goal, economy) → bool
- GetPrerequisites(goal, economy) → array of subgoals
- Recursive descent until affordable action found

### Phase C: Dynamic Goal Chain
- Strategy dice influence goal ordering
- Map analysis influences goal selection (island → skip navy goals)
- Threat detection reprioritizes (rush detected → defense goal jumps to top)

### Phase D: Priority Focus Integration
- Phase 4d's priority system becomes part of goal evaluation
- Current goal = current priority
- All BP focuses on current goal unless interrupted by higher priority

---

## Open Questions

- How deep should recursion go? Cap at 3-4 levels?
- Should goals have timeouts? ("If T2 lab not started by minute 8, reassess")
- How to handle interrupted goals? (enemy attack mid-build)
- Should the goal chain be visible in debug overlay?
- How does this interact with the C++ default task system?

---

*Captured: 2026-02-18, during Phase 4 implementation*
*Ready to implement after Phase 4 testing confirms current changes work*
