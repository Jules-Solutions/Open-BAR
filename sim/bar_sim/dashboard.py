"""
BAR Unit Data Analysis Dashboard
=================================
Interactive Plotly Dash dashboard for analyzing Beyond All Reason unit economics.

Core question: How much buildpower can I support given my economy?

Usage:
    python -m bar_sim.dashboard
    python cli.py dashboard [--port 8050]
"""

import csv
import io
import json
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from scipy import stats as sp_stats
from dash import Dash, html, dcc, Input, Output, State, callback, dash_table

# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------

DATA_DIR = Path(__file__).parent.parent / "data"
METAL_ENERGY_RATIO = 60  # 1 Metal = 60 Energy in BAR

UNIT_CATEGORIES = {
    "bot": "Bot",
    "vehicle": "Vehicle",
    "aircraft": "Aircraft",
    "ship": "Ship",
    "hovercraft": "Hovercraft",
    "building": "Building",
}


def load_unit_data() -> pd.DataFrame:
    """Load all units from unitlist.csv into a DataFrame with derived columns."""
    csv_path = DATA_DIR / "unitlist.csv"
    rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            rows.append(row)

    df = pd.DataFrame(rows)

    # Clean: drop empty trailing rows
    df = df.dropna(subset=["id"])
    df = df[df["id"].str.strip() != ""]

    # Numeric conversions
    num_cols = [
        "metalcost", "energycost", "buildtime", "metalmake", "energymake",
        "buildpower", "speed", "health", "dps", "weaponrange", "sightrange",
        "radarrange", "sonarrange", "jammerrange", "height",
    ]
    for col in num_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    # Faction normalization
    df["faction"] = df["faction"].str.upper().str.strip()

    # Tech level
    df["techlevel"] = pd.to_numeric(df["techlevel"], errors="coerce").fillna(1).astype(int)

    # ----- Derived columns -----

    # Total cost (normalized: 1M = 60E)
    df["totalcost"] = df["metalcost"] + df["energycost"] / METAL_ENERGY_RATIO

    # Metal/Energy ratio
    df["me_ratio"] = df.apply(
        lambda r: r["metalcost"] / r["energycost"] if r["energycost"] > 0 else float("inf"),
        axis=1,
    )

    # Resource drain rates (per second at 1 buildpower)
    df["metal_per_sec_per_bp"] = df.apply(
        lambda r: r["metalcost"] / r["buildtime"] if r["buildtime"] > 0 else 0, axis=1
    )
    df["energy_per_sec_per_bp"] = df.apply(
        lambda r: r["energycost"] / r["buildtime"] if r["buildtime"] > 0 else 0, axis=1
    )

    # Total resource rate per bp (normalized)
    df["total_rate_per_bp"] = df["metal_per_sec_per_bp"] + df["energy_per_sec_per_bp"] / METAL_ENERGY_RATIO

    # Unit category from file path
    df["category"] = df.apply(_categorize_unit, axis=1)

    # Boolean flags (from CSV)
    for flag in ["bot", "tank", "air", "ship", "hover", "building"]:
        if flag in df.columns:
            df[f"is_{flag}"] = df[flag].astype(str).str.strip() == "1"

    # Is constructor
    df["is_constructor"] = df["buildpower"] > 0

    # Is economy building
    df["is_econ"] = (df["metalmake"] > 0) | (df["energymake"] > 0)

    # Has weapons
    df["is_combat"] = df["dps"] > 0

    # Display label
    df["label"] = df["name"] + " (" + df["id"] + ")"

    return df


def _categorize_unit(row) -> str:
    """Derive category from CSV flags and file path."""
    file_path = str(row.get("file", "")).lower()
    if "bot" in file_path:
        return "Bot"
    if "vehicle" in file_path:
        return "Vehicle"
    if "aircraft" in file_path or "air" in file_path:
        return "Aircraft"
    if "ship" in file_path or "sea" in file_path:
        return "Ship"
    if "hover" in file_path:
        return "Hovercraft"
    if "building" in file_path or "defence" in file_path or "economy" in file_path or "util" in file_path:
        return "Building"
    # Fallback from flags
    if str(row.get("bot", "")).strip() == "1":
        return "Bot"
    if str(row.get("tank", "")).strip() == "1":
        return "Vehicle"
    if str(row.get("air", "")).strip() == "1":
        return "Aircraft"
    if str(row.get("ship", "")).strip() == "1":
        return "Ship"
    if str(row.get("hover", "")).strip() == "1":
        return "Hovercraft"
    if str(row.get("building", "")).strip() == "1":
        return "Building"
    return "Other"


# ---------------------------------------------------------------------------
# Dash App
# ---------------------------------------------------------------------------

# BAR-inspired dark theme colors
COLORS = {
    "bg": "#0d1117",
    "card": "#161b22",
    "border": "#30363d",
    "text": "#e6edf3",
    "muted": "#8b949e",
    "metal": "#4dabf7",       # Blue for metal
    "energy": "#ffd43b",      # Yellow/gold for energy
    "armada": "#339af0",      # Blue for Armada
    "cortex": "#e03131",      # Red for Cortex
    "accent": "#58a6ff",
    "green": "#3fb950",
    "orange": "#d29922",
    "grid": "#21262d",
}

PLOT_TEMPLATE = "plotly_dark"


