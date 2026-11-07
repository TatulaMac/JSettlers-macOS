# Changelog

All notable changes of **JSettlers macOS** compared to upstream
[settlers-remake](https://github.com/paulwedeck/settlers-remake) are listed here, newest version first.
The version numbers are specific to this macOS build; upstream does not number its versions (it only shows the git commit).

## [0.6.0-alpha] - first public release

Based on [PR #92](https://github.com/paulwedeck/settlers-remake/pull/92) of upstream (Apple Silicon support), commit `47d1d4e`.
Every change below is a separate file in the [`patches`](patches) folder.

### Packaging and platform
- Native Apple Silicon (arm64) app in a DMG. The Java runtime is bundled, nothing has to be installed.
- OpenGL (JOGL) is the default graphics backend on macOS (the Vulkan/MoltenVK backend showed a gray game screen).
- The app works in `~/Library/Application Support/JSettlers` (the game writes logs and replays into its working directory,
  which is not writable when an app is started from Finder - "Start game" used to fail silently).
- The window title and the top right corner show the release version instead of the git commit.

### Fixed
- **LAN multiplayer** (patch 01): a game hosted on a Mac was not visible to other computers. The server announcement was sent to an IPv6 address first;
  on macOS this failed, the IPv4 announcement was never sent and the announcing stopped for good. It is now sent separately on every network interface
  and one failing destination no longer stops the others.
- **End-of-game statistics** (02): all players were shown as `HUMAN`. AI players now show their real type (e.g. `AI_VERY_HARD`), human players their name
  (game setting "player name", default: the Mac user name).
- **Spell "Gifts of the gods"** (03): mana was spent but often nothing appeared (0 stacks were possible, stacks could be empty and about a third of the
  possible goods cannot be dropped). Now 1-5 stacks of 1-8 droppable goods (no gold, no gems) appear on free own or neutral ground.
- **Soldiers chasing passers-by** (04): soldiers ran across the map after every enemy unit within 30 fields, including geologists, so one AI geologist could
  lure a whole army away and orders could not be followed. Non-military enemy units (geologists, pioneers, thieves, carriers) are now only attacked
  within 3 fields. Military units and priests are still engaged from the full distance.
  (`Ctrl` + right click = forced move that ignores enemies, `Alt` + right click = patrol; on a Mac: Control + two-finger click.)
- **Text quality and size** (05): all texts are 50 % bigger (setting `font-scale`) and have no colored (cyan) fringe any more. The glyph texture was
  uploaded with swapped color channels (ARGB instead of RGBA). Every font size now has its own glyph texture rendered directly in its final pixel size
  (before, one 30 px texture was scaled down to 11-17 px and looked jagged). On macOS "Helvetica Neue" is preferred (fallback Arial).
- **Game speed and frame rate limit** (10): the game ran about 10 % slower than the set speed (`Speed 0.9` at 1.0x) because the game clock waited a fixed
  50 ms after every step. It now follows the real time. A frame rate limit of 60 only reached about 52 FPS because of a coarse timer; frames are now paced
  with nanosecond precision.
- **Amazon storage building: black artifact** (11): the building consists of 6 sprite parts and each part carries the shadow of the whole building.
  The translucent shadow (53 % opacity) was drawn six times on top of itself and came out solid black. It is now drawn once.
  (The game data is fine; the same artifact is present in the unmodified Android version.)
- **In-game messages** (08, 09): the texts overlapped the left side panel. They are now placed right of the panel
  (setting `message-offset-x`, default 50 px). Messages of rice farms and beekeepers showed their raw key (`Cannot_find_work_rice_farm`); they have proper
  texts now, and any other message without a translation shows a readable text instead of the raw key.

### Added
- **Click on a message jumps to its place** (08), e.g. to the woodcutter that cannot find trees. Messages are colored by kind
  (attacks red, "no work found" orange, minerals green).
- **"No soldier available" message** (08): a tower, large tower or castle that has waited 5 seconds for its first soldier (nobody in reach, so its border
  does not expand) reports it; repeated every 2 minutes while it is still empty.
- **Building costs in the build menu** (06): hovering over a building shows the materials needed (e.g. `Plank: 2, Stone: 3`).
- **Tooltips next to the mouse cursor** (07) instead of under its tip (settings `tooltip-offset-x` / `tooltip-offset-y`).
- **Settings file** `~/Library/Application Support/JSettlers/tweaks.properties` (created at the first start, commented) with `font-scale`, `tooltip-offset-x`,
  `tooltip-offset-y`, `message-offset-x` and `jvm-options`. The file used is recorded in `tweaks-status.txt` next to it.

### Known issues
- With the OpenGL (JOGL) backend the frame rate is limited to roughly 90 FPS and drops by about 10 FPS when zoomed out or in big battles: every frame is
  read back from the graphics card and copied into the window by Java (`GLJPanel`). The setting `jvm-options=-Dsun.java2d.metal=true` in `tweaks.properties`
  can be tried (not tested).
- The app is signed ad hoc and not notarized by Apple, so macOS asks for a confirmation at the first start (see the README).
- Only Apple Silicon Macs are supported by this build. Not tested with macOS versions other than macOS 27.
- Not all message texts are translated into all languages; missing ones are shown in English.
