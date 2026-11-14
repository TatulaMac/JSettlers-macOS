# Changelog

All notable changes of **JSettlers macOS** compared to upstream
[settlers-remake](https://github.com/paulwedeck/settlers-remake) are listed here, newest version first.
The version numbers are specific to this macOS build; upstream does not number its versions (it only shows the git commit).

## [0.6.3-alpha] - HD graphics, automatic work area, smithies, messages, growth

Same upstream base as before ([PR #92](https://github.com/paulwedeck/settlers-remake/pull/92), commit `47d1d4e`). New patches: `17-hd-graphics.patch`,
`18-smithy-output.patch`, `19-auto-work-area.patch`, `20-convert-specialists-to-bearers.patch`, `21-faster-growth.patch`,
`22-settler-messages-and-tool-demand.patch`. Changed patches: `08-in-game-messages.patch` and `12-language-selection-czech.patch` (new messages).

### Added
- **HD graphics** (patch 17): *Settings > HD graphics* (Yes/No, default No; restart needed). Units, buildings, objects, terrain and icons are enlarged 2x
  on the player's own computer from his own game files; the result is stored in `~/Library/Application Support/JSettlers/hd` and is never distributed.
  It uses the AI engine Real-ESRGAN ncnn Vulkan (MIT license) if it is part of the app, otherwise a built-in enlarger. The first start takes a few minutes.
- **Smithy output** (patch 18): the panels of the tool smithy and the weapon smithy show the finished products lying at the building (icon and count per
  kind, in extra rows of 5 icons when there are many).
- **Automatic work area** (patch 19): lumberjacks, stonecutters, fishers, waterworks, foresters, rice farms and beekeepers move their work area to the
  nearest work when there is nothing left to do (the lumberjack and stonecutter areas are bigger). Farms and winegrowers return to their default area, or
  move up to twice the work radius to the side of an obstacle or of a full field. Setting the work area by hand still works. The beekeeper's work area is
  twice as big as before.
- **Turn thieves and geologists back into carriers** (patch 20), like the pioneers; the converted units stay selected (also for pioneers); the long texts of
  the conversion buttons fit on the button.
- **New messages** (patches 08, 12, 22), in English and Czech: the tool for a building is missing; no free settler is available for a building; no free
  settler is available for arming soldiers in the barracks. The messages appear after 10 seconds and are repeated every 2 minutes while the problem lasts.
- **Tool smithy follows the settings** (patches 18, 22): it produces shovels and hammers up to the numbers of diggers and bricklayers set in the settlers
  settings, so it reacts whenever you raise these numbers during the game and the tools are missing in the storage (before, it worked only while a
  construction site was waiting). It does not produce tools that are already lying at the building or in a storage.

### Changed
- **Faster growth** (patch 21): corn grows 7 minutes (was 10), wine 6 (was 9), rice 7 (was 11), beehives 60-120 s when empty and 75-120 s while growing.
  Farmers, winegrowers, rice farmers and beekeepers pause 2 s instead of 8 s after every job. Ripe crops still rot after 3 minutes.
- **Barracks arm soldiers only from free settlers** (patch 22): carriers reserved by the minimum carrier setting stay carriers. Before, the barracks took
  them and the carriers were missing in the production.
- **Harvesting has priority** (patch 19): farmers, winegrowers, rice farmers and beekeepers harvest ripe crops also in former work areas and in the default
  area before they plant, so crops do not rot after the work area has been moved.
- The HD notice at the first start is shorter; the window is simply closed when the enlarging is done.

### Fixed
- Missing messages: a building that could not be occupied because of a missing tool or settler stayed silent (patches 08, 12, 22). Settlers reserved as
  carriers by the settings were counted as free, so no message appeared.
- False "cannot find work" messages of the workers (patch 19).
- A thief carrying nothing dropped one piece of wood when it was turned back into a carrier (patch 20).
- Typo in the header of the Czech translation file (patch 12).

## [0.6.2-alpha] - control groups, peace time

Same upstream base as before ([PR #92](https://github.com/paulwedeck/settlers-remake/pull/92), commit `47d1d4e`). New patches: `15-control-groups.patch`, `16-peacetime.patch`.

### Added
- **Control groups** (patch 15): select units and press **Control + 1 ... 9, 0** to store them in a group, press **1 ... 9, 0** to select that group
  again. Works for every unit type that can be selected (soldiers, thieves, pioneers, geologists, ...), so a group of geologists in a guarded mountain
  can be called back with one key. Details: only units are stored (not buildings); a selection with several types keeps the same rule as a manual
  selection (the type with the highest priority wins, e.g. soldiers before geologists); a unit is member of one group only (the last one it was
  added to, as in other strategy games); dead units are dropped from the group; Control + number with
  nothing selected empties the group; the groups are part of the user interface only (not saved with the game, not sent to other players).
- **Peace time** (patch 16): the "Peacetime" selection of the new-game screen (single player and the host of a multiplayer game) was a placeholder
  with only "without". It now offers 10, 20, 30, 40, 50 and 60 minutes. While the peace time runs, nobody attacks anybody (soldiers, towers and
  castles do not react to enemies); when it is over, the soldiers look around once more and fight as usual. The remaining time is shown at the top
  right, left of the zoom ("Peace time: 9:41", Czech: "Doba míru: 9:41"), and disappears when the peace time is over. The time is counted in game
  time (it stops while the game is paused and runs faster with a higher game speed). The host's setting is sent to all players as a normal game
  task, so it is the same for everybody and part of replays (players who join a multiplayer game see the selection greyed out; the countdown in the game shows the time). It is not stored in savegames (a loaded game starts without peace time). Texts are
  in English and Czech.

### Fixed
- **Marketplace shadow (Asian)** (patch 11): the two parts of the marketplace each carried the shadow of the whole building, so the shadow became a
  solid black area (the same problem as the Amazon storage). Only one part draws the shadow now.
- **Promote tooltip** (patch 06): once a soldier type has reached the highest level, hovering over the (invisible) promote button no longer shows
  "Promote ...".
- A modifier key (Control, Shift, Option, Command) pressed alone (patch 15) is no longer treated as a key event. It used to block the next key press until
  it was released, so no shortcut could be combined with a modifier key.
- **Keyboard focus** (patch 15): the game screen now takes the keyboard focus when the mouse enters it or is pressed on it. Before, nothing gave
  it the focus, so keyboard shortcuts could stay without any effect on the Mac.

## [0.6.1-alpha] - language selection, thieves, zoom indicator

Same upstream base as 0.6.0-alpha ([PR #92](https://github.com/paulwedeck/settlers-remake/pull/92), commit `47d1d4e`).
New patches: `12-language-selection-czech.patch`, `13-thief-fixes.patch`, `14-zoom-indicator.patch`.

### Fixed
- **Thieves never stole anything** (patch 13): a thief ordered to steal walked to the pile, started to take a good and aborted the action by itself after
  a moment to walk back home empty-handed, then repeated this forever. The "go home" order was set *before* the stealing instead of after it, and that
  order has a higher priority than the stealing. Now the thief takes one good, carries it back to its own ground, drops it there and waits for the next
  order. If the pile is empty when it arrives, it walks back. A thief ordered from enemy ground no longer takes that spot as its home.
- **Soldiers did not notice thieves** (patch 13): since patch 04 of 0.6.0 (soldiers only attack non-military units within 3 fields) swordsmen and
  pikemen noticed a thief only when it was 3 fields away. A thief standing on the ground of the soldier's team is now attacked from the full distance.
  (Archers still ignore thieves until another soldier has hit them - that is how the game was designed.)

### Added
- **Zoom indicator** (patch 14): the current zoom is shown at the top right of the game screen, left of the frame rate, version and time
  (e.g. `Zoom: 100%`, in Czech `Měřítko: 100%`). 100% is the original size. It makes it easy to get back to the normal view after zooming in or out.
- **Language selection** (patch 12): *Settings* in the main menu has a new **Language** list. The menus are rebuilt when the language is changed,
  so no restart is needed. Available: **English** (default) and **Czech**. The choice is saved in the game settings (setting `locale`).
  Switching back works completely: the score table after a game and the map filter buttons (e.g. *Imported*) are translated again as well
  (they used to keep the texts of the previous language).
- **Complete Czech translation** (`labels_cs.properties`, all 480+ texts): menus, buildings, materials, settlers, spells, messages, tooltips, dialogs.
  Texts that are missing in a translation fall back to English.
- **Czech characters in the in-game font**: the glyph atlas of the in-game text (messages, tooltips, panels) now contains
  the letters ě š č ř ž ý á í é ú ů ď ť ň and their capitals; before, they were not drawn.
- **Fixed a glyph texture bug** (patch 12): the quads of the characters in the last line of the glyph texture reached below the texture, so the bottom
  pixel row was stretched into a solid block under letters with a flat bottom (e.g. z, e, u). It was invisible before because those lines contained
  only rarely used characters.
- To add another language: add `labels_xx.properties` next to `labels_en.properties` and one entry in `GameLanguage.java`.

### Changed
- Documentation: the control hints are written for the Mac now (Control + two-finger click = forced move / recall, Option + two-finger click = patrol).
- **English is now always the default language.** Before, the language of the computer was used when a matching translation existed (de, es, pl, ...).
  Those translations are still in the game (incomplete, English fallback) but are not offered in the language list yet.
  An advanced user can still set `locale=de` (any language code) in the game settings file.
- English texts: fixed typos (e.g. "Summon Sto", "Irrigate dessert", "Musicvolume", "recruted soldiers", "Metalurgist"), added the missing texts of
  the settings (GUI scale, AI tower focus) and of the server editor (username). The settings entries "timerless redraw" and "system default" are
  translatable now.

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
