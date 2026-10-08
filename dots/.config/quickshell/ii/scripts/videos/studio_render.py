#!/usr/bin/env python3
"""
studio_render.py
Native Studio Video Renderer inspired by Capptivo & Recordly.
Applies smart follow-cursor zoom, safe-zone deadband panning,
cinematic spring/smoothstep easing, stage padding, rounded corners,
click ripple animations, audio click sounds, window mockup frame,
aspect ratio presets (16:9 / 9:16 / 1:1), and on-device Whisper captions.
"""

import sys
import os
import json
import argparse
import subprocess
import math
import struct
import wave
import tempfile

# ─────────────────────────────────────────────────────────────────────────────
# TELEMETRY PARSING
# ─────────────────────────────────────────────────────────────────────────────

def parse_telemetry(telemetry_path):
    if not telemetry_path or not os.path.exists(telemetry_path):
        return None
    try:
        with open(telemetry_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        sys.stderr.write(f"Error reading telemetry: {e}\n")
        return None

# ─────────────────────────────────────────────────────────────────────────────
# ZOOM REGION COMPUTATION (Capptivo Safe-Zone Deadband)
# ─────────────────────────────────────────────────────────────────────────────

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

        seg_scale = (
            f"if(lt(t,{t_in_end:.2f}), {base_scale:.2f}+{delta_scale:.2f}*{ease_in_val},"
            f" if(lt(t,{t_out_start:.2f}), {target_scale:.2f},"
            f" if(lt(t,{t_end:.2f}), {base_scale:.2f}+{delta_scale:.2f}*{ease_out_val}, {base_scale:.2f})))"
        )
        scale_expr = f"if(lt(t,{t_start:.2f}), {scale_expr}, if(lt(t,{t_end:.2f}), {seg_scale}, {scale_expr}))"
        fx_expr = f"if(between(t,{t_start:.2f},{t_end:.2f}), {fx:.3f}, {fx_expr})"
        fy_expr = f"if(between(t,{t_start:.2f},{t_end:.2f}), {fy:.3f}, {fy_expr})"

    w_expr = f"trunc({in_w}*({scale_expr})/2)*2"
    h_expr = f"trunc({in_h}*({scale_expr})/2)*2"
    crop_x = f"(in_w-out_w)*{fx_expr}"
    crop_y = f"(in_h-out_h)*{fy_expr}"

    return w_expr, h_expr, crop_x, crop_y

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1A: CLICK RIPPLE OVERLAY (FFmpeg drawbox-based pulse rings)
# ─────────────────────────────────────────────────────────────────────────────

def build_click_ripple_filter(clicks, inner_w, inner_h, offset_x, offset_y, aspect_ratio="16:9"):
    """
    Generates FFmpeg drawellipse filter expressions for click ripple animations.
    Each left-click creates two expanding translucent rings that fade out over 0.35s.
    """
    if not clicks:
        return ""

    click_downs = [c for c in clicks if c.get("kind") == "down" and c.get("btn") == "left"]
    if not click_downs:
        return ""

    filters = []
    for click in click_downs:
        t0 = click.get("t", 0)
        cx_norm = click.get("x", 0.5)
        cy_norm = click.get("y", 0.5)

        # Map normalized coordinates onto the inner canvas area
        cx = int(offset_x + cx_norm * inner_w)
        cy = int(offset_y + cy_norm * inner_h)

        # Ring 1: inner ripple (fast, 0–0.25s)
        t_dur1 = 0.25
        r1_start = f"(t-{t0:.3f})"
        progress1 = f"(({r1_start})/{t_dur1})"
        alpha1 = f"if(between(t,{t0:.3f},{t0+t_dur1:.3f}), {int(0.7*255)}*(1-{progress1}), 0)"
        r1 = f"if(between(t,{t0:.3f},{t0+t_dur1:.3f}), {8}+{26}*{progress1}, 0)"
        filters.append(
            f"drawellipse=x={cx}:y={cy}:w=2*{r1}:h=2*{r1}:color=0xCBA6F7@0.6:t=2:enable='between(t,{t0:.3f},{t0+t_dur1:.3f})'"
        )

        # Ring 2: outer ripple (slower, 0–0.4s)
        t_dur2 = 0.40
        progress2 = f"((t-{t0:.3f})/{t_dur2})"
        r2 = f"if(between(t,{t0:.3f},{t0+t_dur2:.3f}), {14}+{36}*{progress2}, 0)"
        filters.append(
            f"drawellipse=x={cx}:y={cy}:w=2*{r2}:h=2*{r2}:color=0xA6E3A1@0.35:t=2:enable='between(t,{t0:.3f},{t0+t_dur2:.3f})'"
        )

    if not filters:
        return ""
    return "," + ",".join(filters)

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1B: CLICK SOUND EFFECTS (synthetic tactile click WAV)
# ─────────────────────────────────────────────────────────────────────────────

def generate_click_sound_wav(output_path, sample_rate=44100):
    """
    Synthesizes a crisp mechanical key-click impulse:
    y(t) = sin(2π·2800·t) * exp(-t/0.004), 15ms long.
    """
    duration_ms = 15
    num_samples = int(sample_rate * duration_ms / 1000)
    amplitude = 22000

    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        freq = 2800.0
        decay = math.exp(-t / 0.004)
        val = int(amplitude * math.sin(2 * math.pi * freq * t) * decay)
        val = max(-32768, min(32767, val))
        samples.append(val)

    with wave.open(output_path, 'w') as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        for s in samples:
            wf.writeframes(struct.pack('<hh', s, s))

    return output_path

def build_click_audio_filter(clicks, audio_input_idx, click_wav_path):
    """
    Builds FFmpeg audio filter chain that mixes click sounds at click timestamps.
    Uses adelay to position each click WAV at the correct timestamp.
    Returns filter string and inputs list.
    """
    if not clicks or not os.path.exists(click_wav_path):
        return "", []

    click_downs = [c for c in clicks if c.get("kind") == "down" and c.get("btn") == "left"]
    if not click_downs:
        return "", []

    extra_inputs = []
    delays = []
    for i, click in enumerate(click_downs):
        t_ms = int(click.get("t", 0) * 1000)
        delays.append(t_ms)
        extra_inputs.append(click_wav_path)

    if not extra_inputs:
        return "", []

    # Build amix chain
    n_clicks = len(delays)
    idx_start = audio_input_idx + 1  # The video is input 0, audio is stream 0:a

    mix_parts = []
    for i, d in enumerate(delays):
        label = f"[cs{i}]"
        mix_parts.append(f"[{idx_start + i}:a]adelay={d}|{d},volume=0.45{label}")

    mix_inputs = "".join(f"[cs{i}]" for i in range(n_clicks))
    if audio_input_idx >= 0:
        amix = f"[0:a]{mix_inputs}amix=inputs={n_clicks + 1}:normalize=0,volume=1.0[aout]"
    else:
        amix = f"{mix_inputs}amix=inputs={n_clicks}:normalize=0,volume=1.0[aout]"

    full_audio_filter = ";\n".join(mix_parts) + ";\n" + amix

    return full_audio_filter, extra_inputs

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2A: WINDOW MOCKUP FRAME (macOS traffic-light header)
# ─────────────────────────────────────────────────────────────────────────────

def build_window_frame_filter(inner_w, inner_h, title_text=""):
    """
    Generates FFmpeg drawbox + drawellipse + drawtext filters for a macOS-style
    window header (38px, traffic light buttons, optional centered title pill).
    Returns a filter string to append AFTER the rounded video is ready.
    """
    header_h = 38
    header_bg = "0x1A1B26"
    dot_y = inner_h - (inner_h - header_h) // 2 - header_h // 2 + (inner_h - header_h)

    # Traffic light dots at top left of inner frame
    dot_r = 6
    dot_y_pos = 19  # center vertically in 38px header
    red_x = 16 + dot_r
    yel_x = red_x + dot_r * 2 + 8
    grn_x = yel_x + dot_r * 2 + 8

    # We'll render the header bar over the top of the video using drawbox/drawellipse
    # at overlay time. This requires the video to already be rendered.
    filters = [
        # Header background bar
        f"drawbox=x=0:y=0:w=iw:h={header_h}:color={header_bg}@0.88:t=fill",
        # Separator line
        f"drawbox=x=0:y={header_h}:w=iw:h=1:color=0xFFFFFF@0.08:t=fill",
        # Red close dot
        f"drawellipse=x={red_x}:y={dot_y_pos}:w={dot_r*2}:h={dot_r*2}:color=0xFF5F56@1.0:t=fill",
        # Yellow minimise dot
        f"drawellipse=x={yel_x}:y={dot_y_pos}:w={dot_r*2}:h={dot_r*2}:color=0xFFBD2E@1.0:t=fill",
        # Green maximise dot
        f"drawellipse=x={grn_x}:y={dot_y_pos}:w={dot_r*2}:h={dot_r*2}:color=0x27C93F@1.0:t=fill",
    ]

    if title_text:
        pill_w = min(len(title_text) * 8 + 24, 280)
        pill_x = (inner_w - pill_w) // 2
        filters.append(
            f"drawbox=x={pill_x}:y=7:w={pill_w}:h=24:color=0xFFFFFF@0.08:t=fill:r=12"
        )
        filters.append(
            f"drawtext=text='{title_text}':fontsize=11:fontcolor=white@0.6:x=(iw-tw)/2:y=14"
        )

    return "," + ",".join(filters)

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2B: GIF EXPORT ENGINE (2-pass palette + Lanczos + Bayer dithering)
# ─────────────────────────────────────────────────────────────────────────────

def export_gif(input_file, output_file, fps=24, scale_w=960, t_start=None, t_end=None):
    """
    High-quality GIF export with two-pass palette generation.
    """
    tmpdir = tempfile.mkdtemp()
    palette_path = os.path.join(tmpdir, "palette.png")

    trim_args = []
    if t_start is not None:
        trim_args += ["-ss", str(t_start)]
    if t_end is not None:
        trim_args += ["-to", str(t_end)]

    vf_pass1 = f"fps={fps},scale={scale_w}:-1:flags=lanczos,palettegen=stats_mode=diff"
    vf_pass2 = f"fps={fps},scale={scale_w}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3"

    cmd1 = ["ffmpeg", "-y"] + trim_args + ["-i", input_file, "-vf", vf_pass1, palette_path]
    cmd2 = ["ffmpeg", "-y"] + trim_args + ["-i", input_file, "-i", palette_path, "-lavfi", vf_pass2, output_file]

    print(f"🎨 GIF Pass 1: Generating palette...")
    subprocess.run(cmd1, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"🎬 GIF Pass 2: Encoding with Bayer dithering...")
    subprocess.run(cmd2, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    import shutil
    shutil.rmtree(tmpdir, ignore_errors=True)
    size_mb = os.path.getsize(output_file) / (1024 * 1024)
    print(f"✅ GIF exported ({size_mb:.1f} MB) → {output_file}")

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: WHISPER CAPTIONS (ASS subtitle generation)
# ─────────────────────────────────────────────────────────────────────────────

def generate_whisper_captions(input_video, output_ass, model="tiny.en"):
    """
    Extracts audio from video and runs Whisper to generate ASS captions.
    Tries whisper-cli (whisper.cpp) first, then python-openai-whisper.
    Returns path to .ass file on success, None on failure.
    """
    tmpdir = tempfile.mkdtemp()
    audio_path = os.path.join(tmpdir, "audio.wav")

    # Extract audio
    print("🎙️  Extracting audio for Whisper transcription...")
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", input_video, "-vn", "-ar", "16000", "-ac", "1", "-f", "wav", audio_path],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception as e:
        sys.stderr.write(f"Audio extraction failed: {e}\n")
        return None

    # Try whisper-cli (whisper.cpp - faster, lighter)
    whisper_cli = subprocess.run(["which", "whisper-cli"], capture_output=True).stdout.strip().decode()
    if whisper_cli:
        srt_out = os.path.join(tmpdir, "captions.srt")
        model_path = os.path.expanduser(f"~/.local/share/whisper-models/ggml-{model}.bin")
        if not os.path.exists(model_path):
            # Try default locations
            for candidate in [
                f"/usr/share/whisper/{model}.bin",
                os.path.expanduser(f"~/.cache/whisper/{model}.bin"),
            ]:
                if os.path.exists(candidate):
                    model_path = candidate
                    break

        if os.path.exists(model_path):
            print(f"🤖 Transcribing with whisper-cli (model: {model})...")
            result = subprocess.run(
                [whisper_cli, "-m", model_path, "-f", audio_path, "--output-srt", "--output-file",
                 os.path.join(tmpdir, "captions")],
                capture_output=True, text=True
            )
            if os.path.exists(srt_out):
                return _srt_to_ass(srt_out, output_ass)
        else:
            sys.stderr.write(f"⚠️  Whisper model not found at {model_path}. Skipping captions.\n")
            sys.stderr.write(f"   Install: yay -S whisper-cpp && whisper-cli --download-model {model}\n")

    # Try python-openai-whisper
    try:
        import whisper as openai_whisper
        print(f"🤖 Transcribing with openai-whisper (model: {model})...")
        m = openai_whisper.load_model(model.replace(".en", "") if ".en" in model else model)
        result = m.transcribe(audio_path, language="en", word_timestamps=True)
        return _whisper_result_to_ass(result, output_ass)
    except ImportError:
        sys.stderr.write("⚠️  Whisper not installed. Captions skipped.\n")
        sys.stderr.write("   Install: sudo pacman -S python-openai-whisper  OR  sudo pacman -S whisper-cpp\n")
        return None
    except Exception as e:
        sys.stderr.write(f"⚠️  Whisper transcription failed: {e}\n")
        return None
    finally:
        import shutil
        shutil.rmtree(tmpdir, ignore_errors=True)

def _srt_to_ass(srt_path, ass_path):
    """Convert SRT to styled ASS subtitle file."""
    ass_header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 1

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Outfit,30,&H00FFFFFF,&H000000FF,&H00CBA6F7,&H88121318,-1,0,0,0,100,100,0,0,3,2.5,0,2,40,40,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    import re

    def srt_time_to_ass(t):
        t = t.replace(",", ".")
        h, m, rest = t.split(":")
        s, ms = rest.split(".")
        ms_int = int(ms.ljust(3, '0')[:3])
        return f"{int(h)}:{int(m):02d}:{int(s):02d}.{ms_int // 10:02d}"

    events = []
    with open(srt_path, "r", encoding="utf-8") as f:
        blocks = f.read().strip().split("\n\n")

    for block in blocks:
        lines = block.strip().split("\n")
        if len(lines) < 3:
            continue
        times = lines[1].split(" --> ")
        if len(times) != 2:
            continue
        start_t = srt_time_to_ass(times[0].strip())
        end_t = srt_time_to_ass(times[1].strip())
        text = " ".join(lines[2:]).strip()
        text = re.sub(r"<[^>]+>", "", text)
        events.append(f"Dialogue: 0,{start_t},{end_t},Default,,0,0,0,,{{\\an2}}{text}")

    with open(ass_path, "w", encoding="utf-8") as f:
        f.write(ass_header + "\n".join(events) + "\n")

    return ass_path

def _whisper_result_to_ass(result, ass_path):
    """Convert openai-whisper result dict to styled ASS file."""
    ass_header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 1

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Outfit,30,&H00FFFFFF,&H000000FF,&H00CBA6F7,&H88121318,-1,0,0,0,100,100,0,0,3,2.5,0,2,40,40,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    def sec_to_ass(sec):
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int((sec % 1) * 100)
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    events = []
    for seg in result.get("segments", []):
        start_t = sec_to_ass(seg["start"])
        end_t = sec_to_ass(seg["end"])
        text = seg["text"].strip()
        if text:
            events.append(f"Dialogue: 0,{start_t},{end_t},Default,,0,0,0,,{{\\an2}}{text}")

    with open(ass_path, "w", encoding="utf-8") as f:
        f.write(ass_header + "\n".join(events) + "\n")

    return ass_path

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RENDERER
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Studio Screen Video Renderer — Capptivo/Recordly-grade output on Arch Linux")
    parser.add_argument("--input", "-i", required=True, help="Input raw MP4 file")
    parser.add_argument("--telemetry", "-t", default=None, help="Input telemetry JSON")
    parser.add_argument("--output", "-o", default=None, help="Output studio MP4")

    # Stage & look
    parser.add_argument("--preset", default="gradient",
                        choices=["gradient", "blur", "dark", "obsidian"],
                        help="Stage background preset")
    parser.add_argument("--padding", type=int, default=56, help="Stage canvas margin in pixels")
    parser.add_argument("--radius", type=int, default=22, help="Video container corner radius in pixels")

    # Zoom
    parser.add_argument("--zoom-scale", type=float, default=1.45, help="Zoom magnification factor")
    parser.add_argument("--no-zoom", action="store_true", help="Disable follow-cursor zoom")

    # Phase 1: Click effects
    parser.add_argument("--click-ripple", action="store_true", default=True,
                        help="Overlay animated click ripple rings (default: on)")
    parser.add_argument("--no-click-ripple", dest="click_ripple", action="store_false",
                        help="Disable click ripple rings")
    parser.add_argument("--click-sound", action="store_true", default=True,
                        help="Mix synthetic click sounds into audio (default: on)")
    parser.add_argument("--no-click-sound", dest="click_sound", action="store_false",
                        help="Disable click sounds")

    # Phase 2: Window frame & aspect ratio
    parser.add_argument("--window-frame", action="store_true", default=False,
                        help="Add macOS-style window mockup header (traffic lights)")
    parser.add_argument("--window-title", default="", help="Optional title text in window header pill")
    parser.add_argument("--aspect", default="16:9",
                        choices=["16:9", "9:16", "1:1", "4:3"],
                        help="Output aspect ratio preset (default: 16:9)")

    # Phase 3: GIF / WebM export
    parser.add_argument("--gif", action="store_true", help="Also export high-quality GIF")
    parser.add_argument("--gif-fps", type=int, default=24, help="GIF frame rate (default: 24)")
    parser.add_argument("--gif-width", type=int, default=960, help="GIF width in pixels (default: 960)")

    # Phase 4: Whisper captions
    parser.add_argument("--captions", action="store_true", default=False,
                        help="Generate and burn on-device Whisper subtitles")
    parser.add_argument("--captions-model", default="tiny.en",
                        choices=["tiny", "tiny.en", "base", "base.en", "small", "small.en"],
                        help="Whisper model size (default: tiny.en)")

    args = parser.parse_args()

    input_file = os.path.abspath(args.input)
    if not os.path.exists(input_file):
        sys.stderr.write(f"Error: input file {input_file} not found\n")
        sys.exit(1)

    telemetry_file = args.telemetry or input_file.replace(".mp4", ".telemetry.json")
    output_file = args.output or input_file.replace(".mp4", "_studio.mp4")
    tmpdir = tempfile.mkdtemp(prefix="studio_render_")

    # ── Probe input video ──────────────────────────────────────────────────
    probe_cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,duration",
        "-of", "json", input_file
    ]
    try:
        probe_out = subprocess.check_output(probe_cmd, stderr=subprocess.DEVNULL).decode()
        probe_data = json.loads(probe_out)
        stream = probe_data["streams"][0]
        in_w = int(stream["width"])
        in_h = int(stream["height"])
        fps_parts = stream["r_frame_rate"].split("/")
        fps = int(fps_parts[0]) // int(fps_parts[1]) if len(fps_parts) > 1 else 60
    except Exception:
        in_w, in_h, fps = 1920, 1080, 60

    # Check for audio stream
    probe_audio = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name",
         "-of", "json", input_file],
        capture_output=True, text=True
    )
    has_audio = "codec_name" in probe_audio.stdout

    telemetry = parse_telemetry(telemetry_file)
    clicks = telemetry.get("clicks", []) if telemetry else []

    regions = []
    if not args.no_zoom:
        regions = compute_zoom_regions(telemetry, default_scale=args.zoom_scale, auto_clicks=True)

    print(f"🎬 Studio Renderer: {len(regions)} zoom segments, {len(clicks)} click events detected.")
    print(f"   Mode: aspect={args.aspect} | frame={'on' if args.window_frame else 'off'} | "
          f"ripple={'on' if args.click_ripple else 'off'} | "
          f"sounds={'on' if args.click_sound else 'off'} | "
          f"captions={'on' if args.captions else 'off'}")

    duration = telemetry.get("duration", 10) if telemetry else 10
    w_expr, h_expr, crop_x, crop_y = build_scale_crop_expressions(regions, in_w, in_h, duration)

    # ── Determine output stage dimensions based on aspect ratio ───────────
    # Stage is always based on input resolution but canvas sized for target ratio
    aspect_map = {
        "16:9": (in_w, in_h),
        "9:16": (in_h * 9 // 16, in_h),   # tall portrait canvas
        "1:1":  (min(in_w, in_h), min(in_w, in_h)),
        "4:3":  (in_h * 4 // 3, in_h),
    }
    stage_w, stage_h = aspect_map.get(args.aspect, (in_w, in_h))
    # Ensure even dimensions
    stage_w = stage_w - (stage_w % 2)
    stage_h = stage_h - (stage_h % 2)

    pad = args.padding
    r = args.radius

    # Add header space for window frame
    header_h = 38 if args.window_frame else 0
    effective_pad_top = pad + header_h

    inner_max_w = stage_w - (pad * 2)
    inner_max_h = stage_h - pad - effective_pad_top
    aspect_ratio = in_w / in_h

    if inner_max_w / inner_max_h > aspect_ratio:
        inner_h = inner_max_h
        inner_w = int(inner_h * aspect_ratio)
    else:
        inner_w = inner_max_w
        inner_h = int(inner_w / aspect_ratio)

    inner_w = inner_w - (inner_w % 2)
    inner_h = inner_h - (inner_h % 2)

    offset_x = (stage_w - inner_w) // 2
    offset_y = effective_pad_top + (stage_h - pad - effective_pad_top - inner_h) // 2

    # ── Phase 4: Generate Whisper captions ASS file ───────────────────────
    ass_file = None
    if args.captions:
        ass_file = os.path.join(tmpdir, "captions.ass")
        result = generate_whisper_captions(input_file, ass_file, model=args.captions_model)
        if result:
            print(f"✅ Captions generated: {ass_file}")
        else:
            print("⚠️  Captions generation failed — rendering without subtitles.")
            ass_file = None

    # ── Phase 1B: Generate click sound WAV ───────────────────────────────
    click_wav = None
    extra_audio_inputs = []
    audio_filter_chain = ""
    click_audio_inputs = []

    if args.click_sound and has_audio and clicks:
        click_wav = os.path.join(tmpdir, "click.wav")
        generate_click_sound_wav(click_wav)
        audio_filter_chain, click_audio_inputs = build_click_audio_filter(
            clicks, 0, click_wav
        )

    # ── Build Background filter ───────────────────────────────────────────
    if args.preset == "blur":
        bg_filter = (f"[0:v]scale={stage_w}:{stage_h}:force_original_aspect_ratio=increase,"
                     f"crop={stage_w}:{stage_h},gblur=sigma=35:steps=2[bg];")
    elif args.preset == "gradient":
        bg_filter = (f"color=c=0x12131C:s={stage_w}x{stage_h}[bg_base];"
                     f"[bg_base]format=yuva420p[bg];")
    elif args.preset == "obsidian":
        bg_filter = f"color=c=0x0E0F12:s={stage_w}x{stage_h}[bg];"
    else:
        bg_filter = f"color=c=0x181920:s={stage_w}x{stage_h}[bg];"

    # ── Rounded corners alpha mask ────────────────────────────────────────
    geq_alpha = (
        f"if(gt(abs(W/2-X),W/2-{r})*gt(abs(H/2-Y),H/2-{r}),"
        f"if(lte(hypot({r}-(W/2-abs(W/2-X)),{r}-(H/2-abs(H/2-Y))),{r}),255,0),255)"
    )

    # ── Phase 1A: Click ripple filter ─────────────────────────────────────
    ripple_filter = ""
    if args.click_ripple and clicks:
        ripple_filter = build_click_ripple_filter(clicks, inner_w, inner_h, offset_x, offset_y)

    # ── Phase 2A: Window frame filter ─────────────────────────────────────
    frame_filter = ""
    if args.window_frame:
        frame_filter = build_window_frame_filter(inner_w, inner_h, title_text=args.window_title)

    # ── Build main video filter_complex ──────────────────────────────────
    # [0:v] → zoom & crop → scale to inner → round corners → overlay on bg → ripple → frame → captions
    caption_filter = f",subtitles='{ass_file}':force_style='FontName=Outfit'" if ass_file else ""

    filter_complex = (
        f"{bg_filter}"
        f"[0:v]scale=w='{w_expr}':h='{h_expr}':eval=frame,"
        f"crop=w={in_w}:h={in_h}:x='{crop_x}':y='{crop_y}'[zoomed];"
        f"[zoomed]scale={inner_w}:{inner_h},format=yuva420p,"
        f"geq=lum='p(X,Y)':a='{geq_alpha}'[rounded];"
        f"[bg][rounded]overlay=x={offset_x}:y={offset_y}:shortest=1[composed];"
        f"[composed]{{}}{ripple_filter[1:] if ripple_filter else 'null'}"
        f"{frame_filter}{caption_filter}[outv]"
    )

    # Clean up empty null filter
    filter_complex = filter_complex.replace("[composed];[composed]null", "[composed]null")
    filter_complex = filter_complex.replace("{}", "")
    filter_complex = filter_complex.replace("[composed];[composed]", "[composed]")
    # Simpler safe version: build the post-compose chain
    post_compose = []
    if ripple_filter:
        post_compose.append(ripple_filter.lstrip(","))
    if frame_filter:
        post_compose.append(frame_filter.lstrip(","))

    if post_compose:
        post_str = "," + ",".join(post_compose) + caption_filter
    else:
        post_str = caption_filter

    filter_complex = (
        f"{bg_filter}"
        f"[0:v]scale=w='{w_expr}':h='{h_expr}':eval=frame,"
        f"crop=w={in_w}:h={in_h}:x='{crop_x}':y='{crop_y}'[zoomed];"
        f"[zoomed]scale={inner_w}:{inner_h},format=yuva420p,"
        f"geq=lum='p(X,Y)':a='{geq_alpha}'[rounded];"
        f"[bg][rounded]overlay=x={offset_x}:y={offset_y}:shortest=1{post_str}[outv]"
    )

    # ── Build FFmpeg command ───────────────────────────────────────────────
    ffmpeg_cmd = ["ffmpeg", "-y", "-i", input_file]

    # Add click WAV inputs
    for wav_path in click_audio_inputs:
        ffmpeg_cmd += ["-i", wav_path]

    ffmpeg_cmd += ["-filter_complex", filter_complex]
    ffmpeg_cmd += ["-map", "[outv]"]

    # Audio mapping
    if audio_filter_chain and click_audio_inputs:
        # Separate audio filter_complex pass
        # For simplicity, use -af chain (works when no video audio filter needed)
        n_clicks = len(click_audio_inputs)
        audio_fc_parts = []
        for i in range(n_clicks):
            t_ms = int([c for c in clicks if c.get("kind") == "down" and c.get("btn") == "left"][i].get("t", 0) * 1000)
            audio_fc_parts.append(f"[{i+1}:a]adelay={t_ms}|{t_ms},volume=0.45[cs{i}]")
        mix_in = "[0:a]" + "".join(f"[cs{i}]" for i in range(n_clicks))
        audio_fc_parts.append(f"{mix_in}amix=inputs={n_clicks+1}:normalize=0,volume=1.0[aout]")
        audio_fc = ";\n".join(audio_fc_parts)

        # Merge audio filter into main filter_complex
        filter_complex_with_audio = filter_complex + ";\n" + audio_fc
        ffmpeg_cmd = ["ffmpeg", "-y", "-i", input_file]
        for wav_path in click_audio_inputs:
            ffmpeg_cmd += ["-i", wav_path]
        ffmpeg_cmd += ["-filter_complex", filter_complex_with_audio]
        ffmpeg_cmd += ["-map", "[outv]", "-map", "[aout]"]
    else:
        if has_audio:
            ffmpeg_cmd += ["-map", "0:a?"]
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", "192k"] if click_audio_inputs else ["-c:a", "copy"]

    ffmpeg_cmd += [
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "17",
        "-pix_fmt", "yuv420p",
        output_file
    ]

    print(f"\n🚀 Rendering Studio Video → {output_file}")
    print(f"   Stage: {stage_w}×{stage_h} | Inner: {inner_w}×{inner_h} | Offset: ({offset_x},{offset_y})")
    proc = subprocess.Popen(ffmpeg_cmd, stderr=subprocess.PIPE, text=True)
    for line in proc.stderr:
        if "frame=" in line or "fps=" in line:
            sys.stdout.write(f"\r{line.strip()[:90]}")
            sys.stdout.flush()

    proc.wait()
    sys.stdout.write("\n")

    # Cleanup
    import shutil
    shutil.rmtree(tmpdir, ignore_errors=True)

    if proc.returncode == 0 and os.path.exists(output_file):
        size_mb = os.path.getsize(output_file) / (1024 * 1024)
        print(f"\n✅ Studio Polish Complete! ({size_mb:.1f} MB) → {output_file}")

        # ── Phase 3: GIF Export ────────────────────────────────────────
        if args.gif:
            gif_out = output_file.replace("_studio.mp4", "_studio.gif").replace(".mp4", ".gif")
            try:
                export_gif(output_file, gif_out, fps=args.gif_fps, scale_w=args.gif_width)
            except Exception as e:
                sys.stderr.write(f"⚠️  GIF export failed: {e}\n")

        subprocess.run([
            "notify-send", "Studio Polish Complete",
            f"✨ {os.path.basename(output_file)} ({size_mb:.1f} MB)",
            "-i", "video-x-generic",
            "-a", "Recording Studio",
            "-u", "normal"
        ], check=False)
    else:
        print(f"❌ Render failed with exit code {proc.returncode}")
        sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
