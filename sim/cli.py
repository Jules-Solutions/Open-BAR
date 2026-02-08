"""
BAR Build Order Simulator - CLI Entry Point
=============================================
Usage:
    python cli.py simulate <file> [--duration 600] [--export-json out.json]
    python cli.py compare <file1> <file2> [...]
    python cli.py interactive
    python cli.py optimize --goal max_metal [--target-time 300] [--export-json out.json]
"""

import argparse
import sys

from bar_sim.io import load_build_order
from bar_sim.engine import SimulationEngine
from bar_sim.format import print_full_report
from bar_sim.compare import compare_and_print
from bar_sim.optimizer import Optimizer, make_goal
from bar_sim.models import MapConfig


def _resolve_map_config(map_name: str) -> MapConfig:
    """Resolve a map name to a MapConfig for the Python sim engine."""
    from bar_sim.map_data import get_map_data, map_data_to_map_config
    md = get_map_data(map_name)
    if md:
        mc = map_data_to_map_config(md)
        print(f"[map] {md.name}: wind={md.wind_min}-{md.wind_max}, "
              f"mex={mc.mex_spots}x{mc.mex_value}M, "
              f"tidal={mc.tidal_value}, geo={'yes' if mc.has_geo else 'no'}")
        return mc
    print(f"[map] Warning: '{map_name}' not found, using defaults")
    return MapConfig()


def cmd_simulate(args):
    bo = load_build_order(args.file)
    # Override map config if --map is specified
    if args.map:
        bo.map_config = _resolve_map_config(args.map)
        bo.map_name = args.map

    # CLI strategy override (creates or overrides strategy config)
    if args.strategy:
        from bar_sim.strategy import parse_strategy_string
        bo.strategy_config = parse_strategy_string(args.strategy)
        print(f"[strategy] {bo.strategy_config.summary()}")

    # CLI goal additions (only work in strategy mode)
    if args.goal:
        if not bo.strategy_config:
            from bar_sim.strategy import StrategyConfig
            bo.strategy_config = StrategyConfig()
            print("[strategy] Auto-enabled strategy mode for goals")

    if getattr(args, "engine", "python") == "headless":
        from bar_sim.headless import HeadlessEngine
        engine = HeadlessEngine(map_name=args.map or "delta_siege_dry_v5.7.1")
        result = engine.run(bo, args.duration, faction=args.faction)
    else:
        engine = SimulationEngine(bo, args.duration)

        # Add CLI goals to engine's goal queue (if strategy mode)
        if args.goal and engine._strategy_mode and engine._goal_queue:
            from bar_sim.goals import parse_goal_string
            for g_str in args.goal:
                g = parse_goal_string(g_str)
                if g:
                    engine._goal_queue.add(
                        g.goal_type, g.description,
                        target_unit=g.target_unit,
                        target_count=g.target_count,
                        target_value=g.target_value,
                    )
                    print(f"[goal] Added: {g.description}")

        result = engine.run()
    print_full_report(result)

    if args.export_json:
        from bar_sim.io import export_build_order_json
        export_build_order_json(bo, args.export_json)
        print(f"\nExported JSON to {args.export_json}")


def cmd_compare(args):
    results = []
    for f in args.files:
        try:
            bo = load_build_order(f)
            engine = SimulationEngine(bo, args.duration)
            results.append(engine.run())
        except Exception as e:
            print(f"Error loading {f}: {e}")
    if results:
        compare_and_print(results)


def cmd_interactive(args):
    from bar_sim.repl import BuildOrderREPL
    repl = BuildOrderREPL()
    repl.cmdloop()


