"""
BAR Build Order Simulator - Web Frontend
==========================================
FastAPI server serving API + static files.

Usage:
    python -m bar_sim.web
    python cli.py web [--port 8080]
"""

import copy
import json
import queue
import threading
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel
import uvicorn

from bar_sim.models import (
    BuildOrder, BuildAction, BuildActionType, MapConfig, SimResult,
)
from bar_sim.engine import SimulationEngine
from bar_sim.io import load_build_order, save_build_order
from bar_sim.econ import UNITS, set_faction
from bar_sim.optimizer import Optimizer, make_goal

# Paths
STATIC_DIR = Path(__file__).parent / "static"
DATA_DIR = Path(__file__).parent.parent / "data"
BUILD_ORDERS_DIR = DATA_DIR / "build_orders"

app = FastAPI(title="BAR Build Order Simulator")


# ---------------------------------------------------------------------------
# Pydantic models for request/response
# ---------------------------------------------------------------------------

class MapConfigIn(BaseModel):
    avg_wind: float = 12.0
    wind_variance: float = 3.0
    mex_value: float = 2.0
    mex_spots: int = 6
    has_geo: bool = False
    tidal_value: float = 0.0
    reclaim_metal: float = 0.0


class BuildOrderIn(BaseModel):
    name: str = "Untitled"
    description: str = ""
    map_config: MapConfigIn = MapConfigIn()
    commander_queue: list[str] = []
    factory_queues: dict[str, list[str]] = {}
    constructor_queues: dict[str, list[str]] = {}


class SimulateRequest(BaseModel):
    build_order: Optional[BuildOrderIn] = None
    filename: Optional[str] = None
    duration: int = 600
    engine: str = "python"  # "python" or "headless"
    map_name: Optional[str] = None  # auto-resolve MapConfig from map data


class CompareRequest(BaseModel):
    build_orders: list[BuildOrderIn] = []
    filenames: list[str] = []
    duration: int = 600


class OptimizeRequest(BaseModel):
    goal: str = "max_metal"
    target_time: int = 300
    duration: int = 600
    map_config: MapConfigIn = MapConfigIn()
    generations: int = 100
    pop_size: int = 60
    start_from: Optional[str] = None


class SaveRequest(BaseModel):
    build_order: BuildOrderIn
    filename: str


class FactionRequest(BaseModel):
    faction: str = "armada"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _bo_from_input(bo_in: BuildOrderIn) -> BuildOrder:
    """Convert Pydantic model to internal BuildOrder."""
    mc = MapConfig(
        avg_wind=bo_in.map_config.avg_wind,
        wind_variance=bo_in.map_config.wind_variance,
        mex_value=bo_in.map_config.mex_value,
        mex_spots=bo_in.map_config.mex_spots,
        has_geo=bo_in.map_config.has_geo,
        tidal_value=bo_in.map_config.tidal_value,
        reclaim_metal=bo_in.map_config.reclaim_metal,
    )
    bo = BuildOrder(name=bo_in.name, description=bo_in.description, map_config=mc)
    for key in bo_in.commander_queue:
        bo.commander_queue.append(BuildAction(unit_key=key))
    for fid, keys in bo_in.factory_queues.items():
        bo.factory_queues[fid] = [
            BuildAction(unit_key=k, action_type=BuildActionType.PRODUCE_UNIT)
            for k in keys
        ]
    for cid, keys in bo_in.constructor_queues.items():
        bo.constructor_queues[cid] = [
            BuildAction(unit_key=k) for k in keys
        ]
    return bo


def _result_to_dict(result: SimResult) -> dict:
    """Convert SimResult to JSON-serializable dict."""
    return {
        "build_order_name": result.build_order_name,
        "total_ticks": result.total_ticks,
        "milestones": [
            {"tick": m.tick, "event": m.event, "description": m.description,
             "metal_income": m.metal_income, "energy_income": m.energy_income}
            for m in result.milestones
        ],
        "stall_events": [
            {"start_tick": s.start_tick, "end_tick": s.end_tick,
             "resource": s.resource, "severity": s.severity}
            for s in result.stall_events
        ],
        "completion_log": [
            {"tick": t, "unit_key": u, "builder_id": b}
            for t, u, b in result.completion_log
        ],
        "snapshots": [
            {"tick": s.tick, "metal_income": s.metal_income,
             "energy_income": s.energy_income, "metal_stored": s.metal_stored,
             "energy_stored": s.energy_stored,
             "metal_expenditure": s.metal_expenditure,
             "energy_expenditure": s.energy_expenditure,
             "build_power": s.build_power, "army_value_metal": s.army_value_metal,
             "stall_factor": s.stall_factor, "unit_counts": s.unit_counts}
            for s in result.snapshots
        ],
        "time_to_first_factory": result.time_to_first_factory,
        "time_to_first_constructor": result.time_to_first_constructor,
        "time_to_first_nano": result.time_to_first_nano,
        "time_to_t2_lab": result.time_to_t2_lab,
        "peak_metal_income": result.peak_metal_income,
        "peak_energy_income": result.peak_energy_income,
        "total_metal_stall_seconds": result.total_metal_stall_seconds,
        "total_energy_stall_seconds": result.total_energy_stall_seconds,
        "total_army_metal_value": result.total_army_metal_value,
    }


