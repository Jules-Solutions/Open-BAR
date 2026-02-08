"""Tests for Lua parity constants."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from bar_sim.parity import (
    STALL_THRESHOLD, FLOAT_THRESHOLD, RESOURCE_BUFFER, ECON_PRIORITIES,
)


def test_stall_threshold():
    """Must match Lua: stallThreshold = 0.05."""
    assert STALL_THRESHOLD == 0.05


def test_float_threshold():
    """Must match Lua: floatThreshold = 0.80."""
    assert FLOAT_THRESHOLD == 0.80


def test_resource_buffer():
    """Must match Lua: metalCost * 0.15 / energyCost * 0.15."""
    assert RESOURCE_BUFFER == 0.15


def test_econ_priorities_match_lua():
    """Priorities must match Lua BUILD_PRIORITY table."""
    expected = [
        ("mex",          "metal_stall",  100),
        ("wind",         "energy_stall",  90),
        ("solar",        "energy_stall",  85),
        ("mex",          "always",        70),
        ("wind",         "always",        50),
        ("converter_t1", "energy_float",  40),
    ]
    assert ECON_PRIORITIES == expected


def test_thresholds_in_valid_range():
    """Thresholds should be between 0 and 1."""
    assert 0 < STALL_THRESHOLD < 1
    assert 0 < FLOAT_THRESHOLD < 1
    assert 0 < RESOURCE_BUFFER < 1
    assert STALL_THRESHOLD < FLOAT_THRESHOLD
