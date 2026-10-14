pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root

    implicitWidth: 290
    implicitHeight: 485

    required property MprisPlayer player
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000
    property int visualizerSmoothing: 2
    property real radius: Appearance.rounding.normal

    // Find the player with full duration (> 30s) if activePlayer only provides a short HTML5 buffer (e.g. 8-10s)
    readonly property MprisPlayer effectivePlayer: {
        if (root.player && root.player.length > 30) return root.player;
        if (MprisController.players) {
            let realCandidate = MprisController.players.find(p => p.length > 30 && (
                p.isPlaying ||
                (root.player?.trackTitle && p.trackTitle && (p.trackTitle.includes(root.player.trackTitle) || root.player.trackTitle.includes(p.trackTitle)))
            ));
            if (realCandidate) return realCandidate;
        }
        return root.player;
    }

    readonly property real trackLength: effectivePlayer?.length ?? (root.player?.length ?? 0)
    readonly property real trackPosition: effectivePlayer?.position ?? (root.player?.position ?? 0)

    // Artwork resolution with companion fallback
    property var artUrl: {
        let p = effectivePlayer ?? root.player;
        if (p?.trackArtUrl && p.trackArtUrl.length > 0 && !p.trackArtUrl.includes("brave") && !p.trackArtUrl.includes("chromium")) {
            return p.trackArtUrl;
        }
        if (root.player?.trackArtUrl && root.player.trackArtUrl.length > 0 && !root.player.trackArtUrl.includes("brave") && !root.player.trackArtUrl.includes("chromium")) {
            return root.player.trackArtUrl;
        }
        if (MprisController.players) {
            let companion = MprisController.players.find(cp => cp.trackArtUrl && cp.trackArtUrl.length > 0 && !cp.trackArtUrl.includes("brave") && !cp.trackArtUrl.includes("chromium"));
            if (companion) return companion.trackArtUrl;
        }
        return p?.trackArtUrl ?? "";
    }

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl ?? "")
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool downloaded: false

    property string displayedArtFilePath: {
        if (!root.artUrl || root.artUrl.length === 0) return "";
        if (root.artUrl.startsWith("file://") || root.artUrl.startsWith("/")) {
            return root.artUrl;
        }
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    // Split title and artist if Brave bundles them as "Title • Artist"
    readonly property var titleArtistSplit: {
        let p = effectivePlayer ?? root.player;
        let title = p?.trackTitle ?? "";
        let artist = p?.trackArtist ?? "";

        if ((!artist || artist.length === 0) && MprisController.players) {
            let companion = MprisController.players.find(cp => cp.trackArtist && cp.trackArtist.length > 0);
            if (companion) artist = companion.trackArtist;
        }

        if ((!artist || artist.length === 0) && title.includes(" • ")) {
            let idx = title.lastIndexOf(" • ");
            return {
                title: title.substring(0, idx).trim(),
                artist: title.substring(idx + 3).trim()
            };
        }

        return {
            title: title,
            artist: artist
        };
    }

    Timer {
        running: (effectivePlayer?.playbackState === MprisPlaybackState.Playing) || (root.player?.playbackState === MprisPlaybackState.Playing)
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: {
            effectivePlayer?.positionChanged();
            if (root.player && root.player !== effectivePlayer) {
                root.player.positionChanged();
            }
        }
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            return;
        }
        if (root.artUrl.startsWith("file://") || root.artUrl.startsWith("/")) {
            root.downloaded = true;
            return;
        }

        coverArtDownloader.targetFile = root.artUrl;
        coverArtDownloader.artFilePath = root.artFilePath;
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    Component.onCompleted: {
        if (root.artUrl && (root.artUrl.startsWith("file://") || root.artUrl.startsWith("/"))) {
            root.downloaded = true;
        } else if (root.artUrl && root.artUrl.length > 0) {
            coverArtDownloader.targetFile = root.artUrl;
            coverArtDownloader.artFilePath = root.artFilePath;
            root.downloaded = false;
            coverArtDownloader.running = true;
        }
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f '${artFilePath}' ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true;
        }
    }

    // Wallpaper-driven color palette so the widget dramatically and harmoniously reflects wallpaper changes
    property QtObject blendedColors: Appearance.colors

    function toggleShuffle() {
        if (root.player && root.player.shuffleSupported) {
            root.player.shuffle = !root.player.shuffle;
        }
    }

    function cycleLoop() {
        if (!root.player || !root.player.loopSupported) return;
        const current = root.player.loopState;
        if (current === MprisLoopState.None) {
            root.player.loopState = MprisLoopState.Playlist;
        } else if (current === MprisLoopState.Playlist) {
            root.player.loopState = MprisLoopState.Track;
        } else {
            root.player.loopState = MprisLoopState.None;
        }
    }

    StyledRectangularShadow {
        target: background
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 0.96)
        radius: root.radius
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        // Ambient blurred album art backdrop
        StyledImage {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            opacity: 0.18

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }
        }

        // Subtle gradient overlay from top to bottom
        Rectangle {
            anchors.fill: parent
            radius: background.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.transparentize(blendedColors.colLayer0, 0.35) }
                GradientStop { position: 0.45; color: ColorUtils.transparentize(blendedColors.colLayer0, 0.15) }
                GradientStop { position: 1.0; color: ColorUtils.applyAlpha(blendedColors.colLayer0, 0.95) }
            }
        }

        // Bottom audio wave visualizer
        WaveVisualizer {
            id: visualizerCanvas
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 80
            live: root.player?.isPlaying ?? false
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        // Main content column
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14
            anchors.bottomMargin: 18
            spacing: 8



            // Prominent square album art with ambient shadow & quick play hover
            Item {
                id: artContainer
                Layout.fillWidth: true
                Layout.preferredHeight: width
                Layout.alignment: Qt.AlignHCenter

                RectangularShadow {
                    anchors.fill: artClip
                    radius: artClip.radius
                    blur: 16
                    offset: Qt.vector2d(0.0, 5.0)
                    spread: 0.05
                    color: ColorUtils.transparentize(blendedColors.colPrimary, 0.55)
                    cached: true
                }

                Rectangle {
                    id: artClip
                    anchors.fill: parent
                    radius: Appearance.rounding.verysmall + 4
                    color: ColorUtils.transparentize(blendedColors.colLayer1, 0.5)

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artClip.width
                            height: artClip.height
                            radius: artClip.radius
                        }
                    }

                    StyledImage {
                        id: mediaArt
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !root.displayedArtFilePath || root.displayedArtFilePath.length === 0
                        color: blendedColors.colLayer1

                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 56
                            color: blendedColors.colSubtext
                            text: "album"
                        }
                    }

                    MouseArea {
                        id: artMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (root.effectivePlayer ?? root.player)?.togglePlaying()

                        Rectangle {
                            anchors.fill: parent
                            color: ColorUtils.applyAlpha(blendedColors.colLayer0, 0.4)
                            opacity: artMouseArea.containsMouse ? 1 : 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 48
                                height: 48
                                radius: 24
                                color: ColorUtils.applyAlpha(blendedColors.colLayer0, 0.8)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 28
                                    color: blendedColors.colOnLayer0
                                    fill: 1
                                    text: ((root.effectivePlayer ?? root.player)?.isPlaying ?? false) ? "pause" : "play_arrow"
                                }
                            }
                        }
                    }
                }
            }

            // Track info: Title, Artist/Album, and Like button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        id: trackTitle
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: blendedColors.colOnLayer0
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.titleArtistSplit.title) || Translation.tr("Untitled")
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }

                    StyledText {
                        id: trackArtist
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: blendedColors.colSubtext
                        elide: Text.ElideRight
                        text: root.titleArtistSplit.artist || Translation.tr("Unknown Artist")
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }
                }

                RippleButton {
                    id: heartBtn
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    property bool liked: false
                    colBackground: "transparent"
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => { heartBtn.liked = !heartBtn.liked }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        fill: heartBtn.liked ? 1 : 0
                        color: heartBtn.liked ? "#1DB954" : blendedColors.colSubtext
                        text: heartBtn.liked ? "favorite" : "favorite_border"

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            // Timeline: seek slider and timestamp labels
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: ((root.effectivePlayer?.canSeek || root.player?.canSeek) ?? false)
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            wavy: false
                            highlightColor: blendedColors.colPrimary
                            trackColor: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.4)
                            handleColor: blendedColors.colPrimary
                            value: (root.trackLength > 0) ? (root.trackPosition / root.trackLength) : 0
                            onMoved: {
                                if (root.trackLength > 0) {
                                    if (root.effectivePlayer) {
                                        root.effectivePlayer.position = value * root.trackLength;
                                    }
                                    if (root.player && root.player !== root.effectivePlayer && root.player.canSeek) {
                                        root.player.position = value * (root.player.length > 30 ? root.trackLength : root.player.length);
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: !((root.effectivePlayer?.canSeek || root.player?.canSeek) ?? false)
                        sourceComponent: StyledProgressBar {
                            wavy: false
                            highlightColor: blendedColors.colPrimary
                            trackColor: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.4)
                            value: (root.trackLength > 0) ? (root.trackPosition / root.trackLength) : 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: blendedColors.colSubtext
                        text: StringUtils.friendlyTimeForSeconds(root.trackPosition)
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: blendedColors.colSubtext
                        text: StringUtils.friendlyTimeForSeconds(root.trackLength)
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            // Controls row: Shuffle, Previous, Play/Pause FAB, Next, Repeat
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 4
                spacing: 12

                RippleButton {
                    id: shuffleBtn
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 17
                    enabled: (root.effectivePlayer ?? root.player)?.shuffleSupported ?? false
                    opacity: enabled ? 1.0 : 0.35
                    property bool active: (root.effectivePlayer ?? root.player)?.shuffle ?? false
                    colBackground: "transparent"
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.toggleShuffle()

                    contentItem: Item {
                        anchors.fill: parent
                        MaterialSymbol {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: shuffleBtn.active ? -2 : 0
                            iconSize: 20
                            color: shuffleBtn.active ? (blendedColors.colPrimary || "#1DB954") : blendedColors.colSubtext
                            text: "shuffle"
                        }
                        Rectangle {
                            visible: shuffleBtn.active
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 4
                            height: 4
                            radius: 2
                            color: blendedColors.colPrimary || "#1DB954"
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 19
                    enabled: (root.effectivePlayer ?? root.player)?.canGoPrevious ?? true
                    opacity: enabled ? 1.0 : 0.4
                    colBackground: "transparent"
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => (root.effectivePlayer ?? root.player)?.previous()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 26
                        color: blendedColors.colOnLayer0
                        fill: 1
                        text: "skip_previous"
                    }
                }

                RippleButton {
                    id: playPauseButton
                    property real size: 48
                    implicitWidth: size
                    implicitHeight: size
                    buttonRadius: size / 2
                    colBackground: blendedColors.colPrimary
                    colBackgroundHover: blendedColors.colPrimaryHover
                    colRipple: blendedColors.colPrimaryActive
                    downAction: () => (root.effectivePlayer ?? root.player)?.togglePlaying()

                    RectangularShadow {
                        anchors.fill: parent
                        radius: parent.buttonRadius
                        blur: 8
                        offset: Qt.vector2d(0.0, 2.0)
                        spread: 0.1
                        color: ColorUtils.transparentize(blendedColors.colPrimary, 0.4)
                        cached: true
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 28
                        fill: 1
                        color: blendedColors.colOnPrimary
                        text: ((root.effectivePlayer ?? root.player)?.isPlaying ?? false) ? "pause" : "play_arrow"

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 19
                    enabled: (root.effectivePlayer ?? root.player)?.canGoNext ?? true
                    opacity: enabled ? 1.0 : 0.4
                    colBackground: "transparent"
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => (root.effectivePlayer ?? root.player)?.next()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 26
                        color: blendedColors.colOnLayer0
                        fill: 1
                        text: "skip_next"
                    }
                }

                RippleButton {
                    id: repeatBtn
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 17
                    enabled: (root.effectivePlayer ?? root.player)?.loopSupported ?? false
                    opacity: enabled ? 1.0 : 0.35
                    property var loopState: (root.effectivePlayer ?? root.player)?.loopState ?? MprisLoopState.None
                    property bool active: loopState !== MprisLoopState.None
                    colBackground: "transparent"
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.cycleLoop()

                    contentItem: Item {
                        anchors.fill: parent
                        MaterialSymbol {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: repeatBtn.active ? -2 : 0
                            iconSize: 20
                            color: repeatBtn.active ? (blendedColors.colPrimary || "#1DB954") : blendedColors.colSubtext
                            text: repeatBtn.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                        }
                        Rectangle {
                            visible: repeatBtn.active
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 4
                            height: 4
                            radius: 2
                            color: blendedColors.colPrimary || "#1DB954"
                        }
                    }
                }
            }
        }
    }
}
