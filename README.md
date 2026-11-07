# JSettlers macOS

**Unofficial macOS build (Apple Silicon) of [JSettlers / settlers-remake](https://github.com/paulwedeck/settlers-remake)** - an open source remake of
*The Settlers III*. Download the DMG, drag the app to Applications, play. **You do not need to install Java.**

> This project is not affiliated with, endorsed by or supported by Ubisoft, Blue Byte or the upstream JSettlers project.
> The game data (graphics and sound) of *The Settlers III* is **not included** - you need your own copy (see below).

Current version: **0.6.0-alpha** (alpha: expect bugs; saved games may become invalid in future versions).
See the [changelog](CHANGELOG.md) for everything that differs from upstream.

## What you need
- A Mac with **Apple Silicon** (M1 or newer). Developed and tested on macOS 27; other versions are untested.
- The game data of **The Settlers III**: the folders `GFX` and `SND` (and optionally `MAP`) of an original installation.
  The free demo of the Amazons also works. You do not have to run the original game, only copy these folders somewhere
  (the original game is a Windows game; installing it on a PC and copying the folders is enough).
  Tested with the GOG version 1.60 data.

## Installation
1. Download `JSettlers-macOS-v0.6.0-alpha-arm64.dmg` from the [Releases](../../releases) page.
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

## Tips
- `Ctrl` + right click (on a Mac: Control + two-finger click) = forced move that ignores enemies; `Alt` + right click = patrol.
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
useful messages, correct game speed, better soldier behavior, fixes for the "Gifts of the gods" spell, end-of-game statistics and
the Amazon storage building.

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
