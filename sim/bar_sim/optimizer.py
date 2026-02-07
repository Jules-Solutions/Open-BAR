"""
BAR Build Order Simulator - Optimizer
=======================================
Genetic Algorithm optimizer with tournament selection, crossover,
adaptive mutation, elitism, and stagnation-triggered restarts.

Inspired by NatSte01/AUTOMATED-BUILD-ORDERS but built on top of our
tick-based multi-builder simulation engine for much higher fidelity.
"""

import copy
import random
import time
from typing import List, Optional, Callable, Tuple

from bar_sim.econ import UNITS
from bar_sim.models import (
    BuildOrder, BuildAction, BuildActionType, MapConfig, SimResult, Snapshot,
)
from bar_sim.engine import SimulationEngine, FACTORY_KEYS, CONSTRUCTOR_KEYS


# ---------------------------------------------------------------------------
# Optimization goals
# ---------------------------------------------------------------------------

class OptGoal:
    """An optimization objective with a scoring function."""

    def __init__(self, name: str, description: str,
                 score_fn: Callable[[SimResult], float],
                 higher_is_better: bool = True):
        self.name = name
        self.description = description
        self.score_fn = score_fn
        self.higher_is_better = higher_is_better

    def score(self, result: SimResult) -> float:
        return self.score_fn(result)

    def is_better(self, a: float, b: float) -> bool:
        """Is score `a` better than score `b`?"""
        if self.higher_is_better:
            return a > b
        return a < b

    @property
    def worst_score(self) -> float:
        return float('-inf') if self.higher_is_better else float('inf')


def _snap_at(result: SimResult, tick: int) -> Optional[Snapshot]:
    best = None
    for s in result.snapshots:
        if s.tick <= tick:
            best = s
        else:
            break
    return best


def make_goal(goal_name: str, target_time: int = 300) -> OptGoal:
    """Create an optimization goal by name."""
    goals = {
        "max_metal": OptGoal(
            name="max_metal",
            description=f"Maximize metal income at {target_time}s",
            score_fn=lambda r: (_snap_at(r, target_time).metal_income
                                if _snap_at(r, target_time) else 0),
        ),
        "max_energy": OptGoal(
            name="max_energy",
            description=f"Maximize energy income at {target_time}s",
            score_fn=lambda r: (_snap_at(r, target_time).energy_income
                                if _snap_at(r, target_time) else 0),
        ),
        "fastest_factory": OptGoal(
            name="fastest_factory",
            description="Minimize time to first factory",
            score_fn=lambda r: r.time_to_first_factory or 9999,
            higher_is_better=False,
        ),
        "fastest_t2": OptGoal(
            name="fastest_t2",
            description="Minimize time to T2 lab",
            score_fn=lambda r: r.time_to_t2_lab or 9999,
            higher_is_better=False,
        ),
        "max_army": OptGoal(
            name="max_army",
            description=f"Maximize army metal value at {target_time}s",
            score_fn=lambda r: (_snap_at(r, target_time).army_value_metal
                                if _snap_at(r, target_time) else 0),
        ),
        "min_stall": OptGoal(
            name="min_stall",
            description="Minimize total stall seconds",
            score_fn=lambda r: r.total_metal_stall_seconds + r.total_energy_stall_seconds,
            higher_is_better=False,
        ),
        "balanced": OptGoal(
            name="balanced",
            description=f"Balanced score (eco + army - stalls) at {target_time}s",
            score_fn=lambda r: _balanced_score(r, target_time),
        ),
    }
    if goal_name not in goals:
        raise ValueError(f"Unknown goal: {goal_name}. Choose from: {list(goals.keys())}")
    return goals[goal_name]


def _balanced_score(result: SimResult, target_time: int) -> float:
    snap = _snap_at(result, target_time)
    if not snap:
        return 0
    metal_score = snap.metal_income * 10
    energy_score = snap.energy_income * 0.5
    army_score = snap.army_value_metal * 0.1
    stall_penalty = (result.total_metal_stall_seconds + result.total_energy_stall_seconds) * 2
    return metal_score + energy_score + army_score - stall_penalty


# ---------------------------------------------------------------------------
# Unit pools & constraints
# ---------------------------------------------------------------------------

