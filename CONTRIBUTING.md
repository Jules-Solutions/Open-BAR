# Contributing to TotallyLegal

Thanks for your interest in contributing to the TotallyLegal widget suite for Beyond All Reason.

## Getting Started

1. Fork the repo and clone it locally
2. Run `lua\LuaUI\install.bat` to symlink widgets into your BAR data directory
3. Launch BAR and test your changes in a skirmish game

## Project Structure

- `lua/LuaUI/Widgets/` - Lua widgets that run inside BAR
- `sim/` - Python simulation engine (standalone)
- `docs/` - Architecture and strategy documentation

## Widget Naming Convention

All widgets follow this pattern: `{type}_totallylegal_{name}.lua`

| Prefix | System | Examples |
|--------|--------|----------|
| `lib_` | Perception (shared state) | `lib_totallylegal_core` |
| `gui_` | Presentation (display only) | `gui_totallylegal_overlay` |
| `auto_` | Execution: micro | `auto_totallylegal_dodge` |
| `engine_` | Execution: macro / Decision | `engine_totallylegal_econ` |

## Development Guidelines

### Lua Widgets

- All widgets read shared state from `WG.TotallyLegal` (provided by `lib_totallylegal_core`)
- Every widget that issues `GiveOrderToUnit` must check `automationLevel >= 1`
- Use `pcall` around any cross-widget reads to handle load order / disabled widgets
- Nil-safe access everywhere: another widget might not be loaded
- Test with widgets disabled individually to verify graceful degradation

### Python Simulation

- Use `uv` or `pip install -e .` from the `sim/` directory
- Run `python cli.py --help` for available commands

## Submitting Changes

1. Create a branch from `main`
2. Make your changes
3. Test in-game (skirmish vs AI)
4. Submit a pull request with a description of what changed and why

## Reporting Bugs

Open an issue with:
- What you expected to happen
- What actually happened
- Spring log output (if relevant)
- Which widgets were enabled
