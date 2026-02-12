# PRD: Unit Puppeteer

> **Status:** DRAFT v2
> **Created:** 2026-02-12
> **Widget Family:** `auto_puppeteer_*` (Execution: Micro)
> **Layers:** 103-108
> **Depends on:** `01_totallylegal_core.lua`

---

## 1. Problem Statement

In Beyond All Reason, individual unit micro separates good players from great ones. Currently, TotallyLegal offers auto-dodge (projectile avoidance) and auto-skirmish (range kiting) as separate widgets. But real unit micro is an integrated system: you don't just dodge OR kite — you path safely, hold formation, rotate firing positions, space against splash, and dodge when shot at — all simultaneously.

The player's existing tools for multi-unit control are also primitive: click-and-drag produces a line. No circles, no squares, no nested formations, no tactical shapes. Units walk through enemy fire because the game gives no pathing intelligence around weapon ranges.

**Unit Puppeteer** solves this as a family of coordinated micro widgets.

---

## 2. Vision

A family of widgets that make your units feel like they have a brain. Selected units:
- **Never walk into danger they don't need to** (range-aware pathing)
- **Hold smart formations** (not just lines — circles, squares, firing lines)
- **Auto-sort by role** (tanks front, arty back, scouts flanks)
- **Rotate through firing positions** (shoot, cycle, reload, re-engage)
- **March together** (speed-matched, no stragglers)
- **Spread against splash** (scatter toggle)
- **Dodge what they can** (integrated projectile avoidance)

The player issues high-level intent ("go there", "attack that") and Puppeteer handles the micro execution.

---

## 3. Multi-Widget Architecture

Unlike the original monolith approach, Puppeteer is split into **multiple cooperating widgets**. Each handles one concern cleanly. They coordinate through a shared `WG.TotallyLegal.Puppeteer` state table.

```
auto_puppeteer_core.lua        (Layer 103) — Shared state, toggle system, unit management
auto_puppeteer_smartmove.lua   (Layer 104) — Range-aware pathing
auto_puppeteer_dodge.lua       (Layer 105) — Formation-aware projectile dodging
auto_puppeteer_formations.lua  (Layer 106) — Shape formations + role sorting
auto_puppeteer_firingline.lua  (Layer 107) — Shoot-cycle rotation
auto_puppeteer_march.lua       (Layer 108) — Speed-matched movement + scatter + range walk
```

**Why multiple files:**
- Each feature can be independently enabled/disabled by the player
- Follows existing TotallyLegal pattern (`auto_dodge`, `auto_skirmish`, `auto_rezbot` are separate)
- Smaller files = easier to debug, test, and iterate
- A broken feature doesn't take down the whole system

**Coordination:** All widgets read/write through `WG.TotallyLegal.Puppeteer`. The core widget (Layer 103) owns the state table and loads first. Other widgets nil-safe access it.

---

## 4. Feature Breakdown

### 4.1 Puppeteer Core (`auto_puppeteer_core.lua`)

**Responsibility:** Shared state owner, toggle management, unit registration.

**Provides:**
```lua
WG.TotallyLegal.Puppeteer = {
    active = true,
    toggles = {
        smartMove = true,       -- Range-aware pathing
        dodge = true,           -- Projectile avoidance
        formations = true,      -- Shape formations
        formationShape = "line", -- "line"|"circle"|"half_circle"|"square"|"star"
        formationNesting = 1,   -- 1-5 concentric layers
        roleSort = true,        -- Auto-sort units by role in formation
        firingLine = false,     -- Shoot-cycle rotation
        firingLineWidth = 1,    -- 1-5 units wide
        scatter = false,        -- Anti-splash spacing
        scatterDistance = 120,  -- elmos between units
        march = false,          -- Speed-matched movement
        rangeWalk = false,      -- Convergent range walking
    },
    -- Managed unit registry (written by core, read by all)
    units = {},                 -- unitID -> { defID, class, range, speed, radius, formationPos, state }
    -- Formation groups (written by formations widget)
    groups = {},                -- groupID -> { shape, center, radius, facing, unitIDs, positions }
    -- Firing line state (written by firing line widget)
    firingLines = {},           -- lineID -> { unitQueue, activeSlots, cycleState }
}
```

**Also handles:**
- Unit registration/deregistration (UnitCreated/UnitDestroyed callbacks)
- Toggle persistence via `Spring.SetConfigInt` / `Spring.GetConfigInt`
- Conflict resolution: when Puppeteer is active, signal old dodge/skirmish to yield

### 4.2 Smart Move (`auto_puppeteer_smartmove.lua`)

