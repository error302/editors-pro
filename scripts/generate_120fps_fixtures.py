"""Generate tiny numbered 120 fps inputs for native frame-identity regressions."""
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "high_frame_rate"
OUT.mkdir(parents=True, exist_ok=True)
WIDTH, HEIGHT, COUNT = 128, 72, 240
GLYPHS = ["111101101101111", "010110010010111", "111001111100111",
          "111001111001111", "101101111001001", "111100111001111",
          "111100111101111", "111001010010010", "111101111101111",
          "111101111001111"]


def frame(number):
    pixels = bytearray([32] * (WIDTH * HEIGHT * 3))
    for y in range(32):
        for x in range(WIDTH):
            value = 224 if (number >> (x // 16)) & 1 else 32
            offset = (y * WIDTH + x) * 3
            pixels[offset:offset + 3] = bytes([value] * 3)
    for index, digit in enumerate(f"{number:03}"):
        glyph = GLYPHS[int(digit)]
        for row in range(5):
            for col in range(3):
                if glyph[row * 3 + col] != "1":
                    continue
                for dy in range(5):
                    for dx in range(5):
                        x, y = 35 + index * 20 + col * 5 + dx, 39 + row * 5 + dy
                        offset = (y * WIDTH + x) * 3
                        pixels[offset:offset + 3] = bytes([224] * 3)
    return pixels


raw = b"".join(frame(number) for number in range(COUNT))
for name, gop, bframes in [("all_keyframes", 1, 0), ("normal_gop", 48, 3)]:
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "128x72",
        "-framerate", "120", "-i", "pipe:0", "-an", "-c:v", "libx264",
        "-preset", "medium", "-crf", "12", "-pix_fmt", "yuv420p",
        "-g", str(gop), "-bf", str(bframes), "-sc_threshold", "0",
        "-video_track_timescale", "15360", str(OUT / f"{name}_120fps.mp4"),
    ], input=raw, check=True)
