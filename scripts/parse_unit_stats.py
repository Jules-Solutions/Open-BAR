"""
BAR Unit Stats Parser for Dodge Widget Redesign
=================================================
Parses all BAR unit definition Lua files and produces comprehensive
statistics for projectile dodging physics simulation.

Output: formatted tables to stdout + JSON at docs/dodge_unit_stats.json
"""

import json
import os
import re
import statistics
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

UNITS_DIR = Path(r"C:\Jules.Life\Projects\TheLab\Experiments\BAR\Prod\Beyond-All-Reason\units")
OUTPUT_JSON = Path(r"C:\Jules.Life\Projects\TheLab\Experiments\BAR\docs\dodge_unit_stats.json")

# Spring Engine turnrate conversion:
# turnrate is in "angular units per game frame"
# 65536 angular units = 360 degrees, game runs at 30 fps
# So: degrees_per_sec = turnrate * (360 / 65536) * 30
GAME_FPS = 30
SPRING_TURNRATE_TO_DEG_S = (360.0 / 65536.0) * GAME_FPS
FOOTPRINT_ELMO_SIZE = 8  # each footprint square is 8x8 elmos

# Movement class classification
# Spring movementclass strings can have prefixes and numeric suffixes.
# We match keywords in order of specificity (longest first).
# The keyword must appear as a substring in the uppercase movementclass string.
MOVEMENT_CLASS_KEYWORDS = [
    # Most specific first
    ("ALLTERRAIN", "Hover"),     # raptor/scav all-terrain units
    ("EPICSUBMARINE", "Ship"),
    ("EPICSHIP",  "Gantry/T3"),
    ("EPICVEH",   "Gantry/T3"),
    ("EPICBOT",   "Gantry/T3"),
    ("EPIC",      "Gantry/T3"),
    # Hover before BOT/TANK (HOVER appears in RAPTORSMALLHOVER etc.)
    ("HOVER",     "Hover"),
    # Submarines
    ("UBOAT",     "Ship"),
    ("SUBMARINE", "Ship"),
    # Ships/boats
    ("BOAT",      "Ship"),
    ("SHIP",      "Ship"),
    # Vehicles/tanks
    ("TANK",      "Vehicle"),
    ("VEH",       "Vehicle"),
    # Commander
    ("COMMANDER", "Bot"),
    # Nano constructors
    ("NANO",      "Bot"),
    # Bots last (BOT appears in many prefixed names like HABOT, SBOT, TBOT, etc.)
    ("BOT",       "Bot"),
]

# Weapon types that are relevant for dodging analysis
# (excluding Shield, DGun, Melee which don't produce projectiles to dodge)
PROJECTILE_WEAPON_TYPES = {
    "Cannon", "MissileLauncher", "BeamLaser", "LaserCannon",
    "StarburstLauncher", "LightningCannon", "Flame",
    "TorpedoLauncher", "AircraftBomb",
}

# Test ranges for cross-reference dodge analysis
TEST_RANGES = [100, 200, 300, 500, 800]

# Reference dodger profiles
REFERENCE_DODGERS = {
    "Fast Bot (PW)":    {"speed": 87.0, "turnrate": 1214.4, "name": "armpw"},
    "Medium Tank":      {"speed": 75.9, "turnrate": 340.0, "name": "armstump"},
    "Fast Hover":       {"speed": 113.7, "turnrate": 640.0, "name": "armsh"},
    "Slow Heavy":       {"speed": 45.6, "turnrate": 1214.4, "name": "armbanth"},
}


# ---------------------------------------------------------------------------
# Lua Parser (regex-based)
# ---------------------------------------------------------------------------

def parse_lua_value(text: str) -> str | float | bool | None:
    """Parse a single Lua value from a string."""
    text = text.strip().rstrip(",")
    # String
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    # Boolean
    if text == "true":
        return True
    if text == "false":
        return False
    # Number
    try:
        return float(text)
    except ValueError:
        return text


def extract_top_level_block(content: str) -> str:
    """
    Extract only the top-level key=value assignments from a Lua table block,
    stopping when we hit known nested tables (featuredefs, sfxtypes, sounds,
    customparams, weapondefs, weapons).

    This avoids picking up values from deeply nested sub-tables like
    featuredefs.dead.collisionvolumescales.
    """
    lines = content.split("\n")
    result_lines = []
    depth = 0
    in_nested = False
    # Known nested table names that we want to skip for flat key extraction
    nested_tables = {
        "featuredefs", "sfxtypes", "sounds", "customparams",
        "weapondefs", "weapons",
    }

    for line in lines:
        stripped = line.strip()

        # Track brace depth to know if we're inside a nested table
        if in_nested:
            depth += stripped.count("{") - stripped.count("}")
            if depth <= 0:
                in_nested = False
                depth = 0
            continue

        # Check if this line starts a nested table we want to skip
        match = re.match(r'(\w+)\s*=\s*\{', stripped)
        if match:
            tname = match.group(1).lower()
            if tname in nested_tables:
                in_nested = True
                # Count braces on this line
                depth = stripped.count("{") - stripped.count("}")
                if depth <= 0:
                    in_nested = False
                    depth = 0
                continue

        result_lines.append(line)

    return "\n".join(result_lines)


def parse_lua_flat_keys(content: str) -> dict:
    """
    Extract key = value pairs from the top level of a Lua table.
    Filters out nested tables first to avoid picking up deep values.
    Returns a flat dict of top-level keys and their values.
    """
    # First extract only top-level content
    top_content = extract_top_level_block(content)

    result = {}
    # Match simple key = value (not nested tables)
    for m in re.finditer(r'^\s*(\w+)\s*=\s*([^,{}\n]+)', top_content, re.MULTILINE):
        key = m.group(1).lower()
        val = parse_lua_value(m.group(2))
        result[key] = val
    return result


