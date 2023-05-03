# Zig Software Renderer

Tentative software renderer in zig

# Hell World

This branch `ldjam` contains the game _Hell world_ created in a few days to test the framework. 

You can find an online version of the game here : https://valden.itch.io/hell-world

The game use software rendering to display it's graphics. It generates a texture that can then be displayed by the backend on the screen. The big adventage of that is that the game is extremely portable (it's thanks to that technique that "DOOM can run on everything" became a meme). While a little bit complicated, the audio works kinda the same : the backend only need to call `init` then `gen_samples` on an audio thread and everything else is handled.

Game resources are bundled with the executable using `@embedFile()`. On the desktop target debug mode, some .json files (for the death explosion and the .tmj level files) are watched for change and dynamicaly reloaded and parsed through the `loadJsonResource` function in `game.zig`.

The game can be build as a standalone executable for windows (`zig build exe` or `zig build run`) via SDL or as a HTML5 game (`zig build web` then serve the `zig-out/web` folder with a local server like `python -m http.server` and navigate to `localhost/index.html`). The build also show how to use the itch.io cli butler to publish the game (`zig build web-publish` but you would need to have my credentials to actually do that).

This code is in the state I finished the project, and is kinda messy. At the moment SDL is vendored with the repository and some parts of the engine could be better refactored. The game code is not in great shape too. The build.zig is also kinda messy because the HTML5 build was a big iterative process.

The HTML5 build is interesting because it create 2 wasm modules : one for the core gameplay and one for the audio thread. The game can send (for the moment very simple )commands to the audio thead via the game.playSound function. That function actually calls the JS code, that relays the message thought a port to the audioWorker that then calls a function in the audio WASM instance. What a journey.

The "parts" of level desing are made with [Tiled](https://www.mapeditor.org/). The game picks a layer randomly (except in debug where the bottom layer will always be picked first to make testing easyer), and then create one "block" for each rectangle in the layer at the correct offset.

External libraries used : 
* [dr_wav](https://github.com/mackron/dr_libs/blob/master/dr_wav.h)
* [dr_mp3](https://github.com/mackron/dr_libs/blob/master/dr_mp3.h)
* [stb_vorbis](https://github.com/nothings/stb/blob/master/stb_vorbis.c)
* [stb_image](https://github.com/nothings/stb/blob/master/stb_image.h)
* [SDL2 (window backend)](https://www.libsdl.org/) (disabled because I couldn't get the wasm module to build)
* [Zig callocators](https://gist.github.com/pfgithub/65c13d7dc889a4b2ba25131994be0d20)  (wraps zig allocators so they can be used with C code, very usefull for wasm)