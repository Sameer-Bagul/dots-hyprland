pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions as CF
import qs.services

/**
 * RecordingStudioService
 * Core coordinator for Studio Screen Recording inspired by Recordly & Capptivo.
 * Handles webcam bubble PiP, dual audio mixing, auto-follow cursor zoom,
 * countdown animation, and floating studio controls.
 */
Singleton {
    id: root

    // ================= State Properties =================
    property bool isRecording: false
    property bool isPaused: false
    property bool setupModalOpen: false
    property bool countdownActive: false
    property int countdownValue: 3
    property int elapsedSeconds: 0
    property string formattedTime: "00:00"
    property string targetFilePath: ""
    property real simulatedAudioLevel: 0.0

    // Capture mode: "fullscreen" (active monitor), "region", "window"
    property string captureMode: "fullscreen"
    property string regionGeometry: ""
    property int fps: 60

    // ================= Face Cam / Webcam Bubble =================
    property bool cameraEnabled: false
    property string cameraShape: "circle" // "circle" or "rectangle"
    property int cameraSizePreset: 1 // 0: Small (160px), 1: Medium (220px), 2: Large (280px)
    readonly property real cameraBaseSize: cameraSizePreset === 0 ? 160 : (cameraSizePreset === 1 ? 220 : 280)
    readonly property real cameraWidth: cameraShape === "circle" ? cameraBaseSize : Math.round(cameraBaseSize * 1.45)
    readonly property real cameraHeight: cameraBaseSize
    property bool cameraMirrored: true
    property real cameraX: 48
    property real cameraY: 80

    // ================= Audio Inputs =================
    property bool micEnabled: true
    property string micDevice: "default"
    property bool systemAudioEnabled: true
    property string systemAudioDevice: "default"

    // ================= Cursor Tracking & Zoom =================
    property bool autoZoomEnabled: false
    property bool zoomActive: false
    property real zoomFactor: 1.35

    // Path to studio_record.sh
    readonly property string studioRecordScriptPath: CF.FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/studio_record.sh`)

    // Timer for recording duration
    Timer {
        id: recordingTimer
        interval: 1000
        repeat: true
        running: root.isRecording && !root.isPaused
        onTriggered: {
            root.elapsedSeconds++;
            let mins = Math.floor(root.elapsedSeconds / 60);
            let secs = root.elapsedSeconds % 60;
            let mStr = mins < 10 ? "0" + mins : String(mins);
            let sStr = secs < 10 ? "0" + secs : String(secs);
            root.formattedTime = `${mStr}:${sStr}`;
        }
    }

    // Timer for 3-second animated countdown
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: root.countdownActive
        onTriggered: {
            if (root.countdownValue > 1) {
                root.countdownValue--;
            } else {
                root.countdownValue = 0;
                root.countdownActive = false;
                root.launchRecorderProcess();
            }
        }
    }

    // Dynamic audio level simulation for live recording bar VU meter
    Timer {
        id: vuMeterTimer
        interval: 90
        repeat: true
        running: root.isRecording && root.micEnabled && !root.isPaused
        onTriggered: {
            let base = (Audio.source && !Audio.source.audio.muted) ? Audio.source.audio.volume : 0.6;
            let wave = Math.random() * 0.45 + 0.15;
            root.simulatedAudioLevel = Math.min(1.0, base * wave);
        }
    }

    // ================= Action Methods =================

    function openStudioSetup(mode) {
        if (mode !== undefined && mode.length > 0) {
            root.captureMode = mode;
        }
        root.setupModalOpen = true;
    }

    function closeStudioSetup() {
        root.setupModalOpen = false;
    }

    // Start with countdown
    function startRecordingWithCountdown() {
        root.setupModalOpen = false;
        root.countdownValue = 3;
        root.countdownActive = true;
    }

    // Internal launch once countdown finishes
    function launchRecorderProcess() {
        root.elapsedSeconds = 0;
        root.formattedTime = "00:00";
        root.isRecording = true;
        root.isPaused = false;

        let args = [
            root.studioRecordScriptPath,
            "--mode", root.captureMode,
            "--fps", String(root.fps),
            "--mic", root.micEnabled ? "1" : "0",
            "--sys", root.systemAudioEnabled ? "1" : "0"
        ];

        if (root.captureMode === "region" && root.regionGeometry.length > 0) {
            args.push("--geometry", root.regionGeometry);
        }

        if (root.micEnabled && root.micDevice !== "default") {
            args.push("--mic-device", root.micDevice);
        }

        if (root.systemAudioEnabled && root.systemAudioDevice !== "default") {
            args.push("--sys-device", root.systemAudioDevice);
        }

        // Execute recorder in background
        Quickshell.execDetached(args);

        // If Auto-Zoom is enabled at start, gently activate cursor follow zoom
        if (root.autoZoomEnabled) {
            root.setZoom(true);
        }
    }

    // Stop and finalize MP4
    function stopRecording() {
        if (!root.isRecording) return;
        root.isRecording = false;
        root.isPaused = false;
        root.countdownActive = false;
        recordingTimer.stop();

        // Always reset zoom to 1.0 when recording stops
        if (root.zoomActive) {
            root.setZoom(false);
        }

        Quickshell.execDetached([root.studioRecordScriptPath, "--stop"]);
    }

    // Cancel and discard recording
    function cancelRecording() {
        if (!root.isRecording && !root.countdownActive) return;
        root.isRecording = false;
        root.isPaused = false;
        root.countdownActive = false;
        recordingTimer.stop();

        if (root.zoomActive) {
            root.setZoom(false);
        }

        Quickshell.execDetached([root.studioRecordScriptPath, "--stop"]);
    }

    // Pause / Resume
    function togglePause() {
        if (!root.isRecording) return;
        root.isPaused = !root.isPaused;
        // In wf-recorder, SIGUSR1 toggles pause/resume
        Quickshell.execDetached(["bash", "-c", "pkill -SIGUSR1 wf-recorder 2>/dev/null || true"]);
    }

    // ================= Auto Cursor Tracking & Zoom =================

    function setZoom(active) {
        root.zoomActive = active;
        const factor = active ? String(root.zoomFactor) : "1.0";
        const rigid = active ? "false" : "true";
        const cmd = `hyprctl eval "hl.config({ cursor = { zoom_factor = ${factor}, zoom_rigid = ${rigid} } })" 2>/dev/null || (hyprctl keyword cursor:zoom_rigid ${rigid} 2>/dev/null && hyprctl keyword cursor:zoom_factor ${factor} 2>/dev/null) || true`;
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function toggleZoom() {
        root.setZoom(!root.zoomActive);
    }

    // ================= Camera Bubble Controls =================

    function toggleCamera() {
        root.cameraEnabled = !root.cameraEnabled;
    }

    function cycleCameraShape() {
        root.cameraShape = (root.cameraShape === "circle") ? "rectangle" : "circle";
    }

    function cycleCameraSize() {
        root.cameraSizePreset = (root.cameraSizePreset + 1) % 3;
    }

    function toggleCameraMirror() {
        root.cameraMirrored = !root.cameraMirrored;
    }

    // IPC handler for external triggers
    IpcHandler {
        target: "studio"

        function open() {
            root.openStudioSetup();
        }
        function close() {
            root.closeStudioSetup();
        }
        function toggle() {
            root.setupModalOpen = !root.setupModalOpen;
        }
        function start() {
            root.startRecordingWithCountdown();
        }
        function stop() {
            root.stopRecording();
        }
        function toggleZoom() {
            root.toggleZoom();
        }
        function toggleCamera() {
            root.toggleCamera();
        }
    }
}
