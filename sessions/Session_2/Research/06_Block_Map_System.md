# Research Report 06: The Block Map & Build Chain System

> **Session:** Session_2 (BARB Quest)
> **Date:** 2026-02-13
> **Status:** KEY FILE -- Deep-dive analysis of the spatial blocking and building chain systems
> **Source Files:**
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/block_map.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/ArmadaBuildChain.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/CortexBuildChain.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/LegionBuildChain.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/ArmadaEconomy.json`
> - `Prod/Skirmish/Barb3/stable/config/experimental_balanced/ArmadaFactory.json`
> - `Prod/Skirmish/Barb3/stable/script/experimental_balanced/init.as`
> - `Prod/Skirmish/Barb3/stable/script/src/define.as`

---

## Table of Contents

1. [Block Map Overview](#1-block-map-overview)
2. [Configuration Schema](#2-configuration-schema)
3. [Units of Measurement](#3-units-of-measurement)
4. [Blocker Shapes](#4-blocker-shapes)
5. [Structure Types -- Full Taxonomy](#5-structure-types----full-taxonomy)
6. [The Ignore / Not_Ignore System](#6-the-ignore--not_ignore-system)
7. [Instance Mapping -- Units to Categories](#7-instance-mapping----units-to-categories)
8. [Build Chain System](#8-build-chain-system)
9. [How Block Map Interacts with C++ Placement](#9-how-block-map-interacts-with-c-placement)
10. [Current Limitations -- Why Buildings Still Scatter](#10-current-limitations----why-buildings-still-scatter)
11. [What Needs to Change for True Block Placement](#11-what-needs-to-change-for-true-block-placement)
12. [Full Annotated block_map.json](#appendix-a-full-annotated-block_mapjson)

---

## 1. Block Map Overview

`block_map.json` is the spatial blocking configuration file consumed by the C++ CircuitAI engine (which powers Barb3). It defines **exclusion zones** around every building category, controlling the minimum spacing between structures during AI placement.

**What it does:**
- Assigns every building to a **category** (e.g., `fac_land_t1`, `solar`, `def_low`)
- Defines a **blocker shape** (rectangle or circle) around each category
- Specifies **size**, **yard** (spacer), and **offset** for rectangle blockers
- Specifies **radius** for circle blockers
- Controls which structure types **ignore** or **respect** each other's exclusion zones

**What it does NOT do:**
- It does not tell the AI **where** to place buildings (positive guidance)
- It does not define building **groups** or **modules**
- It does not plan ahead -- each building is placed independently
- It does not create organized layouts -- only prevents overlaps

**How it is loaded:** The file is listed as a profile config in the AngelScript init:

```angelscript
// From: script/experimental_balanced/init.as
@data.profile = @(array<string> = {
    "ArmadaBehaviour",
    "CortexBehaviour",
    "ArmadaBuildChain",
    "CortexBuildChain",
    "block_map",           // <-- loaded here, shared across all factions
    "commander",
    "ArmadaEconomy",
    ...
});
```

Key observation: `block_map.json` is **faction-agnostic** -- it is loaded once and applies to all factions (Armada, Cortex, Legion). The `instance` section maps each faction's specific unit names to the shared category definitions.

---

## 2. Configuration Schema

The full schema of `block_map.json` follows this structure:

```
{
  "building": {
    "class_land": {
      "<category_name>": {
        "type": [<blocker_shape>, <structure_type>],
        "offset": [left/right, front/back],
        "size": [width, depth],
        "yard": [width_extra, depth_extra],
        "radius": <int | "explosion" | "expl_ally">,
        "ignore": [<structure_type>, ...],
        "not_ignore": [<structure_type>, ...]
      },
      ...
      "_default_": { ... }
    },
    "instance": {
      "<category_name>": ["unit1", "unit2", ...],
      ...
    }
  }
}
```

### Field-by-Field Breakdown

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | `[string, string]` | Required | `[blocker_shape, structure_type]`. Shape is `"rectangle"` or `"circle"`. Structure type is one of the taxonomy values (see Section 5). |
| `offset` | `[int, int]` | `[0, 0]` | Shifts the yardmap relative to the building center, in block_map units. First value = left/right, second = front/back. Orientation is **South-facing**. |
| `size` | `[int, int]` | Unit's footprint | Size of the blocker rectangle **without** yard. In block_map units. |
| `yard` | `[int, int]` | `[0, 0]` | Additional spacer added to size. `block_size = size + yard`. This is the padding that enforces spacing. |
| `radius` | `int` or `string` | `"explosion"` | For circle blockers only. Integer = fixed radius in block_map units. `"explosion"` = auto-calculated from unit's explosion radius. `"expl_ally"` = scales with ally count. |
| `ignore` | `[string, ...]` | `["none"]` | List of structure types whose exclusion zones this building can overlap. Special values: `"none"` (respect all), `"all"` (ignore everything). |
| `not_ignore` | `[string, ...]` | N/A | Inverse of ignore: **only** the listed structure types block this building. Everything else is allowed to overlap. Cannot coexist with `ignore`. |

### Important Default Behaviors

- If neither `ignore` nor `not_ignore` is specified, the default is `"ignore": ["none"]` -- maximum strictness, nothing overlaps.
- If `size` is not specified, it defaults to the unit's actual footprint from the UnitDef.
- The `_default_` category is a catch-all for any building not explicitly mapped in `instance`.

---

## 3. Units of Measurement

This is the single most important technical detail for working with `block_map.json`.

### The Conversion Chain

```
1 block_map unit = SQUARE_SIZE * 2 = 8 * 2 = 16 elmos
```

From `define.as`:
```angelscript
const int SQUARE_SIZE = 8;
```

And from the block_map.json comments:
```json
// Unit of measurement: 1 size/yard/radius = SQUARE_SIZE * 2 = 16 elmos, integer.
```

### Conversion Table

| Block Map Units | Game Squares (8 elmo) | Elmos |
|----------------:|----------------------:|------:|
| 1 | 2 | 16 |
| 2 | 4 | 32 |
| 4 | 8 | 64 |
| 5 | 10 | 80 |
| 6 | 12 | 96 |
| 7 | 14 | 112 |
| 8 | 16 | 128 |
| 10 | 20 | 160 |
| 12 | 24 | 192 |
| 20 | 40 | 320 |
| 30 | 60 | 480 |

### Worked Example: T1 Land Factory (`fac_land_t1`)

```json
"fac_land_t1": {
    "type": ["rectangle", "factory"],
    "offset": [0, 5],
    "size": [8, 8],
    "yard": [0, 30]
}
```

- **size**: `[8, 8]` = 128 x 128 elmos (the building footprint)
- **yard**: `[0, 30]` = 0 elmo side padding, 480 elmo front/back padding
- **block_size**: `size + yard = [8, 38]` = 128 x 608 elmos total exclusion zone
- **offset**: `[0, 5]` = center shifted 80 elmos toward the back (South-facing)

The massive 480 elmo front/back yard on T1 factories creates a long exclusion lane -- this is the **factory exit corridor**. Units rolling off the production line need clear space to move, so the block_map enforces a 480-elmo buffer in front of and behind the factory.

### Why the Factory Yard is Asymmetric

The `offset: [0, 5]` shifts the center 80 elmos toward the back. Combined with the yard, this means the exclusion zone extends **further in front** (where units exit) than behind. The total zone from center:
- Front: `(38/2 * 16) - (5 * 16)` = 304 - 80 = **224 elmos forward**
- Back: `(38/2 * 16) + (5 * 16)` = 304 + 80 = **384 elmos backward**

This creates a generous exit lane while allowing tighter packing behind factories.

---

## 4. Blocker Shapes

### Rectangle Blockers

The primary shape for most buildings. Defined by `size`, `yard`, and `offset`.

**Block size calculation:**
```
block_width  = (size[0] + yard[0]) * 16 elmos
block_depth  = (size[1] + yard[1]) * 16 elmos
```

**Offset shifts the yardmap center** in South-facing orientation:
- `offset[0]` > 0 shifts right, < 0 shifts left
- `offset[1]` > 0 shifts toward back, < 0 shifts toward front

**All rectangle entries in the config:**

| Category | size | yard | offset | Total Block (elmos) |
|----------|------|------|--------|---------------------|
| `fac_land_t1` | [8,8] | [0,30] | [0,5] | 128 x 608 |
| `fac_land_t2` | (default) | [12,20] | [4,6] | ~(def+192) x (def+320) |
| `fac_air` | (default) | (none) | (none) | Unit footprint only |
| `fac_water` | (default) | [10,12] | [0,4] | ~(def+160) x (def+192) |
| `fac_strider` | (default) | [6,8] | [0,4] | ~(def+96) x (def+128) |
| `solar` | (default) | [6,6] | (none) | ~(def+96) x (def+96) |
| `advsolar` | (default) | [5,5] | (none) | ~(def+80) x (def+80) |
| `wind` | (default) | (none) | (none) | Unit footprint only |
| `geo` | (default) | [4,4] | (none) | ~(def+64) x (def+64) |
| `geo2` | (default) | [6,6] | (none) | ~(def+96) x (def+96) |
| `fusion` | (default) | [5,5] | (none) | ~(def+80) x (def+80) |
| `store` | (default) | [4,4] | (none) | ~(def+64) x (def+64) |
| `mex` | (default) | (none) | [0,-4] | Unit footprint, shifted 64 elmos forward |
| `mex2` | (default) | (none) | (none) | Unit footprint only |
| `converter` | (default) | [7,7] | (none) | ~(def+112) x (def+112) |
| `def_air` | (default) | [2,2] | (none) | ~(def+32) x (def+32) |
| `caretaker` | (default) | (none) | (none) | Unit footprint only |
| `small` | (default) | (none) | (none) | Unit footprint only |
| `_default_` | (default) | [4,4] | (none) | ~(def+64) x (def+64) |

### Circle Blockers

Used for defense turrets and superweapons. Defined by `radius`.

**Block area:** A circle of `radius * 16` elmos centered on the building.

**All circle entries in the config:**

| Category | radius | Elmo Radius | Purpose |
|----------|--------|-------------|---------|
| `def_low` | 6 | 96 | Light turrets (LLT, beamer) -- keep them spread out |
| `def_mid` | 7 | 112 | Medium turrets (HLT, popup) -- slightly wider spread |
| `def_hvy` | 8 | 128 | Heavy turrets (annihilator, doomsday) -- maximum spacing |
| `superweapon` | (has yard [8,8]) | N/A | Uses yard instead of radius, but typed as circle |
| `protector` | (default) | "explosion" | Auto-calculated from explosion radius |

**Special radius values:**
- `"explosion"` -- the C++ engine automatically calculates the radius from the unit's explosion damage radius in its UnitDef. This ensures buildings are spaced outside each other's death explosions.
- `"expl_ally"` -- similar to explosion, but the radius scales inversely with team size: `radius ~ 1 player .. radius/2 ~ 4+ players`. More allies means tighter packing is acceptable because there is more economic redundancy.

The `def_low` comment in the config confirms the math:
```json
"radius": 6,  // 128 / (SQUARE_SIZE * 2) = 128 / 16 = 8
```
Note: the comment says 128/16=8, but the actual value is 6. This appears to be a stale comment -- the radius was likely reduced from 8 to 6 to allow tighter defense clustering.

---

## 5. Structure Types -- Full Taxonomy

The second element in the `"type"` array assigns each building category to a **structure type**. Structure types are the language of the ignore/not_ignore system -- they define which groups of buildings interact with each other.

### Complete Structure Type Inventory

| Structure Type | Categories Using It | Physical Examples | Role |
|----------------|--------------------|--------------------|------|
| `factory` | fac_land_t1, fac_land_t2, fac_air, fac_water, fac_strider | Bot lab, vehicle plant, aircraft plant, shipyard, gantry | Production buildings with exit lanes |
| `mex` | mex, mex2, store | Metal extractors (T1, T2), metal/energy storage | Economy extraction; placed on map spots |
| `geo` | geo, geo2 | Geothermal plant (T1, T2) | Economy extraction; placed on geo spots |
| `pylon` | (not used in current config) | Energy pylons | Grid connectors (reserved for future use) |
| `convert` | converter | Metal makers (T1, T2), floating makers | Resource conversion |
| `engy_low` | wind | Wind turbines, tidal generators | Cheap renewable energy |
| `engy_mid` | solar, advsolar | Solar generators, advanced solar | Mid-tier energy |
| `engy_high` | fusion | Fusion reactors (T2, advanced) | High-tier energy |
| `def_low` | def_low, def_mid, def_hvy | LLT, beamer, HLT, popup, annihilator, doomsday | All defense turrets share one structure type family |
| `special` | superweapon, protector | Nukes, antinukes, shields | Superweapons and shields |
| `nano` | caretaker | Nano caretakers (land and sea) | Construction assist |
| `terra` | (commented out in config) | Terraform | Terrain modification |
| `unknown` | def_air, small, _default_ | AA turrets, radar towers, misc small buildings | Catch-all |

**Critical observation:** `def_mid` and `def_hvy` both use structure type `"def_low"`, not `"def_mid"` or `"def_high"`. This means ALL defense turrets (light, medium, heavy) are treated as the same structure type for ignore/not_ignore purposes. The different circle radii (6, 7, 8) control spacing, but the interaction rules are identical.

The config comments list additional structure types (`def_mid`, `def_high`) that are **defined in the C++ engine** but **not currently used** in this config:
```
// engy_low: wind
// engy_mid: fusion    <-- NOTE: comment says fusion = engy_mid, but config has fusion = engy_high
// engy_high:
// def_low: def_low, llt, dragonclaw
// def_mid:             <-- unused
// def_high:            <-- unused
// unknown: small, default
// special: superweapon
// terra:               <-- commented out
```

---

## 6. The Ignore / Not_Ignore System

This is the interaction engine that controls which buildings can be placed near each other. Every category has either an `ignore` or `not_ignore` list (never both) that determines which structure types it respects.

### How It Works

When the C++ engine tries to place building A:
1. It checks all existing buildings within A's block zone
2. For each existing building B, it checks B's structure type
3. **If A has `"ignore"`:** B's type is in the ignore list --> overlap allowed. Otherwise --> blocked.
4. **If A has `"not_ignore"`:** B's type is in the not_ignore list --> blocked. Otherwise --> overlap allowed.

### Special Values

- `"ignore": ["none"]` -- nothing is ignored; ALL structure types block this building. **This is the default.**
- `"ignore": ["all"]` -- everything is ignored; this building can be placed anywhere (within terrain constraints).

### Concrete Examples from the Config

**1. Wind Turbines -- Can Overlap Each Other**
```json
"wind": {
    "type": ["rectangle", "engy_low"],
    "ignore": ["engy_low"]
}
```
Wind turbines (structure type `engy_low`) ignore each other. They can be packed tightly together because they are small and cheap. But they still respect factory zones, defense zones, etc.

**2. Metal Extractors -- Ignore Everything**
```json
"mex": {
    "type": ["rectangle", "mex"],
    "offset": [0, -4],
    "ignore": ["all"]
}
```
T1 mexes have `"ignore": ["all"]`. They can be placed inside any other building's exclusion zone. This makes sense: mex positions are fixed on the map (at metal spots), so the AI must be able to place them regardless of what else is nearby.

**3. Air Factories -- Selective Blocking**
```json
"fac_air": {
    "type": ["rectangle", "factory"],
    "not_ignore": ["convert", "factory", "special"]
}
```
Air factories use `not_ignore` instead of `ignore`. Only converters, other factories, and superweapons block them. Everything else (defenses, energy, storage) can overlap. This gives air factories more placement freedom since they do not need ground exit lanes.

**4. Stores -- Only Blocked by Factories and Terraform**
```json
"store": {
    "type": ["rectangle", "mex"],
    "yard": [4, 4],
    "not_ignore": ["factory", "terra"]
}
```
Storage buildings can go almost anywhere -- only factory exit lanes and terraform operations block them. Note the structure type is `"mex"` even though it is storage; this means other buildings that ignore `mex` also ignore stores.

**5. Light Defenses -- Ignore Economy Buildings**
```json
"def_low": {
    "type": ["circle", "def_low"],
    "radius": 6,
    "ignore": ["engy_mid", "engy_high", "engy_low", "nano"]
}
```
Light turrets ignore all energy buildings and nano caretakers. They maintain spacing from other defenses, factories, and mexes, but can be freely placed near solar farms and wind fields.

**6. Solar Panels -- Relaxed Spacing**
```json
"solar": {
    "type": ["rectangle", "engy_mid"],
    "ignore": ["engy_mid", "def_low", "mex", "def_low"],
    "yard": [6, 6]
}
```
Solars ignore each other (`engy_mid`), defenses, and mexes. They have a 96-elmo yard, but can be placed near/in defense clusters and mex positions. Note the duplicate `"def_low"` entry -- a harmless bug.

**7. Fusion Reactors -- Ignore Mexes and Other Fusions**
```json
"fusion": {
    "type": ["rectangle", "engy_high"],
    "yard": [5, 5],
    "ignore": ["mex", "engy_high"]
}
```
Fusions can be packed near mexes and near each other. They respect factory zones, defense zones, and converter zones.

**8. T1 Land Factory -- Maximum Strictness**
```json
"fac_land_t1": {
    "type": ["rectangle", "factory"],
    "offset": [0, 5],
    "size": [8, 8],
    "yard": [0, 30]
    // no ignore specified --> defaults to "ignore": ["none"]
}
```
No `ignore` or `not_ignore` specified, so it defaults to `"ignore": ["none"]`. Every structure type blocks T1 land factory placement. Combined with the massive 608-elmo exclusion zone, T1 land factories are the most placement-constrained buildings in the game.

### Interaction Matrix (Key Pairings)

| Building A | Can Overlap B's Zone? | Reason |
|------------|----------------------|--------|
| mex | YES (any building) | `"ignore": ["all"]` |
| wind | wind | `"ignore": ["engy_low"]` |
| solar | solar, defense, mex | `"ignore": ["engy_mid", "def_low", "mex"]` |
| fusion | fusion, mex | `"ignore": ["mex", "engy_high"]` |
| defense (low) | solar, fusion, wind, nano | `"ignore": ["engy_mid", "engy_high", "engy_low", "nano"]` |
| air factory | everything except converters, factories, superweapons | `"not_ignore": ["convert", "factory", "special"]` |
| store | everything except factories, terraform | `"not_ignore": ["factory", "terra"]` |
| small (radar) | everything except factories, defenses, terraform | `"not_ignore": ["factory", "def_low", "terra"]` |
| T1 factory | NOTHING -- blocks everything | default `"ignore": ["none"]` |

---

## 7. Instance Mapping -- Units to Categories

The `instance` section maps specific unit definition names to block_map categories. Every building in the game must appear in one of these lists (or falls into `_default_`).

### Full Instance Map (All Three Factions)

```json
"instance": {
    "fac_land_t2": [
        "armalab",  "armavp",           // Armada T2 bot/veh
        "coralab",  "coravp",           // Cortex T2 bot/veh
        "legalab",  "legavp"            // Legion T2 bot/veh
    ],
    "fac_land_t1": [
        "armlab",   "armvp",   "armhp",  // Armada T1 bot/veh/hover
        "corlab",   "corvp",   "corhp",  // Cortex T1 bot/veh/hover
        "leglab",   "legvp",   "leghp"   // Legion T1 bot/veh/hover
    ],
    "fac_water": [
        "armsy",    "armasy",            // Armada T1/T2 shipyard
        "corsy",    "corasy",            // Cortex T1/T2 shipyard
        "legsy",    "legadvshipyard"     // Legion T1/T2 shipyard
    ],
    "fac_air": [
        "armap",    "armaap",            // Armada T1/T2 air
        "corap",    "coraap",            // Cortex T1/T2 air
        "legap",    "legaap"             // Legion T1/T2 air
    ],
    "fac_strider": [
        "armshltx",   "armshltxuw",      // Armada gantry (land/underwater)
        "corgant",    "corgantuw",       // Cortex gantry (land/underwater)
        "leggant",    "leggantuw"        // Legion gantry (land/underwater)
    ],
    "solar": [
        "armsolar", "corsolar", "legsolar"
    ],
    "advsolar": [
        "armadvsol", "coradvsol", "legadvsol"
    ],
    "wind": [
        "armwin",   "corwin",   "legwin",     // Wind generators
        "armtide",  "cortide",  "legtide"     // Tidal generators
    ],
    "geo": [
        "armgeo",   "corgeo",   "leggeo"      // T1 geothermal
    ],
    "geo2": [
        "armageo",  "corageo",  "legageo"     // T2 geothermal
    ],
    "fusion": [
        "armfus",    "armuwfus",  "armckfus",  "armafus",   // Armada fusions
        "corfus",    "coruwfus",  "corafus",                // Cortex fusions
        "legfus",    "legafus",   "leganavalfusion"         // Legion fusions
    ],
    "store": [
        "armmstor",  "armestor",                // Armada metal/energy storage
        "cormstor",  "corestor",                // Cortex metal/energy storage
        "legmstor",  "legestor"                 // Legion metal/energy storage
    ],
    "mex": [
        "armmex",   "cormex",   "legmex"       // T1 metal extractors
    ],
    "mex2": [
        "armmoho",  "cormoho",  "legmoho",     // T2 metal extractors
        "armuwmme", "coruwmme"                  // Underwater metal extractors
    ],
    "converter": [
        "armmakr",   "cormakr",                 // T1 metal makers
        "armmmkr",   "cormmkr",                 // T2 metal makers
        "armfmkr",   "corfmkr",                 // Floating metal makers
        "armuwmmm",  "coruwmmm",                // Underwater metal makers
        "legeconv",  "legadveconv",             // Legion converters
        "leganavaleconv"                        // Legion naval converter
    ],
    "def_low": [
        "armllt",    "corllt",    "leglht",    // Light laser towers
        "armbeamer", "corhllt",   "legmg"      // Beamers / heavy LLT / MG
    ],
    "def_mid": [
        "armclaw",   "cormaw",                  // Popup defenses
        "armpb",     "corvipe",                 // Pop-up arty
        "armhlt",    "corhlt",    "legdtr",     // Heavy laser turrets
        "legapopupdef", "leghive"               // Legion variants
    ],
    "def_hvy": [
        "armamb",    "cortoast",                // Ambushers / toasters
        "armanni",   "cordoom",                 // Annihilators / doomsdays
        "armguard",  "corpun",                  // Long-range cannons
        "armkraken", "corfdoom",                // Naval heavy
        "legacluster", "legbastion",            // Legion clusters
        "legcluster",  "legfmg"                 // Legion variants
    ],
    "def_air": [
        "armferret", "armcir",                  // Armada AA
        "corrl",     "cormadsam", "corerad",    // Cortex AA
        "legrhapsis", "leglupara"               // Legion AA
    ],
    "caretaker": [
        "armnanotc",     "cornanotc",     "legnanotc",      // Land nanos
        "armnanotcplat", "cornanotcplat", "legnanotcplat"   // Naval nanos
    ],
    "small": [
        "armrad", "corrad", "legrad"            // Radar towers
    ]
}
```

### Notable Observations

1. **Tidal generators share the `wind` category.** `armtide`/`cortide`/`legtide` are in the `wind` category, so they share wind's `"ignore": ["engy_low"]` rule. Tidal gens can overlap each other just like wind turbines.

2. **Hovercraft plants are T1 factories.** `armhp`/`corhp`/`leghp` are in `fac_land_t1`, meaning they get the full 608-elmo exclusion zone and maximum strictness.

3. **AA turrets are "unknown" type.** `def_air` uses `"type": ["rectangle", "unknown"]` -- they are not classified as defenses but as unknowns, with `"not_ignore": ["factory", "mex"]`. This gives AA turrets extremely permissive placement -- only factories and mexes block them.

4. **Radar towers are "small"** with `"not_ignore": ["factory", "def_low", "terra"]` -- they can go almost anywhere except in factory exit lanes and defense clusters.

5. **Buildings NOT in the instance map** (no explicit category) fall to `_default_`:
   ```json
   "_default_": {
       "type": ["rectangle", "unknown"],
       "yard": [4, 4],
       "ignore": ["engy_high"]
   }
   ```
   They get a 64-elmo padding, can overlap fusion zones, but respect everything else. This includes jammers, shields, anti-nukes, and any building the config author did not explicitly map.

---

## 8. Build Chain System

The BuildChain JSON files (`ArmadaBuildChain.json`, `CortexBuildChain.json`, `LegionBuildChain.json`) define **what gets built after a building finishes construction**. They are the reactive adjacency system -- the closest thing the current AI has to "block planning."

Each faction has its own BuildChain file, loaded per-faction in `init.as`.

### 8.1 Porcupine System (Defense Chains)

The `porcupine` section defines automated defense clustering.

**Armada porcupine unit roster:**
```json
"unit": {
    "armada": [
        "armllt",     // 0  - Light Laser Tower
        "armtl",      // 1  - Torpedo Launcher
        "armrl",      // 2  - Rocket Launcher (AA)
        "armbeamer",  // 3  - Beamer
        "armhlt",     // 4  - Heavy Laser Tower
        "armjuno",    // 5  - Juno (radar disruption)
        "armclaw",    // 6  - Dragon's Claw (popup)
        "armcir",     // 7  - Chainsaw AA
        "armferret",  // 8  - Ferret AA
        "armpb",      // 9  - Pit Bull (popup arty)
        "armatl",     // 10 - Advanced Torpedo
        "armflak",    // 11 - Flak AA
        "armamb",     // 12 - Ambusher
        "armanni",    // 13 - Annihilator
        "armguard",   // 14 - Guardian (LR cannon)
        "armamd",     // 15 - Anti-Nuke
        "armtarg",    // 16 - Targeting Facility
        "armgate",    // 17 - Shield Generator
        "armmercury", // 18 - Mercury (long-range AA)
        "armnanotc",  // 19 - Nano Caretaker
        "armbrtha",   // 20 - Big Bertha (LRPC)
        "armvulc",    // 21 - Vulcan (super LRPC)
        "armemp"      // 22 - EMP Launcher
    ]
}
```

**Income-bounded build sequence:**
```json
"land":  [0, 2, 3, 3, 4, 3, 7, 5, 12, 12, 15, 13, 18, 17, 18, 20, 22, 20, 19, 19, 20, 20, 18, 17, 17, 22, 12, 12, 21, 12, 12, 12],
"water": [1, 1, 19, 1, 4, 9, 10, 9, 10]
```

These arrays specify which unit index to build as the defense count increases. So the first land defense built is index 0 (armllt), the second is index 2 (armrl), the third and fourth are both index 3 (armbeamer), and so on.

The actual number of defenses per cluster is bounded by income:
```json
"amount": {
    "offset": [-2.0, 2.0],
    "factor": [48.0, 32.0],   // 10x10 map ~ 48.0, 20x20 map ~ 32.0
    "map": [10, 20]
}
```

The formula: `defense_count = income / factor + random(offset)`, where `factor` interpolates between 48.0 (small maps) and 32.0 (large maps).

**Defense clustering range:**
```json
"point_range": 600.0
```
Defenses in a porcupine cluster must be within **600 elmos** of each other.

**Time-based base defense:**
```json
"base": [
    [3, 420],    // Build unit[3] (beamer) at 420s  (7 min)
    [10, 1200],  // Build unit[10] (adv torp) at 1200s (20 min)
    [15, 1220],  // Build unit[15] (anti-nuke) at 1220s
    [14, 1300],  // Build unit[14] (guardian) at 1300s
    [15, 1320],  // Build unit[15] (anti-nuke again)
    [12, 1800]   // Build unit[12] (ambusher) at 1800s (30 min)
]
```
These are scheduled base defenses triggered by game time, not income.

**Superweapons:**
```json
"superweapon": {
    "unit": { "armada": ["armamd", "armsilo"] },
    "weight": [0.10, 0.60],
    "condition": [200, 500]   // min 200 metal income, max 500 seconds to build
}
```

### 8.2 Hub Build Chain (Adjacency System)

The `build_chain` section is the core of the adjacency system. When a building finishes construction, it triggers a chain of follow-up builds.

**Structure:**
```json
"build_chain": {
    "<trigger_category>": {
        "<trigger_unit>": {
            "porc": true,          // trigger porcupine defense
            "hub": [
                [  // chain1
                    {"unit": "<def>", "category": "<cat>", "offset": <offset>, "condition": <cond>, "priority": "<pri>"},
                    ...
                ],
                [  // chain2 (alternative)
                    ...
                ]
            ]
        }
    }
}
```

**Trigger categories:** `energy`, `geo`, `defence`, `factory`, `mex`, `store`

### 8.3 Hub Entry Fields

Each hub entry defines one building to chain:

| Field | Type | Description |
|-------|------|-------------|
| `unit` | string | UnitDef name to build |
| `category` | string | Build category: `nano`, `defence`, `convert`, `energy`, `store` |
| `offset` | varies | Placement offset from trigger building (see below) |
| `condition` | object | Optional conditions for this chain entry |
| `priority` | string | Build priority: `low`, `normal`, `high`, `now` |

### 8.4 Offset Types

Offsets come in two formats:

**1. Absolute offset `[x, z]` -- in elmos, South-facing**
```json
{"unit": "armmakr", "category": "convert", "offset": [80, 80]}
```
Places the metal maker 80 elmos right and 80 elmos behind the trigger building (in South-facing orientation).

**2. Directional offset `{"direction": delta}`**
```json
{"unit": "armnanotc", "category": "nano", "offset": {"left": 5}}
{"unit": "armnanotc", "category": "nano", "offset": {"front": 10}}
{"unit": "armnanotc", "category": "nano", "offset": {"back": 5}}
```
The direction names (`left`, `right`, `front`, `back`) are relative to the building's facing. The delta appears to be in **block_map units** (x16 elmos) for directional offsets, but some entries like `"front": 80` and `"front": 120` suggest elmos. The units are inconsistent -- small values (5, 10, 15) likely represent block_map units while large values (80, 120, 150) are in elmos.

Looking at the actual values more carefully:
- Nano offsets: `{"left": 5}`, `{"front": 5}`, `{"back": 5}` -- small values, likely block_map units = 80 elmos
- Defense/energy offsets: `{"front": 80}`, `{"front": 120}`, `{"front": 150}`, `{"back": 160}` -- large values, likely elmos
- Absolute offsets: `[80, 80]`, `[120, 120]`, `[150, 150]` -- explicitly in elmos

### 8.5 Conditions

Optional conditions gate whether a chain entry is executed:

| Condition | Type | Description |
|-----------|------|-------------|
| `air` | bool | Only build if enemy has air units (`true`) |
| `energy` | bool | Only build if energy surplus exists (`true`) |
| `wind` | float | Only build if wind speed exceeds threshold |
| `m_inc>` | float | Only build if metal income exceeds value |
| `m_inc<` | float | Only build if metal income is below value |
| `sensor` | float | Only build if sensor coverage exceeds threshold |
| `chance` | float | Random probability (0.0 to 1.0) |

**Examples from the config:**
```json
// Only build flak AA if enemy has air units
{"unit": "armflak", "category": "defence", "offset": {"front": 120}, "condition": {"air": true}}

