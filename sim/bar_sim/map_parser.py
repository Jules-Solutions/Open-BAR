"""
BAR Map Parser - Extract map metadata from BAR data files
==========================================================
Parses ArchiveCache20.lua for basic map metadata, and extracts
mapinfo.lua from .sd7 archives for wind, start positions, etc.
"""

import os
import re
import tempfile
from pathlib import Path
from typing import Optional

from bar_sim.models import MapData, StartPosition

# ---------------------------------------------------------------------------
# Path detection (reuse headless.py patterns)
# ---------------------------------------------------------------------------

_BAR_INSTALL_CANDIDATES = [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Beyond-All-Reason" / "data",
    Path("C:/Program Files/Beyond-All-Reason/data"),
    Path("C:/Program Files (x86)/Beyond-All-Reason/data"),
    Path.home() / "Beyond-All-Reason" / "data",
]


def find_bar_data_dir() -> Optional[Path]:
    env_path = os.environ.get("BAR_DATA_DIR")
    if env_path:
        p = Path(env_path)
        if p.exists():
            return p
    for candidate in _BAR_INSTALL_CANDIDATES:
        if candidate.exists():
            return candidate
    return None


def find_archive_cache() -> Optional[Path]:
    """Locate ArchiveCache20.lua on disk."""
    data_dir = find_bar_data_dir()
    if not data_dir:
        return None
    cache = data_dir / "cache" / "ArchiveCache20.lua"
    return cache if cache.exists() else None


def find_maps_dir() -> Optional[Path]:
    """Locate the maps directory containing .sd7 files."""
    data_dir = find_bar_data_dir()
    if not data_dir:
        return None
    maps_dir = data_dir / "maps"
    return maps_dir if maps_dir.exists() else None


# ---------------------------------------------------------------------------
# ArchiveCache20.lua parsing
# ---------------------------------------------------------------------------

def parse_archive_cache(cache_path: Path = None) -> list[dict]:
    """Parse ArchiveCache20.lua and return map entries (modtype=3).

    The file is machine-generated Lua with a very consistent format.
    We split on archive blocks and extract key-value pairs with regex.
    """
    if cache_path is None:
        cache_path = find_archive_cache()
    if not cache_path or not cache_path.exists():
        return []

    content = cache_path.read_text(encoding="utf-8", errors="replace")

    # Split into archive blocks (each starts with { and has archivedata)
    # Pattern: each block starts after "archives = {" or after "},\n\t\t{"
    blocks = re.split(r'\n\t\t\{', content)

    maps = []
    for block in blocks:
        # Only process map entries (modtype = 3)
        if "modtype = 3" not in block:
            continue

        entry = {}

        # Top-level fields: name (filename), path
        m = re.search(r'^\s*name\s*=\s*"([^"]+)"', block, re.MULTILINE)
        if m:
            entry["filename"] = m.group(1)

        # archivedata fields
        def extract_str(key):
            m = re.search(rf'{key}\s*=\s*"([^"]*)"', block)
            return m.group(1) if m else ""

        def extract_num(key):
            m = re.search(rf'{key}\s*=\s*([\d.+-]+)', block)
            if m:
                try:
                    return float(m.group(1))
                except ValueError:
                    return 0.0
            return 0.0

        def extract_bool(key):
            m = re.search(rf'{key}\s*=\s*(true|false)', block)
            return m.group(1) == "true" if m else False

        entry["name"] = extract_str("name_pure") or extract_str(r"\bname")
        entry["shortname"] = extract_str("shortname")
        entry["author"] = extract_str("author")
        entry["description"] = extract_str("description")
        entry["version"] = extract_str("version")
        entry["mapfile"] = extract_str("mapfile")

        entry["max_metal"] = extract_num("maxmetal")
        entry["tidal_strength"] = extract_num("tidalstrength")
        entry["gravity"] = extract_num("gravity")
        entry["extractor_radius"] = extract_num("extractorradius")
        entry["maphardness"] = extract_num("maphardness")

        entry["autoshowmetal"] = extract_bool("autoshowmetal")
        entry["voidground"] = extract_bool("voidground")
        entry["voidwater"] = extract_bool("voidwater")

        if entry.get("filename"):
            maps.append(entry)

    return maps


# ---------------------------------------------------------------------------
# mapinfo.lua extraction from .sd7
# ---------------------------------------------------------------------------

def extract_mapinfo_lua(sd7_path: Path) -> Optional[str]:
    """Extract mapinfo.lua content from a .sd7 archive.

    Uses py7zr for selective extraction (only the small text file).
    Returns the file content as string, or None if not found.
    """
    try:
        import py7zr
    except ImportError:
        return None

    if not sd7_path.exists():
        return None

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            with py7zr.SevenZipFile(str(sd7_path), "r") as z:
                names = z.getnames()
                if "mapinfo.lua" not in names:
                    return None
                z.extract(tmpdir, targets=["mapinfo.lua"])
            mapinfo_path = Path(tmpdir) / "mapinfo.lua"
            if mapinfo_path.exists():
                return mapinfo_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"[map_parser] Error extracting mapinfo.lua from {sd7_path}: {e}")

    return None


