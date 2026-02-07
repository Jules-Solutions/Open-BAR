

Okay I reeeeaaaaallllyyy like BAR and I looove programming. Now my biggest luck is that the LuaUI and the game as a whole is open source and they encourage tinkers like me to go and have fun soooo I will answer this call with war cry that will scare even the most gruesome mech bot titan.

Soo Bar says: We can quietly run a private “mystery advantage” widget in public multiplayer if we are sharing it. 
- This means this repo will be public and we will share it in the discord.
- We should really check out what already exists before we dive into this.

- We will also implement 2 modes to run the widget from the get go to honour the game rules:
	- All: (default for unranked/PvE/custom)
	- No Automation (default for PvP)


- We will make sure there are no hardcoded paths in our widgets so we can maintain it easily after future changes.


- So the question is, is there a python LUA libary or even a BAR libary? What amazing widgets are out there already? Are there frameworks? 


Widgets and features I want to build or find:
- auto skirmishing
- automated rezbots,
- projectile dodging
- In general a module/libary that can be used to script strategies and stuff for BAR in python would be amazing. Like a full interface for python. Does this already exist? Is this useful or basically redundant because we can just use the Lua stuff?
	- Buut If we do any automations we will need our own little version of this anyway so why not build it intelligently and reusably
	- One part of this system would for sure be hooks like: Server loaded, Location chosen, Game started etc.
		- In one of these starting hooks we should add that we create a vector db of the map with an entry for every coordinate. Every coordinate has attributes like: can be built on, is on "even" ground (basically can be reached by bot/vehicle/airplane). Or is this already solved with Lua? I honestly have no idea what I am talking about here on technical level but I assume we need this informtion to create and working automation sooo this is why I brought  it up.
	- Like it would be cool if I could literall write a script that goes: if energy surplus > 70 build convertor etc. 
