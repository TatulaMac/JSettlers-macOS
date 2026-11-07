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
#     ~/JSettlers-build/dist/JSettlers-macOS-v0.6.0-alpha-arm64.dmg       (the app, this is what users download)
#     ~/JSettlers-build/dist/JSettlers-macOS-v0.6.0-alpha-source.zip      (complete, already patched source code)
#
# How it works: it downloads the upstream source code (https://github.com/paulwedeck/settlers-remake, the state of
# pull request #92 "Apple Silicon support", commit 47d1d4e), applies the patches embedded below (the same patches
# are in the "patches" folder of the project repository), compiles everything and packs it into JSettlers.app.
#
set -euo pipefail

RELEASE_VERSION="0.6.0-alpha"   # shown in the game (window title and top right corner) and used in the file names

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
# 08 Messages: readable texts, new "no soldier available" message, colours, click on a message jumps to its place.
# 09 Messages are placed right of the side panel (setting message-offset-x); the settings file is found more reliably.
# 10 Game speed 1.0x is really 1.0x (it was 0.9x) and the frame rate limit is accurate (60 was ~52).
# 11 Amazon storage building: the shadow was drawn six times on top of itself and came out black.
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
index 84285a5..0a42c57 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/EMessageType.java
@@ -36,5 +36,10 @@ public enum EMessageType {
 	/**
 	 * The worker of a building was not able to find a place to execute his action in his work are for some time.
 	 */
-	NOTHING_FOUND_IN_SEARCH_AREA
+	NOTHING_FOUND_IN_SEARCH_AREA,
+
+	/**
+	 * A military building has been finished but no soldier is available to occupy it.
+	 */
+	NO_SOLDIER_AVAILABLE
 }
diff --git a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
index f805b43..80baee1 100644
--- a/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
+++ b/jsettlers.common/src/main/java/jsettlers/common/menu/messages/SimpleMessage.java
@@ -139,6 +139,17 @@ public class SimpleMessage implements IMessage {
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
 	/**
 	 *
 	 * @param at
diff --git a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/MapContent.java
index 247a98c..2d680b6 100644
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
@@ -443,10 +450,81 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
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
+		if (label.startsWith("cannot_find_work_")) {
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
@@ -454,7 +532,7 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 		int messageIndex;
 		if(textDrawPosition == ETextDrawPosition.DESKTOP) {
 			offsetY = MESSAGE_OFFSET_Y;
-			offsetX = MESSAGE_OFFSET_X;
+			offsetX = controls.getPanelWidth() + MESSAGE_OFFSET_X;
 			yDirection = 1;
 			messageIndex = 0;
 		} else {
@@ -466,8 +544,9 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
 		for (IMessage m : messenger.getMessages()) {
 			float x = offsetX;
-			float y = offsetY + messageIndex * (fontSize.getSize()*1.3f) * yDirection;
+			float y = offsetY + messageIndex * lineHeight * yDirection;
 			float a = messageAlpha(m);
+			float startX = x;
 			if (m.getSender() >= 0) {
 				String name = getPlayername(m.getSender()) + ":";
 				Color color = MapDrawContext.getPlayerColor(m.getSender());
@@ -479,10 +558,15 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
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
@@ -888,6 +972,15 @@ public final class MapContent implements RegionContent, IMapInterfaceListener, A
 
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
index 70a2723..3582ff8 100644
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
index 092b2f3..7b18afe 100644
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
index 470af44..9dbf08e 100644
--- a/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
+++ b/jsettlers.graphics/src/main/resources/jsettlers/graphics/localization/labels_en.properties
@@ -379,6 +379,11 @@ cannot_find_work_FARM = Your grain farm can't find find enough spots to plant wh
 cannot_find_work_WINEGROWER = Your winery can't find enough spots for growing vines in its work area.
 cannot_find_work_WATERWORKS = Your waterworks can't find any river in its work area.
 cannot_find_work_FISHER = Your fisher can't find any sea in its work area.
+cannot_find_work_RICE_FARM = Your rice farm can't find enough spots to plant rice in its work area.
+cannot_find_work_BEEKEEPING = Your beekeeper can't find enough free spots for beehives in its work area.
+no_soldier_available_TOWER = Your guard tower can't be occupied: no soldier is available.
+no_soldier_available_BIG_TOWER = Your large guard tower can't be occupied: no soldier is available.
+no_soldier_available_CASTLE = Your castle can't be occupied: no soldier is available.
 action_firerer_slow = Warning! The game is responding slowly.
 
 # progress display
diff --git a/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java b/jsettlers.logic/src/main/java/jsettlers/logic/buildings/military/occupying/OccupyingBuilding.java
index 3d10b59..d81dc28 100644
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
index 10cc924..1b19833 100644
--- a/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java
+++ b/jsettlers.graphics/src/main/java/jsettlers/graphics/map/draw/MapObjectDrawer.java
@@ -1349,8 +1349,22 @@ public class MapObjectDrawer {
 			} else if(variant.isVariantOf(EBuildingType.STOCK)) {
 				float[] zvalues = new float[] {-4*z_per_y, -2*z_per_y, 2*z_per_y, 3*z_per_y, 2*z_per_y, -2*z_per_y};
 				ImageLink[] images = variant.getImages();
+				// Every part of the storage carries the shadow of the whole building. Drawn six times on top of each other the translucent shadow
+				// becomes a solid black area, so only the last part that has a shadow draws it.
+				int shadowPart = 0;
 				for (int i = 0; i != 6; i++) {
-					draw(imageProvider.getImage(images[i]), x, y, zvalues[i], color);
+					Image part = imageProvider.getImage(images[i]);
+					if (part instanceof SettlerImage && ((SettlerImage) part).getShadow() != null) {
+						shadowPart = i;
+					}
+				}
+				for (int i = 0; i != 6; i++) {
+					Image part = imageProvider.getImage(images[i]);
+					if (i == shadowPart) {
+						draw(part, x, y, zvalues[i], color);
+					} else {
+						drawOnlyImage(part, x, y, zvalues[i], null, color);
+					}
 				}
 			} else {
 				ImageLink[] images = variant.getImages();
PATCH_EOF
PATCH_NAMES="01-lan-multiplayer-broadcast 02-endgame-player-names 03-gifts-of-the-gods-spell 04-soldiers-ignore-far-civilians 05-font-quality-and-size 06-building-cost-tooltip 07-tooltip-position 08-in-game-messages 09-messages-layout-and-settings-file 10-game-speed-and-fps-limit 11-amazon-storage-shadow"
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

Tips: Ctrl + right click = forced move (ignores enemies), Alt + right click = patrol. On a Mac use Control + click
with two fingers. Click on a message at the bottom of the screen = jump to the place it is about.

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
