"""
BAR Unit Database - SQLite backend for unit data
=================================================
Imports unitlist.csv into SQLite and provides query functions.
The alias table maps simulator short keys (e.g. "mex") to game IDs (e.g. "armmex").
"""

import csv
import sqlite3
from pathlib import Path
from typing import Optional, Dict

DB_PATH = Path(__file__).parent.parent / "data" / "bar_units.db"
CSV_PATH = Path(__file__).parent.parent / "data" / "unitlist.csv"

# Module-level cache: (faction, db_path) -> dict
_cache: Dict[tuple, dict] = {}


# ---------------------------------------------------------------------------
# Alias seed data: (short_key, armada_id, cortex_id, energy_upkeep, notes)
# ---------------------------------------------------------------------------

# (short_key, armada_id, cortex_id, energy_upkeep, energy_prod_override, metal_prod_override, notes)
# energy_prod_override/metal_prod_override: None = use CSV value, float = override
ALIAS_SEED = [
    # Energy production
    ("solar", "armsolar", "corsolar", 0, 20, None, "Constant 20 E/s. No energy cost to build."),
    ("wind", "armwin", "corwin", 0, None, None, "Output varies with wind (0-25). Check map wind."),
    ("tidal", "armtide", "cortide", 0, None, None, "Stable output, water-only. Map dependent."),
    ("geo_t1", "armgeo", "corgeo", 0, None, None, "Requires geo vent. 300 E/s stable."),
    ("adv_solar", "armadvsol", "coradvsol", 0, None, None, "75-80 E/s. High energy cost to build."),
    ("fusion", "armfus", "corfus", 0, None, None, "T2. Arm:750 Cor:850 E/s. Explodes when killed!"),
    # Metal production
    ("mex", "armmex", "cormex", 3, None, None, "Output depends on metal spot value. Uses 3 E/s."),
    ("moho", "armmoho", "cormoho", 15, None, None, "T2. Produces 4x base mex. Uses 15 E/s."),
    ("converter_t1", "armmakr", "cormakr", 70, None, 1.0, "Converts 70 E/s into 1 M/s. Auto-activates."),
    ("converter_t2", "armmmkr", "cormmkr", 600, None, 10.3, "T2. Converts 600 E/s into 10.3 M/s."),
    # Build power
    ("nano", "armnanotc", "cornanotc", 0, None, None, "200 BP. Stationary. Great for assisting factory."),
    ("naval_nano", "armnanotcplat", "cornanotcplat", 0, None, None, "200 BP. Water-only."),
    # Utility buildings
    ("radar", "armrad", "corrad", 15, None, None, "~2100 range. Essential for early warning. Uses 15 E/s."),
    ("energy_storage", "armestor", "corestor", 0, None, None, "Adds 6000 energy storage."),
    ("metal_storage", "armmstor", "cormstor", 0, None, None, "Adds 3000 metal storage."),
    # Factories
    ("bot_lab", "armlab", "corlab", 0, None, None, "T1 bots. 150 BP base."),
    ("vehicle_plant", "armvp", "corvp", 0, None, None, "T1 vehicles. 150 BP base."),
    ("aircraft_plant", "armap", "corap", 0, None, None, "T1 aircraft. 150 BP base."),
    ("adv_bot_lab", "armalab", "coralab", 0, None, None, "T2 bots. 600 BP base."),
    ("adv_vehicle_plant", "armavp", "coravp", 0, None, None, "T2 vehicles. 600 BP base."),
    ("adv_aircraft_plant", "armaap", "coraap", 0, None, None, "T2 aircraft. 600 BP base."),
    # Bots
    ("tick", "armflea", "corak", 0, None, None, "Fast scout. Explodes on death."),
    ("pawn", "armpw", "corak", 0, None, None, "Fast infantry bot."),
    ("grunt", "armham", "corthud", 0, None, None, "Light plasma bot."),
    ("rocketer", "armrock", "corstorm", 0, None, None, "Rocket bot. Good vs static defenses."),
    ("con_bot", "armck", "corck", 0, None, None, "T1 constructor. 80-85 BP."),
    ("rez_bot", "armrectr", "cornecro", 0, None, None, "Stealth. 200 BP for rez/reclaim."),
    ("adv_con_bot", "armack", "corack", 0, None, None, "T2 constructor. 210-220 BP."),
    # Vehicles
    ("flash", "armflash", "corgator", 0, None, None, "Fast raider. Good for early harass."),
    ("stumpy", "armstump", "corraid", 0, None, None, "Medium assault tank."),
    ("con_vehicle", "armcv", "corcv", 0, None, None, "T1 constructor. 90-95 BP. Faster than con bot."),
    ("adv_con_vehicle", "armacv", "coracv", 0, None, None, "T2 constructor. 290-310 BP."),
    # Defenses
    ("llt", "armllt", "corllt", 0, None, None, "Light Laser Tower. ~430 range."),
    ("hlt", "armhlt", "corhlt", 0, None, None, "Heavy Laser Tower. ~620 range."),
    # Commander
    ("commander", "armcom", "corcom", 0, None, None, "300 BP. D-gun costs 500 energy. Dies = you lose!"),
]


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

