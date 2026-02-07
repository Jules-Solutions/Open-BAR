"""
BAR Build Order Simulator - I/O
================================
Load and save build orders from YAML files.
"""

import json
import yaml
from pathlib import Path
from bar_sim.models import BuildOrder, BuildAction, BuildActionType, MapConfig
from bar_sim.strategy import StrategyConfig, parse_strategy_string
from bar_sim.goals import GoalQueue, GoalType, parse_goal_string


def load_build_order(filepath: str) -> BuildOrder:
    with open(filepath, "r") as f:
        data = yaml.safe_load(f)

    map_name = data.get("map_name")
    map_data = data.get("map", {})

    # If map_name is set, try to auto-resolve MapConfig from real map data
    if map_name:
        try:
            from bar_sim.map_data import get_map_data, map_data_to_map_config
            md = get_map_data(map_name)
            if md:
                mc = map_data_to_map_config(md)
            else:
                mc = MapConfig(**{k: map_data[k] for k in map_data if k in MapConfig.__dataclass_fields__})
        except Exception:
            mc = MapConfig(**{k: map_data[k] for k in map_data if k in MapConfig.__dataclass_fields__})
    else:
        mc = MapConfig(
            avg_wind=map_data.get("avg_wind", 12.0),
            wind_variance=map_data.get("wind_variance", 3.0),
            mex_value=map_data.get("mex_value", 2.0),
            mex_spots=map_data.get("mex_spots", 6),
            has_geo=map_data.get("has_geo", False),
            tidal_value=map_data.get("tidal_value", 0.0),
            reclaim_metal=map_data.get("reclaim_metal", 0.0),
        )

    bo = BuildOrder(
        name=data.get("name", Path(filepath).stem),
        description=data.get("description", ""),
        map_config=mc,
        map_name=map_name,
    )

    # Commander queue
    for item in data.get("commander_queue", []):
        bo.commander_queue.append(
            BuildAction(unit_key=item, action_type=BuildActionType.BUILD_STRUCTURE)
        )

    # Factory queues (factory_0_queue, factory_1_queue, etc.)
    for key, value in data.items():
        if key.startswith("factory_") and key.endswith("_queue"):
            factory_id = key.replace("_queue", "")
            bo.factory_queues[factory_id] = [
                BuildAction(unit_key=item, action_type=BuildActionType.PRODUCE_UNIT)
                for item in value
            ]

    # Constructor queues (con_1_queue, con_2_queue, etc.)
    for key, value in data.items():
        if key.startswith("con_") and key.endswith("_queue"):
            con_id = key.replace("_queue", "")
            bo.constructor_queues[con_id] = [
                BuildAction(unit_key=item, action_type=BuildActionType.BUILD_STRUCTURE)
                for item in value
            ]

    # Strategy config (optional)
    strat_data = data.get("strategy")
    if strat_data:
        bo.strategy_config = _parse_strategy_block(strat_data)

    return bo


def save_build_order(bo: BuildOrder, filepath: str):
    data = {
        "name": bo.name,
        "description": bo.description,
    }
    if bo.map_name:
        data["map_name"] = bo.map_name
    data["map"] = {
        "avg_wind": bo.map_config.avg_wind,
        "wind_variance": bo.map_config.wind_variance,
        "mex_value": bo.map_config.mex_value,
        "mex_spots": bo.map_config.mex_spots,
        "has_geo": bo.map_config.has_geo,
        "tidal_value": bo.map_config.tidal_value,
    }
    data["commander_queue"] = [a.unit_key for a in bo.commander_queue]
    for fid, queue in bo.factory_queues.items():
        data[f"{fid}_queue"] = [a.unit_key for a in queue]
    for cid, queue in bo.constructor_queues.items():
        data[f"{cid}_queue"] = [a.unit_key for a in queue]

    if bo.strategy_config:
        data["strategy"] = _serialize_strategy(bo.strategy_config)

    with open(filepath, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def export_build_order_json(bo: BuildOrder, filepath: str):
    """Export build order as JSON for Lua widget consumption."""
    data = {
        "name": bo.name,
        "commander_queue": [a.unit_key for a in bo.commander_queue],
    }
    for fid, queue in bo.factory_queues.items():
        data[f"{fid}_queue"] = [a.unit_key for a in queue]
    for cid, queue in bo.constructor_queues.items():
        data[f"{cid}_queue"] = [a.unit_key for a in queue]

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)


# ---------------------------------------------------------------------------
# Strategy YAML helpers
# ---------------------------------------------------------------------------

def _parse_strategy_block(strat_data: dict) -> StrategyConfig:
    """Parse a strategy: YAML block into a StrategyConfig."""
    from bar_sim.strategy import (
        EnergyStrategy, UnitComposition, Posture, T2Timing,
        Role, AttackStrategy, EmergencyMode,
    )
    enum_fields = {
        "energy_strategy": EnergyStrategy,
        "unit_composition": UnitComposition,
        "posture": Posture,
        "t2_timing": T2Timing,
        "role": Role,
        "attack_strategy": AttackStrategy,
        "emergency_mode": EmergencyMode,
    }
    int_fields = {"opening_mex_count", "econ_army_balance", "emergency_start_tick",
                  "emergency_duration", "rally_threshold"}

    config = StrategyConfig()
    for key, val in strat_data.items():
        if key in enum_fields:
            setattr(config, key, enum_fields[key](val))
        elif key in int_fields:
            setattr(config, key, int(val))
    return config


def _serialize_strategy(config: StrategyConfig) -> dict:
    """Serialize a StrategyConfig to a YAML-friendly dict."""
    return {
        "opening_mex_count": config.opening_mex_count,
        "energy_strategy": config.energy_strategy.value,
        "unit_composition": config.unit_composition.value,
        "posture": config.posture.value,
        "t2_timing": config.t2_timing.value,
        "econ_army_balance": config.econ_army_balance,
        "role": config.role.value,
        "attack_strategy": config.attack_strategy.value,
        "emergency_mode": config.emergency_mode.value,
    }
