"""
BAR Build Order Simulator - Simulation Engine
===============================================
Tick-based economy simulation (1 tick = 1 game second).
"""

import math
import random
from copy import deepcopy
from typing import Dict, Optional

from bar_sim.econ import UNITS as ECON_UNITS
from bar_sim.models import (
    BuildOrder, BuildAction, BuildActionType,
    Builder, BuildTask, SimState, SimResult,
    Milestone, StallEvent, Snapshot, MapConfig,
)

# Unit keys that are factories
FACTORY_KEYS = {"bot_lab", "vehicle_plant", "aircraft_plant",
                "adv_bot_lab", "adv_vehicle_plant", "adv_aircraft_plant"}

# Unit keys that are constructors (mobile builders)
CONSTRUCTOR_KEYS = {"con_bot", "con_vehicle", "adv_con_bot", "adv_con_vehicle"}

# Default walk time (seconds) for mobile builders between structures
WALK_TIME = 3


class SimulationEngine:
    def __init__(self, build_order: BuildOrder, duration: int = 600, seed: int = 42):
        self.bo = build_order
        # Auto-resolve map_name to MapConfig if set
        if build_order.map_name and build_order.map_config == MapConfig():
            try:
                from bar_sim.map_data import get_map_data, map_data_to_map_config
                md = get_map_data(build_order.map_name)
                if md:
                    build_order.map_config = map_data_to_map_config(md)
            except Exception:
                pass
        self.duration = duration
        self.rng = random.Random(seed)
        self.state = SimState()
        self.result = SimResult(build_order_name=build_order.name, total_ticks=duration)
        self._next_task_id_counter = 0
        self._factory_counter = 0
        self._con_counter = 0
        self._nano_counter = 0
        self._current_stall: Optional[StallEvent] = None
        self._army_value = 0.0

        # Strategy mode
        self._strategy_mode = build_order.strategy_config is not None
        self._strategy_config = build_order.strategy_config
        self._mex_built = 0
        self._factory_type_map: Dict[str, str] = {}  # builder_id -> factory unit_key

        # Initialize army + goal tracking eagerly (so CLI can add goals before run())
        if self._strategy_mode:
            from bar_sim.production import ArmyComposition
            from bar_sim.goals import GoalQueue
            self._army = ArmyComposition()
            self._goal_queue = GoalQueue()
        else:
            self._army = None
            self._goal_queue = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def run(self) -> SimResult:
        self._initialize()
        for tick in range(1, self.duration + 1):
            self.state.tick = tick
            self._step_tick()
            if tick % 30 == 0:
                self._record_snapshot()
        self._finalize()
        return self.result

    # ------------------------------------------------------------------
    # Initialization
    # ------------------------------------------------------------------

    def _initialize(self):
        s = self.state
        s.metal_stored = 500.0
        s.energy_stored = 1000.0
        s.metal_storage_cap = 500.0
        s.energy_storage_cap = 1000.0

        # Commander BP from unit data (fixes old hardcode of 200 -> actual 300)
        cmd_unit = ECON_UNITS.get("commander")
        cmd_bp = cmd_unit.build_power if cmd_unit else 300

        # Strategy mode: generate opening from config
        cmd_queue = list(self.bo.commander_queue)
        if self._strategy_mode and not cmd_queue:
            from bar_sim.strategy import generate_opening
            cmd_queue = generate_opening(self._strategy_config)

        # Commander builder
        cmd = Builder(
            builder_id="commander",
            build_power=cmd_bp,
            builder_type="commander",
            is_active=True,
            activated_at=0,
            queue=cmd_queue,
        )
        s.builders["commander"] = cmd

        # Take initial snapshot at tick 0
        self._record_snapshot()

    # ------------------------------------------------------------------
    # Per-tick simulation
    # ------------------------------------------------------------------

    def _step_tick(self):
        self._update_wind()
        self._assign_idle_builders()
        if self._strategy_mode:
            self._update_emergency()
            self._update_econ_state()
        self._calculate_income()
        self._calculate_expenditure()
        self._calculate_stall()
        self._apply_construction()
        self._update_resources()
        self._update_converters()
        self._process_completions()
        self._track_stall_events()
        self._track_peaks()

    # ------------------------------------------------------------------
    # Phase 1: Wind
    # ------------------------------------------------------------------

    def _update_wind(self):
        mc = self.bo.map_config
        base = mc.avg_wind + mc.wind_variance * math.sin(self.state.tick * 0.05)
        noise = self.rng.uniform(-mc.wind_variance * 0.3, mc.wind_variance * 0.3)
        self.state.current_wind = max(0, min(25, base + noise))

    # ------------------------------------------------------------------
    # Phase 2: Assign idle builders to next task
    # ------------------------------------------------------------------

    def _assign_idle_builders(self):
        for bid, builder in self.state.builders.items():
            if not builder.is_active or not builder.is_idle:
                continue
            if builder.builder_type == "nano":
                self._assign_nano(builder)
                continue

            # Strategy mode: once queue exhausted, switch to dynamic decisions
            if builder.queue_index >= len(builder.queue):
                if self._strategy_mode:
                    action = self._strategy_assign_builder(bid, builder)
                    if action is None:
                        continue
                else:
                    continue
            else:
                action = builder.queue[builder.queue_index]
                builder.queue_index += 1

            unit_key = action.unit_key
            unit = ECON_UNITS.get(unit_key)
            if unit is None:
                continue

            walk = WALK_TIME if builder.builder_type in ("commander", "constructor") else 0

            task = BuildTask(
                task_id=self._next_task_id(),
                unit_key=unit_key,
                action_type=action.action_type,
                total_build_work=float(unit.build_time),
                metal_cost_total=float(unit.metal_cost),
                energy_cost_total=float(unit.energy_cost),
                walk_delay=walk,
                assigned_builders=[bid],
                started_at=self.state.tick,
            )
            builder.current_task = task
            builder.is_idle = False
            self.state.active_tasks.append(task)

    def _assign_nano(self, nano: Builder):
        target_id = nano.assist_target
        if not target_id:
            # Find first active factory
            for bid, b in self.state.builders.items():
                if b.builder_type == "factory" and b.is_active:
                    nano.assist_target = bid
                    target_id = bid
                    break
        if not target_id:
            return

        target = self.state.builders.get(target_id)
        if target and target.current_task:
            if nano.builder_id not in target.current_task.assigned_builders:
                target.current_task.assigned_builders.append(nano.builder_id)
            nano.current_task = target.current_task
            nano.is_idle = False
        else:
            nano.is_idle = True
            nano.current_task = None

    # ------------------------------------------------------------------
    # Phase 3: Calculate income
    # ------------------------------------------------------------------

    def _calculate_income(self):
        s = self.state
        mc = self.bo.map_config
        metal = 0.0
        energy = 0.0

        # Commander energy (from unit data; fixes old hardcode of 25 -> actual 30)
        cmd_unit = ECON_UNITS.get("commander")
        energy += cmd_unit.energy_production if cmd_unit else 30.0

        # Buildings
        mex_count = s.buildings.get("mex", 0)
        metal += mex_count * mc.mex_value

        moho_count = s.buildings.get("moho", 0)
        metal += moho_count * mc.mex_value * 4

        wind_count = s.buildings.get("wind", 0)
        energy += wind_count * s.current_wind

        for key in ("solar", "adv_solar", "geo_t1", "fusion"):
            count = s.buildings.get(key, 0)
            if count > 0:
                unit = ECON_UNITS.get(key)
                if unit:
                    energy += count * unit.energy_production

        for key in ("tidal",):
            count = s.buildings.get(key, 0)
            if count > 0:
                energy += count * mc.tidal_value

        # Energy upkeep from buildings
        for key, count in s.buildings.items():
            unit = ECON_UNITS.get(key)
            if unit and unit.energy_upkeep > 0 and count > 0:
                energy -= count * unit.energy_upkeep

        # Constructor energy production
        for key, count in s.units.items():
            unit = ECON_UNITS.get(key)
            if unit and unit.energy_production > 0 and count > 0:
                energy += count * unit.energy_production

        s.metal_income = metal
        s.energy_income = energy

    # ------------------------------------------------------------------
    # Phase 4: Calculate expenditure from active construction
    # ------------------------------------------------------------------

    def _calculate_expenditure(self):
        total_m = 0.0
        total_e = 0.0

        for task in self.state.active_tasks:
            if task.walk_delay > 0:
                task._pending_bp = 0
                task._pending_metal_drain = 0
                task._pending_energy_drain = 0
                continue

            unit = ECON_UNITS.get(task.unit_key)
            if not unit or unit.build_time == 0:
                continue

            bp = 0
            for bid in task.assigned_builders:
                b = self.state.builders.get(bid)
                if b and b.is_active:
                    bp += b.build_power
            if bp == 0:
                continue

            m_per_s = unit.metal_cost * bp / unit.build_time
            e_per_s = unit.energy_cost * bp / unit.build_time

            task._pending_bp = bp
            task._pending_metal_drain = m_per_s
            task._pending_energy_drain = e_per_s

            total_m += m_per_s
            total_e += e_per_s

        self.state.metal_expenditure = total_m
        self.state.energy_expenditure = total_e

    # ------------------------------------------------------------------
    # Phase 5: Stall factor
    # ------------------------------------------------------------------

    def _calculate_stall(self):
        s = self.state

        if s.metal_expenditure > 0:
            avail = s.metal_income + s.metal_stored
            s.metal_stall_factor = min(1.0, avail / s.metal_expenditure)
        else:
            s.metal_stall_factor = 1.0

        if s.energy_expenditure > 0:
            avail = s.energy_income + s.energy_stored
            s.energy_stall_factor = min(1.0, avail / s.energy_expenditure)
        else:
            s.energy_stall_factor = 1.0

        s.effective_stall_factor = min(s.metal_stall_factor, s.energy_stall_factor)

    # ------------------------------------------------------------------
    # Phase 6: Apply construction progress
    # ------------------------------------------------------------------

    def _apply_construction(self):
        stall = self.state.effective_stall_factor

        for task in self.state.active_tasks:
            if task.walk_delay > 0:
                task.walk_delay -= 1
                continue

            eff_bp = task._pending_bp * stall
            m_drain = task._pending_metal_drain * stall
            e_drain = task._pending_energy_drain * stall

            task.work_done += eff_bp
            task.metal_spent += m_drain
            task.energy_spent += e_drain

            self.state.metal_stored -= m_drain
            self.state.energy_stored -= e_drain

    # ------------------------------------------------------------------
    # Phase 7: Update resources (income)
    # ------------------------------------------------------------------

    def _update_resources(self):
        s = self.state
        s.metal_stored += s.metal_income
        s.energy_stored += s.energy_income
        s.metal_stored = max(0, min(s.metal_stored, s.metal_storage_cap))
        s.energy_stored = max(0, min(s.energy_stored, s.energy_storage_cap))

    # ------------------------------------------------------------------
    # Phase 8: Converters
    # ------------------------------------------------------------------

    def _update_converters(self):
        s = self.state
        t1 = s.buildings.get("converter_t1", 0)
        t2 = s.buildings.get("converter_t2", 0)

        if t1 == 0 and t2 == 0:
            s.active_converters_t1 = 0
            s.active_converters_t2 = 0
            return

        ratio = s.energy_stored / s.energy_storage_cap if s.energy_storage_cap > 0 else 0
        if ratio < 0.8:
            s.active_converters_t1 = 0
            s.active_converters_t2 = 0
            return

        available = s.energy_stored - s.energy_storage_cap * 0.5
        t2_active = min(t2, int(available / 600)) if available > 0 else 0
        available -= t2_active * 600
        t1_active = min(t1, int(available / 70)) if available > 0 else 0

        s.active_converters_t1 = t1_active
        s.active_converters_t2 = t2_active

        m_produced = t1_active * 1.0 + t2_active * 10.3
        e_consumed = t1_active * 70 + t2_active * 600

        s.metal_stored += m_produced
        s.energy_stored -= e_consumed
        s.metal_income += m_produced

    # ------------------------------------------------------------------
    # Phase 9: Process completed tasks
    # ------------------------------------------------------------------

    def _process_completions(self):
        completed = [t for t in self.state.active_tasks if t.is_complete]
        for task in completed:
            task.completed_at = self.state.tick
            self.state.active_tasks.remove(task)
            self.state.completed_tasks.append(task)
            self._on_complete(task)

    def _on_complete(self, task: BuildTask):
        s = self.state
        key = task.unit_key

        # Find the builder that owned this task
        owner_id = task.assigned_builders[0] if task.assigned_builders else "unknown"

        self.result.completion_log.append((self.state.tick, key, owner_id))

        if task.action_type == BuildActionType.BUILD_STRUCTURE:
            s.buildings[key] = s.buildings.get(key, 0) + 1
            self._on_building_complete(key, task)
        elif task.action_type == BuildActionType.PRODUCE_UNIT:
            s.units[key] = s.units.get(key, 0) + 1
            self._on_unit_produced(key, task)

        # Free builders assigned to this task
        for bid in task.assigned_builders:
            b = s.builders.get(bid)
            if b and b.current_task is task:
                b.current_task = None
                b.is_idle = True

    def _on_building_complete(self, key: str, task: BuildTask):
        s = self.state
        unit = ECON_UNITS.get(key)

        # Factory -> activate as builder
        if key in FACTORY_KEYS:
            fid = f"factory_{self._factory_counter}"
            self._factory_counter += 1
            bp = unit.build_power if unit else 150

            if self._strategy_mode:
                # Strategy mode: empty queue (dynamic production decisions)
                fqueue = []
                self._factory_type_map[fid] = key
            else:
                fqueue = self.bo.factory_queues.get(fid,
                         self.bo.factory_queues.get("factory_0", []))

            new_builder = Builder(
                builder_id=fid,
                build_power=bp,
                builder_type="factory",
                is_active=True,
                activated_at=self.state.tick,
                queue=list(fqueue),
            )
            s.builders[fid] = new_builder
            self._milestone("first_factory", f"{unit.name if unit else key} online")

        # Nano -> activate as assisting builder
        if key == "nano":
            nid = f"nano_{self._nano_counter}"
            self._nano_counter += 1
            new_builder = Builder(
                builder_id=nid,
                build_power=200,
                builder_type="nano",
                is_active=True,
                activated_at=self.state.tick,
            )
            s.builders[nid] = new_builder
            self._milestone("first_nano", "Nano turret online")

        # Mex tracking (for strategy mode remaining_mex calc)
        if key == "mex":
            self._mex_built += 1

        # Storage
        if key == "metal_storage":
            s.metal_storage_cap += 3000
        elif key == "energy_storage":
            s.energy_storage_cap += 6000

    def _on_unit_produced(self, key: str, task: BuildTask):
        s = self.state
        unit = ECON_UNITS.get(key)

        # Constructor -> activate as builder
        if key in CONSTRUCTOR_KEYS:
            cid = f"con_{self._con_counter + 1}"
            self._con_counter += 1
            bp = unit.build_power if unit else 100

            if self._strategy_mode:
                # Strategy mode: empty queue (dynamic econ decisions)
                cqueue = []
            else:
                cqueue = self.bo.constructor_queues.get(cid,
                         self.bo.constructor_queues.get("con_1", []))

            new_builder = Builder(
                builder_id=cid,
                build_power=bp,
                builder_type="constructor",
                is_active=True,
                activated_at=self.state.tick,
                queue=list(cqueue),
            )
            s.builders[cid] = new_builder

            # Constructor storage bonus (+50 each)
            s.metal_storage_cap += 50
            s.energy_storage_cap += 50

            self._milestone("first_constructor", f"{unit.name if unit else key} produced")

        # Track army value for non-builder units
        if key not in CONSTRUCTOR_KEYS:
            if unit:
                self._army_value += unit.metal_cost

        # Strategy mode: track army composition + goal progress
        if self._strategy_mode and self._army:
            metal_cost = unit.metal_cost if unit else 0
            self._army.record_unit(key, metal_cost)
            s.army_by_role = dict(self._army.counts_by_role)

            if self._goal_queue:
                total_bp = sum(b.build_power for b in s.builders.values() if b.is_active)
                self._goal_queue.tick(s, self._army.counts_by_unit, total_bp)

        self._milestone_for_unit(key)

    def _milestone_for_unit(self, key: str):
        if key == "tick":
            self._milestone("first_scout", "First scout produced")

    # ------------------------------------------------------------------
    # Milestone tracking
    # ------------------------------------------------------------------

    def _milestone(self, event: str, desc: str):
        if any(m.event == event for m in self.result.milestones):
            return
        self.result.milestones.append(Milestone(
            tick=self.state.tick,
            event=event,
            description=desc,
            metal_income=self.state.metal_income,
            energy_income=self.state.energy_income,
        ))
        # Set convenience fields
        if event == "first_factory":
            self.result.time_to_first_factory = self.state.tick
        elif event == "first_constructor":
            self.result.time_to_first_constructor = self.state.tick
        elif event == "first_nano":
            self.result.time_to_first_nano = self.state.tick
        elif event == "first_t2_lab":
            self.result.time_to_t2_lab = self.state.tick

    # ------------------------------------------------------------------
    # Stall event tracking
    # ------------------------------------------------------------------

    def _track_stall_events(self):
        s = self.state
        is_stalling = s.effective_stall_factor < 0.95

        if is_stalling:
            resource = "metal" if s.metal_stall_factor < s.energy_stall_factor else "energy"
            if resource == "metal":
                self.result.total_metal_stall_seconds += 1
            else:
                self.result.total_energy_stall_seconds += 1

            if self._current_stall is None:
                self._current_stall = StallEvent(
                    start_tick=s.tick, resource=resource,
                    severity=1.0 - s.effective_stall_factor,
                )
            else:
                self._current_stall.end_tick = s.tick
                self._current_stall.severity = max(
                    self._current_stall.severity, 1.0 - s.effective_stall_factor
                )
        else:
            if self._current_stall is not None:
                self._current_stall.end_tick = s.tick - 1
                self.result.stall_events.append(self._current_stall)
                self._current_stall = None

    def _track_peaks(self):
        self.result.peak_metal_income = max(self.result.peak_metal_income, self.state.metal_income)
        self.result.peak_energy_income = max(self.result.peak_energy_income, self.state.energy_income)

    # ------------------------------------------------------------------
    # Snapshot recording
    # ------------------------------------------------------------------

    def _record_snapshot(self):
        s = self.state
        total_bp = sum(b.build_power for b in s.builders.values() if b.is_active)
        self.result.snapshots.append(Snapshot(
            tick=s.tick,
            metal_income=s.metal_income,
            energy_income=s.energy_income,
            metal_stored=s.metal_stored,
            energy_stored=s.energy_stored,
            metal_expenditure=s.metal_expenditure,
            energy_expenditure=s.energy_expenditure,
            build_power=total_bp,
            army_value_metal=self._army_value,
            stall_factor=s.effective_stall_factor,
            unit_counts=dict(s.buildings | s.units),
            army_by_role=dict(s.army_by_role),
            econ_state=s.econ_state,
        ))

    # ------------------------------------------------------------------
    # Finalization
    # ------------------------------------------------------------------

    def _finalize(self):
        # Close any open stall event
        if self._current_stall:
            self._current_stall.end_tick = self.state.tick
            self.result.stall_events.append(self._current_stall)
        self.result.total_army_metal_value = self._army_value

        # Strategy mode results
        if self._strategy_mode:
            if self._army:
                self.result.army_composition_final = dict(self._army.counts_by_role)
            if self._goal_queue:
                self.result.goal_completions = list(self._goal_queue.completions)
            if self._strategy_config:
                self.result.strategy_used = self._strategy_config.summary()

    # ------------------------------------------------------------------
    # Utilities
    # ------------------------------------------------------------------

    def _next_task_id(self) -> int:
        self._next_task_id_counter += 1
        return self._next_task_id_counter

    # ------------------------------------------------------------------
    # Strategy mode methods
    # ------------------------------------------------------------------

    def _update_emergency(self):
        """Check if emergency mode should activate or expire."""
        cfg = self._strategy_config
        if not cfg or cfg.emergency_mode.value == "none":
            self.state.emergency_active = False
            return

        tick = self.state.tick
        start = cfg.emergency_start_tick
        if start is None:
            # Emergency not scheduled
            self.state.emergency_active = False
            return

        if tick < start:
            self.state.emergency_active = False
            return

        if tick >= start + cfg.emergency_duration:
            # Emergency expired — clear it
            from bar_sim.strategy import EmergencyMode
            cfg.emergency_mode = EmergencyMode.NONE
            cfg.emergency_start_tick = None
            self.state.emergency_active = False
            return

        self.state.emergency_active = True
        if self.state.emergency_start_tick is None:
            self.state.emergency_start_tick = tick

    def _update_econ_state(self):
        """Classify economy state for strategy decisions."""
        from bar_sim.econ_ctrl import classify_econ_state
        self.state.econ_state = classify_econ_state(self.state)

    def _strategy_assign_builder(self, bid: str, builder: "Builder") -> Optional[BuildAction]:
        """Get a dynamic build action for a builder in strategy mode."""
        if builder.builder_type == "factory":
            return self._strategy_factory_action(bid)
        elif builder.builder_type in ("commander", "constructor"):
            return self._strategy_econ_action(bid)
        return None

    def _strategy_factory_action(self, factory_bid: str) -> Optional[BuildAction]:
        """Choose production for a factory using deficit-based logic."""
        from bar_sim.production import choose_factory_production

        factory_type = self._factory_type_map.get(factory_bid, "bot_lab")

        # Get goal overrides
        prod_override = None
        if self._goal_queue:
            _, prod_override = self._goal_queue.get_overrides()

        return choose_factory_production(
            self._strategy_config, self._army, factory_type, prod_override
        )

    def _strategy_econ_action(self, builder_bid: str) -> Optional[BuildAction]:
        """Choose economy build for a commander/constructor."""
        from bar_sim.econ_ctrl import choose_econ_build

        remaining_mex = self.bo.map_config.mex_spots - self._mex_built

        # Get goal overrides
        econ_override = None
        if self._goal_queue:
            econ_override, _ = self._goal_queue.get_overrides()

        return choose_econ_build(
            self._strategy_config, self.state, self.state.econ_state,
            remaining_mex, econ_override
        )
