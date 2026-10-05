pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * CameraBubble.qml
 * Picture-in-Picture draggable webcam overlay for Studio Screen Recording.
 * Inspired by Recordly, Loom, and Screen Studio.
 * Supports Circular Bubble and Rounded Rect, mirror flip, corner snapping, and size presets.
 */
PanelWindow {
    id: root

    readonly property bool shouldBeVisible: RecordingStudioService.cameraEnabled && (RecordingStudioService.isRecording || RecordingStudioService.setupModalOpen)
    visible: shouldBeVisible

    color: "transparent"
    WlrLayershell.namespace: "quickshell:cameraBubble"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Only the camera bubble intercepts mouse clicks, rest passes through
    mask: Region {
        item: bubbleWrapper
    }

    MediaDevices {
        id: mediaDevices
    }

    Item {
        id: bubbleWrapper
        x: RecordingStudioService.cameraX
        y: RecordingStudioService.cameraY
        width: RecordingStudioService.cameraWidth
        height: RecordingStudioService.cameraHeight
        z: 100

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Camera Feed Container with Mask
        Item {
            id: videoContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: videoContainer.width
                    height: videoContainer.height
                    radius: (RecordingStudioService.cameraShape === "circle") ? (width / 2) : 24
                }
            }

            // Dark placeholder background if camera is warming up
            Rectangle {
                anchors.fill: parent
                color: "#121316"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "videocam"
                        iconSize: 32
                        color: Appearance.m3colors.m3primary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Camera Active")
                        font.pixelSize: 11
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }
            }

            CaptureSession {
                id: captureSession
                camera: Camera {
                    id: camera
                    cameraDevice: mediaDevices.defaultVideoInput
                    active: root.shouldBeVisible
                }
                videoOutput: videoOutput
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                // Horizontal mirror transform
                transform: Scale {
                    origin.x: videoOutput.width / 2
                    xScale: RecordingStudioService.cameraMirrored ? -1 : 1
                }
            }
        }

        // Glowing outer accent ring
        Rectangle {
            id: accentRing
            anchors.fill: parent
            radius: (RecordingStudioService.cameraShape === "circle") ? (width / 2) : 24
            color: "transparent"
            border.width: 3
            border.color: RecordingStudioService.isRecording ? Appearance.m3colors.m3primary : Appearance.m3colors.m3secondary

            // Smooth subtle breathing pulse when recording
            SequentialAnimation on border.width {
                running: RecordingStudioService.isRecording && !RecordingStudioService.isPaused
                loops: Animation.Infinite
                NumberAnimation { to: 4.5; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 2.5; duration: 900; easing.type: Easing.InOutQuad }
            }
        }

        // Floating Quick Controls Toolbar on Hover
        StyledRectangle {
            id: hoverBar
            visible: dragMouseArea.containsMouse || hoverBarMouse.containsMouse
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            implicitHeight: 32
            implicitWidth: controlsRow.implicitWidth + 14
            radius: Appearance.rounding.full
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant
            z: 200

            MouseArea {
                id: hoverBarMouse
                anchors.fill: parent
                hoverEnabled: true
            }

            RowLayout {
                id: controlsRow
                anchors.centerIn: parent
                spacing: 6

                // Shape Switcher (Circle / Rectangle)
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.cycleCameraShape()
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: (RecordingStudioService.cameraShape === "circle") ? "crop_16_9" : "radio_button_unchecked"
                        iconSize: 15
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledToolTip { text: Translation.tr("Switch Shape (Circle / Rectangle)") }
                }

                // Size Switcher (S / M / L)
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.cycleCameraSize()
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "photo_size_select_small"
                        iconSize: 15
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledToolTip { text: Translation.tr("Cycle Size Preset") }
                }

                // Mirror Flip Toggle
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.toggleCameraMirror()
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "flip"
                        iconSize: 15
                        color: RecordingStudioService.cameraMirrored ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                    }
                    StyledToolTip { text: Translation.tr("Flip / Mirror Camera") }
                }

                // Hide Camera
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: RecordingStudioService.toggleCamera()
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 15
                        color: Appearance.m3colors.m3error
                    }
                    StyledToolTip { text: Translation.tr("Hide Camera Bubble") }
                }
            }
        }

        // Draggable Area covering the entire bubble
        MouseArea {
            id: dragMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: bubbleWrapper
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 16
            drag.maximumX: Math.max(root.width - bubbleWrapper.width - 16, 16)
            drag.minimumY: 16
            drag.maximumY: Math.max(root.height - bubbleWrapper.height - 16, 16)

            onReleased: {
                RecordingStudioService.cameraX = bubbleWrapper.x;
                RecordingStudioService.cameraY = bubbleWrapper.y;
            }
        }
    }
}
