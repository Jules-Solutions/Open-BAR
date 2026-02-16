# Research Report 08: Modular Block-Based Building Placement Design

> **Session:** Session_2 (BARB Quest)
> **Date:** 2026-02-13
> **Status:** DESIGN DOCUMENT -- Proposed solution for block-based building placement in BARB AI
> **Depends On:**
> - Report 05: Blueprint API (pattern reference)
> - Report 06: Block Map & Build Chain System (constraint layer analysis)
> **Source Context:**
> - `sessions/Session_2/Build Module Quest.md` (Jules's original design ideas)
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/block_map.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/ArmadaBuildChain.json`
> - `Prod/Skirmish/Barb3/stable/script/src/manager/builder.as`
> - `Prod/Skirmish/Barb3/stable/script/src/task.as`
> - `Prod/Skirmish/Barb3/stable/script/src/roles/tech.as`
> - `Prod/Skirmish/Barb3/stable/script/src/roles/front.as`

---

## Table of Contents

1. [Design Goals](#1-design-goals)
2. [Core Concept: Block Templates](#2-core-concept-block-templates)
3. [Block Template Data Format](#3-block-template-data-format)
4. [Block Template Library](#4-block-template-library)
5. [Placement Algorithm](#5-placement-algorithm)
6. [Seed Point Selection](#6-seed-point-selection)
7. [Integration with Existing Systems](#7-integration-with-existing-systems)
8. [Block State Tracking](#8-block-state-tracking)
9. [Zone System Integration](#9-zone-system-integration)
10. [Spacing and Safety Rules](#10-spacing-and-safety-rules)
11. [Configuration Points](#11-configuration-points)
12. [Phased Implementation Plan](#12-phased-implementation-plan)
13. [Open Questions](#13-open-questions)

---

## 1. Design Goals

The current Barb3 building placement system suffers from a fundamental gap: `block_map.json` defines negative constraints (what cannot overlap what), and `build_chain.json` defines reactive adjacency (what to build after something finishes), but neither system provides positive guidance -- a plan for where buildings should go before they are needed. The result is bases that respect spacing rules but look like a random scatter plot.

This design proposes a **Block Template System** -- a layer of positive placement guidance that sits between the AngelScript role handlers and the C++ `CBuilderManager`, directing buildings into organized, pre-planned clusters.

### 1.1 Compact Bases

Buildings should be clustered in organized blocks, not scattered across available territory. A wind farm should look like a wind farm. A factory complex should have nanos around it and energy behind it. A defensive line should form a wall, not a constellation.

```
CURRENT STATE (scattered):                 TARGET STATE (blocked):

  W       W                                ┌─────────────────┐
     W          W                          │ W  W  W  W  W  │
  W    W     W                             │ W  W  W  W  W  │
        W       W                          │ W  W  W  W  W  │
  W          W                             └─────────────────┘
     W    W
```

### 1.2 Configurable

Different block templates per building type, faction, and difficulty. A "Hard" profile might use larger, denser blocks. A "Nightmare" profile might stack factories more aggressively. Templates are JSON-driven, not hard-coded.

### 1.3 Compatible

Works WITH the existing `block_map.json` and `build_chain.json` systems, not instead of them. Block_map exclusion zones are still validated for every slot. Build chains still fire on building completion. This system adds a layer on top; it does not rip out the floor.

### 1.4 Efficient

Reduces builder walking time between constructions. When a builder finishes one building in a block, the next slot is adjacent. No more walking across the map to place the next wind turbine.

### 1.5 Defensible

Organized blocks are easier to defend than scattered buildings. A 4x4 wind farm needs a turret on each corner. Sixteen scattered wind turbines need sixteen turrets or are simply undefendable.

### 1.6 Practical

Everything described here can be implemented in AngelScript without C++ engine modifications. The system uses the existing `aiBuilderMgr.Enqueue(SBuildTask)` API with explicit positions rather than relying on `aiBuilderMgr.DefaultMakeTask()` to choose positions.

---

## 2. Core Concept: Block Templates

A **block template** is a predefined arrangement of N building slots, each slot specifying a relative position where a particular building type should be placed.

### 2.1 What a Block Template Contains

```
Block Template = {
    name:         unique identifier
    category:     which building category this template handles
    grid:         [columns, rows] of slots
    slot_spacing: [x_gap, z_gap] between adjacent slots (in elmos)
    building_def: which unit to place in each slot (or pattern)
    fill_order:   sequence in which slots are populated
    min_fill:     minimum slots needed before block is considered "started"
    max_fill:     maximum slots in this block
    rotation:     how the block orients relative to the map
}
```

### 2.2 Visual Example: Wind Block (4x4)

```
Block Origin (0,0) at top-left
Slot spacing: 32 elmos x, 32 elmos z (2 block_map units each)

    col0    col1    col2    col3

row0  [W]-----[W]-----[W]-----[W]     W = wind turbine slot
       |       |       |       |
       | 32e   | 32e   | 32e   |       e = elmos
       |       |       |       |
row1  [W]-----[W]-----[W]-----[W]     Total footprint:
       |       |       |       |       width  = 3 * 32 + footprint = ~112 elmos
       | 32e   | 32e   | 32e   |       depth  = 3 * 32 + footprint = ~112 elmos
       |       |       |       |
row2  [W]-----[W]-----[W]-----[W]     16 wind turbine slots
       |       |       |       |
       | 32e   | 32e   | 32e   |
       |       |       |       |
row3  [W]-----[W]-----[W]-----[W]

Fill order (row_first):
  (0,0) -> (1,0) -> (2,0) -> (3,0) -> (0,1) -> (1,1) -> ... -> (3,3)
```

Wind turbines have `"ignore": ["engy_low"]` in block_map.json, meaning they can overlap each other's exclusion zones. With no yard defined, their block_map footprint is just the unit size (roughly 2x2 block_map units = 32x32 elmos). A spacing of 32 elmos places them adjacent but not overlapping -- tight, clean wind farms.

### 2.3 Visual Example: Factory Cluster

```
Factory Cluster Block (facing South)

         ┌─────┐
         │NANO │  <- nano behind factory (build_chain style)
         └──┬──┘
            |
    ┌───────┼───────┐
    │  N    │    N  │  <- nanos on sides
    │       │       │
    │   ┌───┴───┐   │
    │   │       │   │
    │   │  FAC  │   │
    │   │       │   │
    │   └───┬───┘   │
    │       │       │
    └───────┼───────┘
            |
         (exit)      <- factory exit lane kept clear
            |
         [LLT]       <- defense in front (from build_chain)

Block slots:
  Slot 0: Factory (center)          -- seed building
  Slot 1: Nano (left side)          -- offset from factory center
  Slot 2: Nano (right side)
  Slot 3: Nano (behind)
  Slot 4: LLT (front, past exit)    -- respects factory yard exclusion
```

This layout is already implied by the `build_chain.json` hub entries for factories (e.g., `armlab` triggers an LLT behind it, `armalab` triggers 4 nanos + fusion). The block template formalizes it and reserves the space in advance.

### 2.4 Visual Example: Fusion Complex Block

```
Fusion Complex Block (facing South)

    ┌───────────────────────────────────────┐
    │                                       │
    │  [MM] [MM] [MM]     [MM] [MM] [MM]   │  MM = T2 Metal Maker
    │                                       │
    │         [N]  [N]  [N]                 │  N  = Nano Caretaker
    │                                       │
    │            ┌─────┐                    │
    │            │     │                    │
    │            │ FUS │                    │  FUS = Fusion Reactor
    │            │     │                    │
    │            └─────┘                    │
    │                                       │
    │         [N]  [N]  [N]                 │
    │                                       │
    │  [AA]                         [AA]    │  AA = Flak / Ferret
    │                                       │
    └───────────────────────────────────────┘

Block slots (fill order):
  Slot 0:  Fusion (center)              -- seed
  Slot 1:  Nano (front-left)            -- immediate assist
  Slot 2:  Nano (front-center)
  Slot 3:  Nano (front-right)
  Slot 4:  Nano (back-left)
  Slot 5:  Nano (back-center)
  Slot 6:  Nano (back-right)
  Slot 7:  MM (top-left cluster)        -- metal makers behind
  Slot 8:  MM (top-center)
  Slot 9:  MM (top-right)
  Slot 10: MM (top-far-left cluster)
  Slot 11: MM (top-far-center)
  Slot 12: MM (top-far-right)
  Slot 13: AA (bottom-left)             -- conditional (air: true)
  Slot 14: AA (bottom-right)            -- conditional (air: true)
```

This mirrors what `ArmadaBuildChain.json` already defines for `armafus`:
```json
"armafus": {
    "hub": [[
        {"unit": "armnanotc", "offset": {"front": 5}},
        {"unit": "armnanotc", "offset": {"front": 10}},
        {"unit": "armmmkr",  "offset": [120, 120]},
        {"unit": "armmmkr",  "offset": [120, -120]},
        {"unit": "armflak",  "offset": {"front": 150}, "condition": {"air": true}},
        {"unit": "armmercury", "offset": {"front": 150}}
    ]]
}
```

The difference: the block template reserves ALL this space at the moment the fusion location is chosen, guaranteeing that converters and AA land in organized positions rather than scattering because the space was taken by an unrelated solar panel.

---

## 3. Block Template Data Format

### 3.1 Schema

Block templates live in a JSON config file, loaded alongside `block_map.json` and `build_chain.json` in the profile config. The format is compatible with the existing Barb3 config loading pipeline.

```json
{
    "block_templates": {
        "<template_name>": {
            "category": "<block_map_category>",
            "grid": [<columns>, <rows>],
            "slot_spacing": [<x_elmos>, <z_elmos>],
            "building": "<block_map_category | unit_name>",
            "fill_order": "<row_first | col_first | spiral_in | center_out>",
            "min_fill": <int>,
            "max_fill": <int>,
            "rotation": "<auto | fixed_south | face_enemy | face_center>",
            "conditions": {
                "<condition_key>": <value>
            },
            "slots": [
                // Optional: explicit slot definitions (overrides grid)
                {
                    "offset": [<x_elmos>, <z_elmos>],
                    "building": "<unit_name | block_map_category>",
                    "condition": { ... },
                    "priority": "<low | normal | high | now>"
                }
            ]
        }
    }
}
```

### 3.2 Field Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `category` | string | yes | -- | The block_map category this template serves (e.g., `"engy_low"`, `"factory"`, `"engy_high"`) |
| `grid` | [int, int] | no* | -- | Columns x rows for uniform grid templates. *Either `grid` or `slots` is required. |
| `slot_spacing` | [int, int] | no | [32, 32] | X and Z gap between adjacent grid slots, in elmos |
| `building` | string | no* | -- | Default building to place in each slot. Can be a block_map category name (resolved to faction-specific unit at runtime) or a specific unit name. *Required if using `grid`. |
| `fill_order` | string | no | `"row_first"` | Order to fill slots: `row_first` (left-to-right, top-to-bottom), `col_first` (top-to-bottom, left-to-right), `spiral_in` (outside edges first), `center_out` (center slot first, expand outward) |
| `min_fill` | int | no | 1 | Minimum valid slots required to commit a block at a location. If terrain validation produces fewer than this, the location is rejected. |
| `max_fill` | int | no | all slots | Maximum buildings in this block. May be less than total grid slots if you want partial fills. |
| `rotation` | string | no | `"auto"` | How to orient the block: `auto` (engine picks best), `fixed_south` (always south-facing), `face_enemy` (front toward enemy spawn), `face_center` (front toward map center) |
| `conditions` | object | no | none | Global conditions for this template (same format as build_chain conditions: `air`, `energy`, `m_inc>`, `chance`, etc.). Template is skipped if conditions are not met. |
| `slots` | array | no* | -- | Explicit slot definitions for non-uniform templates. Each slot has its own offset, building type, and conditions. *Required if not using `grid`. |

### 3.3 Slot Definition (for `slots` array)

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `offset` | [int, int] | yes | -- | Position offset from block origin, in elmos. South-facing orientation. |
| `building` | string | yes | -- | Unit name or block_map category to place here |
| `condition` | object | no | none | Conditions for this specific slot (same format as build_chain) |
| `priority` | string | no | `"normal"` | Build priority for this slot's task |
| `role` | string | no | `"fill"` | Slot role: `"seed"` (placed first, defines block anchor), `"fill"` (placed after seed), `"optional"` (only if economy allows) |

### 3.4 Two Template Modes

**Grid Mode** (uniform repeating blocks like wind farms):
```json
{
    "wind_block_4x4": {
        "category": "engy_low",
        "grid": [4, 4],
        "slot_spacing": [32, 32],
        "building": "wind",
        "fill_order": "row_first",
        "min_fill": 4,
        "max_fill": 16,
        "rotation": "auto"
    }
}
```

**Slot Mode** (heterogeneous blocks like factory clusters):
```json
{
    "factory_cluster_t1": {
        "category": "factory",
        "rotation": "face_enemy",
        "min_fill": 2,
        "slots": [
            {"offset": [0, 0],     "building": "fac_land_t1", "role": "seed"},
            {"offset": [-80, 0],   "building": "caretaker",   "role": "fill", "priority": "high"},
            {"offset": [80, 0],    "building": "caretaker",   "role": "fill", "priority": "high"},
            {"offset": [0, -80],   "building": "caretaker",   "role": "fill"},
            {"offset": [0, 200],   "building": "def_low",     "role": "fill", "priority": "now"}
        ]
    }
}
```

The `building` field in slots can reference a block_map category name (e.g., `"wind"`, `"fac_land_t1"`). At runtime, the system resolves this to the correct faction-specific unit name using the same instance mapping that `block_map.json` already provides. If the field contains a specific unit name (e.g., `"armwin"`), it is used directly. This allows templates to be faction-agnostic.

---

## 4. Block Template Library

### 4.1 Energy Blocks

#### `wind_block_4x4` -- Basic Wind Farm

```json
{
    "category": "engy_low",
    "grid": [4, 4],
    "slot_spacing": [32, 32],
    "building": "wind",
    "fill_order": "row_first",
    "min_fill": 4,
    "max_fill": 16,
    "rotation": "auto"
}
```

```
  32e  32e  32e
[W]--[W]--[W]--[W]   16 slots
 |    |    |    |     Footprint: ~128 x 128 elmos
[W]--[W]--[W]--[W]   Wind ignores wind (engy_low ignores engy_low)
 |    |    |    |     so block_map permits tight packing
[W]--[W]--[W]--[W]
 |    |    |    |
[W]--[W]--[W]--[W]
```

**Rationale:** Wind turbines have `"ignore": ["engy_low"]` and no yard, so they can be packed as tightly as their footprint allows. A 4x4 grid of 16 winds is the standard energy block for T1. This is the simplest and most visibly impactful template to implement first.

#### `wind_block_3x3` -- Compact Wind Farm

```json
{
    "category": "engy_low",
    "grid": [3, 3],
    "slot_spacing": [32, 32],
    "building": "wind",
    "fill_order": "row_first",
    "min_fill": 3,
    "max_fill": 9,
    "rotation": "auto"
}
```

For tighter maps or lower difficulty profiles. 9 wind slots instead of 16.

#### `solar_block_3x3` -- Solar Array

```json
{
    "category": "engy_mid",
    "grid": [3, 3],
    "slot_spacing": [112, 112],
    "building": "solar",
    "fill_order": "center_out",
    "min_fill": 3,
    "max_fill": 9,
    "rotation": "auto"
}
```

```
Spacing = 112 elmos (7 block_map units)
Matches solar yard: [6,6] = 96 elmos + footprint margin

  [S]----[S]----[S]
   |      |      |     9 slots
   |112e  |112e  |     Footprint: ~336 x 336 elmos
   |      |      |     Solar ignores solar + def_low + mex
  [S]----[S]----[S]
   |      |      |
   |112e  |112e  |
   |      |      |
  [S]----[S]----[S]
```

Solars have `"yard": [6, 6]` (96 elmo padding) and `"ignore": ["engy_mid", "def_low", "mex"]`. The 112-elmo spacing respects the yard with a small margin for the building footprint. Solars ignore each other, so the block_map will not block inter-slot placement.

#### `fusion_complex` -- Fusion + Nanos + Converters + AA

```json
{
    "category": "engy_high",
    "rotation": "face_enemy",
    "min_fill": 3,
    "slots": [
        {"offset": [0, 0],       "building": "fusion",    "role": "seed"},
        {"offset": [-80, 0],     "building": "caretaker",  "role": "fill", "priority": "high"},
        {"offset": [80, 0],      "building": "caretaker",  "role": "fill", "priority": "high"},
        {"offset": [0, -80],     "building": "caretaker",  "role": "fill"},
        {"offset": [0, 80],      "building": "caretaker",  "role": "fill"},
        {"offset": [-120, -120], "building": "converter",  "role": "fill", "condition": {"energy": true}},
        {"offset": [120, -120],  "building": "converter",  "role": "fill", "condition": {"energy": true}},
        {"offset": [-120, 120],  "building": "converter",  "role": "fill", "condition": {"energy": true}},
        {"offset": [120, 120],   "building": "converter",  "role": "fill", "condition": {"energy": true}},
        {"offset": [-160, 0],    "building": "def_air",    "role": "optional", "condition": {"air": true}},
        {"offset": [160, 0],     "building": "def_air",    "role": "optional", "condition": {"air": true}}
    ]
}
```

```
                 [AA]
                  |
  [MM]---[MM]----[N]----[MM]---[MM]
           |      |      |
           |     [N]     |
           |      |      |
          [N]--[FUSION]--[N]
                  |
                 [N]
                  |
                 [AA]

Legend: FUSION = seed, N = nano, MM = metal maker, AA = anti-air
```

This replaces the scattered build_chain hub for fusion reactors with a guaranteed layout. The fusion is placed first (seed), nanos fill immediately around it, then converters and AA fill as economy allows.

### 4.2 Factory Blocks

#### `factory_cluster_t1` -- T1 Factory with Support

```json
{
    "category": "factory",
    "rotation": "face_enemy",
    "min_fill": 2,
    "slots": [
        {"offset": [0, 0],      "building": "fac_land_t1", "role": "seed"},
        {"offset": [0, -160],   "building": "def_low",     "role": "fill", "priority": "now"},
        {"offset": [-80, 64],   "building": "caretaker",   "role": "fill"},
        {"offset": [80, 64],    "building": "caretaker",   "role": "fill"}
    ]
}
```

```
                 ┌─────┐
                 │ LLT │   <- defense behind factory (facing enemy)
                 └──┬──┘
                    |
        ┌───────────┼───────────┐
        │ NANO      │      NANO │
        │           │           │
        │     ┌─────┴─────┐     │
        │     │           │     │
        │     │  FACTORY  │     │
        │     │           │     │
        │     └─────┬─────┘     │
        │           │           │
        └───────────┼───────────┘
                    |
              (exit lane)
```

**Note:** The LLT is placed behind the factory (negative Z in South-facing = behind = toward safe territory). The exit lane faces forward (positive Z = toward enemy). The offset of -160 for the LLT is chosen to clear the factory's 608-elmo exclusion zone -- specifically, the `fac_land_t1` has `"size": [8,8]` + `"yard": [0,30]` = `[8, 38]` block_map units. The back edge extends `(38/2 + 5) * 16 = 384` elmos behind center, so a defense at -160 from factory center does NOT fall within the factory's own exclusion zone, since defenses ignore energy but DO NOT ignore factories. However, since `def_low` has `"ignore": ["engy_mid", "engy_high", "engy_low", "nano"]`, it respects factory zones. The placement algorithm will validate this via `TestBuildOrder` regardless; the offset is a suggestion, not a guarantee.

#### `factory_cluster_t2` -- T2 Factory Complex

```json
{
    "category": "factory",
    "rotation": "face_enemy",
    "min_fill": 2,
    "slots": [
        {"offset": [0, 0],        "building": "fac_land_t2", "role": "seed"},
        {"offset": [-80, 0],      "building": "caretaker", "role": "fill", "priority": "high"},
        {"offset": [-80, 0],      "building": "caretaker", "role": "fill", "priority": "high"},
        {"offset": [0, -80],      "building": "caretaker", "role": "fill"},
        {"offset": [0, -80],      "building": "caretaker", "role": "fill"},
        {"offset": [0, 200],      "building": "fusion",   "role": "fill", "condition": {"m_inc>": 15}},
        {"offset": [-160, -160],  "building": "def_air",  "role": "optional", "condition": {"air": true}}
    ]
}
```

Mirrors the `armalab` build_chain pattern: 4 nanos (2 left, 2 behind) + fusion behind + AA conditional.

### 4.3 Defense Blocks

#### `defense_line` -- Linear Turret Row

```json
{
    "category": "def_low",
    "grid": [5, 1],
    "slot_spacing": [192, 0],
    "building": "def_low",
    "fill_order": "center_out",
    "min_fill": 2,
    "max_fill": 5,
    "rotation": "face_enemy"
}
```

```
Spacing = 192 elmos (12 block_map units)
def_low radius: 6 block_map units = 96 elmos
192 elmos > 2 * 96 elmos: slots do not overlap each other's circles

  [T]----192e----[T]----192e----[T]----192e----[T]----192e----[T]

  5 turrets in a line, facing the enemy
  Fill from center outward: slot2 -> slot1 -> slot3 -> slot0 -> slot4
```

This creates a defensive wall. The center_out fill order means the first turret goes in the middle of the line, then expands to both sides. The 192-elmo spacing ensures turrets respect `def_low` circle radius (96 elmos) -- each turret is outside the previous one's exclusion zone.

#### `aa_cluster` -- Anti-Air Battery

```json
{
    "category": "def_air",
    "rotation": "auto",
    "min_fill": 2,
    "slots": [
        {"offset": [0, 0],    "building": "def_air",  "role": "seed"},
        {"offset": [64, 0],   "building": "def_air",  "role": "fill"},
        {"offset": [-64, 0],  "building": "def_air",  "role": "fill"},
        {"offset": [0, 80],   "building": "small",    "role": "fill"}
    ]
}
```

```
  [AA]---[AA]---[AA]
           |
         [RAD]

3 AA turrets in a row + radar tower behind them.
def_air has yard: [2,2] (32 elmos) and not_ignore: ["factory", "mex"]
So AA turrets are very permissive -- tight 64-elmo spacing works.
```

### 4.4 Economy Blocks

#### `converter_block` -- Metal Maker Cluster

```json
{
    "category": "convert",
    "grid": [3, 2],
    "slot_spacing": [128, 128],
    "building": "converter",
    "fill_order": "row_first",
    "min_fill": 2,
    "max_fill": 6,
    "rotation": "auto",
    "conditions": {"energy": true}
}
```

```
Spacing = 128 elmos (8 block_map units)
converter yard: [7,7] = 112 elmos
128 > 112: clears the yard with margin

  [MM]---128e---[MM]---128e---[MM]
   |             |             |
  128e          128e          128e
   |             |             |
  [MM]---128e---[MM]---128e---[MM]

6 metal makers in a 3x2 grid
Global condition: only starts if energy surplus exists
```

Converters have `"yard": [7,7]` (112 elmo padding) and `"ignore": ["convert"]` (they can overlap each other). However, the yard is still enforced against non-converter buildings. The 128-elmo spacing keeps each converter just outside the next one's yard limit relative to non-converter neighbors, while converter-converter overlap is permitted by the ignore rule.

#### `storage_block` -- Metal + Energy Storage

```json
{
    "category": "mex",
    "rotation": "auto",
    "min_fill": 2,
    "slots": [
        {"offset": [0, 0],    "building": "store",  "role": "seed"},
        {"offset": [80, 0],   "building": "store",  "role": "fill"},
        {"offset": [0, 80],   "building": "store",  "role": "fill"},
        {"offset": [80, 80],  "building": "store",  "role": "fill"}
    ]
}
```

Stores have `"not_ignore": ["factory", "terra"]` -- extremely permissive placement. A 2x2 cluster of storage buildings with 80-elmo spacing keeps them compact.

### 4.5 Complete Template Summary

| Template | Mode | Slots | Footprint (approx) | Purpose |
|----------|------|-------|---------------------|---------|
| `wind_block_4x4` | grid | 16 | 128 x 128 elmos | T1 energy backbone |
| `wind_block_3x3` | grid | 9 | 96 x 96 elmos | Compact T1 energy |
| `solar_block_3x3` | grid | 9 | 336 x 336 elmos | Mid-tier energy |
| `fusion_complex` | slots | 11 | ~400 x 400 elmos | T2 energy + support |
| `factory_cluster_t1` | slots | 4 | ~320 x 480 elmos | T1 factory + nanos + defense |
| `factory_cluster_t2` | slots | 7 | ~400 x 600 elmos | T2 factory complex |
| `defense_line` | grid | 5 | 768 x ~32 elmos | Turret wall |
| `aa_cluster` | slots | 4 | ~192 x ~112 elmos | Anti-air battery |
| `converter_block` | grid | 6 | 384 x 256 elmos | Metal maker farm |
| `storage_block` | slots | 4 | 160 x 160 elmos | Storage cluster |

---

## 5. Placement Algorithm

### 5.1 Overview: PlaceBlock

The core algorithm for placing a block template in the world.

```
PlaceBlock(template, seed_position, facing) -> BlockInstance | null
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INPUT:
  template       -- the block template definition
  seed_position  -- suggested world position (AIFloat3) for block origin
  facing         -- the block's orientation (0=S, 1=E, 2=N, 3=W), or -1 for auto

OUTPUT:
  BlockInstance with list of validated slot positions, or null if not viable

STEPS:

1. DETERMINE ORIENTATION
   if facing == -1 (auto):
     if template.rotation == "face_enemy":
       facing = direction from seed_position toward nearest enemy start
     elif template.rotation == "face_center":
       facing = direction from seed_position toward map center
     else:
       facing = try all 4, pick the one with most valid slots

2. CALCULATE BLOCK FOOTPRINT
   if template has grid:
     width  = (grid[0] - 1) * slot_spacing[0] + building_footprint_x
     depth  = (grid[1] - 1) * slot_spacing[1] + building_footprint_z
   else (slot mode):
     width  = max(slot.offset[0]) - min(slot.offset[0]) + building_footprint_x
     depth  = max(slot.offset[1]) - min(slot.offset[1]) + building_footprint_z

3. FOR EACH SLOT in fill_order:
   a. Calculate world_pos = seed_position + RotateOffset(slot.offset, facing)
   b. Resolve building name:
      - If slot.building is a block_map category, resolve to faction unit name
      - Get CCircuitDef@ for the unit name
      - Check CCircuitDef.IsAvailable(ai.frame)
   c. Validate conditions:
      - If slot has conditions, evaluate them (air check, energy check, etc.)
      - If conditions fail, mark slot as CONDITIONAL_SKIP
   d. Validate position:
      - Spring.TestBuildOrder(defId, world_pos, facing) must return ALLOWED
        (This is the engine-level check: terrain, slope, water, unit blocking)
      - block_map exclusion zones are enforced by the C++ engine via TestBuildOrder
        (Our explicit positions still go through the same validation pipeline)
   e. Result:
      - If valid: mark slot as PLANNED, record world_pos
      - If invalid: mark slot as TERRAIN_SKIP

4. COUNT VALID SLOTS
   valid_count = count of PLANNED slots
   if valid_count < template.min_fill:
     return null  // not enough space, try different location

5. COMMIT BLOCK
   Create BlockInstance with all PLANNED slots
   return BlockInstance
```

### 5.2 Orientation Rotation

Slot offsets are defined in South-facing orientation (consistent with block_map and build_chain conventions). The rotation transform converts these to actual world positions.

```
RotateOffset(offset, facing) -> AIFloat3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Given offset = [dx, dz] in South-facing:
  dx > 0 = right of building center
  dz > 0 = behind building center (away from exit)
  dz < 0 = in front of building center (toward exit)

Facing 0 (South, default):  world = (seed.x + dx, seed.z + dz)
Facing 1 (East):            world = (seed.x - dz, seed.z + dx)
Facing 2 (North):           world = (seed.x - dx, seed.z - dz)
Facing 3 (West):            world = (seed.x + dz, seed.z - dx)
```

In AngelScript:
```angelscript
AIFloat3 RotateOffset(int dx, int dz, int facing)
{
    AIFloat3 result;
    switch (facing) {
        case 0: result.x = float(dx);  result.z = float(dz);  break; // South
        case 1: result.x = float(-dz); result.z = float(dx);  break; // East
        case 2: result.x = float(-dx); result.z = float(-dz); break; // North
        case 3: result.x = float(dz);  result.z = float(-dx); break; // West
    }
    result.y = 0.f;
    return result;
}
```

### 5.3 Validation Pipeline

Each slot position passes through this validation stack:

```
    Slot Offset
        |
        v
    RotateOffset() -- transform to world coordinates
        |
        v
    Resolve Building Def -- category -> faction unit name -> CCircuitDef@
        |
        v
    Check Conditions -- air? energy? m_inc? chance?
        |  (fail -> CONDITIONAL_SKIP)
        v
    TestBuildOrder() -- engine validates terrain, slope, water, blocking units
        |  (fail -> TERRAIN_SKIP)
        v
    PLANNED -- slot is valid, record position
```

**Important:** We do NOT need to manually check block_map exclusion zones. The C++ `TestBuildOrder` and `CBuilderManager` already enforce block_map rules when processing any build request. By calling `aiBuilderMgr.Enqueue(SBuildTask)` with an explicit position, the C++ side still validates against block_map. If the position violates a block_map constraint, the build will be rejected or repositioned by the engine.

However, the slot-level validation should pre-check via `TestBuildOrder` to avoid enqueuing tasks that will immediately fail. The lightweight check:

```angelscript
// Pseudocode for slot validation
bool ValidateSlotPosition(CCircuitDef@ def, AIFloat3 worldPos, int facing)
{
    // Engine-level terrain/blocking check
    int result = ai.TestBuildOrder(def, worldPos, facing);
    return (result != 0);  // 0 = blocked, non-zero = allowed
}
```

### 5.4 Fill Order Patterns

The fill order determines the sequence in which slots are populated. This affects both the visual progression and the builder's walk path.

```
ROW_FIRST (left-to-right, top-to-bottom):

  1---2---3---4
  |   |   |   |
  5---6---7---8
  |   |   |   |
  9--10--11--12

COL_FIRST (top-to-bottom, left-to-right):

  1---4---7--10
  |   |   |   |
  2---5---8--11
  |   |   |   |
  3---6---9--12

SPIRAL_IN (outside edges first, spiral inward):

  1---2---3---4
  |           |
  12  13-14  5
  |       |  |
  11  16-15  6
  |           |
  10--9---8---7

CENTER_OUT (center first, expand outward):

  9---5---6--10
  |   |   |   |
  7---1---2--11
  |   |   |   |
  8---3---4--12
```

**`center_out` is best for seed buildings** (factories, fusions) where the center building should be placed first and support structures radiate outward.

**`row_first` is best for uniform grids** (wind farms, solar arrays) where a builder moves left-to-right, row by row, minimizing backtracking.

**`spiral_in` is best for defensive blocks** where the perimeter should be fortified first.

For slot-mode templates, the fill order is simply the order of the `slots` array. The `"role": "seed"` slot is always placed first regardless of array position.

---

## 6. Seed Point Selection

When the AI decides it needs a new block, it must choose WHERE to place the block origin. This is the highest-level placement decision.

### 6.1 Algorithm: FindBlockSeed

```
FindBlockSeed(template, builder_position) -> AIFloat3 | null
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INPUT:
  template         -- the block template we want to place
  builder_position -- current position of the builder unit

OUTPUT:
  Best seed position, or null if no valid location found

STEPS:

1. CHECK EXISTING BLOCKS
   For each active BlockInstance of this template.category:
     if block.filledCount < block.maxFill:
       // Existing block has room -- don't start a new one
       return null  (caller should fill existing block instead)

2. GATHER CANDIDATE POSITIONS
   candidates = []

   a. BASE CENTER OFFSET
      base_center = average position of own buildings (from C++ economy clusters)
      for each direction in [toward_mex, toward_geo, away_from_enemy, lateral]:
        candidate = base_center + direction * BLOCK_SEED_DISTANCE
        candidates.push(candidate)

   b. NEAR EXISTING INFRASTRUCTURE
      if template is energy block:
        for each factory:
          candidates.push(factory.pos + offset_behind_factory)
      if template is factory block:
        for each energy_cluster:
          candidates.push(energy_cluster.center + offset_toward_front)
      if template is defense block:
        for each front_line_point:
          candidates.push(front_point + offset_behind)

   c. BUILDER PROXIMITY BIAS
      candidates.push(builder_position)  // builder's current location as fallback

3. SCORE CANDIDATES
   for each candidate in candidates:
     score = 0.0

     // Distance from base center (closer = better, up to a point)
     dist = Distance(candidate, base_center)
     score += BASE_PROXIMITY_WEIGHT * max(0, 1.0 - dist / MAX_BASE_RADIUS)

     // Distance from builder (closer = less walk time)
     bdist = Distance(candidate, builder_position)
     score += BUILDER_PROXIMITY_WEIGHT * max(0, 1.0 - bdist / MAX_BUILDER_RANGE)

     // Safety (distance from front line)
     front_dist = DistanceToFrontLine(candidate)
     score += SAFETY_WEIGHT * clamp(front_dist / SAFE_DISTANCE, 0.0, 1.0)

     // Terrain quality (flat, buildable area around seed)
     flat_count = CountFlatTilesInRadius(candidate, template.footprint)
     score += TERRAIN_WEIGHT * (flat_count / expected_tiles)

     // Penalty: too close to existing blocks of same type
     for each existing_block of same category:
       if Distance(candidate, existing_block.seed) < MIN_BLOCK_SPACING:
         score -= OVERLAP_PENALTY

     candidate.score = score

4. TRY TOP CANDIDATES
   Sort candidates by score descending
   for each candidate (top N):
     block = PlaceBlock(template, candidate.pos, -1)  // auto-facing
     if block is not null:
       return candidate.pos

   return null  // no valid location found
```

### 6.2 Seed Distance Constants

These control how far from various reference points the system looks for block locations.

```
BLOCK_SEED_DISTANCE      = 400 elmos   -- how far from base center to search
MAX_BASE_RADIUS          = 1200 elmos  -- beyond this, penalty for being too far
MAX_BUILDER_RANGE        = 800 elmos   -- beyond this, no builder proximity bonus
SAFE_DISTANCE            = 600 elmos   -- minimum distance from front line
MIN_BLOCK_SPACING        = 200 elmos   -- minimum gap between blocks of same type
BASE_PROXIMITY_WEIGHT    = 0.3
BUILDER_PROXIMITY_WEIGHT = 0.2
SAFETY_WEIGHT            = 0.3
TERRAIN_WEIGHT           = 0.2
OVERLAP_PENALTY          = 0.5
```

These are all tunable per profile (see Section 11).

### 6.3 Context-Specific Seeding

Different template categories use different seeding strategies:

| Template Category | Primary Seed Strategy | Secondary |
|------------------|----------------------|-----------|
| Energy (wind, solar) | Behind factories, near base center | Builder proximity |
| Factory | Behind front line, near resources | Map start position |
| Defense | Along defensive perimeter | Near threatened mexes |
| Economy (converters) | Adjacent to energy blocks | Near fusion complexes |
| Storage | Near base center | Near factories |
| AA | Above high-value targets (fusions, gantries) | Along air approach vectors |

---

## 7. Integration with Existing Systems

### 7.1 Integration with block_map.json

**block_map.json stays untouched.** It continues to define exclusion zones, structure types, ignore rules, and instance mappings. The block template system operates on top of it.

```
LAYER STACK:

  ┌──────────────────────────────────────────┐
  │  Block Template System (NEW)             │  Positive guidance:
  │  "Place wind at (X,Z) in this block"     │  WHERE to build
  └──────────────┬───────────────────────────┘
                 │
  ┌──────────────┴───────────────────────────┐
  │  block_map.json (EXISTING)               │  Negative constraints:
  │  "Don't overlap factory exclusion zone"  │  WHERE NOT to build
  └──────────────┬───────────────────────────┘
                 │
  ┌──────────────┴───────────────────────────┐
  │  C++ CBuilderManager (ENGINE)            │  Execution:
  │  TestBuildOrder, path planning, assign   │  Actually builds it
  └──────────────────────────────────────────┘
```

The template system provides a position suggestion. The block_map constraints (enforced by the C++ engine) validate that suggestion. If a slot position violates block_map rules, it gets marked as TERRAIN_SKIP and the block has a gap at that slot. The template survives gaps -- the `min_fill` threshold determines whether the block is still viable.

**Specific interactions:**

- Wind slots use `slot_spacing: [32, 32]`. Wind's block_map entry has `"ignore": ["engy_low"]`, so wind-to-wind overlap is allowed. The template's spacing is purely aesthetic -- the engine would accept tighter packing.

- Factory cluster slots position nanos at offsets that respect the factory's exclusion yard (`[0, 30]` = 480 elmo front/back). The nano's block_map entry (`"ignore": ["mex", "engy_mid", "engy_high"]`) does NOT ignore factories, so nanos must be placed outside the factory exclusion zone. The slot offsets are designed with this in mind.

- Defense line slots use 192-elmo spacing. `def_low` has `"radius": 6` = 96 elmos. Since defense circles block each other (no self-ignore for def_mid/def_hvy), the 192-elmo spacing ensures no overlap.

### 7.2 Integration with build_chain.json

**build_chain.json also stays untouched** for now. The two systems coexist:

**Scenario A: Template takes priority over chain**

When a building completes that is part of a block template, the template system fills the next slot. Build_chain still fires, but its chain entries may be redundant (the template already planned those buildings). To avoid double-building:

```
OnBuildingComplete(unit):
  1. Is this unit in an active BlockInstance?
     YES -> Mark the slot as BUILT
            Get next unfilled slot from this BlockInstance
            If found: Enqueue build task for next slot (template takes priority)
            SKIP build_chain hub for this unit
     NO  -> Let build_chain fire normally (fallback to current behavior)
```

The key insight: if a fusion is part of a `fusion_complex` block, we suppress its build_chain hub (which would scatter nanos and converters) and instead fill the template's pre-planned slots. If the fusion was placed independently (not part of any block), build_chain fires normally.

**Scenario B: Chain triggers new block**

Build_chain can be extended to trigger the creation of a new block:

```json
// Hypothetical build_chain extension (future Phase C):
"armfus": {
    "block": "fusion_complex"  // instead of "hub", trigger a block template
}
```

This is a Phase C enhancement. For Phase A/B, both systems operate independently: templates handle what they handle, build_chain handles the rest.

**Scenario C: Hybrid -- chain fills within block**

The most elegant integration: build_chain hub entries are reinterpreted as "fill next slot in active block." The chain's offset is ignored (replaced by the template's slot positions), but the chain's conditions and building types are respected.

### 7.3 Integration with AngelScript Role Handlers

The role handlers (`tech.as`, `front.as`, `air.as`, etc.) currently call `Builder::MakeDefaultTaskWithLog()` which in turn calls `aiBuilderMgr.DefaultMakeTask(unit)`. The C++ engine then decides what and where to build.

The block template system intercepts this flow for managed building types:

```
CURRENT FLOW:
  Role handler -> DefaultMakeTask() -> C++ decides position -> builder moves & builds

NEW FLOW (for block-managed types):
  Role handler -> BlockPlanner.GetNextTask(builder) -> either:
    a. Fill next slot in existing block -> Enqueue(SBuildTask) with explicit position
    b. Start new block -> FindBlockSeed + PlaceBlock + Enqueue first slot
    c. No block needed -> fall through to DefaultMakeTask() (unchanged)
```

In code:
```angelscript
IUnitTask@ MakeTaskWithBlocks(Id unitId, const string &in roleLabel)
{
    CCircuitUnit@ v = ai.GetTeamUnit(unitId);
    if (v is null) return null;

    // Try block-based placement first
    IUnitTask@ blockTask = BlockPlanner::GetNextTask(v, roleLabel);
    if (blockTask !is null) {
        return blockTask;
    }

    // Fall through to C++ default for non-blocked building types
    return aiBuilderMgr.DefaultMakeTask(v);
}
```

**Per-role block priorities:**

| Role | Primary Block Templates | Notes |
|------|------------------------|-------|
| TECH | `wind_block_4x4`, `solar_block_3x3`, `fusion_complex` | Tech focuses on energy infrastructure |
| FRONT | `factory_cluster_t1`, `factory_cluster_t2`, `defense_line` | Front focuses on production and defense |
| AIR | `aa_cluster` | Air role handles AA batteries |
| SEA | (water-specific templates, future) | Naval blocks are Phase D |

Each role declares which templates it will use. The `BlockPlanner` checks the role's template list when deciding what to build.

### 7.4 Integration with CBuilderManager

The critical integration point. Two pathways exist for creating build tasks:

**Pathway 1: DefaultMakeTask (current)**
```angelscript
IUnitTask@ t = aiBuilderMgr.DefaultMakeTask(v);
```
The C++ engine decides everything: what to build, where to build it, which builder gets it. The block_map constraints are applied internally.

**Pathway 2: Enqueue with explicit position (block system)**
```angelscript
SBuildTask task = TaskB::Common(
    Task::BuildType::ENERGY,          // build type
    Task::Priority::NORMAL,           // priority
    windDef,                          // CCircuitDef@ for the wind turbine
    slotWorldPosition,                // explicit position from our block template
    16.0f,                            // shake: very small (1 SQUARE_SIZE) to keep it precise
    true,                             // isActive
    ASSIGN_TIMEOUT                    // timeout
);
IUnitTask@ t = aiBuilderMgr.Enqueue(task);
```

The `shake` parameter is critical. In the default system, `shake` is typically `SQUARE_SIZE * 32 = 256 elmos`, giving the engine a lot of freedom to randomize the position. For block-based placement, we want **minimal shake** -- `SQUARE_SIZE * 2 = 16 elmos` or even `0` -- because the position was carefully planned.

**The Enqueue pathway already exists** and is used extensively in the current codebase:
- `Builder::_EnqueueGenericByName()` -- enqueues structures by name at anchor positions
- `Builder::EnqueueStaticAALight()`, `EnqueueStaticLLT()`, etc. -- specific structure types
- All of these call `aiBuilderMgr.Enqueue(TaskB::Common(...))` with explicit positions

The block template system simply generates the positions more intelligently than ad-hoc anchor offsets.

---

## 8. Block State Tracking

The system must track active blocks across the game lifetime. This state lives in AngelScript memory, not in config files.

### 8.1 Data Structures

```angelscript
// ============================================================
// BLOCK SLOT -- one building position within a block
// ============================================================
enum SlotState {
    EMPTY = 0,           // not yet attempted
    PLANNED,             // build task enqueued
    BUILT,               // building completed
    TERRAIN_SKIP,        // terrain validation failed, permanently skipped
    CONDITIONAL_SKIP,    // condition not met, may retry later
    DESTROYED            // building was built but later destroyed
}

class BlockSlot {
    AIFloat3 worldPosition;      // absolute world position
    string buildingName;         // unit def name to build here
    string buildingCategory;     // block_map category
    string role;                 // "seed", "fill", "optional"
    SlotState state;             // current state
    Id unitId;                   // unit id once built (or -1)
    int enqueueFrame;            // frame when build task was enqueued
    int builtFrame;              // frame when construction completed
    Task::Priority priority;     // build priority for this slot

    BlockSlot() {
        state = SlotState::EMPTY;
        unitId = Id(-1);
        enqueueFrame = -1;
        builtFrame = -1;
        priority = Task::Priority::NORMAL;
    }

    bool IsAvailable() {
        return state == SlotState::EMPTY || state == SlotState::CONDITIONAL_SKIP;
    }

    bool IsTerminal() {
        return state == SlotState::BUILT || state == SlotState::TERRAIN_SKIP;
    }
}

// ============================================================
// BLOCK INSTANCE -- one placed block in the world
// ============================================================
class BlockInstance {
    string templateName;           // which template definition
    string category;               // block_map category
    AIFloat3 seedPosition;         // world position of block origin
    int facing;                    // 0-3 orientation
    array<BlockSlot@> slots;       // all slots in this block
    int createdFrame;              // when this block was created
    bool isComplete;               // all slots filled or terminal

    int GetFilledCount() {
        int count = 0;
        for (uint i = 0; i < slots.length(); ++i) {
            if (slots[i].state == SlotState::BUILT) count++;
        }
        return count;
    }

    int GetPlannedCount() {
        int count = 0;
        for (uint i = 0; i < slots.length(); ++i) {
            if (slots[i].state == SlotState::PLANNED) count++;
        }
        return count;
    }

    int GetAvailableCount() {
        int count = 0;
        for (uint i = 0; i < slots.length(); ++i) {
            if (slots[i].IsAvailable()) count++;
        }
        return count;
    }

    BlockSlot@ GetNextAvailableSlot() {
        // Returns first slot in fill order that is EMPTY or CONDITIONAL_SKIP
        for (uint i = 0; i < slots.length(); ++i) {
            if (slots[i].IsAvailable()) return slots[i];
        }
        return null;
    }

    void UpdateCompletionState() {
        for (uint i = 0; i < slots.length(); ++i) {
            if (!slots[i].IsTerminal() && slots[i].state != SlotState::CONDITIONAL_SKIP) {
                isComplete = false;
                return;
            }
        }
        isComplete = true;
    }

    // Check if a specific unit belongs to this block
    BlockSlot@ FindSlotByUnit(Id uid) {
        for (uint i = 0; i < slots.length(); ++i) {
            if (slots[i].unitId == uid) return slots[i];
        }
        return null;
    }

    // Check if a world position matches any slot in this block
    BlockSlot@ FindSlotNearPosition(AIFloat3 pos, float tolerance = 32.f) {
        for (uint i = 0; i < slots.length(); ++i) {
            float dx = slots[i].worldPosition.x - pos.x;
            float dz = slots[i].worldPosition.z - pos.z;
            if (dx * dx + dz * dz < tolerance * tolerance) {
                return slots[i];
            }
        }
        return null;
    }
}

// ============================================================
// BLOCK PLANNER -- global block management
// ============================================================
class BlockPlanner {
    array<BlockInstance@> activeBlocks;    // all active blocks
    array<BlockInstance@> completedBlocks; // archived completed blocks
    dictionary templateDefs;              // loaded template definitions

    // Find an existing block of the given category that has room
    BlockInstance@ FindBlockWithRoom(const string &in category) {
        for (uint i = 0; i < activeBlocks.length(); ++i) {
            if (activeBlocks[i].category == category
                && activeBlocks[i].GetAvailableCount() > 0) {
                return activeBlocks[i];
            }
        }
        return null;
    }

    // Get the next build task for a builder, using block placement
    IUnitTask@ GetNextTask(CCircuitUnit@ builder, const string &in roleLabel) {
        // 1. Check if any active block has an unfilled slot
        //    (prefer filling existing blocks over starting new ones)
        // 2. If not, determine if a new block should be started
        //    based on economy state and role priorities
        // 3. If starting new block: FindBlockSeed + PlaceBlock
        // 4. Enqueue the build task for the first/next slot
        // 5. Return the task, or null to fall through to DefaultMakeTask
        // ... (see Section 5 for full algorithm)
        return null; // placeholder
    }

    // Called when any building completes construction
    void OnBuildingComplete(CCircuitUnit@ unit) {
        // Check if this building belongs to any active block
        for (uint i = 0; i < activeBlocks.length(); ++i) {
            BlockSlot@ slot = activeBlocks[i].FindSlotNearPosition(
                unit.GetPos(ai.frame), 48.f
            );
            if (slot !is null && slot.state == SlotState::PLANNED) {
                slot.state = SlotState::BUILT;
                slot.unitId = unit.id;
                slot.builtFrame = ai.frame;
                activeBlocks[i].UpdateCompletionState();

                // If block is complete, move to completed list
                if (activeBlocks[i].isComplete) {
                    completedBlocks.insertLast(activeBlocks[i]);
                    activeBlocks.removeAt(i);
                }
                return;
            }
        }
    }

    // Called when a building is destroyed
    void OnBuildingDestroyed(Id unitId) {
        // Check active blocks
        for (uint i = 0; i < activeBlocks.length(); ++i) {
            BlockSlot@ slot = activeBlocks[i].FindSlotByUnit(unitId);
            if (slot !is null) {
                slot.state = SlotState::DESTROYED;
                slot.unitId = Id(-1);
                // Block may need repair -- re-mark as incomplete
                activeBlocks[i].isComplete = false;
                return;
            }
        }
        // Check completed blocks (building destroyed after block was archived)
        for (uint i = 0; i < completedBlocks.length(); ++i) {
            BlockSlot@ slot = completedBlocks[i].FindSlotByUnit(unitId);
            if (slot !is null) {
                slot.state = SlotState::DESTROYED;
                slot.unitId = Id(-1);
                // Move back to active for rebuild consideration
                activeBlocks.insertLast(completedBlocks[i]);
                completedBlocks.removeAt(i);
                return;
            }
        }
    }

    // Periodic update: retry CONDITIONAL_SKIP slots, clean up stale blocks
    void Update(int frame) {
        for (uint i = 0; i < activeBlocks.length(); ++i) {
            BlockInstance@ block = activeBlocks[i];

            // Re-evaluate conditional skips
            for (uint j = 0; j < block.slots.length(); ++j) {
                if (block.slots[j].state == SlotState::CONDITIONAL_SKIP) {
                    // Re-check conditions (air threat, energy surplus, etc.)
                    // If now met, mark as EMPTY so it can be picked up
                }
            }

            // Timeout check: if a PLANNED slot has been pending too long
            for (uint j = 0; j < block.slots.length(); ++j) {
                if (block.slots[j].state == SlotState::PLANNED
                    && (frame - block.slots[j].enqueueFrame) > ASSIGN_TIMEOUT) {
                    // Build task expired -- mark as EMPTY for retry
                    block.slots[j].state = SlotState::EMPTY;
                    block.slots[j].enqueueFrame = -1;
                }
            }

            block.UpdateCompletionState();
        }
    }
}
```

### 8.2 Memory Considerations

Each `BlockInstance` contains an array of `BlockSlot` objects. For a 4x4 wind farm, that is 16 slots. For a fusion complex, 11 slots. In a typical game, an AI might create 10-20 blocks total. At 16 slots per block with ~64 bytes per slot, total memory is roughly:

```
20 blocks * 16 slots * 64 bytes = ~20 KB
```

This is negligible. AngelScript dictionaries and arrays handle this without issue.

### 8.3 Persistence

Block state is NOT persisted to disk. If the game is saved and reloaded, block state is lost. This is acceptable because:

1. The block system is advisory, not mandatory -- buildings still function without block tracking
2. On reload, the system can scan existing buildings and reconstruct approximate block state
3. The C++ engine handles save/load of actual units and build tasks

A future enhancement could serialize block state to a game-state string, but this is out of scope for the initial implementation.

---

## 9. Zone System Integration

Jules's Build Module Quest notes describe a zone-based approach to base layout. The block template system maps naturally onto these zones.

### 9.1 Zone Definitions

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    ENEMY TERRITORY                              │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  FRONT LINE (no building, active combat)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DEFENSIVE PERIMETER                                            │
│  defense_line blocks go here                                    │
│  aa_cluster blocks go here                                      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BUILDING ZONE (safe territory, main base)                      │
│                                                                 │
│  ┌────────┐  ┌──────────────┐  ┌────────┐                      │
│  │ WIND   │  │  FACTORY     │  │ WIND   │                      │
│  │ BLOCK  │  │  CLUSTER     │  │ BLOCK  │                      │
│  └────────┘  └──────────────┘  └────────┘                      │
│                                                                 │
│  ┌──────────────────┐  ┌─────────┐                              │
│  │ FUSION COMPLEX   │  │ STORAGE │                              │
│  └──────────────────┘  └─────────┘                              │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  EXPANSION ZONE (toward unclaimed mex spots)                    │
│  New blocks seed here when building zone fills up               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 9.2 Zone -> Template Mapping

| Zone | Allowed Templates | Placement Priority |
|------|------------------|-------------------|
| **Defensive Perimeter** | `defense_line`, `aa_cluster` | Highest -- protect the base |
| **Building Zone** (near factories) | `factory_cluster_t1/t2`, `converter_block`, `storage_block` | High -- production infrastructure |
| **Building Zone** (behind factories) | `wind_block_4x4`, `solar_block_3x3`, `fusion_complex` | Normal -- energy behind production |
| **Expansion Zone** | `wind_block_3x3`, `defense_line` (smaller) | Low -- expand gradually |
| **Front Line** | NONE | Never build blocks here |

### 9.3 Zone Detection

The Barb3 engine already provides zone information through the terrain manager:

```angelscript
// Existing API (from terrain.as and the C++ terrain manager):
aiTerrainMgr.SetAllyZoneRange(range);   // ally zone boundary
// Enemy position detection via military manager
// Front line approximation via threat maps
```

For the block system, zone boundaries can be approximated:

```
BUILDING ZONE boundary:
  = ally_zone_range from base center
  = typically 600-1200 elmos from start position

DEFENSIVE PERIMETER:
  = outer ring of building zone
  = ally_zone_range * 0.8 to ally_zone_range * 1.0

EXPANSION ZONE:
  = beyond building zone, toward unclaimed metal spots
  = ally_zone_range * 1.0 to * 1.5

FRONT LINE:
  = average position of forward military units
  = or midpoint between own and enemy start positions
```

### 9.4 Interaction with Barb3's Zone System

Barb3 already has the concept of `AllyZoneRange` (set per-role in the init functions). The block seed selection algorithm (Section 6) uses this as the primary constraint:

- Seeds within `AllyZoneRange * 0.7` = BUILDING ZONE (energy, factories)
- Seeds between `AllyZoneRange * 0.7` and `* 1.0` = DEFENSIVE PERIMETER (defense blocks)
- Seeds beyond `AllyZoneRange * 1.0` = EXPANSION ZONE (only if safe)

---

## 10. Spacing and Safety Rules

### 10.1 Explosion Radius Buffer

From Jules's Build Module Quest notes:
> "No module is ever placed within another module's explosive range or builds itself with buildings in its own explosive range."

This is already partially enforced by `block_map.json` through the `"radius": "explosion"` setting (used for `def_low`, `superweapon`, etc.). However, block-to-block spacing adds an additional layer:

```
RULE: No two blocks of the same type within BLOCK_EXPLOSION_BUFFER elmos
      of each other, where BLOCK_EXPLOSION_BUFFER = max explosion radius
      of any building in the template * 2.

Example: A fusion has an explosion radius of approximately 128 elmos.
         Two fusion_complex blocks should be at least 256 elmos apart
         (center to center of their seed buildings).
```

The block_map `"ignore": ["engy_high"]` for fusion already allows fusions to overlap each other, but the block-level spacing rule keeps entire COMPLEXES separated for survivability.

### 10.2 Factory Exit Lanes

Factory templates must leave the front clear. The existing block_map enforces this through the factory yard (`[0, 30]` = 480 elmo front/back padding), but the template system must additionally:

1. Orient factory blocks so the exit faces the front line (or open terrain)
2. Not place other block templates (wind farms, defense lines) in the factory's exit lane
3. Mark the exit lane as "reserved" so future block seed selection avoids it

```
FACTORY EXIT LANE:

  ┌──────────────┐
  │   FACTORY    │
  └──────┬───────┘
         |
         |  480 elmos (yard[1] * 16)
         |  THIS LANE IS RESERVED
         |  No block seeds allowed here
         |
         v (toward front / open terrain)
```

### 10.3 Pathability

Blocks must not create enclosed spaces that trap constructors.

```
BAD: Walls of buildings with no gaps

  [W][W][W][W][W]
  [W]           [W]
  [W]  TRAPPED  [W]   <- constructor cannot exit
  [W]           [W]
  [W][W][W][W][W]

GOOD: Leave access gaps

  [W][W]   [W][W]
  [W]           [W]
       ACCESS       <- gap for pathfinding
  [W]           [W]
  [W][W]   [W][W]
```

For grid-mode templates, pathability is ensured by the `slot_spacing` values -- the gaps between slots provide natural pathways. For slot-mode templates, the designer must ensure that slot offsets leave movement corridors.

The placement algorithm should additionally verify pathability by checking that the builder can reach all unfilled slots from outside the block. A simple check: ensure at least one edge of the block's bounding box is accessible from the base center.

### 10.4 Metal Spot Exclusion

Metal extractors (mexes) are placed on fixed map spots. Block templates must never cover mex spots with non-mex buildings.

```
RULE: Before committing a block at a seed position, check all known metal
      spots within the block's footprint. If any are found:
      a. If the template is for mexes -- align slots to metal spots (special case)
      b. If not -- shift the seed position to avoid covering the spots
      c. If shifting is not possible -- reject this seed location
```

Mexes have `"ignore": ["all"]` in block_map, so they CAN be placed inside any block's exclusion zone. But we want to prevent the reverse: a wind farm covering a mex spot makes the spot unbuildable (the wind turbine footprint physically occupies the location).

```angelscript
bool HasMexSpotsInFootprint(AIFloat3 seedPos, int footprintW, int footprintD)
{
    // Check all metal spots against the block's bounding box
    // Returns true if any metal spot falls within the block footprint
    // ... uses ai.GetMetalSpots() or equivalent API
    return false; // placeholder
}
```

---

## 11. Configuration Points

Every aspect of the block system is tunable per difficulty profile. This section defines what a profile can adjust.

### 11.1 Profile-Level Settings

These go in the profile's global config (alongside existing settings):

```json
{
    "block_system": {
        "enabled": true,
        "template_file": "block_templates.json",

        "seed_constants": {
            "block_seed_distance": 400,
            "max_base_radius": 1200,
            "max_builder_range": 800,
            "safe_distance": 600,
            "min_block_spacing": 200
        },

        "seed_weights": {
            "base_proximity": 0.3,
            "builder_proximity": 0.2,
            "safety": 0.3,
            "terrain": 0.2,
            "overlap_penalty": 0.5
        },

        "role_templates": {
            "TECH": ["wind_block_4x4", "solar_block_3x3", "fusion_complex", "converter_block"],
            "FRONT": ["factory_cluster_t1", "factory_cluster_t2", "defense_line", "wind_block_3x3"],
            "AIR": ["aa_cluster"],
            "SEA": []
        },

        "template_overrides": {
            "wind_block_4x4": {
                "max_fill": 12,
                "slot_spacing": [48, 48]
            }
        },

        "limits": {
            "max_blocks_per_category": {
                "engy_low": 4,
                "engy_mid": 2,
                "engy_high": 3,
                "factory": 4,
                "def_low": 3,
                "convert": 2
            },
            "max_total_blocks": 20,
            "min_income_for_new_block": {
                "engy_low": 0,
                "engy_mid": 5,
                "engy_high": 15,
                "factory": 0,
                "def_low": 5,
                "convert": 10
            }
        }
    }
}
```

### 11.2 Per-Difficulty Variations

| Setting | Easy | Medium | Hard | Nightmare |
|---------|------|--------|------|-----------|
| `enabled` | false | true | true | true |
| Wind block size | -- | 3x3 (9) | 4x4 (16) | 4x4 (16) |
| Solar block size | -- | 2x2 (4) | 3x3 (9) | 3x3 (9) |
| Factory cluster nanos | -- | 2 | 3 | 4 |
| Defense line turrets | -- | 3 | 5 | 7 |
| Max blocks per category | -- | 2 | 3 | 5 |
| Max total blocks | -- | 8 | 15 | 25 |
| Min income for fusion_complex | -- | 20 | 15 | 10 |
| Block spacing tightness | -- | 1.2x | 1.0x | 0.8x |

Easy difficulty does not use the block system (falls through to DefaultMakeTask for classic scatter behavior). This ensures backward compatibility.

### 11.3 Per-Map Overrides

Some maps require adjusted block configurations:

```json
{
    "map_overrides": {
        "Supreme_Isthmus": {
            "template_overrides": {
                "wind_block_4x4": {"grid": [3, 3], "max_fill": 9},
                "defense_line": {"grid": [3, 1], "max_fill": 3}
            },
            "seed_constants": {"safe_distance": 400}
        },
        "Throne_v2": {
            "limits": {"max_blocks_per_category": {"engy_low": 2}}
        }
    }
}
```

Maps with tight starting positions (like isthmus maps) use smaller blocks. Maps with wide-open spaces can use larger blocks and more aggressive expansion.

---

## 12. Phased Implementation Plan

### Phase A: MVP (Proof of Concept)

**Goal:** Demonstrate that block-based placement works for one building type.

**Scope:**
- One template: `wind_block_4x4`
- Hard-coded in AngelScript (no JSON loading yet)
- Intercept wind turbine placement in TECH role only
- No block state tracking beyond a simple array
- No build_chain integration (wind turbines have no chain entries anyway)

**Implementation Steps:**

1. Create `block_planner.as` in `script/src/helpers/`
2. Define `WindBlockTemplate` as a hard-coded class with 4x4 grid offsets
3. Add `BlockSlot` and `BlockInstance` classes (simplified)
4. Implement `PlaceBlock()` with `TestBuildOrder` validation
5. Implement `FindWindBlockSeed()` using base center + factory positions
6. In `tech.as` builder task creation, intercept wind turbine build requests:
   - Before calling `DefaultMakeTask`, check if a wind block needs filling
   - If yes: enqueue wind turbine at the next block slot position
   - If no: fall through to default behavior

**Success Criteria:**
- Wind turbines form visible 4x4 grids instead of scattering
- No regression in other building types (everything else still uses DefaultMakeTask)
- Builder walk time between wind turbines is visibly reduced
- Works on at least 3 different maps

**Estimated Effort:** 2-3 sessions

### Phase B: Template Library + State Tracking

**Goal:** Full block template system with JSON config and proper state management.

**Scope:**
- All templates from Section 4 (wind, solar, fusion, factory, defense, converter, storage, AA)
- JSON-based template loading (alongside block_map.json in profile config)
- Full BlockSlot / BlockInstance / BlockPlanner classes
- Seed point selection algorithm (scored candidates)
- OnBuildingComplete / OnBuildingDestroyed hooks
- Per-role template assignments

**Implementation Steps:**

1. Create `block_templates.json` config file
2. Build JSON parser for template definitions (grid mode + slot mode)
3. Implement faction-specific building resolution (category -> unit name)
4. Full `BlockPlanner` class with `activeBlocks` / `completedBlocks`
5. Implement `FindBlockSeed()` with scored candidate positions
6. Hook into `OnBuildingComplete` to update block slot states
7. Hook into `OnBuildingDestroyed` to mark slots as DESTROYED
8. Modify all role handlers to use `MakeTaskWithBlocks()` instead of raw `DefaultMakeTask`
9. Periodic `BlockPlanner.Update()` for timeout cleanup and condition re-evaluation

**Success Criteria:**
- All energy blocks (wind, solar, fusion) place in organized clusters
- Factory clusters have nanos properly positioned around them
- Defense lines form along the defensive perimeter
- Block state survives across the game (tracks fills, completions, destructions)
- Configurable per-profile

**Estimated Effort:** 4-6 sessions

### Phase C: Full Integration

**Goal:** Deep integration with build_chain, per-role priorities, and zone awareness.

**Scope:**
- Build_chain suppression for block-managed buildings
- Build_chain triggers new block creation
- Zone-aware seed selection (building zone, defensive perimeter, expansion zone)
- Per-map configuration overrides
- Block rotation and terrain adaptation (auto-facing)
- Rebuild logic for destroyed blocks

**Implementation Steps:**

1. Modify build_chain handling to check block membership before firing
2. Add `"block"` trigger type to build_chain schema
3. Implement zone boundary detection using AllyZoneRange
4. Add map override loading and merging
5. Implement auto-rotation (try all 4 facings, pick best)
6. Implement rebuild-or-abandon decision for destroyed blocks
7. Performance profiling and optimization

**Success Criteria:**
- Build chains and blocks work together without double-building
- Fusion completion triggers converter_block creation (via chain -> block)
- Zone boundaries correctly constrain block placement
- Maps with irregular terrain still produce reasonable layouts
- No noticeable performance impact

**Estimated Effort:** 4-6 sessions

### Phase D: Polish + All Factions

**Goal:** Production-ready system across all factions, difficulties, and map types.

**Scope:**
- All three factions (Armada, Cortex, Legion) with faction-specific templates
- All difficulty profiles (Easy: disabled, Medium-Nightmare: tuned)
- Water map support (tidal blocks, shipyard clusters)
- Island map support (smaller blocks, per-island seeding)
- Edge case handling (steep terrain, narrow passages, 1v1 vs FFA)
- Performance optimization (block count limits, lazy evaluation)
- Comprehensive logging for debugging

**Implementation Steps:**

1. Create faction-specific template variants where needed
2. Tune all difficulty profiles
3. Add water-specific templates (tidal_block, shipyard_cluster)
4. Test on map archetypes: open (All That Glitters), tight (Supreme Isthmus), island (Throne), water (Tundra Continents)
5. Stress test with multiple AIs on large maps
6. Final performance pass

**Success Criteria:**
- All factions produce organized bases on all map types
- No crashes, hangs, or infinite loops in block placement
- Performance: < 1ms per frame for block system overhead
- Visual improvement is obvious to players watching the AI

**Estimated Effort:** 3-5 sessions

### Implementation Timeline

```
Phase A: Sessions N to N+2    (MVP: wind blocks only)
Phase B: Sessions N+3 to N+8  (Full template library)
Phase C: Sessions N+9 to N+14 (Deep integration)
Phase D: Sessions N+15 to N+19 (Polish + all factions)

Total estimated: 13-20 sessions
```

---

## 13. Open Questions

### 13.1 Irregular Terrain

**Question:** How does the AI handle blocks on maps with significant height variation, cliffs, or water edges?

**Proposed Answer:** The `TestBuildOrder` engine call already handles terrain validation per-slot. If a slot fails terrain check, it is marked as `TERRAIN_SKIP` and the block has a gap. The `min_fill` threshold determines whether the block is still worth committing. For very rough terrain, the auto-rotation system tries all 4 orientations to find the one with the most valid slots. Maps with extreme terrain (like mountain passes) may need smaller block templates via map overrides.

### 13.2 Partial Destruction

**Question:** When a block is partially destroyed, should the AI rebuild or start a new block?

**Proposed Answer:** Decision tree:
1. If < 30% of the block is destroyed: rebuild in place (mark destroyed slots as EMPTY)
2. If 30-70% destroyed: evaluate economy. If surplus, rebuild. If strained, abandon.
3. If > 70% destroyed: abandon the block (mark all remaining slots as TERRAIN_SKIP)
4. A "rebuild" simply re-enqueues build tasks at the original slot positions.

The `OnBuildingDestroyed` handler marks slots as `DESTROYED`. The periodic `Update()` can re-mark these as `EMPTY` if rebuild is chosen.

### 13.3 Block Priority vs DefaultMakeTask

**Question:** Should blocks have priority over individual DefaultMakeTask decisions?

**Proposed Answer:** Yes, within limits. If a block has unfilled slots AND the builder can build that building type, the block takes priority. This prevents the C++ engine from placing a wind turbine across the map when there is an unfilled slot in a nearby wind block.

However, DefaultMakeTask still controls building type selection (what to build next: energy, factory, defense). The block system only controls WHERE that building goes. The decision flow:

```
1. C++ economy manager decides "need more energy" (DefaultMakeTask would build a wind)
2. Block system intercepts: "there's a wind block with empty slots near the builder"
3. Block system: Enqueue wind at the specific slot position
4. Result: same building type, organized position
```

If no block has room and no new block can be seeded, DefaultMakeTask fires as fallback.

### 13.4 Opening Build Order Transition

**Question:** How to handle the transition from the scripted opening build order to block-based mid-game?

**Proposed Answer:** The opening build order (commander's initial sequence) runs first and is not affected by the block system. The block system activates once the first factory is complete and the economy transitions from "opening" to "steady state."

Detection heuristic: `block_system_active = (ai.frame > 3 * MINUTE) && (factory_count > 0)`

Alternatively, the first factory's build_chain could trigger the creation of the first energy block behind the factory, providing a smooth transition:

```
Commander builds factory -> Factory completes -> build_chain triggers ->
  Block system: "Factory cluster complete. Seed wind_block_4x4 behind factory."
```

### 13.5 Cooperative AI (Multi-AI Teams)

**Question:** When multiple AIs share a team, how do blocks interact?

**Proposed Answer:** Each AI maintains its own block state independently. Block_map exclusion zones are shared via the C++ engine (one AI's buildings create exclusion zones that other AIs respect). The block seed selection algorithm naturally avoids areas already occupied by allies because `TestBuildOrder` will fail at positions where ally buildings exist.

No explicit inter-AI block coordination is needed for Phase A-C. Phase D could add ally-awareness to seed selection (e.g., "don't seed a wind block where the ally is already building").

### 13.6 Performance Budget

**Question:** What is the performance budget for the block system?

**Proposed Answer:** Target: < 1ms per frame averaged over 30 frames. The block system does not need to run every frame:

```
Block Planning:  every 30 frames (1 second)  -- check for unfilled slots
Seed Search:     every 300 frames (10 seconds) -- look for new block locations
State Update:    every 90 frames (3 seconds)  -- timeout cleanup, condition re-eval
```

The most expensive operation is `FindBlockSeed` (scoring candidate positions, trying `PlaceBlock` at each). This is bounded by the number of candidates (typically 5-10) and the number of slots per template (typically 4-16). Each `TestBuildOrder` call is an engine callback and is the main cost.

Worst case: 10 candidates * 16 slots * 1 TestBuildOrder = 160 engine calls per seed search. At 10-second intervals, this is ~16 calls per second -- well within budget.

---

## Summary: The One-Page Version

The Modular Block-Based Building Placement system adds **positive placement guidance** to Barb3's existing negative constraint system (block_map) and reactive adjacency system (build_chain).

**What it is:** A library of JSON-defined block templates (wind farms, factory clusters, defense lines, fusion complexes) that specify where buildings should go relative to each other, placed as organized groups in the game world.

**How it works:**
1. Role handler decides a building type is needed (energy, factory, defense)
2. Block Planner checks: is there an existing block with room? If yes, fill the next slot.
3. If not, find a new location (scored candidates based on base center, safety, terrain)
4. Validate each slot position via `TestBuildOrder` (engine enforces block_map constraints)
5. Enqueue build tasks at explicit positions via `aiBuilderMgr.Enqueue(SBuildTask)`
6. Track block state: planned, built, destroyed, complete

**What it preserves:** block_map.json exclusion zones, build_chain.json reactions, DefaultMakeTask fallback for unmanaged building types, all existing role handler logic.

**What it adds:** Organized base layouts, reduced builder walking time, defensible building clusters, configurable per-difficulty and per-map.

**Implementation:** Four phases over 13-20 sessions, starting with a wind-block MVP in AngelScript and culminating in a production-ready system across all factions and map types.

---

*End of Research Report 08.*
