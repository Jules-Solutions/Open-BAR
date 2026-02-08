"""Shared test fixtures for the BAR simulator test suite."""

import sys
from pathlib import Path

import pytest

# Ensure sim/ is on the path so `bar_sim` imports work
SIM_ROOT = Path(__file__).parent.parent
if str(SIM_ROOT) not in sys.path:
    sys.path.insert(0, str(SIM_ROOT))

from bar_sim.models import (
    BuildOrder, BuildAction, BuildActionType,
    MapConfig, MexSpot, StartPosition, MapData,
)


@pytest.fixture
def default_map_config():
    """Standard 1v1 map config with decent wind."""
    return MapConfig(
        avg_wind=12.0,
        wind_variance=3.0,
        mex_value=2.0,
        mex_spots=6,
        has_geo=False,
    )


@pytest.fixture
def wind_opening_bo(default_map_config):
    """Simple wind opening: 2 mex, 2 wind, 1 factory."""
    return BuildOrder(
        name="Test Wind Opening",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="mex"),
            BuildAction(unit_key="mex"),
            BuildAction(unit_key="wind"),
            BuildAction(unit_key="wind"),
            BuildAction(unit_key="bot_lab"),
        ],
    )


@pytest.fixture
def simple_mex_bo(default_map_config):
    """Just build a single mex — minimal test case."""
    return BuildOrder(
        name="Single Mex",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="mex"),
        ],
    )


@pytest.fixture
def sample_mex_spots():
    """Mex spots arranged in a line from start position."""
    return [
        MexSpot(x=300, z=300, metal=2.0),
        MexSpot(x=600, z=300, metal=2.0),
        MexSpot(x=900, z=500, metal=2.0),
        MexSpot(x=1400, z=800, metal=2.0),
    ]


@pytest.fixture
def sample_start_pos():
    return StartPosition(x=200, z=200, team_id=0)


@pytest.fixture
def sample_map_data(sample_mex_spots):
    """MapData for a simple test map."""
    return MapData(
        name="Test Map",
        filename="test_map.sd7",
        shortname="TestMap",
        map_width=8192,
        map_height=8192,
        wind_min=5.0,
        wind_max=15.0,
        max_metal=2.0,
        start_positions=[
            StartPosition(x=200, z=200, team_id=0),
            StartPosition(x=7992, z=7992, team_id=1),
        ],
        mex_spots=sample_mex_spots,
    )