def create_app(df: pd.DataFrame = None) -> Dash:
    if df is None:
        df = load_unit_data()

    app = Dash(
        __name__,
        title="BAR Unit Economics Dashboard",
        suppress_callback_exceptions=True,
    )

    factions = sorted(df["faction"].unique())
    categories = sorted(df["category"].unique())
    tech_levels = sorted(df["techlevel"].unique())

    app.layout = html.Div(
        style={"backgroundColor": COLORS["bg"], "color": COLORS["text"], "minHeight": "100vh", "fontFamily": "system-ui, -apple-system, sans-serif"},
        children=[
            # --- Header ---
            html.Div(
                style={"padding": "24px 32px", "borderBottom": f"1px solid {COLORS['border']}"},
                children=[
                    html.H1("BAR Unit Economics Dashboard", style={"margin": 0, "fontSize": "28px", "fontWeight": 600}),
                    html.P(
                        "Interactive analysis of Beyond All Reason unit data — costs, rates, buildpower economics",
                        style={"margin": "4px 0 0 0", "color": COLORS["muted"], "fontSize": "14px"},
                    ),
                ],
            ),

            # --- Global Filters ---
            html.Div(
                style={
                    "padding": "16px 32px",
                    "backgroundColor": COLORS["card"],
                    "borderBottom": f"1px solid {COLORS['border']}",
                    "display": "flex",
                    "gap": "24px",
                    "flexWrap": "wrap",
                    "alignItems": "flex-end",
                },
                children=[
                    _filter_block("Faction", dcc.Dropdown(
                        id="filter-faction",
                        options=[{"label": f, "value": f} for f in factions],
                        value=factions,
                        multi=True,
                        style={"width": "280px"},
                    )),
                    _filter_block("Category", dcc.Dropdown(
                        id="filter-category",
                        options=[{"label": c, "value": c} for c in categories],
                        value=categories,
                        multi=True,
                        style={"width": "320px"},
                    )),
                    _filter_block("Tech Level", dcc.Checklist(
                        id="filter-tech",
                        options=[{"label": f" T{t}", "value": t} for t in tech_levels],
                        value=tech_levels,
                        inline=True,
                        style={"display": "flex", "gap": "12px"},
                        inputStyle={"marginRight": "4px"},
                    )),
                    _filter_block("Show", dcc.Checklist(
                        id="filter-flags",
                        options=[
                            {"label": " Combat", "value": "combat"},
                            {"label": " Constructors", "value": "constructors"},
                            {"label": " Economy", "value": "econ"},
                        ],
                        value=["combat", "constructors", "econ"],
                        inline=True,
                        style={"display": "flex", "gap": "12px"},
                        inputStyle={"marginRight": "4px"},
                    )),
                ],
            ),

            # --- Tab Navigation ---
            dcc.Tabs(
                id="main-tabs",
                value="tab-costs",
                style={"padding": "0 32px", "backgroundColor": COLORS["bg"]},
                children=[
                    dcc.Tab(label="Cost Analysis", value="tab-costs",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Resource Ratios", value="tab-ratios",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Build Rates", value="tab-rates",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Buildpower Economics", value="tab-buildpower",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Buildpower Calculator", value="tab-calculator",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="BP Recommender", value="tab-recommender",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Blueprint Nanos", value="tab-blueprints",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                    dcc.Tab(label="Unit Table", value="tab-table",
                            style=_tab_style(), selected_style=_tab_selected_style()),
                ],
            ),

            # --- Tab Content ---
            html.Div(id="tab-content", style={"padding": "24px 32px"}),

            # --- Hidden data store (filtered) ---
            dcc.Store(id="filtered-data"),
        ],
    )

    # -----------------------------------------------------------------------
    # Callbacks
    # -----------------------------------------------------------------------

    @app.callback(
        Output("filtered-data", "data"),
        [
            Input("filter-faction", "value"),
            Input("filter-category", "value"),
            Input("filter-tech", "value"),
            Input("filter-flags", "value"),
        ],
    )
    def filter_data(factions_sel, categories_sel, tech_sel, flags_sel):
        filtered = df.copy()
        if factions_sel:
            filtered = filtered[filtered["faction"].isin(factions_sel)]
        if categories_sel:
            filtered = filtered[filtered["category"].isin(categories_sel)]
        if tech_sel:
            filtered = filtered[filtered["techlevel"].isin(tech_sel)]

        # Flag filters: show units matching ANY checked flag, or all if none
        if flags_sel:
            mask = pd.Series(False, index=filtered.index)
            if "combat" in flags_sel:
                mask |= filtered["is_combat"]
            if "constructors" in flags_sel:
                mask |= filtered["is_constructor"]
            if "econ" in flags_sel:
                mask |= filtered["is_econ"]
            # Always include units that don't fit any flag (misc)
            is_misc = ~filtered["is_combat"] & ~filtered["is_constructor"] & ~filtered["is_econ"]
            mask |= is_misc
            filtered = filtered[mask]

        # Serialize to JSON for store
        return filtered.to_json(orient="split", date_format="iso")

    @app.callback(
        Output("tab-content", "children"),
        [Input("main-tabs", "value"), Input("filtered-data", "data")],
    )
    def render_tab(tab, data_json):
        if data_json is None:
            return html.P("No data loaded.")
        fdf = pd.read_json(io.StringIO(data_json), orient="split")
        if tab == "tab-costs":
            return _render_costs_tab(fdf)
        elif tab == "tab-ratios":
            return _render_ratios_tab(fdf)
        elif tab == "tab-rates":
            return _render_rates_tab(fdf)
        elif tab == "tab-buildpower":
            return _render_buildpower_tab(fdf)
        elif tab == "tab-calculator":
            return _render_calculator_tab(fdf)
        elif tab == "tab-recommender":
            return _render_recommender_tab(fdf)
        elif tab == "tab-blueprints":
            return _render_blueprint_nanos_tab(fdf)
        elif tab == "tab-table":
            return _render_table_tab(fdf)
        return html.P("Unknown tab")

    # --- Calculator callbacks ---
    @app.callback(
        Output("calc-output", "children"),
        [
            Input("calc-metal-income", "value"),
            Input("calc-energy-income", "value"),
            Input("calc-unit-select", "value"),
            Input("calc-buildpower-range", "value"),
        ],
        prevent_initial_call=True,
    )
    def update_calculator(metal_income, energy_income, selected_units, bp_range):
        if not metal_income or not energy_income or not selected_units:
            return html.P("Set your economy and select units to analyze.", style={"color": COLORS["muted"]})

        metal_income = float(metal_income)
        energy_income = float(energy_income)
        bp_min, bp_max = bp_range if bp_range else [0, 2000]

        results = []
        for uid in selected_units:
            row = df[df["id"] == uid]
            if row.empty:
                continue
            r = row.iloc[0]
            m_rate = r["metal_per_sec_per_bp"]
            e_rate = r["energy_per_sec_per_bp"]

            if m_rate > 0:
                max_bp_metal = metal_income / m_rate
            else:
                max_bp_metal = float("inf")
            if e_rate > 0:
                max_bp_energy = energy_income / e_rate
            else:
                max_bp_energy = float("inf")

            max_bp = min(max_bp_metal, max_bp_energy)
            bottleneck = "Metal" if max_bp_metal < max_bp_energy else "Energy"

            results.append({
                "unit": r["label"],
                "id": r["id"],
                "m_rate": m_rate,
                "e_rate": e_rate,
                "max_bp": max_bp,
                "bottleneck": bottleneck,
                "max_bp_metal": max_bp_metal,
                "max_bp_energy": max_bp_energy,
            })

        if not results:
            return html.P("No valid units selected.", style={"color": COLORS["muted"]})

        # --- Summary table ---
        summary_rows = []
        for r in results:
            summary_rows.append(html.Tr([
                html.Td(r["unit"], style={"padding": "8px 12px"}),
                html.Td(f"{r['m_rate']:.4f}", style={"padding": "8px 12px", "color": COLORS["metal"]}),
                html.Td(f"{r['e_rate']:.4f}", style={"padding": "8px 12px", "color": COLORS["energy"]}),
                html.Td(f"{r['max_bp']:.0f}", style={"padding": "8px 12px", "fontWeight": "bold", "color": COLORS["green"]}),
                html.Td(r["bottleneck"], style={
                    "padding": "8px 12px",
                    "color": COLORS["metal"] if r["bottleneck"] == "Metal" else COLORS["energy"],
                }),
            ]))

        summary_table = html.Table(
            style={"width": "100%", "borderCollapse": "collapse", "marginBottom": "24px"},
            children=[
                html.Thead(html.Tr([
                    html.Th("Unit", style=_th_style()),
                    html.Th("M/s per BP", style=_th_style()),
                    html.Th("E/s per BP", style=_th_style()),
                    html.Th("Max Sustainable BP", style=_th_style()),
                    html.Th("Bottleneck", style=_th_style()),
                ])),
                html.Tbody(summary_rows),
            ],
        )

        # --- Buildpower drain curves ---
        bp_values = list(range(int(bp_min), int(bp_max) + 1, max(1, (int(bp_max) - int(bp_min)) // 200)))
        fig = make_subplots(
            rows=1, cols=2,
            subplot_titles=["Metal Drain vs BP", "Energy Drain vs BP"],
            horizontal_spacing=0.08,
        )

        for r in results:
            metal_drain = [bp * r["m_rate"] for bp in bp_values]
            energy_drain = [bp * r["e_rate"] for bp in bp_values]

            fig.add_trace(go.Scatter(
                x=bp_values, y=metal_drain,
                name=f"{r['unit']} (M)", mode="lines",
                line=dict(width=2),
                hovertemplate="BP: %{x}<br>M/s drain: %{y:.1f}<extra></extra>",
            ), row=1, col=1)

            fig.add_trace(go.Scatter(
                x=bp_values, y=energy_drain,
                name=f"{r['unit']} (E)", mode="lines",
                line=dict(width=2, dash="dash"),
                hovertemplate="BP: %{x}<br>E/s drain: %{y:.1f}<extra></extra>",
            ), row=1, col=2)

        # Income lines
        fig.add_hline(y=metal_income, line_dash="dot", line_color=COLORS["metal"],
                      annotation_text=f"Metal income: {metal_income}", row=1, col=1)
        fig.add_hline(y=energy_income, line_dash="dot", line_color=COLORS["energy"],
                      annotation_text=f"Energy income: {energy_income}", row=1, col=2)

        fig.update_layout(
            template=PLOT_TEMPLATE,
            paper_bgcolor=COLORS["bg"],
            plot_bgcolor=COLORS["card"],
            height=450,
            xaxis_title="Total Buildpower",
            xaxis2_title="Total Buildpower",
            yaxis_title="Metal/s",
            yaxis2_title="Energy/s",
            legend=dict(orientation="h", y=-0.15),
        )

        # --- Breakeven visualization ---
        breakeven_fig = go.Figure()
        for r in results:
            # At what BP does metal drain = energy drain (normalized)?
            # metal_drain = bp * m_rate, energy_drain_normalized = bp * e_rate / 60
            # These cross when m_rate = e_rate/60, which is a fixed ratio, so no crossover
            # Instead: show where income lines cross drain lines
            if r["m_rate"] > 0:
                bp_metal_limit = metal_income / r["m_rate"]
            else:
                bp_metal_limit = bp_max
            if r["e_rate"] > 0:
                bp_energy_limit = energy_income / r["e_rate"]
            else:
                bp_energy_limit = bp_max

            breakeven_fig.add_trace(go.Bar(
                name=r["unit"],
                x=[r["unit"]],
                y=[min(bp_metal_limit, bp_energy_limit)],
                marker_color=COLORS["green"],
                hovertemplate=(
                    f"Max BP: {min(bp_metal_limit, bp_energy_limit):.0f}<br>"
                    f"Metal-limited BP: {bp_metal_limit:.0f}<br>"
                    f"Energy-limited BP: {bp_energy_limit:.0f}<br>"
                    f"Bottleneck: {r['bottleneck']}<extra></extra>"
                ),
            ))

            # Show the "unused capacity" as stacked bar
            diff = abs(bp_metal_limit - bp_energy_limit)
            breakeven_fig.add_trace(go.Bar(
                name=f"{r['unit']} (unused capacity)",
                x=[r["unit"]],
                y=[diff],
                marker_color=COLORS["orange"],
                opacity=0.5,
                hovertemplate=f"Unused capacity: {diff:.0f} BP<extra></extra>",
                showlegend=False,
            ))

        breakeven_fig.update_layout(
            template=PLOT_TEMPLATE,
            paper_bgcolor=COLORS["bg"],
            plot_bgcolor=COLORS["card"],
            barmode="stack",
            title="Max Sustainable Buildpower per Unit (green = usable, orange = wasted capacity from non-bottleneck resource)",
            yaxis_title="Buildpower",
            height=400,
            showlegend=False,
        )

        return html.Div([
            html.H3("Analysis Results", style={"marginBottom": "16px"}),
            summary_table,
            dcc.Graph(figure=fig, config={"displayModeBar": True}),
            html.Hr(style={"borderColor": COLORS["border"], "margin": "24px 0"}),
            dcc.Graph(figure=breakeven_fig, config={"displayModeBar": True}),
        ])

    # --- BP Recommender callback ---
    @app.callback(
        Output("rec-output", "children"),
        [
            Input("rec-metal-income", "value"),
            Input("rec-energy-income", "value"),
            Input("rec-metal-spend", "value"),
            Input("rec-energy-spend", "value"),
            Input("rec-current-bp", "value"),
            Input("rec-profile", "value"),
        ],
        prevent_initial_call=True,
    )
    def update_recommender(metal_in, energy_in, metal_spend, energy_spend, current_bp, profile):
        NANO_BP = 200

        if not metal_in or not energy_in:
            return html.P("Enter your economy stats.", style={"color": COLORS["muted"]})

        metal_in = float(metal_in or 0)
        energy_in = float(energy_in or 0)
        metal_spend = float(metal_spend or 0)
        energy_spend = float(energy_spend or 0)
        current_bp = float(current_bp or 0)

        # Available resources for building
        avail_m = metal_in - metal_spend
        avail_e = energy_in - energy_spend

        if avail_m <= 0 and avail_e <= 0:
            return html.P("No resources available for building after other spending.",
                          style={"color": "#ff6b6b"})

        # Compute drain rates for each known profile
        build_df = df[df["buildtime"] > 0].copy()
        buildings = build_df[build_df["category"] == "Building"]
        mobile = build_df[build_df["category"] != "Building"]
        econ_bldg = buildings[buildings["is_econ"]]
        defense_bldg = buildings[buildings["is_combat"]]

        profiles_data = {}
        for name, sub_df in [
            ("Economy Buildings", econ_bldg),
            ("Defense Buildings", defense_bldg),
            ("Mobile Units", mobile),
            ("Mixed (All)", build_df),
        ]:
            if not sub_df.empty:
                profiles_data[name] = {
                    "m_per_bp": sub_df["metal_per_sec_per_bp"].mean(),
                    "e_per_bp": sub_df["energy_per_sec_per_bp"].mean(),
                }

        if profile not in profiles_data:
            return html.P("Selected profile has no data.", style={"color": COLORS["muted"]})

        p = profiles_data[profile]
        m_per_bp = p["m_per_bp"]
        e_per_bp = p["e_per_bp"]

        # Max sustainable BP
        max_bp_metal = avail_m / m_per_bp if m_per_bp > 0 else float("inf")
        max_bp_energy = avail_e / e_per_bp if e_per_bp > 0 else float("inf")
        recommended_bp = min(max_bp_metal, max_bp_energy)
        bottleneck = "Metal" if max_bp_metal < max_bp_energy else "Energy"

        delta = recommended_bp - current_bp
        delta_nanos = delta / NANO_BP

        # Current drain
        cur_m_drain = current_bp * m_per_bp
        cur_e_drain = current_bp * e_per_bp
        rec_m_drain = recommended_bp * m_per_bp
        rec_e_drain = recommended_bp * e_per_bp

        # Color coding
        delta_color = COLORS["green"] if delta >= 0 else "#ff6b6b"
        delta_sign = "+" if delta >= 0 else ""
        advice = "Add constructors!" if delta > 200 else "Reduce constructors!" if delta < -200 else "You're well balanced."

        # --- Gauge figure ---
        fig = go.Figure()

        # BP bar - current
        fig.add_trace(go.Bar(
            y=["Buildpower"], x=[current_bp], orientation="h",
            name="Current BP", marker_color=COLORS["accent"],
            text=[f"{current_bp:.0f}"], textposition="inside",
        ))

        # BP bar - recommended overlay
        fig.add_shape(
            type="line", x0=recommended_bp, x1=recommended_bp,
            y0=-0.5, y1=0.5, line=dict(color=COLORS["green"], width=3, dash="dash"),
        )
        fig.add_annotation(
            x=recommended_bp, y=0.5, text=f"Recommended: {recommended_bp:.0f}",
            showarrow=True, arrowhead=2, font=dict(color=COLORS["green"], size=12),
        )

        # Drain bars
        fig.add_trace(go.Bar(
            y=["Metal Drain"], x=[cur_m_drain], orientation="h",
            name="Current M Drain", marker_color=COLORS["metal"],
            text=[f"{cur_m_drain:.1f} / {avail_m:.1f} M/s"], textposition="inside",
        ))
        fig.add_trace(go.Bar(
            y=["Energy Drain"], x=[cur_e_drain], orientation="h",
            name="Current E Drain", marker_color=COLORS["energy"],
            text=[f"{cur_e_drain:.0f} / {avail_e:.0f} E/s"], textposition="inside",
        ))

        fig.update_layout(
            template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
            height=250, showlegend=False,
            xaxis_title="", barmode="overlay",
            margin=dict(l=120),
        )

        # Multi-profile comparison
        comparison_rows = []
        for pname, pdata in profiles_data.items():
            pm = pdata["m_per_bp"]
            pe = pdata["e_per_bp"]
            pbp_m = avail_m / pm if pm > 0 else float("inf")
            pbp_e = avail_e / pe if pe > 0 else float("inf")
            pbp = min(pbp_m, pbp_e)
            pbn = "Metal" if pbp_m < pbp_e else "Energy"
            pdelta = pbp - current_bp
            comparison_rows.append(html.Tr([
                html.Td(pname, style={"padding": "8px 12px", "fontWeight": "bold" if pname == profile else "normal"}),
                html.Td(f"{pbp:.0f}", style={"padding": "8px 12px", "color": COLORS["green"]}),
                html.Td(f"{pdelta:+.0f}", style={"padding": "8px 12px", "color": COLORS["green"] if pdelta >= 0 else "#ff6b6b"}),
                html.Td(f"{pdelta / NANO_BP:+.1f} nanos", style={"padding": "8px 12px", "color": COLORS["muted"]}),
                html.Td(pbn, style={"padding": "8px 12px", "color": COLORS["metal"] if pbn == "Metal" else COLORS["energy"]}),
            ]))

        comparison_table = html.Table(
            style={"width": "100%", "borderCollapse": "collapse", "marginTop": "16px"},
            children=[
                html.Thead(html.Tr([
                    html.Th("Profile", style=_th_style()),
                    html.Th("Sustainable BP", style=_th_style()),
                    html.Th("Delta", style=_th_style()),
                    html.Th("≈ Nanos", style=_th_style()),
                    html.Th("Bottleneck", style=_th_style()),
                ])),
                html.Tbody(comparison_rows),
            ],
        )

        return html.Div([
            # Big delta card
            html.Div(
                style={"display": "grid", "gridTemplateColumns": "1fr 1fr 1fr 1fr", "gap": "12px", "marginBottom": "16px"},
                children=[
                    _stat_card("Recommended BP", f"{recommended_bp:.0f}",
                               f"Bottleneck: {bottleneck}"),
                    _stat_card("Delta",
                               f"{delta_sign}{delta:.0f} BP",
                               f"({delta_sign}{delta_nanos:.1f} nano turrets)"),
                    _stat_card("Status",
                               "UNDER-BUILT" if delta > 200 else "OVER-BUILT" if delta < -200 else "BALANCED",
                               advice),
                    _stat_card("Efficiency",
                               f"{min(100, current_bp / recommended_bp * 100):.0f}%" if recommended_bp > 0 else "N/A",
                               "Current / Recommended BP"),
                ],
            ),
            html.Div(
                style={"textAlign": "center", "fontSize": "32px", "fontWeight": 700,
                       "color": delta_color, "margin": "8px 0 16px"},
                children=f"{delta_sign}{delta:.0f} BP ({delta_sign}{delta_nanos:.1f} nanos)  →  {advice}",
            ),

            dcc.Graph(figure=fig, config={"displayModeBar": True}),

            html.H4("All Profiles Comparison", style={"marginTop": "24px", "marginBottom": "4px"}),
            html.P("Sustainable BP varies by what you're building:", style={"color": COLORS["muted"], "fontSize": "13px"}),
            comparison_table,
        ])

    return app


# ---------------------------------------------------------------------------
# Tab Renderers
# ---------------------------------------------------------------------------

def _render_costs_tab(df: pd.DataFrame):
    """Plot 1: Metal cost (x) vs Energy cost (y) — scatter by faction.

    Enhanced with OLS regression, confidence band, marginal distributions,
    and annotation of key outliers.
    """
    # ---------- Primary scatter with marginals ----------
    fig = px.scatter(
        df,
        x="metalcost",
        y="energycost",
        color="faction",
        symbol="category",
        size="health",
        size_max=18,
        hover_name="label",
        hover_data={"metalcost": True, "energycost": True, "techlevel": True, "category": True, "buildtime": True},
        color_discrete_map={"ARMADA": COLORS["armada"], "CORTEX": COLORS["cortex"]},
        labels={"metalcost": "Metal Cost", "energycost": "Energy Cost", "faction": "Faction", "category": "Category"},
        marginal_x="histogram",
        marginal_y="histogram",
    )

    # --- OLS regression + 95% CI band ---
    cost_df = df[(df["metalcost"] > 0) & (df["energycost"] > 0)].copy()
    if len(cost_df) > 5:
        x_vals = cost_df["metalcost"].values
        y_vals = cost_df["energycost"].values
        slope, intercept, r_value, p_value, std_err = sp_stats.linregress(x_vals, y_vals)
        x_line = np.linspace(x_vals.min(), x_vals.max(), 200)
        y_line = slope * x_line + intercept

        # Prediction interval (95%)
        n = len(x_vals)
        x_mean = x_vals.mean()
        se = np.sqrt(np.sum((y_vals - slope * x_vals - intercept) ** 2) / (n - 2))
        t_crit = sp_stats.t.ppf(0.975, n - 2)
        h = 1 / n + (x_line - x_mean) ** 2 / np.sum((x_vals - x_mean) ** 2)
        ci_upper = y_line + t_crit * se * np.sqrt(h)
        ci_lower = y_line - t_crit * se * np.sqrt(h)

        fig.add_trace(go.Scatter(
            x=x_line, y=y_line, mode="lines",
            name=f"OLS (R²={r_value**2:.3f}, slope={slope:.1f})",
            line=dict(color="white", width=2, dash="dash"),
        ))
        fig.add_trace(go.Scatter(
            x=np.concatenate([x_line, x_line[::-1]]),
            y=np.concatenate([ci_upper, ci_lower[::-1]]),
            fill="toself", fillcolor="rgba(255,255,255,0.08)",
            line=dict(width=0), name="95% CI", showlegend=True, hoverinfo="skip",
        ))

    # --- Annotate outliers (top 3 most expensive) ---
    top3 = df.nlargest(3, "totalcost")
    for _, row in top3.iterrows():
        fig.add_annotation(
            x=row["metalcost"], y=row["energycost"],
            text=row["name"], showarrow=True, arrowhead=2,
            font=dict(size=10, color=COLORS["accent"]),
            arrowcolor=COLORS["accent"], ax=30, ay=-30,
        )

    fig.update_layout(
        template=PLOT_TEMPLATE,
        paper_bgcolor=COLORS["bg"],
        plot_bgcolor=COLORS["card"],
        title="Unit Costs: Metal vs Energy (with OLS regression & 95% CI)",
        height=700,
        legend=dict(orientation="h", y=-0.15),
    )

    # ---------- Cost distribution violin ----------
    cost_melt = df[df["metalcost"] > 0][["label", "faction", "category", "metalcost", "energycost"]].copy()

    fig_violin = make_subplots(rows=1, cols=2, subplot_titles=["Metal Cost Distribution", "Energy Cost Distribution"])
    for i, (col, color) in enumerate([("metalcost", COLORS["metal"]), ("energycost", COLORS["energy"])]):
        for faction in sorted(df["faction"].unique()):
            fdata = cost_melt[cost_melt["faction"] == faction][col]
            if fdata.empty:
                continue
            fig_violin.add_trace(go.Violin(
                y=fdata, name=f"{faction}", legendgroup=faction,
                fillcolor=COLORS["armada"] if "ARM" in faction else COLORS["cortex"],
                line_color=COLORS["armada"] if "ARM" in faction else COLORS["cortex"],
                opacity=0.6, box_visible=True, meanline_visible=True,
                showlegend=(i == 0),
            ), row=1, col=i + 1)

    fig_violin.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=350, violinmode="overlay",
    )

    # ---------- Summary statistics ----------
    stats_data = []
    for cat in sorted(df["category"].unique()):
        cdf = df[df["category"] == cat]
        if cdf["metalcost"].sum() == 0:
            continue
        stats_data.append({
            "Category": cat,
            "n": len(cdf),
            "Metal μ": f"{cdf['metalcost'].mean():.0f}",
            "Metal σ": f"{cdf['metalcost'].std():.0f}",
            "Metal Med": f"{cdf['metalcost'].median():.0f}",
            "Energy μ": f"{cdf['energycost'].mean():.0f}",
            "Energy σ": f"{cdf['energycost'].std():.0f}",
            "Energy Med": f"{cdf['energycost'].median():.0f}",
            "M/E Ratio μ": f"{cdf['me_ratio'].replace([np.inf, -np.inf], np.nan).mean():.4f}",
        })

    # Log scale toggle
    return html.Div([
        html.Div(
            style={"display": "flex", "gap": "16px", "marginBottom": "12px", "alignItems": "center"},
            children=[
                html.Label("Scale: ", style={"color": COLORS["muted"]}),
                dcc.RadioItems(
                    id="cost-scale",
                    options=[{"label": " Linear", "value": "linear"}, {"label": " Log", "value": "log"}],
                    value="linear",
                    inline=True,
                    inputStyle={"marginRight": "4px"},
                    style={"display": "flex", "gap": "16px"},
                ),
            ],
        ),
        dcc.Graph(id="cost-scatter", figure=fig, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_violin, config={"displayModeBar": True}),

        # Stats table
        html.Details(
            style={"marginTop": "12px"},
            children=[
                html.Summary("Descriptive Statistics by Category", style={"cursor": "pointer", "color": COLORS["accent"]}),
                dash_table.DataTable(
                    columns=[{"name": k, "id": k} for k in stats_data[0].keys()] if stats_data else [],
                    data=stats_data,
                    style_header={"backgroundColor": COLORS["card"], "color": COLORS["text"], "fontWeight": 600},
                    style_cell={"backgroundColor": COLORS["bg"], "color": COLORS["text"], "border": f"1px solid {COLORS['border']}", "fontSize": "12px", "padding": "6px 10px"},
                    sort_action="native",
                ),
            ],
        ),
        _card("Insight",
              f"OLS regression: Energy ≈ {slope:.1f} × Metal + {intercept:.0f} (R²={r_value**2:.3f}). "
              f"The regression slope ~{slope:.0f} means each additional metal costs ~{slope:.0f} energy on average. "
              f"BAR's canonical ratio is 1M=60E, but actual unit costs show varying ratios across categories." if len(cost_df) > 5 else
              "Each point is a unit. Size = health. Hover for details."),
    ])


def _render_ratios_tab(df: pd.DataFrame):
    """Plot 2: M/E ratio sorted by total resource cost (1M = 60E).

    Enhanced with category box-plots, mean/median reference lines, and
    coefficient of variation analysis.
    """
    sorted_df = df[df["energycost"] > 0].sort_values("totalcost").copy()
    sorted_df["rank"] = range(len(sorted_df))

    fig = make_subplots(
        rows=2, cols=1,
        subplot_titles=[
            "Metal/Energy Cost Ratio (sorted by total cost, 1M=60E)",
            "Stacked Cost Composition (sorted by total cost)",
        ],
        vertical_spacing=0.12,
        row_heights=[0.5, 0.5],
    )

    me_ratios = sorted_df["me_ratio"].replace([np.inf, -np.inf], np.nan).dropna()
    ratio_mean = me_ratios.mean()
    ratio_median = me_ratios.median()
    ratio_std = me_ratios.std()

    # Top: ratio bar chart
    fig.add_trace(go.Bar(
        x=sorted_df["label"],
        y=sorted_df["me_ratio"],
        marker_color=[COLORS["armada"] if f == "ARMADA" else COLORS["cortex"] for f in sorted_df["faction"]],
        hovertemplate="%{x}<br>M/E Ratio: %{y:.4f}<br>Total Cost: %{customdata:.0f}<extra></extra>",
        customdata=sorted_df["totalcost"],
        name="M/E Ratio",
    ), row=1, col=1)

    # Mean + ±1σ reference lines
    fig.add_hline(y=ratio_mean, line_dash="dash", line_color=COLORS["green"],
                  annotation_text=f"μ = {ratio_mean:.4f}", row=1, col=1)
    fig.add_hline(y=ratio_median, line_dash="dot", line_color=COLORS["orange"],
                  annotation_text=f"Med = {ratio_median:.4f}", row=1, col=1)
    fig.add_hline(y=ratio_mean + ratio_std, line_dash="dot", line_color="rgba(255,255,255,0.2)",
                  annotation_text=f"+1σ = {ratio_mean + ratio_std:.4f}", row=1, col=1)
    fig.add_hline(y=max(0, ratio_mean - ratio_std), line_dash="dot", line_color="rgba(255,255,255,0.2)",
                  annotation_text=f"-1σ = {max(0, ratio_mean - ratio_std):.4f}", row=1, col=1)

    # Bottom: stacked metal + energy (normalized)
    fig.add_trace(go.Bar(
        x=sorted_df["label"],
        y=sorted_df["metalcost"],
        name="Metal Cost",
        marker_color=COLORS["metal"],
        hovertemplate="%{x}<br>Metal: %{y:.0f}<extra></extra>",
    ), row=2, col=1)
    fig.add_trace(go.Bar(
        x=sorted_df["label"],
        y=sorted_df["energycost"] / METAL_ENERGY_RATIO,
        name="Energy Cost (÷60)",
        marker_color=COLORS["energy"],
        hovertemplate="%{x}<br>Energy (÷60): %{y:.0f}<extra></extra>",
    ), row=2, col=1)

    fig.update_layout(
        template=PLOT_TEMPLATE,
        paper_bgcolor=COLORS["bg"],
        plot_bgcolor=COLORS["card"],
        height=900,
        barmode="stack",
        showlegend=True,
        legend=dict(orientation="h", y=-0.05),
        xaxis=dict(showticklabels=False),
        xaxis2=dict(showticklabels=False),
    )

    # ---------- Box plot of M/E ratio by category ----------
    fig_box = go.Figure()
    for cat in sorted(sorted_df["category"].unique()):
        cdf = sorted_df[sorted_df["category"] == cat]
        fig_box.add_trace(go.Box(
            y=cdf["me_ratio"], name=cat, boxmean="sd",
            marker_color=COLORS["accent"],
            line_color=COLORS["accent"],
            hovertemplate="%{y:.4f}<extra>" + cat + "</extra>",
        ))
    fig_box.add_hline(y=1 / METAL_ENERGY_RATIO, line_dash="dash", line_color=COLORS["energy"],
                      annotation_text=f"1/60 = {1/METAL_ENERGY_RATIO:.4f} (parity)")
    fig_box.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=350, title="M/E Ratio Distribution by Category (diamond = mean, line = median)",
        yaxis_title="Metal / Energy Ratio",
    )

    # ---------- Coefficient of variation analysis ----------
    cv_data = []
    for cat in sorted(df["category"].unique()):
        cdf = df[df["category"] == cat]
        for col, label in [("metalcost", "Metal"), ("energycost", "Energy"), ("totalcost", "Total")]:
            vals = cdf[col]
            if vals.std() > 0 and vals.mean() > 0:
                cv_data.append({"Category": cat, "Resource": label,
                                "CV": vals.std() / vals.mean(), "n": len(cdf)})

    if cv_data:
        cv_df = pd.DataFrame(cv_data)
        fig_cv = px.bar(
            cv_df, x="Category", y="CV", color="Resource", barmode="group",
            color_discrete_map={"Metal": COLORS["metal"], "Energy": COLORS["energy"], "Total": COLORS["accent"]},
            title="Coefficient of Variation (σ/μ) — higher = more spread within category",
        )
        fig_cv.update_layout(
            template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
            height=300,
        )
    else:
        fig_cv = go.Figure()

    return html.Div([
        dcc.Graph(figure=fig, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_box, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_cv, config={"displayModeBar": True}),
        _card("Insight",
              f"M/E Ratio: μ={ratio_mean:.4f}, σ={ratio_std:.4f}, CV={ratio_std/ratio_mean:.2f}. "
              f"Median ({ratio_median:.4f}) < Mean indicates right-skew — a few units are disproportionately metal-heavy. "
              f"Category box plots reveal which unit types deviate most from the canonical 1:60 ratio."),
    ])


def _render_rates_tab(df: pd.DataFrame):
    """Plot 3: Metal/s and Energy/s considering buildtime (resource drain rate scatter).

    Enhanced with OLS regression, density contours, KDE marginals, percentile
    bands, and a category-level heatmap of drain characteristics.
    """
    build_df = df[df["buildtime"] > 0].copy()

    # ----- Scatter with regression + marginal KDE -----
    fig1 = px.scatter(
        build_df,
        x="metal_per_sec_per_bp",
        y="energy_per_sec_per_bp",
        color="faction",
        symbol="category",
        size="totalcost",
        size_max=18,
        hover_name="label",
        hover_data={
            "metal_per_sec_per_bp": ":.4f",
            "energy_per_sec_per_bp": ":.4f",
            "metalcost": True,
            "energycost": True,
            "buildtime": True,
        },
        color_discrete_map={"ARMADA": COLORS["armada"], "CORTEX": COLORS["cortex"]},
        labels={
            "metal_per_sec_per_bp": "Metal/s per BP",
            "energy_per_sec_per_bp": "Energy/s per BP",
        },
        marginal_x="violin",
        marginal_y="violin",
    )

    # OLS regression on drain rates
    if len(build_df) > 5:
        x_v = build_df["metal_per_sec_per_bp"].values
        y_v = build_df["energy_per_sec_per_bp"].values
        slope, intercept, r_val, p_val, std_err = sp_stats.linregress(x_v, y_v)
        x_fit = np.linspace(x_v.min(), x_v.max(), 100)
        y_fit = slope * x_fit + intercept

        fig1.add_trace(go.Scatter(
            x=x_fit, y=y_fit, mode="lines",
            name=f"OLS (E/s = {slope:.1f}·M/s + {intercept:.3f}, R²={r_val**2:.3f})",
            line=dict(color="white", width=2, dash="dash"),
        ))

        # Theoretical 1:60 line
        fig1.add_trace(go.Scatter(
            x=x_fit, y=x_fit * METAL_ENERGY_RATIO,
            mode="lines", name=f"Theoretical 1:{METAL_ENERGY_RATIO}",
            line=dict(color=COLORS["energy"], width=1, dash="dot"),
        ))

        # Percentile markers
        for pct, label, color in [(25, "P25", "#868e96"), (50, "P50", COLORS["orange"]), (75, "P75", "#868e96")]:
            m_p = np.percentile(x_v, pct)
            e_p = np.percentile(y_v, pct)
            fig1.add_trace(go.Scatter(
                x=[m_p], y=[e_p], mode="markers+text",
                text=[label], textposition="top center",
                marker=dict(size=12, color=color, symbol="diamond"),
                name=f"{label} ({m_p:.4f}, {e_p:.4f})",
                textfont=dict(color=color, size=10),
            ))

    fig1.update_layout(
        template=PLOT_TEMPLATE,
        paper_bgcolor=COLORS["bg"],
        plot_bgcolor=COLORS["card"],
        title="Resource Drain Rates with OLS Regression & Percentile Markers",
        height=650,
        legend=dict(orientation="h", y=-0.18, font=dict(size=10)),
    )

    # ----- Drain rate heatmap by category × tech level -----
    if len(build_df) > 0:
        heat_data = build_df.groupby(["category", "techlevel"]).agg(
            m_mean=("metal_per_sec_per_bp", "mean"),
            e_mean=("energy_per_sec_per_bp", "mean"),
            m_std=("metal_per_sec_per_bp", "std"),
            count=("metal_per_sec_per_bp", "count"),
        ).reset_index()

        cats = sorted(heat_data["category"].unique())
        techs = sorted(heat_data["techlevel"].unique())

        z_metal = []
        z_energy = []
        text_m = []
        text_e = []
        for cat in cats:
            row_m = []
            row_e = []
            txt_m = []
            txt_e = []
            for tech in techs:
                match = heat_data[(heat_data["category"] == cat) & (heat_data["techlevel"] == tech)]
                if not match.empty:
                    row_m.append(match["m_mean"].values[0])
                    row_e.append(match["e_mean"].values[0])
                    txt_m.append(f"{match['m_mean'].values[0]:.4f} (n={match['count'].values[0]})")
                    txt_e.append(f"{match['e_mean'].values[0]:.4f} (n={match['count'].values[0]})")
                else:
                    row_m.append(None)
                    row_e.append(None)
                    txt_m.append("")
                    txt_e.append("")
            z_metal.append(row_m)
            z_energy.append(row_e)
            text_m.append(txt_m)
            text_e.append(txt_e)

        fig_heat = make_subplots(rows=1, cols=2,
                                 subplot_titles=["Avg Metal/s per BP", "Avg Energy/s per BP"],
                                 horizontal_spacing=0.12)
        fig_heat.add_trace(go.Heatmap(
            z=z_metal, x=[f"T{t}" for t in techs], y=cats,
            text=text_m, texttemplate="%{text}", colorscale="Blues",
            colorbar=dict(title="M/s/BP", x=0.45),
        ), row=1, col=1)
        fig_heat.add_trace(go.Heatmap(
            z=z_energy, x=[f"T{t}" for t in techs], y=cats,
            text=text_e, texttemplate="%{text}", colorscale="YlOrRd",
            colorbar=dict(title="E/s/BP", x=1.02),
        ), row=1, col=2)
        fig_heat.update_layout(
            template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
            height=350, title="Drain Rate Heatmap: Category × Tech Level",
        )
    else:
        fig_heat = go.Figure()

    # Bar chart: Top 40 most expensive to build (rate-wise)
    top_drain = build_df.nlargest(40, "total_rate_per_bp").sort_values("total_rate_per_bp", ascending=True)
    fig2 = go.Figure()
    fig2.add_trace(go.Bar(
        y=top_drain["label"],
        x=top_drain["metal_per_sec_per_bp"],
        name="Metal/s per BP",
        orientation="h",
        marker_color=COLORS["metal"],
    ))
    fig2.add_trace(go.Bar(
        y=top_drain["label"],
        x=top_drain["energy_per_sec_per_bp"] / METAL_ENERGY_RATIO,
        name="Energy/s per BP (÷60)",
        orientation="h",
        marker_color=COLORS["energy"],
    ))

    # Add mean + median reference lines
    avg_total = build_df["total_rate_per_bp"].mean()
    med_total = build_df["total_rate_per_bp"].median()
    fig2.add_vline(x=avg_total, line_dash="dash", line_color=COLORS["green"],
                   annotation_text=f"μ={avg_total:.4f}")
    fig2.add_vline(x=med_total, line_dash="dot", line_color=COLORS["orange"],
                   annotation_text=f"Med={med_total:.4f}")

    fig2.update_layout(
        template=PLOT_TEMPLATE,
        paper_bgcolor=COLORS["bg"],
        plot_bgcolor=COLORS["card"],
        barmode="stack",
        title="Top 40 Highest Resource Drain per BP (with mean & median reference)",
        xaxis_title="Normalized rate (M-equivalent/s per BP)",
        height=800,
        legend=dict(orientation="h", y=-0.05),
    )

    # ----- Summary stats table -----
    drain_stats = []
    for cat in sorted(build_df["category"].unique()):
        cdf = build_df[build_df["category"] == cat]
        drain_stats.append({
            "Category": cat,
            "n": str(len(cdf)),
            "M/s/BP μ": f"{cdf['metal_per_sec_per_bp'].mean():.4f}",
            "M/s/BP σ": f"{cdf['metal_per_sec_per_bp'].std():.4f}",
            "M/s/BP P50": f"{cdf['metal_per_sec_per_bp'].median():.4f}",
            "E/s/BP μ": f"{cdf['energy_per_sec_per_bp'].mean():.4f}",
            "E/s/BP σ": f"{cdf['energy_per_sec_per_bp'].std():.4f}",
            "E/s/BP P50": f"{cdf['energy_per_sec_per_bp'].median():.4f}",
            "Actual M:E": f"1:{cdf['energy_per_sec_per_bp'].mean() / cdf['metal_per_sec_per_bp'].mean():.1f}" if cdf['metal_per_sec_per_bp'].mean() > 0 else "N/A",
        })

    return html.Div([
        dcc.Graph(figure=fig1, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_heat, config={"displayModeBar": True}),
        html.Hr(style={"borderColor": COLORS["border"], "margin": "24px 0"}),
        dcc.Graph(figure=fig2, config={"displayModeBar": True}),
        html.Details(
            style={"marginTop": "12px"},
            children=[
                html.Summary("Drain Rate Statistics by Category", style={"cursor": "pointer", "color": COLORS["accent"]}),
                dash_table.DataTable(
                    columns=[{"name": k, "id": k} for k in drain_stats[0].keys()] if drain_stats else [],
                    data=drain_stats,
                    style_header={"backgroundColor": COLORS["card"], "color": COLORS["text"], "fontWeight": 600},
                    style_cell={"backgroundColor": COLORS["bg"], "color": COLORS["text"], "border": f"1px solid {COLORS['border']}", "fontSize": "12px", "padding": "6px 10px"},
                    sort_action="native",
                ),
            ],
        ),
        _card("Insight",
              f"Drain rates show how hungry each unit is per buildpower. "
              f"OLS: E/s ≈ {slope:.1f}·M/s + {intercept:.3f} (R²={r_val**2:.3f}). "
              f"Theoretical 1:60 ratio is shown as dotted yellow line — actual drain ratios vary by category. "
              f"The heatmap reveals T2 units often have LOWER drain per BP (cost more but proportionally slower to build)." if len(build_df) > 5 else
              "These rates show how hungry each unit is to build."),
    ])


def _render_buildpower_tab(df: pd.DataFrame):
    """Plot 4: Resource consumption curves as buildpower scales — the core analysis.

    Uses the filtered dataset from global filters. Splits buildings into
    Economy, Defense, Factory, and Utility subcategories for deeper analysis.
    """
    build_df = df[df["buildtime"] > 0].copy()
    bp_range = list(range(50, 3001, 50))

    # ----- Classify units into meaningful groups -----
    buildings = build_df[build_df["category"] == "Building"]
    mobile = build_df[build_df["category"] != "Building"]

    # Building subcategories
    econ_bldg = buildings[buildings["is_econ"]]
    defense_bldg = buildings[buildings["is_combat"]]
    factory_bldg = buildings[buildings["is_constructor"]]
    utility_bldg = buildings[~buildings["is_econ"] & ~buildings["is_combat"] & ~buildings["is_constructor"]]

    subcats = {
        "Mobile: Bot": build_df[build_df["category"] == "Bot"],
        "Mobile: Vehicle": build_df[build_df["category"] == "Vehicle"],
        "Mobile: Aircraft": build_df[build_df["category"] == "Aircraft"],
        "Mobile: Ship": build_df[build_df["category"] == "Ship"],
        "Mobile: Hovercraft": build_df[build_df["category"] == "Hovercraft"],
        "Bldg: Economy": econ_bldg,
        "Bldg: Defense": defense_bldg,
        "Bldg: Factory": factory_bldg,
        "Bldg: Utility": utility_bldg,
    }

    subcat_colors = {
        "Mobile: Bot": "#74c0fc",
        "Mobile: Vehicle": "#63e6be",
        "Mobile: Aircraft": "#b197fc",
        "Mobile: Ship": "#a9e34b",
        "Mobile: Hovercraft": "#ffa94d",
        "Bldg: Economy": COLORS["energy"],
        "Bldg: Defense": "#ff6b6b",
        "Bldg: Factory": "#69db7c",
        "Bldg: Utility": "#868e96",
    }

    # ----- Figure 1: Drain curves by subcat -----
    fig1 = make_subplots(
        rows=1, cols=2,
        subplot_titles=["Metal Drain vs Buildpower", "Energy Drain vs Buildpower"],
        horizontal_spacing=0.08,
    )

    for cat_name, cat_df in subcats.items():
        if cat_df.empty:
            continue
        avg_m = cat_df["metal_per_sec_per_bp"].mean()
        avg_e = cat_df["energy_per_sec_per_bp"].mean()
        color = subcat_colors.get(cat_name, "#adb5bd")

        fig1.add_trace(go.Scatter(
            x=bp_range, y=[bp * avg_m for bp in bp_range],
            name=f"{cat_name} (n={len(cat_df)})", mode="lines",
            line=dict(color=color, width=2, dash="dash" if "Bldg" in cat_name else "solid"),
            hovertemplate=f"{cat_name}<br>BP: %{{x}}<br>M/s: %{{y:.1f}}<extra></extra>",
        ), row=1, col=1)
        fig1.add_trace(go.Scatter(
            x=bp_range, y=[bp * avg_e for bp in bp_range],
            name=f"{cat_name}", mode="lines", showlegend=False,
            line=dict(color=color, width=2, dash="dash" if "Bldg" in cat_name else "solid"),
            hovertemplate=f"{cat_name}<br>BP: %{{x}}<br>E/s: %{{y:.1f}}<extra></extra>",
        ), row=1, col=2)

    fig1.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=500, legend=dict(font=dict(size=10)),
        xaxis_title="Buildpower", xaxis2_title="Buildpower",
        yaxis_title="Metal/s", yaxis2_title="Energy/s",
    )

    # ----- Figure 2: Avg drain rate comparison bars -----
    bar_groups = [
        ("All Mobile", mobile),
        ("All Buildings", buildings),
        ("Bldg: Economy", econ_bldg),
        ("Bldg: Defense", defense_bldg),
        ("Bldg: Factory", factory_bldg),
        ("Bldg: Utility", utility_bldg),
    ]

    bar_labels = []
    bar_m_vals = []
    bar_e_vals = []
    bar_counts = []
    for lbl, bdf in bar_groups:
        if not bdf.empty:
            bar_labels.append(lbl)
            bar_m_vals.append(bdf["metal_per_sec_per_bp"].mean())
            bar_e_vals.append(bdf["energy_per_sec_per_bp"].mean())
            bar_counts.append(len(bdf))

    fig2 = go.Figure()
    fig2.add_trace(go.Bar(
        y=bar_labels, x=bar_m_vals, name="Metal/s/BP", orientation="h",
        marker_color=COLORS["metal"], text=[f"{v:.4f}" for v in bar_m_vals], textposition="auto",
    ))
    fig2.add_trace(go.Bar(
        y=bar_labels, x=[v / 60 for v in bar_e_vals], name="Energy/s/BP (÷60)", orientation="h",
        marker_color=COLORS["energy"], text=[f"{v:.4f}" for v in bar_e_vals], textposition="auto",
    ))
    fig2.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=300, barmode="group",
        title="Avg Resource Drain per BP — by Category (Energy scaled ÷60 for comparison)",
        xaxis_title="Rate per BP", margin=dict(l=120),
    )

    # ----- Figure 3: Nano turret rules of thumb -----
    NANO_BP = 200
    energy_sources = [
        ("Wind (10E)", 10),
        ("Solar (20E)", 20),
        ("Adv Solar (80E)", 80),
        ("Geo (300E)", 300),
        ("Fusion (750-850E)", 800),
        ("Adv Geo (1250E)", 1250),
        ("Adv Fusion (3000E)", 3000),
    ]

    # Compute for different building targets
    target_groups = [
        ("Building Economy", econ_bldg, COLORS["energy"]),
        ("Building Defense", defense_bldg, "#ff6b6b"),
        ("Building Factories", factory_bldg, "#69db7c"),
        ("Building Mobile Units", mobile, "#74c0fc"),
    ]

    fig3_rows = []
    nano_table_data = []

    for tgt_name, tgt_df, tgt_color in target_groups:
        if tgt_df.empty:
            continue
        avg_m = tgt_df["metal_per_sec_per_bp"].mean()
        avg_e = tgt_df["energy_per_sec_per_bp"].mean()

        for src_name, e_out in energy_sources:
            nanos = e_out / (NANO_BP * avg_e) if avg_e > 0 else 0
            metal_need = nanos * NANO_BP * avg_m
            nano_table_data.append({
                "target": tgt_name,
                "source": src_name,
                "energy_output": e_out,
                "nanos": round(nanos, 1),
                "bp_sustained": round(nanos * NANO_BP),
                "metal_needed": round(metal_need, 1),
                "e_drain_per_nano": round(NANO_BP * avg_e, 1),
                "m_drain_per_nano": round(NANO_BP * avg_m, 1),
            })

    nano_df = pd.DataFrame(nano_table_data)

    fig3 = go.Figure()
    for tgt_name, tgt_df, tgt_color in target_groups:
        if tgt_df.empty:
            continue
        subset = nano_df[nano_df["target"] == tgt_name]
        fig3.add_trace(go.Bar(
            x=subset["source"], y=subset["nanos"],
            name=tgt_name, marker_color=tgt_color,
            text=[f"{v:.1f}" for v in subset["nanos"]], textposition="auto",
            hovertemplate="%{x}<br>" + tgt_name + "<br>Nanos: %{y:.1f}<br>BP: %{customdata[0]}<br>M/s needed: %{customdata[1]:.1f}<extra></extra>",
            customdata=list(zip(subset["bp_sustained"], subset["metal_needed"])),
        ))
    fig3.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=400, barmode="group",
        title="Nano Turrets (200 BP) Sustainable per Energy Building",
        xaxis_title="Energy Source", yaxis_title="# Nano Turrets",
    )

    # ----- Milestones -----
    milestones = [
        {"label": "Early T1 (5M, 100E)", "metal": 5, "energy": 100},
        {"label": "Mid T1 (15M, 400E)", "metal": 15, "energy": 400},
        {"label": "Late T1 (30M, 800E)", "metal": 30, "energy": 800},
        {"label": "Early T2 (50M, 2000E)", "metal": 50, "energy": 2000},
        {"label": "Mid T2 (100M, 5000E)", "metal": 100, "energy": 5000},
        {"label": "Late game (200M, 15000E)", "metal": 200, "energy": 15000},
    ]

    fig4 = go.Figure()
    for tgt_name, tgt_df, tgt_color in [
        ("Economy", econ_bldg, COLORS["energy"]),
        ("Defense", defense_bldg, "#ff6b6b"),
        ("Mobile", mobile, "#74c0fc"),
    ]:
        if tgt_df.empty:
            continue
        med_m = tgt_df["metal_per_sec_per_bp"].median()
        med_e = tgt_df["energy_per_sec_per_bp"].median()
        bps = []
        for ms in milestones:
            if med_m > 0 and med_e > 0:
                bps.append(min(ms["metal"] / med_m, ms["energy"] / med_e))
            else:
                bps.append(0)
        fig4.add_trace(go.Bar(
            x=[ms["label"] for ms in milestones], y=bps,
            name=f"Building {tgt_name}", marker_color=tgt_color,
            hovertemplate="%{x}<br>Max BP: %{y:.0f}<extra></extra>",
        ))
    fig4.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=400, barmode="group",
        title="Max Sustainable Buildpower at Economy Milestones (by target type)",
        xaxis_title="Economy Stage", yaxis_title="Sustainable BP",
    )

    # ----- Summary stats -----
    all_avg_m = build_df["metal_per_sec_per_bp"].mean()
    all_avg_e = build_df["energy_per_sec_per_bp"].mean()
    all_med_m = build_df["metal_per_sec_per_bp"].median()
    all_med_e = build_df["energy_per_sec_per_bp"].median()

    def _safe_ratio(a, b):
        return f"1:{a / b:.1f}" if b > 0 else "N/A"

    # ----- Nano rule of thumb summary -----
    nano_rules = []
    for tgt_name, tgt_df, _ in target_groups:
        if tgt_df.empty:
            continue
        avg_e = tgt_df["energy_per_sec_per_bp"].mean()
        avg_m = tgt_df["metal_per_sec_per_bp"].mean()
        drain_e = NANO_BP * avg_e
        drain_m = NANO_BP * avg_m
        nano_rules.append(
            f"• {tgt_name}: Each nano drains ~{drain_m:.1f} M/s + {drain_e:.0f} E/s → "
            f"1 Fusion ({800}E) ≈ {800 / drain_e:.1f} nanos, "
            f"1 Adv Fusion (3000E) ≈ {3000 / drain_e:.0f} nanos"
        )

    return html.Div([
        html.H3("Buildpower Economics — Filtered Analysis", style={"marginBottom": "4px"}),
        html.P(
            "All data below uses the current global filters (faction, category, tech level). "
            "Buildings are split into Economy, Defense, Factory, and Utility subcategories.",
            style={"color": COLORS["muted"], "fontSize": "13px", "marginBottom": "16px"},
        ),

        # Drain curves
        dcc.Graph(figure=fig1, config={"displayModeBar": True}),

        # Avg drain comparison
        dcc.Graph(figure=fig2, config={"displayModeBar": True}),

        # Stat cards
        html.Div(
            style={"display": "grid", "gridTemplateColumns": "1fr 1fr 1fr 1fr", "gap": "12px", "margin": "16px 0"},
            children=[
                _stat_card("Avg M drain/BP", f"{all_avg_m:.4f}", "All filtered units"),
                _stat_card("Avg E drain/BP", f"{all_avg_e:.4f}", "All filtered units"),
                _stat_card("M:E Drain Ratio", _safe_ratio(all_avg_e, all_avg_m), "Energy per metal"),
                _stat_card("Filtered Units", f"{len(build_df)}", f"{len(mobile)} mobile, {len(buildings)} buildings"),
            ],
        ),

        # Nano rules
        html.H3("Nano Turret Rules of Thumb", style={"marginTop": "24px", "marginBottom": "4px"}),
        html.P(
            f"Each nano turret has {NANO_BP} BP. How many can each energy building sustain?",
            style={"color": COLORS["muted"], "fontSize": "13px", "marginBottom": "8px"},
        ),
        dcc.Graph(figure=fig3, config={"displayModeBar": True}),
        _card("Quick Reference — Nanos per Energy Building", "\n".join(nano_rules)),

        # Detailed nano table
        html.Details([
            html.Summary("Detailed Nano Sustainability Table", style={"cursor": "pointer", "color": COLORS["accent"], "marginTop": "8px"}),
            dash_table.DataTable(
                columns=[
                    {"name": "Building What", "id": "target"},
                    {"name": "Energy Source", "id": "source"},
                    {"name": "E Output", "id": "energy_output"},
                    {"name": "# Nanos", "id": "nanos"},
                    {"name": "BP Sustained", "id": "bp_sustained"},
                    {"name": "M/s Needed", "id": "metal_needed"},
                ],
                data=nano_table_data,
                style_header={"backgroundColor": COLORS["card"], "color": COLORS["text"], "fontWeight": 600},
                style_cell={"backgroundColor": COLORS["bg"], "color": COLORS["text"], "border": f"1px solid {COLORS['border']}", "fontSize": "12px"},
                style_data_conditional=[
                    {"if": {"filter_query": "{nanos} >= 1"}, "color": COLORS["green"]},
                ],
                page_size=30,
                sort_action="native",
                filter_action="native",
            ),
        ]),

        # Milestone zones
        html.H3("Sustainable BP at Economy Milestones", style={"marginTop": "24px", "marginBottom": "4px"}),
        dcc.Graph(figure=fig4, config={"displayModeBar": True}),

        # Key insight
        _card("Key Insight",
              f"On average, each point of buildpower drains {all_avg_m:.4f} M/s and {all_avg_e:.4f} E/s. "
              f"Buildings cost more per BP than mobile units (defense buildings are the most energy-hungry at ~1.0 E/s/BP). "
              f"1000 BP building mobile units needs ~{1000 * mobile['metal_per_sec_per_bp'].mean():.0f} M/s and "
              f"~{1000 * mobile['energy_per_sec_per_bp'].mean():.0f} E/s. "
              f"1000 BP building defenses needs ~{1000 * defense_bldg['metal_per_sec_per_bp'].mean():.0f} M/s and "
              f"~{1000 * defense_bldg['energy_per_sec_per_bp'].mean():.0f} E/s." if not defense_bldg.empty else
              f"On average, each point of buildpower drains {all_avg_m:.4f} M/s and {all_avg_e:.4f} E/s."),
    ])