**The problem:** You issue a move command, your units walk straight through an enemy Stinger field and die.

**Behavior:**
- When a move command is issued, check if the path crosses any known enemy weapon range
- **Destination outside range:** Units path around the danger zone (arc around the weapon range circle) or walk through it at maximum speed if no safe path exists
- **Destination inside range:** Units stop at the edge of the weapon range, just outside engagement distance
- **Override:** If the player issues a FIGHT command (attack-move), pathing override is disabled — units enter range aggressively

**Data needed:**
- Enemy unit positions (`Spring.GetUnitsInRectangle` with `Spring.ENEMY_UNITS`)
- Enemy weapon ranges (`WeaponDefs` via enemy `UnitDefs`)
- Current move command destination (`Spring.GetUnitCommands`)

**Edge cases:**
- Multiple overlapping enemy ranges -> find gaps or choose shortest crossing
- Enemy units are mobile -> recalculate on movement (throttled, position hash)
- Units in a queue of orders -> only evaluate the current leg
- Destination unreachable without crossing range -> warn and path through at max speed

**Hooks:** `CommandNotify` to intercept `CMD_MOVE` on managed units.

### 4.3 Formation-Aware Dodge (`auto_puppeteer_dodge.lua`)

**Evolves** the existing `auto_totallylegal_dodge.lua` with formation awareness.

