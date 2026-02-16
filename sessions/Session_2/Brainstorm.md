
Okay so here is what's up. As you know we started building some widgets. Now I got in contact with one of the devs that is working on a new BAR AI and I asked him how I could help and he gave us the quest to improve the building logic of the new BARB AI. See more in the Projects/TheLab/Experiments/BAR/sessions/Session_2/Brainstorm file.

I cloned the repos of the Game and the new ai in: Projects/TheLab/Experiments/BAR/Prod
and you can find some chat logs of the discord ai chat rooms here: Projects/TheLab/Experiments/BAR/Discord_Chats

What else I want to do:
- Finish the quest we were tasked with
- connect game data synced with website on top of existing csv/json export
- Improved Simulator/calculator deployed
- Export/scrape/download all game data or at least find a way to do it so we can use it to feed the Ai we are going to build.

How we will do this:
- Summarize the discord chat logs to maybe already find pointers and leads. And in general to get up to speed.
- Analyze how bars architecture and implementation and in general figure out how it works. Document it ofc
- Research the technologies and patterns used and create research documents for it
- Analyze and document how the current ais Barb2 & 3 work and what their differences are.
- Track down the angelscript Felenious mentioned and all other vital files for our quest.
- Decide if we are gonna dig into C++ or if there is another way
- Create our dev setup for this
	- Game running in dev/debug mode
	- IDE and deps installed
	- Dev tools installed etc
	- Full setup with all bells and whistles
- figure out how to build the modular build order thingy to fulfil our quest
- See from there


We should also find or build a function to find reclaimable metal laying around, from dead units or wreckage buildings.


# Some other thoughts:

Game grid layout:
- Big grid: ca. 180 cord, 4x4
- Small grid: ca. 45 cord, 3x3, 15 cord squares
	- This is the grid builds snap to
- Verify these numbers in the code
- Metal extractors seem to always mostly 



- Leverage the blueprint api to the max for the modular building AI
	- Is there a max amount of blueprints we can possibly do?
		- Is this determined by how the blueprints are loeded?
		- They are basically json files right?
		- Is always only the blueprint chosen and its neighbours being loaded into memory or all of them? or just one?


# New thoughts

- We should build a compass that allows users to communicate directions however their camera is angled