def _render_calculator_tab(df: pd.DataFrame):
    """Interactive buildpower calculator — the core tool."""
    build_df = df[(df["buildtime"] > 0) & (df["metalcost"] > 0)].copy()
    unit_options = [
        {"label": f"{r['label']} [T{r['techlevel']}]", "value": r["id"]}
        for _, r in build_df.sort_values(["category", "name"]).iterrows()
    ]

    return html.Div([
        html.H3("Buildpower Economy Calculator", style={"marginBottom": "8px"}),
        html.P(
            "Set your economy, select units you're building, and see exactly how much buildpower you can sustain.",
            style={"color": COLORS["muted"], "marginBottom": "20px"},
        ),

        # Inputs row
        html.Div(
            style={"display": "flex", "gap": "24px", "flexWrap": "wrap", "marginBottom": "24px"},
            children=[
                _input_block("Metal Income (M/s)", dcc.Input(
                    id="calc-metal-income", type="number", value=20, min=0, step=1,
                    style=_input_style(),
                )),
                _input_block("Energy Income (E/s)", dcc.Input(
                    id="calc-energy-income", type="number", value=500, min=0, step=10,
                    style=_input_style(),
                )),
                _input_block("Buildpower Range", dcc.RangeSlider(
                    id="calc-buildpower-range",
                    min=0, max=5000, step=50,
                    value=[0, 2000],
                    marks={0: "0", 500: "500", 1000: "1K", 2000: "2K", 3000: "3K", 5000: "5K"},
                    tooltip={"placement": "bottom", "always_visible": False},
                )),
            ],
        ),

        # Unit selector
        html.Div(
            style={"marginBottom": "24px"},
            children=[
                html.Label("Select Units to Analyze:", style={"fontWeight": 600, "marginBottom": "8px", "display": "block"}),
                html.Div(
                    style={"display": "flex", "gap": "8px", "marginBottom": "8px"},
                    children=[
                        html.Button("All Constructors", id="btn-constructors",
                                    style=_btn_style(), n_clicks=0),
                        html.Button("All Factories", id="btn-factories",
                                    style=_btn_style(), n_clicks=0),
                        html.Button("T1 Combat", id="btn-t1-combat",
                                    style=_btn_style(), n_clicks=0),
                        html.Button("T2 Combat", id="btn-t2-combat",
                                    style=_btn_style(), n_clicks=0),
                    ],
                ),
                dcc.Dropdown(
                    id="calc-unit-select",
                    options=unit_options,
                    value=[],
                    multi=True,
                    placeholder="Search and select units...",
                    style={"backgroundColor": COLORS["card"]},
                ),
            ],
        ),

        # Output area
        html.Div(id="calc-output"),
    ])


