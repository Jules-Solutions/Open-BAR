"""
Beyond All Reason - State-Based Strategy System
================================================
A complete decision framework for 1v1 gameplay (Armada).
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional
from enum import Enum, auto


class State(Enum):
    """Game states with clear thresholds."""
    OPENING = auto()      # 0-3 mex, no factory complete
    FOUNDATION = auto()   # Factory up, no constructor out yet
    EXPANSION = auto()    # 1 con, <8 M/s
    SCALING = auto()      # 8-20 M/s, building toward T2
    T2_READY = auto()     # 20+ M/s, 500+ E/s, 1000+ stored
    T2_TRANSITION = auto() # T2 lab building/built
    LATE_GAME = auto()    # Moho eco online


@dataclass
class Threshold:
    """Defines when to transition between states."""
    name: str
    conditions: Dict[str, float]
    description: str


# =============================================================================
# STATE DEFINITIONS WITH PRECISE THRESHOLDS
# =============================================================================

STATE_THRESHOLDS = {
    State.OPENING: Threshold(
        name="Opening",
        conditions={
            "mex_count": (0, 2),      # 0-2 mexes
            "factory_complete": False,
        },
        description="Secure starting resources and get factory down"
    ),
    
    State.FOUNDATION: Threshold(
        name="Foundation",
        conditions={
            "mex_count": (2, 3),
            "factory_complete": True,
            "con_count": 0,
        },
        description="Factory online, getting first constructor out"
    ),
    
    State.EXPANSION: Threshold(
        name="Expansion",
        conditions={
            "mex_count": (3, 8),
            "metal_income": (3, 8),
            "con_count": (1, 2),
        },
        description="Aggressive expansion, claiming map control"
    ),
    
    State.SCALING: Threshold(
        name="Scaling",
        conditions={
            "mex_count": (6, 12),
            "metal_income": (8, 20),
            "energy_income": (100, 500),
        },
        description="Building economy toward T2 readiness"
    ),
    
    State.T2_READY: Threshold(
        name="T2 Ready",
        conditions={
            "metal_income": (20, float('inf')),
            "energy_income": (500, float('inf')),
            "metal_stored": (1000, float('inf')),
        },
        description="Economy can support T2 transition"
    ),
    
    State.T2_TRANSITION: Threshold(
        name="T2 Transition",
        conditions={
            "has_t2_lab": True,
        },
        description="Building T2 infrastructure"
    ),
    
    State.LATE_GAME: Threshold(
        name="Late Game",
        conditions={
            "moho_count": (3, float('inf')),
            "has_fusion": True,
        },
        description="T2 economy online, scaling to late game"
    ),
}


# =============================================================================
# PRIORITIES PER STATE
# =============================================================================

@dataclass 
class Priority:
    """A prioritized action."""
    rank: int
    action: str
    target: str  # What you're trying to achieve
    threshold: str  # When this is complete


STATE_PRIORITIES = {
    State.OPENING: [
        Priority(1, "Build Mex #1", "Metal income", "mex_count >= 1"),
        Priority(2, "Build Mex #2", "Metal income", "mex_count >= 2"),
        Priority(3, "Build 2-3 Energy", "Energy positive", "energy_income >= 40"),
        Priority(4, "Place Bot Lab", "Production", "factory_building = True"),
    ],
    
    State.FOUNDATION: [
        Priority(1, "Complete Mex #3", "Full starting metal", "mex_count >= 3"),
        Priority(2, "Energy scale", "Stay positive", "energy_income >= 60"),
        Priority(3, "Queue: Tick → Tick → Combat → Con", "Factory working", "factory_queue set"),
        Priority(4, "Build Radar", "Vision", "radar_count >= 1"),
    ],
    
    State.EXPANSION: [
        Priority(1, "Con: Grab contested mexes", "Map control", "mex_count >= 6"),
        Priority(2, "Con: 1-2 LLT at key points", "Defense", "llt_count >= 2"),
        Priority(3, "Commander: Energy scale", "Prepare for nano", "energy_income >= 100"),
        Priority(4, "Factory: Combat units", "Army", "continuous"),
        Priority(5, "Evaluate: Can support nano?", "Build power", "metal >= 8 AND energy >= 100"),
    ],
    
    State.SCALING: [
        Priority(1, "Build Nano on factory", "200 BP boost", "nano_count >= 1"),
        Priority(2, "Con: Continue mex expansion", "10+ mex target", "mex_count >= 10"),
        Priority(3, "Get 2nd Constructor", "Expansion speed", "con_count >= 2"),
        Priority(4, "Energy: Scale toward 500 E/s", "T2 prep", "energy_income >= 500"),
        Priority(5, "Bank metal: 1000-2000", "T2 prep", "metal_stored >= 1000"),
    ],
    
    State.T2_READY: [
        Priority(1, "Start T2 Lab", "T2 access", "t2_lab_building = True"),
        Priority(2, "Maintain T1 production", "Army", "factory producing"),
        Priority(3, "Protect key mexes", "Economy", "defenses at back mex"),
        Priority(4, "Queue T2 Con first", "Moho access", "t2_con queued"),
    ],
    
    State.T2_TRANSITION: [
        Priority(1, "T2 Con → Moho back mexes", "4x metal income", "moho_count >= 3"),
        Priority(2, "T2 Con → Fusion", "Energy for T2", "fusion_count >= 1"),
        Priority(3, "T1 Factory: Keep producing", "Army", "continuous"),
        Priority(4, "Consider T2 units", "Power spike", "as needed"),
    ],
    
    State.LATE_GAME: [
        Priority(1, "All mex → Moho", "Max metal", "all_mex_upgraded"),
        Priority(2, "Multiple Fusions", "Energy abundance", "fusion_count >= 2"),
        Priority(3, "Add Nano farm", "Production speed", "nano_count >= 3"),
        Priority(4, "T2 Converters if excess E", "Metal boost", "as needed"),
        Priority(5, "Consider T3/Experimentals", "End game", "as appropriate"),
    ],
}


# =============================================================================
# MODIFIERS (Conditional Rules)
# =============================================================================

@dataclass
class Modifier:
    """Conditional adjustment to priorities."""
    name: str
    condition: str
    effect: str
    applies_to: List[State]


MODIFIERS = [
    # === ENERGY MODIFIERS ===
    Modifier(
        name="No Wind Map",
        condition="avg_wind < 7",
        effect="Build Solar only. Skip Wind Turbines entirely.",
        applies_to=[State.OPENING, State.FOUNDATION, State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="High Wind Map", 
        condition="avg_wind >= 12",
        effect="Wind only. Consider Energy Storage for variance.",
        applies_to=[State.OPENING, State.FOUNDATION, State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="Has Geo Vents",
        condition="geo_vents_available",
        effect="Prioritize Geothermal (300 E/s stable) over wind/solar.",
        applies_to=[State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="Water Map - Tidal",
        condition="is_water_map AND tidal_value > 18",
        effect="Tidal generators for stable energy if you have water access.",
        applies_to=[State.EXPANSION, State.SCALING]
    ),
    
    # === ENEMY BEHAVIOR MODIFIERS ===
    Modifier(
        name="Enemy Rush Detected",
        condition="enemy_army_approaching AND game_time < 180",
        effect="Pause expansion. Commander to front. Build LLT. Factory: combat units only.",
        applies_to=[State.FOUNDATION, State.EXPANSION]
    ),
    Modifier(
        name="Enemy Turtling",
        condition="enemy_not_expanding AND enemy_defensive",
        effect="Eco harder. Delay army. You can outscale them.",
        applies_to=[State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="Air Threat",
        condition="enemy_air_plant_spotted OR bombers_incoming",
        effect="Build 1-2 AA turrets. Add AA units to army. Spread buildings.",
        applies_to=[State.EXPANSION, State.SCALING, State.T2_READY]
    ),
    Modifier(
        name="Losing Map Control",
        condition="mex_count_decreasing OR losing_fights",
        effect="Prioritize army over eco. Reclaim wrecks. Defensive play.",
        applies_to=[State.EXPANSION, State.SCALING]
    ),
    
    # === TERRAIN MODIFIERS ===
    Modifier(
        name="Hilly/Rough Terrain",
        condition="map_has_cliffs OR map_rough_terrain",
        effect="Prefer Bot Lab over Vehicle Plant. Bots traverse better.",
        applies_to=[State.OPENING, State.FOUNDATION]
    ),
    Modifier(
        name="Open/Flat Map",
        condition="map_is_flat AND map_is_open",
        effect="Consider Vehicle Plant. Tanks have stronger stats.",
        applies_to=[State.OPENING, State.FOUNDATION]
    ),
    
    # === ECONOMY MODIFIERS ===
    Modifier(
        name="Energy Stalling",
        condition="energy_income < energy_consumption",
        effect="STOP building. Build energy immediately. Pause factory.",
        applies_to=[State.FOUNDATION, State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="Metal Floating",
        condition="metal_stored > 80% capacity AND metal_income > 0",
        effect="Add build power OR build more units. You're wasting resources.",
        applies_to=[State.EXPANSION, State.SCALING]
    ),
    Modifier(
        name="Rich Reclaim Available",
        condition="wrecks_nearby OR features_to_reclaim",
        effect="Send constructor to reclaim. Big early metal boost.",
        applies_to=[State.FOUNDATION, State.EXPANSION]
    ),
]


# =============================================================================
# CORE LOOP (Always True)
# =============================================================================

CORE_LOOP = """
═══════════════════════════════════════════════════════════════════════════════
                              CORE LOOP
    These rules are ALWAYS active, every second of the game.
    Check these BEFORE acting on state priorities.
