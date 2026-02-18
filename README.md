# TotallyLegal - Beyond All Reason Widget Suite, Micro AI & Strategy Engine

A modular automation and strategy system for [Beyond All Reason](https://www.beyondallreason.info/), built as a Lua widget suite with a Python simulation engine — plus contributions to the BARB Skirmish AI.

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
BAR/
├── lua/LuaUI/Widgets/         # Lua widget suite (12 active widgets)
│   ├── 01_totallylegal_core   # Core perception library
│   ├── auto_puppeteer_*       # Micro automation (dodge, kite, raid, march)
│   ├── gui_*                  # Presentation overlays and panels
│   └── _shelf/                # Shelved macro widgets (Phase 6+)
├── sim/                       # Python simulation engine
│   ├── bar_sim/               # Core simulation package (20+ modules)
│   ├── data/                  # Unit DB, build orders, map cache
│   ├── tests/                 # pytest suite (36+ tests)
│   └── cli.py                 # CLI entry point
├── Prod/                      # Reference code (gitignored)
│   ├── Beyond-All-Reason/     # BAR game source (reference)
│   └── Skirmish/              # Skirmish AI source (BARb, Barb3)
├── docs/                      # Architecture, strategy, status, roadmap
├── sessions/                  # Work sessions and research
│   └── Session_2/             # BARB Quest (active)
└── Discord_Chats/             # Communication logs with BAR devs
```

## Active Workstreams

### 1. Puppeteer Micro Suite (Complete)

Formation-aware micro automation for unit control:

| Widget | Function |
|--------|----------|
| `auto_puppeteer_core` | Shared state, unit tracking, formation detection |
| `auto_puppeteer_dodge` | Projectile dodging with formation awareness |
| `auto_puppeteer_firingline` | Optimal range kiting |
| `auto_puppeteer_formations` | Unit formation management |
| `auto_puppeteer_march` | Group movement coordination |
| `auto_puppeteer_raid` | Automated mex raiding patrol |
| `auto_puppeteer_smartmove` | Reactive rerouting around enemies |
| `gui_puppeteer_panel` | Puppeteer control panel |

### 2. BARB Quest (Active)

Improving building placement for the [BARB Skirmish AI](https://github.com/Felnious/Skirmish). Quest given by Felenious, the BARB lead developer.

**Problem:** BARB places buildings independently with 256-elmo randomization, causing scattered bases that waste space.

**Solution:** Block-based placement system that organizes buildings into compact grids (starting with 4x4 wind turbine blocks).

**Status:** MVP code written, dev environment set up, pending in-game testing.

See [sessions/Session_2/](sessions/Session_2/) for full research, design docs, and setup guide.

### 3. Presentation Widgets (Complete)

| Widget | Function |
|--------|----------|
| `gui_totallylegal_overlay` | Resource breakdown, unit census |
| `gui_totallylegal_sidebar` | KSP-style widget toggle bar |
| `gui_totallylegal_timeline` | Economy timeline graph |

### 4. Simulation Engine (Complete)

Python-based build order simulation and optimization:

```bash
cd sim
pip install -e .
python cli.py simulate data/build_orders/wind_opening.yaml
```

## Installation

### Lua Widgets (In-Game)

Widgets are symlinked into the BAR data directory:
```
%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\Widgets\TotallyLegal\
```

1. Run `lua\LuaUI\install.bat` to create the symlink
2. Launch BAR — widgets appear in the widget list
3. Toggle widgets via the sidebar panel

### Barb3 AI (Development)

Barb3 is deployed as a separate Skirmish AI alongside the stock BARb:

```powershell
# One-time setup: create directory junction
New-Item -ItemType Junction `
  -Path "<BAR-data>\engine\<version>\AI\Skirmish\Barb3" `
  -Target "<repo>\Prod\Skirmish\Barb3"
```

See [sessions/Session_2/SETUP.md](sessions/Session_2/SETUP.md) for full setup guide.

### Python Simulation Engine

```bash
cd sim
pip install -e .
pytest                    # Run test suite
python cli.py --help      # CLI commands
```

## The Five Systems

| System | Purpose | Components |
|--------|---------|------------|
| **Perception** | Read game state: units, resources, map, enemy intel | `01_totallylegal_core`, `auto_puppeteer_core` |
| **Simulation** | Model the game forward: predictions, optimization | Python `bar_sim` engine |
| **Decision** | Choose strategy: human, advisory, or autonomous | Future sim bridge |
| **Execution** | Carry out decisions: build, produce, move, fight | `auto_puppeteer_*` widgets |
| **Presentation** | Show information: overlays, panels, recommendations | `gui_*` widgets |

## Automation & Fair Play

TotallyLegal respects BAR's automation rules:

- **Level 0 (Overlay):** Zero `GiveOrderToUnit` calls. Read-only info display. Safe for ranked and PvP.
- **Level 1+ (Execution):** Uses `GiveOrderToUnit` for automation. Automatically disabled when the game's `noautomation` rule is active.

## Tech Stack

| Layer | Language | Details |
|-------|----------|---------|
| In-game widgets | Lua | Spring RTS widget API, `WG.*` shared state |
| Simulation engine | Python 3.11+ | pyyaml, fastapi, pytest |
| Skirmish AI (BARB) | AngelScript | CircuitAI C++ framework, `.as` scripts |
| Game engine | C++ | Spring/Recoil engine (reference only) |

## Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| 1-3 | Done | Perception, execution, presentation stabilized |
| 4 | Done | Puppeteer micro suite (dodge, kite, raid, march, formations) |
| 5 | Done | Simulation engine (build orders, optimization) |
| BARB Quest | Active | Block-based building placement for BARB AI |
| 6 | Planned | Sim bridge (connect Python sim to Lua execution) |
| 7 | Planned | AI agent (autonomous strategy via RL) |

## License

GNU General Public License v2.0 - see [LICENSE](LICENSE) for details.
