#!/usr/bin/env bash
# Studio Screen Recorder backend for Quickshell
# Supports wf-recorder, dual audio mixing (Mic + System), framerate, output/geometry, and graceful cleanup

PID_FILE="/tmp/quickshell_studio_record.pid"
STATUS_FILE="/tmp/quickshell_studio_record.json"
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"

CUSTOM_PATH=$(jq -r '.screenRecord.savePath' "$CONFIG_FILE" 2>/dev/null)
RECORDING_DIR="${CUSTOM_PATH:-$HOME/Videos/Recordings}"
mkdir -p "$RECORDING_DIR"

# ----------------- Stop Command -----------------
if [[ "$1" == "--stop" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        REC_PID=$(cat "$PID_FILE")
        if kill -0 "$REC_PID" 2>/dev/null; then
            kill -2 "$REC_PID" 2>/dev/null
            # Wait up to 3 seconds for clean mp4 finalization
            for _ in {1..30}; do
                if ! kill -0 "$REC_PID" 2>/dev/null; then
                    break
                fi
                sleep 0.1
            done
        fi
        rm -f "$PID_FILE"
    fi
    pkill -2 wf-recorder 2>/dev/null
    exit 0
fi

# ----------------- Status Command -----------------
if [[ "$1" == "--status" ]]; then
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        cat "$STATUS_FILE" 2>/dev/null || echo '{"running": true}'
    else
        echo '{"running": false}'
    fi
    exit 0
fi

# ----------------- Parse Arguments -----------------
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
RENDER_ASPECT="16:9"
RENDER_PRESET="gradient"
RENDER_WINDOW_FRAME=0
RENDER_WINDOW_TITLE=""
RENDER_NO_CLICK_RIPPLE=0
RENDER_NO_CLICK_SOUND=0
RENDER_NO_ZOOM=0
RENDER_CAPTIONS=0
RENDER_CAPTIONS_MODEL="tiny.en"
RENDER_GIF=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"; shift 2 ;;
        --output)
            OUTPUT_MONITOR="$2"; shift 2 ;;
        --geometry)
            GEOMETRY="$2"; shift 2 ;;
        --fps)
            FPS="$2"; shift 2 ;;
        --mic)
            USE_MIC="$2"; shift 2 ;;
        --mic-device)
            MIC_SRC="$2"; shift 2 ;;
        --sys)
            USE_SYS="$2"; shift 2 ;;
        --sys-device)
            SYS_SRC="$2"; shift 2 ;;
        --file)
            CUSTOM_FILE="$2"; shift 2 ;;
        --auto-polish)
            AUTO_POLISH="$2"; shift 2 ;;
        --render-aspect)
            RENDER_ASPECT="$2"; shift 2 ;;
        --render-preset)
            RENDER_PRESET="$2"; shift 2 ;;
        --render-window-frame)
            RENDER_WINDOW_FRAME="$2"; shift 2 ;;
        --render-window-title)
            RENDER_WINDOW_TITLE="$2"; shift 2 ;;
        --render-no-click-ripple)
            RENDER_NO_CLICK_RIPPLE="$2"; shift 2 ;;
        --render-no-click-sound)
            RENDER_NO_CLICK_SOUND="$2"; shift 2 ;;
        --render-no-zoom)
            RENDER_NO_ZOOM="$2"; shift 2 ;;
        --render-captions)
            RENDER_CAPTIONS="$2"; shift 2 ;;
        --render-captions-model)
            RENDER_CAPTIONS_MODEL="$2"; shift 2 ;;
        --render-gif)
            RENDER_GIF="$2"; shift 2 ;;
        *)
            shift ;;
    esac
done

# If another studio recording is running, stop it
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    kill -2 "$(cat "$PID_FILE")"
    sleep 0.5
fi

# Determine default audio devices if not specified
if [[ -z "$MIC_SRC" || "$MIC_SRC" == "default" ]]; then
    MIC_SRC=$(pactl get-default-source 2>/dev/null)
fi