_SCHEMA = """
CREATE TABLE IF NOT EXISTS units (
    id          TEXT PRIMARY KEY,
    faction     TEXT NOT NULL,
    techlevel   INTEGER,
    name        TEXT,
    tooltip     TEXT,
    metalcost   INTEGER DEFAULT 0,
    energycost  INTEGER DEFAULT 0,
    buildtime   INTEGER DEFAULT 0,
    metalmake   REAL DEFAULT 0,
    energymake  REAL DEFAULT 0,
    buildpower  INTEGER DEFAULT 0,
    speed       REAL DEFAULT 0,
    health      INTEGER DEFAULT 0,
    dps         REAL DEFAULT 0,
    weaponrange REAL DEFAULT 0,
    building    INTEGER DEFAULT 0,
    bot         INTEGER DEFAULT 0,
    tank        INTEGER DEFAULT 0,
    air         INTEGER DEFAULT 0,
    ship        INTEGER DEFAULT 0,
    hover       INTEGER DEFAULT 0,
    specials    TEXT,
    weapons     TEXT,
    buildoptions TEXT,
    buildable   INTEGER DEFAULT 1,
    file        TEXT
);

CREATE TABLE IF NOT EXISTS unit_aliases (
    short_key                TEXT PRIMARY KEY,
    armada_id                TEXT NOT NULL,
    cortex_id                TEXT,
    energy_upkeep            REAL DEFAULT 0,
    energy_production_override REAL,
    metal_production_override  REAL,
    notes                    TEXT
);

CREATE TABLE IF NOT EXISTS metadata (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS idx_units_faction ON units(faction);
CREATE INDEX IF NOT EXISTS idx_units_faction_tech ON units(faction, techlevel);
"""

# CSV columns to import (in order they appear in the CSV)
_CSV_COLUMNS = [
    "id", "faction", "techlevel", "name", "tooltip", "description",
    "radaricon", "height", "metalcost", "energycost", "buildtime",
    "metalmake", "energymake", "buildpower", "speed", "health",
    "amphib", "sub", "air", "hover", "ship", "tank", "bot", "building",
    "dps", "weaponrange", "jammerrange", "sonarrange", "radarrange",
    "sightrange", "airsightrange", "specials", "weapons", "buildoptions",
    "buildable", "file",
]

# Columns we store in the units table
_STORED_COLUMNS = [
    "id", "faction", "techlevel", "name", "tooltip",
    "metalcost", "energycost", "buildtime", "metalmake", "energymake",
    "buildpower", "speed", "health", "dps", "weaponrange",
    "building", "bot", "tank", "air", "ship", "hover",
    "specials", "weapons", "buildoptions", "buildable", "file",
]


# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

def init_db(db_path=DB_PATH) -> sqlite3.Connection:
    """Create tables if they don't exist. Returns connection."""
    conn = sqlite3.connect(str(db_path))
    conn.executescript(_SCHEMA)
    conn.commit()
    return conn


