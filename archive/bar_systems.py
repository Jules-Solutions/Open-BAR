"""
Beyond All Reason - Complete Game Systems
=========================================
All the subsystems that make up complete gameplay.
"""

from dataclasses import dataclass
from typing import List, Dict, Tuple
from enum import Enum, auto
import math


# =============================================================================
# CONVERTER SYSTEM
# =============================================================================

class ConverterSystem:
    """
    Energy Converters: Turn excess energy into metal.
    
    Key insight: Converters are controlled by the YELLOW SLIDER on your resource bar.
    They auto-activate when energy goes above the slider threshold.
    """
    
    # T1 Converter: 70 E/s -> 1 M/s
    T1_ENERGY_COST = 70
    T1_METAL_OUTPUT = 1.0
    T1_RATIO = T1_METAL_OUTPUT / T1_ENERGY_COST  # 0.0143 M per E
    
    # T2 Converter: 600 E/s -> 10.3 M/s
    T2_ENERGY_COST = 600
    T2_METAL_OUTPUT = 10.3
    T2_RATIO = T2_METAL_OUTPUT / T2_ENERGY_COST  # 0.0172 M per E (20% better)
    
    @staticmethod
    def when_to_build() -> Dict:
        """Rules for when to build converters."""
        return {
            "prerequisites": [
                "Energy income exceeds consumption by 100+ E/s",
                "All practical mex expansion done (or too dangerous)",
                "Yellow slider already at ~70-80% and still floating E",
            ],
            "dont_build_if": [
                "You can still safely expand to mexes",
                "Energy income is tight",
                "You're about to go T2 (save resources)",
            ],
            "t1_vs_t2": {
                "t1": "Early game, when you have slight excess E. Costs almost no metal.",
                "t2": "Mid-late game with Fusion. 20% more efficient. Needs T2 con.",
            },
            "placement_rules": [
                "NEVER cluster converters - they chain explode!",
                "Space them at least 2 building widths apart",
                "Keep away from important structures",
            ],
            "slider_management": [
                "Yellow slider = energy threshold for converter activation",
                "Start at 70-80% to avoid stalling",
                "Lower it if you want more metal conversion",
                "Raise it if you're energy stalling",
            ],
        }
    
    @staticmethod
    def calculate_conversion(excess_energy: float, t1_count: int = 0, t2_count: int = 0) -> Dict:
        """Calculate metal output from converters given excess energy."""
        t1_can_run = min(t1_count, int(excess_energy / ConverterSystem.T1_ENERGY_COST))
        remaining_e = excess_energy - (t1_can_run * ConverterSystem.T1_ENERGY_COST)
        t2_can_run = min(t2_count, int(remaining_e / ConverterSystem.T2_ENERGY_COST))
        
        t1_metal = t1_can_run * ConverterSystem.T1_METAL_OUTPUT
        t2_metal = t2_can_run * ConverterSystem.T2_METAL_OUTPUT
        
        return {
            "excess_energy": excess_energy,
            "t1_running": t1_can_run,
            "t2_running": t2_can_run,
            "t1_metal_output": t1_metal,
            "t2_metal_output": t2_metal,
            "total_metal_output": t1_metal + t2_metal,
            "energy_used": (t1_can_run * 70) + (t2_can_run * 600),
        }


# =============================================================================
# DEFENSE SYSTEM
# =============================================================================

