Okay so Felenious sent us the following message in discord:
"add building in blocks instead of spread areas that's an issue we have where they waste space
I have an angelscript for that but it requires a lot of testing"
​

Noow its not much to go on but enough to write a PR I for us.

So I know we kinda already solved this to 50% in one of our previous sessions in the build or econ automation or we at least thought/planned about it.
But lets still take it from the top.
Currently I have no idea about how to actually code this like technically. Felenious said something about C++ and angle script. I have no idea what angel scripts are but I know C++ as the second most holy language but aside from basic CS and meme knowledge nothing. Soo we will need to do a crash course on these later to bring me up to speed. 

What I do understand is that the current AI places buildings seemingly randomly splattered in "safe" territory or just spreading out in some algo with some randomness. (these are guesses from seeing the ais behaviour). Now this is not really space, walk time or defence efficient. So the next AI should do that better.

So we were dabbling in lua scripts. WTF is lua? you just generated it and it worked and I didn't question it. They are "game rules" right? So basically a huge api for a game on top of the engine correct? Soo when Felenious tells us to build a better build placement system he wants us to write lua or C++? How is he new AI built?


I have a few ideas how to accomplish that:
- Full map scan and coordinate mapping
	- Now I am not sure if this is technically useful but its how I imagine it in my mind.
	- This could something like this:
		- Pregame: (If possible without hassle, If not then just the first steps at game start)
			- We create an array for every coordinate of the map.
				- Okay actually not every coordinate I looked closely at the grid layout of the game. See in the brainstorm. We only need every square buildings can snap o to for the buildings logic. So we basically use a smaller coordinate system then the base game.
				- But I see a problem on the horizon with this. This shouldn't become a architectural limitation. We should still use and follow the games logic. No need to build a second system for where everything is on top of it. But we should definitely make sure our ai only to deal with the complexity it needs to and if this makes things easier we should use it. 
			- We assign every coordinate if its in general buildable or not
			- We assign what units can reach each coordinate
			- We assign the metal spots to its coordinates (there already is a built in widget api for this I believe)
			- Choosing Com landing location -> This is another project by itself we will stub this if we even include it.
			- And either start the opening build que already here or in the next step.
		- After game starts:
			- Define map zones,  primary and secondary frontline for the entire team.
			- Select metal extractors to be built -> This is another project as well
			- Queue Build opening
				- The stuff here we could basically do with a few "hard coded modules that just find the closest space that respects the spacing. The actual opening logic is another project as well buuut to test we will need to have a opening so we need our own solution.
			- We define a seed point for our base inside our building zone and close to the commander. The seed point is in the middle of a big square and all the neighbouring big squares should be mostly >50% free to build on.  
			- Now we get to the interesting part:
					- Okay so the map has this grid and each one has 4x4 squares inside. Now I feel like that would be a good way to contain the building in modules. Like we build our prebuilt square modules for each building type and when a building type is needed it is built in one of the big grids following the layout and spacing we defined either programmatically or manually. One of these squares fits 16 wind mills without spacing. Lets throw in a space so we get 2 lanes winds, one lane space and one lane wind. And if a djastend wind module is going to be built it is built rotatted on the side with only one lane of windmils. This is just and example for windmils tho.
					- This is just a first idea to solve the problem in the easiest way. But I think the approach of filling up containers is the way to go. This container should better be a configs based programmatically generated pattern of buildings.
					- Okay for the starting location we have the the seed for other other buildings where the position is relevant such as other labs, static defences. Like stuff that needs more then one building type to work. We can define project seeds from where it expands.
					- 
	- 
	- We assign the commander landing positions of us and all teammates
	- 
- Module size per building
- Module size by area and ratio
- Map zones
	- Types
		- Building zones
		- Territory / potentially future build zones
		- Front (the line between team and enemy territory)
		- Defensive line (line behind the front line where the actual defences are built)
		- Danger (Basically everywhere the enemy range is)
		- Middle line (horizontal, diagonal or vertical depending on map)
			- All the others we can somehow detect if we find a way to detect this one.
			- Or if we reaaalllyy have to I can assign them "manually" to each map..
		- Each map zone is player based and the sum of the players in a team give a teams map zones.
			- We need to figure out if the ais can communicate. Like are we coding one ai that can play with other ais/humans or are we designing an ai that controls all the ais on a team? If the first can the ais still share states some way?
			- We can also first define some of them team wide from the start ofc like middle and frontline
			- You know what I mean here? I didn't spell it out full but its clear right?
	- 
	- 
	- Team building zone
	- Enemy
	- Player building
- Build area
- Grid based
- Spacing rules
	- Basically: No module is ever placed withing another modules explosive range or builds itself with buildings in its own explosive range.
	- 
