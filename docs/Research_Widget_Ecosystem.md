# BAR Widget Ecosystem Research

> Research conducted 2026-02-05. Covers: existing widgets, community repos, Lua API, policies, map/terrain API, headless mode, and gaps.

---

## 1. Key Repositories

### Official: [beyond-all-reason/Beyond-All-Reason](https://github.com/beyond-all-reason/Beyond-All-Reason)
The main game repo. Contains **~350+ built-in widgets** in `luaui/Widgets/`. This is the primary reference for how widgets are structured.

### Community: [beyond-all-reason/bar_widgets](https://github.com/beyond-all-reason/bar_widgets)
Official community widget submission repo. Strict guidelines:
- One widget per `widgets/{widget_name}/` folder with a README
- GPL-2.0 license
- Must not provide unfair advantages or exploit mechanics
- Must have clean, readable code
- Rejected widgets cannot be resubmitted

### Third-party: [zxbc/BAR_widgets](https://github.com/zxbc/BAR_widgets)
Community collection with **38 widgets**. Notable ones relevant to our project:
- `cmd_customformations2` -- custom unit formations
- `cmd_distributive_commands` -- distribute orders across units
- `cmd_single_volley_attack_mode` -- single-shot attack patterns
- `gui_attackrange_gl4` -- attack range visualization
- `gui_defenserange_gl4` -- defense range visualization
- `gui_healthbars_gl4` -- health bars
- `gui_smart_commands` -- intelligent command suggestions
- `unit_statePrefs` -- unit state management

