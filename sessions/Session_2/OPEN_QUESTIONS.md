# BARB Quest - Open Questions

> **Purpose:** Tracks all unknowns and partially-answered questions for the BARB building placement quest.
>
> **Status Values:**
> - **Unknown** -- No answer yet, needs investigation or confirmation
> - **Partially Answered** -- We have leads or partial info but not full confidence
> - **Answered** -- Confirmed understanding, included in research reports
>
> **Update Policy:** This file is updated as research progresses, code is analyzed, or Felenious provides answers.
> Questions we specifically need to bring to Felenious are collected in the [Questions for Felenious](#questions-for-felenious) section at the bottom.
>
> **Last Updated:** 2026-02-13 (post-research sweep)

---

## AngelScript / CircuitAI Integration

| Question                                                                                          | Status             | Notes                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| How does CircuitAI's C++ code decide building placement before AngelScript gets involved?         | **Answered**       | C++ `CBuilderManager.DefaultMakeTask()` performs position search. Reads `block_map.json` for exclusion zone constraints, calls `Spring.TestBuildOrder` for final validation. AS decides WHAT and WHEN to build; C++ decides WHERE (unless AS overrides position via `Enqueue(SBuildTask)`). See Report 07 Section 3.                             |
| Can we override placement completely in AngelScript or does C++ always do final position finding? | **Answered**       | AS can specify target position via `SBuildTask.position`. C++ then finds the nearest valid position from that target using block_map constraints + TestBuildOrder. We control the *intent*; C++ does final validation/snapping. This is sufficient for our quest -- we compute desired block positions and let C++ validate them. See Report 07. |
| What is the `SBuildTask.shake` parameter?                                                         | **Answered**       | Position randomization radius. `shake = 0` means place at exact position; `shake = 256` is the default randomization. For block placement we want `shake = 0` to get precise positions. See Report 01 Section 7.                                                                                                                                 |
| How does `SBuildTask.spotId` / `pointId` work for mex placement?                                  | **Answered** | `TaskB::Spot()` is a separate constructor from `TaskB::Common()`, specifically for mex placement. Pass the metal spot ID so CircuitAI tracks which spots are claimed. `TaskB::Common()` sets `pointId = -1` (unused for non-mex buildings). BAR has a built-in resource spot finder at `common/upgets/api_resource_spot_finder.lua` (both widget and gadget versions). See task.as lines 86-99. |

---

## Block Map System

| Question | Status | Notes |
|----------|--------|-------|
| How does `block_map.json` actually prevent scattering? | **Answered** | **It does NOT prevent scattering.** Block_map is a purely negative constraint system -- it defines exclusion zones (what CANNOT overlap) but provides zero positive guidance on where things SHOULD go. Each building is placed independently. This is the root cause of the quest. We need to add positive guidance (templates/blocks) on top of existing negative constraints. See Report 06 Section 10 and Report 07 Section 6. |
| What does "yard" mean in `block_map.json`? | **Answered** | `block_size = size + yard`. Yard is extra spacing around the building footprint. Units: 1 = SQUARE_SIZE * 2 = 16 elmos. E.g., factory T1 has `"yard": [0, 30]` = 480 elmo clearance in front/back for rally path. |
| What do "ignore" and "not_ignore" do precisely? | **Answered** | `"ignore"` lists structure types whose exclusion zones this building can overlap with. `"not_ignore"` is the inverse -- only those listed types are respected. E.g., wind ignores `"engy_low"` so winds CAN be placed near other winds, but there's no mechanism to say they SHOULD cluster. |
| Is `block_map.json` shared between allyTeam AIs? | Partially Answered | The file is loaded per-AI-instance in `init.as` as part of the profile config array. It's faction-agnostic (shared categories, faction-specific instance mapping). Whether allied AIs share spatial state at runtime is still unknown. **Ask Felenious.** |

---

## Building Placement Algorithm

| Question                                                                  | Status       | Notes                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Where exactly in CircuitAI C++ is the position search implemented?        | Unknown      | Only `.dll` is included in the distribution, not C++ source. The open-source CircuitAI repo (rlcevg/CircuitAI on GitHub) may have it. Low priority -- we can work around it via AS position overrides.                                                                                                                  |
| Can we control placement direction/preference in AngelScript?             | **Answered** | Yes, via `SBuildTask.position` we specify exact target coordinates. No directional bias control in the API itself, but we compute positions ourselves in AS and pass them to `Enqueue()`. The build_chain system also supports directional offsets (`"front"`, `"back"`, `"left"`, `"right"`). See Report 06 Section 8. |
| How does STAI's `FindClosestBuildSite` differ from CircuitAI's algorithm? | **Answered** | STAI uses Lua spiral search with random starting angle, rectangle avoidance, and 5-layer validation. CircuitAI uses compiled C++ position search with block_map exclusion zones. Both are independent single-building placement -- neither does group planning. See Report 07 Sections 2-3.                             |
| Is there a maximum number of blocks/templates we can define?              | Unknown      | Need to test or ask Felenious. Relevant for scaling the system to all building types.                                                                                                                                                                                                                                   |

---

## BAR Game Grid

| Question | Status | Notes |
|----------|--------|-------|
| What is the exact game grid size buildings snap to? | **Answered** | SQUARE_SIZE = 8 elmos. Building grid = SQUARE_SIZE * 2 = 16 elmos. This is the unit used throughout block_map.json. Confirmed in `Prod/Skirmish/BARb/stable/script/define.as`: `const int SQUARE_SIZE = 8;` |
| What is SQUARE_SIZE in BAR? | **Answered** | 8 elmos. Same as standard Spring RTS. Block_map unit = SQUARE_SIZE * 2 = 16 elmos. |
| Can buildings be placed at any position or only grid-aligned? | **Answered** | Grid-aligned only. Spring's `Pos2BuildPos` snaps to the 16-elmo grid. Confirmed in STAI's `CanBuildHere` function which calls `Spring.Pos2BuildPos(unittype:ID(), x, y, z)` before `TestBuildOrder`. See Report 07 Section 2. |

---

## Multi-AI Coordination

| Question                                                 | Status  | Notes                                                                                                                                                                                          |
| -------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Can allied AIs share state about building zones?         | Unknown | Important for preventing overlapping bases and coordinating territory usage. **Ask Felenious.**                                                                                                |
| How do multiple AIs avoid building on top of each other? | Unknown | Does CircuitAI have built-in ally awareness, or do we need to handle this in AS? The engine's `TestBuildOrder` would reject overlapping buildings, but that's a last resort, not coordination. |

---

## Development Workflow

| Question                                                                 | Status             | Notes                                                                                                                                                                               |
| ------------------------------------------------------------------------ | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Do we need to recompile `SkirmishAI.dll` to change AngelScript behavior? | **Answered**       | No. AS files are loaded at runtime by the C++ engine. The DLL is the CircuitAI runtime; AS scripts are hot-loadable configuration. Just edit `.as` files and restart the match.     |
| Where do Barb3 AI logs appear?                                           | Partially Answered | `AiLog()` is a global function in AS (confirmed in angelscript-references.md). Spring writes to `infolog.txt` in the game data directory. Need to confirm AI-specific logs go there too or if there's a separate file. |
| How do we select a specific difficulty profile for testing?              | **Answered** | Profiles map to config folders: `experimental_balanced` (standard), `experimental_ThirtyBonus` (30% eco bonus), `experimental_FiftyBonus` (50%), `experimental_HundredBonus` (100%), `experimental_Suicidal`. Each has its own `init.as` that loads faction-specific configs. Legion support is conditional on `experimentallegionfaction` mod option. |
| What is the development loop for testing changes?                        | Partially Answered | Modify `.as` files, restart match (not full game restart -- AS is reloaded per match). No hot-reload during a running match confirmed. Exact workflow still needs testing.          |

---

## Quest Scope

| Question                                                                           | Status             | Notes                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Does Felenious want modifications to Barb3 directly or a separate module?          | Unknown            | His Discord message said "I have an angelscript for that" suggesting extending existing Barb3. Need explicit confirmation. **Ask Felenious.**                                             |
| What maps should we prioritize for testing?                                        | Partially Answered | Barb3 has 20 map configs. Smaller maps with clear land areas would be best for initial testing. No specific list given.                                                                   |
| Should block placement work for all factions or start with one?                    | Unknown            | Separate build chain configs exist for Armada, Cortex, and Legion. Block_map categories are faction-agnostic. Starting with Armada would be logical (most documented). **Ask Felenious.** |
| What counts as "done" for this quest?                                              | Unknown            | Need to clarify acceptance criteria with Felenious. Is it "buildings form tight blocks" or something more specific like "energy buildings cluster within X elmos"? **Ask Felenious.**     |
| Does Felenious have a branch or WIP code for block placement we should start from? | Unknown            | He mentioned having an AngelScript for it. Need to ask if there is existing code. **Ask Felenious.**                                                                                      |

---

## New Questions Discovered During Research

| Question                                                               | Status             | Notes                                                                                                                                                                                                                           |
| ---------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| What is C++ `DefaultMakeTask()`'s search algorithm? Spiral? Grid scan? | Unknown            | We only have the DLL, not the C++ source. Could check CircuitAI GitHub repo. Low priority since we can override positions from AS.                                                                                              |
| How does the `ignore` system interact with C++ placement at runtime?   | Partially Answered | C++ reads block_map.json at initialization and uses it during position search. The ignore rules allow overlapping exclusion zones between specified types. Exact algorithm unknown without C++ source.                          |
| Can AS create new building categories in block_map.json?               | Unknown            | Currently categories are fixed in the JSON. Need to know if C++ supports dynamic category registration or if we must work within existing categories.                                                                           |
| What happens when block_map yard is 0 and no explicit size?            | Partially Answered | The comment on wind says `// default: "explosion"` suggesting explosion radius is used as default spacer when yard is unset. Need to confirm.                                                                                   |
| How does block_map handle building facing/rotation?                    | Partially Answered | The offset comment says "South facing [left/right, front/back]". CircuitAI likely rotates the blocker based on build direction. Needs testing.                                                                                  |
| What is the maximum range for build_chain offsets?                     | Unknown            | Current configs use offsets up to 150 elmos. No documented limit.                                                                                                                                                               |
| Can build_chain trigger multiple chains from one building?             | **Answered**       | Yes -- the hub array can contain multiple chain arrays, each executed independently. E.g., armafus has one chain with nanos, converters, AND defence.                                                                           |
| How does Barb3 choose which builder handles a queued task?             | Partially Answered | `builder.as` has a promotion system and BuilderTaskTrack class. Builders are categorized by primary/secondary/tactical roles and assigned based on category (bot/veh/air/sea). Full assignment algorithm needs deeper analysis. |
| Does CircuitAI's position search consider terrain slope?               | Unknown            | Spring's `TestBuildOrder` validates terrain, but whether CircuitAI pre-filters by slope is unknown.                                                                                                                             |

---

## Questions for Felenious

These are the questions we need to bring to Felenious directly, either because only he can answer them or because it would save significant research time.

**Architecture and Control:**
1. Can we fully specify building position from AngelScript and have C++ honor it (within TestBuildOrder validity)? We believe yes via `Enqueue(SBuildTask)` -- please confirm.
2. ~~What does `SBuildTask.shake` actually do?~~ **ANSWERED:** Position randomization radius (0 = exact, 256 = default).
3. Is there a maximum number of block templates or building categories we can define?
4. Can we add new categories to `block_map.json` or are they hardcoded in the C++ side?

**Block Map and Coordination:**
5. Is block_map spatial state shared between allied AIs on the same team?
6. How do multiple BARB AIs on the same team currently avoid building on top of each other?

**Development:**
7. Where do Barb3 AI logs appear? What is the recommended way to debug AS scripts?
8. What is the fastest dev loop? Modify `.as` file, restart match -- anything faster?
9. Which difficulty profile (config folder) is best for testing building placement?

**Quest Scope:**
10. Should we modify Barb3 directly or build a separate module?
11. Should we start with one faction (Armada?) or target all three from the start?
12. Do you have a branch or WIP AngelScript code for block placement we should build on?
13. What does "done" look like for this quest? What are the acceptance criteria?
14. Which maps should we prioritize for testing?

---

## Summary of Research Progress

**Answered during this research run (14 questions):**
- CircuitAI placement architecture (C++ does position search, AS can override)
- AngelScript override capability (yes, via SBuildTask.position + Enqueue)
- Why block_map doesn't prevent scattering (negative-only constraints)
- Yard meaning (block_size = size + yard, 1 unit = 16 elmos)
- Ignore/not_ignore semantics (overlap permission lists)
- Placement direction control (AS computes positions, build_chain has directional offsets)
- STAI vs CircuitAI differences (Lua spiral vs C++ block_map, both single-building)
- Game grid size (SQUARE_SIZE = 8 elmos, building grid = 16 elmos)
- SQUARE_SIZE value (8 elmos, confirmed in define.as)
- Grid-alignment (yes, Pos2BuildPos snaps to 16-elmo grid)
- No DLL recompilation needed (AS is hot-loadable)
- SBuildTask.shake parameter (0 = exact position, 256 = default randomization)
- Build_chain can trigger multiple chains (yes, hub array supports it)
- Root cause of scattering (no group planning, spiral pushes outward, negative-only constraints, reactive adjacency)

**Still need Felenious for (14 questions):**
See [Questions for Felenious](#questions-for-felenious) above.

**New questions discovered (9):**
See [New Questions Discovered During Research](#new-questions-discovered-during-research) above.