═══════════════════════════════════════════════════════════════════════════════

1. NEVER STALL METAL
   → If metal bar depleting: Build mex, reclaim, slow down production
   
2. NEVER STALL ENERGY  
   → If energy bar depleting: Build energy NOW, pause factory if needed
   
3. NEVER FLOAT RESOURCES
   → If bars full: Add build power, build more units, expand faster
   
4. ALWAYS HAVE VISION
   → Radar coverage on approaches, scouts exploring
   
5. ALWAYS QUEUE PRODUCTION
   → Factory should never be idle (unless energy stalling)
   
6. PROTECT YOUR COMMANDER
   → Don't lose it carelessly. It's your win condition.
"""


# =============================================================================
# TRANSITION TRIGGERS
# =============================================================================

TRANSITIONS = """
═══════════════════════════════════════════════════════════════════════════════
                           STATE TRANSITIONS
═══════════════════════════════════════════════════════════════════════════════

OPENING → FOUNDATION
  Trigger: Factory placed and building
  
FOUNDATION → EXPANSION  
  Trigger: First constructor bot completed
  
EXPANSION → SCALING
  Trigger: Metal income ≥ 8 M/s AND can support nano (energy ≥ 100 E/s)
  
SCALING → T2_READY
  Trigger: Metal income ≥ 20 M/s AND Energy income ≥ 500 E/s AND Metal stored ≥ 1000
  