def _bo_to_dict(bo: BuildOrder) -> dict:
    """Convert BuildOrder to JSON-serializable dict for the editor."""
    return {
        "name": bo.name,
        "description": bo.description,
        "map_config": {
            "avg_wind": bo.map_config.avg_wind,
            "wind_variance": bo.map_config.wind_variance,
            "mex_value": bo.map_config.mex_value,
            "mex_spots": bo.map_config.mex_spots,
            "has_geo": bo.map_config.has_geo,
            "tidal_value": bo.map_config.tidal_value,
            "reclaim_metal": bo.map_config.reclaim_metal,
        },
        "commander_queue": [a.unit_key for a in bo.commander_queue],
        "factory_queues": {
            fid: [a.unit_key for a in q]
            for fid, q in bo.factory_queues.items()
        },
        "constructor_queues": {
            cid: [a.unit_key for a in q]
            for cid, q in bo.constructor_queues.items()
        },
    }


# ---------------------------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------------------------

@app.get("/api/units")
def api_units():
    """Return unit catalog for current faction."""
    from bar_sim.optimizer import COMMANDER_POOL, FACTORY_PRODUCIBLE, CON_POOL
    result = {}
    for key, u in sorted(UNITS.items()):
        result[key] = {
            "name": u.name,
            "metal_cost": u.metal_cost,
            "energy_cost": u.energy_cost,
            "build_time": u.build_time,
            "build_power": u.build_power,
            "metal_production": u.metal_production,
            "energy_production": u.energy_production,
            "energy_upkeep": u.energy_upkeep,
            "health": u.health,
            "notes": u.notes,
        }
    return {
        "units": result,
        "pools": {
            "commander": COMMANDER_POOL,
            "factory": FACTORY_PRODUCIBLE,
            "constructor": CON_POOL,
        },
    }


@app.get("/api/build-orders")
def api_build_orders():
    """List saved YAML files."""
    files = []
    if BUILD_ORDERS_DIR.exists():
        for f in sorted(BUILD_ORDERS_DIR.glob("*.yaml")):
            files.append({"filename": f.name, "stem": f.stem})
    return {"build_orders": files}


@app.get("/api/build-orders/{filename}")
def api_build_order_detail(filename: str):
    """Load a specific build order."""
    filepath = BUILD_ORDERS_DIR / filename
    if not filepath.exists():
        raise HTTPException(404, f"Build order not found: {filename}")
    bo = load_build_order(str(filepath))
    return _bo_to_dict(bo)


@app.post("/api/simulate")
def api_simulate(req: SimulateRequest):
    """Run simulation and return result."""
    if req.filename:
        filepath = BUILD_ORDERS_DIR / req.filename
        if not filepath.exists():
            raise HTTPException(404, f"Build order not found: {req.filename}")
        bo = load_build_order(str(filepath))
    elif req.build_order:
        bo = _bo_from_input(req.build_order)
    else:
        raise HTTPException(400, "Provide either build_order or filename")

    # Auto-resolve map config from map name
    if req.map_name:
        try:
            from bar_sim.map_data import get_map_data, map_data_to_map_config
            md = get_map_data(req.map_name)
            if md:
                bo.map_config = map_data_to_map_config(md)
                bo.map_name = req.map_name
        except Exception:
            pass

    if req.engine == "headless":
        from bar_sim.headless import HeadlessEngine
        try:
            headless = HeadlessEngine(map_name=req.map_name or "delta_siege_dry_v5.7.1")
            result = headless.run(bo, req.duration)
        except (FileNotFoundError, RuntimeError) as e:
            raise HTTPException(500, f"Headless engine error: {e}")
    else:
        engine = SimulationEngine(bo, req.duration)
        result = engine.run()
    return _result_to_dict(result)


