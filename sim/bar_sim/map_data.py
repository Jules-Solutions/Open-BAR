"""
BAR Map Data - Cache management and mex assignment
====================================================
Manages cached MapData JSON files and provides the MapData -> MapConfig
bridge with Voronoi-style mex spot partitioning.
"""

import json
import math
from pathlib import Path
from typing import Optional

from bar_sim.models import (
    MapConfig, MapData, MexSpot, GeoVent, StartPosition,
)

MAPS_DATA_DIR = Path(__file__).parent.parent / "data" / "maps"


# ---------------------------------------------------------------------------
# Cache I/O
# ---------------------------------------------------------------------------

def save_map_cache(map_data: MapData) -> Path:
    """Serialize MapData to JSON in data/maps/."""
    MAPS_DATA_DIR.mkdir(parents=True, exist_ok=True)

    stem = map_data.filename.replace(".sd7", "")
    path = MAPS_DATA_DIR / f"{stem}.json"

    data = {
        "name": map_data.name,
        "filename": map_data.filename,
        "shortname": map_data.shortname,
        "map_width": map_data.map_width,
        "map_height": map_data.map_height,
        "wind_min": map_data.wind_min,
        "wind_max": map_data.wind_max,
        "tidal_strength": map_data.tidal_strength,
        "gravity": map_data.gravity,
        "max_metal": map_data.max_metal,
        "extractor_radius": map_data.extractor_radius,
        "start_positions": [
            {"x": sp.x, "z": sp.z, "team_id": sp.team_id}
            for sp in map_data.start_positions
        ],
        "mex_spots": [
            {"x": ms.x, "z": ms.z, "metal": ms.metal}
            for ms in map_data.mex_spots
        ],
        "geo_vents": [
            {"x": gv.x, "z": gv.z}
            for gv in map_data.geo_vents
        ],
        "total_reclaim_metal": map_data.total_reclaim_metal,
        "total_reclaim_energy": map_data.total_reclaim_energy,
        "author": map_data.author,
        "description": map_data.description,
        "source": map_data.source,
    }

    with open(path, "w") as f:
        json.dump(data, f, indent=2)

    return path


def load_map_cache(map_name: str) -> Optional[MapData]:
    """Load cached MapData JSON. Returns None if not cached."""
    from bar_sim.map_parser import map_name_to_filename

    # Try direct filename match first
    stem = map_name.replace(".sd7", "")
    path = MAPS_DATA_DIR / f"{stem}.json"

    if not path.exists():
        # Try fuzzy filename resolution
        filename = map_name_to_filename(map_name)
        if filename:
            stem = filename.replace(".sd7", "")
            path = MAPS_DATA_DIR / f"{stem}.json"

    if not path.exists():
        return None

    with open(path, "r") as f:
        data = json.load(f)

    return MapData(
        name=data["name"],
        filename=data["filename"],
        shortname=data.get("shortname", ""),
        map_width=data.get("map_width", 0),
        map_height=data.get("map_height", 0),
        wind_min=data.get("wind_min", 0.0),
        wind_max=data.get("wind_max", 25.0),
        tidal_strength=data.get("tidal_strength", 0.0),
        gravity=data.get("gravity", 100.0),
        max_metal=data.get("max_metal", 2.0),
        extractor_radius=data.get("extractor_radius", 90.0),
        start_positions=[
            StartPosition(x=sp["x"], z=sp["z"], team_id=sp.get("team_id", 0))
            for sp in data.get("start_positions", [])
        ],
        mex_spots=[
            MexSpot(x=ms["x"], z=ms["z"], metal=ms.get("metal", 2.0))
            for ms in data.get("mex_spots", [])
        ],
        geo_vents=[
            GeoVent(x=gv["x"], z=gv["z"])
            for gv in data.get("geo_vents", [])
        ],
        total_reclaim_metal=data.get("total_reclaim_metal", 0.0),
        total_reclaim_energy=data.get("total_reclaim_energy", 0.0),
        author=data.get("author", ""),
        description=data.get("description", ""),
        source=data.get("source", "cached"),
    )


def list_cached_maps() -> list[str]:
    """Return list of map names that have been scanned/cached."""
    if not MAPS_DATA_DIR.exists():
        return []
    return sorted(p.stem for p in MAPS_DATA_DIR.glob("*.json"))


