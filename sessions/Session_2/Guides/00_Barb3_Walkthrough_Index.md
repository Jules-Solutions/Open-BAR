# Barb3 AI Walkthrough — TECH Role, Chronological

> A step-by-step breakdown of what the Barb3 AI does during a game, focused on the **TECH role** with `experimental_balanced` profile.
>
> **Profile:** `experimental_balanced` | **Role:** TECH | **Faction:** Armada (examples)
> **Source:** `Prod/Skirmish/Barb3/stable/script/src/`

---

## How to Read These Guides

Each guide covers a time window and follows this format:

1. **What triggers** — the code function and condition
2. **What it does** — the actual behavior in plain English
3. **Key thresholds** — the numbers that gate each decision
4. **Source reference** — `file.as:line_number` so you can read the code yourself

All thresholds come from `global.as` → `RoleSettings::Tech` namespace unless noted otherwise.

---

## Walkthrough Index

| Guide | Time Period | Key Events |
|-------|------------|------------|
| [01 — Spawn & Opening](01_Minutes_00-05_Spawn_and_Opening.md) | 0:00–5:00 | Init, role selection, first factory, opener queue, early economy |
| [02 — T2 Transition](02_Minutes_05-10_T2_Transition.md) | 5:00–10:00 | T2 lab construction, first T2 constructor, fusion reactor, recycling |
| [03 — Scaling & First Military](03_Minutes_10-20_Scaling_and_Military.md) | 10:00–20:00 | Gantry, air plants, nuke silo, economy scaling, first combat units |
| [04 — Late Game](04_Minutes_20-30_Late_Game.md) | 20:00–30:00 | Advanced fusion, multi-gantry, T3 experimentals, full military |
| [05 — Endgame & Systems Overview](05_Minutes_30_Plus_Endgame.md) | 30:00+ | Nuke policy, dynamic caps, donation, steady-state loops |

## Reference Docs

| Guide | Content |
|-------|---------|
| [06 — Map Configurations](06_Map_Configurations.md) | All 18 configured maps with roles, unit bans, factory weights |
| [07 — Building Decision Files](07_Building_Decision_Files.md) | Every code file in the building pipeline with reading order |

---

## Key Concepts

### The Decision Waterfall

Every time a constructor is idle, Barb3 asks `Tech_BuilderAiMakeTask()` — "what should this unit build next?" The answer is a **waterfall** of if-statements, checked top to bottom. The first condition that passes wins. If nothing passes, it falls through to C++ `DefaultMakeTask`.

### Economy Gating

Almost every decision is gated by **10-second rolling minimum** metal/energy income (not instantaneous). This prevents the AI from overreacting to income spikes. See `Economy::GetMinMetalIncomeLast10s()` in `economy.as`.

### The Strategy Bitmask

At game start, 3 independent dice are rolled:
- **T2_RUSH** (85% chance) — lowers expansion thresholds
- **T3_RUSH** (35% chance) — affects gantry timing
- **NUKE_RUSH** (25% chance) — enables early nuke silo

These are independent flags, not mutually exclusive. A game can have all 3 active.

### Unit Cap System

TECH starts with almost everything capped to 0 (no combat units, no vehicles, no hover, minimal labs). Caps are dynamically raised as income grows via `Tech_EconomyUpdate()` and `Tech_IncomeBuilderLimits()`.

---

## Architecture Quick Reference

```
Engine (C++) → calls AngelScript hooks every tick (30 FPS)
                    │
                    ├── Economy::AiUpdateEconomy()     — resource tracking
                    ├── Factory::AiMakeTask()           — what should factory produce?
                    ├── Builder::AiMakeTask()           — what should constructor build?
                    ├── Military::AiMakeTask()          — what should combat unit do?
                    └── Military::AiMakeDefence()       — should we build turrets?
                              │
                              └── All delegate to ProfileController → RoleConfig
                                  which routes to Tech_* handlers
```

### Key Files

| File | What It Does |
|------|-------------|
| `init.as` | Loads JSON configs, armor/category definitions |
| `main.as` | Strategy dice rolls, map registration, main loop |
| `setup.as` | Map resolution, role matching, deferred initialization |
| `global.as` | All thresholds, settings, shared state |
| `roles/tech.as` | TECH role: all builder/factory/military/economy decisions |
| `manager/builder.as` | Constructor hierarchy, task lifecycle |
| `manager/factory.as` | Factory tracking, primary lab references |
| `manager/economy.as` | Resource tracking, sliding-window minimums |
| `manager/military.as` | Combat delegation, defense triggers |
| `helpers/block_planner.as` | Wind grid placement (our addition) |
| `types/opener.as` | Probabilistic factory build queue system |

---

*Created: 2026-02-17 | Based on Barb3 `experimental_balanced` profile*
