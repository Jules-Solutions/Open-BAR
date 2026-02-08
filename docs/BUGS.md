# TotallyLegal: Bug Catalog

Tracked bugs from the codebase audit, mapped to the phase that fixes them.

## Perception Bugs (Phase 2) -- ALL FIXED

| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 1 | Duplicate BuildKeyTable in goals vs core | engine_goals.lua | Removed from goals, all calls use TL.ResolveKey() | FIXED |
| 2 | Duplicate role classification in goals | engine_goals.lua | Replaced with prod.roleMappings lookups | FIXED |
| 3 | Faction detection silently fails if no commander found | lib_core.lua | Added fallback name-prefix scan + retry every 1s for 5s | FIXED |
| 4 | Mex placement ignores build area constraint | lib_core.lua | FindNearestMexSpot now accepts and respects buildArea | FIXED |
| 5 | Circular dependency econ<->goals (load order) | Multiple | All cross-widget reads nil-safe, pcall in all GameFrames, _ready flags | FIXED |
| 6 | Config shutdown nils Strategy while others still read it | engine_config.lua | Shutdown sets Strategy._ready = false instead of niling | FIXED |

## Execution Bugs (Phase 3) -- ALL FIXED

### 3a: Config & Strategy
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 7 | Slider allocations can exceed 100% | engine_config.lua:54-91 | DEFERRED: only one slider exists, correctly clamped 0-100. Redesign is a future feature. | DEFERRED |
| 8 | No strategy validation | engine_config.lua | ValidateStrategy() warns on contradictory combos (bots+anti_aa_raid, eco+aggressive, etc.) | FIXED |

### 3b: Economy Manager
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 9 | Constructor collision (multiple cons build same position) | engine_econ.lua:181-270 | Mex claim system in core: ClaimMexSpot/ReleaseMexClaim prevents double-targeting | FIXED |
| 10 | Stale goal reserves never clear | engine_econ.lua:103-117 | Reserve suppression only applies when goals.activeGoal exists | FIXED |

### 3c: Production Manager
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 11 | Goal production count goes negative | engine_prod.lua:292-300 | mathMax(0, goalOverride.count - 1) prevents underflow | FIXED |
| 12 | Aircraft roles not differentiated | engine_prod.lua:106-109 | Added fighter/bomber/gunship/air_constructor classification | FIXED |

### 3d: Zone Manager
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 13 | Dead units remain in rally/front groups | engine_zone.lua:188-194 | CleanDeadUnits() runs first in GameFrame, atomic cleanup across all groups | FIXED |
| 14 | Secondary line only reads at GameStart | engine_zone.lua:150-157 | Secondary line polled every GameFrame cycle; front updates on change | FIXED |

### 3e: Build Order Executor
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 15 | Phase tracking race condition (instant rejection) | engine_build.lua:218-233 | Increased elapsed threshold from 10 to 30 frames (1s) | FIXED |
| 16 | buildOrderFile config field unused | engine_build.lua:70 / engine_config.lua:70 | LoadBuildOrderFromFile() reads JSON via VFS.LoadFile, parses array-of-objects | FIXED |

### 3f: Goals System
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 17 | Stall detection false positive | engine_goals.lua:845-860 | Reset _lastCheckedProgress = nil when activating new goal in AdvanceQueue | FIXED |
| 18 | Goal overrides linger after completion | engine_goals.lua:646-654 | ClearOverrides() called at top of AdvanceQueue(), before activeGoal = nil | FIXED |
| 19 | Goals<->econ/prod/zone wiring is fragile | Multiple files | Nil-guard warnings in GenerateOverrides; UnitDefs validation in econ+prod consumers | FIXED |

### 3g: Strategy Execution
| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| 20 | Piercing assault has abort but others don't | engine_strategy.lua:184-256 | Added loss threshold abort (60% casualties) to creeping; bait-death abort to fake_retreat | FIXED |
| 21 | Retreat goes to rally point but units have no "retreating" state | engine_strategy.lua:247-249 | "retreating" assignment state; zone manager skips retreating units, flips to "rally" when idle | FIXED |

## Micro Bugs (Phase 4)

| # | Bug | File | Fix |
|---|-----|------|-----|
| 22 | Dodge radius too small for large units | auto_dodge.lua:53 | Scale CFG.dodgeRadius by unit size (def.xsize * 8) |
| 23 | Dodge has no minimum projectile travel time check | auto_dodge.lua:170-227 | Skip projectiles that will arrive in < 3 frames (undodgeable) |
| 24 | Skirmish overrides player movement commands | auto_skirmish.lua:177-232 | Only process units that are idle or attack-moving, not player-commanded |
| 25 | Rezbot spam-reassigns every frame | auto_rezbot.lua:161-246 | Add per-bot cooldown (CFG.updateFrequency * 3), clean stale feature assignments |
