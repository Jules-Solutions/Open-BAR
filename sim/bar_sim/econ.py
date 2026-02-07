"""
Beyond All Reason - Strategy Toolkit
=====================================
Data-driven decision framework for BAR gameplay.

Unit data loaded from SQLite database (bar_units.db), which is auto-generated
from unitlist.csv. Falls back to legacy hardcoded values if DB is unavailable.

See bar_db.py for the import pipeline and alias mapping.
"""

from dataclasses import dataclass
from typing import Optional
import math


# =============================================================================
# UNIT DATA
# =============================================================================

@dataclass
class Unit:
    name: str
    metal_cost: int
    energy_cost: int
    build_time: int  # in "build power seconds" (cost / buildpower = seconds)
    build_power: int = 0  # if it can build
    metal_production: float = 0  # per second
    energy_production: float = 0  # per second
    energy_upkeep: float = 0  # per second (negative = consumes)
    health: int = 0
    notes: str = ""


# Legacy hardcoded values (fallback if DB is unavailable)
_LEGACY_UNITS = {
    # === ENERGY PRODUCTION ===
    "solar": Unit(
        name="Solar Collector",
        metal_cost=150,
        energy_cost=0,
        build_time=2100,
        energy_production=20,
        health=280,
        notes="Constant 20 E/s. No energy cost to build - good when energy starved."
    ),
    "wind": Unit(
        name="Wind Turbine",
        metal_cost=40,
        energy_cost=175,
        build_time=1050,
        energy_production=0,  # Variable - use wind_energy() function
        health=196,
        notes="Output varies with wind (0-25). Check map wind with 'I' key."
    ),
    "tidal": Unit(
        name="Tidal Generator",
        metal_cost=175,
        energy_cost=1750,
        build_time=3500,
        energy_production=0,  # Map dependent - typically 18-25
        health=330,
        notes="Stable output, but water-only. Check map tidal value."
    ),
    "geo_t1": Unit(
        name="Geothermal Powerplant",
        metal_cost=350,
        energy_cost=3500,
        build_time=7500,
        energy_production=300,
        health=1600,
        notes="Requires geo vent. 300 E/s stable."
    ),
    "adv_solar": Unit(
        name="Advanced Solar Collector",
        metal_cost=280,
        energy_cost=2800,
        build_time=5600,
        energy_production=75,
        health=480,
        notes="75 E/s. High energy cost - don't build when stalling."
    ),
    "fusion": Unit(
        name="Fusion Reactor",
        metal_cost=3500,
        energy_cost=16000,
        build_time=30000,
        energy_production=1000,
        health=4500,
        notes="1000 E/s. T2 building. Explodes when killed!"
    ),
    
    # === METAL PRODUCTION ===
    "mex": Unit(
        name="Metal Extractor",
        metal_cost=50,
        energy_cost=500,
        build_time=1200,
        metal_production=0,  # Map dependent: typically 1.8-2.5
        energy_upkeep=3,
        health=270,
        notes="Output depends on metal spot value. Uses 3 E/s."
    ),
    "moho": Unit(
        name="Advanced Metal Extractor (Moho)",
        metal_cost=550,
        energy_cost=6600,
        build_time=14000,
        metal_production=0,  # 4x the mex value
        energy_upkeep=15,
        health=2400,
        notes="T2. Produces 4x base mex. Uses 15 E/s."
    ),
    "converter_t1": Unit(
        name="Energy Converter",
        metal_cost=1,
        energy_cost=1150,
        build_time=2500,
        metal_production=1.0,  # When active
        energy_upkeep=70,
        health=167,
        notes="Converts 70 E/s into 1 M/s. Auto-activates when excess energy."
    ),
    "converter_t2": Unit(
        name="Advanced Energy Converter",
        metal_cost=200,
        energy_cost=6000,
        build_time=12000,
        metal_production=10.3,  # When active
        energy_upkeep=600,
        health=500,
        notes="T2. Converts 600 E/s into 10.3 M/s. More efficient than T1."
    ),
    
    # === BUILD POWER ===
    "nano": Unit(
        name="Construction Turret",
        metal_cost=200,
        energy_cost=4000,
        build_time=6000,
        build_power=200,
        health=550,
        notes="200 BP. Stationary. Great for assisting factory."
    ),
    "naval_nano": Unit(
        name="Naval Construction Turret",
        metal_cost=230,
        energy_cost=4600,
        build_time=7000,
        build_power=250,
        health=550,
        notes="250 BP. Water-only."
    ),
    
    # === OTHER BUILDINGS ===
    "radar": Unit(
        name="Radar Tower",
        metal_cost=50,
        energy_cost=500,
        build_time=1500,
        energy_upkeep=15,
        health=150,
        notes="~1800 range. Essential for early warning."
    ),
    "energy_storage": Unit(
        name="Energy Storage",
        metal_cost=175,
        energy_cost=1750,
        build_time=3500,
        health=800,
        notes="Adds 6000 energy storage. Useful with wind."
    ),
    "metal_storage": Unit(
        name="Metal Storage",
        metal_cost=200,
        energy_cost=0,
        build_time=2500,
        health=1000,
        notes="Adds 3000 metal storage."
    ),
    
    # === FACTORIES ===
    "bot_lab": Unit(
        name="Bot Lab",
        metal_cost=650,
        energy_cost=1300,
        build_time=7000,
        build_power=100,
        health=2700,
        notes="T1 bots. 100 BP base."
    ),
    "vehicle_plant": Unit(
        name="Vehicle Plant",
        metal_cost=700,
        energy_cost=1400,
        build_time=7500,
        build_power=100,
        health=3000,
        notes="T1 vehicles. 100 BP base."
    ),
    "aircraft_plant": Unit(
        name="Aircraft Plant",
        metal_cost=800,
        energy_cost=2800,
        build_time=8000,
        build_power=100,
        health=2500,
        notes="T1 aircraft."
    ),
    "adv_bot_lab": Unit(
        name="Advanced Bot Lab",
        metal_cost=2200,
        energy_cost=12000,
        build_time=25000,
        build_power=300,
        health=5000,
        notes="T2 bots. 300 BP base."
    ),
    "adv_vehicle_plant": Unit(
        name="Advanced Vehicle Plant",
        metal_cost=2400,
        energy_cost=14000,
        build_time=28000,
        build_power=300,
        health=5500,
        notes="T2 vehicles. 300 BP base."
    ),
    
    # === BOTS ===
    "tick": Unit(
        name="Tick (Scout)",
        metal_cost=25,
        energy_cost=300,
        build_time=1100,
        health=55,
        notes="Fast scout. Explodes on death (small damage)."
    ),
    "pawn": Unit(
        name="Pawn (Light Infantry)",
        metal_cost=35,
        energy_cost=700,
        build_time=1500,
        health=200,
        notes="Basic infantry. Good vs other light units."
    ),
    "grunt": Unit(
        name="Grunt (Medium Infantry)",
        metal_cost=55,
        energy_cost=800,
        build_time=2000,
        health=400,
        notes="Laser bot. More range than Pawn."
    ),
    "rocketer": Unit(
        name="Rocketer (Rocket Bot)",
        metal_cost=150,
        energy_cost=2000,
        build_time=4000,
        health=400,
        notes="Good vs defenses. Outranges LLT."
    ),
    "con_bot": Unit(
        name="Construction Bot",
        metal_cost=100,
        energy_cost=1000,
        build_time=3000,
        build_power=100,
        energy_production=3,  # Constructors produce small energy
        health=400,
        notes="100 BP. +50 storage. Produces 3 E/s just by existing."
    ),
    "rez_bot": Unit(
        name="Lazarus (Resurrection Bot)",
        metal_cost=130,
        energy_cost=2600,
        build_time=4500,
        build_power=150,  # for resurrect/reclaim
        health=500,
        notes="Stealth. 150 BP for rez/reclaim. No energy production."
    ),
    "adv_con_bot": Unit(
        name="Advanced Construction Bot",
        metal_cost=400,
        energy_cost=4000,
        build_time=10000,
        build_power=200,
        energy_production=7,
        health=800,
        notes="T2. 200 BP. +100 storage. Produces 7 E/s."
    ),
    
    # === VEHICLES ===
    "flash": Unit(
        name="Flash (Raider Tank)",
        metal_cost=55,
        energy_cost=800,
        build_time=2100,
        health=400,
        notes="Fast raider. Good for early harass."
    ),
    "stumpy": Unit(
        name="Stumpy (Light Tank)",
        metal_cost=120,
        energy_cost=1400,
        build_time=3500,
        health=900,
        notes="Bread and butter tank."
    ),
    "con_vehicle": Unit(
        name="Construction Vehicle",
        metal_cost=130,
        energy_cost=1300,
        build_time=4000,
        build_power=100,
        energy_production=5,
        health=600,
        notes="100 BP. +50 storage. Faster than con bot."
    ),
    
    # === DEFENSES ===
    "llt": Unit(
        name="Light Laser Tower",
        metal_cost=85,
        energy_cost=850,
        build_time=2800,
        health=650,
        notes="Basic defense. ~350 range."
    ),
    "hlt": Unit(
        name="Heavy Laser Tower",
        metal_cost=350,
        energy_cost=3500,
        build_time=8000,
        health=2200,
        notes="Stronger defense. ~500 range."
    ),
    
    # === COMMANDER ===
    "commander": Unit(
        name="Commander",
        metal_cost=0,
        energy_cost=0,
        build_time=0,
        build_power=200,
        energy_production=25,  # Commanders produce energy
        health=3500,
        notes="200 BP. D-gun costs 500 energy. Dies = you lose!"
    ),
}


