# Development Environment Setup — BARB Quest

> How to set up, deploy, and test Barb3 AI changes on your local BAR installation.
>
> **Last Updated:** 2026-02-16

---

## Prerequisites

- **Beyond All Reason** installed via the official launcher
- Windows 10/11

---

## Directory Layout

### BAR Installation

```
C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\
├── Beyond-All-Reason.exe          # Launcher
└── data\
    ├── engine\recoil_2025.06.12\  # Recoil engine
    │   ├── spring.exe             # Game (graphical)
    │   ├── spring-headless.exe    # Game (no rendering, for automated testing)
    │   └── AI\Skirmish\           # Skirmish AI directory
    │       ├── BARb\stable\       # Live BARb (shipped with engine, DO NOT MODIFY)
    │       ├── Barb3\ → junction  # Our dev copy (symlinked from repo)
    │       ├── CircuitAI\
    │       └── NullAI\
    ├── LuaUI\Widgets\             # Widget directory
    │   └── TotallyLegal\ → junction  # Our widget suite
    ├── infolog.txt                 # Game log output (AI logs go here)
    ├── maps\                      # Downloaded maps
    └── demos\                     # Replay files
```

### Repo Structure (relevant to Barb3 development)

```
BAR\Prod\Skirmish\Barb3\
└── stable\
    ├── AIInfo.lua                 # shortName='Barb3' (registers as separate AI)
    ├── AIOptions.lua              # Difficulty profiles
    ├── SkirmishAI.dll             # CircuitAI runtime (Felenious's build, Feb 13)
    ├── config\
    │   ├── experimental_balanced\ # Default profile configs
    │   │   ├── block_map.json     # Spatial exclusion zones
    │   │   ├── ArmadaBuildChain.json
    │   │   ├── ArmadaBehaviour.json
    │   │   ├── ArmadaEconomy.json
    │   │   └── ...
    │   ├── experimental_ThirtyBonus\
    │   ├── experimental_FiftyBonus\
    │   ├── experimental_EightyBonus\
    │   ├── experimental_HundredBonus\
    │   └── experimental_Suicidal\
    └── script\
        ├── experimental_balanced\
        │   ├── init.as            # Profile entry point
        │   └── main.as            # Profile wrapper
        └── src\                   # Shared AngelScript source (~80 files)
            ├── define.as          # Constants (SECOND=30, SQUARE_SIZE=8)
            ├── global.as          # Global state (Map::StartPos, AISettings::Side)
            ├── task.as            # SBuildTask struct, TaskB factories
            ├── manager\
            │   ├── builder.as     # Build task management (MODIFIED)
            │   ├── economy.as
            │   ├── factory.as
            │   └── military.as
            ├── roles\
            │   └── tech.as        # Tech builder decisions (MODIFIED)
            ├── helpers\
            │   ├── block_planner.as  # Wind grid placement (NEW)
            │   ├── generic_helpers.as
            │   ├── unit_helpers.as
            │   ├── economy_helpers.as
            │   └── ...
            ├── types\
            └── maps\
```

---

## Enable Developer Mode (one-time setup)

By default, BAR's lobby hides custom AIs behind a "Simplified AI List" filter. To see Barb3:

### 1. Create `devmode.txt`

Create an empty file at:
```
C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data\devmode.txt
```

This unlocks the **Developer** tab in BAR's Settings menu.

### 2. Uncheck "Simplified AI List"

1. Restart BAR (close launcher fully, reopen)
2. Go to **Settings > Developer**
3. **Uncheck "Simplified AI List"**
4. Return to Skirmish — Barb3 will now appear in the AI chooser

Without this, the lobby only shows officially registered AIs (BARb, SimpleAI, etc.) and hides any custom AIs in the Skirmish directory.

