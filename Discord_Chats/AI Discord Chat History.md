Extraction Date: 13.02.2026 20:26

1. We have an ai that has the ability to be able to build what we tell them to but can't release it yet
2. ### sam(73 61 6d)![](https://cdn.discordapp.com/clan-badges/1187823000934953060/ec60c5e6d1f14d3bbff586e2e0b9e54e.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 24.12.2025 15:31
    yeah but even on great divide and center command which i both play a lot like i 1v2'd the AI without any real effort which unless ive gotten a ton better and the guy i play with got a absolute ton better then it doesnt make sence
3. like the med AI i am used to being trashy at building but it would at least still apply pressure across the map but the hard AI is normally relitivly hard to hold a line in a 1v2
4. ### ҉Seth🦆Gamre(Lead Surveyor)![Rollenicon, Team Leaders](https://cdn.discordapp.com/role-icons/1384586105696813156/2d1a05cb15eb560af587766458c3af47.webp?size=28&quality=lossless) _—_ 24.12.2025 17:31
    I have a game mode in mind, calling it "space race" It's a race to capture a massive war spaceship in the middle of the map. Barb's right now have no conception of using capture let alone objectives. Not sure how to proceed
5. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 24.12.2025 18:14
    Well the coms don’t use capture but the assist drones do, not sure what behavior differs between them.
6. ### Isfet Solaris![](https://cdn.discordapp.com/clan-badges/1369283374790742086/439c5b7117f3f3e8e574b4766d1b7e73.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 24.12.2025 18:18
    Out of curiosity, is there a way to make the AI more intelligent about lava? Some friends and I were playing and filled a slot with AI, but it kept walking directly into the lava and treating it like water.
7. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 24.12.2025 18:19
    Uh not that I have seen yet sadly.
8. ### Isfet Solaris![](https://cdn.discordapp.com/clan-badges/1369283374790742086/439c5b7117f3f3e8e574b4766d1b7e73.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 24.12.2025 18:20
    Alright, just figured it was worth asking o7