def _render_recommender_tab(df: pd.DataFrame):
    """BP Recommender: input live economy stats → compute recommended buildpower and delta."""
    NANO_BP = 200

    build_df = df[df["buildtime"] > 0].copy()
    buildings = build_df[build_df["category"] == "Building"]
    mobile = build_df[build_df["category"] != "Building"]
    econ_bldg = buildings[buildings["is_econ"]]
    defense_bldg = buildings[buildings["is_combat"]]

    # Pre-compute drain rates for each target profile
    profiles = {}
    for name, sub_df in [
        ("Economy Buildings", econ_bldg),
        ("Defense Buildings", defense_bldg),
        ("Mobile Units", mobile),
        ("Mixed (All)", build_df),
    ]:
        if not sub_df.empty:
            profiles[name] = {
                "m_per_bp": sub_df["metal_per_sec_per_bp"].mean(),
                "e_per_bp": sub_df["energy_per_sec_per_bp"].mean(),
            }

    # Build the profile options
    profile_options = [{"label": k, "value": k} for k in profiles]

    return html.Div([
        html.H3("Live BP Recommender", style={"marginBottom": "4px"}),
        html.P(
            "Enter your current economy and active buildpower — see if you're under- or over-building. "
            "The recommender computes the maximum buildpower your economy can sustain based on what you're building.",
            style={"color": COLORS["muted"], "fontSize": "13px", "marginBottom": "20px"},
        ),

        # Inputs
        html.Div(
            style={"display": "flex", "gap": "20px", "flexWrap": "wrap", "marginBottom": "16px"},
            children=[
                _input_block("Metal Income (M/s)", dcc.Input(
                    id="rec-metal-income", type="number", value=30, min=0, step=1,
                    style=_input_style(),
                )),
                _input_block("Energy Income (E/s)", dcc.Input(
                    id="rec-energy-income", type="number", value=800, min=0, step=10,
                    style=_input_style(),
                )),
                _input_block("Metal Spend (non-BP M/s)", dcc.Input(
                    id="rec-metal-spend", type="number", value=0, min=0, step=1,
                    style=_input_style(),
                    placeholder="Other drains (units moving, etc.)",
                )),
                _input_block("Energy Spend (non-BP E/s)", dcc.Input(
                    id="rec-energy-spend", type="number", value=0, min=0, step=10,
                    style=_input_style(),
                    placeholder="Other drains (radar, shields, etc.)",
                )),
            ],
        ),
        html.Div(
            style={"display": "flex", "gap": "20px", "flexWrap": "wrap", "marginBottom": "24px"},
            children=[
                _input_block("Current Active BP", dcc.Input(
                    id="rec-current-bp", type="number", value=500, min=0, step=50,
                    style=_input_style(),
                )),
                _input_block("Building Profile", dcc.Dropdown(
                    id="rec-profile",
                    options=profile_options,
                    value="Mixed (All)" if "Mixed (All)" in profiles else (profile_options[0]["value"] if profile_options else None),
                    style={"backgroundColor": COLORS["card"], "minWidth": "220px"},
                )),
            ],
        ),

        # Output
        html.Div(id="rec-output"),

        # Reference cards
        html.Div(
            style={"marginTop": "20px"},
            children=[
                _card("How to Read This",
                      "Green delta → You can afford MORE buildpower (add constructors). "
                      "Red delta → You're over-saturated (some constructors are idle or stalling). "
                      "Metal is usually the bottleneck; energy is cheaper to scale."),
            ],
        ),
    ])


