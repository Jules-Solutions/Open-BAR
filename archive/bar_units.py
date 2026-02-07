"""
Beyond All Reason - Complete Unit Database
==========================================
All Armada units with stats, roles, and counter relationships.

Sources: Official BAR website, game files, community guides
Last updated: January 2025
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional
from enum import Enum, auto


# =============================================================================
# ENUMS
# =============================================================================

class UnitType(Enum):
    BUILDING = auto()
    BOT = auto()
    VEHICLE = auto()
    AIRCRAFT = auto()
    SHIP = auto()
    HOVERCRAFT = auto()
    DEFENSE = auto()
    COMMANDER = auto()


class Role(Enum):
    # Economy
    METAL_PRODUCTION = auto()
    ENERGY_PRODUCTION = auto()
    METAL_CONVERSION = auto()
    STORAGE = auto()
    CONSTRUCTION = auto()
    
    # Combat
    SCOUT = auto()
    RAIDER = auto()
    ASSAULT = auto()
    SKIRMISHER = auto()
    ARTILLERY = auto()
    ANTI_AIR = auto()
    
    # Air
    FIGHTER = auto()
    BOMBER = auto()
    GUNSHIP = auto()
    TRANSPORT = auto()
    
    # Support
    REPAIR = auto()
    RESURRECT = auto()
    RADAR = auto()
    JAMMER = auto()
    
    # Defense
    POINT_DEFENSE = auto()
    AREA_DEFENSE = auto()
    STATIC_ARTY = auto()


class DamageType(Enum):
    LIGHT = auto()      # Good vs light units
    MEDIUM = auto()     # Balanced
    HEAVY = auto()      # Good vs heavy/buildings
    EXPLOSIVE = auto()  # AoE damage
    LASER = auto()      # Hitscan, accurate
    EMP = auto()        # Stun/disable


# =============================================================================
# UNIT DATA CLASS
# =============================================================================

@dataclass
class Unit:
    name: str
    internal_name: str
    unit_type: UnitType
    tech_level: int  # 1, 2, or 3
    
    # Costs
    metal_cost: int
    energy_cost: int
    build_time: int  # Build power cost
    
    # Stats
    health: int
    speed: float = 0  # elmos per second
    build_power: int = 0
    
    # Production (for eco buildings)
    metal_production: float = 0
    energy_production: float = 0
    energy_upkeep: float = 0
    
    # Combat
    dps: float = 0
    weapon_range: int = 0
    damage_type: Optional[DamageType] = None
    
    # Roles and info
    roles: List[Role] = field(default_factory=list)
    strong_vs: List[str] = field(default_factory=list)
    weak_vs: List[str] = field(default_factory=list)
    notes: str = ""


# =============================================================================
# COMPLETE UNIT DATABASE - ARMADA
# =============================================================================

UNITS = {
    # =========================================================================
    # ECONOMY BUILDINGS
    # =========================================================================
    
    # --- Metal Production ---
    "mex": Unit(
        name="Metal Extractor",
        internal_name="armmex",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=50,
        energy_cost=500,
        build_time=1200,
        health=270,
        metal_production=2.0,  # Map dependent: 1.8-2.5 typical
        energy_upkeep=3,
        roles=[Role.METAL_PRODUCTION],
        notes="Output depends on metal spot. ~2 M/s typical. Uses 3 E/s."
    ),
    
    "moho": Unit(
        name="Advanced Metal Extractor (Moho)",
        internal_name="armmoho",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=550,
        energy_cost=6600,
        build_time=14000,
        health=2400,
        metal_production=8.0,  # 4x base mex value
        energy_upkeep=15,
        roles=[Role.METAL_PRODUCTION],
        notes="T2. Produces 4x base mex value. Priority upgrade target."
    ),
    
    # --- Energy Converters ---
    "converter_t1": Unit(
        name="Energy Converter",
        internal_name="armmakr",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=1,
        energy_cost=1150,
        build_time=2500,
        health=167,
        metal_production=1.0,  # When active
        energy_upkeep=70,
        roles=[Role.METAL_CONVERSION],
        notes="Converts 70 E/s → 1 M/s. Auto-activates via yellow slider. Chain explodes!"
    ),
    
    "converter_t2": Unit(
        name="Advanced Energy Converter",
        internal_name="armmmkr",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=200,
        energy_cost=6000,
        build_time=12000,
        health=500,
        metal_production=10.3,  # When active
        energy_upkeep=600,
        roles=[Role.METAL_CONVERSION],
        notes="Converts 600 E/s → 10.3 M/s. Better ratio than T1. Still explodes."
    ),
    
    # --- Energy Production ---
    "solar": Unit(
        name="Solar Collector",
        internal_name="armsolar",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=150,
        energy_cost=0,
        build_time=2100,
        health=280,
        energy_production=20,
        roles=[Role.ENERGY_PRODUCTION],
        notes="Constant 20 E/s. No energy cost - good when E-stalling."
    ),
    
    "wind": Unit(
        name="Wind Turbine",
        internal_name="armwin",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=40,
        energy_cost=175,
        build_time=1050,
        health=196,
        energy_production=0,  # Variable: 0-25 based on wind
        roles=[Role.ENERGY_PRODUCTION],
        notes="Output = wind speed (0-25). Check map info with 'I'."
    ),
    
    "tidal": Unit(
        name="Tidal Generator",
        internal_name="armtide",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=175,
        energy_cost=1750,
        build_time=3500,
        health=330,
        energy_production=20,  # Map dependent: typically 18-25
        roles=[Role.ENERGY_PRODUCTION],
        notes="Water only. Stable output. Check map tidal value."
    ),
    
    "geo_t1": Unit(
        name="Geothermal Powerplant",
        internal_name="armgeo",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=350,
        energy_cost=3500,
        build_time=7500,
        health=1600,
        energy_production=300,
        roles=[Role.ENERGY_PRODUCTION],
        notes="Requires geo vent. 300 E/s stable. High priority if available."
    ),
    
    "adv_solar": Unit(
        name="Advanced Solar Collector",
        internal_name="armadvsol",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=280,
        energy_cost=2800,
        build_time=5600,
        health=480,
        energy_production=75,
        roles=[Role.ENERGY_PRODUCTION],
        notes="75 E/s. High E cost to build - don't build when stalling."
    ),
    
    "fusion": Unit(
        name="Fusion Reactor",
        internal_name="armfus",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=3500,
        energy_cost=16000,
        build_time=30000,
        health=4500,
        energy_production=1000,
        roles=[Role.ENERGY_PRODUCTION],
        notes="T2. 1000 E/s. EXPLODES when killed - don't cluster!"
    ),
    
    "adv_fusion": Unit(
        name="Advanced Fusion Reactor",
        internal_name="armafus",
        unit_type=UnitType.BUILDING,
        tech_level=3,
        metal_cost=6000,
        energy_cost=48000,
        build_time=72000,
        health=8000,
        energy_production=3000,
        roles=[Role.ENERGY_PRODUCTION],
        notes="T3. 3000 E/s. Massive explosion on death."
    ),
    
    # --- Storage ---
    "metal_storage": Unit(
        name="Metal Storage",
        internal_name="armmstor",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=200,
        energy_cost=0,
        build_time=2500,
        health=1000,
        roles=[Role.STORAGE],
        notes="+3000 metal storage. Build before T2 to bank resources."
    ),
    
    "energy_storage": Unit(
        name="Energy Storage",
        internal_name="armestor",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=175,
        energy_cost=1750,
        build_time=3500,
        health=800,
        roles=[Role.STORAGE],
        notes="+6000 energy storage. Essential with wind for variance buffer."
    ),
    
    # --- Build Power ---
    "nano": Unit(
        name="Construction Turret (Nano)",
        internal_name="armnanotc",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=200,
        energy_cost=4000,
        build_time=6000,
        health=550,
        build_power=200,
        roles=[Role.CONSTRUCTION],
        notes="200 BP stationary. Assist factory. Better than 2nd factory."
    ),
    
    # --- Radar/Intel ---
    "radar": Unit(
        name="Radar Tower",
        internal_name="armrad",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=50,
        energy_cost=500,
        build_time=1500,
        health=150,
        energy_upkeep=15,
        roles=[Role.RADAR],
        notes="~1800 radar range. Place on high ground. Essential early."
    ),
    
    "adv_radar": Unit(
        name="Advanced Radar Tower",
        internal_name="armarad",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=280,
        energy_cost=2800,
        build_time=5600,
        health=400,
        energy_upkeep=50,
        roles=[Role.RADAR],
        notes="T2. ~4000 radar range. Map-wide coverage."
    ),
    
    "jammer": Unit(
        name="Radar Jammer (Sneaky Pete)",
        internal_name="armjamt",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=90,
        energy_cost=900,
        build_time=2500,
        health=250,
        energy_upkeep=25,
        roles=[Role.JAMMER],
        notes="Hides units from radar in area. Use near front."
    ),
    
    "veil": Unit(
        name="Long-Range Jammer (Veil)",
        internal_name="armveil",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=350,
        energy_cost=8400,
        build_time=10000,
        health=500,
        energy_upkeep=150,
        roles=[Role.JAMMER],
        notes="T2. Large jamming radius. High energy cost."
    ),
    
    # =========================================================================
    # FACTORIES
    # =========================================================================
    
    "bot_lab": Unit(
        name="Bot Lab",
        internal_name="armlab",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=650,
        energy_cost=1300,
        build_time=7000,
        health=2700,
        build_power=100,
        roles=[Role.CONSTRUCTION],
        notes="T1 bots. Default 1v1 choice. 100 BP base."
    ),
    
    "vehicle_plant": Unit(
        name="Vehicle Plant",
        internal_name="armvp",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=700,
        energy_cost=1400,
        build_time=7500,
        health=3000,
        build_power=100,
        roles=[Role.CONSTRUCTION],
        notes="T1 vehicles. Better on flat maps. 100 BP base."
    ),
    
    "aircraft_plant": Unit(
        name="Aircraft Plant",
        internal_name="armap",
        unit_type=UnitType.BUILDING,
        tech_level=1,
        metal_cost=800,
        energy_cost=2800,
        build_time=8000,
        health=2500,
        build_power=100,
        roles=[Role.CONSTRUCTION],
        notes="T1 air. High energy cost. Don't build first usually."
    ),
    
    "adv_bot_lab": Unit(
        name="Advanced Bot Lab",
        internal_name="armalab",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=2200,
        energy_cost=12000,
        build_time=25000,
        health=5000,
        build_power=300,
        roles=[Role.CONSTRUCTION],
        notes="T2 bots. 300 BP. First T2 factory usually."
    ),
    
    "adv_vehicle_plant": Unit(
        name="Advanced Vehicle Plant",
        internal_name="armavp",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=2400,
        energy_cost=14000,
        build_time=28000,
        health=5500,
        build_power=300,
        roles=[Role.CONSTRUCTION],
        notes="T2 vehicles. 300 BP. Strong assault units."
    ),
    
    "adv_aircraft_plant": Unit(
        name="Advanced Aircraft Plant",
        internal_name="armaap",
        unit_type=UnitType.BUILDING,
        tech_level=2,
        metal_cost=2000,
        energy_cost=20000,
        build_time=24000,
        health=4000,
        build_power=200,
        roles=[Role.CONSTRUCTION],
        notes="T2 air. Bombers, gunships. Expensive."
    ),
    
    "gantry": Unit(
        name="Experimental Gantry",
        internal_name="armapt3",
        unit_type=UnitType.BUILDING,
        tech_level=3,
        metal_cost=5000,
        energy_cost=40000,
        build_time=60000,
        health=8000,
        build_power=500,
        roles=[Role.CONSTRUCTION],
        notes="T3 experimentals. Game-enders."
    ),
    
    # =========================================================================
    # DEFENSES
    # =========================================================================
    
    "llt": Unit(
        name="Light Laser Tower",
        internal_name="armllt",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=85,
        energy_cost=850,
        build_time=2800,
        health=650,
        dps=75,
        weapon_range=350,
        damage_type=DamageType.LASER,
        roles=[Role.POINT_DEFENSE],
        strong_vs=["scouts", "raiders", "light units"],
        weak_vs=["rocketer", "artillery", "tanks"],
        notes="Basic point defense. ~350 range. Outranged by Rocketer!"
    ),
    
    "hlt": Unit(
        name="Heavy Laser Tower (Sentinel)",
        internal_name="armhlt",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=350,
        energy_cost=3500,
        build_time=8000,
        health=2200,
        dps=200,
        weapon_range=500,
        damage_type=DamageType.LASER,
        roles=[Role.POINT_DEFENSE],
        strong_vs=["assault units", "medium tanks"],
        weak_vs=["artillery", "bombers", "long range"],
        notes="Strong vs ground assault. Still outranged by arty."
    ),
    
    "beamer": Unit(
        name="Beamer (Pop-up Laser)",
        internal_name="armbeamer",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=180,
        energy_cost=3600,
        build_time=4500,
        health=600,
        dps=120,
        weapon_range=430,
        damage_type=DamageType.LASER,
        roles=[Role.POINT_DEFENSE],
        strong_vs=["assault units"],
        weak_vs=["artillery", "bombers"],
        notes="Retracts when not firing. Harder to spot. Surprise defense."
    ),
    
    "plasma_t1": Unit(
        name="Plasma Battery (Ambusher)",
        internal_name="armpb",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=500,
        energy_cost=5000,
        build_time=10000,
        health=1800,
        dps=150,
        weapon_range=700,
        damage_type=DamageType.EXPLOSIVE,
        roles=[Role.AREA_DEFENSE],
        strong_vs=["medium units", "groups"],
        weak_vs=["fast raiders", "air"],
        notes="Pop-up plasma. AoE damage. Good vs clumped units."
    ),
    
    "pulsar": Unit(
        name="Pulsar (Heavy Plasma)",
        internal_name="armanni",
        unit_type=UnitType.DEFENSE,
        tech_level=2,
        metal_cost=1500,
        energy_cost=18000,
        build_time=25000,
        health=4500,
        dps=500,
        weapon_range=900,
        damage_type=DamageType.HEAVY,
        energy_upkeep=150,  # Per shot
        roles=[Role.AREA_DEFENSE],
        strong_vs=["T2 units", "heavy tanks", "assault"],
        weak_vs=["artillery", "bombers", "swarms"],
        notes="T2. Devastating single-target. Uses energy per shot."
    ),
    
    "dragon_teeth": Unit(
        name="Dragon's Teeth",
        internal_name="armdrag",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=3,
        energy_cost=0,
        build_time=150,
        health=160,
        roles=[],
        notes="Blocks pathing. Slows pushes. Cheap. Use in rows."
    ),
    
    "fortification": Unit(
        name="Fortification Wall",
        internal_name="armfort",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=15,
        energy_cost=0,
        build_time=400,
        health=2400,
        roles=[],
        notes="Taller wall. Blocks LoS and shots. More expensive."
    ),
    
    # --- Anti-Air Defenses ---
    "aa_tower": Unit(
        name="Chainsaw (AA Turret)",
        internal_name="armrl",
        unit_type=UnitType.DEFENSE,
        tech_level=1,
        metal_cost=85,
        energy_cost=850,
        build_time=2500,
        health=500,
        dps=100,
        weapon_range=800,
        damage_type=DamageType.LIGHT,
        roles=[Role.ANTI_AIR],
        strong_vs=["scouts", "fighters", "light air"],
        weak_vs=["gunships", "heavy bombers"],
        notes="Basic AA. Build 2-3 to cover base. ~800 range."
    ),
    
    "flak": Unit(
        name="Flak Cannon (Rattler)",
        internal_name="armflak",
        unit_type=UnitType.DEFENSE,
        tech_level=2,
        metal_cost=450,
        energy_cost=4500,
        build_time=9000,
        health=1400,
        dps=300,
        weapon_range=900,
        damage_type=DamageType.EXPLOSIVE,
        roles=[Role.ANTI_AIR],
        strong_vs=["all aircraft", "bomber groups"],
        weak_vs=["ground units"],
        notes="T2. AoE AA. Devastating vs air blobs."
    ),
    
    "screamer": Unit(
        name="Screamer (AA Missile)",
        internal_name="armcir",
        unit_type=UnitType.DEFENSE,
        tech_level=2,
        metal_cost=600,
        energy_cost=9000,
        build_time=12000,
        health=1200,
        dps=400,
        weapon_range=1200,
        damage_type=DamageType.HEAVY,
        roles=[Role.ANTI_AIR],
        strong_vs=["heavy air", "bombers"],
        weak_vs=["ground units"],
        notes="T2. Long range AA. High single-target damage."
    ),
    
    # --- Artillery ---
    "lrpc": Unit(
        name="Big Bertha (Long Range Plasma)",
        internal_name="armbrtha",
        unit_type=UnitType.DEFENSE,
        tech_level=2,
        metal_cost=2500,
        energy_cost=30000,
        build_time=40000,
        health=3500,
        dps=150,
        weapon_range=5000,
        damage_type=DamageType.EXPLOSIVE,
        energy_upkeep=500,  # Per shot
        roles=[Role.STATIC_ARTY],
        strong_vs=["stationary targets", "buildings"],
        weak_vs=["mobile units", "spread targets"],
        notes="T2. Map-range artillery. Expensive to fire. Inaccurate."
    ),
    
    # --- Anti-Nuke ---
    "antinuke": Unit(
        name="Protector (Anti-Nuke)",
        internal_name="armamd",
        unit_type=UnitType.DEFENSE,
        tech_level=2,
        metal_cost=1800,
        energy_cost=54000,
        build_time=45000,
        health=3000,
        weapon_range=4000,
        roles=[],
        notes="Intercepts nukes. Must stockpile missiles. Essential vs nuke."
    ),
    
    # =========================================================================
    # T1 BOTS
    # =========================================================================
    
    "tick": Unit(
        name="Tick",
        internal_name="armflea",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=25,
        energy_cost=300,
        build_time=1100,
        health=55,
        speed=135,
        dps=8,
        weapon_range=120,
        damage_type=DamageType.LIGHT,
        roles=[Role.SCOUT],
        strong_vs=["other scouts"],
        weak_vs=["everything else"],
        notes="Fast scout. Explodes on death (25 damage). Expendable."
    ),
    
    "pawn": Unit(
        name="Pawn",
        internal_name="armpw",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=35,
        energy_cost=700,
        build_time=1500,
        health=200,
        speed=75,
        dps=25,
        weapon_range=180,
        damage_type=DamageType.LIGHT,
        roles=[Role.RAIDER],
        strong_vs=["scouts", "constructors", "artillery"],
        weak_vs=["grunts", "tanks", "defenses"],
        notes="Light infantry. Fast, cheap. Swarm unit."
    ),
    
    "grunt": Unit(
        name="Grunt",
        internal_name="armpw1",  # Actually armham
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=55,
        energy_cost=800,
        build_time=2000,
        health=400,
        speed=54,
        dps=40,
        weapon_range=220,
        damage_type=DamageType.LASER,
        roles=[Role.ASSAULT],
        strong_vs=["pawns", "scouts", "light units"],
        weak_vs=["tanks", "rockeaters", "defenses"],
        notes="Medium infantry. Better range than Pawn. Core early unit."
    ),
    
    "rocketer": Unit(
        name="Rocketer (Hammer)",
        internal_name="armham",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=150,
        energy_cost=2000,
        build_time=4000,
        health=400,
        speed=48,
        dps=50,
        weapon_range=450,
        damage_type=DamageType.EXPLOSIVE,
        roles=[Role.SKIRMISHER],
        strong_vs=["LLT", "defenses", "slow units"],
        weak_vs=["raiders", "fast units"],
        notes="Outranges LLT! Use to push defensive positions."
    ),
    
    "warrior": Unit(
        name="Warrior",
        internal_name="armwar",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=200,
        energy_cost=2500,
        build_time=5000,
        health=1000,
        speed=42,
        dps=60,
        weapon_range=200,
        damage_type=DamageType.MEDIUM,
        roles=[Role.ASSAULT],
        strong_vs=["light units", "swarms"],
        weak_vs=["tanks", "artillery"],
        notes="Tanky bot. Good vs swarms. AoE weapon."
    ),
    
    "con_bot": Unit(
        name="Construction Bot",
        internal_name="armck",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=100,
        energy_cost=1000,
        build_time=3000,
        health=400,
        speed=42,
        build_power=100,
        energy_production=3,
        roles=[Role.CONSTRUCTION],
        notes="100 BP. +50 storage. Produces 3 E/s. Core expansion unit."
    ),
    
    "rez_bot": Unit(
        name="Lazarus (Resurrector)",
        internal_name="armrectr",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=130,
        energy_cost=2600,
        build_time=4500,
        health=500,
        speed=48,
        build_power=150,
        roles=[Role.RESURRECT, Role.REPAIR],
        notes="Stealth. 150 BP for rez/reclaim. Rez costs energy. High value."
    ),
    
    "jethro": Unit(
        name="Jethro (AA Bot)",
        internal_name="armjeth",
        unit_type=UnitType.BOT,
        tech_level=1,
        metal_cost=130,
        energy_cost=1600,
        build_time=3500,
        health=450,
        speed=54,
        dps=60,
        weapon_range=700,
        damage_type=DamageType.LIGHT,
        roles=[Role.ANTI_AIR],
        strong_vs=["scouts", "bombers", "fighters"],
        weak_vs=["ground units"],
        notes="Mobile AA. Mix into army for air defense."
    ),
    
    # =========================================================================
    # T2 BOTS
    # =========================================================================
    
    "adv_con_bot": Unit(
        name="Advanced Construction Bot",
        internal_name="armack",
        unit_type=UnitType.BOT,
        tech_level=2,
        metal_cost=400,
        energy_cost=4000,
        build_time=10000,
        health=800,
        speed=36,
        build_power=200,
        energy_production=7,
        roles=[Role.CONSTRUCTION],
        notes="T2. 200 BP. +100 storage. First T2 unit to build!"
    ),
    
    "zeus": Unit(
        name="Zeus (Assault Bot)",
        internal_name="armzeus",
        unit_type=UnitType.BOT,
        tech_level=2,
        metal_cost=350,
        energy_cost=5600,
        build_time=7500,
        health=2000,
        speed=42,
        dps=120,
        weapon_range=280,
        damage_type=DamageType.LASER,
        energy_upkeep=15,  # Per shot
        roles=[Role.ASSAULT],
        strong_vs=["T1 units", "light tanks"],
        weak_vs=["skirmishers", "artillery"],
        notes="T2 assault. Lightning gun. Strong but short range."
    ),
    
    "invader": Unit(
        name="Invader (Artillery Bot)",
        internal_name="armmav",
        unit_type=UnitType.BOT,
        tech_level=2,
        metal_cost=350,
        energy_cost=6000,
        build_time=8500,
        health=1200,
        speed=36,
        dps=100,
        weapon_range=700,
        damage_type=DamageType.EXPLOSIVE,
        roles=[Role.ARTILLERY],
        strong_vs=["defenses", "slow units", "groups"],
        weak_vs=["fast raiders", "air"],
        notes="T2 mobile arty. AoE. Good vs defensive positions."
    ),
    
    "eraser": Unit(
        name="Eraser (EMP Bot)",
        internal_name="armsptk",
        unit_type=UnitType.BOT,
        tech_level=2,
        metal_cost=400,
        energy_cost=8000,
        build_time=9000,
        health=1000,
        speed=48,
        dps=0,  # EMP doesn't do damage
        weapon_range=400,
        damage_type=DamageType.EMP,
        roles=[Role.SKIRMISHER],
        strong_vs=["all ground units", "defenses"],
        weak_vs=["air", "fast units"],
        notes="T2 EMP. Stuns targets. Combo with Zeus/assault."
    ),
    
    "fido": Unit(
        name="Fido (Skirmisher)",
        internal_name="armfido",
        unit_type=UnitType.BOT,
        tech_level=2,
        metal_cost=300,
        energy_cost=4200,
        build_time=6500,
        health=1100,
        speed=48,
        dps=80,
        weapon_range=450,
        damage_type=DamageType.MEDIUM,
        roles=[Role.SKIRMISHER],
        strong_vs=["assault units", "short range"],
        weak_vs=["artillery", "air"],
        notes="T2 skirmisher. Good range. Mobile."
    ),
    
    # =========================================================================
    # T1 VEHICLES
    # =========================================================================
    
    "jeffy": Unit(
        name="Jeffy (Scout Car)",
        internal_name="armfav",
        unit_type=UnitType.VEHICLE,
        tech_level=1,
        metal_cost=30,
        energy_cost=500,
        build_time=1200,
        health=100,
        speed=126,
        dps=10,
        weapon_range=150,
        damage_type=DamageType.LIGHT,
        roles=[Role.SCOUT],
        strong_vs=["other scouts"],
        weak_vs=["everything else"],
        notes="Fast scout vehicle. Slightly tougher than Tick."
    ),
    
    "flash": Unit(
        name="Flash (Raider)",
        internal_name="armflash",
        unit_type=UnitType.VEHICLE,
        tech_level=1,
        metal_cost=55,
        energy_cost=800,
        build_time=2100,
        health=400,
        speed=96,
        dps=35,
        weapon_range=200,
        damage_type=DamageType.LASER,
        roles=[Role.RAIDER],
        strong_vs=["constructors", "artillery", "economy"],
        weak_vs=["defenses", "assault units"],
        notes="Fast raider. Hit and run. Don't fight head-on."
    ),
    
    "stumpy": Unit(
        name="Stumpy (Light Tank)",
        internal_name="armstump",
        unit_type=UnitType.VEHICLE,
        tech_level=1,
        metal_cost=120,
        energy_cost=1400,
        build_time=3500,
        health=900,
        speed=54,
        dps=55,
        weapon_range=280,
        damage_type=DamageType.MEDIUM,
        roles=[Role.ASSAULT],
        strong_vs=["bots", "light units"],
        weak_vs=["rockeaters", "artillery"],
        notes="Bread and butter tank. Good all-rounder."
    ),
    
    "samson": Unit(
        name="Samson (AA Vehicle)",
        internal_name="armyork",
        unit_type=UnitType.VEHICLE,
        tech_level=1,
        metal_cost=180,
        energy_cost=2200,
        build_time=4500,
        health=800,
        speed=60,
        dps=80,
        weapon_range=800,
        damage_type=DamageType.LIGHT,
        roles=[Role.ANTI_AIR],
        strong_vs=["all air"],
        weak_vs=["ground units"],
        notes="Mobile AA vehicle. Faster than Jethro. Mix into army."
    ),
    
    "con_vehicle": Unit(
        name="Construction Vehicle",
        internal_name="armcv",
        unit_type=UnitType.VEHICLE,
        tech_level=1,
        metal_cost=130,
        energy_cost=1300,
        build_time=4000,
        health=600,
        speed=54,
        build_power=100,
        energy_production=5,
        roles=[Role.CONSTRUCTION],
        notes="100 BP. Faster than con bot. +50 storage."
    ),
    
    # =========================================================================
    # T2 VEHICLES
    # =========================================================================
    
    "adv_con_vehicle": Unit(
        name="Advanced Construction Vehicle",
        internal_name="armacv",
        unit_type=UnitType.VEHICLE,
        tech_level=2,
        metal_cost=450,
        energy_cost=4500,
        build_time=11000,
        health=1000,
        speed=48,
        build_power=200,
        energy_production=10,
        roles=[Role.CONSTRUCTION],
        notes="T2. 200 BP. Faster than T2 con bot."
    ),
    
    "bulldog": Unit(
        name="Bulldog (Heavy Tank)",
        internal_name="armbull",
        unit_type=UnitType.VEHICLE,
        tech_level=2,
        metal_cost=500,
        energy_cost=6000,
        build_time=10000,
        health=3500,
        speed=42,
        dps=150,
        weapon_range=350,
        damage_type=DamageType.HEAVY,
        roles=[Role.ASSAULT],
        strong_vs=["T1 units", "defenses"],
        weak_vs=["skirmishers", "EMP"],
        notes="T2 heavy tank. Pushes hard. Protect from EMP."
    ),
    
    "penetrator": Unit(
        name="Penetrator (Tank Destroyer)",
        internal_name="armmart",
        unit_type=UnitType.VEHICLE,
        tech_level=2,
        metal_cost=600,
        energy_cost=9000,
        build_time=12000,
        health=2000,
        speed=36,
        dps=200,
        weapon_range=700,
        damage_type=DamageType.HEAVY,
        roles=[Role.SKIRMISHER],
        strong_vs=["heavy tanks", "assault"],
        weak_vs=["raiders", "air"],
        notes="T2 long-range anti-armor. Support unit."
    ),
    
    "triton": Unit(
        name="Triton (Amphibious Tank)",
        internal_name="armcroc",
        unit_type=UnitType.VEHICLE,
        tech_level=2,
        metal_cost=400,
        energy_cost=6400,
        build_time=9000,
        health=2500,
        speed=48,
        dps=100,
        weapon_range=300,
        damage_type=DamageType.MEDIUM,
        roles=[Role.ASSAULT],
        strong_vs=["light units"],
        weak_vs=["heavy tanks"],
        notes="T2 amphibious. Can cross water. Flanking potential."
    ),
    
    # =========================================================================
    # T1 AIRCRAFT
    # =========================================================================
    
    "blink": Unit(
        name="Blink (Air Scout)",
        internal_name="armpeep",
        unit_type=UnitType.AIRCRAFT,
        tech_level=1,
        metal_cost=25,
        energy_cost=1500,
        build_time=2000,
        health=50,
        speed=300,
        roles=[Role.SCOUT],
        notes="Fast air scout. Huge vision. Fragile."
    ),
    
    "phoenix": Unit(
        name="Phoenix (Bomber)",
        internal_name="armthund",
        unit_type=UnitType.AIRCRAFT,
        tech_level=1,
        metal_cost=150,
        energy_cost=4500,
        build_time=6000,
        health=600,
        speed=210,
        dps=200,  # Per bomb run
        damage_type=DamageType.EXPLOSIVE,
        roles=[Role.BOMBER],
        strong_vs=["buildings", "stationary targets"],
        weak_vs=["fighters", "AA"],
        notes="T1 bomber. Good for sniping mexes/constructors."
    ),
    
    "freedom": Unit(
        name="Freedom Fighter",
        internal_name="armfig",
        unit_type=UnitType.AIRCRAFT,
        tech_level=1,
        metal_cost=100,
        energy_cost=3000,
        build_time=4000,
        health=400,
        speed=270,
        dps=80,
        damage_type=DamageType.LIGHT,
        roles=[Role.FIGHTER],
        strong_vs=["other air"],
        weak_vs=["ground AA"],
        notes="Air superiority. Counter enemy air. Patrol key areas."
    ),
    
    "con_air": Unit(
        name="Construction Aircraft",
        internal_name="armca",
        unit_type=UnitType.AIRCRAFT,
        tech_level=1,
        metal_cost=100,
        energy_cost=4000,
        build_time=5000,
        health=200,
        speed=180,
        build_power=80,
        roles=[Role.CONSTRUCTION],
        notes="80 BP. Slow builder. Use for hard-to-reach spots only."
    ),
    
    # =========================================================================
    # T2 AIRCRAFT
    # =========================================================================
    
    "lance": Unit(
        name="Lance (Torpedo Bomber)",
        internal_name="armlance",
        unit_type=UnitType.AIRCRAFT,
        tech_level=2,
        metal_cost=240,
        energy_cost=6000,
        build_time=8000,
        health=800,
        speed=240,
        dps=300,
        roles=[Role.BOMBER],
        strong_vs=["ships", "subs"],
        weak_vs=["fighters", "AA"],
        notes="T2 torpedo bomber. Anti-navy."
    ),
    
    "stiletto": Unit(
        name="Stiletto (Heavy Gunship)",
        internal_name="armbrawl",
        unit_type=UnitType.AIRCRAFT,
        tech_level=2,
        metal_cost=350,
        energy_cost=8000,
        build_time=9000,
        health=1800,
        speed=150,
        dps=150,
        weapon_range=400,
        damage_type=DamageType.MEDIUM,
        roles=[Role.GUNSHIP],
        strong_vs=["ground units", "buildings"],
        weak_vs=["AA", "fighters"],
        notes="T2 gunship. Hovers and shoots. Good vs ground."
    ),
    
    "lightning": Unit(
        name="Lightning (Strategic Bomber)",
        internal_name="armpnix",
        unit_type=UnitType.AIRCRAFT,
        tech_level=2,
        metal_cost=400,
        energy_cost=15000,
        build_time=12000,
        health=2000,
        speed=240,
        dps=800,  # Per bomb run
        damage_type=DamageType.HEAVY,
        roles=[Role.BOMBER],
        strong_vs=["buildings", "heavy targets"],
        weak_vs=["fighters", "AA"],
        notes="T2 heavy bomber. High damage. Snipe priority targets."
    ),
    
    # =========================================================================
    # COMMANDER
    # =========================================================================
    
    "commander": Unit(
        name="Commander",
        internal_name="armcom",
        unit_type=UnitType.COMMANDER,
        tech_level=1,
        metal_cost=0,  # Starting unit
        energy_cost=0,
        build_time=0,
        health=3500,
        speed=36,
        build_power=200,
        energy_production=25,
        dps=100,
        weapon_range=300,
        damage_type=DamageType.LASER,
        roles=[Role.CONSTRUCTION, Role.ASSAULT],
        notes="200 BP. D-gun kills anything (500 E). Dies = you lose! Explodes big."
    ),
}


# =============================================================================
# COUNTER MATRIX
# =============================================================================

def get_counter(unit_name: str) -> Dict[str, List[str]]:
    """Get what a unit is strong/weak against."""
    if unit_name in UNITS:
        u = UNITS[unit_name]
        return {
            "strong_vs": u.strong_vs,
            "weak_vs": u.weak_vs,
        }
    return {"strong_vs": [], "weak_vs": []}


# Simplified counter relationships for quick reference
COUNTER_MATRIX = {
    # Unit Category -> What beats it
    "scouts": ["any combat unit"],
    "raiders": ["defenses", "assault units", "superior numbers"],
    "assault_bots": ["skirmishers", "artillery", "tanks"],
    "assault_tanks": ["rockeaters", "EMP", "artillery", "skirmishers"],
    "skirmishers": ["raiders", "fast units", "air"],
    "artillery": ["raiders", "air", "fast assault"],
    "defenses": ["rockeaters", "artillery", "bombers", "EMP"],
    "light_air": ["fighters", "AA turrets", "mobile AA"],
    "bombers": ["fighters", "AA", "spread buildings"],
    "gunships": ["flak", "AA missiles", "fighters"],
}


def print_counter_matrix():
    """Print the counter relationships."""
    print("\n" + "=" * 60)
    print("COUNTER MATRIX - What Beats What")
    print("=" * 60)
    for unit_type, counters in COUNTER_MATRIX.items():
        print(f"\n{unit_type.upper()} beaten by:")
        for counter in counters:
            print(f"  • {counter}")


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def get_units_by_role(role: Role) -> List[Unit]:
    """Get all units with a specific role."""
    return [u for u in UNITS.values() if role in u.roles]


def get_units_by_type(unit_type: UnitType) -> List[Unit]:
    """Get all units of a specific type."""
    return [u for u in UNITS.values() if u.unit_type == unit_type]


def get_units_by_tech(tech_level: int) -> List[Unit]:
    """Get all units of a specific tech level."""
    return [u for u in UNITS.values() if u.tech_level == tech_level]


def print_defenses():
    """Print all defense structures."""
    print("\n" + "=" * 70)
    print("DEFENSE STRUCTURES")
    print("=" * 70)
    defenses = get_units_by_type(UnitType.DEFENSE)
    for d in sorted(defenses, key=lambda x: x.metal_cost):
        print(f"\n{d.name} (T{d.tech_level})")
        print(f"  Cost: {d.metal_cost}M / {d.energy_cost}E")
        print(f"  Health: {d.health} | Range: {d.weapon_range} | DPS: {d.dps}")
        if d.strong_vs:
            print(f"  Strong vs: {', '.join(d.strong_vs)}")
        if d.weak_vs:
            print(f"  Weak vs: {', '.join(d.weak_vs)}")
        print(f"  Notes: {d.notes}")


if __name__ == "__main__":
    print("BAR UNIT DATABASE")
    print("=" * 50)
    print(f"Total units in database: {len(UNITS)}")
    print(f"Buildings: {len(get_units_by_type(UnitType.BUILDING))}")
    print(f"Defenses: {len(get_units_by_type(UnitType.DEFENSE))}")
    print(f"Bots: {len(get_units_by_type(UnitType.BOT))}")
    print(f"Vehicles: {len(get_units_by_type(UnitType.VEHICLE))}")
    print(f"Aircraft: {len(get_units_by_type(UnitType.AIRCRAFT))}")
    
    print_defenses()
    print_counter_matrix()