# =============================================================================
# DB-BACKED UNITS (with legacy fallback)
# =============================================================================

def _load_units(faction: str = "ARMADA") -> dict:
    """Load units from SQLite DB, falling back to legacy dict on failure."""
    try:
        from bar_sim.db import ensure_db, load_units_dict, clear_cache
        ensure_db()
        clear_cache()
        return load_units_dict(faction)
    except Exception:
        return dict(_LEGACY_UNITS)


# Module-level UNITS dict -- all consumers import this
UNITS = _load_units()


def set_faction(faction: str):
    """Reload UNITS dict for a different faction (ARMADA or CORTEX).

    Clears and repopulates the existing dict object so that all modules
    that imported UNITS via 'from bar_econ import UNITS' see the update.
    """
    new_data = _load_units(faction.upper())
    UNITS.clear()
    UNITS.update(new_data)


# =============================================================================
# ECONOMY CALCULATIONS
# =============================================================================

def wind_energy(avg_wind: float, variance: float = 0) -> tuple[float, float, float]:
    """
    Calculate wind turbine energy output.
    
    Args:
        avg_wind: Map's average wind value (shown in map info)
        variance: Wind variance (how much it fluctuates)
    
    Returns:
        (min_energy, avg_energy, max_energy) per wind turbine
    """
    # Wind turbines produce between 0-25 E/s based on wind speed
    # Actual formula: output = min(25, max(0, wind_speed))
    min_e = max(0, avg_wind - variance)
    max_e = min(25, avg_wind + variance)
    return (min_e, avg_wind, max_e)