def cmd_map(args):
    """Handle map list|info|scan subcommands."""
    action = args.map_action

    if action == "list":
        from bar_sim.map_parser import list_available_maps
        from bar_sim.map_data import list_cached_maps
        maps = list_available_maps()
        cached = set(list_cached_maps())
        print(f"Available maps: {len(maps)}")
        print(f"{'Name':<45} {'Metal':>5} {'Tidal':>5} {'Scanned':>7}")
        print("-" * 65)
        for m in maps:
            stem = m["filename"].replace(".sd7", "")
            scanned = "yes" if stem in cached else ""
            print(f"{m['name'][:44]:<45} {m['max_metal']:>5.1f} {m['tidal_strength']:>5.1f} {scanned:>7}")

    elif action == "info":
        from bar_sim.map_data import get_map_data, map_data_to_map_config
        md = get_map_data(args.name)
        if not md:
            print(f"Map not found: {args.name}")
            return
        mc = map_data_to_map_config(md)
        print(f"Map: {md.name}")
        print(f"  Filename:    {md.filename}")
        print(f"  Author:      {md.author}")
        print(f"  Wind:        {md.wind_min} - {md.wind_max}")
        print(f"  Tidal:       {md.tidal_strength}")
        print(f"  Max Metal:   {md.max_metal}")
        print(f"  Gravity:     {md.gravity}")
        print(f"  Dimensions:  {md.map_width} x {md.map_height}")
        print(f"  Mex spots:   {len(md.mex_spots)} total, {mc.mex_spots} for player")
        print(f"  Geo vents:   {len(md.geo_vents)}")
        print(f"  Reclaim:     {md.total_reclaim_metal:.0f}M / {md.total_reclaim_energy:.0f}E")
        print(f"  Starts:      {len(md.start_positions)} positions")
        print(f"  Source:      {md.source}")
        print(f"\n  SimEngine MapConfig:")
        print(f"    avg_wind={mc.avg_wind}, mex_value={mc.mex_value}, "
              f"mex_spots={mc.mex_spots}, has_geo={mc.has_geo}, "
              f"tidal={mc.tidal_value}")

    elif action == "scan":
        from bar_sim.headless import HeadlessEngine
        try:
            he = HeadlessEngine()
            md = he.scan_map(args.name)
            print(f"\nScan complete: {md.name}")
            print(f"  Mex spots: {len(md.mex_spots)}")
            print(f"  Geo vents: {len(md.geo_vents)}")
            print(f"  Wind: {md.wind_min} - {md.wind_max}")
            print(f"  Starts: {len(md.start_positions)}")
        except (FileNotFoundError, RuntimeError) as e:
            print(f"Scan failed: {e}")

    elif action == "cache-popular":
        POPULAR_MAPS = [
            "delta_siege_dry", "comet_catcher_remake", "supreme_isthmus",
            "supreme_battlefield", "eye_of_horus", "quicksilver_remake",
            "all_that_glitters",
        ]
        from bar_sim.headless import HeadlessEngine
        from bar_sim.map_data import list_cached_maps
        cached = set(list_cached_maps())
        he = None
        for map_name in POPULAR_MAPS:
            if map_name in cached:
                print(f"  [cached] {map_name}")
                continue
            print(f"  [scanning] {map_name}...")
            try:
                if he is None:
                    he = HeadlessEngine()
                md = he.scan_map(map_name)
                print(f"    -> {len(md.mex_spots)} mex spots, {len(md.geo_vents)} geo vents")
            except Exception as e:
                print(f"    -> FAILED: {e}")