@app.post("/api/compare")
def api_compare(req: CompareRequest):
    """Simulate multiple BOs and return all results."""
    results = []

    for bo_in in req.build_orders:
        bo = _bo_from_input(bo_in)
        engine = SimulationEngine(bo, req.duration)
        results.append(_result_to_dict(engine.run()))

    for fname in req.filenames:
        filepath = BUILD_ORDERS_DIR / fname
        if filepath.exists():
            bo = load_build_order(str(filepath))
            engine = SimulationEngine(bo, req.duration)
            results.append(_result_to_dict(engine.run()))

    return {"results": results}


@app.post("/api/save")
def api_save(req: SaveRequest):
    """Save build order to YAML."""
    bo = _bo_from_input(req.build_order)
    filename = req.filename
    if not filename.endswith(".yaml"):
        filename += ".yaml"
    filepath = BUILD_ORDERS_DIR / filename
    save_build_order(bo, str(filepath))
    return {"saved": filename}


@app.post("/api/faction")
def api_faction(req: FactionRequest):
    """Switch faction."""
    faction = req.faction.upper()
    if faction not in ("ARMADA", "CORTEX"):
        raise HTTPException(400, "Faction must be armada or cortex")
    set_faction(faction)
    return {"faction": faction, "unit_count": len(UNITS)}


# ---------------------------------------------------------------------------
# Map API
# ---------------------------------------------------------------------------

@app.get("/api/maps")
def api_maps():
    """List all available maps with basic metadata."""
    try:
        from bar_sim.map_parser import list_available_maps
        from bar_sim.map_data import list_cached_maps
        maps = list_available_maps()
        cached = set(list_cached_maps())
        for m in maps:
            m["scanned"] = m["filename"].replace(".sd7", "") in cached
        return {"maps": maps}
    except Exception as e:
        raise HTTPException(500, f"Error listing maps: {e}")


@app.get("/api/maps/{name}")
def api_map_detail(name: str):
    """Get detailed map data (from cache + static parse)."""
    from bar_sim.map_data import get_map_data, map_data_to_map_config
    md = get_map_data(name)
    if not md:
        raise HTTPException(404, f"Map not found: {name}")
    mc = map_data_to_map_config(md)
    return {
        "name": md.name,
        "filename": md.filename,
        "shortname": md.shortname,
        "author": md.author,
        "wind_min": md.wind_min,
        "wind_max": md.wind_max,
        "tidal_strength": md.tidal_strength,
        "max_metal": md.max_metal,
        "gravity": md.gravity,
        "map_width": md.map_width,
        "map_height": md.map_height,
        "mex_spots_total": len(md.mex_spots),
        "geo_vents": len(md.geo_vents),
        "start_positions": len(md.start_positions),
        "total_reclaim_metal": md.total_reclaim_metal,
        "total_reclaim_energy": md.total_reclaim_energy,
        "source": md.source,
        "map_config": {
            "avg_wind": mc.avg_wind,
            "wind_variance": mc.wind_variance,
            "mex_value": mc.mex_value,
            "mex_spots": mc.mex_spots,
            "has_geo": mc.has_geo,
            "tidal_value": mc.tidal_value,
            "reclaim_metal": mc.reclaim_metal,
        },
    }


@app.post("/api/maps/{name}/scan")
def api_map_scan(name: str):
    """Trigger a headless map scan (blocking, ~3-10s)."""
    try:
        from bar_sim.headless import HeadlessEngine
        he = HeadlessEngine()
        md = he.scan_map(name)
        return {
            "status": "ok",
            "name": md.name,
            "mex_spots": len(md.mex_spots),
            "geo_vents": len(md.geo_vents),
            "wind_min": md.wind_min,
            "wind_max": md.wind_max,
            "start_positions": len(md.start_positions),
        }
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))
    except RuntimeError as e:
        raise HTTPException(500, str(e))


