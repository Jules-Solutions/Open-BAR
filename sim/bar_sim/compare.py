"""
BAR Build Order Simulator - Comparison
========================================
Side-by-side build order comparison.
"""

from typing import List
from bar_sim.models import SimResult
from bar_sim.format import fmt_time, fmt_rate


def _find_snapshot_at(result: SimResult, tick: int):
    best = None
    for s in result.snapshots:
        if s.tick <= tick:
            best = s
        else:
            break
    return best


def compare_and_print(results: List[SimResult]):
    if not results:
        return

    names = [r.build_order_name for r in results]
    col_w = max(20, max(len(n) for n in names) + 2)

    print()
    print("=" * (16 + col_w * len(results)))
    print("  BUILD ORDER COMPARISON")
    print("=" * (16 + col_w * len(results)))

    # Header
    print(f"{'':>16}", end="")
    for name in names:
        print(f"{name:>{col_w}}", end="")
    print()
    print(f"{'':>16}", end="")
    for _ in names:
        print(f"{'=' * (col_w - 2):>{col_w}}", end="")
    print()

    # Milestones
    print("\nMILESTONES")
    milestone_keys = [
        ("first_factory", "1st Factory"),
        ("first_scout", "1st Scout"),
        ("first_constructor", "1st Con"),
        ("first_nano", "1st Nano"),
    ]
    for key, label in milestone_keys:
        print(f" {label:<15}", end="")
        for r in results:
            ms = next((m for m in r.milestones if m.event == key), None)
            val = fmt_time(ms.tick) if ms else "--"
            print(f"{val:>{col_w}}", end="")
        print()

    # Economy at checkpoints
    for t in [180, 300, 420]:
        print(f"\nECONOMY @ {fmt_time(t)}")
        print(f" {'M/s':<15}", end="")
        for r in results:
            s = _find_snapshot_at(r, t)
            print(f"{fmt_rate(s.metal_income) if s else '--':>{col_w}}", end="")
        print()

        print(f" {'E/s':<15}", end="")
        for r in results:
            s = _find_snapshot_at(r, t)
            print(f"{fmt_rate(s.energy_income) if s else '--':>{col_w}}", end="")
        print()

        print(f" {'Stored M':<15}", end="")
        for r in results:
            s = _find_snapshot_at(r, t)
            print(f"{f'{s.metal_stored:.0f}' if s else '--':>{col_w}}", end="")
        print()

        print(f" {'Army Value':<15}", end="")
        for r in results:
            s = _find_snapshot_at(r, t)
            print(f"{f'{s.army_value_metal:.0f}' if s else '--':>{col_w}}", end="")
        print()

    # Army composition (strategy mode)
    has_army = any(r.army_composition_final for r in results)
    if has_army:
        print(f"\nARMY COMPOSITION")
        all_roles = set()
        for r in results:
            all_roles.update(r.army_composition_final.keys())
        for role in sorted(all_roles):
            print(f" {role:<15}", end="")
            for r in results:
                count = r.army_composition_final.get(role, 0)
                print(f"{str(count):>{col_w}}", end="")
            print()

    # Stalling
    print(f"\nSTALLING")
    print(f" {'Metal stall':<15}", end="")
    for r in results:
        print(f"{f'{r.total_metal_stall_seconds}s':>{col_w}}", end="")
    print()
    print(f" {'Energy stall':<15}", end="")
    for r in results:
        print(f"{f'{r.total_energy_stall_seconds}s':>{col_w}}", end="")
    print()

    # Winners
    print(f"\nWINNER BY CATEGORY")
    _print_winner("Fastest Factory", results, names,
                  lambda r: r.time_to_first_factory,
                  lambda v: fmt_time(v), lower_is_better=True)
    _print_winner("Best 5:00 eco", results, names,
                  lambda r: _find_snapshot_at(r, 300).metal_income if _find_snapshot_at(r, 300) else 0,
                  lambda v: f"{v:.1f} M/s")
    _print_winner("Best 5:00 army", results, names,
                  lambda r: _find_snapshot_at(r, 300).army_value_metal if _find_snapshot_at(r, 300) else 0,
                  lambda v: f"{v:.0f} metal")
    _print_winner("Least stalling", results, names,
                  lambda r: r.total_metal_stall_seconds + r.total_energy_stall_seconds,
                  lambda v: f"{v}s", lower_is_better=True)
    print()


def _print_winner(label, results, names, metric_fn, fmt_fn, lower_is_better=False):
    vals = []
    for r in results:
        try:
            v = metric_fn(r)
            vals.append(v if v is not None else (float('inf') if lower_is_better else float('-inf')))
        except Exception:
            vals.append(float('inf') if lower_is_better else float('-inf'))

    if lower_is_better:
        best_idx = min(range(len(vals)), key=lambda i: vals[i])
    else:
        best_idx = max(range(len(vals)), key=lambda i: vals[i])

    best_val = vals[best_idx]
    if best_val in (float('inf'), float('-inf')):
        return

    print(f" {label:<20} {names[best_idx]} ({fmt_fn(best_val)})")