Reference: `Prod/Adding AI to Beyond All Reason.md` (Felenious's guide)

---

## Symlink Setup

The engine discovers Skirmish AIs by scanning `AI\Skirmish\*\`. We deploy Barb3 as a **separate AI** alongside the stock BARb using a directory junction.

### Create the junction (one-time setup)

Open PowerShell and run:

```powershell
New-Item -ItemType Junction `
  -Path "C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.12\AI\Skirmish\Barb3" `
  -Target "C:\Jules.Life\Projects\TheLab\Experiments\BAR\Prod\Skirmish\Barb3"
```

### Verify

```powershell
dir "C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.12\AI\Skirmish"
```

You should see:
```
BARb/          # Stock AI (untouched)
Barb3 -> ...   # Junction to our repo
CircuitAI/
NullAI/
```

### Remove the junction (if needed)

```powershell
# Removes the junction only, NOT the target files
(Get-Item "...\AI\Skirmish\Barb3").Delete()
```

---

## How the Engine Loads Barb3

1. Engine starts, scans `AI\Skirmish\*\*\AIInfo.lua`
2. Finds `Barb3\stable\AIInfo.lua` with `shortName = 'Barb3'`
3. Registers "Barb3" as an available AI in the lobby
4. Player selects Barb3 + difficulty profile (e.g., `experimental_balanced`)
5. Engine loads `SkirmishAI.dll` (CircuitAI C++ runtime)
6. CircuitAI loads JSON configs from `config\experimental_balanced\`
7. CircuitAI compiles AngelScript from `script\experimental_balanced\init.as` which includes `script\src\*`
8. Game loop: engine calls `@Entry_Update(frame)` each tick (30 FPS simulation)

**Key point:** AngelScript files are compiled fresh each match. Edit `.as` files, start a new match, changes are live. No DLL recompilation needed.

---

## Development Loop

```
1. Edit .as file(s) in Prod\Skirmish\Barb3\stable\script\src\
2. Start a new skirmish match with Barb3 AI
3. Observe behavior in-game
4. Check infolog.txt for [BlockPlanner] / [TECH] / [BUILDER] log entries
5. Repeat
```

### Important

- **No hot-reload:** Changes only take effect on a NEW match (AngelScript is compiled at match start)
- **No game restart needed:** Just start a new skirmish from the lobby — don't need to close BAR entirely
- **JSON config changes** also take effect on new match start

---

## Testing a Match

### Via BAR Launcher (recommended)

1. Open BAR launcher
2. Click **Skirmish** (singleplayer)
3. Add an AI opponent:
   - Select **Barb3** (NOT BARb — that's the stock AI)
   - Difficulty: **Experimental | Balanced**
4. Pick a small land map (e.g., Supreme Isthmus, Comet Catcher, Archsimkats)
5. Choose any faction (Armada, Cortex, or Legion)
6. Start the match

### What to Watch For

- **Wind turbines:** Should form visible 4x4 grids instead of scattering randomly
- **Log entries:** Check `infolog.txt` for `[BlockPlanner]` messages
- **Fallback behavior:** If block planner returns null, AI falls through to normal C++ placement

### Via Headless (automated, no graphics)

Create a start script `_script.txt`:

```ini
[GAME]
{
    Mapname=Supreme Isthmus v3.1;
    GameType=Beyond All Reason $VERSION;
    StartPosType=2;

    [AI0]
    {
        Name=Barb3 Test;
        ShortName=Barb3;
        Version=stable;
        Team=0;
        Host=0;
        [OPTIONS]
        {
            profile=experimental_balanced;
        }
    }

    [AI1]
    {
        Name=BARb Opponent;
        ShortName=BARb;
        Version=stable;
        Team=1;
        Host=0;
    }

    [TEAM0]
    {
        TeamLeader=0;
        AllyTeam=0;
        Side=Armada;
    }

    [TEAM1]
    {
        TeamLeader=0;
        AllyTeam=1;
        Side=Cortex;
    }

    [ALLYTEAM0] { NumAllies=0; }
    [ALLYTEAM1] { NumAllies=0; }

    [MODOPTIONS]
    {
        MinSpeed=1;
        MaxSpeed=100;
    }
}
```

Run:
```cmd
"C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2025.06.12\spring-headless.exe" --write-dir "C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data" _script.txt
```

---

## Logs

All AI output goes to:

```
C:\Users\julia\AppData\Local\Programs\Beyond-All-Reason\data\infolog.txt
```

### Log Levels

The `GenericHelpers::LogUtil(msg, level)` function filters by log level:
- **Level 1:** Important events (block creation, major decisions)
- **Level 2:** Standard operations (enqueue, slot fill, economy snapshots)
- **Level 3:** Verbose/debug (cooldowns, availability checks)
- **Level 4:** Trace (function entry/exit)

### What to Search For

| Pattern | Meaning |
|---------|---------|
| `[BlockPlanner] Created wind block` | New 4x4 grid started |
| `[BlockPlanner] Enqueued` | Wind turbine queued at grid position |
| `[BlockPlanner] Slot N FILLED` | Wind turbine built successfully |
| `[BlockPlanner] Slot N reset to EMPTY` | Build failed, will retry |
| `[TECH] Block planner: wind block task` | Tech role intercepted for block placement |
| `[BlockPlanner] No block available` | All blocks full or on cooldown |

---

## Key Differences: BARb vs Barb3

| | BARb (stock) | Barb3 (Felenious dev) |
|---|---|---|
| **shortName** | `BARb` | `Barb3` |
| **Script files** | ~11 .as files | ~80+ .as files |
| **Profiles** | `dev/` only | `experimental_balanced`, `ThirtyBonus`, `FiftyBonus`, `EightyBonus`, `HundredBonus`, `Suicidal` |
| **Architecture** | Flat manager files | Modular: managers, roles, helpers, types, maps |
| **DLL** | Nov 28 build (6.3MB) | Feb 13 build (6.3MB), different hash |
| **Config** | 7 JSON files + dev/ | 8+ JSON files per profile, faction-specific |

Barb3 is Felenious's active development version — significantly more advanced than the stock BARb shipped with the engine.

---

## Troubleshooting

### Barb3 doesn't appear in lobby

- Verify junction exists: `dir ...\AI\Skirmish\` should show `Barb3`
- Verify `AIInfo.lua` is readable through the junction
- Restart BAR launcher (AI list is cached)

### AngelScript compilation errors

- Check `infolog.txt` for `AngelScript` error messages
- Common issues: missing includes, type mismatches, null handle access
- The error will include file path and line number

### AI does nothing / crashes immediately

- Check `infolog.txt` for early errors
- Verify the DLL matches the engine version (Barb3's DLL was built for this engine)
- Try stock BARb first to confirm the engine works

### Block planner not triggering

- Check economy thresholds: needs metal income > 5.0 AND (energy income < 200 OR energy stalling)
- Check wind def availability: `armwin`/`corwin`/`legwin` must be unlocked
- Check logs for `[BlockPlanner] ShouldInterceptForWind` decisions

### Engine version changes after BAR update

If BAR updates and the engine version changes (e.g., `recoil_2025.07.xx`):
1. The old junction becomes orphaned (old engine dir may be deleted)
2. Recreate the junction pointing to the new engine's `AI\Skirmish\` directory
3. The repo files don't change — just the junction target path

---

## File Modification Checklist

When making changes to Barb3:

1. **Edit files** in `Prod\Skirmish\Barb3\stable\script\src\`
2. **Start new match** — changes compile on match start
3. **Check infolog.txt** — search for your log messages
4. **Note:** `Prod/` is gitignored — these are local development files only