def parse_mapinfo_lua(content: str) -> dict:
    """Parse mapinfo.lua content to extract wind, start positions, etc.

    Returns dict with: wind_min, wind_max, start_positions, gravity,
    tidal_strength, max_metal, extractor_radius.
    """
    result = {}

    # Wind: atmosphere.minWind / atmosphere.maxWind
    m = re.search(r'minWind\s*=\s*([\d.]+)', content)
    if m:
        result["wind_min"] = float(m.group(1))
    m = re.search(r'maxWind\s*=\s*([\d.]+)', content)
    if m:
        result["wind_max"] = float(m.group(1))

    # Start positions: teams = { [0] = {startPos = {x = 819, z = 1044}}, ... }
    positions = []
    for m in re.finditer(
        r'\[(\d+)\]\s*=\s*\{startPos\s*=\s*\{x\s*=\s*([\d.]+)\s*,\s*z\s*=\s*([\d.]+)\s*\}\}',
        content,
    ):
        positions.append(StartPosition(
            x=float(m.group(2)),
            z=float(m.group(3)),
            team_id=int(m.group(1)),
        ))
    if positions:
        result["start_positions"] = positions

    # Other fields that might override cache values
    m = re.search(r'gravity\s*=\s*([\d.]+)', content)
    if m:
        result["gravity"] = float(m.group(1))
    m = re.search(r'tidalStrength\s*=\s*([\d.]+)', content)
    if m:
        result["tidal_strength"] = float(m.group(1))
    m = re.search(r'maxMetal\s*=\s*([\d.]+)', content)
    if m:
        result["max_metal"] = float(m.group(1))
    m = re.search(r'extractorRadius\s*=\s*([\d.]+)', content)
    if m:
        result["extractor_radius"] = float(m.group(1))

    return result


# ---------------------------------------------------------------------------
# Combined metadata
# ---------------------------------------------------------------------------

def build_map_metadata(filename: str) -> Optional[MapData]:
    """Build MapData from archive cache + mapinfo.lua (no runtime scan).

    Gives us everything except mex spot locations and geo vents.
    """
    cache_entries = parse_archive_cache()
    entry = None
    filename_lower = filename.lower()

    for e in cache_entries:
        fn = e.get("filename", "")
        # Match by filename (with or without .sd7)
        if fn.lower() == filename_lower or fn.lower() == filename_lower + ".sd7":
            entry = e
            break
        # Match by name or shortname
        name_lower = e.get("name", "").lower().replace(" ", "_")
        short_lower = e.get("shortname", "").lower()
        if filename_lower in (name_lower, short_lower):
            entry = e
            break

    if not entry:
        return None

    sd7_filename = entry["filename"]
    md = MapData(
        name=entry.get("name", sd7_filename),
        filename=sd7_filename,
        shortname=entry.get("shortname", ""),
        max_metal=entry.get("max_metal", 2.0),
        tidal_strength=entry.get("tidal_strength", 0.0),
        gravity=entry.get("gravity", 100.0),
        extractor_radius=entry.get("extractor_radius", 90.0),
        author=entry.get("author", ""),
        description=entry.get("description", ""),
        source="cache",
    )

    # Try to extract mapinfo.lua for wind + start positions
    maps_dir = find_maps_dir()
    if maps_dir:
        sd7_path = maps_dir / sd7_filename
        mapinfo_content = extract_mapinfo_lua(sd7_path)
        if mapinfo_content:
            info = parse_mapinfo_lua(mapinfo_content)
            if "wind_min" in info:
                md.wind_min = info["wind_min"]
            if "wind_max" in info:
                md.wind_max = info["wind_max"]
            if "start_positions" in info:
                md.start_positions = info["start_positions"]
            if "gravity" in info:
                md.gravity = info["gravity"]
            if "tidal_strength" in info:
                md.tidal_strength = info["tidal_strength"]
            if "max_metal" in info:
                md.max_metal = info["max_metal"]
            if "extractor_radius" in info:
                md.extractor_radius = info["extractor_radius"]
            md.source = "mapinfo"

    return md


def list_available_maps() -> list[dict]:
    """Return list of all maps with basic metadata from archive cache."""
    entries = parse_archive_cache()
    result = []
    for e in entries:
        result.append({
            "filename": e.get("filename", ""),
            "name": e.get("name", ""),
            "shortname": e.get("shortname", ""),
            "author": e.get("author", ""),
            "max_metal": e.get("max_metal", 0),
            "tidal_strength": e.get("tidal_strength", 0),
            "extractor_radius": e.get("extractor_radius", 0),
        })
    return sorted(result, key=lambda x: x["name"].lower())


def map_name_to_filename(query: str) -> Optional[str]:
    """Fuzzy match a map name/query to its .sd7 filename.

    Tries: exact filename, case-insensitive match, contains match.
    """
    entries = parse_archive_cache()
    query_lower = query.lower().replace(" ", "_")

    # Strip .sd7 if present
    if query_lower.endswith(".sd7"):
        query_lower = query_lower[:-4]

    # Exact filename match
    for e in entries:
        fn = e["filename"].lower()
        if fn == query_lower + ".sd7" or fn == query_lower:
            return e["filename"]

    # Name or shortname match
    for e in entries:
        name = e.get("name", "").lower().replace(" ", "_")
        short = e.get("shortname", "").lower()
        if query_lower == name or query_lower == short:
            return e["filename"]

    # Contains match (partial)
    matches = []
    for e in entries:
        fn = e["filename"].lower()
        name = e.get("name", "").lower()
        if query_lower in fn or query_lower in name:
            matches.append(e["filename"])

    if len(matches) == 1:
        return matches[0]
    elif matches:
        # Return shortest match (most specific)
        return min(matches, key=len)

    return None
