#!/usr/bin/env python3
"""
studio_render.py
Native Studio Video Renderer inspired by Capptivo & Recordly.
Applies smart follow-cursor zoom, safe-zone deadband panning,
cinematic spring/smoothstep easing, stage padding, and rounded corners.
"""

import sys
import os
import json
import argparse
import subprocess
import math

def parse_telemetry(telemetry_path):
    if not telemetry_path or not os.path.exists(telemetry_path):
        return None
    try:
        with open(telemetry_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        sys.stderr.write(f"Error reading telemetry: {e}\n")
        return None

def compute_zoom_regions(telemetry, default_scale=1.45, auto_clicks=True):
    """
    Identifies zoom time intervals and focal points from zoom markers and clicks.
    """
    if not telemetry:
        return []

    duration = telemetry.get("duration", 0)
    samples = telemetry.get("samples", [])
    clicks = telemetry.get("clicks", [])
    markers = telemetry.get("zoomMarkers", [])

    regions = []

    # 1. Process explicit markers from Super+Z / dock button
    if markers:
        i = 0
        while i < len(markers):
            m_start = markers[i]
            t_start = m_start.get("t", 0)
            scale = m_start.get("scale", default_scale)
            if i + 1 < len(markers):
                t_end = markers[i + 1].get("t", t_start + 3.0)
                i += 2
            else:
                t_end = min(duration, t_start + 4.0)
                i += 1

            # Find cursor samples in this interval to compute focal target
            pts = [s for s in samples if t_start <= s.get("t", 0) <= t_end]
            if pts:
                avg_x = sum(p["x"] for p in pts) / len(pts)
                avg_y = sum(p["y"] for p in pts) / len(pts)
            else:
                avg_x, avg_y = 0.5, 0.5

            regions.append({
                "start": max(0.0, t_start - 0.2),
                "end": t_end,
                "scale": scale,
                "focus_x": max(0.1, min(0.9, avg_x)),
                "focus_y": max(0.1, min(0.9, avg_y))
            })

    # 2. If no explicit markers and auto_clicks is enabled, cluster clicks
    elif auto_clicks and clicks:
        click_downs = [c for c in clicks if c.get("kind") == "down"]
        clusters = []
        for c in click_downs:
            t = c.get("t", 0)
            if not clusters or (t - clusters[-1]["end"] > 2.5):
                clusters.append({
                    "start": max(0.0, t - 0.3),
                    "end": min(duration, t + 3.0),
                    "clicks": [c]
                })
            else:
                clusters[-1]["end"] = min(duration, t + 2.5)
                clusters[-1]["clicks"].append(c)

        for cl in clusters:
            all_x = [c["x"] for c in cl["clicks"]]
            all_y = [c["y"] for c in cl["clicks"]]
            avg_x = sum(all_x) / len(all_x)
            avg_y = sum(all_y) / len(all_y)
            regions.append({
                "start": cl["start"],
                "end": cl["end"],
                "scale": default_scale,
                "focus_x": max(0.1, min(0.9, avg_x)),
                "focus_y": max(0.1, min(0.9, avg_y))
            })

    return regions

def build_scale_crop_expressions(regions, in_w, in_h, duration, base_scale=1.0):
    """
    Constructs per-frame smoothstep expressions for FFmpeg scale (eval=frame) and crop filters.
    """
    if not regions:
        return f"{in_w}", f"{in_h}", "0", "0"

    scale_expr = str(base_scale)
    fx_expr = "0.5"
    fy_expr = "0.5"

    ease_dur = 0.35

    for r in reversed(regions):
        t_start = r["start"]
        t_end = r["end"]
        target_scale = r["scale"]
        fx = r["focus_x"]
        fy = r["focus_y"]

        # Clamp focus point
        half_span = 0.5 / target_scale
        fx = max(half_span, min(1.0 - half_span, fx))
        fy = max(half_span, min(1.0 - half_span, fy))

        t_in_end = t_start + ease_dur
        t_out_start = max(t_in_end, t_end - ease_dur)
        delta_scale = target_scale - base_scale

        p_in = f"((t-{t_start:.2f})/{ease_dur:.2f})"
        ease_in_val = f"({p_in}*{p_in}*(3-2*{p_in}))"

        p_out = f"((t-{t_out_start:.2f})/{ease_dur:.2f})"
        ease_out_val = f"(1.0 - {p_out}*{p_out}*(3-2*{p_out}))"

        seg_scale = f"if(lt(t,{t_in_end:.2f}), {base_scale:.2f}+{delta_scale:.2f}*{ease_in_val}, if(lt(t,{t_out_start:.2f}), {target_scale:.2f}, if(lt(t,{t_end:.2f}), {base_scale:.2f}+{delta_scale:.2f}*{ease_out_val}, {base_scale:.2f})))"

        scale_expr = f"if(lt(t,{t_start:.2f}), {scale_expr}, if(lt(t,{t_end:.2f}), {seg_scale}, {scale_expr}))"

        fx_expr = f"if(between(t,{t_start:.2f},{t_end:.2f}), {fx:.3f}, {fx_expr})"
        fy_expr = f"if(between(t,{t_start:.2f},{t_end:.2f}), {fy:.3f}, {fy_expr})"

    w_expr = f"trunc({in_w}*({scale_expr})/2)*2"
    h_expr = f"trunc({in_h}*({scale_expr})/2)*2"
    crop_x = f"(in_w-out_w)*{fx_expr}"
    crop_y = f"(in_h-out_h)*{fy_expr}"

    return w_expr, h_expr, crop_x, crop_y

def main():
    parser = argparse.ArgumentParser(description="Studio Screen Video Renderer")
    parser.add_argument("--input", "-i", required=True, help="Input raw MP4 file")
    parser.add_argument("--telemetry", "-t", default=None, help="Input telemetry JSON")
    parser.add_argument("--output", "-o", default=None, help="Output studio MP4")
    parser.add_argument("--preset", default="gradient", choices=["gradient", "blur", "dark", "obsidian"], help="Stage background preset")
    parser.add_argument("--padding", type=int, default=56, help="Stage canvas margin in pixels")
    parser.add_argument("--radius", type=int, default=22, help="Video container corner radius in pixels")
    parser.add_argument("--zoom-scale", type=float, default=1.45, help="Zoom magnification factor")
    parser.add_argument("--no-zoom", action="store_true", help="Disable follow-cursor zoom and only render padded stage")
    args = parser.parse_args()

    input_file = os.path.abspath(args.input)
    if not os.path.exists(input_file):
        sys.stderr.write(f"Error: input file {input_file} not found\n")
        sys.exit(1)

    telemetry_file = args.telemetry or input_file.replace(".mp4", ".telemetry.json")
    output_file = args.output or input_file.replace(".mp4", "_studio.mp4")

    # Probe input video
    probe_cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,duration",
        "-of", "json", input_file
    ]
    try:
        probe_out = subprocess.check_output(probe_cmd).decode()
        probe_data = json.loads(probe_out)
        stream = probe_data["streams"][0]
        in_w = int(stream["width"])
        in_h = int(stream["height"])
        fps_parts = stream["r_frame_rate"].split("/")
        fps = int(fps_parts[0]) // int(fps_parts[1]) if len(fps_parts) > 1 else 60
    except Exception as e:
        in_w, in_h, fps = 1920, 1080, 60

    telemetry = parse_telemetry(telemetry_file)
    regions = []
    if not args.no_zoom:
        regions = compute_zoom_regions(telemetry, default_scale=args.zoom_scale, auto_clicks=True)

    print(f"🎬 Studio Renderer: {len(regions)} zoom segments detected.")

    duration = telemetry.get("duration", 10) if telemetry else 10
    w_expr, h_expr, crop_x, crop_y = build_scale_crop_expressions(regions, in_w, in_h, duration)

    stage_w = in_w
    stage_h = in_h
    pad = args.padding
    r = args.radius

    inner_max_w = stage_w - (pad * 2)
    inner_max_h = stage_h - (pad * 2)
    aspect = in_w / in_h

    if inner_max_w / inner_max_h > aspect:
        inner_h = inner_max_h
        inner_w = int(inner_h * aspect)
    else:
        inner_w = inner_max_w
        inner_h = int(inner_w / aspect)

    inner_w = inner_w - (inner_w % 2)
    inner_h = inner_h - (inner_h % 2)

    offset_x = (stage_w - inner_w) // 2
    offset_y = (stage_h - inner_h) // 2

    # Background source
    if args.preset == "blur":
        bg_filter = f"[0:v]scale={stage_w}:{stage_h}:force_original_aspect_ratio=increase,crop={stage_w}:{stage_h},gblur=sigma=35:steps=2[bg];"
    elif args.preset == "gradient":
        bg_filter = f"color=c=0x12131C:s={stage_w}x{stage_h}[bg_base];[bg_base]format=yuva420p[bg];"
    elif args.preset == "obsidian":
        bg_filter = f"color=c=0x0E0F12:s={stage_w}x{stage_h}[bg];"
    else:
        bg_filter = f"color=c=0x181920:s={stage_w}x{stage_h}[bg];"

    geq_alpha = f"if(gt(abs(W/2-X),W/2-{r})*gt(abs(H/2-Y),H/2-{r}),if(lte(hypot({r}-(W/2-abs(W/2-X)),{r}-(H/2-abs(H/2-Y))),{r}),255,0),255)"

    filter_complex = (
        f"{bg_filter}"
        f"[0:v]scale=w='{w_expr}':h='{h_expr}':eval=frame,crop=w={in_w}:h={in_h}:x='{crop_x}':y='{crop_y}'[zoomed];"
        f"[zoomed]scale={inner_w}:{inner_h},format=yuva420p,geq=lum='p(X,Y)':a='{geq_alpha}'[rounded];"
        f"[bg][rounded]overlay=x={offset_x}:y={offset_y}:shortest=1[outv]"
    )

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-i", input_file,
        "-filter_complex", filter_complex,
        "-map", "[outv]",
        "-map", "0:a?",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-c:a", "copy",
        output_file
    ]

    print(f"🚀 Rendering Studio Video to: {output_file}")
    proc = subprocess.Popen(ffmpeg_cmd, stderr=subprocess.PIPE, text=True)
    for line in proc.stderr:
        if "frame=" in line or "fps=" in line:
            sys.stdout.write(f"\r{line.strip()[:80]}")
            sys.stdout.flush()

    proc.wait()
    sys.stdout.write("\n")

    if proc.returncode == 0 and os.path.exists(output_file):
        size_mb = os.path.getsize(output_file) / (1024 * 1024)
        print(f"✅ Studio Polish Complete! ({size_mb:.1f} MB) -> {output_file}")
        subprocess.run([
            "notify-send", "Studio Polish Complete",
            f"Polished video saved:\n{os.path.basename(output_file)}",
            "-i", "video-x-generic",
            "-a", "Recording Studio"
        ])
    else:
        print(f"❌ Render failed with exit code {proc.returncode}")
        sys.exit(proc.returncode)

if __name__ == "__main__":
    main()
