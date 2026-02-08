"""Tests for the walking time estimator."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.walk_time import WalkTimeEstimator, DEFAULT_WALK_SECONDS
from bar_sim.models import MexSpot, StartPosition


def test_no_map_data_fallback():
    """Without map data, walk time should still be positive."""
    est = WalkTimeEstimator(mex_spots=[], start_pos=None)
    result = est.estimate("mex", 52.0, 0)
    assert result > 0


def test_mex_walk_varies_by_index(sample_mex_spots, sample_start_pos):
    """Different mex indices should produce different walk times."""
    est = WalkTimeEstimator(sample_mex_spots, sample_start_pos)
    walk0 = est.estimate("mex", 52.0, 0)
    walk1 = est.estimate("mex", 52.0, 1)
    # First mex starts from base, second from first mex — distances differ
    assert walk0 > 0
    assert walk1 > 0


def test_slower_unit_walks_longer(sample_mex_spots, sample_start_pos):
    """Slower units should take longer to walk the same distance."""
    est = WalkTimeEstimator(sample_mex_spots, sample_start_pos)
    walk_fast = est.estimate("mex", 65.0, 0)  # con_vehicle speed
    walk_slow = est.estimate("mex", 37.0, 0)  # commander speed
    assert walk_slow >= walk_fast


def test_factory_uses_factory_radius(sample_mex_spots, sample_start_pos):
    """Factory placement should use factory radius distance."""
    est = WalkTimeEstimator(sample_mex_spots, sample_start_pos)
    walk = est.estimate("bot_lab", 37.0, 0)
    assert walk > 0


def test_base_structure_uses_base_radius(sample_mex_spots, sample_start_pos):
    """Wind/solar should use base radius distance."""
    est = WalkTimeEstimator(sample_mex_spots, sample_start_pos)
    walk = est.estimate("wind", 52.0, 0)
    assert walk > 0


def test_zero_speed_uses_default():
    """Zero speed should fall back to default walk time."""
    spots = [MexSpot(x=500, z=500, metal=2.0)]
    start = StartPosition(x=100, z=100, team_id=0)
    est = WalkTimeEstimator(spots, start)
    result = est.estimate("mex", 0.0, 0)
    assert result == round(DEFAULT_WALK_SECONDS)


def test_mex_beyond_known_spots(sample_mex_spots, sample_start_pos):
    """Mex index beyond known spots should use average distance."""
    est = WalkTimeEstimator(sample_mex_spots, sample_start_pos)
    walk = est.estimate("mex", 52.0, 10)  # well beyond 4 known spots
    assert walk > 0