// 80% chance to build a jammer behind annihilator
{"unit": "armjamt", "category": "defence", "offset": {"back": 80}, "condition": {"chance": 0.8}}

// Only build metal maker if energy surplus
{"unit": "armmakr", "category": "convert", "offset": [80, 80], "condition": {"energy": true}}
```

### 8.6 Concrete Build Chain Examples

**T2 Bot Lab (Armada) -- triggers nano + fusion chain:**
```json
"armalab": {
    "hub": [[
        {"unit": "armnanotc", "category": "nano", "offset": {"left": 5}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"left": 5}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"back": 5}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"back": 5}, "priority": "normal"},
        {"unit": "armfus", "category": "energy", "offset": {"back": 40}, "priority": "normal"}
    ]]
}
```
When a T2 bot lab finishes: build 2 nanos to the left, 2 nanos behind, and a fusion reactor behind.

**Advanced Fusion (Armada) -- triggers nano + converter + defense chain:**
```json
"armafus": {
    "hub": [[
        {"unit": "armnanotc", "category": "nano", "offset": {"front": 5}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"front": 10}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"front": 15}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"front": 20}, "priority": "normal"},
        {"unit": "armnanotc", "category": "nano", "offset": {"front": 25}, "priority": "normal"},
        {"unit": "armmmkr",  "category": "convert", "offset": [120, 120]},
        {"unit": "armmmkr",  "category": "convert", "offset": [120, -120]},
        {"unit": "armmmkr",  "category": "convert", "offset": [150, 120]},
        {"unit": "armmmkr",  "category": "convert", "offset": [120, 150]},
        {"unit": "armmmkr",  "category": "convert", "offset": [150, 150]},
        {"unit": "armflak",     "category": "defence", "offset": {"front": 150}, "priority": "normal"},
        {"unit": "armmercury",  "category": "defence", "offset": {"front": 150}, "priority": "normal"}
    ]]
}
```
Advanced fusion triggers: 5 nanos in a line ahead, 5 metal makers in an L-shape to the side, plus flak and mercury AA.

**Gantry/Strider Hub (Armada) -- maximum nano saturation:**
```json
"armshltx": {
    "hub": [[
        {"unit": "armnanotc", "offset": {"left": 5},  ...},   // x4 left
        {"unit": "armnanotc", "offset": {"back": 5},  ...},   // x4 back
        {"unit": "armnanotc", "offset": {"right": 5}, ...}    // x4 right
    ]]
}
```
12 nanos total surrounding the gantry on 3 sides (left, back, right). The front is left clear for strider exit.

**Mex completion -- triggers porcupine:**
```json
"mex": {
    "armmex":   { "porc": true },
    "armmoho":  { "porc": true },
    "armuwmme": { "porc": true }
}
```
Every mex completion triggers the porcupine defense system to consider placing a defense near it.

### 8.7 Faction Differences

Comparing the three faction BuildChain files reveals structural similarity with unit-name differences:

**Armada vs Cortex:** Nearly identical structure. Cortex has some differences:
- Cortex `corlab` (T1 bot lab) triggers a defense (LLT) behind it, while Armada `armlab` does not have a factory chain entry for T1 bot lab.
- Cortex T2 factories chain into `coruwadves` (underwater advanced energy storage) -- Armada does not.
- Cortex `corap` (T1 air) triggers a defense + nano, while Armada `armap` triggers only nanos.

**Legion -- Significant Differences:**
- Legion does NOT have the `land`/`water` porcupine arrays (missing from config). It relies only on the `unit` roster and `superweapon` section.
- Legion fusion (`legfus`) triggers only an AA defense chain, not nanos. Armada/Cortex fusions trigger 5 nanos + flak.
- Legion advanced fusion (`legafus`) triggers flak + long-range AA, but NO metal makers and NO nanos.
- Legion has no `store` section in build_chain at all.
- Legion has a typo: `"priority": "nonormalw"` in `legalab` chain entry (should be `"normal"`).

---

## 9. How Block Map Interacts with C++ Placement

The placement flow from request to building start:

```
1. AngelScript Manager (builder.as)
   --> Decides WHAT to build (unit type, rough location)
   --> Calls aiBuilderMgr.DefaultMakeTask(unit)