def wind_vs_solar_breakeven(avg_wind: float) -> dict:
    """
    Compare wind vs solar efficiency at given wind level.
    
    Returns dict with analysis.
    """
    solar = UNITS["solar"]
    wind = UNITS["wind"]
    
    wind_output = avg_wind  # Simplified: actual output ≈ avg_wind
    solar_output = solar.energy_production
    
    # Metal efficiency: energy produced per metal spent
    wind_metal_eff = wind_output / wind.metal_cost if wind.metal_cost > 0 else 0
    solar_metal_eff = solar_output / solar.metal_cost
    
    # How many of each to get 100 E/s
    wind_for_100 = math.ceil(100 / wind_output) if wind_output > 0 else float('inf')
    solar_for_100 = math.ceil(100 / solar_output)
    
    wind_metal_for_100 = wind_for_100 * wind.metal_cost
    solar_metal_for_100 = solar_for_100 * solar.metal_cost
    
    return {
        "avg_wind": avg_wind,
        "wind_output_per_turbine": wind_output,
        "solar_output": solar_output,
        "wind_metal_efficiency": round(wind_metal_eff, 4),
        "solar_metal_efficiency": round(solar_metal_eff, 4),
        "better_choice": "wind" if wind_metal_eff > solar_metal_eff else "solar",
        "wind_needed_for_100E": wind_for_100,
        "solar_needed_for_100E": solar_for_100,
        "wind_metal_for_100E": wind_metal_for_100,
        "solar_metal_for_100E": solar_metal_for_100,
        "breakeven_wind": round(solar_output * wind.metal_cost / solar.metal_cost, 1),
    }


def build_time(unit: Unit, build_power: int) -> float:
    """
    Calculate time to build a unit given available build power.
    
    Args:
        unit: The unit to build
        build_power: Total BP applied (commander + nanos + cons)
    
    Returns:
        Build time in seconds
    """
    if build_power <= 0:
        return float('inf')
    return unit.build_time / build_power


