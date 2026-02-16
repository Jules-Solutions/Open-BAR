# Discord Message Drafts — Session 2

> **Date:** 2026-02-16
> **Purpose:** Draft messages for Jules to review, edit, and send
> **Status:** DRAFT — Do not send without Jules's review

---

## 1. DM to Felenious — Block Placement Questions

> Context: We've been deep-diving into the codebase for a few days. These are the remaining blockers before we start writing code.

---

Heey Felenious, I've been going through the Barb3 codebase and I think I have a solid understanding of the architecture now. block_map.json, build_chain, the AngelScript layer, how Enqueue(SBuildTask) works.

Before I start writing code for the block placement system, I have a few questions:

**Quick confirms:**
1. Can I fully control building position via `Enqueue(SBuildTask)` with `shake = 0`? I'm planning to compute block positions in AS and pass exact coordinates to the C++ side. The C++ does final validation via TestBuildOrder, is that right?
2. Can I add new categories to `block_map.json` or are the categories hardcoded on the C++ side?

**Dev setup:**
3. Which difficulty profile is best for testing building placement? I'm guessing `experimental_balanced`?

**Scope:**
4. Do you have a branch or WIP AngelScript code for the block building stuff you mentioned? You said "I have an angelscript for that", would save me a lot of time if I could build on top of existing work.
5. Should I modify Barb3 directly or build it as a separate module?
6. I'm planning to start with Armada, then port to all factions since block_map categories are faction-agnostic. Sound right?

No rush, whenever you have a minute. I'm going to start prototyping in the meantime.

---

## 2. Response to Group Chat (AI Discord)

> Context: Responding to the full conversation (Feb 12 - Feb 15). Addresses MrDeadKingz, RobotRobert03, Noodles, ACowAdonis, TheBlindjin, and Felenious. Jules wants to engage both sides of the ML debate, offer concrete value, and position himself as the bridge.

---

Hey everyone, I've been quietly heads-down in the Barb3 codebase for the past few days working on the block placement quest Felenious gave me. Mapped out the full architecture — block_map.json, build_chain, AngelScript layer, how the C++ placement works. Going to start prototyping soon.

But this conversation is exactly what I was hoping would happen so let me jump in.

**@ACowAdonis** Your point about replays vs simulation is the most important one in this thread. You're right — the replay file is just timestamped commands. "Move here, build this." It doesn't tell you what happened between those commands. Did the units fight? Did the eco stall? Was the timing good or did the player panic-build? The simulation creates the meaning, the replay is just the input log.

That said, I think there's a middle path. We don't NEED the full simulation state from replays if we use them for the right things. Build order timing, factory sequences, eco curves — those are extractable from command logs alone because they're player decisions, not simulation outcomes. "Player built their 2nd factory at frame 2700" is useful data even without knowing what happened to their army.

For the stuff that DOES need simulation awareness (micro decisions, army positioning, combat timing) — that's where self-play shines. Generate your own data with full state access.

**@Noodles** The LLM-on-commands idea is interesting and I'd love to dig into it with you. A few thoughts:

1. The tokenization problem is real but solvable. BAR commands are structured (unitID + commandType + params), not freeform text. Should map cleanly to a finite vocabulary.
2. Conditioning on vision is the hard part. The command stream alone is missing too much context (as ACowAdonis pointed out). But BAR's engine gives us something better than video we can extract structured game state directly (unit positions, resource levels, threat maps, visibility). That's way more information-dense than pixels.
3. Your compartmentalized ML idea (use AI to decide what to build, where to deploy, whether to push/hold/raid) maps almost perfectly to what I'm working towards. The rule system handles execution, ML handles strategy selection.

Also, you mentioned you have access to an HPC cluster. That could be the key bottleneck solver if headless BAR runs fast enough.

**@TheBlindjin** Great question about headless BAR speed — that's the make-or-break for any training approach. Spring engine supports headless mode up to 999x speed since there's no rendering bottleneck. If we can get a 10-minute game running in under a second, we're looking at thousands of games per hour on a single machine (CPU-bound, but still massive). Haven't benchmarked it yet but that's on my list. Will report back.

**@MrDeadKingz** Re: eco reclaim — dug into this more. The block_map system has zero positive placement guidance, just exclusion zones. Every building placed independently with 256-elmo randomization. That's why it scatters. The block system I'm building fixes this with compact modules. Your idea about reclaiming low-tier eco when upgrading is good — in a block system this would be "flag wind block as reclaimable once fusion comes online, rebuild in freed space."

**Re: the bigger picture** — here's what I think the architecture looks like:

- **Layer 1** = Felenious's rule system (Barb3). The foundation. Hard-coded, deterministic, battle-tested. This stays.
- **Layer 2** = Data-informed tuning. Extract timing benchmarks from current-patch replays. "When should the AI build its 2nd factory on this map in this position?" Not ML, just statistical analysis of what works.
- **Layer 3** = Parameter optimization via self-play. Barb3 has hundreds of tunable JSON parameters. Instead of manual iteration, run headless matches between AI variants and converge on optimal configs. Bayesian optimization, not neural networks.
- **Layer 4** = The ambitious one. RL or LLM-based strategy selection. Noodles's command-prediction approach or modular RL sub-policies for specific decisions. This is where the HPC cluster matters.

Felenious said "show me something working." Fair. Here's my plan: deliver the block placement system first (proving I can actually modify Barb3), build the data pipeline second (game state export, replay parsing), then tackle the ML layer with whoever wants to collaborate.

**On the data front** — ACowAdonis you've got 800GB, Felenious 730GB, pandaro mentioned there's a replay parser. Between that and the live game data I'm already collecting through my widget suite (economy tracking, unit census, build timing), we probably have more data than anyone's tried to use systematically. The question isn't whether there's enough data — it's whether we can extract the right features from it.

Who's interested in getting a working group going? I'm building the infrastructure regardless (it's useful for the block placement and Barb3 work). But if Noodles wants to try the LLM approach and ACowAdonis wants to dig into replay analysis, we could divide and conquer.

---

### Alternative: Shorter version (if the above is too long)

Hey everyone, been heads-down in the Barb3 codebase for the block placement quest. Quick thoughts on this thread:

@ACowAdonis — 100% agree replays are command logs, not game state. But they're still useful for build order timing and eco benchmarks. For simulation-dependent decisions, self-play is the move.

@Noodles — Your LLM-on-commands idea is interesting. I'd condition on structured game state rather than video though — way more information-dense. The compartmentalized ML approach (AI decides what to build, where to deploy) maps to what I'm working towards. Would love to dig into this with you.

@TheBlindjin — Headless speed is the key question. Going to benchmark it. Spring supports up to 999x in headless (no rendering), so potentially thousands of games per hour per machine (CPU-bound).

My plan: deliver block placement first (proving the workflow), build data pipeline second (game state export + replay parsing), then tackle ML with whoever wants to collaborate. Felenious said show him something working — that's the right bar.

Who's in for a working group?

---

## 3. AI Training Strategy — Refined Approach

> Context: Jules's original idea + RobotRobert03's pushback. This is the refined strategy to present to the group (or keep for our own planning).

See separate document: `sessions/Session_2/Research/09_AI_Training_Strategy.md`
