# Discord Barb 2.0 Testing Summary

> **Source:** `Discord_Chats/Discord Barb 2.0 Testing Forum chat history.md`
> **Messages:** 27 | **Period:** Feb 6-8, 2026
> **Extraction Date:** Feb 13, 2026

---

## Key Participants

| Name | Role | Key Contributions/Reports |
|------|------|---------------------------|
| **[SMRT]Felnious** | AI Developer (1600 Hours AIdev), SMRT clan | Created Barb 2.0, announced official test release, provided guidance on known issues (avoid Legion, map compatibility), responded to bug reports |
| **Tommy** | Tester, SMRT-affiliated | Extensive hands-on testing at 30% and 100% profiles; reported bomber spam bug, constructor spam, FPS collapse; experimented with custom Sweetmare air-only profile with AA tweak |
| **Saranbaatar** | Tester | Reported AI producing 19 nukes in a 3v3; observed commander stationarity bug across multiple games |
| **Erendil** | Tester | Most detailed bug reporter; identified base defense vulnerability, T1 factory self-destruction bug on Supreme Crossing, compared Barb v1 vs v2 defense building behavior; provided 3 replay files |
| **[SMRT]RobotRobert03** | Community member | Minimal contribution (anticipation message only) |

---

## Test Findings

### Critical Bugs