def eco_ratio_check(metal_income: float, energy_income: float, build_power: int) -> dict:
    """
    Check if economy is balanced per official guide ratios.
    
    Optimal ratio from guide: 200 BP per 5 M/s and 100 E/s
    """
    # Target ratios
    target_bp_per_5m = 200
    target_bp_per_100e = 200
    
    # What BP could your income support?
    bp_supported_by_metal = (metal_income / 5) * target_bp_per_5m
    bp_supported_by_energy = (energy_income / 100) * target_bp_per_100e
    
    limiting_factor = "metal" if bp_supported_by_metal < bp_supported_by_energy else "energy"
    max_useful_bp = min(bp_supported_by_metal, bp_supported_by_energy)
    
    return {
        "metal_income": metal_income,
        "energy_income": energy_income,
        "current_build_power": build_power,
        "bp_supported_by_metal": round(bp_supported_by_metal),
        "bp_supported_by_energy": round(bp_supported_by_energy),
        "max_useful_bp": round(max_useful_bp),
        "limiting_factor": limiting_factor,
        "bp_surplus": build_power - max_useful_bp,
        "is_balanced": abs(build_power - max_useful_bp) < 50,
        "recommendation": (
            f"Add more {limiting_factor} production" if max_useful_bp < build_power 
            else f"Add more build power (current: {build_power}, can support: {round(max_useful_bp)})"
        )
    }


def t2_readiness_check(metal_income: float, energy_income: float, metal_stored: float) -> dict:
    """
    Check if ready to transition to T2.
    
    Based on guide: Need ~1000-2000 metal stored, +20 M/s, +500 E/s
    """
    # Thresholds from official guide
    MIN_METAL_INCOME = 20
    MIN_ENERGY_INCOME = 500
    MIN_METAL_STORED = 1000
    RECOMMENDED_METAL_STORED = 2000
    
    # T2 investment cost (rough)
    T2_FACTORY_COST = 2200  # Advanced Bot Lab
    T2_CON_COST = 400
    FIRST_MOHO_COST = 550
    TOTAL_T2_INVESTMENT = T2_FACTORY_COST + T2_CON_COST + (FIRST_MOHO_COST * 3)  # ~4000
    
    ready = (
        metal_income >= MIN_METAL_INCOME and
        energy_income >= MIN_ENERGY_INCOME and
        metal_stored >= MIN_METAL_STORED
    )
    
    return {
        "metal_income": metal_income,
        "energy_income": energy_income,
        "metal_stored": metal_stored,
        "ready_for_t2": ready,
        "metal_income_ok": metal_income >= MIN_METAL_INCOME,
        "energy_income_ok": energy_income >= MIN_ENERGY_INCOME,
        "metal_stored_ok": metal_stored >= MIN_METAL_STORED,
        "estimated_t2_investment": TOTAL_T2_INVESTMENT,
        "time_to_save": (
            max(0, RECOMMENDED_METAL_STORED - metal_stored) / metal_income 
            if metal_income > 0 else float('inf')
        ),
        "blockers": [
            issue for issue, ok in [
                (f"Need +{MIN_METAL_INCOME - metal_income:.1f} M/s", metal_income < MIN_METAL_INCOME),
                (f"Need +{MIN_ENERGY_INCOME - energy_income:.0f} E/s", energy_income < MIN_ENERGY_INCOME),
                (f"Need +{MIN_METAL_STORED - metal_stored:.0f} metal stored", metal_stored < MIN_METAL_STORED),
            ] if ok
        ]
    }


def nano_threshold(metal_income: float, energy_income: float) -> dict:
    """
    Calculate when you can support a nano turret.
    
    Rule: 200 BP (1 nano) per 5 M/s and 100 E/s
    """
    nano = UNITS["nano"]
    
    # Can your eco support a nano's BP?
    bp_from_metal = (metal_income / 5) * 200
    bp_from_energy = (energy_income / 100) * 200
    supportable_bp = min(bp_from_metal, bp_from_energy)
    
    can_support_nano = supportable_bp >= 200
    
    return {
        "metal_income": metal_income,
        "energy_income": energy_income,
        "supportable_bp": round(supportable_bp),
        "nano_bp": 200,
        "can_support_nano": can_support_nano,
        "nanos_supportable": int(supportable_bp / 200),
        "nano_metal_cost": nano.metal_cost,
        "nano_energy_cost": nano.energy_cost,
        "recommendation": (
            "Build nano turret to assist factory" if can_support_nano
            else f"Need {max(0, 200 - supportable_bp):.0f} more supportable BP first"
        )
    }


