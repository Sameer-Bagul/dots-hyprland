pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * StudioRecorderModal.qml
 * Studio Recording Setup Panel inspired by Recordly & Capptivo.
 * Configure webcam bubble, microphone, system audio, and auto cursor tracking
 * before launching high-quality screen recordings.
 */
PanelWindow {
    id: root

    visible: RecordingStudioService.setupModalOpen
    color: "transparent"
    WlrLayershell.namespace: "quickshell:recordingModal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: RecordingStudioService.setupModalOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)

        MouseArea {
            anchors.fill: parent
            onClicked: RecordingStudioService.closeStudioSetup()
        }
    }

    // Modal Card
    StyledRectangle {
        id: modalContent
        anchors.centerIn: parent
        width: 600
        implicitHeight: mainCol.implicitHeight + 40
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surface
        border.width: 1
        border.color: Appearance.m3colors.m3outlineVariant
        z: 100
        focus: true
        Keys.onEscapePressed: RecordingStudioService.closeStudioSetup()

        MouseArea {
            anchors.fill: parent
            // prevent click from bubbling to backdrop
        }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            // ---------------- Header ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledRectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: Appearance.m3colors.m3primaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "videocam"
                        iconSize: 24
                        color: Appearance.m3colors.m3onPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Studio Screen Recorder")
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.m3colors.m3onSurface
                    }

                    StyledText {
                        text: Translation.tr("Record professional demos with face cam, dual audio, and cursor tracking.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.closeStudioSetup()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.m3colors.m3onSurface
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Appearance.m3colors.m3outlineVariant }

            // ---------------- Source & Framerate Row ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Capture Target
                RowLayout {
                    spacing: 6

                    RippleButton {
                        implicitWidth: fullBtnRow.implicitWidth + 20
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        readonly property bool isSelected: RecordingStudioService.captureMode === "fullscreen"
                        colBackground: isSelected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: RecordingStudioService.captureMode = "fullscreen"

                        RowLayout {
                            id: fullBtnRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "screenshot_monitor"
                                iconSize: 16
                                color: parent.parent.isSelected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                text: Translation.tr("Entire Screen")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: parent.parent.isSelected
                                color: parent.parent.isSelected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: regBtnRow.implicitWidth + 20
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        readonly property bool isSelected: RecordingStudioService.captureMode === "region"
                        colBackground: isSelected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: RecordingStudioService.captureMode = "region"

                        RowLayout {
                            id: regBtnRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "crop"
                                iconSize: 16
                                color: parent.parent.isSelected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                text: Translation.tr("Selected Area")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: parent.parent.isSelected
                                color: parent.parent.isSelected ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Framerate (60fps vs 30fps)
                RowLayout {
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Rate:")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }

                    RippleButton {
                        implicitWidth: 48
                        implicitHeight: 28
                        buttonRadius: 14
                        readonly property bool isSelected: RecordingStudioService.fps === 60
                        colBackground: isSelected ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: RecordingStudioService.fps = 60
                        StyledText {
                            anchors.centerIn: parent
                            text: "60 FPS"
                            font.bold: parent.isSelected
                            font.pixelSize: 10
                            color: parent.isSelected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                        }
                    }

                    RippleButton {
                        implicitWidth: 48
                        implicitHeight: 28
                        buttonRadius: 14
                        readonly property bool isSelected: RecordingStudioService.fps === 30
                        colBackground: isSelected ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: RecordingStudioService.fps = 30
                        StyledText {
                            anchors.centerIn: parent
                            text: "30 FPS"
                            font.bold: parent.isSelected
                            font.pixelSize: 10
                            color: parent.isSelected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                        }
                    }
                }
            }

            // ---------------- 2-Column Bento Grid ----------------
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 14
                rowSpacing: 14

                // CARD 1: Face Cam / Webcam Bubble
                StyledRectangle {
                    Layout.fillWidth: true
                    implicitHeight: camCardCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.m3colors.m3surfaceContainer
                    border.width: 1
                    border.color: Appearance.m3colors.m3outlineVariant

                    ColumnLayout {
                        id: camCardCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // Toggle Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "videocam"; iconSize: 20; color: Appearance.m3colors.m3primary }
                            StyledText {
                                text: Translation.tr("Face Cam Bubble")
                                font.bold: true
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3onSurface
                            }
                            Item { Layout.fillWidth: true }
                            StyledSwitch {
                                checked: RecordingStudioService.cameraEnabled
                                onCheckedChanged: RecordingStudioService.cameraEnabled = checked
                            }
                        }

                        // Shape & Size controls (enabled only when camera on)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            opacity: RecordingStudioService.cameraEnabled ? 1.0 : 0.45
                            enabled: RecordingStudioService.cameraEnabled

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { text: Translation.tr("Shape"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.m3colors.m3onSurfaceVariant }
                                Item { Layout.fillWidth: true }
                                RippleButton {
                                    implicitHeight: 26
                                    implicitWidth: 64
                                    buttonRadius: 13
                                    readonly property bool isSelected: RecordingStudioService.cameraShape === "circle"
                                    colBackground: isSelected ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                                    onClicked: RecordingStudioService.cameraShape = "circle"
                                    StyledText { anchors.centerIn: parent; text: Translation.tr("Circle"); font.pixelSize: 10; color: parent.isSelected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface }
                                }
                                RippleButton {
                                    implicitHeight: 26
                                    implicitWidth: 64
                                    buttonRadius: 13
                                    readonly property bool isSelected: RecordingStudioService.cameraShape === "rectangle"
                                    colBackground: isSelected ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                                    onClicked: RecordingStudioService.cameraShape = "rectangle"
                                    StyledText { anchors.centerIn: parent; text: Translation.tr("Rect"); font.pixelSize: 10; color: parent.isSelected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { text: Translation.tr("Size"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.m3colors.m3onSurfaceVariant }
                                Item { Layout.fillWidth: true }
                                Repeater {
                                    model: [Translation.tr("S"), Translation.tr("M"), Translation.tr("L")]
                                    delegate: RippleButton {
                                        required property var modelData
                                        required property int index
                                        implicitHeight: 26
                                        implicitWidth: 36
                                        buttonRadius: 13
                                        readonly property bool isSelected: RecordingStudioService.cameraSizePreset === index
                                        colBackground: isSelected ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                                        onClicked: RecordingStudioService.cameraSizePreset = index
                                        StyledText { anchors.centerIn: parent; text: modelData; font.pixelSize: 10; color: parent.isSelected ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { text: Translation.tr("Mirror Camera"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.m3colors.m3onSurfaceVariant }
                                Item { Layout.fillWidth: true }
                                StyledSwitch {
                                    checked: RecordingStudioService.cameraMirrored
                                    onCheckedChanged: RecordingStudioService.cameraMirrored = checked
                                }
                            }
                        }
                    }
                }

                // CARD 2: Audio Mixing & Cursor Tracking
                StyledRectangle {
                    Layout.fillWidth: true
                    implicitHeight: audioCardCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.m3colors.m3surfaceContainer
                    border.width: 1
                    border.color: Appearance.m3colors.m3outlineVariant

                    ColumnLayout {
                        id: audioCardCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "mic"; iconSize: 20; color: Appearance.m3colors.m3primary }
                            StyledText {
                                text: Translation.tr("Audio & Cursor Studio")
                                font.bold: true
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3onSurface
                            }
                        }

                        // Microphone Toggle
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "mic"; iconSize: 16; color: Appearance.m3colors.m3onSurfaceVariant }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { text: Translation.tr("Microphone Voice"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onSurface }
                                StyledText { text: Translation.tr("Record your narration"); font.pixelSize: 10; color: Appearance.m3colors.m3outline }
                            }
                            StyledSwitch {
                                checked: RecordingStudioService.micEnabled
                                onCheckedChanged: RecordingStudioService.micEnabled = checked
                            }
                        }

                        // System Audio Toggle
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "volume_up"; iconSize: 16; color: Appearance.m3colors.m3onSurfaceVariant }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { text: Translation.tr("Desktop & App Sound"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onSurface }
                                StyledText { text: Translation.tr("Mix system audio into stream"); font.pixelSize: 10; color: Appearance.m3colors.m3outline }
                            }
                            StyledSwitch {
                                checked: RecordingStudioService.systemAudioEnabled
                                onCheckedChanged: RecordingStudioService.systemAudioEnabled = checked
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Appearance.m3colors.m3outlineVariant }

                        // Auto Cursor Tracking / Zoom
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "zoom_in"; iconSize: 16; color: Appearance.m3colors.m3secondary }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { text: Translation.tr("Follow-Cursor Zoom"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onSurface }
                                StyledText { text: Translation.tr("Smooth Hyprland camera glide"); font.pixelSize: 10; color: Appearance.m3colors.m3secondary }
                            }
                            StyledSwitch {
                                checked: RecordingStudioService.autoZoomEnabled
                                onCheckedChanged: RecordingStudioService.autoZoomEnabled = checked
                            }
                        }
                    }
                }
            }

            // ---------------- Action Footer ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    spacing: 6
                    MaterialSymbol { text: "timer"; iconSize: 16; color: Appearance.m3colors.m3primary }
                    StyledText {
                        text: Translation.tr("3s Countdown on Start")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 84
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.closeStudioSetup()
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                    }
                }

                RippleButton {
                    implicitWidth: startRow.implicitWidth + 28
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.m3colors.m3primary
                    onClicked: RecordingStudioService.startRecordingWithCountdown()

                    RowLayout {
                        id: startRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: "#FF3B30"
                        }
                        StyledText {
                            text: Translation.tr("Start Studio Recording")
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
            }
        }
    }
}
