"""
BAR Build Order Simulator - Production Controller
===================================================
Deficit-based factory production decisions.
Mirrors engine_totallylegal_prod.lua QueueProduction logic.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from bar_sim.models import BuildAction, BuildActionType
from bar_sim.strategy import (
    StrategyConfig, UnitComposition, UnitRole, Role, EmergencyMode,
    UNIT_ROLE_MAP, COMPOSITIONS, FACTORY_BUILDLISTS,
    apply_role_adjustments,
)


# ---------------------------------------------------------------------------
# Army composition tracking
# ---------------------------------------------------------------------------

@dataclass
class ArmyComposition:
    counts_by_role: Dict[str, int] = field(default_factory=dict)   # role.value -> count
    counts_by_unit: Dict[str, int] = field(default_factory=dict)   # unit_key -> count
    total_combat: int = 0
    total_value: float = 0.0
    units_produced: int = 0

    def record_unit(self, unit_key: str, metal_cost: float = 0.0):
        """Record a produced unit into the composition tracker."""
        role = UNIT_ROLE_MAP.get(unit_key)
        self.counts_by_unit[unit_key] = self.counts_by_unit.get(unit_key, 0) + 1
        self.units_produced += 1

        if role:
            role_key = role.value
            self.counts_by_role[role_key] = self.counts_by_role.get(role_key, 0) + 1
            if role not in (UnitRole.CONSTRUCTOR, UnitRole.UTILITY):
                self.total_combat += 1
                self.total_value += metal_cost

    def get_role_count(self, role: UnitRole) -> int:
        return self.counts_by_role.get(role.value, 0)


# ---------------------------------------------------------------------------
# Factory production selection
# ---------------------------------------------------------------------------

def cheapest_combat_unit(factory_type: str) -> Optional[str]:
    """Find the cheapest non-constructor, non-utility unit a factory can build."""
    from bar_sim.econ import UNITS as ECON_UNITS

    buildlist = FACTORY_BUILDLISTS.get(factory_type, [])
    best_key = None
    best_cost = float("inf")

    for key in buildlist:
        role = UNIT_ROLE_MAP.get(key)
        if role and role not in (UnitRole.CONSTRUCTOR, UnitRole.UTILITY):
            unit = ECON_UNITS.get(key)
            cost = unit.metal_cost if unit else float("inf")
            if cost < best_cost:
                best_cost = cost
                best_key = key

    return best_key


def _find_best_unit_for_role(buildlist: List[str], target_role: UnitRole) -> Optional[str]:
    """Find the most expensive unit matching target_role in a factory's buildlist.

    Mirrors Lua FindBestUnit: picks highest metal cost match.
    """
    from bar_sim.econ import UNITS as ECON_UNITS

    best_key = None
    best_cost = -1.0

    for key in buildlist:
        role = UNIT_ROLE_MAP.get(key)
        if role == target_role:
            unit = ECON_UNITS.get(key)
            cost = unit.metal_cost if unit else 0
            if cost > best_cost:
                best_cost = cost
                best_key = key

    return best_key


def choose_factory_production(
    config: StrategyConfig,
    army: ArmyComposition,
    factory_type: str,
    prod_override: Optional[str] = None,
) -> Optional[BuildAction]:
    """Choose what a factory should produce next.

    Args:
        config: Active strategy config.
        army: Current army composition.
        factory_type: Key of the factory (e.g. "bot_lab").
        prod_override: If set, force-produce this unit_key (from goal system).

    Returns:
        BuildAction or None if nothing to produce.
    """
    buildlist = FACTORY_BUILDLISTS.get(factory_type, [])
    if not buildlist:
        return None

    # Goal override: produce specific unit if factory can build it
    if prod_override and prod_override in buildlist:
        return BuildAction(unit_key=prod_override, action_type=BuildActionType.PRODUCE_UNIT)

    # Emergency: mobilization -> flood cheapest combat unit
    if config.emergency_mode == EmergencyMode.MOBILIZATION:
        key = cheapest_combat_unit(factory_type)
        if key:
            return BuildAction(unit_key=key, action_type=BuildActionType.PRODUCE_UNIT)
        return None

    # Get composition weights
    comp_key = config.unit_composition.value
    weights = COMPOSITIONS.get(comp_key, COMPOSITIONS["mixed"])

    # Apply role adjustments
    weights = apply_role_adjustments(weights, config.role)

    # Deficit-based selection: find role with highest deficit
    total_combat = max(army.total_combat, 10)
    best_role: Optional[UnitRole] = None
    best_deficit = float("-inf")

    for unit_role, weight in weights.items():
        desired = weight * total_combat
        actual = army.get_role_count(unit_role)
        deficit = desired - actual

        if deficit > best_deficit:
            # Check if factory can build this role
            unit_key = _find_best_unit_for_role(buildlist, unit_role)
            if unit_key:
                best_deficit = deficit
                best_role = unit_role

    if best_role:
        unit_key = _find_best_unit_for_role(buildlist, best_role)
        if unit_key:
            return BuildAction(unit_key=unit_key, action_type=BuildActionType.PRODUCE_UNIT)

    return None
