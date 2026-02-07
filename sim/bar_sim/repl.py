"""
BAR Build Order Simulator - Interactive REPL
==============================================
"""

import cmd
import copy
from typing import Optional

from bar_sim.econ import UNITS
from bar_sim.models import BuildOrder, BuildAction, BuildActionType, MapConfig
from bar_sim.engine import SimulationEngine
from bar_sim.format import print_full_report, print_milestones, print_timeline, print_snapshots
from bar_sim.compare import compare_and_print
from bar_sim.io import load_build_order, save_build_order


class BuildOrderREPL(cmd.Cmd):
    intro = (
        "\n"
        "================================================\n"
        "  BAR Build Order Simulator - Interactive Mode\n"
        "================================================\n"
        "Type 'help' for commands. Type 'units' for available unit keys.\n"
    )
    prompt = "bar> "

    def __init__(self):
        super().__init__()
        self.bo: Optional[BuildOrder] = None
        self.last_result = None
        self.undo_stack = []
        self.redo_stack = []
        self._new_bo()

    def _new_bo(self):
        self.bo = BuildOrder(
            name="Untitled",
            map_config=MapConfig(),
        )

    def _save_undo(self):
        self.undo_stack.append(copy.deepcopy(self.bo))
        self.redo_stack.clear()

    # ------------------------------------------------------------------
    # Commands
    # ------------------------------------------------------------------

    def do_load(self, arg):
        """Load build order from YAML: load <filepath>"""
        if not arg:
            print("Usage: load <filepath>")
            return
        try:
            self.bo = load_build_order(arg.strip())
            print(f"Loaded: {self.bo.name}")
        except Exception as e:
            print(f"Error: {e}")

    def do_save(self, arg):
        """Save build order to YAML: save <filepath>"""
        if not arg:
            print("Usage: save <filepath>")
            return
        try:
            save_build_order(self.bo, arg.strip())
            print(f"Saved to {arg.strip()}")
        except Exception as e:
            print(f"Error: {e}")

    def do_name(self, arg):
        """Set build order name: name <text>"""
        if arg:
            self.bo.name = arg.strip()
            print(f"Name: {self.bo.name}")

    def do_show(self, arg):
        """Show current build order"""
        print(f"\nBuild Order: {self.bo.name}")
        mc = self.bo.map_config
        print(f"Map: wind={mc.avg_wind}, mex={mc.mex_value}, spots={mc.mex_spots}")

        print(f"\nCommander Queue ({len(self.bo.commander_queue)} items):")
        for i, a in enumerate(self.bo.commander_queue):
            unit = UNITS.get(a.unit_key)
            name = unit.name if unit else a.unit_key
            print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")

        for fid, q in self.bo.factory_queues.items():
            print(f"\n{fid} Queue ({len(q)} items):")
            for i, a in enumerate(q):
                unit = UNITS.get(a.unit_key)
                name = unit.name if unit else a.unit_key
                print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")

        for cid, q in self.bo.constructor_queues.items():
            print(f"\n{cid} Queue ({len(q)} items):")
            for i, a in enumerate(q):
                unit = UNITS.get(a.unit_key)
                name = unit.name if unit else a.unit_key
                print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")
        print()

    def do_add(self, arg):
        """Add unit to queue: add <unit_key> [queue] [position]
        Queues: com (default), fac0, con1, con2, etc."""
        parts = arg.split()
        if not parts:
            print("Usage: add <unit_key> [queue] [position]")
            return

        unit_key = parts[0]
        if unit_key not in UNITS:
            print(f"Unknown unit: {unit_key}. Type 'units' for list.")
            return

        queue_name = parts[1] if len(parts) > 1 else "com"
        pos = int(parts[2]) - 1 if len(parts) > 2 else None

        self._save_undo()
        queue = self._get_queue(queue_name)
        if queue is None:
            return

        action_type = (BuildActionType.PRODUCE_UNIT
                       if queue_name.startswith("fac")
                       else BuildActionType.BUILD_STRUCTURE)
        action = BuildAction(unit_key=unit_key, action_type=action_type)

        if pos is not None and 0 <= pos <= len(queue):
            queue.insert(pos, action)
        else:
            queue.append(action)

        print(f"Added {unit_key} to {queue_name}")

    def do_remove(self, arg):
        """Remove item from queue: remove <queue> <position>"""
        parts = arg.split()
        if len(parts) < 2:
            print("Usage: remove <queue> <position>")
            return
        queue_name = parts[0]
        pos = int(parts[1]) - 1
        queue = self._get_queue(queue_name)
        if queue is None:
            return
        if 0 <= pos < len(queue):
            self._save_undo()
            removed = queue.pop(pos)
            print(f"Removed {removed.unit_key} from {queue_name} pos {pos+1}")
        else:
            print(f"Invalid position {pos+1}")

    def do_swap(self, arg):
        """Swap two items: swap <queue> <pos1> <pos2>"""
        parts = arg.split()
        if len(parts) < 3:
            print("Usage: swap <queue> <pos1> <pos2>")
            return
        queue_name = parts[0]
        p1, p2 = int(parts[1]) - 1, int(parts[2]) - 1
        queue = self._get_queue(queue_name)
        if queue and 0 <= p1 < len(queue) and 0 <= p2 < len(queue):
            self._save_undo()
            queue[p1], queue[p2] = queue[p2], queue[p1]
            print(f"Swapped positions {p1+1} and {p2+1} in {queue_name}")
        else:
            print("Invalid positions")

    def do_sim(self, arg):
        """Run simulation: sim [duration_seconds]"""
        duration = int(arg) if arg.strip() else 600
        engine = SimulationEngine(self.bo, duration)
        self.last_result = engine.run()
        print_full_report(self.last_result)

    def do_compare(self, arg):
        """Compare with file: compare <file1> [file2...]"""
        if not arg:
            print("Usage: compare <file1> [file2...]")
            return
        files = arg.split()
        results = []
        # Run current BO
        engine = SimulationEngine(self.bo, 600)
        results.append(engine.run())
        # Run comparison files
        for f in files:
            try:
                bo = load_build_order(f.strip())
                eng = SimulationEngine(bo, 600)
                results.append(eng.run())
            except Exception as e:
                print(f"Error loading {f}: {e}")
        compare_and_print(results)

    def do_set(self, arg):
        """Set map parameter: set <param> <value>
        Params: wind, mex_value, mex_spots, has_geo"""
        parts = arg.split()
        if len(parts) < 2:
            print("Usage: set <param> <value>")
            return
        param, value = parts[0], parts[1]
        mc = self.bo.map_config
        if param == "wind":
            mc.avg_wind = float(value)
        elif param == "mex_value":
            mc.mex_value = float(value)
        elif param == "mex_spots":
            mc.mex_spots = int(value)
        elif param == "has_geo":
            mc.has_geo = value.lower() in ("true", "1", "yes")
        else:
            print(f"Unknown param: {param}")
            return
        print(f"Set {param} = {value}")

    def do_units(self, arg):
        """List available unit keys"""
        print(f"\n{'Key':<20} {'Name':<30} {'Metal':>6} {'Energy':>8} {'Build Time':>10}")
        print("-" * 76)
        for key in sorted(UNITS.keys()):
            u = UNITS[key]
            print(f"{key:<20} {u.name:<30} {u.metal_cost:>6} {u.energy_cost:>8} {u.build_time:>10}")
        print()

    def do_info(self, arg):
        """Show unit info: info <unit_key>"""
        if not arg:
            print("Usage: info <unit_key>")
            return
        key = arg.strip()
        u = UNITS.get(key)
        if not u:
            print(f"Unknown unit: {key}")
            return
        print(f"\n  {u.name} ({key})")
        print(f"  Metal cost:      {u.metal_cost}")
        print(f"  Energy cost:     {u.energy_cost}")
        print(f"  Build time:      {u.build_time} (={u.build_time/200:.1f}s @200BP)")
        if u.build_power:
            print(f"  Build power:     {u.build_power}")
        if u.metal_production:
            print(f"  Metal prod:      {u.metal_production}/s")
        if u.energy_production:
            print(f"  Energy prod:     {u.energy_production}/s")
        if u.energy_upkeep:
            print(f"  Energy upkeep:   {u.energy_upkeep}/s")
        print(f"  Notes: {u.notes}")
        print()

    def do_faction(self, arg):
        """Switch faction: faction armada|cortex"""
        if not arg or arg.strip().lower() not in ("armada", "cortex"):
            print("Usage: faction armada|cortex")
            return
        from bar_sim.econ import set_faction
        faction = arg.strip().upper()
        set_faction(faction)
        print(f"Switched to {faction} ({len(UNITS)} units loaded)")

    def do_undo(self, arg):
        """Undo last change"""
        if self.undo_stack:
            self.redo_stack.append(copy.deepcopy(self.bo))
            self.bo = self.undo_stack.pop()
            print("Undone.")
        else:
            print("Nothing to undo.")

    def do_redo(self, arg):
        """Redo last undone change"""
        if self.redo_stack:
            self.undo_stack.append(copy.deepcopy(self.bo))
            self.bo = self.redo_stack.pop()
            print("Redone.")
        else:
            print("Nothing to redo.")

    def do_strategy(self, arg):
        """View or set strategy config: strategy [param] [value]
        No args = show current config. With args = set param."""
        if not arg:
            if not self.bo.strategy_config:
                print("No strategy config set. Use 'strategy enable' to enable strategy mode.")
                return
            cfg = self.bo.strategy_config
            print(f"\n  Strategy: {cfg.summary()}")
            print(f"  opening_mex_count:  {cfg.opening_mex_count}")
            print(f"  energy_strategy:    {cfg.energy_strategy.value}")
            print(f"  unit_composition:   {cfg.unit_composition.value}")
            print(f"  posture:            {cfg.posture.value}")
            print(f"  t2_timing:          {cfg.t2_timing.value}")
            print(f"  role:               {cfg.role.value}")
            print(f"  emergency_mode:     {cfg.emergency_mode.value}")
            print(f"  rally_threshold:    {cfg.rally_threshold}")
            print()
            return

        parts = arg.split()
        if parts[0] == "enable":
            from bar_sim.strategy import StrategyConfig
            self.bo.strategy_config = StrategyConfig()
            print("Strategy mode enabled (default config)")
            return
        if parts[0] == "disable":
            self.bo.strategy_config = None
            print("Strategy mode disabled")
            return

        if len(parts) < 2:
            print("Usage: strategy <param> <value>")
            return

        if not self.bo.strategy_config:
            from bar_sim.strategy import StrategyConfig
            self.bo.strategy_config = StrategyConfig()

        from bar_sim.strategy import parse_strategy_string
        cfg = parse_strategy_string(f"{parts[0]}={parts[1]}")
        for attr in vars(cfg):
            val = getattr(cfg, attr)
            default = getattr(self.bo.strategy_config.__class__(), attr, None)
            if val != default:
                setattr(self.bo.strategy_config, attr, val)
                print(f"Set {parts[0]} = {parts[1]}")
                return
        print(f"Unknown param: {parts[0]}")

    def do_goals(self, arg):
        """List goals from last sim run"""
        if not self.last_result:
            print("Run 'sim' first to see goal results.")
            return
        if self.last_result.goal_completions:
            from bar_sim.format import fmt_time
            print("\nGoal completions:")
            for tick, desc in self.last_result.goal_completions:
                print(f"  {fmt_time(tick):>6}  {desc}")
        else:
            print("No goal completions recorded.")

    def do_composition(self, arg):
        """Show army composition from last sim run"""
        if not self.last_result:
            print("Run 'sim' first to see composition.")
            return
        if self.last_result.army_composition_final:
            from bar_sim.format import print_army_composition
            print_army_composition(self.last_result)
        else:
            print("No army composition data (not in strategy mode?)")

    def do_emergency(self, arg):
        """Set emergency mode: emergency <mode> [start_tick] [duration]
        Modes: none, defend_base, mobilization"""
        parts = arg.split()
        if not parts:
            print("Usage: emergency <mode> [start_tick] [duration]")
            return
        if not self.bo.strategy_config:
            from bar_sim.strategy import StrategyConfig
            self.bo.strategy_config = StrategyConfig()
        from bar_sim.strategy import EmergencyMode
        try:
            self.bo.strategy_config.emergency_mode = EmergencyMode(parts[0])
        except ValueError:
            print(f"Unknown mode: {parts[0]}. Use: none, defend_base, mobilization")
            return
        if len(parts) >= 2:
            self.bo.strategy_config.emergency_start_tick = int(parts[1])
        if len(parts) >= 3:
            self.bo.strategy_config.emergency_duration = int(parts[2])
        print(f"Emergency: {self.bo.strategy_config.emergency_mode.value}")

    def do_quit(self, arg):
        """Exit the REPL"""
        print("Bye!")
        return True

    do_exit = do_quit
    do_q = do_quit

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _get_queue(self, name):
        if name in ("com", "commander"):
            return self.bo.commander_queue
        if name.startswith("fac"):
            fid = "factory_" + name[3:]
            if fid not in self.bo.factory_queues:
                self.bo.factory_queues[fid] = []
            return self.bo.factory_queues[fid]
        if name.startswith("con"):
            cid = "con_" + name[3:]
            if cid not in self.bo.constructor_queues:
                self.bo.constructor_queues[cid] = []
            return self.bo.constructor_queues[cid]
        print(f"Unknown queue: {name}. Use com, fac0, con1, etc.")
        return None
