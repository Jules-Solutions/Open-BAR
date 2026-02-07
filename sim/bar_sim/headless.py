"""
BAR Build Order Simulator - Headless Game Engine Integration
=============================================================
Runs build orders in the real BAR game engine (headless mode at max speed).
Provides ground-truth simulation with perfect stalling, priority, nano range,
converter, walk time, and reclaim mechanics.

Communication:
    Python writes:  data/headless/input/build_order.json
    Lua writes:     data/headless/output/sim_result.json
"""

import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional

from bar_sim.db import get_game_id_map, ensure_db
from bar_sim.models import (
    BuildOrder, BuildActionType, SimResult,
    Milestone, StallEvent, Snapshot,
    MapData, MexSpot, GeoVent, StartPosition,
)

# ---------------------------------------------------------------------------
# Path auto-detection
# ---------------------------------------------------------------------------

# Common BAR install locations (Windows)
_BAR_INSTALL_CANDIDATES = [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Beyond-All-Reason" / "data",
    Path("C:/Program Files/Beyond-All-Reason/data"),
    Path("C:/Program Files (x86)/Beyond-All-Reason/data"),
    Path.home() / "Beyond-All-Reason" / "data",
]

_ENGINE_GLOB = "engine/recoil_*/spring-headless.exe"

PROJECT_ROOT = Path(__file__).parent.parent
HEADLESS_DIR = PROJECT_ROOT / "data" / "headless"
INPUT_DIR = HEADLESS_DIR / "input"
OUTPUT_DIR = HEADLESS_DIR / "output"
LUA_SRC = Path(__file__).parent / "lua" / "sim_executor.lua"
MAP_SCANNER_SRC = Path(__file__).parent / "lua" / "map_scanner.lua"

# Default map and game
DEFAULT_MAP = "delta_siege_dry_v5.7.1"
DEFAULT_GAME = "byar:test"
DEFAULT_DURATION_FRAMES = 18000  # 600 seconds * 30 fps

# Startscript template
STARTSCRIPT_TEMPLATE = """\
[GAME]
{{
  MapName={map_name};
  GameType={game_type};
  IsHost=1;

  [ALLYTEAM0]
  {{
  }}
  [ALLYTEAM1]
  {{
  }}

  [TEAM0]
  {{
    TeamLeader=0;
    AllyTeam=0;
    Side={side};
  }}
  [TEAM1]
  {{
    TeamLeader=0;
    AllyTeam=1;
  }}

  [PLAYER0]
  {{
    Name=Simulator;
    Spectator=0;
    Team=0;
  }}

  [AI0]
  {{
    Name=DummyEnemy;
    ShortName=NullAI;
    Team=1;
    Host=0;
  }}

  [MODOPTIONS]
  {{
    MinSpeed=9999;
    MaxSpeed=9999;
  }}
}}
"""


def find_bar_data_dir() -> Optional[Path]:
    """Auto-detect BAR data directory."""
    # Check environment variable first
    env_path = os.environ.get("BAR_DATA_DIR")
    if env_path:
        p = Path(env_path)
        if p.exists():
            return p

    for candidate in _BAR_INSTALL_CANDIDATES:
        if candidate.exists():
            return candidate

    return None


def find_engine_exe(data_dir: Path) -> Optional[Path]:
    """Find spring-headless.exe in the engine directory."""
    matches = sorted(data_dir.glob(_ENGINE_GLOB), reverse=True)
    return matches[0] if matches else None


# ---------------------------------------------------------------------------
# HeadlessEngine
# ---------------------------------------------------------------------------