9. ### lamer![Rollenicon, Contributors](https://cdn.discordapp.com/role-icons/549291914164305920/a34e8548e7a4982377b34afa932b8875.webp?size=28&quality=lossless) _—_ 24.12.2025 19:10
    Let that mode have a special drone-unit spawned automatically by commander every Nth minute. Disable control for such unit on spawn: [https://github.com/rlcevg/CircuitAI/blob/barbarian/data/script/dev/main.as#L54](https://github.com/rlcevg/CircuitAI/blob/barbarian/data/script/dev/main.as#L54 "https://github.com/rlcevg/CircuitAI/blob/barbarian/data/script/dev/main.as#L54") Give it a command to capture. Or decoy commanders can capture, adjust its probability weight with special json config. Disable control on decoy commanders and give it capture order on spawn or after some time.
10. Should i add `Unit::Capture` command to AS interface or `Unit::ExecuteCustomCommand` that would allow execution of any (game-specific or engine built-in) command? (for the future)
11. ### lamer![Rollenicon, Contributors](https://cdn.discordapp.com/role-icons/549291914164305920/a34e8548e7a4982377b34afa932b8875.webp?size=28&quality=lossless) _—_ 24.12.2025 19:20
    For such case a DefendTask with specific unit as a target would be great, for the future.
12. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 24.12.2025 20:24
    I'll be looking at smaller maps later on for specific build orders but usually small maps are to fast for ais to get going as they use a generic build order across all maps and aren't currently customizable per map
13. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 26.12.2025 05:06
    @Floris New Update for the Legion Sea ![😄](https://discord.com/assets/58a76b2430663605.svg) [https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6501](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6501 "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6501")
    GitHub
    [Legion Hotfix #1 Navy/Seaplanes - 12/25/2025 by Felnious · Pull Re...](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6501)
    Work done --Fixed for Hard and Hard_Aggressive -Fixed a T2 Lab Placement Issue -Fixed Economy Block_Map to Include Legion New Buildings -Fixed Legion Sea Labs to have a better Opening -Created a Va...
    [](https://opengraph.githubassets.com/8597987a432ac004695d78fea2b1dd9fc3ad3eb2c3effcdf33100e1b46618699/beyond-all-reason/Beyond-All-Reason/pull/6501)
    ![Legion Hotfix #1 Navy/Seaplanes - 12/25/2025 by Felnious · Pull Re...](https://images-ext-1.discordapp.net/external/g7e_jsTxPVMBqqYjE2qtUct0XLnRPidejLvubSi0MFw/https/opengraph.githubassets.com/8597987a432ac004695d78fea2b1dd9fc3ad3eb2c3effcdf33100e1b46618699/beyond-all-reason/Beyond-All-Reason/pull/6501?format=webp&width=500&height=250)
14. ### sicbastard _—_ 26.12.2025 16:46
    Hoe do the tasks work?
15. ### lamer![Rollenicon, Contributors](https://cdn.discordapp.com/role-icons/549291914164305920/a34e8548e7a4982377b34afa932b8875.webp?size=28&quality=lossless) _—_ 26.12.2025 16:55
    I'd say like a states in a state machine
16. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 27.12.2025 21:21
    can some one tell me if the following was tried: 1) take the Barb AI files, and extract the hooks and calls from the .as files 2) create new files from the .as and .json by making different calls I doubt this allows for any deep alteration of the AI, but this could be a starting point
17. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 27.12.2025 22:02
    [](https://cdn.discordapp.com/attachments/549286426026573833/1454580211826950397/image.png?ex=69903a23&is=698ee8a3&hm=c3731440e8c5e53acdca406e7290d77289b3ae672ae45ab2ea65d9d320b83419&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1454580211826950397/image.png?ex=69903a23&is=698ee8a3&hm=c3731440e8c5e53acdca406e7290d77289b3ae672ae45ab2ea65d9d320b83419&=&format=webp&quality=lossless&width=341&height=341)
    [](https://cdn.discordapp.com/attachments/549286426026573833/1454580212867141754/image.png?ex=69903a23&is=698ee8a3&hm=d9135cbb57795404ecb609013882fe7bd76e3ba99805a337384fc355dcf6cd7a&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1454580212867141754/image.png?ex=69903a23&is=698ee8a3&hm=d9135cbb57795404ecb609013882fe7bd76e3ba99805a337384fc355dcf6cd7a&=&format=webp&quality=lossless&width=341&height=341)
    [](https://cdn.discordapp.com/attachments/549286426026573833/1454580213534032044/image.png?ex=69903a23&is=698ee8a3&hm=7ac6e5314cfaa0ffa6f99d95f7ebc8773bb04ff4b3e256f7b2290d59600687f0&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1454580213534032044/image.png?ex=69903a23&is=698ee8a3&hm=7ac6e5314cfaa0ffa6f99d95f7ebc8773bb04ff4b3e256f7b2290d59600687f0&=&format=webp&quality=lossless&width=226&height=226)
    [](https://cdn.discordapp.com/attachments/549286426026573833/1454580214192668722/image.png?ex=69903a23&is=698ee8a3&hm=71b5e2870de96f2d6c5fa03955f80d4cd3dcb2817037741a1680c45e6b2c21bf&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1454580214192668722/image.png?ex=69903a23&is=698ee8a3&hm=71b5e2870de96f2d6c5fa03955f80d4cd3dcb2817037741a1680c45e6b2c21bf&=&format=webp&quality=lossless&width=226&height=226)
    [](https://cdn.discordapp.com/attachments/549286426026573833/1454580214809235476/image.png?ex=69903a24&is=698ee8a4&hm=2727990fcd017e801098843618d2641ac73a03b4570d666f6afdd0a49181b352&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1454580214809235476/image.png?ex=69903a24&is=698ee8a4&hm=2727990fcd017e801098843618d2641ac73a03b4570d666f6afdd0a49181b352&=&format=webp&quality=lossless&width=226&height=226)
18. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 27.12.2025 22:02
    Yes
19. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 27.12.2025 22:03
    ok, so I'm not insane, I looked into the CIrcuitAI stuff, and angelcode, and I don't want to touch assembly
20. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 27.12.2025 22:03
    ![😄](https://discord.com/assets/58a76b2430663605.svg)
21. i have total control over what the AI can and cant do
22. where to walk
23. where to build
24. where to attack
25. what, when, how many?
26. do i wanna draw profanity with walls with AI.... Yes i could... but COC
27. XD
28. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 27.12.2025 22:12
    you seen nothing robert XD
29. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 27.12.2025 23:36
    ok, making progress with my stuff
30. I just need to ask a thing here, did anyone already make an efficiency equation? AKA, any unit/action translated into metal over time
31. I have a rough start already, with the eco and converter math with unit pricing, but I don't have one that'reliable for action involving build power and build time
32. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 27.12.2025 23:46
    actually, I need time to build power conversion
33. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 27.12.2025 23:53
    nvm
34. ### sicbastard _—_ 28.12.2025 02:52
    ?
35. can we help somehow?
36. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 28.12.2025 20:27
    figured it out, no problems, tx for the suggestion
37. ### Arxam![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 28.12.2025 22:30
    some of the code is written, and i'll start bug hunting soon, is there a repo or showcase option to present AI performance?
38. my goal is to show the effectivness or lack of it, and use the existing AI as contrast
39. ### sicbastard _—_ 29.12.2025 15:12
    Performance in terms of cpu usage or winning?
40. I just set up a skirmish
41. How can i get the buildings previosly discovered? Right now my bot is only aware or structures it xan have in LOS and ignores buildings that are "ghosts" on the map. So basically he can only see what is currently in LOS.
42. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 29.12.2025 15:40
    Ai still have starfall disabled yeah?
43. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 29.12.2025 19:57
    Yeah
44. ### [SMRT]Felnious(1600 Hours AIdev)![](https://cdn.discordapp.com/clan-badges/1216088951392309370/afef8e1d14121535e46a4a27cefda396.png?size=16)![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 01:37
    ill have a fix here soon
45. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 01:38
    Oh no rush was just curious someone in main was asking the other day
46. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 02:10
    He says no rush cause he don’t want to die to it ![😅](https://discord.com/assets/5134d215343b97ef.svg).
47. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 02:10
    why you gotta call me out like that...fucker lmfao
48. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 02:10
    Death from above ![🤣](https://discord.com/assets/e5bddb2a9171637d.svg)
49. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 02:11
    i already know its gonna be real bad lol
50. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 02:11
    Tbh we are all dreading the day it gets added
51. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 02:11
    yeah... positive note new starfall model looks sick
52. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 02:12
    True dat.
53. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 02:13
    that wind up mechanic was the cherry on top
54. ### [SMRT]RobotRobert03![:camera_with_flash:](https://discord.com/assets/454ea1a4aa51f9d5.svg) _—_ 30.12.2025 02:14
    Legions polish is nice, hope it gets passed down to the other factions eventually
55. ### Bones![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![:test_tube:](https://discord.com/assets/e5aa5c7ba473596f.svg) _—_ 30.12.2025 02:14
    yeah i have faith Armada and Cortex will get the same treatment
56. ### ZephyrSkies _—_ 30.12.2025 03:32
    They will
57. ### ZephyrSkies _—_ 30.12.2025 03:34
    [](https://cdn.discordapp.com/attachments/549286426026573833/1455388478404690093/Scream_if_you_love_poland.gif?ex=699087e5&is=698f3665&hm=9e25a33d1d86a6b01f3c5f9cf9d9ab363802272b9a3170881995f4ad5c121aec&)
    ![Bild](https://media.discordapp.net/attachments/549286426026573833/1455388478404690093/Scream_if_you_love_poland.gif?ex=699087e5&is=698f3665&hm=9e25a33d1d86a6b01f3c5f9cf9d9ab363802272b9a3170881995f4ad5c121aec&=&format=webp&width=250&height=220)
58. ### 𝑫𝒂𝒎𝒈𝒂𝒎 (Audio Design Lead)![](https://cdn.discordapp.com/clan-badges/549281623154229250/2d8bea68b3152b52858942d2bc854cc7.png?size=16)![Rollenicon, Team Leaders](https://cdn.discordapp.com/role-icons/1384586105696813156/2d1a05cb15eb560af587766458c3af47.webp?size=28&quality=lossless) _—_ 30.12.2025 03:37
    [](https://tenor.com/view/screaming-internally-spongebob-spongebob-scream-intensifies-gif-6589653077021924320)
​