class DefenseSystem:
    """
    When, where, and what defenses to build.
    
    Core principle: Defenses trade mobility for cost-efficiency.
    They're stronger per-metal than mobile units, but can't move.
    """
    
    @staticmethod
    def defense_vs_army_decision() -> Dict:
        """When to build defense vs more army."""
        return {
            "build_defense_when": [
                "Protecting a key position you can't afford to lose",
                "Buying time to eco/tech while enemy is aggressive",
                "Choke points where defense can cover approaches",
                "You're ahead and want to secure the lead",
                "AA coverage for your base against air harass",
            ],
            "build_army_instead_when": [
                "You need to contest map control",
                "Enemy is turtling (army lets you dictate when to fight)",
                "Open terrain with no good choke points",
                "You're behind and need to take risks",
            ],
            "golden_rule": "Defense can't win games alone. You need army to take ground.",
        }
    
    @staticmethod
    def defense_placement_guide() -> Dict:
        """Where to place defenses."""
        return {
            "llt": {
                "when": "Early game, protecting expansions, key mexes",
                "where": [
                    "Just behind contested mexes",
                    "Choke points on attack routes",
                    "NOT at front line (outranged by Rocketer)",
                ],
                "how_many": "1-2 per position. Don't over-invest.",
                "warning": "Outranged by Rocketer (450 vs 350). Will die to rocket push.",
            },
            "hlt": {
                "when": "Mid game, when enemy has assault units",
                "where": [
                    "Behind LLTs as second line",
                    "Protecting important eco clusters",
                    "Narrow chokes where range matters less",
                ],
                "how_many": "1-2 to support LLT positions.",
            },
            "plasma": {
                "when": "Mid game, vs grouped/slow enemies",
                "where": [
                    "High ground (extra range)",
                    "Covering wide approaches",
                    "Behind walls to force clumping",
                ],
                "how_many": "1-2 per defensive position.",
            },
            "pulsar": {
                "when": "T2, when enemy has heavy units",
                "where": [
                    "Core defensive positions",
                    "Protecting critical infrastructure",
                ],
                "how_many": "1-2 max. Very expensive.",
                "warning": "Uses 150 energy per shot. Can drain you.",
            },
            "aa_turrets": {
                "when": "IMMEDIATELY when enemy air plant spotted",
                "where": [
                    "Cover your factory",
                    "Cover your eco cluster",
                    "Overlapping fields of fire",
                ],
                "how_many": "2-3 minimum to cover base. More if heavy air.",
            },
            "walls": {
                "when": "To funnel enemies, protect from raiders",
                "where": [
                    "Gaps between terrain features",
                    "Around eco to slow raiders",
                    "To create chokepoints",
                ],
                "types": {
                    "dragons_teeth": "Cheap (3M). Blocks pathing. Use liberally.",
                    "fortification": "Expensive (15M). Blocks shots. Use sparingly.",
                }
            },
        }
    
    @staticmethod
    def defense_cost_efficiency() -> Dict:
        """Compare defense cost to unit cost for same firepower."""
        return {
            "llt_vs_grunt": {
                "llt_cost": 85,
                "grunt_cost": 55,
                "llt_dps": 75,
                "grunt_dps": 40,
                "verdict": "LLT is 2x DPS for 1.5x cost. Efficient if it survives.",
            },
            "hlt_vs_warrior": {
                "hlt_cost": 350,
                "warrior_cost": 200,
                "hlt_dps": 200,
                "warrior_dps": 60,
                "verdict": "HLT is 3x DPS for 1.75x cost. Very efficient.",
            },
            "key_insight": "Defenses are cost-efficient IF they can shoot. "
                          "Outranging them = free kills.",
        }


# =============================================================================
# AIR SYSTEM
# =============================================================================

