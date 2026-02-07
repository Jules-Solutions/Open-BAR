
# Disclaimer:
- All values are always a very conservative estimate. The idea is that we have a surplus if we play correctly so we calculate with a bit more expenses then there are to stay in surplus.
- 

# Economic play styles by faction:

|Factory|Econ profile|
|---|---|
|**Bots**|Cheap, energy-light, metal-efficient|
|**Vehicles**|Heavier metal, moderate energy|
|**Air**|Extreme energy, low metal|
# Formulas

BuildTime = unit.buildtime / TotalBuildPower

Cost per second to build something:
Metal/s = metalCost * TotalBuildPower / buildtime
Energy/s = energyCost * TotalBuildPower / buildtime


# Base start to get into the game

Faction: Armada
Role: Self sufficient
Vehicles: 

This strategy is state and phase based.


1. Pregame 
	- com queue
		- 2x mex
		- 3x wind
		- 1x lab
		- 3x wind
		- 1x mex (If close)
		- 2x solar
		- 1x Radar
		- -> Get all defendable Mexes
		- 10x wind
		- 1x Energy convertor
		- 2-3x sentry towers near lab
		- 1x Energy Storage
		- 1x Metal Storage
		- -> Then either go to the front and help defend and build sentry towers or build energy
		- If energy then build 6 wind and 2 solar and 1 convertor groups.
		- If sentry towers build one big square away from the front first every second big square, radar and AA and every big square a sentry.
	- Expected Result:
		- 3-5 Mex = 6 -15 M/s
		- 14 wind 2 solar = 180 E/s

3. Game start
	- As soon as lab is done queue the following
		- 1 Con
		- 5 scouts
		- 10 light combats
		- 1 Con
		- 10 light combats
		- 1 Con
		- 10 light combats
		- 1 Rez
		- 20 light combats 
		- 150 medium combats
	- Then we establish econ and front in parallel
		- Build ca. 10 econ groups until 20 M/s & 300 E/s is reached
			- This is the first time we can let our lab run fully so this is the first stable point
			- Assuming 5 Mex we need 10 Econ groups.
		- Establish front (costs 4-6 M/s + 30-60 E/s)
			- Build defence line one big square away from the front 
			- Every second big square a sentry
			- One square behind the defence 2 radar & 2 AA
			- Then fill out sentry one every square and AA one each second square
			- Station troops half a square in front of the defence line
			- Set rally point one square behind the defences
			- Add dragons teeth and mines if bored and eco allows it
			- Full T1 defence expansion: Queue overwatch tower every second square between the sentries and gauntlet in the gaps between the AA
			- Keep the enemy on his toes with small raids and bullying
		- Build one or two nanos at lab depending on eco
	- Econ group early game:
		- 6 wind 16s
		- 2 solar 26s
		- 1 convertor 26s
		- Output: 1 M/s + 30 E/s
		- Time @BP400: 43.5 (Idea is to scale to this)
		- Demand: 20-25 M/s + 400 E/s
	- Expected Result:
		- 20 M/s + 300 E/s + 600 BP
		- Time: 9 min

4. Early to mid scaling
	- Prerequisites: +20 M/s, +1000 E/s & front under control
	- Goals:
		- Upgrade all Mex
	-  Eco group T2 transition:
		- 3 Advanced solar
		- 2 Convertors
		- Output: 2 M/s + 120 E/s
		- Time @BP400: 73s
		- Demand: 20M/s + 400 E/s
	- Actions
		- Cycle 3 cons in the lab in case one dies its instantly replaced
		- Cycle 20 of each unit relevant for the fight (+5 AA units if enemy is heavy on air and we want to raid soon)
		- Balance econ with converters
		- Find constructions site for T2 scaling and build a nano there
		- Build 2 eco groups inside nanos range
		- Build advanced lab/plant in nanos range
			- Queue only a constructor no other units yet
			- Send constructor to upgrade Mexes -> 8.5 M/s + 100 E/s demand
		- Build 1 eco group
		- Build 2 nanos
		- build 2 eco groups
		- Build 1 nano
		- Optionally fortify adv plant
		- If possible start first serious raid coordinated with teammates
	- Expected result:
		- Ready to start producing T2 units
		- 5 Eco groups = 10 M/s + 600 E/s
		- Adv mexes = 35 M/s
		- Total: 55 M/s + 1000 E/s

