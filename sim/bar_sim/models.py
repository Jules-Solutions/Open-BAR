"""
BAR Build Order Simulator - Data Models
========================================
All dataclasses for the simulation engine.
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple
from enum import Enum, auto


# ---------------------------------------------------------------------------
# Map configuration
# ---------------------------------------------------------------------------

@dataclass
class MapConfig:
    avg_wind: float = 12.0
    wind_variance: float = 3.0
    mex_value: float = 2.0
    mex_spots: int = 6
    has_geo: bool = False
    tidal_value: float = 0.0
    reclaim_metal: float = 0.0


# ---------------------------------------------------------------------------
# Map data (from real map files)
# ---------------------------------------------------------------------------

@dataclass
class MexSpot:
    x: float
    z: float
    metal: float = 2.0


@dataclass
class GeoVent:
    x: float
    z: float


@dataclass
class StartPosition:
    x: float
    z: float
    team_id: int = 0


@dataclass
class MapData:
    """Complete map data from archive parsing + runtime scanning."""
    name: str
    filename: str

    shortname: str = ""
    map_width: int = 0
    map_height: int = 0
    wind_min: float = 0.0
    wind_max: float = 25.0
    tidal_strength: float = 0.0
    gravity: float = 100.0
    max_metal: float = 2.0
    extractor_radius: float = 90.0

    start_positions: List["StartPosition"] = field(default_factory=list)
    mex_spots: List["MexSpot"] = field(default_factory=list)
    geo_vents: List["GeoVent"] = field(default_factory=list)

    total_reclaim_metal: float = 0.0
    total_reclaim_energy: float = 0.0

    author: str = ""
    description: str = ""
    source: str = "unknown"  # "cache", "mapinfo", "scanned"


# ---------------------------------------------------------------------------
# Build order definitions
# ---------------------------------------------------------------------------

class BuildActionType(Enum):
    BUILD_STRUCTURE = auto()
    PRODUCE_UNIT = auto()
    ASSIST = auto()
    RECLAIM = auto()


@dataclass
class BuildAction:
    unit_key: str
    action_type: BuildActionType = BuildActionType.BUILD_STRUCTURE
    repeat: int = 1


@dataclass
class BuildOrder:
    name: str
    description: str = ""
    map_config: MapConfig = field(default_factory=MapConfig)
    map_name: Optional[str] = None  # if set, auto-resolve MapConfig from map data
    commander_queue: List[BuildAction] = field(default_factory=list)
    factory_queues: Dict[str, List[BuildAction]] = field(default_factory=dict)
    constructor_queues: Dict[str, List[BuildAction]] = field(default_factory=dict)
    strategy_config: Optional["StrategyConfig"] = None  # enables strategy mode when set


# ---------------------------------------------------------------------------
# Runtime simulation entities
# ---------------------------------------------------------------------------

@dataclass
class BuildTask:
    task_id: int
    unit_key: str
    action_type: BuildActionType
    total_build_work: float        # BP-seconds needed
    metal_cost_total: float = 0.0
    energy_cost_total: float = 0.0

    work_done: float = 0.0
    metal_spent: float = 0.0
    energy_spent: float = 0.0
    walk_delay: int = 0            # ticks of walking before build starts

    assigned_builders: List[str] = field(default_factory=list)
    started_at: int = 0
    completed_at: Optional[int] = None

    # Transient per-tick values (set during expenditure calc)
    _pending_bp: float = 0.0
    _pending_metal_drain: float = 0.0
    _pending_energy_drain: float = 0.0

    @property
    def progress(self) -> float:
        return min(1.0, self.work_done / self.total_build_work) if self.total_build_work > 0 else 1.0

    @property
    def is_complete(self) -> bool:
        return self.work_done >= self.total_build_work


@dataclass
class Builder:
    builder_id: str
    build_power: int
    builder_type: str              # "commander", "factory", "constructor", "nano"

    current_task: Optional[BuildTask] = None
    queue: List[BuildAction] = field(default_factory=list)
    queue_index: int = 0

    is_active: bool = True
    activated_at: int = 0
    is_idle: bool = True

    assist_target: Optional[str] = None  # for nanos


# ---------------------------------------------------------------------------
# Simulation state
# ---------------------------------------------------------------------------

@dataclass
class SimState:
    tick: int = 0

    metal_stored: float = 500.0
    energy_stored: float = 1000.0
    metal_storage_cap: float = 500.0
    energy_storage_cap: float = 1000.0

    metal_income: float = 0.0
    energy_income: float = 0.0
    metal_expenditure: float = 0.0
    energy_expenditure: float = 0.0

    metal_stall_factor: float = 1.0
    energy_stall_factor: float = 1.0
    effective_stall_factor: float = 1.0

    buildings: Dict[str, int] = field(default_factory=dict)
    units: Dict[str, int] = field(default_factory=dict)

    builders: Dict[str, Builder] = field(default_factory=dict)
    active_tasks: List[BuildTask] = field(default_factory=list)
    completed_tasks: List[BuildTask] = field(default_factory=list)

    active_converters_t1: int = 0
    active_converters_t2: int = 0
    current_wind: float = 0.0

    # Strategy mode fields
    army_by_role: Dict[str, int] = field(default_factory=dict)
    econ_state: str = "balanced"
    emergency_active: bool = False
    emergency_start_tick: Optional[int] = None


# ---------------------------------------------------------------------------
# Simulation results
# ---------------------------------------------------------------------------

@dataclass
class Milestone:
    tick: int
    event: str
    description: str
    metal_income: float = 0.0
    energy_income: float = 0.0


@dataclass
class StallEvent:
    start_tick: int
    end_tick: int = 0
    resource: str = "metal"
    severity: float = 0.0


@dataclass
class Snapshot:
    tick: int
    metal_income: float = 0.0
    energy_income: float = 0.0
    metal_stored: float = 0.0
    energy_stored: float = 0.0
    metal_expenditure: float = 0.0
    energy_expenditure: float = 0.0
    build_power: int = 0
    army_value_metal: float = 0.0
    stall_factor: float = 1.0
    unit_counts: Dict[str, int] = field(default_factory=dict)
    army_by_role: Dict[str, int] = field(default_factory=dict)
    econ_state: str = "balanced"


@dataclass
class SimResult:
    build_order_name: str = ""
    total_ticks: int = 0

    milestones: List[Milestone] = field(default_factory=list)
    stall_events: List[StallEvent] = field(default_factory=list)
    completion_log: List[Tuple[int, str, str]] = field(default_factory=list)
    snapshots: List[Snapshot] = field(default_factory=list)

    time_to_first_factory: Optional[int] = None
    time_to_first_constructor: Optional[int] = None
    time_to_first_nano: Optional[int] = None
    time_to_t2_lab: Optional[int] = None
    peak_metal_income: float = 0.0
    peak_energy_income: float = 0.0
    total_metal_stall_seconds: int = 0
    total_energy_stall_seconds: int = 0
    total_army_metal_value: float = 0.0

    # Strategy mode results
    army_composition_final: Dict[str, int] = field(default_factory=dict)
    goal_completions: List[Tuple[int, str]] = field(default_factory=list)
    strategy_used: Optional[str] = None
