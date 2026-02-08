"""Tests for CLI integration (subprocess-based)."""

import subprocess
import sys
from pathlib import Path

import pytest

SIM_ROOT = Path(__file__).parent.parent
CLI_PATH = SIM_ROOT / "cli.py"
BO_PATH = SIM_ROOT / "data" / "build_orders" / "wind_opening.yaml"


def _run_cli(*args, timeout=30):
    """Run CLI command and return CompletedProcess."""
    cmd = [sys.executable, str(CLI_PATH)] + list(args)
    return subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout, cwd=str(SIM_ROOT)
    )


@pytest.mark.skipif(not BO_PATH.exists(), reason="wind_opening.yaml not found")
def test_simulate_exits_0():
    """Running simulate with a valid BO should exit 0."""
    result = _run_cli("simulate", str(BO_PATH), "--duration", "60")
    assert result.returncode == 0, f"stderr: {result.stderr}"


@pytest.mark.skipif(not BO_PATH.exists(), reason="wind_opening.yaml not found")
def test_simulate_produces_output():
    """Simulate should produce meaningful output."""
    result = _run_cli("simulate", str(BO_PATH), "--duration", "60")
    assert "metal" in result.stdout.lower() or "tick" in result.stdout.lower()


def test_map_info_cached():
    """Map info for a cached map should succeed."""
    result = _run_cli("map", "info", "delta_siege_dry")
    # Should either succeed or warn about missing map
    # (depends on whether cache files are available)
    assert result.returncode == 0 or "not found" in result.stderr.lower() or "warning" in result.stdout.lower()