5. Midgame
	- Prerequisites: Expected results form previous phase 
	- Goal: Get full T2 production going and scale into
		- Supercharge lab with 3 nanos -> 25 M/s + 300 E/s
		- Scale advanced lab to 9 nanos -> 75 M/s + 900 E/s
		- Basically: Scale into T2 econ
	- Econ group mid game:
		- 1 Fusion reactor
		- 1 Advanced convertor
		- + 2 Nanos
		- Built with min. 5 nanos!!!!
		- Output: 10 M/s + 200 E/s 
	- Actions:
		- Build one nano 
		- Build 7 Econ groups
		- As soon as eco allows it throw on T2 unit production and fortify front with second adv con and place nanos at front for repair
		- Second raid with remaining T1 and a few T2 if early compared to enemy (This could already bring the win)
	- Expected Result:
		- T2 army
		- 150 M/s + 2000 E/s

6. Late game
	- TBD
	- Here it is hard to find a good Strat because for one it really depends on so much stuff and also I haven't really gotten to this yet so I don't really understand the full dynamics yet
	- But basically scale offence and defence into T2 with long range, nukes and anti nukes
	- Plus scaling to T3


Note: For multiplayer games we need to create a front, tech & sea strat as well. Also this strat is of course more of a guide then hard instructions!!!


With avg. of 10 wind this gives us 100 Energy of which 70 will be converted so we get 1 M & 30 E per group. These are starting numbers assuming wind is viable if no wind then replace the 10 wind with 5 Solars.


- Demand ≥ 1000 E/s
	- Start building advanced solar instead of mils or regular solar


motioncorrect.github.io/unit-comparison-tool

Buildtimes:
- Advanced vehicle plant: 180s
- Windmills: 16s
- Solar: 26s
- Advanced solar: 80s
- E converter: 26s
- Gauntlet: 214s

# Econ budgets:

### Building
Gauntlet:
- 5.8 M/s
- 58.41 E/s
- cost
	- 1250 M
	- 12500 E
	- 214s

Sentry (for temporary defence)
- 3.54 M/s
- 28.3 E/s
- cost
	- 85 M
	- 680 E
	- 24s

Beamer (for fixed defence)
- 3.95 m/s
- 21.25 E/s
- cost
	- 190 M
	- 1500 E
	- 48s

adv solar = 80 E
- costs = 350 M + 5000 E + 80s
- /s cost at 100 BP = 4.375 M/s + 62.5 E
- at 400 BP = 17.5 M/s + 250 E/s


Adv Mex
- 4.2 M/s
- 51.7 E/s
- cost
	- 620 M
	- 7700 E
	- 149s

Now the issue is that the advanced vehicle lab has 3 min build time and costs 14k E & 2.6k M
- Okay so at 100 BP it takes 28 E/s and 5.2 M/s
- Goal is 1 min
- So we need 300 BP and 74 E/s + 15.6 m/s
- Okay so its not realistic that we will make an additional 15.6 M with our previous econ group strategy because this would mean that we need to build 16 econ groups and that not realistic.
- We can reclaim all the messy start stuff that should give us ca. 500 Metal, collect all the metal on the map lets say another 100. Okay that is not a lot but this boost of 600 Metal is what we need to reclaim right before the advanced bot lab build starts. (Bot lab alone is 375 Metal and 30 per wind mill so this means we can get 675 Metal from reclaiming plant and 10 windmills)
- If we are not playing front we can probably shut the main lab down for 1 min or so...


### Maintaining 
Bot lab producing Ticks/Pawns & Rovers/Blitz:
- 10-20 M/s
- 150-300 E/s

Vehicle Plant
- 20-40 M/s
- 300-600  E/s

Air Plant
- 10-25 M/s
- 600-1200 E/s

Energy convertor T1
- 70 E/s
- For 1 M/s

Energy convertor T2
- 600 Energy/s
- For 1' M/s


One nano:
- 5 M/s
- 150 E/s





