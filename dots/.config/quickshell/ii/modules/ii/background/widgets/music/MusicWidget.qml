pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import qs.modules.ii.mediaControls

AbstractBackgroundWidget {
    id: root

    configEntryName: "music"

    scale: 1.0
    Behavior on scale { enabled: false }

    readonly property list<MprisPlayer> players: MprisController.players
    readonly property MprisPlayer activePlayer: MprisController.activePlayer ?? (players.length > 0 ? players[0] : null)

    readonly property bool hasTrack: (activePlayer && ((activePlayer.trackTitle && activePlayer.trackTitle.length > 0) || (activePlayer.trackArtist && activePlayer.trackArtist.length > 0))) ?? false
    readonly property bool hideWhenIdle: Config.options.background.widgets.music?.hideWhenIdle ?? true
    readonly property string musicLayout: Config.options.background.widgets.music?.layout ?? Config.options.background.widgets.music?.style ?? "horizontal"
    readonly property bool isVertical: musicLayout === "vertical" || musicLayout === "spotify" || musicLayout === "card"

    visible: (!hideWhenIdle || hasTrack) && (opacity > 0)

    implicitWidth: isVertical ? 290 : Appearance.sizes.mediaControlsWidth
    implicitHeight: isVertical ? 485 : Appearance.sizes.mediaControlsHeight

    property list<real> visualizerPoints: []

    Process {
        id: cavaProc
        running: root.visible && (root.activePlayer?.isPlaying ?? false)
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.activePlayer !== null
        sourceComponent: root.isVertical ? verticalComponent : horizontalComponent
    }

    Component {
        id: horizontalComponent
        PlayerControl {
            player: root.activePlayer
            visualizerPoints: root.visualizerPoints
            implicitWidth: root.implicitWidth
            implicitHeight: root.implicitHeight
            radius: Appearance.rounding.normal
        }
    }

    Component {
        id: verticalComponent
        SpotifyCard {
            player: root.activePlayer
            visualizerPoints: root.visualizerPoints
            implicitWidth: root.implicitWidth
            implicitHeight: root.implicitHeight
            radius: Appearance.rounding.normal
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        visible: root.activePlayer === null && !root.hideWhenIdle
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12
            visible: root.isVertical

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 48
                color: Appearance.colors.colSubtext
                text: "music_off"
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
                text: Translation.tr("No active player")
            }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            visible: !root.isVertical

            MaterialSymbol {
                iconSize: 32
                color: Appearance.colors.colSubtext
                text: "music_off"
            }

            StyledText {
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
                text: Translation.tr("No active player")
            }
        }
    }
}