def extract_weapondefs(content: str) -> list[dict]:
    """
    Extract all weapon definitions from a unit's Lua content.
    Returns a list of weapon stat dicts.
    """
    weapons = []

    # Find the weapondefs block
    wdefs_match = re.search(r'weapondefs\s*=\s*\{', content)
    if not wdefs_match:
        return weapons

    start = wdefs_match.end()
    # Find each weapon definition inside weapondefs
    # Pattern: weaponname = { ... }
    depth = 1
    pos = start
    while pos < len(content) and depth > 0:
        if content[pos] == '{':
            depth += 1
        elif content[pos] == '}':
            depth -= 1
        pos += 1

    weapondefs_block = content[start:pos - 1]

    # Now find each named weapon inside weapondefs
    # We only match names at the first indent level inside weapondefs (depth 0)
    # This avoids matching sub-tables like damage, customparams, badcolor, etc.
    weapon_starts = []
    scan_pos = 0
    scan_depth = 0

    while scan_pos < len(weapondefs_block):
        ch = weapondefs_block[scan_pos]
        if ch == '{':
            scan_depth += 1
        elif ch == '}':
            scan_depth -= 1
        elif scan_depth == 0:
            # At top level of weapondefs - check for name = {
            m = re.match(r'(\w+)\s*=\s*\{', weapondefs_block[scan_pos:])
            if m:
                weapon_starts.append((m.group(1).lower(), scan_pos + m.end()))
                scan_depth = 1  # we just entered this weapon's block
                scan_pos += m.end()
                continue
        scan_pos += 1

    for idx, (wname, wstart) in enumerate(weapon_starts):
        # Find the end of this weapon block
        wdepth = 1
        wpos = wstart
        while wpos < len(weapondefs_block) and wdepth > 0:
            if weapondefs_block[wpos] == '{':
                wdepth += 1
            elif weapondefs_block[wpos] == '}':
                wdepth -= 1
            wpos += 1

        weapon_block = weapondefs_block[wstart:wpos - 1]
        wstats = parse_lua_flat_keys(weapon_block)
        wstats["_weapon_name"] = wname

        # Extract damage.default
        dmg_match = re.search(r'damage\s*=\s*\{([^}]+)\}', weapon_block)
        if dmg_match:
            dmg_block = dmg_match.group(1)
            for dm in re.finditer(r'(\w+)\s*=\s*([\d.]+)', dmg_block):
                if dm.group(1).lower() == "default":
                    wstats["damage_default"] = float(dm.group(2))

        weapons.append(wstats)

    return weapons


def parse_unit_file(filepath: Path) -> list[dict]:
    """
    Parse a Lua unit definition file.
    Returns a list of unit dicts (usually 1, but can be multiple).
    """
    try:
        text = filepath.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []

    units = []

    # Determine faction from directory path
    path_str = str(filepath).replace("\\", "/")
    faction = "Unknown"
    if "/Arm" in path_str or "arm" in filepath.name[:3]:
        faction = "Armada"
    elif "/Cor" in path_str or "cor" in filepath.name[:3]:
        faction = "Cortex"
    elif "/Legion" in path_str or "leg" in filepath.name[:3]:
        faction = "Legion"

    # Determine directory-based class hint
    dir_class = "Unknown"
    for dirname in ["Bots", "Vehicles", "Hovercraft", "Ships", "Gantry",
                     "Aircraft", "Buildings", "Seaplanes", "SeaDefense",
                     "SeaDefences", "Constructors", "Economy", "Labs",
                     "Defenses", "SeaEconomy", "SeaUtility", "Utilities",
                     "Other", "T3"]:
        if dirname.lower() in path_str.lower():
            dir_class = dirname
            break

    # Find all top-level unit definitions: unitname = { ... }
    # The file starts with "return {" and has unitname = { ... } inside
    # Find unit name blocks
    unit_name_pattern = re.compile(r'^\t(\w+)\s*=\s*\{', re.MULTILINE)
    for um in unit_name_pattern.finditer(text):
        uname = um.group(1).lower()
        ustart = um.end()

        # Find the matching closing brace at depth 1
        depth = 1
        pos = ustart
        while pos < len(text) and depth > 0:
            if text[pos] == '{':
                depth += 1
            elif text[pos] == '}':
                depth -= 1
            pos += 1

        unit_block = text[ustart:pos - 1]

        # Parse flat keys
        unit_data = parse_lua_flat_keys(unit_block)
        unit_data["_name"] = uname
        unit_data["_faction"] = faction
        unit_data["_dir_class"] = dir_class
        unit_data["_filepath"] = str(filepath)

        # Parse collision volume scales
        cvs = unit_data.get("collisionvolumescales")
        if cvs and isinstance(cvs, str):
            parts = cvs.strip('"').split()
            if len(parts) == 3:
                try:
                    unit_data["_cvs_x"] = float(parts[0])
                    unit_data["_cvs_y"] = float(parts[1])
                    unit_data["_cvs_z"] = float(parts[2])
                except ValueError:
                    pass

        # Parse subfolder from customparams
        sf_match = re.search(r'subfolder\s*=\s*"([^"]+)"', unit_block)
        if sf_match:
            unit_data["_subfolder"] = sf_match.group(1)

        # Determine unit class from movementclass
        mc = unit_data.get("movementclass", "")
        if isinstance(mc, str) and mc:
            unit_data["_unit_class"] = classify_movement(mc)
        else:
            unit_data["_unit_class"] = "Unknown"

        # Override with Gantry/T3 if in gantry folder or techlevel=3 or T3 folder
        techlevel_match = re.search(r'techlevel\s*=\s*(\d+)', unit_block)
        if techlevel_match and int(techlevel_match.group(1)) == 3:
            unit_data["_unit_class"] = "Gantry/T3"
        elif "gantry" in path_str.lower() or "/t3/" in path_str.lower():
            unit_data["_unit_class"] = "Gantry/T3"

        # Check if building
        is_building = False
        if "yardmap" in unit_data:
            is_building = True
        if unit_data.get("maxacc", -1) == 0 and unit_data.get("speed", 0) == 0:
            is_building = True
        # No movementclass = likely building
        if not unit_data.get("movementclass"):
            is_building = True
        unit_data["_is_building"] = is_building

        # Check if aircraft
        is_aircraft = "aircraft" in path_str.lower() or "seaplane" in path_str.lower()
        if isinstance(mc, str) and mc.upper().startswith("AIR"):
            is_aircraft = True
        unit_data["_is_aircraft"] = is_aircraft

        # Check if mobile
        can_move = unit_data.get("canmove", False)
        speed = unit_data.get("speed", 0)
        if isinstance(speed, str):
            try:
                speed = float(speed)
            except ValueError:
                speed = 0
        unit_data["_is_mobile"] = bool(can_move) and speed > 0 and not is_building

        # Parse weapons
        unit_data["_weapons"] = extract_weapondefs(unit_block)

        units.append(unit_data)

    return units