# Common opening structures for commander
COMMANDER_POOL = ["mex", "wind", "solar", "bot_lab", "vehicle_plant", "radar",
                  "llt", "nano", "energy_storage", "metal_storage",
                  "adv_bot_lab", "adv_vehicle_plant", "geo_t1", "hlt"]

# Units producible by factories
FACTORY_PRODUCIBLE = ["tick", "pawn", "grunt", "rocketer", "flash", "stumpy",
                      "con_bot", "con_vehicle", "rez_bot"]

# Constructor building pool
CON_POOL = ["mex", "wind", "solar", "radar", "llt", "nano",
            "energy_storage", "metal_storage", "hlt", "adv_solar"]


def _has_factory(bo: BuildOrder) -> bool:
    return any(a.unit_key in FACTORY_KEYS for a in bo.commander_queue)


def _mex_count(bo: BuildOrder) -> int:
    count = sum(1 for a in bo.commander_queue if a.unit_key == "mex")
    for q in bo.constructor_queues.values():
        count += sum(1 for a in q if a.unit_key == "mex")
    return count


def _all_queues(bo: BuildOrder) -> List[List[BuildAction]]:
    result = []
    if bo.commander_queue:
        result.append(bo.commander_queue)
    for q in bo.factory_queues.values():
        if q:
            result.append(q)
    for q in bo.constructor_queues.values():
        if q:
            result.append(q)
    return result


def _all_queues_with_pools(bo: BuildOrder):
    result = []
    if bo.commander_queue:
        result.append((bo.commander_queue, COMMANDER_POOL))
    for fid, q in bo.factory_queues.items():
        if q:
            result.append((q, FACTORY_PRODUCIBLE))
    for cid, q in bo.constructor_queues.items():
        if q:
            result.append((q, CON_POOL))
    return result


def enforce_constraints(bo: BuildOrder, map_config: MapConfig) -> BuildOrder:
    """Fix constraint violations in a build order."""
    if not _has_factory(bo):
        pos = min(4, len(bo.commander_queue))
        bo.commander_queue.insert(pos, BuildAction(unit_key="bot_lab"))

    total_mex = _mex_count(bo)
    if total_mex > map_config.mex_spots:
        excess = total_mex - map_config.mex_spots
        for q in bo.constructor_queues.values():
            for i in range(len(q) - 1, -1, -1):
                if excess <= 0:
                    break
                if q[i].unit_key == "mex":
                    q.pop(i)
                    excess -= 1
        if excess > 0:
            for i in range(len(bo.commander_queue) - 1, -1, -1):
                if excess <= 0:
                    break
                if bo.commander_queue[i].unit_key == "mex":
                    bo.commander_queue.pop(i)
                    excess -= 1

    if not map_config.has_geo:
        for q in _all_queues(bo):
            for i in range(len(q) - 1, -1, -1):
                if q[i].unit_key in ("geo_t1",):
                    q.pop(i)

    return bo


# ---------------------------------------------------------------------------
# Greedy seed generator
# ---------------------------------------------------------------------------

def greedy_seed(map_config: MapConfig, duration: int = 600,
                max_com_queue: int = 15, max_fac_queue: int = 12,
                max_con_queue: int = 8) -> BuildOrder:
    """Generate a reasonable starting build order using economic heuristics."""
    bo = BuildOrder(name="Greedy Seed", map_config=copy.deepcopy(map_config))
    com = bo.commander_queue

    com.append(BuildAction(unit_key="mex"))
    com.append(BuildAction(unit_key="mex"))

    energy_key = "wind" if map_config.avg_wind >= 7 else "solar"
    com.append(BuildAction(unit_key=energy_key))
    com.append(BuildAction(unit_key=energy_key))
    com.append(BuildAction(unit_key="bot_lab"))
    com.append(BuildAction(unit_key="mex"))
    com.append(BuildAction(unit_key=energy_key))
    com.append(BuildAction(unit_key=energy_key))
    com.append(BuildAction(unit_key="radar"))

    mex_placed = 3
    remaining = max_com_queue - len(com)
    for i in range(remaining):
        if mex_placed < map_config.mex_spots and i % 3 == 0:
            com.append(BuildAction(unit_key="mex"))
            mex_placed += 1
        elif i == remaining - 1:
            com.append(BuildAction(unit_key="nano"))
        else:
            com.append(BuildAction(unit_key=energy_key))

    fac_q = []
    fac_q.append(BuildAction(unit_key="tick", action_type=BuildActionType.PRODUCE_UNIT))
    fac_q.append(BuildAction(unit_key="grunt", action_type=BuildActionType.PRODUCE_UNIT))
    fac_q.append(BuildAction(unit_key="grunt", action_type=BuildActionType.PRODUCE_UNIT))
    fac_q.append(BuildAction(unit_key="con_bot", action_type=BuildActionType.PRODUCE_UNIT))
    for _ in range(max_fac_queue - 4):
        fac_q.append(BuildAction(unit_key="grunt", action_type=BuildActionType.PRODUCE_UNIT))
    bo.factory_queues["factory_0"] = fac_q

    con_q = []
    con_mex = 0
    for i in range(max_con_queue):
        if con_mex < 3 and i % 2 == 0:
            con_q.append(BuildAction(unit_key="mex"))
            con_mex += 1
        else:
            con_q.append(BuildAction(unit_key=energy_key))
    bo.constructor_queues["con_1"] = con_q

    return bo