class AirSystem:
    """
    Air play: when to go air, how to respond, air micro.
    """
    
    @staticmethod
    def when_to_build_air_plant() -> Dict:
        """Decision framework for air factory."""
        return {
            "go_air_when": [
                "Enemy has no AA and you can punish it",
                "Map has hard-to-reach expansions (island mexes)",
                "You have strong eco lead and can afford air + ground",
                "Need to contest air superiority (enemy went air)",
            ],
            "dont_go_air_when": [
                "Your eco can't support two production lines",
                "Enemy already has strong AA presence",
                "Small map where ground can reach everywhere fast",
                "You're behind and need immediate ground presence",
            ],
            "air_first_pitfalls": [
                "Air plant costs 800M/2800E - expensive!",
                "Air units die to AA - if enemy has AA, you wasted resources",
                "No air factory means delayed ground production",
            ],
        }
    
    @staticmethod
    def air_unit_roles() -> Dict:
        """What each air unit does."""
        return {
            "scout": {
                "unit": "Blink",
                "role": "Map vision, spotting enemy army/eco",
                "use": "Send one early to scout. Expendable.",
            },
            "fighter": {
                "unit": "Freedom Fighter",
                "role": "Kill enemy air, air superiority",
                "use": "Patrol over your base/army. Intercept bombers.",
            },
            "bomber": {
                "unit": "Phoenix (T1) / Lightning (T2)",
                "role": "Destroy buildings, snipe targets",
                "use": "Hit constructors, lone units, mexes. Avoid AA.",
            },
            "gunship": {
                "unit": "Stiletto (T2)",
                "role": "Ground attack, sustained damage",
                "use": "Support ground pushes. Kill stuff AA can't protect.",
            },
        }
    
    @staticmethod
    def aa_response_timing() -> Dict:
        """When and how to respond to air threats."""
        return {
            "scout_enemy_air_plant": {
                "response": "Build 2-3 AA turrets covering base",
                "urgency": "HIGH - bombers come fast",
                "time_window": "~90 seconds before first bomber arrives",
            },
            "bombers_incoming": {
                "response": [
                    "Pull constructors to safety",
                    "Spread important buildings",
                    "Add mobile AA to army",
                ],
                "urgency": "IMMEDIATE",
            },
            "air_superiority_lost": {
                "response": [
                    "Build fighters to contest",
                    "Add flak for AoE AA",
                    "Don't let air units cluster",
                ],
            },
            "aa_ratio": {
                "turrets": "2-3 per base cluster",
                "mobile": "1-2 per 10 ground units in army",
            },
        }


# =============================================================================
# COMBAT SYSTEM
# =============================================================================

class CombatSystem:
    """
    Micro, engagement decisions, army management.
    """
    
    @staticmethod
    def engagement_decision() -> Dict:
        """When to fight, when to retreat."""
        return {
            "take_fight_when": [
                "You have superior army value",
                "Terrain advantage (high ground, choke)",
                "Enemy army is split/out of position",
                "Enemy has no retreat path",
                "You have repair/rez support nearby",
            ],
            "avoid_fight_when": [
                "Enemy has superior army value",
                "Fighting into defenses",
                "Your army is split",
                "You can't afford to lose these units",
            ],
            "force_fight_when": [
                "Enemy is about to out-eco you",
                "You have timing attack (early aggression)",
                "Enemy is vulnerable (constructors exposed)",
            ],
        }
    
    @staticmethod
    def micro_techniques() -> Dict:
        """Basic micro techniques."""
        return {
            "kiting": {
                "what": "Attack while moving backward",
                "when": "Your units have range advantage",
                "how": "Attack-move, then move back before enemy closes",
                "example": "Rocketers vs Grunts - outrange and kite",
            },
            "focus_fire": {
                "what": "Concentrate fire on single targets",
                "when": "Enemy has high-value targets",
                "how": "Right-click specific targets, don't attack-move",
                "example": "Focus the Zeus before it gets in range",
            },
            "concave": {
                "what": "Arc formation so all units can fire",
                "when": "Before engagement",
                "how": "Spread units in crescent shape facing enemy",
                "why": "More units firing = more DPS",
            },
            "terrain_use": {
                "high_ground": "Extra range for artillery, plasma",
                "water": "Use amphibious units to flank",
                "cliffs": "Bots can climb, vehicles can't",
                "chokes": "Force enemy to clump for AoE",
            },
            "retreat_and_repair": {
                "what": "Pull damaged units, repair, return",
                "when": "Units below 50% health",
                "how": "Send to constructor/rez bot behind lines",
                "why": "Repaired unit = free metal vs enemy",
            },
        }
    
    @staticmethod
    def wreck_economy() -> Dict:
        """Managing wrecks during/after fights."""
        return {
            "wreck_value": "Wrecks give 1/3 to 2/3 of unit metal cost",
            "commander_wreck": "1250 metal! Always contest this.",
            "during_fight": [
                "Don't stop fighting to reclaim",
                "Send rez bot to edge of fight for opportunistic rez",
            ],
            "after_fight": [
                "Immediately send constructor to reclaim",
                "Rez bot to resurrect high-value wrecks",
                "Prioritize enemy wrecks (they'll want them too)",
            ],
            "rez_vs_reclaim": {
                "resurrect": "Get full unit for energy cost. Better for expensive units.",
                "reclaim": "Get ~50% metal instantly. Better for cheap units.",
            },
        }


