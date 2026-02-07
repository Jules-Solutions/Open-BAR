"""
BAR Build Order Simulator - Strategy System
============================================
Enums, StrategyConfig, unit role mapping, composition tables,
role adjustments, and opening build generation.

Mirrors the TotallyLegal Lua widget strategy system for parity.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional

from bar_sim.models import BuildAction, BuildActionType


# ---------------------------------------------------------------------------
# Strategy enums (mirror Lua engine_totallylegal_config.lua)
# ---------------------------------------------------------------------------

class EnergyStrategy(Enum):
    AUTO = "auto"
    WIND_ONLY = "wind_only"
    SOLAR_ONLY = "solar_only"
    MIXED = "mixed"


class UnitComposition(Enum):
    BOTS = "bots"
    VEHICLES = "vehicles"
    MIXED = "mixed"


class Posture(Enum):
    DEFENSIVE = "defensive"
    BALANCED = "balanced"
    AGGRESSIVE = "aggressive"


class T2Timing(Enum):
    EARLY = "early"
    STANDARD = "standard"
    LATE = "late"


class Role(Enum):
    BALANCED = "balanced"
    ECO = "eco"
    AGGRO = "aggro"
    SUPPORT = "support"


class AttackStrategy(Enum):
    NONE = "none"
    CREEPING = "creeping"
    PIERCING = "piercing"
    FAKE_RETREAT = "fake_retreat"
    ANTI_AA_RAID = "anti_aa_raid"


class EmergencyMode(Enum):
    NONE = "none"
    DEFEND_BASE = "defend_base"
    MOBILIZATION = "mobilization"


# ---------------------------------------------------------------------------
# Unit roles (for army composition tracking)
# ---------------------------------------------------------------------------

class UnitRole(Enum):
    SCOUT = "scout"
    RAIDER = "raider"
    ASSAULT = "assault"
    SKIRMISHER = "skirmisher"
    LIGHT_TANK = "light_tank"
    HEAVY_TANK = "heavy_tank"
    ARTILLERY = "artillery"
    AA = "aa"
    CONSTRUCTOR = "constructor"
    UTILITY = "utility"
    AIRCRAFT = "aircraft"


# Map from unit short_key -> UnitRole
# Mirrors Lua engine_totallylegal_prod.lua BuildRoleMappings()
UNIT_ROLE_MAP: Dict[str, UnitRole] = {
    # Bots
    "tick":         UnitRole.SCOUT,
    "pawn":         UnitRole.RAIDER,
    "grunt":        UnitRole.ASSAULT,
    "rocketer":     UnitRole.SKIRMISHER,
    "rez_bot":      UnitRole.UTILITY,
    "con_bot":      UnitRole.CONSTRUCTOR,
    "adv_con_bot":  UnitRole.CONSTRUCTOR,

    # Vehicles
    "flash":        UnitRole.RAIDER,
    "stumpy":       UnitRole.LIGHT_TANK,
    "con_vehicle":  UnitRole.CONSTRUCTOR,
    "adv_con_vehicle": UnitRole.CONSTRUCTOR,
}


# ---------------------------------------------------------------------------
# Composition tables (mirror Lua COMPOSITIONS in engine_totallylegal_prod.lua)
# ---------------------------------------------------------------------------

COMPOSITIONS: Dict[str, Dict[UnitRole, float]] = {
    "bots": {
        UnitRole.RAIDER:     0.40,
        UnitRole.ASSAULT:    0.30,
        UnitRole.SKIRMISHER: 0.20,
        UnitRole.AA:         0.10,
    },
    "vehicles": {
        UnitRole.SCOUT:      0.10,
        UnitRole.LIGHT_TANK: 0.30,
        UnitRole.HEAVY_TANK: 0.30,
        UnitRole.ARTILLERY:  0.20,
        UnitRole.AA:         0.10,
    },
    "mixed": {
        UnitRole.RAIDER:      0.25,
        UnitRole.ASSAULT:     0.25,
        UnitRole.LIGHT_TANK:  0.20,
        UnitRole.SKIRMISHER:  0.15,
        UnitRole.AA:          0.10,
        UnitRole.CONSTRUCTOR: 0.05,
    },
}


# ---------------------------------------------------------------------------
# Factory build lists (which units each factory can produce)
# ---------------------------------------------------------------------------

FACTORY_BUILDLISTS: Dict[str, List[str]] = {
    "bot_lab":           ["tick", "pawn", "grunt", "rocketer", "con_bot", "rez_bot"],
    "vehicle_plant":     ["flash", "stumpy", "con_vehicle"],
    "aircraft_plant":    [],  # not yet modeled
    "adv_bot_lab":       ["adv_con_bot"],
    "adv_vehicle_plant": ["adv_con_vehicle"],
    "adv_aircraft_plant": [],
}


# ---------------------------------------------------------------------------
# Strategy configuration (mirror Lua engine_totallylegal_config.lua strategy table)
# ---------------------------------------------------------------------------

@dataclass
class StrategyConfig:
    opening_mex_count: int = 2             # 1-4
    energy_strategy: EnergyStrategy = EnergyStrategy.AUTO
    unit_composition: UnitComposition = UnitComposition.BOTS
    posture: Posture = Posture.BALANCED
    t2_timing: T2Timing = T2Timing.STANDARD
    econ_army_balance: int = 50            # 0=all army, 100=all econ
    role: Role = Role.BALANCED
    attack_strategy: AttackStrategy = AttackStrategy.NONE

    emergency_mode: EmergencyMode = EmergencyMode.NONE
    emergency_start_tick: Optional[int] = None
    emergency_duration: int = 60           # seconds (= ticks in sim)

    rally_threshold: int = 5

    def summary(self) -> str:
        parts = [
            f"role={self.role.value}",
            f"comp={self.unit_composition.value}",
            f"posture={self.posture.value}",
        ]
        if self.energy_strategy != EnergyStrategy.AUTO:
            parts.append(f"energy={self.energy_strategy.value}")
        if self.emergency_mode != EmergencyMode.NONE:
            parts.append(f"emergency={self.emergency_mode.value}")
        return ", ".join(parts)


# ---------------------------------------------------------------------------
# Role-based composition adjustments
# (mirror Lua engine_totallylegal_prod.lua QueueProduction role adjustments)
# ---------------------------------------------------------------------------

def apply_role_adjustments(
    weights: Dict[UnitRole, float],
    role: Role,
) -> Dict[UnitRole, float]:
    """Apply role-based adjustments to composition weights.

    Returns a new dict (does not mutate input).
    """
    if role == Role.BALANCED:
        return dict(weights)

    adjusted = {}
    for unit_role, w in weights.items():
        if role == Role.AGGRO:
            if unit_role in (UnitRole.RAIDER, UnitRole.ASSAULT):
                w = w + 0.10
            elif unit_role == UnitRole.CONSTRUCTOR:
                w = 0.0
        elif role == Role.ECO:
            if unit_role == UnitRole.CONSTRUCTOR:
                w = 0.15
        elif role == Role.SUPPORT:
            if unit_role in (UnitRole.CONSTRUCTOR, UnitRole.UTILITY):
                w = w + 0.05
        adjusted[unit_role] = w

    return adjusted


# ---------------------------------------------------------------------------
# Opening build generation
# (mirrors TotallyLegal opening: mex*N, energy, factory, wind, wind, mex)
# ---------------------------------------------------------------------------

def _factory_key_for_composition(comp: UnitComposition) -> str:
    if comp == UnitComposition.VEHICLES:
        return "vehicle_plant"
    return "bot_lab"  # bots and mixed both use bot_lab


def generate_opening(config: StrategyConfig) -> List[BuildAction]:
    """Generate commander opening build queue from strategy config.

    Mirrors the standard BAR opening pattern:
    1. mex x opening_mex_count
    2. energy (strategy-dependent)
    3. factory
    4. wind, wind
    5. mex
    """
    actions: List[BuildAction] = []

    # 1. Opening mexes
    for _ in range(config.opening_mex_count):
        actions.append(BuildAction(unit_key="mex", action_type=BuildActionType.BUILD_STRUCTURE))

    # 2. Energy (based on strategy)
    es = config.energy_strategy
    if es == EnergyStrategy.AUTO or es == EnergyStrategy.WIND_ONLY:
        actions.append(BuildAction(unit_key="wind", action_type=BuildActionType.BUILD_STRUCTURE))
        actions.append(BuildAction(unit_key="wind", action_type=BuildActionType.BUILD_STRUCTURE))
    elif es == EnergyStrategy.SOLAR_ONLY:
        actions.append(BuildAction(unit_key="solar", action_type=BuildActionType.BUILD_STRUCTURE))
    elif es == EnergyStrategy.MIXED:
        actions.append(BuildAction(unit_key="wind", action_type=BuildActionType.BUILD_STRUCTURE))
        actions.append(BuildAction(unit_key="solar", action_type=BuildActionType.BUILD_STRUCTURE))

    # 3. Factory
    factory_key = _factory_key_for_composition(config.unit_composition)
    actions.append(BuildAction(unit_key=factory_key, action_type=BuildActionType.BUILD_STRUCTURE))

    # 4. Post-factory energy
    actions.append(BuildAction(unit_key="wind", action_type=BuildActionType.BUILD_STRUCTURE))
    actions.append(BuildAction(unit_key="wind", action_type=BuildActionType.BUILD_STRUCTURE))

    # 5. Extra mex
    actions.append(BuildAction(unit_key="mex", action_type=BuildActionType.BUILD_STRUCTURE))

    return actions


# ---------------------------------------------------------------------------
# Utility: parse strategy config from a key=value string
# ---------------------------------------------------------------------------

_ENUM_MAP = {
    "energy_strategy": EnergyStrategy,
    "unit_composition": UnitComposition,
    "posture": Posture,
    "t2_timing": T2Timing,
    "role": Role,
    "attack_strategy": AttackStrategy,
    "emergency_mode": EmergencyMode,
}

_INT_FIELDS = {"opening_mex_count", "econ_army_balance", "emergency_start_tick",
               "emergency_duration", "rally_threshold"}


def parse_strategy_string(s: str) -> StrategyConfig:
    """Parse 'role=aggro,composition=bots,posture=aggressive' into StrategyConfig."""
    config = StrategyConfig()
    if not s or not s.strip():
        return config

    for part in s.split(","):
        part = part.strip()
        if "=" not in part:
            continue
        key, val = part.split("=", 1)
        key = key.strip()
        val = val.strip()

        # Handle common aliases
        if key == "composition":
            key = "unit_composition"
        if key == "energy":
            key = "energy_strategy"
        if key == "emergency":
            key = "emergency_mode"
        if key == "attack":
            key = "attack_strategy"

        if key in _ENUM_MAP:
            enum_cls = _ENUM_MAP[key]
            setattr(config, key, enum_cls(val))
        elif key in _INT_FIELDS:
            setattr(config, key, int(val))

    return config
