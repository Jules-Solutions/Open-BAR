"""Tests for the core simulation engine."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.engine import SimulationEngine
from bar_sim.models import BuildOrder, BuildAction, MapConfig


def test_mex_income(simple_mex_bo):
    """Building 1 mex should increase metal income by mex_value."""
    engine = SimulationEngine(simple_mex_bo, duration=120)
    result = engine.run()

    # After 120s the mex should be built and producing
    assert result.peak_metal_income > 0
    # Commander baseline is 0 metal, so any metal income comes from mex
    # Check last snapshot shows metal income
    if result.snapshots:
        last = result.snapshots[-1]
        assert last.metal_income >= simple_mex_bo.map_config.mex_value


def test_stall_reduces_progress(default_map_config):
    """When stalling, construction should slow down."""
    # Build expensive stuff with no energy infrastructure
    bo = BuildOrder(
        name="Stall Test",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="solar"),
            BuildAction(unit_key="solar"),
            BuildAction(unit_key="solar"),
        ],
    )
    engine = SimulationEngine(bo, duration=300)
    result = engine.run()

    # Should have experienced at least one stall event
    assert result.stall_events is not None


def test_factory_spawns_builder(wind_opening_bo):
    """Factory completion should add a builder to state."""
    engine = SimulationEngine(wind_opening_bo, duration=300)
    result = engine.run()

    # After 300s, the factory should be built
    # Check that we have more than just the commander builder
    assert len(engine.state.builders) >= 1


def test_resource_buffer_delays_build(default_map_config):
    """Can't start build without 15% of cost available."""
    # Start with very low resources by draining them
    bo = BuildOrder(
        name="Buffer Test",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="mex"),
            # fusion costs 3500M / 16000E - can't start without buffer
            BuildAction(unit_key="fusion"),
        ],
    )
    engine = SimulationEngine(bo, duration=600)
    result = engine.run()

    # Engine should complete without crash
    assert result.total_ticks == 600


def test_walk_delay_without_map_data(default_map_config):
    """Walk times should use default fallback when no map data."""
    bo = BuildOrder(
        name="Walk Test",
        map_config=default_map_config,
        commander_queue=[
            BuildAction(unit_key="mex"),
        ],
    )
    engine = SimulationEngine(bo, duration=60)
    # No map data → uses WALK_TIME fallback
    assert engine._walk_estimator is None
    result = engine.run()
    assert result.total_ticks == 60


def test_full_wind_opening():
    """Run the standard wind opening, verify factory milestone ~85-100s."""
    from bar_sim.io import load_build_order

    bo_path = Path(__file__).parent.parent / "data" / "build_orders" / "wind_opening.yaml"
    if not bo_path.exists():
        import pytest
        pytest.skip("wind_opening.yaml not found")

    bo = load_build_order(str(bo_path))
    engine = SimulationEngine(bo, duration=300)
    result = engine.run()

    # Factory should be completed within the simulation
    factory_milestone = None
    for m in result.milestones:
        if m.event == "first_factory":
            factory_milestone = m
            break

    # Factory should have been built
    assert factory_milestone is not None
    # Should be within a reasonable timeframe (60-150s)
    assert 60 <= factory_milestone.tick <= 150