def cmd_optimize(args):
    from pathlib import Path

    # If --map is specified, auto-resolve MapConfig from map data
    map_label = "defaults"
    if args.map:
        mc = _resolve_map_config(args.map)
        map_label = args.map
    else:
        mc = MapConfig(
            avg_wind=args.wind,
            mex_value=args.mex_value,
            mex_spots=args.mex_spots,
            has_geo=args.has_geo,
        )

    goal = make_goal(args.goal, target_time=args.target_time)

    print("=" * 60)
    print("  BAR BUILD ORDER OPTIMIZER")
    print("=" * 60)
    print(f"  Goal:        {goal.description}")
    print(f"  Map:         {map_label}")
    print(f"  Wind:        avg={mc.avg_wind}, variance={mc.wind_variance}")
    print(f"  Mex:         {mc.mex_spots} spots x {mc.mex_value} M/s")
    print(f"  Geo:         {'yes' if mc.has_geo else 'no'}")
    print(f"  GA:          pop={args.pop_size}, generations={args.generations}")
    print(f"  Duration:    {args.duration}s")
    print("=" * 60)
    print()

    # Load starting BO if provided
    initial_bo = None
    if args.start_from:
        initial_bo = load_build_order(args.start_from)
        initial_bo.map_config = mc
        print(f"Starting from: {initial_bo.name}")

    opt = Optimizer(
        goal=goal,
        map_config=mc,
        duration=args.duration,
        population_size=args.pop_size,
        max_generations=args.generations,
        verbose=True,
    )
    best = opt.optimize(initial_bo)

    # Show the result
    print("\n" + "=" * 60)
    print("  OPTIMIZED BUILD ORDER")
    print("=" * 60)

    print(f"\nCommander Queue ({len(best.commander_queue)} items):")
    from bar_sim.econ import UNITS
    for i, a in enumerate(best.commander_queue):
        unit = UNITS.get(a.unit_key)
        name = unit.name if unit else a.unit_key
        print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")

    for fid, q in best.factory_queues.items():
        print(f"\n{fid} Queue ({len(q)} items):")
        for i, a in enumerate(q):
            unit = UNITS.get(a.unit_key)
            name = unit.name if unit else a.unit_key
            print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")

    for cid, q in best.constructor_queues.items():
        print(f"\n{cid} Queue ({len(q)} items):")
        for i, a in enumerate(q):
            unit = UNITS.get(a.unit_key)
            name = unit.name if unit else a.unit_key
            print(f"  {i+1:>3}. {a.unit_key:<18} ({name})")

    # Run final sim and show top N comparison if requested
    print("\n--- SIMULATION OF OPTIMIZED BUILD ---")
    engine = SimulationEngine(best, args.duration)
    result = engine.run()
    print_full_report(result)

    # Show top N candidates comparison
    top_n = getattr(args, "top", 1)
    if top_n > 1 and hasattr(opt, "top_results") and opt.top_results:
        print(f"\n--- TOP {min(top_n, len(opt.top_results))} CANDIDATES ---")
        print(f"{'#':<4} {'Score':>10} {'Factory(s)':>10} {'Metal @300':>10}")
        print("-" * 40)
        for i, (score, bo_candidate) in enumerate(opt.top_results[:top_n]):
            sim = SimulationEngine(bo_candidate, args.duration)
            r = sim.run()
            factory_tick = r.time_to_first_factory or "-"
            metal_300 = "-"
            for snap in r.snapshots:
                if snap.tick >= 300:
                    metal_300 = f"{snap.metal_income:.1f}"
                    break
            print(f"{i+1:<4} {score:>10.2f} {str(factory_tick):>10} {metal_300:>10}")

    # Auto-save: if --output not specified, save to default path
    output_path = args.output
    if not output_path:
        data_dir = Path(__file__).parent / "data" / "build_orders"
        data_dir.mkdir(parents=True, exist_ok=True)
        map_slug = map_label.replace(" ", "_").lower()
        output_path = str(data_dir / f"optimized_{map_slug}_{args.goal}.yaml")

    from bar_sim.io import save_build_order
    save_build_order(best, output_path)
    print(f"\nSaved to {output_path}")

    if args.export_json:
        from bar_sim.io import export_build_order_json
        export_build_order_json(best, args.export_json)
        print(f"\nExported JSON to {args.export_json}")


