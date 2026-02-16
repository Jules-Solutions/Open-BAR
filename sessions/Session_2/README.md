# The BARB Quest — Session 2

## Quest Origin
- **Given by:** Felenious ([SMRT]Felnious), lead AI developer of BARB
- **Channel:** BAR Discord AI development channel
- **Date:** February 2026
- **His words:** "Add building in blocks instead of spread areas — that's an issue we have where they waste space. I have an angelscript for that but it requires a lot of testing."

## Objective
Implement block-based building placement for the BARB AI to replace scattered/spread building placement. Buildings should be placed in organized clusters/modules instead of randomly in "safe" territory.

## Scope
- **Primary:** Modify Barb3 (modern AngelScript-based BARB AI) to place buildings in block formations
- **Secondary:** Research all relevant AI systems (STAI, BARb v2, Barb3, Blueprint API)
- **Stretch:** Integrate with TotallyLegal widget suite for visualization

## Tech Stack
- **AngelScript** (Barb3 scripting layer on top of CircuitAI C++ framework)
- **Lua** (STAI, BAR widgets, Blueprint system)
- **Python** (TotallyLegal simulation engine)
- **Spring RTS Engine** (game engine)

## Key People
| Name | Role | Context |
|------|------|---------|
| Felenious | BARB AI Lead Dev | Gave us the quest, 1600+ dev hours on BARB |
| Jules | Project Owner | Our side, building TotallyLegal widget suite |
| Arxam | AI Researcher | Working on unit efficiency equations |
| lamer | Contributor | CircuitAI/AngelScript expertise |

## Session Documents

### Root
| File | Description |
|------|-------------|
| [README.md](README.md) | This file — quest overview |
| [TODO.md](TODO.md) | Phased project todolist |
| [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) | Tracked unknowns |
| [Brainstorm.md](Brainstorm.md) | Jules's raw quest brainstorm |
| [Build Module Quest.md](Build%20Module%20Quest.md) | Technical spec for modular building |
| [Guide ideas.md](Guide%20ideas.md) | Outline for beginner guides |

### Summaries/
| File | Description |
|------|-------------|
| [Discord_AI_Chat_Summary.md](Summaries/Discord_AI_Chat_Summary.md) | Summary of 58 AI Discord messages (Dec 2025) |
| [Discord_Barb2_Testing_Summary.md](Summaries/Discord_Barb2_Testing_Summary.md) | Summary of 27 Barb 2.0 testing messages (Feb 2026) |

### Research/
| File | Description |
|------|-------------|
| [01_BAR_Architecture.md](Research/01_BAR_Architecture.md) | Spring RTS engine, widget/gadget system, AI interface |
| [02_AngelScript_Reference.md](Research/02_AngelScript_Reference.md) | AngelScript crash course + CircuitAI API |
| [03_STAI_Analysis.md](Research/03_STAI_Analysis.md) | STAI architecture deep dive |
| [04_BARBv2_vs_Barb3.md](Research/04_BARBv2_vs_Barb3.md) | Structural comparison of BARB versions |
| [05_Blueprint_API.md](Research/05_Blueprint_API.md) | BAR Blueprint system analysis |
| [06_Block_Map_System.md](Research/06_Block_Map_System.md) | block_map.json deep dive (KEY for quest) |
| [07_Building_Placement_Logic.md](Research/07_Building_Placement_Logic.md) | Cross-AI placement comparison |
| [08_Modular_Build_Design.md](Research/08_Modular_Build_Design.md) | Proposed block-based building design |

### Context/
| File | Description |
|------|-------------|
| [Key_File_Index.md](Context/Key_File_Index.md) | Quick reference to critical source files |

## Related Project Docs
- [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) — TotallyLegal five-system architecture
- [CHECKPOINT_2026-02-08.md](../../docs/CHECKPOINT_2026-02-08.md) — Deep analysis with STAI research
- [PLAN.md](../../docs/PLAN.md) — TotallyLegal roadmap (Phases 1-7)
- [BAR_STRATEGY.md](../../docs/BAR_STRATEGY.md) — Strategy framework

## External Resources
- [BARB Skirmish Repo](https://github.com/Felnious/Skirmish) — Felenious's AI repo
- [CircuitAI](https://github.com/rlcevg/CircuitAI) — C++ framework Barb3 is built on
- [Beyond All Reason](https://www.beyondallreason.info/) — The game
- [BAR GitHub](https://github.com/beyond-all-reason/Beyond-All-Reason) — Game source

## Status
**Phase: Research & Documentation (initializing)**