if [[ -z "$SYS_SRC" || "$SYS_SRC" == "default" ]]; then
    DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null)
    SYS_SRC="${DEFAULT_SINK}.monitor"
fi

if [[ -z "$OUTPUT_MONITOR" ]]; then
    OUTPUT_MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused == true)) | .name' 2>/dev/null)
    if [[ -z "$OUTPUT_MONITOR" || "$OUTPUT_MONITOR" == "null" ]]; then
        OUTPUT_MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
    fi
fi

# Output file path
TIMESTAMP=$(date '+%Y-%m-%d_%H.%M.%S')
FILENAME="Studio_Recording_${TIMESTAMP}.mp4"
if [[ -n "$CUSTOM_FILE" ]]; then
    TARGET_PATH="$CUSTOM_FILE"
    FILENAME=$(basename "$CUSTOM_FILE")
else
    TARGET_PATH="${RECORDING_DIR}/${FILENAME}"
fi

# ----------------- Audio Mixing Setup -----------------
SINK_MODULE=""
MIC_MODULE=""
SYS_MODULE=""
AUDIO_ARG=""

cleanup_audio() {
    [[ -n "$TELEM_PID" ]] && kill -2 "$TELEM_PID" 2>/dev/null
    [[ -n "$MIC_MODULE" ]] && pactl unload-module "$MIC_MODULE" 2>/dev/null
    [[ -n "$SYS_MODULE" ]] && pactl unload-module "$SYS_MODULE" 2>/dev/null
    [[ -n "$SINK_MODULE" ]] && pactl unload-module "$SINK_MODULE" 2>/dev/null
    rm -f "$PID_FILE" "$STATUS_FILE"
}
trap cleanup_audio EXIT INT TERM

if [[ "$USE_MIC" -eq 1 && "$USE_SYS" -eq 1 ]]; then
    # Dual mix: Create temporary null sink & route both mic and system monitor through it
    MIX_SINK_NAME="studio_mix_$$"
    SINK_MODULE=$(pactl load-module module-null-sink sink_name="$MIX_SINK_NAME" sink_properties=device.description="StudioRecordingMix" 2>/dev/null)
    if [[ -n "$SINK_MODULE" ]]; then
        MIC_MODULE=$(pactl load-module module-loopback source="$MIC_SRC" sink="$MIX_SINK_NAME" latency_msec=20 2>/dev/null)
        SYS_MODULE=$(pactl load-module module-loopback source="$SYS_SRC" sink="$MIX_SINK_NAME" latency_msec=20 2>/dev/null)
        AUDIO_ARG="--audio=${MIX_SINK_NAME}.monitor"
    else
        # Fallback to single mic if loopback creation failed
        AUDIO_ARG="--audio=$MIC_SRC"
    fi
elif [[ "$USE_MIC" -eq 1 ]]; then
    AUDIO_ARG="--audio=$MIC_SRC"
elif [[ "$USE_SYS" -eq 1 ]]; then
    AUDIO_ARG="--audio=$SYS_SRC"
fi

# ----------------- Build wf-recorder Command -----------------
WF_ARGS=("-r" "$FPS" "-x" "yuv420p" "-f" "$TARGET_PATH")

if [[ -n "$AUDIO_ARG" ]]; then
    WF_ARGS+=("$AUDIO_ARG")
fi

if [[ "$MODE" == "region" ]]; then
    if [[ -z "$GEOMETRY" ]]; then
        if ! GEOMETRY=$(slurp 2>/dev/null); then
            notify-send "Studio Recorder" "Area selection was cancelled" -u low -a 'StudioRecorder' &
            exit 1
        fi
    fi
    WF_ARGS+=("-g" "$GEOMETRY")
else
    if [[ -n "$OUTPUT_MONITOR" ]]; then
        WF_ARGS+=("-o" "$OUTPUT_MONITOR")
    fi
fi

# Save status JSON
cat << EOF > "$STATUS_FILE"
{
    "running": true,
    "pid": $$,
    "file": "${TARGET_PATH}",
    "filename": "${FILENAME}",
    "mode": "${MODE}",
    "fps": ${FPS},
    "mic": ${USE_MIC},
    "systemAudio": ${USE_SYS},
    "startedAt": "$(date -Iseconds)"
}
EOF