def main():
    parser = argparse.ArgumentParser(
        description="BAR Build Order Simulator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--faction", choices=["armada", "cortex"],
                       default="armada",
                       help="Faction to simulate (default: armada)")
    sub = parser.add_subparsers(dest="command", help="Command to run")

    # simulate
    p_sim = sub.add_parser("simulate", aliases=["sim"],
                           help="Simulate a build order from YAML")
    p_sim.add_argument("file", help="Path to build order YAML file")
    p_sim.add_argument("--duration", "-d", type=int, default=600,
                       help="Simulation duration in seconds (default: 600)")
    p_sim.add_argument("--engine", "-e", choices=["python", "headless"],
                       default="python",
                       help="Simulation engine (default: python)")
    p_sim.add_argument("--map", "-m", default=None,
                       help="Map name (auto-populates wind/mex/tidal from map data)")
    p_sim.add_argument("--export-json", default=None,
                       help="Export build order as JSON for Lua widget consumption")
    p_sim.add_argument("--strategy", "-s", default=None,
                       help="Strategy config: 'role=aggro,composition=bots,posture=aggressive'")
    p_sim.add_argument("--goal", "-g", action="append", default=None,
                       help="Add goal (repeatable): 'economy_target:20' or 'tech_transition'")

    # compare
    p_cmp = sub.add_parser("compare", aliases=["cmp"],
                           help="Compare multiple build orders")
    p_cmp.add_argument("files", nargs="+", help="Build order YAML files")
    p_cmp.add_argument("--duration", "-d", type=int, default=600,
                       help="Simulation duration in seconds (default: 600)")

    # interactive
    p_int = sub.add_parser("interactive", aliases=["repl", "i"],
                           help="Interactive REPL mode")

    # optimize
    p_opt = sub.add_parser("optimize", aliases=["opt"],
                           help="Auto-optimize a build order")
    p_opt.add_argument("--goal", "-g", required=True,
                       choices=["max_metal", "max_energy", "fastest_factory",
                                "fastest_t2", "max_army", "min_stall", "balanced"],
                       help="Optimization goal")
    p_opt.add_argument("--target-time", "-t", type=int, default=300,
                       help="Target time for time-based goals (default: 300)")
    p_opt.add_argument("--duration", "-d", type=int, default=600,
                       help="Simulation duration (default: 600)")
    p_opt.add_argument("--generations", "-n", type=int, default=100,
                       help="GA generations (default: 100)")
    p_opt.add_argument("--pop-size", "-p", type=int, default=60,
                       help="Population size (default: 60)")
    p_opt.add_argument("--wind", type=float, default=12.0,
                       help="Average wind speed (default: 12.0)")
    p_opt.add_argument("--mex-value", type=float, default=2.0,
                       help="Metal extractor value (default: 2.0)")
    p_opt.add_argument("--mex-spots", type=int, default=6,
                       help="Available mex spots (default: 6)")
    p_opt.add_argument("--has-geo", action="store_true",
                       help="Map has geothermal vent")
    p_opt.add_argument("--map", default=None,
                       help="Map name (overrides manual wind/mex/tidal args)")
    p_opt.add_argument("--start-from", "-s",
                       help="Start from existing build order YAML")
    p_opt.add_argument("--output", "-o",
                       help="Save optimized build order to YAML")
    p_opt.add_argument("--top", type=int, default=1,
                       help="Show top N candidates after optimization (default: 1)")
    p_opt.add_argument("--export-json", default=None,
                       help="Export optimized build order as JSON for Lua widget consumption")

    # map
    p_map = sub.add_parser("map", help="Map data management")
    p_map.add_argument("map_action", choices=["list", "info", "scan", "cache-popular"],
                       help="list=show all maps, info=show details, scan=headless scan, cache-popular=scan popular maps")
    p_map.add_argument("name", nargs="?", default=None,
                       help="Map name (required for info/scan)")

    # web
    p_web = sub.add_parser("web", aliases=["serve"],
                           help="Start the web frontend")
    p_web.add_argument("--port", type=int, default=8080,
                       help="Port to serve on (default: 8080)")

    args = parser.parse_args()

    # Apply faction selection before running any command
    if args.faction != "armada":
        from bar_sim.econ import set_faction
        set_faction(args.faction.upper())

    if args.command in ("simulate", "sim"):
        cmd_simulate(args)
    elif args.command in ("compare", "cmp"):
        cmd_compare(args)
    elif args.command in ("interactive", "repl", "i"):
        cmd_interactive(args)
    elif args.command in ("optimize", "opt"):
        cmd_optimize(args)
    elif args.command == "map":
        cmd_map(args)
    elif args.command in ("web", "serve"):
        from bar_sim.web import start_server
        start_server(port=args.port)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
