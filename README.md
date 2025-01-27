# StatusEffectLibrary
 Simplify the process for implementing your own status effects into The Binding of Isaac: Repentance.

## Features
- Register completely custom status effects with an identifier, which it turned into both an enum and a bitmask
- Can render multiple icons from multiple effects at once. If you have REPENTOGON, it can render directly where other status effects are meant to be displayed on the enemy
- Primary usage is for enemies, but can be used for players as well
- Many different customization options for your status effect, per application and/or the effect overall
- Works in tandem with multiple mods using StatusEffectLibrary, so icons from multiple mods can be rendered side to side

## Installation
Setting up the library is simple. If you look at the main code of this repository, you'll see a main.lua that should work as intended. Just to put it within steps though:
1. First, [download the latest release, found here.](https://github.com/BenevolusGoat/status-effect-library/releases/)
2. Place the file anywhere in your mod. I recommend putting it in a neatly organized place, such as in a folder named "utility" that's within a greater "scripts" folder.
3. In your `main.lua` file, `include` the file. StatusEffectLibrary is a global, so you can access it at any time with "StatusEffectLibrary".
4. Within the status_effect_library.lua file, change out the "SELExample" variable with a global for your mod. If you don't have a global, it's merely used as a name identifier, and you can go to line 43 to change the string to "YourModNameHere's Status Effect Library".

## To find out how to use, please open the wiki
https://github.com/BenevolusGoat/status-effect-library/wiki