# =============================================================================
# COMMANDER SYSTEM
# =============================================================================

class CommanderSystem:
    """
    Commander usage, D-gun, positioning, risk management.
    """
    
    @staticmethod
    def commander_roles_by_phase() -> Dict:
        """How commander role changes through game."""
        return {
            "early_game": {
                "role": "Primary builder",
                "tasks": [
                    "Build opening eco",
                    "Build factory",
                    "Scale energy",
                    "First nano turret",
                ],
                "position": "In base, building",
            },
            "mid_game": {
                "role": "Front-line threat / builder",
                "tasks": [
                    "D-gun to win fights",
                    "Capture key territory",
                    "Build forward defenses",
                    "Reclaim wrecks",
                ],
                "position": "Behind front line, close enough to D-gun",
            },
            "late_game": {
                "role": "Defense / opportunistic",
                "tasks": [
                    "Protect against assassination",
                    "Build experimental projects",
                    "Emergency D-gun defense",
                ],
                "position": "Safe in base, or with army",
            },
        }
    
    @staticmethod
    def dgun_usage() -> Dict:
        """D-gun mechanics and tactics."""
        return {
            "stats": {
                "damage": "Kills anything in one hit (except commanders)",
                "energy_cost": 500,
                "reload": "1 second",
                "range": "~350",
            },
            "best_targets": [
                "T2 assault units (Zeus, Bulldogs)",
                "Expensive units (anything >300 metal)",
                "Enemy commander (won't kill, but damages)",
                "Clumped groups (AoE splash)",
            ],
            "dont_dgun": [
                "Cheap units (waste of 500 energy)",
                "When energy stalling (you'll stall harder)",
                "Into superior numbers (you'll die)",
            ],
            "dgun_tricks": [
                "D-gun + regular weapon combo for burst",
                "D-gun to open fight, then retreat",
                "D-gun wrecks to deny resurrect",
            ],
        }
    
    @staticmethod
    def commander_safety() -> Dict:
        """Keeping your commander alive."""
        return {
            "threats": [
                "Bomber snipes",
                "EMP + focus fire",
                "Swarm overwhelming",
                "Counter D-gun (enemy com)",
            ],
            "safety_measures": [
                "Always know where enemy army is",
                "Don't overextend alone",
                "Have retreat path planned",
                "Keep mobile AA nearby if air threat",
            ],
            "death_explosion": {
                "damage": "~5000 in large AoE",
                "can_use_offensively": True,
                "com_bomb_tactic": "Self-destruct in enemy base. Very risky.",
            },
            "rule_of_thumb": "If you're not sure it's safe, it's not safe.",
        }


# =============================================================================
# MAP CONTROL SYSTEM
# =============================================================================

