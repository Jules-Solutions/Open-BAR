"""
BAR Build Order Simulator - Goal Queue System
===============================================
Goal/project queue with override mechanics for directing
economy and production controllers.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple

from bar_sim.econ_ctrl import EconOverride
from bar_sim.models import SimState


# ---------------------------------------------------------------------------
# Goal types
# ---------------------------------------------------------------------------

class GoalType(Enum):
    UNIT_PRODUCTION = "unit_production"       # produce N of unit_key
    STRUCTURE_BUILD = "structure_build"       # build N of unit_key
    ECONOMY_TARGET = "economy_target"         # reach target metal income
    TECH_TRANSITION = "tech_transition"       # get any T2 factory online
    BUILDPOWER_TARGET = "buildpower_target"   # reach total BP threshold


class GoalStatus(Enum):
    PENDING = "pending"
    ACTIVE = "active"
    COMPLETED = "completed"


# ---------------------------------------------------------------------------
# Goal dataclass
# ---------------------------------------------------------------------------

@dataclass
class Goal:
    id: int
    goal_type: GoalType
    description: str = ""

    target_unit: Optional[str] = None        # for unit_production, structure_build
    target_count: int = 1                    # for unit_production, structure_build
    target_value: float = 0.0                # for economy_target, buildpower_target

    status: GoalStatus = GoalStatus.PENDING
    started_at: Optional[int] = None
    completed_at: Optional[int] = None
    progress: float = 0.0

    # What fraction of constructors to dedicate to this goal's project
    project_funding: float = 0.0             # 0.0 = none, 1.0 = all constructors


# ---------------------------------------------------------------------------
# Goal queue
# ---------------------------------------------------------------------------

class GoalQueue:
    def __init__(self):
        self._goals: List[Goal] = []
        self._next_id = 1
        self._completions: List[Tuple[int, str]] = []

    @property
    def goals(self) -> List[Goal]:
        return self._goals

    @property
    def completions(self) -> List[Tuple[int, str]]:
        return self._completions

    def add(
        self,
        goal_type: GoalType,
        description: str = "",
        target_unit: Optional[str] = None,
        target_count: int = 1,
        target_value: float = 0.0,
        project_funding: float = 0.0,
    ) -> Goal:
        g = Goal(
            id=self._next_id,
            goal_type=goal_type,
            description=description,
            target_unit=target_unit,
            target_count=target_count,
            target_value=target_value,
            project_funding=project_funding,
        )
        self._next_id += 1
        self._goals.append(g)
        return g

    def get_active(self) -> Optional[Goal]:
        """Get the first non-completed goal (activate it if pending)."""
        for g in self._goals:
            if g.status == GoalStatus.COMPLETED:
                continue
            if g.status == GoalStatus.PENDING:
                g.status = GoalStatus.ACTIVE
            return g
        return None

    def tick(self, state: SimState, army_by_unit: Dict[str, int], total_bp: float) -> Optional[Goal]:
        """Check completion of active goal, advance queue.

        Returns the newly completed goal if any.
        """
        active = self.get_active()
        if not active:
            return None

        if active.started_at is None:
            active.started_at = state.tick

        completed = self._check_completion(active, state, army_by_unit, total_bp)
        if completed:
            active.status = GoalStatus.COMPLETED
            active.completed_at = state.tick
            active.progress = 1.0
            self._completions.append((state.tick, active.description))
            return active

        # Update progress
        active.progress = self._calc_progress(active, state, army_by_unit, total_bp)
        return None

    def get_overrides(self) -> Tuple[EconOverride, Optional[str]]:
        """Get economy overrides and production override from the active goal.

        Returns:
            (econ_override, prod_override_unit_key_or_None)
        """
        active = self.get_active()
        if not active:
            return EconOverride(), None

        econ = EconOverride()
        prod_override = None

        if active.goal_type == GoalType.UNIT_PRODUCTION:
            prod_override = active.target_unit

        elif active.goal_type == GoalType.STRUCTURE_BUILD:
            econ.force_build = active.target_unit

        elif active.goal_type == GoalType.ECONOMY_TARGET:
            # Reserve metal to avoid spending it all while banking for eco
            econ.reserve_metal = 200.0

        elif active.goal_type == GoalType.TECH_TRANSITION:
            # Reserve for expensive T2 factory
            econ.reserve_metal = 500.0

        return econ, prod_override

    # -----------------------------------------------------------------------
    # Completion checks
    # -----------------------------------------------------------------------

    def _check_completion(
        self,
        goal: Goal,
        state: SimState,
        army_by_unit: Dict[str, int],
        total_bp: float,
    ) -> bool:
        gt = goal.goal_type

        if gt == GoalType.UNIT_PRODUCTION:
            count = army_by_unit.get(goal.target_unit or "", 0)
            return count >= goal.target_count

        elif gt == GoalType.STRUCTURE_BUILD:
            count = state.buildings.get(goal.target_unit or "", 0)
            return count >= goal.target_count

        elif gt == GoalType.ECONOMY_TARGET:
            return state.metal_income >= goal.target_value

        elif gt == GoalType.TECH_TRANSITION:
            t2_factories = {"adv_bot_lab", "adv_vehicle_plant", "adv_aircraft_plant"}
            return any(state.buildings.get(k, 0) > 0 for k in t2_factories)

        elif gt == GoalType.BUILDPOWER_TARGET:
            return total_bp >= goal.target_value

        return False

    def _calc_progress(
        self,
        goal: Goal,
        state: SimState,
        army_by_unit: Dict[str, int],
        total_bp: float,
    ) -> float:
        gt = goal.goal_type

        if gt == GoalType.UNIT_PRODUCTION and goal.target_count > 0:
            count = army_by_unit.get(goal.target_unit or "", 0)
            return min(1.0, count / goal.target_count)

        elif gt == GoalType.STRUCTURE_BUILD and goal.target_count > 0:
            count = state.buildings.get(goal.target_unit or "", 0)
            return min(1.0, count / goal.target_count)

        elif gt == GoalType.ECONOMY_TARGET and goal.target_value > 0:
            return min(1.0, state.metal_income / goal.target_value)

        elif gt == GoalType.TECH_TRANSITION:
            # Binary
            return 1.0 if self._check_completion(goal, state, army_by_unit, total_bp) else 0.0

        elif gt == GoalType.BUILDPOWER_TARGET and goal.target_value > 0:
            return min(1.0, total_bp / goal.target_value)

        return 0.0


# ---------------------------------------------------------------------------
# Parse goal from string (for CLI)
# ---------------------------------------------------------------------------

def parse_goal_string(s: str) -> Optional[Goal]:
    """Parse 'economy_target:20' or 'unit_production:grunt:5' into a Goal-add call.

    Returns a Goal object (with id=0, to be replaced by GoalQueue.add).
    """
    parts = s.strip().split(":")
    if not parts:
        return None

    type_str = parts[0].strip()
    try:
        goal_type = GoalType(type_str)
    except ValueError:
        return None

    target_unit = None
    target_count = 1
    target_value = 0.0
    description = type_str

    if goal_type in (GoalType.UNIT_PRODUCTION, GoalType.STRUCTURE_BUILD):
        if len(parts) >= 2:
            target_unit = parts[1].strip()
        if len(parts) >= 3:
            target_count = int(parts[2].strip())
        description = f"{type_str}: {target_unit} x{target_count}"

    elif goal_type in (GoalType.ECONOMY_TARGET, GoalType.BUILDPOWER_TARGET):
        if len(parts) >= 2:
            target_value = float(parts[1].strip())
        description = f"{type_str}: {target_value}"

    elif goal_type == GoalType.TECH_TRANSITION:
        description = "Tech transition to T2"

    return Goal(
        id=0,
        goal_type=goal_type,
        description=description,
        target_unit=target_unit,
        target_count=target_count,
        target_value=target_value,
    )
