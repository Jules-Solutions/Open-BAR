# BARB Quest — TODO

## Phase 0: Research & Documentation [CURRENT]
- [x] Create quest folder structure (sessions/Session_2/)
- [x] Create README.md (quest overview)
- [x] Create OPEN_QUESTIONS.md
- [x] Create Context/Key_File_Index.md
- [x] Summarize Discord AI chat history
- [x] Summarize Discord Barb 2.0 testing history
- [x] Research Report 01: BAR Architecture
- [x] Research Report 02: AngelScript Reference
- [x] Research Report 03: STAI Analysis
- [x] Research Report 04: BARBv2 vs Barb3 Comparison
- [x] Research Report 05: Blueprint API
- [x] Research Report 06: Block Map System Deep Dive
- [ ] Research Report 07: Building Placement Logic (cross-AI synthesis)
- [ ] Research Report 08: Modular Build Design Proposal
- [ ] Update OPEN_QUESTIONS.md with research findings
- [ ] Review all reports for completeness

## Phase 1: Development Environment Setup
- [ ] Verify BAR game launches in dev/debug mode
- [ ] Load Barb3 AI in a skirmish game (select experimental_balanced profile)
- [ ] Locate AI log output (where does AiLog write to?)
- [ ] Set up AngelScript editing in IDE (syntax highlighting, file associations)
- [ ] Run a test game and observe current building placement behavior
- [ ] Take screenshots of current scattered placement for "before" comparison
- [ ] Document the dev loop: modify .as → restart AI → observe → iterate
- [ ] Create a test skirmish scenario (specific map, specific AI settings)
- [ ] Write SETUP.md documenting the full dev environment

## Phase 2: Prototype Block Placement (MVP)
- [ ] Define WindBlock template data structure in AngelScript
- [ ] Implement block seed point selection (near factories/existing energy)
- [ ] Implement slot position calculation (grid math with rotation)
- [ ] Implement slot validation (TestBuildOrder + block_map checks)
- [ ] Hook into Barb3: override DefaultMakeTask for wind turbines only
- [ ] Use aiBuilderMgr.Enqueue(SBuildTask) with calculated positions
- [ ] Test: wind turbines should form a grid instead of scattering
- [ ] Take "after" screenshots for comparison
- [ ] Fix any issues (terrain problems, validation failures)
- [ ] Show results to Felenious for early feedback

## Phase 3: Template Library & Config System
- [ ] Move template definitions to JSON config (new block_templates.json)
- [ ] Add solar_block template (3x3 grid of solar panels)
- [ ] Add factory_cluster template (factory + nanos + defense)
- [ ] Add fusion_block template (fusion + nanos + converters ring)
- [ ] Add defense_line template (row of turrets along perimeter)
- [ ] Implement block state tracking (BlockInstance, BlockSlot classes)
- [ ] Implement "fill existing block before starting new" logic
- [ ] Implement block rotation based on available space
- [ ] Integrate with build_chain.json (block triggers on building completion)
- [ ] Per-role block priorities (TECH prioritizes energy blocks, etc.)

## Phase 4: Full System Integration
- [ ] Cover all building categories with templates
- [ ] Integrate with zone system (building zone, defense perimeter)
- [ ] Handle factory exit lane protection
- [ ] Handle explosion radius safety buffers
- [ ] Per-map configuration support (different block sizes for different maps)
- [ ] Edge case: island maps, tight spaces, water-adjacent bases
- [ ] Edge case: partially destroyed blocks (rebuild vs start new?)
- [ ] Opening → mid-game transition (when do blocks start?)

## Phase 5: Multi-Faction & Testing
- [ ] Configure all templates for Armada, Cortex, Legion
- [ ] Test on 5+ different maps (varied terrain)
- [ ] Test all difficulty profiles
- [ ] Performance profiling (no frame drops from placement calculations)
- [ ] Compare building quality: block placement vs default scattered
- [ ] Collect feedback from BAR community testers
- [ ] Address feedback and iterate

## Phase 6: PR & Delivery
- [ ] Clean up code for PR submission
- [ ] Write documentation for the block system
- [ ] Take before/after screenshots for PR description
- [ ] Ensure backward compatibility with existing config
- [ ] Submit PR to Felenious's Skirmish repo
- [ ] Address code review feedback
- [ ] Final testing after review changes

## Stretch Goals
- [ ] Reclaim-aware placement (detect metal wreckage, build around it)
- [ ] Dynamic block resizing based on available space
- [ ] Learning from player blueprints (parse popular layouts)
- [ ] Commander landing zone optimization
- [ ] Multi-AI coordination (share building zones between allied AIs)
- [ ] Connect to TotallyLegal simulation engine for optimal block parameters
- [ ] Web dashboard showing block placement stats

## Active Questions (Quick Reference)
See OPEN_QUESTIONS.md for full tracking. Key blockers:
- Where do AI logs appear? (Need for Phase 1)
- Can we fully override placement in AngelScript? (Need for Phase 2)
- Does Felenious want modifications to Barb3 directly? (Need for Phase 2)
- What maps should we prioritize? (Need for Phase 5)

---
*Last updated: 2026-02-13*
*Quest given by: Felenious ([SMRT]Felnious), BAR AI Lead Developer*