1. **Bomber Spam / Infinite Air Production (300 bombers/sec)**
   - **Reporter:** Tommy (msg #13)
   - **Profile:** 30% bonus profile
   - **Impact:** Game-breaking. Air factory produces ~300 bombers per second, crashing the game to 1 FPS by the 10-minute mark.
   - **Evidence:** Screenshot attached showing massive bomber count.
   - **Note:** Occurs on both 30% and 100% profiles (msg #14).

2. **FPS Collapse at ~10 Minutes**
   - **Reporter:** Tommy (msg #7, #14)
   - **Profile:** Both 30% and 100%
   - **Impact:** Game grinds to 1 FPS by 10 minutes on all tested profiles, making games unplayable past that point.
   - **Root cause:** Likely linked to uncapped unit production (bombers, constructors).

3. **T1 Factory Self-Destruction on Supreme Crossing**
   - **Reporter:** Erendil (msg #26)
   - **Map:** Supreme Crossing
   - **Impact:** AI starting in the top-half right position destroys its own T1 factory, leaving it with only the commander and construction bots until it builds a T2 factory much later. This effectively cripples the AI for the early-to-mid game.

### Building & Base Issues

1. **No Static Defenses Built**
   - **Reporter:** Erendil (msg #21)
   - **Impact:** AI base is extremely vulnerable. Does not build static defenses (LLTs, etc.), making it trivially defeated by early bot rushes. A single static defense turret would be enough to stop these rushes.
   - **Context:** Felnious acknowledged that "anyone is vulnerable to pre 3 min rush" (msg #22), but Erendil countered that a single LLT or keeping the commander at base would solve it (msg #23).
   - **Comparison:** Barb v1 builds more defenses and builds them faster than v2. In head-to-head tests (3x Barb v1 vs 3x Barb v2), v1 won on Supreme Crossing twice due to better defensive behavior (msg #26).

2. **Constructor Spam (Never Stops Making Cons)**
   - **Reporter:** Tommy (msg #16)
   - **Impact:** AI continuously produces construction bots without limit. Combined with other production issues, this contributes to the FPS collapse. Tommy noted the need to "make sure they're spread out, because they do not ever stop making cons."
   - **Evidence:** Screenshot showing excessive constructor count.

### Unit Production Issues

1. **19 Nukes in a Single Game**
   - **Reporter:** Saranbaatar (msg #8)
   - **Context:** 3v3 match. One AI built 19 nuclear missiles.
   - **Impact:** Severe resource allocation imbalance -- funneling everything into nukes rather than balanced army composition.

2. **Uncapped Air Production**
   - **Reporter:** Tommy (msg #13-14)
   - **Impact:** Air factory has no production cap or rate limiter, leading to the 300 bombers/sec bug described above.

3. **T2 Sea Lab Fails to Spawn**
   - **Reporter:** Felnious (msg #12)
   - **Impact:** T2 naval tech tree inaccessible in some conditions.

### Map-Specific Issues

| Map | Issue | Reporter |
|-----|-------|----------|
| **Supreme Crossing** | AI in top-half right position destroys its own T1 factory, leaving only commander + con bots | Erendil (msg #26) |
| **Supreme Crossing** | Barb v2 loses to Barb v1 due to weaker early defense | Erendil (msg #26) |
| **Ancient Bastion Remake 0.5** | Base wipeout in 3v3 (one AI's base destroyed quickly) | Erendil (msg #21) |
| **Avalanche 3.4** | AI weak at defending base vs small bot infiltrations in 4v scav mode | Erendil (msg #21) |
| **General (limited maps)** | Felnious noted only a few maps ship with the test release; some maps the AI simply cannot play | Felnious (msg #6, #27) |

### AI Behavior Issues

1. **Commander Stationarity**
   - **Reporter:** Saranbaatar (msg #20)
   - **Impact:** Not all commanders move out of their starting area. Across multiple games, some commanders remain stationary and never move to the frontline. Unclear if this is RNG-based or a systematic bug.

2. **Commander Sent to Build Mex Instead of Defending**
   - **Reporter:** Erendil (msg #23, implied)
   - **Impact:** Commander leaves base to build metal extractors, leaving the base undefended against early rushes. A commander staying at base would itself be sufficient defense against early bot rushes.

3. **Legion Faction Broken**
   - **Reporter:** Felnious (msg #11)
   - **Impact:** Legion faction should be avoided entirely in the current test build. No details given on the specific failure mode.

---

## Bug Catalog

| Bug | Severity | Map | Reporter | Status |
|-----|----------|-----|----------|--------|
| Air factory produces ~300 bombers/sec | **CRITICAL** | General | Tommy | Open |
| FPS collapse to 1 FPS by 10 min | **CRITICAL** | General | Tommy | Open |
| T1 factory self-destruction | **HIGH** | Supreme Crossing (top-right spawn) | Erendil | Open |
| No static defenses built | **HIGH** | General | Erendil | Open / Acknowledged |
| Constructor spam (never stops building cons) | **HIGH** | General | Tommy | Open |
| Commander stays stationary at base | **MEDIUM** | General | Saranbaatar | Open |
| AI builds 19 nukes in one game | **MEDIUM** | General (3v3) | Saranbaatar | Open |
| T2 sea lab fails to spawn | **MEDIUM** | Naval maps | Felnious | Open |
| Legion faction non-functional | **HIGH** | General | Felnious | Known / Avoid |
| Barb v2 weaker defense than v1 | **MEDIUM** | Supreme Crossing | Erendil | Open |
| Commander leaves base to build mex (no early defense) | **MEDIUM** | General | Erendil | Acknowledged |

---

## Implications for BARB Quest

These test findings have direct relevance to our block-based building approach:

- **Base defense vulnerability is the #1 reported issue.** Barb 2.0 builds no static defenses, making bases trivially rushable. This strongly validates the need for a building placement system that prioritizes defensive structures early. Our block-based approach could ensure LLTs and other static defenses are placed as part of the initial base layout, not left to chance.

- **Constructor spam confirms builder coordination is broken.** The AI produces unlimited constructors but apparently does not coordinate what they build. A block-based building system with defined construction zones would give constructors purposeful build orders rather than aimless behavior.

- **Space management issues directly support the "blocks not spread" approach.** Tommy's observation that units need to be "spread out" because constructors never stop building suggests the AI has no spatial awareness of its own base footprint. Block-based placement with defined zones would prevent structures from being crammed together and would manage space intentionally.

- **T1 factory self-destruction on Supreme Crossing** suggests the AI's building placement logic can conflict with existing structures. A block-based system with placement validation would prevent the AI from demolishing its own critical infrastructure.

- **Commander behavior (stationary or mex-wandering)** indicates the early game opening sequence is not well-defined. Block-based build orders could include a commander opening sequence that balances economy expansion with base defense.

- **Barb v1 outperforms v2 on defense** because v1 builds static defenses earlier and more reliably. Whatever building system we design must match or exceed v1's defensive timing while incorporating v2's improved offensive play.

---

## Configuration & Balance Notes

- **Profile System:** Barb 2.0 uses a percentage-based "bonus profile" system. Profiles tested include 30% and 100%. Both caused game-breaking performance issues at the 10-minute mark.
- **100% profile** is explicitly expected to crash games (Tommy, msg #7: "100% bonus profile gonna crash my game at the 10min mark, insanity").
- **Custom profiles possible:** Tommy modified a "Sweetmare" profile to be pure air and combined it with an AA variant tweak (msg #19).
- **Tweaks not recommended:** Felnious explicitly suggested not using tweaks during testing (msg #18).
- **Limited maps:** Only a few maps ship with the test release. Configs are still being tested and finalized (msg #6).
- **Legion faction:** Explicitly marked as non-functional -- avoid in testing (msg #11).
- **GitHub repository:** Test release published at https://github.com/Felnious/Skirmish (msg #6).
- **JSON configs mentioned:** Profile configs are JSON-based (implied by the profile percentage system and Felnious's config references).

---

## Key Quotes

> **Felnious (msg #1):** "This is where you populate any Errors/Bugs/Issues/Inefficiencies with the New Barb2.0 Scripts that make the Barbarians play like real players rather then 5v1 until you lose :D."

> **Tommy (msg #5):** "The games looked pretty good last night when they worked"

> **Tommy (msg #13-14):** "Air decided to shit out 300 bombers a second (30%profile)" ... "30% and 100% tried so far and both grind the game to 1fps by 10mins lol"

> **Tommy (msg #16):** "Duly noted to make sure they're spread out, because they do not ever stop making cons"

> **Tommy (msg #19):** "Modified a sweetmare to basically be pure air and it's hella fun with our aa variant tweak Great work so far though! Can't wait to try an actual pve match against this thing and see wtf happens"

> **Saranbaatar (msg #20):** "Not all commanders move out of their starting area base i've noticed, multiple games now, where they where kind of staionary and didnt move to frontline, or is that just rng messing with me?"

> **Erendil (msg #21):** "Good job so far. one big problem : The AI base is realy vulnerable. No static defenses. A bot rush at the start of a game just wipe it out."

> **Erendil (msg #23):** "True but just one static if enough to stop that rush (or the commander if he isn't send to a build a mex spot)"

> **Erendil (msg #26):** "It's random, I just tested 3 barbv1 vs 3 v2 and V1 barb build more defenses and faster. V1 manage to win on supreme crossing two times."

> **Felnious (msg #22):** "anyone is vulnerable to pre 3 min rush"

> **Felnious (msg #27):** "there are maps that it can play"

---

## Test Replays Referenced

| Replay File | Map | Mode | Size | Reporter |
|------------|-----|------|------|----------|
| `2026-02-08_10-32-20-151_Supreme_Crossing_V1_2025.06.18.sdfz` | Supreme Crossing V1 | AI vs AI (likely 1v1 with bot rush) | 7.52 MB | Erendil |
| `2026-02-08_09-27-27-155_Ancient_Bastion_Remake_0.5_2025.06.18.sdfz` | Ancient Bastion Remake 0.5 | 3v3 (one base wiped fast) | 6.24 MB | Erendil |
| `2026-02-08_11-23-54-289_Avalanche_3.4_2025.06.18.sdfz` | Avalanche 3.4 | 4v Scav | 35.64 KB | Erendil |

**Screenshots referenced (not downloadable, Discord CDN):**
- Tommy's bomber spam screenshot (msg #13)
- Tommy's constructor spam screenshot (msg #16)
- Tommy's end-of-session stats screenshot (msg #17)

---

## Timeline

| Date | Event |
|------|-------|
| **Feb 6, 2026 06:28** | Felnious opens the Barb 2.0 Testing Forum |
| **Feb 6, 2026 07:18-07:48** | RobotRobert03 and Tommy express anticipation |
| **Feb 7, 2026 21:02** | Tommy reports games "looked pretty good last night when they worked" |
| **Feb 8, 2026 09:10** | Felnious announces official test release with GitHub link |
| **Feb 8, 2026 11:17-11:43** | Tommy's test session: discovers bomber spam, FPS collapse, constructor spam at 30% and 100% profiles |
| **Feb 8, 2026 11:21-11:22** | Saranbaatar reports 19-nuke AI in 3v3 |
| **Feb 8, 2026 11:35-11:38** | Felnious advises avoiding Legion, notes T2 sea lab spawn issue |
| **Feb 8, 2026 12:35** | Saranbaatar reports commander stationarity across multiple games |
| **Feb 8, 2026 12:35-13:43** | Erendil's detailed testing session: base vulnerability, v1 vs v2 comparison, Supreme Crossing factory bug, 3 replay files uploaded |
