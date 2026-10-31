"""Turns the screencast frames of one scene into an optimised GIF, using the real frame timestamps."""
import json
import os
import sys

from PIL import Image

scene, frames_root, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
width = int(sys.argv[4]) if len(sys.argv) > 4 else 800
fps = int(sys.argv[5]) if len(sys.argv) > 5 else 20
colors = int(sys.argv[6]) if len(sys.argv) > 6 else 192
hold_ms = 1500

directory = os.path.join(frames_root, scene)
meta = json.load(open(os.path.join(directory, "frames.json")))
frames, end = meta["frames"], meta["end"]

# Pick, for every 1/fps tick, the latest frame already on screen. The page only repaints when
# something changes, so the last frame stays until the scene ends.
step = 1000 // fps
picks = []
for tick in range(0, end + step, step):
    chosen = frames[0]
    for f in frames:
        if f["t"] <= tick:
            chosen = f
        else:
            break
    picks.append(chosen["file"])

# Merge runs of identical frames into one longer frame.
runs = []
for name in picks:
    if runs and runs[-1][0] == name:
        runs[-1][1] += step
    else:
        runs.append([name, step])
runs[-1][1] += hold_ms

first = Image.open(os.path.join(directory, runs[0][0])).convert("RGB")
height = round(first.height * width / first.width)

def load(name):
    return Image.open(os.path.join(directory, name)).convert("RGB").resize((width, height), Image.LANCZOS)

# One global palette keeps colours stable from frame to frame.
sample = [load(runs[i][0]) for i in range(0, len(runs), max(1, len(runs) // 12))]
mosaic = Image.new("RGB", (width, height * len(sample)))
for i, im in enumerate(sample):
    mosaic.paste(im, (0, i * height))
palette = mosaic.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)

images = [load(name).quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for name, _ in runs]
images[0].save(
    out_path, save_all=True, append_images=images[1:], duration=[d for _, d in runs],
    loop=0, optimize=False, disposal=1,
)
size = os.path.getsize(out_path) / 1024 / 1024
total = sum(d for _, d in runs) / 1000
print(f"{scene}: {len(runs)} quadros, {total:.1f}s, {width}x{height}, {size:.2f} MB")