def _render_blueprint_nanos_tab(df: pd.DataFrame):
    """Blueprint Nanos: optimal nano turret count for key expensive structures.

    Computes how many nanos (200 BP each) to assign per structure at various
    economy stages, such that the build drain stays within a configurable
    fraction of total income. Metal is almost always the bottleneck.
    """
    NANO_BP = 200

    # Key structures by id
    KEY_STRUCTS = [
        ("armfus", "Fusion Reactor", "ARMADA"),
        ("corfus", "Fusion Reactor", "CORTEX"),
        ("armafus", "Adv Fusion Reactor", "ARMADA"),
        ("corafus", "Adv Fusion Reactor", "CORTEX"),
        ("armalab", "Adv Bot Lab", "ARMADA"),
        ("coralab", "Adv Bot Lab", "CORTEX"),
        ("armavp", "Adv Vehicle Plant", "ARMADA"),
        ("coravp", "Adv Vehicle Plant", "CORTEX"),
        ("armaap", "Adv Aircraft Plant", "ARMADA"),
        ("coraap", "Adv Aircraft Plant", "CORTEX"),
        ("armshltx", "Exp Gantry", "ARMADA"),
        ("corgant", "Exp Gantry", "CORTEX"),
    ]

    eco_stages = [
        ("Late T1", 30, 800),
        ("Early T2", 50, 2000),
        ("Mid T2", 80, 4000),
        ("Late T2", 120, 8000),
    ]

    BUDGET_FRAC = 0.50  # Default: spend 50% of income on construction

    # Build table data
    table_data = []
    struct_info = {}
    for uid, label, faction in KEY_STRUCTS:
        row = df[df["id"] == uid]
        if row.empty:
            continue
        r = row.iloc[0]
        mc, ec, bt = r["metalcost"], r["energycost"], r["buildtime"]
        if bt <= 0 or mc <= 0:
            continue

        struct_info[uid] = {"label": label, "faction": faction, "mc": mc, "ec": ec, "bt": bt}

        for eco_name, m_inc, e_inc in eco_stages:
            avail_m = m_inc * BUDGET_FRAC
            avail_e = e_inc * BUDGET_FRAC
            bp_m = bt * avail_m / mc
            bp_e = bt * avail_e / ec if ec > 0 else 99999
            max_bp = min(bp_m, bp_e)
            nanos = max(0, (max_bp - NANO_BP) / NANO_BP)  # subtract builder's own BP
            rec_nanos = max(0, round(nanos))
            total_bp = NANO_BP + rec_nanos * NANO_BP
            build_time = bt / total_bp
            m_drain = mc / build_time
            e_drain = ec / build_time
            bn = "Metal" if bp_m < bp_e else "Energy"

            table_data.append({
                "structure": f"{label} ({faction[:3]})",
                "uid": uid,
                "faction": faction,
                "eco_stage": eco_name,
                "m_income": m_inc,
                "e_income": e_inc,
                "rec_nanos": rec_nanos,
                "total_bp": total_bp,
                "build_time": round(build_time),
                "m_drain": round(m_drain, 1),
                "e_drain": round(e_drain),
                "m_pct": round(m_drain / m_inc * 100, 1),
                "bottleneck": bn,
            })

    if not table_data:
        return html.Div([html.P("No key structures found in filtered data.", style={"color": COLORS["muted"]})])

    tbl_df = pd.DataFrame(table_data)

    # ---------- Figure 1: Heatmap — recommended nanos per structure × eco stage ----------
    structs_ordered = []
    seen = set()
    for uid, label, faction in KEY_STRUCTS:
        key = f"{label} ({faction[:3]})"
        if key not in seen and uid in struct_info:
            structs_ordered.append(key)
            seen.add(key)

    eco_labels = [e[0] for e in eco_stages]
    z_nanos = []
    z_text = []
    for s in structs_ordered:
        row_z = []
        row_t = []
        for eco in eco_labels:
            match = tbl_df[(tbl_df["structure"] == s) & (tbl_df["eco_stage"] == eco)]
            if not match.empty:
                n = match.iloc[0]["rec_nanos"]
                t = match.iloc[0]["build_time"]
                row_z.append(n)
                row_t.append(f"{n}n ({t}s)")
            else:
                row_z.append(0)
                row_t.append("")
        z_nanos.append(row_z)
        z_text.append(row_t)

    fig_heat = go.Figure(go.Heatmap(
        z=z_nanos, x=eco_labels, y=structs_ordered,
        text=z_text, texttemplate="%{text}",
        colorscale=[[0, COLORS["bg"]], [0.3, "#1a5276"], [0.6, "#2471a3"], [1, "#5dade2"]],
        colorbar=dict(title="Nanos"),
        hovertemplate="%{y}<br>%{x}<br>Nanos: %{z}<extra></extra>",
    ))
    fig_heat.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=450, title="Blueprint Nanos: Recommended Nano Turrets per Structure × Economy Stage (50% budget)",
        yaxis=dict(autorange="reversed"),
    )

    # ---------- Figure 2: Build time curves at various nano counts ----------
    fig_curves = make_subplots(
        rows=2, cols=2,
        subplot_titles=["Fusion Reactor", "Adv Fusion Reactor", "Adv Lab/Plant", "Exp Gantry"],
        vertical_spacing=0.12, horizontal_spacing=0.08,
    )

    curve_groups = [
        (["armfus", "corfus"], 1, 1),
        (["armafus", "corafus"], 1, 2),
        (["armalab", "coralab", "armavp", "coravp", "armaap", "coraap"], 2, 1),
        (["armshltx", "corgant"], 2, 2),
    ]

    nano_range = list(range(0, 16))
    fac_colors = {"ARMADA": COLORS["armada"], "CORTEX": COLORS["cortex"]}

    for uids, row_idx, col_idx in curve_groups:
        for uid in uids:
            if uid not in struct_info:
                continue
            si = struct_info[uid]
            times = [si["bt"] / (NANO_BP + n * NANO_BP) for n in nano_range]
            m_drains = [si["mc"] / t for t in times]

            fig_curves.add_trace(go.Scatter(
                x=nano_range, y=times, mode="lines+markers",
                name=f"{si['label']} ({si['faction'][:3]})",
                line=dict(color=fac_colors.get(si["faction"], "#adb5bd"), width=2),
                marker=dict(size=4),
                hovertemplate=f"{si['label']} ({si['faction'][:3]})<br>"
                              "Nanos: %{x}<br>Time: %{y:.0f}s<br>"
                              f"M drain: %{{customdata:.1f}} M/s<extra></extra>",
                customdata=m_drains,
                showlegend=(row_idx == 1 and col_idx == 1),
            ), row=row_idx, col=col_idx)

        # Economy drain threshold lines
        for eco_name, m_inc, _ in eco_stages:
            fig_curves.add_hline(y=0, row=row_idx, col=col_idx)  # placeholder

    fig_curves.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=550, title="Build Time vs Nano Count (each nano = 200 BP assist)",
    )
    fig_curves.update_xaxes(title_text="# Nano Turrets", row=2)
    fig_curves.update_yaxes(title_text="Build Time (s)", col=1)

    # ---------- Figure 3: Metal drain % of income at each nano count ----------
    fig_drain = make_subplots(
        rows=1, cols=2,
        subplot_titles=["Metal Drain (% of income)", "Energy Drain (% of income)"],
        horizontal_spacing=0.08,
    )

    # Just do the most impactful structures
    highlight = ["armafus", "corafus", "armshltx", "corgant", "armfus", "corfus"]
    for uid in highlight:
        if uid not in struct_info:
            continue
        si = struct_info[uid]
        for eco_name, m_inc, e_inc in [("Mid T2", 80, 4000)]:
            m_pcts = [si["mc"] / (si["bt"] / (NANO_BP + n * NANO_BP)) / m_inc * 100 for n in nano_range]
            e_pcts = [si["ec"] / (si["bt"] / (NANO_BP + n * NANO_BP)) / e_inc * 100 for n in nano_range]

            fig_drain.add_trace(go.Scatter(
                x=nano_range, y=m_pcts, mode="lines",
                name=f"{si['label']} ({si['faction'][:3]})",
                line=dict(color=fac_colors.get(si["faction"], "#adb5bd"), width=2),
                hovertemplate=f"{si['label']}<br>Nanos: %{{x}}<br>M drain: %{{y:.1f}}%<extra></extra>",
            ), row=1, col=1)
            fig_drain.add_trace(go.Scatter(
                x=nano_range, y=e_pcts, mode="lines",
                name=f"{si['label']} ({si['faction'][:3]})",
                line=dict(color=fac_colors.get(si["faction"], "#adb5bd"), width=2, dash="dash"),
                showlegend=False,
                hovertemplate=f"{si['label']}<br>Nanos: %{{x}}<br>E drain: %{{y:.1f}}%<extra></extra>",
            ), row=1, col=2)

    # 50% budget line
    fig_drain.add_hline(y=50, line_dash="dash", line_color=COLORS["orange"],
                        annotation_text="50% budget", row=1, col=1)
    fig_drain.add_hline(y=50, line_dash="dash", line_color=COLORS["orange"],
                        annotation_text="50% budget", row=1, col=2)
    fig_drain.add_hline(y=100, line_dash="dot", line_color="#ff6b6b",
                        annotation_text="100% (stalling)", row=1, col=1)
    fig_drain.add_hline(y=100, line_dash="dot", line_color="#ff6b6b",
                        annotation_text="100% (stalling)", row=1, col=2)

    fig_drain.update_layout(
        template=PLOT_TEMPLATE, paper_bgcolor=COLORS["bg"], plot_bgcolor=COLORS["card"],
        height=400, title="Build Drain as % of Mid T2 Economy (80M, 4000E) vs Nano Count",
    )
    fig_drain.update_xaxes(title_text="# Nano Turrets")
    fig_drain.update_yaxes(title_text="% of Income")

    # ---------- Quick reference card ----------
    ref_lines = ["**Blueprint Defaults (50% economy budget @ each stage):**", ""]
    ref_lines.append(f"{'Structure':<30} {'Late T1':>8} {'Early T2':>9} {'Mid T2':>8} {'Late T2':>8}")
    for s in structs_ordered:
        line = f"{s:<30}"
        for eco in eco_labels:
            match = tbl_df[(tbl_df["structure"] == s) & (tbl_df["eco_stage"] == eco)]
            if not match.empty:
                line += f" {match.iloc[0]['rec_nanos']:>7}n"
            else:
                line += f" {'?':>7}"
        ref_lines.append(line)

    # ---------- Detailed table ----------
    detail_cols = [
        {"name": "Structure", "id": "structure"},
        {"name": "Economy", "id": "eco_stage"},
        {"name": "Nanos", "id": "rec_nanos"},
        {"name": "Total BP", "id": "total_bp"},
        {"name": "Build Time", "id": "build_time"},
        {"name": "M/s Drain", "id": "m_drain"},
        {"name": "E/s Drain", "id": "e_drain"},
        {"name": "M% Income", "id": "m_pct"},
        {"name": "Bottleneck", "id": "bottleneck"},
    ]

    return html.Div([
        html.H3("Blueprint Nano Calculator", style={"marginBottom": "4px"}),
        html.P(
            "How many nano turrets (200 BP each) should your blueprint include for key expensive structures? "
            "Calculated so build drain stays within 50% of your income at each economy stage. Metal is almost always the bottleneck.",
            style={"color": COLORS["muted"], "fontSize": "13px", "marginBottom": "16px"},
        ),

        dcc.Graph(figure=fig_heat, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_curves, config={"displayModeBar": True}),
        dcc.Graph(figure=fig_drain, config={"displayModeBar": True}),

        html.Pre(
            "\n".join(ref_lines),
            style={"backgroundColor": COLORS["card"], "padding": "16px", "borderRadius": "8px",
                   "fontSize": "13px", "fontFamily": "monospace", "overflowX": "auto",
                   "border": f"1px solid {COLORS['border']}", "marginTop": "16px"},
        ),

        html.Details(
            style={"marginTop": "12px"},
            children=[
                html.Summary("Full Blueprint Data Table", style={"cursor": "pointer", "color": COLORS["accent"]}),
                dash_table.DataTable(
                    columns=detail_cols,
                    data=table_data,
                    style_header={"backgroundColor": COLORS["card"], "color": COLORS["text"], "fontWeight": 600},
                    style_cell={"backgroundColor": COLORS["bg"], "color": COLORS["text"],
                                "border": f"1px solid {COLORS['border']}", "fontSize": "12px", "padding": "6px 10px"},
                    style_data_conditional=[
                        {"if": {"filter_query": "{m_pct} > 50"}, "color": COLORS["orange"]},
                        {"if": {"filter_query": "{m_pct} > 80"}, "color": "#ff6b6b"},
                    ],
                    sort_action="native",
                    filter_action="native",
                    page_size=50,
                ),
            ],
        ),

        _card("Key Takeaway",
              "Metal is almost always the bottleneck for big structures. "
              "At Mid T2 (80M, 4000E): Fusion needs 2 nanos, Adv Fusion needs 5-6 nanos, "
              "Adv Labs/Plants need 1 nano, Exp Gantry needs 1 nano. "
              "Adding nanos beyond the 50% threshold causes stalling — the structure builds faster "
              "but you starve the rest of your economy. Scale nanos with economy, not ahead of it."),
    ])