class MapControlSystem:
    """
    Expansion, territory control, reclaim.
    """
    
    @staticmethod
    def expansion_priority() -> Dict:
        """How to prioritize expansion."""
        return {
            "priority_order": [
                "1. Your starting mexes (safe, close)",
                "2. Safe side expansion (away from enemy)",
                "3. Contested middle mexes (with protection)",
                "4. Forward/aggressive mexes (when winning)",
            ],
            "dont_expand": [
                "Into enemy territory without army",
                "Faster than you can protect",
                "When enemy is about to attack",
            ],
        }
    
    @staticmethod
    def choke_points() -> Dict:
        """Using terrain to your advantage."""
        return {
            "what": "Narrow passages that funnel units",
            "value": [
                "Defense is more effective",
                "AoE weapons are stronger",
                "Smaller army can hold larger",
            ],
            "how_to_use": [
                "Build defenses covering choke",
                "Use walls to create artificial chokes",
                "Position army at choke, not in open",
            ],
            "attacking_chokes": [
                "Use artillery to outrange defenses",
                "Use air to bypass",
                "EMP to disable, then rush",
            ],
        }
    
    @staticmethod
    def reclaim_fields() -> Dict:
        """Maps often have reclaimable features."""
        return {
            "rocks_trees": "Some maps have tons of reclaimable features",
            "early_boost": "Sending con to reclaim can give big early metal spike",
            "wreck_fields": "After big fights, prioritize reclaiming",
            "deny_enemy": "Reclaim on their side of map denies them resources",
        }


# =============================================================================
# STORAGE SYSTEM
# =============================================================================

class StorageSystem:
    """
    When and why to build storage.
    """
    
    @staticmethod
    def storage_guide() -> Dict:
        """Storage building decisions."""
        return {
            "metal_storage": {
                "when": [
                    "Before T2 transition (bank 1000-2000)",
                    "When income > spending and you want to save for big purchase",
                ],
                "how_much": "1-2 (each gives 3000 storage)",
                "dont_need": "If you're spending everything efficiently",
            },
            "energy_storage": {
                "when": [
                    "Using wind (buffer for variance)",
                    "Using weapons that spike energy (D-gun, Pulsar)",
                    "Before building Fusion (helps smooth transition)",
                ],
                "how_much": "1-2 (each gives 6000 storage)",
                "key_insight": "Storage doesn't produce - only stores. Don't overbuild.",
            },
        }


# =============================================================================
# LATE GAME SYSTEM
# =============================================================================

class LateGameSystem:
    """
    T3, nukes, experimentals, mass production.
    """
    
    @staticmethod
    def late_game_goals() -> Dict:
        """What to aim for in late game."""
        return {
            "economy": {
                "all_mohos": "Every mex upgraded to Moho",
                "multiple_fusions": "2-4 Fusion Reactors",
                "converter_farm": "Use excess energy for metal",
            },
            "production": {
                "nano_farm": "3-5 nanos assisting factory",
                "multiple_factories": "Now it's ok to have 2+ factories",
                "t2_units": "Spam T2 assault (Zeus, Bulldogs)",
            },
            "game_enders": {
                "nukes": "Expensive but map-changing. Need anti-nuke response.",
                "big_bertha": "Long range artillery pressure.",
                "experimentals": "T3 units that can solo armies.",
            },
        }
    
    @staticmethod
    def nuke_guide() -> Dict:
        """Nuclear warfare."""
        return {
            "your_nuke": {
                "cost": "2500M + huge energy to stockpile",
                "use": "Destroy eco clusters, mass armies, force spread",
                "warning": "Enemy anti-nuke stops it. Scout first.",
            },
            "anti_nuke": {
                "cost": "1800M + 54000E",
                "coverage": "~4000 range",
                "must_have": "As soon as enemy might have nuke",
                "stockpile": "Keep missiles stockpiled!",
            },
        }


# =============================================================================
# RECOVERY SYSTEM
# =============================================================================

class RecoverySystem:
    """
    What to do when behind.
    """
    
    @staticmethod
    def recovery_guide() -> Dict:
        """How to recover from setbacks."""
        return {
            "lost_army": {
                "immediate": "Don't panic. Check eco.",
                "actions": [
                    "Reclaim the wrecks!",
                    "Build emergency defenses",
                    "Rebuild army efficiently",
                ],
            },
            "lost_eco": {
                "immediate": "Rebuild metal first",
                "actions": [
                    "Every mex is priority",
                    "Don't try to rebuild everything at once",
                    "Scale back production until eco recovers",
                ],
            },
            "behind_overall": {
                "mindset": "You can still win. Look for opportunities.",
                "options": [
                    "Turtle and out-tech",
                    "All-in timing attack",
                    "Harass their eco, don't fight main army",
                    "Go air if they have no AA",
                ],
            },
            "key_insight": "The game isn't over until commander dies. Stay calm.",
        }