def mex_value(base_value: float = 2.0) -> dict:
    """
    Calculate metal extractor economics.
    
    Args:
        base_value: Metal spot value (typically 1.8-2.5 on most maps)
    """
    mex = UNITS["mex"]
    moho = UNITS["moho"]
    
    mex_output = base_value
    moho_output = base_value * 4
    
    # Payback time (how long until the mex pays for itself)
    mex_payback = mex.metal_cost / mex_output
    moho_payback = moho.metal_cost / moho_output
    
    # Upgrade efficiency (moho upgrade from existing mex)
    upgrade_metal = moho.metal_cost - 15  # ~15 metal reclaimed from mex
    upgrade_payback = upgrade_metal / (moho_output - mex_output)
    
    return {
        "base_spot_value": base_value,
        "mex_output": mex_output,
        "moho_output": moho_output,
        "mex_metal_cost": mex.metal_cost,
        "moho_metal_cost": moho.metal_cost,
        "mex_payback_seconds": round(mex_payback, 1),
        "moho_payback_seconds": round(moho_payback, 1),
        "moho_upgrade_payback_seconds": round(upgrade_payback, 1),
        "mex_efficiency": round(mex_output / mex.metal_cost * 100, 2),
        "moho_efficiency": round(moho_output / moho.metal_cost * 100, 2),
    }


# =============================================================================
# STATE SYSTEM
# =============================================================================

@dataclass
class GameState:
    """Current game state snapshot."""
    mex_count: int
    metal_income: float  # M/s
    energy_income: float  # E/s
    build_power: int  # Total BP
    metal_stored: float
    energy_stored: float
    con_count: int
    nano_count: int
    has_t2_lab: bool = False
    has_t2_con: bool = False


def determine_state(gs: GameState) -> str:
    """
    Determine which strategic state the game is in.
    
    Returns state name.
    """
    if gs.mex_count < 3:
        return "OPENING"
    elif gs.mex_count <= 3 and gs.con_count == 0:
        return "FOUNDATION"
    elif gs.metal_income < 8:
        return "EXPANSION"
    elif not gs.has_t2_lab and gs.metal_income < 20:
        return "SCALING"
    elif not gs.has_t2_lab and gs.metal_income >= 20:
        return "T2_READY"
    elif gs.has_t2_lab and not gs.has_t2_con:
        return "T2_TRANSITION"
    else:
        return "LATE_GAME"