def _render_table_tab(df: pd.DataFrame):
    """Raw data table with all unit stats."""
    display_cols = [
        "id", "name", "faction", "techlevel", "category",
        "metalcost", "energycost", "totalcost", "buildtime",
        "metalmake", "energymake", "buildpower", "speed", "health",
        "dps", "weaponrange",
        "metal_per_sec_per_bp", "energy_per_sec_per_bp",
    ]
    available = [c for c in display_cols if c in df.columns]

    return html.Div([
        html.H3("Full Unit Data Table", style={"marginBottom": "16px"}),
        dash_table.DataTable(
            data=df[available].round(4).to_dict("records"),
            columns=[{"name": c, "id": c} for c in available],
            filter_action="native",
            sort_action="native",
            sort_mode="multi",
            page_size=50,
            style_table={"overflowX": "auto"},
            style_header={
                "backgroundColor": COLORS["card"],
                "color": COLORS["text"],
                "fontWeight": 600,
                "borderBottom": f"2px solid {COLORS['border']}",
            },
            style_cell={
                "backgroundColor": COLORS["bg"],
                "color": COLORS["text"],
                "border": f"1px solid {COLORS['border']}",
                "padding": "8px 12px",
                "fontSize": "13px",
            },
            style_filter={
                "backgroundColor": COLORS["card"],
                "color": COLORS["text"],
            },
        ),
    ])