def random_seed(map_config: MapConfig, rng: random.Random,
                max_com: int = 15, max_fac: int = 12, max_con: int = 8) -> BuildOrder:
    """Generate a random (but valid) build order for population diversity."""
    bo = BuildOrder(name="Random Seed", map_config=copy.deepcopy(map_config))
    energy_key = "wind" if map_config.avg_wind >= 7 else "solar"

    # Commander: always start mex, mex, then random mix ending with a factory somewhere
    com = bo.commander_queue
    com.append(BuildAction(unit_key="mex"))
    com.append(BuildAction(unit_key="mex"))

    factory_placed = False
    for _ in range(rng.randint(8, max_com)):
        roll = rng.random()
        if not factory_placed and roll < 0.15:
            com.append(BuildAction(unit_key=rng.choice(["bot_lab", "vehicle_plant"])))
            factory_placed = True
        elif roll < 0.5:
            com.append(BuildAction(unit_key=energy_key))
        elif roll < 0.7:
            com.append(BuildAction(unit_key="mex"))
        else:
            com.append(BuildAction(unit_key=rng.choice(COMMANDER_POOL)))

    # Factory queue
    fac_q = []
    fac_q.append(BuildAction(unit_key="tick", action_type=BuildActionType.PRODUCE_UNIT))
    for _ in range(rng.randint(6, max_fac)):
        fac_q.append(BuildAction(
            unit_key=rng.choice(FACTORY_PRODUCIBLE),
            action_type=BuildActionType.PRODUCE_UNIT))
    bo.factory_queues["factory_0"] = fac_q

    # Constructor queue
    con_q = []
    for _ in range(rng.randint(4, max_con)):
        con_q.append(BuildAction(unit_key=rng.choice(CON_POOL)))
    bo.constructor_queues["con_1"] = con_q

    return bo


# ---------------------------------------------------------------------------
# Mutation operators
# ---------------------------------------------------------------------------

def _mutate_swap(bo: BuildOrder, rng: random.Random) -> BuildOrder:
    """Swap two adjacent items in a random queue."""
    new = copy.deepcopy(bo)
    queues = _all_queues(new)
    if not queues:
        return new
    q = rng.choice(queues)
    if len(q) < 2:
        return new
    i = rng.randint(0, len(q) - 2)
    q[i], q[i + 1] = q[i + 1], q[i]
    return new


def _mutate_replace(bo: BuildOrder, rng: random.Random) -> BuildOrder:
    """Replace one item in a random queue with a valid alternative."""
    new = copy.deepcopy(bo)
    queues = _all_queues_with_pools(new)
    if not queues:
        return new
    q, pool = rng.choice(queues)
    if not q or not pool:
        return new
    i = rng.randint(0, len(q) - 1)
    old_type = q[i].action_type
    new_key = rng.choice(pool)
    q[i] = BuildAction(unit_key=new_key, action_type=old_type)
    return new