class HeadlessEngine:
    """Runs a build order in the real BAR game engine (headless mode)."""

    def __init__(
        self,
        bar_data_dir: Optional[Path] = None,
        map_name: str = DEFAULT_MAP,
        game_type: str = DEFAULT_GAME,
        timeout: int = 120,
    ):
        self.bar_data_dir = bar_data_dir or find_bar_data_dir()
        if not self.bar_data_dir:
            raise FileNotFoundError(
                "BAR data directory not found. Set BAR_DATA_DIR environment variable "
                "or install BAR to a standard location."
            )

        self.engine_exe = find_engine_exe(self.bar_data_dir)
        if not self.engine_exe:
            raise FileNotFoundError(
                f"spring-headless.exe not found in {self.bar_data_dir / 'engine'}"
            )

        self.map_name = map_name
        self.game_type = game_type
        self.timeout = timeout
        self.widget_dir = self.bar_data_dir / "LuaUI" / "Widgets"
        self.write_dir = self.bar_data_dir  # Spring write dir is the data dir

    def run(self, build_order: BuildOrder, duration: int = 600, faction: str = "ARMADA") -> SimResult:
        """Full pipeline: translate BO -> write files -> launch engine -> parse results."""
        duration_frames = duration * 30

        # 1. Translate build order to game IDs
        bo_json = self._translate_build_order(build_order, faction, duration_frames)

        # 2. Write build order JSON
        self._write_build_order(bo_json)

        # 3. Write startscript
        side = "Armada" if faction.upper() == "ARMADA" else "Cortex"
        script_path = self._write_startscript(side)

        # 4. Deploy widget
        self._deploy_widget()

        # 5. Launch engine
        result_path = self._run_engine(script_path)

        # 6. Parse results
        return self._parse_results(result_path, build_order.name, duration)

    def scan_map(self, map_name: str) -> MapData:
        """One-time map scan: deploy scanner widget, launch headless, parse output.

        Returns a MapData with mex spots, geo vents, start positions, wind, etc.
        Results are merged with static metadata from the archive cache and saved
        to the map data cache for future use.
        """
        from bar_sim.map_data import save_map_cache
        from bar_sim.map_parser import build_map_metadata, map_name_to_filename

        # Resolve map name to filename
        filename = map_name_to_filename(map_name)
        if filename:
            engine_map_name = filename.replace(".sd7", "")
        else:
            engine_map_name = map_name.replace(".sd7", "")
            filename = map_name if map_name.endswith(".sd7") else map_name + ".sd7"

        print(f"[scan_map] Scanning map: {engine_map_name}")

        # Deploy map_scanner.lua (temporarily replacing sim_executor if present)
        self._deploy_scanner_widget()

        # Write startscript targeting this map
        script_path = self._write_scan_startscript(engine_map_name)

        # Clear old output
        output_path = self.write_dir / "headless" / "output" / "map_data.json"
        if output_path.exists():
            output_path.unlink()

        # Launch engine (scanner quits on its own after GameStart)
        cmd = [str(self.engine_exe), str(script_path)]
        print(f"[scan_map] Launching: {' '.join(cmd)}")
        start_time = time.time()

        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.bar_data_dir),
                timeout=60,  # scanner should finish in <10s
                capture_output=True,
                text=True,
            )
            elapsed = time.time() - start_time
            print(f"[scan_map] Engine finished in {elapsed:.1f}s (exit code: {proc.returncode})")
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"Map scan timed out after 60s for {engine_map_name}")
        finally:
            self._remove_scanner_widget()

        # Parse output JSON
        if not output_path.exists():
            # Check local output dir too
            local_output = OUTPUT_DIR / "map_data.json"
            if local_output.exists():
                output_path = local_output
            else:
                raise RuntimeError(
                    f"No map_data.json found at {output_path}. "
                    "Scanner widget may not have loaded."
                )

        with open(output_path, "r") as f:
            scan_data = json.load(f)

        # Build MapData from scan results
        md = MapData(
            name=scan_data.get("map_name", engine_map_name),
            filename=filename,
            map_width=scan_data.get("map_width", 0),
            map_height=scan_data.get("map_height", 0),
            wind_min=scan_data.get("wind_min", 0.0),
            wind_max=scan_data.get("wind_max", 25.0),
            tidal_strength=scan_data.get("tidal", 0.0),
            gravity=scan_data.get("gravity", 100.0),
            start_positions=[
                StartPosition(x=sp["x"], z=sp["z"], team_id=sp.get("team_id", 0))
                for sp in scan_data.get("start_positions", [])
            ],
            mex_spots=[
                MexSpot(x=ms["x"], z=ms["z"], metal=ms.get("metal", 2.0))
                for ms in scan_data.get("mex_spots", [])
            ],
            geo_vents=[
                GeoVent(x=gv["x"], z=gv["z"])
                for gv in scan_data.get("geo_vents", [])
            ],
            total_reclaim_metal=scan_data.get("total_reclaim_metal", 0.0),
            total_reclaim_energy=scan_data.get("total_reclaim_energy", 0.0),
            source="scanned",
        )

        # Merge with static metadata (for fields the scanner might miss)
        static_md = build_map_metadata(engine_map_name)
        if static_md:
            md.shortname = static_md.shortname
            md.author = static_md.author
            md.description = static_md.description
            md.max_metal = static_md.max_metal or md.max_metal
            md.extractor_radius = static_md.extractor_radius or md.extractor_radius
            # Prefer scanner wind data over static (scanner gets runtime values)
            if md.wind_min == 0 and md.wind_max == 25.0 and static_md.wind_min > 0:
                md.wind_min = static_md.wind_min
                md.wind_max = static_md.wind_max
            # Use static start positions if scanner didn't find any
            if not md.start_positions and static_md.start_positions:
                md.start_positions = static_md.start_positions

        # Save to cache
        cache_path = save_map_cache(md)
        print(f"[scan_map] Cached to {cache_path}")
        print(f"[scan_map] Mex spots: {len(md.mex_spots)}, "
              f"Geo vents: {len(md.geo_vents)}, "
              f"Wind: {md.wind_min}-{md.wind_max}")

        return md

    def _deploy_scanner_widget(self):
        """Deploy map_scanner.lua to BAR's widget directory."""
        if not MAP_SCANNER_SRC.exists():
            raise FileNotFoundError(f"Map scanner widget not found: {MAP_SCANNER_SRC}")

        dest = self.widget_dir / "map_scanner.lua"
        (self.write_dir / "headless" / "output").mkdir(parents=True, exist_ok=True)

        shutil.copy2(str(MAP_SCANNER_SRC), str(dest))
        print(f"[scan_map] Scanner widget deployed to {dest}")

        # Temporarily remove sim_executor to avoid conflicts
        sim_widget = self.widget_dir / "sim_executor.lua"
        self._sim_executor_backup = None
        if sim_widget.exists():
            backup = self.widget_dir / "sim_executor.lua.bak"
            shutil.move(str(sim_widget), str(backup))
            self._sim_executor_backup = backup

    def _remove_scanner_widget(self):
        """Clean up map_scanner.lua and restore sim_executor if backed up."""
        scanner = self.widget_dir / "map_scanner.lua"
        if scanner.exists():
            scanner.unlink()

        if getattr(self, "_sim_executor_backup", None) and self._sim_executor_backup.exists():
            dest = self.widget_dir / "sim_executor.lua"
            shutil.move(str(self._sim_executor_backup), str(dest))

    def _write_scan_startscript(self, map_name: str) -> Path:
        """Write a minimal startscript for map scanning."""
        content = STARTSCRIPT_TEMPLATE.format(
            map_name=map_name,
            game_type=self.game_type,
            side="Armada",
        )
        script_path = HEADLESS_DIR / "scan_startscript.txt"
        with open(script_path, "w") as f:
            f.write(content)
        return script_path

    def _translate_build_order(
        self, bo: BuildOrder, faction: str, duration_frames: int
    ) -> dict:
        """Convert a BuildOrder (short keys) to a JSON dict with game IDs."""
        ensure_db()
        alias_map = get_game_id_map(faction.upper())

        def translate_queue(actions, default_type="build"):
            result = []
            for action in actions:
                game_id = alias_map.get(action.unit_key)
                if not game_id:
                    print(f"[headless] WARNING: No game ID for '{action.unit_key}', skipping")
                    continue
                action_type = "produce" if action.action_type == BuildActionType.PRODUCE_UNIT else "build"
                result.append({"game_id": game_id, "type": action_type})
            return result

        bo_dict = {
            "name": bo.name,
            "faction": faction.lower(),
            "duration_frames": duration_frames,
            "map_mex_value": bo.map_config.mex_value,
            "commander_queue": translate_queue(bo.commander_queue),
            "factory_queues": {},
            "constructor_queues": {},
        }

        for fid, queue in bo.factory_queues.items():
            bo_dict["factory_queues"][fid] = translate_queue(queue, "produce")

        for cid, queue in bo.constructor_queues.items():
            bo_dict["constructor_queues"][cid] = translate_queue(queue, "build")

        return bo_dict

    def _write_build_order(self, bo_dict: dict):
        """Write build order JSON to the headless input directory."""
        # Write to both project dir and Spring write dir
        for base in [HEADLESS_DIR, self.write_dir / "headless"]:
            input_dir = base / "input"
            input_dir.mkdir(parents=True, exist_ok=True)
            path = input_dir / "build_order.json"
            with open(path, "w") as f:
                json.dump(bo_dict, f, indent=2)

    def _write_startscript(self, side: str) -> Path:
        """Write the startscript.txt for the engine."""
        content = STARTSCRIPT_TEMPLATE.format(
            map_name=self.map_name,
            game_type=self.game_type,
            side=side,
        )
        script_path = HEADLESS_DIR / "startscript.txt"
        with open(script_path, "w") as f:
            f.write(content)
        return script_path

    def _deploy_widget(self):
        """Copy sim_executor.lua to BAR's widget directory."""
        if not LUA_SRC.exists():
            raise FileNotFoundError(f"Lua widget not found: {LUA_SRC}")

        dest = self.widget_dir / "sim_executor.lua"

        # Also ensure the headless dirs exist in the Spring write dir
        (self.write_dir / "headless" / "input").mkdir(parents=True, exist_ok=True)
        (self.write_dir / "headless" / "output").mkdir(parents=True, exist_ok=True)

        # Only copy if source is newer or dest doesn't exist
        if not dest.exists() or os.path.getmtime(str(LUA_SRC)) > os.path.getmtime(str(dest)):
            shutil.copy2(str(LUA_SRC), str(dest))
            print(f"[headless] Widget deployed to {dest}")
        else:
            print(f"[headless] Widget already up-to-date at {dest}")

    def _run_engine(self, script_path: Path) -> Path:
        """Launch spring-headless.exe and wait for completion."""
        result_path = self.write_dir / "headless" / "output" / "sim_result.json"

        # Remove old results
        if result_path.exists():
            result_path.unlink()

        # Also check project-local output
        local_result = OUTPUT_DIR / "sim_result.json"
        if local_result.exists():
            local_result.unlink()

        cmd = [
            str(self.engine_exe),
            str(script_path),
        ]

        print(f"[headless] Launching: {' '.join(cmd)}")
        start_time = time.time()

        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.bar_data_dir),
                timeout=self.timeout,
                capture_output=True,
                text=True,
            )
            elapsed = time.time() - start_time
            print(f"[headless] Engine finished in {elapsed:.1f}s (exit code: {proc.returncode})")

            if proc.returncode != 0:
                # Print last few lines of output for debugging
                stderr_lines = (proc.stderr or "").strip().split("\n")[-10:]
                stdout_lines = (proc.stdout or "").strip().split("\n")[-10:]
                if stderr_lines:
                    print("[headless] stderr (last 10 lines):")
                    for line in stderr_lines:
                        print(f"  {line}")
                if stdout_lines:
                    print("[headless] stdout (last 10 lines):")
                    for line in stdout_lines:
                        print(f"  {line}")

        except subprocess.TimeoutExpired:
            print(f"[headless] ERROR: Engine timed out after {self.timeout}s")
            raise RuntimeError(f"Headless engine timed out after {self.timeout}s")

        # Check for result file
        if not result_path.exists():
            if local_result.exists():
                result_path = local_result
            else:
                raise RuntimeError(
                    f"No result file found at {result_path} or {local_result}. "
                    "The Lua widget may not have been loaded or may have errored."
                )

        return result_path

    def _parse_results(self, result_path: Path, bo_name: str, duration: int) -> SimResult:
        """Parse the Lua-written JSON into a SimResult dataclass."""
        with open(result_path, "r") as f:
            data = json.load(f)

        result = SimResult(
            build_order_name=data.get("build_order_name", bo_name),
            total_ticks=duration,
        )

        # Snapshots
        for s in data.get("snapshots", []):
            result.snapshots.append(Snapshot(
                tick=s.get("tick", 0),
                metal_income=s.get("metal_income", 0),
                energy_income=s.get("energy_income", 0),
                metal_stored=s.get("metal_stored", 0),
                energy_stored=s.get("energy_stored", 0),
                metal_expenditure=s.get("metal_expenditure", 0),
                energy_expenditure=s.get("energy_expenditure", 0),
                build_power=s.get("build_power", 0),
                army_value_metal=s.get("army_value_metal", 0),
                stall_factor=s.get("stall_factor", 1.0),
                unit_counts=s.get("unit_counts", {}),
            ))

        # Milestones
        for m in data.get("milestones", []):
            event = m.get("event", "")
            result.milestones.append(Milestone(
                tick=m.get("tick", 0),
                event=event,
                description=m.get("description", ""),
                metal_income=m.get("metal_income", 0),
                energy_income=m.get("energy_income", 0),
            ))
            # Set convenience fields
            if event == "first_factory":
                result.time_to_first_factory = m.get("tick", 0)
            elif event == "first_constructor":
                result.time_to_first_constructor = m.get("tick", 0)
            elif event == "first_nano":
                result.time_to_first_nano = m.get("tick", 0)
            elif event == "first_t2_lab":
                result.time_to_t2_lab = m.get("tick", 0)

        # Stall events
        for s in data.get("stall_events", []):
            result.stall_events.append(StallEvent(
                start_tick=s.get("start_tick", 0),
                end_tick=s.get("end_tick", 0),
                resource=s.get("resource", "metal"),
                severity=s.get("severity", 0),
            ))

        # Completion log
        for c in data.get("completion_log", []):
            frame = c.get("frame", 0)
            tick = frame // 30 if isinstance(frame, int) else 0
            result.completion_log.append((
                tick,
                c.get("game_id", ""),
                c.get("builder_type", ""),
            ))

        # Summary stats
        result.peak_metal_income = data.get("peak_metal_income", 0)
        result.peak_energy_income = data.get("peak_energy_income", 0)
        result.total_metal_stall_seconds = data.get("total_metal_stall_seconds", 0)
        result.total_energy_stall_seconds = data.get("total_energy_stall_seconds", 0)
        result.total_army_metal_value = data.get("total_army_metal_value", 0)

        return result
