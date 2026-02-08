"""Tests for map data cache loading and Voronoi assignment."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.map_data import (
    load_map_cache, assign_mex_spots, map_data_to_map_config, list_cached_maps,
)
from bar_sim.models import MexSpot, StartPosition, MapData


def test_load_cached_delta_siege():
    """Should load delta_siege_dry from cached JSON."""
    md = load_map_cache("delta_siege_dry")
    if md is None:
        import pytest
        pytest.skip("delta_siege_dry.json not in cache")

    assert md.name == "Delta Siege Dry"
    assert len(md.mex_spots) > 0
    assert len(md.start_positions) == 2
    assert md.wind_min > 0


def test_load_cache_normalized_name():
    """Should find cache by normalized name (e.g. 'DeltaSiege')."""
    md = load_map_cache("DeltaSiegeDry")
    if md is None:
        import pytest
        pytest.skip("delta_siege_dry.json not in cache")
    assert md.name == "Delta Siege Dry"


def test_assign_mex_spots_symmetric():
    """Symmetric map should assign ~equal mex spots to each player."""
    spots = [
        MexSpot(x=100, z=100, metal=2.0),
        MexSpot(x=200, z=100, metal=2.0),
        MexSpot(x=7900, z=7900, metal=2.0),
        MexSpot(x=8000, z=7900, metal=2.0),
    ]
    starts = [
        StartPosition(x=100, z=100, team_id=0),
        StartPosition(x=8000, z=8000, team_id=1),
    ]
    p0 = assign_mex_spots(spots, starts, 0)
    p1 = assign_mex_spots(spots, starts, 1)
    assert len(p0) == 2
    assert len(p1) == 2


def test_assign_mex_spots_sorted_by_distance():
    """Assigned mex spots should be sorted closest first."""
    spots = [
        MexSpot(x=500, z=500, metal=2.0),
        MexSpot(x=200, z=200, metal=2.0),
        MexSpot(x=300, z=300, metal=2.0),
    ]
    starts = [StartPosition(x=100, z=100, team_id=0)]
    result = assign_mex_spots(spots, starts, 0)
    # Should be sorted by distance from (100, 100)
    dists = [
        (s.x - 100) ** 2 + (s.z - 100) ** 2 for s in result
    ]
    assert dists == sorted(dists)


def test_map_data_to_config(sample_map_data):
    """MapData should convert to MapConfig correctly."""
    mc = map_data_to_map_config(sample_map_data, player_team=0, num_players=2)
    assert mc.avg_wind == 10.0  # (5+15)/2
    assert mc.wind_variance == 5.0  # (15-5)/2
    assert mc.mex_value == 2.0
    assert mc.mex_spots > 0


def test_list_cached_maps():
    """Should list available cached maps."""
    maps = list_cached_maps()
    # We created at least 3 cached maps
    assert isinstance(maps, list)