def _mutate_insert(bo: BuildOrder, rng: random.Random) -> BuildOrder:
    """Insert a new item at a random position in a random queue."""
    new = copy.deepcopy(bo)
    queues = _all_queues_with_pools(new)
    if not queues:
        return new
    q, pool = rng.choice(queues)
    if not pool:
        return new
    new_key = rng.choice(pool)
    action_type = (BuildActionType.PRODUCE_UNIT
                   if any(q is new.factory_queues.get(fid)
                          for fid in new.factory_queues)
                   else BuildActionType.BUILD_STRUCTURE)
    pos = rng.randint(0, len(q))
    q.insert(pos, BuildAction(unit_key=new_key, action_type=action_type))
    return new


def _mutate_remove(bo: BuildOrder, rng: random.Random) -> BuildOrder:
    """Remove one item from a random queue (if queue has > 3 items)."""
    new = copy.deepcopy(bo)
    queues = _all_queues(new)
    if not queues:
        return new
    q = rng.choice(queues)
    if len(q) <= 3:
        return new
    i = rng.randint(0, len(q) - 1)
    q.pop(i)
    return new


def _mutate_shuffle_segment(bo: BuildOrder, rng: random.Random) -> BuildOrder:
    """Shuffle a small segment (2-4 items) within a random queue."""
    new = copy.deepcopy(bo)
    queues = _all_queues(new)
    if not queues:
        return new
    q = rng.choice(queues)
    if len(q) < 3:
        return new
    seg_len = rng.randint(2, min(4, len(q)))
    start = rng.randint(0, len(q) - seg_len)
    segment = q[start:start + seg_len]
    rng.shuffle(segment)
    q[start:start + seg_len] = segment
    return new


MUTATIONS = [_mutate_swap, _mutate_replace, _mutate_insert,
             _mutate_remove, _mutate_shuffle_segment]


# ---------------------------------------------------------------------------
# Crossover operators
# ---------------------------------------------------------------------------

def _crossover_one_point(parent1: BuildOrder, parent2: BuildOrder,
                         rng: random.Random) -> Tuple[BuildOrder, BuildOrder]:
    """Single-point crossover on each queue independently."""
    c1 = copy.deepcopy(parent1)
    c2 = copy.deepcopy(parent2)

    # Crossover commander queues
    _crossover_queue(c1.commander_queue, c2.commander_queue, rng)

    # Crossover factory queues (factory_0 from each)
    for fid in set(list(c1.factory_queues.keys()) + list(c2.factory_queues.keys())):
        q1 = c1.factory_queues.get(fid, [])
        q2 = c2.factory_queues.get(fid, [])
        if q1 and q2:
            _crossover_queue(q1, q2, rng)
            c1.factory_queues[fid] = q1
            c2.factory_queues[fid] = q2

    # Crossover constructor queues
    for cid in set(list(c1.constructor_queues.keys()) + list(c2.constructor_queues.keys())):
        q1 = c1.constructor_queues.get(cid, [])
        q2 = c2.constructor_queues.get(cid, [])
        if q1 and q2:
            _crossover_queue(q1, q2, rng)
            c1.constructor_queues[cid] = q1
            c2.constructor_queues[cid] = q2

    return c1, c2


def _crossover_queue(q1: List[BuildAction], q2: List[BuildAction],
                     rng: random.Random):
    """In-place single-point crossover on two queues."""
    if len(q1) < 2 or len(q2) < 2:
        return
    point = rng.randint(1, min(len(q1), len(q2)) - 1)
    tail1, tail2 = q1[point:], q2[point:]
    q1[point:] = tail2
    q2[point:] = tail1


def _crossover_uniform(parent1: BuildOrder, parent2: BuildOrder,
                       rng: random.Random) -> Tuple[BuildOrder, BuildOrder]:
    """Uniform crossover: for each queue position, randomly pick from either parent."""
    c1 = copy.deepcopy(parent1)
    c2 = copy.deepcopy(parent2)

    _uniform_queue(c1.commander_queue, c2.commander_queue, rng)

    for fid in set(list(c1.factory_queues.keys()) + list(c2.factory_queues.keys())):
        q1 = c1.factory_queues.get(fid, [])
        q2 = c2.factory_queues.get(fid, [])
        if q1 and q2:
            _uniform_queue(q1, q2, rng)
            c1.factory_queues[fid] = q1
            c2.factory_queues[fid] = q2

    for cid in set(list(c1.constructor_queues.keys()) + list(c2.constructor_queues.keys())):
        q1 = c1.constructor_queues.get(cid, [])
        q2 = c2.constructor_queues.get(cid, [])
        if q1 and q2:
            _uniform_queue(q1, q2, rng)
            c1.constructor_queues[cid] = q1
            c2.constructor_queues[cid] = q2

    return c1, c2


