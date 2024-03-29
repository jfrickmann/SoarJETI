# SoarJETI sailplane apps for JETI radios

This is a collection of score keeping apps for sailplanes. In addition, I have also included a couple of utility apps that I find useful.

## Installation

- Download the [Zip file](https://github.com/jfrickmann/SoarJETI/archive/refs/heads/main.zip) to your computer and extract it.
- Connect the transmitter to your computer, and copy everyting in the **Apps** folder over to the **Apps** folder on your transmitter's SD-card.
- Navigate to **Applications**, **User Applications** on your radio's menus, and add the app(s) to the currently loaded model. They will be added to the transmitter menus as described below for each app. You will notice that there are two files for each app. The first file is a compiled .lc file. It uses less memory and starts up faster. You want to use this one on radios with small memories. The second file is the .lua file with the full source code. It runs fine on radios with big memories.

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

This is a score keeping app for F5J electric gliders. It is useful for both practice and contests.

It provides its own timers implemented in Lua, and does not rely on the built-in timers. Therefore, if you want to test the app, it may be a good idea to first make a copy of your model and delete the timers you set up, to avoid duplicate time calls. The timers from the app can also be added to the Main Screen as Displayed Telemetry.

The flight timer starts when you start the motor. It counts up the motor time to 30 sec. and then another 10 sec. until the start height is recorded by the AMRT device. The flight timer is stopped by a switch. You can adjust the flight time as you wish before the flight, and you can also adjust it during the flight if you want to come back sooner and practice a landing after finding lift.

The app can show cell voltages from a MULi6S LiPo battery sensor and give a low battery warning. It also works with an altimeter to call out the start height and get altitude calls during flight. Using an altimeter is not allowed under the F5J rules, but the height calls can be turned off with a switch to comply with the spirit of the rules.

Scores can be saved and edited, so you can keep an electronic score card during contests.

This app will be added to the bottom of the Main Menu.

[![F5J score](http://img.youtube.com/vi/IRz6s9MLGiI/hqdefault.jpg)](http://www.youtube.com/watch?v=IRz6s9MLGiI "Click on the image to play Youtube video")

## Vibes on Event
This app can produce haptic vibes in a similar way to Sounds on Events. I have made it for my DS-12, which only has an internal haptic unit. On radios with haptic gimbals, it will only vibrate the right stick.

This app will be added to the bottom of the Advanced Properties Menu.

## Print global variables
This app can be used to test if some variables have leaked to the global Lua environment, because they were not declared `local`. The list is printed to the Lua console, and globals defined by the JETI Lua API are filtered out.

This app will be added to the bottom of the Applications Menu.