### Other
- [jorisvddonk/bar-replay-analyzer](https://github.com/jorisvddonk/bar-replay-analyzer) -- replay analysis tools
- [beyond-all-reason/ZBStudioAPI](https://github.com/beyond-all-reason/ZBStudioAPI) -- IDE API definitions for autocomplete

---

## 2. Built-in Widget Inventory (Main Repo)

The game ships with **~350+ widgets** in `luaui/Widgets/`. Here's what already exists that overlaps with our brainstorm:

### Already Exists (Direct Overlap)

| Our Idea | Existing Widget(s) | Status |
|----------|-------------------|--------|
| Attack range overlay | `gui_attackrange_gl4.lua`, `gui_defenserange_gl4.lua` | Built-in |
| Health bars | `gui_healthbars_gl4.lua` | Built-in |
| Economy stats | `gui_ecostats.lua`, `gui_top_bar.lua`, `gui_converter_usage.lua` | Built-in |
| Build ETA | `gui_build_eta.lua` | Built-in |
| Reclaim highlight | `gui_reclaim_field_highlight.lua`, `gui_reclaiminfo.lua` | Built-in |
| Unit stats overlay | `gui_unit_stats.lua`, `gui_spectatingstats.lua` | Built-in |
| Idle builder alerts | `gui_idle_builders.lua`, `gui_unit_idlebuilder_icons.lua` | Built-in |
| Smart area reclaim | `unit_smart_area_reclaim.lua` | Built-in |
| Transport AI | `unit_transport_ai.lua` | Built-in |
| Builder priority | `unit_builder_priority.lua` | Built-in |
| Factory queue management | `cmd_factoryqmanager.lua`, `cmd_commandq_manager.lua` | Built-in |
| Auto cloak | `unit_auto_cloak.lua` | Built-in |
| Area mex placement | `cmd_area_mex.lua` | Built-in |
| Build menu / grid menu | `gui_buildmenu.lua`, `gui_gridmenu.lua` | Built-in |
| Sensor range display | `gui_sensor_ranges_*.lua` (radar, LOS, sonar, jammer) | Built-in |
| Damage stats | `stats_damage.lua` | Built-in |
| Team stats | `gui_teamstats.lua` | Built-in |
| Spectator HUD | `gui_spectator_hud.lua` | Built-in |
| Metal spots overlay | `gui_metalspots.lua`, `gui_prospector.lua` | Built-in |
| Build spacing | `gui_buildspacing.lua`, `cmd_persistent_build_spacing.lua` | Built-in |
| Pregame build planning | `gui_pregame_build.lua` | Built-in |

### Partially Exists (Could Extend)

| Our Idea | Closest Existing | Gap |
|----------|-----------------|-----|
| PvP overlay (resource breakdown) | `gui_ecostats.lua`, `gui_top_bar.lua` | Doesn't show per-unit-type production breakdown |
| Build power dashboard | `gui_idle_builders.lua` | Shows idle builders, not total/active/stalling BP |
| Threat estimator | Nothing | No enemy capability prediction exists |
| Timeline graph (expected vs actual) | Nothing | No economic prediction/comparison tool |
| Priority highlights (glowing circles) | `gfx_HighlightUnit_GL4.lua` | Exists as a rendering primitive, not as a priority system |

### Does NOT Exist (Opportunities)

| Our Idea | Notes |
|----------|-------|
| Auto skirmishing | Explicitly mentioned in GDT policy as automation (PvE only) |
| Automated rezbots | Explicitly mentioned in GDT policy as automation (PvE only) |
| Projectile dodging | Explicitly mentioned in GDT policy as automation (PvE only) |
| Strategic automation engine | Nothing remotely close exists |
| Goal/project queue system | Nothing exists |
| Frontline management (draw lines, auto-defend) | Nothing exists |
| Attack strategy presets | Nothing exists |
| Build order simulator (offline) | Nothing exists |
| Economic prediction timeline | Nothing exists |
| Risk/threat estimator | Nothing exists |
| AI agent player | BAR has built-in AIs but no widget-driven adaptive AI |

---

## 3. Widget Policy (GDT Rules)

Source: [Issue #3910](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/3910) and [Issue #3879](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/3879)

### Three-Tier System

| Mode | Default For | What's Allowed |
|------|-------------|----------------|
| **All** | Unranked, PvE, Custom | Everything including automation |
| **No Automation** | PvP Ranked | Visual + input convenience only. Blocks any widget calling `GiveOrder`-type APIs |
| **None** | (optional) | All custom widgets disabled |

### What Counts as Automation
Any widget that **issues commands on behalf of the player** using:
- `Spring.GiveOrderToUnit()`
- `Spring.GiveOrderArrayToUnit()`
- `Spring.GiveOrderToUnitArray()`

**Explicitly called out as automation:**
- Auto skirmishing
- Automated resurrection bots
- Projectile dodging

### Implications for TotallyLegalWidget
- **Tier 1 widgets (auto skirmish, rezbots, dodging):** PvE/Unranked ONLY
- **Tier 3 strategic automation:** PvE/Unranked ONLY
- **Tier 4 PvP overlay:** Ranked-safe (read-only, no GiveOrder calls)
- **Tier 5 simulator:** Offline tool, not a widget at all -- no policy concern
- Our two-mode system (All / No Automation) aligns perfectly with GDT policy

---

## 4. Lua API -- What's Available

### Widget Architecture
- **Widgets** = client-side only (LuaUI). Cannot modify game state. Can read game state and draw UI.
- **Gadgets** = server-side (LuaRules). Can modify game state. Synced (deterministic) + unsynced contexts.
- Communication: Widgets talk to gadgets via `Spring.SendLuaRulesMsg()`. Widgets share data via the `WG` global table.

### Widget Lifecycle
```
Discovery (VFS scan) -> loadstring() -> GetInfo() -> Initialize() -> Active (callins) -> Shutdown()
```

### Key Call-ins
| Category | Functions |
|----------|----------|
| Lifecycle | `Initialize()`, `Shutdown()`, `Update()` |
| Rendering | `DrawScreen()`, `DrawWorld()`, `DrawInMiniMap()` |
| Input | `KeyPress()`, `MousePress()`, `MouseMove()` |
| Unit events | `UnitCreated()`, `UnitFinished()`, `UnitDestroyed()` |
| Commands | `CommandNotify()`, `DefaultCommand()` |
| Game | `GameStart()`, `GameFrame()` (30Hz), `GameOver()` |

### Unit Control (Automation Mode Only)
```lua
Spring.GiveOrderToUnit(unitID, cmdID, cmdParams, cmdOptions)
Spring.GiveOrderArrayToUnit(unitID, cmdArray, cmdOptions)
Spring.GiveOrderToUnitArray(unitIDs, cmd, params, options)
```

### Unit Info
```lua
Spring.GetUnitPosition(unitID)      -- x, y, z
Spring.GetUnitDefID(unitID)         -- unit definition ID
Spring.GetUnitTeam(unitID)          -- team
Spring.GetUnitHealth(unitID)        -- health, maxHealth
```

### Map & Terrain (Answers the "Do We Need a Vector DB?" Question)
```lua
Spring.GetGroundHeight(x, z)           -- height at position
Spring.GetGroundOrigHeight(x, z)       -- pre-terraforming height
Spring.GetGroundNormal(x, z)           -- normal vector + slope
Spring.GetGroundInfo(x, z)             -- type, metal, hardness, tankSpeed, kbotSpeed,
                                       --   hoverSpeed, shipSpeed, receiveTracks
Spring.GetGroundBlocked(x, z)          -- nil or "feature"/featureID or "unit"/unitID
Spring.GetSmoothMeshHeight(x, z)       -- smoothed height
Spring.GetTerrainTypeData(i)           -- terrain type properties
Spring.GetMapOptions()                 -- map configuration
```

**Verdict on the vector DB idea:** The engine already exposes per-position terrain data (buildability via `GetGroundBlocked`, pathability via `GetGroundInfo` speed values, slope via `GetGroundNormal`). A full vector DB is **overkill**. Instead:
- Query these APIs on-demand or cache a grid at game start
- The existing `api_resource_spot_finder.lua` already demonstrates map scanning for metal spots
- For pathfinding: `Spring.GetUnitEstimatedPath(unitID)` and `Path.RequestPath()` exist natively

### Pathfinding API
```lua
Path.RequestPath(moveType, startX, startY, startZ, endX, endY, endZ [, radius])  -- returns path object
path:GetPathWayPoints()   -- table of waypoints + 3 detail levels
path:Next()               -- next waypoint (dynamic resolution)
Path.InitPathNodeCostsArray()   -- custom cost overlays
Path.SetPathNodeCost()          -- modify individual node costs
```

### Rendering
```lua
gl.Text(text, x, y, size, align)
gl.Rect(x1, y1, x2, y2)
gl.Color(r, g, b, a)
```
Many built-in widgets use GL4 shaders (see `*_gl4.lua` files) for performant rendering.

### Config Persistence
```lua
widget:GetConfigData()    -- save settings between sessions
widget:SetConfigData(data)
```

---

## 5. Python-Lua Bridge

**Finding: No existing Python-Lua bridge for BAR/Spring.**

- BAR uses Lua exclusively for widget/gadget scripting
- Python is used only for offline tooling (3D model conversion, data analysis)
- The Recoil engine (BAR's fork of Spring) embeds Lua; there's no socket/IPC interface for external scripts
- Community has not built a Python bridge

### Options
1. **Pure Lua** -- Write everything in Lua. This is what the entire community does. Zero friction.
2. **Lua + external process** -- Widget communicates via file I/O or localhost socket to a Python process. Hacky but possible for ML/AI features.
3. **Build a Python-Lua bridge** -- Significant engineering effort with unclear benefit for Tiers 1-4.

**Recommendation:** Start with pure Lua for Tiers 1-5. Only introduce Python for Tier 6 (AI agent) where ML libraries are needed. At that point, use the headless mode + external process approach.

---

## 6. Headless Mode

Source: [BAR Headless writeup](https://neek-sss.gitlab.io/yarsh-technologies-blog/posts/bar_headless/)

BAR can run **without a GUI** via `spring-headless.exe`:
- Games run at up to 9999x speed
- Supports AI vs AI games
- Can replay recorded matches
- Custom widgets can inject data extraction (CSV export, etc.)

**Relevance:**
- **Tier 5 (Build Order Simulator):** Could run simulations headlessly at max speed and extract economy data
- **Tier 6 (AI Agent):** Train/evaluate AI agents at 9999x speed without GPU overhead
- This is a major asset -- most games don't offer this

---

## 7. Recommendations & Prioritization

### Start Here (Low Effort, High Value, Ranked-Safe)

1. **PvP Overlay Widget** (Tier 4) -- Most of the data is available via existing APIs. Build on top of what `gui_ecostats.lua` and `gui_top_bar.lua` already do. Focus on:
   - Per-unit-type resource production breakdown
   - Build power utilization dashboard (total / active / idle / stalling)
   - Threat estimator (time-based enemy capability prediction)

2. **Study existing widgets** -- Before writing code, read these built-in widgets thoroughly:
   - `gui_ecostats.lua` -- economy display patterns
   - `gui_attackrange_gl4.lua` -- range visualization (GL4 rendering)
   - `unit_transport_ai.lua` -- how automation widgets issue orders
   - `cmd_factoryqmanager.lua` -- factory queue management
   - `api_resource_spot_finder.lua` -- map scanning patterns
   - `gui_pregame_build.lua` -- pre-game planning UI

### Then (Medium Effort, PvE Only)

3. **Auto Skirmishing Widget** (Tier 1) -- Unit micro automation. Read `cmd_customformations2.lua` and `unit_transport_ai.lua` for patterns on issuing orders.

4. **Automated Rezbots** (Tier 1) -- Extend `unit_smart_area_reclaim.lua` patterns.

### Later (High Effort)

5. **Build Order Simulator** (Tier 5) -- Can leverage headless mode. This is more of an external tool than a widget.

6. **Strategic Automation Engine** (Tier 3) -- The big one. Needs all the foundation from Tiers 1 and 4.

7. **AI Agent** (Tier 6) -- Needs everything else built first.

### Skip or Reconsider

- **Python-Lua bridge** (Tier 2) -- Not worth building until Tier 6. Pure Lua is sufficient for everything else.
- **Map vector DB** -- The engine's terrain API already provides this data. Cache a grid at game start if needed.
- **Projectile dodging** -- Technically complex (need to track projectile trajectories). Save for later.

---

## 8. Development Setup

### Where Widgets Live
```
BAR-install-directory/data/games/BAR.sdd/luaui/Widgets/
```
Custom widgets go in the user's data directory (exact path depends on OS).

### IDE Support
- [ZBStudioAPI](https://github.com/beyond-all-reason/ZBStudioAPI) provides autocomplete definitions
- [Lua Language Server setup guide](https://beyond-all-reason.github.io/spring/guides/lua-language-server) for VS Code

### Debugging
Built-in debug widgets: `dbg_widget_profiler.lua`, `dbg_widget_auto_reloader.lua`, `dbg_frame_grapher.lua`

### Reference Docs
- [Spring Lua SyncedRead API](https://springrts.com/wiki/Lua_SyncedRead) -- all readable game state functions
- [Spring Lua Widgets](https://springrts.com/wiki/Lua_Widgets) -- widget system documentation
- [Spring Lua PathFinder](https://springrts.com/wiki/Lua_PathFinder) -- pathfinding API
- [Spring Lua Scripting](https://springrts.com/wiki/Lua_Scripting) -- main scripting overview
- [DeepWiki: BAR Development & Modding](https://deepwiki.com/beyond-all-reason/Beyond-All-Reason/8-development-and-modding) -- comprehensive guide
- [Simple mods/tweaks guide](https://gist.github.com/efrec/153081a7d43db3ad7a3c4fc5c9a689f8)

---

## Sources

- [beyond-all-reason/Beyond-All-Reason](https://github.com/beyond-all-reason/Beyond-All-Reason)
- [beyond-all-reason/bar_widgets](https://github.com/beyond-all-reason/bar_widgets)
- [zxbc/BAR_widgets](https://github.com/zxbc/BAR_widgets)
- [GDT Custom Widget Rules (Issue #3910)](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/3910)
- [Custom Widgets Disabled in Ranked (Issue #3879)](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/3879)
- [DeepWiki: Development & Modding](https://deepwiki.com/beyond-all-reason/Beyond-All-Reason/8-development-and-modding)
- [Spring Lua SyncedRead](https://springrts.com/wiki/Lua_SyncedRead)
- [Spring Lua PathFinder](https://springrts.com/wiki/Lua_PathFinder)
- [Spring Lua Widgets](https://springrts.com/wiki/Lua_Widgets)
- [BAR Headless Guide](https://neek-sss.gitlab.io/yarsh-technologies-blog/posts/bar_headless/)
- [Recoil Engine: Documenting Lua](https://beyond-all-reason.github.io/spring/development/documenting-lua)
- [Recoil Engine: Lua Language Server](https://beyond-all-reason.github.io/spring/guides/lua-language-server)
