pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

Scope {
    id: root

    StudioRecorderModal {}
    CameraBubble {}
    StudioRecordingBar {}
    StudioCountdownOverlay {}


    GlobalShortcut {
        name: "studioRecorderOpen"
        description: "Opens Studio Screen Recorder setup"
        onPressed: {
            RecordingStudioService.setupModalOpen = !RecordingStudioService.setupModalOpen;
        }
    }

    GlobalShortcut {
        name: "studioZoomToggle"
        description: "Toggles camera follow-zoom during recording"
        onPressed: RecordingStudioService.toggleZoom()
    }
}

