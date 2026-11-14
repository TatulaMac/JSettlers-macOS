# JSettlers macOS

**Unofficial macOS build (Apple Silicon) of [JSettlers / settlers-remake](https://github.com/paulwedeck/settlers-remake)** - an open source remake of
*The Settlers III*. Download the DMG, drag the app to Applications, play. **You do not need to install Java.**

> This project is not affiliated with, endorsed by or supported by Ubisoft, Blue Byte or the upstream JSettlers project.
> The game data (graphics and sound) of *The Settlers III* is **not included** - you need your own copy (see below).

Current version: **0.6.3-alpha** (alpha: expect bugs; saved games may become invalid in future versions).
See the [changelog](CHANGELOG.md) for everything that differs from upstream.

## What you need
- A Mac with **Apple Silicon** (M1 or newer). Developed and tested on macOS 27; other versions are untested.
- The game data of **The Settlers III**: the folders `GFX` and `SND` (and optionally `MAP`) of an original installation.
  The free demo of the Amazons also works. You do not have to run the original game, only copy these folders somewhere
  (the original game is a Windows game; installing it on a PC and copying the folders is enough).
  Tested with the GOG version 1.60 data.

## Installation
1. Download `JSettlers-macOS-v0.6.3-alpha-arm64.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **JSettlers** to the **Applications** folder.
3. Start JSettlers. macOS may say the app is damaged or from an unidentified developer. It is not signed by Apple (it is signed ad hoc),
   so you have to allow it once. Do **one** of these:
   - Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to JSettlers; or
   - run in Terminal: `xattr -dr com.apple.quarantine /Applications/JSettlers.app`
4. At the first start the game asks for the folder of your Settlers III installation. Select the folder that contains `GFX` and `SND`.

## Files and settings
Everything the game writes is in `~/Library/Application Support/JSettlers`:

| What | Where |
|---|---|
| Settings (text size, tooltip and message positions) | `tweaks.properties` |
| Logs and replays of your games (please attach them to bug reports) | `logs/` |
| Your own maps (`.rmap`) | `maps/` |

`tweaks.properties` is created at the first start, every setting is explained in the file. Edit it, save it and restart the game.

| Setting | Default | Meaning |
|---|---|---|
| `font-scale` | 1.5 | size of all texts (1.0 = original) |
| `tooltip-offset-x`, `tooltip-offset-y` | 32, 0 | tooltip distance from the cursor in pixels |
| `message-offset-x` | 50 | distance of the in-game messages from the right edge of the left panel in pixels |
| `jvm-options` | (off) | experimental Java options |

## Language
The game starts in **English**. To change the language open **Settings** in the main menu, choose a language in the **Language** list and click OK;
the menus switch immediately, no restart is needed. Available languages: **English** and **Czech (Čeština)**.
Texts that are not translated are shown in English. Translations are plain text files
(`labels_xx.properties`); contributions of other languages are welcome (see the [changelog](CHANGELOG.md) of 0.6.1).

## HD graphics (optional)
**Settings > HD graphics = Yes**, then restart the game (the default is No). At the first start the game enlarges the graphics of **your own** game files
(units, buildings, objects, terrain and icons) 2x on your computer. This takes a few minutes; close the window when it is done. The enlarged images are stored only
in `~/Library/Application Support/JSettlers/hd`; they are never part of this project or of the DMG. Delete that folder to start over.
If the app contains the AI engine ([Real-ESRGAN ncnn Vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan), MIT license) the enlarged images have
better colours, otherwise a built-in enlarger is used.

## Tips
- **Control + two-finger click** (the secondary click of your trackpad; with a mouse: Control + right click) = forced move: the selected units walk
  there and ignore enemies on the way (recall).
- **Option + two-finger click** = patrol between the current position and the clicked position.
- **Control groups:** select units and press **Control + 1** (to **9** and **0**) to store them in a group; press **1** (to **9** and **0**)
  to select the group again. It works for soldiers, thieves, pioneers, geologists and all other units, so a group of geologists can be called
  back with one key without selecting them one by one. A unit belongs to one group only (the last one it was stored in). Units that died are dropped from the group. A group is kept until you overwrite it
  (Control + number with nothing selected empties it); groups are not saved with the game. Buildings cannot be stored.
- **Peace time:** when creating a game (single player, or as the host of a multiplayer game) you can choose a peace time of 10 to 60 minutes. Nobody
  attacks until it is over; the countdown is shown at the top right, left of the zoom. It is not saved with the game.
- **Automatic work area:** lumberjacks, stonecutters, fishers, waterworks, foresters, rice farms and beekeepers move their work area to the nearest
  work when nothing is left to do, so you do not have to click it again and again; farms and winegrowers return to their default area or move a bit
  to the side of an obstacle. You can still set the work area by hand. Farmers, winegrowers, rice farmers and beekeepers harvest ripe crops of
  former work areas first, so they do not rot.
- **Messages about missing workers:** if a building cannot be occupied you are told why: no tool, or no free settler (carriers reserved by the minimum
  carrier setting are not free). The same message appears if the barracks cannot arm soldiers because no free settler is left; barracks never take
  settlers from the reserved carriers.
- Thieves and geologists can be turned back into carriers (like pioneers) with a button in the selection panel; the converted units stay selected.
- The tool smithy and the weapon smithy show the finished products lying at the building. The tool smithy also produces shovels and hammers up to the
  numbers of diggers and bricklayers set in the settlers settings.
- A plain two-finger click on a spot is the normal move command. A thief ordered next to a pile of enemy goods steals it and carries it home.
- The **zoom** is shown at the top right, left of the frame rate (100% = original size, one image pixel per screen pixel).
- Click on a message at the bottom of the screen to jump to the place it is about.
- LAN game: the host opens the LAN tab, clicks "Start local server" and creates a game; the others see it in the list.
  All players must use the same version.
- The upstream [manual](https://github.com/jsettlers/settlers-remake/wiki/JSettlers-Manual) describes the controls.

## Reporting bugs
Open an issue here and attach the log folder of the game in question (`~/Library/Application Support/JSettlers/logs/...`), tell us the game time
and the version shown in the top right corner of the game.

## What is different from upstream?
This build is [PR #92](https://github.com/paulwedeck/settlers-remake/pull/92) (Apple Silicon support, commit `47d1d4e`) plus the patches in
[`patches`](patches), listed in the [changelog](CHANGELOG.md): LAN multiplayer on macOS, readable bigger text, building costs in the build menu,
useful messages, correct game speed, better soldier behavior, fixes for the "Gifts of the gods" spell, end-of-game statistics,
the Amazon and Asian storage/market buildings, a language selection (English, Czech), thief fixes, a zoom indicator, control groups
(Control + number), a selectable peace time, optional HD graphics, an automatic work area, faster growth of crops and more messages
about missing tools and settlers.

## Building it yourself
You need a Mac with Apple Silicon, git, Xcode command line tools and JDK 17 (`brew install --cask temurin@17`).

```
bash build-jsettlers-macos-dmg.sh
```

The script downloads the upstream source code, applies the patches, compiles the game, bundles Java and creates the DMG
(`~/JSettlers-build/dist`). The patches are embedded in the script and are also available as separate files in [`patches`](patches).
Every release also contains a ZIP with the complete, already patched source code (`JSettlers-macOS-vX.Y.Z-source.zip`).

## License and credits
- JSettlers / settlers-remake is released under the **MIT license** (see [LICENSE](LICENSE)). Authors: Paul Wedeck, Michael Zangl, Andreas Eberle,
  Andreas Butti and many other contributors. Apple Silicon support: Kev Zettler (PR #92).
- The patches and scripts in this repository are released under the same MIT license.
- The audio libraries (LGPL: JLayer, Tritonus, MP3SPI, VorbisSPI, JOrbis, J-Ogg) and the JAXB libraries are shipped as separate `.jar` files inside the app.
  The app also contains an OpenJDK runtime (GPL v2 with Classpath Exception). More details are in `THIRD-PARTY-NOTICES.txt` inside the DMG.
- *The Settlers* is a trademark of its owner; the game data is not distributed here.