# ---------------------------------------------------------------------------
# Helper Components
# ---------------------------------------------------------------------------

def _filter_block(label, component):
    return html.Div([
        html.Label(label, style={"fontSize": "12px", "color": COLORS["muted"], "marginBottom": "4px", "display": "block"}),
        component,
    ])


def _input_block(label, component):
    return html.Div(
        style={"minWidth": "180px", "flex": "1"},
        children=[
            html.Label(label, style={"fontSize": "13px", "color": COLORS["muted"], "marginBottom": "4px", "display": "block"}),
            component,
        ],
    )


def _card(title, text):
    return html.Div(
        style={
            "backgroundColor": COLORS["card"],
            "border": f"1px solid {COLORS['border']}",
            "borderRadius": "8px",
            "padding": "16px",
            "marginTop": "16px",
        },
        children=[
            html.Strong(title, style={"color": COLORS["accent"]}),
            html.P(text, style={"color": COLORS["muted"], "margin": "8px 0 0 0", "fontSize": "14px"}),
        ],
    )


def _stat_card(label, value, sub):
    return html.Div(
        style={
            "backgroundColor": COLORS["card"],
            "border": f"1px solid {COLORS['border']}",
            "borderRadius": "8px",
            "padding": "16px",
            "textAlign": "center",
        },
        children=[
            html.Div(label, style={"color": COLORS["muted"], "fontSize": "12px"}),
            html.Div(value, style={"fontSize": "24px", "fontWeight": 700, "margin": "8px 0"}),
            html.Div(sub, style={"color": COLORS["muted"], "fontSize": "11px"}),
        ],
    )