# ---------------------------------------------------------------------------
# Map data retrieval (cache + fallback to parser)
# ---------------------------------------------------------------------------

def get_map_data(map_name: str, scan_if_missing: bool = False) -> Optional[MapData]:
    """Load MapData from cache, falling back to static parse.

    If scan_if_missing=True and cache doesn't have mex spots,
    triggers a headless scan (blocking, ~3-5s).
    """
    # Try cache first (has mex spots from scanner)
    cached = load_map_cache(map_name)
    if cached and cached.mex_spots:
        return cached

    # Fall back to static metadata (no mex spots)
    from bar_sim.map_parser import build_map_metadata, map_name_to_filename
    filename = map_name_to_filename(map_name)
    if filename:
        md = build_map_metadata(filename.replace(".sd7", ""))
    else:
        md = build_map_metadata(map_name)

    if not md:
        return cached  # return cache even without mex spots

    # Merge: if cache had some data, keep it; update from static parse
    if cached:
        # Cache is newer, but might be missing wind data
        if cached.wind_min == 0 and cached.wind_max == 25.0 and md.wind_min > 0:
            cached.wind_min = md.wind_min
            cached.wind_max = md.wind_max
        if not cached.start_positions and md.start_positions:
            cached.start_positions = md.start_positions
        return cached

    # Trigger headless scan if requested and we don't have mex spots
    if scan_if_missing and not md.mex_spots:
        try:
            from bar_sim.headless import HeadlessEngine
            engine = HeadlessEngine(map_name=md.filename.replace(".sd7", ""))
            return engine.scan_map(md.filename.replace(".sd7", ""))
        except Exception as e:
            print(f"[map_data] Scan failed: {e}")

    return md


# ---------------------------------------------------------------------------
# Mex assignment (Voronoi partition)
# ---------------------------------------------------------------------------

def assign_mex_spots(
    mex_spots: list[MexSpot],
    start_positions: list[StartPosition],
    player_team: int = 0,
) -> list[MexSpot]:
    """Voronoi-style mex assignment: each spot goes to nearest start position.

    Returns only the spots assigned to player_team, sorted by distance
    from the player's start position (closest first).
    """
    if not mex_spots or not start_positions:
        return list(mex_spots)

    # Find player's start position
    player_start = None
    for sp in start_positions:
        if sp.team_id == player_team:
            player_start = sp
            break
    if not player_start:
        player_start = start_positions[0]

    my_spots = []
    for spot in mex_spots:
        # Find nearest start position
        nearest = min(
            start_positions,
            key=lambda sp: (sp.x - spot.x) ** 2 + (sp.z - spot.z) ** 2,
        )
        if nearest.team_id == player_team:
            my_spots.append(spot)

    # Sort by distance from player start (closest first)
    my_spots.sort(
        key=lambda s: (s.x - player_start.x) ** 2 + (s.z - player_start.z) ** 2
    )

    return my_spots


# ---------------------------------------------------------------------------
# MapData -> MapConfig conversion
# ---------------------------------------------------------------------------

def map_data_to_map_config(
    map_data: MapData,
    player_team: int = 0,
    num_players: int = 2,
) -> MapConfig:
    """Convert MapData to MapConfig for the simulation engine.

    Uses assign_mex_spots() to determine how many spots belong to the player.
    """
    avg_wind = (map_data.wind_min + map_data.wind_max) / 2
    wind_variance = (map_data.wind_max - map_data.wind_min) / 2

    # Determine mex spots for this player
    if map_data.mex_spots and map_data.start_positions:
        # Use only start positions for the number of players in game
        active_starts = map_data.start_positions[:num_players]
        my_mexes = assign_mex_spots(map_data.mex_spots, active_starts, player_team)
        mex_count = len(my_mexes)
    elif map_data.mex_spots:
        # No start positions: divide evenly
        mex_count = len(map_data.mex_spots) // max(1, num_players)
    else:
        mex_count = 6  # default fallback

    # Check for nearby geo vents
    has_geo = len(map_data.geo_vents) > 0

    return MapConfig(
        avg_wind=round(avg_wind, 1),
        wind_variance=round(wind_variance, 1),
        mex_value=map_data.max_metal,
        mex_spots=mex_count,
        has_geo=has_geo,
        tidal_value=map_data.tidal_strength,
        reclaim_metal=map_data.total_reclaim_metal / max(1, num_players),
    )