@app.post("/api/optimize")
def api_optimize(req: OptimizeRequest):
    """Start GA optimization with SSE streaming."""
    mc = MapConfig(
        avg_wind=req.map_config.avg_wind,
        mex_value=req.map_config.mex_value,
        mex_spots=req.map_config.mex_spots,
        has_geo=req.map_config.has_geo,
    )
    goal = make_goal(req.goal, target_time=req.target_time)

    initial_bo = None
    if req.start_from:
        filepath = BUILD_ORDERS_DIR / req.start_from
        if filepath.exists():
            initial_bo = load_build_order(str(filepath))
            initial_bo.map_config = mc

    progress_queue = queue.Queue()
    cancel_event = threading.Event()

    def run_optimizer():
        opt = Optimizer(
            goal=goal,
            map_config=mc,
            duration=req.duration,
            population_size=req.pop_size,
            max_generations=req.generations,
            verbose=False,
        )

        # Monkey-patch to capture progress
        original_optimize = opt.optimize.__func__

        # We'll run a simplified version that reports progress
        import copy as _copy
        import time as _time
        import random as _random

        from bar_sim.optimizer import (
            greedy_seed, random_seed, enforce_constraints, MUTATIONS,
            _crossover_one_point, _crossover_uniform,
        )

        # Init population
        pop = opt._init_population(initial_bo)
        best_score, best_bo = opt._best_of(pop)
        opt.history.append(best_score)

        progress_queue.put(("progress", {
            "generation": 0,
            "best_score": best_score,
            "gen_best": best_score,
            "mutation_rate": opt.base_mutation_rate,
            "stagnation": 0,
            "total_generations": opt.max_generations,
        }))

        mutation_rate = opt.base_mutation_rate
        stagnation = 0

        for gen in range(opt.max_generations):
            if cancel_event.is_set():
                break

            if opt.goal.higher_is_better:
                pop.sort(key=lambda x: x[0], reverse=True)
            else:
                pop.sort(key=lambda x: x[0])

            gen_best_score = pop[0][0]

            if opt.goal.is_better(gen_best_score, best_score):
                best_score = gen_best_score
                best_bo = _copy.deepcopy(pop[0][1])
                stagnation = 0
            else:
                stagnation += 1

            opt.history.append(best_score)

            # Report progress
            progress_queue.put(("progress", {
                "generation": gen + 1,
                "best_score": round(best_score, 2),
                "gen_best": round(gen_best_score, 2),
                "mutation_rate": round(mutation_rate, 3),
                "stagnation": stagnation,
                "total_generations": opt.max_generations,
            }))

            # Stagnation handling
            if stagnation >= opt.catastrophe_limit:
                pop = opt._init_population(best_bo)
                mutation_rate = opt.base_mutation_rate
                stagnation = 0
                continue
            elif stagnation >= opt.stagnation_limit:
                mutation_rate = opt.hyper_mutation_rate
            else:
                mutation_rate = max(0.05, mutation_rate * opt.mutation_decay)

            # Build next generation
            new_pop = list(pop[:opt.elitism_count])
            while len(new_pop) < opt.population_size:
                p1 = opt._tournament_select(pop)
                p2 = opt._tournament_select(pop)
                if opt.rng.random() < opt.crossover_rate:
                    if opt.rng.random() < 0.7:
                        c1, c2 = _crossover_one_point(p1, p2, opt.rng)
                    else:
                        c1, c2 = _crossover_uniform(p1, p2, opt.rng)
                else:
                    c1, c2 = p1, p2

                for child in (c1, c2):
                    if len(new_pop) >= opt.population_size:
                        break
                    if opt.rng.random() < mutation_rate:
                        n_muts = 1 if mutation_rate < 0.6 else opt.rng.randint(1, 3)
                        for _ in range(n_muts):
                            mut = opt.rng.choice(MUTATIONS)
                            child = mut(child, opt.rng)
                    child = enforce_constraints(child, opt.map_config)
                    score = opt._evaluate(child)
                    new_pop.append((score, child))

            pop = new_pop[:opt.population_size]

        # Final result
        best_bo.name = f"Optimized ({opt.goal.name})"
        engine = SimulationEngine(best_bo, req.duration)
        final_result = engine.run()

        progress_queue.put(("complete", {
            "build_order": _bo_to_dict(best_bo),
            "result": _result_to_dict(final_result),
            "history": [round(h, 2) for h in opt.history],
        }))

    thread = threading.Thread(target=run_optimizer, daemon=True)
    thread.start()

    def event_stream():
        while True:
            try:
                event_type, data = progress_queue.get(timeout=60)
                yield f"event: {event_type}\ndata: {json.dumps(data)}\n\n"
                if event_type == "complete":
                    break
            except queue.Empty:
                yield f"event: ping\ndata: {{}}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# Static files & SPA fallback
# ---------------------------------------------------------------------------

@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


# Mount static after routes so API routes take priority
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


def start_server(port: int = 8080):
    """Start the uvicorn server."""
    print(f"Starting BAR Build Order Simulator at http://localhost:{port}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")


if __name__ == "__main__":
    start_server()