echo "$$" > "$PID_FILE"

# Launch wf-recorder
wf-recorder "${WF_ARGS[@]}" &
REC_PID=$!
echo "$REC_PID" > "$PID_FILE"

# Launch cursor & interaction telemetry logger
TELEMETRY_PATH="${TARGET_PATH%.mp4}.telemetry.json"
TELEM_ARGS=("--output" "$TELEMETRY_PATH" "--watch-pid" "$REC_PID")
if [[ -n "$GEOMETRY" ]]; then
    TELEM_ARGS+=("--geometry" "$GEOMETRY")
elif [[ -n "$OUTPUT_MONITOR" ]]; then
    TELEM_ARGS+=("--monitor" "$OUTPUT_MONITOR")
fi

python3 "$SCRIPT_DIR/studio_telemetry.py" "${TELEM_ARGS[@]}" &
TELEM_PID=$!

# Wait for recorder to terminate
wait "$REC_PID" 2>/dev/null

if [[ -n "$TELEM_PID" ]]; then
    kill -2 "$TELEM_PID" 2>/dev/null
    wait "$TELEM_PID" 2>/dev/null
fi

# Send completion notification with Studio Polish action
if [[ -f "$TARGET_PATH" && -s "$TARGET_PATH" ]]; then
    FILE_SIZE=$(du -h "$TARGET_PATH" | cut -f1)

    # Build studio_render.py arguments from capture flags
    RENDER_ARGS=("-i" "$TARGET_PATH" "--aspect" "$RENDER_ASPECT" "--preset" "$RENDER_PRESET")
    [[ "$RENDER_WINDOW_FRAME" -eq 1 ]] && RENDER_ARGS+=("--window-frame")
    [[ -n "$RENDER_WINDOW_TITLE" ]] && RENDER_ARGS+=("--window-title" "$RENDER_WINDOW_TITLE")
    [[ "$RENDER_NO_CLICK_RIPPLE" -eq 1 ]] && RENDER_ARGS+=("--no-click-ripple")
    [[ "$RENDER_NO_CLICK_SOUND" -eq 1 ]] && RENDER_ARGS+=("--no-click-sound")
    [[ "$RENDER_NO_ZOOM" -eq 1 ]] && RENDER_ARGS+=("--no-zoom")
    [[ "$RENDER_CAPTIONS" -eq 1 ]] && RENDER_ARGS+=("--captions" "--captions-model" "$RENDER_CAPTIONS_MODEL")
    [[ "$RENDER_GIF" -eq 1 ]] && RENDER_ARGS+=("--gif")

    if [[ "$AUTO_POLISH" -eq 1 ]]; then
        notify-send "Recording Complete" "Applying Studio Polish..." \
            -i "video-x-generic" -a "Recording Studio" 2>/dev/null || true
        python3 "$SCRIPT_DIR/studio_render.py" "${RENDER_ARGS[@]}" &
    else
        ACTION=$(notify-send "Studio Recording Saved" \
            "${FILENAME} (${FILE_SIZE})\nSaved in ${RECORDING_DIR}" \
            -i "video-x-generic" \
            -a "Recording Studio" \
            --action="polish=✨ Apply Studio Polish" \
            --action="open=▶ Open Video" \
            --action="folder=📁 Open Folder" 2>/dev/null || true)

        if [[ "$ACTION" == "polish" ]]; then
            notify-send "Studio Polish" "Rendering polished video..." \
                -i "video-x-generic" -a "Recording Studio" 2>/dev/null || true
            python3 "$SCRIPT_DIR/studio_render.py" "${RENDER_ARGS[@]}" &
        elif [[ "$ACTION" == "open" ]]; then
            xdg-open "$TARGET_PATH" &
        elif [[ "$ACTION" == "folder" ]]; then
            xdg-open "$RECORDING_DIR" &
        fi
    fi
fi
