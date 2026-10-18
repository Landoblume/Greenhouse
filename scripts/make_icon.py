"""Draw the 1024x1024 app icon: a sprout in a pot on a green gradient.

    python3 scripts/make_icon.py

App Store Connect rejects icons with an alpha channel, so the image is RGB.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "Greenhouse/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

img = Image.new("RGB", (SIZE, SIZE))
draw = ImageDraw.Draw(img)

# Vertical gradient, light sage at the top to deep green at the bottom.
top, bottom = (168, 214, 160), (36, 110, 70)
for y in range(SIZE):
    t = y / (SIZE - 1)
    draw.line([(0, y), (SIZE, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

# Terracotta pot with a rim.
pot = (196, 104, 66)
rim = (214, 124, 84)
draw.polygon([(352, 640), (672, 640), (632, 880), (392, 880)], fill=pot)
draw.rounded_rectangle([(320, 592), (704, 668)], radius=18, fill=rim)

# Stem and two leaves.
leaf = (240, 250, 232)
draw.rounded_rectangle([(500, 360), (524, 600)], radius=12, fill=leaf)
draw.ellipse([(300, 300), (520, 440)], fill=leaf)
draw.ellipse([(504, 220), (724, 360)], fill=leaf)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print(f"wrote {OUT}")
