"""
BAR Build Order Simulator - Walk Time Estimator
=================================================
Estimates walk time for builders based on unit speed, distance,
and map-specific mex spot locations.

Replaces the hardcoded WALK_TIME = 3 constant.
"""

import math
from typing import Optional

from bar_sim.models import MexSpot, StartPosition


# Pathfinding overhead multiplier (straight-line * this = realistic walk)
PATHFINDING_OVERHEAD = 1.3

# Approximate base radius for non-mex structures (elmos)
BASE_RADIUS = 200

# Factory placement distance from start (elmos)
FACTORY_RADIUS = 300

# Fallback walk time when no map data or speed info available
DEFAULT_WALK_SECONDS = 3.0


class WalkTimeEstimator:
    """Estimates walk time in seconds for builders moving between build sites.

    Uses mex spot positions and start position to calculate realistic
    walking times based on unit speed and distance.
    """

    def __init__(
        self,
        mex_spots: list[MexSpot],
        start_pos: Optional[StartPosition] = None,
        default_walk_seconds: float = DEFAULT_WALK_SECONDS,
    ):
        self.mex_spots = mex_spots
        self.start_pos = start_pos
        self.default_walk = default_walk_seconds

        # Pre-compute distances between consecutive mex spots
        self._mex_distances: list[float] = []
        self._start_to_first_mex: float = 0.0

        if start_pos and mex_spots:
            # Distance from start to first mex
            first = mex_spots[0]
            self._start_to_first_mex = math.sqrt(
                (first.x - start_pos.x) ** 2 + (first.z - start_pos.z) ** 2
            )
            # Distances between consecutive mex spots
            for i in range(1, len(mex_spots)):
                prev = mex_spots[i - 1]
                curr = mex_spots[i]
                dist = math.sqrt(
                    (curr.x - prev.x) ** 2 + (curr.z - prev.z) ** 2
                )
                self._mex_distances.append(dist)

    def estimate(self, unit_key: str, builder_speed: float, build_index: int = 0) -> int:
        """Estimate walk time in simulation ticks (seconds).

        Args:
            unit_key: What's being built (e.g. "mex", "wind", "bot_lab")
            builder_speed: Movement speed of the builder in elmos/s
            build_index: How many of this type have been built already
                         (used for mex to pick correct distance)

        Returns:
            Walk time in seconds (integer, minimum 1)
        """
        if builder_speed <= 0:
            return round(self.default_walk)

        if unit_key == "mex":
            dist = self._mex_walk_distance(build_index)
        elif unit_key in ("bot_lab", "vehicle_plant", "aircraft_plant",
                          "adv_bot_lab", "adv_vehicle_plant", "adv_aircraft_plant"):
            dist = FACTORY_RADIUS
        else:
            # Base structures: wind, solar, radar, llt, etc.
            dist = BASE_RADIUS

        walk_seconds = (dist * PATHFINDING_OVERHEAD) / builder_speed
        return max(1, round(walk_seconds))

    def _mex_walk_distance(self, mex_index: int) -> float:
        """Get distance to walk for the Nth mex build."""
        if not self.mex_spots:
            return BASE_RADIUS  # no map data fallback

        if mex_index == 0:
            # First mex: walk from start position
            return self._start_to_first_mex if self._start_to_first_mex > 0 else BASE_RADIUS
        elif mex_index - 1 < len(self._mex_distances):
            # Walk from previous mex to this one
            return self._mex_distances[mex_index - 1]
        else:
            # Beyond known mex spots: use average of known distances
            if self._mex_distances:
                return sum(self._mex_distances) / len(self._mex_distances)
            return BASE_RADIUS