- 100% efficient goal achievement -> Change game to giving general orders and the game does the rest
	- Like before the game starts I can chose the faction, start location, how many mex opening (1-4), unit type, select role, set a primary and a secondary front/defence line, define building area, define lane, set wind strategy (auto, opening only, wind only, solar only, percentage), defensive or offensive, solo T2 transition vs Get T2 con from teammate at min X and probably a few more things I will think of.
	- Then I chose a series of goals and projects like get 5 medium tanks to the frontline, get T1 lab/plant running smoothly with X Buildpower, build (light,medium,heavy) T1 defences for base and front respectively, scale economy until con 2 bot comes or get T2 up, transition to T2 econ, get T2 lab/plant running with X BP, Get T3 up and running with X BP, build nuke, build long range plasma canon, build X Titans etc. Every goal is then achieved in the most efficient and fastest way possible.
	- When the game starts the widget automatically places the opening build orders perfectly, ques the right units and then manages the build orders perfectly without wasting resources. To achieve the set goals and projects given the constraints from the strategy and the map.
	- It could also calculate a prediction on how it should go economically if we follow this
	- Ah yeah also a slider that I can set on how much percent of the resources should be spent on econ and how much on units. (If units can't consume more then more lab/plants and/or building towers are built)
		- With the option to put on auto,
	- A slider for how much percent of the resources should be saved to fill the storage or give to the team
	- What also would be fun is if I could give project orders like build long range plasma cannon and the game builds or if available frees the needed resources and build the project where I placed it. Another project could be to get 50 titans and then our tool figures out the most efficient way to get there.
		- We probably would need a slider to define the percent of resources that should be used to finance these kind of projects besides the regular econ scaling and unit production.
	- Also I don't micromanage my troops I draw a primary (Will never fall, if it falls we have basically lost (usually near the base)) and a secondary defensive line (this is the line to support and define the actual front this line can be moved by us or the enemy) and set the mood to defend then I define enemy base core and a few strategic targets or strategic milestones. After that my troops move by themselves to fire and doge bullets. When I set the mode to attack the front line / secondary defence line is slowly moved forward with my units attacking whatever.
		- Or even better we could have multiple attack strategies:
			- Creeping forward
				- Moving front slowly in the direction of the base core
			- Piercing assault
				- Fire concentrated on one point and focus is to move into enemy territory as quickly as possible only attacking mobile or stationary defences
			- Fake retreat
				- Small expedition poses as the only troops defending right outside of jammers and starts attack
				- When attack starts to fail they retreat and lure the enemy into range of my longer ranged units that hold fire until I give the order to open fire when enough enemy units are in the death zone
			- Anti Anti Defences raid
				- Focus only on destroying, AA, Anti nukes, plasma domes, jammers etc
				- Basically a fast assault that clears the way for our air force to bomb everything into oblivion
			- What else?
	- Ofc our troops, defences and frontlines dynamically react to the enemies range
	- We should also have a defend base for life and death mode in which troop production is temporarily unsustainably maximized and all units guard and protect the base from the direction the enemy is coming and efficiently attacks all enemies within a radius of the base buildings (Base area needs to be defined as well it seams or is build area = base area?)
	- Also a mobilisation mode in which we temporarily maximize T1 and/or T2 unit production unsustainably to supply the front.
- PvP overlay
	- What unit type produced how much resources
		- Like windmills produce 200 E/s, solar 15 E/s etc
	- How many units of each type I have
	- How much total build power I have and how much is actually being used. If not used how much is idle and how much is stalling
	- Big fucking glowing circle around high priority stuff
	- A timeline with some graphs and checkpoints that shows expected vs predicted vs actual
	- A risk estimator that estimates what kind of firepower our opponent could be in possession of.
		- For example after the first T2 unit is spotted a timer starts for: the build time of constructing a nuke building + time it takes to produce a nuke multiplied by X build power. At the start the risk level would be low to medium T1 units, after 2 min or so it would be medium to high T2 units and air. We should also calculate a range from when there can realistically be T2 units on the field to now there are T2s for sure and the same for T3 and the long range stationary canons. What else?
- The simulation of the simulation tool
	- This is used to design build order and calculate their output, cost, build time (ranges?) etc with set map parameters and certain available area to build on and do the actual accurate math to get the mathematically most optimal build orders possible and quickly iterate and optimize on them.
		- This should solve the issue of: I have an idea how to do optimize this for 5%. Waits 5min for build to finish, doesn't know if it was actually better or even e bit worse. Now clear numbers, no comparison etc sooo many problems.
- If we have all of that we basically have all the tools to let an ai agent play the game. Like build our own ai but it is adaptive, strategic and we build in memory + reinforcement learning so symbolic, semantic and logical reasoning combined to become the ultimate BAR beast with OS over 9'000 (for PVE and agent software demos only ofc)

### approach (clean + low drama)
1. **Start from an existing widget** similar to what you want (BAR_widgets community repos are a common starting point).
2. Build in **small slices**:
    - draw something on screen
    - read game state (units, selection, resources)
    - add UI controls/settings
3. Decide early if it must be **ranked-safe**:
    - If yes: **do not** call GiveOrder-type APIs.
    - If no (PvE only): still keep it shareable if used on public servers.
4. Package it so you can publish it easily (Git repo + README); that aligns with BAR’s public-availability expectation.
### Faster / cheaper alternative
- Don’t write a widget first.
- First, see if it’s achievable via:
    - keybind/uikey tweaks
    - existing widgets + configuration​
        This avoids maintenance and avoids policy pitfalls.


Our goal is “work with the game, not dominate it on day 1”:
1. **Write a purely visual widget first** (draw overlays, UI panels).
2. Then add **input conveniences** (selection helpers, smart UI), but keep it non-automating.
3. Only then explore automation — in **offline/PvE** — and be ready that it’s not ranked-appropriate.
4. If you need deeper behavior changes, move to **game-side** (gadget/mod) work and use the BAR dev workflow.