def _uniform_queue(q1: List[BuildAction], q2: List[BuildAction],
                   rng: random.Random):
    """In-place uniform crossover on two queues."""
    min_len = min(len(q1), len(q2))
    for i in range(min_len):
        if rng.random() < 0.5:
            q1[i], q2[i] = q2[i], q1[i]


# ---------------------------------------------------------------------------
# Genetic Algorithm
# ---------------------------------------------------------------------------

# An individual: (score, build_order)
Individual = Tuple[float, BuildOrder]


class Optimizer:
    """
    Genetic Algorithm build order optimizer.

    Population-based search with:
    - Tournament selection
    - One-point and uniform crossover
    - Adaptive mutation rate (decays, spikes on stagnation)
    - Elitism (top N survive unchanged)
    - Stagnation detection with catastrophic restart
    - Heuristic-seeded initial population
    """

    def __init__(self, goal: OptGoal, map_config: MapConfig,
                 duration: int = 600, seed: int = 42,
                 # GA parameters
                 population_size: int = 60,
                 max_generations: int = 200,
                 elitism_count: int = 4,
                 tournament_size: int = 5,
                 mutation_rate: float = 0.4,
                 mutation_decay: float = 0.995,
                 crossover_rate: float = 0.7,
                 stagnation_limit: int = 25,
                 catastrophe_limit: int = 50,
                 hyper_mutation_rate: float = 0.9,
                 verbose: bool = True,
                 # legacy alias
                 max_iterations: int = 0):
        self.goal = goal
        self.map_config = map_config
        self.duration = duration
        self.rng = random.Random(seed)
        self.verbose = verbose

        self.population_size = population_size
        self.max_generations = max_generations if max_iterations == 0 else max_iterations
        self.elitism_count = min(elitism_count, population_size // 2)
        self.tournament_size = min(tournament_size, population_size)
        self.base_mutation_rate = mutation_rate
        self.mutation_decay = mutation_decay
        self.crossover_rate = crossover_rate
        self.stagnation_limit = stagnation_limit
        self.catastrophe_limit = catastrophe_limit
        self.hyper_mutation_rate = hyper_mutation_rate

        self.history: List[float] = []

    # ------------------------------------------------------------------
    # Evaluation
    # ------------------------------------------------------------------

    def _evaluate(self, bo: BuildOrder) -> float:
        try:
            engine = SimulationEngine(bo, self.duration)
            result = engine.run()
            return self.goal.score(result)
        except Exception:
            return self.goal.worst_score

    # ------------------------------------------------------------------
    # Population initialization
    # ------------------------------------------------------------------

    def _init_population(self, initial_bo: Optional[BuildOrder]) -> List[Individual]:
        pop: List[Individual] = []

        # Heuristic seeds (1/3 of population)
        n_heuristic = self.population_size // 3
        for _ in range(n_heuristic):
            bo = greedy_seed(self.map_config, self.duration)
            # Light mutation for diversity
            for _ in range(self.rng.randint(0, 3)):
                mut = self.rng.choice(MUTATIONS)
                bo = mut(bo, self.rng)
            bo = enforce_constraints(bo, self.map_config)
            score = self._evaluate(bo)
            pop.append((score, bo))

        # If user provided an initial BO, seed several variants
        if initial_bo is not None:
            bo = copy.deepcopy(initial_bo)
            bo = enforce_constraints(bo, self.map_config)
            score = self._evaluate(bo)
            pop.append((score, bo))
            # Mutated variants of the provided BO
            for _ in range(min(5, self.population_size // 6)):
                variant = copy.deepcopy(initial_bo)
                for _ in range(self.rng.randint(1, 4)):
                    mut = self.rng.choice(MUTATIONS)
                    variant = mut(variant, self.rng)
                variant = enforce_constraints(variant, self.map_config)
                score = self._evaluate(variant)
                pop.append((score, variant))

        # Fill remaining with random seeds
        while len(pop) < self.population_size:
            bo = random_seed(self.map_config, self.rng)
            bo = enforce_constraints(bo, self.map_config)
            score = self._evaluate(bo)
            pop.append((score, bo))

        return pop[:self.population_size]

    # ------------------------------------------------------------------
    # Selection
    # ------------------------------------------------------------------

    def _tournament_select(self, pop: List[Individual]) -> BuildOrder:
        """Pick tournament_size individuals, return the best one's BO."""
        candidates = self.rng.sample(pop, min(self.tournament_size, len(pop)))
        if self.goal.higher_is_better:
            best = max(candidates, key=lambda x: x[0])
        else:
            best = min(candidates, key=lambda x: x[0])
        return copy.deepcopy(best[1])

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------

    def optimize(self, initial_bo: Optional[BuildOrder] = None) -> BuildOrder:
        """Run the genetic algorithm. Returns the best build order found."""
        t0 = time.time()

        if self.verbose:
            print(f"Initializing population ({self.population_size})...")

        pop = self._init_population(initial_bo)
        best_score, best_bo = self._best_of(pop)
        self.history.append(best_score)

        if self.verbose:
            print(f"  Initial best: {best_score:.2f}")
            print(f"\nRunning GA ({self.max_generations} generations, "
                  f"pop={self.population_size}, "
                  f"elite={self.elitism_count}, "
                  f"tourn={self.tournament_size})...\n")

        mutation_rate = self.base_mutation_rate
        stagnation = 0
        catastrophe_count = 0

        for gen in range(self.max_generations):
            # Sort population
            if self.goal.higher_is_better:
                pop.sort(key=lambda x: x[0], reverse=True)
            else:
                pop.sort(key=lambda x: x[0])

            gen_best_score = pop[0][0]

            # Track improvement
            if self.goal.is_better(gen_best_score, best_score):
                best_score = gen_best_score
                best_bo = copy.deepcopy(pop[0][1])
                stagnation = 0
            else:
                stagnation += 1

            self.history.append(best_score)

            # Progress reporting
            if self.verbose and (gen + 1) % 10 == 0:
                elapsed = time.time() - t0
                print(f"  Gen {gen+1:>4} | best: {best_score:>8.2f} | "
                      f"gen_best: {gen_best_score:>8.2f} | "
                      f"mut: {mutation_rate:.3f} | "
                      f"stag: {stagnation:>2} | "
                      f"{elapsed:.1f}s")

            # --- Stagnation handling ---
            if stagnation >= self.catastrophe_limit:
                # Catastrophic restart: keep only the global best,
                # regenerate everything else
                catastrophe_count += 1
                if self.verbose:
                    print(f"  *** Catastrophe #{catastrophe_count} at gen {gen+1} "
                          f"(stagnation={stagnation}) ***")
                pop = self._init_population(best_bo)
                mutation_rate = self.base_mutation_rate
                stagnation = 0
                continue

            elif stagnation >= self.stagnation_limit:
                # Hyper-mutation phase
                mutation_rate = self.hyper_mutation_rate
            else:
                # Normal decay
                mutation_rate = max(0.05, mutation_rate * self.mutation_decay)

            # --- Build next generation ---
            new_pop: List[Individual] = []

            # Elitism: carry over top N unchanged
            for i in range(self.elitism_count):
                new_pop.append(pop[i])

            # Fill rest via selection + crossover + mutation
            while len(new_pop) < self.population_size:
                parent1 = self._tournament_select(pop)
                parent2 = self._tournament_select(pop)

                # Crossover
                if self.rng.random() < self.crossover_rate:
                    if self.rng.random() < 0.7:
                        child1, child2 = _crossover_one_point(parent1, parent2, self.rng)
                    else:
                        child1, child2 = _crossover_uniform(parent1, parent2, self.rng)
                else:
                    child1, child2 = parent1, parent2

                # Mutation
                for child in (child1, child2):
                    if len(new_pop) >= self.population_size:
                        break

                    if self.rng.random() < mutation_rate:
                        # Apply 1-3 mutations depending on rate
                        n_muts = 1 if mutation_rate < 0.6 else self.rng.randint(1, 3)
                        for _ in range(n_muts):
                            mut = self.rng.choice(MUTATIONS)
                            child = mut(child, self.rng)

                    child = enforce_constraints(child, self.map_config)
                    score = self._evaluate(child)
                    new_pop.append((score, child))

            pop = new_pop[:self.population_size]

        # Final sort and return
        elapsed = time.time() - t0
        if self.verbose:
            print(f"\nDone in {elapsed:.1f}s. Best score: {best_score:.2f}")
            if catastrophe_count:
                print(f"  Catastrophic restarts: {catastrophe_count}")

        best_bo.name = f"Optimized ({self.goal.name})"
        return best_bo

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _best_of(self, pop: List[Individual]) -> Tuple[float, BuildOrder]:
        if self.goal.higher_is_better:
            best = max(pop, key=lambda x: x[0])
        else:
            best = min(pop, key=lambda x: x[0])
        return best[0], copy.deepcopy(best[1])


# ---------------------------------------------------------------------------
# Strategy Optimizer
# ---------------------------------------------------------------------------

class StrategyOptimizer:
    """
    Genetic Algorithm optimizer for StrategyConfig parameters.

    Instead of evolving build queues, evolves strategy configs and lets the
    dynamic decision system generate the build orders.

    Genome: StrategyConfig flattened to a vector of enum indices + integers.
    """

    def __init__(self, goal: OptGoal, map_config: MapConfig,
                 duration: int = 600, seed: int = 42,
                 population_size: int = 40,
                 max_generations: int = 80,
                 verbose: bool = True):
        self.goal = goal
        self.map_config = map_config
        self.duration = duration
        self.rng = random.Random(seed)
        self.verbose = verbose
        self.population_size = population_size
        self.max_generations = max_generations
        self.history: List[float] = []

    def _config_to_genome(self, config) -> List[int]:
        """Flatten StrategyConfig to integer vector."""
        from bar_sim.strategy import (
            EnergyStrategy, UnitComposition, Posture, T2Timing,
            Role, AttackStrategy, EmergencyMode,
        )
        return [
            config.opening_mex_count,
            list(EnergyStrategy).index(config.energy_strategy),
            list(UnitComposition).index(config.unit_composition),
            list(Posture).index(config.posture),
            list(T2Timing).index(config.t2_timing),
            config.econ_army_balance,
            list(Role).index(config.role),
            list(AttackStrategy).index(config.attack_strategy),
        ]

    def _genome_to_config(self, genome: List[int]):
        """Reconstruct StrategyConfig from integer vector."""
        from bar_sim.strategy import (
            StrategyConfig, EnergyStrategy, UnitComposition, Posture, T2Timing,
            Role, AttackStrategy, EmergencyMode,
        )
        enums = [
            list(EnergyStrategy),
            list(UnitComposition),
            list(Posture),
            list(T2Timing),
        ]
        return StrategyConfig(
            opening_mex_count=max(1, min(4, genome[0])),
            energy_strategy=list(EnergyStrategy)[genome[1] % len(EnergyStrategy)],
            unit_composition=list(UnitComposition)[genome[2] % len(UnitComposition)],
            posture=list(Posture)[genome[3] % len(Posture)],
            t2_timing=list(T2Timing)[genome[4] % len(T2Timing)],
            econ_army_balance=max(0, min(100, genome[5])),
            role=list(Role)[genome[6] % len(Role)],
            attack_strategy=list(AttackStrategy)[genome[7] % len(AttackStrategy)],
        )

    def _evaluate(self, config) -> float:
        try:
            bo = BuildOrder(
                name="StratOpt",
                map_config=copy.deepcopy(self.map_config),
                strategy_config=config,
            )
            engine = SimulationEngine(bo, self.duration)
            result = engine.run()
            return self.goal.score(result)
        except Exception:
            return self.goal.worst_score

    def _mutate_genome(self, genome: List[int]) -> List[int]:
        g = list(genome)
        idx = self.rng.randint(0, len(g) - 1)
        if idx == 0:
            g[idx] = self.rng.randint(1, 4)
        elif idx == 5:
            g[idx] = max(0, min(100, g[idx] + self.rng.randint(-15, 15)))
        else:
            g[idx] = self.rng.randint(0, 10)  # will be clamped by modulo
        return g

    def _crossover_genomes(self, g1: List[int], g2: List[int]) -> List[int]:
        child = []
        for a, b in zip(g1, g2):
            child.append(a if self.rng.random() < 0.5 else b)
        return child

    def optimize(self) -> "StrategyConfig":
        """Run the strategy GA. Returns the best StrategyConfig found."""
        from bar_sim.strategy import StrategyConfig

        t0 = time.time()

        # Init population
        pop = []
        for _ in range(self.population_size):
            genome = [
                self.rng.randint(1, 4),
                self.rng.randint(0, 3),
                self.rng.randint(0, 2),
                self.rng.randint(0, 2),
                self.rng.randint(0, 2),
                self.rng.randint(10, 90),
                self.rng.randint(0, 3),
                self.rng.randint(0, 4),
            ]
            config = self._genome_to_config(genome)
            score = self._evaluate(config)
            pop.append((score, genome))

        if self.goal.higher_is_better:
            pop.sort(key=lambda x: x[0], reverse=True)
        else:
            pop.sort(key=lambda x: x[0])
        best_score, best_genome = pop[0][0], list(pop[0][1])

        if self.verbose:
            print(f"  Initial best: {best_score:.2f}")

        for gen in range(self.max_generations):
            new_pop = [pop[0], pop[1]]  # elitism

            while len(new_pop) < self.population_size:
                # Tournament select
                t = self.rng.sample(pop, min(5, len(pop)))
                if self.goal.higher_is_better:
                    p1 = max(t, key=lambda x: x[0])[1]
                else:
                    p1 = min(t, key=lambda x: x[0])[1]
                t = self.rng.sample(pop, min(5, len(pop)))
                if self.goal.higher_is_better:
                    p2 = max(t, key=lambda x: x[0])[1]
                else:
                    p2 = min(t, key=lambda x: x[0])[1]

                child = self._crossover_genomes(p1, p2)
                if self.rng.random() < 0.5:
                    child = self._mutate_genome(child)

                config = self._genome_to_config(child)
                score = self._evaluate(config)
                new_pop.append((score, child))

            if self.goal.higher_is_better:
                new_pop.sort(key=lambda x: x[0], reverse=True)
            else:
                new_pop.sort(key=lambda x: x[0])
            pop = new_pop[:self.population_size]

            if self.goal.is_better(pop[0][0], best_score):
                best_score = pop[0][0]
                best_genome = list(pop[0][1])

            self.history.append(best_score)

            if self.verbose and (gen + 1) % 10 == 0:
                elapsed = time.time() - t0
                print(f"  Gen {gen+1:>4} | best: {best_score:>8.2f} | {elapsed:.1f}s")

        best_config = self._genome_to_config(best_genome)
        if self.verbose:
            elapsed = time.time() - t0
            print(f"\nDone in {elapsed:.1f}s. Best: {best_score:.2f}")
            print(f"  Config: {best_config.summary()}")
        return best_config


# Strategy-mode goals for make_goal
def make_strategy_goal(goal_name: str, target_time: int = 300) -> OptGoal:
    """Create an optimization goal suitable for StrategyOptimizer."""
    goals = {
        "best_composition": OptGoal(
            name="best_composition",
            description=f"Maximize army value * role diversity at {target_time}s",
            score_fn=lambda r: _composition_score(r, target_time),
        ),
        "fastest_goal": OptGoal(
            name="fastest_goal",
            description="Minimize tick to complete first goal",
            score_fn=lambda r: (r.goal_completions[0][0]
                                if r.goal_completions else 9999),
            higher_is_better=False,
        ),
        "max_eco_strat": OptGoal(
            name="max_eco_strat",
            description=f"Maximize metal income at {target_time}s via strategy",
            score_fn=lambda r: (_snap_at(r, target_time).metal_income
                                if _snap_at(r, target_time) else 0),
        ),
    }
    if goal_name not in goals:
        raise ValueError(f"Unknown strategy goal: {goal_name}. "
                         f"Choose from: {list(goals.keys())}")
    return goals[goal_name]


def _composition_score(result: SimResult, target_time: int) -> float:
    """Score: army_value * (1 + diversity_bonus).
    Diversity = number of distinct roles present / max roles."""
    snap = _snap_at(result, target_time)
    if not snap:
        return 0
    army_value = snap.army_value_metal
    roles = snap.army_by_role
    distinct_roles = len([v for v in roles.values() if v > 0])
    max_roles = max(distinct_roles, 1)
    diversity_bonus = min(distinct_roles / 6.0, 1.0)  # up to 6 roles = max bonus
    return army_value * (1.0 + diversity_bonus * 0.5)