T2_READY → T2_TRANSITION
  Trigger: T2 Lab construction started
  
T2_TRANSITION → LATE_GAME
  Trigger: 3+ Moho mexes built AND at least 1 Fusion Reactor
"""


# =============================================================================
# QUICK REFERENCE
# =============================================================================

def print_quick_reference():
    """Print a quick reference card."""
    print("""
╔═══════════════════════════════════════════════════════════════════════════════╗
║                    BAR 1V1 QUICK REFERENCE (ARMADA)                          ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║  OPENING (first ~60 seconds)                                                  ║
║  ───────────────────────────                                                  ║
║  Commander: Mex → Mex → 2-3 Energy → Bot Lab                                  ║
║  Factory queue: Tick → Tick → Pawn/Grunt → Constructor                        ║
║                                                                               ║
║  ENERGY DECISION                                                              ║
║  ───────────────                                                              ║
║  Wind ≥ 7  → Build Wind Turbines (40M, variable output)                       ║
║  Wind < 7  → Build Solar (150M, steady 20 E/s)                                ║
║                                                                               ║
║  KEY THRESHOLDS                                                               ║
║  ──────────────                                                               ║
║  Nano Turret: Build when Metal ≥ 8/s AND Energy ≥ 100/s                       ║
║  2nd Con:     After first nano, when expanding is safe                        ║
║  T2 Ready:    Metal ≥ 20/s, Energy ≥ 500/s, Stored ≥ 1000M                    ║
║                                                                               ║
║  ECONOMY RATIOS (from official guide)                                         ║
║  ────────────────────────────────────                                         ║
║  200 Build Power per 5 M/s and 100 E/s                                        ║
║  Commander = 200 BP, Nano = 200 BP, T1 Con = 100 BP                           ║
║                                                                               ║
║  T2 TRANSITION                                                                ║
║  ─────────────                                                                ║
║  Total investment: ~4000 metal (lab + con + first mohos)                      ║
║  First T2 con priorities: Moho back mexes → Fusion → More mohos               ║
║                                                                               ║
║  COMMON MISTAKES                                                              ║
║  ───────────────                                                              ║
║  ✗ Building nano before eco can support it                                    ║
║  ✗ Multiple T1 factories (wasteful - use nanos instead)                       ║
║  ✗ Going T2 while stalling resources                                          ║
║  ✗ Floating metal (build power bottleneck)                                    ║
║  ✗ Ignoring radar/scouting                                                    ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
""")


def print_modifier_reference():
    """Print all modifiers."""
    print("\n" + "=" * 70)
    print("MODIFIERS - Conditional Rules")
    print("=" * 70)
    
    for mod in MODIFIERS:
        states = ", ".join([s.name for s in mod.applies_to])
        print(f"\n[{mod.name}]")
        print(f"  IF: {mod.condition}")
        print(f"  THEN: {mod.effect}")
        print(f"  Applies to: {states}")


if __name__ == "__main__":
    print(CORE_LOOP)
    print(TRANSITIONS)
    print_quick_reference()
    print_modifier_reference()
