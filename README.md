# SoarJETI sailplane apps for JETI radios
You can find the Lua source code for all of the apps under [Src](https://github.com/jfrickmann/SoarJETI/tree/main/Src). Radios with plenty of memory can run these source files as is, but I have also added compiled files under [Apps](https://github.com/jfrickmann/SoarJETI/tree/main/Apps), and these will consume less memory and start up faster, because they do not have to be compiled from source by the radio. I have a DS-12 myself, and I have not tested the apps on other radio models. But I doubt that the score keeping apps will be able to run on older radios with small memories.
In addition to the score keeping apps for sailplanes, I have also included a couple of utility apps that I find useful.

To install the apps on your transmitter, connect the transmitter to your computer, and copy over the files from *either* [Apps](https://github.com/jfrickmann/SoarJETI/tree/main/Apps) *or* [Src](https://github.com/jfrickmann/SoarJETI/tree/main/Src) in this repository to the *Apps* folder on your transmitter's SD-card. Then, navigate to **Applications**, **User Applications** on your radio's menus, and install the apps for the currently loaded model. Notice that the apps will be added to the radio's menus as described below for each app.

## F3K score keeping

[![F3K score](http://img.youtube.com/vi/SAaVfNJSD7Y/0.jpg)](http://www.youtube.com/watch?v=SAaVfNJSD7Y "F3K score")

This app will be added to the bottom of the Main Menu.

## F5J score keeping
This app will be added to the bottom of the Main Menu.

## Vibes on Event
This app can produce haptic vibes in a similar way as Sounds on Events. I have made it for my DS-12, which only has one internal vibrator. On radios with haptic gimbals, it will only vibrate the right stick.

This app will be added to the bottom of the Advanced Properties Menu.

## Print global variables
This app can be used to test if some variables "leak" to the global environment, because they were not declared `local`. The list is printed to the Lua console, and globals defined by the JETI Lua API are filtered out.

This app will be added to the bottom of the Applications Menu.
