"""
BAR Build Order Simulator - Lua Parity Constants
==================================================
Central registry of all constants that must match the Lua widget values.
Each constant includes its source file and line reference.
"""

# ---------------------------------------------------------------------------
# Economy thresholds (engine_totallylegal_econ.lua:48-49)
# ---------------------------------------------------------------------------

STALL_THRESHOLD = 0.05   # < 5% storage = stalling
FLOAT_THRESHOLD = 0.80   # > 80% storage = floating

# ---------------------------------------------------------------------------
# Resource buffer (engine_totallylegal_econ.lua:146-147)
# ---------------------------------------------------------------------------
# Builder won't start a task unless it has at least 15% of the cost in storage.
# metalNeeded = metalCost * 0.15, energyNeeded = energyCost * 0.15

RESOURCE_BUFFER = 0.15

# ---------------------------------------------------------------------------
# Economy build priorities (engine_totallylegal_econ.lua:53-60)
# ---------------------------------------------------------------------------
# (unit_key, condition, priority)

ECON_PRIORITIES = [
    ("mex",          "metal_stall",  100),
    ("wind",         "energy_stall",  90),
    ("solar",        "energy_stall",  85),
    ("mex",          "always",        70),
    ("wind",         "always",        50),
    ("converter_t1", "energy_float",  40),
]
