# Barb3 Map Configurations

> Complete inventory of all maps with Barb3-specific configurations.
>
> **Source:** `script/src/maps.as` + `script/src/maps/*.as`

---

## Summary

- **Total configured maps:** 18
- **Total start spots:** ~233
- **Maps with unit bans:** 7
- **Maps with role-specific limits:** 4
- **Maps with strategic objectives:** 1 (Supreme Isthmus)
- **Unconfigured maps:** All other BAR maps fall through to C++ defaults (no role assignment, no unit bans)

---

## Map List

| # | Map Name | File | Start Spots | Roles | Unit Bans | Notes |
|---|----------|------|-------------|-------|-----------|-------|
| 1 | Supreme Isthmus | `supreme_isthmus.as` | 16 | HOVER_SEA, TECH, AIR, FRONT, FRONT_TECH, SEA | armpincer, corgarp | Only map with strategic objectives (5) |
| 2 | All That Glitters | `all_that_glitters.as` | 16 | FRONT, AIR, TECH | None | Standard land map |
| 3 | Eight Horses | `eight_horses.as` | 16 | FRONT, AIR, SEA, FRONT_TECH | coramph | Mixed land/sea |
| 4 | Flats and Forests | `flats_and_forests.as` | 16 | FRONT, AIR, TECH | None | Standard land map |
| 5 | Glacial Gap | `glacial_gap.as` | 16 | TECH, FRONT, SEA, HOVER_SEA | armthor; HOVER_SEA: no vehicles | Mixed with water |
| 6 | Forge | `forge.as` | 16 | FRONT, FRONT_TECH, AIR, TECH | None | Standard land map |
| 7 | Red River Estuary | `red_river_estuary.as` | 16 | FRONT, AIR, FRONT_TECH, SEA | armthor | Mixed land/sea |
| 8 | Serene Caldera | `serene_caldera.as` | 16 | SEA, AIR | All vehicles + all land labs banned | Sea-dominant |
| 9 | Shore to Shore V3 | `shore_to_shore.as` | 12 | TECH, AIR, HOVER_SEA, SEA | All T1 vehicles + 30 land combat units | Heavy water map |
| 10 | Swirly Rock | `swirly_rock.as` | 16 | FRONT, AIR, TECH | None | Standard land map |
| 11 | Koom Valley | `koom_valley.as` | 14 | FRONT, TECH | None | Land-focused |
| 12 | Acidic Quarry | `acidic_quarry.as` | 4 | AIR only | All land defenses disabled | Air-exclusive |
| 13 | Tempest | `tempest.as` | 16 | FRONT, TECH, AIR, HOVER_SEA, SEA | HOVER_SEA: no vehicles | Full role spread |
| 14 | Tundra Continents | `tundra_continents.as` | 16 | HOVER_SEA, TECH, SEA, AIR | armthor; HOVER_SEA: no vehicles | Some landlocked spots |
| 15 | Raptor Crater | `raptor_crater.as` | 8 | FRONT, TECH, AIR | None | Smaller map |
| 16 | Sinkhole Network | `sinkhole_network.as` | 8 | FRONT, TECH, FRONT_TECH | None | Smaller map |
| 17 | Ancient Bastion Remake | `ancient_bastion_remake.as` | 9 | FRONT, AIR, TECH | None | Medium map |
| 18 | Mediterraneum V1 | `mediterraneum.as` | 28 | AIR, FRONT, SEA, TECH, HOVER_SEA | None | Largest map (28 spots) |

---

## What Each Map Config Defines

Each map config in `maps/*.as` can define:

1. **Start Spots** — `StartSpot` objects with:
   - Position (x, z coordinates)
   - Preferred role (FRONT, TECH, AIR, SEA, HOVER_SEA, FRONT_TECH)
   - `landLocked` flag (surrounded by water?)

2. **Unit Limits** — `getUnitLimits()` returns a dictionary of `unitName → maxCount`
   - Maps can ban specific units (set to 0)
   - Applied globally to all roles on that map

3. **Role-Specific Unit Limits** — `getRoleUnitLimits()` returns per-role dictionaries
   - Example: HOVER_SEA role can't build vehicles on certain maps

4. **Factory Weights** — `getFactoryWeights()` returns per-role factory preference weights
   - Higher weight = more likely to be selected as starting factory
   - Example: FRONT prefers vehicles (weight 5) over bots (weight 2)

5. **Strategic Objectives** — Only Supreme Isthmus uses this
   - Named locations with coordinates and tactical purpose

---

## Common Factory Weight Patterns

Most maps use the same weights:

| Role | Armada | Cortex | Legion |
|------|--------|--------|--------|
| FRONT | armlab(2), armvp(5) | corlab(2), corvp(5) | leglab(2), legvp(5) |
| AIR | armap(3) | corap(3) | legap(3) |
| SEA | armsy(4) | corsy(4) | legsy(4) |
| HOVER_SEA | armhp(4) | corhp(4) | leghp(4) |
| TECH | armlab(4) | corlab(4) | leglab(4) |
| FRONT_TECH | armlab(4) | corlab(4) | leglab(4) |

FRONT strongly prefers vehicle plants (5) over bot labs (2). TECH always uses bot labs (4).

---

## Maps Without Configs

Any BAR map not in this list has **no Barb3-specific configuration**. On those maps:
- Role falls through to C++ default (usually FRONT)
- No unit bans
- No factory weight preferences
- Default start spot selection

This means on ~80% of BAR maps, the AI plays with generic behavior.

---

*Created: 2026-02-17*