# ---------------------------------------------------------------------------
# Statistics helpers
# ---------------------------------------------------------------------------

def safe_stats(values: list[float]) -> dict:
    """Compute min, avg, max, median for a list of floats."""
    if not values:
        return {"min": None, "avg": None, "max": None, "median": None, "count": 0}
    return {
        "min": round(min(values), 3),
        "avg": round(statistics.mean(values), 3),
        "max": round(max(values), 3),
        "median": round(statistics.median(values), 3),
        "count": len(values),
    }


def classify_movement(movementclass: str) -> str:
    """Map a movementclass string to a readable class name using keyword matching."""
    if not movementclass or not isinstance(movementclass, str):
        return "Unknown"
    mc = movementclass.upper()
    for keyword, cls in MOVEMENT_CLASS_KEYWORDS:
        if keyword in mc:
            return cls
    return "Unknown"


# ---------------------------------------------------------------------------
# Table formatting
# ---------------------------------------------------------------------------

def print_divider(width: int = 120):
    print("=" * width)


def print_header(title: str, width: int = 120):
    print()
    print_divider(width)
    print(f"  {title}")
    print_divider(width)


def format_table(headers: list[str], rows: list[list], col_widths: list[int] | None = None):
    """Print a formatted table."""
    if not col_widths:
        col_widths = []
        for i, h in enumerate(headers):
            max_w = len(str(h))
            for row in rows:
                if i < len(row):
                    max_w = max(max_w, len(str(row[i])))
            col_widths.append(min(max_w + 2, 30))

    # Header
    header_line = ""
    for i, h in enumerate(headers):
        header_line += str(h).ljust(col_widths[i])
    print(header_line)
    print("-" * sum(col_widths))

    # Rows
    for row in rows:
        line = ""
        for i, val in enumerate(row):
            if i < len(col_widths):
                line += str(val).ljust(col_widths[i])
        print(line)


def fmt(val, decimals=2) -> str:
    """Format a numeric value."""
    if val is None:
        return "N/A"
    if isinstance(val, float):
        return f"{val:.{decimals}f}"
    return str(val)


# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def main():
    # -----------------------------------------------------------------------
    # Phase 1: Parse all files
    # -----------------------------------------------------------------------
    print("Scanning unit files...")
    all_units = []
    lua_files = list(UNITS_DIR.rglob("*.lua"))
    print(f"Found {len(lua_files)} Lua files")

    for fp in lua_files:
        parsed = parse_unit_file(fp)
        all_units.extend(parsed)

    print(f"Parsed {len(all_units)} unit definitions")

    # Separate mobile ground/hover/ship units vs buildings
    mobile_units = [u for u in all_units if u.get("_is_mobile") and not u.get("_is_aircraft")]
    buildings = [u for u in all_units if u.get("_is_building")]
    aircraft = [u for u in all_units if u.get("_is_aircraft")]

    # Count categories (they can overlap, so compute exclusive counts)
    mobile_only = [u for u in all_units if u.get("_is_mobile") and not u.get("_is_aircraft")]
    building_only = [u for u in all_units if u.get("_is_building") and not u.get("_is_mobile") and not u.get("_is_aircraft")]
    aircraft_only = [u for u in all_units if u.get("_is_aircraft")]
    other = [u for u in all_units
             if not u.get("_is_mobile") and not u.get("_is_building") and not u.get("_is_aircraft")]

    print(f"  Mobile ground/hover/ship: {len(mobile_units)}")
    print(f"  Buildings/turrets:        {len(buildings)} ({len(building_only)} exclusive)")
    print(f"  Aircraft:                 {len(aircraft)}")
    print(f"  Uncategorized:            {len(other)}")

    # -----------------------------------------------------------------------
    # Phase 2: Compute stats for mobile units
    # -----------------------------------------------------------------------

    # Group by faction + class
    groups: dict[str, list[dict]] = defaultdict(list)
    for u in mobile_units:
        faction = u.get("_faction", "Unknown")
        unit_class = u.get("_unit_class", "Unknown")
        key = f"{faction} | {unit_class}"
        groups[key].append(u)

    # Also keep "All" groups
    for u in mobile_units:
        groups[f"ALL | {u.get('_unit_class', 'Unknown')}"].append(u)
        groups[f"{u.get('_faction', 'Unknown')} | ALL"].append(u)
        groups["ALL | ALL"].append(u)

    # -----------------------------------------------------------------------
    # Stat 1: Footprint Area
    # -----------------------------------------------------------------------
    print_header("1. UNIT FOOTPRINT AREA (Mobile Non-Aircraft)")

    headers = ["Group", "Count", "FPx min", "FPx max", "FPz min", "FPz max",
               "Area(elmo2) min", "Area avg", "Area max", "Area median"]
    rows = []

    footprint_data = {}
    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        fpx_vals = [u.get("footprintx", 0) for u in gunits if u.get("footprintx")]
        fpz_vals = [u.get("footprintz", 0) for u in gunits if u.get("footprintz")]
        area_vals = [
            u.get("footprintx", 0) * u.get("footprintz", 0) * (FOOTPRINT_ELMO_SIZE ** 2)
            for u in gunits
            if u.get("footprintx") and u.get("footprintz")
        ]
        s = safe_stats(area_vals)
        footprint_data[gname] = s
        rows.append([
            gname, len(gunits),
            fmt(min(fpx_vals) if fpx_vals else None, 0),
            fmt(max(fpx_vals) if fpx_vals else None, 0),
            fmt(min(fpz_vals) if fpz_vals else None, 0),
            fmt(max(fpz_vals) if fpz_vals else None, 0),
            fmt(s["min"], 0), fmt(s["avg"], 0), fmt(s["max"], 0), fmt(s["median"], 0),
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 2: Collision Volume
    # -----------------------------------------------------------------------
    print_header("2. COLLISION VOLUME DIMENSIONS (Mobile Non-Aircraft)")

    headers = ["Group", "Count", "CVS_X min", "CVS_X avg", "CVS_X max",
               "CVS_Z min", "CVS_Z avg", "CVS_Z max",
               "Floor(X*Z) min", "Floor avg", "Floor max"]
    rows = []
    collision_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        cx = [u["_cvs_x"] for u in gunits if "_cvs_x" in u]
        cz = [u["_cvs_z"] for u in gunits if "_cvs_z" in u]
        floor_area = [u["_cvs_x"] * u["_cvs_z"] for u in gunits if "_cvs_x" in u and "_cvs_z" in u]

        sx = safe_stats(cx)
        sz = safe_stats(cz)
        sf = safe_stats(floor_area)
        collision_data[gname] = {"x": sx, "z": sz, "floor": sf}

        rows.append([
            gname, len(gunits),
            fmt(sx["min"]), fmt(sx["avg"]), fmt(sx["max"]),
            fmt(sz["min"]), fmt(sz["avg"]), fmt(sz["max"]),
            fmt(sf["min"], 0), fmt(sf["avg"], 0), fmt(sf["max"], 0),
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 3: Speed
    # -----------------------------------------------------------------------
    print_header("3. SPEED (elmos/s, Mobile Non-Aircraft)")

    headers = ["Group", "Count", "Min", "Avg", "Max", "Median"]
    rows = []
    speed_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        vals = [float(u["speed"]) for u in gunits if u.get("speed")]
        s = safe_stats(vals)
        speed_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"]), fmt(s["avg"]), fmt(s["max"]), fmt(s["median"])])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 4: Turn Rate (deg/s)
    # -----------------------------------------------------------------------
    print_header("4. TURN RATE (degrees/second, Mobile Non-Aircraft)")

    headers = ["Group", "Count", "Min", "Avg", "Max", "Median"]
    rows = []
    turnrate_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        vals = [float(u["turnrate"]) * SPRING_TURNRATE_TO_DEG_S for u in gunits if u.get("turnrate")]
        s = safe_stats(vals)
        turnrate_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"]), fmt(s["avg"]), fmt(s["max"]), fmt(s["median"])])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 5: Turn Times (45, 90, 180 degrees)
    # -----------------------------------------------------------------------
    print_header("5. TURN TIMES IN SECONDS (Mobile Non-Aircraft)")

    headers = ["Group", "Count",
               "45deg min", "45deg avg", "45deg max",
               "90deg min", "90deg avg", "90deg max",
               "180deg min", "180deg avg", "180deg max"]
    rows = []
    turn_time_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        t45, t90, t180 = [], [], []
        for u in gunits:
            if u.get("turnrate"):
                deg_s = float(u["turnrate"]) * SPRING_TURNRATE_TO_DEG_S
                if deg_s > 0:
                    t45.append(45.0 / deg_s)
                    t90.append(90.0 / deg_s)
                    t180.append(180.0 / deg_s)
        s45 = safe_stats(t45)
        s90 = safe_stats(t90)
        s180 = safe_stats(t180)
        turn_time_data[gname] = {"45": s45, "90": s90, "180": s180}
        rows.append([
            gname, s45["count"],
            fmt(s45["min"], 3), fmt(s45["avg"], 3), fmt(s45["max"], 3),
            fmt(s90["min"], 3), fmt(s90["avg"], 3), fmt(s90["max"], 3),
            fmt(s180["min"], 3), fmt(s180["avg"], 3), fmt(s180["max"], 3),
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 6: Acceleration (elmos/s^2)
    # -----------------------------------------------------------------------
    print_header("6. ACCELERATION (elmos/s^2, Mobile Non-Aircraft)")
    print("  Note: Lua maxacc is in elmos/frame^2. Multiply by 900 (30fps^2) for elmos/s^2.")
    print()

    headers = ["Group", "Count", "Min", "Avg", "Max", "Median"]
    rows = []
    accel_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        vals = [float(u["maxacc"]) * (GAME_FPS ** 2) for u in gunits if u.get("maxacc")]
        s = safe_stats(vals)
        accel_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"]), fmt(s["avg"]), fmt(s["max"]), fmt(s["median"])])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 7: Time to full speed from standstill
    # -----------------------------------------------------------------------
    print_header("7. TIME TO FULL SPEED FROM STANDSTILL (seconds, Mobile Non-Aircraft)")

    headers = ["Group", "Count", "Min", "Avg", "Max", "Median"]
    rows = []
    accel_time_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        vals = []
        for u in gunits:
            spd = u.get("speed", 0)
            acc = u.get("maxacc", 0)
            if isinstance(spd, str):
                try:
                    spd = float(spd)
                except ValueError:
                    continue
            if isinstance(acc, str):
                try:
                    acc = float(acc)
                except ValueError:
                    continue
            if spd > 0 and acc > 0:
                acc_s2 = acc * (GAME_FPS ** 2)
                vals.append(spd / acc_s2)
        s = safe_stats(vals)
        accel_time_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"], 3), fmt(s["avg"], 3), fmt(s["max"], 3), fmt(s["median"], 3)])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Phase 3: Weapon stats from ALL units (mobile + buildings)
    # -----------------------------------------------------------------------

    # Collect all weapons with their source unit info
    all_weapons = []
    for u in all_units:
        for w in u.get("_weapons", []):
            wtype = w.get("weapontype", "Unknown")
            if isinstance(wtype, str):
                wtype = wtype.strip('"')
            w["_source_unit"] = u.get("_name", "unknown")
            w["_source_faction"] = u.get("_faction", "Unknown")
            w["_source_is_mobile"] = u.get("_is_mobile", False)
            w["_source_is_building"] = u.get("_is_building", False)
            w["_source_is_aircraft"] = u.get("_is_aircraft", False)
            w["_source_unit_class"] = u.get("_unit_class", "Unknown")
            w["_weapontype"] = wtype

            # Determine if artillery
            has_high_traj = w.get("hightrajectory") in (1, 1.0, "1", True)
            has_mygravity = "mygravity" in w and w.get("mygravity", 0) not in (0, None)
            w["_is_artillery"] = has_high_traj or has_mygravity

            all_weapons.append(w)

    print_header("8. WEAPON RANGE (all weapons from mobile + buildings)")

    # Group weapons by source type
    weapon_groups = defaultdict(list)
    for w in all_weapons:
        if w.get("_source_is_mobile"):
            cls = w["_source_unit_class"]
            weapon_groups[f"Mobile {cls}"].append(w)
            weapon_groups["Mobile ALL"].append(w)
        if w.get("_source_is_building"):
            weapon_groups["Building/Turret"].append(w)
        weapon_groups["ALL"].append(w)

    headers = ["Group", "Count", "Range Min", "Range Avg", "Range Max", "Range Median"]
    rows = []
    range_data = {}

    for gname in sorted(weapon_groups.keys()):
        wlist = weapon_groups[gname]
        vals = [float(w["range"]) for w in wlist if w.get("range")]
        s = safe_stats(vals)
        range_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"], 0), fmt(s["avg"], 0), fmt(s["max"], 0), fmt(s["median"], 0)])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 9: AoE / damage radius
    # -----------------------------------------------------------------------
    print_header("9. AREA OF EFFECT (AoE radius in elmos)")

    headers = ["Group", "Count w/AoE", "AoE Min", "AoE Avg", "AoE Max", "AoE Median",
               "Point-dmg (<=8)", "No AoE"]
    rows = []
    aoe_data = {}

    for gname in sorted(weapon_groups.keys()):
        wlist = weapon_groups[gname]
        aoe_vals = [float(w["areaofeffect"]) for w in wlist if w.get("areaofeffect") and float(w.get("areaofeffect", 0)) > 8]
        point_dmg = sum(1 for w in wlist if w.get("areaofeffect") is not None and float(w.get("areaofeffect", 0)) <= 8)
        no_aoe = sum(1 for w in wlist if w.get("areaofeffect") is None)
        s = safe_stats(aoe_vals)
        aoe_data[gname] = {"stats": s, "point_damage_count": point_dmg, "no_aoe_count": no_aoe}
        rows.append([
            gname, s["count"],
            fmt(s["min"], 0), fmt(s["avg"], 0), fmt(s["max"], 0), fmt(s["median"], 0),
            point_dmg, no_aoe
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 10: Projectile velocity
    # -----------------------------------------------------------------------
    print_header("10. PROJECTILE VELOCITY (elmos/s)")
    print("  Note: Lua weaponvelocity is already in elmos/s (engine divides by GAME_SPEED internally).")
    print()

    headers = ["Group", "Count", "Vel Min", "Vel Avg", "Vel Max", "Vel Median"]
    rows = []
    velocity_data = {}

    for gname in sorted(weapon_groups.keys()):
        wlist = weapon_groups[gname]
        vals = []
        for w in wlist:
            wv = w.get("weaponvelocity")
            if wv is not None:
                try:
                    # weaponvelocity in Lua is elmos/frame for most weapon types
                    # But for BeamLaser/LightningCannon it's essentially instant
                    wtype = w.get("_weapontype", "")
                    if wtype in ("BeamLaser", "LightningCannon"):
                        continue  # instant hit, no travel time
                    vals.append(float(wv))
                except (ValueError, TypeError):
                    pass
        s = safe_stats(vals)
        velocity_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"], 0), fmt(s["avg"], 0), fmt(s["max"], 0), fmt(s["median"], 0)])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 11: Time to impact at max range
    # -----------------------------------------------------------------------
    print_header("11. TIME TO IMPACT AT MAX RANGE (seconds)")
    print("  Note: range / weaponvelocity. Excludes instant-hit weapons (BeamLaser, Lightning).")
    print()

    headers = ["Group", "Count", "TTI Min", "TTI Avg", "TTI Max", "TTI Median"]
    rows = []
    tti_data = {}

    for gname in sorted(weapon_groups.keys()):
        wlist = weapon_groups[gname]
        vals = []
        for w in wlist:
            rng = w.get("range")
            wv = w.get("weaponvelocity")
            wtype = w.get("_weapontype", "")
            if wtype in ("BeamLaser", "LightningCannon"):
                continue
            if rng and wv:
                try:
                    vel_s = float(wv)
                    if vel_s > 0:
                        vals.append(float(rng) / vel_s)
                except (ValueError, TypeError):
                    pass
        s = safe_stats(vals)
        tti_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"], 3), fmt(s["avg"], 3), fmt(s["max"], 3), fmt(s["median"], 3)])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 12: Weapon type distribution
    # -----------------------------------------------------------------------
    print_header("12. WEAPON TYPE DISTRIBUTION")

    type_counts = defaultdict(int)
    type_by_source = defaultdict(lambda: defaultdict(int))
    for w in all_weapons:
        wtype = w.get("_weapontype", "Unknown")
        type_counts[wtype] += 1
        if w.get("_source_is_mobile"):
            type_by_source["Mobile"][wtype] += 1
        if w.get("_source_is_building"):
            type_by_source["Building"][wtype] += 1
        if w.get("_source_is_aircraft"):
            type_by_source["Aircraft"][wtype] += 1

    headers = ["Weapon Type", "Total", "Mobile", "Building", "Aircraft"]
    rows = []
    for wtype in sorted(type_counts.keys(), key=lambda x: -type_counts[x]):
        rows.append([
            wtype, type_counts[wtype],
            type_by_source["Mobile"].get(wtype, 0),
            type_by_source["Building"].get(wtype, 0),
            type_by_source["Aircraft"].get(wtype, 0),
        ])
    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 13: Direct fire vs artillery
    # -----------------------------------------------------------------------
    print_header("13. DIRECT FIRE vs ARTILLERY WEAPONS")

    artillery_weapons = [w for w in all_weapons if w.get("_is_artillery")]
    direct_weapons = [w for w in all_weapons if not w.get("_is_artillery")]

    print(f"  Direct fire weapons:  {len(direct_weapons)}")
    print(f"  Artillery weapons:    {len(artillery_weapons)}")
    print()

    if artillery_weapons:
        headers = ["Unit", "Weapon", "Type", "Range", "Velocity*30", "HighTraj", "MyGravity"]
        rows = []
        for w in sorted(artillery_weapons, key=lambda x: x.get("_source_unit", "")):
            vel = w.get("weaponvelocity")
            vel_s = fmt(float(vel), 0) if vel else "N/A"
            rows.append([
                w.get("_source_unit", "?"),
                w.get("_weapon_name", "?"),
                w.get("_weapontype", "?"),
                fmt(w.get("range"), 0),
                vel_s,
                "Yes" if w.get("hightrajectory") in (1, 1.0, "1", True) else "No",
                fmt(w.get("mygravity"), 3) if w.get("mygravity") else "N/A",
            ])
        format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 14: Cross-reference dodge analysis
    # -----------------------------------------------------------------------
    print_header("14. DODGE FEASIBILITY ANALYSIS")
    print("  For each common weapon, at various ranges, how much lateral movement")
    print("  can a reference dodger achieve during projectile flight time?")
    print()

    # Collect representative weapons (non-instant, non-torpedo, non-bomb)
    dodge_relevant_weapons = []
    seen_weapons = set()
    for w in all_weapons:
        wtype = w.get("_weapontype", "")
        if wtype in ("BeamLaser", "LightningCannon", "TorpedoLauncher",
                      "AircraftBomb", "Shield", "DGun", "Melee", "Flame"):
            continue
        rng = w.get("range")
        wv = w.get("weaponvelocity")
        if not rng or not wv:
            continue
        # De-duplicate by unit name
        uname = w.get("_source_unit", "")
        wname = w.get("_weapon_name", "")
        key = f"{uname}_{wname}"
        if key in seen_weapons:
            continue
        seen_weapons.add(key)
        dodge_relevant_weapons.append(w)

    # Sort by range descending for interesting output
    dodge_relevant_weapons.sort(key=lambda x: float(x.get("range", 0)), reverse=True)

    # Take a representative sample: pick weapons with distinct velocity/range combos
    # Group by velocity bucket and pick representative
    vel_range_buckets = {}
    for w in dodge_relevant_weapons:
        vel = float(w["weaponvelocity"])
        rng = float(w["range"])
        bucket = (round(vel / 500) * 500, round(rng / 100) * 100)
        if bucket not in vel_range_buckets:
            vel_range_buckets[bucket] = w

    sample_weapons = sorted(vel_range_buckets.values(), key=lambda x: float(x.get("range", 0)))

    # For each reference dodger, compute lateral movement at each test range
    for dodger_name, dodger_stats in REFERENCE_DODGERS.items():
        print(f"\n  --- Reference Dodger: {dodger_name} ---")
        print(f"      Speed: {dodger_stats['speed']} elmos/s | TurnRate: {dodger_stats['turnrate']} Spring units "
              f"({dodger_stats['turnrate'] * SPRING_TURNRATE_TO_DEG_S:.1f} deg/s)")
        print()

        headers = ["Attacker", "WpnType", "Vel(e/s)", "MaxRange",
                   *[f"Lat@{r}e" for r in TEST_RANGES],
                   *[f"TTI@{r}e" for r in TEST_RANGES]]
        rows = []

        for w in sample_weapons:
            vel_es = float(w["weaponvelocity"])
            max_range = float(w["range"])
            wtype = w.get("_weapontype", "?")
            uname = w.get("_source_unit", "?")

            lat_values = []
            tti_values = []
            for test_r in TEST_RANGES:
                if test_r > max_range * 1.2:
                    lat_values.append("-")
                    tti_values.append("-")
                    continue
                tti = test_r / vel_es if vel_es > 0 else 999
                # Lateral movement: assume unit is already moving perpendicular at full speed
                # (best case). Real dodge needs turn time + acceleration.
                lateral = dodger_stats["speed"] * tti
                lat_values.append(fmt(lateral, 1))
                tti_values.append(fmt(tti, 3))

            rows.append([
                uname[:16], wtype[:10], fmt(vel_es, 0), fmt(max_range, 0),
                *lat_values, *tti_values
            ])

        format_table(headers, rows)

    # -----------------------------------------------------------------------
    # More realistic dodge analysis: accounting for turn time + acceleration
    # -----------------------------------------------------------------------
    print_header("14b. REALISTIC DODGE DISTANCE (including turn time + acceleration)")
    print("  Assumes unit is moving FORWARD and must turn 90 degrees then accelerate laterally.")
    print("  lateral_dist = 0.5 * accel * (max(0, flight_time - turn_time))^2, capped at speed * remaining_time")
    print()

    for dodger_name, dodger_stats in REFERENCE_DODGERS.items():
        # Find the actual unit to get accel
        dodger_unit = None
        for u in mobile_units:
            if u.get("_name") == dodger_stats["name"]:
                dodger_unit = u
                break

        if not dodger_unit:
            print(f"  Could not find unit data for {dodger_name}, skipping.")
            continue

        d_speed = float(dodger_unit.get("speed", 0))
        d_turnrate = float(dodger_unit.get("turnrate", 0))
        d_maxacc = float(dodger_unit.get("maxacc", 0))
        d_deg_s = d_turnrate * SPRING_TURNRATE_TO_DEG_S
        d_accel_s2 = d_maxacc * (GAME_FPS ** 2)
        d_turn90 = 90.0 / d_deg_s if d_deg_s > 0 else 999
        d_time_to_speed = d_speed / d_accel_s2 if d_accel_s2 > 0 else 999

        print(f"\n  --- {dodger_name} ({dodger_stats['name']}) ---")
        print(f"      Speed: {d_speed} e/s | TurnRate: {d_deg_s:.1f} deg/s | "
              f"Accel: {d_accel_s2:.1f} e/s^2 | Turn90: {d_turn90:.3f}s | "
              f"TimeToSpeed: {d_time_to_speed:.3f}s")
        print()

        # Get the half-footprint (dodge clearance needed)
        half_fp = 0
        if "_cvs_x" in dodger_unit and "_cvs_z" in dodger_unit:
            half_fp = max(dodger_unit["_cvs_x"], dodger_unit["_cvs_z"]) / 2.0
        print(f"      Half-footprint (dodge clearance): {half_fp:.1f} elmos")
        print()

        headers = ["Attacker", "Vel(e/s)", "Range",
                   *[f"Dodge@{r}" for r in TEST_RANGES],
                   *[f"Clear@{r}?" for r in TEST_RANGES]]
        rows = []

        for w in sample_weapons:
            vel_es = float(w["weaponvelocity"])
            max_range = float(w["range"])
            uname = w.get("_source_unit", "?")
            aoe = float(w.get("areaofeffect", 0))
            dodge_clearance = half_fp + aoe  # need to clear own footprint + AoE

            dodge_vals = []
            clear_vals = []
            for test_r in TEST_RANGES:
                if test_r > max_range * 1.2:
                    dodge_vals.append("-")
                    clear_vals.append("-")
                    continue
                tti = test_r / vel_es if vel_es > 0 else 999

                # Time available for lateral movement after turning
                move_time = max(0, tti - d_turn90)

                # Distance with acceleration (constant accel until max speed, then cruise)
                if move_time <= 0:
                    lateral = 0
                elif move_time <= d_time_to_speed:
                    # Still accelerating
                    lateral = 0.5 * d_accel_s2 * move_time ** 2
                else:
                    # Accelerated to full speed, then cruised
                    accel_dist = 0.5 * d_accel_s2 * d_time_to_speed ** 2
                    cruise_dist = d_speed * (move_time - d_time_to_speed)
                    lateral = accel_dist + cruise_dist

                dodge_vals.append(fmt(lateral, 1))
                clear_vals.append("YES" if lateral >= dodge_clearance else "no")

            rows.append([
                uname[:16], fmt(vel_es, 0), fmt(max_range, 0),
                *dodge_vals, *clear_vals
            ])

        format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Stat 15: Distance to clear own footprint
    # -----------------------------------------------------------------------
    print_header("15. DISTANCE TO CLEAR OWN FOOTPRINT (half collision volume)")

    headers = ["Group", "Count", "HalfCV Min", "HalfCV Avg", "HalfCV Max", "HalfCV Median"]
    rows = []
    halfcv_data = {}

    for gname in sorted(groups.keys()):
        gunits = groups[gname]
        vals = []
        for u in gunits:
            if "_cvs_x" in u and "_cvs_z" in u:
                half = max(u["_cvs_x"], u["_cvs_z"]) / 2.0
                vals.append(half)
        s = safe_stats(vals)
        halfcv_data[gname] = s
        rows.append([gname, s["count"], fmt(s["min"]), fmt(s["avg"]), fmt(s["max"]), fmt(s["median"])])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # BONUS: Per-unit detail table for mobile units
    # -----------------------------------------------------------------------
    print_header("APPENDIX A: PER-UNIT DETAIL TABLE (Mobile Non-Aircraft)")

    headers = ["Name", "Faction", "Class", "Speed", "TurnDeg/s", "Accel(e/s2)",
               "T2Speed(s)", "FPx", "FPz", "CVS_X", "CVS_Z", "HalfCV", "HP", "MovClass"]
    rows = []
    per_unit_data = []

    for u in sorted(mobile_units, key=lambda x: (x.get("_faction", ""), x.get("_unit_class", ""), x.get("_name", ""))):
        spd = float(u.get("speed", 0))
        tr = float(u.get("turnrate", 0))
        deg_s = tr * SPRING_TURNRATE_TO_DEG_S
        acc = float(u.get("maxacc", 0))
        acc_s2 = acc * (GAME_FPS ** 2)
        t2s = spd / acc_s2 if acc_s2 > 0 else None
        cvx = u.get("_cvs_x")
        cvz = u.get("_cvs_z")
        half_cv = max(cvx, cvz) / 2.0 if cvx is not None and cvz is not None else None

        unit_record = {
            "name": u.get("_name", ""),
            "faction": u.get("_faction", ""),
            "unit_class": u.get("_unit_class", ""),
            "speed_elmos_s": spd,
            "turnrate_deg_s": round(deg_s, 2),
            "turnrate_spring": tr,
            "accel_elmos_s2": round(acc_s2, 2),
            "accel_lua_raw": acc,
            "time_to_full_speed_s": round(t2s, 4) if t2s else None,
            "footprint_x": u.get("footprintx"),
            "footprint_z": u.get("footprintz"),
            "footprint_area_elmo2": u.get("footprintx", 0) * u.get("footprintz", 0) * 64 if u.get("footprintx") else None,
            "collision_volume_x": cvx,
            "collision_volume_y": u.get("_cvs_y"),
            "collision_volume_z": cvz,
            "collision_floor_area": round(cvx * cvz, 1) if cvx and cvz else None,
            "half_collision_clearance": round(half_cv, 1) if half_cv else None,
            "health": u.get("health"),
            "movementclass": u.get("movementclass", ""),
            "turn_time_45_s": round(45.0 / deg_s, 4) if deg_s > 0 else None,
            "turn_time_90_s": round(90.0 / deg_s, 4) if deg_s > 0 else None,
            "turn_time_180_s": round(180.0 / deg_s, 4) if deg_s > 0 else None,
            "weapons": [],
        }

        # Add weapon data
        for w in u.get("_weapons", []):
            wrec = {
                "name": w.get("_weapon_name", ""),
                "type": w.get("_weapontype", ""),
                "range": w.get("range"),
                "aoe": w.get("areaofeffect"),
                "velocity_lua": w.get("weaponvelocity"),
                "velocity_elmos_s": round(float(w["weaponvelocity"]), 1) if w.get("weaponvelocity") else None,
                "reload_time": w.get("reloadtime"),
                "damage_default": w.get("damage_default"),
                "is_artillery": w.get("_is_artillery", False),
            }
            unit_record["weapons"].append(wrec)

        per_unit_data.append(unit_record)

        rows.append([
            u.get("_name", "")[:16],
            u.get("_faction", "")[:3],
            u.get("_unit_class", "")[:8],
            fmt(spd, 1),
            fmt(deg_s, 1),
            fmt(acc_s2, 1),
            fmt(t2s, 3) if t2s else "N/A",
            u.get("footprintx", "?"),
            u.get("footprintz", "?"),
            fmt(cvx) if cvx else "N/A",
            fmt(cvz) if cvz else "N/A",
            fmt(half_cv, 1) if half_cv else "N/A",
            u.get("health", "?"),
            str(u.get("movementclass", ""))[:10],
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # BONUS: Per-weapon detail table for buildings/turrets
    # -----------------------------------------------------------------------
    print_header("APPENDIX B: BUILDING/TURRET WEAPON DETAIL TABLE")

    building_weapons = [w for w in all_weapons if w.get("_source_is_building")]
    headers = ["Unit", "Weapon", "Type", "Range", "AoE", "Vel(e/s)", "TTI@Max", "Reload", "DmgDef", "Arty?"]
    rows = []
    building_weapon_data = []

    for w in sorted(building_weapons, key=lambda x: (x.get("_source_unit", ""), x.get("_weapon_name", ""))):
        vel = w.get("weaponvelocity")
        rng = w.get("range")
        wtype = w.get("_weapontype", "")
        vel_es = float(vel) if vel else None

        if wtype in ("BeamLaser", "LightningCannon"):
            tti = 0
        elif vel_es and rng and vel_es > 0:
            tti = float(rng) / vel_es
        else:
            tti = None

        wrec = {
            "unit": w.get("_source_unit", ""),
            "weapon_name": w.get("_weapon_name", ""),
            "type": wtype,
            "range": rng,
            "aoe": w.get("areaofeffect"),
            "velocity_elmos_s": round(vel_es, 1) if vel_es else None,
            "tti_at_max_range": round(tti, 3) if tti is not None else None,
            "reload_time": w.get("reloadtime"),
            "damage_default": w.get("damage_default"),
            "is_artillery": w.get("_is_artillery", False),
        }
        building_weapon_data.append(wrec)

        rows.append([
            w.get("_source_unit", "?")[:16],
            w.get("_weapon_name", "?")[:16],
            wtype[:10],
            fmt(rng, 0) if rng else "N/A",
            fmt(w.get("areaofeffect"), 0) if w.get("areaofeffect") else "N/A",
            fmt(vel_es, 0) if vel_es else "instant",
            fmt(tti, 3) if tti is not None else "0.000",
            fmt(w.get("reloadtime"), 2) if w.get("reloadtime") else "N/A",
            fmt(w.get("damage_default"), 0) if w.get("damage_default") else "N/A",
            "YES" if w.get("_is_artillery") else "no",
        ])

    format_table(headers, rows)

    # -----------------------------------------------------------------------
    # Build the full JSON output
    # -----------------------------------------------------------------------
    output_data = {
        "_metadata": {
            "generated_for": "BAR Dodge Widget Redesign",
            "source_dir": str(UNITS_DIR),
            "total_lua_files": len(lua_files),
            "total_units_parsed": len(all_units),
            "mobile_ground_units": len(mobile_units),
            "buildings": len(buildings),
            "aircraft": len(aircraft),
            "total_weapons_parsed": len(all_weapons),
            "spring_turnrate_conversion": "degrees_per_sec = turnrate * (360 / 65536)",
            "game_fps": GAME_FPS,
            "footprint_elmo_size": FOOTPRINT_ELMO_SIZE,
        },
        "group_stats": {
            "footprint_area": {k: v for k, v in footprint_data.items()},
            "collision_volume": {k: v for k, v in collision_data.items()},
            "speed_elmos_s": {k: v for k, v in speed_data.items()},
            "turnrate_deg_s": {k: v for k, v in turnrate_data.items()},
            "turn_times": {k: v for k, v in turn_time_data.items()},
            "acceleration_elmos_s2": {k: v for k, v in accel_data.items()},
            "time_to_full_speed_s": {k: v for k, v in accel_time_data.items()},
            "half_collision_clearance": {k: v for k, v in halfcv_data.items()},
        },
        "weapon_stats": {
            "range": {k: v for k, v in range_data.items()},
            "aoe": {k: v for k, v in aoe_data.items()},
            "projectile_velocity_elmos_s": {k: v for k, v in velocity_data.items()},
            "time_to_impact_at_max_range_s": {k: v for k, v in tti_data.items()},
            "weapon_type_distribution": dict(type_counts),
            "weapon_type_by_source": {k: dict(v) for k, v in type_by_source.items()},
            "artillery_weapon_count": len(artillery_weapons),
            "direct_fire_weapon_count": len(direct_weapons),
        },
        "per_unit_mobile": per_unit_data,
        "building_turret_weapons": building_weapon_data,
    }

    # Save JSON
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2, default=str)

    print(f"\n\nJSON output saved to: {OUTPUT_JSON}")
    print(f"Total data points: {len(per_unit_data)} mobile units, {len(building_weapon_data)} building weapons")


if __name__ == "__main__":
    main()
