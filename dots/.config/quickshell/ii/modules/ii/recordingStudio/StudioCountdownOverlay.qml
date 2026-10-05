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
 * StudioCountdownOverlay.qml
 * Animated 3-second countdown overlay before studio screen recording begins.
 * Gives the presenter time to prepare with a bold, cinematic visual pulse.
 */
PanelWindow {
    id: root

    visible: RecordingStudioService.countdownActive
    color: "transparent"
    WlrLayershell.namespace: "quickshell:recordingCountdown"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Semi-transparent cinematic dark blur veil
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        // MouseArea to absorb clicks during countdown and allow Esc to cancel
        MouseArea {
            anchors.fill: parent
            onClicked: RecordingStudioService.cancelRecording()
        }

        Item {
            anchors.centerIn: parent
            width: 320
            height: 320

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 24

                // Countdown Pulsing Circle
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    width: 140
                    height: 140

                    StyledRectangle {
                        id: pulseCircle
                        anchors.fill: parent
                        radius: 70
                        color: Appearance.m3colors.m3primary
                        border.width: 4
                        border.color: Appearance.m3colors.m3onPrimary

                        scale: 1.0
                        onScaleChanged: {
                            // reset
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(RecordingStudioService.countdownValue)
                            font.bold: true
                            font.pixelSize: 72
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }

                    // Dynamic scale bounce on each second tick
                    Connections {
                        target: RecordingStudioService
                        function onCountdownValueChanged() {
                            bounceAnim.restart();
                        }
                    }

                    SequentialAnimation {
                        id: bounceAnim
                        NumberAnimation { target: pulseCircle; property: "scale"; from: 0.65; to: 1.15; duration: 200; easing.type: Easing.OutBack }
                        NumberAnimation { target: pulseCircle; property: "scale"; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Get Ready...")
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: "#FFFFFF"
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Recording starts in %1s").arg(RecordingStudioService.countdownValue)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Qt.rgba(1, 1, 1, 0.75)
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitHeight: 34
                    implicitWidth: 120
                    buttonRadius: 17
                    colBackground: Qt.rgba(1, 1, 1, 0.18)
                    onClicked: RecordingStudioService.cancelRecording()

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol { text: "close"; iconSize: 16; color: "#FFFFFF" }
                        StyledText { text: Translation.tr("Cancel"); font.pixelSize: Appearance.font.pixelSize.small; color: "#FFFFFF" }
                    }
                }
            }
        }
    }
}