# =============================================================================
# PRINT ALL SYSTEMS
# =============================================================================

def print_converter_guide():
    """Print converter usage guide."""
    print("\n" + "=" * 70)
    print("ENERGY CONVERTERS")
    print("=" * 70)
    guide = ConverterSystem.when_to_build()
    
    print("\nWHEN TO BUILD:")
    for item in guide["prerequisites"]:
        print(f"  ✓ {item}")
    
    print("\nDON'T BUILD IF:")
    for item in guide["dont_build_if"]:
        print(f"  ✗ {item}")
    
    print("\nT1 vs T2:")
    print(f"  T1: {guide['t1_vs_t2']['t1']}")
    print(f"  T2: {guide['t1_vs_t2']['t2']}")
    
    print("\nPLACEMENT:")
    for item in guide["placement_rules"]:
        print(f"  • {item}")
    
    print("\nYELLOW SLIDER:")
    for item in guide["slider_management"]:
        print(f"  • {item}")


def print_defense_guide():
    """Print defense guide."""
    print("\n" + "=" * 70)
    print("DEFENSE GUIDE")
    print("=" * 70)
    
    placement = DefenseSystem.defense_placement_guide()
    for defense, info in placement.items():
        print(f"\n{defense.upper()}")
        print(f"  When: {info.get('when', 'N/A')}")
        if 'where' in info:
            print("  Where:")
            for loc in info['where']:
                print(f"    • {loc}")
        if 'how_many' in info:
            print(f"  How many: {info['how_many']}")
        if 'warning' in info:
            print(f"  ⚠ WARNING: {info['warning']}")


def print_air_guide():
    """Print air guide."""
    print("\n" + "=" * 70)
    print("AIR GUIDE")
    print("=" * 70)
    
    air = AirSystem.when_to_build_air_plant()
    print("\nGO AIR WHEN:")
    for item in air["go_air_when"]:
        print(f"  ✓ {item}")
    
    print("\nDON'T GO AIR WHEN:")
    for item in air["dont_go_air_when"]:
        print(f"  ✗ {item}")
    
    response = AirSystem.aa_response_timing()
    print("\nAA RESPONSE:")
    print(f"  Scout air plant → {response['scout_enemy_air_plant']['response']}")
    print(f"  Urgency: {response['scout_enemy_air_plant']['urgency']}")


def print_combat_guide():
    """Print combat guide."""
    print("\n" + "=" * 70)
    print("COMBAT GUIDE")
    print("=" * 70)
    
    micro = CombatSystem.micro_techniques()
    for technique, info in micro.items():
        print(f"\n{technique.upper()}")
        print(f"  What: {info.get('what', info)}")
        if isinstance(info, dict):
            if 'when' in info:
                print(f"  When: {info['when']}")
            if 'how' in info:
                print(f"  How: {info['how']}")


def print_commander_guide():
    """Print commander guide."""
    print("\n" + "=" * 70)
    print("COMMANDER GUIDE")
    print("=" * 70)
    
    dgun = CommanderSystem.dgun_usage()
    print("\nD-GUN:")
    print(f"  Damage: {dgun['stats']['damage']}")
    print(f"  Cost: {dgun['stats']['energy_cost']} energy")
    print("\n  Best targets:")
    for target in dgun["best_targets"]:
        print(f"    • {target}")
    
    safety = CommanderSystem.commander_safety()
    print("\nSAFETY:")
    print(f"  Death explosion: {safety['death_explosion']['damage']}")
    print(f"  Rule: {safety['rule_of_thumb']}")


if __name__ == "__main__":
    print_converter_guide()
    print_defense_guide()
    print_air_guide()
    print_combat_guide()
    print_commander_guide()