def get_priorities(state: str) -> list[str]:
    """Get priority list for a given state."""
    priorities = {
        "OPENING": [
            "1. Build 2 metal extractors",
            "2. Build 2-3 energy (wind if ≥7, else solar)",
            "3. Build Bot Lab",
            "4. Queue: Tick → Tick → Combat → Constructor",
        ],
        "FOUNDATION": [
            "1. Complete factory",
            "2. Commander: Mex #3, more energy, radar",
            "3. First Tick for scouting",
            "4. Get Constructor Bot out ASAP",
        ],
        "EXPANSION": [
            "1. Constructor: grab contested mexes",
            "2. Build LLT at key chokes",
            "3. Scale energy to stay positive",
            "4. Factory: combat units",
            "5. Commander: prepare for nano (at 8 M/s, 100 E/s)",
        ],
        "SCALING": [
            "1. Build nano turret assisting factory",
            "2. Continue mex expansion (target: 10+)",
            "3. Get 2nd constructor",
            "4. Scale energy for T2 prep (target: 500 E/s)",
            "5. Bank metal (target: 1000-2000)",
        ],
        "T2_READY": [
            "1. Start T2 factory (Adv Bot Lab)",
            "2. Continue T1 unit production",
            "3. Protect economy",
            "4. Queue T2 constructor immediately",
        ],
        "T2_TRANSITION": [
            "1. T2 Con: Upgrade back mexes to Moho first",
            "2. Build Fusion Reactor",
            "3. T1 factory keeps producing",
            "4. Consider sharing T2 con with allies (team games)",
        ],
        "LATE_GAME": [
            "1. Upgrade all mexes to Moho",
            "2. Add Fusion Reactors",
            "3. Scale T2 production",
            "4. Consider T2 converters",
            "5. Tech to T3 when appropriate",
        ],
    }
    return priorities.get(state, ["Unknown state"])


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def print_state_analysis(gs: GameState):
    """Print full state analysis."""
    state = determine_state(gs)
    priorities = get_priorities(state)
    
    print("=" * 60)
    print(f"CURRENT STATE: {state}")
    print("=" * 60)
    print(f"\nEconomy:")
    print(f"  Metal:  {gs.metal_income:.1f}/s  ({gs.metal_stored:.0f} stored)")
    print(f"  Energy: {gs.energy_income:.0f}/s ({gs.energy_stored:.0f} stored)")
    print(f"  Build Power: {gs.build_power}")
    print(f"\nAssets:")
    print(f"  Mexes: {gs.mex_count}")
    print(f"  Constructors: {gs.con_count}")
    print(f"  Nano Turrets: {gs.nano_count}")
    print(f"  T2 Lab: {'Yes' if gs.has_t2_lab else 'No'}")
    
    print(f"\nPRIORITIES:")
    for p in priorities:
        print(f"  {p}")
    
    # Additional checks
    print(f"\nANALYSIS:")
    
    eco = eco_ratio_check(gs.metal_income, gs.energy_income, gs.build_power)
    print(f"  Economy balance: {eco['recommendation']}")
    
    nano = nano_threshold(gs.metal_income, gs.energy_income)
    if not nano['can_support_nano'] and gs.nano_count == 0:
        print(f"  Nano: Not ready yet ({nano['recommendation']})")
    elif nano['nanos_supportable'] > gs.nano_count:
        print(f"  Nano: Can support {nano['nanos_supportable'] - gs.nano_count} more")
    
    t2 = t2_readiness_check(gs.metal_income, gs.energy_income, gs.metal_stored)
    if not gs.has_t2_lab:
        if t2['ready_for_t2']:
            print(f"  T2: READY TO GO")
        else:
            print(f"  T2 blockers: {', '.join(t2['blockers']) if t2['blockers'] else 'None'}")


def print_unit_costs():
    """Print a table of key unit costs."""
    print("\n" + "=" * 80)
    print("KEY UNIT COSTS (Armada)")
    print("=" * 80)
    print(f"{'Unit':<30} {'Metal':>8} {'Energy':>8} {'Time@200BP':>12} {'Notes':<25}")
    print("-" * 80)
    
    key_units = [
        "mex", "solar", "wind", "radar", "llt",
        "bot_lab", "nano", "con_bot", 
        "tick", "pawn", "grunt", "rocketer",
        "adv_bot_lab", "adv_con_bot", "moho", "fusion"
    ]
    
    for key in key_units:
        if key in UNITS:
            u = UNITS[key]
            time_200bp = u.build_time / 200
            print(f"{u.name:<30} {u.metal_cost:>8} {u.energy_cost:>8} {time_200bp:>10.1f}s  {u.notes[:25]}")


def wind_comparison_table():
    """Print wind vs solar comparison at different wind levels."""
    print("\n" + "=" * 60)
    print("WIND VS SOLAR COMPARISON")
    print("=" * 60)
    print(f"{'Wind Avg':>10} {'Better':>10} {'Wind/100E':>12} {'Solar/100E':>12}")
    print("-" * 60)
    
    for wind in [3, 5, 7, 9, 11, 13, 15, 20]:
        comparison = wind_vs_solar_breakeven(wind)
        print(f"{wind:>10} {comparison['better_choice']:>10} "
              f"{comparison['wind_needed_for_100E']:>12} "
              f"{comparison['solar_needed_for_100E']:>12}")
    
    print(f"\nBreakeven point: wind = {wind_vs_solar_breakeven(7)['breakeven_wind']}")


# =============================================================================
# MAIN - Example usage
# =============================================================================

if __name__ == "__main__":
    print("BEYOND ALL REASON - STRATEGY TOOLKIT")
    print("====================================\n")
    
    # Example: Analyze a game state
    example_state = GameState(
        mex_count=6,
        metal_income=10.5,
        energy_income=120,
        build_power=300,  # Commander + 1 nano
        metal_stored=450,
        energy_stored=1500,
        con_count=1,
        nano_count=1,
        has_t2_lab=False,
        has_t2_con=False
    )
    
    print_state_analysis(example_state)
    print_unit_costs()
    wind_comparison_table()