def import_csv(csv_path=CSV_PATH, db_path=DB_PATH) -> int:
    """Parse unitlist.csv and insert all rows. Returns row count."""
    conn = init_db(db_path)
    # Clear existing data for idempotent re-import
    conn.execute("DELETE FROM units")

    placeholders = ", ".join("?" for _ in _STORED_COLUMNS)
    col_names = ", ".join(_STORED_COLUMNS)
    insert_sql = f"INSERT OR REPLACE INTO units ({col_names}) VALUES ({placeholders})"

    count = 0
    with open(str(csv_path), "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";", fieldnames=_CSV_COLUMNS)
        # Skip header row
        next(reader)
        for row in reader:
            if not row.get("id"):
                continue
            # Strip trailing empty field from trailing semicolon
            values = []
            for col in _STORED_COLUMNS:
                val = row.get(col, "").strip()
                if col in ("techlevel", "metalcost", "energycost", "buildtime",
                           "buildpower", "health", "building", "bot", "tank",
                           "air", "ship", "hover", "buildable"):
                    values.append(int(val) if val else 0)
                elif col in ("metalmake", "energymake", "speed", "dps", "weaponrange"):
                    values.append(float(val) if val else 0.0)
                else:
                    values.append(val)
            conn.execute(insert_sql, values)
            count += 1

    # Store metadata
    from datetime import datetime
    conn.execute("INSERT OR REPLACE INTO metadata VALUES (?, ?)",
                 ("csv_imported_at", datetime.now().isoformat()))
    conn.execute("INSERT OR REPLACE INTO metadata VALUES (?, ?)",
                 ("csv_row_count", str(count)))
    conn.execute("INSERT OR REPLACE INTO metadata VALUES (?, ?)",
                 ("schema_version", "1"))
    conn.commit()
    conn.close()
    return count


def seed_aliases(db_path=DB_PATH) -> int:
    """Insert the curated alias mapping. Returns alias count."""
    conn = init_db(db_path)
    conn.execute("DELETE FROM unit_aliases")
    insert_sql = ("INSERT INTO unit_aliases "
                  "(short_key, armada_id, cortex_id, energy_upkeep, "
                  "energy_production_override, metal_production_override, notes) "
                  "VALUES (?, ?, ?, ?, ?, ?, ?)")
    for row in ALIAS_SEED:
        conn.execute(insert_sql, row)
    conn.commit()
    count = len(ALIAS_SEED)
    conn.close()
    return count


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

def load_units_dict(faction: str = "ARMADA", db_path=DB_PATH) -> dict:
    """
    Load aliased units as {short_key: Unit} matching bar_econ.Unit interface.
    Results are cached per (faction, db_path).
    """
    cache_key = (faction.upper(), str(db_path))
    if cache_key in _cache:
        return _cache[cache_key]

    from bar_sim.econ import Unit

    faction_col = "armada_id" if faction.upper() == "ARMADA" else "cortex_id"
    query = f"""
        SELECT
            a.short_key,
            a.energy_upkeep,
            a.energy_production_override,
            a.metal_production_override,
            a.notes,
            u.name,
            u.metalcost,
            u.energycost,
            u.buildtime,
            u.buildpower,
            u.metalmake,
            u.energymake,
            u.health
        FROM unit_aliases a
        JOIN units u ON u.id = a.{faction_col}
        WHERE a.{faction_col} IS NOT NULL
    """
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    result = {}
    for row in conn.execute(query):
        # Use override values when set, otherwise fall back to CSV
        e_prod = row["energy_production_override"]
        if e_prod is None:
            e_prod = row["energymake"]
        m_prod = row["metal_production_override"]
        if m_prod is None:
            m_prod = row["metalmake"]

        result[row["short_key"]] = Unit(
            name=row["name"],
            metal_cost=row["metalcost"],
            energy_cost=row["energycost"],
            build_time=row["buildtime"],
            build_power=row["buildpower"],
            metal_production=m_prod,
            energy_production=e_prod,
            energy_upkeep=row["energy_upkeep"],
            health=row["health"],
            notes=row["notes"] or "",
        )
    conn.close()

    _cache[cache_key] = result
    return result


def get_unit_by_game_id(game_id: str, db_path=DB_PATH) -> Optional[dict]:
    """Fetch a single unit row by game ID."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    row = conn.execute("SELECT * FROM units WHERE id = ?", (game_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_alias_map(db_path=DB_PATH) -> dict:
    """Return full alias table as {short_key: {armada_id, cortex_id, ...}}."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    result = {}
    for row in conn.execute("SELECT * FROM unit_aliases"):
        result[row["short_key"]] = dict(row)
    conn.close()
    return result


def get_game_id_map(faction: str = "ARMADA", db_path=DB_PATH) -> dict:
    """Return {short_key: game_id} for a given faction.

    Example: get_game_id_map("ARMADA")["mex"] -> "armmex"
    """
    faction_col = "armada_id" if faction.upper() == "ARMADA" else "cortex_id"
    conn = sqlite3.connect(str(db_path))
    result = {}
    for row in conn.execute(
        f"SELECT short_key, {faction_col} FROM unit_aliases WHERE {faction_col} IS NOT NULL"
    ):
        result[row[0]] = row[1]
    conn.close()
    return result


def get_buildoptions(game_id: str, db_path=DB_PATH) -> list:
    """Parse buildoptions for a game ID. Returns list of game IDs."""
    conn = sqlite3.connect(str(db_path))
    row = conn.execute("SELECT buildoptions FROM units WHERE id = ?",
                       (game_id,)).fetchone()
    conn.close()
    if not row or not row[0]:
        return []
    return [x.strip() for x in row[0].split(",") if x.strip()]


def clear_cache():
    """Clear the module-level cache."""
    _cache.clear()


def ensure_db(db_path=DB_PATH, csv_path=CSV_PATH):
    """Auto-create DB from CSV if it doesn't exist."""
    db = Path(db_path)
    if db.exists():
        return
    csv_file = Path(csv_path)
    if not csv_file.exists():
        raise FileNotFoundError(f"CSV not found: {csv_path}")
    count = import_csv(csv_path, db_path)
    aliases = seed_aliases(db_path)
    print(f"[bar_db] Created {db_path}: {count} units, {aliases} aliases")


# ---------------------------------------------------------------------------
# CLI: python bar_db.py [--verify]
# ---------------------------------------------------------------------------

def _print_diff():
    """Print comparison of old hardcoded vs new DB values."""
    from bar_sim.econ import _LEGACY_UNITS
    db_units = load_units_dict("ARMADA")

    print(f"\n{'short_key':<18} {'field':<16} {'hardcoded':>10} {'csv':>10} {'delta':>10}")
    print("-" * 66)

    diffs = 0
    for key in sorted(_LEGACY_UNITS):
        old = _LEGACY_UNITS[key]
        new = db_units.get(key)
        if not new:
            print(f"{key:<18} {'MISSING':>16}")
            continue
        fields = [
            ("metal_cost", old.metal_cost, new.metal_cost),
            ("energy_cost", old.energy_cost, new.energy_cost),
            ("build_time", old.build_time, new.build_time),
            ("build_power", old.build_power, new.build_power),
            ("energy_prod", old.energy_production, new.energy_production),
            ("health", old.health, new.health),
        ]
        for fname, oval, nval in fields:
            if oval != nval:
                delta = nval - oval
                sign = "+" if delta > 0 else ""
                print(f"{key:<18} {fname:<16} {oval:>10} {nval:>10} {sign}{delta:>9}")
                diffs += 1

    print(f"\n{diffs} value differences found across {len(_LEGACY_UNITS)} units.")


def _verify(db_path=DB_PATH):
    """Run integrity checks."""
    conn = sqlite3.connect(str(db_path))

    # Check row counts
    total = conn.execute("SELECT COUNT(*) FROM units").fetchone()[0]
    arm = conn.execute("SELECT COUNT(*) FROM units WHERE faction='ARMADA'").fetchone()[0]
    cor = conn.execute("SELECT COUNT(*) FROM units WHERE faction='CORTEX'").fetchone()[0]
    aliases = conn.execute("SELECT COUNT(*) FROM unit_aliases").fetchone()[0]
    print(f"Units: {total} total ({arm} ARMADA + {cor} CORTEX)")
    print(f"Aliases: {aliases}")

    # Check alias integrity
    errors = 0
    for row in conn.execute("SELECT short_key, armada_id, cortex_id FROM unit_aliases"):
        sk, aid, cid = row
        if aid:
            r = conn.execute("SELECT id FROM units WHERE id=?", (aid,)).fetchone()
            if not r:
                print(f"  ERROR: alias '{sk}' armada_id '{aid}' not found in units")
                errors += 1
        if cid:
            r = conn.execute("SELECT id FROM units WHERE id=?", (cid,)).fetchone()
            if not r:
                print(f"  ERROR: alias '{sk}' cortex_id '{cid}' not found in units")
                errors += 1

    conn.close()

    # Check round-trip
    try:
        from bar_sim.econ import _LEGACY_UNITS
        db_units = load_units_dict("ARMADA")
        missing = [k for k in _LEGACY_UNITS if k not in db_units]
        if missing:
            print(f"  WARNING: {len(missing)} legacy keys missing from DB: {missing}")
            errors += len(missing)
        else:
            print(f"  All {len(_LEGACY_UNITS)} legacy keys present in DB")
    except ImportError:
        print("  Skipping legacy check (_LEGACY_UNITS not available)")

    if errors:
        print(f"\n{errors} errors found!")
    else:
        print("\nAll checks passed!")

    return errors


if __name__ == "__main__":
    import sys
    verify = "--verify" in sys.argv

    print("BAR Unit Database Import")
    print("=" * 40)

    count = import_csv()
    print(f"Imported {count} units from CSV")

    aliases = seed_aliases()
    print(f"Seeded {aliases} aliases")

    if verify:
        print("\n--- Verification ---")
        _verify()
        print("\n--- Value Diff (Hardcoded vs CSV) ---")
        _print_diff()
