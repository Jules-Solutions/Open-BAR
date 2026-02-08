"""Tests for economy state classification and build priorities."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.econ_ctrl import classify_econ_state, ECON_PRIORITIES
from bar_sim.models import SimState


def test_classify_balanced():
    """Normal resource levels should classify as balanced."""
    s = SimState(
        metal_stored=250, metal_storage_cap=500,
        energy_stored=500, energy_storage_cap=1000,
    )
    assert classify_econ_state(s) == "balanced"


def test_classify_metal_stall():
    """Very low metal should classify as metal_stall."""
    s = SimState(
        metal_stored=10, metal_storage_cap=500,
        energy_stored=500, energy_storage_cap=1000,
    )
    assert classify_econ_state(s) == "metal_stall"


def test_classify_energy_stall():
    """Very low energy should classify as energy_stall."""
    s = SimState(
        metal_stored=250, metal_storage_cap=500,
        energy_stored=20, energy_storage_cap=1000,
    )
    assert classify_econ_state(s) == "energy_stall"


def test_classify_metal_float():
    """Near-full metal should classify as metal_float."""
    s = SimState(
        metal_stored=450, metal_storage_cap=500,
        energy_stored=500, energy_storage_cap=1000,
    )
    assert classify_econ_state(s) == "metal_float"


def test_classify_energy_float():
    """Near-full energy should classify as energy_float."""
    s = SimState(
        metal_stored=250, metal_storage_cap=500,
        energy_stored=900, energy_storage_cap=1000,
    )
    assert classify_econ_state(s) == "energy_float"


def test_econ_priorities_sorted():
    """Priorities should be in descending order."""
    priorities = [p[2] for p in ECON_PRIORITIES]
    assert priorities == sorted(priorities, reverse=True)


def test_econ_priorities_all_positive():
    """All priority values should be positive."""
    for _, _, prio in ECON_PRIORITIES:
        assert prio > 0
