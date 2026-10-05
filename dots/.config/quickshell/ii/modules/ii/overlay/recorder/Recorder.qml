pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: 380
    minimumHeight: 140

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 8
        ColumnLayout {
            id: contentColumn
            anchors.centerIn: parent
            spacing: 10

            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 10

                BigRecorderButton {
                    materialSymbol: "screenshot_region"
                    name: "Screenshot region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "photo_camera"
                    name: "Screenshot"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["bash", "-c", "grim - | wl-copy"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "screen_record"
                    name: "Record region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "recordWithSound"]);
                    }
                }
                
                BigRecorderButton {
                    materialSymbol: "capture"
                    name: "Record screen"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen", "--sound"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "video_camera_front"
                    name: "Studio Recording (Recordly)"
                    isStudio: true
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        RecordingStudioService.openStudioSetup();
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 8

                RippleButton {
                    Layout.fillWidth: false
                    buttonRadius: height / 2
                    colBackground: Qt.rgba(Appearance.m3colors.m3primary.r, Appearance.m3colors.m3primary.g, Appearance.m3colors.m3primary.b, 0.16)
                    colBackgroundHover: Qt.rgba(Appearance.m3colors.m3primary.r, Appearance.m3colors.m3primary.g, Appearance.m3colors.m3primary.b, 0.26)
                    colRipple: Appearance.m3colors.m3primaryContainer
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        RecordingStudioService.openStudioSetup();
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 6
                        bottomPadding: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "auto_awesome"
                            iconSize: 18
                            color: Appearance.m3colors.m3primary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Recordly Studio")
                            font.bold: true
                            color: Appearance.m3colors.m3primary
                        }
                    }
                }

                RippleButton {
                    Layout.fillWidth: false
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Qt.openUrlExternally(`file://${Config.options.screenRecord.savePath}`);
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 6
                        bottomPadding: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "folder_open"
                            iconSize: 18
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Recordings")
                        }
                    }
                }
            }
        }
    }

    component BigRecorderButton: RippleButton {
        id: bigButton
        required property string materialSymbol
        required property string name
        property bool isStudio: false
        implicitHeight: 66
        implicitWidth: 66
        buttonRadius: height / 2

        colBackground: isStudio ? Appearance.m3colors.m3primaryContainer : Appearance.colors.colLayer3
        colBackgroundHover: isStudio ? Qt.darker(Appearance.m3colors.m3primaryContainer, 1.1) : Appearance.colors.colLayer3Hover
        colRipple: isStudio ? Appearance.m3colors.m3primary : Appearance.colors.colLayer3Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: bigButton.materialSymbol
            iconSize: 28
            color: bigButton.isStudio ? Appearance.m3colors.m3onPrimaryContainer : Appearance.colors.colText
        }

        StyledToolTip {
            text: bigButton.name
        }
    }
}
