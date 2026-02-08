"""Tests for YAML I/O round-trip."""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.io import load_build_order, save_build_order
from bar_sim.models import BuildOrder, BuildAction, MapConfig


def test_load_wind_opening():
    """Should load wind_opening.yaml without error."""
    bo_path = Path(__file__).parent.parent / "data" / "build_orders" / "wind_opening.yaml"
    if not bo_path.exists():
        import pytest
        pytest.skip("wind_opening.yaml not found")

    bo = load_build_order(str(bo_path))
    assert bo.name == "Wind Opening (Standard)"
    assert len(bo.commander_queue) > 0
    assert bo.map_config.avg_wind > 0


def test_save_and_reload_round_trip(default_map_config):
    """Save a build order to YAML, reload it, verify contents match."""
    bo = BuildOrder(
        name="Round Trip Test",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="mex"),
            BuildAction(unit_key="wind"),
        ],
    )

    with tempfile.NamedTemporaryFile(suffix=".yaml", delete=False, mode="w") as f:
        tmppath = f.name

    try:
        save_build_order(bo, tmppath)
        loaded = load_build_order(tmppath)
        assert loaded.name == "Round Trip Test"
        assert len(loaded.commander_queue) == 2
        assert loaded.commander_queue[0].unit_key == "mex"
        assert loaded.commander_queue[1].unit_key == "wind"
    finally:
        Path(tmppath).unlink(missing_ok=True)
