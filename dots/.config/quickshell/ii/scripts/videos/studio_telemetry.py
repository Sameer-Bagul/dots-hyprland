#!/usr/bin/env python3
"""
studio_telemetry.py
High-frequency cursor and interaction telemetry logger for Studio Screen Recorder.
Logs cursor trajectory, click coordinates, and hotkey zoom markers at ~60 Hz.
Inspired by Capptivo (cursor.json) and Recordly.
"""

import sys
import os
import time
import json
import signal
import socket
import select
import struct
import glob
import subprocess
import threading

running = True

def handle_signal(sig, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)

def get_monitor_geometry(target_name=None):
    try:
        out = subprocess.check_output(["hyprctl", "monitors", "-j"], stderr=subprocess.DEVNULL)
        monitors = json.loads(out)
        if target_name:
            for m in monitors:
                if m.get("name") == target_name:
                    return m["x"], m["y"], m["width"], m["height"]
        # Default to focused
        for m in monitors:
            if m.get("focused"):
                return m["x"], m["y"], m["width"], m["height"]
        if monitors:
            m = monitors[0]
            return m["x"], m["y"], m["width"], m["height"]
    except Exception as e:
        sys.stderr.write(f"Failed to query hyprctl monitors: {e}\n")
    return 0, 0, 1920, 1080

def get_cursor_pos():
    try:
        out = subprocess.check_output(["hyprctl", "cursorpos"], stderr=subprocess.DEVNULL).decode().strip()
        parts = out.split(",")
        return float(parts[0].strip()), float(parts[1].strip())
    except:
        return None, None

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Studio Recorder Telemetry Logger")
    parser.add_argument("--output", "-o", required=True, help="Output JSON path")
    parser.add_argument("--monitor", "-m", default=None, help="Target monitor name")
    parser.add_argument("--geometry", "-g", default=None, help="Capture geometry X,Y WxH for region recording")
    parser.add_argument("--watch-pid", "-p", type=int, default=None, help="Watch recorder PID and exit when it stops")
    parser.add_argument("--sock", default="/tmp/studio_telemetry.sock", help="Unix socket path for zoom markers")
    args = parser.parse_args()

    if args.geometry:
        try:
            parts = args.geometry.strip().split()
            gx, gy = [float(v) for v in parts[0].split(",")]
            gw, gh = [float(v) for v in parts[1].split("x")]
            mx, my, mw, mh = gx, gy, gw, gh
        except Exception as e:
            sys.stderr.write(f"Failed to parse geometry '{args.geometry}': {e}\n")
            mx, my, mw, mh = get_monitor_geometry(args.monitor)
    else:
        mx, my, mw, mh = get_monitor_geometry(args.monitor)

    t0 = time.time()

    samples = []
    clicks = []
    zoom_markers = []

    # Prepare Unix socket for external IPC triggers (e.g. Super+Z zoom markers)
    if os.path.exists(args.sock):
        try:
            os.remove(args.sock)
        except:
            pass

    ipc_server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        ipc_server.bind(args.sock)
        ipc_server.setblocking(False)
    except Exception as e:
        sys.stderr.write(f"IPC bind error: {e}\n")
        ipc_server = None

    # Open mouse input devices for click tracking
    input_fds = []
    for dev in glob.glob("/dev/input/event*"):
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
            input_fds.append(fd)
        except:
            pass

    EV_KEY = 1
    BTN_LEFT = 272
    BTN_RIGHT = 273
    BTN_MIDDLE = 274

    last_x, last_y = -1, -1
    last_sample_time = 0

    try:
        while running:
            now = time.time()
            elapsed = round(now - t0, 4)

            # Check watch PID
            if args.watch_pid and (now - last_sample_time >= 0.5):
                try:
                    os.kill(args.watch_pid, 0)
                except OSError:
                    break

            # 1. Check IPC socket for zoom markers
            if ipc_server:
                try:
                    data, _ = ipc_server.recvfrom(1024)
                    msg = data.decode().strip()
                    if msg.startswith("ZOOM_TOGGLE"):
                        parts = msg.split()
                        scale = float(parts[1]) if len(parts) > 1 else 1.5
                        zoom_markers.append({
                            "t": elapsed,
                            "scale": scale,
                            "event": "toggle"
                        })
                    elif msg == "STOP":
                        break
                except (BlockingIOError, socket.error):
                    pass

            # 2. Check mouse input events for clicks
            if input_fds:
                r, _, _ = select.select(input_fds, [], [], 0)
                for fd in r:
                    try:
                        while True:
                            buf = os.read(fd, 24)
                            if len(buf) < 24:
                                break
                            _, _, ev_type, ev_code, ev_val = struct.unpack("qqHHi", buf)
                            if ev_type == EV_KEY and ev_code in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
                                btn_name = "left" if ev_code == BTN_LEFT else ("right" if ev_code == BTN_RIGHT else "middle")
                                kind = "down" if ev_val == 1 else ("up" if ev_val == 0 else "repeat")
                                cx, cy = get_cursor_pos()
                                if cx is not None:
                                    norm_x = max(0.0, min(1.0, (cx - mx) / mw))
                                    norm_y = max(0.0, min(1.0, (cy - my) / mh))
                                    clicks.append({
                                        "t": elapsed,
                                        "x": round(norm_x, 4),
                                        "y": round(norm_y, 4),
                                        "kind": kind,
                                        "btn": btn_name
                                    })
                    except (BlockingIOError, OSError):
                        pass

            # 3. Sample cursor position at ~60 Hz (every 16ms)
            if now - last_sample_time >= 0.016:
                last_sample_time = now
                cx, cy = get_cursor_pos()
                if cx is not None:
                    norm_x = max(0.0, min(1.0, (cx - mx) / mw))
                    norm_y = max(0.0, min(1.0, (cy - my) / mh))
                    # Record sample
                    samples.append({
                        "t": elapsed,
                        "x": round(norm_x, 4),
                        "y": round(norm_y, 4)
                    })

            # Sleep short slice to prevent high CPU burn
            time.sleep(0.005)

    finally:
        for fd in input_fds:
            try:
                os.close(fd)
            except:
                pass
        if ipc_server:
            try:
                ipc_server.close()
                if os.path.exists(args.sock):
                    os.remove(args.sock)
            except:
                pass

        total_duration = round(time.time() - t0, 3)
        doc = {
            "version": 1,
            "duration": total_duration,
            "monitor": {
                "name": args.monitor,
                "x": mx,
                "y": my,
                "width": mw,
                "height": mh
            },
            "sampleCount": len(samples),
            "clickCount": len(clicks),
            "zoomMarkerCount": len(zoom_markers),
            "samples": samples,
            "clicks": clicks,
            "zoomMarkers": zoom_markers
        }

        # Write output
        out_dir = os.path.dirname(os.path.abspath(args.output))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)

        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=2)

if __name__ == "__main__":
    main()