**What changes from current dodge:**
- Dodge direction prefers **toward formation position** rather than random perpendicular
- After dodge, unit **returns to formation position** (re-issues formation move after cooldown)
- Dodge is **suppressed** when unit is in firing line active slot (don't dodge while shooting)

**What stays the same:**
- Core trajectory prediction algorithm (`PredictImpact`)
- Hitscan weapon filtering
- Cooldown system
- Performance cap

**Relationship to old widget:**
- When Puppeteer is active (`WG.TotallyLegal.Puppeteer.active`), old `auto_totallylegal_dodge` auto-disables
- When Puppeteer is inactive, old dodge works as before
- Player can choose: simple dodge OR Puppeteer dodge, not both

### 4.4 Formations (`auto_puppeteer_formations.lua`)

**The problem:** Click-and-drag only produces a line. No tactical formations.

**Shapes:**
| Shape | Description | Use Case |
|-------|-------------|----------|
| Line | Default BAR behavior | General movement |
| Circle | Units on circumference | Defensive perimeter |
| Half-circle | Arc facing threat direction | Offensive semicircle |
| Square | Units on perimeter of rectangle | Base defense, area hold |
| Star | Alternating inner/outer radius | Concentrated firepower |
| Nested | 2-5 concentric shapes | Layered defense |

**How it works:**
1. Player selects formation shape (toggle button or hotkey)
2. Player click-drags a move command on selected units
3. Widget intercepts via `CommandNotify`
4. Calculates formation positions based on:
   - **Drag start** = formation center
   - **Drag direction** = facing orientation
   - **Drag length** = formation radius/size
   - **Number of units** = distribution density
5. Issues individual `CMD_MOVE` to each unit's calculated position

**Shape math:**
```
Circle:      pos[i] = center + radius * (cos(2*pi*i/N), sin(2*pi*i/N))
Half-circle: pos[i] = center + radius * (cos(pi*i/(N-1) - pi/2), sin(pi*i/(N-1) - pi/2))
Square:      distribute N units evenly along perimeter of square
Star:        alternate between inner_radius and outer_radius (outer = radius, inner = radius*0.5)
Nested:      split units across layers proportional to perimeter length
```

**Unit assignment:** Greedy nearest — for each formation position, assign the closest unassigned unit. Minimizes total travel distance.

**Role-Based Sorting:**
When `roleSort` is enabled, units auto-sort by classification before assignment:
- **Front rank:** Assault units (tanks, bots with short range + high HP)
- **Middle rank:** Standard combat (medium range)
- **Back rank:** Artillery, long-range units
- **Flanks:** Fast units, scouts, raiders

Classification uses existing `TL.GetUnitClass()` data: `maxSpeed`, `weaponCount`, weapon range, HP.

**Sorting algorithm:**
```
1. Classify each unit: assault | standard | artillery | scout
   - assault:   range < 350 AND hp > 1000
   - artillery: range > 600
   - scout:     speed > 80 AND hp < 500
   - standard:  everything else
2. For formations with depth (nested, square):
   - Inner/front layers get assault + standard
   - Outer/back layers get artillery
   - Flanks get scouts
3. For line formations:
   - Center = assault, edges = artillery, tips = scouts
```

### 4.5 Firing Line (`auto_puppeteer_firingline.lua`)

**The problem:** Units of the same type all fire at once and all reload at once. Staggering fire is better.

**Behavior:**
- Toggle: **Firing Line** mode
- When enabled, same-type units form a line perpendicular to the nearest enemy
- Cycle:
  1. First unit(s) in queue move to **firing position** (front, in weapon range)
  2. Fire weapon(s)
  3. After firing (weapon reload begins), move **sideways and back** to reload position
  4. If a nano/constructor is nearby, reloading unit positions near it for healing
  5. Next unit(s) in queue take the firing position
  6. Repeat — continuous staggered fire

**Configuration:**
- Line width: 1-5 units simultaneously at the front
- Side preference: left or right cycling (or alternating)

**State machine per unit:**
```
waiting -> advancing -> firing -> cycling -> reloading -> waiting
```

**Requirements:**
- `Spring.GetUnitWeaponState(unitID, weaponNum)` for reload progress
- `WeaponDefs[wDefID].reload` for reload time
- Track nearby constructors for heal-seek behavior

### 4.6 March & Spacing (`auto_puppeteer_march.lua`)

**Three features in one widget** — all related to how units move as a group:

#### Speed-Matched March
- When `march` toggle is ON, all selected units move at the speed of the slowest unit in the group
- Implementation: issue `CMD_MOVE` to intermediate waypoints, timed so fast units don't outpace slow ones
- Alternative: use `CMD_SET_WANTED_MAX_SPEED` if available in Spring API
- Prevents fast raiders arriving 10 seconds before your main army

#### Scatter (Anti-Splash)
- When `scatter` toggle is ON, units maintain minimum spacing from each other
- Spacing = configurable distance (default 120 elmos)
- Applied on top of formations — formation shape is preserved but scaled up if needed
- Implementation: after formation positions calculated, apply repulsion solver (3-5 iterations, push overlapping units apart along connecting vector)

#### Convergent Range Walking
- When `rangeWalk` toggle is ON and units are moving toward a known engagement:
  - Sort units by weapon range
  - Short range units walk in front
  - Long range units walk behind
  - Offset = `own_range - shortest_range` behind the front line
  - All weapon ranges converge on the same engagement line
- Combined with `march`: units arrive together AND at correct depth

---

## 5. Toggle System

All features independently toggleable via sidebar buttons or hotkeys:

| Toggle | Default | Widget | Hotkey | Description |
|--------|---------|--------|--------|-------------|
| Smart Move | ON | smartmove | `Alt+M` | Range-aware pathing |
| Dodge | ON | dodge | `Alt+D` | Projectile avoidance |
| Formations | ON | formations | `Alt+F` (cycles shape) | Shape selector |
| Role Sort | ON | formations | `Alt+O` | Auto-sort by unit role |
| Firing Line | OFF | firingline | `Alt+L` | Shoot-cycle rotation |
| Scatter | OFF | march | `Alt+S` | Anti-splash spacing |
| March | OFF | march | `Alt+G` | Speed-matched movement |
| Range Walk | OFF | march | `Alt+W` | Convergent range movement |

Toggles stored in `WG.TotallyLegal.Puppeteer.toggles` and persisted via Spring config.

---

## 6. UI / Presentation

### Sidebar integration
Add Puppeteer section to sidebar (`gui_totallylegal_sidebar.lua`):
- Main icon: `UP` — expands to show sub-toggles
- Each sub-feature shown as a small toggle button
- Active toggles highlighted

### Formation shape selector
- Row of shape icons: `—` (line) `O` (circle) `C` (half-circle) `[]` (square) `*` (star)
- Click to select, highlighted = active
- Nesting depth: `+`/`-` buttons

### Visual feedback (overlay, PvP safe)
- Formation positions as faint ground markers when issuing commands
- Firing line queue visualization (who's next)
- Scatter spacing rings around units

---

## 7. Phasing

### Phase 1: Foundation + Smart Move
**Widgets:** `auto_puppeteer_core.lua`, `auto_puppeteer_smartmove.lua`

1. Core: shared state table, toggle system, unit registry, persistence
2. Smart Move: intercept `CMD_MOVE`, check enemy ranges, stop/reroute
3. Conflict resolution with old dodge/skirmish widgets
4. Sidebar icon

**Acceptance:**
- [ ] Units with Smart Move ON stop before walking into Stinger/LLT range
- [ ] Units path around enemy range if destination is beyond it
- [ ] FIGHT command overrides Smart Move (aggressive push)
- [ ] Toggles persist across game restart
- [ ] Sidebar shows Puppeteer section

### Phase 2: Dodge Integration
**Widget:** `auto_puppeteer_dodge.lua`

4. Absorb dodge algorithm from `auto_totallylegal_dodge.lua`
5. Add formation-aware dodge direction
6. Post-dodge return-to-position

**Acceptance:**
- [ ] Dodge works identically to old widget when no formation active
- [ ] With formation, dodge direction prefers toward formation position
- [ ] Old dodge widget auto-disables when Puppeteer active

### Phase 3: Formation Shapes + Role Sort
**Widget:** `auto_puppeteer_formations.lua`

7. `CommandNotify` hook for drag-command interception
8. Shape math for all 5 shapes + nested
9. Role classification and depth sorting
10. Formation position overlay

**Acceptance:**
- [ ] Click-drag with Circle selected distributes units in a circle
- [ ] Nesting 2+ creates concentric shapes
- [ ] Role sort places tanks front, arty back when enabled
- [ ] Formation positions shown as ground markers during drag

### Phase 4: March & Spacing
**Widget:** `auto_puppeteer_march.lua`

11. Speed-matched marching
12. Scatter spacing solver
13. Convergent range walking

**Acceptance:**
- [ ] March ON: mixed-speed group moves at slowest unit's speed
- [ ] Scatter keeps units apart by configured distance
- [ ] Range Walk: mixed-range groups sort by depth when moving toward enemy

### Phase 5: Firing Line
**Widget:** `auto_puppeteer_firingline.lua`

14. Firing line state machine
15. Cycle choreography (advance, fire, cycle, reload)
16. Heal-seek behavior near constructors

**Acceptance:**
- [ ] Same-type units cycle through fire-reload positions
- [ ] Continuous fire maintained (no gap between cycles)
- [ ] Units seek nearby constructors for healing during reload

---

## 8. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance: many units * enemy range checks | FPS drop | Throttle: position-hash change detection, cache enemy ranges per defID, stagger unit processing across frames |
| Order conflicts with player commands | Units feel unresponsive | Respect player commands: `CMD_FIGHT`, `CMD_ATTACK`, `CMD_PATROL` override Puppeteer. Only modify `CMD_MOVE`. |
| Formation positions on impassable terrain | Units stuck | Validate with `spGetGroundHeight()` + `Spring.TestMoveOrder()` |
| Dodge conflicts with formation holding | Units never return | Post-dodge: re-issue formation position after cooldown expires |
| Firing line timing gaps | DPS loss | Use actual weapon reload state (`GetUnitWeaponState`) not estimated timing |
| Enemy range data for invisible units | Walk into unscouted danger | Only avoid visible enemy ranges. Fog of war = unknown risk (acceptable, that's what scouting is for). |
| Multi-widget coordination bugs | Conflicting orders | Clear ownership: each widget type writes only its section of the state table. Order priority: dodge > smartmove > formation > march. |

---

## 9. Future Extensions

Not in scope, but natural evolutions:

- **Terrain-aware formations** — Use height maps: prefer high ground, avoid low ground. Units on hills get range bonus.
- **Weapon arc awareness** — Formations orient units so turret arcs cover the threat direction.
- **Formation rotation** — Entire formation pivots to face incoming threat without breaking shape.
- **Focus fire from formation** — All units target the same high-value enemy.
- **Waypoint formation transitions** — March in column, deploy in circle at destination. Formation shape changes at each waypoint.

---

## 10. Open Questions

1. **Should Puppeteer fully replace dodge/skirmish, or coexist?** Current proposal: coexist but old widgets auto-disable when Puppeteer is active. Player can choose simple or advanced.

2. **How to handle air units?** Air units have 3D pathing. Proposal: ground + naval only for Phase 1. Air units excluded from Puppeteer management.

3. **CommandNotify vs GameFrame for formations?** Both needed: `CommandNotify` for formation calculation at command time, `GameFrame` for maintenance/dodge/repositioning.

4. **Managed unit lifecycle?** When player selects units and enables Puppeteer, those units become "managed." Proposal: units stay managed until Puppeteer toggled off or units given a new manual command outside Puppeteer.

5. **Nesting depth** — Is 5 layers too many? Probably 2-3 is the practical max. Keep configurable but default to 2.

6. **Widget file naming** — `auto_puppeteer_*.lua` vs `auto_totallylegal_puppeteer_*.lua`? The `totallylegal` prefix is long but consistent with the project. Proposal: use `auto_puppeteer_*` for brevity since the family is self-contained.

---

*This document will evolve as implementation begins. Phase 1 is the priority.*
