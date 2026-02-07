"""
BAR Build Order Simulator - Output Formatting
================================================
Pretty-printing for simulation results.
"""

from bar_sim.models import SimResult, Snapshot


def fmt_time(tick: int) -> str:
    m, s = divmod(tick, 60)
    return f"{m}:{s:02d}"


def fmt_rate(val: float) -> str:
    if val >= 1000:
        return f"{val:.0f}"
    return f"{val:.1f}"


def print_full_report(result: SimResult):
    print()
    print("=" * 70)
    print(f"  BAR BUILD ORDER SIMULATOR")
    print(f"  Build Order: {result.build_order_name}")
    if result.strategy_used:
        print(f"  Strategy: {result.strategy_used}")
    print(f"  Duration: {fmt_time(result.total_ticks)}")
    print("=" * 70)

    print_timeline(result)
    print_milestones(result)
    print_snapshots(result)
    print_stall_events(result)
    if result.army_composition_final:
        print_army_composition(result)
    if result.goal_completions:
        print_goal_completions(result)
    print_summary(result)


def print_timeline(result: SimResult):
    print()
    print("--- CONSTRUCTION TIMELINE ---")
    print(f" {'Time':>6}  {'Builder':<14} {'Completed':<24} {'M/s':>6} {'E/s':>7}")
    print(f" {'----':>6}  {'-------':<14} {'---------':<24} {'---':>6} {'---':>7}")

    # Find the income at each completion tick from snapshots
    snap_map = {}
    for s in result.snapshots:
        snap_map[s.tick] = s

    for tick, unit_key, builder_id in result.completion_log:
        # Find nearest snapshot for income data
        nearest = None
        for s in result.snapshots:
            if s.tick <= tick:
                nearest = s
            else:
                break

        m_inc = nearest.metal_income if nearest else 0
        e_inc = nearest.energy_income if nearest else 0

        # Use milestone data if available (more accurate for that tick)
        for ms in result.milestones:
            if ms.tick == tick:
                m_inc = ms.metal_income
                e_inc = ms.energy_income
                break

        from bar_sim.econ import UNITS
        unit = UNITS.get(unit_key)
        name = unit.name if unit else unit_key

        print(f" {fmt_time(tick):>6}  {builder_id:<14} {name:<24} {fmt_rate(m_inc):>6} {fmt_rate(e_inc):>7}")


def print_milestones(result: SimResult):
    if not result.milestones:
        return
    print()
    print("--- MILESTONES ---")
    for m in sorted(result.milestones, key=lambda x: x.tick):
        print(f" {m.event:<22} {fmt_time(m.tick):>6}  "
              f"(M: {fmt_rate(m.metal_income)}/s, E: {fmt_rate(m.energy_income)}/s)")


def print_snapshots(result: SimResult):
    print()
    print("--- ECONOMY SNAPSHOTS ---")
    print(f" {'Time':>6} {'M/s':>6} {'E/s':>7} {'M strd':>8} {'E strd':>8} "
          f"{'BP':>5} {'Army M':>8} {'Stall':>6}")
    print(f" {'----':>6} {'---':>6} {'---':>7} {'------':>8} {'------':>8} "
          f"{'--':>5} {'------':>8} {'-----':>6}")

    for s in result.snapshots:
        stall_str = "" if s.stall_factor >= 0.95 else f"{s.stall_factor:.0%}"
        print(f" {fmt_time(s.tick):>6} {fmt_rate(s.metal_income):>6} "
              f"{fmt_rate(s.energy_income):>7} {s.metal_stored:>8.0f} "
              f"{s.energy_stored:>8.0f} {s.build_power:>5} "
              f"{s.army_value_metal:>8.0f} {stall_str:>6}")


def print_stall_events(result: SimResult):
    print()
    if not result.stall_events:
        print("--- STALL EVENTS ---")
        print(" None! (clean build order)")
        return

    print("--- STALL EVENTS ---")
    for se in result.stall_events:
        duration = se.end_tick - se.start_tick + 1
        print(f" {fmt_time(se.start_tick)}-{fmt_time(se.end_tick)} "
              f"{se.resource:<8} {duration:>3}s  severity: {se.severity:.0%}")


def print_army_composition(result: SimResult):
    if not result.army_composition_final:
        return
    print()
    print("--- ARMY COMPOSITION ---")
    total = sum(result.army_composition_final.values())
    if total == 0:
        print(" No units produced")
        return
    print(f" {'Role':<16} {'Count':>6} {'%':>6}")
    print(f" {'-' * 16} {'-' * 6} {'-' * 6}")
    for role in sorted(result.army_composition_final.keys()):
        count = result.army_composition_final[role]
        pct = count / total * 100
        print(f" {role:<16} {count:>6} {pct:>5.1f}%")
    print(f" {'TOTAL':<16} {total:>6}")


def print_goal_completions(result: SimResult):
    if not result.goal_completions:
        return
    print()
    print("--- GOAL COMPLETIONS ---")
    for tick, desc in result.goal_completions:
        print(f" {fmt_time(tick):>6}  {desc}")


def print_summary(result: SimResult):
    print()
    print("--- SUMMARY ---")
    print(f" Total army value:     {result.total_army_metal_value:.0f} metal")
    print(f" Peak M/s:             {fmt_rate(result.peak_metal_income)}")
    print(f" Peak E/s:             {fmt_rate(result.peak_energy_income)}")
    print(f" Metal stall seconds:  {result.total_metal_stall_seconds}")
    print(f" Energy stall seconds: {result.total_energy_stall_seconds}")

    if result.time_to_first_factory:
        print(f" First factory:        {fmt_time(result.time_to_first_factory)}")
    if result.time_to_first_constructor:
        print(f" First constructor:    {fmt_time(result.time_to_first_constructor)}")
    if result.time_to_first_nano:
        print(f" First nano:           {fmt_time(result.time_to_first_nano)}")
