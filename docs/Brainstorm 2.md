We are building the optimal T2 transition build order for glitters v2.3.

optimisation:
- after the first units we need two converters not one.
- Align solar better for more efficent spacing. 


Current timing:
 with 4 con and com

5:1 unit buildorder con to janus 

T2 start at 10:40 but stalling immediately 3min build
- Plus 150 E overflow during t2 build

No reclaiming or waiting done tho.

12:40  T2 finished

13 Janus produced

21 M & 1000 E




- adjust default priority settings.


66:55 start test 2

3 con 1 com

basic eco built at 6min

9min T2 build start

11.5 min T2 build finished


Optimizations:
- Eat metal from one solar and wind and the T1 lab to fund faster T2 build
	- 550 from econ reclaim and 590 from T1 lab
		- -> 1140 M 
- only build 3 nanos (delete last  one)
- turn T2 lab 90° to the left
- Leave space to drive past nanos  -> 3 nano line instead of 2x2
- Only secure further mexes after the first nano is built. Before that the build power is too valuable since we have storage.
	- So instead of rushing the commander out, built first module together with con bot and use commander to get con asap.
- Place the blueprint so the nanos are in reach of the starting mexs
- Don't produce T2 units during mex upgrade 





Test 3


Note early windstall hindered T1 lab by 20sec

13:00 T2 built

16 Janus produced




Adv solar cost:
350 M
5000 E

88 sec buildtime

Make 80 E/s

60 E = 1 M

26k E cost

Breakeven after 325 sec production


Wind:
40 M
175  E

cost: 2575 E

18 sec

cost  / windspeed = breakeven


x = number of windmills
tb = time to build construction = x * 18
Em = Energy made during construction = (x * 18 * windspeed) / 2.71 

cost = 2575 * x

x = 80 / windspeed
t breakeven = time it takes to make back the cost = (cost - Em) / windspeed

(2575x) - (9x * 0.5 windspeed)

(206'000 / windspeed) - 360 = t







Start: 0

Build first wind


Second try

Okay what I need is a function that takes the windspeed as input and gives the time to break even to build windmills that in the end produce 80 energy.


x = number of windmills



t = (cost - (x * 18 * windspeed) / 2.71)  



conversion factor: 80 / windspeed


