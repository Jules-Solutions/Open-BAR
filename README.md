# TotallyLegal - Beyond All Reason Widget Suite & Strategy Engine

A modular automation and strategy system for [Beyond All Reason](https://www.beyondallreason.info/), built as a Lua widget suite with a Python simulation engine.

## What Is This?

TotallyLegal is a **system of systems** for BAR that operates at four automation levels:

| Level | Mode | You Do | System Does |
|-------|------|--------|-------------|
| 0 | Overlay | Play normally | Display info (PvP safe) |
| 1 | Execute | Set the strategy | Execute it |
| 2 | Advise | Approve/override | Recommend + execute |
| 3 | Autonomous | Watch | Decide + execute |

The same underlying systems (perception, simulation, decision, execution, presentation) compose differently at each level. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system design.

## Project Structure

```
TotallyLegal/
├── lua/LuaUI/Widgets/     # Lua widget suite (19 widgets)
├── sim/                    # Python simulation engine
│   ├── bar_sim/            # Core simulation package
│   ├── data/               # Unit data, build orders, maps
│   └── cli.py              # CLI entry point
├── docs/                   # Architecture, strategy guides
└── archive/                # Legacy files
```

## Installation

### Lua Widgets (In-Game)

1. Run the install script to symlink widgets into your BAR data directory:
   ```
   lua\LuaUI\install.bat
   ```
2. Launch BAR. Widgets appear in the widget list under "TotallyLegal".
3. Use the config panel (Ctrl+F3) to set your automation level and strategy.

### Python Simulation Engine

```bash
cd sim
pip install -e .
python cli.py simulate data/build_orders/wind_opening.yaml
```

## The Five Systems

| System | Purpose | Components |
|--------|---------|------------|
| **Perception** | Read game state: units, resources, map, enemy intel | `lib_core`, `engine_mapzones` |
| **Simulation** | Model the game forward: predictions, optimization | Python `bar_sim` engine |
| **Decision** | Choose strategy: human, advisory, or autonomous | `engine_config`, future sim bridge |
| **Execution** | Carry out decisions: build, produce, move, fight | `engine_*`, `auto_*` widgets |
| **Presentation** | Show information: overlays, panels, recommendations | `gui_*` widgets |

## Widget Inventory

### Perception
- `lib_totallylegal_core.lua` - Shared state, unit classification, resource tracking
- `engine_totallylegal_mapzones.lua` - Map sector analysis

### Presentation (PvP Safe - Level 0+)
- `gui_totallylegal_overlay.lua` - Resource breakdown, unit census, build power
- `gui_totallylegal_goals.lua` - Goal queue display
- `gui_totallylegal_timeline.lua` - Economy timeline graph
- `gui_totallylegal_threat.lua` - Threat estimation display
- `gui_totallylegal_priority.lua` - Priority highlighting

### Execution: Micro (Level 1+)
- `auto_totallylegal_dodge.lua` - Projectile dodging
- `auto_totallylegal_skirmish.lua` - Optimal range kiting
- `auto_totallylegal_rezbot.lua` - Resurrection/reclaim automation

### Execution: Macro (Level 1+)
- `engine_totallylegal_config.lua` - Strategy configuration panel
- `engine_totallylegal_build.lua` - Opening build order executor
- `engine_totallylegal_econ.lua` - Economy management
- `engine_totallylegal_prod.lua` - Factory production queuing
- `engine_totallylegal_zone.lua` - Zone and frontline management
- `engine_totallylegal_goals.lua` - Goal queue orchestration
- `engine_totallylegal_strategy.lua` - Attack strategy execution

## Automation & Fair Play

TotallyLegal respects BAR's automation rules:

- **Level 0 (Overlay):** Zero `GiveOrder` calls. Read-only info display. Safe for ranked and PvP.
- **Level 1+ (Execution):** Uses `GiveOrder` for automation. Automatically disabled when the game's `noautomation` rule is active. PvE and unranked only.

## Status

**Work in progress.** Currently functional: overlays, auto-dodge. Macro systems (economy, production, zones, goals, strategy) are under active development.

## License

GNU General Public License v2.0 - see [LICENSE](LICENSE) for details.
