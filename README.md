# SoarJETI sailplane apps for JETI radios

You can find the Lua source code for all of the apps under [Src](https://github.com/jfrickmann/SoarJETI/tree/main/Src). Radios with plenty of memory can run these source files as is, but I have also added compiled files under [Apps](https://github.com/jfrickmann/SoarJETI/tree/main/Apps), and these will consume less memory and start up faster, because they do not have to be compiled from source by the radio.

For older radios with small memories, look under [Stripped](https://github.com/jfrickmann/SoarJETI/tree/main/Stripped). These files have been compiled and stripped for debug info, to further save memory.

In addition to the score keeping apps for sailplanes, I have also included a couple of utility apps that I find useful.

To install the apps on your transmitter, connect the transmitter to your computer, and copy over the Lua files (.lua or .lc), as well as the entire [F3K score](https://github.com/jfrickmann/SoarJETI/tree/main/F3K%20score) and [F5J score](https://github.com/jfrickmann/SoarJETI/tree/main/F5J%20score) folders with contents, to the *Apps* folder on your transmitter's SD-card.

Then, navigate to **Applications**, **User Applications** on your radio's menus, and add the apps to the currently loaded model. Notice that they will be added to the menus as described below for each app.

## F3K score keeping

This is a score keeping app with all of the official F3K tasks and two practice tasks.

It provides its own timers implemented in Lua, and does not rely on the built-in timers. Therefore, if you want to test the app, it may be a good idea to first make a copy of your model and delete the timers you set up, to avoid duplicate time calls. The timers from the app can also be added to the Main Screen as Displayed Telemetry.

It starts and stops the flight timer when you activate the Launch switch. In normal mode, you activate Launch to start the timer, and again to stop it. In "QR" mode, the timer starts again immediately when you release the Launch switch, so you can tip catch and do quick turnarounds. By default, the flight timer freezes at the end of the task window, so you can land and save the flight time.

For Poker and the Quick Relaunch practice task, you can set the time target with a dial.

For 1234, you get some extra time calls before every minute, to help you decide if you want to land on the next whole minute. It also sets "smart" target times, depending on the already recorded flights.

There is also a feature to call out the remaining task window time every 10 sec. to help you decide when to launch during "last flights" rounds.

Scores can be saved and edited, so you can keep an electronic score card during contests.

This app will be added to the bottom of the Main Menu.

[![F3K score](http://img.youtube.com/vi/SAaVfNJSD7Y/hqdefault.jpg)](http://www.youtube.com/watch?v=SAaVfNJSD7Y "Click on the image to play Youtube video")

## F5J score keeping
This app will be added to the bottom of the Main Menu.

## Vibes on Event
This app can produce haptic vibes in a similar way to Sounds on Events. I have made it for my DS-12, which only has an internal haptic unit. On radios with haptic gimbals, it will only vibrate the right stick.

This app will be added to the bottom of the Advanced Properties Menu.

## Print global variables
This app can be used to test if some variables have leaked to the global Lua environment, because they were not declared `local`. The list is printed to the Lua console, and globals defined by the JETI Lua API are filtered out.

This app will be added to the bottom of the Applications Menu.
