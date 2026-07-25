# BAR Sim — Feature Roadmap & Ideas

> **Created:** 2026-03-03  
> **Status:** Living document — captures future features, open questions, and design ideas

---

## Completed

### Dashboard v1 (Session baseline)
- [x] 6-tab interactive Plotly Dash dashboard
- [x] Global filters (faction, category, tech, flags)
- [x] Cost Analysis, Resource Ratios, Build Rates, Buildpower Economics, Calculator, Unit Table

### Dashboard v2 (Current session enhancements)
- [x] Buildpower Economics: split mobile vs buildings, subcategories (econ/defense/factory/utility)
- [x] Nano turret rules of thumb: nanos-per-energy-building chart + table
- [x] BP Recommender tab: live economy → recommended BP → delta
- [x] Blueprint Nanos tab: optimal nano count per key structure per economy stage
- [x] Statistical overlays: OLS regression + 95% CI, marginal distributions, violin plots
- [x] Heatmaps: drain rate Category × Tech Level, blueprint nanos Structure × Economy
- [x] Descriptive statistics tables (μ, σ, median, CV) on every tab
- [x] Percentile markers, ±1σ bands, mean/median reference lines throughout

---

## Next Up (Incremental)

### Dashboard v3 — Polish & Interactive
- [ ] **Budget slider on Blueprint Nanos tab** — let user set 25%/50%/75% budget fraction interactively
- [ ] **Custom economy inputs on Blueprint tab** — type your exact M/s and E/s instead of preset stages
- [ ] **Unit comparison mode** — select 2-5 units side by side with radar/spider chart
- [ ] **Cost efficiency scatter** — DPS/cost, health/cost, speed/cost as separate analysis
- [ ] **Build order simulator** — timeline view: "if I build X then Y, what does my economy curve look like"
- [ ] **Faction parity analysis** — systematic ARM vs COR comparison with statistical tests (t-test, Mann-Whitney)

### Data Quality
- [ ] **Validate unitlist.csv** against game source — are all 377 units current?
- [ ] **Add missing unit properties** — armor type, weapon type, AOE radius, reload time
- [ ] **Historical data** — track balance patches, compare unit stats across versions

---

## Big Feature: Claude Code as Live Game Coach

### Vision
Use Claude Code as a real-time BAR game coach that reads game state and provides data-driven recommendations via voice output.

### Architecture Concept
```
BAR Game → Game Logs/API → Parser → Claude Code Agent
                                         ↓
                                    Analysis Engine
                                         ↓
                                    Voice TTS Output → Player
```

### Core Capabilities
1. **Economy monitoring** — detect stalls before they happen
   - "Your metal income can't sustain 3 more nanos. Pause unit production for 30s to unlock fusion first."
   - "You're floating 200 E/s. Add a nano turret or expand."

2. **Build order guidance** — situational suggestions
   - "At 8 min with 2 factories and 20M/s, you should be teching to T2 now."
   - "Your opponent has 3x your unit count. Shift to defense and turtle until adv fusion is up."

3. **Prediction models** — project future economy states
   - "If you build adv fusion now (5 nanos, 242s), you'll have +3000 E/s by minute 12."
   - "At current expansion rate, you'll hit metal bottleneck in 90 seconds."

4. **Opponent modeling** — analyze visible enemy actions
   - "Enemy is massing T1 bots. Counter with: LLT line + PW behind."
   - "Scouted 2 adv air plants — expect strategic bombers in ~3 minutes."

5. **Post-game analysis** — review and learn
   - Track key decision points, missed opportunities, economy curves
   - Compare against known build orders and templates

### Implementation Phases

**Phase 0: Data Foundation (current)**
- Dashboard with all unit economics ✅
- Blueprint nano recommendations ✅
- BP recommender ✅

**Phase 1: Game Log Reader**
- Parse BAR replay files / infolog.txt for economy snapshots
- Extract: time, metal income/spend/stored, energy income/spend/stored, unit count, buildpower
- Display economy timeline in dashboard

**Phase 2: Post-Game Coach**
- Feed replay data through analysis pipeline
- Identify decision points: "At 5:30 you had 50M floating — should have started nano earlier"
- Compare actual vs optimal economy curves

**Phase 3: Live Integration**
- Read game state in real-time (file watch on game logs or memory)
- Push recommendations through Claude Code
- Rate-limit suggestions to avoid spam (1 per 30s, prioritized)

**Phase 4: Voice Output**
- TTS integration (system TTS or API)
- Claude Code generates text → TTS speaks it
- Priority system: critical warnings spoken, info suggestions queued

**Phase 5: Strategy Templates**
- Pre-built build orders with decision trees
- "Rush" vs "Boom" vs "Tech" templates
- Adaptive: "You deviated from Rush at 4:00 — adapting to hybrid strategy"

**Phase 6: Performance Tracking**
- Persist game results (win/loss, economy peaks, timing milestones)
- Track improvement over time
- Skill assessment: "Your early game economy is top 20%, but you consistently stall at T2 transition"

### Open Questions to Unblock

1. **Game log access:** Does BAR write economy snapshots to a log file during gameplay? What format? Where?
   - Check: `infolog.txt`, `replay.sdfz` files, or widget data output
   - Is there a Lua widget that can dump economy state to a file in real-time?

2. **Real-time vs replay:** Should Phase 1 target live games or replay analysis first?
   - Replay is safer / easier to develop against
   - Live is more exciting but needs file-watching and low latency

3. **Voice TTS:** What TTS solution?
   - System TTS (free, offline) — `pyttsx3` on Windows, `say` on Mac
   - Cloud TTS (better quality) — Google Cloud TTS, ElevenLabs
   - Does Claude Code have a native way to play audio?

4. **Game API:** Does BAR have any external API or mod support for data export?
   - Custom Lua widget that writes JSON to a known path every N seconds?
   - BAR lobby API for match history?

5. **Strategy templates:** Where to source build orders?
   - Community guides on BAR Discord / forums
   - Watch pro replays and extract timings
   - Manual encoding by Jules

6. **Opponent data:** How much enemy info is visible in replays/logs?
   - Fog of war: limited to scouted info in live games
   - Full visibility in replays

7. **Performance baseline:** What metrics define "good" play at different skill levels?
   - Metal income at 5/10/15 min for bronze/silver/gold/diamond
   - Unit count / army value curves
   - Need community benchmarks

---

## Other Ideas

### Blueprint Library
- Store and share optimized blueprints with nano placement
- "Community-approved T2 rush blueprint: 1 adv lab + 3 nanos + 2 fusion"

### Economy Optimization Solver
- Given target: "I want to build Adv Fusion in under 3 minutes"
- Solver: "You need at minimum 60 M/s and 800 E/s. Current gap: +30M, +200E. Build 2 solar + 1 mex first."

### Unit Composition Advisor
- "What's the most cost-efficient counter to mass T1 bots?"
- Use DPS/cost and armor-type-effectiveness data

### Map-Aware Analysis
- Different maps have different mex spots, topology, expansion patterns
- "On this map, your 3rd expansion should be at position X, not Y"

---

*This file is maintained by the orchestrator agent. Jules: answer the open questions above to unblock the next phases.*
