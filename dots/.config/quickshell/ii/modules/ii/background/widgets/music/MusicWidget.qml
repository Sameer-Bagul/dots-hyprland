pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
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

AbstractBackgroundWidget {
    id: root

    configEntryName: "music"

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hasTrack: (player && ((player.trackTitle && player.trackTitle.length > 0) || (player.trackArtist && player.trackArtist.length > 0))) ?? false
    readonly property bool hideWhenIdle: Config.options.background.widgets.music?.hideWhenIdle ?? true

    visible: (!hideWhenIdle || hasTrack) && (opacity > 0)

    implicitWidth: cardBackground.implicitWidth
    implicitHeight: cardBackground.implicitHeight

    // Cover art handling
    property var artUrl: player?.trackArtUrl ?? ""
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl || "")
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool downloaded: false
    property string displayedArtFilePath: {
        if (!artUrl || artUrl.length === 0) return "";
        if (artUrl.startsWith("file://")) return artUrl;
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtUrlChanged: {
        if (!artUrl || artUrl.length === 0 || artUrl.startsWith("file://")) {
            return;
        }
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: [
            "bash", "-c",
            `mkdir -p '${root.artDownloadLocation}' && [ -f '${artFilePath}' ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'`
        ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true;
        }
    }

    Timer {
        running: root.player?.playbackState === MprisPlaybackState.Playing
        interval: 500
        repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged();
        }
    }

    StyledDropShadow {
        target: cardBackground
    }

    Rectangle {
        id: cardBackground
        implicitWidth: 340
        implicitHeight: 110
        radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.35)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // Album art square
            Rectangle {
                id: artContainer
                Layout.preferredWidth: 86
                Layout.preferredHeight: 86
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer
                clip: true

                StyledImage {
                    id: artImage
                    anchors.fill: parent
                    visible: root.displayedArtFilePath.length > 0 && status === Image.Ready
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    asynchronous: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !artImage.visible
                    iconSize: 40
                    color: Appearance.colors.colOnSecondaryContainer
                    text: root.player?.isPlaying ? "equalizer" : "music_note"
                }
            }

            // Track info & controls column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                // Title
                StyledText {
                    id: titleText
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("No media playing")
                }

                // Artist
                StyledText {
                    id: artistText
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: root.player?.trackArtist || (root.hasTrack ? Translation.tr("Unknown Artist") : "")
                }

                Item { Layout.fillHeight: true }

                // Time progress row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 14

                        StyledSlider {
                            anchors.fill: parent
                            configuration: StyledSlider.Configuration.Wavy
                            highlightColor: Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colSecondaryContainer
                            handleColor: Appearance.colors.colPrimary
                            enabled: (root.player?.canSeek ?? false) && (root.player?.length > 0)
                            value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                            onMoved: {
                                if (root.player && root.player.length > 0) {
                                    root.player.position = value * root.player.length;
                                }
                            }
                        }
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                        visible: root.hasTrack && (root.player?.length > 0)
                    }
                }

                // Controls row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    // Previous button
                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        enabled: root.player?.canGoPrevious ?? false
                        onClicked: root.player?.previous()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 18
                            color: parent.enabled ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                            text: "skip_previous"
                        }
                    }

                    // Play/Pause button
                    RippleButton {
                        implicitWidth: 34
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        enabled: root.player !== null
                        onClicked: root.player?.togglePlaying()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 20
                            color: Appearance.colors.colOnPrimary
                            text: root.player?.isPlaying ? "pause" : "play_arrow"
                        }
                    }

                    // Next button
                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        enabled: root.player?.canGoNext ?? false
                        onClicked: root.player?.next()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 18
                            color: parent.enabled ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                            text: "skip_next"
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
