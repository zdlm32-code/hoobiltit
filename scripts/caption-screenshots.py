"""Caption the raw simulator captures for the App Store.

    python3 scripts/caption-screenshots.py

Reads store/screenshots/<set>/*.png (raw captures, kept as they are) and writes
store/screenshots/captioned/<set>/ at the same pixel size, which is what App Store
Connect requires for the slot: a headline and a line of context on the site's dark
background, with the capture below it. Screenshots are the first thing a store visitor
reads; a raw map screen does not say what the app is for.

Captions are keyed on the file name after its number, so reordering files keeps them.
"""
import glob
import os
from PIL import Image, ImageDraw, ImageFont

BG = (26, 29, 35)
TEXT = (232, 234, 238)
YELLOW = (247, 200, 70)
MUTED = (160, 166, 176)
FONT = "/System/Library/Fonts/SFNS.ttf"

# (headline, the part of it drawn in yellow, context line)
CAPTIONS = {
    "roundrock-tx": ("Who built this road?", "this road", "The owner, and the project that built it"),
    "maricopa":     ("Down to the recorded plat", "recorded plat", "Maricopa County, Arizona, in full"),
    "maricopa-az":  ("Down to the recorded plat", "recorded plat", "Maricopa County, Arizona, in full"),
    "classvi-nh":   ("Even the roads nobody maintains", "nobody maintains", "New Hampshire's Class VI roads, named as such"),
    "private-vt":   ("Public road, or private?", "private?", "More than 16,000 private roads in Vermont alone"),
    "charlotte-nc": ("Who maintains it, city by city", "city by city", "From North Carolina DOT's own records"),
}


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    # Axes are Width, Optical Size, GRAD, Weight — in that order.
    f.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
    return f


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def fit(draw, text, weight, size, max_width):
    while size > 20 and draw.textlength(text, font=font(size, weight)) > max_width:
        size -= 2
    return font(size, weight)


def caption(path, out_path):
    key = os.path.splitext(os.path.basename(path))[0].split("-", 1)[1]
    headline, accent, context = CAPTIONS[key]
    raw = Image.open(path).convert("RGB")
    W, H = raw.size
    unit = W / 1320                      # layout is drawn for the iPhone, scaled for iPad
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    margin = int(90 * unit)

    head = fit(d, headline, 760, int(104 * unit), W - 2 * margin)
    y = int(150 * unit)
    x = (W - d.textlength(headline, font=head)) / 2
    before, _, after = headline.partition(accent)
    for part, colour in ((before, TEXT), (accent, YELLOW), (after, TEXT)):
        d.text((x, y), part, font=head, fill=colour)
        x += d.textlength(part, font=head)

    sub = fit(d, context, 480, int(50 * unit), W - 2 * margin)
    y += int(150 * unit)
    d.text(((W - d.textlength(context, font=sub)) / 2, y), context, font=sub, fill=MUTED)

    # The capture, framed and running off the bottom edge like a phone held up to the reader.
    top = int(470 * unit)
    width = int(W * 0.80)
    shot = raw.resize((width, int(raw.height * width / W)), Image.LANCZOS)
    bezel = int(22 * unit)
    frame = Image.new("RGB", (width + 2 * bezel, shot.height + 2 * bezel), (60, 64, 72))
    fx = (W - frame.width) // 2
    canvas.paste(frame, (fx, top - bezel), rounded_mask(frame.size, int(110 * unit)))
    canvas.paste(shot, (fx + bezel, top), rounded_mask(shot.size, int(90 * unit)))
    canvas.save(out_path, optimize=True)


for folder in ("iphone69", "ipad13"):
    out_dir = f"store/screenshots/captioned/{folder}"
    os.makedirs(out_dir, exist_ok=True)
    for path in sorted(glob.glob(f"store/screenshots/{folder}/*.png")):
        out = os.path.join(out_dir, os.path.basename(path))
        caption(path, out)
        print(out)