def _tab_style():
    return {
        "backgroundColor": COLORS["bg"],
        "color": COLORS["muted"],
        "border": "none",
        "borderBottom": f"2px solid transparent",
        "padding": "12px 20px",
        "fontWeight": 500,
    }


def _tab_selected_style():
    return {
        "backgroundColor": COLORS["bg"],
        "color": COLORS["text"],
        "border": "none",
        "borderBottom": f"2px solid {COLORS['accent']}",
        "padding": "12px 20px",
        "fontWeight": 600,
    }


def _th_style():
    return {
        "padding": "8px 12px",
        "textAlign": "left",
        "borderBottom": f"2px solid {COLORS['border']}",
        "color": COLORS["muted"],
        "fontSize": "12px",
        "textTransform": "uppercase",
    }


def _input_style():
    return {
        "backgroundColor": COLORS["card"],
        "color": COLORS["text"],
        "border": f"1px solid {COLORS['border']}",
        "borderRadius": "4px",
        "padding": "8px 12px",
        "width": "100%",
    }


def _btn_style():
    return {
        "backgroundColor": COLORS["card"],
        "color": COLORS["text"],
        "border": f"1px solid {COLORS['border']}",
        "borderRadius": "4px",
        "padding": "6px 14px",
        "cursor": "pointer",
        "fontSize": "13px",
    }


# ---------------------------------------------------------------------------
# Quick-select button callbacks
# ---------------------------------------------------------------------------

def register_quick_select_callbacks(app, df):
    """Register callbacks for the quick-select buttons in the calculator."""

    @app.callback(
        Output("calc-unit-select", "value"),
        [
            Input("btn-constructors", "n_clicks"),
            Input("btn-factories", "n_clicks"),
            Input("btn-t1-combat", "n_clicks"),
            Input("btn-t2-combat", "n_clicks"),
        ],
        [State("calc-unit-select", "value")],
        prevent_initial_call=True,
    )
    def quick_select(n_con, n_fac, n_t1, n_t2, current):
        from dash import ctx
        triggered = ctx.triggered_id

        build_df = df[(df["buildtime"] > 0) & (df["metalcost"] > 0)]

        if triggered == "btn-constructors":
            return list(build_df[build_df["is_constructor"] & ~build_df["category"].isin(["Building"])]["id"])
        elif triggered == "btn-factories":
            return list(build_df[build_df["is_constructor"] & (build_df["category"] == "Building")]["id"])
        elif triggered == "btn-t1-combat":
            return list(build_df[(build_df["is_combat"]) & (build_df["techlevel"] == 1)]["id"][:15])
        elif triggered == "btn-t2-combat":
            return list(build_df[(build_df["is_combat"]) & (build_df["techlevel"] == 2)]["id"][:15])
        return current or []


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(port: int = 8050, debug: bool = False):
    df = load_unit_data()
    app = create_app(df)
    register_quick_select_callbacks(app, df)
    print(f"\n  BAR Unit Economics Dashboard")
    print(f"  http://localhost:{port}\n")
    app.run(debug=debug, port=port)


if __name__ == "__main__":
    main()
