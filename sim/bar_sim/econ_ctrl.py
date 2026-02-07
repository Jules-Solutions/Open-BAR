"""
BAR Build Order Simulator - Economy Controller
================================================
Dynamic constructor/commander build decisions based on economy state.
Mirrors engine_totallylegal_econ.lua AnalyzeEconomy + GetBuildTask logic.
"""

from dataclasses import dataclass, field
from typing import Optional, Tuple

from bar_sim.models import BuildAction, BuildActionType, SimState
from bar_sim.strategy import StrategyConfig, Role, EmergencyMode


# ---------------------------------------------------------------------------
# Economy state classification
# (mirrors Lua AnalyzeEconomy thresholds)
# ---------------------------------------------------------------------------

STALL_THRESHOLD = 0.05   # < 5% storage = stalling
FLOAT_THRESHOLD = 0.80   # > 80% storage = floating


def classify_econ_state(state: SimState) -> str:
    """Classify economy into a state string.

    Returns one of: "metal_stall", "energy_stall", "metal_float",
    "energy_float", "balanced".
    """
    metal_fill = state.metal_stored / state.metal_storage_cap if state.metal_storage_cap > 0 else 0
    energy_fill = state.energy_stored / state.energy_storage_cap if state.energy_storage_cap > 0 else 0

    if metal_fill < STALL_THRESHOLD:
        return "metal_stall"
    elif energy_fill < STALL_THRESHOLD:
        return "energy_stall"
    elif metal_fill > FLOAT_THRESHOLD:
        return "metal_float"
    elif energy_fill > FLOAT_THRESHOLD:
        return "energy_float"
    else:
        return "balanced"


# ---------------------------------------------------------------------------
# Economy build priority table
# (mirrors Lua BUILD_PRIORITY in engine_totallylegal_econ.lua)
# ---------------------------------------------------------------------------

# (unit_key, condition, priority)
ECON_PRIORITIES = [
    ("mex",          "metal_stall",  100),
    ("wind",         "energy_stall",  90),
    ("solar",        "energy_stall",  85),
    ("mex",          "always",        70),
    ("wind",         "always",        50),
    ("converter_t1", "energy_float",  40),
]


# ---------------------------------------------------------------------------
# Economy override (from goal system)
# ---------------------------------------------------------------------------

@dataclass
class EconOverride:
    force_build: Optional[str] = None        # force build this unit_key
    suppress_econ: bool = False              # skip econ building (e.g. mobilization)
    reserve_metal: float = 0.0              # suppress metal_float while banking
    reserve_energy: float = 0.0             # suppress energy_float while banking


# ---------------------------------------------------------------------------
# Build decision
# ---------------------------------------------------------------------------

def choose_econ_build(
    config: StrategyConfig,
    state: SimState,
    econ_state: str,
    remaining_mex: int,
    override: Optional[EconOverride] = None,
) -> Optional[BuildAction]:
    """Choose what a constructor/commander should build next.

    Args:
        config: Active strategy config.
        state: Current simulation state.
        econ_state: Classified economy state string.
        remaining_mex: How many mex spots are still available.
        override: Goal-system overrides.

    Returns:
        BuildAction or None if nothing to build.
    """
    role = config.role
    emergency = config.emergency_mode

    # Emergency: defend_base -> build LLT
    if emergency == EmergencyMode.DEFEND_BASE:
        return BuildAction(unit_key="llt", action_type=BuildActionType.BUILD_STRUCTURE)

    # Emergency: mobilization -> skip econ building entirely
    if emergency == EmergencyMode.MOBILIZATION:
        return None

    # Override: suppress econ
    if override and override.suppress_econ:
        return None

    # Override: forced build
    if override and override.force_build:
        return BuildAction(unit_key=override.force_build, action_type=BuildActionType.BUILD_STRUCTURE)

    # Apply reserve thresholds (suppress float while banking)
    adjusted_econ = econ_state
    if override:
        if (override.reserve_metal > 0
                and state.metal_stored < override.reserve_metal
                and adjusted_econ == "metal_float"):
            adjusted_econ = "balanced"
        if (override.reserve_energy > 0
                and state.energy_stored < override.reserve_energy
                and adjusted_econ == "energy_float"):
            adjusted_econ = "balanced"

    # Role: eco -> always try mex first
    if role == Role.ECO and remaining_mex > 0:
        return BuildAction(unit_key="mex", action_type=BuildActionType.BUILD_STRUCTURE)

    # Standard priority iteration
    for key, condition, _prio in ECON_PRIORITIES:
        if condition == "always" or condition == adjusted_econ:
            # Skip mex if no spots left
            if key == "mex" and remaining_mex <= 0:
                continue
            return BuildAction(unit_key=key, action_type=BuildActionType.BUILD_STRUCTURE)

    # Role: support -> fallback to radar
    if role == Role.SUPPORT:
        return BuildAction(unit_key="radar", action_type=BuildActionType.BUILD_STRUCTURE)

    return None
