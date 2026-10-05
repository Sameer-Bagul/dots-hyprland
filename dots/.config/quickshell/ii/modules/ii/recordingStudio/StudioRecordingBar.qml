pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * StudioRecordingBar.qml
 * Floating capsule dock that appears while recording is active.
 * Shows elapsed time, animated audio VU meter, cursor follow-zoom toggle,
 * camera toggle, mic mute, pause, and stop/finish controls.
 */
PanelWindow {
    id: root

    visible: RecordingStudioService.isRecording
    color: "transparent"
    WlrLayershell.namespace: "quickshell:recordingBar"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Only the dock pill consumes clicks, clicks around it pass through
    mask: Region {
        item: floatingDock
    }

    StyledRectangle {
        id: floatingDock
        x: Math.round((root.width - width) / 2)
        y: 56
        implicitHeight: 46
        implicitWidth: dockLayout.implicitWidth + 24
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3surfaceContainerHighest
        border.width: 1
        border.color: Appearance.m3colors.m3outlineVariant
        z: 999

        DragHandler {
            target: floatingDock
            xAxis.minimum: 16
            xAxis.maximum: Math.max(root.width - floatingDock.width - 16, 16)
            yAxis.minimum: 16
            yAxis.maximum: Math.max(root.height - floatingDock.height - 16, 16)
        }

        RowLayout {
            id: dockLayout
            anchors.centerIn: parent
            spacing: 10

            // 1. Live Recording State & Timer Badge
            RowLayout {
                spacing: 8

                // Pulsing Red Recording Dot
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: RecordingStudioService.isPaused ? Appearance.m3colors.m3tertiary : "#FF3B30"

                    SequentialAnimation on opacity {
                        running: RecordingStudioService.isRecording && !RecordingStudioService.isPaused
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    text: RecordingStudioService.isPaused ? Translation.tr("PAUSED") : "REC"
                    font.bold: true
                    font.pixelSize: 11
                    color: RecordingStudioService.isPaused ? Appearance.m3colors.m3tertiary : "#FF3B30"
                }

                StyledText {
                    text: RecordingStudioService.formattedTime
                    font.bold: true
                    font.family: "monospace"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSurface
                }
            }

            Rectangle { width: 1; height: 22; color: Appearance.m3colors.m3outlineVariant }

            // 2. Animated Audio VU Equalizer Meter
            RowLayout {
                spacing: 3
                visible: RecordingStudioService.micEnabled

                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: 3
                        readonly property real targetH: {
                            if (!RecordingStudioService.isRecording || RecordingStudioService.isPaused) return 4;
                            let level = RecordingStudioService.simulatedAudioLevel;
                            let factor = (index % 2 === 0) ? 1.0 : 0.7;
                            return Math.max(4, Math.round(level * 18 * factor));
                        }
                        height: targetH
                        radius: 1.5
                        color: Appearance.m3colors.m3primary
                        Behavior on height { NumberAnimation { duration: 80 } }
                    }
                }
            }

            Rectangle {
                visible: RecordingStudioService.micEnabled
                width: 1; height: 22; color: Appearance.m3colors.m3outlineVariant
            }

            // 3. Zoom Focus Toggle (Smooth Hyprland Cursor Follow)
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: RecordingStudioService.zoomActive ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                onClicked: RecordingStudioService.toggleZoom()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: RecordingStudioService.zoomActive ? "zoom_out" : "zoom_in"
                    iconSize: 18
                    color: RecordingStudioService.zoomActive ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                }
                StyledToolTip { text: Translation.tr("Toggle Follow-Cursor Zoom (Super+Z)") }
            }

            // 4. Camera Bubble Toggle
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: RecordingStudioService.cameraEnabled ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                onClicked: RecordingStudioService.toggleCamera()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: RecordingStudioService.cameraEnabled ? "videocam" : "videocam_off"
                    iconSize: 18
                    color: RecordingStudioService.cameraEnabled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                }
                StyledToolTip { text: Translation.tr("Toggle Camera Overlay") }
            }

            // 5. Microphone Mute Toggle
            RippleButton {
                id: micButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                readonly property bool isMuted: (Audio.source && Audio.source.audio) ? Audio.source.audio.muted : false
                colBackground: micButton.isMuted ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3surfaceContainerHigh
                onClicked: Audio.toggleMicMute()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: micButton.isMuted ? "mic_off" : "mic"
                    iconSize: 18
                    color: micButton.isMuted ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSurface
                }
                StyledToolTip { text: micButton.isMuted ? Translation.tr("Unmute Microphone") : Translation.tr("Mute Microphone") }
            }

            // 6. Pause / Resume Button
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                onClicked: RecordingStudioService.togglePause()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: RecordingStudioService.isPaused ? "play_arrow" : "pause"
                    iconSize: 18
                    color: Appearance.m3colors.m3onSurface
                }
                StyledToolTip { text: RecordingStudioService.isPaused ? Translation.tr("Resume Recording") : Translation.tr("Pause Recording") }
            }

            Rectangle { width: 1; height: 22; color: Appearance.m3colors.m3outlineVariant }

            // 7. Finish & Save Button
            RippleButton {
                implicitWidth: finishRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: 17
                colBackground: Appearance.m3colors.m3primary
                onClicked: RecordingStudioService.stopRecording()

                RowLayout {
                    id: finishRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "stop_circle"
                        iconSize: 18
                        color: Appearance.m3colors.m3onPrimary
                    }
                    StyledText {
                        text: Translation.tr("Finish")
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onPrimary
                    }
                }
                StyledToolTip { text: Translation.tr("Stop and save video to ~/Videos/Recordings") }
            }

            // 8. Cancel / Discard Button
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                onClicked: RecordingStudioService.cancelRecording()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.m3colors.m3outline
                }
                StyledToolTip { text: Translation.tr("Discard & Cancel Recording") }
            }
        }
    }
}