2. C++ CBuilderManager
   --> Receives the build task
   --> Reads block_map.json (loaded at init via profile config)
   --> Determines the building's category from instance mapping
   --> Looks up blocker shape, size, yard, offset, ignore rules

3. C++ Placement Search
   --> Starts from a seed point (near the builder or suggested position)
   --> Searches outward (spiral or grid pattern) for a valid position
   --> For each candidate position:
       a. Check terrain buildability
       b. Check block_map exclusion zones of ALL existing buildings
       c. For each existing building within range:
          - Get its structure type
          - Check current building's ignore/not_ignore against it
          - If blocked --> reject this position
       d. If no conflicts --> valid position found

4. C++ Build Execution
   --> Assigns builder to the valid position
   --> Builder moves to location and starts construction

5. C++ Build Completion Event
   --> Triggers BuildChain (if configured for this unit)
   --> Chain entries become new build tasks, feeding back to step 2
```

**Key insight:** The C++ engine processes `block_map.json` and `BuildChain.json` natively. The AngelScript layer does not directly manipulate block_map data. The script decides *what* to build; the C++ engine decides *where* it goes, constrained by block_map rules.

---

## 10. Current Limitations -- Why Buildings Still Scatter

Despite the block_map exclusion system and the build_chain adjacency system, Barb3 bases still look disorganized. Here is why:

### 10.1 Block Map is Negative-Only

Block_map defines what **cannot** be placed near what. It has no concept of what **should** be placed near what. The result: buildings respect spacing rules but have no preference for forming organized clusters.

```
CURRENT: "Don't put a solar here because there's a factory nearby"
MISSING: "Put the solar here because it's part of the energy block behind the factory"
```

### 10.2 No Group Planning

Each building is placed independently. When the AI decides to build 5 wind turbines, it finds a valid position for #1, then later finds a valid position for #2 (which may be far from #1), and so on. There is no concept of:
- "Reserve a 4x4 area for a wind farm"
- "Place all 5 winds in a row"
- "Start filling this block template"

### 10.3 Build Chain is Reactive, Not Proactive

Build chains only trigger **after** a building completes. The AI does not plan ahead:
- It does not reserve space for chain buildings when placing the trigger building
- Chain buildings search for positions from the trigger building's location outward
- If the space around the trigger building is already occupied, chain buildings scatter elsewhere
- No mechanism to ensure the entire chain fits before starting the trigger building

### 10.4 No Block Templates

The system has no concept of predefined building arrangements. A "fusion block" (fusion + 5 nanos + 5 converters + AA) should be a single template placed as a unit. Instead, each component is placed individually through chain reactions.

### 10.5 Seed Point Drift

The search algorithm spreads outward from a seed point. Over time, as exclusion zones fill in, new buildings are pushed further and further from the base center. There is no mechanism to:
- Return to partially-filled areas
- Maintain compact blocks
- Fill gaps before expanding outward

### 10.6 No Facing Awareness for Chains

Build chain offsets are in South-facing orientation, but the actual building may face any direction. The C++ engine rotates offsets based on facing, but this means chain building positions depend on the trigger building's facing -- which is not always optimal for base layout.

---

## 11. What Needs to Change for True Block Placement

Based on this analysis, here is what the Build Module Quest needs to deliver:

### 11.1 Positive Placement Guidance

Block_map exclusion zones remain valid (they prevent overlaps and maintain factory exit lanes). But the system needs an additional layer that provides **positive** guidance:

```
NEW: "There is a designated energy block at position (X, Z).
      Place the next fusion at (X+offset, Z+offset) within that block."
