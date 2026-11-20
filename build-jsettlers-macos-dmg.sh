#!/usr/bin/env bash
#
# JSettlers macOS - build script
#
# Builds the unofficial macOS (Apple Silicon) edition of JSettlers (settlers-remake) into a DMG.
# Java is bundled inside the app, so the people who download the DMG do not need to install anything.
#
# Usage (in Terminal):
#     bash build-jsettlers-macos-dmg.sh
#
# What the script needs: a Mac with Apple Silicon, git, JDK 17 (brew install --cask temurin@17) and an internet
# connection (Gradle downloads the dependencies). The results are placed in:
#     ~/JSettlers-build/dist/JSettlers-macOS-v0.6.4-alpha-arm64.dmg       (the app, this is what users download)
#     ~/JSettlers-build/dist/JSettlers-macOS-v0.6.4-alpha-source.zip      (complete, already patched source code)
#
# How it works: it downloads the upstream source code (https://github.com/paulwedeck/settlers-remake, the state of
# pull request #92 "Apple Silicon support", commit 47d1d4e), applies the patches embedded below (the same patches
# are in the "patches" folder of the project repository), compiles everything and packs it into JSettlers.app.
#
set -euo pipefail

RELEASE_VERSION="0.6.4-alpha"   # shown in the game (window title and top right corner) and used in the file names

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- checks
[[ "$(uname -s)" == "Darwin" ]] || die "This script is meant for macOS."
[[ "$(uname -m)" == "arm64" ]] || die "This script is meant for Apple Silicon (arm64). On an Intel Mac the result would be unusable."
command -v git >/dev/null 2>&1 || die "git is missing (install it with: xcode-select --install)."

JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null)" || die "JDK 17 not found. Install it with: brew install --cask temurin@17"
export JAVA_HOME
for tool in java jlink jpackage; do
	[[ -x "$JAVA_HOME/bin/$tool" ]] || die "'$tool' is missing in $JAVA_HOME. You need the full JDK 17, not only a JRE."
done
say "Using Java: $("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"

# ---------------------------------------------------------------- source code
WORK="${JSETTLERS_BUILD_DIR:-$HOME/JSettlers-build}"
SRC="$WORK/settlers-remake"
TESTED_COMMIT="47d1d4e"     # state of PR #92 this build was made and tested with
mkdir -p "$WORK"

if [[ ! -d "$SRC/.git" ]]; then
	say "Downloading the source code"
	git clone https://github.com/paulwedeck/settlers-remake.git "$SRC"
fi
cd "$SRC"

say "Switching to PR #92 (Apple Silicon support)"
git fetch -q origin pull/92/head
git reset -q --hard
git clean -fdq   # also removes new files of a previous build (otherwise the patches would not apply a second time)
git checkout -q --detach FETCH_HEAD
HEAD_SHORT="$(git rev-parse --short HEAD)"
if [[ "$HEAD_SHORT" != "$TESTED_COMMIT"* && "$TESTED_COMMIT" != "$HEAD_SHORT"* ]]; then
	echo "WARNING: PR #92 has changed in the meantime (it is at $HEAD_SHORT, the tested state was $TESTED_COMMIT)."
	echo "         The build is attempted anyway, but the result may differ or the patches may not apply."
fi

# ---------------------------------------------------------------- default graphics backend
# On macOS the Vulkan backend (MoltenVK) is the default, but it shows a gray screen here.
# The default backend is switched to JOGL (OpenGL).
say "Setting JOGL as the default graphics backend on macOS"
F="go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/EBackendType.java"
perl -0pi -e 's/(JOGL\(JOGLContextCreator::new, "jogl", Platform\.MACOSX, )null(, null\))/$1Platform.MACOSX$2/;
              s/(VULKAN\(VulkanContextCreator::new, "vulkan", null, )Platform\.MACOSX(, VK::getFunctionProvider\))/$1null$2/' "$F"
grep -q 'JOGL(JOGLContextCreator::new, "jogl", Platform.MACOSX, Platform.MACOSX, null)' "$F" \
	|| die "Changing the default backend (JOGL) failed - $F looks different than expected."
grep -q 'VULKAN(VulkanContextCreator::new, "vulkan", null, null, VK::getFunctionProvider)' "$F" \
	|| die "Changing the default backend (Vulkan) failed - $F looks different than expected."

# ---------------------------------------------------------------- version label
# The game shows the git commit in the window title and in the top right corner. Show the release version instead.
say "Setting the version label to $RELEASE_VERSION"
RELEASE_VERSION="$RELEASE_VERSION" perl -pi -e 's/localRev\.substring\(0, 8\)/"$ENV{RELEASE_VERSION}"/' jsettlers.common/build.gradle
grep -q "\"$RELEASE_VERSION\", localRev" jsettlers.common/build.gradle || die "Setting the version label failed - jsettlers.common/build.gradle looks different than expected."
find . -name CommitInfo.java -path "*generated*" -delete   # make sure the label is generated again

# ---------------------------------------------------------------- patches
# 01 LAN multiplayer: a game hosted on a Mac was invisible to other computers (the announcement stopped after the first IPv6 error).
# 02 End of game: AI players show their type (e.g. AI_VERY_HARD) and human players their name instead of "HUMAN".
# 03 Spell "Gifts of the gods": mana was spent but often nothing appeared.
# 04 Soldiers no longer run across the map after every foreign geologist/pioneer/thief (only within 3 fields).
# 05 Text: 50 % bigger (setting font-scale), sharp glyphs rendered in their final size, no coloured fringe.
# 06 Build menu: hovering over a building shows its cost.
# 07 Tooltips are placed next to the mouse cursor (settings tooltip-offset-x/y).
# 08 Messages: readable texts, new messages ("no soldier available", "tool missing", "no free settler"), colours, click on a message jumps to its place.
# 09 Messages are placed right of the side panel (setting message-offset-x); the settings file is found more reliably.
# 10 Game speed 1.0x is really 1.0x (it was 0.9x) and the frame rate limit is accurate (60 was ~52).
# 11 Amazon storage building: the shadow was drawn six times on top of itself and came out black.
# 12 Language selection in Settings (English default, Czech) with a complete Czech translation, Czech characters in the in-game font.
# 13 Thieves: stealing was aborted by the thief itself (it never took anything); soldiers notice thieves on their own ground from afar.
# 14 Zoom indicator ("Zoom: 100%") left of the frame rate, version and time at the top right of the screen.
# 15 Control groups: Control + 1..0 stores the selected units (soldiers, thieves, pioneers, geologists, ...), 1..0 selects them again.
# 16 Peace time: selectable (10-60 minutes) when a game is created; countdown at the top right; nobody attacks until it is over.
# 17 HD graphics (off by default, switch in Settings): units, buildings, objects, terrain and icons are enlarged 2x on the player's own computer
#    (Application Support/JSettlers/hd), with the built-in enlarger or the optional AI engine (Real-ESRGAN).
# 18 Tool smithy and weapon smithy panels show the finished products lying at the building (icon + count per kind; extra rows if there are many);
#    the tool smithy no longer makes tools that are already lying there waiting to be picked up
# 19 Automatic work area: lumberjack, stonecutter, fisher, waterworks, forester, rice farm and beekeeper (bigger area) move their work area to the nearest work when
#    there is nothing left to do; farm and winegrower return to their default area or move a bit to the side of an obstacle; no more false
#    "cannot find work" messages. Farm, winegrower, rice farm and beekeeper harvest ripe crops of former work areas first, so they do not rot.
# 20 Thieves and geologists can be turned back into carriers (like pioneers); converted units stay selected; long button texts fit.
# 21 Faster growth: corn, wine, rice and beehives grow about a third faster; farmers, winegrowers, rice farmers and beekeepers pause 2 s
#    instead of 8 s after each job.
# 22 "No free settler" messages also appear when carriers are reserved by the minimum carrier setting and for barracks (arming);
#    barracks only arm free settlers, never carriers reserved by the minimum carrier setting;
#    the tool smithy also produces shovels and hammers up to the digger/bricklayer numbers set in the settings.
# 23 Lobby (single player, LAN host/client): selectable player colors (new last column "Color", sent over the network, used in the game);
#    the preview map shows the numbers of the map slots (positions) at the real start points. Changes the network protocol (version 0.6.4+ only).
# (18 also: buildings with 4-5 material buttons, e.g. the Amazon laboratory, get evenly spaced buttons that no longer overlap.)
# (19 also: the winegrower moves its work area over the whole allowed range, because vines grow only on slopes.)
# 24 LAN: new tab "Load game" next to "New match": the host continues a saved game (single player and multiplayer saves are interchangeable).
#    Position, nation and team are fixed by the save, human/computer type can be changed. Every player needs the same save file; a player
#    who misses it gets a message instead of joining. The network clock counts lockstep steps from the saved game time.
# 25 EXPERIMENTAL, LAN only: human players that choose the same color and the same nation play together as ONE player (shared position,
#    shown with the same position number in the lobby). Remove this patch from PATCH_NAMES if it causes trouble.
# (22 also: requests of destroyed or conquered buildings are dropped, so there are no more "no free settler" messages about a ruin.)
# 26 Saving: the message "Game saved." is shown; the list of games shows date AND time of the save; the id of a saved game is the same on all
#    computers of a LAN game (every computer saves when one player saves), so each player can load the save from his own folder.
#    A saved game also remembers the colors of the players (new saves only) and restores them when it is loaded.
# 27 In-game chat for network games: press Enter (or click the chat button of the minimap) to write a message, Enter sends it, Escape cancels.
#    The message is shown to all players with the name and in the color of the sender.
# 28 Network lobby: the guests see the peace time the host selects;
#    the settings of the new-game window (players, resources, peace time) are centered on the same line as their labels;
#    fixes a saved game that was loaded into a LAN game: the clock reported the saved game time to the server while the game was loading, so
#    the server stopped waiting for the players and their commands were executed with a huge delay.
say "Applying the patches"
mkdir -p "$WORK/patches"
cat > "$WORK/patches/01-lan-multiplayer-broadcast.patch" <<'PATCH_EOF'
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/lan/LanServerBroadcastThread.java b/jsettlers.network/src/main/java/jsettlers/network/server/lan/LanServerBroadcastThread.java
index b4e6d4d..65f0eb3 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/lan/LanServerBroadcastThread.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/lan/LanServerBroadcastThread.java
@@ -17,8 +17,15 @@ package jsettlers.network.server.lan;
 import java.io.IOException;
 import java.net.DatagramPacket;
 import java.net.DatagramSocket;
+import java.net.Inet4Address;
 import java.net.InetAddress;
+import java.net.InetSocketAddress;
+import java.net.InterfaceAddress;
+import java.net.NetworkInterface;
 import java.net.SocketException;
+import java.util.Collections;
+import java.util.HashSet;
+import java.util.Set;
 import java.util.Timer;
 import java.util.TimerTask;
 
@@ -26,28 +33,35 @@ import jsettlers.network.NetworkConstants;
 import jsettlers.network.infrastructure.log.Logger;
 
 /**
- * This thread broadcasts a small package over the network to inform LAN members of the server address
- * 
+ * This thread broadcasts a small package over the network to inform LAN members of the server address.
+ * <p>
+ * The package is sent separately on every active IPv4 network interface (directed broadcast + limited broadcast), so that it works on machines with
+ * several interfaces (Wi-Fi, VPN, virtual adapters) and on systems (macOS, Windows) where a single send to 255.255.255.255 does not reach the LAN.
+ * A failing destination never stops the broadcasting of the other destinations.
+ *
  * @author Andreas Eberle
  * 
  */
 public final class LanServerBroadcastThread {
 
-	private final DatagramSocket socket;
 	private final Timer broadcastTimer;
 	private final TimerTask broadcastTask;
 	private final Logger logger;
+	private final Set<String> reportedProblems = new HashSet<>();
 	private boolean active;
 
 	public LanServerBroadcastThread(Logger logger) throws SocketException {
 		this.logger = logger;
-		socket = new DatagramSocket();
 		active = false;
 
 		broadcastTask = new TimerTask() {
 			@Override
 			public void run() {
-				broadcast();
+				try {
+					broadcast();
+				} catch (Throwable t) {
+					report("broadcast", t);
+				}
 			}
 		};
 
@@ -56,22 +70,69 @@ public final class LanServerBroadcastThread {
 
 	private void broadcast() {
 		byte[] data = NetworkConstants.Server.BROADCAST_MESSAGE.getBytes();
+		int port = NetworkConstants.Server.BROADCAST_PORT;
+		boolean sentAnywhere = false;
 
 		try {
-			broadcast(NetworkConstants.Server.BROADCAST_PORT, socket, data);
-		} catch (IOException e) {
-			logger.error(e);
-			logger.warn("Stopped server broadcasting due to exception.");
-			shutdown();
+			for (NetworkInterface networkInterface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
+				if (!networkInterface.isUp() || networkInterface.isLoopback()) {
+					continue;
+				}
+				for (InterfaceAddress interfaceAddress : networkInterface.getInterfaceAddresses()) {
+					if (!(interfaceAddress.getAddress() instanceof Inet4Address)) {
+						continue;
+					}
+					InetAddress local = interfaceAddress.getAddress();
+					InetAddress directed = interfaceAddress.getBroadcast();
+					if (directed != null) {
+						sentAnywhere |= send(local, directed, port, data);
+					}
+					sentAnywhere |= send(local, InetAddress.getByAddress(new byte[] { -1, -1, -1, -1 }), port, data);
+				}
+			}
+		} catch (Throwable t) {
+			report("interfaces", t);
+		}
+
+		if (!sentAnywhere) {
+			// no usable interface found: let the system choose
+			send(null, getLimitedBroadcast(), port, data);
 		}
 	}
 
-	private void broadcast(int udpPort, DatagramSocket socket, byte[] data) throws IOException {
-		InetAddress dst6 = InetAddress.getByAddress(NetworkConstants.Server.MULTICAST_IP6);
-		InetAddress dst4 = InetAddress.getByAddress(new byte[]{-1, -1, -1, -1});
+	private static InetAddress getLimitedBroadcast() {
+		try {
+			return InetAddress.getByAddress(new byte[] { -1, -1, -1, -1 });
+		} catch (java.net.UnknownHostException e) {
+			throw new IllegalStateException(e);
+		}
+	}
 
-		socket.send(new DatagramPacket(data, data.length, dst6, udpPort));
-		socket.send(new DatagramPacket(data, data.length, dst4, udpPort));
+	/**
+	 * Sends one packet from the given local address (or any address if null) to dst.
+	 * 
+	 * @return true if the packet was sent.
+	 */
+	private boolean send(InetAddress local, InetAddress dst, int port, byte[] data) {
+		try (DatagramSocket socket = new DatagramSocket(new InetSocketAddress(local, 0))) {
+			socket.setBroadcast(true);
+			socket.send(new DatagramPacket(data, data.length, dst, port));
+			return true;
+		} catch (IOException e) {
+			report((local != null ? local.getHostAddress() : "any") + " -> " + dst.getHostAddress(), e);
+			return false;
+		}
+	}
+
+	private void report(String where, Throwable t) {
+		String key = where + ":" + t.getClass().getName();
+		boolean first;
+		synchronized (reportedProblems) {
+			first = reportedProblems.add(key);
+		}
+		if (first) { // report each problem only once, the broadcast runs every 2 seconds
+			logger.warn("LAN broadcast problem (" + where + "): " + t + " - continuing with other destinations.");
+		}
 	}
 
 	public void start() {
@@ -84,7 +145,6 @@ public final class LanServerBroadcastThread {
 	public void shutdown() {
 		if(!active) return;
 		broadcastTimer.cancel();
-		socket.close();
 		active = false;
 	}
 
PATCH_EOF
cat > "$WORK/patches/02-endgame-player-names.patch" <<'PATCH_EOF'
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/PartitionsGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/PartitionsGrid.java
index c44dcf1..e5aeb11 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/PartitionsGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/PartitionsGrid.java
@@ -99,6 +99,8 @@ public final class PartitionsGrid implements Serializable, IScheduledTimerable {
 				teams.computeIfAbsent(playerSetting.getTeamId(), Team::new);
 				Team team = teams.get(playerSetting.getTeamId());
 				this.players[playerId] = new Player(playerId, team, (byte) playerSettings.length, playerSetting.getPlayerType(), playerSetting.getCivilisation());
+				this.players[playerId].setDisplayType(playerSetting.getDisplayType());
+				this.players[playerId].setDisplayName(playerSetting.getDisplayName());
 				team.registerPlayer(this.players[playerId]);
 				this.blockedPartitionsForPlayers[playerId] = createNewPartition(playerId); // create a blocked partition for every player
 				players[playerId].scheduleTasks();
@@ -118,6 +120,8 @@ public final class PartitionsGrid implements Serializable, IScheduledTimerable {
 		for (int i = 0; i < players.length; i++) {
 			if (players[i] != null && playerSettings[i].isAvailable()) {
 				players[i].setPlayerType(playerSettings[i].getPlayerType());
+				players[i].setDisplayType(playerSettings[i].getDisplayType());
+				players[i].setDisplayName(playerSettings[i].getDisplayName());
 				players[i].setCivilisation(playerSettings[i].getCivilisation());
 			}
 		}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/player/EndgameStatistic.java b/jsettlers.logic/src/main/java/jsettlers/logic/player/EndgameStatistic.java
index 5ebe08a..a6565c3 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/player/EndgameStatistic.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/player/EndgameStatistic.java
@@ -50,7 +50,11 @@ public class EndgameStatistic implements IEndgameStatistic, Serializable {
 
 	@Override
 	public String getName() {
-		return player.getPlayerType().toString();
+		String name = player.getDisplayName();
+		if (player.getDisplayType() == EPlayerType.HUMAN && name != null && !name.trim().isEmpty()) {
+			return name;
+		}
+		return String.valueOf(player.getDisplayType());
 	}
 
 	@Override
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/player/Player.java b/jsettlers.logic/src/main/java/jsettlers/logic/player/Player.java
index 353532a..8414573 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/player/Player.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/player/Player.java
@@ -55,6 +55,8 @@ public class Player implements Serializable, IMessenger, IInGamePlayer, IOffersC
 	private ECivilisation civilisation;
 
 	private transient EPlayerType               playerType;
+	private transient EPlayerType               displayType;
+	private transient String                    displayName;
 	private transient CombatStrengthInformation combatStrengthInfo = new CombatStrengthInformation();
 	private transient IMessenger                messenger;
 
@@ -172,6 +174,25 @@ public class Player implements Serializable, IMessenger, IInGamePlayer, IOffersC
 		return civilisation;
 	}
 
+	/**
+	 * @return the type to show to the user (differs from {@link #getPlayerType()} on multiplayer clients, where AI players are treated as human).
+	 */
+	public EPlayerType getDisplayType() {
+		return displayType != null ? displayType : playerType;
+	}
+
+	public String getDisplayName() {
+		return displayName;
+	}
+
+	public void setDisplayName(String displayName) {
+		this.displayName = displayName;
+	}
+
+	public void setDisplayType(EPlayerType displayType) {
+		this.displayType = displayType;
+	}
+
 	public void setPlayerType(EPlayerType playerType) {
 		this.playerType = playerType;
 	}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/player/PlayerSetting.java b/jsettlers.logic/src/main/java/jsettlers/logic/player/PlayerSetting.java
index 5ad0a62..384557c 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/player/PlayerSetting.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/player/PlayerSetting.java
@@ -38,6 +38,10 @@ public class PlayerSetting {
 	private final Byte teamId;
 	private final ECivilisation civilisation;
 	private final EPlayerType playerType;
+	/** Only for display (e.g. end-game statistics). Not serialized. If null, {@link #playerType} is used. */
+	private EPlayerType displayType;
+	/** Only for display (e.g. end-game statistics): name of a human player. Not serialized. */
+	private String displayName;
 
 	/**
 	 * Creates a new {@link PlayerSetting} object for a human player.
@@ -94,6 +98,28 @@ public class PlayerSetting {
 		return civilisation;
 	}
 
+	/**
+	 * @return the type that should be shown to the user. On multiplayer clients all slots are {@link EPlayerType#HUMAN} for the game logic (the AI
+	 * only runs on the host), but the real type of the slot is still known and is shown here.
+	 */
+	public EPlayerType getDisplayType() {
+		return displayType != null ? displayType : playerType;
+	}
+
+	public String getDisplayName() {
+		return displayName;
+	}
+
+	public PlayerSetting withDisplayName(String displayName) {
+		this.displayName = displayName;
+		return this;
+	}
+
+	public PlayerSetting withDisplayType(EPlayerType displayType) {
+		this.displayType = displayType;
+		return this;
+	}
+
 	@Override
 	public String toString() {
 		return "PlayerSetting{" +
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
index 779743f..4951097 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
@@ -150,9 +150,9 @@ public class MultiplayerGame {
 				.map(slot -> {
 					PlayerSetting playerSetting;
 					if(iAmTheHost) {
-						playerSetting = new PlayerSetting(slot.getType(), slot.getCivilisation(), slot.getTeam());
+						playerSetting = new PlayerSetting(slot.getType(), slot.getCivilisation(), slot.getTeam()).withDisplayName(playerNameOf(slot));
 					} else {
-						playerSetting = new PlayerSetting(EPlayerType.HUMAN, slot.getCivilisation(), slot.getTeam());
+						playerSetting = new PlayerSetting(EPlayerType.HUMAN, slot.getCivilisation(), slot.getTeam()).withDisplayType(slot.getType()).withDisplayName(playerNameOf(slot));
 					}
 
 					return Map.entry(slot.getPosition(), playerSetting);
@@ -160,6 +160,10 @@ public class MultiplayerGame {
 		return IntStream.range(0, maxPlayers).mapToObj(i -> playerSettings.computeIfAbsent((byte) i, v -> new PlayerSetting())).toArray(PlayerSetting[]::new);
 	}
 
+	private static String playerNameOf(IMultiplayerSlot slot) {
+		return slot.getPlayer() != null ? slot.getPlayer().getName() : null;
+	}
+
 	private byte calculateOwnPlayerId() {
 		String myId = networkClient.getPlayerInfo().getId();
 		for (IMultiplayerSlot currSlot : slotList.getItems()) {
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 6d58ca2..5d03de4 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -229,7 +229,7 @@ public class JoinGamePanel extends BackgroundPanel {
 					.map(playerSlot -> {
 						if (playerSlot.isAvailable()) {
 							return new PlayerSetting(playerSlot.getPlayerType(), playerSlot.getCivilisation(),
-									playerSlot.getTeam());
+									playerSlot.getTeam()).withDisplayName(playerSlot.getPlayerName());
 						} else {
 							return new PlayerSetting();
 						}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
index 046b3b7..c1b6258 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
@@ -211,6 +211,10 @@ public class PlayerSlot {
 		for(ECivilisation civ : ECivilisation.values()) civilisationComboBox.addItem(new CivilisationUiWrapper(civ));
 	}
 
+	public String getPlayerName() {
+		return playerNameLabel.getText();
+	}
+
 	public void setPlayerName(String playerName) {
 		playerNameLabel.setText(playerName);
 	}
PATCH_EOF
cat > "$WORK/patches/03-gifts-of-the-gods-spell.patch" <<'PATCH_EOF'
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/MageMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/MageMovable.java
index fdf4a7f..4101fc3 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/MageMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/MageMovable.java
@@ -2,6 +2,7 @@ package jsettlers.logic.movable.military;
 
 import java.util.ArrayDeque;
 import java.util.ArrayList;
+import java.util.Arrays;
 import java.util.Comparator;
 import java.util.List;
 import java.util.Queue;
@@ -42,6 +43,11 @@ import static jsettlers.common.landscape.ELandscapeType.*;
 
 public class MageMovable extends AttackableHumanMovable implements IMageMovable {
 
+	/** Materials that can appear with the spell "gifts of the gods": all droppable materials except the most valuable ones (gold, gems). */
+	private static final EMaterialType[] GIFT_MATERIALS = Arrays.stream(EMaterialType.DROPPABLE_MATERIALS)
+			.filter(type -> type != EMaterialType.GOLD && type != EMaterialType.GEMS)
+			.toArray(EMaterialType[]::new);
+
 	private static final long serialVersionUID = 1L;
 
 	private static final float ACTION1_DURATION = 1f;
@@ -325,12 +331,13 @@ public class MageMovable extends AttackableHumanMovable implements IMageMovable
 			case GIFTS:
 				spellRegion(ESpellType.GIFTS_RADIUS).filter((x, y) -> !grid.isBlockedOrProtected(x, y))
 						.filter((x, y) -> teamId(x, y) == -1 || teamId(x, y) == teamId())
-						.limit(MatchConstants.random().nextInt(ESpellType.GIFTS_MAX_STACKS+1))
+						// at least one stack, so that the mana is never spent for nothing
+						.limit(1 + MatchConstants.random().nextInt(ESpellType.GIFTS_MAX_STACKS))
 						.forEach((x, y) -> {
 							ShortPoint2D at = new ShortPoint2D(x, y);
-							//TODO only give useful stuff
-							EMaterialType type = EMaterialType.values()[MatchConstants.random().nextInt(EMaterialType.values().length)];
-							int size = MatchConstants.random().nextInt(9);
+							// only materials that can really be dropped (the old code also picked e.g. NO_MATERIAL, which is invisible)
+							EMaterialType type = GIFT_MATERIALS[MatchConstants.random().nextInt(GIFT_MATERIALS.length)];
+							int size = 1 + MatchConstants.random().nextInt(8);
 							for(int i = 0; i != size; i++) grid.dropMaterial(at, type, true, false);
 							effectLocations.add(at);
 						});
PATCH_EOF
cat > "$WORK/patches/04-soldiers-ignore-far-civilians.patch" <<'PATCH_EOF'
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/constants/Constants.java b/jsettlers.logic/src/main/java/jsettlers/logic/constants/Constants.java
index bb3445a..a4183dc 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/constants/Constants.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/constants/Constants.java
@@ -56,6 +56,12 @@ public final class Constants {
 	 */
 	public static final short SOLDIER_SEARCH_RADIUS = 30;
 
+	/**
+	 * The radius within soldiers attack non-military enemy units (geologists, pioneers, ...) on their own. Further away they ignore them, so that a
+	 * single passing geologist can not lure a whole army away.
+	 */
+	public static final short SOLDIER_CIVILIAN_SEARCH_RADIUS = 3;
+
 	public static final short DEFAULT_ATTACK_RADIUS = 1;
 
 	public static final short PIKEMAN_ATTACK_RADIUS = 2;
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
index e8a6b18..1cfd28c 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
@@ -1578,15 +1578,22 @@ public final class MainGrid implements Serializable {
 												final short maxSearchRadius, final boolean includeTowers) {
 			boolean isBowman = searchingAttackable.getMovableType().isBowman();
 
-			IAttackable enemy = searchEnemyInArea(position, searchingAttackable.getPlayer(), minSearchRadius, maxSearchRadius, isBowman, includeTowers);
+			// Soldiers must not run across the map after passers-by (e.g. geologists or pioneers); they only react to non-military units when these are close.
+			boolean ignoreFarCivilians = EMovableType.SOLDIERS.contains(searchingAttackable.getMovableType());
+
+			IAttackable enemy = searchEnemyInArea(position, searchingAttackable.getPlayer(), minSearchRadius, maxSearchRadius, isBowman, includeTowers, ignoreFarCivilians);
 			if (includeTowers && !isBowman && enemy == null) {
-				enemy = searchEnemyInArea(position, searchingAttackable.getPlayer(), maxSearchRadius, Constants.TOWER_ATTACKABLE_SEARCH_RADIUS, false, true);
+				enemy = searchEnemyInArea(position, searchingAttackable.getPlayer(), maxSearchRadius, Constants.TOWER_ATTACKABLE_SEARCH_RADIUS, false, true, ignoreFarCivilians);
 			}
 
 			return enemy;
 		}
 
-		private IAttackable searchEnemyInArea(final ShortPoint2D position, final IPlayer searchingPlayer, final short minSearchRadius, final short maxSearchRadius, boolean isBowman, boolean includeTowers) {
+		private boolean isMilitary(EMovableType type) {
+			return EMovableType.SOLDIERS.contains(type) || type == EMovableType.MAGE;
+		}
+
+		private IAttackable searchEnemyInArea(final ShortPoint2D position, final IPlayer searchingPlayer, final short minSearchRadius, final short maxSearchRadius, boolean isBowman, boolean includeTowers, boolean ignoreFarCivilians) {
 			int minDistance = Integer.MAX_VALUE;
 			IAttackable result = null;
 
@@ -1617,6 +1624,12 @@ public final class MainGrid implements Serializable {
 
 
 				int attackDistance = attackable.getPosition().getOnGridDistTo(position);
+
+				if(ignoreFarCivilians && attackDistance > Constants.SOLDIER_CIVILIAN_SEARCH_RADIUS && attackable instanceof IAttackableMovable
+						&& !isMilitary(attackable.getMovableType())) {
+					continue;
+				}
+
 				if(attackDistance < minDistance) {
 					minDistance = attackDistance;
 					result = attackable;
PATCH_EOF
cat > "$WORK/patches/05-font-quality-and-size.patch" <<'PATCH_EOF'
diff --git a/go.graphics.swing/src/main/java/go/graphics/swing/text/LWJGLTextDrawer.java b/go.graphics.swing/src/main/java/go/graphics/swing/text/LWJGLTextDrawer.java
index 54b6236..e6a75f0 100644
--- a/go.graphics.swing/src/main/java/go/graphics/swing/text/LWJGLTextDrawer.java
+++ b/go.graphics.swing/src/main/java/go/graphics/swing/text/LWJGLTextDrawer.java
@@ -15,27 +15,74 @@
 package go.graphics.swing.text;
 
 import go.graphics.GLDrawContext;
+import go.graphics.Tweaks;
 import go.graphics.text.AbstractTextDrawer;
 import go.graphics.text.EFontSize;
+import go.graphics.text.TextDrawer;
 
 import java.awt.Color;
 import java.awt.Font;
 import java.awt.FontMetrics;
 import java.awt.Graphics2D;
+import java.awt.GraphicsEnvironment;
 import java.awt.RenderingHints;
 import java.awt.Toolkit;
 import java.awt.image.BufferedImage;
+import java.util.Arrays;
+import java.util.EnumMap;
+import java.util.HashSet;
+import java.util.Set;
 
 public final class LWJGLTextDrawer extends AbstractTextDrawer<GLDrawContext> {
 	private static final int DEFAULT_DPI = 96;
-	private static final Font FONT = new Font("Arial", Font.PLAIN, TEXTURE_GENERATION_SIZE);
+	private static final String FONT_FAMILY = chooseFontFamily();
+
+	/**
+	 * Makes all texts bigger (or smaller). Setting "font-scale" (see {@link Tweaks}).
+	 */
+	private static final float FONT_SCALE = Tweaks.getFloat("font-scale", 1.5f, 0.5f, 4f);
+
+	private final float guiScale;
+	private final EnumMap<EFontSize, LWJGLTextDrawer> sizedAtlases = new EnumMap<>(EFontSize.class);
+	private Font font;
+
+	/** Prefers the macOS system font look, falls back to Arial (and finally to the Java default sans serif font). */
+	private static String chooseFontFamily() {
+		try {
+			Set<String> families = new HashSet<>(Arrays.asList(GraphicsEnvironment.getLocalGraphicsEnvironment().getAvailableFontFamilyNames()));
+			for (String family : new String[] {"Helvetica Neue", "Arial"}) {
+				if (families.contains(family)) return family;
+			}
+		} catch (Throwable ignored) {
+		}
+		return Font.SANS_SERIF;
+	}
 
 	/**
 	 * Creates a new text drawer.
 	 *
 	 */
 	public LWJGLTextDrawer(GLDrawContext drawContext, float guiScale) {
-		super(drawContext, guiScale);
+		this(drawContext, guiScale, null);
+	}
+
+	private LWJGLTextDrawer(GLDrawContext drawContext, float guiScale, EFontSize atlasSize) {
+		super(drawContext, guiScale, atlasSize);
+		this.guiScale = guiScale;
+	}
+
+	/**
+	 * Every font size gets its own glyph texture rendered directly in the final pixel size. That is much sharper than scaling down one big texture.
+	 */
+	@Override
+	public TextDrawer derive(EFontSize size) {
+		if (atlasSize != null) return super.derive(size);
+		return sizedAtlases.computeIfAbsent(size, s -> new LWJGLTextDrawer(drawContext, guiScale, s)).derive(size);
+	}
+
+	private Font createFont() {
+		float pixelSize = atlasSize == null ? TEXTURE_GENERATION_SIZE : Math.max(1f, atlasSize.getSize() * scalingFactor * FONT_SCALE);
+		return new Font(FONT_FAMILY, Font.PLAIN, 1).deriveFont(pixelSize);
 	}
 
 	@Override
@@ -51,14 +98,16 @@ public final class LWJGLTextDrawer extends AbstractTextDrawer<GLDrawContext> {
 		tmp_graph.setRenderingHint(
 				RenderingHints.KEY_TEXT_ANTIALIASING,
 				RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
-		tmp_graph.setFont(FONT);
+		tmp_graph.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON);
+		font = createFont();
+		tmp_graph.setFont(font);
 		FontMetrics fm = tmp_graph.getFontMetrics();
 		for(int i = 0;i != CHARACTER_COUNT; i++) char_widths[i] = fm.charWidth(CHARACTERS.charAt(i));
 		gentex_line_height = fm.getHeight();
 
 		EFontSize[] values = EFontSize.values();
 		for(int i = 0; i != values.length; i++) {
-			tmp_graph.setFont(FONT.deriveFont(values[i].getSize()));
+			tmp_graph.setFont(font.deriveFont(values[i].getSize()));
 			heightPerSize[i] = tmp_graph.getFontMetrics().getHeight();
 		}
 
@@ -69,7 +118,23 @@ public final class LWJGLTextDrawer extends AbstractTextDrawer<GLDrawContext> {
 
 	@Override
 	protected int[] getRGB() {
-		return pre_render.getRGB(0, 0, tex_width, tex_height, null, 0, tex_width);
+		int[] pixels = pre_render.getRGB(0, 0, tex_width, tex_height, null, 0, tex_width);
+		// The glyphs were drawn white on black. Convert them to white pixels whose alpha is derived from the brightness.
+		//  - The game uploads textures as RGBA (red in the highest byte), not as ARGB like Java: so the color has to be packed as 0xRRGGBBAA.
+		//    (Using ARGB mixes up the channels and gives a cyan fringe around the text.)
+		//  - The shader discards every pixel with alpha < 0.5, so the soft edge of the glyphs is mapped to the alpha range 0.5-1.0 and very faint
+		//    pixels are dropped. That gives smooth edges without a halo.
+		for (int i = 0; i < pixels.length; i++) {
+			int p = pixels[i];
+			int coverage = (((p >> 16) & 0xFF) + ((p >> 8) & 0xFF) + (p & 0xFF)) / 3;
+			if (coverage < 64) {
+				pixels[i] = 0; // fully transparent pixels must be black, otherwise a box is drawn around every glyph
+			} else {
+				int alpha = 128 + (coverage - 64) * 127 / 191;
+				pixels[i] = 0xFFFFFF00 | alpha;
+			}
+		}
+		return pixels;
 	}
 
 	private BufferedImage pre_render;
@@ -77,13 +142,16 @@ public final class LWJGLTextDrawer extends AbstractTextDrawer<GLDrawContext> {
 
 	@Override
 	protected void setupBitmapDraw() {
-		pre_render = new BufferedImage(tex_width, tex_height, BufferedImage.TYPE_INT_ARGB);
+		pre_render = new BufferedImage(tex_width, tex_height, BufferedImage.TYPE_INT_RGB);
 		graph = pre_render.createGraphics();
+		graph.setColor(Color.BLACK);
+		graph.fillRect(0, 0, tex_width, tex_height);
 		graph.setRenderingHint(
 				RenderingHints.KEY_TEXT_ANTIALIASING,
 				RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
+		graph.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON);
 		graph.setColor(Color.WHITE);
-		graph.setFont(FONT);
+		graph.setFont(font);
 	}
 
 	@Override
diff --git a/go.graphics/src/main/java/go/graphics/Tweaks.java b/go.graphics/src/main/java/go/graphics/Tweaks.java
new file mode 100644
index 0000000..20dc681
--- /dev/null
+++ b/go.graphics/src/main/java/go/graphics/Tweaks.java
@@ -0,0 +1,50 @@
+package go.graphics;
+
+import java.io.File;
+import java.io.FileInputStream;
+import java.io.IOException;
+import java.io.InputStream;
+import java.util.Properties;
+
+/**
+ * Small user adjustable settings (text size, tooltip position, ...).
+ * <p>
+ * A value is read from the java system property "settlers.&lt;key&gt;" or from the file "tweaks.properties" in the working directory of the game
+ * (on macOS: ~/Library/Application Support/JSettlers/tweaks.properties). The game must be restarted after changing the file.
+ */
+public final class Tweaks {
+	private static Properties fileValues;
+
+	private Tweaks() {
+	}
+
+	private static synchronized String get(String key) {
+		String value = System.getProperty("settlers." + key);
+		if (value != null) return value;
+
+		if (fileValues == null) {
+			fileValues = new Properties();
+			File file = new File("tweaks.properties");
+			if (file.isFile()) {
+				try (InputStream in = new FileInputStream(file)) {
+					fileValues.load(in);
+				} catch (IOException | RuntimeException e) {
+					System.err.println("Could not read " + file.getAbsolutePath() + ": " + e);
+				}
+			}
+		}
+		return fileValues.getProperty(key);
+	}
+
+	public static float getFloat(String key, float defaultValue, float min, float max) {
+		String value = get(key);
+		if (value == null) return defaultValue;
+		try {
+			float parsed = Float.parseFloat(value.trim());
+			if (parsed >= min && parsed <= max) return parsed;
+		} catch (NumberFormatException ignored) {
+		}
+		System.err.println("Ignoring invalid value '" + value + "' of setting " + key);
+		return defaultValue;
+	}
+}
diff --git a/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java b/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
index bba4f50..ca34e24 100644
--- a/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
+++ b/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
@@ -63,7 +63,14 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 
 	protected static final int TEXTURE_GENERATION_SIZE = 30;
 
-	private final float scalingFactor;
+	protected final float scalingFactor;
+
+	/**
+	 * If not null, the glyph texture of this drawer is rendered directly in the pixel size of this font size (including the scaling factor), so that
+	 * the text is drawn 1:1 without scaling the glyphs (which makes small text blurry/jagged). If null, the glyphs are rendered with
+	 * {@link #TEXTURE_GENERATION_SIZE} and scaled for every size.
+	 */
+	protected final EFontSize atlasSize;
 
 	private UnifiedDrawHandle geometry;
 	protected TextureHandle font_tex;
@@ -82,7 +89,12 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 	 *
 	 */
 	public AbstractTextDrawer(T drawContext, float guiScale) {
+		this(drawContext, guiScale, null);
+	}
+
+	public AbstractTextDrawer(T drawContext, float guiScale, EFontSize atlasSize) {
 		this.drawContext = drawContext;
+		this.atlasSize = atlasSize;
 		scalingFactor = guiScale <= 0.51f ? calculateScalingFactor() : guiScale;
 
 		int descent = init();
@@ -183,7 +195,13 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 		private final float lineHeight;
 
 		private SizedTextDrawer(EFontSize size) {
-			lineHeight = heightPerSize[size.ordinal()]*scalingFactor;
+			if (atlasSize == null) {
+				lineHeight = heightPerSize[size.ordinal()]*scalingFactor;
+			} else if (atlasSize == size) {
+				lineHeight = gentex_line_height; // glyphs are already rendered in the final size => draw them 1:1
+			} else {
+				lineHeight = gentex_line_height*size.getSize()/atlasSize.getSize();
+			}
 			widthFactor = lineHeight/gentex_line_height;
 		}
 
PATCH_EOF
cat > "$WORK/patches/06-building-cost-tooltip.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/buildings/BuildingButton.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/buildings/BuildingButton.java
index 75e420c..0df42f1 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/buildings/BuildingButton.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/buildings/BuildingButton.java
@@ -17,7 +17,12 @@ package jsettlers.graphics.map.controls.original.panel.content.buildings;
 import go.graphics.GLDrawContext;
 import go.graphics.text.EFontSize;
 
+import java.util.EnumMap;
+import java.util.Map;
+
 import jsettlers.common.buildings.BuildingVariant;
+import jsettlers.common.buildings.stacks.ConstructionStack;
+import jsettlers.common.material.EMaterialType;
 import jsettlers.common.images.EImageLinkType;
 import jsettlers.common.images.ImageLink;
 import jsettlers.common.images.OriginalImageLink;
@@ -58,12 +63,39 @@ public class BuildingButton extends Button implements UiContentUpdater.IUiConten
 	private final Label constructedLabel = new Label("", EFontSize.SMALL, EHorizontalAlignment.RIGHT, EVerticalAlignment.TOP);
 
 	public BuildingButton(BuildingVariant building) {
-		super(new ShowConstructionMarksAction(building.getType()), null, null, Labels.getName(building.getType()));
+		super(new ShowConstructionMarksAction(building.getType()), null, null, createDescription(building));
 		this.building = building;
 		buildingImageLink = building.getGuiImage();
 		addChild(constructedLabel, 0.05f, 0.05f, .95f, .95f);
 	}
 
+	/**
+	 * Tooltip text: the name of the building and, in the second line, the materials needed to build it (e.g. "Plank: 2, Stone: 3").
+	 */
+	private static String createDescription(BuildingVariant building) {
+		String name = Labels.getName(building.getType());
+		try {
+			Map<EMaterialType, Integer> costs = new EnumMap<>(EMaterialType.class);
+			for (ConstructionStack stack : building.getConstructionStacks()) {
+				if (stack.requiredForBuild() > 0) {
+					costs.merge(stack.getMaterialType(), (int) stack.requiredForBuild(), Integer::sum);
+				}
+			}
+			if (costs.isEmpty()) return name;
+
+			StringBuilder text = new StringBuilder(name).append('\n');
+			boolean first = true;
+			for (Map.Entry<EMaterialType, Integer> cost : costs.entrySet()) {
+				if (!first) text.append(", ");
+				text.append(Labels.getName(cost.getKey(), false)).append(": ").append(cost.getValue());
+				first = false;
+			}
+			return text.toString();
+		} catch (RuntimeException e) {
+			return name; // the cost is only additional information
+		}
+	}
+
 	@Override
 	public void drawAt(GLDrawContext gl) {
 		drawBackground(gl);
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/settlers/warriors/WarriorsPanel.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/settlers/warriors/WarriorsPanel.java
index 8f0f6d4..fc879d9 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/settlers/warriors/WarriorsPanel.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/content/settlers/warriors/WarriorsPanel.java
@@ -184,6 +184,9 @@ public class WarriorsPanel extends AbstractContentProvider {
 
 		@Override
 		public String getDescription(float relativeX, float relativeY) {
+			if (mannaInformation == null || mannaInformation.getLevel(soldierType) >= mannaInformation.getMaximumLevel()) {
+				return null; // highest level reached: there is nothing to promote to, the button is not drawn either
+			}
 			return Labels.getString("upgrade_warriors", Labels.getName(soldierType));
 		}
 
PATCH_EOF
cat > "$WORK/patches/07-tooltip-position.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 25b8621..247a98c 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -23,6 +23,7 @@ import java.util.Optional;
 
 import java.util.Set;
 import go.graphics.GLDrawContext;
+import go.graphics.Tweaks;
 import go.graphics.UIPoint;
 import go.graphics.UnifiedDrawHandle;
 import go.graphics.event.GOEvent;
@@ -572,10 +573,20 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 	private void drawTooltip(GLDrawContext gl) {
 		if (!tooltipString.isEmpty()) {
 			TextDrawer drawer = textDrawer.getTextDrawer(gl, EFontSize.NORMAL);
-			drawer.drawString((int) mousePosition.getX(), (int) mousePosition.getY(), tooltipString);
+
+			// The text is drawn to the right of the mouse cursor. The upper edge of the text is at the same height as the upper edge of the native
+			// mouse cursor (which starts at the mouse position and reaches downwards).
+			float x = (int) mousePosition.getX() + TOOLTIP_OFFSET_X;
+			float y = (int) mousePosition.getY() - drawer.getHeight("X") + TOOLTIP_OFFSET_Y;
+			drawer.drawString(x, y, tooltipString);
 		}
 	}
 
+	/** Distance of the tooltip text from the mouse position (pixels), so that the mouse cursor does not hide the text. Settings "tooltip-offset-x/y". */
+	private static final float TOOLTIP_OFFSET_X = Tweaks.getFloat("tooltip-offset-x", 32, -500, 500);
+	/** Positive values move the text up. */
+	private static final float TOOLTIP_OFFSET_Y = Tweaks.getFloat("tooltip-offset-y", 0, -500, 500);
+
 	private void drawActionThreadSlow(GLDrawContext gl) {
 		TextDrawer drawer = textDrawer.getTextDrawer(gl, EFontSize.NORMAL);
 		String string = Labels.getString("action_firerer_slow");
PATCH_EOF
cat > "$WORK/patches/08-in-game-messages.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
index 84285a5f5..4466ffbda 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
@@ -36,5 +36,20 @@ public enum EMessageType {
 	/**
 	 * The worker of a building was not able to find a place to execute his action in his work are for some time.
 	 */
-	NOTHING_FOUND_IN_SEARCH_AREA
+	NOTHING_FOUND_IN_SEARCH_AREA,
+
+	/**
+	 * A military building has been finished but no soldier is available to occupy it.
+	 */
+	NO_SOLDIER_AVAILABLE,
+
+	/**
+	 * A building has been finished but its worker cannot be created because the tool for this profession is missing.
+	 */
+	MISSING_TOOL,
+
+	/**
+	 * A building has been finished but its worker cannot be created because there is no free carrier to become the worker.
+	 */
+	NO_FREE_BEARER
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
index f805b4397..0fb7a759a 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
@@ -139,6 +139,42 @@ public class SimpleMessage implements IMessage {
 		return new SimpleMessage(EMessageType.NOTHING_FOUND_IN_SEARCH_AREA, "cannot_find_work_" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
 	}
 
+	/**
+	 * Create a new message that a military building has no soldier available to occupy it.
+	 *
+	 * @param building
+	 * 		The building
+	 * @return The message object
+	 */
+	public static IMessage noSoldierAvailable(IBuilding building) {
+		return new SimpleMessage(EMessageType.NO_SOLDIER_AVAILABLE, "no_soldier_available_" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
+	}
+
+	/**
+	 * Create a new message that a building cannot be occupied because the tool of its worker is missing.
+	 *
+	 * @param building
+	 * 		The building
+	 * @param tool
+	 * 		The missing tool
+	 * @return The message object
+	 */
+	public static IMessage missingTool(IBuilding building, EMaterialType tool) {
+		// the text is composed from the building and the tool, see MapContent
+		return new SimpleMessage(EMessageType.MISSING_TOOL, "missing_tool|" + building.getBuildingVariant().getType() + "|" + tool, (byte) -1, building.getPosition());
+	}
+
+	/**
+	 * Create a new message that a building cannot be occupied because there is no free carrier who could become its worker.
+	 *
+	 * @param building
+	 * 		The building
+	 * @return The message object
+	 */
+	public static IMessage noFreeBearer(IBuilding building) {
+		return new SimpleMessage(EMessageType.NO_FREE_BEARER, "no_free_bearer|" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
+	}
+
 	/**
 	 *
 	 * @param at
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 247a98ccd..74208c013 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -16,9 +16,12 @@ package jsettlers.graphics.map;
 
 import java.io.PrintWriter;
 import java.io.StringWriter;
+import java.util.ArrayList;
 import java.util.BitSet;
 
 import go.graphics.EPrimitiveType;
+import java.util.List;
+import java.util.Locale;
 import java.util.Optional;
 
 import java.util.Set;
@@ -69,6 +72,7 @@ import jsettlers.common.menu.IStartedGame;
 import jsettlers.common.menu.UIState;
 import jsettlers.common.action.EMoveToType;
 import jsettlers.common.action.MoveToAction;
+import jsettlers.common.menu.messages.EMessageType;
 import jsettlers.common.menu.messages.IMessage;
 import jsettlers.common.movable.IGraphicsMovable;
 import jsettlers.common.player.IPlayer;
@@ -157,7 +161,10 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 	private static final int SCREEN_PADDING = 50;
 	private static final float OVERDRAW_BOTTOM_PX = 50;
-	private static final float MESSAGE_OFFSET_X = 300;
+	/**
+	 * Distance between the right edge of the left side panel and the start of the message texts (setting message-offset-x).
+	 */
+	private static final float MESSAGE_OFFSET_X = Tweaks.getFloat("message-offset-x", 24, -500, 2000);
 	private static final int MESSAGE_OFFSET_Y = 30;
 	private static final long GOTO_MARK_TIME = 1500;
 	private static final long DOUBLE_CLICK_TIME = 500;
@@ -443,10 +450,92 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 		drawer.drawString((windowWidth - drawer.getWidth(msg)) / 2, windowHeight - 7 * EFontSize.HEADLINE.getSize(), color, msg);
 	}
 
+	/**
+	 * Screen areas of the messages drawn last (x, y, width, height), used to jump to the message position on click.
+	 */
+	private volatile MessageArea[] messageAreas = new MessageArea[0];
+
+	private static final class MessageArea {
+		private final float x;
+		private final float y;
+		private final float width;
+		private final float height;
+		private final ShortPoint2D position;
+
+		private MessageArea(float x, float y, float width, float height, ShortPoint2D position) {
+			this.x = x;
+			this.y = y;
+			this.width = width;
+			this.height = height;
+			this.position = position;
+		}
+
+		private boolean contains(UIPoint point) {
+			return point.getX() >= x && point.getX() <= x + width && point.getY() >= y && point.getY() <= y + height;
+		}
+	}
+
+	private static String capitalizeWords(String key) {
+		String text = key.replace('_', ' ').trim().toLowerCase(Locale.ENGLISH);
+		return text.isEmpty() ? key : Character.toUpperCase(text.charAt(0)) + text.substring(1);
+	}
+
+	private static String buildingNameOf(String buildingType) {
+		String name = Labels.getString("building_" + buildingType);
+		return name.equals("building_" + buildingType) ? capitalizeWords(buildingType) : name;
+	}
+
+	/**
+	 * Gets the readable text of a message. Messages whose text is missing in the language files get a readable text made from their key instead of
+	 * showing the raw key.
+	 */
+	private static String getMessageText(IMessage m) {
+		String label = m.getMessageLabel();
+		String text = Labels.getString(label);
+		if (m.getType() == EMessageType.CHAT || !text.equals(label)) {
+			return text;
+		}
+		if (label.startsWith("missing_tool|")) {
+			String[] parts = label.split("\\|");
+			String toolKey = "material_" + parts[2];
+			String tool = Labels.getString(toolKey);
+			tool = tool.equals(toolKey) ? capitalizeWords(parts[2]) : tool;
+			return Labels.getString("message_missing_tool", buildingNameOf(parts[1]), tool.toLowerCase(Locale.ROOT));
+		} else if (label.startsWith("no_free_bearer|")) {
+			String[] parts = label.split("\\|");
+			return Labels.getString("message_no_free_bearer", buildingNameOf(parts[1]));
+		} else if (label.startsWith("cannot_find_work_")) {
+			return buildingNameOf(label.substring("cannot_find_work_".length())) + ": no work found in its work area.";
+		} else if (label.startsWith("no_soldier_available_")) {
+			return buildingNameOf(label.substring("no_soldier_available_".length())) + " has no soldier to occupy it.";
+		} else if (label.startsWith("minerals_")) {
+			return "A geologist found " + capitalizeWords(label.substring("minerals_".length())).toLowerCase(Locale.ENGLISH) + ".";
+		}
+		return capitalizeWords(label);
+	}
+
+	private static Color getMessageColor(IMessage m, float alpha) {
+		switch (m.getType()) {
+		case ATTACKED:
+			return new Color(1f, 0.45f, 0.35f, alpha);
+		case NOTHING_FOUND_IN_SEARCH_AREA:
+		case NO_SOLDIER_AVAILABLE:
+		case MISSING_TOOL:
+		case NO_FREE_BEARER:
+			return new Color(1f, 0.8f, 0.3f, alpha);
+		case MINERALS:
+			return new Color(0.6f, 1f, 0.6f, alpha);
+		default:
+			return new Color(1, 1, 1, alpha);
+		}
+	}
+
 	private void drawMessages(GLDrawContext gl) {
 		EFontSize fontSize = EFontSize.HEADLINE;
 		TextDrawer drawer = textDrawer.getTextDrawer(gl, fontSize);
 		messenger.doTick();
+		float lineHeight = Math.max(fontSize.getSize() * 1.3f, drawer.getHeight("X") * 1.35f);
+		List<MessageArea> areas = new ArrayList<>();
 
 		float offsetY;
 		float offsetX;
@@ -454,7 +543,7 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 		int messageIndex;
 		if(textDrawPosition == ETextDrawPosition.DESKTOP) {
 			offsetY = MESSAGE_OFFSET_Y;
-			offsetX = MESSAGE_OFFSET_X;
+			offsetX = controls.getPanelWidth() + MESSAGE_OFFSET_X;
 			yDirection = 1;
 			messageIndex = 0;
 		} else {
@@ -466,8 +555,9 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 		for (IMessage m : messenger.getMessages()) {
 			float x = offsetX;
-			float y = offsetY + messageIndex * (fontSize.getSize()*1.3f) * yDirection;
+			float y = offsetY + messageIndex * lineHeight * yDirection;
 			float a = messageAlpha(m);
+			float startX = x;
 			if (m.getSender() >= 0) {
 				String name = getPlayername(m.getSender()) + ":";
 				Color color = MapDrawContext.getPlayerColor(m.getSender());
@@ -479,10 +569,15 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 				x += width + 10;
 			}
 
-			drawer.drawString(x, y, new Color(1, 1, 1, a), Labels.getString(m.getMessageLabel()));
+			String text = getMessageText(m);
+			drawer.drawString(x, y, getMessageColor(m, a), text);
+			if (m.getPosition() != null) {
+				areas.add(new MessageArea(startX, y - lineHeight * 0.2f, x - startX + drawer.getWidth(text), lineHeight, m.getPosition()));
+			}
 
 			messageIndex++;
 		}
+		messageAreas = areas.toArray(new MessageArea[0]);
 	}
 
 	private String getPlayername(byte sender) {
@@ -888,6 +983,15 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 	private Optional<Action> getActionForCommand(GOCommandEvent commandEvent) {
 		UIPoint position = commandEvent.getCommandPosition();
+		if (commandEvent.isSelecting()) {
+			for (MessageArea area : messageAreas) {
+				if (area.contains(position)) {
+					// a click on a message text shows the place the message is about
+					scrollTo(area.position, true);
+					return Optional.empty();
+				}
+			}
+		}
 		if (controls.containsPoint(position)) {
 			if (commandEvent.isSelecting()) {
 				return controls.getActionForSelect(position);
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/IControls.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/IControls.java
index 70a272356..3582ff844 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/IControls.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/IControls.java
@@ -63,6 +63,15 @@ public interface IControls extends IMapInterfaceListener {
 	 */
 	boolean containsPoint(UIPoint position);
 
+	/**
+	 * Gets the width of the user interface panel that covers the left side of the screen.
+	 *
+	 * @return The width in pixels, 0 if there is no such panel.
+	 */
+	default float getPanelWidth() {
+		return 0;
+	}
+
 	/**
 	 * Gets the description for a given point, e.g. for tooltipps. May be called for any position.
 	 *
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
index 092b2f34d..7b18afe1d 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
@@ -181,6 +181,11 @@ public class OriginalControls implements IControls {
 				* uiBase.getPosition().getHeight();
 	}
 
+	@Override
+	public float getPanelWidth() {
+		return uiBase.getPosition().getWidth();
+	}
+
 	@Override
 	public boolean containsPoint(UIPoint position) {
 		float width = uiBase.getPosition().getWidth();
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 470af449d..b9e221d48 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -379,6 +379,13 @@ cannot_find_work_FARM = Your grain farm can't find find enough spots to plant wh
 cannot_find_work_WINEGROWER = Your winery can't find enough spots for growing vines in its work area.
 cannot_find_work_WATERWORKS = Your waterworks can't find any river in its work area.
 cannot_find_work_FISHER = Your fisher can't find any sea in its work area.
+cannot_find_work_RICE_FARM = Your rice farm can't find enough spots to plant rice in its work area.
+cannot_find_work_BEEKEEPING = Your beekeeper can't find enough free spots for beehives in its work area.
+no_soldier_available_TOWER = Your guard tower can't be occupied: no soldier is available.
+no_soldier_available_BIG_TOWER = Your large guard tower can't be occupied: no soldier is available.
+no_soldier_available_CASTLE = Your castle can't be occupied: no soldier is available.
+message_missing_tool = %s can't be occupied: tool missing (%s).
+message_no_free_bearer = %s can't be occupied: no free carrier is available.
 action_firerer_slow = Warning! The game is responding slowly.
 
 # progress display
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
index 3d10b591e..d81dc280a 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
@@ -67,6 +67,10 @@ public class OccupyingBuilding extends Building implements IBuilding.IOccupied,
 	private static final long serialVersionUID = 5267249978497095473L;
 
 	private static final int TIMER_PERIOD = 500;
+	/** Number of timer periods (500 ms each) without any soldier before the player is warned: 20 seconds. */
+	private static final int NO_SOLDIER_WARNING_TICKS = 40;
+	/** The warning is repeated after this many timer periods (2 minutes) while the building is still empty. */
+	private static final int NO_SOLDIER_WARNING_REPEAT_TICKS = 240;
 
 	private final LinkedList<OccupierPlace> emptyPlaces = new LinkedList<>();
 	private final SoldierRequests searchedSoldiers = new SoldierRequests();
@@ -78,6 +82,7 @@ public class OccupyingBuilding extends Building implements IBuilding.IOccupied,
 	private DijkstraContinuableRequest dijkstraRequest;
 
 	private boolean occupiedArea;
+	private int unoccupiedTicks = 0;
 	private float doorHealth = 50f;
 	private boolean inFight = false;
 	private AttackableTowerMapObject attackableTowerObject = null;
@@ -176,9 +181,25 @@ public class OccupyingBuilding extends Building implements IBuilding.IOccupied,
 		increaseDoorHealth();
 		releaseNextSoldierIfNeeded();
 		searchSoldiersIfNeeded();
+		warnIfNoSoldierAvailable();
 		return TIMER_PERIOD;
 	}
 
+	/**
+	 * Tells the player when this building has been waiting for its first soldier for a long time (nobody in reach to occupy it).
+	 */
+	private void warnIfNoSoldierAvailable() {
+		if (sortedOccupiers.isEmpty() && comingSoldiers.isEmpty() && !searchedSoldiers.isEmpty()) {
+			unoccupiedTicks++;
+			if (unoccupiedTicks == NO_SOLDIER_WARNING_TICKS
+					|| (unoccupiedTicks > NO_SOLDIER_WARNING_TICKS && (unoccupiedTicks - NO_SOLDIER_WARNING_TICKS) % NO_SOLDIER_WARNING_REPEAT_TICKS == 0)) {
+				getPlayer().showMessage(SimpleMessage.noSoldierAvailable(this));
+			}
+		} else {
+			unoccupiedTicks = 0;
+		}
+	}
+
 	private void increaseDoorHealth() {
 		if (doorHealth < 1 && !inFight) {
 			doorHealth = Math.min(1, doorHealth + Constants.TOWER_DOOR_REGENERATION);
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/workers/WorkerBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/workers/WorkerBuilding.java
index 75e5e3d11..a7f86b8ed 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/workers/WorkerBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/workers/WorkerBuilding.java
@@ -20,6 +20,7 @@ import java.util.List;
 import jsettlers.common.buildings.EBuildingType;
 import jsettlers.common.mapobject.EMapObjectType;
 import jsettlers.common.material.EMaterialType;
+import jsettlers.common.menu.messages.IMessage;
 import jsettlers.common.position.ShortPoint2D;
 import jsettlers.common.utils.Tuple;
 import jsettlers.logic.buildings.IBuildingsGrid;
@@ -61,6 +62,11 @@ public class WorkerBuilding extends WorkAreaBuilding implements IWorkerRequestBu
 		return -1; // no scheduling required
 	}
 
+	@Override
+	public void showMessage(IMessage message) {
+		getPlayer().showMessage(message);
+	}
+
 	private void requestWorker() {
 		super.grid.requestBuildingWorker(super.getBuildingVariant().getWorkerType(), this);
 	}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
index ef0277490..10294909a 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
@@ -19,6 +19,7 @@ import java.util.Iterator;
 import java.util.LinkedList;
 
 import jsettlers.common.material.EMaterialType;
+import jsettlers.common.menu.messages.SimpleMessage;
 import jsettlers.common.movable.EDirection;
 import jsettlers.common.movable.EMovableType;
 import jsettlers.common.player.IPlayer;
@@ -314,6 +315,17 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 	private void handleWorkerCreationRequests() {
 		Iterator<WorkerCreationRequest> iterator = workerCreationRequests.iterator();
 
+		if (joblessBearer.isEmpty()) {
+			// every new worker needs a free carrier, tell the player if one is missing for a building
+			for (WorkerCreationRequest request : workerCreationRequests) {
+				if (request instanceof WorkerRequest && request.isRequestAlive()) {
+					WorkerRequest workerRequest = (WorkerRequest) request;
+					workerRequest.warnPlayer(SimpleMessage.noFreeBearer(workerRequest.building));
+				}
+			}
+			return;
+		}
+
 		while(iterator.hasNext() && !joblessBearer.isEmpty()) {
 			WorkerCreationRequest workerCreationRequest = iterator.next();
 			if (!workerCreationRequest.isRequestAlive() || tryToCreateWorker(workerCreationRequest)) {
@@ -337,6 +349,10 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 
 			if(offer == null) { // no tool found => cannot create worker
 				workerCreationRequest.setToolProductionRequired(true);
+				if (workerCreationRequest instanceof WorkerRequest) {
+					WorkerRequest workerRequest = (WorkerRequest) workerCreationRequest;
+					workerRequest.warnPlayer(SimpleMessage.missingTool(workerRequest.building, tool));
+				}
 				return false;
 			}
 		}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
index 7ae61823a..d7e8a6f9c 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
@@ -15,6 +15,7 @@
 package jsettlers.logic.map.grid.partition.manager.manageables.interfaces;
 
 import jsettlers.common.buildings.BuildingVariant;
+import jsettlers.common.menu.messages.IMessage;
 import jsettlers.common.buildings.EBuildingType;
 import jsettlers.common.buildings.IBuilding;
 import jsettlers.common.mapobject.EMapObjectType;
@@ -64,5 +65,10 @@ public interface IWorkerRequestBuilding extends IPlayerable, ILocatable, IBuildi
 
 	void setCannotWork(boolean cannotWork);
 
+	/**
+	 * Shows a message to the owner of this building.
+	 */
+	void showMessage(IMessage message);
+
 	void addMapObjectCleanupPosition(ShortPoint2D pos, EMapObjectType objectType);
 }
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/objects/WorkerRequest.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/objects/WorkerRequest.java
index 3a9b1b99d..d1fd4121a 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/objects/WorkerRequest.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/objects/WorkerRequest.java
@@ -16,9 +16,11 @@ package jsettlers.logic.map.grid.partition.manager.objects;
 
 import java.io.Serializable;
 
+import jsettlers.common.menu.messages.IMessage;
 import jsettlers.common.movable.EMovableType;
 import jsettlers.common.position.ILocatable;
 import jsettlers.common.position.ShortPoint2D;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.logic.map.grid.partition.manager.manageables.interfaces.IWorkerRequestBuilding;
 
 public final class WorkerRequest extends WorkerCreationRequest implements ILocatable, Serializable {
@@ -28,6 +30,10 @@ public final class WorkerRequest extends WorkerCreationRequest implements ILocat
 	public final IWorkerRequestBuilding building;
 	public boolean creationRequested = false;
 
+	private static final int WARNING_DELAY = 10 * 1000;
+	private static final int WARNING_REPEAT = 120 * 1000;
+	private int nextWarningTime = 0;
+
 	public WorkerRequest(EMovableType movableType, IWorkerRequestBuilding building) {
 		this.building = building;
 		this.movableType = movableType;
@@ -43,6 +49,24 @@ public final class WorkerRequest extends WorkerCreationRequest implements ILocat
 		return movableType + "    " + creationRequested + "     " + building.getBuildingVariant();
 	}
 
+	/**
+	 * Tells the player that this building waits for its worker for a long time. The message is shown after a delay and then repeated from time to
+	 * time, as long as the request is waiting.
+	 *
+	 * @param message
+	 * 		The message to show.
+	 */
+	public void warnPlayer(IMessage message) {
+		int now = MatchConstants.clock().getTime();
+		if (nextWarningTime == 0) {
+			nextWarningTime = now + WARNING_DELAY;
+		}
+		if (now >= nextWarningTime) {
+			nextWarningTime = now + WARNING_REPEAT;
+			building.showMessage(message);
+		}
+	}
+
 	@Override
 	public boolean isRequestAlive() {
 		return !building.isDestroyed();
PATCH_EOF
cat > "$WORK/patches/09-messages-layout-and-settings-file.patch" <<'PATCH_EOF'
diff --git a/go.graphics/src/main/java/go/graphics/Tweaks.java b/go.graphics/src/main/java/go/graphics/Tweaks.java
index 20dc681..50ff443 100644
--- a/go.graphics/src/main/java/go/graphics/Tweaks.java
+++ b/go.graphics/src/main/java/go/graphics/Tweaks.java
@@ -2,8 +2,12 @@ package go.graphics;
 
 import java.io.File;
 import java.io.FileInputStream;
+import java.io.FileOutputStream;
 import java.io.IOException;
 import java.io.InputStream;
+import java.io.OutputStreamWriter;
+import java.io.Writer;
+import java.nio.charset.StandardCharsets;
 import java.util.Properties;
 
 /**
@@ -24,23 +28,50 @@ public final class Tweaks {
 
 		if (fileValues == null) {
 			fileValues = new Properties();
-			File file = new File("tweaks.properties");
+			loadFile();
+		}
+		return fileValues.getProperty(key);
+	}
+
+	/**
+	 * Loads the first existing settings file: tweaks.properties in the working directory, otherwise the one in the application folder on macOS.
+	 */
+	private static void loadFile() {
+		String home = System.getProperty("user.home", ".");
+		File[] candidates = {
+				new File("tweaks.properties"),
+				new File(home, "Library/Application Support/JSettlers/tweaks.properties"),
+		};
+		for (File file : candidates) {
 			if (file.isFile()) {
 				try (InputStream in = new FileInputStream(file)) {
 					fileValues.load(in);
+					report("settings read from " + file.getAbsolutePath() + ": " + fileValues);
 				} catch (IOException | RuntimeException e) {
-					System.err.println("Could not read " + file.getAbsolutePath() + ": " + e);
+					report("could not read " + file.getAbsolutePath() + ": " + e);
 				}
+				return;
 			}
 		}
-		return fileValues.getProperty(key);
+		report("no tweaks.properties found (working directory: " + new File(".").getAbsolutePath() + "), using defaults");
+	}
+
+	/**
+	 * Prints which settings file was used, also to tweaks-status.txt in the working directory so that the user can check it without a terminal.
+	 */
+	private static void report(String text) {
+		System.err.println("Tweaks: " + text);
+		try (Writer out = new OutputStreamWriter(new FileOutputStream("tweaks-status.txt"), StandardCharsets.UTF_8)) {
+			out.write(text + System.lineSeparator());
+		} catch (IOException | RuntimeException ignored) {
+		}
 	}
 
 	public static float getFloat(String key, float defaultValue, float min, float max) {
 		String value = get(key);
 		if (value == null) return defaultValue;
 		try {
-			float parsed = Float.parseFloat(value.trim());
+			float parsed = Float.parseFloat(value.trim().replace(',', '.'));
 			if (parsed >= min && parsed <= max) return parsed;
 		} catch (NumberFormatException ignored) {
 		}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 2d680b6..53ce710 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -164,7 +164,7 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 	/**
 	 * Distance between the right edge of the left side panel and the start of the message texts (setting message-offset-x).
 	 */
-	private static final float MESSAGE_OFFSET_X = Tweaks.getFloat("message-offset-x", 24, -500, 2000);
+	private static final float MESSAGE_OFFSET_X = Tweaks.getFloat("message-offset-x", 50, -500, 2000);
 	private static final int MESSAGE_OFFSET_Y = 30;
 	private static final long GOTO_MARK_TIME = 1500;
 	private static final long DOUBLE_CLICK_TIME = 500;
@@ -434,7 +434,7 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 	private float messageAlpha(IMessage m) {
 		int age = m.getAge();
 		return age < 1500
-				? Math.min(1, age / 1000f)
+				? Math.min(1, age / 250f)
 				: Math.max(0, 1f - (float) age / IMessage.MESSAGE_TTL);
 	}
 
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
index 7b18afe..c33bda9 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
@@ -183,7 +183,8 @@ public class OriginalControls implements IControls {
 
 	@Override
 	public float getPanelWidth() {
-		return uiBase.getPosition().getWidth();
+		// the lower part of the panel ends at the same x position that is used in containsPoint (the minimap decoration reaches further right above it)
+		return layoutProperties.miniMap.RIGHT_DECORATION_LEFT * uiBase.getPosition().getWidth();
 	}
 
 	@Override
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
index d81dc28..3b73e13 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
@@ -67,8 +67,8 @@ public class OccupyingBuilding extends Building implements IBuilding.IOccupied,
 	private static final long serialVersionUID = 5267249978497095473L;
 
 	private static final int TIMER_PERIOD = 500;
-	/** Number of timer periods (500 ms each) without any soldier before the player is warned: 20 seconds. */
-	private static final int NO_SOLDIER_WARNING_TICKS = 40;
+	/** Number of timer periods (500 ms each) without any soldier before the player is warned: 5 seconds. */
+	private static final int NO_SOLDIER_WARNING_TICKS = 10;
 	/** The warning is repeated after this many timer periods (2 minutes) while the building is still empty. */
 	private static final int NO_SOLDIER_WARNING_REPEAT_TICKS = 240;
 
PATCH_EOF
cat > "$WORK/patches/10-game-speed-and-fps-limit.patch" <<'PATCH_EOF'
diff --git a/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/JOGLContextCreator.java b/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/JOGLContextCreator.java
index 748f9b7..b49aaba 100644
--- a/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/JOGLContextCreator.java
+++ b/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/JOGLContextCreator.java
@@ -14,6 +14,10 @@
  *******************************************************************************/
 package go.graphics.swing.contextcreator;
 
+import java.util.concurrent.Executors;
+import java.util.concurrent.ScheduledExecutorService;
+import java.util.concurrent.TimeUnit;
+
 import com.jogamp.opengl.GLAutoDrawable;
 import com.jogamp.opengl.GLCapabilities;
 import com.jogamp.opengl.GLContext;
@@ -26,13 +30,58 @@ import go.graphics.swing.event.swingInterpreter.GOSwingEventConverter;
 
 public class JOGLContextCreator extends ContextCreator<GLJPanel> implements GLEventListener {
 
+	/**
+	 * With a frame rate limit the frames are paced here with nanosecond precision. The coarse Swing timer (whole milliseconds, on macOS with a lot of
+	 * jitter) only reached about 52 frames per second at a limit of 60.
+	 */
+	private final ScheduledExecutorService framePacer = Executors.newSingleThreadScheduledExecutor(runnable -> {
+		Thread thread = new Thread(runnable, "frame pacer");
+		thread.setDaemon(true);
+		return thread;
+	});
+	private long nextFrameNanos = 0;
+	private volatile long lastDisplayNanos = 0;
+
 	public JOGLContextCreator(ContextContainer container, boolean debug) {
 		super(container, debug);
 	}
 
 	@Override
 	public void stop() {
+		framePacer.shutdownNow();
+	}
+
+	@Override
+	public void repaint() {
+		// With a frame rate limit the next frame is already scheduled after each frame. Requests of the outer timer are only used to restart the
+		// frames when none has been drawn for a while.
+		if (fpsLimit != 0 && lastDisplayNanos != 0 && System.nanoTime() - lastDisplayNanos < 250_000_000L) {
+			return;
+		}
+		super.repaint();
+	}
+
+	private void scheduleNextFrame() {
+		if (fpsLimit == 0) {
+			super.repaint();
+			return;
+		}
+
+		long interval = 1_000_000_000L / fpsLimit;
+		long now = System.nanoTime();
+		long base = (nextFrameNanos == 0 || now - nextFrameNanos > 2 * interval) ? now : nextFrameNanos;
+		nextFrameNanos = base + interval;
 
+		long delay = nextFrameNanos - now;
+		if (delay <= 200_000L) {
+			super.repaint();
+		} else {
+			try {
+				framePacer.schedule(() -> canvas.repaint(), delay, TimeUnit.NANOSECONDS);
+			} catch (RuntimeException ignored) {
+				// stopped
+			}
+		}
 	}
 
 	@Override
@@ -60,10 +109,11 @@ public class JOGLContextCreator extends ContextCreator<GLJPanel> implements GLEv
 
 	@Override
 	public void display(GLAutoDrawable drawable) {
+		lastDisplayNanos = System.nanoTime();
 		try {
 			parent.draw();
 			parent.finishFrame();
-			if(fpsLimit == 0) repaint();
+			scheduleNextFrame();
 		} catch(ContextException ignored) {}
 	}
 
diff --git a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
index f973bd6..2df6ae8 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
@@ -60,6 +60,8 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 	private float progress = 0.0f;
 
 	private boolean scheduled = false;
+	/** System time (nanoseconds) of the previous call of {@link #run()}, 0 if there was none. */
+	private long lastRunNanos = 0;
 
 	private ITaskExecutor taskExecutor;
 	private DataOutputStream replayLogStream;
@@ -80,7 +82,9 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 	public synchronized void startExecution() {
 		if (!scheduled) {
 			scheduled = true;
-			timer.schedule(this, 0, TIME_SLICE);
+			// The timer thread wakes up more often than once per time slice and the game time is advanced by the real time that has passed. A fixed
+			// delay of TIME_SLICE would make every step a bit longer (on macOS about 10 %), so the game would run slower than the set speed.
+			timer.schedule(this, 0, TIME_SLICE / 5);
 		}
 	}
 
@@ -94,16 +98,21 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 
 	@Override
 	public void run() {
+		long now = System.nanoTime();
+		// number of time slices that have passed since the last call (limited, so that a long stall does not cause a huge burst of steps)
+		float slices = lastRunNanos == 0 ? 0 : Math.min(4f, (now - lastRunNanos) / (TIME_SLICE * 1000000f));
+		lastRunNanos = now;
+
 		if (!isPausing) {
 			if (pauseTime <= 0) { // this is used for synchronizing the network clients
-				progress += speedFactor;
+				progress += speedFactor * slices;
 
 				while (progress >= 1) {
 					executeRun();
 					progress--;
 				}
 			} else {
-				pauseTime -= TIME_SLICE;
+				pauseTime -= Math.round(TIME_SLICE * slices);
 			}
 		}
 	}
PATCH_EOF
cat > "$WORK/patches/11-amazon-storage-shadow.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java
index 10cc924..8f25f5b 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java
@@ -1321,6 +1321,8 @@ public class MapObjectDrawer {
 	 * @param color
 	 * 		Gray color shade
 	 */
+	private boolean marketplaceLogged = false;
+
 	private void drawBuilding(int x, int y, IBuilding building, float color) {
 		BuildingVariant variant = building.getBuildingVariant();
 
@@ -1349,14 +1351,50 @@ public class MapObjectDrawer {
 			} else if(variant.isVariantOf(EBuildingType.STOCK)) {
 				float[] zvalues = new float[] {-4*z_per_y, -2*z_per_y, 2*z_per_y, 3*z_per_y, 2*z_per_y, -2*z_per_y};
 				ImageLink[] images = variant.getImages();
+				// Every part of the storage carries the shadow of the whole building. Drawn six times on top of each other the translucent shadow
+				// becomes a solid black area, so only the last part that has a shadow draws it.
+				int shadowPart = 0;
+				for (int i = 0; i != 6; i++) {
+					Image part = imageProvider.getImage(images[i]);
+					if (part instanceof SettlerImage && ((SettlerImage) part).getShadow() != null) {
+						shadowPart = i;
+					}
+				}
 				for (int i = 0; i != 6; i++) {
-					draw(imageProvider.getImage(images[i]), x, y, zvalues[i], color);
+					Image part = imageProvider.getImage(images[i]);
+					if (i == shadowPart) {
+						draw(part, x, y, zvalues[i], color);
+					} else {
+						drawOnlyImage(part, x, y, zvalues[i], null, color);
+					}
 				}
 			} else {
 				ImageLink[] images = variant.getImages();
+
+				// Like the storage, the two parts of a marketplace carry (nearly) the same shadow of the whole building. Drawn on top of each other
+				// the translucent shadows add up to a solid black area, so only the first part (the base, it has the larger shadow and is drawn behind
+				// the building) draws its shadow.
+				int shadowPart = -1;
+				if (variant.isVariantOf(EBuildingType.MARKET_PLACE)) {
+					shadowPart = 0;
+					if (!marketplaceLogged) {
+						marketplaceLogged = true;
+						for (int i = 0; i < images.length; i++) {
+							Image part = imageProvider.getImage(images[i]);
+							System.out.println("marketplace part " + i + ": " + part.getClass().getSimpleName() + ", shadow: "
+									+ (part instanceof SettlerImage ? String.valueOf(((SettlerImage) part).getShadow() != null) : "n/a"));
+						}
+					}
+				}
+
 				if (images.length > 0) {
 					Image image = imageProvider.getImage(images[0]);
-					draw(image, x, y, building.getBuildingVariant().isVariantOf(EBuildingType.MARKET_PLACE) ? BACKGROUND_Z : 0, null, color);
+					float z = building.getBuildingVariant().isVariantOf(EBuildingType.MARKET_PLACE) ? BACKGROUND_Z : 0;
+					if (shadowPart == -1 || shadowPart == 0) {
+						draw(image, x, y, z, null, color);
+					} else {
+						drawOnlyImage(image, x, y, z, null, color);
+					}
 				}
 
 				byte fow = visibleGrid != null ? visibleGrid[x][y] : CommonConstants.FOG_OF_WAR_VISIBLE;
@@ -1367,7 +1405,11 @@ public class MapObjectDrawer {
 
 				for (int i = 1; i < images.length; i++) {
 					Image image = imageProvider.getImage(images[i]);
-					draw(image, x, y, tower_front_offset, color);
+					if (shadowPart == -1 || shadowPart == i) {
+						draw(image, x, y, tower_front_offset, color);
+					} else {
+						drawOnlyImage(image, x, y, tower_front_offset, null, color);
+					}
 				}
 			}
 		} else if (state >= .01f) {
PATCH_EOF
cat > "$WORK/patches/12-language-selection-czech.patch" <<'PATCH_EOF'
diff --git a/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java b/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
index ca34e246f..82fc46d6e 100644
--- a/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
+++ b/go.graphics/src/main/java/go/graphics/text/AbstractTextDrawer.java
@@ -49,6 +49,13 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 
 		charsBuilder.append("АБВГДЖЗИКЛМНОПРСТУФХШабвгдежзийклмнопрстуфхцчшщыьэюяё"); // russian
 
+		// czech (only characters that are not part of the lists above)
+		for (char c : "ÁÉÍÓÚÝáéíóúýČčĎďĚěŇňŘřŠšŤťŮůŽž".toCharArray()) {
+			if (charsBuilder.indexOf(String.valueOf(c)) < 0) {
+				charsBuilder.append(c);
+			}
+		}
+
 		// TODO add more language specific characters if needed
 
 		// infinity symbol
@@ -98,7 +105,7 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 		scalingFactor = guiScale <= 0.51f ? calculateScalingFactor() : guiScale;
 
 		int descent = init();
-		generateTexture();
+		generateTexture(descent);
 		generateGeometry(descent);
 	}
 
@@ -128,11 +135,14 @@ public abstract class AbstractTextDrawer<T extends GLDrawContext> {
 
 	protected abstract void endDraw();
 
-	private void generateTexture() {
+	private void generateTexture(int descent) {
 		int max_len = getMaxLen();
 
 		tex_width = max_len;
-		tex_height = gentex_line_height*TEXTURE_LINE_COUNT;
+		// The quad of every character reaches "descent" pixels below the baseline of its line (see generateGeometry), so the last line needs this
+		// extra space. Without it the quads of the characters in the last line reach beyond the texture and the bottom pixel row of the texture is
+		// stretched downwards, which draws a solid block below letters with a flat bottom (z, e, u ...).
+		tex_height = gentex_line_height*TEXTURE_LINE_COUNT + descent;
 
 		setupBitmapDraw();
 
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/AbstractLabels.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/AbstractLabels.java
index 5186ba7f3..72cf286fc 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/AbstractLabels.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/AbstractLabels.java
@@ -17,6 +17,8 @@ package jsettlers.graphics.localization;
 import java.io.IOException;
 import java.io.InputStream;
 import java.io.InputStreamReader;
+import java.util.ArrayList;
+import java.util.List;
 import java.util.Locale;
 import java.util.Properties;
 
@@ -111,6 +113,16 @@ public abstract class AbstractLabels {
 		return loadedLabels;
 	}
 
+	/**
+	 * Forgets all loaded labels, so that they are loaded again (using the current preferred locale) the next time a string is requested. Call this
+	 * after {@link #setPreferredLocale(Locale)} to switch the language at runtime.
+	 */
+	protected synchronized void reloadLabels() {
+		loadedLabels = null;
+		usedLocale = null;
+		labelsLoaded = false;
+	}
+
 	private void loadLabels() {
 		LocaleSuffix[] locales = getLocaleSuffixes();
 
@@ -148,12 +160,16 @@ public abstract class AbstractLabels {
 	 * @return The list, ordered from least to most preferred.
 	 */
 	public LocaleSuffix[] getLocaleSuffixes() {
-		LocaleSuffix[] locales = new LocaleSuffix[] {
-				new LocaleSuffix(new Locale("en"), false),
-				new LocaleSuffix(preferredLocale, false),
-				new LocaleSuffix(preferredLocale, true),
-		};
-		return locales;
+		// English is always loaded first, so that missing translations fall back to English.
+		List<LocaleSuffix> locales = new ArrayList<>();
+		locales.add(new LocaleSuffix(new Locale("en"), false));
+		if (!"en".equals(preferredLocale.getLanguage())) {
+			locales.add(new LocaleSuffix(preferredLocale, false));
+		}
+		if (!preferredLocale.getCountry().isEmpty()) {
+			locales.add(new LocaleSuffix(preferredLocale, true));
+		}
+		return locales.toArray(new LocaleSuffix[0]);
 	}
 
 	/**
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/Labels.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/Labels.java
index 430954e5e..f3735f562 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/Labels.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/localization/Labels.java
@@ -45,6 +45,14 @@ public final class Labels extends AbstractLabels {
 		return inputStream;
 	}
 
+	/**
+	 * Loads the labels again using the preferred locale set with {@link AbstractLabels#setPreferredLocale(Locale)}. Strings that were already
+	 * requested are not updated, so user interface components have to be created again after calling this.
+	 */
+	public static void reload() {
+		INSTANCE.reloadLabels();
+	}
+
 	/**
 	 * Gets a string.
 	 * 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
new file mode 100644
index 000000000..85c0b1d5e
--- /dev/null
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -0,0 +1,614 @@
+###############################################################################
+# Czech translation (čeština) for the JSettlers macOS build.
+# Same license as the rest of the project (MIT). File encoding: UTF-8.
+#
+# Keep the placeholders (%s, %d, %.0f%% ...) exactly as in labels_en.properties.
+# Only characters that exist in the in-game font atlas may be used (ASCII, Czech letters, a few others);
+# do not use typographic quotes. Missing keys fall back to English.
+###############################################################################
+# buildings
+building_FORESTER    = Chata lesníka
+building_LUMBERJACK  = Chata dřevorubce
+building_STONECUTTER = Chata kameníka
+building_SAWMILL     = Pila
+
+building_SULFURMINE = Důl na síru
+building_GEMSMINE   = Důl na drahokamy
+building_COALMINE   = Uhelný důl
+building_IRONMINE   = Důl na železnou rudu
+building_GOLDMINE   = Zlatý důl
+building_GOLDMELT   = Tavírna zlata
+building_IRONMELT   = Tavírna železa
+building_TOOLSMITH  = Kovárna nástrojů
+building_WEAPONSMITH = Kovárna zbraní
+
+building_FARM            = Obilná farma
+building_PIG_FARM        = Prasečí farma
+building_DONKEY_FARM     = Oslí farma
+building_MILL            = Mlýn
+building_BAKER           = Pekárna
+building_WATERWORKS      = Vodárna
+building_SLAUGHTERHOUSE  = Jatka
+building_FISHER          = Chata rybáře
+building_WINEGROWER      = Vinařství
+building_CHARCOAL_BURNER = Chata uhlíře
+
+building_SMALL_LIVINGHOUSE  = Malý obytný dům
+building_MEDIUM_LIVINGHOUSE = Střední obytný dům
+building_BIG_LIVINGHOUSE    = Velký obytný dům
+
+building_LOOKOUT_TOWER = Rozhledna
+building_TOWER         = Strážní věž
+building_BIG_TOWER     = Velká strážní věž
+building_CASTLE        = Hrad
+building_HOSPITAL      = Příbytek léčitele
+building_BARRACK       = Kasárna
+building_DOCKYARD      = Loděnice
+building_HARBOR        = Přístav
+building_MARKET_PLACE  = Tržiště
+building_STOCK         = Sklad
+
+building_TEMPLE        = Malý chrám
+building_BIG_TEMPLE    = Velký chrám
+
+building_BREWERY       = Pivovar
+building_RICE_FARM     = Rýžová farma
+building_BEEKEEPING    = Včelín
+building_DISTILLERY    = Palírna
+building_LABORATORY    = Laboratoř
+building_MEAD_BREWERY  = Medovírna
+
+# soldiers
+soldier_SWORDSMAN = Šermíř
+soldier_BOWMAN = Lučištník
+soldier_PIKEMAN = Kopiník
+
+# materials
+material_AXE = Sekera
+material_AXEp = Sekery
+material_BOW = Luk
+material_BOWp = Luky
+material_BLADE = Lopata
+material_BLADEp = Lopaty
+material_BREAD = Chléb
+material_BREADp = Chléb
+material_COAL = Uhlí
+material_COALp = Uhlí
+material_CROP = Obilí
+material_CROPp = Obilí
+material_FISH = Ryba
+material_FISHp = Ryby
+material_FISHINGROD = Rybářský prut
+material_FISHINGRODp = Rybářské pruty
+material_FLOUR = Mouka
+material_FLOURp = Mouka
+material_GOLD = Zlato
+material_GOLDp = Zlato
+material_GOLDORE = Zlatá ruda
+material_GOLDOREp = Zlatá ruda
+material_HAMMER = Kladivo
+material_HAMMERp = Kladiva
+material_IRON = Železo
+material_IRONp = Železo
+material_IRONORE = Železná ruda
+material_IRONOREp = Železná ruda
+material_MEAT = Maso
+material_MEATp = Maso
+material_PICK = Krumpáč
+material_PICKp = Krumpáče
+material_PIG = Prase
+material_PIGp = Prasata
+material_PLANK   = Prkno
+material_PLANKp  = Prkna
+material_SAW = Pila
+material_SAWp = Pily
+material_SCYTHE = Kosa
+material_SCYTHEp = Kosy
+material_SPEAR = Kopí
+material_SPEARp = Kopí
+material_STONE   = Kámen
+material_STONEp  = Kameny
+material_SWORD = Meč
+material_SWORDp = Meče
+material_TRUNK   = Kmen
+material_TRUNKp  = Kmeny
+material_WATER = Voda
+material_WATERp = Voda
+material_WINE = Víno
+material_WINEp = Víno
+material_HONEY = Med
+material_HONEYp = Med
+material_MEAD = Medovina
+material_MEADp = Medovina
+material_RICE = Rýže
+material_RICEp = Rýže
+material_LIQUOR = Rýžová pálenka
+material_LIQUORp = Rýžová pálenka
+material_SULFUR = Síra
+material_SULFURp = Síra
+material_GEMS = Drahokamy
+material_GEMSp = Drahokamy
+material_KEG = Soudek
+material_KEGp = Soudky
+material_GUN_POWDER = Střelný prach
+material_GUN_POWDERp = Střelný prach
+material_CANNON_AMMO = Dělová munice
+material_CANNON_AMMOp = Dělová munice
+material_BALLISTA_AMMO = Munice do balisty
+material_BALLISTA_AMMOp = Munice do balisty
+material_CATAPULT_AMMO = Munice do katapultu
+material_CATAPULT_AMMOp = Munice do katapultu
+
+resource_FISH = Ryby
+resource_COAL = Uhlí
+resource_GOLDORE = Zlato
+resource_IRONORE = Železná ruda
+resource_BRIMSTONE = Síra
+resource_GEMSTONE = Drahokam
+
+# actions
+action_BUILD = Stavět
+action_ASK_DESTROY = Zbourat
+action_MOVE_TO = Přesunout
+action_START_WORKING = Zahájit práci
+action_STOP_WORKING = Zastavit práci
+action_NEXT_OF_TYPE = Další budova tohoto typu
+action_ASK_SET_WORK_AREA = Nastavit pracovní oblast
+action_ASK_SET_DOCK = Nastavit pozici přístaviště
+action_MAKE_FERRY = Postavit trajekt
+action_MAKE_CARGO_SHIP = Postavit nákladní loď
+
+action_SOLDIERS_ALL = Naplnit věž vojáky
+action_SOLDIERS_ONE = Propustit všechny kromě jednoho
+action_SOLDIERS_MORE_SWORDSMAN = Přidat šermíře
+action_SOLDIERS_LESS_SWORDSMAN = Propustit šermíře
+action_SOLDIERS_MORE_PIKEMAN = Přidat kopiníka
+action_SOLDIERS_LESS_PIKEMAN = Propustit kopiníka
+action_SOLDIERS_MORE_BOWMAN = Přidat lučištníka
+action_SOLDIERS_LESS_BOWMAN = Propustit lučištníka
+
+# building types (for menu panels)
+buildingtypes_normal   = Surovinové budovy
+buildingtypes_food     = Potravinářské budovy
+buildingtypes_military = Vojenské budovy
+buildingtypes_social   = Ostatní budovy
+
+# roman spells
+spell_ROMAN_EYE = Boží oko
+spell_desc_ROMAN_EYE = Na několik sekund se odkryje zamžená oblast
+
+spell_IRRIGATE = Zavlažit poušť
+spell_desc_IRRIGATE = Promění poušť v trávu
+
+spell_GREEN_THUMB = Zelený palec
+spell_desc_GREEN_THUMB = Farmáři a lesníci rychleji pěstují obilí, víno nebo stromy
+
+spell_DEFEATISM = Defétismus
+spell_desc_DEFEATISM = Nepřátelské jednotky způsobují menší poškození
+
+spell_GILDING = Pozlacení železa
+spell_desc_GILDING = Promění železo ve zlato
+
+spell_CURSE_MOUNTAIN = Vyčerpat zdroje
+spell_desc_CURSE_MOUNTAIN = Sníží zásoby surovin ve vybrané hoře
+
+spell_DEFECT = Převést nepřátele
+spell_desc_DEFECT = Několik nepřátelských jednotek přebehne na vaši stranu
+
+# egyptian spells
+spell_DESERTIFICATION = Vypálit louky
+spell_desc_DESERTIFICATION = Promění užitečnou trávu v neplodnou poušť
+
+spell_DRAIN_MOOR = Vysušit rašeliniště
+spell_desc_DRAIN_MOOR = Promění bažinu v trávu
+
+spell_CONVERT_FOOD = Proměnit ryby v maso
+spell_desc_CONVERT_FOOD = Umožňuje efektivně vyrábět železnou rudu bez pěstování obilí
+
+spell_BURN_FOREST = Vypálit les
+spell_desc_BURN_FOREST = Zapálí několik stromů. Oheň se šíří jen na sousední stromy, nakonec vyhasne a zanechá jen bláto.
+
+spell_INCREASE_MORALE = Zvýšit morálku
+spell_desc_INCREASE_MORALE = Vaše jednotky způsobují větší poškození
+
+spell_SEND_FOES = Teleportovat nepřátele
+spell_desc_SEND_FOES = Vyberte libovolné místo na mapě, kam se teleportují nepřátelští vojáci z okolí
+
+spell_CURSE_BOWMAN = Prokletí lučištníci
+spell_desc_CURSE_BOWMAN = Promění nepřátelské lučištníky v okolí na pionýry
+
+# asian spells
+spell_MELT_SNOW = Rozpustit sníh
+spell_desc_MELT_SNOW = Promění sníh ve skálu. Umožní přejít jinak neprůchodná pohoří.
+
+spell_SUMMON_STONE = Přivolat kámen
+spell_desc_SUMMON_STONE = Umístí několik kamenů na vybrané místo
+
+spell_SUMMON_FISH = Přivolat ryby
+spell_desc_SUMMON_FISH = Umístí několik ryb do vybraných vod
+
+spell_MELT_STONE = Roztavit kámen
+spell_desc_MELT_STONE = Promění kameny v železné pruty
+
+spell_SHIELD = Chránit bojovníky
+spell_desc_SHIELD = Vojáci, kněží, pionýři atd. utrpí menší poškození
+
+spell_MOTIVATE_SWORDSMAN = Motivovat šermíře
+spell_desc_MOTIVATE_SWORDSMAN = Šermíři udeří dvakrát častěji a každým úderem způsobí o třetinu větší poškození
+
+spell_CALL_HELP = Přivolat pomoc
+spell_desc_CALL_HELP = Teleportuje vojáky z vybraného místa ke knězi, který kouzlo sesílá.
+
+# amazon spells
+spell_AMAZON_EYE = Boží oko
+spell_desc_AMAZON_EYE = Odkryje mlhu války
+
+spell_SUMMON_FOREST = Přivolat les
+spell_desc_SUMMON_FOREST = Zasadí stromy poblíž vybraného místa
+
+spell_FREEZE_FOES = Zmrazit nepřátele
+spell_desc_FREEZE_FOES = Nepřáteltští vojáci se přestanou hýbat a bít
+
+spell_SEND_GOODS = Poslat zboží
+spell_desc_SEND_GOODS = Teleportuje blízké hromady zboží na vybrané místo
+
+spell_REMOVE_GOLD = Odstranit zlato
+spell_desc_REMOVE_GOLD = Promění zlaté pruty v kameny
+
+spell_CALL_GOODS = Přivolat zboží
+spell_desc_CALL_GOODS = Teleportuje hromady zboží z vybraného místa (pokud je na vaší půdě) na pozici kněze
+
+spell_DESTROY_ARROWS = Zničit šípy
+spell_desc_DESTROY_ARROWS = Nepřáteltští lučištníci nebudou moci střílet šípy a zraňovat vaše vojáky
+
+# common spell
+spell_GIFTS = Boží dary
+spell_desc_GIFTS = Objeví se několik užitečných hromad zboží
+
+spell_cost = %d many
+spell_failed = Nemáte dost many k seslání tohoto kouzla
+
+manna_available = K dispozici: %d many
+
+minimap-occupied = Zobrazit hranice hráčů na minimapě.
+minimap-settlers = Zobrazit osadníky na minimapě.
+minimap-buildings = Zobrazit budovy na minimapě.
+
+# Stock Control Panel Titles
+controlpanel_title_inventory = Zásoby
+controlpanel_tools_title = Nástroje
+controlpanel_weapons_title = Zbraně
+controlpanel_distribution_title = Rozdělování zboží
+controlpanel_transportation_title = Doprava zboží
+
+# Settlers Control Panel Titles
+settler_stats_title = Statistika osadníků
+settler_stats_bed = Lůžka
+settler_stats_civilian = Civilisté
+settler_stats_soldier = Vojáci
+settler_stats_worker = Pracovníci
+
+# Settlers Profession Panel
+settler_profession_title = Osadníci
+settler_profession_currently = Nyní: %d (%.0f%%)
+settler_profession_relative = v %
+settler_profession_absolute = absolutně
+
+warriors_title = Vojáci
+
+# warriors panel
+upgrade_warriors = Povýšit: %s
+upgrade_warriors_progress = Božské povýšení: %d%%
+combat_strength = Síla: %d%%
+
+# settler selection
+headline_materials = suroviny
+headline_movabletypes = typy
+
+# gui labels
+under_construction = %s (ve výstavbě)
+materials_required = Potřebný materiál:
+productivity = Produktivita: %d%%
+click_castspell = Klikněte na místo, kde se má kouzlo seslát.
+click_set_workcenter = Klikněte pro nastavení pracovní oblasti této budovy.
+click_to_move = Klikněte pro přesun tohoto osadníka.
+click_set_trading_waypoint_WAYPOINT_1 = Klikněte pro nastavení prvního bodu trasy
+click_set_trading_waypoint_WAYPOINT_2 = Klikněte pro nastavení druhého bodu trasy
+click_set_trading_waypoint_WAYPOINT_3 = Klikněte pro nastavení třetího bodu trasy
+click_set_trading_waypoint_DESTINATION = Klikněte pro nastavení cíle obchodu
+abort = Zrušit
+really_destroy_building = Opravdu chcete tuto budovu zbourat?
+priority_HIGH = Nastavit vysokou prioritu.
+priority_LOW = Nastavit normální prioritu.
+priority_STOPPED = Zastavit práci
+building-build-in-progress = Staveniště: %s
+building-material-count = %d
+building-material-required = %d/%d
+stop = Zastavit
+kill = Zabít
+work = Pracovat zde
+unload = Vyložit trajekty
+convert_1_to_GEOLOGIST = Jeden nový geolog
+convert_all_to_GEOLOGIST = Přeměnit vybrané na geology
+convert_1_to_THIEF = Jeden nový zloděj
+convert_all_to_THIEF = Přeměnit vybrané na zloděje
+convert_1_to_PIONEER = Jeden nový pionýr
+convert_all_to_PIONEER = Přeměnit vybrané na pionýry
+convert_1_to_BEARER = Jeden nový nosič
+convert_all_to_BEARER = Přeměnit vybrané na nosiče
+
+
+# stock gui labels
+stock-material-local = Skladovat zde vybraný materiál
+dont-stock-material-local = Neskladovat zde vybraný materiál
+
+stock-material-global = Skladovat vybraný materiál všude
+dont-stock-material-global = Neskladovat vybraný materiál všude
+priority-to-top = Dát vybranému materiálu nejvyšší prioritu
+priority-one-up = Zvýšit prioritu vybraného materiálu o jedna
+priority-one-down = Snížit prioritu vybraného materiálu o jedna
+priority-to-bottom = Dát vybranému materiálu nejnižší prioritu
+
+
+# statistics
+materials_overview_title = Skladované materiály
+
+
+select_to_build = Kam postavit: %s?
+
+#messages
+winstate_WON = Zvítězili jste!
+winstate_LOST = Prohráli jste!
+attacked    = Jste napadeni.
+attacked_donkey = Vaši osli byli napadeni.
+minerals_COAL = Geolog našel uhlí.
+minerals_IRONORE = Geolog našel železo.
+minerals_GOLDORE = Geolog našel zlato.
+minerals_BRIMSTONE = Geolog našel síru.
+minerals_GEMS = Geolog našel drahokamy.
+cannot_find_work_LUMBERJACK = Váš dřevorubec nemůže ve své pracovní oblasti najít žádné stromy.
+cannot_find_work_STONECUTTER = Váš kameník nemůže ve své pracovní oblasti najít žádný kámen.
+cannot_find_work_FORESTER = Váš lesník nemůže ve své pracovní oblasti najít volné místo pro nové stromy.
+cannot_find_work_FARM = Vaše obilná farma nemůže ve své pracovní oblasti najít dost míst pro setí obilí.
+cannot_find_work_WINEGROWER = Vaše vinařství nemůže ve své pracovní oblasti najít dost míst pro pěstování vína.
+cannot_find_work_WATERWORKS = Vaše vodárna nemůže ve své pracovní oblasti najít žádnou řeku.
+cannot_find_work_FISHER = Váš rybář nemůže ve své pracovní oblasti najít žádné moře.
+cannot_find_work_RICE_FARM = Vaše rýžová farma nemůže ve své pracovní oblasti najít dost míst pro sázení rýže.
+cannot_find_work_BEEKEEPING = Váš včelař nemůže ve své pracovní oblasti najít dost volných míst pro úly.
+no_soldier_available_TOWER = Vaši strážní věž nelze obsadit: není k dispozici žádný voják.
+no_soldier_available_BIG_TOWER = Vaši velkou strážní věž nelze obsadit: není k dispozici žádný voják.
+no_soldier_available_CASTLE = Váš hrad nelze obsadit: není k dispozici žádný voják.
+message_missing_tool = %s nelze obsadit: chybí nástroj (%s).
+message_no_free_bearer = %s nelze obsadit: není k dispozici žádný volný nosič.
+action_firerer_slow = Pozor! Hra reaguje pomalu.
+
+# progress display
+progress_LOADING = načítání...
+progress_LOADING_IMAGES = načítání obrázků...
+progress_LOADING_MAP = načítání mapy...
+progress_WAITING_FOR_OTHER_PLAYERS = Čekání na ostatní hráče.
+
+
+movable_BEARER = Nosič
+movable_BEARERp = Nosiči
+movable_SMITH = Kovář
+movable_LUMBERJACK = Dřevorubec
+movable_STONECUTTER = Kameník
+movable_SAWMILLER = Pilař
+movable_FORESTER = Lesník
+movable_MELTER = Hutník
+movable_MINER = Horník
+movable_FISHERMAN = Rybář
+movable_FARMER = Farmář
+movable_MILLER = Mlynář
+movable_BAKER = Pekař
+movable_PIG_FARMER = Chovatel prasat
+movable_SLAUGHTERER = Řezník
+movable_CHARCOAL_BURNER = Uhlíř
+movable_WATERWORKER = Vodař
+
+movable_BRICKLAYER = Stavitel
+movable_BRICKLAYERp = Stavitelé
+movable_DIGGER = Kopáč
+movable_DIGGERp = Kopáči
+
+movable_THIEF = Zloděj
+movable_GEOLOGIST = Geolog
+movable_PIONEER = Pionýr
+movable_TEST_MOVABLE = TEST_MOVABLE
+
+movable_SWORDSMAN_L1 = Šermíř (L1)
+movable_SWORDSMAN_L2 = Šermíř (L2)
+movable_SWORDSMAN_L3 = Šermíř (L3)
+
+movable_PIKEMAN_L1 = Kopiník (L1)
+movable_PIKEMAN_L2 = Kopiník (L2)
+movable_PIKEMAN_L3 = Kopiník (L3)
+
+movable_BOWMAN_L1 = Lučištník (L1)
+movable_BOWMAN_L2 = Lučištník (L2)
+movable_BOWMAN_L3 = Lučištník (L3)
+
+movable_MAGE = Kněz
+movable_DONKEY = Osel
+movable_WHITEFLAGGED_DONKEY = Chráněný osel
+
+movable_FERRY = Trajekt
+movable_CARGO_SHIP = Nákladní loď
+
+movable_BREWER = Sládek
+
+# Gets hours, minutes, seconds
+map-time = Čas: %d:%02d:%02d
+map-fps = FPS: %.1f Rychlost: %.1fx
+
+# Start screen
+
+start-newgame = Nová hra pro jednoho hráče
+start-newgame-start = Spustit hru
+start-loadgame = Načíst hru
+start-loadgame-start = Načíst
+start-newmultiplayer = Nová síťová hra
+start-newmultiplayer-start = Spustit
+start-joinmultiplayer = Připojit se k síťové hře
+start-joinmultiplayer-start = Připojit
+start-recovermultiplayer = Obnovit síťovou hru
+start-startgame = Spustit hru
+
+start-joining-start = Spustit
+start-joining-ready = Připraven
+
+settings-title = Nastavení
+settings-name = Jméno hráče
+settings-language = Jazyk
+settings-server = Server pro hru více hráčů
+settings-volume = Hlasitost
+settings-volume-music = Hlasitost hudby
+settings-music-playall = Přehrávat všechny hudební skladby
+settings-fps-limit = Limit FPS
+settings-fps-limit-none = bez časovače
+settings-backend = Vykreslování
+settings-gui-scale = Velikost rozhraní
+settings-gui-scale-default = výchozí dle systému
+settings-ai-tower-focus = AI staví více věží
+settings-back = Zpět
+settings-ok = OK
+game-menu-pause = Pozastavit
+game-menu-music = Hudba
+game-menu-cancel = Zrušit
+game-menu-quit = Ukončit hru
+game-menu-save = Uložit hru
+game-menu-description = Ukončit nebo uložit hru
+
+multiplayer-joinmatch-title = Připojit se ke hře
+multiplayer-newmatch-title = Nová hra
+
+multiplayer-indicator-match = hra
+multiplayer-indicator-maps = mapy
+multiplayer-indicator-res = zdroje
+multiplayer-indicator-auth = ověření
+
+multiplayer-addserver = Přidat server
+multiplayer-lanpanel = LAN
+multiplayer-lan-overview = Připojení
+multiplayer-lan-start-server = Spustit místní server
+multiplayer-lan-stop-server = Zastavit místní server
+multiplayer-lan-connect = připojit
+multiplayer-lan-disconnect = odpojit
+multiplayer-lan-server-label = server běží (hráčů: %d)
+multiplayer-lan-client-label = připojeno k %s
+multiplayer-lan-search-label = nalezeno serverů: %d
+
+multiplayer-offline = Bez připojení
+multiplayer-connecting = Připojování...
+multiplayer-online = Připojeno
+
+multiplayer-server-name = Název
+multiplayer-server-type = Typ
+multiplayer-server-address = IP/název hostitele
+multiplayer-server-url = URL
+multiplayer-server-username = Uživatelské jméno
+
+multiplayer-server-cancel = Zrušit
+multiplayer-server-delete = Smazat
+multiplayer-server-reset = Obnovit
+multiplayer-server-save = Uložit
+
+multiplayer-mapslist-title = Mapy
+multiplayer-mapslist-entry = "%s" od %s
+multiplayer-mapslist-refresh = Obnovit
+multiplayer-mapslist-download = Stáhnout
+
+multiplayer-log-title = Záznam
+multiplayer-log-settings = Nastavení
+
+# Swing extras
+
+place-folders-at = Zkopírujte prosím obrázky Osadníků do složky %s a zvukové soubory do složky %s.
+bad-folders-version = Potřebujete grafiku z originálního vydání Settlers III. Zkopírujte ji prosím do složky %s.
+place-folders-hint = Složky GFX a SND by měly být zde.
+version-build = revize: %s
+
+select-settlers-3-folder = Vyberte složku s originální instalací Settlers III.
+error-no-settlers-3-folder-selected = Nebyla vybrána žádná originální instalace Settlers III. Bez grafických souborů nelze hru spustit. Ukončuji...
+error-settings-not-saveable = Nastavení se nepodařilo uložit. Ověřte prosím, že do složky JSettlers lze zapisovat.
+
+settlers-folder-still-invalid = Vybraná složka s instalací Settlers III není platná. V následujícím dialogu můžete vybrat platnou složku s instalací Settlers III.
+enter-path = Zadejte cestu
+select-valid-settlers-3-folder = Vyberte prosím platnou složku Settlers III
+select-settlers-3-folder-header = JSettlers - Výběr složky Settlers
+error-open-url = Chyba při otevírání adresy URL
+button-start = Spustit
+i-need-help-button = Potřebuji pomoc
+
+main-panel-exit-button = Konec
+main-panel-new-single-player-game-button = Hra pro jednoho hráče
+date.date-only = d. M. yyyy
+general.search = Hledat
+
+join-game-panel-number-of-players = Počet hráčů
+join-game-panel-start-resources = Počáteční suroviny
+join-game-panel-new-single-player-game-title = Nová hra pro jednoho hráče
+join-game-panel-new-multi-player-game-title = Nová hra více hráčů
+join-game-panel-join-multi-player-game-title = Připojit se ke hře více hráčů
+join-game-panel-start = Spustit hru
+join-game-panel-cancel = Zrušit
+join-game-panel-peace-time = Doba míru
+join-game-panel-player-name = Jméno
+join-game-panel-civilisation = Národ
+join-game-panel-player-type = Typ
+join-game-panel-map-slot = Pozice
+join-game-panel-team = Tým
+join-game-panel-send-chat-message = Odeslat
+
+stats-panel-exit = Další
+stats-panel-name = Jméno
+stats-panel-team = Tým
+stats-panel-manna = Mana
+stats-panel-gold = Zlato
+stats-panel-soldiers = naverbovaní vojáci
+
+peace-time-WITHOUT = žádná
+player-type-HUMAN = Člověk
+player-type-AI_VERY_EASY = Počítač (velmi snadný)
+player-type-AI_EASY = Počítač (snadný)
+player-type-AI_HARD = Počítač (těžký)
+player-type-AI_VERY_HARD = Počítač (velmi těžký)
+
+civilisation-ROMAN = Říman
+civilisation-EGYPTIAN = Egypťan
+civilisation-ASIAN = Asiat
+civilisation-AMAZON = Amazonka
+civilisation-random = Náhodný
+
+player-name-random = Náhodné
+player-name-ROMAN-AI_VERY_EASY = Titus
+player-name-ROMAN-AI_EASY = Augustus
+player-name-ROMAN-AI_HARD = Octavianus
+player-name-ROMAN-AI_VERY_HARD = Caesar
+map-start-resources-HIGH_GOODS = Vysoké
+map-start-resources-MEDIUM_GOODS = Střední
+map-start-resources-LOW_GOODS = Nízké
+
+mapfilter.ALL              = Vše
+mapfilter.JSETTLER         = Pouze JSettlers
+mapfilter.SETTLER_IMPORTED = Importované
+mapfilter.title            = Filtr:
+
+network-messageLabel-PLAYER_JOINED = Hráč se připojil.
+network-messageLabel-PLAYER_LEFT  = Hráč odešel.
+network-messageLabel-UNAUTHORIZED  = Hráč není oprávněn.
+network-messageLabel-NOT_ALL_PLAYERS_READY  = Ne všichni hráči jsou připraveni!
+network-messageLabel-READY_STATE_CHANGED  = Hráč změnil svůj stav připravenosti.
+network-messageLabel-UNKNOWN_ERROR  = Došlo k neznámé chybě.
+network-messageLabel-INVALID_STATE_ERROR = Byl přijat nesprávný stav.
+
+
+errordlg-header = Chyba
+errordlg-map-loading-failed = Mapu se nepodařilo načíst.
+errordlg-start-failed = Došlo k neočekávané chybě:
+
+error-rendering = Došlo k chybě :/\nNahlašte prosím tuto chybu na GitHubu\nPřečtěte si část "Found a bug?" v souboru readme\n(github.com/paulwedeck/settlers-remake)\n\n%s
+
+flatpak-title=Vyberte složku s originální hrou
+flatpak-description=JSettlers ke spuštění potřebuje soubory s grafikou a zvukem z instalace Settlers 3.\nPokud kopii nevlastníte, přečtěte si README na naší stránce GitHub.\nChcete-li pokračovat, musíte nyní vybrat složku s takovou instalací.
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index b9e221d48..38ffeb25d 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -183,7 +183,7 @@ buildingtypes_social   = Misc. Buildings
 spell_ROMAN_EYE = Eye of god
 spell_desc_ROMAN_EYE = A foggy region will be visible for a few seconds
 
-spell_IRRIGATE = Irrigate dessert
+spell_IRRIGATE = Irrigate desert
 spell_desc_IRRIGATE = Transform desert to grass
 
 spell_GREEN_THUMB = Green thumb
@@ -227,8 +227,8 @@ spell_desc_CURSE_BOWMAN = Convert nearby enemy bowman to pioneers
 spell_MELT_SNOW = Melt Snow
 spell_desc_MELT_SNOW = Transform snow into rock. This allows you cross otherwise uncrossable mountain ranges.
 
-spell_SUMMON_STONE = Summon Sto
-spell_desc_SUMMON_STONE = Place some stones on the selection positionne
+spell_SUMMON_STONE = Summon Stone
+spell_desc_SUMMON_STONE = Place some stones on the selected position
 
 spell_SUMMON_FISH = Summon Fish
 spell_desc_SUMMON_FISH = Place some fish in the selected waters
@@ -265,7 +265,7 @@ spell_CALL_GOODS = Call goods
 spell_desc_CALL_GOODS = Teleport stacks from the selected position (as long as it is on your ground) to the position of the priest
 
 spell_DESTROY_ARROWS = Destroy arrows
-spell_desc_DESTROY_ARROWS = Enemy bowman will be unable to shot arrows and damage your soldiers
+spell_desc_DESTROY_ARROWS = Enemy bowmen will be unable to shoot arrows and damage your soldiers
 
 #common spell
 spell_GIFTS = Gifts of god
@@ -375,7 +375,7 @@ minerals_GEMS = A geologist found gems.
 cannot_find_work_LUMBERJACK = Your woodcutter can't find any trees in its work area.
 cannot_find_work_STONECUTTER = Your stonecutter can't find any stone in its work area.
 cannot_find_work_FORESTER = Your forester can't find any free space for new trees in its work area.
-cannot_find_work_FARM = Your grain farm can't find find enough spots to plant wheat in its work area.
+cannot_find_work_FARM = Your grain farm can't find enough spots to plant wheat in its work area.
 cannot_find_work_WINEGROWER = Your winery can't find enough spots for growing vines in its work area.
 cannot_find_work_WATERWORKS = Your waterworks can't find any river in its work area.
 cannot_find_work_FISHER = Your fisher can't find any sea in its work area.
@@ -402,7 +402,7 @@ movable_LUMBERJACK = Woodcutter
 movable_STONECUTTER = Stonecutter
 movable_SAWMILLER = Sawmiller
 movable_FORESTER = Forester
-movable_MELTER = Metalurgist
+movable_MELTER = Metallurgist
 movable_MINER = Miner
 movable_FISHERMAN = Fisherman
 movable_FARMER = Farmer
@@ -466,12 +466,17 @@ start-joining-ready = Ready
 
 settings-title = Settings
 settings-name = Player Name
+settings-language = Language
 settings-server = server for multiplayer games
 settings-volume = Volume
-settings-volume-music = Musicvolume
+settings-volume-music = Music Volume
 settings-music-playall = Play all music tracks
 settings-fps-limit = FPS Limit
+settings-fps-limit-none = timerless redraw
 settings-backend = Drawing Backend
+settings-gui-scale = GUI Scale
+settings-gui-scale-default = system default
+settings-ai-tower-focus = AI builds more towers
 settings-back = Back
 settings-ok = OK
 game-menu-pause = Pause
@@ -508,6 +513,7 @@ multiplayer-server-name = Name
 multiplayer-server-type = Type
 multiplayer-server-address = IP/hostname
 multiplayer-server-url = URL
+multiplayer-server-username = Username
 
 multiplayer-server-cancel = Cancel
 multiplayer-server-delete = Delete
@@ -566,7 +572,7 @@ stats-panel-name = Name
 stats-panel-team = Team
 stats-panel-manna = Manna
 stats-panel-gold = Gold
-stats-panel-soldiers = recruted soldiers
+stats-panel-soldiers = recruited soldiers
 
 peace-time-WITHOUT = without
 player-type-HUMAN = Human
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/JSettlersFrame.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/JSettlersFrame.java
index 270291357..b36a96d55 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/JSettlersFrame.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/JSettlersFrame.java
@@ -41,6 +41,8 @@ import jsettlers.common.menu.IStartedGame;
 import jsettlers.common.menu.IStartingGame;
 import jsettlers.graphics.map.ETextDrawPosition;
 import jsettlers.graphics.map.MapContent;
+import jsettlers.graphics.localization.AbstractLabels;
+import jsettlers.graphics.localization.Labels;
 import jsettlers.logic.map.loading.MapLoader;
 import jsettlers.main.swing.menu.joinpanel.JoinGamePanel;
 import jsettlers.main.swing.menu.mainmenu.MainMenuPanel;
@@ -54,10 +56,11 @@ import jsettlers.main.swing.settings.SettingsManager;
 public class JSettlersFrame extends JFrame {
 	private static final long serialVersionUID = 2607082717493797224L;
 
-	private final MainMenuPanel mainPanel;
-	private final EndgameStatsPanel endgameStatsPanel = new EndgameStatsPanel(this);
-	private final StartingGamePanel startingGamePanel = new StartingGamePanel(this);
-	private final JoinGamePanel joinGamePanel = new JoinGamePanel(this);
+	// not final: the menus are created again when the language is changed
+	private MainMenuPanel mainPanel;
+	private EndgameStatsPanel endgameStatsPanel = new EndgameStatsPanel(this);
+	private StartingGamePanel startingGamePanel = new StartingGamePanel(this);
+	private JoinGamePanel joinGamePanel = new JoinGamePanel(this);
 	private final SwingSoundPlayer soundPlayer = new SwingSoundPlayer(SettingsManager.getInstance());
 
 	private Timer redrawTimer;
@@ -122,6 +125,22 @@ public class JSettlersFrame extends JFrame {
 		}
 	}
 
+	/**
+	 * Switches the user interface to the language selected in the settings. All texts of the menus are read when the menus are created, so all menus
+	 * are created again. This must only be called while the main menu is shown.
+	 */
+	public void applyLanguage() {
+		AbstractLabels.setPreferredLocale(SettingsManager.getInstance().getLocale());
+		Labels.reload();
+
+		mainPanel.dispose();
+		mainPanel = new MainMenuPanel(this);
+		endgameStatsPanel = new EndgameStatsPanel(this);
+		startingGamePanel = new StartingGamePanel(this);
+		joinGamePanel = new JoinGamePanel(this);
+		showMainMenu();
+	}
+
 	public void showMainMenu() {
 		setNewContentPane(mainPanel);
 	}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/mainmenu/MainMenuPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/mainmenu/MainMenuPanel.java
index 355b8e36c..c51c98412 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/mainmenu/MainMenuPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/mainmenu/MainMenuPanel.java
@@ -76,6 +76,8 @@ public class MainMenuPanel extends SplitedBackgroundPanel {
 
 	private final OpenPanel openSinglePlayerPanel;
 
+	private final Timer updateServerTimer;
+
 	public MainMenuPanel(JSettlersFrame settlersFrame) {
 		this.settlersFrame = settlersFrame;
 
@@ -94,7 +96,7 @@ public class MainMenuPanel extends SplitedBackgroundPanel {
 		SwingUtilities.updateComponentTreeUI(this);
 
 
-		Timer updateServerTimer = new Timer(0, action -> {
+		updateServerTimer = new Timer(0, action -> {
 				Component mainPanel = getComponent(2);
 				if(mainPanel instanceof ServerConnectionPanel) {
 					((ServerConnectionPanel)mainPanel).update();
@@ -106,6 +108,20 @@ public class MainMenuPanel extends SplitedBackgroundPanel {
 		updateServerTimer.start();
 	}
 
+	/**
+	 * Stops the background timer of this panel. Call this when the panel is replaced by a new one (for example after the language was changed).
+	 */
+	public void dispose() {
+		updateServerTimer.stop();
+	}
+
+	/**
+	 * Called by the settings panel when the user selected another language.
+	 */
+	public void languageChanged() {
+		settlersFrame.applyLanguage();
+	}
+
 	private void initButtonPanel() {
 		buttonPanel.setLayout(new GridLayout(0, 1, 20, 20));
 
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/RemoteMapDirectoryPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/RemoteMapDirectoryPanel.java
index fbafe181f..9f66f1498 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/RemoteMapDirectoryPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/RemoteMapDirectoryPanel.java
@@ -41,7 +41,8 @@ public class RemoteMapDirectoryPanel extends JPanel {
 	private final JProgressBar progressBar;
 	private final RemoteMapEntryPanel selectedPanel;
 	private static final String RETURN = "..";
-	private static final String REFRESH = Labels.getString("multiplayer-mapslist-refresh");
+	// compared by identity, so it has to be the same instance for the whole life of this panel (not static, so the language can change)
+	private final String refreshEntry = Labels.getString("multiplayer-mapslist-refresh");
 
 	public RemoteMapDirectoryPanel(IClientConnection connection, OpenPanel openSinglePlayerPanel) {
 		this.connection = connection;
@@ -64,7 +65,7 @@ public class RemoteMapDirectoryPanel extends JPanel {
 				String newDir = currentDir.substring(0, currentDir.lastIndexOf('/'));
 				select(newDir.substring(0, newDir.lastIndexOf('/')+1));
 				selectedPanel.setVisible(false);
-			} else if(selected == REFRESH) {
+			} else if(selected == refreshEntry) {
 				select(currentDir);
 			} else {
 				if(selected instanceof String) {
@@ -133,7 +134,7 @@ public class RemoteMapDirectoryPanel extends JPanel {
 		@Override
 		public Object getElementAt(int i) {
 			if(directory == null) return "";
-			if(i == 0) return REFRESH;
+			if(i == 0) return refreshEntry;
 			i--;
 			if(!currentDir.equals("/")) {
 				if (i == 0) return RETURN;
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/EMapFilter.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/EMapFilter.java
index dd13a9180..54e507847 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/EMapFilter.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/EMapFilter.java
@@ -56,18 +56,6 @@ public enum EMapFilter {
 		}
 	};
 
-	/**
-	 * Translated name
-	 */
-	private final String name;
-
-	/**
-	 * Constructor
-	 */
-	EMapFilter() {
-		this.name = Labels.getString("mapfilter." + name());
-	}
-
 	/**
 	 * Filter a single map entry
 	 * 
@@ -81,6 +69,7 @@ public enum EMapFilter {
 	 * @return Translated name
 	 */
 	public String getName() {
-		return name;
+		// looked up every time (not stored), so that it follows a change of the language
+		return Labels.getString("mapfilter." + name());
 	}
 }
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/SearchTextField.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/SearchTextField.java
index e74e26aa0..6535cbbf3 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/SearchTextField.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/SearchTextField.java
@@ -36,7 +36,7 @@ public class SearchTextField extends JTextField {
 	/**
 	 * Search text
 	 */
-	private static final String SEARCH = Labels.getString("general.search");
+	private final String search = Labels.getString("general.search");
 
 	/**
 	 * Search icon
@@ -100,7 +100,7 @@ public class SearchTextField extends JTextField {
 		if (getText().isEmpty()) {
 			x += searchIcon.getIconWidth() + 6;
 			int y = this.getHeight() - (this.getHeight() - g.getFontMetrics().getHeight()) / 2 - g.getFontMetrics().getDescent();
-			g.drawString(SEARCH, x, y);
+			g.drawString(search, x, y);
 		}
 	}
 }
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
index 3cd777d6b..64fcc7ae6 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
@@ -19,6 +19,7 @@ import java.awt.GridLayout;
 
 import javax.swing.JButton;
 import javax.swing.JCheckBox;
+import javax.swing.JComboBox;
 import javax.swing.JComponent;
 import javax.swing.JLabel;
 import javax.swing.JPanel;
@@ -29,6 +30,7 @@ import go.graphics.swing.contextcreator.BackendSelector;
 import jsettlers.graphics.localization.Labels;
 import jsettlers.main.swing.lookandfeel.ELFStyle;
 import jsettlers.main.swing.menu.mainmenu.MainMenuPanel;
+import jsettlers.main.swing.settings.GameLanguage;
 import jsettlers.main.swing.settings.SettingsManager;
 
 /**
@@ -49,8 +51,9 @@ public class SettingsMenuPanel extends JPanel {
 	private final SettingsSlider volumeSlider = new SettingsSlider("%", 0,100, null);
 	private final SettingsSlider volumeMusicSlider = new SettingsSlider("%", 0,100, null);
 	private final JCheckBox playAllMusicCheckBox = new JCheckBox();
-	private final SettingsSlider fpsLimitSlider = new SettingsSlider("fps", 0,240, "timerless redraw");
-	private final SettingsSlider guiScaleSlider = new SettingsSlider("%", 50,400, "system default");
+	private final SettingsSlider fpsLimitSlider = new SettingsSlider("fps", 0,240, Labels.getString("settings-fps-limit-none"));
+	private final SettingsSlider guiScaleSlider = new SettingsSlider("%", 50,400, Labels.getString("settings-gui-scale-default"));
+	private final JComboBox<GameLanguage> languageSelector = new JComboBox<>(GameLanguage.values());
 	private final JCheckBox aiTowerFocusCheckBox = new JCheckBox();
 	private final BackendSelector backendSelector = new BackendSelector();
 
@@ -73,10 +76,14 @@ public class SettingsMenuPanel extends JPanel {
 
 		playerNameField.putClientProperty(ELFStyle.KEY, ELFStyle.TEXT_DEFAULT);
 		backendSelector.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
+		languageSelector.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
+		languageSelector.setEditable(false);
 		
 		SwingUtilities.updateComponentTreeUI(playerNameField);
 		addSetting("settings-name", playerNameField);
 
+		addSetting("settings-language", languageSelector);
+
 		addSetting("settings-volume", volumeSlider);
 
 		addSetting("settings-volume-music", volumeMusicSlider);
@@ -128,6 +135,14 @@ public class SettingsMenuPanel extends JPanel {
 			settingsManager.setBackend(backendSelector.getSelectedItem()+"");
 			settingsManager.setGuiScale(guiScaleSlider.getValue()/100f);
 			settingsManager.setAiNoPioneers(aiTowerFocusCheckBox.isSelected());
+
+			GameLanguage selectedLanguage = (GameLanguage) languageSelector.getSelectedItem();
+			if (selectedLanguage != null && selectedLanguage != GameLanguage.fromLocale(settingsManager.getLocale())) {
+				settingsManager.setLocale(selectedLanguage.getLocale());
+				// replaces all menus (including this one), so there is nothing left to reset here
+				mainMenuPanel.languageChanged();
+				return;
+			}
 			mainMenuPanel.reset();
 		});
 
@@ -141,6 +156,7 @@ public class SettingsMenuPanel extends JPanel {
 	public void initializeValues() {
 		SettingsManager settingsManager = SettingsManager.getInstance();
 		playerNameField.setText(settingsManager.getPlayer().getName());
+		languageSelector.setSelectedItem(GameLanguage.fromLocale(settingsManager.getLocale()));
 		volumeSlider.setValue((int) (settingsManager.getVolume() * 100));
 		volumeMusicSlider.setValue((int) (settingsManager.getMusicVolume() * 100));
 		playAllMusicCheckBox.setSelected(settingsManager.isMusicPlayAll());
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/statspanel/EndgameStatsPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/statspanel/EndgameStatsPanel.java
index 1988dd255..298ba121c 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/statspanel/EndgameStatsPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/statspanel/EndgameStatsPanel.java
@@ -51,7 +51,8 @@ public class EndgameStatsPanel extends BackgroundPanel {
 		SwingUtilities.updateComponentTreeUI(this);
 	}
 
-	private static final String[] columns = new String[] {
+	// not static: the texts must follow a change of the language (the panel is created again then)
+	private final String[] columns = new String[] {
 			Labels.getString("stats-panel-name"),
 			Labels.getString("stats-panel-team"),
 			Labels.getString("stats-panel-manna"),
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/GameLanguage.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/GameLanguage.java
new file mode 100644
index 000000000..1420a49b1
--- /dev/null
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/GameLanguage.java
@@ -0,0 +1,65 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ */
+package jsettlers.main.swing.settings;
+
+import java.util.Locale;
+
+/**
+ * The languages the user can choose in the settings menu. English is the default and is always used as the fallback for texts that are not
+ * translated.
+ * <p>
+ * To add a language, add a <code>labels_xx.properties</code> file next to <code>labels_en.properties</code> (in jsettlers.graphics) and an entry here.
+ * The name is shown in the language itself, so it can be found even when the interface is in a language the user does not understand.
+ */
+public enum GameLanguage {
+	ENGLISH("en", "English"),
+	// "\u010C" = C with caron, "\u0161" = s with caron (written as escapes so that the source encoding does not matter)
+	CZECH("cs", "\u010Ce\u0161tina");
+
+	public static final GameLanguage DEFAULT = ENGLISH;
+
+	private final String languageCode;
+	private final String displayName;
+
+	GameLanguage(String languageCode, String displayName) {
+		this.languageCode = languageCode;
+		this.displayName = displayName;
+	}
+
+	public String getLanguageCode() {
+		return languageCode;
+	}
+
+	public Locale getLocale() {
+		return new Locale(languageCode);
+	}
+
+	/**
+	 * Finds the entry for a locale. Only the language is compared; unknown languages result in {@link #DEFAULT}.
+	 */
+	public static GameLanguage fromLocale(Locale locale) {
+		for (GameLanguage language : values()) {
+			if (language.languageCode.equalsIgnoreCase(locale.getLanguage())) {
+				return language;
+			}
+		}
+		return DEFAULT;
+	}
+
+	@Override
+	public String toString() {
+		return displayName;
+	}
+}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
index 1b0f22cfe..edfaf0158 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
@@ -298,16 +298,26 @@ public class SettingsManager implements ISoundSettingsProvider {
 		return getOptional(SETTING_DISABLE_ORIGINAL_MAPS);
 	}
 
+	/**
+	 * Gets the language of the user interface. English is used unless another language was chosen in the settings menu (or with the setting
+	 * "locale", for example <code>cs</code> or <code>de_de</code>).
+	 */
 	public Locale getLocale() {
 		return Optional.ofNullable(get(SETTING_LOCALE)).map(localeString -> {
-			String[] localeParts = localeString.split("_");
-			if (localeParts.length == 2) {
-				return new Locale(localeParts[0], localeParts[1]);
+			String[] localeParts = localeString.trim().split("[_-]");
+			if (localeParts.length == 1 && !localeParts[0].isEmpty()) {
+				return new Locale(localeParts[0].toLowerCase(Locale.ENGLISH));
+			} else if (localeParts.length == 2) {
+				return new Locale(localeParts[0].toLowerCase(Locale.ENGLISH), localeParts[1].toUpperCase(Locale.ENGLISH));
 			} else {
-				System.err.println("Please specify the locale with language and country. (For example: de_de or en_us). Using default locale.");
-				return Locale.getDefault();
+				System.err.println("Please specify the locale with a language and optionally a country. (For example: cs, de_de or en_us). Using English.");
+				return GameLanguage.DEFAULT.getLocale();
 			}
-		}).orElse(Locale.getDefault());
+		}).orElse(GameLanguage.DEFAULT.getLocale());
+	}
+
+	public void setLocale(Locale locale) {
+		set(SETTING_LOCALE, locale.getLanguage());
 	}
 
 	public String getMapFile() {
PATCH_EOF
cat > "$WORK/patches/13-thief-fixes.patch" <<'PATCH_EOF'
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
index 1cfd28c..fbd6efb 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
@@ -1589,6 +1589,19 @@ public final class MainGrid implements Serializable {
 			return enemy;
 		}
 
+		/**
+		 * A thief on the ground of the searching player's team is stealing from it, so soldiers react to it from the full distance (unlike other
+		 * non-military units that are only attacked when they are close).
+		 */
+		private boolean isThiefOnGroundOf(IAttackable attackable, IPlayer player) {
+			if (attackable.getMovableType() != EMovableType.THIEF) {
+				return false;
+			}
+			ShortPoint2D thiefPosition = attackable.getPosition();
+			Player owner = partitionsGrid.getPlayerAt(thiefPosition.x, thiefPosition.y);
+			return owner != null && owner.getTeamId() == player.getTeamId();
+		}
+
 		private boolean isMilitary(EMovableType type) {
 			return EMovableType.SOLDIERS.contains(type) || type == EMovableType.MAGE;
 		}
@@ -1626,7 +1639,7 @@ public final class MainGrid implements Serializable {
 				int attackDistance = attackable.getPosition().getOnGridDistTo(position);
 
 				if(ignoreFarCivilians && attackDistance > Constants.SOLDIER_CIVILIAN_SEARCH_RADIUS && attackable instanceof IAttackableMovable
-						&& !isMilitary(attackable.getMovableType())) {
+						&& !isMilitary(attackable.getMovableType()) && !isThiefOnGroundOf(attackable, searchingPlayer)) {
 					continue;
 				}
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
index de16fdd..952cc6d 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
@@ -33,6 +33,11 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 
 	private ShortPoint2D returnPos = null;
 
+	/**
+	 * The last position the thief was ordered from while it was on its own ground. The stolen material is carried back here.
+	 */
+	private ShortPoint2D homePos = null;
+
 	public ThiefMovable(AbstractMovableGrid grid, ShortPoint2D position, Player player, Movable movable) {
 		super(grid, EMovableType.THIEF, position, player, movable);
 	}
@@ -50,12 +55,17 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 						mov.currentTarget = null;
 						mov.returnPos = null;
 
+						// remember where to bring the stolen material to (an order given on enemy ground must not make this position the destination)
+						if (mov.homePos == null || mov.isOnOwnGround()) {
+							mov.homePos = mov.position;
+						}
+
 						// steal something
 						if(mov.nextMoveToType.isWorkOnDestination() && mov.getMaterial() == EMaterialType.NO_MATERIAL) {
 							Path dijkstraPath = mov.grid.searchDijkstra(mov, mov.nextTarget.x, mov.nextTarget.y, (short) 30, ESearchType.FOREIGN_MATERIAL);
 							if (dijkstraPath != null) {
 								mov.currentTarget = dijkstraPath.getTargetPosition();
-								mov.returnPos = mov.position;
+								mov.returnPos = mov.homePos;
 							}
 						}
 						if(mov.currentTarget == null) {
@@ -75,7 +85,12 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 					)
 				),
 				guard(mov -> (mov.getMaterial() != EMaterialType.NO_MATERIAL && mov.isOnOwnGround()),
-					action(ThiefMovable::dropMaterialIfPossible)
+					action(mov -> {
+						mov.dropMaterialIfPossible();
+						// one stolen good per order: wait for the next order now
+						mov.currentTarget = null;
+						mov.returnPos = null;
+					})
 				),
 				guard(mov -> mov.currentTarget != null,
 					sequence(
@@ -85,12 +100,18 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 						),
 						selector(
 							condition(mov -> mov.getMaterial() != EMaterialType.NO_MATERIAL),
-							sequence(
+							selector(
+								sequence(
+									stealMaterial(),
+									// Carry the stolen material home. This must be set AFTER the stealing: the go-to-target guard above has a higher priority than
+									// this branch, so setting it before aborted the stealing while it was still running (the thief walked back and forth and never took anything).
+									action(mov -> mov.goToTarget = mov.returnPos)
+								),
+								// nothing (left) to steal here: give up and go back
 								action(mov -> {
-									// 
+									mov.currentTarget = null;
 									mov.goToTarget = mov.returnPos;
-								}),
-								stealMaterial()
+								})
 							)
 						)
 					)
PATCH_EOF
cat > "$WORK/patches/14-zoom-indicator.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index feac693..f421148 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -643,6 +643,11 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 			x -= fps.length() * letterWidth;
 			drawer.drawString(x, yFirstLine, fps);
+
+			// current zoom, left of the frame rate (100% = zoom factor 1, one image pixel per screen pixel)
+			String zoomString = Labels.getString("map-zoom", Math.round(context.getScreen().getZoom() * 100));
+			x -= (zoomString.length() + 1) * letterWidth;
+			drawer.drawString(x, yFirstLine, zoomString);
 		}
 	}
 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index c7a749f..d97e521 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -439,6 +439,7 @@ movable_BREWER = Sládek
 # Gets hours, minutes, seconds
 map-time = Čas: %d:%02d:%02d
 map-fps = FPS: %.1f Rychlost: %.1fx
+map-zoom = Měřítko: %d%%
 
 # Start screen
 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 58428f9..e8d0ef5 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -445,6 +445,7 @@ movable_BREWER = Brewer
 # Gets hours, minutes, seconds
 map-time = Time: %d:%02d:%02d
 map-fps = FPS: %.1f Speed: %.1fx
+map-zoom = Zoom: %d%%
 
 # Start screen
 
PATCH_EOF
cat > "$WORK/patches/15-control-groups.patch" <<'PATCH_EOF'
diff --git a/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/GLFWContextCreator.java b/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/GLFWContextCreator.java
index 3c19034..9b6ae5d 100644
--- a/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/GLFWContextCreator.java
+++ b/go.graphics.swing/src/main/java/go/graphics/swing/contextcreator/GLFWContextCreator.java
@@ -179,6 +179,10 @@ public class GLFWContextCreator extends AsyncContextCreator {
 				}
 			}
 
+			if(mod != null) {
+				return; // a modifier key alone is no key event, it would block the next key (e.g. Control + 1) until it is released
+			}
+
 			if(action == GLFW.GLFW_PRESS) {
 				startKeyEvent(name);
 			} else if(action == GLFW.GLFW_RELEASE){
diff --git a/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java b/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
index 25271b4..859fdf9 100644
--- a/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
+++ b/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
@@ -62,6 +62,11 @@ public class GOSwingEventConverter extends AbstractEventConverter
 
 	private int modifiers;
 
+	/**
+	 * The component that receives the keyboard events.
+	 */
+	private final Component component;
+
 	/**
 	 * Creates a new event converter, that converts swing events to go events.
 	 * 
@@ -72,6 +77,7 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	 */
 	public GOSwingEventConverter(Component component, GOEventHandlerProvider provider) {
 		super(provider);
+		this.component = component;
 		this.scaleFactor = () -> {
 			AffineTransform trans = component.getGraphicsConfiguration().getDefaultTransform();
 			return (trans != null) ? trans.getScaleX() : 1.0;
@@ -89,6 +95,15 @@ public class GOSwingEventConverter extends AbstractEventConverter
 		addReplaceRule(new EventReplacementRule(ReplacableEvent.PAN, Replacement.COMMAND_ACTION, MOUSE_TIME_TRSHOLD, MOUSE_MOVE_TRESHOLD));
 	}
 
+	/**
+	 * Nothing else gives the keyboard focus to the game screen (a click on a canvas does not do that by itself), so no key was received at all.
+	 */
+	private void requestKeyboardFocus() {
+		if (!component.hasFocus()) {
+			component.requestFocusInWindow();
+		}
+	}
+
 	private UIPoint convertToLocal(MouseEvent e) {
 		return new UIPoint(e.getX() * scaleFactor.get(), (e.getComponent().getHeight() - e.getY()) * scaleFactor.get());
 
@@ -97,6 +112,7 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	@Override
 	public void mouseEntered(MouseEvent e) {
 		updateModifiers(e);
+		requestKeyboardFocus();
 		startHover(convertToLocal(e));
 	}
 
@@ -120,6 +136,7 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	@Override
 	public void mousePressed(MouseEvent e) {
 		updateModifiers(e);
+		requestKeyboardFocus();
 		int mouseButton = e.getButton();
 		UIPoint local = convertToLocal(e);
 		if (mouseButton == MouseEvent.BUTTON1) {
@@ -160,6 +177,9 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	@Override
 	public void keyPressed(KeyEvent e) {
 		updateModifiers(e);
+		if (isModifierKey(e)) {
+			return; // a modifier key alone is no key event, it would block the next key (e.g. Control + 1) until it is released
+		}
 		String text = getKeyName(e);
 		startKeyEvent(text);
 		/*
@@ -261,9 +281,18 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	@Override
 	public void keyReleased(KeyEvent e) {
 		updateModifiers(e);
+		if (isModifierKey(e)) {
+			return;
+		}
 		endKeyEvent(getKeyName(e));
 	}
 
+	private static boolean isModifierKey(KeyEvent e) {
+		int code = e.getKeyCode();
+		return code == KeyEvent.VK_CONTROL || code == KeyEvent.VK_SHIFT || code == KeyEvent.VK_ALT || code == KeyEvent.VK_ALT_GRAPH
+				|| code == KeyEvent.VK_META;
+	}
+
 	@Override
 	public void keyTyped(KeyEvent e) {
 	}
diff --git a/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java b/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
index fc1a84e..eb00550 100644
--- a/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
+++ b/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
@@ -210,6 +210,17 @@ public class AbstractEventConverter {
 	}
 
 	protected synchronized void startKeyEvent(String string) {
+		if (string == null) {
+			return;
+		}
+		if (string.length() == 1 && string.charAt(0) >= '0' && string.charAt(0) <= '9' && getCurrentModifiers().contains(EModifier.CTRL)) {
+			// Control + digit is a different key than the digit alone (control groups)
+			string = "CTRL+" + string;
+		}
+		char lastChar = string.charAt(string.length() - 1);
+		if (lastChar >= '0' && lastChar <= '9') {
+			System.out.println("key pressed: " + string); // helps to find out whether the control group keys arrive
+		}
 		if (ongoingKeyEvent == null) {
 			ongoingKeyEvent = new GOKeyEvent(string);
 			replaceKeyEvent(ongoingKeyEvent);
diff --git a/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java b/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
index 8d990a8..5f7931c 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
@@ -113,6 +113,20 @@ public enum EActionType {
 	 */
 	SHOW_SELECTION,
 
+	/**
+	 * Stores the current selection in a control group (Control + 0..9).
+	 *
+	 * @see GroupAction
+	 */
+	ASSIGN_GROUP,
+
+	/**
+	 * Selects the units of a control group again (0..9).
+	 *
+	 * @see GroupAction
+	 */
+	RECALL_GROUP,
+
 	/**
 	 * Sets the screen to display current message.
 	 */
diff --git a/jsettlers.common/src/main/java/jsettlers/common/action/GroupAction.java b/jsettlers.common/src/main/java/jsettlers/common/action/GroupAction.java
new file mode 100644
index 0000000..e8adc61
--- /dev/null
+++ b/jsettlers.common/src/main/java/jsettlers/common/action/GroupAction.java
@@ -0,0 +1,27 @@
+package jsettlers.common.action;
+
+/**
+ * Action for the control groups: {@link EActionType#ASSIGN_GROUP} and {@link EActionType#RECALL_GROUP}.
+ */
+public class GroupAction extends Action {
+
+	/** Number of groups (keys 1 to 9 and 0). */
+	public static final int GROUP_COUNT = 10;
+
+	private final int group;
+
+	/**
+	 * @param actionType
+	 *            {@link EActionType#ASSIGN_GROUP} or {@link EActionType#RECALL_GROUP}
+	 * @param group
+	 *            The number of the group, 0 to {@link #GROUP_COUNT} - 1 (the number on the key).
+	 */
+	public GroupAction(EActionType actionType, int group) {
+		super(actionType);
+		this.group = group;
+	}
+
+	public int getGroup() {
+		return group;
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index f421148..12cbde8 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -49,6 +49,7 @@ import jsettlers.common.CommitInfo;
 import jsettlers.common.CommonConstants;
 import jsettlers.common.action.Action;
 import jsettlers.common.action.EActionType;
+import jsettlers.common.action.GroupAction;
 import jsettlers.common.action.IAction;
 import jsettlers.common.action.PointAction;
 import jsettlers.common.action.ScreenChangeAction;
@@ -924,6 +925,12 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 			return new Action(EActionType.DESTROY);
 		} else if ("ESCAPE".equalsIgnoreCase(keyCode)) {
 			return new Action(EActionType.ABORT);
+		} else if (keyCode != null && keyCode.length() == 1 && keyCode.charAt(0) >= '0' && keyCode.charAt(0) <= '9') {
+			// 0..9: select a control group
+			return new GroupAction(EActionType.RECALL_GROUP, keyCode.charAt(0) - '0');
+		} else if (keyCode != null && keyCode.length() == 6 && keyCode.startsWith("CTRL+") && keyCode.charAt(5) >= '0' && keyCode.charAt(5) <= '9') {
+			// Control + 0..9: store the selection in a control group
+			return new GroupAction(EActionType.ASSIGN_GROUP, keyCode.charAt(5) - '0');
 		} else {
 			return null;
 		}
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
index d407a20..de0f737 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
@@ -14,6 +14,7 @@
  */
 package jsettlers.input;
 
+import java.util.ArrayList;
 import java.util.Comparator;
 import java.util.EnumSet;
 import java.util.LinkedList;
@@ -32,6 +33,7 @@ import jsettlers.common.CommonConstants;
 import jsettlers.common.action.BuildAction;
 import jsettlers.common.action.CastSpellAction;
 import jsettlers.common.action.ChangeTradingRequestAction;
+import jsettlers.common.action.GroupAction;
 import jsettlers.common.action.ConvertAction;
 import jsettlers.common.action.EActionType;
 import jsettlers.common.action.EMoveToType;
@@ -131,6 +133,21 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 	 */
 	private SelectionSet currentSelection = new SelectionSet();
 
+	/**
+	 * The control groups (Control + 0..9 stores the selection, 0..9 selects it). Only used by the user interface, so they are not part of the game
+	 * state and are not saved.
+	 */
+	private final List<IGuiMovable>[] controlGroups = newControlGroups();
+
+	@SuppressWarnings("unchecked")
+	private static List<IGuiMovable>[] newControlGroups() {
+		final List<IGuiMovable>[] groups = new List[GroupAction.GROUP_COUNT];
+		for (int i = 0; i < groups.length; i++) {
+			groups[i] = new ArrayList<>();
+		}
+		return groups;
+	}
+
 	public GuiInterface(IMapInterfaceConnector connector, IGameClock clock, ITaskScheduler taskScheduler, IGuiInputGrid grid, IGameStoppable gameStoppable, byte playerId, boolean multiplayer) {
 		this.connector = connector;
 		this.clock = clock;
@@ -285,6 +302,14 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 				showSelection();
 				break;
 
+			case ASSIGN_GROUP:
+				assignGroup(((GroupAction) action).getGroup());
+				break;
+
+			case RECALL_GROUP:
+				recallGroup(((GroupAction) action).getGroup());
+				break;
+
 			case SCREEN_CHANGE:
 				constructionMarksCalculator.setScreen(((ScreenChangeAction) action).getScreenArea());
 				break;
@@ -570,6 +595,51 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 		}
 	}
 
+	/**
+	 * Stores the movables of the current selection in the given control group (and removes them from every other group, a unit is only member of one
+	 * group). An empty selection empties the group. Buildings are not stored, the selection is left as it is in that case.
+	 */
+	private void assignGroup(int group) {
+		if (group < 0 || group >= controlGroups.length || (currentSelection.getSelectionType() == ESelectionType.BUILDING && !currentSelection.isEmpty())) {
+			return;
+		}
+
+		final List<IGuiMovable> members = new ArrayList<>();
+		for (final ISelectable selectable : currentSelection) {
+			if (selectable instanceof IGuiMovable) {
+				members.add((IGuiMovable) selectable);
+			}
+		}
+		// a unit is only member of one group: the last one it was added to
+		for (final List<IGuiMovable> otherGroup : controlGroups) {
+			otherGroup.removeAll(members);
+		}
+		controlGroups[group] = members;
+	}
+
+	/**
+	 * Selects the members of the given control group that are still alive (and still ours). The selection is not changed if nobody is left.
+	 */
+	private void recallGroup(int group) {
+		if (group < 0 || group >= controlGroups.length) {
+			return;
+		}
+
+		final List<IGuiMovable> members = new ArrayList<>();
+		for (final IGuiMovable member : controlGroups[group]) {
+			if (!(member instanceof IGraphicsMovable) || ((IGraphicsMovable) member).isAlive()) {
+				if (canSelectPlayer(member.getPlayer())) {
+					members.add(member);
+				}
+			}
+		}
+		controlGroups[group] = members; // forget the dead ones
+
+		if (!members.isEmpty()) {
+			setSelection(new SelectionSet(members));
+		}
+	}
+
 	private void showSelection() {
 		int x = 0;
 		int y = 0;
PATCH_EOF
cat > "$WORK/patches/16-peacetime.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/statistics/IGameTimeProvider.java b/jsettlers.common/src/main/java/jsettlers/common/statistics/IGameTimeProvider.java
index 3636a9a..7da015b 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/statistics/IGameTimeProvider.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/statistics/IGameTimeProvider.java
@@ -58,4 +58,13 @@ public interface IGameTimeProvider {
 	 * @return true if the game is pausing, false if not.
 	 */
 	boolean isGamePausing();
+
+	/**
+	 * Gets the game time at which the peace time ends.
+	 *
+	 * @return The game time in milliseconds at which the peace time ends. 0 if there is no peace time.
+	 */
+	default int getPeaceTimeEnd() {
+		return 0;
+	}
 }
\ No newline at end of file
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 12cbde8..ccfda38 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -649,6 +649,15 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 			String zoomString = Labels.getString("map-zoom", Math.round(context.getScreen().getZoom() * 100));
 			x -= (zoomString.length() + 1) * letterWidth;
 			drawer.drawString(x, yFirstLine, zoomString);
+
+			// remaining peace time, left of the zoom. It disappears when the peace time is over.
+			int peaceTimeLeft = gameTimeProvider.getPeaceTimeEnd() - gameTimeProvider.getGameTime();
+			if (peaceTimeLeft > 0) {
+				int secondsLeft = (peaceTimeLeft + 999) / 1000;
+				String peaceString = Labels.getString("map-peacetime", secondsLeft / 60, secondsLeft % 60);
+				x -= (peaceString.length() + 1) * letterWidth;
+				drawer.drawString(x, yFirstLine, peaceString);
+			}
 		}
 	}
 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index d97e521..2e57b60 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -440,6 +440,7 @@ movable_BREWER = Sládek
 map-time = Čas: %d:%02d:%02d
 map-fps = FPS: %.1f Rychlost: %.1fx
 map-zoom = Měřítko: %d%%
+map-peacetime = Doba míru: %d:%02d
 
 # Start screen
 
@@ -568,6 +569,12 @@ stats-panel-gold = Zlato
 stats-panel-soldiers = naverbovaní vojáci
 
 peace-time-WITHOUT = žádná
+peace-time-MINUTES_10 = 10 minut
+peace-time-MINUTES_20 = 20 minut
+peace-time-MINUTES_30 = 30 minut
+peace-time-MINUTES_40 = 40 minut
+peace-time-MINUTES_50 = 50 minut
+peace-time-MINUTES_60 = 60 minut
 player-type-HUMAN = Člověk
 player-type-AI_VERY_EASY = Počítač (velmi snadný)
 player-type-AI_EASY = Počítač (snadný)
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index e8d0ef5..1c1c85c 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -446,6 +446,7 @@ movable_BREWER = Brewer
 map-time = Time: %d:%02d:%02d
 map-fps = FPS: %.1f Speed: %.1fx
 map-zoom = Zoom: %d%%
+map-peacetime = Peace time: %d:%02d
 
 # Start screen
 
@@ -574,6 +575,12 @@ stats-panel-gold = Gold
 stats-panel-soldiers = recruited soldiers
 
 peace-time-WITHOUT = without
+peace-time-MINUTES_10 = 10 minutes
+peace-time-MINUTES_20 = 20 minutes
+peace-time-MINUTES_30 = 30 minutes
+peace-time-MINUTES_40 = 40 minutes
+peace-time-MINUTES_50 = 50 minutes
+peace-time-MINUTES_60 = 60 minutes
 player-type-HUMAN = Human
 player-type-AI_VERY_EASY = Computer (very easy)
 player-type-AI_EASY = Computer (easy)
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
index 58cdb58..fa7cd74 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
@@ -39,6 +39,7 @@ import jsettlers.input.tasks.EGuiAction;
 import jsettlers.input.tasks.MovableGuiTask;
 import jsettlers.input.tasks.MoveToGuiTask;
 import jsettlers.input.tasks.OrderShipGuiTask;
+import jsettlers.input.tasks.PeaceTimeGuiTask;
 import jsettlers.input.tasks.SetAcceptedStockMaterialGuiTask;
 import jsettlers.input.tasks.SetBuildingPriorityGuiTask;
 import jsettlers.input.tasks.SetDockGuiTask;
@@ -59,6 +60,7 @@ import jsettlers.logic.buildings.military.occupying.OccupyingBuilding;
 import jsettlers.logic.buildings.others.StockBuilding;
 import jsettlers.logic.buildings.trading.TradingBuilding;
 import jsettlers.logic.buildings.workers.DockyardBuilding;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.logic.map.grid.partition.manager.settings.MaterialProductionSettings;
 import jsettlers.logic.movable.Movable;
 import jsettlers.logic.movable.MovableManager;
@@ -243,6 +245,12 @@ class GuiTaskExecutor implements ITaskExecutor {
 				break;
 			}
 
+			case SET_PEACE_TIME: {
+				PeaceTimeGuiTask task = (PeaceTimeGuiTask) guiTask;
+				MatchConstants.setPeaceTimeEnd(task.getMinutes() * 60 * 1000);
+				break;
+			}
+
 			default:
 				break;
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/tasks/EGuiAction.java b/jsettlers.logic/src/main/java/jsettlers/input/tasks/EGuiAction.java
index 214977d..2ceef04 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/tasks/EGuiAction.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/tasks/EGuiAction.java
@@ -57,6 +57,13 @@ public enum EGuiAction {
 	CAST_SPELL,
 	CHANGE_MOVABLE_SETTINGS,
 	SET_MOVABLE_LIMIT_TYPE,
+
+	/**
+	 * Sets the peace time (no fighting) at the beginning of a game.
+	 *
+	 * @see PeaceTimeGuiTask
+	 */
+	SET_PEACE_TIME,
 	;
 
 	public static final EGuiAction[] VALUES = values();
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/tasks/PeaceTimeGuiTask.java b/jsettlers.logic/src/main/java/jsettlers/input/tasks/PeaceTimeGuiTask.java
new file mode 100644
index 0000000..3233c88
--- /dev/null
+++ b/jsettlers.logic/src/main/java/jsettlers/input/tasks/PeaceTimeGuiTask.java
@@ -0,0 +1,51 @@
+package jsettlers.input.tasks;
+
+import java.io.DataInputStream;
+import java.io.DataOutputStream;
+import java.io.IOException;
+
+/**
+ * Sets the length of the peace time at the start of a game. During the peace time, no military unit attacks anybody.
+ * <p>
+ * The task is a normal lockstep task, so all players of a multiplayer game (and replays) get the same peace time.
+ */
+public class PeaceTimeGuiTask extends SimpleGuiTask {
+	private int minutes;
+
+	public PeaceTimeGuiTask() {
+	}
+
+	public PeaceTimeGuiTask(byte playerId, int minutes) {
+		super(EGuiAction.SET_PEACE_TIME, playerId);
+		this.minutes = minutes;
+	}
+
+	/**
+	 * @return The length of the peace time in minutes of game time (counted from the start of the game).
+	 */
+	public int getMinutes() {
+		return minutes;
+	}
+
+	@Override
+	protected void serializeTask(DataOutputStream dos) throws IOException {
+		super.serializeTask(dos);
+		dos.writeInt(minutes);
+	}
+
+	@Override
+	protected void deserializeTask(DataInputStream dis) throws IOException {
+		super.deserializeTask(dis);
+		minutes = dis.readInt();
+	}
+
+	@Override
+	public boolean equals(Object o) {
+		return this == o || (o instanceof PeaceTimeGuiTask && super.equals(o) && minutes == ((PeaceTimeGuiTask) o).minutes);
+	}
+
+	@Override
+	public int hashCode() {
+		return 31 * super.hashCode() + minutes;
+	}
+}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/constants/MatchConstants.java b/jsettlers.logic/src/main/java/jsettlers/logic/constants/MatchConstants.java
index e97a3e2..cbe4b9e 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/constants/MatchConstants.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/constants/MatchConstants.java
@@ -55,6 +55,12 @@ public final class MatchConstants {
 	private static ExtendedRandom gameRandom;
 	private static ExtendedRandom aiRandom;
 
+	/**
+	 * Game time (in ms) at which the peace time ends. 0 = no peace time. It is set by a lockstep task, so it is the same on all clients.
+	 * It is not part of savegames (a loaded game has no peace time).
+	 */
+	private static volatile int peaceTimeEnd = 0;
+
 	public static void init(IGameClock clock, long randomSeed) {
 		clearState();
 		MatchConstants.clock = clock;
@@ -69,10 +75,31 @@ public final class MatchConstants {
 			clock.stopExecution();
 		}
 		clock = null;
+		peaceTimeEnd = 0;
 		gameRandom = null;
 		aiRandom = null;
 	}
 
+	public static void setPeaceTimeEnd(int gameTimeMs) {
+		peaceTimeEnd = Math.max(gameTimeMs, 0);
+	}
+
+	/**
+	 * @return The game time in ms at which the peace time ends, 0 if there is no peace time.
+	 */
+	public static int getPeaceTimeEnd() {
+		return peaceTimeEnd;
+	}
+
+	/**
+	 * @return true while the peace time is running. During the peace time, nobody may attack anybody.
+	 */
+	public static boolean isPeaceTime() {
+		IGameClock currentClock = clock;
+		int end = peaceTimeEnd;
+		return end > 0 && currentClock != null && currentClock.getTime() < end;
+	}
+
 	public static IGameClock clock() {
 		return clock;
 	}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/movable/MovableGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/movable/MovableGrid.java
index ea267dc..27f2b4e 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/movable/MovableGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/movable/MovableGrid.java
@@ -28,6 +28,7 @@ import jsettlers.common.utils.coordinates.CoordinateStream;
 import jsettlers.common.utils.mutables.MutableBoolean;
 import jsettlers.logic.SerializationUtils;
 import jsettlers.logic.constants.Constants;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.logic.map.grid.landscape.IWalkableGround;
 import jsettlers.logic.movable.interfaces.IAttackable;
 import jsettlers.logic.movable.interfaces.IAttackableMovable;
@@ -148,6 +149,9 @@ public final class MovableGrid implements Serializable {
 	 * @return
 	 */
 	public static boolean isEnemy(IPlayer player, IAttackable otherAttackable) {
+		if (MatchConstants.isPeaceTime()) {
+			return false; // nobody attacks anybody during the peace time
+		}
 		return otherAttackable.getPlayer().getTeamId() != player.getTeamId() && otherAttackable.isAttackable();
 	}
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/objects/ObjectsGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/objects/ObjectsGrid.java
index 7afd22e..e34c27a 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/objects/ObjectsGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/objects/ObjectsGrid.java
@@ -30,6 +30,7 @@ import jsettlers.common.utils.coordinates.CoordinateStream;
 import jsettlers.logic.SerializationUtils;
 import jsettlers.logic.buildings.Building;
 import jsettlers.logic.constants.Constants;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.logic.movable.interfaces.IAttackable;
 import jsettlers.logic.movable.interfaces.IInformable;
 
@@ -217,12 +218,13 @@ public final class ObjectsGrid implements Serializable {
 		}
 
 		byte movableTeam = attackable.getPlayer().getTeamId();
+		final boolean peaceTime = MatchConstants.isPeaceTime(); // towers do not react to enemies during the peace time
 
 		area.filterBounds(width, height)
 				.forEach((x, y) -> {
 					IAttackable currTower = (IAttackable) getMapObjectAt(x, y, EMapObjectType.ATTACKABLE_TOWER);
 
-					if (currTower != null && currTower.getPlayer().getTeamId() != movableTeam) {
+					if (!peaceTime && currTower != null && currTower.getPlayer().getTeamId() != movableTeam) {
 						currTower.informAboutAttackable(attackable);
 
 						if (informAttackable) {
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/SoldierMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/SoldierMovable.java
index e022db6..445e9e3 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/SoldierMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/military/SoldierMovable.java
@@ -40,6 +40,8 @@ public abstract class SoldierMovable extends AttackableHumanMovable implements I
 	private ShortPoint2D[] patrolPoints = null;
 
 	private boolean enemyNearby;
+	/** true, after the soldier has looked around once more because the peace time is over. */
+	private boolean peaceEndHandled;
 	private IAttackable toCloseEnemy;
 	private ShortPoint2D startPoint;
 
@@ -130,7 +132,7 @@ public abstract class SoldierMovable extends AttackableHumanMovable implements I
 					)
 				),
 				// attack enemies from the top of the tower
-				guard(mov -> mov.isBowman() && mov.isInTower && mov.enemyNearby,
+				guard(mov -> mov.isBowman() && mov.isInTower && mov.hasEnemyNearby(),
 					sequence(
 						selector(
 							findEnemy(),
@@ -143,7 +145,7 @@ public abstract class SoldierMovable extends AttackableHumanMovable implements I
 					)
 				),
 				// attack enemy
-				guard(mov -> mov.enemyNearby && !mov.isInTower,
+				guard(mov -> mov.hasEnemyNearby() && !mov.isInTower,
 					selector(
 						sequence(
 							// handle potential enemy
@@ -224,6 +226,18 @@ public abstract class SoldierMovable extends AttackableHumanMovable implements I
 		);
 	}
 
+	/**
+	 * Enemies are not reported to the soldiers during the peace time (and a soldier that has found nobody stops looking). So every soldier has to
+	 * look around once when the peace time is over, otherwise it would only notice enemies that move next to it.
+	 */
+	private boolean hasEnemyNearby() {
+		if (!enemyNearby && !peaceEndHandled && MatchConstants.getPeaceTimeEnd() > 0 && !MatchConstants.isPeaceTime()) {
+			enemyNearby = true;
+			peaceEndHandled = true;
+		}
+		return enemyNearby;
+	}
+
 	private static Node<SoldierMovable> findEnemy() {
 		return condition(mov -> {
 			mov.enemy = mov.grid.getEnemyInSearchArea(mov.getAttackPosition(), mov, mov.getMinSearchDistance(), mov.getMaxSearchDistance(), !mov.defending);
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/GameTimeProvider.java b/jsettlers.logic/src/main/java/jsettlers/main/GameTimeProvider.java
index 1f868b6..20d6843 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/GameTimeProvider.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/GameTimeProvider.java
@@ -15,6 +15,7 @@
 package jsettlers.main;
 
 import jsettlers.common.statistics.IGameTimeProvider;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.network.client.interfaces.IGameClock;
 
 /**
@@ -41,6 +42,11 @@ public class GameTimeProvider implements IGameTimeProvider {
 		return gameClock.isPausing();
 	}
 
+	@Override
+	public int getPeaceTimeEnd() {
+		return MatchConstants.getPeaceTimeEnd();
+	}
+
 	@Override
 	public float getGameSpeed() {
 		return gameClock.getGameSpeed();
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
index 61b0d1f..ae5133d 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
@@ -44,6 +44,7 @@ import jsettlers.common.statistics.IGameTimeProvider;
 import jsettlers.input.GuiInterface;
 import jsettlers.input.IGameStoppable;
 import jsettlers.input.PlayerState;
+import jsettlers.input.tasks.PeaceTimeGuiTask;
 import jsettlers.logic.buildings.Building;
 import jsettlers.logic.buildings.trading.HarborBuilding;
 import jsettlers.logic.buildings.trading.MarketBuilding;
@@ -70,6 +71,16 @@ public class JSettlersGame {
 	private static final SimpleDateFormat LOG_DATE_FORMATTER = new SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US);
 	private final Object stopMutex = new Object();
 
+	/**
+	 * Length of the peace time (in minutes) for the next game that is started. Set by the menu of the host / single player just before the game
+	 * is started. The game reads and resets it when it starts. It is sent to all players as a normal game task.
+	 */
+	private static volatile int nextGamePeaceTimeMinutes = 0;
+
+	public static void setNextGamePeaceTimeMinutes(int minutes) {
+		nextGamePeaceTimeMinutes = Math.max(minutes, 0);
+	}
+
 	private final IGameCreator mapCreator;
 	private final INetworkConnector networkConnector;
 	private final boolean multiplayer;
@@ -222,6 +233,9 @@ public class JSettlersGame {
 				networkConnector.setStartFinished(true);
 				waitForAllPlayersStartFinished(networkConnector);
 
+				final int peaceTimeMinutes = nextGamePeaceTimeMinutes;
+				nextGamePeaceTimeMinutes = 0;
+
 				final IMapInterfaceConnector connector = startingGameListener.preLoadFinished(this);
 				GuiInterface guiInterface = new GuiInterface(connector, MatchConstants.clock(), networkConnector.getTaskScheduler(),
 						mainGrid.getGuiInputGrid(), this, initialGameState.getPlayerId(), multiplayer);
@@ -232,6 +246,9 @@ public class JSettlersGame {
 				networkConnector.getGameClock().schedule(aiExecutor, (short) 1000);
 
 				MatchConstants.clock().startExecution(); // WARNING: GAME CLOCK IS STARTED!
+				if (peaceTimeMinutes > 0 && replayFileInputStream == null) { // a replay contains this task already
+					networkConnector.getTaskScheduler().scheduleTask(new PeaceTimeGuiTask(initialGameState.getPlayerId(), peaceTimeMinutes));
+				}
 				// NO CONFIGURATION AFTER THIS POINT! =================================
 				gameRunning = true;
 
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 5d03de4..7047f90 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -238,6 +238,7 @@ public class JoinGamePanel extends BackgroundPanel {
 
 			MapStartResourcesUIWrapper selected = (MapStartResourcesUIWrapper) startResourcesComboBox.getSelectedItem();
 			InitialGameState initialGameState = new InitialGameState(playerSlots.get(0).getSlot(), playerSettings, randomSeed, selected.getStartResources());
+			applySelectedPeaceTime();
 			JSettlersGame game = new JSettlersGame(mapLoader, initialGameState);
 			IStartingGame startingGame = game.start();
 			settlersFrame.showStartingGamePanel(startingGame);
@@ -251,7 +252,7 @@ public class JoinGamePanel extends BackgroundPanel {
 	public void setNewMultiPlayerMap(MapLoader mapLoader, IMultiplayerConnector connector) {
 		this.playerSlotFactory = new HostOfMultiplayerPlayerSlotFactory(connector);
 		titleLabel.setText(Labels.getString("join-game-panel-new-multi-player-game-title"));
-		peaceTimeComboBox.setEnabled(false);
+		peaceTimeComboBox.setEnabled(true);
 		startResourcesComboBox.setEnabled(false);
 		startGameButton.setVisible(true);
 		setChatVisible(true);
@@ -269,7 +270,10 @@ public class JoinGamePanel extends BackgroundPanel {
 			public void gameJoined(IJoinPhaseMultiplayerGameConnector connector) {
 				SwingUtilities.invokeLater(() -> {
 					initializeChatFor(connector);
-					setStartButtonActionListener(e -> connector.startGame());
+					setStartButtonActionListener(e -> {
+						applySelectedPeaceTime();
+						connector.startGame();
+					});
 					connector.getSlots().setListener(changingSlots -> onSlotsChanged(changingSlots, connector, myId, true));
 					connector.setMultiplayerListener(new IMultiplayerListener() {
 						@Override
@@ -399,12 +403,23 @@ public class JoinGamePanel extends BackgroundPanel {
 		});
 	}
 
+	/**
+	 * Hands the selected peace time over to the game that is started next.
+	 */
+	private void applySelectedPeaceTime() {
+		EPeaceTime selected = (EPeaceTime) peaceTimeComboBox.getSelectedItem();
+		JSettlersGame.setNextGamePeaceTimeMinutes(selected == null ? 0 : selected.minutes);
+	}
+
 	private void prepareUiFor(MapLoader mapLoader) {
 		this.mapLoader = mapLoader;
 		mapNameLabel.setText(mapLoader.getMapName());
 		mapImage.setIcon(new ImageIcon(JSettlersSwingUtil.createBufferedImageFrom(mapLoader)));
 		peaceTimeComboBox.removeAllItems();
-		peaceTimeComboBox.addItem(EPeaceTime.WITHOUT);
+		for (EPeaceTime peaceTime : EPeaceTime.values()) {
+			peaceTimeComboBox.addItem(peaceTime);
+		}
+		peaceTimeComboBox.setSelectedItem(EPeaceTime.WITHOUT);
 		startResourcesComboBox.removeAllItems();
 		Arrays.stream(EMapStartResources.values())
 				.map(MapStartResourcesUIWrapper::new)
@@ -512,7 +527,19 @@ public class JoinGamePanel extends BackgroundPanel {
 	}
 
 	private enum EPeaceTime {
-		WITHOUT;
+		WITHOUT(0),
+		MINUTES_10(10),
+		MINUTES_20(20),
+		MINUTES_30(30),
+		MINUTES_40(40),
+		MINUTES_50(50),
+		MINUTES_60(60);
+
+		final int minutes;
+
+		EPeaceTime(int minutes) {
+			this.minutes = minutes;
+		}
 
 		@Override
 		public String toString() {
PATCH_EOF
cat > "$WORK/patches/17-hd-graphics.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdCacheFile.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdCacheFile.java
new file mode 100644
index 000000000..7e31c37f7
--- /dev/null
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdCacheFile.java
@@ -0,0 +1,312 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.graphics.image.hd;
+
+import java.io.ByteArrayOutputStream;
+import java.io.Closeable;
+import java.io.File;
+import java.io.IOException;
+import java.io.RandomAccessFile;
+import java.nio.ByteBuffer;
+import java.nio.ByteOrder;
+import java.nio.IntBuffer;
+import java.util.HashMap;
+import java.util.Map;
+import java.util.zip.DataFormatException;
+import java.util.zip.Deflater;
+import java.util.zip.Inflater;
+
+import go.graphics.ImageData;
+
+/**
+ * A file with the enlarged ("HD") versions of the images of one original graphics file (siedler3_XX.*.dat).
+ * <p>
+ * The images are found by the position and kind of the image in the original file. The file is created on the computer of the user from the original
+ * graphics (see {@link HdGenerator}); the enlarged images are never distributed.
+ * <p>
+ * Layout: header (magic, version, scale, size of the original file, engine name, number of images, position of the index), the compressed
+ * images, the index (position in the original file, width, height, position and length of the data).
+ */
+public final class HdCacheFile implements Closeable {
+	private static final int MAGIC = 0x4A534844; // "JSHD"
+	private static final int VERSION = 3;
+
+	/** Kinds of images, they are part of the key of an image. */
+	public static final int KIND_SETTLER = 0;
+	public static final int KIND_TORSO = 1;
+	public static final int KIND_SHADOW = 2;
+	/** A terrain texture (a repeating tile). */
+	public static final int KIND_LANDSCAPE = 3;
+	/** An icon, button or other image of the user interface. */
+	public static final int KIND_GUI = 4;
+
+	/**
+	 * The key of an image: its position in the original graphics file and its kind.
+	 */
+	public static long key(long position, int kind) {
+		return (position << 3) | kind;
+	}
+
+	public static long positionOf(long key) {
+		return key >>> 3;
+	}
+
+	public static int kindOf(long key) {
+		return (int) (key & 7);
+	}
+
+	private static final class Entry {
+		final int width;
+		final int height;
+		final long offset;
+		final int length;
+
+		Entry(int width, int height, long offset, int length) {
+			this.width = width;
+			this.height = height;
+			this.offset = offset;
+			this.length = length;
+		}
+	}
+
+	private final RandomAccessFile file;
+	private final Map<Long, Entry> index;
+	private final int scale;
+	private final String engine;
+
+	private HdCacheFile(RandomAccessFile file, Map<Long, Entry> index, int scale, String engine) {
+		this.file = file;
+		this.index = index;
+		this.scale = scale;
+		this.engine = engine;
+	}
+
+	/**
+	 * Opens a cache file.
+	 *
+	 * @param sourceSize
+	 *            The size of the original graphics file. The cache is only used if it was created from a file of the same size.
+	 * @param engine
+	 *            The engine the cache has to be made with, null if any engine is fine.
+	 * @return The cache or null, if it does not exist or does not fit.
+	 */
+	public static HdCacheFile open(File cacheFile, long sourceSize, String engine) {
+		if (!cacheFile.isFile()) {
+			return null;
+		}
+		RandomAccessFile raf = null;
+		try {
+			raf = new RandomAccessFile(cacheFile, "r");
+			if (raf.readInt() != MAGIC || raf.readInt() != VERSION) {
+				raf.close();
+				return null;
+			}
+			int scale = raf.readInt();
+			long size = raf.readLong();
+			String cacheEngine = raf.readUTF();
+			int count = raf.readInt();
+			long indexPosition = raf.readLong();
+			if (size != sourceSize || scale != HdGraphics.SCALE || indexPosition <= 0 || (engine != null && !engine.equals(cacheEngine))) {
+				raf.close();
+				return null;
+			}
+
+			raf.seek(indexPosition);
+			Map<Long, Entry> index = new HashMap<>(count * 2);
+			for (int i = 0; i < count; i++) {
+				long key = raf.readLong();
+				int width = raf.readInt();
+				int height = raf.readInt();
+				long offset = raf.readLong();
+				int length = raf.readInt();
+				index.put(key, new Entry(width, height, offset, length));
+			}
+			return new HdCacheFile(raf, index, scale, cacheEngine);
+		} catch (IOException e) {
+			HdGraphics.log("the file " + cacheFile + " can not be read: " + e);
+			if (raf != null) {
+				try {
+					raf.close();
+				} catch (IOException ex) { /* nothing to do */ }
+			}
+			return null;
+		}
+	}
+
+	public String getEngine() {
+		return engine;
+	}
+
+	public int getImageCount() {
+		return index.size();
+	}
+
+	/**
+	 * Gets the enlarged image.
+	 *
+	 * @param key
+	 *            The key of the image, see {@link #key(long, int)}.
+	 * @return The image or null if there is none.
+	 */
+	public ImageData get(long key) {
+		Entry entry = index.get(key);
+		if (entry == null) {
+			return null;
+		}
+
+		byte[] compressed = new byte[entry.length];
+		synchronized (this) {
+			try {
+				file.seek(entry.offset);
+				file.readFully(compressed);
+			} catch (IOException e) {
+				HdGraphics.log("reading an image failed: " + e);
+				return null;
+			}
+		}
+
+		byte[] raw = new byte[entry.width * entry.height * 4];
+		Inflater inflater = new Inflater();
+		try {
+			inflater.setInput(compressed);
+			int done = 0;
+			while (done < raw.length && !inflater.finished()) {
+				int read = inflater.inflate(raw, done, raw.length - done);
+				if (read == 0 && (inflater.needsInput() || inflater.needsDictionary())) {
+					break;
+				}
+				done += read;
+			}
+			if (done != raw.length) {
+				return null;
+			}
+		} catch (DataFormatException e) {
+			return null;
+		} finally {
+			inflater.end();
+		}
+
+		IntBuffer buffer = ByteBuffer.allocateDirect(raw.length).order(ByteOrder.nativeOrder()).asIntBuffer();
+		ByteBuffer bytes = ByteBuffer.wrap(raw).order(ByteOrder.BIG_ENDIAN);
+		for (int i = 0; i < entry.width * entry.height; i++) {
+			buffer.put(i, bytes.getInt());
+		}
+		buffer.rewind();
+		return ImageData.of(buffer, entry.width, entry.height);
+	}
+
+	@Override
+	public void close() throws IOException {
+		file.close();
+	}
+
+	/**
+	 * Creates a cache file.
+	 */
+	public static final class Writer implements Closeable {
+		private final File target;
+		private final File temp;
+		private final RandomAccessFile file;
+		private final String engine;
+		private final long sourceSize;
+		private final Map<Long, Entry> entries = new HashMap<>();
+		private final Deflater deflater = new Deflater(Deflater.BEST_SPEED);
+
+		public Writer(File target, long sourceSize, String engine) throws IOException {
+			this.target = target;
+			this.temp = new File(target.getPath() + ".tmp");
+			this.sourceSize = sourceSize;
+			this.engine = engine;
+			File parent = target.getAbsoluteFile().getParentFile();
+			if (parent != null) {
+				parent.mkdirs();
+			}
+			this.file = new RandomAccessFile(temp, "rw");
+			this.file.setLength(0);
+			writeHeader(0);
+		}
+
+		private void writeHeader(long indexPosition) throws IOException {
+			file.seek(0);
+			file.writeInt(MAGIC);
+			file.writeInt(VERSION);
+			file.writeInt(HdGraphics.SCALE);
+			file.writeLong(sourceSize);
+			file.writeUTF(engine);
+			file.writeInt(entries.size());
+			file.writeLong(indexPosition);
+		}
+
+		/**
+		 * @param pixels
+		 *            The pixels in the format of {@link ImageData} (red, green, blue, alpha).
+		 */
+		public void add(long key, int width, int height, int[] pixels) throws IOException {
+			ByteBuffer bytes = ByteBuffer.allocate(width * height * 4).order(ByteOrder.BIG_ENDIAN);
+			bytes.asIntBuffer().put(pixels, 0, width * height);
+
+			deflater.reset();
+			deflater.setInput(bytes.array());
+			deflater.finish();
+			ByteArrayOutputStream out = new ByteArrayOutputStream(bytes.capacity() / 2 + 64);
+			byte[] chunk = new byte[16384];
+			while (!deflater.finished()) {
+				int length = deflater.deflate(chunk);
+				out.write(chunk, 0, length);
+			}
+
+			long offset = file.length();
+			file.seek(offset);
+			file.write(out.toByteArray());
+			entries.put(key, new Entry(width, height, offset, out.size()));
+		}
+
+		@Override
+		public void close() throws IOException {
+			try {
+				long indexPosition = file.length();
+				file.seek(indexPosition);
+				for (Map.Entry<Long, Entry> e : entries.entrySet()) {
+					file.writeLong(e.getKey());
+					file.writeInt(e.getValue().width);
+					file.writeInt(e.getValue().height);
+					file.writeLong(e.getValue().offset);
+					file.writeInt(e.getValue().length);
+				}
+				writeHeader(indexPosition);
+			} finally {
+				file.close();
+				deflater.end();
+			}
+			if (target.exists() && !target.delete()) {
+				throw new IOException("Can not replace " + target);
+			}
+			if (!temp.renameTo(target)) {
+				throw new IOException("Can not rename " + temp + " to " + target);
+			}
+		}
+
+		/**
+		 * Gives up (e.g. after an error): removes the unfinished file.
+		 */
+		public void abort() {
+			try {
+				file.close();
+			} catch (IOException e) { /* nothing to do */ }
+			deflater.end();
+			temp.delete();
+		}
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdEngine.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdEngine.java
new file mode 100644
index 000000000..77d691632
--- /dev/null
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdEngine.java
@@ -0,0 +1,169 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.graphics.image.hd;
+
+import java.io.File;
+import java.io.IOException;
+import java.nio.file.Files;
+import java.nio.file.Path;
+import java.nio.file.StandardCopyOption;
+import java.util.concurrent.TimeUnit;
+import java.util.function.IntConsumer;
+import java.util.stream.Stream;
+
+/**
+ * The optional AI engine of the HD graphics: the command line program "realesrgan-ncnn-vulkan" (Real-ESRGAN, MIT licence). It is not part of the
+ * game. If it is installed (the build script of the macOS version downloads it, or the folder is given with the system property
+ * "settlers.hd.engine"), it makes the colours of the enlarged images, otherwise the built-in enlarger is used.
+ */
+final class HdEngine {
+	static final String EXECUTABLE = "realesrgan-ncnn-vulkan";
+	static final String MODEL = "realesr-animevideov3";
+	private static final String FAILED_MARKER = "engine-failed.txt";
+
+	private HdEngine() {
+	}
+
+	static File getSourceDir() {
+		String path = System.getProperty("settlers.hd.engine");
+		if (path == null || path.isEmpty()) {
+			return null;
+		}
+		File dir = new File(path);
+		return new File(dir, EXECUTABLE).isFile() && new File(dir, "models").isDirectory() ? dir : null;
+	}
+
+	/**
+	 * @return true if an engine is installed and did not fail before.
+	 */
+	static boolean isAvailable(File cacheDir) {
+		return getSourceDir() != null && !new File(cacheDir, FAILED_MARKER).exists();
+	}
+
+	static void markFailed(File cacheDir, String reason) {
+		try {
+			cacheDir.mkdirs();
+			Files.write(new File(cacheDir, FAILED_MARKER).toPath(),
+					("The AI engine did not work, so the built-in enlarger is used.\nDelete this file to try the engine again.\n" + reason + "\n")
+							.getBytes("UTF-8"));
+		} catch (IOException e) {
+			HdGraphics.log(String.valueOf(e));
+		}
+	}
+
+	/**
+	 * Copies the engine to the cache folder (so it can be started and signed there) and returns the program.
+	 */
+	static File install(File cacheDir) throws IOException {
+		File source = getSourceDir();
+		if (source == null) {
+			throw new IOException("There is no engine.");
+		}
+		File target = new File(cacheDir, "engine");
+		File exe = new File(target, EXECUTABLE);
+		File stamp = new File(target, ".source-size");
+		String sourceStamp = String.valueOf(new File(source, EXECUTABLE).length());
+		if (!exe.isFile() || !stamp.isFile() || !new String(Files.readAllBytes(stamp.toPath()), "UTF-8").equals(sourceStamp)) {
+			deleteRecursively(target);
+			copyRecursively(source.toPath(), target.toPath());
+			exe.setExecutable(true, false);
+			Files.write(stamp.toPath(), sourceStamp.getBytes("UTF-8"));
+			if (System.getProperty("os.name", "").toLowerCase().contains("mac")) {
+				runQuietly("xattr", "-cr", target.getAbsolutePath());
+				runQuietly("codesign", "--force", "--sign", "-", exe.getAbsolutePath());
+			}
+		}
+		return exe;
+	}
+
+	private static void runQuietly(String... command) {
+		try {
+			Process p = new ProcessBuilder(command).redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
+			p.waitFor(60, TimeUnit.SECONDS);
+		} catch (Exception e) {
+			// best effort
+		}
+	}
+
+	private static void copyRecursively(Path from, Path to) throws IOException {
+		try (Stream<Path> stream = Files.walk(from)) {
+			for (Path p : (Iterable<Path>) stream::iterator) {
+				Path dest = to.resolve(from.relativize(p).toString());
+				if (Files.isDirectory(p)) {
+					Files.createDirectories(dest);
+				} else {
+					Files.createDirectories(dest.getParent());
+					Files.copy(p, dest, StandardCopyOption.REPLACE_EXISTING);
+				}
+			}
+		}
+	}
+
+	static void deleteRecursively(File file) {
+		if (file == null || !file.exists()) {
+			return;
+		}
+		File[] children = file.listFiles();
+		if (children != null) {
+			for (File child : children) {
+				deleteRecursively(child);
+			}
+		}
+		file.delete();
+	}
+
+	/**
+	 * Enlarges all png images of a folder two times.
+	 *
+	 * @param progress
+	 *            Gets the number of images that are done.
+	 * @return true if the engine finished without an error.
+	 */
+	static boolean run(File exe, File inputDir, File outputDir, int expected, File log, IntConsumer progress) {
+		outputDir.mkdirs();
+		try {
+			Process process = new ProcessBuilder(exe.getAbsolutePath(),
+					"-i", inputDir.getAbsolutePath(),
+					"-o", outputDir.getAbsolutePath(),
+					"-n", MODEL,
+					"-s", "2",
+					"-f", "png",
+					"-m", new File(exe.getParentFile(), "models").getAbsolutePath())
+							.directory(exe.getParentFile())
+							.redirectErrorStream(true)
+							.redirectOutput(ProcessBuilder.Redirect.appendTo(log))
+							.start();
+
+			long deadline = System.currentTimeMillis() + TimeUnit.MINUTES.toMillis(45);
+			while (!process.waitFor(400, TimeUnit.MILLISECONDS)) {
+				String[] done = outputDir.list();
+				progress.accept(done == null ? 0 : done.length);
+				if (System.currentTimeMillis() > deadline) {
+					process.destroyForcibly();
+					return false;
+				}
+			}
+			String[] done = outputDir.list();
+			progress.accept(done == null ? 0 : done.length);
+			return process.exitValue() == 0 && done != null && done.length >= expected * 0.95;
+		} catch (IOException e) {
+			HdGraphics.log("the engine could not be started: " + e);
+			return false;
+		} catch (InterruptedException e) {
+			Thread.currentThread().interrupt();
+			return false;
+		}
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGenerator.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGenerator.java
new file mode 100644
index 000000000..3f76cbfcd
--- /dev/null
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGenerator.java
@@ -0,0 +1,262 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.graphics.image.hd;
+
+import java.awt.image.BufferedImage;
+import java.io.File;
+import java.io.IOException;
+import java.nio.IntBuffer;
+import java.util.ArrayList;
+import java.util.List;
+import java.util.TreeSet;
+
+import javax.imageio.ImageIO;
+
+import jsettlers.graphics.image.Image;
+import jsettlers.graphics.image.reader.AdvancedDatFileReader;
+import jsettlers.graphics.image.reader.ImageMetadata;
+import jsettlers.graphics.image.reader.IntArrayWriter;
+import jsettlers.graphics.image.reader.translator.DatBitmapTranslator;
+
+/**
+ * Creates the cache file with the enlarged images of one graphics file.
+ */
+final class HdGenerator {
+	private static final int CHUNK = 800;
+
+	/** Larger images are not enlarged (the enlarged image has to fit into a texture of the graphics card). */
+	private static final int MAX_SIZE = 900;
+
+	/** Thrown if the AI engine does not work. */
+	static final class EngineFailure extends Exception {
+		private static final long serialVersionUID = 1L;
+
+		EngineFailure(String message) {
+			super(message);
+		}
+	}
+
+	private final AdvancedDatFileReader reader;
+	private final File cacheFile;
+	private final File sourceFile;
+	private final HdGraphics.Progress progress;
+	private final java.util.Set<Long> spritesWithTorso = new java.util.HashSet<>();
+
+	HdGenerator(AdvancedDatFileReader reader, File cacheFile, HdGraphics.Progress progress) {
+		this.reader = reader;
+		this.sourceFile = reader.getFile();
+		this.cacheFile = cacheFile;
+		this.progress = progress;
+	}
+
+	/**
+	 * Counts the images that have to be enlarged.
+	 */
+	int countImages() {
+		TreeSet<Long> keys = new TreeSet<>();
+		reader.collectSettlerImagePositions(keys, spritesWithTorso);
+		int[] counts = new int[8];
+		for (long key : keys) {
+			counts[HdCacheFile.kindOf(key)]++;
+		}
+		HdGraphics.log(sourceFile.getName() + ": " + counts[HdCacheFile.KIND_SETTLER] + " pictures ("
+				+ spritesWithTorso.size() + " with team colour), " + counts[HdCacheFile.KIND_TORSO] + " team colour masks, "
+				+ counts[HdCacheFile.KIND_SHADOW] + " shadows, " + counts[HdCacheFile.KIND_LANDSCAPE] + " terrain textures, "
+				+ counts[HdCacheFile.KIND_GUI] + " interface images");
+		return keys.size();
+	}
+
+	private static final class RawImage {
+		final long key;
+		final int width;
+		final int height;
+		final int[] pixels;
+		/** The outline has to stay exactly as it is (sprites that are drawn with a torso). */
+		boolean exactOutline;
+
+		RawImage(long key, int width, int height, int[] pixels) {
+			this.key = key;
+			this.width = width;
+			this.height = height;
+			this.pixels = pixels;
+		}
+	}
+
+	private RawImage read(long key) throws IOException {
+		DatBitmapTranslator<? extends Image> translator;
+		switch (HdCacheFile.kindOf(key)) {
+		case HdCacheFile.KIND_TORSO:
+			translator = reader.getTorsoTranslator();
+			break;
+		case HdCacheFile.KIND_SHADOW:
+			translator = reader.getShadowTranslator();
+			break;
+		case HdCacheFile.KIND_LANDSCAPE:
+			translator = reader.getLandscapeTranslator();
+			break;
+		case HdCacheFile.KIND_GUI:
+			translator = reader.getGuiTranslator();
+			break;
+		default:
+			translator = reader.getSettlerTranslator();
+			break;
+		}
+		return read(translator, key);
+	}
+
+	private <T extends Image> RawImage read(DatBitmapTranslator<T> translator, long key) throws IOException {
+		long position = HdCacheFile.positionOf(key);
+		ImageMetadata metadata = new ImageMetadata();
+		long dataPos = reader.readImageHeader(translator, metadata, position);
+		if (metadata.width <= 0 || metadata.height <= 0 || metadata.width > MAX_SIZE || metadata.height > MAX_SIZE) {
+			return null;
+		}
+		IntArrayWriter array = new IntArrayWriter();
+		reader.readCompressedData(translator, metadata, array, dataPos);
+		IntBuffer buffer = array.getArray().duplicate();
+		buffer.rewind();
+		int[] pixels = new int[metadata.width * metadata.height];
+		buffer.get(pixels, 0, Math.min(pixels.length, buffer.remaining()));
+		RawImage image = new RawImage(key, metadata.width, metadata.height, pixels);
+		image.exactOutline = spritesWithTorso.contains(key);
+		return image;
+	}
+
+	/**
+	 * Creates the file.
+	 *
+	 * @param engineName
+	 *            The name written to the file.
+	 * @param engineExe
+	 *            The AI engine, or null for the built-in enlarger.
+	 * @param workDir
+	 *            A folder for the temporary files of the engine.
+	 */
+	void generate(String engineName, File engineExe, File workDir, File cacheDir) throws IOException, EngineFailure {
+		TreeSet<Long> keySet = new TreeSet<>();
+		reader.collectSettlerImagePositions(keySet, spritesWithTorso);
+		List<Long> keys = new ArrayList<>(keySet);
+
+		HdCacheFile.Writer writer = new HdCacheFile.Writer(cacheFile, sourceFile.length(), engineName);
+		boolean ok = false;
+		try {
+			for (int from = 0; from < keys.size(); from += CHUNK) {
+				List<Long> chunk = keys.subList(from, Math.min(keys.size(), from + CHUNK));
+				List<RawImage> colorImages = new ArrayList<>();
+
+				for (long key : chunk) {
+					RawImage image = read(key);
+					if (image == null) {
+						progress.imageDone();
+						continue;
+					}
+					int imageKind = HdCacheFile.kindOf(key);
+					boolean colors = imageKind == HdCacheFile.KIND_SETTLER || imageKind == HdCacheFile.KIND_GUI || imageKind == HdCacheFile.KIND_LANDSCAPE;
+					if (engineExe != null && colors) {
+						colorImages.add(image);
+					} else {
+						writer.add(key, image.width * 2, image.height * 2, upscaleBuiltIn(image));
+						progress.imageDone();
+					}
+				}
+
+				if (!colorImages.isEmpty()) {
+					enlargeWithEngine(colorImages, writer, engineExe, workDir, cacheDir);
+				}
+			}
+			ok = true;
+		} finally {
+			if (ok) {
+				writer.close();
+			} else {
+				writer.abort();
+			}
+		}
+	}
+
+	private static boolean isTile(RawImage image) {
+		return HdCacheFile.kindOf(image.key) == HdCacheFile.KIND_LANDSCAPE;
+	}
+
+	private static int[] upscaleBuiltIn(RawImage image) {
+		int kind = HdCacheFile.kindOf(image.key);
+		if (kind == HdCacheFile.KIND_LANDSCAPE) {
+			return HdUpscaler.upscaleTile(image.pixels, image.width, image.height);
+		}
+		if (kind == HdCacheFile.KIND_TORSO) {
+			return HdUpscaler.upscale(image.pixels, image.width, image.height, HdUpscaler.Kind.TORSO);
+		}
+		if (kind == HdCacheFile.KIND_SHADOW) {
+			return HdUpscaler.upscale(image.pixels, image.width, image.height, HdUpscaler.Kind.MASK);
+		}
+		return HdUpscaler.upscale(image.pixels, image.width, image.height,
+				image.exactOutline ? HdUpscaler.Kind.COLOR_EXACT_OUTLINE : HdUpscaler.Kind.COLOR);
+	}
+
+	private void enlargeWithEngine(List<RawImage> images, HdCacheFile.Writer writer, File exe, File workDir, File cacheDir)
+			throws IOException, EngineFailure {
+		File in = new File(workDir, "in");
+		File out = new File(workDir, "out");
+		HdEngine.deleteRecursively(workDir);
+		in.mkdirs();
+		out.mkdirs();
+
+		for (int i = 0; i < images.size(); i++) {
+			RawImage image = images.get(i);
+			BufferedImage input = isTile(image) ? HdUpscaler.paddedTile(image.pixels, image.width, image.height)
+					: HdUpscaler.dilatedRgb(image.pixels, image.width, image.height);
+			ImageIO.write(input, "png", new File(in, String.format("%05d.png", i)));
+		}
+
+		int[] counted = {0};
+		boolean engineOk = HdEngine.run(exe, in, out, images.size(), new File(cacheDir, "engine.log"), done -> {
+			while (counted[0] < done) {
+				counted[0]++;
+				progress.imageDone();
+			}
+		});
+		if (!engineOk) {
+			HdEngine.deleteRecursively(workDir);
+			throw new EngineFailure("The engine did not finish (see engine.log).");
+		}
+
+		for (int i = 0; i < images.size(); i++) {
+			RawImage image = images.get(i);
+			int[] result = null;
+			File file = new File(out, String.format("%05d.png", i));
+			if (file.isFile()) {
+				BufferedImage enlarged = ImageIO.read(file);
+				boolean tile = isTile(image);
+				int expectedWidth = tile ? 2 * (image.width + 2 * HdUpscaler.TILE_PAD) : image.width * 2;
+				int expectedHeight = tile ? 2 * (image.height + 2 * HdUpscaler.TILE_PAD) : image.height * 2;
+				if (enlarged != null && enlarged.getWidth() == expectedWidth && enlarged.getHeight() == expectedHeight) {
+					int[] rgb = enlarged.getRGB(0, 0, enlarged.getWidth(), enlarged.getHeight(), null, 0, enlarged.getWidth());
+					result = tile ? HdUpscaler.composeTile(image.pixels, image.width, image.height, rgb)
+							: HdUpscaler.compose(image.pixels, image.width, image.height, rgb, image.exactOutline);
+				}
+			}
+			if (result == null) {
+				result = upscaleBuiltIn(image);
+			}
+			writer.add(image.key, image.width * 2, image.height * 2, result);
+		}
+		// the images that the engine did not report are still counted as done
+		while (counted[0] < images.size()) {
+			counted[0]++;
+			progress.imageDone();
+		}
+		HdEngine.deleteRecursively(workDir);
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGraphics.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGraphics.java
new file mode 100644
index 000000000..815de8bd8
--- /dev/null
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGraphics.java
@@ -0,0 +1,263 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.graphics.image.hd;
+
+import java.io.File;
+import java.io.IOException;
+import java.util.ArrayList;
+import java.util.List;
+import java.util.Locale;
+
+import jsettlers.graphics.image.reader.AdvancedDatFileReader;
+import jsettlers.graphics.image.reader.DatFileType;
+import jsettlers.graphics.image.reader.shadowmap.ShadowMapping;
+import jsettlers.graphics.image.reader.versions.DefaultGfxFolderMapping.DefaultDatFileMapping;
+
+/**
+ * The HD graphics: the images of the units, buildings and objects of the original game are enlarged two times on the computer of the user (with the
+ * built-in enlarger or, if it is installed, with an AI engine). The result is stored in a cache folder (on macOS in "Application Support") and is
+ * used instead of the original images. The enlarged images are only made for the user from his own copy of the game and are never distributed.
+ */
+public final class HdGraphics {
+	/** The images are enlarged by this factor. */
+	public static final int SCALE = 2;
+
+	private static final String BUILTIN_ENGINE = "builtin-lanczos3-x2-v2";
+	private static final String AI_ENGINE = "realesrgan-animevideov3-x2-v2";
+
+	private static volatile boolean enabled = false;
+
+	private HdGraphics() {
+	}
+
+	/** Reports the progress of {@link #prepare}. */
+	public interface Progress {
+		/** One image is finished. */
+		void imageDone();
+	}
+
+	/** Receives the state of {@link #prepare}. */
+	public interface Listener {
+		/**
+		 * @param text
+		 *            What is happening.
+		 * @param done
+		 *            Finished images.
+		 * @param total
+		 *            All images that have to be enlarged.
+		 */
+		void update(String text, int done, int total);
+	}
+
+	/**
+	 * Writes a line to the console and to the file "hd.log" in the cache folder.
+	 */
+	public static synchronized void log(String message) {
+		System.out.println("HD graphics: " + message);
+		try {
+			File dir = getCacheDir();
+			dir.mkdirs();
+			java.nio.file.Files.write(new File(dir, "hd.log").toPath(),
+					(new java.util.Date() + "  " + message + "\n").getBytes("UTF-8"),
+					java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.APPEND);
+		} catch (IOException | RuntimeException e) {
+			// the log is only a help
+		}
+	}
+
+	public static boolean isEnabled() {
+		return enabled;
+	}
+
+	public static void setEnabled(boolean enabled) {
+		HdGraphics.enabled = enabled;
+	}
+
+	/**
+	 * The folder with the enlarged images.
+	 */
+	public static File getCacheDir() {
+		String path = System.getProperty("settlers.hd.dir");
+		if (path != null && !path.isEmpty()) {
+			return new File(path);
+		}
+		String home = System.getProperty("user.home", ".");
+		if (System.getProperty("os.name", "").toLowerCase(Locale.ENGLISH).contains("mac")) {
+			return new File(home, "Library/Application Support/JSettlers/hd");
+		}
+		return new File(home, ".jsettlers/hd");
+	}
+
+	private static File cacheFileFor(File dat) {
+		return new File(getCacheDir(), dat.getName().toLowerCase(Locale.ENGLISH) + ".x" + SCALE + ".hd");
+	}
+
+	private static String desiredEngineName() {
+		return HdEngine.isAvailable(getCacheDir()) ? AI_ENGINE : BUILTIN_ENGINE;
+	}
+
+	/**
+	 * Opens the enlarged images for a graphics file.
+	 *
+	 * @return The images or null if there are none (they are then not used).
+	 */
+	public static HdCacheFile openCache(File dat) {
+		if (!enabled) {
+			return null;
+		}
+		// a cache of the other engine is fine here, it is replaced by prepare() when it is started
+		HdCacheFile cache = HdCacheFile.open(cacheFileFor(dat), dat.length(), null);
+		log(dat.getName() + ": " + (cache == null ? "no enlarged images, the original ones are used" : cache.getImageCount() + " enlarged images (" + cache.getEngine() + ")"));
+		return cache;
+	}
+
+	private static List<File> findGraphicsFiles(File gfxFolder) {
+		List<File> result = new ArrayList<>();
+		File[] files = gfxFolder.listFiles();
+		if (files == null) {
+			return result;
+		}
+		for (File file : files) {
+			String name = file.getName().toLowerCase(Locale.ENGLISH);
+			if (!file.isFile() || !name.startsWith("siedler3_")) {
+				continue;
+			}
+			for (DatFileType type : DatFileType.values()) {
+				if (name.endsWith(type.getFileSuffix())) {
+					result.add(file);
+					break;
+				}
+			}
+		}
+		result.sort((a, b) -> a.getName().compareToIgnoreCase(b.getName()));
+		return result;
+	}
+
+	private static AdvancedDatFileReader createReader(File file) {
+		String name = file.getName().toLowerCase(Locale.ENGLISH);
+		int index = -1;
+		try {
+			index = Integer.parseInt(name.substring("siedler3_".length(), "siedler3_".length() + 2));
+		} catch (RuntimeException e) {
+			// no number: no special shadow handling
+		}
+		return new AdvancedDatFileReader(file, DatFileType.getForPath(file), new DefaultDatFileMapping(), ShadowMapping.getMappingFor(index),
+				"F" + index);
+	}
+
+	/**
+	 * Creates the missing enlarged images. Takes some minutes the first time and nothing when everything exists.
+	 *
+	 * @param gfxFolder
+	 *            The folder with the original graphics.
+	 * @param listener
+	 *            Gets the progress, may be null.
+	 */
+	public static void prepare(File gfxFolder, Listener listener) {
+		File cacheDir = getCacheDir();
+		String wantedEngine = desiredEngineName();
+		log("preparing, engine: " + wantedEngine + ", folder: " + gfxFolder);
+
+		List<File> todo = new ArrayList<>();
+		List<AdvancedDatFileReader> readers = new ArrayList<>();
+		int total = 0;
+		for (File dat : findGraphicsFiles(gfxFolder)) {
+			if (HdCacheFile.open(cacheFileFor(dat), dat.length(), wantedEngine) != null) {
+				continue;
+			}
+			try {
+				AdvancedDatFileReader reader = createReader(dat);
+				int count = new HdGenerator(reader, cacheFileFor(dat), () -> { }).countImages();
+				if (count > 0) {
+					todo.add(dat);
+					readers.add(reader);
+					total += count;
+				} else {
+					// nothing to enlarge in this file: remember that, so it is not examined again at every start
+					try (HdCacheFile.Writer writer = new HdCacheFile.Writer(cacheFileFor(dat), dat.length(), wantedEngine)) {
+						// an empty file
+					} catch (IOException e) {
+						log(dat.getName() + ": " + e);
+					}
+				}
+			} catch (RuntimeException e) {
+				log(dat.getName() + " can not be read: " + e);
+			}
+		}
+		if (todo.isEmpty()) {
+			return;
+		}
+
+		final int totalImages = total;
+		final int[] done = {0};
+		final String[] text = {""};
+		final long[] lastReport = {0};
+		Progress progress = () -> {
+			done[0]++;
+			long now = System.currentTimeMillis();
+			if (listener != null && now - lastReport[0] > 150) {
+				lastReport[0] = now;
+				listener.update(text[0], Math.min(done[0], totalImages), totalImages);
+			}
+		};
+
+		File engineExe = null;
+		if (wantedEngine.equals(AI_ENGINE)) {
+			try {
+				engineExe = HdEngine.install(cacheDir);
+			} catch (IOException e) {
+				log("the AI engine can not be installed: " + e);
+				HdEngine.markFailed(cacheDir, e.toString());
+				wantedEngine = BUILTIN_ENGINE;
+			}
+		}
+
+		for (int i = 0; i < todo.size(); i++) {
+			File dat = todo.get(i);
+			text[0] = dat.getName();
+			if (listener != null) {
+				listener.update(text[0], Math.min(done[0], totalImages), totalImages);
+			}
+			int before = done[0];
+			try {
+				new HdGenerator(readers.get(i), cacheFileFor(dat), progress).generate(wantedEngine,
+						wantedEngine.equals(AI_ENGINE) ? engineExe : null, new File(cacheDir, "work"), cacheDir);
+			} catch (HdGenerator.EngineFailure e) {
+				log(e.getMessage() + " The built-in enlarger is used.");
+				HdEngine.markFailed(cacheDir, e.getMessage());
+				wantedEngine = BUILTIN_ENGINE;
+				engineExe = null;
+				done[0] = before;
+				try {
+					new HdGenerator(readers.get(i), cacheFileFor(dat), progress).generate(wantedEngine, null, new File(cacheDir, "work"), cacheDir);
+				} catch (IOException | HdGenerator.EngineFailure ex) {
+					log(dat.getName() + " failed: " + ex);
+				}
+			} catch (IOException e) {
+				log(dat.getName() + " failed: " + e);
+			}
+		}
+		if (listener != null) {
+			listener.update("", totalImages, totalImages);
+		}
+	}
+
+	/**
+	 * Gets the mapping that is used for the shadows (public for tools).
+	 */
+	static ShadowMapping shadowMappingFor(int fileIndex) {
+		return ShadowMapping.getMappingFor(fileIndex);
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdUpscaler.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdUpscaler.java
new file mode 100644
index 000000000..45dce546e
--- /dev/null
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdUpscaler.java
@@ -0,0 +1,413 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.graphics.image.hd;
+
+import java.awt.image.BufferedImage;
+
+/**
+ * The built-in enlarger of the HD graphics. It enlarges the images two times without any additional software.
+ * <p>
+ * Pictures: Lanczos resampling of the colors (the colors of the sprite are first spread into the transparent area, so the edge of a sprite does
+ * not get a dark or light halo), a smooth, anti-aliased edge by enlarging the transparency separately.<br>
+ * Masks (team colour, shadow): smooth cubic interpolation of every channel.
+ * <p>
+ * The pixels are in the format of {@link go.graphics.ImageData}: 0xRRGGBBAA, a pixel that is 0 is transparent.
+ */
+public final class HdUpscaler {
+	private HdUpscaler() {
+	}
+
+	public enum Kind {
+		/** A picture with colours (a unit, a building, ...). */
+		COLOR,
+		/** The shadow images. */
+		MASK,
+		/** A picture that is drawn together with a torso: the outline stays exactly as in the original (no soft edge), see SettlerImage. */
+		COLOR_EXACT_OUTLINE,
+		/** The torso (team colour) images: the covered area stays exactly as in the original, only the intensity is smoothed. */
+		TORSO
+	}
+
+	private interface Kernel {
+		float radius();
+
+		float weight(float d);
+	}
+
+	private static final Kernel LANCZOS3 = new Kernel() {
+		@Override
+		public float radius() {
+			return 3;
+		}
+
+		@Override
+		public float weight(float d) {
+			d = Math.abs(d);
+			if (d < 1e-6f) {
+				return 1;
+			}
+			if (d >= 3) {
+				return 0;
+			}
+			double pd = Math.PI * d;
+			return (float) (3 * Math.sin(pd) * Math.sin(pd / 3) / (pd * pd));
+		}
+	};
+
+	private static final Kernel CATMULL_ROM = new Kernel() {
+		@Override
+		public float radius() {
+			return 2;
+		}
+
+		@Override
+		public float weight(float d) {
+			d = Math.abs(d);
+			if (d < 1) {
+				return 1.5f * d * d * d - 2.5f * d * d + 1;
+			} else if (d < 2) {
+				return -0.5f * d * d * d + 2.5f * d * d - 4 * d + 2;
+			}
+			return 0;
+		}
+	};
+
+	/**
+	 * Enlarges one channel (values 0..255) two times, horizontally and vertically.
+	 */
+	private static float[] resample2x(float[] src, int w, int h, Kernel kernel) {
+		return resample2x(src, w, h, kernel, false);
+	}
+
+	/**
+	 * @param wrap
+	 *            true: the image is a repeating tile, the pixels beyond the border are the pixels of the other side.
+	 */
+	private static float[] resample2x(float[] src, int w, int h, Kernel kernel, boolean wrap) {
+		int radius = (int) kernel.radius();
+		int taps = radius * 2;
+
+		// two phases: the output pixel left (-0.25) and right (+0.25) of the centre of the source pixel
+		float[][] weights = new float[2][taps];
+		for (int phase = 0; phase < 2; phase++) {
+			float centre = phase == 0 ? -0.25f : 0.25f;
+			int first = (int) Math.floor(centre) - radius + 1;
+			float sum = 0;
+			for (int t = 0; t < taps; t++) {
+				weights[phase][t] = kernel.weight(first + t - centre);
+				sum += weights[phase][t];
+			}
+			for (int t = 0; t < taps; t++) {
+				weights[phase][t] /= sum;
+			}
+		}
+
+		int w2 = w * 2;
+		int h2 = h * 2;
+		float[] tmp = new float[w2 * h];
+		for (int y = 0; y < h; y++) {
+			for (int ox = 0; ox < w2; ox++) {
+				int phase = ox & 1;
+				int sx = ox >> 1;
+				int first = (phase == 0 ? -1 : 0) - radius + 1;
+				float v = 0;
+				for (int t = 0; t < taps; t++) {
+					int x = wrap ? Math.floorMod(sx + first + t, w) : Math.min(w - 1, Math.max(0, sx + first + t));
+					v += src[y * w + x] * weights[phase][t];
+				}
+				tmp[y * w2 + ox] = v;
+			}
+		}
+
+		float[] out = new float[w2 * h2];
+		for (int oy = 0; oy < h2; oy++) {
+			int phase = oy & 1;
+			int sy = oy >> 1;
+			int first = (phase == 0 ? -1 : 0) - radius + 1;
+			for (int x = 0; x < w2; x++) {
+				float v = 0;
+				for (int t = 0; t < taps; t++) {
+					int y = wrap ? Math.floorMod(sy + first + t, h) : Math.min(h - 1, Math.max(0, sy + first + t));
+					v += tmp[y * w2 + x] * weights[phase][t];
+				}
+				out[oy * w2 + x] = v;
+			}
+		}
+		return out;
+	}
+
+	private static float[] channel(int[] pixels, int shift) {
+		float[] c = new float[pixels.length];
+		for (int i = 0; i < c.length; i++) {
+			c[i] = (pixels[i] >>> shift) & 0xFF;
+		}
+		return c;
+	}
+
+	private static int clamp8(float v) {
+		return v <= 0 ? 0 : v >= 255 ? 255 : Math.round(v);
+	}
+
+	/**
+	 * Spreads the colours of the visible pixels into the transparent area around them (3 pixels). Only the colours of the transparent pixels are
+	 * changed (and they are not visible), the result has the same size.
+	 */
+	private static void dilate(float[] r, float[] g, float[] b, boolean[] valid, int w, int h) {
+		boolean[] known = valid.clone();
+		float avgR = 0, avgG = 0, avgB = 0;
+		int count = 0;
+		for (int i = 0; i < known.length; i++) {
+			if (known[i]) {
+				avgR += r[i];
+				avgG += g[i];
+				avgB += b[i];
+				count++;
+			}
+		}
+		if (count == 0) {
+			return;
+		}
+		avgR /= count;
+		avgG /= count;
+		avgB /= count;
+
+		for (int pass = 0; pass < 3; pass++) {
+			boolean[] next = known.clone();
+			for (int y = 0; y < h; y++) {
+				for (int x = 0; x < w; x++) {
+					int i = y * w + x;
+					if (known[i]) {
+						continue;
+					}
+					float sr = 0, sg = 0, sb = 0;
+					int n = 0;
+					for (int dy = -1; dy <= 1; dy++) {
+						for (int dx = -1; dx <= 1; dx++) {
+							int nx = x + dx;
+							int ny = y + dy;
+							if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
+								continue;
+							}
+							int j = ny * w + nx;
+							if (known[j]) {
+								sr += r[j];
+								sg += g[j];
+								sb += b[j];
+								n++;
+							}
+						}
+					}
+					if (n > 0) {
+						r[i] = sr / n;
+						g[i] = sg / n;
+						b[i] = sb / n;
+						next[i] = true;
+					}
+				}
+			}
+			known = next;
+		}
+		for (int i = 0; i < known.length; i++) {
+			if (!known[i]) {
+				r[i] = avgR;
+				g[i] = avgG;
+				b[i] = avgB;
+			}
+		}
+	}
+
+	/**
+	 * The colours of a picture with the transparent area filled with the colours of the border (opaque). This is what the AI engine gets.
+	 */
+	public static BufferedImage dilatedRgb(int[] pixels, int w, int h) {
+		float[] r = channel(pixels, 24);
+		float[] g = channel(pixels, 16);
+		float[] b = channel(pixels, 8);
+		boolean[] valid = new boolean[pixels.length];
+		for (int i = 0; i < valid.length; i++) {
+			valid[i] = (pixels[i] & 0xFF) != 0;
+		}
+		dilate(r, g, b, valid, w, h);
+
+		BufferedImage image = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
+		for (int y = 0; y < h; y++) {
+			for (int x = 0; x < w; x++) {
+				int i = y * w + x;
+				image.setRGB(x, y, (clamp8(r[i]) << 16) | (clamp8(g[i]) << 8) | clamp8(b[i]));
+			}
+		}
+		return image;
+	}
+
+	/** The enlarged transparency, a little steeper, so the edge stays crisp but is no staircase. */
+	private static float[] enlargedAlpha(int[] pixels, int w, int h) {
+		float[] a = resample2x(channel(pixels, 0), w, h, LANCZOS3);
+		for (int i = 0; i < a.length; i++) {
+			float t = a[i] / 255f;
+			t = (t - 0.5f) * 1.6f + 0.5f;
+			a[i] = Math.max(0, Math.min(1, t)) * 255f;
+		}
+		return a;
+	}
+
+	private static int pack(int r, int g, int b, int a) {
+		if (a < 6) {
+			return 0;
+		}
+		return (r << 24) | (g << 16) | (b << 8) | a;
+	}
+
+	/**
+	 * Enlarges the image two times.
+	 *
+	 * @param pixels
+	 *            The pixels, w*h.
+	 * @return The enlarged pixels, 2w*2h.
+	 */
+	public static int[] upscale(int[] pixels, int w, int h, Kind kind) {
+		int[] result = new int[w * h * 4];
+		if (kind == Kind.MASK) {
+			float[][] c = new float[4][];
+			for (int i = 0; i < 4; i++) {
+				c[i] = resample2x(channel(pixels, 24 - 8 * i), w, h, CATMULL_ROM);
+			}
+			for (int i = 0; i < result.length; i++) {
+				int v = (clamp8(c[0][i]) << 24) | (clamp8(c[1][i]) << 16) | (clamp8(c[2][i]) << 8) | clamp8(c[3][i]);
+				result[i] = v;
+			}
+			return result;
+		}
+
+		if (kind == Kind.TORSO) {
+			// covered = any pixel that is not 0 (that is what the game checks)
+			float[] r = channel(pixels, 24);
+			float[] g = channel(pixels, 16);
+			float[] b = channel(pixels, 8);
+			boolean[] valid = new boolean[pixels.length];
+			for (int i = 0; i < valid.length; i++) {
+				valid[i] = pixels[i] != 0;
+			}
+			dilate(r, g, b, valid, w, h);
+			float[] b2 = resample2x(b, w, h, CATMULL_ROM);
+			for (int y = 0; y < h * 2; y++) {
+				for (int x = 0; x < w * 2; x++) {
+					if (valid[(y / 2) * w + x / 2]) {
+						result[y * w * 2 + x] = (clamp8(b2[y * w * 2 + x]) << 8) | 0xFF;
+					}
+				}
+			}
+			return result;
+		}
+
+		float[] r = channel(pixels, 24);
+		float[] g = channel(pixels, 16);
+		float[] b = channel(pixels, 8);
+		boolean[] valid = new boolean[pixels.length];
+		for (int i = 0; i < valid.length; i++) {
+			valid[i] = (pixels[i] & 0xFF) != 0;
+		}
+		dilate(r, g, b, valid, w, h);
+
+		float[] r2 = resample2x(r, w, h, LANCZOS3);
+		float[] g2 = resample2x(g, w, h, LANCZOS3);
+		float[] b2 = resample2x(b, w, h, LANCZOS3);
+		float[] a2 = kind == Kind.COLOR_EXACT_OUTLINE ? exactAlpha(pixels, w, h) : enlargedAlpha(pixels, w, h);
+		for (int i = 0; i < result.length; i++) {
+			result[i] = kind == Kind.COLOR_EXACT_OUTLINE ? packExact(clamp8(r2[i]), clamp8(g2[i]), clamp8(b2[i]), clamp8(a2[i]))
+					: pack(clamp8(r2[i]), clamp8(g2[i]), clamp8(b2[i]), clamp8(a2[i]));
+		}
+		return result;
+	}
+
+	/** The transparency copied pixel by pixel (every pixel becomes 2x2 pixels), so the outline is exactly the original one. */
+	private static float[] exactAlpha(int[] pixels, int w, int h) {
+		float[] a = new float[w * h * 4];
+		for (int y = 0; y < h * 2; y++) {
+			for (int x = 0; x < w * 2; x++) {
+				a[y * w * 2 + x] = pixels[(y / 2) * w + x / 2] & 0xFF;
+			}
+		}
+		return a;
+	}
+
+	private static int packExact(int r, int g, int b, int a) {
+		return a == 0 ? 0 : (r << 24) | (g << 16) | (b << 8) | a;
+	}
+
+	/**
+	 * Builds the enlarged image from the colours made by the AI engine (2w*2h, 0xRRGGBB, opaque) and the enlarged transparency of the original.
+	 */
+	public static int[] compose(int[] original, int w, int h, int[] enlargedRgb, boolean exactOutline) {
+		float[] a2 = exactOutline ? exactAlpha(original, w, h) : enlargedAlpha(original, w, h);
+		int[] result = new int[w * h * 4];
+		for (int i = 0; i < result.length; i++) {
+			int rgb = enlargedRgb[i];
+			int r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
+			result[i] = exactOutline ? packExact(r, g, b, clamp8(a2[i])) : pack(r, g, b, clamp8(a2[i]));
+		}
+		return result;
+	}
+
+	/**
+	 * Enlarges a terrain texture (a repeating tile, without transparency) two times. The edges fit to the opposite edges, so the tiles stay seamless.
+	 */
+	public static int[] upscaleTile(int[] pixels, int w, int h) {
+		float[][] c = new float[4][];
+		for (int i = 0; i < 4; i++) {
+			c[i] = resample2x(channel(pixels, 24 - 8 * i), w, h, LANCZOS3, true);
+		}
+		int[] result = new int[w * h * 4];
+		for (int i = 0; i < result.length; i++) {
+			result[i] = (clamp8(c[0][i]) << 24) | (clamp8(c[1][i]) << 16) | (clamp8(c[2][i]) << 8) | clamp8(c[3][i]);
+		}
+		return result;
+	}
+
+	/** How many pixels of the neighbouring repetition the AI engine gets around a terrain tile. */
+	public static final int TILE_PAD = 16;
+
+	/**
+	 * A terrain tile for the AI engine: the tile with a border of the neighbouring repetitions (so the result has no seams).
+	 */
+	public static BufferedImage paddedTile(int[] pixels, int w, int h) {
+		BufferedImage image = new BufferedImage(w + 2 * TILE_PAD, h + 2 * TILE_PAD, BufferedImage.TYPE_INT_RGB);
+		for (int y = 0; y < h + 2 * TILE_PAD; y++) {
+			for (int x = 0; x < w + 2 * TILE_PAD; x++) {
+				int p = pixels[Math.floorMod(y - TILE_PAD, h) * w + Math.floorMod(x - TILE_PAD, w)];
+				image.setRGB(x, y, p >>> 8);
+			}
+		}
+		return image;
+	}
+
+	/**
+	 * Cuts the enlarged tile out of the enlarged padded tile.
+	 *
+	 * @param enlargedRgb
+	 *            The enlarged padded tile (2*(w+2*pad) wide).
+	 */
+	public static int[] composeTile(int[] original, int w, int h, int[] enlargedRgb) {
+		int[] plain = upscaleTile(original, w, h);
+		int paddedWidth = 2 * (w + 2 * TILE_PAD);
+		int[] result = new int[w * h * 4];
+		for (int y = 0; y < h * 2; y++) {
+			for (int x = 0; x < w * 2; x++) {
+				int rgb = enlargedRgb[(y + 2 * TILE_PAD) * paddedWidth + x + 2 * TILE_PAD];
+				result[y * w * 2 + x] = (rgb << 8) | (plain[y * w * 2 + x] & 0xFF);
+			}
+		}
+		return result;
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/AdvancedDatFileReader.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/AdvancedDatFileReader.java
index 1161efd4d..57ab6efe3 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/AdvancedDatFileReader.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/AdvancedDatFileReader.java
@@ -29,6 +29,7 @@ import jsettlers.graphics.image.SettlerImage;
 import jsettlers.graphics.image.reader.bytereader.ByteReader;
 import jsettlers.graphics.image.reader.shadowmap.IdentityShadowMapping;
 import jsettlers.graphics.image.reader.shadowmap.ShadowMapping;
+import jsettlers.graphics.image.hd.HdCacheFile;
 import jsettlers.graphics.image.reader.translator.DatBitmapTranslator;
 import jsettlers.graphics.image.reader.translator.GuiTranslator;
 import jsettlers.graphics.image.reader.translator.LandscapeTranslator;
@@ -242,6 +243,11 @@ public class AdvancedDatFileReader implements DatFileReader {
 	private final DatFileType type;
 	private final String file_name;
 
+	/**
+	 * The enlarged ("HD") versions of the settler images, or null if the HD graphics are not used.
+	 */
+	private HdCacheFile hdCache = null;
+
 	public AdvancedDatFileReader(File file, DatFileType type, String file_name) {
 		this(file, type, new DefaultDatFileMapping(), new IdentityShadowMapping(), file_name);
 	}
@@ -538,14 +544,14 @@ public class AdvancedDatFileReader implements DatFileReader {
 
 		SettlerImage[] images = new SettlerImage[framePositions.length];
 		for (int i = 0; i < framePositions.length; i++) {
-			images[i] = DatBitmapReader.getImage(settlerTranslator, this, framePositions[i], name + "-S" + goldIndex + ":" + i);
+			images[i] = DatBitmapReader.getImage(settlerTranslator, this, framePositions[i], name + "-S" + goldIndex + ":" + i, hdCache, HdCacheFile.KIND_SETTLER);
 		}
 
 		int torsoPosition = torsoStarts[realSettlerIndex];
 		if (torsoPosition >= 0) {
 			long[] torsoPositions = readSequenceHeader(torsoPosition);
 			for (int i = 0; i < torsoPositions.length && i < framePositions.length; i++) {
-				SingleImage torso = DatBitmapReader.getImage(torsoTranslator, this, torsoPositions[i], name + "-T" + goldIndex + ":" + i);
+				SingleImage torso = DatBitmapReader.getImage(torsoTranslator, this, torsoPositions[i], name + "-T" + goldIndex + ":" + i, hdCache, HdCacheFile.KIND_TORSO);
 				images[i].setTorso(torso);
 			}
 		}
@@ -555,7 +561,7 @@ public class AdvancedDatFileReader implements DatFileReader {
 			long[] shadowPositions = readSequenceHeader(shadowPosition);
 			for (int i = 0; i < shadowPositions.length
 				&& i < framePositions.length; i++) {
-				SingleImage shadow = DatBitmapReader.getImage(shadowTranslator, this, shadowPositions[i], name + "-SH" + goldIndex + ":" + i);
+				SingleImage shadow = DatBitmapReader.getImage(shadowTranslator, this, shadowPositions[i], name + "-SH" + goldIndex + ":" + i, hdCache, HdCacheFile.KIND_SHADOW);
 				images[i].setShadow(shadow);
 			}
 		}
@@ -639,7 +645,7 @@ public class AdvancedDatFileReader implements DatFileReader {
 		initializeIfNeeded();
 
 		try {
-			SingleImage image = DatBitmapReader.getImage(landscapeTranslator, this, landscapeStarts[index], name);
+			SingleImage image = DatBitmapReader.getImage(landscapeTranslator, this, landscapeStarts[index], name, hdCache, HdCacheFile.KIND_LANDSCAPE);
 			landscapeImages[index] = image;
 		} catch (IOException e) {
 			landscapeImages[index] = NullImage.getForLandscape();
@@ -692,13 +698,103 @@ public class AdvancedDatFileReader implements DatFileReader {
 		initializeIfNeeded();
 		try {
 			int theseGraphicsFilesIndex = mapping.mapGuiImage(goldIndex);
-			SingleImage image = DatBitmapReader.getImage(guiTranslator, this, guiStarts[theseGraphicsFilesIndex], name);
+			SingleImage image = DatBitmapReader.getImage(guiTranslator, this, guiStarts[theseGraphicsFilesIndex], name, hdCache, HdCacheFile.KIND_GUI);
 			guiImages[goldIndex] = image;
 		} catch (IOException | ArrayIndexOutOfBoundsException e) {
 			guiImages[goldIndex] = NullImage.getForGui();
 		}
 	}
 
+	/**
+	 * Sets the enlarged images that are used instead of the original settler images. Has to be called before the images are loaded.
+	 */
+	public void setHdCache(HdCacheFile hdCache) {
+		this.hdCache = hdCache;
+	}
+
+	public File getFile() {
+		return file;
+	}
+
+	@Override
+	public go.graphics.ImageData getHdLandscape(int index) {
+		initializeIfNeeded();
+		if (hdCache == null || index < 0 || index >= landscapeStarts.length) {
+			return null;
+		}
+		return hdCache.get(HdCacheFile.key(landscapeStarts[index], HdCacheFile.KIND_LANDSCAPE));
+	}
+
+	public DatBitmapTranslator<SingleImage> getGuiTranslator() {
+		return guiTranslator;
+	}
+
+	public DatFileType getType() {
+		return type;
+	}
+
+	/**
+	 * Collects the positions of all images that are enlarged by the HD graphics: settler sequences (including torsos and shadows), terrain and gui images.
+	 *
+	 * @param positions
+	 *            Receives the keys ({@link HdCacheFile#key(long, int)}).
+	 */
+	public synchronized void collectSettlerImagePositions(java.util.Set<Long> positions) {
+		collectSettlerImagePositions(positions, new java.util.HashSet<>());
+	}
+
+	/**
+	 * @param spritesWithTorso
+	 *            Receives the keys of the settler images that are drawn together with a torso (team colour). Their outline must stay exactly as
+	 *            it is, otherwise holes appear between the sprite and its torso.
+	 */
+	public synchronized void collectSettlerImagePositions(java.util.Set<Long> positions, java.util.Set<Long> spritesWithTorso) {
+		initializeIfNeeded();
+		for (int i = 0; i < settlerStarts.length; i++) {
+			if (settlerStarts[i] < 0 || torsoStarts[i] < 0) {
+				continue;
+			}
+			try {
+				long[] sprites = readSequenceHeader(settlerStarts[i]);
+				int torsos = readSequenceHeader(torsoStarts[i]).length;
+				for (int j = 0; j < sprites.length && j < torsos; j++) {
+					spritesWithTorso.add(HdCacheFile.key(sprites[j], HdCacheFile.KIND_SETTLER));
+				}
+			} catch (Exception e) {
+				// not a valid sequence
+			}
+		}
+		collectPositions(settlerStarts, HdCacheFile.KIND_SETTLER, positions);
+		collectPositions(torsoStarts, HdCacheFile.KIND_TORSO, positions);
+		collectPositions(shadowStarts, HdCacheFile.KIND_SHADOW, positions);
+		// landscape and gui "starts" are the positions of the images themselves
+		for (int start : landscapeStarts) {
+			if (start > 0) {
+				positions.add(HdCacheFile.key(start, HdCacheFile.KIND_LANDSCAPE));
+			}
+		}
+		for (int start : guiStarts) {
+			if (start > 0) {
+				positions.add(HdCacheFile.key(start, HdCacheFile.KIND_GUI));
+			}
+		}
+	}
+
+	private void collectPositions(int[] starts, int kind, java.util.Set<Long> positions) {
+		for (int start : starts) {
+			if (start < 0) {
+				continue;
+			}
+			try {
+				for (long position : readSequenceHeader(start)) {
+					positions.add(HdCacheFile.key(position, kind));
+				}
+			} catch (Exception e) {
+				// not a valid sequence, there are no images to enlarge
+			}
+		}
+	}
+
 	public long[] getSettlerPointers(int seqIndex) throws IOException {
 		initializeIfNeeded();
 		return readSequenceHeader(settlerStarts[seqIndex]);
@@ -722,6 +818,10 @@ public class AdvancedDatFileReader implements DatFileReader {
 		return torsoTranslator;
 	}
 
+	public DatBitmapTranslator<SingleImage> getShadowTranslator() {
+		return shadowTranslator;
+	}
+
 	@Override
 	public DatBitmapTranslator<SingleImage> getLandscapeTranslator() {
 		return landscapeTranslator;
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatBitmapReader.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatBitmapReader.java
index c69c69cd5..df566c87b 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatBitmapReader.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatBitmapReader.java
@@ -17,6 +17,8 @@ package jsettlers.graphics.image.reader;
 import java.io.IOException;
 
 import jsettlers.graphics.image.Image;
+import jsettlers.graphics.image.hd.HdCacheFile;
+import jsettlers.graphics.image.hd.HdGraphics;
 import jsettlers.graphics.image.reader.bytereader.ByteReader;
 import jsettlers.graphics.image.reader.translator.HeaderType;
 import jsettlers.graphics.image.reader.translator.DatBitmapTranslator;
@@ -238,9 +240,29 @@ public final class DatBitmapReader<T extends Image> {
 	public static <T extends Image> T getImage(
 			DatBitmapTranslator<T> translator, AdvancedDatFileReader reader, long position, String name)
 			throws IOException {
+		return getImage(translator, reader, position, name, null, 0);
+	}
+
+	/**
+	 * Like {@link #getImage(DatBitmapTranslator, AdvancedDatFileReader, long, String)}, but uses the enlarged image of the HD graphics if there is one.
+	 *
+	 * @param hdCache
+	 *            The enlarged images, may be null.
+	 * @param hdKind
+	 *            The kind of the image, see {@link HdCacheFile#KIND_SETTLER}.
+	 */
+	public static <T extends Image> T getImage(
+			DatBitmapTranslator<T> translator, AdvancedDatFileReader reader, long position, String name, HdCacheFile hdCache, int hdKind)
+			throws IOException {
 		ImageMetadata metadata = new ImageMetadata();
 		long dataPos = reader.readImageHeader(translator, metadata, position);
 		return translator.createImage(metadata, () -> {
+			if (hdCache != null && metadata.width > 0 && metadata.height > 0) {
+				ImageData hd = hdCache.get(HdCacheFile.key(position, hdKind));
+				if (hd != null && hd.getWidth() == metadata.width * HdGraphics.SCALE && hd.getHeight() == metadata.height * HdGraphics.SCALE) {
+					return hd;
+				}
+			}
 			IntArrayWriter array = new IntArrayWriter();
 			try {
 				reader.readCompressedData(translator, metadata, array, dataPos);
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatFileReader.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatFileReader.java
index 4d6adbbf6..dd9e3f14d 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatFileReader.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/image/reader/DatFileReader.java
@@ -27,6 +27,15 @@ public interface DatFileReader extends DatFileSet {
 
 	long getOffsetForLandscape(int index);
 
+	/**
+	 * Gets the enlarged version of a landscape (terrain) image if the HD graphics are used.
+	 *
+	 * @return The image (twice the size of the original) or null.
+	 */
+	default go.graphics.ImageData getHdLandscape(int index) {
+		return null;
+	}
+
 	<T extends Image> long readImageHeader(DatBitmapTranslator<T> translator,
 										   ImageMetadata metadata,
 										   long offset) throws IOException;
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/Background.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/Background.java
index 499cb3626..463762dac 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/Background.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/Background.java
@@ -41,6 +41,7 @@ import jsettlers.common.position.FloatRectangle;
 import jsettlers.graphics.image.Image;
 import jsettlers.graphics.image.NullImage;
 import jsettlers.graphics.image.SingleImage;
+import jsettlers.graphics.image.hd.HdGraphics;
 import jsettlers.graphics.image.reader.translator.DatBitmapTranslator;
 import jsettlers.graphics.map.MapDrawContext;
 import jsettlers.graphics.image.reader.DatFileReader;
@@ -70,6 +71,9 @@ public class Background implements IGraphicsBackgroundListener {
 	 */
 	private static final int TEXTURE_GRID = 32;
 
+	/** How far (in pixels of the original texture) the points are kept inside of a texture when the HD terrain is used. */
+	private static final float HD_TEXTURE_INSET = 0.5f;
+
 	private static final int BYTES_PER_FIELD = 4*6*3*2; // 4 bytes per float * 6 components(x,y,z,t,v,color) * 3 points per triangle * 2 triangles per field
 
 	/**
@@ -864,15 +868,20 @@ public class Background implements IGraphicsBackgroundListener {
 	private final int mapWidth, mapHeight;
 
 	private static ImageData getTextureData(boolean original) {
-		int[] data = new int[TEXTURE_SIZE * TEXTURE_SIZE];
-		try {
-			addTextures(data);
-		} catch (IOException e) {
-			e.printStackTrace();
-		}
+		// the HD graphics: the same texture, but with the enlarged images (twice the size, the coordinates are relative, so nothing else changes)
+		ImageData orig = createHdTextureData();
+
+		if (orig == null) {
+			int[] data = new int[TEXTURE_SIZE * TEXTURE_SIZE];
+			try {
+				addTextures(data);
+			} catch (IOException e) {
+				e.printStackTrace();
+			}
 
-		ImageData orig = new ImageData(TEXTURE_SIZE, TEXTURE_SIZE);
-		orig.getWriteData32().put(data).rewind();
+			orig = new ImageData(TEXTURE_SIZE, TEXTURE_SIZE);
+			orig.getWriteData32().put(data).rewind();
+		}
 
 		if(original) {
 			return orig;
@@ -928,6 +937,10 @@ public class Background implements IGraphicsBackgroundListener {
 			long startTime = System.currentTimeMillis();
 			ImageData data = getTextureData(original);
 			texture = context.generateTexture(data, "background-" + (original?"original":"custom"));
+			if (data.getWidth() > TEXTURE_SIZE) {
+				// the HD terrain is smoothed when it is zoomed (the coordinates are kept inside the cells, see addTriangleToGeometry)
+				texture.setType(go.graphics.ETextureType.LINEAR_FILTER);
+			}
 			textures.put(original, texture);
 
 			System.out.println("Background texture generated in " + (System.currentTimeMillis() - startTime) + "ms");
@@ -940,7 +953,70 @@ public class Background implements IGraphicsBackgroundListener {
 		return getTextureData(context, DrawConstants.FORCE_ORIGINAL);
 	}
 
+	/**
+	 * Creates the texture from the enlarged landscape images.
+	 *
+	 * @return The texture or null if the HD graphics are not used or an enlarged image is missing.
+	 */
+	private static ImageData createHdTextureData() {
+		if (!HdGraphics.isEnabled()) {
+			return null;
+		}
+		DatFileReader reader = ImageProvider.getInstance().getFileReader(LAND_FILE);
+		if (reader == null) {
+			HdGraphics.log("the terrain graphics file was not found, the original terrain is used.");
+			return null;
+		}
+
+		final int scale = HdGraphics.SCALE;
+		final int size = TEXTURE_SIZE * scale;
+		int[] data = new int[size * size];
+		ImageWriter imageWriter = new ImageWriter();
+		imageWriter.data = data;
+		imageWriter.stride = size;
+
+		for (int index = 0; index < TEXTURE_POSITIONS.length; index++) {
+			ImageData hd = reader.getHdLandscape(index);
+			if (hd == null) {
+				HdGraphics.log("the enlarged terrain texture " + index + " is missing, the original terrain is used.");
+				return null;
+			}
+			int[] position = TEXTURE_POSITIONS[index];
+			int x = position[0] * TEXTURE_GRID * scale;
+			int y = position[1] * TEXTURE_GRID * scale;
+			int start = y * size + x;
+			int cellSize = position[2] * TEXTURE_GRID * scale;
+			int end = (y + cellSize) * size + x;
+			imageWriter.arrayOffset = start;
+			imageWriter.cellSize = cellSize;
+			imageWriter.maxOffset = end;
+
+			// the same as for the original images
+			IntBuffer pixels = hd.getReadData32();
+			int[] line = new int[hd.getWidth()];
+			for (int row = 0; row < hd.getHeight(); row++) {
+				pixels.position(row * hd.getWidth());
+				pixels.get(line);
+				imageWriter.writeLine(line, line.length);
+			}
+			pixels.rewind();
+
+			int arrayOffset = imageWriter.arrayOffset;
+			int l = arrayOffset - start;
+			while (arrayOffset < end) {
+				System.arraycopy(data, arrayOffset - l, data, arrayOffset, cellSize);
+				arrayOffset += size;
+			}
+		}
+
+		ImageData result = new ImageData(size, size);
+		result.getWriteData32().put(data).rewind();
+		HdGraphics.log("HD terrain texture " + size + "x" + size + " is used.");
+		return result;
+	}
+
 	private static class ImageWriter implements ImageArrayProvider {
+		int stride = TEXTURE_SIZE;
 		int arrayOffset;
 		int cellSize;
 		int maxOffset;
@@ -957,7 +1033,7 @@ public class Background implements IGraphicsBackgroundListener {
 				for (int i = 0; i < cellSize; i++) {
 					this.data[arrayOffset + i] = data[i % length];
 				}
-				arrayOffset += TEXTURE_SIZE;
+				arrayOffset += stride;
 			}
 		}
 	}
@@ -1304,22 +1380,39 @@ public class Background implements IGraphicsBackgroundListener {
 		addDx += positions[0] * TEXTURE_GRID;
 		addDy += positions[1] * TEXTURE_GRID;
 
+		// With the smoothed HD terrain the points on the border of a texture would also pick up colours of the neighbouring texture in the
+		// atlas (a thin wrong line between two terrain types). So the points are kept half a pixel inside of the texture.
+		float minU = positions[0] * TEXTURE_GRID;
+		float minV = positions[1] * TEXTURE_GRID;
+		float maxU = Float.POSITIVE_INFINITY;
+		float maxV = Float.POSITIVE_INFINITY;
+		if (HdGraphics.isEnabled()) {
+			maxU = minU + positions[2] * TEXTURE_GRID - HD_TEXTURE_INSET;
+			maxV = minV + positions[2] * TEXTURE_GRID - HD_TEXTURE_INSET;
+			minU += HD_TEXTURE_INSET;
+			minV += HD_TEXTURE_INSET;
+		} else {
+			// the original game: nothing is changed
+			minU = Float.NEGATIVE_INFINITY;
+			minV = Float.NEGATIVE_INFINITY;
+		}
+
 		{
 			// left
-			float u = (texturePos[0] + addDx) / TEXTURE_SIZE;
-			float v = (texturePos[1] + addDy) / TEXTURE_SIZE;
+			float u = Math.min(maxU, Math.max(minU, texturePos[0] + addDx)) / TEXTURE_SIZE;
+			float v = Math.min(maxV, Math.max(minV, texturePos[1] + addDy)) / TEXTURE_SIZE;
 			addPointToGeometry(context, buffer, up?x2:x1, up?y2:y1, u, v);
 		}
 		{
 			// bottom
-			float u = (texturePos[2] + addDx) / TEXTURE_SIZE;
-			float v = (texturePos[3] + addDy) / TEXTURE_SIZE;
+			float u = Math.min(maxU, Math.max(minU, texturePos[2] + addDx)) / TEXTURE_SIZE;
+			float v = Math.min(maxV, Math.max(minV, texturePos[3] + addDy)) / TEXTURE_SIZE;
 			addPointToGeometry(context, buffer, up?x1:x2, up?y1:y2, u, v);
 		}
 		{
 			// right
-			float u = (texturePos[4] + addDx) / TEXTURE_SIZE;
-			float v = (texturePos[5] + addDy) / TEXTURE_SIZE;
+			float u = Math.min(maxU, Math.max(minU, texturePos[4] + addDx)) / TEXTURE_SIZE;
+			float v = Math.min(maxV, Math.max(minV, texturePos[5] + addDy)) / TEXTURE_SIZE;
 			addPointToGeometry(context, buffer, x3, y3, u, v);
 		}
 
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/ImageProvider.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/ImageProvider.java
index 2cecfc854..cbbbda473 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/ImageProvider.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/ImageProvider.java
@@ -25,6 +25,7 @@ import jsettlers.graphics.image.Image;
 import jsettlers.graphics.image.ImageIndexFile;
 import jsettlers.graphics.image.SingleImage;
 import jsettlers.graphics.image.NullImage;
+import jsettlers.graphics.image.hd.HdGraphics;
 import jsettlers.graphics.image.reader.AdvancedDatFileReader;
 import jsettlers.graphics.image.reader.DatFileReader;
 import jsettlers.graphics.image.reader.DatFileSet;
@@ -319,7 +320,11 @@ public final class ImageProvider {
 			ShadowMapping shadowMapping = ShadowMapping.getMappingFor(fileIndex);
 
 			if (file != null) {
-				reader = new AdvancedDatFileReader(file, type, gfxFolderMapping.getDatFileMapping(fileIndex), shadowMapping, "F" + fileIndex);
+				AdvancedDatFileReader datReader = new AdvancedDatFileReader(file, type, gfxFolderMapping.getDatFileMapping(fileIndex), shadowMapping, "F" + fileIndex);
+				if (HdGraphics.isEnabled()) {
+					datReader.setHdCache(HdGraphics.openCache(file));
+				}
+				reader = datReader;
 				break;
 			}
 		}
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index 2e57b608e..6788bb81f 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -618,3 +618,11 @@ error-rendering = Došlo k chybě :/\nNahlašte prosím tuto chybu na GitHubu\nP
 
 flatpak-title=Vyberte složku s originální hrou
 flatpak-description=JSettlers ke spuštění potřebuje soubory s grafikou a zvukem z instalace Settlers 3.\nPokud kopii nevlastníte, přečtěte si README na naší stránce GitHub.\nChcete-li pokračovat, musíte nyní vybrat složku s takovou instalací.
+settings-hd-graphics = HD grafika (nutný restart)
+settings-hd-graphics-no = Ne
+settings-hd-graphics-yes = Ano
+settings-hd-graphics-restart = HD grafika se použije po restartu hry. Při prvním zapnutí se při dalším startu vytvoří zvětšené obrázky z vašich původních herních souborů, což potrvá několik minut.
+settings-hd-graphics-restart-short = Změna se projeví po restartu hry.
+hd-graphics-title = HD grafika
+hd-graphics-preparing = Zvětšuji původní grafiku (jen poprvé) ...
+hd-graphics-remaining = zbývá asi %d min
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 1c1c85c37..7bcff886b 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -623,4 +623,12 @@ errordlg-start-failed = Unexpected Error occurred:
 error-rendering = An error has occured :/\nPlease report this bug on GitHub\nTake note of the "Found a bug?" section in the readme\n(github.com/paulwedeck/settlers-remake)\n\n%s
 
 flatpak-title=Select original game directory
-flatpak-description=JSettlers needs graphics and sound files from a Settlers 3 installation to run.\nIf you don't own a copy read the README on our GitHub page.\nYou must now select such an installation directory to proceed.
\ No newline at end of file
+flatpak-description=JSettlers needs graphics and sound files from a Settlers 3 installation to run.\nIf you don't own a copy read the README on our GitHub page.\nYou must now select such an installation directory to proceed.
+settings-hd-graphics = HD graphics (needs restart)
+settings-hd-graphics-no = No
+settings-hd-graphics-yes = Yes
+settings-hd-graphics-restart = The HD graphics are used after the game is restarted. When they are switched on for the first time, the enlarged images are made from your original game files at the next start, which takes a few minutes.
+settings-hd-graphics-restart-short = The change is applied after the game is restarted.
+hd-graphics-title = HD graphics
+hd-graphics-preparing = Enlarging the original graphics (only the first time) ...
+hd-graphics-remaining = about %d min left
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
index 64fcc7ae6..af4b5fec3 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/settingsmenu/SettingsMenuPanel.java
@@ -16,6 +16,7 @@ package jsettlers.main.swing.menu.settingsmenu;
 
 import java.awt.BorderLayout;
 import java.awt.GridLayout;
+import java.io.File;
 
 import javax.swing.JButton;
 import javax.swing.JCheckBox;
@@ -23,10 +24,12 @@ import javax.swing.JComboBox;
 import javax.swing.JComponent;
 import javax.swing.JLabel;
 import javax.swing.JPanel;
+import javax.swing.JOptionPane;
 import javax.swing.JTextField;
 import javax.swing.SwingUtilities;
 
 import go.graphics.swing.contextcreator.BackendSelector;
+import jsettlers.graphics.image.hd.HdGraphics;
 import jsettlers.graphics.localization.Labels;
 import jsettlers.main.swing.lookandfeel.ELFStyle;
 import jsettlers.main.swing.menu.mainmenu.MainMenuPanel;
@@ -54,6 +57,7 @@ public class SettingsMenuPanel extends JPanel {
 	private final SettingsSlider fpsLimitSlider = new SettingsSlider("fps", 0,240, Labels.getString("settings-fps-limit-none"));
 	private final SettingsSlider guiScaleSlider = new SettingsSlider("%", 50,400, Labels.getString("settings-gui-scale-default"));
 	private final JComboBox<GameLanguage> languageSelector = new JComboBox<>(GameLanguage.values());
+	private final JComboBox<HdOption> hdSelector = new JComboBox<>(HdOption.values());
 	private final JCheckBox aiTowerFocusCheckBox = new JCheckBox();
 	private final BackendSelector backendSelector = new BackendSelector();
 
@@ -78,6 +82,8 @@ public class SettingsMenuPanel extends JPanel {
 		backendSelector.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
 		languageSelector.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
 		languageSelector.setEditable(false);
+		hdSelector.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
+		hdSelector.setEditable(false);
 		
 		SwingUtilities.updateComponentTreeUI(playerNameField);
 		addSetting("settings-name", playerNameField);
@@ -95,6 +101,7 @@ public class SettingsMenuPanel extends JPanel {
 		addSetting("settings-backend", backendSelector);
 
 		addSetting("settings-gui-scale", guiScaleSlider);
+		addSetting("settings-hd-graphics", hdSelector);
 		addSetting("settings-ai-tower-focus", aiTowerFocusCheckBox);
 		
 		initButton();
@@ -136,14 +143,26 @@ public class SettingsMenuPanel extends JPanel {
 			settingsManager.setGuiScale(guiScaleSlider.getValue()/100f);
 			settingsManager.setAiNoPioneers(aiTowerFocusCheckBox.isSelected());
 
+			HdOption selectedHd = (HdOption) hdSelector.getSelectedItem();
+			boolean hdChanged = selectedHd != null && selectedHd.enabled != settingsManager.isHdGraphics();
+			if (hdChanged) {
+				settingsManager.setHdGraphics(selectedHd.enabled);
+			}
+
 			GameLanguage selectedLanguage = (GameLanguage) languageSelector.getSelectedItem();
 			if (selectedLanguage != null && selectedLanguage != GameLanguage.fromLocale(settingsManager.getLocale())) {
 				settingsManager.setLocale(selectedLanguage.getLocale());
 				// replaces all menus (including this one), so there is nothing left to reset here
 				mainMenuPanel.languageChanged();
+				if (hdChanged) {
+					showHdRestartNotice(selectedHd.enabled);
+				}
 				return;
 			}
 			mainMenuPanel.reset();
+			if (hdChanged) {
+				showHdRestartNotice(selectedHd.enabled);
+			}
 		});
 
 		JPanel buttonPanel = new JPanel();
@@ -163,6 +182,43 @@ public class SettingsMenuPanel extends JPanel {
 		fpsLimitSlider.setValue(settingsManager.getFpsLimit());
 		backendSelector.setSelectedItem(settingsManager.getBackend());
 		guiScaleSlider.setValue(Math.round(settingsManager.getGuiScale()*100));
+		hdSelector.setSelectedItem(settingsManager.isHdGraphics() ? HdOption.YES : HdOption.NO);
 		aiTowerFocusCheckBox.setSelected(settingsManager.getAiTowerFocus());
 	}
+
+	/**
+	 * Tells the player that the HD setting needs a restart. The dialog has no button, it is just closed with the window (like the native dialogs on
+	 * macOS). The remark about the first start is only shown while no enlarged images exist yet.
+	 */
+	private void showHdRestartNotice(boolean enabled) {
+		String key = enabled && !hasHdImages() ? "settings-hd-graphics-restart" : "settings-hd-graphics-restart-short";
+		JOptionPane.showOptionDialog(this, Labels.getString(key), Labels.getString("settings-hd-graphics"), JOptionPane.DEFAULT_OPTION,
+				JOptionPane.INFORMATION_MESSAGE, null, new Object[0], null);
+	}
+
+	private static boolean hasHdImages() {
+		File[] files = HdGraphics.getCacheDir().listFiles((dir, name) -> name.endsWith(".hd"));
+		return files != null && files.length > 0;
+	}
+
+	/**
+	 * The choices of the HD graphics setting.
+	 */
+	private enum HdOption {
+		NO(false, "settings-hd-graphics-no"),
+		YES(true, "settings-hd-graphics-yes");
+
+		private final boolean enabled;
+		private final String labelKey;
+
+		HdOption(boolean enabled, String labelKey) {
+			this.enabled = enabled;
+			this.labelKey = labelKey;
+		}
+
+		@Override
+		public String toString() {
+			return Labels.getString(labelKey);
+		}
+	}
 }
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/HdSetup.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/HdSetup.java
new file mode 100644
index 000000000..52938290e
--- /dev/null
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/HdSetup.java
@@ -0,0 +1,99 @@
+/*******************************************************************************
+ * Copyright (c) 2026
+ *
+ * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
+ * to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
+ * and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
+ *
+ * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
+ *
+ * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+ * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+ * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
+ * DEALINGS IN THE SOFTWARE.
+ *******************************************************************************/
+package jsettlers.main.swing.resources;
+
+import java.awt.BorderLayout;
+import java.awt.GraphicsEnvironment;
+import java.io.File;
+
+import javax.swing.BorderFactory;
+import javax.swing.JDialog;
+import javax.swing.JLabel;
+import javax.swing.JProgressBar;
+import javax.swing.SwingUtilities;
+
+import jsettlers.graphics.image.hd.HdGraphics;
+import jsettlers.graphics.localization.Labels;
+
+/**
+ * Prepares the HD graphics when the game starts: makes the enlarged images if they do not exist yet and shows the progress.
+ */
+final class HdSetup {
+	private HdSetup() {
+	}
+
+	static void prepare(File gfxFolder) {
+		HdGraphics.setEnabled(true);
+
+		JDialog[] dialog = new JDialog[1];
+		JLabel[] info = new JLabel[1];
+		JProgressBar[] bar = new JProgressBar[1];
+		boolean showDialog = !GraphicsEnvironment.isHeadless();
+		long[] start = {0};
+
+		try {
+			HdGraphics.prepare(gfxFolder, (text, done, total) -> {
+				if (!showDialog) {
+					return;
+				}
+				if (start[0] == 0) {
+					start[0] = System.currentTimeMillis();
+				}
+				Runnable update = () -> {
+					if (dialog[0] == null) {
+						JLabel title = new JLabel(Labels.getString("hd-graphics-preparing"));
+						info[0] = new JLabel(" ");
+						bar[0] = new JProgressBar(0, 1000);
+						bar[0].setStringPainted(true);
+						dialog[0] = new JDialog((java.awt.Frame) null, Labels.getString("hd-graphics-title"), false);
+						dialog[0].setDefaultCloseOperation(JDialog.DO_NOTHING_ON_CLOSE);
+						dialog[0].setLayout(new BorderLayout(10, 10));
+						((javax.swing.JComponent) dialog[0].getContentPane()).setBorder(BorderFactory.createEmptyBorder(15, 20, 15, 20));
+						dialog[0].add(title, BorderLayout.NORTH);
+						dialog[0].add(bar[0], BorderLayout.CENTER);
+						dialog[0].add(info[0], BorderLayout.SOUTH);
+						dialog[0].setSize(520, 150);
+						dialog[0].setLocationRelativeTo(null);
+						dialog[0].setVisible(true);
+					}
+					bar[0].setValue(total == 0 ? 0 : (int) (done * 1000L / total));
+					String remaining = "";
+					long elapsed = System.currentTimeMillis() - start[0];
+					if (done > 50 && elapsed > 5000) {
+						long seconds = elapsed * (total - done) / done / 1000;
+						remaining = Labels.getString("hd-graphics-remaining", Math.max(1, (seconds + 30) / 60));
+					}
+					bar[0].setString(done + " / " + total);
+					info[0].setText(text + (remaining.isEmpty() ? "" : "   -   " + remaining));
+				};
+				if (SwingUtilities.isEventDispatchThread()) {
+					update.run();
+				} else {
+					SwingUtilities.invokeLater(update);
+				}
+			});
+		} catch (RuntimeException | Error e) {
+			e.printStackTrace();
+		} finally {
+			if (showDialog) {
+				SwingUtilities.invokeLater(() -> {
+					if (dialog[0] != null) {
+						dialog[0].dispose();
+					}
+				});
+			}
+		}
+	}
+}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/SwingResourceLoader.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/SwingResourceLoader.java
index 9be5a225e..ff93cb33c 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/SwingResourceLoader.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/resources/SwingResourceLoader.java
@@ -53,6 +53,11 @@ public class SwingResourceLoader {
 			SettingsManager.getInstance().setSettlersVersionId(settlersVersionId);
 		}
 
+		// the HD graphics: enlarged images, made once from the original graphics (see HdGraphics)
+		if (SettingsManager.getInstance().isHdGraphics()) {
+			HdSetup.prepare(settlersFolders.gfxFolder);
+		}
+
 		// setup image and sound provider
 		ImageProvider.setLookupPath(settlersFolders.gfxFolder, settlersVersionId);
 		SoundManager.setLookupPath(settlersFolders.sndFolder);
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
index edfaf0158..792a0b955 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/settings/SettingsManager.java
@@ -52,6 +52,7 @@ public class SettingsManager implements ISoundSettingsProvider {
 
 	private static final String SETTING_USERNAME = "name";
 	private static final String SETTING_LOCALE = "locale";
+	private static final String SETTING_HD_GRAPHICS = "hd-graphics";
 	private static final String SETTING_VOLUME = "volume";
 	private static final String SETTING_VOLUME_MUSIC = "volume-music";
 	private static final String SETTING_MUSIC_PLAYALL = "music-playall";
@@ -227,6 +228,17 @@ public class SettingsManager implements ISoundSettingsProvider {
 				.map(s -> ECivilisation.valueOf(s.toUpperCase()));
 	}
 
+	/**
+	 * Gets if the HD graphics (enlarged images of the original graphics) are used. Off unless it was switched on in the settings menu.
+	 */
+	public boolean isHdGraphics() {
+		return Optional.ofNullable(get(SETTING_HD_GRAPHICS)).map(Boolean::parseBoolean).orElse(false);
+	}
+
+	public void setHdGraphics(boolean hdGraphics) {
+		set(SETTING_HD_GRAPHICS, Boolean.toString(hdGraphics));
+	}
+
 	public boolean getAiTowerFocus() {
 		return Optional.ofNullable(get(SETTING_AI_TOWER_FOCUS))
 				.map(Boolean::parseBoolean)
PATCH_EOF
cat > "$WORK/patches/18-smithy-output.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/BuildingSelectionContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/BuildingSelectionContent.java
index 0eb7c83a2..12ed49ef6 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/BuildingSelectionContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/BuildingSelectionContent.java
@@ -20,6 +20,7 @@ import java.util.Optional;
 import go.graphics.GLDrawContext;
 import go.graphics.text.EFontSize;
 import jsettlers.common.buildings.BuildingVariant;
+import jsettlers.common.buildings.EBuildingType;
 import jsettlers.common.buildings.IBuilding;
 import jsettlers.common.images.EImageLinkType;
 import jsettlers.common.images.ImageLink;
@@ -400,21 +401,54 @@ public class BuildingSelectionContent extends AbstractSelectionContent {
 		}
 	}
 
+	private static final int SMITHY_BUTTONS_PER_ROW = 5;
+	/** Gap between two rows of material buttons, relative to the height of one row (3 of 29 pixels). */
+	private static final float SMITHY_ROW_GAP = 3f / 29;
+
 	private void addRequestAndOfferStacks(UIPanel materialArea, BuildingState state) {
 		// hardcoded...
 		float buttonWidth = 18f / (127 - 9);
 		float buttonSpace = 12f / (127 - 9);
 
+		List<StackState> stacks = state.getStackStates();
+
+		// The tool and weapon smithies can have many different products lying at the building. Up to 5 buttons stay in one row (with a smaller
+		// gap if needed). With more, the first row moves up and the rest is placed in rows below it, the last row at the original position.
+		// Other buildings with 4 or 5 stacks (e.g. the laboratory of the Amazons: 2 requested and 2 offered materials) get the smaller gap too,
+		// otherwise the buttons of the requested and the offered materials overlap.
+		boolean smithy = building.getBuildingVariant().getType() == EBuildingType.TOOLSMITH
+				|| building.getBuildingVariant().getType() == EBuildingType.WEAPONSMITH;
+		int perRow = Integer.MAX_VALUE;
+		if (smithy) {
+			perRow = SMITHY_BUTTONS_PER_ROW;
+		}
+		if (stacks.size() > 3 && (smithy || stacks.size() <= SMITHY_BUTTONS_PER_ROW)) {
+			int inRow = Math.min(stacks.size(), SMITHY_BUTTONS_PER_ROW);
+			buttonSpace = (1 - inRow * buttonWidth) / (inRow + 1);
+		}
+		int rows = Math.max(1, (stacks.size() + perRow - 1) / perRow);
+		float rowStep = 1 + SMITHY_ROW_GAP;
+
 		float requestX = buttonSpace;
 		float offerX = 1 - buttonSpace - buttonWidth;
+		int index = 0;
+		for (StackState mat : stacks) {
+			int row = index / perRow;
+			if (index % perRow == 0) {
+				requestX = buttonSpace;
+				offerX = 1 - buttonSpace - buttonWidth;
+			}
+			index++;
+
+			float bottom = (rows - 1 - row) * rowStep;
+			float top = bottom + 1;
 
-		for (StackState mat : state.getStackStates()) {
 			MaterialDisplay display = new MaterialDisplay(mat);
 			if (mat.isOffering()) {
-				materialArea.addChild(display, offerX, 0, offerX + buttonWidth, 1);
+				materialArea.addChild(display, offerX, bottom, offerX + buttonWidth, top);
 				offerX -= buttonSpace + buttonWidth;
 			} else {
-				materialArea.addChild(display, requestX, 0, requestX + buttonWidth, 1);
+				materialArea.addChild(display, requestX, bottom, requestX + buttonWidth, top);
 				requestX += buttonSpace + buttonWidth;
 			}
 		}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/Building.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/Building.java
index 721e41d6a..7cd1c5b98 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/Building.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/Building.java
@@ -35,6 +35,7 @@ import jsettlers.common.buildings.stacks.ConstructionStack;
 import jsettlers.common.buildings.stacks.RelativeStack;
 import jsettlers.common.map.shapes.FreeMapArea;
 import jsettlers.common.mapobject.EMapObjectType;
+import jsettlers.common.material.EMaterialType;
 import jsettlers.common.material.EPriority;
 import jsettlers.common.movable.EDirection;
 import jsettlers.common.player.IPlayerable;
@@ -670,11 +671,41 @@ public abstract class Building extends AbstractHexMapObject implements IConstruc
 				byte stackSize = grid.getRequestStackGrid().getStackSize(offerStack.calculatePoint(pos), offerStack.getMaterialType());
 				materials.add(new BuildingMaterial(offerStack.getMaterialType(), stackSize, true));
 			}
+
+			addSmithyOutput(materials);
 		}
 
 		return materials;
 	}
 
+	/**
+	 * The tool and weapon smithies have no fixed offer stacks, they drop whatever they produced at one position. Show every kind that currently lies
+	 * there so the player can see what has to be carried away.
+	 */
+	private void addSmithyOutput(List<IBuildingMaterial> materials) {
+		Collection<EMaterialType> products;
+		if (type == EBuildingType.TOOLSMITH) {
+			products = EMaterialType.TOOLS;
+		} else if (type == EBuildingType.WEAPONSMITH) {
+			products = EMaterialType.WEAPONS;
+		} else {
+			return;
+		}
+
+		RelativePoint dropPosition = getBuildingVariant().getSmithDropPosition();
+		if (dropPosition == null) {
+			return;
+		}
+		ShortPoint2D dropPoint = dropPosition.calculatePoint(pos);
+
+		for (EMaterialType product : products) {
+			byte stackSize = grid.getRequestStackGrid().getStackSize(dropPoint, product);
+			if (stackSize > 0) {
+				materials.add(new BuildingMaterial(product, stackSize, true));
+			}
+		}
+	}
+
 	public void setPriority(EPriority newPriority) {
 		this.priority = newPriority;
 		if (stacks != null) {
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
index 10294909a..fd332444d 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
@@ -448,9 +448,13 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 				continue; // skip inactive requests and requests not needing a tool production
 			}
 
+			EMaterialType tool = request.requestedMovableType().getTool();
+			if (materialOffers.getOfferCloseTo(tool, EOfferPriority.LOWEST, request.getPosition()) != null) {
+				continue; // this tool has already been produced and only waits to be picked up, do not produce more of it
+			}
+
 			request.setToolProductionRequired(false); // FIXME @andreas-eberle: Investigate if this is correct! And why it doesn't break the system
 
-			EMaterialType tool = request.requestedMovableType().getTool();
 			byte prio = priorityForTool[tool.ordinal];
 
 			if (prio > bestPrio) {
PATCH_EOF
cat > "$WORK/patches/19-auto-work-area.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/resources/jsettlers/common/buildings/amazon/beekeeping.xml b/jsettlers.common/src/main/resources/jsettlers/common/buildings/amazon/beekeeping.xml
index 6ad1b8cac..25bf56e55 100644
--- a/jsettlers.common/src/main/resources/jsettlers/common/buildings/amazon/beekeeping.xml
+++ b/jsettlers.common/src/main/resources/jsettlers/common/buildings/amazon/beekeeping.xml
@@ -1,6 +1,6 @@
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE building SYSTEM "../building.dtd" >
-<building worker="BEEKEEPER" workradius="10">
+<building worker="BEEKEEPER" workradius="20">
 	<ground groundtype="GRASS" />
 	<ground groundtype="EARTH" />
 	<ground groundtype="FLATTENED" />
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
index d7e8a6f9c..424a393ae 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IWorkerRequestBuilding.java
@@ -42,6 +42,11 @@ public interface IWorkerRequestBuilding extends IPlayerable, ILocatable, IBuildi
 
 	ShortPoint2D getWorkAreaCenter();
 
+	/**
+	 * Moves the work area. Used by workers to follow the work automatically if nothing is left to do in the current area.
+	 */
+	void setWorkAreaCenter(ShortPoint2D newWorkAreaCenter);
+
 	void occupyBuilding(IManageableWorker worker);
 
 	BuildingVariant getBuildingVariant();
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BuildingWorkerMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BuildingWorkerMovable.java
index 1d83319e6..b7fd2c587 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BuildingWorkerMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BuildingWorkerMovable.java
@@ -5,6 +5,8 @@ import jsettlers.algorithms.simplebehaviortree.IEMaterialTypeSupplier;
 import jsettlers.algorithms.simplebehaviortree.IShortSupplier;
 import jsettlers.algorithms.simplebehaviortree.Node;
 import jsettlers.algorithms.simplebehaviortree.nodes.Guard;
+import jsettlers.algorithms.path.Path;
+import jsettlers.common.buildings.BuildingVariant;
 import jsettlers.common.buildings.EBuildingType;
 import jsettlers.common.buildings.IBuilding;
 import jsettlers.common.buildings.stacks.RelativeStack;
@@ -28,6 +30,8 @@ import jsettlers.logic.player.Player;
 import java.io.FileOutputStream;
 import java.io.IOException;
 import java.io.PrintStream;
+import java.util.ArrayList;
+import java.util.List;
 import java.util.function.Supplier;
 
 import static jsettlers.algorithms.simplebehaviortree.BehaviorTreeHelper.*;
@@ -39,6 +43,10 @@ public class BuildingWorkerMovable extends CivilianMovable implements IBuildingW
 	protected IWorkerRequestBuilding building;
 	private boolean registered = false;
 	protected int searchFailedCtr = 0;
+	/** Work area centers used before the current one. Ripe crops that were planted there are still harvested. */
+	private final List<ShortPoint2D> formerWorkAreaCenters = new ArrayList<>();
+	private ShortPoint2D lastWorkAreaCenter = null;
+	private static final int MAX_FORMER_WORK_AREA_CENTERS = 4;
 
 	public BuildingWorkerMovable(AbstractMovableGrid grid, EMovableType movableType, ShortPoint2D position, Player player, Movable replace) {
 		super(grid, movableType, position, player, replace);
@@ -279,12 +287,64 @@ public class BuildingWorkerMovable extends CivilianMovable implements IBuildingW
 	protected static <T extends BuildingWorkerMovable> Node<T> preSearchPathNoWarning(boolean dijkstra, ESearchType searchType) {
 		return BehaviorTreeHelper.condition(mov -> {
 			ShortPoint2D workAreaCenter = mov.building.getWorkAreaCenter();
+			mov.rememberWorkAreaCenter(workAreaCenter);
 
-			return mov.preSearchPath(dijkstra, workAreaCenter.x, workAreaCenter.y, mov.building.getBuildingVariant().getWorkRadius(),
+			boolean found = mov.preSearchPath(dijkstra, workAreaCenter.x, workAreaCenter.y, mov.building.getBuildingVariant().getWorkRadius(),
 					searchType);
+			if (found) { // there is work (e.g. planting), so there is no reason to complain
+				mov.searchFailedCtr = 0;
+				mov.building.setCannotWork(false);
+			}
+			return found;
 		});
 	}
 
+	protected void rememberWorkAreaCenter(ShortPoint2D center) {
+		if (lastWorkAreaCenter != null && !lastWorkAreaCenter.equals(center)) {
+			formerWorkAreaCenters.remove(lastWorkAreaCenter);
+			formerWorkAreaCenters.add(lastWorkAreaCenter);
+			if (formerWorkAreaCenters.size() > MAX_FORMER_WORK_AREA_CENTERS) {
+				formerWorkAreaCenters.remove(0);
+			}
+		}
+		lastWorkAreaCenter = center;
+	}
+
+	/**
+	 * Like {@link #preSearchPath}, but for harvesting: if there is nothing ripe in the current work area, the former work areas and the default work
+	 * area are searched too. So crops that were planted before the work area was moved are harvested first, instead of rotting away.
+	 */
+	protected static <T extends BuildingWorkerMovable> Node<T> preSearchHarvestPath(ESearchType searchType) {
+		return selector(
+				preSearchPathNoWarning(true, searchType),
+				condition(mov -> {
+					if (mov.preSearchHarvestElsewhere(searchType)) {
+						mov.searchFailedCtr = 0;
+						mov.building.setCannotWork(false);
+						return true;
+					}
+					return false;
+				}),
+				preSearchPath(true, searchType) // nothing to harvest at all: usual handling of failed searches
+		);
+	}
+
+	protected boolean preSearchHarvestElsewhere(ESearchType searchType) {
+		short radius = building.getBuildingVariant().getWorkRadius();
+		ShortPoint2D current = building.getWorkAreaCenter();
+		List<ShortPoint2D> bases = new ArrayList<>(formerWorkAreaCenters);
+		bases.add(building.getBuildingVariant().getDefaultWorkcenter().calculatePoint(building.getPosition()));
+		for (ShortPoint2D base : bases) {
+			if (base.equals(current) || !isInGrid(base)) {
+				continue;
+			}
+			if (preSearchPath(true, base.x, base.y, radius, searchType)) {
+				return true;
+			}
+		}
+		return false;
+	}
+
 	protected static <T extends BuildingWorkerMovable> Node<T> preSearchPath(boolean dijkstra, ESearchType searchType) {
 		return selector(
 				sequence(
@@ -298,7 +358,10 @@ public class BuildingWorkerMovable extends CivilianMovable implements IBuildingW
 					action(mov -> {
 						mov.searchFailedCtr++;
 
-						if (mov.searchFailedCtr > 10) {
+						if (mov.isTimeToMoveWorkArea() && mov.moveWorkAreaToWork(searchType, true)) {
+							mov.searchFailedCtr = 0;
+							mov.building.setCannotWork(false);
+						} else if (mov.searchFailedCtr > 10) {
 							mov.building.setCannotWork(true);
 							mov.player.showMessage(SimpleMessage.cannotFindWork(mov.building));
 						}
@@ -308,6 +371,155 @@ public class BuildingWorkerMovable extends CivilianMovable implements IBuildingW
 		);
 	}
 
+	// ---- Automatic work area: if there is nothing to do in the current work area, the building looks for work nearby and moves its work area.
+
+	/** The first automatic attempt is made after this many failed searches (before the "cannot find work" message would appear). */
+	private static final int AUTO_AREA_FIRST_TRY = 2;
+	/** After that, another attempt is made after this many failed searches (about 2 seconds). */
+	private static final int AUTO_AREA_RETRY_PERIOD = 34;
+
+	protected boolean isTimeToMoveWorkArea() {
+		return searchFailedCtr >= AUTO_AREA_FIRST_TRY && (searchFailedCtr - AUTO_AREA_FIRST_TRY) % AUTO_AREA_RETRY_PERIOD == 0;
+	}
+
+	/**
+	 * A node that moves the work area to a place where there is work for the given search types (tried in the given order).
+	 */
+	protected static <T extends BuildingWorkerMovable> Node<T> autoWorkArea(ESearchType... searchTypes) {
+		return action(mov -> {
+			for (ESearchType searchType : searchTypes) {
+				if (mov.moveWorkAreaToWork(searchType, false)) {
+					mov.searchFailedCtr = 0;
+					mov.building.setCannotWork(false);
+					return;
+				}
+			}
+		});
+	}
+
+	/**
+	 * Looks for work of the given type outside of the current work area and moves the work area there.
+	 * <ul>
+	 * <li>Trees, stones, fish, rivers (big areas): the area follows the nearest work within twice the work radius of the current center or the default
+	 * center, but not further than three times the work radius from the building.</li>
+	 * <li>Tree planting: like above, but with a smaller range.</li>
+	 * <li>Rice: the area follows the nearest swamp that can be planted or harvested within three times the work radius.</li>
+	 * <li>Bees: like rice, the area follows the nearest place for a hive (grass next to a tree) within twice the work radius.</li>
+	 * <li>Corn and wine (they work around the building): the area returns to the default center if there is work, otherwise it moves a bit to the
+	 * side, up to twice the work radius from the default center. Vines can only be planted on slopes, so the winegrower
+	 * searches the whole range that is allowed for a work area (almost four work radii from the building).</li>
+	 * </ul>
+	 *
+	 * @param searchType
+	 * 		The type of work.
+	 * @param onlyBigAreas
+	 * 		If true, only the types that do not have a separate "nothing to do" fallback in their behaviour are handled.
+	 * @return true if the work area was moved.
+	 */
+	protected boolean moveWorkAreaToWork(ESearchType searchType, boolean onlyBigAreas) {
+		BuildingVariant variant = building.getBuildingVariant();
+		short radius = variant.getWorkRadius();
+		if (radius <= 0) {
+			return false;
+		}
+
+		ShortPoint2D buildingPos = building.getPosition();
+		ShortPoint2D current = building.getWorkAreaCenter();
+		ShortPoint2D home = variant.getDefaultWorkcenter().calculatePoint(buildingPos);
+		if (current == null) {
+			return false;
+		}
+
+		int searchRadius;
+		int maxDistance;
+		boolean homeFirst = false;
+		ShortPoint2D limitCenter = buildingPos; // maxDistance is measured from here
+		switch (searchType) {
+		case CUTTABLE_TREE:
+		case CUTTABLE_STONE:
+		case FISHABLE:
+		case RIVER:
+			searchRadius = 2 * radius;
+			maxDistance = 3 * radius;
+			break;
+		case PLANTABLE_TREE:
+			searchRadius = (3 * radius) / 2;
+			maxDistance = 2 * radius;
+			break;
+		case PLANTABLE_RICE:
+		case HARVESTABLE_RICE:
+			if (onlyBigAreas) {
+				return false;
+			}
+			searchRadius = 3 * radius;
+			maxDistance = 3 * radius;
+			break;
+		case PLANTABLE_HIVE:
+		case HARVESTABLE_HIVE:
+			// hives need grass next to a tree, so the beekeeper follows the nearest suitable place
+			if (onlyBigAreas) {
+				return false;
+			}
+			searchRadius = 2 * radius;
+			maxDistance = 2 * radius;
+			break;
+		case CUTTABLE_CORN:
+		case PLANTABLE_CORN:
+			// work around the building: go back to the default center if there is something to do there, otherwise move the area a bit
+			// to the side (e.g. if the default area is blocked by a building)
+			if (onlyBigAreas) {
+				return false;
+			}
+			homeFirst = true;
+			limitCenter = home;
+			searchRadius = 2 * radius;
+			maxDistance = 2 * radius; // measured from the default center, because that is already some way from the building
+			break;
+		case HARVESTABLE_WINE:
+		case PLANTABLE_WINE:
+			// like corn, but vines can only be planted on slopes, which are rare, so the whole range that is allowed for a work area is searched
+			if (onlyBigAreas) {
+				return false;
+			}
+			homeFirst = true;
+			searchRadius = 4 * radius;
+			maxDistance = 4 * radius - 1; // measured from the building; a work area must be closer than 4 work radii to its building
+			break;
+		default:
+			return false;
+		}
+
+		if (homeFirst && !current.equals(home) && isInGrid(home) && grid.searchDijkstra(this, home.x, home.y, radius, searchType) != null) {
+			building.setWorkAreaCenter(home);
+			if (building.getWorkAreaCenter().equals(home)) {
+				return true;
+			}
+		}
+
+		ShortPoint2D[] bases = current.equals(home) ? new ShortPoint2D[] { current } : new ShortPoint2D[] { current, home };
+		for (ShortPoint2D base : bases) {
+			if (!isInGrid(base)) {
+				continue;
+			}
+			Path path = grid.searchDijkstra(this, base.x, base.y, (short) searchRadius, searchType);
+			if (path == null) {
+				continue;
+			}
+			ShortPoint2D target = path.getTargetPosition();
+			if (!target.equals(current) && limitCenter.getOnGridDistTo(target) <= maxDistance) {
+				building.setWorkAreaCenter(target);
+				if (building.getWorkAreaCenter().equals(target)) {
+					return true;
+				}
+			}
+		}
+		return false;
+	}
+
+	private boolean isInGrid(ShortPoint2D point) {
+		return point.x >= 0 && point.y >= 0 && point.x < grid.getWidth() && point.y < grid.getHeight();
+	}
+
 	protected boolean tryTakingResource() {
 		if(building.getBuildingVariant().isVariantOf(EBuildingType.FISHER)) {
 			EDirection fishDirection = getDirection();
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
index f69e1c4b1..45f79d30f 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
@@ -242,7 +242,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 						selector(
 							sequence(
 								outputStackNotFull(EMaterialType.WINE),
-								preSearchPath(true, ESearchType.HARVESTABLE_WINE),
+								preSearchHarvestPath(ESearchType.HARVESTABLE_WINE),
 								ignoreFailure(
 									sequence(
 										setMaterialNode(EMaterialType.BASKET),
@@ -284,6 +284,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 								)
 							),
 							sequence(
+								autoWorkArea(ESearchType.HARVESTABLE_WINE, ESearchType.PLANTABLE_WINE),
 								sleep(1000),
 								alwaysFail()
 							)
@@ -303,7 +304,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 						selector(
 							sequence(
 								outputStackNotFull(EMaterialType.CROP),
-								preSearchPath(true, ESearchType.CUTTABLE_CORN),
+								preSearchHarvestPath(ESearchType.CUTTABLE_CORN),
 								ignoreFailure(
 									sequence(
 										show(),
@@ -360,6 +361,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 								)
 							),
 							sequence(
+								autoWorkArea(ESearchType.CUTTABLE_CORN, ESearchType.PLANTABLE_CORN),
 								sleep(1000),
 								alwaysFail()
 							)
@@ -573,7 +575,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 						selector(
 							sequence(
 								outputStackNotFull(EMaterialType.RICE),
-								preSearchPath(true, ESearchType.HARVESTABLE_RICE),
+								preSearchHarvestPath(ESearchType.HARVESTABLE_RICE),
 								ignoreFailure(
 									sequence(
 										condition(mov -> true),
@@ -611,6 +613,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 								)
 							),
 							sequence(
+								autoWorkArea(ESearchType.PLANTABLE_RICE, ESearchType.HARVESTABLE_RICE),
 								sleep(1000),
 								alwaysFail()
 							)
@@ -630,7 +633,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 						selector(
 							sequence(
 								outputStackNotFull(EMaterialType.HONEY),
-								preSearchPath(true, ESearchType.HARVESTABLE_HIVE),
+								preSearchHarvestPath(ESearchType.HARVESTABLE_HIVE),
 								ignoreFailure(
 									sequence(
 										show(),
@@ -670,6 +673,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 								)
 							),
 							sequence(
+								autoWorkArea(ESearchType.HARVESTABLE_HIVE, ESearchType.PLANTABLE_HIVE),
 								sleep(1000),
 								alwaysFail()
 							)
PATCH_EOF
cat > "$WORK/patches/20-convert-specialists-to-bearers.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/SpecialistSelectionContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/SpecialistSelectionContent.java
index 6b8491905..9be91a0d8 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/SpecialistSelectionContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/panel/selection/SpecialistSelectionContent.java
@@ -50,7 +50,9 @@ public class SpecialistSelectionContent extends AbstractSelectionContent {
 		panel.addChild(stop, .1f, .1f, .5f, .2f);
 		panel.addChild(work, .5f, .1f, .9f, .2f);
 
-		if (selection.getMovableCount(EMovableType.PIONEER, null) > 0) {
+		if (selection.getMovableCount(EMovableType.PIONEER, null) > 0
+				|| selection.getMovableCount(EMovableType.THIEF, null) > 0
+				|| selection.getMovableCount(EMovableType.GEOLOGIST, null) > 0) {
 			UIPanel convert = new LabeledButton(Labels.getString("convert_all_to_BEARER"),
 					new ConvertAction(EMovableType.BEARER,
 							Short.MAX_VALUE));
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/ui/LabeledButton.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/ui/LabeledButton.java
index 59a721d5f..0cdeccd73 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/ui/LabeledButton.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/ui/LabeledButton.java
@@ -37,6 +37,9 @@ public class LabeledButton extends Button {
 	private static final OriginalImageLink BUTTON_ACTIVE = new OriginalImageLink(
 			EImageLinkType.GUI, 3, 327, 0);
 
+	/** The part of the button width that the text may use. */
+	private static final float MAX_TEXT_WIDTH = 0.92f;
+
 	private final EFontSize size;
 	private boolean enabled = true;
 
@@ -55,8 +58,14 @@ public class LabeledButton extends Button {
 	public void drawAt(GLDrawContext gl) {
 		super.drawAt(gl);
 
+		String label = getText();
 		TextDrawer drawer = gl.getTextDrawer(size);
-		drawer.renderCentered(getPosition().getCenterX(), getPosition().getCenterY(), getText());
+		float maxWidth = getPosition().getWidth() * MAX_TEXT_WIDTH;
+		if (size != EFontSize.SMALL && drawer.getWidth(label) > maxWidth) {
+			// the text does not fit on the button (long translations), use the smaller font
+			drawer = gl.getTextDrawer(EFontSize.SMALL);
+		}
+		drawer.renderCentered(getPosition().getCenterX(), getPosition().getCenterY(), label);
 	}
 
 	protected String getText() {
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index 263bb2cbb..ba7c4b285 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -329,13 +329,13 @@ kill = Zabít
 work = Pracovat zde
 unload = Vyložit trajekty
 convert_1_to_GEOLOGIST = Jeden nový geolog
-convert_all_to_GEOLOGIST = Přeměnit vybrané na geology
+convert_all_to_GEOLOGIST = Vybrané na geology
 convert_1_to_THIEF = Jeden nový zloděj
-convert_all_to_THIEF = Přeměnit vybrané na zloděje
+convert_all_to_THIEF = Vybrané na zloděje
 convert_1_to_PIONEER = Jeden nový pionýr
-convert_all_to_PIONEER = Přeměnit vybrané na pionýry
+convert_all_to_PIONEER = Vybrané na pionýry
 convert_1_to_BEARER = Jeden nový nosič
-convert_all_to_BEARER = Přeměnit vybrané na nosiče
+convert_all_to_BEARER = Vybrané na nosiče
 
 
 # stock gui labels
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 82b004014..e63454ac7 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -335,13 +335,13 @@ kill = Kill
 work = Work here
 unload = Unload ferries
 convert_1_to_GEOLOGIST = One new geologist
-convert_all_to_GEOLOGIST = Convert selected to geologists
+convert_all_to_GEOLOGIST = Selected to geologists
 convert_1_to_THIEF = One new thief
-convert_all_to_THIEF = Convert selected to thieves
+convert_all_to_THIEF = Selected to thieves
 convert_1_to_PIONEER = One new pioneer
-convert_all_to_PIONEER = Convert selected to pioneers
+convert_all_to_PIONEER = Selected to pioneers
 convert_1_to_BEARER = One new carrier
-convert_all_to_BEARER = Convert selected to carriers
+convert_all_to_BEARER = Selected to carriers
 
 
 # stock gui labels
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
index de0f73715..3e830ba33 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
@@ -543,7 +543,7 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 				for (final ISelectable curr : currentSelection) {
 					if (curr instanceof IGraphicsMovable) {
 						final EMovableType currType = ((IGraphicsMovable) curr).getMovableType();
-						if (currType == EMovableType.PIONEER) {
+						if (currType == EMovableType.PIONEER || currType == EMovableType.THIEF || currType == EMovableType.GEOLOGIST) {
 							convertables.add(curr);
 							if (convertables.size() >= action.getAmount()) {
 								break;
@@ -840,6 +840,27 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 		updateSelection(SelectionSet::createFromFilteredSelectionSetUpdatingType);
 	}
 
+	@Override
+	public void renewSelection(List<? extends ISelectable> additional) {
+		if (currentSelection.isEmpty() || additional.isEmpty()) {
+			renewSelection();
+			return;
+		}
+
+		Predicate<ISelectable> stillSelected = selectable -> selectable.isSelected() && canSelectPlayer(selectable.getPlayer());
+		List<ISelectable> all = new ArrayList<>();
+		currentSelection.stream().filter(stillSelected).forEach(all::add);
+		additional.stream().filter(stillSelected).filter(selectable -> !all.contains(selectable)).forEach(all::add);
+
+		SelectionSet newSelection = new SelectionSet(all);
+		for (ISelectable selectable : additional) {
+			if (!newSelection.contains(selectable)) {
+				selectable.setSelected(false); // could not be added to the new selection
+			}
+		}
+		setSelection(newSelection);
+	}
+
 	private void updateSelection(BiFunction<SelectionSet, Predicate<ISelectable>, SelectionSet> updateFunction) {
 		if (!currentSelection.isEmpty()) {
 			SelectionSet newSelection = updateFunction.apply(currentSelection, selectable -> selectable.isSelected() && canSelectPlayer(selectable.getPlayer()));
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
index fa7cd74c5..27be3242d 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
@@ -16,6 +16,7 @@ package jsettlers.input;
 
 import java.io.IOException;
 import java.util.Iterator;
+import java.util.ArrayList;
 import java.util.List;
 
 import java.util.Objects;
@@ -29,6 +30,7 @@ import jsettlers.common.buildings.IBuilding;
 import jsettlers.common.map.shapes.HexGridArea;
 import jsettlers.common.movable.EMovableType;
 import jsettlers.common.position.ShortPoint2D;
+import jsettlers.common.selectable.ISelectable;
 import jsettlers.common.utils.mutables.MutableInt;
 import jsettlers.input.tasks.CastSpellGuiTask;
 import jsettlers.input.tasks.ChangeTowerSoldiersGuiTask;
@@ -69,7 +71,7 @@ import jsettlers.logic.movable.interfaces.IBearerMovable;
 import jsettlers.logic.movable.interfaces.IFerryMovable;
 import jsettlers.logic.movable.interfaces.ILogicMovable;
 import jsettlers.logic.movable.interfaces.IMageMovable;
-import jsettlers.logic.movable.interfaces.IPioneerMovable;
+import jsettlers.logic.movable.interfaces.IConvertibleToBearer;
 import jsettlers.network.client.task.packets.TaskPacket;
 import jsettlers.network.synchronic.timer.ITaskExecutor;
 
@@ -313,8 +315,10 @@ class GuiTaskExecutor implements ITaskExecutor {
 	}
 
 	private void convertMovables(ConvertGuiTask guiTask) {
+		List<ISelectable> convertedSelected = new ArrayList<>();
 		for (Integer currID : guiTask.getSelection()) {
 			ILogicMovable movable = MovableManager.getMovableByID(currID);
+			boolean wasSelected = movable != null && movable.isSelected();
 			switch(guiTask.getTargetType()) {
 				case GEOLOGIST:
 				case PIONEER:
@@ -324,15 +328,23 @@ class GuiTaskExecutor implements ITaskExecutor {
 					}
 					break;
 				case BEARER:
-					if(movable instanceof IPioneerMovable) {
-						((IPioneerMovable)movable).convertToBearer();
+					if(movable instanceof IConvertibleToBearer) {
+						((IConvertibleToBearer)movable).convertToBearer();
 					}
 					break;
 				default:
 					System.err.println("Illegal conversion from " + movable.getMovableType() + " to " + guiTask.getTargetType());
 			}
+
+			if (wasSelected && movable instanceof Movable) { // the new movables stay selected
+				Movable replacement = ((Movable) movable).getReplacement();
+				if (replacement != null) {
+					replacement.setSelected(true);
+					convertedSelected.add(replacement);
+				}
+			}
 		}
-		guiInterface.renewSelection();
+		guiInterface.renewSelection(convertedSelected);
 	}
 
 	private void stopOrStartWorking(List<Integer> selectedMovables, boolean stop) {
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/ITaskExecutorGuiInterface.java b/jsettlers.logic/src/main/java/jsettlers/input/ITaskExecutorGuiInterface.java
index 9bb51635a..90529e6c6 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/ITaskExecutorGuiInterface.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/ITaskExecutorGuiInterface.java
@@ -14,7 +14,10 @@
  *******************************************************************************/
 package jsettlers.input;
 
+import java.util.List;
+
 import jsettlers.common.menu.UIState;
+import jsettlers.common.selectable.ISelectable;
 
 /**
  * Interface for TaskExecutor to give commands to the GuiInterface using the executor.
@@ -29,6 +32,14 @@ public interface ITaskExecutorGuiInterface {
 	 */
 	void renewSelection();
 
+	/**
+	 * Renews the current selection and adds the given movables to it. This is used after movables have been converted: the new movables stay selected.
+	 *
+	 * @param additional
+	 * 		The new movables that have to be part of the selection.
+	 */
+	void renewSelection(List<? extends ISelectable> additional);
+
 	/**
 	 * 
 	 * @return Returns the current {@link UIState} that can be used to save it with a savegame.
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/Movable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/Movable.java
index 79ecf5316..e16706af5 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/Movable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/Movable.java
@@ -115,6 +115,8 @@ public abstract class Movable implements ILogicMovable, FoWTask {
 	protected int     flockDelay  = 700;
 
 	private transient boolean selected    = false;
+	/** The movable that replaced this one (e.g. a bearer that was converted to a geologist), or null. */
+	private transient Movable replacedBy = null;
 	private transient boolean soundPlayed = false;
 
 	protected boolean playerControlled;
@@ -895,6 +897,13 @@ public abstract class Movable implements ILogicMovable, FoWTask {
 		this.selected = selected;
 	}
 
+	/**
+	 * @return The movable that took the place of this one when it was converted, or null if it has not been replaced.
+	 */
+	public final Movable getReplacement() {
+		return replacedBy;
+	}
+
 	@Override
 	public void stopOrStartWorking(boolean stop) {
 	}
@@ -1028,7 +1037,10 @@ public abstract class Movable implements ILogicMovable, FoWTask {
 		MovableManager.add(movable);
 		grid.enterPosition(position, movable, true);
 
-		if(replaceMovable != null) replaceMovable.killMovable();
+		if(replaceMovable != null) {
+			replaceMovable.replacedBy = movable;
+			replaceMovable.killMovable();
+		}
 		return movable;
 	}
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IConvertibleToBearer.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IConvertibleToBearer.java
new file mode 100644
index 000000000..dbfc8744f
--- /dev/null
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IConvertibleToBearer.java
@@ -0,0 +1,14 @@
+package jsettlers.logic.movable.interfaces;
+
+/**
+ * A movable that can be turned back into a normal carrier by the player (pioneers, thieves and geologists).
+ */
+public interface IConvertibleToBearer {
+
+	/**
+	 * Replaces this movable by a bearer. This only works on the ground of the owner.
+	 *
+	 * @return true if the movable has been converted.
+	 */
+	boolean convertToBearer();
+}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IPioneerMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IPioneerMovable.java
index f2f650a7d..d8b879879 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IPioneerMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/interfaces/IPioneerMovable.java
@@ -1,6 +1,6 @@
 package jsettlers.logic.movable.interfaces;
 
-public interface IPioneerMovable extends IAttackableHumanMovable {
+public interface IPioneerMovable extends IAttackableHumanMovable, IConvertibleToBearer {
 
 	boolean convertToBearer();
 }
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/GeologistMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/GeologistMovable.java
index 1e2f65959..defd2ebeb 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/GeologistMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/GeologistMovable.java
@@ -14,11 +14,12 @@ import jsettlers.logic.movable.MovableManager;
 import jsettlers.logic.movable.other.AttackableHumanMovable;
 import jsettlers.logic.movable.Movable;
 import jsettlers.logic.movable.interfaces.AbstractMovableGrid;
+import jsettlers.logic.movable.interfaces.IConvertibleToBearer;
 import jsettlers.logic.player.Player;
 
 import static jsettlers.algorithms.simplebehaviortree.BehaviorTreeHelper.*;
 
-public class GeologistMovable extends AttackableHumanMovable {
+public class GeologistMovable extends AttackableHumanMovable implements IConvertibleToBearer {
 
 	private static final long serialVersionUID = 1L;
 
@@ -37,6 +38,15 @@ public class GeologistMovable extends AttackableHumanMovable {
 		MovableManager.registerBehaviour(EMovableType.GEOLOGIST, new Root<>(createGeologistBehaviour()));
 	}
 
+	@Override
+	public boolean convertToBearer() {
+		if (!player.equals(grid.getPlayerAt(position))) return false;
+
+		createMovable(EMovableType.BEARER, player, position, grid, this);
+
+		return true;
+	}
+
 	public static Node<GeologistMovable> createGeologistBehaviour() {
 		return guardSelector(
 				handleFrozenEffect(),
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
index 952cc6dcf..840421a41 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java
@@ -16,11 +16,12 @@ import jsettlers.logic.movable.MovableManager;
 import jsettlers.logic.movable.other.AttackableHumanMovable;
 import jsettlers.logic.movable.Movable;
 import jsettlers.logic.movable.interfaces.AbstractMovableGrid;
+import jsettlers.logic.movable.interfaces.IConvertibleToBearer;
 import jsettlers.logic.player.Player;
 
 import static jsettlers.algorithms.simplebehaviortree.BehaviorTreeHelper.*;
 
-public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThief {
+public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThief, IConvertibleToBearer {
 
 	private static final long serialVersionUID = 1;
 
@@ -122,7 +123,9 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 
 	private void dropMaterialIfPossible() {
 		EMaterialType stolenMaterial = setMaterial(EMaterialType.NO_MATERIAL);
-		grid.dropMaterial(position, stolenMaterial, true, true);
+		if (stolenMaterial != EMaterialType.NO_MATERIAL) { // otherwise a log of wood (material 0) would appear
+			grid.dropMaterial(position, stolenMaterial, true, true);
+		}
 	}
 
 	protected static Node<ThiefMovable> stealMaterial() {
@@ -158,6 +161,15 @@ public class ThiefMovable extends AttackableHumanMovable implements IGraphicsThi
 		uncoveredBy.clear();
 	}
 
+	@Override
+	public boolean convertToBearer() {
+		if (!player.equals(grid.getPlayerAt(position))) return false;
+
+		createMovable(EMovableType.BEARER, player, position, grid, this);
+
+		return true;
+	}
+
 	@Override
 	protected void decoupleMovable() {
 		super.decoupleMovable();
PATCH_EOF
cat > "$WORK/patches/21-faster-growth.patch" <<'PATCH_EOF'
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
index 8963ce1e7..1cd802187 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/SimpleBuildingWorkerMovable.java
@@ -290,7 +290,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 							)
 						),
 						enterHome(),
-						sleep(8000)
+						sleep(2000)
 					)
 				)
 		);
@@ -367,7 +367,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 							)
 						),
 						enterHome(),
-						sleep(8000)
+						sleep(2000)
 					)
 				)
 		);
@@ -619,7 +619,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 							)
 						),
 						enterHome(),
-						sleep(8000)
+						sleep(2000)
 					)
 				)
 		);
@@ -679,7 +679,7 @@ public class SimpleBuildingWorkerMovable extends BuildingWorkerMovable {
 							)
 						),
 						enterHome(),
-						sleep(8000)
+						sleep(2000)
 					)
 				)
 		);
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/objects/HiveObject.java b/jsettlers.logic/src/main/java/jsettlers/logic/objects/HiveObject.java
index 4930e8552..8fabd89ef 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/objects/HiveObject.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/objects/HiveObject.java
@@ -33,8 +33,8 @@ import jsettlers.logic.map.grid.objects.MapObjectsManager;
 public final class HiveObject extends ProgressingSoundableObject {
 	private static final long serialVersionUID = -8416528218446090558L;
 
-	private static final int[] EMPTY_DURATION_BOUNDS = {90, 180};
-	private static final int[] GROWTH_DURATION_BOUNDS = {110, 180};
+	private static final int[] EMPTY_DURATION_BOUNDS = {60, 120};
+	private static final int[] GROWTH_DURATION_BOUNDS = {75, 120};
 	//private static final int[] BEE_ANIMATION_BOUNDS = {0, 5};
 
 	private EMapObjectType state;
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Corn.java b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Corn.java
index bc2eacf7a..00284a064 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Corn.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Corn.java
@@ -31,7 +31,7 @@ import jsettlers.logic.map.grid.objects.MapObjectsManager;
 public final class Corn extends GrowingObject {
 	private static final long serialVersionUID = -7535441306083940418L;
 
-	public static final float GROWTH_DURATION = 10 * 60;
+	public static final float GROWTH_DURATION = 7 * 60; // faster than the original (10 * 60)
 	public static final float DECOMPOSE_DURATION = 3 * 60;
 	public static final float REMOVE_DURATION = 2 * 60;
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Rice.java b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Rice.java
index 9568d5877..a75c87984 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Rice.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Rice.java
@@ -29,7 +29,7 @@ import jsettlers.logic.map.grid.objects.MapObjectsManager;
 public final class Rice extends GrowingObject {
 	private static final long serialVersionUID = 8086261556083213266L;
 
-	public static final float GROWTH_DURATION = 11 * 60;
+	public static final float GROWTH_DURATION = 7 * 60; // faster than the original (11 * 60)
 	public static final float DECOMPOSE_DURATION = 3 * 60;
 	public static final float REMOVE_DURATION = 2 * 60;
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Wine.java b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Wine.java
index 2dba94b0c..9e82fee3f 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Wine.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Wine.java
@@ -29,7 +29,7 @@ import jsettlers.logic.map.grid.objects.MapObjectsManager;
 public final class Wine extends GrowingObject {
 	private static final long serialVersionUID = -7535441306083940418L;
 
-	public static final float GROWTH_DURATION = 9 * 60;
+	public static final float GROWTH_DURATION = 6 * 60; // faster than the original (9 * 60)
 	public static final float DECOMPOSE_DURATION = 3 * 60;
 	public static final float REMOVE_DURATION = 2 * 60;
 
PATCH_EOF
cat > "$WORK/patches/22-settler-messages-and-tool-demand.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
index 0fb7a759a..c31d09956 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
@@ -175,6 +175,17 @@ public class SimpleMessage implements IMessage {
 		return new SimpleMessage(EMessageType.NO_FREE_BEARER, "no_free_bearer|" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
 	}
 
+	/**
+	 * Create a new message that a barrack cannot arm soldiers because there is no free settler who could become a soldier.
+	 *
+	 * @param building
+	 * 		The barrack
+	 * @return The message object
+	 */
+	public static IMessage noFreeSettlerForSoldiers(IBuilding building) {
+		return new SimpleMessage(EMessageType.NO_FREE_BEARER, "no_free_bearer_soldier|" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
+	}
+
 	/**
 	 *
 	 * @param at
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 3aaa34bf2..6333ecca8 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -505,6 +505,9 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 		} else if (label.startsWith("no_free_bearer|")) {
 			String[] parts = label.split("\\|");
 			return Labels.getString("message_no_free_bearer", buildingNameOf(parts[1]));
+		} else if (label.startsWith("no_free_bearer_soldier|")) {
+			String[] parts = label.split("\\|");
+			return Labels.getString("message_no_free_bearer_soldier", buildingNameOf(parts[1]));
 		} else if (label.startsWith("cannot_find_work_")) {
 			return buildingNameOf(label.substring("cannot_find_work_".length())) + ": no work found in its work area.";
 		} else if (label.startsWith("no_soldier_available_")) {
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index be81af342..c65076796 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -379,7 +379,8 @@ no_soldier_available_TOWER = Vaši strážní věž nelze obsadit: není k dispo
 no_soldier_available_BIG_TOWER = Vaši velkou strážní věž nelze obsadit: není k dispozici žádný voják.
 no_soldier_available_CASTLE = Váš hrad nelze obsadit: není k dispozici žádný voják.
 message_missing_tool = %s nelze obsadit: chybí nástroj (%s).
-message_no_free_bearer = %s nelze obsadit: není k dispozici žádný volný nosič.
+message_no_free_bearer = %s nelze obsadit: není k dispozici žádný volný osadník.
+message_no_free_bearer_soldier = %s nemůže zbrojit: není k dispozici žádný volný osadník.
 action_firerer_slow = Pozor! Hra reaguje pomalu.
 
 # progress display
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index e63454ac7..ba8046ff8 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -385,7 +385,8 @@ no_soldier_available_TOWER = Your guard tower can't be occupied: no soldier is a
 no_soldier_available_BIG_TOWER = Your large guard tower can't be occupied: no soldier is available.
 no_soldier_available_CASTLE = Your castle can't be occupied: no soldier is available.
 message_missing_tool = %s can't be occupied: tool missing (%s).
-message_no_free_bearer = %s can't be occupied: no free carrier is available.
+message_no_free_bearer = %s can't be occupied: no free settler is available.
+message_no_free_bearer_soldier = %s can't arm soldiers: no free settler is available.
 action_firerer_slow = Warning! The game is responding slowly.
 
 # progress display
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/Barrack.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/Barrack.java
index ee2287608..7045270c8 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/Barrack.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/Barrack.java
@@ -17,6 +17,7 @@ package jsettlers.logic.buildings.military;
 import jsettlers.common.buildings.EBuildingType;
 import jsettlers.common.mapobject.EMapObjectType;
 import jsettlers.common.material.EMaterialType;
+import jsettlers.common.menu.messages.SimpleMessage;
 import jsettlers.common.movable.EMovableType;
 import jsettlers.common.movable.ESoldierType;
 import jsettlers.common.position.ShortPoint2D;
@@ -25,6 +26,7 @@ import jsettlers.logic.buildings.WorkAreaBuilding;
 import jsettlers.logic.buildings.stack.IRequestStack;
 import jsettlers.logic.buildings.stack.IRequestStackListener;
 import jsettlers.logic.buildings.stack.RequestStack;
+import jsettlers.logic.constants.MatchConstants;
 import jsettlers.logic.map.grid.partition.manager.manageables.interfaces.IBarrack;
 import jsettlers.logic.player.Player;
 
@@ -77,6 +79,27 @@ public final class Barrack extends WorkAreaBuilding implements IBarrack, IReques
 		}
 	}
 
+	private static final int WARNING_DELAY = 10 * 1000;
+	private static final int WARNING_REPEAT = 120 * 1000;
+	private int nextWarningTime = 0;
+
+	@Override
+	public void warnNoFreeSettler() {
+		int now = MatchConstants.clock().getTime();
+		if (nextWarningTime == 0) {
+			nextWarningTime = now + WARNING_DELAY;
+		}
+		if (now >= nextWarningTime) {
+			nextWarningTime = now + WARNING_REPEAT;
+			getPlayer().showMessage(SimpleMessage.noFreeSettlerForSoldiers(this));
+		}
+	}
+
+	@Override
+	public void clearNoFreeSettlerWarning() {
+		nextWarningTime = 0;
+	}
+
 	@Override
 	public void bearerRequestFailed() {
 		super.grid.requestSoldierable(this);
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
index 3b73e13d5..4a35703a3 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
@@ -189,6 +189,9 @@ public class OccupyingBuilding extends Building implements IBuilding.IOccupied,
 	 * Tells the player when this building has been waiting for its first soldier for a long time (nobody in reach to occupy it).
 	 */
 	private void warnIfNoSoldierAvailable() {
+		if (isDestroyed()) {
+			return;
+		}
 		if (sortedOccupiers.isEmpty() && comingSoldiers.isEmpty() && !searchedSoldiers.isEmpty()) {
 			unoccupiedTicks++;
 			if (unoccupiedTicks == NO_SOLDIER_WARNING_TICKS
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
index fd332444d..041fcd03b 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java
@@ -293,6 +293,9 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 
 	private void handleWorkerRequest() {
 		WorkerRequest workerRequest = workerRequests.poll();
+		if (workerRequest != null && !workerRequest.isRequestAlive()) {
+			return; // the building does not exist any more: forget the request
+		}
 		if (workerRequest != null) {
 			IManageableWorker worker = joblessWorkers.removeObjectNextTo(workerRequest.getPosition(), currentWorker -> currentWorker.getMovableType() == workerRequest.movableType);
 
@@ -315,10 +318,15 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 	private void handleWorkerCreationRequests() {
 		Iterator<WorkerCreationRequest> iterator = workerCreationRequests.iterator();
 
-		if (joblessBearer.isEmpty()) {
-			// every new worker needs a free carrier, tell the player if one is missing for a building
-			for (WorkerCreationRequest request : workerCreationRequests) {
-				if (request instanceof WorkerRequest && request.isRequestAlive()) {
+		// Every new worker needs a free settler (carrier). Carriers that are reserved by the minimum carrier setting must not be converted.
+		boolean carriersReserved = settings.getProfessionSettings().getSettings(EMovableType.BEARER).getRemainingAmount() > -1;
+		if (joblessBearer.isEmpty() || carriersReserved) {
+			// tell the player if a settler is missing for a building
+			while (iterator.hasNext()) {
+				WorkerCreationRequest request = iterator.next();
+				if (!request.isRequestAlive()) {
+					iterator.remove();
+				} else if (request instanceof WorkerRequest) {
 					WorkerRequest workerRequest = (WorkerRequest) request;
 					workerRequest.warnPlayer(SimpleMessage.noFreeBearer(workerRequest.building));
 				}
@@ -381,14 +389,36 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 
 	private void handleSoldierCreationRequest() {
 		SoldierCreationRequest soilderRequest = soldierCreationRequests.poll();
+		if (soilderRequest != null && soilderRequest.getBarrack().isDestroyed()) {
+			return; // the barrack does not exist any more: forget the request, so there are no more messages about it
+		}
 		if (soilderRequest != null) {
-			IManageableBearer manageableBearer = joblessBearer.removeObjectNextTo(soilderRequest.getPosition());
-			if (manageableBearer == null || !manageableBearer.becomeSoldier(soilderRequest.getBarrack())) {
+			// Soldiers may only be armed from free settlers: carriers that are reserved by the minimum carrier setting must stay carriers.
+			boolean carriersReserved = settings.getProfessionSettings().getSettings(EMovableType.BEARER).getRemainingAmount() > -1;
+			IManageableBearer manageableBearer = carriersReserved ? null : joblessBearer.removeObjectNextTo(soilderRequest.getPosition());
+			if (manageableBearer == null) {
+				// weapons are waiting, but there is no free settler who could take them
+				soilderRequest.getBarrack().warnNoFreeSettler();
 				soldierCreationRequests.addLast(soilderRequest);
+			} else if (!manageableBearer.becomeSoldier(this, soilderRequest.getBarrack())) {
+				soldierCreationRequests.addLast(soilderRequest);
+			} else {
+				settings.getProfessionSettings().markTempBearerConversion(EMovableType.SWORDSMAN_L1);
+				soilderRequest.getBarrack().clearNoFreeSettlerWarning();
 			}
 		}
 	}
 
+	@Override
+	public void soldierCreationFulfilled() {
+		settings.getProfessionSettings().applyBearerConversion(EMovableType.SWORDSMAN_L1);
+	}
+
+	@Override
+	public void soldierCreationFailed() {
+		settings.getProfessionSettings().abortBearerConversion(EMovableType.SWORDSMAN_L1);
+	}
+
 	private void handleDiggerRequest() {
 		DiggerRequest request = diggerRequests.peek();
 		if (request == null) {
@@ -463,6 +493,37 @@ public abstract class PartitionManager implements IScheduledTimerable, Serializa
 			}
 		}
 
+		if (bestTool == null) {
+			bestTool = popToolForProfessionSettings();
+		}
+
+		return bestTool;
+	}
+
+	/**
+	 * Tools of diggers and bricklayers that are missing to reach the numbers set in the settlers' profession settings. This keeps the tool smithy
+	 * working when the player raises these numbers later in the game, even if no request is waiting for a tool at that moment.
+	 *
+	 * @return The tool that should be produced or <code>null</code> if no tool is missing.
+	 */
+	private EMaterialType popToolForProfessionSettings() {
+		ProfessionSettings professionSettings = settings.getProfessionSettings();
+		int spareBearers = (int) Math.floor(-professionSettings.getSettings(EMovableType.BEARER).getRemainingAmount());
+		if (spareBearers < 1) {
+			return null; // no carrier could be converted anyway
+		}
+
+		EMaterialType bestTool = null;
+		int bestMissing = 0;
+		for (EMovableType type : new EMovableType[] { EMovableType.DIGGER, EMovableType.BRICKLAYER }) {
+			EMaterialType tool = type.getTool();
+			int wanted = Math.min((int) Math.floor(professionSettings.getSettings(type).getRemainingAmount()), spareBearers);
+			int missing = wanted - materialOffers.getMaterialCounts().getAmountOf(tool);
+			if (missing > bestMissing) {
+				bestMissing = missing;
+				bestTool = tool;
+			}
+		}
 		return bestTool;
 	}
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/IManageableBearer.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/IManageableBearer.java
index 05b6fd0d1..b875c3158 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/IManageableBearer.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/IManageableBearer.java
@@ -29,7 +29,7 @@ public interface IManageableBearer extends IManageable, ILocatable, IManagerBear
 
 	boolean becomeWorker(IWorkerRequester requester, WorkerCreationRequest request, IMaterialOffer offer);
 
-	boolean becomeSoldier(IBarrack barrack);
+	boolean becomeSoldier(IWorkerRequester requester, IBarrack barrack);
 
 	/**
 	 * This interface is used by the bearers to signal the need of a reoffer of the worker creation request.
@@ -40,5 +40,15 @@ public interface IManageableBearer extends IManageable, ILocatable, IManagerBear
 		void workerCreationRequestFailed(WorkerCreationRequest failedRequest);
 
 		void workerCreationRequestFulfilled(WorkerCreationRequest fulfilledRequest);
+
+		/**
+		 * Called when a bearer, who was sent to a barrack, has become a soldier.
+		 */
+		void soldierCreationFulfilled();
+
+		/**
+		 * Called when a bearer, who was sent to a barrack, could not become a soldier.
+		 */
+		void soldierCreationFailed();
 	}
 }
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IBarrack.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IBarrack.java
index ffefc09c4..8721f637f 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IBarrack.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/manageables/interfaces/IBarrack.java
@@ -49,4 +49,20 @@ public interface IBarrack extends ILocatable {
 	 * @return Returns the position where the newly created soldier should walk.
 	 */
 	ShortPoint2D getSoldierTargetPosition();
+
+	/**
+	 * Tells the player that weapons are waiting in this barrack but no free settler is available to become a soldier. The message is delayed and
+	 * repeated from time to time while the situation lasts.
+	 */
+	void warnNoFreeSettler();
+
+	/**
+	 * Called when a free settler has been found, so the next shortage is announced again after the usual delay.
+	 */
+	void clearNoFreeSettlerWarning();
+
+	/**
+	 * @return True if the barrack does not exist any more (it was destroyed or conquered). Requests of such a barrack are dropped.
+	 */
+	boolean isDestroyed();
 }
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BearerMovable.java b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BearerMovable.java
index 836b7a918..ebc3d4a9e 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BearerMovable.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BearerMovable.java
@@ -38,6 +38,7 @@ public class BearerMovable extends CivilianMovable implements IBearerMovable, IM
 	private IBarrack              barrack;
 	private IManageableBearer.IWorkerRequester workerRequester;
 	private WorkerCreationRequest workerCreationRequest;
+	private IManageableBearer.IWorkerRequester soldierRequester;
 
 	private boolean registered = false;
 
@@ -104,6 +105,8 @@ public class BearerMovable extends CivilianMovable implements IBearerMovable, IM
 
 								ShortPoint2D targetPosition = mov.barrack.getSoldierTargetPosition();
 								mov.barrack = null;
+								mov.soldierRequester.soldierCreationFulfilled();
+								mov.soldierRequester = null;
 
 
 								mov.player.getEndgameStatistic().incrementAmountOfProducedSoldiers();
@@ -162,6 +165,7 @@ public class BearerMovable extends CivilianMovable implements IBearerMovable, IM
 						mov.offer = null;
 						mov.request = null;
 						mov.barrack = null;
+						mov.soldierRequester = null;
 						mov.materialType = null;
 						mov.workerRequester = null;
 						mov.workerCreationRequest = null;
@@ -240,6 +244,10 @@ public class BearerMovable extends CivilianMovable implements IBearerMovable, IM
 		}
 
 		if(barrack != null) {
+			if(soldierRequester != null) {
+				soldierRequester.soldierCreationFailed();
+				soldierRequester = null;
+			}
 			barrack.bearerRequestFailed();
 			barrack = null;
 		}
@@ -274,9 +282,10 @@ public class BearerMovable extends CivilianMovable implements IBearerMovable, IM
 	}
 
 	@Override
-	public boolean becomeSoldier(IBarrack barrack) {
+	public boolean becomeSoldier(IManageableBearer.IWorkerRequester requester, IBarrack barrack) {
 		if(!registered) return false;
 
+		this.soldierRequester = requester;
 		this.barrack = barrack;
 		registered = false;
 		return true;
PATCH_EOF
cat > "$WORK/patches/23-lobby-colors-and-positions.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java b/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
index bde71ea79..063e0efe9 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
@@ -63,6 +63,12 @@ public interface IJoinPhaseMultiplayerGameConnector {
 
 	void setTeam(byte slot, byte team);
 
+	/**
+	 * Sets the color of a slot (index of the color table, see {@link jsettlers.common.player.PlayerColors}).
+	 */
+	default void setColor(byte slot, byte color) {
+	}
+
 	void setPlayerCount(int playerCount);
 
 	/**
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/IMultiplayerSlot.java b/jsettlers.common/src/main/java/jsettlers/common/menu/IMultiplayerSlot.java
index 6bede4976..2a9a7d77c 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/IMultiplayerSlot.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/IMultiplayerSlot.java
@@ -13,4 +13,11 @@ public interface IMultiplayerSlot {
 	byte getTeam();
 
 	byte getPosition();
+
+	/**
+	 * @return The index of the color chosen for this slot (see {@link jsettlers.common.player.PlayerColors}).
+	 */
+	default byte getColor() {
+		return getPosition();
+	}
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java b/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java
new file mode 100644
index 000000000..f887f45d1
--- /dev/null
+++ b/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java
@@ -0,0 +1,59 @@
+package jsettlers.common.player;
+
+/**
+ * Holds the colors the players have chosen for the game that is running or starting. A color is the index of an entry of the player color
+ * table of the graphics. Without a choice, the color of a player is given by his player id (the position on the map).
+ */
+public final class PlayerColors {
+
+	/** Number of colors a player can choose from (the colors of the original game). */
+	public static final int SELECTABLE_COLORS = 20;
+
+	private static volatile byte[] colorIndexByPlayerId = null;
+
+	private PlayerColors() {
+	}
+
+	/**
+	 * Sets the colors for the next game.
+	 *
+	 * @param colorIndexByPlayerId
+	 * 		The index of the color for every player id (position on the map) or <code>null</code> for the default colors.
+	 */
+	public static void set(byte[] colorIndexByPlayerId) {
+		PlayerColors.colorIndexByPlayerId = colorIndexByPlayerId == null ? null : colorIndexByPlayerId.clone();
+	}
+
+	private static volatile byte[] preparedColors = null;
+
+	/**
+	 * Prepares the colors of the game that is started next. They become active when the game object is created ({@link #applyPrepared()}).
+	 * Games that are started without preparing colors (saved games, replays) use the default colors.
+	 */
+	public static void prepareNextGame(byte[] colorIndexByPlayerId) {
+		preparedColors = colorIndexByPlayerId == null ? null : colorIndexByPlayerId.clone();
+	}
+
+	/**
+	 * Makes the prepared colors the colors of the running game.
+	 */
+	public static void applyPrepared() {
+		set(preparedColors);
+		preparedColors = null;
+	}
+
+	public static void reset() {
+		colorIndexByPlayerId = null;
+	}
+
+	/**
+	 * @return The index of the color of the given player.
+	 */
+	public static int getColorIndex(byte playerId) {
+		byte[] colors = colorIndexByPlayerId;
+		if (colors != null && playerId >= 0 && playerId < colors.length) {
+			return colors[playerId];
+		}
+		return playerId;
+	}
+}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapDrawContext.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapDrawContext.java
index 29c237ac0..3674dcf51 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapDrawContext.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapDrawContext.java
@@ -242,7 +242,18 @@ public final class MapDrawContext implements IGLProvider {
 	}
 
 	/**
-	 * Gets the color for a given player.
+	 * Gets an entry of the player color table.
+	 *
+	 * @param colorIndex
+	 *            The index of the color.
+	 * @return The color.
+	 */
+	public static Color getSelectableColor(int colorIndex) {
+		return PLAYER_COLORS[Math.abs(colorIndex) % PLAYER_COLORS.length];
+	}
+
+	/**
+	 * Gets the color for a given player, taking the colors chosen in the lobby into account.
 	 *
 	 * @param player
 	 *            The player to get the color for.
@@ -250,7 +261,7 @@ public final class MapDrawContext implements IGLProvider {
 	 */
 	public static Color getPlayerColor(byte player) {
 		if (player >= 0) {
-			return PLAYER_COLORS[player % PLAYER_COLORS.length];
+			return PLAYER_COLORS[Math.abs(jsettlers.common.player.PlayerColors.getColorIndex(player)) % PLAYER_COLORS.length];
 		} else {
 			return Color.BLACK;
 		}
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index c65076796..9b240e8b8 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -562,6 +562,7 @@ join-game-panel-civilisation = Národ
 join-game-panel-player-type = Typ
 join-game-panel-map-slot = Pozice
 join-game-panel-team = Tým
+join-game-panel-color = Barva
 join-game-panel-send-chat-message = Odeslat
 
 stats-panel-exit = Další
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index ba8046ff8..5587dd15b 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -568,6 +568,7 @@ join-game-panel-civilisation = Civilisation
 join-game-panel-player-type = Type
 join-game-panel-map-slot = Position
 join-game-panel-team = Team
+join-game-panel-color = Color
 join-game-panel-send-chat-message = Send
 
 stats-panel-exit = Next
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
index ae5133d7f..f856bfc11 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
@@ -100,6 +100,7 @@ public class JSettlersGame {
 			boolean controlAll, boolean multiplayer, DataInputStream replayFileInputStream) {
 		configureLogging(mapCreator);
 
+		jsettlers.common.player.PlayerColors.applyPrepared();
 		this.initialGameState = initialGameState;
 
 		System.out.println("OS version: " + System.getProperty("os.name") + " " + System.getProperty("os.arch") + " "
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
index 495109732..57672463b 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
@@ -135,6 +135,7 @@ public class MultiplayerGame {
 			MapLoader mapLoader = MapList.getDefaultList().getMapById(packet.getMatchInfo().getMapInfo().getId());
 			long randomSeed = packet.getRandomSeed();
 			PlayerSetting[] playerSettings = determinePlayerSettings();
+			jsettlers.common.player.PlayerColors.prepareNextGame(determinePlayerColors());
 			byte ownPlayerId = calculateOwnPlayerId();
 			// TODO start resources
 			InitialGameState initialGameState = new InitialGameState(ownPlayerId, playerSettings, randomSeed);
@@ -160,6 +161,19 @@ public class MultiplayerGame {
 		return IntStream.range(0, maxPlayers).mapToObj(i -> playerSettings.computeIfAbsent((byte) i, v -> new PlayerSetting())).toArray(PlayerSetting[]::new);
 	}
 
+	private byte[] determinePlayerColors() {
+		byte[] colors = new byte[Math.max(maxPlayers, 1)];
+		for (int i = 0; i < colors.length; i++) {
+			colors[i] = (byte) i;
+		}
+		for (IMultiplayerSlot slot : slotList.getItems()) {
+			if (slot.getPosition() >= 0 && slot.getPosition() < colors.length) {
+				colors[slot.getPosition()] = slot.getColor();
+			}
+		}
+		return colors;
+	}
+
 	private static String playerNameOf(IMultiplayerSlot slot) {
 		return slot.getPlayer() != null ? slot.getPlayer().getName() : null;
 	}
@@ -272,6 +286,11 @@ public class MultiplayerGame {
 				networkClient.setTeam(slot, team);
 			}
 
+			@Override
+			public void setColor(byte slot, byte color) {
+				networkClient.setColor(slot, color);
+			}
+
 			@Override
 			public void setType(byte slot, EPlayerType playerType) {
 				networkClient.setType(slot, (byte) playerType.ordinal());
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/datatypes/MultiplayerSlot.java b/jsettlers.logic/src/main/java/jsettlers/main/datatypes/MultiplayerSlot.java
index ec9b152f9..abab75a71 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/datatypes/MultiplayerSlot.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/datatypes/MultiplayerSlot.java
@@ -13,6 +13,7 @@ public class MultiplayerSlot implements IMultiplayerSlot {
 	private final ECivilisation civilisation;
 	private final byte team;
 	private final byte position;
+	private final byte color;
 
 
 	public MultiplayerSlot(SlotInfoPacket packet) {
@@ -23,6 +24,7 @@ public class MultiplayerSlot implements IMultiplayerSlot {
 		this.player = player;
 		this.team = packet.getTeam();
 		this.position = packet.getPosition();
+		this.color = packet.getColor();
 		this.civilisation = getCivilisation(packet.getCivilisation());
 		this.type = getPlayerType(packet.getPlayerType());
 	}
@@ -67,4 +69,9 @@ public class MultiplayerSlot implements IMultiplayerSlot {
 	public byte getPosition() {
 		return position;
 	}
+
+	@Override
+	public byte getColor() {
+		return color;
+	}
 }
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 7047f90a0..748d105ff 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -14,7 +14,14 @@
  *******************************************************************************/
 package jsettlers.main.swing.menu.joinpanel;
 
+import java.awt.BasicStroke;
 import java.awt.BorderLayout;
+import java.awt.Color;
+import java.awt.Font;
+import java.awt.FontMetrics;
+import java.awt.Graphics2D;
+import java.awt.RenderingHints;
+import java.awt.image.BufferedImage;
 import java.awt.FlowLayout;
 import java.awt.GridBagConstraints;
 import java.awt.GridBagLayout;
@@ -50,10 +57,15 @@ import jsettlers.common.menu.IMultiplayerListener;
 import jsettlers.common.menu.IMultiplayerPlayer;
 import jsettlers.common.menu.IMultiplayerSlot;
 import jsettlers.common.menu.IStartingGame;
+import jsettlers.common.player.PlayerColors;
 import jsettlers.common.utils.collections.ChangingList;
 import jsettlers.graphics.localization.Labels;
 import jsettlers.logic.map.loading.EMapStartResources;
+import jsettlers.graphics.map.MapDrawContext;
 import jsettlers.logic.map.loading.MapLoader;
+import jsettlers.logic.map.loading.data.IMapData;
+import jsettlers.logic.map.loading.newmap.MapFileHeader;
+import jsettlers.common.position.ShortPoint2D;
 import jsettlers.logic.player.InitialGameState;
 import jsettlers.logic.player.PlayerSetting;
 import jsettlers.main.JSettlersGame;
@@ -108,12 +120,18 @@ public class JoinGamePanel extends BackgroundPanel {
 	private final JLabel slotsHeadlineType = new JLabel();
 	private final JLabel slotsHeadlineMapSlot = new JLabel();
 	private final JLabel slotsHeadlineTeam = new JLabel();
+	private final JLabel slotsHeadlineColor = new JLabel();
 	private final JTextField chatInputField = new JTextField();
 	private final JTextArea chatArea = new JTextArea();
 	private final JButton sendChatMessageButton = new JButton();
 	private MapLoader mapLoader;
 	private final List<PlayerSlot> playerSlots = new ArrayList<>();
 	private IPlayerSlotFactory playerSlotFactory;
+	/** The preview image of the map without any decoration. */
+	private BufferedImage previewBase;
+	/** Positions of the start points in the preview image (index = position on the map), <code>null</code> as long as they are unknown. */
+	private int[][] previewStartPoints;
+	private Thread previewStartPointsThread;
 
 	public JoinGamePanel(JSettlersFrame settlersFrame) {
 		this.settlersFrame = settlersFrame;
@@ -190,6 +208,7 @@ public class JoinGamePanel extends BackgroundPanel {
 		slotsHeadlineType.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_DYNAMIC);
 		slotsHeadlineMapSlot.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_DYNAMIC);
 		slotsHeadlineTeam.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_DYNAMIC);
+		slotsHeadlineColor.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_DYNAMIC);
 		sendChatMessageButton.putClientProperty(ELFStyle.KEY, ELFStyle.BUTTON_MENU);
 		chatInputField.putClientProperty(ELFStyle.KEY, ELFStyle.TEXT_DEFAULT);
 		chatArea.putClientProperty(ELFStyle.KEY, ELFStyle.PANEL_DARK);
@@ -211,6 +230,7 @@ public class JoinGamePanel extends BackgroundPanel {
 		slotsHeadlineType.setText(Labels.getString("join-game-panel-player-type"));
 		slotsHeadlineMapSlot.setText(Labels.getString("join-game-panel-map-slot"));
 		slotsHeadlineTeam.setText(Labels.getString("join-game-panel-team"));
+		slotsHeadlineColor.setText(Labels.getString("join-game-panel-color"));
 		sendChatMessageButton.setText(Labels.getString("join-game-panel-send-chat-message"));
 	}
 
@@ -236,6 +256,8 @@ public class JoinGamePanel extends BackgroundPanel {
 					})
 					.toArray(PlayerSetting[]::new);
 
+			waitForPreviewStartPoints();
+			PlayerColors.prepareNextGame(determinePlayerColors());
 			MapStartResourcesUIWrapper selected = (MapStartResourcesUIWrapper) startResourcesComboBox.getSelectedItem();
 			InitialGameState initialGameState = new InitialGameState(playerSlots.get(0).getSlot(), playerSettings, randomSeed, selected.getStartResources());
 			applySelectedPeaceTime();
@@ -272,6 +294,7 @@ public class JoinGamePanel extends BackgroundPanel {
 					initializeChatFor(connector);
 					setStartButtonActionListener(e -> {
 						applySelectedPeaceTime();
+						waitForPreviewStartPoints();
 						connector.startGame();
 					});
 					connector.getSlots().setListener(changingSlots -> onSlotsChanged(changingSlots, connector, myId, true));
@@ -374,6 +397,7 @@ public class JoinGamePanel extends BackgroundPanel {
 				IMultiplayerSlot remoteSlot = slots.next();
 				playerSlot.setCivilisation(remoteSlot.getCivilisation(), false);
 				playerSlot.setTeam(remoteSlot.getTeam(), false);
+				playerSlot.setColor(remoteSlot.getColor(), false);
 				playerSlot.setSlot(remoteSlot.getPosition(), false);
 				IMultiplayerPlayer player = remoteSlot.getPlayer();
 				playerSlot.setPlayerType(remoteSlot.getType(), false);
@@ -414,7 +438,9 @@ public class JoinGamePanel extends BackgroundPanel {
 	private void prepareUiFor(MapLoader mapLoader) {
 		this.mapLoader = mapLoader;
 		mapNameLabel.setText(mapLoader.getMapName());
-		mapImage.setIcon(new ImageIcon(JSettlersSwingUtil.createBufferedImageFrom(mapLoader)));
+		previewBase = JSettlersSwingUtil.createBufferedImageFrom(mapLoader);
+		previewStartPoints = null;
+		mapImage.setIcon(new ImageIcon(previewBase));
 		peaceTimeComboBox.removeAllItems();
 		for (EPeaceTime peaceTime : EPeaceTime.values()) {
 			peaceTimeComboBox.addItem(peaceTime);
@@ -428,6 +454,119 @@ public class JoinGamePanel extends BackgroundPanel {
 		numberOfPlayersComboBox.reset(mapLoader.getMaxPlayers());
 		buildPlayerSlots();
 		updateNumberOfPlayerSlots(mapLoader.getMaxPlayers());
+		loadPreviewStartPoints(mapLoader);
+	}
+
+	/**
+	 * Determines the color of every player id (position on the map) from the color selection of the slots.
+	 */
+	private byte[] determinePlayerColors() {
+		byte[] colors = new byte[Math.max(mapLoader.getMaxPlayers(), 1)];
+		for (int i = 0; i < colors.length; i++) {
+			colors[i] = (byte) i;
+		}
+		for (PlayerSlot playerSlot : playerSlots) {
+			if (playerSlot.isAvailable() && playerSlot.getSlot() >= 0 && playerSlot.getSlot() < colors.length) {
+				colors[playerSlot.getSlot()] = playerSlot.getColor();
+			}
+		}
+		return colors;
+	}
+
+	/**
+	 * Reads the start points of the map in the background to show the numbers of the map slots in the preview image.
+	 */
+	private void loadPreviewStartPoints(MapLoader loader) {
+		Thread thread = new Thread(() -> {
+			try {
+				IMapData mapData = loader.getMapData();
+				int maxPlayers = loader.getMaxPlayers();
+				int size = MapFileHeader.PREVIEW_IMAGE_SIZE;
+				int[][] points = new int[maxPlayers][];
+				for (int i = 0; i < maxPlayers; i++) {
+					ShortPoint2D start = mapData.getStartPoint(i);
+					if (start == null) {
+						continue;
+					}
+					int px = Math.min(Math.max((int) ((double) start.x / mapData.getWidth() * size), 0), size - 1);
+					int py = Math.min(Math.max((int) ((double) start.y / mapData.getHeight() * size), 0), size - 1);
+					// same skew as JSettlersSwingUtil.createBufferedImageFrom()
+					int xOffset = Math.max(size - 1 - (py + 1) / 2, 1);
+					points[i] = new int[] { px + xOffset, py };
+				}
+				SwingUtilities.invokeLater(() -> {
+					if (mapLoader == loader) {
+						previewStartPoints = points;
+						refreshPreview();
+					}
+				});
+			} catch (Throwable t) {
+				// no numbers in the preview: maps that can't supply their start points (saved games)
+			}
+		}, "previewStartPoints");
+		thread.setDaemon(true);
+		previewStartPointsThread = thread;
+		thread.start();
+	}
+
+	/**
+	 * The start points are read with the same map loader that is used to start the game, so wait until the reading is finished.
+	 */
+	private void waitForPreviewStartPoints() {
+		Thread thread = previewStartPointsThread;
+		if (thread != null && thread.isAlive()) {
+			try {
+				thread.join(10000);
+			} catch (InterruptedException e) {
+				Thread.currentThread().interrupt();
+			}
+		}
+	}
+
+	/**
+	 * Draws the numbers of the map slots at the start points into the preview image, in the color chosen for the player of the slot.
+	 */
+	private void refreshPreview() {
+		if (previewBase == null) {
+			return;
+		}
+		int[][] points = previewStartPoints;
+		if (points == null) {
+			return;
+		}
+		BufferedImage image = new BufferedImage(previewBase.getWidth(), previewBase.getHeight(), BufferedImage.TYPE_INT_ARGB);
+		Graphics2D g = image.createGraphics();
+		g.drawImage(previewBase, 0, 0, null);
+		g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
+		g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
+		g.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 11));
+		FontMetrics metrics = g.getFontMetrics();
+		int radius = 8;
+
+		for (PlayerSlot playerSlot : playerSlots) {
+			if (!playerSlot.isAvailable()) {
+				continue;
+			}
+			int position = playerSlot.getSlot();
+			if (position < 0 || position >= points.length || points[position] == null) {
+				continue;
+			}
+			int cx = points[position][0];
+			int cy = points[position][1];
+			jsettlers.common.Color color = MapDrawContext.getSelectableColor(playerSlot.getColor());
+			g.setColor(new Color(color.getRed(), color.getGreen(), color.getBlue()));
+			g.fillOval(cx - radius, cy - radius, 2 * radius, 2 * radius);
+			g.setColor(Color.WHITE);
+			g.setStroke(new BasicStroke(1.5f));
+			g.drawOval(cx - radius, cy - radius, 2 * radius, 2 * radius);
+
+			String text = String.valueOf(position + 1);
+			double brightness = 0.299 * color.getRed() + 0.587 * color.getGreen() + 0.114 * color.getBlue();
+			g.setColor(brightness > 0.6 ? Color.BLACK : Color.WHITE);
+			g.drawString(text, cx - metrics.stringWidth(text) / 2, cy + (metrics.getAscent() - metrics.getDescent()) / 2);
+		}
+		g.dispose();
+		mapImage.setIcon(new ImageIcon(image));
 	}
 
 	private void buildPlayerSlots() {
@@ -444,6 +583,8 @@ public class JoinGamePanel extends BackgroundPanel {
 			PlayerSetting playerSetting = playerSettings[i];
 
 			playerSlot.setSlot(i, true);
+			playerSlot.setColor(i, true);
+			playerSlot.setPreviewListener(this::refreshPreview);
 
 			if (playerSetting.getTeamId() != null) {
 				playerSlot.setTeam(playerSetting.getTeamId(), true);
@@ -492,6 +633,7 @@ public class JoinGamePanel extends BackgroundPanel {
 		SwingUtilities.updateComponentTreeUI(playerSlotsPanel);
 		SlotToggleGroup slotToggleGroup = new SlotToggleGroup();
 		playerSlots.forEach(slotToggleGroup::add);
+		refreshPreview();
 	}
 
 	private void addPlayerSlotHeadline() {
@@ -524,6 +666,12 @@ public class JoinGamePanel extends BackgroundPanel {
 		constraints.gridwidth = 1;
 		constraints.fill = GridBagConstraints.HORIZONTAL;
 		playerSlotsPanel.add(slotsHeadlineTeam, constraints);
+		constraints = new GridBagConstraints();
+		constraints.gridx = 13;
+		constraints.gridy = 0;
+		constraints.gridwidth = 1;
+		constraints.fill = GridBagConstraints.HORIZONTAL;
+		playerSlotsPanel.add(slotsHeadlineColor, constraints);
 	}
 
 	private enum EPeaceTime {
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/ColorUiWrapper.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/ColorUiWrapper.java
new file mode 100644
index 000000000..fa7a0f666
--- /dev/null
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/ColorUiWrapper.java
@@ -0,0 +1,29 @@
+package jsettlers.main.swing.menu.joinpanel.slots;
+
+import jsettlers.common.Color;
+import jsettlers.graphics.map.MapDrawContext;
+
+/**
+ * An entry of the color selection of a player slot: a colored bar and the number of the color.
+ */
+public class ColorUiWrapper {
+
+	private final int colorIndex;
+	private final String text;
+
+	public ColorUiWrapper(int colorIndex) {
+		this.colorIndex = colorIndex;
+		Color color = MapDrawContext.getSelectableColor(colorIndex);
+		int rgb = ((int) (color.getRed() * 255) << 16) | ((int) (color.getGreen() * 255) << 8) | (int) (color.getBlue() * 255);
+		this.text = String.format("<html><font color=\"#%06x\">\u25A0\u25A0\u25A0\u25A0</font> %d</html>", rgb, colorIndex + 1);
+	}
+
+	public int getColorIndex() {
+		return colorIndex;
+	}
+
+	@Override
+	public String toString() {
+		return text;
+	}
+}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
index c1b62582a..2528976f7 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
@@ -17,6 +17,7 @@ package jsettlers.main.swing.menu.joinpanel.slots;
 import jsettlers.common.ai.EPlayerType;
 import jsettlers.common.menu.IJoinPhaseMultiplayerGameConnector;
 import jsettlers.common.player.ECivilisation;
+import jsettlers.common.player.PlayerColors;
 import jsettlers.graphics.image.SingleImage;
 import jsettlers.graphics.localization.Labels;
 import jsettlers.graphics.map.draw.ImageProvider;
@@ -53,6 +54,7 @@ public class PlayerSlot {
 	private final JComboBox<PlayerTypeUiWrapper> typeComboBox = new JComboBox<>();
 	private final JComboBox<Byte> slotComboBox = new JComboBox<>();
 	private final JComboBox<Byte> teamComboBox = new JComboBox<>();
+	private final JComboBox<ColorUiWrapper> colorComboBox = new JComboBox<>();
 	private final JButton readyButton = new JButton();
 	private byte oldSlotValue;
 	private ISlotListener slotListener;
@@ -66,6 +68,8 @@ public class PlayerSlot {
 	private EPlayerType playerType;
 	private byte team;
 	private byte slot;
+	private byte color;
+	private Runnable previewListener;
 
 	public PlayerSlot(byte index) {
 		this.index = index;
@@ -111,6 +115,12 @@ public class PlayerSlot {
 		constraints.gridwidth = 1;
 		constraints.fill = GridBagConstraints.HORIZONTAL;
 		panel.add(teamComboBox, constraints);
+		constraints = new GridBagConstraints();
+		constraints.gridx = 13;
+		constraints.gridy = row + 1;
+		constraints.gridwidth = 1;
+		constraints.fill = GridBagConstraints.HORIZONTAL;
+		panel.add(colorComboBox, constraints);
 	}
 
 	private void setStyle() {
@@ -120,6 +130,7 @@ public class PlayerSlot {
 		readyButton.setMinimumSize(new Dimension(READY_BUTTON_WIDTH, READY_BUTTON_HEIGHT));
 		playerNameLabel.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_DYNAMIC);
 		teamComboBox.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
+		colorComboBox.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
 		slotComboBox.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
 		typeComboBox.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
 		civilisationComboBox.putClientProperty(ELFStyle.KEY, ELFStyle.COMBOBOX);
@@ -179,6 +190,15 @@ public class PlayerSlot {
 				slot = newSlot;
 			}
 		});
+		colorComboBox.addActionListener(e -> {
+			byte newColor = getColor();
+			if (informGameAboutChanges && newColor != color) {
+				gameToBeInformedAboutChanges.setColor(index, newColor);
+				color = newColor;
+			}
+			firePreviewChanged();
+		});
+		slotComboBox.addActionListener(e -> firePreviewChanged());
 		teamComboBox.addActionListener(e -> {
 			byte newTeam = getTeam();
 			if (informGameAboutChanges && newTeam != team) {
@@ -206,7 +226,23 @@ public class PlayerSlot {
 		}
 	}
 
+	private void firePreviewChanged() {
+		if (previewListener != null) {
+			previewListener.run();
+		}
+	}
+
+	/**
+	 * Sets a listener that is called when the map slot or the color of this slot changes.
+	 */
+	public void setPreviewListener(Runnable previewListener) {
+		this.previewListener = previewListener;
+	}
+
 	private void initializeComboBoxes() {
+		for (int i = 0; i < PlayerColors.SELECTABLE_COLORS; i++) {
+			colorComboBox.addItem(new ColorUiWrapper(i));
+		}
 		civilisationComboBox.addItem(new CivilisationUiWrapper());
 		for(ECivilisation civ : ECivilisation.values()) civilisationComboBox.addItem(new CivilisationUiWrapper(civ));
 	}
@@ -251,6 +287,24 @@ public class PlayerSlot {
 		teamComboBox.setSelectedIndex(team);
 	}
 
+	public void setColor(byte color, boolean update) {
+		if (!update) {
+			this.color = color;
+		}
+		int index = Math.abs(color) % PlayerColors.SELECTABLE_COLORS;
+		if (colorComboBox.getSelectedIndex() != index) {
+			colorComboBox.setSelectedIndex(index);
+		}
+	}
+
+	public byte getColor() {
+		return (byte) Math.max(colorComboBox.getSelectedIndex(), 0);
+	}
+
+	public void disableColorInput() {
+		colorComboBox.setEnabled(false);
+	}
+
 	public void disableTeamInput() {
 		teamComboBox.setEnabled(false);
 	}
@@ -296,6 +350,7 @@ public class PlayerSlot {
 		slotComboBox.setEnabled(false);
 		disableCivilisationInput();
 		disableTeamInput();
+		disableColorInput();
 		disablePlayerTypeInput();
 	}
 
diff --git a/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java b/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
index f5d8ddcaf..665ccca77 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
@@ -115,6 +115,7 @@ public final class NetworkConstants {
 		POSITION_CHANGED,
 		TYPE_CHANGED,
 		PLAYER_COUNT_CHANGED,
+		COLOR_CHANGED,
 		;
 
 		private static final ENetworkMessage[] values = ENetworkMessage.values();
@@ -171,6 +172,7 @@ public final class NetworkConstants {
 		CHANGE_PLAYER_TYPE,
 		CHANGE_POSITION,
 		CHANGE_PLAYER_COUNT,
+		CHANGE_COLOR,
 		;
 
 		private static final ENetworkKey[] values = ENetworkKey.values();
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java b/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
index aa1944645..d64c1dd16 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
@@ -169,6 +169,12 @@ public class NetworkClient implements ITaskScheduler, INetworkConnector, INetwor
 		channel.sendPacketAsync(ENetworkKey.CHANGE_TEAM, new ByteTuplePacket(slot, team));
 	}
 
+	@Override
+	public void setColor(byte slot, byte color) throws IllegalStateException {
+		EPlayerState.assertState(state, EPlayerState.IN_MATCH);
+		channel.sendPacketAsync(ENetworkKey.CHANGE_COLOR, new ByteTuplePacket(slot, color));
+	}
+
 	@Override
 	public void setType(byte slot, byte playerType) throws IllegalStateException {
 		EPlayerState.assertState(state, EPlayerState.IN_MATCH);
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
index cb6072caa..c19be0321 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
@@ -96,6 +96,8 @@ public interface INetworkClient {
 
 	void setTeam(byte slot, byte team) throws IllegalStateException;
 
+	void setColor(byte slot, byte color) throws IllegalStateException;
+
 	void setType(byte slot, byte playerType) throws IllegalStateException;
 
 	void setPosition(byte slot, byte position) throws IllegalStateException;
diff --git a/jsettlers.network/src/main/java/jsettlers/network/common/packets/SlotInfoPacket.java b/jsettlers.network/src/main/java/jsettlers/network/common/packets/SlotInfoPacket.java
index 51e4b4100..dfbe36492 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/common/packets/SlotInfoPacket.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/common/packets/SlotInfoPacket.java
@@ -12,6 +12,7 @@ public class SlotInfoPacket extends Packet {
 	private byte playerType;
 	private byte civilisation;
 	private byte position;
+	private byte color;
 
 	public SlotInfoPacket() {
 	}
@@ -21,13 +22,19 @@ public class SlotInfoPacket extends Packet {
 		playerType = slot.getType();
 		civilisation = slot.getCivilisation();
 		position = slot.getPosition();
+		color = slot.getColor();
 	}
 
 	public SlotInfoPacket(byte team, byte playerType, byte civilisation, byte position) {
+		this(team, playerType, civilisation, position, position);
+	}
+
+	public SlotInfoPacket(byte team, byte playerType, byte civilisation, byte position, byte color) {
 		this.team = team;
 		this.playerType = playerType;
 		this.civilisation = civilisation;
 		this.position = position;
+		this.color = color;
 	}
 
 	@Override
@@ -36,6 +43,7 @@ public class SlotInfoPacket extends Packet {
 		dos.writeByte(playerType);
 		dos.writeByte(civilisation);
 		dos.writeByte(position);
+		dos.writeByte(color);
 	}
 
 	@Override
@@ -44,6 +52,7 @@ public class SlotInfoPacket extends Packet {
 		playerType = dis.readByte();
 		civilisation = dis.readByte();
 		position = dis.readByte();
+		color = dis.readByte();
 	}
 
 	@Override
@@ -51,12 +60,13 @@ public class SlotInfoPacket extends Packet {
 		if (this == o) return true;
 		if (o == null || getClass() != o.getClass()) return false;
 		SlotInfoPacket that = (SlotInfoPacket) o;
-		return team == that.team && playerType == that.playerType && civilisation == that.civilisation && position == that.position;
+		return team == that.team && playerType == that.playerType && civilisation == that.civilisation && position == that.position
+				&& color == that.color;
 	}
 
 	@Override
 	public int hashCode() {
-		return Objects.hash(team, playerType, civilisation, position);
+		return Objects.hash(team, playerType, civilisation, position, color);
 	}
 
 	@Override
@@ -66,6 +76,7 @@ public class SlotInfoPacket extends Packet {
 				", playerType=" + playerType +
 				", civilisation=" + civilisation +
 				", position=" + position +
+				", color=" + color +
 				'}';
 	}
 
@@ -84,4 +95,8 @@ public class SlotInfoPacket extends Packet {
 	public byte getPosition() {
 		return position;
 	}
+
+	public byte getColor() {
+		return color;
+	}
 }
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java b/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
index 0910b81d5..ab66480a1 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
@@ -67,6 +67,8 @@ public interface IServerManager {
 
 	void setTeamForSlot(Player player, byte slot, byte team);
 
+	void setColorForSlot(Player player, byte slot, byte color);
+
 	void setPlayerCount(Player player, int playerCount);
 
 	void sendMatchesToPlayer(Player player);
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java b/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
index 47e5747b5..33cdd607b 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
@@ -28,6 +28,7 @@ import jsettlers.network.server.listeners.ChangeCivilisationPacketListener;
 import jsettlers.network.server.listeners.ChangePlayerCountPacketListener;
 import jsettlers.network.server.listeners.ChangePlayerTypePacketListener;
 import jsettlers.network.server.listeners.ChangePositionPacketListener;
+import jsettlers.network.server.listeners.ChangeColorPacketListener;
 import jsettlers.network.server.listeners.ChangeTeamPacketListener;
 import jsettlers.network.server.listeners.ChatMessageForwardingListener;
 import jsettlers.network.server.listeners.IdentifyUserListener;
@@ -96,6 +97,7 @@ public class ServerManager implements IServerManager {
 			channel.registerListener(new ChangePlayerTypePacketListener(this, player));
 			channel.registerListener(new ChangePositionPacketListener(this, player));
 			channel.registerListener(new ChangeTeamPacketListener(this, player));
+			channel.registerListener(new ChangeColorPacketListener(this, player));
 			channel.registerListener(new ChangePlayerCountPacketListener(this, player));
 
 			return true;
@@ -252,6 +254,18 @@ public class ServerManager implements IServerManager {
 		}
 	}
 
+	@Override
+	public void setColorForSlot(Player player, byte slot, byte color) {
+		try {
+			Match match = verifyAndGetMatch(player);
+
+			match.setSlotColor(slot, color);
+		} catch (IllegalStateException e) {
+			player.sendPacket(NetworkConstants.ENetworkKey.REJECT_PACKET,
+					new RejectPacket(NetworkConstants.ENetworkMessage.INVALID_STATE_ERROR, NetworkConstants.ENetworkKey.CHANGE_COLOR));
+		}
+	}
+
 	@Override
 	public void setPlayerCount(Player player, int playerCount) {
 		try {
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangeColorPacketListener.java b/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangeColorPacketListener.java
new file mode 100644
index 000000000..a98f10f30
--- /dev/null
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangeColorPacketListener.java
@@ -0,0 +1,27 @@
+package jsettlers.network.server.listeners;
+
+import java.io.IOException;
+import jsettlers.network.NetworkConstants;
+import jsettlers.network.common.packets.ByteTuplePacket;
+import jsettlers.network.infrastructure.channel.GenericDeserializer;
+import jsettlers.network.infrastructure.channel.listeners.PacketChannelListener;
+import jsettlers.network.server.IServerManager;
+import jsettlers.network.server.match.Player;
+
+public class ChangeColorPacketListener extends PacketChannelListener<ByteTuplePacket> {
+
+	private final IServerManager serverManager;
+	private final Player player;
+
+	public ChangeColorPacketListener(IServerManager serverManager, Player player) {
+		super(NetworkConstants.ENetworkKey.CHANGE_COLOR, new GenericDeserializer<>(ByteTuplePacket.class));
+
+		this.serverManager = serverManager;
+		this.player = player;
+	}
+
+	@Override
+	protected void receivePacket(NetworkConstants.ENetworkKey key, ByteTuplePacket packet) throws IOException {
+		serverManager.setColorForSlot(player, packet.getValueA(), packet.getValueB());
+	}
+}
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java b/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
index 47d1f6891..b0acf7f0e 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
@@ -367,6 +367,19 @@ public class Match {
 		}
 	}
 
+	public void setSlotColor(byte slotId, byte color) {
+		byte oldColor;
+		synchronized (slots) {
+			Slot slot = getSlot(slotId);
+			oldColor = slot.getColor();
+			slot.setColor(color);
+		}
+
+		if(oldColor != color) {
+			sendMatchInfoUpdate(ENetworkMessage.COLOR_CHANGED, null);
+		}
+	}
+
 	public void setPlayerCount(int playerCount) {
 		synchronized (players) {
 			if(playerCount < players.size()) {
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/match/Slot.java b/jsettlers.network/src/main/java/jsettlers/network/server/match/Slot.java
index 32e4d8910..fd304539e 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/match/Slot.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/match/Slot.java
@@ -5,12 +5,14 @@ public class Slot {
 	private byte team;
 	private byte civilisation;
 	private byte position;
+	private byte color;
 
 	public Slot(byte type, byte team, byte civilisation, byte position) {
 		this.type = type;
 		this.team = team;
 		this.civilisation = civilisation;
 		this.position = position;
+		this.color = position;
 	}
 
 	public byte getType() {
@@ -29,6 +31,14 @@ public class Slot {
 		return position;
 	}
 
+	public byte getColor() {
+		return color;
+	}
+
+	public void setColor(byte color) {
+		this.color = color;
+	}
+
 	public void setType(byte type) {
 		this.type = type;
 	}
PATCH_EOF
cat > "$WORK/patches/24-lan-load-game.patch" <<'PATCH_EOF'
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index 9b240e8b8..344f557b0 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -485,6 +485,9 @@ game-menu-description = Ukončit nebo uložit hru
 
 multiplayer-joinmatch-title = Připojit se ke hře
 multiplayer-newmatch-title = Nová hra
+multiplayer-loadmatch-title = Načíst hru
+multiplayer-missing-map-title = Mapa nenalezena
+multiplayer-missing-map-message = Tato hra používá mapu nebo uloženou hru "%s", která není v tomto počítači.\nUložená hra musí být na všech počítačích přesně stejný soubor: zkopírujte soubor hostitele do své složky s uloženými hrami (~/Library/Application Support/JSettlers/save) a hru restartujte.
 
 multiplayer-indicator-match = hra
 multiplayer-indicator-maps = mapy
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 5587dd15b..9dab50058 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -491,6 +491,9 @@ game-menu-description = Quit or Save the game
 
 multiplayer-joinmatch-title = Join match
 multiplayer-newmatch-title = New match
+multiplayer-loadmatch-title = Load game
+multiplayer-missing-map-title = Map not found
+multiplayer-missing-map-message = This game uses the map or saved game "%s", which is not on this computer.\nA saved game must be exactly the same file on all computers: copy the file of the host into your folder of saved games (~/Library/Application Support/JSettlers/save) and restart the game.
 
 multiplayer-indicator-match = match
 multiplayer-indicator-maps = maps
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
index f856bfc11..a3bba0dd8 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
@@ -212,6 +212,10 @@ public class JSettlersGame {
 
 				MainGridWithUiSettings gridWithUiState = mapCreator.loadMainGrid(initialGameState.getPlayerSettings(), initialGameState.getStartResources());
 				mainGrid = gridWithUiState.getMainGrid();
+				if (multiplayer) {
+					// a saved game continues at its saved time, but the lockstep numbers of the network game start at 0
+					networkConnector.getGameClock().setLockstepBase(MatchConstants.clock().getTime());
+				}
 				PlayerState playerState = gridWithUiState.getPlayerState(initialGameState.getPlayerId());
 
 				RescheduleTimer.schedule(MatchConstants.clock()); // schedule timer
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 748d105ff..fa85a2269 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -49,6 +49,7 @@ import javax.swing.border.EmptyBorder;
 import jsettlers.common.menu.ENetworkMessage;
 import jsettlers.common.menu.EProgressState;
 import jsettlers.common.menu.IChatMessageListener;
+import jsettlers.common.ai.EPlayerType;
 import jsettlers.common.menu.IJoinPhaseMultiplayerGameConnector;
 import jsettlers.common.menu.IJoiningGame;
 import jsettlers.common.menu.IJoiningGameListener;
@@ -65,6 +66,7 @@ import jsettlers.graphics.map.MapDrawContext;
 import jsettlers.logic.map.loading.MapLoader;
 import jsettlers.logic.map.loading.data.IMapData;
 import jsettlers.logic.map.loading.newmap.MapFileHeader;
+import jsettlers.logic.map.loading.savegame.SavegameLoader;
 import jsettlers.common.position.ShortPoint2D;
 import jsettlers.logic.player.InitialGameState;
 import jsettlers.logic.player.PlayerSetting;
@@ -132,6 +134,11 @@ public class JoinGamePanel extends BackgroundPanel {
 	/** Positions of the start points in the preview image (index = position on the map), <code>null</code> as long as they are unknown. */
 	private int[][] previewStartPoints;
 	private Thread previewStartPointsThread;
+	/**
+	 * If a saved game is shown: the positions (player ids) of the players of the saved game, in the order of the slots of the lobby.
+	 * <code>null</code> for new games.
+	 */
+	private int[] savedGamePositions;
 
 	public JoinGamePanel(JSettlersFrame settlersFrame) {
 		this.settlersFrame = settlersFrame;
@@ -310,6 +317,9 @@ public class JoinGamePanel extends BackgroundPanel {
 						}
 					});
 
+					if (savedGamePositions != null) {
+						sendSavedGameToServer(connector);
+					}
 					onSlotsChanged(connector.getSlots(), connector, myId, true); // init the UI with the players
 					numberOfPlayersComboBox.informGame(connector);
 				});
@@ -423,7 +433,7 @@ public class JoinGamePanel extends BackgroundPanel {
 				joinMultiPlayerMap.abort();
 				settlersFrame.showMainMenu();
 			});
-			numberOfPlayersComboBox.setEnabled(iAmTheHost);
+			numberOfPlayersComboBox.setEnabled(iAmTheHost && savedGamePositions == null);
 		});
 	}
 
@@ -451,9 +461,11 @@ public class JoinGamePanel extends BackgroundPanel {
 				.map(MapStartResourcesUIWrapper::new)
 				.forEach(startResourcesComboBox::addItem);
 		startResourcesComboBox.setSelectedIndex(EMapStartResources.HIGH_GOODS.value - 1);
-		numberOfPlayersComboBox.reset(mapLoader.getMaxPlayers());
+		savedGamePositions = determineSavedGamePositions(mapLoader);
+		int numberOfSlots = savedGamePositions != null ? savedGamePositions.length : mapLoader.getMaxPlayers();
+		numberOfPlayersComboBox.reset(numberOfSlots);
 		buildPlayerSlots();
-		updateNumberOfPlayerSlots(mapLoader.getMaxPlayers());
+		updateNumberOfPlayerSlots(numberOfSlots);
 		loadPreviewStartPoints(mapLoader);
 	}
 
@@ -569,7 +581,100 @@ public class JoinGamePanel extends BackgroundPanel {
 		mapImage.setIcon(new ImageIcon(image));
 	}
 
+	/**
+	 * Finds the players of a saved game: the positions on the map that are used. The player that saved the game comes first, then the other human
+	 * players, then the computer players. Players that join a LAN game take the slots in this order.
+	 *
+	 * @return The positions, or <code>null</code> if the map is not a saved game.
+	 */
+	private static int[] determineSavedGamePositions(MapLoader mapLoader) {
+		if (!(mapLoader instanceof SavegameLoader)) {
+			return null;
+		}
+		MapFileHeader header = mapLoader.getFileHeader();
+		PlayerSetting[] settings = header.getPlayerSettings();
+		Byte savingPlayer = header.getPlayerId();
+		List<Integer> positions = new ArrayList<>();
+		for (int i = 0; i < settings.length; i++) {
+			if (settings[i].isAvailable()) {
+				positions.add(i);
+			}
+		}
+		positions.sort(Comparator.comparingInt((Integer position) -> {
+			if (savingPlayer != null && savingPlayer.intValue() == position.intValue()) {
+				return 0;
+			}
+			return settings[position].getPlayerType() == EPlayerType.HUMAN || settings[position].getPlayerType() == null ? 1 : 2;
+		}).thenComparingInt(position -> position));
+		return positions.stream().mapToInt(Integer::intValue).toArray();
+	}
+
+	/**
+	 * @return The slot number (team number) that is shown in the lobby for a team of a saved game. The numbers of the teams in the saved game can be
+	 * bigger than the number of players in the lobby, so the teams are numbered in the order of their first appearance.
+	 */
+	private byte savedGameTeamNumber(PlayerSetting[] settings, int slot) {
+		List<Byte> teams = new ArrayList<>();
+		for (int i = 0; i < savedGamePositions.length; i++) {
+			Byte team = settings[savedGamePositions[i]].getTeamId();
+			byte key = team != null ? team : (byte) savedGamePositions[i];
+			if (!teams.contains(key)) {
+				teams.add(key);
+			}
+		}
+		Byte team = settings[savedGamePositions[slot]].getTeamId();
+		return (byte) teams.indexOf(team != null ? team : (byte) savedGamePositions[slot]);
+	}
+
+	private void buildSavedGamePlayerSlots() {
+		PlayerSetting[] settings = mapLoader.getFileHeader().getPlayerSettings();
+		playerSlots.clear();
+		for (byte i = 0; i < savedGamePositions.length; i++) {
+			PlayerSlot playerSlot = playerSlotFactory.createPlayerSlot(i, this.mapLoader);
+			playerSlots.add(playerSlot);
+
+			int position = savedGamePositions[i];
+			PlayerSetting setting = settings[position];
+			playerSlot.setSlot((byte) position, true);
+			playerSlot.setColor((byte) position, true);
+			playerSlot.setPreviewListener(this::refreshPreview);
+			playerSlot.setTeam(savedGameTeamNumber(settings, i), true);
+			if (setting.getCivilisation() != null) {
+				playerSlot.setCivilisation(setting.getCivilisation(), true);
+			}
+			// the position, the nation and the team of a saved game can't be changed
+			playerSlot.disableSlotInput();
+			playerSlot.disableCivilisationInput();
+			playerSlot.disableTeamInput();
+		}
+	}
+
+	/**
+	 * Hands the players of the saved game over to the server of a LAN game: number of slots, positions, nations, teams, colors and types.
+	 */
+	private void sendSavedGameToServer(IJoinPhaseMultiplayerGameConnector connector) {
+		PlayerSetting[] settings = mapLoader.getFileHeader().getPlayerSettings();
+		connector.setPlayerCount(savedGamePositions.length);
+		for (byte i = 0; i < savedGamePositions.length; i++) {
+			int position = savedGamePositions[i];
+			PlayerSetting setting = settings[position];
+			connector.setPosition(i, (byte) position);
+			if (setting.getCivilisation() != null) {
+				connector.setCivilisation(i, setting.getCivilisation());
+			}
+			connector.setTeam(i, savedGameTeamNumber(settings, i));
+			connector.setColor(i, (byte) position);
+			if (i > 0 && setting.getPlayerType() != null) { // the first slot is the host
+				connector.setType(i, setting.getPlayerType());
+			}
+		}
+	}
+
 	private void buildPlayerSlots() {
+		if (savedGamePositions != null) {
+			buildSavedGamePlayerSlots();
+			return;
+		}
 		int maximumNumberOfPlayers = this.mapLoader.getMaxPlayers();
 		playerSlots.clear();
 		for (byte i = 0; i < maximumNumberOfPlayers; i++) {
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
index 2528976f7..7bb2e5706 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
@@ -301,6 +301,10 @@ public class PlayerSlot {
 		return (byte) Math.max(colorComboBox.getSelectedIndex(), 0);
 	}
 
+	public void disableSlotInput() {
+		slotComboBox.setEnabled(false);
+	}
+
 	public void disableColorInput() {
 		colorComboBox.setEnabled(false);
 	}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/ServerConnectionPanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/ServerConnectionPanel.java
index 48433c491..3f68c246b 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/ServerConnectionPanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/multiplayer/ServerConnectionPanel.java
@@ -19,6 +19,7 @@ import java.util.Collections;
 import java.util.List;
 import java.util.stream.Collectors;
 
+import javax.swing.JOptionPane;
 import javax.swing.JPanel;
 import javax.swing.JTabbedPane;
 import javax.swing.SwingUtilities;
@@ -41,6 +42,7 @@ public abstract class ServerConnectionPanel extends JPanel {
 	protected JTabbedPane root = new JTabbedPane();
 	private RemoteMapDirectoryPanel maps = null;
 	private OpenPanel newMatch = null;
+	private OpenPanel loadMatch = null;
 	private OpenPanel joinMatch = null;
 	private JSettlersFrame settlersFrame;
 
@@ -71,15 +73,21 @@ public abstract class ServerConnectionPanel extends JPanel {
 
 		boolean conMatch = connection.isConnected() && connection instanceof IMultiplayerConnector;
 		if(!conMatch && newMatch != null) {
+			root.removeTabAt(i);
 			root.removeTabAt(i);
 			root.removeTabAt(i);
 			newMatch = null;
+			loadMatch = null;
 			joinMatch = null;
 		} else if(conMatch && newMatch == null){
 			newMatch = new OpenPanel(MapList.getDefaultList().getFreshMaps().getItems(), this::openNewMatch);
 			SwingUtilities.updateComponentTreeUI(newMatch);
 			root.insertTab(Labels.getString("multiplayer-newmatch-title"), null, newMatch, null, i);
 
+			loadMatch = new OpenPanel(MapList.getDefaultList().getSavedMaps(), this::openNewMatch);
+			SwingUtilities.updateComponentTreeUI(loadMatch);
+			root.insertTab(Labels.getString("multiplayer-loadmatch-title"), null, loadMatch, null, i + 1);
+
 			joinMatch = new OpenPanel(Collections.emptyList(), this::joinMatch);
 			SwingUtilities.updateComponentTreeUI(joinMatch);
 
@@ -91,7 +99,7 @@ public abstract class ServerConnectionPanel extends JPanel {
 						SwingUtilities.invokeLater(() -> joinMatch.setMapLoaders(mapLoaders));
 					});
 
-			root.insertTab(Labels.getString("multiplayer-joinmatch-title"), null, joinMatch, null, i+1);
+			root.insertTab(Labels.getString("multiplayer-joinmatch-title"), null, joinMatch, null, i + 2);
 		}
 
 		updateAfter(connection, i);
@@ -110,6 +118,13 @@ public abstract class ServerConnectionPanel extends JPanel {
 
 	private void joinMatch(MapLoader loader) {
 		NetworkGameMapLoader networkGameMapLoader = (NetworkGameMapLoader) loader;
+		if (MapList.getDefaultList().getMapById(networkGameMapLoader.getMapId()) == null) {
+			// the map or the saved game of the host is not available on this computer
+			JOptionPane.showMessageDialog(this,
+					Labels.getString("multiplayer-missing-map-message", networkGameMapLoader.getMapName()),
+					Labels.getString("multiplayer-missing-map-title"), JOptionPane.WARNING_MESSAGE);
+			return;
+		}
 		IJoiningGame joiningGame = ((IMultiplayerConnector)getConnection()).joinMultiplayerGame(networkGameMapLoader.getJoinableGame());
 		joiningGame.setListener(new IJoiningGameListener() {
 			@Override
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/IGameClock.java b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/IGameClock.java
index b7f581636..625629023 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/IGameClock.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/IGameClock.java
@@ -33,6 +33,13 @@ public interface IGameClock extends IPausingSupplier {
 
 	void setTime(int newTime);
 
+	/**
+	 * Tells the clock that the lockstep numbers of the network game start counting at the given game time (needed if a saved game is continued
+	 * in a network game: the clock does not start at 0, but the server starts counting the lockstep at 0). Not needed if the game starts at time 0.
+	 */
+	default void setLockstepBase(int gameTime) {
+	}
+
 	void setTaskExecutor(ITaskExecutor taskExecutor);
 
 	void multiplyGameSpeed(float factor);
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/time/ISynchronizableClock.java b/jsettlers.network/src/main/java/jsettlers/network/client/time/ISynchronizableClock.java
index 953cfd91e..d6dbeb432 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/time/ISynchronizableClock.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/time/ISynchronizableClock.java
@@ -27,6 +27,13 @@ public interface ISynchronizableClock {
 	 */
 	int getTime();
 
+	/**
+	 * @return The time that is exchanged with the other clients and the server: the time since the first lockstep of the network game.
+	 */
+	default int getSyncTime() {
+		return getTime();
+	}
+
 	/**
 	 * Pauses the clock for at least the given period of time.
 	 * 
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSyncSenderTimerTask.java b/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSyncSenderTimerTask.java
index c4791bd31..aa907b88e 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSyncSenderTimerTask.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSyncSenderTimerTask.java
@@ -37,7 +37,7 @@ public class TimeSyncSenderTimerTask extends TimerTask {
 
 	@Override
 	public void run() {
-		int localTime = clock.getTime();
+		int localTime = clock.getSyncTime();
 		int expectedTimeAtServer = localTime + channel.getRoundTripTime().getRtt() / 2;
 
 		channel.sendPacketAsync(NetworkConstants.ENetworkKey.TIME_SYNC, new TimeSyncPacket(expectedTimeAtServer));
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSynchronizationListener.java b/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSynchronizationListener.java
index 2ec50c613..2a5a31136 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSynchronizationListener.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/time/TimeSynchronizationListener.java
@@ -43,7 +43,7 @@ public class TimeSynchronizationListener extends PacketChannelListener<TimeSyncP
 	@Override
 	protected void receivePacket(ENetworkKey key, TimeSyncPacket packet) throws IOException {
 		int expectedRemoteTime = packet.getTime() + rttSupplier.getRoundTripTime().getRtt() / 2;
-		int localTime = clock.getTime();
+		int localTime = clock.getSyncTime();
 
 		int deltaTime = localTime - expectedRemoteTime;
 
diff --git a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
index 2df6ae869..acc15333a 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
@@ -52,6 +52,8 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 	private final LinkedList<SyncTasksPacket> tasks = new LinkedList<>();
 
 	private int time = 0;
+	/** Game time at which the lockstep numbers of the network game start counting (0 unless a saved game was loaded into a network game). */
+	private int lockstepBase = 0;
 	private int maxAllowedLockstep = -1;
 
 	private boolean isPausing;
@@ -120,7 +122,7 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 	private synchronized void executeRun() {
 		try {
 			time += TIME_SLICE;
-			final int lockstep = time / NetworkConstants.Client.LOCKSTEP_PERIOD;
+			final int lockstep = (time - lockstepBase) / NetworkConstants.Client.LOCKSTEP_PERIOD;
 
 			// check if the lockstep is allowed
 			synchronized (lockstepLock) {
@@ -336,6 +338,16 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 		return time;
 	}
 
+	@Override
+	public void setLockstepBase(int gameTime) {
+		this.lockstepBase = gameTime;
+	}
+
+	@Override
+	public int getSyncTime() {
+		return time - lockstepBase;
+	}
+
 	@Override
 	public void setReplayLogStream(DataOutputStream replayFileStream) {
 		if (this.replayLogStream != null) {
PATCH_EOF
cat > "$WORK/patches/25-shared-player-experimental.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/SharedPlayers.java b/jsettlers.common/src/main/java/jsettlers/common/menu/SharedPlayers.java
new file mode 100644
index 000000000..460036c81
--- /dev/null
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/SharedPlayers.java
@@ -0,0 +1,53 @@
+package jsettlers.common.menu;
+
+import java.util.List;
+
+/**
+ * Human players of a network game that choose the same color and the same nation play together as one player (experimental). They share the
+ * position on the map of the one of them that has the lowest position.
+ */
+public final class SharedPlayers {
+
+	private SharedPlayers() {
+	}
+
+	/**
+	 * Determines the position of the player each slot belongs to.
+	 *
+	 * @param slots
+	 * 		The slots of the lobby.
+	 * @return For every slot (same order as the list) the position that is used in the game: the position of the slot itself, or - if other human
+	 * players have the same color and nation - the lowest position of this group.
+	 */
+	public static byte[] playerPositions(List<? extends IMultiplayerSlot> slots) {
+		byte[] positions = new byte[slots.size()];
+		for (int i = 0; i < positions.length; i++) {
+			IMultiplayerSlot slot = slots.get(i);
+			positions[i] = slot.getPosition();
+			if (slot.getPlayer() == null) {
+				continue; // only human players are merged
+			}
+			for (int j = 0; j < positions.length; j++) {
+				IMultiplayerSlot other = slots.get(j);
+				if (j != i && other.getPlayer() != null && other.getColor() == slot.getColor() && other.getCivilisation() == slot.getCivilisation()
+						&& other.getPosition() < positions[i]) {
+					positions[i] = other.getPosition();
+				}
+			}
+		}
+		return positions;
+	}
+
+	/**
+	 * @return true if the slot with the given index plays together with at least one other slot.
+	 */
+	public static boolean isShared(List<? extends IMultiplayerSlot> slots, int index) {
+		byte[] positions = playerPositions(slots);
+		for (int i = 0; i < positions.length; i++) {
+			if (i != index && positions[i] == positions[index]) {
+				return true;
+			}
+		}
+		return false;
+	}
+}
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index 344f557b0..f56f45d41 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -566,6 +566,7 @@ join-game-panel-player-type = Typ
 join-game-panel-map-slot = Pozice
 join-game-panel-team = Tým
 join-game-panel-color = Barva
+join-game-panel-shared-player-tooltip = Stejná barva a národ: tito hráči hrají společně jako jeden hráč (experimentální).
 join-game-panel-send-chat-message = Odeslat
 
 stats-panel-exit = Další
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 9dab50058..84004a547 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -572,6 +572,7 @@ join-game-panel-player-type = Type
 join-game-panel-map-slot = Position
 join-game-panel-team = Team
 join-game-panel-color = Color
+join-game-panel-shared-player-tooltip = Same color and nation: these players play together as one player (experimental).
 join-game-panel-send-chat-message = Send
 
 stats-panel-exit = Next
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
index 57672463b..cd853602c 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
@@ -146,14 +146,42 @@ public class MultiplayerGame {
 		};
 	}
 
+	/**
+	 * Human players with the same color and nation play together as one player: only the slot at the lowest position of such a group is a player
+	 * of the game, the others only control it.
+	 */
+	private boolean isMergedIntoOtherSlot(List<? extends IMultiplayerSlot> slots, byte[] playerPositions, IMultiplayerSlot slot) {
+		return playerPositions[slots.indexOf(slot)] != slot.getPosition();
+	}
+
+	private String sharedPlayerName(List<? extends IMultiplayerSlot> slots, byte[] playerPositions, IMultiplayerSlot representative) {
+		StringBuilder name = new StringBuilder();
+		for (int i = 0; i < slots.size(); i++) {
+			IMultiplayerSlot other = slots.get(i);
+			if (other == representative || (playerPositions[i] == representative.getPosition() && other.getPlayer() != null)) {
+				String playerName = playerNameOf(other);
+				if (playerName != null) {
+					if (name.length() > 0) {
+						name.append(" + ");
+					}
+					name.append(playerName);
+				}
+			}
+		}
+		return name.length() > 0 ? name.toString() : null;
+	}
+
 	private PlayerSetting[] determinePlayerSettings() {
-		Map<Byte, PlayerSetting> playerSettings = slotList.getItems().stream().sorted(Comparator.comparingInt(IMultiplayerSlot::getPosition))
+		List<? extends IMultiplayerSlot> allSlots = slotList.getItems();
+		byte[] playerPositions = jsettlers.common.menu.SharedPlayers.playerPositions(allSlots);
+		Map<Byte, PlayerSetting> playerSettings = allSlots.stream().sorted(Comparator.comparingInt(IMultiplayerSlot::getPosition))
+				.filter(slot -> !isMergedIntoOtherSlot(allSlots, playerPositions, slot))
 				.map(slot -> {
 					PlayerSetting playerSetting;
 					if(iAmTheHost) {
-						playerSetting = new PlayerSetting(slot.getType(), slot.getCivilisation(), slot.getTeam()).withDisplayName(playerNameOf(slot));
+						playerSetting = new PlayerSetting(slot.getType(), slot.getCivilisation(), slot.getTeam()).withDisplayName(sharedPlayerName(allSlots, playerPositions, slot));
 					} else {
-						playerSetting = new PlayerSetting(EPlayerType.HUMAN, slot.getCivilisation(), slot.getTeam()).withDisplayType(slot.getType()).withDisplayName(playerNameOf(slot));
+						playerSetting = new PlayerSetting(EPlayerType.HUMAN, slot.getCivilisation(), slot.getTeam()).withDisplayType(slot.getType()).withDisplayName(sharedPlayerName(allSlots, playerPositions, slot));
 					}
 
 					return Map.entry(slot.getPosition(), playerSetting);
@@ -166,8 +194,10 @@ public class MultiplayerGame {
 		for (int i = 0; i < colors.length; i++) {
 			colors[i] = (byte) i;
 		}
-		for (IMultiplayerSlot slot : slotList.getItems()) {
-			if (slot.getPosition() >= 0 && slot.getPosition() < colors.length) {
+		List<? extends IMultiplayerSlot> allSlots = slotList.getItems();
+		byte[] playerPositions = jsettlers.common.menu.SharedPlayers.playerPositions(allSlots);
+		for (IMultiplayerSlot slot : allSlots) {
+			if (playerPositions[allSlots.indexOf(slot)] == slot.getPosition() && slot.getPosition() >= 0 && slot.getPosition() < colors.length) {
 				colors[slot.getPosition()] = slot.getColor();
 			}
 		}
@@ -180,9 +210,12 @@ public class MultiplayerGame {
 
 	private byte calculateOwnPlayerId() {
 		String myId = networkClient.getPlayerInfo().getId();
-		for (IMultiplayerSlot currSlot : slotList.getItems()) {
+		List<? extends IMultiplayerSlot> allSlots = slotList.getItems();
+		byte[] playerPositions = jsettlers.common.menu.SharedPlayers.playerPositions(allSlots);
+		for (int i = 0; i < allSlots.size(); i++) {
+			IMultiplayerSlot currSlot = allSlots.get(i);
 			if(currSlot.getPlayer() != null && currSlot.getPlayer().getId().equals(myId)) {
-				return currSlot.getPosition();
+				return playerPositions[i]; // players that play together as one player share the position
 			}
 		}
 		throw new RuntimeException("Wasn't able to find my id!");
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index fa85a2269..8fd1274e7 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -58,6 +58,7 @@ import jsettlers.common.menu.IMultiplayerListener;
 import jsettlers.common.menu.IMultiplayerPlayer;
 import jsettlers.common.menu.IMultiplayerSlot;
 import jsettlers.common.menu.IStartingGame;
+import jsettlers.common.menu.SharedPlayers;
 import jsettlers.common.player.PlayerColors;
 import jsettlers.common.utils.collections.ChangingList;
 import jsettlers.graphics.localization.Labels;
@@ -429,6 +430,7 @@ public class JoinGamePanel extends BackgroundPanel {
 					playerSlot.setReady(true);
 				}
 			}
+			showSharedPlayers(changingSlots.getItems());
 			setCancelButtonActionListener(e -> {
 				joinMultiPlayerMap.abort();
 				settlersFrame.showMainMenu();
@@ -437,6 +439,18 @@ public class JoinGamePanel extends BackgroundPanel {
 		});
 	}
 
+	/**
+	 * Human players with the same color and nation play together as one player, so they are shown at the same position.
+	 */
+	private void showSharedPlayers(List<? extends IMultiplayerSlot> slots) {
+		byte[] positions = SharedPlayers.playerPositions(slots);
+		for (int i = 0; i < slots.size() && i < playerSlots.size(); i++) {
+			boolean shared = SharedPlayers.isShared(slots, i);
+			playerSlots.get(i).showSharedPosition(positions[i], shared && positions[i] != slots.get(i).getPosition());
+		}
+		refreshPreview();
+	}
+
 	/**
 	 * Hands the selected peace time over to the game that is started next.
 	 */
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
index 7bb2e5706..7b06eb7c6 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/slots/PlayerSlot.java
@@ -70,6 +70,10 @@ public class PlayerSlot {
 	private byte slot;
 	private byte color;
 	private Runnable previewListener;
+	/** true while a slot is shown that is not the real position (players that play together as one player). */
+	private boolean adjustingDisplayedSlot = false;
+	/** false if the position of this slot cannot be changed by the user at all (client of a game, saved game). */
+	private boolean slotInputAllowed = true;
 
 	public PlayerSlot(byte index) {
 		this.index = index;
@@ -156,6 +160,9 @@ public class PlayerSlot {
 		typeComboBox.addActionListener(e -> updateAiPlayerName());
 		civilisationComboBox.addActionListener(e -> updateAiPlayerName());
 		slotComboBox.addActionListener(e -> {
+			if (adjustingDisplayedSlot) {
+				return;
+			}
 			// this is done server side in multiplayer
 			if (slotListener != null && gameToBeInformedAboutChanges == null) {
 				slotListener.slotHasChanged(oldSlotValue, getSlot());
@@ -184,6 +191,9 @@ public class PlayerSlot {
 			}
 		});
 		slotComboBox.addActionListener(e -> {
+			if (adjustingDisplayedSlot) {
+				return;
+			}
 			byte newSlot = getSlot();
 			if(informGameAboutChanges && newSlot != slot) {
 				gameToBeInformedAboutChanges.setPosition(index, newSlot);
@@ -302,9 +312,34 @@ public class PlayerSlot {
 	}
 
 	public void disableSlotInput() {
+		slotInputAllowed = false;
 		slotComboBox.setEnabled(false);
 	}
 
+	/**
+	 * Shows the position of the player this slot plays together with (see {@link jsettlers.common.menu.SharedPlayers}) instead of its own position,
+	 * the position cannot be changed as long as the slot is shown like that. This only changes the display, nothing is sent to the server.
+	 *
+	 * @param position
+	 * 		The position that is shown.
+	 * @param shared
+	 * 		true if the slot plays together with another slot.
+	 */
+	public void showSharedPosition(byte position, boolean shared) {
+		if (shared) {
+			adjustingDisplayedSlot = true;
+			try {
+				if (slotComboBox.getSelectedIndex() != position) {
+					slotComboBox.setSelectedIndex(position);
+				}
+			} finally {
+				adjustingDisplayedSlot = false;
+			}
+		}
+		slotComboBox.setEnabled(slotInputAllowed && !shared);
+		slotComboBox.setToolTipText(shared ? Labels.getString("join-game-panel-shared-player-tooltip") : null);
+	}
+
 	public void disableColorInput() {
 		colorComboBox.setEnabled(false);
 	}
@@ -351,7 +386,7 @@ public class PlayerSlot {
 	}
 
 	public void disableAllInputs() {
-		slotComboBox.setEnabled(false);
+		disableSlotInput();
 		disableCivilisationInput();
 		disableTeamInput();
 		disableColorInput();
PATCH_EOF
cat > "$WORK/patches/26-save-game-improvements.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
index 4466ffbda..cc5f6ac62 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
@@ -51,5 +51,10 @@ public enum EMessageType {
 	/**
 	 * A building has been finished but its worker cannot be created because there is no free carrier to become the worker.
 	 */
-	NO_FREE_BEARER
+	NO_FREE_BEARER,
+
+	/**
+	 * The game has been saved.
+	 */
+	GAME_SAVED
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
index c31d09956..ae87d303e 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
@@ -83,6 +83,9 @@ public class SimpleMessage implements IMessage {
 
 	@Override
 	public boolean duplicates(IMessage m) {
+		if (this.type == EMessageType.GAME_SAVED) {
+			return false; // every save is reported, and the message has no position
+		}
 		if ((m.getSender() == this.sender)
 				&& m.getMessageLabel().equals(this.messageLabel)
 				&& m.getType() == this.type) {
@@ -186,6 +189,15 @@ public class SimpleMessage implements IMessage {
 		return new SimpleMessage(EMessageType.NO_FREE_BEARER, "no_free_bearer_soldier|" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
 	}
 
+	/**
+	 * Creates the message that the game has been saved.
+	 *
+	 * @return The message object
+	 */
+	public static IMessage gameSaved() {
+		return new SimpleMessage(EMessageType.GAME_SAVED, "message_game_saved", (byte) -1, null);
+	}
+
 	/**
 	 *
 	 * @param at
diff --git a/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java b/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java
index f887f45d1..fc9459489 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java
@@ -38,10 +38,34 @@ public final class PlayerColors {
 	 * Makes the prepared colors the colors of the running game.
 	 */
 	public static void applyPrepared() {
-		set(preparedColors);
+		applyPrepared(null);
+	}
+
+	/**
+	 * Makes the prepared colors the colors of the running game. If no colors were prepared, the given colors (e.g. the colors saved in a saved
+	 * game) are used.
+	 *
+	 * @param colorsIfNotPrepared
+	 * 		The colors to use if no colors were prepared or <code>null</code> for the default colors.
+	 */
+	public static void applyPrepared(byte[] colorsIfNotPrepared) {
+		set(preparedColors != null ? preparedColors : colorsIfNotPrepared);
 		preparedColors = null;
 	}
 
+	/**
+	 * @param playerCount
+	 * 		The number of players.
+	 * @return The index of the color of every player of the running game, to store them in a saved game.
+	 */
+	public static byte[] getCurrentColors(int playerCount) {
+		byte[] colors = new byte[playerCount];
+		for (int i = 0; i < playerCount; i++) {
+			colors[i] = (byte) getColorIndex((byte) i);
+		}
+		return colors;
+	}
+
 	public static void reset() {
 		colorIndexByPlayerId = null;
 	}
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 6333ecca8..cf504ced9 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -528,6 +528,7 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 		case NO_FREE_BEARER:
 			return new Color(1f, 0.8f, 0.3f, alpha);
 		case MINERALS:
+		case GAME_SAVED:
 			return new Color(0.6f, 1f, 0.6f, alpha);
 		default:
 			return new Color(1, 1, 1, alpha);
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index f56f45d41..eca38c741 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -380,6 +380,7 @@ no_soldier_available_BIG_TOWER = Vaši velkou strážní věž nelze obsadit: ne
 no_soldier_available_CASTLE = Váš hrad nelze obsadit: není k dispozici žádný voják.
 message_missing_tool = %s nelze obsadit: chybí nástroj (%s).
 message_no_free_bearer = %s nelze obsadit: není k dispozici žádný volný osadník.
+message_game_saved = Hra uložena.
 message_no_free_bearer_soldier = %s nemůže zbrojit: není k dispozici žádný volný osadník.
 action_firerer_slow = Pozor! Hra reaguje pomalu.
 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 84004a547..424274195 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -386,6 +386,7 @@ no_soldier_available_BIG_TOWER = Your large guard tower can't be occupied: no so
 no_soldier_available_CASTLE = Your castle can't be occupied: no soldier is available.
 message_missing_tool = %s can't be occupied: tool missing (%s).
 message_no_free_bearer = %s can't be occupied: no free settler is available.
+message_game_saved = Game saved.
 message_no_free_bearer_soldier = %s can't arm soldiers: no free settler is available.
 action_firerer_slow = Warning! The game is responding slowly.
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
index 27be3242d..3dfc7b1fc 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiTaskExecutor.java
@@ -28,6 +28,7 @@ import jsettlers.common.CommonConstants;
 import jsettlers.common.action.EMoveToType;
 import jsettlers.common.buildings.IBuilding;
 import jsettlers.common.map.shapes.HexGridArea;
+import jsettlers.common.menu.messages.SimpleMessage;
 import jsettlers.common.movable.EMovableType;
 import jsettlers.common.position.ShortPoint2D;
 import jsettlers.common.selectable.ISelectable;
@@ -72,6 +73,7 @@ import jsettlers.logic.movable.interfaces.IFerryMovable;
 import jsettlers.logic.movable.interfaces.ILogicMovable;
 import jsettlers.logic.movable.interfaces.IMageMovable;
 import jsettlers.logic.movable.interfaces.IConvertibleToBearer;
+import jsettlers.logic.player.Player;
 import jsettlers.network.client.task.packets.TaskPacket;
 import jsettlers.network.synchronic.timer.ITaskExecutor;
 
@@ -305,6 +307,10 @@ class GuiTaskExecutor implements ITaskExecutor {
 	private void save() {
 		try {
 			grid.save(playerId, guiInterface.getUIState());
+			Player player = grid.getPlayer(playerId);
+			if (player != null) {
+				player.showMessage(SimpleMessage.gameSaved());
+			}
 		} catch (IOException | InterruptedException e) {
 			e.printStackTrace();
 		}
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
index fbd6efb2e..71e7c4054 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/grid/MainGrid.java
@@ -22,6 +22,8 @@ import java.util.BitSet;
 import java.util.Date;
 import java.util.Locale;
 import java.util.Set;
+import java.util.UUID;
+import java.nio.charset.StandardCharsets;
 
 import java.util.Optional;
 import jsettlers.algorithms.borders.BordersThread;
@@ -427,9 +429,14 @@ public final class MainGrid implements Serializable {
 			}
 		}
 
+		// The id of a saved game depends only on the game and the game time, so all computers of a network game create saves with the same id
+		// (every computer saves when one player saves) and the save can be loaded as a LAN game from each computer.
+		String saveId = UUID.nameUUIDFromBytes((mapId + "|" + MatchConstants.clock().getTime()).getBytes(StandardCharsets.UTF_8)).toString();
+
 		return new MapFileHeader(
 			MapType.SAVED_SINGLE,
 			mapName,
+			saveId,
 			mapId,
 			"TODO: description",
 			width,
@@ -439,7 +446,7 @@ public final class MainGrid implements Serializable {
 			new Date(),
 			bgImage,
 			playerId
-		);
+		).withPlayerColors(jsettlers.common.player.PlayerColors.getCurrentColors(playerConfigurations.length));
 	}
 
 	public ConstructionMarksGrid getConstructionMarksGrid() {
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/map/loading/newmap/MapFileHeader.java b/jsettlers.logic/src/main/java/jsettlers/logic/map/loading/newmap/MapFileHeader.java
index 7df437a50..c9191599c 100644
--- a/jsettlers.logic/src/main/java/jsettlers/logic/map/loading/newmap/MapFileHeader.java
+++ b/jsettlers.logic/src/main/java/jsettlers/logic/map/loading/newmap/MapFileHeader.java
@@ -55,7 +55,8 @@ public class MapFileHeader {
 	private static final short VERSION_DATE_ALWAYS_SAVED = 3;
 	private static final short VERSION_PLAYER_CONFIGURATIONS = 4;
 	private static final short VERSION_PLAYER_ID = 5;
-	private static final short VERSION = 5;
+	private static final short VERSION_PLAYER_COLORS = 6;
+	private static final short VERSION = 6;
 
 	private static final byte[] START_BYTES = new byte[] {
 			'M', 'A', 'P', ' '
@@ -72,6 +73,11 @@ public class MapFileHeader {
 	private final short height;
 	private final short minPlayers;
 	private final PlayerSetting[] playerSettings;
+
+	/**
+	 * The color of every player (index of the selectable color, see PlayerColors) or <code>null</code> if the header has no colors (default colors).
+	 */
+	private byte[] playerColors = null;
 	private final Date creationDate;
 	private final short[] previewImage;
 	private final Byte playerId;
@@ -96,7 +102,10 @@ public class MapFileHeader {
 		this(type, name, UUID.randomUUID().toString(), baseMapId, description, width, height, minPlayers, playerConfigurations, date, previewImage, playerId);
 	}
 
-	private MapFileHeader(MapType type, String name, String mapId, String baseMapId, String description, short width, short height, short minPlayers, PlayerSetting[] playerSettings, Date date,
+	/**
+	 * Creates a header with the given unique id. Saved games use this to get the same id on all computers of a network game.
+	 */
+	public MapFileHeader(MapType type, String name, String mapId, String baseMapId, String description, short width, short height, short minPlayers, PlayerSetting[] playerSettings, Date date,
 			short[] previewImage, Byte playerId) {
 		if (previewImage.length != PREVIEW_IMAGE_SIZE * PREVIEW_IMAGE_SIZE) {
 			throw new IllegalArgumentException("bg image has wrong size.");
@@ -155,6 +164,15 @@ public class MapFileHeader {
 		return playerSettings;
 	}
 
+	public byte[] getPlayerColors() {
+		return playerColors == null ? null : playerColors.clone();
+	}
+
+	public MapFileHeader withPlayerColors(byte[] playerColors) {
+		this.playerColors = playerColors == null ? null : playerColors.clone();
+		return this;
+	}
+
 	public Byte getPlayerId() {
 		return playerId;
 	}
@@ -184,6 +202,11 @@ public class MapFileHeader {
 
 		out.writeLong(creationDate.getTime());
 		out.writeByte(playerId == null ? -1 : playerId);
+
+		out.writeShort(playerColors == null ? 0 : playerColors.length);
+		if (playerColors != null) {
+			out.write(playerColors);
+		}
 		out.flush();
 	}
 
@@ -254,7 +277,17 @@ public class MapFileHeader {
 				playerId = bytePlayerId == -1 ? null : bytePlayerId;
 			}
 
-			return new MapFileHeader(type, mapName, mapId, baseMapId, description, width, height, minPlayers, playerConfigurations, date, bgImage, playerId);
+			byte[] playerColors = null;
+			if (version >= VERSION_PLAYER_COLORS) {
+				int colorCount = in.readShort();
+				if (colorCount > 0) {
+					playerColors = new byte[colorCount];
+					in.readFully(playerColors);
+				}
+			}
+
+			return new MapFileHeader(type, mapName, mapId, baseMapId, description, width, height, minPlayers, playerConfigurations, date, bgImage, playerId)
+					.withPlayerColors(playerColors);
 
 		} catch (Throwable t) {
 			if (t instanceof IOException) {
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
index a3bba0dd8..176e98d06 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
@@ -100,7 +100,12 @@ public class JSettlersGame {
 			boolean controlAll, boolean multiplayer, DataInputStream replayFileInputStream) {
 		configureLogging(mapCreator);
 
-		jsettlers.common.player.PlayerColors.applyPrepared();
+		// the colors chosen in the lobby, or the colors stored in a saved game
+		byte[] savedColors = null;
+		if (mapCreator instanceof MapLoader && ((MapLoader) mapCreator).getFileHeader() != null) {
+			savedColors = ((MapLoader) mapCreator).getFileHeader().getPlayerColors();
+		}
+		jsettlers.common.player.PlayerColors.applyPrepared(savedColors);
 		this.initialGameState = initialGameState;
 
 		System.out.println("OS version: " + System.getProperty("os.name") + " " + System.getProperty("os.arch") + " "
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 8fd1274e7..78a923ada 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -640,6 +640,17 @@ public class JoinGamePanel extends BackgroundPanel {
 		return (byte) teams.indexOf(team != null ? team : (byte) savedGamePositions[slot]);
 	}
 
+	/**
+	 * @return The color the player at the given position had in the saved game.
+	 */
+	private byte savedGameColor(int position) {
+		byte[] savedColors = mapLoader.getFileHeader().getPlayerColors();
+		if (savedColors != null && position >= 0 && position < savedColors.length) {
+			return savedColors[position];
+		}
+		return (byte) position;
+	}
+
 	private void buildSavedGamePlayerSlots() {
 		PlayerSetting[] settings = mapLoader.getFileHeader().getPlayerSettings();
 		playerSlots.clear();
@@ -650,7 +661,7 @@ public class JoinGamePanel extends BackgroundPanel {
 			int position = savedGamePositions[i];
 			PlayerSetting setting = settings[position];
 			playerSlot.setSlot((byte) position, true);
-			playerSlot.setColor((byte) position, true);
+			playerSlot.setColor(savedGameColor(position), true);
 			playerSlot.setPreviewListener(this::refreshPreview);
 			playerSlot.setTeam(savedGameTeamNumber(settings, i), true);
 			if (setting.getCivilisation() != null) {
@@ -677,7 +688,7 @@ public class JoinGamePanel extends BackgroundPanel {
 				connector.setCivilisation(i, setting.getCivilisation());
 			}
 			connector.setTeam(i, savedGameTeamNumber(settings, i));
-			connector.setColor(i, (byte) position);
+			connector.setColor(i, savedGameColor(position));
 			if (i > 0 && setting.getPlayerType() != null) { // the first slot is the host
 				connector.setType(i, setting.getPlayerType());
 			}
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/MapListCellRenderer.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/MapListCellRenderer.java
index d7b309f40..33e0111a2 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/MapListCellRenderer.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/openpanel/MapListCellRenderer.java
@@ -130,6 +130,11 @@ public class MapListCellRenderer implements ListCellRenderer<MapLoader> {
 	 */
 	private final SimpleDateFormat df = new SimpleDateFormat(Labels.getString("date.date-only"));
 
+	/**
+	 * Format for the time that is shown after the date, so saved games of the same day can be told apart.
+	 */
+	private final SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm:ss");
+
 	/**
 	 * Cache for preview images
 	 */
@@ -213,7 +218,7 @@ public class MapListCellRenderer implements ListCellRenderer<MapLoader> {
 		mapNameLabel.setText(value.getMapName());
 		String date = "???";
 		if (value.getCreationDate() != null) {
-			date = df.format(value.getCreationDate());
+			date = df.format(value.getCreationDate()) + " " + timeFormat.format(value.getCreationDate());
 		}
 
 		mapIdLabel.setText(date + " / " + value.getMapId());
PATCH_EOF
cat > "$WORK/patches/27-ingame-chat.patch" <<'PATCH_EOF'
diff --git a/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java b/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
index 859fdf9da..58dfdd61d 100644
--- a/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
+++ b/go.graphics.swing/src/main/java/go/graphics/swing/event/swingInterpreter/GOSwingEventConverter.java
@@ -14,6 +14,7 @@
  *******************************************************************************/
 package go.graphics.swing.event.swingInterpreter;
 
+import go.graphics.event.TextInput;
 import java.awt.Component;
 import java.awt.GraphicsConfiguration;
 import java.awt.GraphicsDevice;
@@ -174,12 +175,50 @@ public class GOSwingEventConverter extends AbstractEventConverter
 		}
 	}
 
+	private volatile boolean enterHeld = false;
+
 	@Override
 	public void keyPressed(KeyEvent e) {
 		updateModifiers(e);
 		if (isModifierKey(e)) {
 			return; // a modifier key alone is no key event, it would block the next key (e.g. Control + 1) until it is released
 		}
+		if (e.getKeyCode() == KeyEvent.VK_ENTER) {
+			// Enter starts and finishes the text input (chat); a held key must not do both
+			if (enterHeld) {
+				return;
+			}
+			TextInput.Listener enterListener = TextInput.getListener();
+			if (enterListener != null) {
+				enterHeld = true;
+				enterListener.enterPressed();
+				return;
+			}
+			if (!isKeyEventOngoing() && TextInput.start()) {
+				enterHeld = true;
+				return;
+			}
+		}
+		TextInput.Listener textInput = TextInput.getListener();
+		if (textInput != null) {
+			// the keyboard is used to type text: only the keys that edit or finish the text are handled, the others are typed (keyTyped)
+			if (!isKeyEventOngoing()) { // the key that started the text input may still be held down
+				switch (e.getKeyCode()) {
+				case KeyEvent.VK_ENTER:
+					textInput.enterPressed();
+					break;
+				case KeyEvent.VK_ESCAPE:
+					textInput.escapePressed();
+					break;
+				case KeyEvent.VK_BACK_SPACE:
+					textInput.backspacePressed();
+					break;
+				default:
+					break;
+				}
+			}
+			return;
+		}
 		String text = getKeyName(e);
 		startKeyEvent(text);
 		/*
@@ -271,6 +310,9 @@ public class GOSwingEventConverter extends AbstractEventConverter
 			case KeyEvent.VK_TAB:
 				text = "TAB";
 				break;
+			case KeyEvent.VK_ENTER:
+				text = "\n";
+				break;
 			default:
 				text = "" + e.getKeyChar();
 			}
@@ -281,6 +323,9 @@ public class GOSwingEventConverter extends AbstractEventConverter
 	@Override
 	public void keyReleased(KeyEvent e) {
 		updateModifiers(e);
+		if (e.getKeyCode() == KeyEvent.VK_ENTER) {
+			enterHeld = false;
+		}
 		if (isModifierKey(e)) {
 			return;
 		}
@@ -295,6 +340,13 @@ public class GOSwingEventConverter extends AbstractEventConverter
 
 	@Override
 	public void keyTyped(KeyEvent e) {
+		TextInput.Listener textInput = TextInput.getListener();
+		if (textInput != null && !isKeyEventOngoing()) {
+			char character = e.getKeyChar();
+			if (character != KeyEvent.CHAR_UNDEFINED && !Character.isISOControl(character)) {
+				textInput.characterTyped(character);
+			}
+		}
 	}
 
 	@Override
diff --git a/go.graphics/src/main/java/go/graphics/event/TextInput.java b/go.graphics/src/main/java/go/graphics/event/TextInput.java
new file mode 100644
index 000000000..3ad42e9f1
--- /dev/null
+++ b/go.graphics/src/main/java/go/graphics/event/TextInput.java
@@ -0,0 +1,82 @@
+package go.graphics.event;
+
+/**
+ * Lets a part of the user interface take over the keyboard to type text (for example the chat of a network game).
+ * <p>
+ * While a {@link Listener} is registered, the keyboard does not trigger the usual key events (hotkeys); the typed characters and the keys Enter,
+ * Escape and Backspace are passed to the listener instead.
+ */
+public final class TextInput {
+	/**
+	 * Receives the typed text.
+	 */
+	public interface Listener {
+		/**
+		 * A printable character was typed.
+		 */
+		void characterTyped(char character);
+
+		/**
+		 * Backspace was pressed.
+		 */
+		void backspacePressed();
+
+		/**
+		 * Enter was pressed: the text is finished.
+		 */
+		void enterPressed();
+
+		/**
+		 * Escape was pressed: the text is cancelled.
+		 */
+		void escapePressed();
+	}
+
+	private static volatile Listener listener = null;
+	private static volatile Runnable starter = null;
+
+	private TextInput() {
+	}
+
+	/**
+	 * Registers the listener that gets the typed text, or removes the current one if <code>null</code> is given.
+	 */
+	public static void setListener(Listener newListener) {
+		listener = newListener;
+	}
+
+	/**
+	 * @return The listener that gets the typed text, or <code>null</code> if the keyboard works as usual.
+	 */
+	public static Listener getListener() {
+		return listener;
+	}
+
+	/**
+	 * Registers the action that starts the text input when the Enter key is pressed, or removes the current one if <code>null</code> is given.
+	 */
+	public static void setStarter(Runnable newStarter) {
+		starter = newStarter;
+	}
+
+	/**
+	 * Starts the text input, if a starter is registered.
+	 *
+	 * @return True if a starter was registered (and called).
+	 */
+	public static boolean start() {
+		Runnable current = starter;
+		if (current == null) {
+			return false;
+		}
+		current.run();
+		return true;
+	}
+
+	/**
+	 * @return True if the keyboard is currently used to type text.
+	 */
+	public static boolean isActive() {
+		return listener != null;
+	}
+}
diff --git a/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java b/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
index eb00550a7..c5ee2ec9d 100644
--- a/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
+++ b/go.graphics/src/main/java/go/graphics/event/interpreter/AbstractEventConverter.java
@@ -229,6 +229,13 @@ public class AbstractEventConverter {
 		}
 	}
 
+	/**
+	 * @return True if a key is currently held that started a key event.
+	 */
+	protected synchronized boolean isKeyEventOngoing() {
+		return ongoingKeyEvent != null;
+	}
+
 	protected synchronized void endKeyEvent(String string) {
 		if (ongoingKeyEvent != null) {
 			ongoingKeyEvent.released();
diff --git a/jsettlers.common/src/main/java/jsettlers/common/action/ChatAction.java b/jsettlers.common/src/main/java/jsettlers/common/action/ChatAction.java
new file mode 100644
index 000000000..03976f248
--- /dev/null
+++ b/jsettlers.common/src/main/java/jsettlers/common/action/ChatAction.java
@@ -0,0 +1,21 @@
+package jsettlers.common.action;
+
+/**
+ * Action to send a chat message: {@link EActionType#SEND_CHAT_MESSAGE}.
+ */
+public class ChatAction extends Action {
+	private final String text;
+
+	/**
+	 * @param text
+	 *            The text of the message.
+	 */
+	public ChatAction(String text) {
+		super(EActionType.SEND_CHAT_MESSAGE);
+		this.text = text;
+	}
+
+	public String getText() {
+		return text;
+	}
+}
diff --git a/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java b/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
index 5f7931c95..a38735db4 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java
@@ -127,6 +127,18 @@ public enum EActionType {
 	 */
 	RECALL_GROUP,
 
+	/**
+	 * Starts typing a chat message (network games only).
+	 */
+	OPEN_CHAT,
+
+	/**
+	 * Sends a chat message to the other players of a network game.
+	 *
+	 * @see ChatAction
+	 */
+	SEND_CHAT_MESSAGE,
+
 	/**
 	 * Sets the screen to display current message.
 	 */
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/IInGameChat.java b/jsettlers.common/src/main/java/jsettlers/common/menu/IInGameChat.java
new file mode 100644
index 000000000..478ec2e7d
--- /dev/null
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/IInGameChat.java
@@ -0,0 +1,41 @@
+package jsettlers.common.menu;
+
+/**
+ * The chat between the players of a network game, while the game is running.
+ */
+public interface IInGameChat {
+	/**
+	 * Receives the chat messages of all players (including the own ones).
+	 */
+	interface IReceiver {
+		/**
+		 * @param playerId
+		 *            The id of the player in the game (gives the color), or -1 if the sender is not known.
+		 * @param playerName
+		 *            The name of the sender.
+		 * @param text
+		 *            The text of the message.
+		 */
+		void chatMessageReceived(byte playerId, String playerName, String text);
+	}
+
+	/**
+	 * Sends a message to all players of the game.
+	 */
+	void sendMessage(String text);
+
+	/**
+	 * Sets the receiver of the messages, <code>null</code> to remove it.
+	 */
+	void setReceiver(IReceiver receiver);
+
+	/**
+	 * @return The id of the own player in the game.
+	 */
+	byte getOwnPlayerId();
+
+	/**
+	 * @return The name of the own player.
+	 */
+	String getOwnPlayerName();
+}
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/IMapInterfaceConnector.java b/jsettlers.common/src/main/java/jsettlers/common/menu/IMapInterfaceConnector.java
index f15a38315..d7384e9c8 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/IMapInterfaceConnector.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/IMapInterfaceConnector.java
@@ -84,4 +84,15 @@ public interface IMapInterfaceConnector extends IMessenger {
 	void fireAction(IAction action);
 
 	void playSound(int soundId, float volume);
+
+	/**
+	 * Allows the user to write chat messages (network games).
+	 *
+	 * @param ownPlayerId
+	 *            The id of the own player in the game, this gives the color of the own messages.
+	 * @param ownPlayerName
+	 *            The name of the own player.
+	 */
+	default void enableChat(byte ownPlayerId, String ownPlayerName) {
+	}
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
index cc5f6ac62..49d0e0b8f 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
@@ -56,5 +56,10 @@ public enum EMessageType {
 	/**
 	 * The game has been saved.
 	 */
-	GAME_SAVED
+	GAME_SAVED,
+
+	/**
+	 * A general information for the user, the label is a key of the language files.
+	 */
+	INFO
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/IMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/IMessage.java
index 5807ba551..e34f6d7bc 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/IMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/IMessage.java
@@ -64,6 +64,15 @@ public interface IMessage {
 	 */
 	byte getSender();
 
+	/**
+	 * Gets the name of the sender of a chat message.
+	 *
+	 * @return The name or <code>null</code> if the message has no sender name (then the name is derived from {@link #getSender()}).
+	 */
+	default String getSenderName() {
+		return null;
+	}
+
 	/**
 	 * gets the position where the event occured.
 	 * 
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
index ae87d303e..8ce2b84df 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
@@ -28,6 +28,7 @@ public class SimpleMessage implements IMessage {
 	private final ShortPoint2D pos;
 	private final String messageLabel;
 	private final EMessageType type;
+	private final String senderName;
 	private int age;
 
 	/**
@@ -43,6 +44,11 @@ public class SimpleMessage implements IMessage {
 	 * 		The position the messageLabel was sent from.
 	 */
 	private SimpleMessage(EMessageType type, String messageLabel, byte sender, ShortPoint2D pos) {
+		this(type, messageLabel, sender, null, pos);
+	}
+
+	private SimpleMessage(EMessageType type, String messageLabel, byte sender, String senderName, ShortPoint2D pos) {
+		this.senderName = senderName;
 		this.type = type;
 		this.messageLabel = messageLabel;
 		this.sender = sender;
@@ -76,6 +82,11 @@ public class SimpleMessage implements IMessage {
 		return sender;
 	}
 
+	@Override
+	public String getSenderName() {
+		return senderName;
+	}
+
 	@Override
 	public ShortPoint2D getPosition() {
 		return pos;
@@ -83,8 +94,8 @@ public class SimpleMessage implements IMessage {
 
 	@Override
 	public boolean duplicates(IMessage m) {
-		if (this.type == EMessageType.GAME_SAVED) {
-			return false; // every save is reported, and the message has no position
+		if (this.type == EMessageType.GAME_SAVED || this.type == EMessageType.INFO || this.type == EMessageType.CHAT) {
+			return false; // these messages are always shown and have no position
 		}
 		if ((m.getSender() == this.sender)
 				&& m.getMessageLabel().equals(this.messageLabel)
@@ -189,6 +200,32 @@ public class SimpleMessage implements IMessage {
 		return new SimpleMessage(EMessageType.NO_FREE_BEARER, "no_free_bearer_soldier|" + building.getBuildingVariant().getType(), (byte) -1, building.getPosition());
 	}
 
+	/**
+	 * Creates a chat message of a player of a network game.
+	 *
+	 * @param sender
+	 * 		The id of the player in the game, this gives the color of the message.
+	 * @param senderName
+	 * 		The name of the player.
+	 * @param text
+	 * 		The text the player wrote.
+	 * @return The message object
+	 */
+	public static IMessage chat(byte sender, String senderName, String text) {
+		return new SimpleMessage(EMessageType.CHAT, text, sender, senderName, null);
+	}
+
+	/**
+	 * Creates a general information for the user.
+	 *
+	 * @param label
+	 * 		The key of the text in the language files.
+	 * @return The message object
+	 */
+	public static IMessage info(String label) {
+		return new SimpleMessage(EMessageType.INFO, label, (byte) -1, null);
+	}
+
 	/**
 	 * Creates the message that the game has been saved.
 	 *
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index cf504ced9..409485cb4 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
@@ -33,6 +33,7 @@ import go.graphics.event.GOEvent;
 import go.graphics.event.GOEventHandler;
 import go.graphics.event.GOKeyEvent;
 import go.graphics.event.GOModalEventHandler;
+import go.graphics.event.TextInput;
 import go.graphics.event.command.EModifier;
 import go.graphics.event.command.GOCommandEvent;
 import go.graphics.event.mouse.GODrawEvent;
@@ -48,6 +49,7 @@ import jsettlers.common.Color;
 import jsettlers.common.CommitInfo;
 import jsettlers.common.CommonConstants;
 import jsettlers.common.action.Action;
+import jsettlers.common.action.ChatAction;
 import jsettlers.common.action.EActionType;
 import jsettlers.common.action.GroupAction;
 import jsettlers.common.action.IAction;
@@ -96,6 +98,7 @@ import jsettlers.graphics.map.draw.Background;
 import jsettlers.graphics.map.draw.DrawConstants;
 import jsettlers.graphics.map.draw.ImageProvider;
 import jsettlers.graphics.map.draw.MapObjectDrawer;
+import jsettlers.common.menu.messages.SimpleMessage;
 import jsettlers.graphics.messages.Messenger;
 import jsettlers.graphics.sound.BackgroundSound;
 import jsettlers.graphics.sound.MusicManager;
@@ -492,8 +495,11 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 	 */
 	private static String getMessageText(IMessage m) {
 		String label = m.getMessageLabel();
+		if (m.getType() == EMessageType.CHAT) {
+			return label; // the text the player wrote
+		}
 		String text = Labels.getString(label);
-		if (m.getType() == EMessageType.CHAT || !text.equals(label)) {
+		if (!text.equals(label)) {
 			return text;
 		}
 		if (label.startsWith("missing_tool|")) {
@@ -563,28 +569,145 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 			float y = offsetY + messageIndex * lineHeight * yDirection;
 			float a = messageAlpha(m);
 			float startX = x;
-			if (m.getSender() >= 0) {
-				String name = getPlayername(m.getSender()) + ":";
-				Color color = MapDrawContext.getPlayerColor(m.getSender());
-				float width = drawer.getWidth(name);
-				for (int i = -1; i < 3; i++) {
-					drawer.drawString(x + i, y - 1, new Color(1, 1, 1, a/2), name);
-				}
-				drawer.drawString(x, y, new Color(color.getRed(), color.getGreen(), color.getBlue(), a), name);
-				x += width + 10;
+			if (m.getSender() >= 0 || m.getSenderName() != null) {
+				String name = (m.getSenderName() != null ? m.getSenderName() : getPlayername(m.getSender())) + ":";
+				x += drawOutlinedText(drawer, x, y, getPlayerMessageColor(m.getSender(), a), a, name) + 10;
 			}
 
 			String text = getMessageText(m);
-			drawer.drawString(x, y, getMessageColor(m, a), text);
+			if (m.getType() == EMessageType.CHAT) {
+				// chat messages have the color of the player who wrote them
+				drawOutlinedText(drawer, x, y, getPlayerMessageColor(m.getSender(), a), a, text);
+			} else {
+				drawer.drawString(x, y, getMessageColor(m, a), text);
+			}
 			if (m.getPosition() != null) {
 				areas.add(new MessageArea(startX, y - lineHeight * 0.2f, x - startX + drawer.getWidth(text), lineHeight, m.getPosition()));
 			}
 
 			messageIndex++;
 		}
+
+		if (chatTyping) {
+			// the message the user is writing, in the color of the own player
+			float y = offsetY + messageIndex * lineHeight * yDirection;
+			String name = chatPlayerName + ":";
+			Color color = getPlayerMessageColor(chatPlayerId, 1f);
+			float x = offsetX + drawOutlinedText(drawer, offsetX, y, color, 1f, name) + 10;
+			String typed;
+			synchronized (chatInput) {
+				typed = chatInput.toString();
+			}
+			drawOutlinedText(drawer, x, y, color, 1f, typed + ((System.currentTimeMillis() / 500) % 2 == 0 ? "_" : " "));
+		}
 		messageAreas = areas.toArray(new MessageArea[0]);
 	}
 
+	private static Color getPlayerMessageColor(byte playerId, float alpha) {
+		if (playerId < 0) {
+			return new Color(1, 1, 1, alpha);
+		}
+		Color color = MapDrawContext.getPlayerColor(playerId);
+		return new Color(color.getRed(), color.getGreen(), color.getBlue(), alpha);
+	}
+
+	/**
+	 * Draws a text with a dark shadow, so that it can be read in every player color. The shadow has the same transparency as the text, so that both
+	 * fade together (the text drawer discards everything that is less than half opaque).
+	 *
+	 * @return The width of the text.
+	 */
+	private static float drawOutlinedText(TextDrawer drawer, float x, float y, Color color, float alpha, String text) {
+		drawer.drawString(x + 1, y - 1, new Color(0, 0, 0, alpha), text);
+		drawer.drawString(x, y, color, text);
+		return drawer.getWidth(text);
+	}
+
+	// ---- chat of network games ----
+
+	private static final int CHAT_MAX_LENGTH = 100;
+
+	private volatile boolean chatEnabled = false;
+	private volatile boolean chatTyping = false;
+	private volatile byte chatPlayerId = -1;
+	private volatile String chatPlayerName = "";
+	private final StringBuilder chatInput = new StringBuilder();
+
+	private final TextInput.Listener chatInputListener = new TextInput.Listener() {
+		@Override
+		public void characterTyped(char character) {
+			synchronized (chatInput) {
+				if (chatInput.length() < CHAT_MAX_LENGTH) {
+					chatInput.append(character);
+				}
+			}
+		}
+
+		@Override
+		public void backspacePressed() {
+			synchronized (chatInput) {
+				if (chatInput.length() > 0) {
+					chatInput.setLength(chatInput.length() - 1);
+				}
+			}
+		}
+
+		@Override
+		public void enterPressed() {
+			String text;
+			synchronized (chatInput) {
+				text = chatInput.toString().trim();
+			}
+			stopChatInput();
+			if (!text.isEmpty()) {
+				getInterfaceConnector().fireAction(new ChatAction(text));
+			}
+		}
+
+		@Override
+		public void escapePressed() {
+			stopChatInput();
+		}
+	};
+
+	/**
+	 * Allows the user to write chat messages.
+	 */
+	public void enableChat(byte ownPlayerId, String ownPlayerName) {
+		this.chatPlayerId = ownPlayerId;
+		this.chatPlayerName = ownPlayerName != null ? ownPlayerName : "";
+		this.chatEnabled = true;
+		TextInput.setStarter(this::startChatInput);
+	}
+
+	/**
+	 * Starts typing a chat message: the keyboard is used for the text until Enter or Escape is pressed.
+	 */
+	private void startChatInput() {
+		if (!chatEnabled) {
+			synchronized (messenger) {
+				messenger.addMessage(SimpleMessage.info("message_chat_only_in_network_games"));
+			}
+			return;
+		}
+		synchronized (chatInput) {
+			chatInput.setLength(0);
+		}
+		chatTyping = true;
+		TextInput.setListener(chatInputListener);
+	}
+
+	private void stopChatInput() {
+		if (TextInput.getListener() == chatInputListener) {
+			TextInput.setListener(null);
+		}
+		chatTyping = false;
+	}
+
+	private static boolean isEnterKey(String keyCode) {
+		return "\n".equals(keyCode) || "\r".equals(keyCode) || "ENTER".equalsIgnoreCase(keyCode);
+	}
+
 	private String getPlayername(byte sender) {
 		// TODO: Player names
 		return "player " + sender;
@@ -843,6 +966,10 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 			Optional<Action> action = getActionForCommand(commandEvent);
 			// also set when action was null, to abort drawing.
 			fireActionEvent(event, action);
+		} else if (event instanceof GOKeyEvent && isEnterKey(((GOKeyEvent) event).getKeyCode())) {
+			if (chatEnabled && !chatTyping) {
+				startChatInput();
+			}
 		} else if (event instanceof GOKeyEvent) {
 			Optional<Action> actionForKeyboard = Optional.ofNullable(getActionForKeyboard(((GOKeyEvent) event).getKeyCode()));
 			actionForKeyboard.ifPresent(action -> 
@@ -1243,6 +1370,10 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 	@Override
 	public void fireAction(IAction action) {
+		if (action.getActionType() == EActionType.OPEN_CHAT) {
+			startChatInput();
+			return;
+		}
 		IAction fire = controls.replaceAction(action);
 		if (fire != null) {
 			getInterfaceConnector().fireAction(fire);
@@ -1260,6 +1391,8 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 	}
 
 	public void stop() {
+		stopChatInput();
+		TextInput.setStarter(null);
 		musicManager.stopMusic();
 		backgroundSound.stop();
 		controls.stop();
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapInterfaceConnector.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapInterfaceConnector.java
index 6d5ff9dea..e0d19c862 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapInterfaceConnector.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapInterfaceConnector.java
@@ -67,6 +67,11 @@ public class MapInterfaceConnector implements ActionFireable, IMapInterfaceConne
 	 * @param selection
 	 *            The selection.
 	 */
+	@Override
+	public void enableChat(byte ownPlayerId, String ownPlayerName) {
+		this.content.enableChat(ownPlayerId, ownPlayerName);
+	}
+
 	@Override
 	public void setSelection(ISelectionSet selection) {
 		this.content.setSelection(selection);
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
index c33bda95f..21054ae3e 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/controls/original/OriginalControls.java
@@ -65,6 +65,7 @@ public class OriginalControls implements IControls {
 	private final MinimapMode minimapSettings = new MinimapMode();
 	private final MainPanel mainPanel;
 	private final Button chatButton;
+	private ActionFireable actionFireable;
 
 	private ControlPanelLayoutProperties layoutProperties;
 	private UIPanel uiBase;
@@ -321,32 +322,14 @@ public class OriginalControls implements IControls {
 	}
 
 	/**
-	 * This should one day display the chat.
+	 * Starts typing a chat message (the same as pressing Enter).
 	 */
 	private final class ShowChatAction extends ExecutableAction {
-		private final MessageContent messageContent = new MessageContent(
-				"This is not yet implemented.",
-				"Cancel",
-				new ExecutableAction() {
-					@Override
-					public void execute() {
-						mainPanel.setContent(ContentType.BUILD_NORMAL);
-						chatButton.setActive(false);
-					}
-				},
-				"Ok",
-				new ExecutableAction() {
-					@Override
-					public void execute() {
-						mainPanel.setContent(ContentType.BUILD_NORMAL);
-						chatButton.setActive(false);
-					}
-				});
-
 		@Override
 		public void execute() {
-			mainPanel.setContent(messageContent);
-			chatButton.setActive(true); // TODO needs to be unset when content changes.
+			if (actionFireable != null) {
+				actionFireable.fireAction(new Action(EActionType.OPEN_CHAT));
+			}
 		}
 	}
 
@@ -424,6 +407,7 @@ public class OriginalControls implements IControls {
 
 	@Override
 	public void setDrawContext(ActionFireable actionFireable, MapDrawContext context) {
+		this.actionFireable = actionFireable;
 		this.context = context;
 		this.minimap = new Minimap(context, minimapSettings);
 	}
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
index eca38c741..155922671 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties
@@ -381,6 +381,7 @@ no_soldier_available_CASTLE = Váš hrad nelze obsadit: není k dispozici žádn
 message_missing_tool = %s nelze obsadit: chybí nástroj (%s).
 message_no_free_bearer = %s nelze obsadit: není k dispozici žádný volný osadník.
 message_game_saved = Hra uložena.
+message_chat_only_in_network_games = Chat je dostupný jen v síťové hře. Zprávu napíšeš po stisku Enter.
 message_no_free_bearer_soldier = %s nemůže zbrojit: není k dispozici žádný volný osadník.
 action_firerer_slow = Pozor! Hra reaguje pomalu.
 
diff --git a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
index 424274195..3bfdb7197 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -387,6 +387,7 @@ no_soldier_available_CASTLE = Your castle can't be occupied: no soldier is avail
 message_missing_tool = %s can't be occupied: tool missing (%s).
 message_no_free_bearer = %s can't be occupied: no free settler is available.
 message_game_saved = Game saved.
+message_chat_only_in_network_games = Chat is only available in network games. Press Enter to write a message.
 message_no_free_bearer_soldier = %s can't arm soldiers: no free settler is available.
 action_firerer_slow = Warning! The game is responding slowly.
 
diff --git a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
index 3e830ba33..81e4e3ea5 100644
--- a/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
+++ b/jsettlers.logic/src/main/java/jsettlers/input/GuiInterface.java
@@ -31,6 +31,8 @@ import java.util.stream.Collectors;
 import jsettlers.algorithms.construction.ConstructionMarksThread;
 import jsettlers.common.CommonConstants;
 import jsettlers.common.action.BuildAction;
+import jsettlers.common.action.ChatAction;
+import jsettlers.common.menu.IInGameChat;
 import jsettlers.common.action.CastSpellAction;
 import jsettlers.common.action.ChangeTradingRequestAction;
 import jsettlers.common.action.GroupAction;
@@ -148,6 +150,15 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 		return groups;
 	}
 
+	private volatile IInGameChat chat;
+
+	/**
+	 * Sets the chat of a network game, so chat messages written by the user are sent to the other players.
+	 */
+	public void setChat(IInGameChat chat) {
+		this.chat = chat;
+	}
+
 	public GuiInterface(IMapInterfaceConnector connector, IGameClock clock, ITaskScheduler taskScheduler, IGuiInputGrid grid, IGameStoppable gameStoppable, byte playerId, boolean multiplayer) {
 		this.connector = connector;
 		this.clock = clock;
@@ -324,6 +335,12 @@ public class GuiInterface implements IMapInterfaceListener, ITaskExecutorGuiInte
 				}
 				break;
 
+			case SEND_CHAT_MESSAGE:
+				if (chat != null) {
+					chat.sendMessage(((ChatAction) action).getText());
+				}
+				break;
+
 			case SAVE:
 				taskScheduler.scheduleTask(new SimpleGuiTask(EGuiAction.QUICK_SAVE, playerId));
 				break;
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
index 176e98d06..dd330cf6e 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/JSettlersGame.java
@@ -34,7 +34,9 @@ import jsettlers.common.logging.MultiplexingOutputStream;
 import jsettlers.common.map.IGraphicsGrid;
 import jsettlers.common.menu.EGameError;
 import jsettlers.common.menu.EProgressState;
+import jsettlers.common.menu.IInGameChat;
 import jsettlers.common.menu.IMapInterfaceConnector;
+import jsettlers.common.menu.messages.SimpleMessage;
 import jsettlers.common.menu.IStartedGame;
 import jsettlers.common.menu.IStartingGame;
 import jsettlers.common.menu.IStartingGameListener;
@@ -84,6 +86,7 @@ public class JSettlersGame {
 	private final IGameCreator mapCreator;
 	private final INetworkConnector networkConnector;
 	private final boolean multiplayer;
+	private IInGameChat chat;
 	private final DataInputStream replayFileInputStream;
 
 	private final GameRunner gameRunner;
@@ -135,6 +138,13 @@ public class JSettlersGame {
 	 * @param mapCreator
 	 * @param networkConnector
 	 */
+	/**
+	 * Sets the chat between the players of a network game. Must be called before the game is started.
+	 */
+	public void setChat(IInGameChat chat) {
+		this.chat = chat;
+	}
+
 	public JSettlersGame(IGameCreator mapCreator, INetworkConnector networkConnector, InitialGameState initialGameState) {
 		this(mapCreator, networkConnector, initialGameState, CommonConstants.CONTROL_ALL, true, null);
 	}
@@ -249,6 +259,11 @@ public class JSettlersGame {
 				final IMapInterfaceConnector connector = startingGameListener.preLoadFinished(this);
 				GuiInterface guiInterface = new GuiInterface(connector, MatchConstants.clock(), networkConnector.getTaskScheduler(),
 						mainGrid.getGuiInputGrid(), this, initialGameState.getPlayerId(), multiplayer);
+				if (chat != null) {
+					guiInterface.setChat(chat);
+					connector.enableChat(chat.getOwnPlayerId(), chat.getOwnPlayerName());
+					chat.setReceiver((playerId, playerName, text) -> connector.showMessage(SimpleMessage.chat(playerId, playerName, text)));
+				}
 				connector.loadUIState(playerState.getUiState()); // This is required after the GuiInterface instantiation so that
 				// ConstructionMarksThread has it's mapArea variable initialized via the EActionType.SCREEN_CHANGE event.
 
@@ -275,6 +290,9 @@ public class JSettlersGame {
 
 				networkConnector.shutdown();
 				mainGrid.stopThreads();
+				if (chat != null) {
+					chat.setReceiver(null);
+				}
 				connector.shutdown();
 				guiInterface.stop();
 				clearState();
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
index cd853602c..42646aa3f 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
@@ -25,6 +25,7 @@ import java.util.stream.IntStream;
 import jsettlers.common.ai.EPlayerType;
 import jsettlers.common.menu.ENetworkMessage;
 import jsettlers.common.menu.IChatMessageListener;
+import jsettlers.common.menu.IInGameChat;
 import jsettlers.common.menu.IJoinPhaseMultiplayerGameConnector;
 import jsettlers.common.menu.IJoiningGame;
 import jsettlers.common.menu.IJoiningGameListener;
@@ -68,6 +69,7 @@ public class MultiplayerGame {
 	private IJoiningGameListener joiningGameListener;
 	private IMultiplayerListener multiplayerListener;
 	private IChatMessageListener chatMessageListener;
+	private volatile InGameChat inGameChat;
 	private boolean iAmTheHost = false;
 	private int maxPlayers;
 
@@ -122,12 +124,73 @@ public class MultiplayerGame {
 
 	private IPacketReceiver<ChatMessagePacket> generateChatMessageReceiver() {
 		return packet -> {
+			InGameChat gameChat = inGameChat;
+			if (gameChat != null && gameChat.deliver(packet.getAuthorId(), packet.getMessage())) {
+				return; // the game is running: the message is shown in the game
+			}
 			if (chatMessageListener != null) {
 				chatMessageListener.chatMessageReceived(packet.getAuthorId(), packet.getMessage());
 			}
 		};
 	}
 
+	/**
+	 * The chat while the game is running. Remembers the names and positions of the players of the start of the game.
+	 */
+	private final class InGameChat implements IInGameChat {
+		private final byte ownPlayerId;
+		private final String ownPlayerName;
+		private final Map<String, Byte> playerIds = new java.util.HashMap<>();
+		private final Map<String, String> playerNames = new java.util.HashMap<>();
+		private volatile IReceiver receiver;
+
+		InGameChat(byte ownPlayerId) {
+			this.ownPlayerId = ownPlayerId;
+			List<? extends IMultiplayerSlot> allSlots = slotList.getItems();
+			byte[] playerPositions = jsettlers.common.menu.SharedPlayers.playerPositions(allSlots);
+			for (int i = 0; i < allSlots.size(); i++) {
+				IMultiplayerPlayer player = allSlots.get(i).getPlayer();
+				if (player != null) {
+					playerIds.put(player.getId(), playerPositions[i]);
+					playerNames.put(player.getId(), player.getName());
+				}
+			}
+			String name = networkClient.getPlayerInfo().getName();
+			this.ownPlayerName = name != null ? name : playerNames.get(networkClient.getPlayerInfo().getId());
+		}
+
+		@Override
+		public void sendMessage(String text) {
+			networkClient.sendChatMessage(text);
+		}
+
+		@Override
+		public void setReceiver(IReceiver receiver) {
+			this.receiver = receiver;
+		}
+
+		@Override
+		public byte getOwnPlayerId() {
+			return ownPlayerId;
+		}
+
+		@Override
+		public String getOwnPlayerName() {
+			return ownPlayerName;
+		}
+
+		boolean deliver(String authorId, String text) {
+			IReceiver currentReceiver = receiver;
+			if (currentReceiver == null) {
+				return false;
+			}
+			Byte playerId = playerIds.get(authorId);
+			String name = playerNames.get(authorId);
+			currentReceiver.chatMessageReceived(playerId != null ? playerId : -1, name != null ? name : authorId, text);
+			return true;
+		}
+	}
+
 	private IPacketReceiver<MatchStartPacket> generateMatchStartedListener() {
 		return packet -> {
 			updateLists(packet.getMatchInfo());
@@ -141,6 +204,8 @@ public class MultiplayerGame {
 			InitialGameState initialGameState = new InitialGameState(ownPlayerId, playerSettings, randomSeed);
 
 			JSettlersGame game = new JSettlersGame(mapLoader, networkClient.getNetworkConnector(), initialGameState);
+			inGameChat = new InGameChat(ownPlayerId);
+			game.setChat(inGameChat);
 
 			multiplayerListener.gameIsStarting(game.start());
 		};
PATCH_EOF
cat > "$WORK/patches/28-lobby-peace-time-and-layout.patch" <<'PATCH_EOF'
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java b/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
index 063e0efe9..d5e22b4f2 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/IJoinPhaseMultiplayerGameConnector.java
@@ -69,6 +69,19 @@ public interface IJoinPhaseMultiplayerGameConnector {
 	default void setColor(byte slot, byte color) {
 	}
 
+	/**
+	 * Tells the other players which peace time (in minutes) the host has selected. Only the host may do this.
+	 */
+	default void setPeaceTime(int minutes) {
+	}
+
+	/**
+	 * @return The peace time (in minutes) the host has selected, as far as it is known.
+	 */
+	default int getPeaceTime() {
+		return 0;
+	}
+
 	void setPlayerCount(int playerCount);
 
 	/**
diff --git a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
index 42646aa3f..2cf534cf8 100644
--- a/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
+++ b/jsettlers.logic/src/main/java/jsettlers/main/MultiplayerGame.java
@@ -72,6 +72,7 @@ public class MultiplayerGame {
 	private volatile InGameChat inGameChat;
 	private boolean iAmTheHost = false;
 	private int maxPlayers;
+	private volatile int peaceTime = 0;
 
 	public MultiplayerGame(AsyncNetworkClientConnector networkClientFactory) {
 		this.networkClientFactory = networkClientFactory;
@@ -302,6 +303,7 @@ public class MultiplayerGame {
 
 	void updateLists(MatchInfoPacket matchInfo) {
 		maxPlayers = matchInfo.getMaxPlayers();
+		peaceTime = matchInfo.getPeaceTime();
 		List<IMultiplayerPlayer> players = new LinkedList<>();
 		for (PlayerInfoPacket playerInfoPacket : matchInfo.getPlayers()) {
 			players.add(new MultiplayerPlayer(playerInfoPacket));
@@ -404,6 +406,16 @@ public class MultiplayerGame {
 				networkClient.setPlayerCount(playerCount);
 			}
 
+			@Override
+			public void setPeaceTime(int minutes) {
+				networkClient.setPeaceTime((byte) minutes);
+			}
+
+			@Override
+			public int getPeaceTime() {
+				return peaceTime;
+			}
+
 			@Override
 			public void setMultiplayerListener(IMultiplayerListener multiplayerListener) {
 				MultiplayerGame.this.multiplayerListener = multiplayerListener;
diff --git a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
index 78a923ada..80cd4c549 100644
--- a/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
+++ b/jsettlers.main.swing/src/main/java/jsettlers/main/swing/menu/joinpanel/JoinGamePanel.java
@@ -26,6 +26,7 @@ import java.awt.FlowLayout;
 import java.awt.GridBagConstraints;
 import java.awt.GridBagLayout;
 import java.awt.GridLayout;
+import java.awt.Insets;
 import java.awt.event.ActionListener;
 import java.util.ArrayList;
 import java.util.Arrays;
@@ -37,6 +38,7 @@ import javax.swing.BorderFactory;
 import javax.swing.ImageIcon;
 import javax.swing.JButton;
 import javax.swing.JComboBox;
+import javax.swing.JComponent;
 import javax.swing.JLabel;
 import javax.swing.JPanel;
 import javax.swing.JScrollPane;
@@ -140,6 +142,8 @@ public class JoinGamePanel extends BackgroundPanel {
 	 * <code>null</code> for new games.
 	 */
 	private int[] savedGamePositions;
+	/** The game that is told about the peace time the host selects, <code>null</code> for everybody but the host of a network game. */
+	private IJoinPhaseMultiplayerGameConnector peaceTimeConnector;
 
 	public JoinGamePanel(JSettlersFrame settlersFrame) {
 		this.settlersFrame = settlersFrame;
@@ -156,12 +160,8 @@ public class JoinGamePanel extends BackgroundPanel {
 		westPanel.add(settingsPanelWrapper, BorderLayout.CENTER);
 		settingsPanelWrapper.add(settingsPanel);
 		//settingsPanel.setLayout(new GridLayout(0, 2, 20, 0));
-		JPanel settingsLabelPanel = new JPanel();
-		settingsLabelPanel.setLayout(new GridLayout(3, 0, 0, 20));
-		JPanel settingsComboBoxPanel = new JPanel();
-		settingsComboBoxPanel.setLayout(new GridLayout(3, 0, 0, 20));
-		settingsPanel.add(settingsLabelPanel);
-		settingsPanel.add(settingsComboBoxPanel);
+		// one row per setting: label and combo box share the row, so that their centers are on the same height
+		settingsPanel.setLayout(new GridBagLayout());
 		mapPanel.setLayout(new BorderLayout());
 		JPanel mapNameLabelWrapper = new JPanel();
 		mapPanel.add(mapNameLabelWrapper, BorderLayout.NORTH);
@@ -169,12 +169,10 @@ public class JoinGamePanel extends BackgroundPanel {
 		mapNameLabel.setHorizontalAlignment(SwingConstants.CENTER);
 		mapPanel.add(mapImage, BorderLayout.CENTER);
 		mapImage.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
-		settingsLabelPanel.add(numberOfPlayersLabel);
-		settingsComboBoxPanel.add(numberOfPlayersComboBox);
-		settingsLabelPanel.add(startResourcesLabel);
-		settingsComboBoxPanel.add(startResourcesComboBox);
-		settingsLabelPanel.add(peaceTimeLabel);
-		settingsComboBoxPanel.add(peaceTimeComboBox);
+		addSettingsRow(0, numberOfPlayersLabel, numberOfPlayersComboBox);
+		addSettingsRow(1, startResourcesLabel, startResourcesComboBox);
+		addSettingsRow(2, peaceTimeLabel, peaceTimeComboBox);
+		peaceTimeComboBox.addActionListener(e -> informAboutPeaceTime());
 		sendChatMessageButton.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 15));
 		JPanel chatPanel = new JPanel();
 		chatPanel.setLayout(new BorderLayout(0, 10));
@@ -203,6 +201,25 @@ public class JoinGamePanel extends BackgroundPanel {
 		add(content);
 	}
 
+	private void addSettingsRow(int row, JComponent label, JComponent comboBox) {
+		int gap = row > 0 ? 20 : 0;
+		GridBagConstraints labelConstraints = new GridBagConstraints();
+		labelConstraints.gridx = 0;
+		labelConstraints.gridy = row;
+		labelConstraints.anchor = GridBagConstraints.CENTER;
+		labelConstraints.fill = GridBagConstraints.HORIZONTAL;
+		labelConstraints.insets = new Insets(gap, 0, 0, 20);
+		settingsPanel.add(label, labelConstraints);
+
+		GridBagConstraints comboBoxConstraints = new GridBagConstraints();
+		comboBoxConstraints.gridx = 1;
+		comboBoxConstraints.gridy = row;
+		comboBoxConstraints.anchor = GridBagConstraints.CENTER;
+		comboBoxConstraints.fill = GridBagConstraints.HORIZONTAL;
+		comboBoxConstraints.insets = new Insets(gap, 0, 0, 0);
+		settingsPanel.add(comboBox, comboBoxConstraints);
+	}
+
 	private void setStyle() {
 		mapNameLabel.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_LONG);
 		numberOfPlayersLabel.putClientProperty(ELFStyle.KEY, ELFStyle.LABEL_SHORT);
@@ -243,6 +260,7 @@ public class JoinGamePanel extends BackgroundPanel {
 	}
 
 	public void setSinglePlayerMap(MapLoader mapLoader) {
+		peaceTimeConnector = null;
 		this.playerSlotFactory = new SinglePlayerSlotFactory();
 		titleLabel.setText(Labels.getString("join-game-panel-new-single-player-game-title"));
 		peaceTimeComboBox.setEnabled(true);
@@ -280,6 +298,7 @@ public class JoinGamePanel extends BackgroundPanel {
 	}
 
 	public void setNewMultiPlayerMap(MapLoader mapLoader, IMultiplayerConnector connector) {
+		peaceTimeConnector = null;
 		this.playerSlotFactory = new HostOfMultiplayerPlayerSlotFactory(connector);
 		titleLabel.setText(Labels.getString("join-game-panel-new-multi-player-game-title"));
 		peaceTimeComboBox.setEnabled(true);
@@ -300,6 +319,8 @@ public class JoinGamePanel extends BackgroundPanel {
 			public void gameJoined(IJoinPhaseMultiplayerGameConnector connector) {
 				SwingUtilities.invokeLater(() -> {
 					initializeChatFor(connector);
+					peaceTimeConnector = connector;
+					informAboutPeaceTime(); // the guests see the peace time from the start
 					setStartButtonActionListener(e -> {
 						applySelectedPeaceTime();
 						waitForPreviewStartPoints();
@@ -336,6 +357,7 @@ public class JoinGamePanel extends BackgroundPanel {
 	}
 
 	public void setJoinMultiPlayerMap(IJoinPhaseMultiplayerGameConnector joinMultiPlayerMap, MapLoader mapLoader, String playerUUID) {
+		peaceTimeConnector = null;
 		playerSlotFactory = new ClientOfMultiplayerPlayerSlotFactory();
 		titleLabel.setText(Labels.getString("join-game-panel-join-multi-player-game-title"));
 		peaceTimeComboBox.setEnabled(false);
@@ -430,6 +452,9 @@ public class JoinGamePanel extends BackgroundPanel {
 					playerSlot.setReady(true);
 				}
 			}
+			if (!iAmTheHost) {
+				showPeaceTimeOfHost(joinMultiPlayerMap.getPeaceTime());
+			}
 			showSharedPlayers(changingSlots.getItems());
 			setCancelButtonActionListener(e -> {
 				joinMultiPlayerMap.abort();
@@ -459,6 +484,27 @@ public class JoinGamePanel extends BackgroundPanel {
 		JSettlersGame.setNextGamePeaceTimeMinutes(selected == null ? 0 : selected.minutes);
 	}
 
+	/**
+	 * Tells the other players of the network game about the peace time the host has selected.
+	 */
+	private void informAboutPeaceTime() {
+		IJoinPhaseMultiplayerGameConnector connector = peaceTimeConnector;
+		EPeaceTime selected = (EPeaceTime) peaceTimeComboBox.getSelectedItem();
+		if (connector != null && selected != null) {
+			connector.setPeaceTime(selected.minutes);
+		}
+	}
+
+	/**
+	 * Shows the peace time the host has selected (only the host can change it).
+	 */
+	private void showPeaceTimeOfHost(int minutes) {
+		EPeaceTime peaceTime = EPeaceTime.ofMinutes(minutes);
+		if (peaceTimeComboBox.getSelectedItem() != peaceTime) {
+			peaceTimeComboBox.setSelectedItem(peaceTime);
+		}
+	}
+
 	private void prepareUiFor(MapLoader mapLoader) {
 		this.mapLoader = mapLoader;
 		mapNameLabel.setText(mapLoader.getMapName());
@@ -819,6 +865,15 @@ public class JoinGamePanel extends BackgroundPanel {
 			this.minutes = minutes;
 		}
 
+		static EPeaceTime ofMinutes(int minutes) {
+			for (EPeaceTime peaceTime : values()) {
+				if (peaceTime.minutes == minutes) {
+					return peaceTime;
+				}
+			}
+			return WITHOUT;
+		}
+
 		@Override
 		public String toString() {
 			return Labels.getString("peace-time-" + name());
diff --git a/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java b/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
index 665ccca77..540101471 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java
@@ -116,6 +116,7 @@ public final class NetworkConstants {
 		TYPE_CHANGED,
 		PLAYER_COUNT_CHANGED,
 		COLOR_CHANGED,
+		PEACE_TIME_CHANGED,
 		;
 
 		private static final ENetworkMessage[] values = ENetworkMessage.values();
@@ -173,6 +174,7 @@ public final class NetworkConstants {
 		CHANGE_POSITION,
 		CHANGE_PLAYER_COUNT,
 		CHANGE_COLOR,
+		CHANGE_PEACE_TIME,
 		;
 
 		private static final ENetworkKey[] values = ENetworkKey.values();
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java b/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
index d64c1dd16..8300110cb 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/NetworkClient.java
@@ -175,6 +175,12 @@ public class NetworkClient implements ITaskScheduler, INetworkConnector, INetwor
 		channel.sendPacketAsync(ENetworkKey.CHANGE_COLOR, new ByteTuplePacket(slot, color));
 	}
 
+	@Override
+	public void setPeaceTime(byte peaceTimeMinutes) throws IllegalStateException {
+		EPlayerState.assertState(state, EPlayerState.IN_MATCH);
+		channel.sendPacketAsync(ENetworkKey.CHANGE_PEACE_TIME, new ByteTuplePacket(peaceTimeMinutes, (byte) 0));
+	}
+
 	@Override
 	public void setType(byte slot, byte playerType) throws IllegalStateException {
 		EPlayerState.assertState(state, EPlayerState.IN_MATCH);
diff --git a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
index c19be0321..f0dfde316 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/client/interfaces/INetworkClient.java
@@ -98,6 +98,11 @@ public interface INetworkClient {
 
 	void setColor(byte slot, byte color) throws IllegalStateException;
 
+	/**
+	 * Tells the other players of the match which peace time (in minutes) the host has selected. Only the host may do this.
+	 */
+	void setPeaceTime(byte peaceTimeMinutes) throws IllegalStateException;
+
 	void setType(byte slot, byte playerType) throws IllegalStateException;
 
 	void setPosition(byte slot, byte position) throws IllegalStateException;
diff --git a/jsettlers.network/src/main/java/jsettlers/network/common/packets/MatchInfoPacket.java b/jsettlers.network/src/main/java/jsettlers/network/common/packets/MatchInfoPacket.java
index 544026bfb..6098f5987 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/common/packets/MatchInfoPacket.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/common/packets/MatchInfoPacket.java
@@ -35,6 +35,8 @@ public class MatchInfoPacket extends Packet {
 	private MapInfoPacket mapInfo;
 	private PlayerInfoPacket[] players;
 	private SlotInfoPacket[] slots;
+	/** The peace time (in minutes) that is selected by the host. */
+	private byte peaceTime;
 
 	public MatchInfoPacket() {
 	}
@@ -56,6 +58,7 @@ public class MatchInfoPacket extends Packet {
 		mapInfo = match.getMap();
 		players = match.getPlayerInfos();
 		slots = match.getSlotInfos();
+		peaceTime = match.getPeaceTime();
 	}
 
 	@Override
@@ -76,6 +79,7 @@ public class MatchInfoPacket extends Packet {
 		for(SlotInfoPacket curr : slots) {
 			curr.serialize(dos);
 		}
+		dos.writeByte(peaceTime);
 	}
 
 	@Override
@@ -104,6 +108,11 @@ public class MatchInfoPacket extends Packet {
 		}
 
 		this.slots = slots;
+		peaceTime = dis.readByte();
+	}
+
+	public byte getPeaceTime() {
+		return peaceTime;
 	}
 
 	public String getId() {
@@ -135,7 +144,7 @@ public class MatchInfoPacket extends Packet {
 		if (this == o) return true;
 		if (o == null || getClass() != o.getClass()) return false;
 		MatchInfoPacket that = (MatchInfoPacket) o;
-		return maxPlayers == that.maxPlayers && Objects.equals(id, that.id) && Objects.equals(matchName, that.matchName) && Objects.equals(mapInfo, that.mapInfo) && Arrays.equals(players, that.players) && Arrays.equals(slots, that.slots);
+		return maxPlayers == that.maxPlayers && peaceTime == that.peaceTime && Objects.equals(id, that.id) && Objects.equals(matchName, that.matchName) && Objects.equals(mapInfo, that.mapInfo) && Arrays.equals(players, that.players) && Arrays.equals(slots, that.slots);
 	}
 
 	@Override
@@ -149,6 +158,6 @@ public class MatchInfoPacket extends Packet {
 	@Override
 	public String toString() {
 		return "MatchInfoPacket [id=" + id + ", matchName=" + matchName + ", maxPlayers=" + maxPlayers + ", mapInfo=" + mapInfo + ", players="
-				+ Arrays.toString(players) + ", slots=" + Arrays.toString(slots) + "]";
+				+ Arrays.toString(players) + ", slots=" + Arrays.toString(slots) + ", peaceTime=" + peaceTime + "]";
 	}
 }
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java b/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
index ab66480a1..1bcf449ff 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/IServerManager.java
@@ -69,6 +69,8 @@ public interface IServerManager {
 
 	void setColorForSlot(Player player, byte slot, byte color);
 
+	void setPeaceTime(Player player, byte peaceTimeMinutes);
+
 	void setPlayerCount(Player player, int playerCount);
 
 	void sendMatchesToPlayer(Player player);
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java b/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
index 33cdd607b..43ee1f16a 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/ServerManager.java
@@ -29,6 +29,7 @@ import jsettlers.network.server.listeners.ChangePlayerCountPacketListener;
 import jsettlers.network.server.listeners.ChangePlayerTypePacketListener;
 import jsettlers.network.server.listeners.ChangePositionPacketListener;
 import jsettlers.network.server.listeners.ChangeColorPacketListener;
+import jsettlers.network.server.listeners.ChangePeaceTimePacketListener;
 import jsettlers.network.server.listeners.ChangeTeamPacketListener;
 import jsettlers.network.server.listeners.ChatMessageForwardingListener;
 import jsettlers.network.server.listeners.IdentifyUserListener;
@@ -98,6 +99,7 @@ public class ServerManager implements IServerManager {
 			channel.registerListener(new ChangePositionPacketListener(this, player));
 			channel.registerListener(new ChangeTeamPacketListener(this, player));
 			channel.registerListener(new ChangeColorPacketListener(this, player));
+			channel.registerListener(new ChangePeaceTimePacketListener(this, player));
 			channel.registerListener(new ChangePlayerCountPacketListener(this, player));
 
 			return true;
@@ -266,6 +268,18 @@ public class ServerManager implements IServerManager {
 		}
 	}
 
+	@Override
+	public void setPeaceTime(Player player, byte peaceTimeMinutes) {
+		try {
+			Match match = verifyAndGetMatch(player);
+
+			match.setPeaceTime(peaceTimeMinutes);
+		} catch (IllegalStateException e) {
+			player.sendPacket(NetworkConstants.ENetworkKey.REJECT_PACKET,
+					new RejectPacket(NetworkConstants.ENetworkMessage.INVALID_STATE_ERROR, NetworkConstants.ENetworkKey.CHANGE_PEACE_TIME));
+		}
+	}
+
 	@Override
 	public void setPlayerCount(Player player, int playerCount) {
 		try {
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangePeaceTimePacketListener.java b/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangePeaceTimePacketListener.java
new file mode 100644
index 000000000..edef5004e
--- /dev/null
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/listeners/ChangePeaceTimePacketListener.java
@@ -0,0 +1,30 @@
+package jsettlers.network.server.listeners;
+
+import java.io.IOException;
+import jsettlers.network.NetworkConstants;
+import jsettlers.network.common.packets.ByteTuplePacket;
+import jsettlers.network.infrastructure.channel.GenericDeserializer;
+import jsettlers.network.infrastructure.channel.listeners.PacketChannelListener;
+import jsettlers.network.server.IServerManager;
+import jsettlers.network.server.match.Player;
+
+/**
+ * Receives the peace time (in minutes) the host has selected. The second value of the packet is not used.
+ */
+public class ChangePeaceTimePacketListener extends PacketChannelListener<ByteTuplePacket> {
+
+	private final IServerManager serverManager;
+	private final Player player;
+
+	public ChangePeaceTimePacketListener(IServerManager serverManager, Player player) {
+		super(NetworkConstants.ENetworkKey.CHANGE_PEACE_TIME, new GenericDeserializer<>(ByteTuplePacket.class));
+
+		this.serverManager = serverManager;
+		this.player = player;
+	}
+
+	@Override
+	protected void receivePacket(NetworkConstants.ENetworkKey key, ByteTuplePacket packet) throws IOException {
+		serverManager.setPeaceTime(player, packet.getValueA());
+	}
+}
diff --git a/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java b/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
index b0acf7f0e..49f2058f1 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/server/match/Match.java
@@ -59,6 +59,7 @@ public class Match {
 	private TaskCollectingListener taskCollectingListener;
 	private TaskSendingTimerTask taskSendingTimerTask;
 	private int currPlayers;
+	private volatile byte peaceTime = 0;
 
 	public Match(String name, int maxPlayers, MapInfoPacket map, Player host, long randomSeed) {
 		this.maxPlayers = maxPlayers;
@@ -380,6 +381,17 @@ public class Match {
 		}
 	}
 
+	public byte getPeaceTime() {
+		return peaceTime;
+	}
+
+	public void setPeaceTime(byte peaceTime) {
+		if(this.peaceTime == peaceTime) return;
+
+		this.peaceTime = peaceTime;
+		sendMatchInfoUpdate(ENetworkMessage.PEACE_TIME_CHANGED, null);
+	}
+
 	public void setPlayerCount(int playerCount) {
 		synchronized (players) {
 			if(playerCount < players.size()) {
diff --git a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
index acc15333a..e5165031d 100644
--- a/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
+++ b/jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java
@@ -345,6 +345,12 @@ public final class NetworkTimer extends TimerTask implements INetworkClientClock
 
 	@Override
 	public int getSyncTime() {
+		if (!scheduled) {
+			// While a game is loading, the clock is already set to the time of the saved game, but the lockstep base is not known yet. Reporting such
+			// a time would make the server believe that this client is far ahead and it would stop waiting for it, so that the commands of the
+			// players are executed with a huge delay (or never).
+			return 0;
+		}
 		return time - lockstepBase;
 	}
 
PATCH_EOF
PATCH_NAMES="01-lan-multiplayer-broadcast 02-endgame-player-names 03-gifts-of-the-gods-spell 04-soldiers-ignore-far-civilians 05-font-quality-and-size 06-building-cost-tooltip 07-tooltip-position 08-in-game-messages 09-messages-layout-and-settings-file 10-game-speed-and-fps-limit 11-amazon-storage-shadow 12-language-selection-czech 13-thief-fixes 14-zoom-indicator 15-control-groups 16-peacetime 17-hd-graphics 18-smithy-output 19-auto-work-area 20-convert-specialists-to-bearers 21-faster-growth 22-settler-messages-and-tool-demand 23-lobby-colors-and-positions 24-lan-load-game 25-shared-player-experimental 26-save-game-improvements 27-ingame-chat 28-lobby-peace-time-and-layout"
for P in $PATCH_NAMES; do
	git apply --check "$WORK/patches/$P.patch" || die "Patch $P cannot be applied - the source code has changed since the tested version."
	git apply --whitespace=nowarn "$WORK/patches/$P.patch"
done
grep -q "SOLDIER_CIVILIAN_SEARCH_RADIUS" jsettlers.logic/src/main/java/jsettlers/logic/constants/Constants.java || die "Patch 04 was not applied."
grep -q "getDisplayName" jsettlers.logic/src/main/java/jsettlers/logic/player/EndgameStatistic.java || die "Patch 02 was not applied."
grep -q "noSoldierAvailable" jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java || die "Patch 08 was not applied."
grep -q "GIFT_MATERIALS" jsettlers.logic/src/main/java/jsettlers/logic/movable/military/MageMovable.java || die "Patch 03 was not applied."
grep -q "reportedProblems" jsettlers.network/src/main/java/jsettlers/network/server/lan/LanServerBroadcastThread.java || die "Patch 01 was not applied."
grep -q "shadowPart" jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java || die "Patch 11 was not applied."
[[ -f jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_cs.properties ]] || die "Patch 12 was not applied."
grep -q "homePos" jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/ThiefMovable.java || die "Patch 13 was not applied."
grep -q "map-zoom" jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java || die "Patch 14 was not applied."
grep -q "RECALL_GROUP" jsettlers.common/src/main/java/jsettlers/common/action/EActionType.java || die "Patch 15 was not applied."
grep -q "isPeaceTime" jsettlers.logic/src/main/java/jsettlers/logic/constants/MatchConstants.java || die "Patch 16 was not applied."
grep -q "class HdGraphics" jsettlers.graphics/src/main/java/jsettlers/graphics/image/hd/HdGraphics.java || die "Patch 17 was not applied."
grep -q "addSmithyOutput" jsettlers.logic/src/main/java/jsettlers/logic/buildings/Building.java || die "Patch 18 was not applied."
grep -q "moveWorkAreaToWork" jsettlers.logic/src/main/java/jsettlers/logic/movable/civilian/BuildingWorkerMovable.java || die "Patch 19 was not applied."
grep -q "IConvertibleToBearer" jsettlers.logic/src/main/java/jsettlers/logic/movable/specialist/GeologistMovable.java || die "Patch 20 was not applied."
grep -q "faster than the original" jsettlers.logic/src/main/java/jsettlers/logic/objects/growing/Corn.java || die "Patch 21 was not applied."
grep -q "popToolForProfessionSettings" jsettlers.logic/src/main/java/jsettlers/logic/map/grid/partition/manager/PartitionManager.java || die "Patch 22 was not applied."
grep -q "class PlayerColors" jsettlers.common/src/main/java/jsettlers/common/player/PlayerColors.java || die "Patch 23 was not applied."
grep -q "setLockstepBase" jsettlers.network/src/main/java/jsettlers/network/synchronic/timer/NetworkTimer.java || die "Patch 24 was not applied."
grep -q "class SharedPlayers" jsettlers.common/src/main/java/jsettlers/common/menu/SharedPlayers.java || die "Patch 25 was not applied."
grep -q "GAME_SAVED" jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java || die "Patch 26 was not applied."
grep -q "class TextInput" go.graphics/src/main/java/go/graphics/event/TextInput.java || die "Patch 27 was not applied."
grep -q "PEACE_TIME_CHANGED" jsettlers.network/src/main/java/jsettlers/network/NetworkConstants.java || die "Patch 28 was not applied."

# ---------------------------------------------------------------- compilation
say "Compiling (the first run takes several minutes, dependencies are downloaded)"
./gradlew --no-daemon :jsettlers.main.swing:installDist :jsettlers.main.swing:copyDependencies

LIBDIR="$SRC/jsettlers.main.swing/build/install/jsettlers.main.swing/lib"
DEPDIR="$SRC/jsettlers.main.swing/build/libs/dependencies"
[[ -d "$LIBDIR" ]] || die "$LIBDIR is missing after compilation."
[[ -d "$DEPDIR" ]] || die "$DEPDIR is missing after compilation (music libraries)."
[[ -d "$SRC/maps/release" ]] || die "The folder maps/release is missing."

# ---------------------------------------------------------------- packing
say "Preparing the files for packing"
rm -rf "$WORK/stage" "$WORK/out" "$WORK/runtime" "$WORK/dist"
mkdir -p "$WORK/stage/input" "$WORK/dist"
cp "$LIBDIR"/*.jar "$WORK/stage/input/"
cp "$DEPDIR"/*.jar "$WORK/stage/input/"
cp -R "$SRC/maps/release" "$WORK/stage/input/maps"

# ---------------------------------------------------------------- optional AI engine for the HD graphics
# The HD graphics (patch 17) always work with the built-in enlarger. If this step succeeds, the game also contains
# Real-ESRGAN ncnn Vulkan (MIT license, https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan), which makes better colours.
# The engine is only a program; the enlarged game images are made later on the computer of the player.
say "Preparing the optional AI engine for the HD graphics (Real-ESRGAN ncnn Vulkan)"
HD_ENGINE_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
HD_ENGINE_DIR="$WORK/stage/input/hd-engine"
HD_ENGINE_INCLUDED=0
set +e   # (errexit must stay active inside the sub-shell below, so it is not used as an "if" condition)
(
	set -e
	DL="$WORK/downloads/hd-engine"
	mkdir -p "$DL"
	[[ -s "$DL/engine.zip" ]] || curl -fL --retry 3 --connect-timeout 30 -o "$DL/engine.zip" "$HD_ENGINE_URL"
	rm -rf "$DL/unzipped"
	mkdir -p "$DL/unzipped"
	unzip -q -o "$DL/engine.zip" -d "$DL/unzipped"
	EXE="$(find "$DL/unzipped" -type f -name realesrgan-ncnn-vulkan | head -1)"
	[[ -n "$EXE" ]] || { echo "the program is not in the archive"; exit 1; }
	EXEDIR="$(dirname "$EXE")"
	[[ -f "$EXEDIR/models/realesr-animevideov3-x2.param" && -f "$EXEDIR/models/realesr-animevideov3-x2.bin" ]] || { echo "the model is not in the archive"; exit 1; }
	rm -rf "$HD_ENGINE_DIR"
	mkdir -p "$HD_ENGINE_DIR/models"
	for item in "$EXEDIR"/*; do
		[[ "$(basename "$item")" == "models" ]] || cp -R "$item" "$HD_ENGINE_DIR/"
	done
	cp "$EXEDIR/models/realesr-animevideov3-x2.param" "$EXEDIR/models/realesr-animevideov3-x2.bin" "$HD_ENGINE_DIR/models/"
	chmod +x "$HD_ENGINE_DIR/realesrgan-ncnn-vulkan"
	xattr -cr "$HD_ENGINE_DIR" 2>/dev/null || true
	codesign --force --sign - "$HD_ENGINE_DIR/realesrgan-ncnn-vulkan" 2>/dev/null || true

	# smoke test: the engine has to enlarge a small picture on this Mac, otherwise it is not used
	TEST="$DL/test"
	rm -rf "$TEST"
	mkdir -p "$TEST"
	echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -D > "$TEST/one.png"
	sips -z 32 32 "$TEST/one.png" --out "$TEST/in.png" >/dev/null
	perl -e 'alarm 180; exec @ARGV' "$HD_ENGINE_DIR/realesrgan-ncnn-vulkan" -i "$TEST/in.png" -o "$TEST/out.png" \
		-n realesr-animevideov3 -s 2 -f png -m "$HD_ENGINE_DIR/models" >"$TEST/log.txt" 2>&1 || { cat "$TEST/log.txt"; exit 1; }
	[[ "$(sips -g pixelWidth "$TEST/out.png" 2>/dev/null | awk '/pixelWidth/ {print $2}')" == "64" ]] || { cat "$TEST/log.txt"; exit 1; }
) >"$WORK/hd-engine-step.log" 2>&1
HD_ENGINE_RC=$?
set -e
if [[ $HD_ENGINE_RC -eq 0 ]]; then
	HD_ENGINE_INCLUDED=1
	echo "The AI engine works and is included in the app."
else
	rm -rf "$HD_ENGINE_DIR"
	echo "(The AI engine could not be prepared, see $WORK/hd-engine-step.log. The HD graphics will use the built-in enlarger.)"
fi

MAIN_JAR="$(cd "$WORK/stage/input" && ls jsettlers.main.swing*.jar 2>/dev/null | head -1)"
[[ -n "$MAIN_JAR" ]] || die "The main jar (jsettlers.main.swing*.jar) was not found."

say "Creating the bundled Java runtime (the Java inside the app)"
"$JAVA_HOME/bin/jlink" --add-modules ALL-MODULE-PATH --strip-debug --no-man-pages --no-header-files \
	--output "$WORK/runtime"

# icon (optional - if it fails, the app simply gets the default icon)
ICON_FILE=""
ICON_PNG="$SRC/jsettlers.main.swing/src/main/resources/jsettlers/main/swing/icon.png"
if [[ -f "$ICON_PNG" ]]; then
	if (
		set -e
		mkdir -p "$WORK/stage/icon.iconset"
		for s in 16 32 128 256 512; do
			sips -z "$s" "$s" "$ICON_PNG" --out "$WORK/stage/icon.iconset/icon_${s}x${s}.png" >/dev/null
		done
		iconutil -c icns "$WORK/stage/icon.iconset" -o "$WORK/stage/JSettlers.icns"
	) >/dev/null 2>&1; then
		ICON_FILE="$WORK/stage/JSettlers.icns"
	else
		echo "(The icon could not be created, continuing without it.)"
	fi
fi

# ---------------------------------------------------------------- JSettlers.app
say "Packing JSettlers.app"
if [[ -n "$ICON_FILE" ]]; then
	ICON_ARGS=(--icon "$ICON_FILE")
else
	ICON_ARGS=()
fi
# (jpackage requires a version starting with 1 or more on macOS, the real version is written to Info.plist below)
"$JAVA_HOME/bin/jpackage" \
	--type app-image \
	--name JSettlers \
	--dest "$WORK/out" \
	--input "$WORK/stage/input" \
	--main-jar "$MAIN_JAR" \
	--main-class jsettlers.main.swing.SwingManagedJSettlers \
	--runtime-image "$WORK/runtime" \
	--app-version 1.0.0 \
	--java-options "-Xmx2G" \
	--java-options '-Dsettlers.maps=$APPDIR/maps' \
	--java-options '-Dsettlers.hd.engine=$APPDIR/hd-engine' \
	${ICON_ARGS[@]+"${ICON_ARGS[@]}"}

APP="$WORK/out/JSettlers.app"
CFG="$APP/Contents/app/JSettlers.cfg"
[[ -f "$CFG" ]] || die "jpackage did not create the configuration $CFG."

# check that all important libraries are on the classpath of the app
for needle in lwjgl jogl-all gluegen jlayer gson; do
	grep -q "$needle" "$CFG" || die "'$needle' is missing on the classpath of the app. See the file: $CFG"
done
say "Classpath check passed ($(grep -o '\.jar' "$CFG" | wc -l | tr -d ' ') libraries)"

# ---------------------------------------------------------------- working folder + launcher
# At startup the game writes into the CURRENT folder ("./logs/..." with the log and the game replay, "./maps"
# for downloaded maps). An app started from Finder/Dock starts in "/", where macOS does not allow writing, so
# "Start game" would silently fail. The main executable of the app is therefore a small script that first
# changes into a writable folder and then starts the real launcher. It also creates the settings file.
say "Setting up the working folder of the app (~/Library/Application Support/JSettlers)"
LAUNCHER="$APP/Contents/MacOS/JSettlers-launcher"
cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$HOME/Library/Application Support/JSettlers"
mkdir -p "$WORKDIR" 2>/dev/null
if [ ! -f "$WORKDIR/tweaks.properties" ]; then
cat > "$WORKDIR/tweaks.properties" 2>/dev/null <<'TWEAKS_EOF'
# JSettlers macOS - settings. Edit the numbers, save the file and restart the game.
# Lines starting with # are comments and are ignored.

# Size of all texts (1.0 = original size, 1.5 = 50 % bigger).
font-scale=1.5

# Distance of tooltips from the mouse cursor in pixels (x: to the right, y: upwards, negative = downwards).
tooltip-offset-x=32
tooltip-offset-y=0

# In-game messages (e.g. "Your woodcutter can't find any trees"): distance of the message texts from the right
# edge of the left side panel in pixels. If the messages overlap the panel, increase the number;
# if they are too far from the panel, decrease it.
message-offset-x=50

# Experimental Java options, e.g. a different window rendering mode if the frame rate is low.
# Remove the # at the beginning of the next line to use it:
# jvm-options=-Dsun.java2d.metal=true
TWEAKS_EOF
fi
JVMOPT="$(grep '^jvm-options=' "$WORKDIR/tweaks.properties" 2>/dev/null | head -1 | cut -d= -f2-)"
if [ -n "$JVMOPT" ]; then export JAVA_TOOL_OPTIONS="$JVMOPT"; fi
cd "$WORKDIR" 2>/dev/null || cd "$HOME" || exit 1
exec "$DIR/JSettlers" "$@"
LAUNCHER_EOF
chmod +x "$LAUNCHER"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable JSettlers-launcher" "$PLIST" \
	|| die "Could not replace the launcher in $PLIST."
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST")" == "JSettlers-launcher" ]] \
	|| die "Info.plist does not have the right launcher after the change."
[[ -x "$APP/Contents/MacOS/JSettlers" ]] || die "The original launcher $APP/Contents/MacOS/JSettlers is missing."
# version shown in Finder (Get Info)
PLAIN_VERSION="${RELEASE_VERSION%%-*}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLAIN_VERSION" "$PLIST" || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PLAIN_VERSION" "$PLIST" || true

# ---------------------------------------------------------------- license files and readme
say "Adding license files and readme"
cp "$SRC/LICENSE.txt" "$WORK/stage/LICENSE.txt"
{
cat <<'NOTICE_EOF'
JSettlers macOS - third-party notices
=====================================

JSettlers macOS is an unofficial build of JSettlers (settlers-remake), an open source remake of "The Settlers III".
It is not affiliated with, endorsed by or supported by Ubisoft or Blue Byte. "The Settlers" is a trademark of its owner.
The original game data (graphics and sound of The Settlers III) is NOT included and is needed to play.

JSettlers / settlers-remake
  MIT license (see LICENSE.txt), https://github.com/paulwedeck/settlers-remake
  Authors: Paul Wedeck, Michael Zangl, Andreas Eberle, Andreas Butti and many other contributors.
  Apple Silicon support (pull request #92): Kev Zettler.
  The changes of this build (patches) are published under the same MIT license.
  Third-party textures used by the game are listed in TEXTURES.md of the upstream project.

HD graphics (optional, off by default)
  The enlarged images are made on the computer of the player from his own copy of The Settlers III and are stored only there
  (~/Library/Application Support/JSettlers/hd). They are never part of this app. If the app contains the folder hd-engine, it
  holds Real-ESRGAN ncnn Vulkan (MIT license, https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan) with the model
  realesr-animevideov3 (BSD-3-Clause, https://github.com/xinntao/Real-ESRGAN), used to make the enlarged images.

Bundled Java runtime
  OpenJDK (build of the JDK this app was built with), GPL v2 with the Classpath Exception, https://openjdk.org

Bundled libraries (separate .jar files in the app, licenses are those of the respective projects)
  LWJGL (BSD-3-Clause), JOGL and GlueGen (BSD-2-Clause), Gson (Apache-2.0), JOML (MIT), lwjgl3-awt,
  the LGPL-licensed audio libraries JLayer, Tritonus, MP3SPI, VorbisSPI, JOrbis and J-Ogg,
  and the JAXB libraries (CDDL 1.1 / GPL v2 with Classpath Exception).
  All libraries are shipped as separate .jar files in JSettlers.app/Contents/app and can be replaced.

NOTICE_EOF
echo "List of the .jar files in this app:"
(cd "$WORK/stage/input" && ls *.jar | sed 's/^/  /')
} > "$WORK/stage/THIRD-PARTY-NOTICES.txt"

cat > "$WORK/stage/README.txt" <<README_EOF
JSettlers macOS v$RELEASE_VERSION  (unofficial build for Macs with Apple Silicon)

1. Drag JSettlers into the Applications folder.
2. Start it. If macOS says the app is damaged or cannot be opened because the developer is unknown, the app is
   simply not signed by Apple (this build is signed ad hoc). Do ONE of these:
   - open System Settings > Privacy & Security, scroll down and click "Open Anyway" next to JSettlers, or
   - run this command in Terminal:   xattr -dr com.apple.quarantine /Applications/JSettlers.app
3. At the first start the game asks for the folder of your ORIGINAL "The Settlers III" installation (or the free
   demo). The folder must contain the sub-folders GFX and SND. This data is not part of JSettlers.
   Java does not have to be installed, it is inside the app.

Settings:  ~/Library/Application Support/JSettlers/tweaks.properties  (text size, tooltip and message positions)
Logs:      ~/Library/Application Support/JSettlers/logs
Own maps:  ~/Library/Application Support/JSettlers/maps

Tips: Control + two-finger click (secondary click) = forced move, your units ignore enemies on the way (recall).
Option + two-finger click = patrol. With a mouse use Control/Option + right click.
The zoom shown at the top right (100% = original size) helps to find the normal view again.
Click on a message at the bottom of the screen = jump to the place it is about.
HD graphics: Settings > "HD graphics" = Yes, then restart. The first start enlarges the graphics of your own game files
(a few minutes) and stores them in ~/Library/Application Support/JSettlers/hd. Delete that folder to start over.

Project page, manual, known issues and the source code: see the README of the project on GitHub.
README_EOF
cp "$WORK/stage/LICENSE.txt" "$WORK/stage/THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/"

# ---------------------------------------------------------------- signature + DMG
say "Signing the app (ad-hoc signature, no Apple developer account)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" || die "The ad-hoc signature did not pass verification."

say "Creating the DMG"
DMGROOT="$WORK/stage/dmg"
rm -rf "$DMGROOT"
mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
cp "$WORK/stage/README.txt" "$WORK/stage/LICENSE.txt" "$WORK/stage/THIRD-PARTY-NOTICES.txt" "$DMGROOT/"
DMG="$WORK/dist/JSettlers-macOS-v${RELEASE_VERSION}-arm64.dmg"
hdiutil create -volname "JSettlers macOS" -srcfolder "$DMGROOT" -ov -format UDZO "$DMG" >/dev/null

# ---------------------------------------------------------------- source code archive
# Complete source code of exactly this build (upstream code + all patches), ready to compile with ./gradlew.
say "Creating the source code archive"
ZIP="$WORK/dist/JSettlers-macOS-v${RELEASE_VERSION}-source.zip"
rm -f "$ZIP"
( cd "$SRC" && git ls-files -co --exclude-standard | grep -v '^\.git/' | zip -q -@ "$ZIP" )

say "DONE"
echo "DMG:    $DMG ($(du -h "$DMG" | cut -f1))"
echo "Source: $ZIP ($(du -h "$ZIP" | cut -f1))"
echo
echo "Test it: open the DMG, drag JSettlers to Applications and start it."
echo "At the first start the game asks for the folder with the original Settlers III data (GFX/SND)."
echo "LAN game: one player opens the LAN tab, clicks \"Start local server\" and creates a game; the others see it in the list."
echo "Settings (text size, tooltip and message positions): ~/Library/Application Support/JSettlers/tweaks.properties"
open "$WORK/dist" 2>/dev/null || true