```

### 11.2 Block Templates

Predefined arrangements of N buildings that form a logical module:

```
WIND_BLOCK (4x4 grid):
  [W][W][_][W][W]
  [W][W][_][W][W]
  [_][_][_][_][_]
  [W][W][_][W][W]

FUSION_BLOCK (8x6 grid):
  [N][N][N][F][N][N][N]
  [_][_][_][_][_][_][_]
  [M][M][M][_][M][M][M]
```

Templates define:
- Building positions relative to block origin
- Block dimensions
- Fill order (which building goes first)
- Expansion rules (how to connect to adjacent blocks)

### 11.3 Seed-Then-Fill Algorithm

```
1. AI decides it needs a fusion complex
2. Find a valid block location (large enough clear area)
3. Place the seed building (fusion) at the block center
4. Fill remaining slots in the template over time
5. Block_map constraints still enforce spacing within the template
6. Build_chain triggers can accelerate template filling
```

### 11.4 Block Reservation

When a block location is chosen, the area should be "reserved" so other independent placement queries do not encroach on it. This prevents the drift problem where chain buildings scatter because the space was taken by unrelated buildings.

### 11.5 Build Chain Integration

Build chains should trigger block template expansion instead of individual building placement:

```
CURRENT:  Fusion complete --> place nano at offset(front: 5)
PROPOSED: Fusion complete --> fill next slot in FUSION_BLOCK template
```

The build_chain config can remain mostly unchanged -- the hub offsets already describe a rough layout. The block template just formalizes and guarantees these layouts.

---

## Appendix A: Full Annotated block_map.json

```jsonc
// Source: Prod/Skirmish/Barb3/stable/config/experimental_balanced/block_map.json
// Mono-space font required
{
//================================================================================================================================
//=========================================B L O C K M A P  C O N F I G==========================================================
//================================================================================================================================

"building": {
    "class_land": {

        //------------------------------------------------------------
        // FACTORIES
        //------------------------------------------------------------

        "fac_land_t1": {
            // T1 Bot Labs, Vehicle Plants, Hovercraft Plants
            // Blocker: rectangle, structure type: factory
            "type": ["rectangle", "factory"],

            // 1 unit = SQUARE_SIZE * 2 = 16 elmos
            // Offset shifts yardmap center in South facing [left/right, front/back]
            "offset": [0, 5],       // Shifts 80 elmos toward back -- extends exit lane forward

            "size": [8, 8],         // 128 x 128 elmos -- building footprint
            "yard": [0, 30]         // 0 side padding, 480 elmo front/back exit lane
                                    // Total block: 128 x 608 elmos
            // DEFAULT: ignore nothing -- strictest blocking
        },

        "fac_land_t2": {
            // T2 Advanced Bot Labs, Advanced Vehicle Plants
            "type": ["rectangle", "factory"],
            // size defaults to unit footprint
            "yard": [12, 20],       // 192 elmo side, 320 elmo front/back padding
            "offset": [4, 6],       // 64 elmos right, 96 elmos back
            "ignore": ["none"]      // Explicit strictest blocking
        },

        "fac_air": {
            // T1 and T2 Aircraft Plants
            "type": ["rectangle", "factory"],
            // No yard -- aircraft don't need ground exit lanes
            // Selective blocking: only converters, factories, superweapons block air plants
            "not_ignore": ["convert", "factory", "special"]
        },

        "fac_water": {
            // T1 and T2 Shipyards
            "type": ["rectangle", "factory"],
            "yard": [10, 12],       // 160 elmo side, 192 elmo front/back
            "offset": [0, 4]        // 64 elmos back
        },

        "fac_strider": {
            // T3 Gantries (9x9 footprint)
            "type": ["rectangle", "factory"],
            "offset": [0, 4],       // 64 elmos back
            "yard": [6, 8],         // 96 side, 128 front/back
            "ignore": ["none"]      // Strictest blocking
        },

        //------------------------------------------------------------
        // ENERGY
        //------------------------------------------------------------

        "solar": {
            // T1 Solar Generators
            "type": ["rectangle", "engy_mid"],
            "ignore": ["engy_mid", "def_low", "mex", "def_low"],  // Note: def_low listed twice (bug)
            "yard": [6, 6]          // 96 elmo padding all sides
            // Can overlap: other solars, defenses, mexes
        },

        "advsolar": {
            // T2 Advanced Solar Generators
            "type": ["rectangle", "engy_mid"],
            "yard": [5, 5],         // 80 elmo padding
            "ignore": ["mex", "engy_mid", "def_low", "nano"]
            // Can overlap: mexes, other mid-energy, defenses, nanos
        },

        "wind": {
            // Wind Turbines and Tidal Generators
            "type": ["rectangle", "engy_low"],
            // No size, yard, or radius specified -- uses unit footprint only
            // Can overlap each other for dense wind farms
            "ignore": ["engy_low"]
        },

        "geo": {
            // T1 Geothermal Plants
            "type": ["rectangle", "geo"],
            "yard": [4, 4],         // 64 elmo padding
            "ignore": ["none"]      // Strict -- geo spots are valuable
        },

        "geo2": {
            // T2 Advanced Geothermal Plants
            "type": ["rectangle", "geo"],
            "yard": [6, 6],         // 96 elmo padding (larger than T1)
            "ignore": ["none"]
        },

        "fusion": {
            // T2 Fusion Reactors (all variants: land, underwater, advanced)
            "type": ["rectangle", "engy_high"],
            "yard": [5, 5],         // 80 elmo padding
            "ignore": ["mex", "engy_high"]
            // Can overlap: mexes (can build near mex spots), other fusions
        },

        // COMMENTED OUT: Singularity reactor (expl_ally radius)
        // Was going to scale exclusion zone with ally count

        //------------------------------------------------------------
        // ECONOMY
        //------------------------------------------------------------

        "store": {
            // Metal and Energy Storage buildings
            "type": ["rectangle", "mex"],    // NOTE: typed as "mex" for ignore purposes
            "yard": [4, 4],                  // 64 elmo padding
            "not_ignore": ["factory", "terra"]
            // Only factories and terraform block storage placement
        },

        "mex": {
            // T1 Metal Extractors (map-spot dependent)
            "type": ["rectangle", "mex"],
            "offset": [0, -4],              // Shifted 64 elmos FORWARD (toward front)
            "ignore": ["all"]               // Can go ANYWHERE -- mex spots are fixed
        },

        "mex2": {
            // T2 Metal Extractors (Moho Mines, underwater)
            "type": ["rectangle", "mex"],
            "ignore": ["all"]               // Same as T1: place-anywhere
        },

        "converter": {
            // Metal Makers / Energy Converters (all tiers, land/water)
            "type": ["rectangle", "convert"],
            "yard": [7, 7],                 // 112 elmo padding -- keeps them somewhat spread
            "ignore": ["convert"]           // Can overlap each other
        },

        //------------------------------------------------------------
        // DEFENSES
        //------------------------------------------------------------

        "def_low": {
            // Light Laser Towers, Beamers
            "type": ["circle", "def_low"],
            "radius": 6,                    // 96 elmo circle
            "ignore": ["engy_mid", "engy_high", "engy_low", "nano"]
            // Defenses ignore all energy and nano buildings
        },

        "def_mid": {
            // Heavy Laser Towers, Popup Defenses
            "type": ["circle", "def_low"],  // NOTE: structure type is "def_low", not "def_mid"
            "radius": 7                     // 112 elmo circle -- wider than def_low
            // DEFAULT: ignore nothing
        },

        "def_hvy": {
            // Annihilators, Doomsdays, Heavy Artillery
            "type": ["circle", "def_low"],  // NOTE: still "def_low" structure type
            "radius": 8                     // 128 elmo circle -- widest defense spacing
            // DEFAULT: ignore nothing
        },

        "def_air": {
            // Anti-Air Turrets (all types)
            "type": ["rectangle", "unknown"],  // NOTE: typed as "unknown", not "def_low"
            "yard": [2, 2],                    // 32 elmo padding (very tight)
            "not_ignore": ["factory", "mex"]
            // Only factories and mexes block AA -- very permissive placement
        },

        //------------------------------------------------------------
        // SUPPORT
        //------------------------------------------------------------

        "caretaker": {
            // Nano Caretakers (land and naval platforms)
            "type": ["rectangle", "nano"],
            "ignore": ["mex", "engy_mid", "engy_high"]
            // Can overlap mex spots and energy buildings
            // No yard -- placed as close as possible to factories
        },

        //------------------------------------------------------------
        // SPECIAL
        //------------------------------------------------------------

        "superweapon": {
            // Nukes, Super LRPCs (Vulcan, Buzzsaw, Starfall)
            "type": ["circle", "special"],
            "ignore": ["mex", "def_low", "engy_high"],
            "yard": [8, 8]                 // 128 elmo padding on circle
        },

        "protector": {
            // Shield Generators, Anti-Nukes
            "type": ["circle", "special"],
            "ignore": ["mex", "def_low", "engy_mid", "engy_high"]
            // Shields can go near defenses and energy
        },

        // COMMENTED OUT: terraform and strider categories

        //------------------------------------------------------------
        // MISC
        //------------------------------------------------------------

        "small": {
            // Radar Towers
            "type": ["rectangle", "unknown"],
            "not_ignore": ["factory", "def_low", "terra"]
            // Very permissive -- only factories, defenses, terraform block
        },

        "_default_": {
            // Catch-all for unmapped buildings
            "type": ["rectangle", "unknown"],
            "yard": [4, 4],                // 64 elmo padding
            "ignore": ["engy_high"]        // Can overlap fusion zones
        }
    },

    //------------------------------------------------------------
    // INSTANCE MAPPING: Unit Names --> Block Categories
    //------------------------------------------------------------

    "instance": {
        "fac_land_t2": ["armalab", "armavp", "coralab", "coravp", "legalab", "legavp"],
        "fac_land_t1": ["armlab", "armvp", "armhp", "corlab", "corvp", "corhp", "leglab", "legvp", "leghp"],
        "fac_water":   ["armsy", "armasy", "corsy", "corasy", "legsy", "legadvshipyard"],
        "fac_air":     ["armap", "armaap", "corap", "coraap", "legap", "legaap"],
        "fac_strider": ["armshltx", "armshltxuw", "corgant", "corgantuw", "leggant", "leggantuw"],
        "solar":       ["armsolar", "corsolar", "legsolar"],
        "advsolar":    ["armadvsol", "coradvsol", "legadvsol"],
        "wind":        ["armwin", "corwin", "armtide", "cortide", "legwin", "legtide"],
        "geo":         ["armgeo", "corgeo", "leggeo"],
        "geo2":        ["armageo", "corageo", "legageo"],
        "fusion":      ["armfus", "armuwfus", "armckfus", "armafus", "corfus", "coruwfus", "corafus",
                        "legfus", "legafus", "leganavalfusion"],
        "store":       ["armmstor", "armestor", "cormstor", "corestor", "legmstor", "legestor"],
        "mex":         ["armmex", "cormex", "legmex"],
        "mex2":        ["armmoho", "cormoho", "armuwmme", "coruwmme", "legmoho"],
        "converter":   ["armmakr", "cormakr", "armmmkr", "cormmkr", "armfmkr", "corfmkr",
                        "armuwmmm", "coruwmmm", "legeconv", "legadveconv", "leganavaleconv"],
        "def_low":     ["armllt", "corllt", "armbeamer", "corhllt", "leglht", "legmg"],
        "def_mid":     ["armclaw", "cormaw", "armpb", "corvipe", "armhlt", "corhlt",
                        "legdtr", "legapopupdef", "leghive"],
        "def_hvy":     ["armamb", "armanni", "cortoast", "cordoom", "armguard", "corpun",
                        "armkraken", "corfdoom", "legacluster", "legbastion", "legcluster", "legfmg"],
        "def_air":     ["armferret", "armcir", "corrl", "cormadsam", "corerad",
                        "legrhapsis", "leglupara"],
        "caretaker":   ["armnanotc", "cornanotc", "legnanotc",
                        "armnanotcplat", "cornanotcplat", "legnanotcplat"],
        "small":       ["armrad", "corrad", "legrad"]
    }
}
}
```

---

## Summary: Key Takeaways for the BARB Quest

1. **block_map.json is the spatial constraint layer** -- it prevents overlapping and enforces spacing, but provides zero positive placement guidance. It is necessary but not sufficient for organized bases.

2. **BuildChain is the adjacency layer** -- it chains follow-up buildings after a trigger completes, providing rough relative positioning. But it is reactive (post-build), not proactive (pre-planned).

3. **The unit of measurement is 16 elmos** (SQUARE_SIZE * 2). All block_map size/yard/radius values must be multiplied by 16 to get game elmos.

4. **Structure types control interactions**, not building categories. Multiple categories can share a structure type (e.g., def_low, def_mid, def_hvy all use type `"def_low"`).

5. **Factories have the largest exclusion zones** (608 elmos for T1 land) due to exit lane requirements. Mexes have zero exclusion (ignore all). These represent the two extremes.

6. **Legion has significant BuildChain gaps** -- missing porcupine arrays, missing store chains, missing nano chains on fusion/advanced fusion. This could explain why Legion AI bases look particularly disorganized.

7. **The gap between block_map (negative constraints) and build_chain (reactive adjacency) is where the Build Module Quest lives.** We need to add a positive, proactive layer that:
   - Defines block templates (predefined building group layouts)
   - Reserves space before building starts
   - Fills templates incrementally as economy allows
   - Integrates with existing block_map constraints and build_chain triggers

8. **Block_map constraints are correct and should be preserved.** The exclusion zones make physical sense (factory exit lanes, explosion spacing, defense distribution). The Build Module should work *within* these constraints, not replace them.

---

*End of Research Report 06.*
